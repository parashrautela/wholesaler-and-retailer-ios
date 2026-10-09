-- Retailer monetisation, step 1: retailer wallets + entitlements + paid themes.
--
-- The credits system is already keyed on auth.users(id) (the column is only
-- *named* wholesaler_id), so a retailer's wallet needs no schema change —
-- only a welcome grant, a rate card that knows its audience, and a way for a
-- signed-in retailer to buy something that stays bought.

BEGIN;

-- ── 1. The rate card knows who each price is for ────────────────────────────
-- Older wholesaler builds list every active row, so retailer-only prices are
-- hidden from them by RLS rather than by the app.

ALTER TABLE public.credit_prices
    ADD COLUMN IF NOT EXISTS audience TEXT NOT NULL DEFAULT 'wholesaler'
    CHECK (audience IN ('wholesaler', 'retailer', 'all'));

UPDATE public.credit_prices SET audience = 'all' WHERE feature_key LIKE 'chamak.%';

DROP POLICY IF EXISTS "rate card is readable" ON public.credit_prices;
CREATE POLICY "rate card is readable" ON public.credit_prices
    FOR SELECT USING (
        is_active AND (
            audience = 'all'
            OR (audience = 'retailer'
                AND EXISTS (SELECT 1 FROM public.retailers r WHERE r.user_id = auth.uid()))
            OR (audience = 'wholesaler'
                AND NOT EXISTS (SELECT 1 FROM public.retailers r WHERE r.user_id = auth.uid()))
        )
    );

INSERT INTO public.credit_prices (feature_key, credits, label, description, sort_order, audience)
VALUES
    ('theme.utsav',  500, 'Utsav store theme',  'Unlock once, keep forever', 110, 'retailer'),
    ('theme.neelam', 500, 'Neelam store theme', 'Unlock once, keep forever', 120, 'retailer')
ON CONFLICT (feature_key) DO NOTHING;

-- ── 2. Welcome gift for retailers ──────────────────────────────────────────
-- credits_grant_welcome() only reads NEW.user_id and NEW.verification_status,
-- both of which retailers has, and its idempotency key is per user.

DROP TRIGGER IF EXISTS trg_credits_welcome_retailer ON public.retailers;
CREATE TRIGGER trg_credits_welcome_retailer
    AFTER INSERT OR UPDATE OF verification_status ON public.retailers
    FOR EACH ROW EXECUTE FUNCTION public.credits_grant_welcome();

-- Retailers verified before this migration get the same gift, once.
DO $$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT user_id FROM public.retailers WHERE verification_status = 'verified' LOOP
        PERFORM public.grant_credits(
            p_user            => r.user_id,
            p_credits         => 2000,
            p_source          => 'welcome',
            p_idempotency_key => 'welcome:' || r.user_id,
            p_expires_at      => now() + INTERVAL '30 days',
            p_note            => 'Welcome gift'
        );
    END LOOP;
END $$;

-- ── 3. Entitlements: things a user has unlocked ────────────────────────────

CREATE TABLE IF NOT EXISTS public.entitlements (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    entitlement_key TEXT NOT NULL,
    source          TEXT NOT NULL CHECK (source IN ('purchase', 'plan', 'grant')),
    ledger_id       UUID,
    expires_at      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, entitlement_key)
);

ALTER TABLE public.entitlements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "own entitlements" ON public.entitlements;
CREATE POLICY "own entitlements" ON public.entitlements
    FOR SELECT USING (auth.uid() = user_id);

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
    );
$$;

REVOKE ALL ON FUNCTION public.has_entitlement(UUID, TEXT) FROM PUBLIC, anon, authenticated;

-- ── 4. Buying a one-off unlock with the caller's own credits ───────────────
-- spend_credits is service-role only; this is the signed-in door to it. Only
-- keys under an allowed prefix can be bought here, so it can never be used to
-- pay for metered work (Chamak etc.) that the pipeline charges itself.

CREATE OR REPLACE FUNCTION public.purchase_entitlement(p_key TEXT)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
    v_user  UUID := auth.uid();
    v_spend JSONB;
BEGIN
    IF v_user IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'error', 'NOT_AUTHENTICATED');
    END IF;

    IF p_key IS NULL OR p_key NOT LIKE 'theme.%' THEN
        RETURN jsonb_build_object('ok', false, 'error', 'NOT_PURCHASABLE');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.retailers
                    WHERE user_id = v_user AND verification_status = 'verified') THEN
        RETURN jsonb_build_object('ok', false, 'error', 'NOT_VERIFIED');
    END IF;

    IF public.has_entitlement(v_user, p_key) THEN
        RETURN jsonb_build_object('ok', true, 'already_owned', true, 'charged', 0);
    END IF;

    -- One key per user per unlock: a retried tap replays, never double-charges.
    v_spend := public.spend_credits(
        p_user            => v_user,
        p_feature_key     => p_key,
        p_idempotency_key => 'entitlement:' || v_user || ':' || p_key,
        p_reference_type  => 'entitlement',
        p_reference_id    => p_key
    );

    IF NOT COALESCE((v_spend->>'ok')::boolean, false) THEN
        RETURN v_spend;
    END IF;

    INSERT INTO public.entitlements (user_id, entitlement_key, source, ledger_id)
    VALUES (v_user, p_key, 'purchase', NULLIF(v_spend->>'ledger_id', '')::uuid)
    ON CONFLICT (user_id, entitlement_key)
    DO UPDATE SET expires_at = NULL, source = 'purchase';

    RETURN v_spend || jsonb_build_object('entitlement_key', p_key);
END;
$$;

REVOKE ALL ON FUNCTION public.purchase_entitlement(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.purchase_entitlement(TEXT) TO authenticated;

-- ── 5. A paid theme can only be selected once it is owned ──────────────────
-- The app hides the button, but retailers can update their own row, so the
-- rule has to live here. Free themes have no price row and pass straight
-- through; service-role writes (auth.uid() IS NULL) are not restricted.

CREATE OR REPLACE FUNCTION public.guard_retailer_theme()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
    IF NEW.selected_theme IS DISTINCT FROM OLD.selected_theme
       AND auth.uid() IS NOT NULL
       AND EXISTS (SELECT 1 FROM public.credit_prices
                    WHERE feature_key = 'theme.' || NEW.selected_theme
                      AND is_active AND credits > 0)
       AND NOT public.has_entitlement(NEW.user_id, 'theme.' || NEW.selected_theme) THEN
        RAISE EXCEPTION 'THEME_LOCKED' USING ERRCODE = 'P0001';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS retailers_guard_theme ON public.retailers;
CREATE TRIGGER retailers_guard_theme
    BEFORE UPDATE OF selected_theme ON public.retailers
    FOR EACH ROW EXECUTE FUNCTION public.guard_retailer_theme();

COMMIT;
