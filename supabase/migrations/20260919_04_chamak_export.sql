-- Retailer monetisation, step 5: View only / View & Export.
--
-- A Chamak result is view-only by default — the app shows it watermarked and
-- capture-protected. "View & Export" is one extra charge per image, recorded
-- as an entitlement (`export.<generation id>`) so it is paid for once and
-- stays unlocked on every device.
--
-- What this does and does not protect: the unlock is a record the app
-- honours. The image file itself is readable by its owner's session either
-- way (storage policy is per-user folder), as it has to be to be shown.

BEGIN;

INSERT INTO public.credit_prices (feature_key, credits, label, description, sort_order, audience)
VALUES ('chamak.export', 100, 'Export a Chamak image',
        'Save or share one result without the watermark', 45, 'retailer')
ON CONFLICT (feature_key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.purchase_export(p_generation UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
    v_user  UUID := auth.uid();
    v_key   TEXT := 'export.' || p_generation;
    v_spend JSONB;
BEGIN
    IF v_user IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'error', 'NOT_AUTHENTICATED');
    END IF;

    -- Their own, finished generation — anything else has nothing to export.
    IF NOT EXISTS (SELECT 1 FROM public.chamak_generations
                    WHERE id = p_generation AND wholesaler_id = v_user
                      AND status = 'done' AND output_image_url IS NOT NULL) THEN
        RETURN jsonb_build_object('ok', false, 'error', 'NOT_EXPORTABLE');
    END IF;

    IF public.has_entitlement(v_user, v_key) THEN
        RETURN jsonb_build_object('ok', true, 'already_owned', true, 'charged', 0);
    END IF;

    v_spend := public.spend_credits(
        p_user            => v_user,
        p_feature_key     => 'chamak.export',
        p_idempotency_key => 'export:' || p_generation,
        p_reference_type  => 'chamak_export',
        p_reference_id    => p_generation::text
    );

    IF NOT COALESCE((v_spend->>'ok')::boolean, false) THEN
        RETURN v_spend;
    END IF;

    INSERT INTO public.entitlements (user_id, entitlement_key, source, ledger_id)
    VALUES (v_user, v_key, 'purchase', NULLIF(v_spend->>'ledger_id', '')::uuid)
    ON CONFLICT (user_id, entitlement_key) DO NOTHING;

    RETURN v_spend || jsonb_build_object('entitlement_key', v_key);
END;
$$;

REVOKE ALL ON FUNCTION public.purchase_export(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.purchase_export(UUID) TO authenticated;

COMMIT;
