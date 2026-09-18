-- Retailer monetisation, step 6 groundwork: what a store does, and on what.
--
-- Business Insights needs history before it can report anything, and Device
-- Add-on Limits needs to know how many devices a store really uses before a
-- limit can be chosen. Both start as plain records: nothing here blocks,
-- charges or limits anyone.

BEGIN;

-- ── Store activity ─────────────────────────────────────────────────────────
-- Written by owner and staff alike; read by the owner only — it is their
-- business report, and staff have no need to see each other's activity.

CREATE TABLE IF NOT EXISTS public.store_events (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    retailer_id UUID NOT NULL DEFAULT public.my_retailer_id()
                REFERENCES public.retailers(id) ON DELETE CASCADE,
    actor_id    UUID DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE SET NULL,
    event       TEXT NOT NULL CHECK (event ~ '^[a-z_]+\.[a-z_]+$' AND length(event) <= 60),
    product_id  UUID REFERENCES public.products(id) ON DELETE SET NULL,
    customer_id UUID REFERENCES public.retailer_customers(id) ON DELETE SET NULL,
    metadata    JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (pg_column_size(metadata) <= 2048),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_store_events_retailer_time
    ON public.store_events (retailer_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_store_events_retailer_event
    ON public.store_events (retailer_id, event, created_at DESC);

ALTER TABLE public.store_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "store records its activity" ON public.store_events;
CREATE POLICY "store records its activity" ON public.store_events
    FOR INSERT TO authenticated
    WITH CHECK (retailer_id = public.my_retailer_id() AND actor_id = auth.uid());

DROP POLICY IF EXISTS "owner reads store activity" ON public.store_events;
CREATE POLICY "owner reads store activity" ON public.store_events
    FOR SELECT TO authenticated
    USING (retailer_id IN (SELECT id FROM public.retailers WHERE user_id = auth.uid()));

-- ── Devices ────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.store_devices (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    retailer_id  UUID NOT NULL REFERENCES public.retailers(id) ON DELETE CASCADE,
    user_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    device_id    TEXT NOT NULL CHECK (length(device_id) BETWEEN 8 AND 64),
    model        TEXT CHECK (model IS NULL OR length(model) <= 60),
    app_version  TEXT CHECK (app_version IS NULL OR length(app_version) <= 20),
    first_seen   TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen    TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, device_id)
);

CREATE INDEX IF NOT EXISTS idx_store_devices_retailer
    ON public.store_devices (retailer_id, last_seen DESC);

ALTER TABLE public.store_devices ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "owner reads store devices" ON public.store_devices;
CREATE POLICY "owner reads store devices" ON public.store_devices
    FOR SELECT TO authenticated
    USING (user_id = auth.uid()
           OR retailer_id IN (SELECT id FROM public.retailers WHERE user_id = auth.uid()));

-- The only way in: the row's owner and store come from the session, never
-- from the caller. Returns the store's device count so a limit can later be
-- answered from the same call.
CREATE OR REPLACE FUNCTION public.register_device(p_device_id TEXT, p_model TEXT, p_app_version TEXT)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
    v_user     UUID := auth.uid();
    v_retailer UUID := public.my_retailer_id();
    v_count    INT;
BEGIN
    IF v_user IS NULL OR v_retailer IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'error', 'NO_STORE');
    END IF;

    INSERT INTO public.store_devices (retailer_id, user_id, device_id, model, app_version)
    VALUES (v_retailer, v_user, p_device_id, left(p_model, 60), left(p_app_version, 20))
    ON CONFLICT (user_id, device_id) DO UPDATE
        SET last_seen = now(), model = EXCLUDED.model, app_version = EXCLUDED.app_version,
            retailer_id = EXCLUDED.retailer_id;

    SELECT count(DISTINCT device_id) INTO v_count
      FROM public.store_devices
     WHERE retailer_id = v_retailer AND last_seen > now() - INTERVAL '30 days';

    RETURN jsonb_build_object('ok', true, 'active_devices', v_count, 'limit', NULL);
END;
$$;

REVOKE ALL ON FUNCTION public.register_device(TEXT, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.register_device(TEXT, TEXT, TEXT) TO authenticated;

COMMIT;
