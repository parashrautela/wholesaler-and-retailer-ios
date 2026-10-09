-- Retailer monetisation, step 4: subscription plans, paid for with credits.
--
-- A plan is a period of time bought from the wallet. Its price lives on the
-- rate card (`plan.<key>`) so spend_credits prices it like everything else;
-- `plans` adds what the rate card can't say: how long it lasts and what it
-- includes. While a plan is active every paid theme is unlocked.
--
-- There is no scheduler on this database, so renewal is lazy: my_plan() —
-- which the app calls on launch — renews a lapsed auto-renewing plan when
-- the wallet can cover it.

BEGIN;

CREATE TABLE IF NOT EXISTS public.plans (
    key         TEXT PRIMARY KEY,
    label       TEXT NOT NULL,
    period_days INT  NOT NULL CHECK (period_days > 0),
    perks       JSONB NOT NULL DEFAULT '[]'::jsonb,   -- lines of copy, shown as-is
    sort_order  INT  NOT NULL DEFAULT 0,
    is_active   BOOLEAN NOT NULL DEFAULT true
);

ALTER TABLE public.plans ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "plans are readable when signed in" ON public.plans;
CREATE POLICY "plans are readable when signed in" ON public.plans
    FOR SELECT TO authenticated USING (is_active);

INSERT INTO public.plans (key, label, period_days, perks, sort_order) VALUES
    ('monthly',   'Monthly',   30,  '["Every store theme unlocked"]', 10),
    ('quarterly', 'Quarterly', 90,  '["Every store theme unlocked", "Save 11% against monthly"]', 20),
    ('yearly',    'Yearly',    365, '["Every store theme unlocked", "Save 17% against monthly"]', 30)
ON CONFLICT (key) DO NOTHING;

INSERT INTO public.credit_prices (feature_key, credits, label, description, sort_order, audience) VALUES
    ('plan.monthly',   3000,  'Monthly plan',   '30 days',  210, 'retailer'),
    ('plan.quarterly', 8000,  'Quarterly plan', '90 days',  220, 'retailer'),
    ('plan.yearly',    30000, 'Yearly plan',    '365 days', 230, 'retailer')
ON CONFLICT (feature_key) DO NOTHING;

-- One row per period bought. A renewal or an early top-up is a new row that
-- starts where the last one ends, so the history is the billing record.
CREATE TABLE IF NOT EXISTS public.retailer_subscriptions (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    plan_key   TEXT NOT NULL REFERENCES public.plans(key),
    starts_at  TIMESTAMPTZ NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    ledger_id  UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (expires_at > starts_at)
);

ALTER TABLE public.retailer_subscriptions
    DROP CONSTRAINT IF EXISTS retailer_subscriptions_user_id_starts_at_key;

CREATE INDEX IF NOT EXISTS idx_retailer_subscriptions_user
    ON public.retailer_subscriptions (user_id, expires_at DESC);

ALTER TABLE public.retailer_subscriptions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "own subscriptions" ON public.retailer_subscriptions;
CREATE POLICY "own subscriptions" ON public.retailer_subscriptions
    FOR SELECT USING (auth.uid() = user_id);

-- Whether to renew is a preference, not a period, so it lives apart.
CREATE TABLE IF NOT EXISTS public.retailer_plan_prefs (
    user_id    UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    auto_renew BOOLEAN NOT NULL DEFAULT true,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.retailer_plan_prefs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "own plan prefs" ON public.retailer_plan_prefs;
CREATE POLICY "own plan prefs" ON public.retailer_plan_prefs
    FOR SELECT USING (auth.uid() = user_id);

-- ── An active plan unlocks every theme ─────────────────────────────────────

CREATE OR REPLACE FUNCTION public.has_active_plan(p_user UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.retailer_subscriptions
         WHERE user_id = p_user AND starts_at <= now() AND expires_at > now()
    );
$$;

REVOKE ALL ON FUNCTION public.has_active_plan(UUID) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.has_entitlement(p_user UUID, p_key TEXT)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.entitlements
         WHERE user_id = p_user
           AND entitlement_key = p_key
           AND (expires_at IS NULL OR expires_at > now())
    ) OR (p_key LIKE 'theme.%' AND public.has_active_plan(p_user));
$$;

-- ── Buying a period ────────────────────────────────────────────────────────
-- Internal: charges p_user for one period of p_plan, starting when their
-- current cover ends (or now). Callers have already decided who p_user is.
--
-- Purchases for one user run one at a time (advisory lock), and each decides
-- whether it is still wanted only after it holds the lock. That is what stops
-- a double tap or a retried request from buying twice; the charge key is then
-- simply unique per period.

CREATE OR REPLACE FUNCTION public.plans_buy_period(p_user UUID, p_plan TEXT, p_reason TEXT)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
    v_plan   public.plans%ROWTYPE;
    v_id     UUID := gen_random_uuid();
    v_cover  TIMESTAMPTZ;
    v_start  TIMESTAMPTZ;
    v_end    TIMESTAMPTZ;
    v_spend  JSONB;
