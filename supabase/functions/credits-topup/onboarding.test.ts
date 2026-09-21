// Run: node --experimental-strip-types --test supabase/functions/credits-topup/onboarding.test.ts
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { DEFAULT_FEE_INR, feeInr, handleOnboardingFee, type FeeRow, type OnboardingDeps } from './onboarding.ts'

const OWNER = { id: 'user-1' }
const STRANGER = { id: 'user-2' }

type Overrides = Partial<Omit<OnboardingDeps, 'env'>> & { env?: Record<string, string>; rows?: FeeRow[] }

function deps({ env: envOver, rows: rowsOver, ...over }: Overrides = {}) {
  const rows: FeeRow[] = rowsOver ?? []
  const calls = { links: [] as unknown[], inserted: [] as unknown[], paid: [] as unknown[] }
  const env = { RAZORPAY_KEY_ID: 'rzp', RAZORPAY_KEY_SECRET: 's', ONBOARDING_FEE_INR: '9', ...(envOver ?? {}) }
  const d: OnboardingDeps = {
    env: (n) => env[n as keyof typeof env] ?? '',
    createPaymentLink: async (body) => { calls.links.push(body); return { ok: true, id: 'plink_1', shortUrl: 'https://rzp.io/x' } },
    fetchPaymentLink: async () => null,
    paidFee: async (u) => rows.find((r) => r.user_id === u && r.status === 'paid') ?? null,
    feeByLink: async (l) => rows.find((r) => r.link_id === l) ?? null,
    insertFee: async (row) => { calls.inserted.push(row) },
    markFeePaid: async (id, pid) => { calls.paid.push([id, pid]) },
    nowSeconds: () => 1000,
    log: () => {},
    ...over,
  }
  return { d, calls }
}

const unpaidRow: FeeRow = { id: 'r1', user_id: OWNER.id, link_id: 'plink_1', amount_paise: 900, status: 'created' }

test('the amount comes from the secret; unset means ₹9; junk falls back', () => {
  assert.equal(feeInr(''), DEFAULT_FEE_INR)
  assert.equal(feeInr('25'), 25)
  assert.equal(feeInr('0'), 0)
  assert.equal(feeInr('nine'), DEFAULT_FEE_INR)
  assert.equal(feeInr('-4'), DEFAULT_FEE_INR)
})

test('status reports amount, required, payable and paid', async () => {
  const { d } = deps()
  const r = await handleOnboardingFee({ action: 'onboarding_status' }, OWNER, d)
  assert.deepEqual(r.body, { ok: true, amount_inr: 9, required: true, payable: true, paid: false })
})

test('a fee of 0 is not required', async () => {
  const { d } = deps({ env: { ONBOARDING_FEE_INR: '0' } })
  const r = await handleOnboardingFee({ action: 'onboarding_status' }, OWNER, d)
  assert.equal(r.body.required, false)
})

test('pay makes a link the credits webhook cannot read as a purchase', async () => {
  const { d, calls } = deps()
  const r = await handleOnboardingFee({ action: 'onboarding_pay' }, OWNER, d)
  assert.equal(r.body.url, 'https://rzp.io/x')
  const link = calls.links[0] as { amount: number; notes: Record<string, string> }
  assert.equal(link.amount, 900)
  assert.deepEqual(link.notes, { purpose: 'onboarding_fee', user_id: OWNER.id, source: 'app' })
  assert.equal('wholesaler_id' in link.notes, false)
  assert.deepEqual(calls.inserted[0], { user_id: OWNER.id, link_id: 'plink_1', amount_paise: 900 })
})

test('pay after paying makes no second link', async () => {
  const { d, calls } = deps({ rows: [{ ...unpaidRow, status: 'paid' }] })
  const r = await handleOnboardingFee({ action: 'onboarding_pay' }, OWNER, d)
  assert.deepEqual(r.body, { ok: true, required: true, paid: true })
  assert.equal(calls.links.length, 0)
})

test('confirm records a paid link', async () => {
  const { d, calls } = deps({
    rows: [unpaidRow],
    fetchPaymentLink: async () => ({
      status: 'paid', amount_paid: 900, notes: { user_id: OWNER.id },
      payments: [{ payment_id: 'pay_1', status: 'captured' }],
    }),
  })
  const r = await handleOnboardingFee({ action: 'onboarding_confirm', link_id: 'plink_1' }, OWNER, d)
  assert.equal(r.body.paid, true)
  assert.deepEqual(calls.paid[0], ['r1', 'pay_1'])
})

test('confirm refuses unpaid, short, or someone else\'s link', async () => {
  const cases: [typeof OWNER, object][] = [
    [OWNER, { status: 'created', amount_paid: 0, notes: { user_id: OWNER.id }, payments: [] }],
    [OWNER, { status: 'paid', amount_paid: 100, notes: { user_id: OWNER.id }, payments: [] }],
    [STRANGER, { status: 'paid', amount_paid: 900, notes: { user_id: OWNER.id }, payments: [] }],
  ]
  for (const [who, link] of cases) {
    const { d, calls } = deps({ rows: [unpaidRow], fetchPaymentLink: async () => link as never })
    const r = await handleOnboardingFee({ action: 'onboarding_confirm', link_id: 'plink_1' }, who, d)
    assert.equal(r.body.paid, false)
    assert.equal(calls.paid.length, 0)
  }
})

test('without Razorpay keys the fee is not payable, so it blocks nobody', async () => {
  const { d } = deps({ env: { RAZORPAY_KEY_SECRET: '' } })
  const r = await handleOnboardingFee({ action: 'onboarding_status' }, OWNER, d)
  assert.equal(r.body.payable, false)
})
