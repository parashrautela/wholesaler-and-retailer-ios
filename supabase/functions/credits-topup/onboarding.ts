// The one-time onboarding fee, collected here because this function already
// holds the Razorpay keys. The amount is set in Railway as ONBOARDING_FEE_INR
// (whole rupees, GST included; 0 turns the fee off) and read from the AI
// pipeline's GET /api/onboarding-fee. If the pipeline can't be reached, the
// Supabase secret of the same name is used, and failing that, ₹9.
//
//   POST { "action": "onboarding_status" }                → amount, required, paid
//   POST { "action": "onboarding_pay" }                   → a Razorpay Payment Link
//   POST { "action": "onboarding_confirm", "link_id" }    → asks Razorpay if it's paid
//
// Confirmation reads the link back from Razorpay rather than waiting for the
// webhook. The link's notes carry purpose=onboarding_fee and no
// wholesaler_id, so razorpay-webhook never treats it as a credit purchase.

import type { AuthUser, RazorpayResult } from './handler.ts'

export const ONBOARDING_PURPOSE = 'onboarding_fee'
export const DEFAULT_FEE_INR = 9
const LINK_LIFETIME_SECONDS = 30 * 60

export interface FeeRow {
  id: string
  user_id: string
  link_id: string
  amount_paise: number
  status: 'created' | 'paid'
}

export interface RazorpayLink {
  status: string
  amount_paid: number
  notes: Record<string, string>
  payments: { payment_id?: string; status?: string }[]
}

export interface OnboardingDeps {
  env: (name: string) => string
  /** The fee as set in Railway, or null when the pipeline can't be reached. */
  railwayFee: () => Promise<number | null>
  createPaymentLink: (body: unknown, keyId: string, keySecret: string) => Promise<RazorpayResult>
  fetchPaymentLink: (linkId: string, keyId: string, keySecret: string) => Promise<RazorpayLink | null>
  paidFee: (userId: string) => Promise<FeeRow | null>
  feeByLink: (linkId: string) => Promise<FeeRow | null>
  insertFee: (row: Omit<FeeRow, 'id' | 'status'>) => Promise<void>
  markFeePaid: (id: string, paymentId: string | null) => Promise<void>
  nowSeconds: () => number
  log: (level: 'info' | 'warn' | 'error', message: string, extra?: Record<string, unknown>) => void
}

export interface FeeReply {
  status: number
  body: Record<string, unknown>
}

export function feeInr(raw: string): number {
  const trimmed = raw.trim()
  if (trimmed === '') return DEFAULT_FEE_INR
  const n = Number(trimmed)
  return Number.isInteger(n) && n >= 0 && n <= 100_000 ? n : DEFAULT_FEE_INR
}

export async function handleOnboardingFee(
  body: Record<string, unknown>,
  user: AuthUser,
  deps: OnboardingDeps,
): Promise<FeeReply> {
  const fromRailway = await deps.railwayFee()
  const amount = fromRailway ?? feeInr(deps.env('ONBOARDING_FEE_INR'))
  const keyId = deps.env('RAZORPAY_KEY_ID').trim()
  const keySecret = deps.env('RAZORPAY_KEY_SECRET').trim()
  const payable = amount > 0 && keyId !== '' && keySecret !== ''

  if (body.action === 'onboarding_status') {
    const paid = amount > 0 ? (await deps.paidFee(user.id)) !== null : false
    return ok({ amount_inr: amount, required: amount > 0, payable, paid })
  }

  if (body.action === 'onboarding_pay') {
    if (amount === 0) return ok({ required: false })
    if (await deps.paidFee(user.id)) return ok({ required: true, paid: true })
    if (!payable) {
      deps.log('error', 'Onboarding fee is on but Razorpay keys are missing')
      return fail(503, 'not_configured', "Payments aren't available right now. Please try again later.")
    }

    const link = await deps.createPaymentLink({
      amount: amount * 100,
      currency: 'INR',
      accept_partial: false,
      description: 'Jewel India: one-time onboarding fee',
      notify: { sms: false, email: false },
      reminder_enable: false,
      expire_by: deps.nowSeconds() + LINK_LIFETIME_SECONDS,
      // Deliberately no wholesaler_id: the credits webhook must never be able
      // to read this as a credit purchase.
      notes: { purpose: ONBOARDING_PURPOSE, user_id: user.id, source: 'app' },
    }, keyId, keySecret)
    if (!link.ok) {
      deps.log('error', 'Razorpay refused the onboarding link', { user_id: user.id, status: link.status, description: link.description })
      return fail(502, 'payment_provider_error', 'Could not start the payment. Please try again in a minute.')
    }

    await deps.insertFee({ user_id: user.id, link_id: link.id, amount_paise: amount * 100 })
    deps.log('info', 'Onboarding fee link created', { user_id: user.id, link_id: link.id, amount_inr: amount })
    return ok({ required: true, paid: false, link_id: link.id, url: link.shortUrl, amount_inr: amount })
  }

  if (body.action === 'onboarding_confirm') {
    const linkId = typeof body.link_id === 'string' ? body.link_id : ''
    const row = linkId ? await deps.feeByLink(linkId) : null
    // Someone else's link, or one we never made: the same answer as unpaid.
    if (!row || row.user_id !== user.id) return ok({ paid: false })
    if (row.status === 'paid') return ok({ paid: true })
    if (keyId === '' || keySecret === '') {
      return fail(503, 'not_configured', "Payments aren't available right now.")
    }

    const link = await deps.fetchPaymentLink(linkId, keyId, keySecret)
    if (!link) return fail(502, 'payment_provider_error', 'Could not check the payment. Please try again.')

    const paid = link.status === 'paid'
      && Number(link.amount_paid ?? 0) >= row.amount_paise
      && (link.notes ?? {}).user_id === user.id
    if (!paid) return ok({ paid: false, status: link.status })

    const paymentId = (link.payments ?? []).find((p) => p.status === 'captured')?.payment_id ?? null
    await deps.markFeePaid(row.id, paymentId)
    deps.log('info', 'Onboarding fee paid', { user_id: user.id, link_id: linkId })
    return ok({ paid: true })
  }

  return fail(400, 'unknown_action', 'Unknown action.')
}

const ok = (body: Record<string, unknown>): FeeReply => ({ status: 200, body: { ok: true, ...body } })
const fail = (status: number, error: string, message: string): FeeReply => ({
  status,
  body: { ok: false, error, message },
})