BEGIN
    SELECT * INTO v_plan FROM public.plans WHERE key = p_plan AND is_active;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'error', 'UNKNOWN_PLAN');
    END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended('plan:' || p_user::text, 0));

    SELECT MAX(expires_at) INTO v_cover
      FROM public.retailer_subscriptions WHERE user_id = p_user;

    IF p_reason = 'auto_renew' THEN
        -- Another launch got here first.
        IF v_cover > now() THEN
            RETURN jsonb_build_object('ok', true, 'charged', 0, 'already_renewed', true);
        END IF;
    ELSIF v_cover > now() + INTERVAL '7 days' THEN
        -- Extending is for the last week of cover. Any earlier and a second
        -- purchase is far more likely a retry of one that already went
        -- through — which would otherwise stack, and charge for, another period.
        RETURN jsonb_build_object('ok', false, 'error', 'ALREADY_ACTIVE', 'expires_at', v_cover);
    END IF;

    v_start := GREATEST(COALESCE(v_cover, now()), now());
    v_end := v_start + make_interval(days => v_plan.period_days);

    v_spend := public.spend_credits(
        p_user            => p_user,
        p_feature_key     => 'plan.' || p_plan,
        p_idempotency_key => 'plan:' || v_id,
        p_reference_type  => 'plan',
        p_reference_id    => v_id::text,
        p_metadata        => jsonb_build_object('reason', p_reason, 'plan', p_plan)
    );

    IF NOT COALESCE((v_spend->>'ok')::boolean, false) THEN
        RETURN v_spend;
    END IF;

    INSERT INTO public.retailer_subscriptions (id, user_id, plan_key, starts_at, expires_at, ledger_id)
    VALUES (v_id, p_user, p_plan, v_start, v_end, NULLIF(v_spend->>'ledger_id', '')::uuid);

    RETURN jsonb_build_object('ok', true, 'charged', v_spend->'charged',
                              'balance', v_spend->'balance',
                              'plan_key', p_plan, 'expires_at', v_end);
END;
$$;

REVOKE ALL ON FUNCTION public.plans_buy_period(UUID, TEXT, TEXT) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.subscribe_plan(p_plan TEXT)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_result JSONB;
BEGIN
    IF v_user IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'error', 'NOT_AUTHENTICATED');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.retailers
                    WHERE user_id = v_user AND verification_status = 'verified') THEN
        RETURN jsonb_build_object('ok', false, 'error', 'NOT_VERIFIED');
    END IF;

    v_result := public.plans_buy_period(v_user, p_plan, 'subscribe');

    -- Choosing a plan is choosing to keep it, until they say otherwise.
    IF COALESCE((v_result->>'ok')::boolean, false) THEN
        INSERT INTO public.retailer_plan_prefs (user_id, auto_renew) VALUES (v_user, true)
        ON CONFLICT (user_id) DO UPDATE SET auto_renew = true, updated_at = now();
    END IF;
    RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.subscribe_plan(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.subscribe_plan(TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.set_plan_auto_renew(p_on BOOLEAN)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'error', 'NOT_AUTHENTICATED');
    END IF;
    INSERT INTO public.retailer_plan_prefs (user_id, auto_renew) VALUES (auth.uid(), p_on)
    ON CONFLICT (user_id) DO UPDATE SET auto_renew = p_on, updated_at = now();
    RETURN jsonb_build_object('ok', true, 'auto_renew', p_on);
END;
$$;

REVOKE ALL ON FUNCTION public.set_plan_auto_renew(BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_plan_auto_renew(BOOLEAN) TO authenticated;

-- ── The caller's plan, renewing it first if it has just lapsed ─────────────
-- Only a plan that ended in the last 30 days renews: someone returning after
-- months should be asked, not charged on sight.

CREATE OR REPLACE FUNCTION public.my_plan()
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
    v_user    UUID := auth.uid();
    v_last    public.retailer_subscriptions%ROWTYPE;
    v_auto    BOOLEAN;
    v_renewal JSONB;
    v_renewed BOOLEAN := false;
    v_failed  TEXT;
BEGIN
    IF v_user IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'error', 'NOT_AUTHENTICATED');
    END IF;

    SELECT * INTO v_last FROM public.retailer_subscriptions
     WHERE user_id = v_user ORDER BY expires_at DESC LIMIT 1;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', true, 'active', false);
    END IF;

    SELECT COALESCE((SELECT auto_renew FROM public.retailer_plan_prefs WHERE user_id = v_user), true)
      INTO v_auto;

    IF v_last.expires_at <= now() AND v_auto AND v_last.expires_at > now() - INTERVAL '30 days' THEN
        v_renewal := public.plans_buy_period(v_user, v_last.plan_key, 'auto_renew');
        IF COALESCE((v_renewal->>'ok')::boolean, false) THEN
            v_renewed := true;
            SELECT * INTO v_last FROM public.retailer_subscriptions
             WHERE user_id = v_user ORDER BY expires_at DESC LIMIT 1;
        ELSE
            v_failed := v_renewal->>'error';
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'ok', true,
        'active', v_last.expires_at > now(),
        'plan_key', v_last.plan_key,
        'expires_at', v_last.expires_at,
        'auto_renew', v_auto,
        'renewed_now', v_renewed,
        'renewal_error', v_failed
    );
END;
$$;

REVOKE ALL ON FUNCTION public.my_plan() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.my_plan() TO authenticated;

COMMIT;
