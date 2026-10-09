// StoreKit 2 consumables: verify Apple's signed transaction on the server,
// bind it to the authenticated Supabase account, then grant once in SQL.
import { createClient } from 'npm:@supabase/supabase-js@2'
import { Environment, SignedDataVerifier } from 'npm:@apple/app-store-server-library@3.1.0'
import { Buffer } from 'node:buffer'
import { appleRootDER } from './apple_roots.ts'

const bundleID = 'com.jewelindia.app'
const appAppleID = 6810498921
const roots = appleRootDER.map((encoded) => Buffer.from(encoded, 'base64'))

const headers = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info',
  'Content-Type': 'application/json',
}
const reply = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), { status, headers })

function claimedEnvironment(jws: string): Environment {
  // The unsigned claim selects a verifier only. It never authorizes a grant.
  const payload = jws.split('.')[1]
  if (!payload) throw new Error('Malformed signed transaction')
  const claim = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8'))
  if (claim.environment === 'Production') return Environment.PRODUCTION
  if (claim.environment === 'Sandbox') return Environment.SANDBOX
  throw new Error('Unknown App Store environment')
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response(null, { headers })
  if (request.method !== 'POST') return reply(405, { error: 'Use POST' })

  const token = (request.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '').trim()
  if (!token) return reply(401, { error: 'Sign in again' })
  const admin = createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '', {
    auth: { persistSession: false, autoRefreshToken: false },
  })
  const { data: { user }, error: authError } = await admin.auth.getUser(token)
  if (authError || !user) return reply(401, { error: 'Sign in again' })

  const body = await request.json().catch(() => null)
  const signed = typeof body?.signed_transaction === 'string' ? body.signed_transaction : ''
  if (!signed || signed.length > 30_000) return reply(400, { error: 'Missing signed transaction' })

  try {
    const environment = claimedEnvironment(signed)
    const verifier = new SignedDataVerifier(
      roots, false, environment, bundleID,
      environment === Environment.PRODUCTION ? appAppleID : undefined,
    )
    const transaction = await verifier.verifyAndDecodeTransaction(signed)
    // The fixed-pack flow sells one consumable at a time. Reject a quantity
    // we cannot credit exactly; Apple permits up to ten in one transaction.
    if (transaction.quantity !== 1) {
      return reply(400, { error: 'Unsupported purchase quantity' })
    }
    if (!transaction.transactionId || !transaction.productId ||
        transaction.revocationDate ||
        transaction.appAccountToken?.toLowerCase() !== user.id.toLowerCase()) {
      return reply(403, { error: 'This purchase does not belong to this account' })
    }

    // The RPC chooses the amount from the server's fixed Apple product table.
    // A replay of the same transaction returns the original grant, never more.
    const { data, error } = await admin.rpc('record_apple_credit_purchase', {
      p_user: user.id,
      p_transaction_id: transaction.transactionId,
      p_product_id: transaction.productId,
      p_signed_transaction: {
        transactionId: transaction.transactionId,
        productId: transaction.productId,
        purchaseDate: transaction.purchaseDate,
        signedDate: transaction.signedDate,
        environment: transaction.environment,
      },
    })
    if (error) {
      console.error('apple-iap grant failed', { transactionId: transaction.transactionId, error: error.message })
      return reply(503, { error: 'Payment confirmed, but credits are still pending. Please try again.' })
    }
    if (!data?.ok) return reply(400, { error: data?.error ?? 'Purchase could not be applied' })
    if (data.status === 'refunded') return reply(403, { error: 'This purchase was refunded' })
    return reply(200, { ok: true, credits: data.credits, replayed: data.replayed, status: data.status ?? 'paid' })
  } catch (error) {
    console.error('apple-iap verification failed', { error: String(error) })
    return reply(400, { error: 'Apple could not verify this purchase' })
  }
})
