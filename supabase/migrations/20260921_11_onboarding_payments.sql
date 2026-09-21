-- The one-time onboarding fee's payments. Written only by the AI pipeline
-- (service role) after it has confirmed the payment with Razorpay; people
-- can read their own, so the app knows whether it's paid.

BEGIN;

CREATE TABLE IF NOT EXISTS public.onboarding_payments (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    link_id      TEXT NOT NULL UNIQUE,
    amount_paise INT  NOT NULL CHECK (amount_paise > 0),
    status       TEXT NOT NULL DEFAULT 'created' CHECK (status IN ('created', 'paid')),
    payment_id   TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    paid_at      TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_onboarding_payments_user
    ON public.onboarding_payments (user_id, status);

ALTER TABLE public.onboarding_payments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "own onboarding payments" ON public.onboarding_payments;
CREATE POLICY "own onboarding payments" ON public.onboarding_payments
    FOR SELECT TO authenticated USING (user_id = auth.uid());

COMMIT;
