// credits-topup: the in-app "Buy credits" backend.
//
// Deployed WITH Supabase JWT verification (the default — never pass
// --no-verify-jwt), so only signed-in users reach this code, and handler.ts
// takes who is buying from that session. The app never says whose wallet to
// fill or what anything costs.
//
//   POST { "action": "options" }                   → packs, priced, with credits
//   POST { "action": "create", "pack_key": "…" }   → a Razorpay Payment Link
//   POST { "action": "onboarding_…" }              → the one-time onboarding fee (onboarding.ts)
//
// The link carries notes.wholesaler_id = the buyer's auth uid, so when it is
// paid, razorpay-webhook grants the credits exactly as for a link made by hand.
// Deploy/config steps: README.md next to this file.

// @ts-ignore: Deno import
import { serve } from "https://deno.land/std@0.177.0/http/server.ts"
// @ts-ignore: Deno import
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import type { Pack } from "../razorpay-webhook/lib.ts"
import { handleTopUp, type RazorpayResult } from "./handler.ts"
import type { FeeRow, RazorpayLink } from "./onboarding.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const RAZORPAY_TIMEOUT_MS = 15_000

function env(name: string): string {
  // @ts-ignore: Deno global
  return Deno.env.get(name) ?? ''
}

function log(level: 'info' | 'warn' | 'error', message: string, extra: Record<string, unknown> = {}) {
  console[level](JSON.stringify({ fn: 'credits-topup', level, message, ...extra }))
}

const admin = createClient(env('SUPABASE_URL'), env('SUPABASE_SERVICE_ROLE_KEY'), {
  auth: { persistSession: false, autoRefreshToken: false },
})

async function createPaymentLink(body: unknown, keyId: string, keySecret: string): Promise<RazorpayResult> {
  try {
    const res = await fetch('https://api.razorpay.com/v1/payment_links', {
      method: 'POST',
      headers: {
        'Authorization': `Basic ${btoa(`${keyId}:${keySecret}`)}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(RAZORPAY_TIMEOUT_MS),
    })
    const data = await res.json().catch(() => null)
    if (res.ok && typeof data?.id === 'string' && typeof data?.short_url === 'string') {
      return { ok: true, id: data.id, shortUrl: data.short_url }
    }
    return { ok: false, status: res.status, description: String(data?.error?.description ?? 'no description') }
  } catch (err) {
    return { ok: false, status: 0, description: err instanceof Error ? err.message : String(err) }
  }
}

async function fetchPaymentLink(linkId: string, keyId: string, keySecret: string): Promise<RazorpayLink | null> {
  try {
    const res = await fetch(`https://api.razorpay.com/v1/payment_links/${encodeURIComponent(linkId)}`, {
      headers: { 'Authorization': `Basic ${btoa(`${keyId}:${keySecret}`)}` },
      signal: AbortSignal.timeout(RAZORPAY_TIMEOUT_MS),
    })
    if (!res.ok) return null
    return await res.json() as RazorpayLink
  } catch {
    return null
  }
}

// The AI pipeline on Railway publishes the fee it's configured with.
const PIPELINE_URL = env('AI_PIPELINE_URL') || 'https://ai-pipeline-production-3f9a.up.railway.app'

async function railwayFee(): Promise<number | null> {
  try {
    const res = await fetch(`${PIPELINE_URL}/api/onboarding-fee`, { signal: AbortSignal.timeout(4_000) })
    if (!res.ok) return null
    const data = await res.json()
    const n = Number(data?.amount_inr)
    return Number.isInteger(n) && n >= 0 && n <= 100_000 ? n : null
  } catch {
    return null
  }
}

const onboarding = {
  railwayFee,
  fetchPaymentLink,
  paidFee: async (userId: string): Promise<FeeRow | null> => {
    const { data, error } = await admin.from('onboarding_payments')
      .select('id, user_id, link_id, amount_paise, status')
      .eq('user_id', userId).eq('status', 'paid').limit(1).maybeSingle()
    if (error) throw new Error(error.message)
    return data
  },
  feeByLink: async (linkId: string): Promise<FeeRow | null> => {
    const { data, error } = await admin.from('onboarding_payments')
      .select('id, user_id, link_id, amount_paise, status')
      .eq('link_id', linkId).maybeSingle()
    if (error) throw new Error(error.message)
    return data
  },
  insertFee: async (row: { user_id: string; link_id: string; amount_paise: number }) => {
    const { error } = await admin.from('onboarding_payments').insert({ ...row, status: 'created' })
    if (error) throw new Error(error.message)
  },
  markFeePaid: async (id: string, paymentId: string | null) => {
    const { error } = await admin.from('onboarding_payments')
      .update({ status: 'paid', payment_id: paymentId, paid_at: new Date().toISOString() })
      .eq('id', id)
    if (error) throw new Error(error.message)
  },
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  let reply
  try {
    reply = await handleTopUp(req.method, req.headers.get('Authorization'), await req.text(), {
      env,
      paymentsEnabled: async () => {
        const { data, error } = await admin.rpc('credits_program_status')
        return !error && data?.payments_enabled === true
      },
      userFromJwt: async (jwt) => {
        const { data, error } = await admin.auth.getUser(jwt)
        return error || !data?.user ? null : data.user
      },
      activePacks: async () => {
        const { data, error } = await admin
          .from('credit_packs')
          .select('key, label, credits, price_inr_ex_gst, active')
          .eq('active', true)
          .order('sort')
        if (error) throw new Error(error.message)
        return (data ?? []) as Pack[]
      },
      // The buyer's business row. Wallets are keyed on the auth user, so a
      // retailer buys exactly as a wholesaler does; `retailers` carries the
      // same three columns, so the handler needs no second shape.
      wholesalerOf: async (userId) => {
        for (const table of ['wholesalers', 'retailers']) {
          const { data, error } = await admin
            .from(table)
            .select('business_name, full_name, verification_status')
            .eq('user_id', userId)
            .maybeSingle()
          if (error) throw new Error(error.message)
          if (data) return data
        }
        return null
      },
      createPaymentLink,
      nowSeconds: () => Math.floor(Date.now() / 1000),
      log,
      onboarding,
    })
  } catch (err) {
    log('error', 'Unhandled error', { error: err instanceof Error ? err.message : String(err) })
    reply = { status: 500, body: { ok: false, error: 'unavailable', message: 'Something went wrong. Please try again.' } }
  }

  return new Response(JSON.stringify(reply.body), {
    status: reply.status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
})
