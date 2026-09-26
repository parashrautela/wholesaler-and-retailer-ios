-- Fixed StoreKit consumables. Keep the App Store Connect product names and
-- quantities in sync with this table before making a product available.
BEGIN;

CREATE TABLE IF NOT EXISTS public.apple_iap_products (
    product_id TEXT PRIMARY KEY,
    -- Apple product keys are independent of the legacy Razorpay pack table.
    pack_key TEXT NOT NULL,
    credits INT NOT NULL CHECK (credits > 0),
    active BOOLEAN NOT NULL DEFAULT true
);

INSERT INTO public.apple_iap_products (product_id, pack_key, credits) VALUES
    ('com.jewelindia.credits.starter', 'starter', 5000),
    ('com.jewelindia.credits.popular', 'popular', 10000),
    ('com.jewelindia.credits.pro', 'pro', 25000),
    ('com.jewelindia.credits.bulk', 'bulk', 50000)
ON CONFLICT (product_id) DO NOTHING;

ALTER TABLE public.apple_iap_products ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "active Apple packs are readable" ON public.apple_iap_products;
CREATE POLICY "active Apple packs are readable" ON public.apple_iap_products
    FOR SELECT TO authenticated USING (active);
GRANT SELECT ON public.apple_iap_products TO authenticated;
GRANT ALL ON public.apple_iap_products TO service_role;
REVOKE INSERT, UPDATE, DELETE ON public.apple_iap_products FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.record_apple_credit_purchase(
    p_user UUID,
    p_transaction_id TEXT,
    p_product_id TEXT,
    p_signed_transaction JSONB
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
    v_product public.apple_iap_products%ROWTYPE;
    v_purchase_id UUID;
    v_existing public.credit_purchases%ROWTYPE;
    v_grant JSONB;
    v_provider_id TEXT := 'apple:' || btrim(COALESCE(p_transaction_id, ''));
BEGIN
    IF p_user IS NULL OR btrim(COALESCE(p_transaction_id, '')) = '' THEN
        RETURN jsonb_build_object('ok', false, 'error', 'INVALID_ARGUMENTS');
    END IF;

    SELECT * INTO v_product FROM public.apple_iap_products
      WHERE product_id = p_product_id AND active FOR SHARE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'error', 'UNKNOWN_PRODUCT');
    END IF;

    PERFORM public.credits_ensure_account(p_user);
    INSERT INTO public.credit_purchases (
        account_id, provider, provider_txn_id, pack_key, credits,
        status, receipt_json, settled_at
    ) VALUES (
        p_user, 'apple', v_provider_id, v_product.pack_key, v_product.credits,
        'paid', p_signed_transaction, now()
    ) ON CONFLICT (provider_txn_id) DO NOTHING
      RETURNING id INTO v_purchase_id;

    IF v_purchase_id IS NULL THEN
        SELECT * INTO v_existing FROM public.credit_purchases
          WHERE provider_txn_id = v_provider_id;
        IF v_existing.account_id IS DISTINCT FROM p_user
           OR v_existing.provider IS DISTINCT FROM 'apple'
           OR v_existing.receipt_json->>'productId' IS DISTINCT FROM p_product_id THEN
            RETURN jsonb_build_object('ok', false, 'error', 'TRANSACTION_ALREADY_USED');
        END IF;
        RETURN jsonb_build_object('ok', true, 'replayed', true,
            'credits', v_existing.credits, 'status', v_existing.status);
    END IF;

    v_grant := public.grant_credits(
        p_user => p_user,
        p_credits => v_product.credits,
        p_source => 'purchase',
        p_idempotency_key => v_provider_id,
        p_expires_at => NULL,
        p_purchase_id => v_purchase_id,
        p_note => 'App Store ' || v_product.pack_key,
        p_metadata => jsonb_build_object('provider', 'apple', 'product_id', p_product_id)
    );
    IF NOT COALESCE((v_grant->>'ok')::boolean, false) THEN
        RAISE EXCEPTION 'Could not grant verified Apple purchase %', p_transaction_id;
    END IF;
    RETURN jsonb_build_object('ok', true, 'replayed', false,
        'credits', v_product.credits, 'balance', v_grant->'balance');
END;
$$;

REVOKE ALL ON FUNCTION public.record_apple_credit_purchase(UUID, TEXT, TEXT, JSONB)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_apple_credit_purchase(UUID, TEXT, TEXT, JSONB)
    TO service_role;

-- A verified App Store refund removes only unused credits from this purchase.
-- Credits already spent become recovery_owed without making a balance negative.
CREATE OR REPLACE FUNCTION public.record_apple_credit_refund(
    p_transaction_id TEXT,
    p_notification JSONB
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
    v_purchase public.credit_purchases%ROWTYPE;
    v_unused INT;
    v_balance INT;
BEGIN
    SELECT * INTO v_purchase FROM public.credit_purchases
      WHERE provider = 'apple'
        AND provider_txn_id = 'apple:' || btrim(COALESCE(p_transaction_id, ''))
      FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'error', 'PURCHASE_NOT_FOUND');
    END IF;
    IF v_purchase.status = 'refunded' THEN
        RETURN jsonb_build_object('ok', true, 'replayed', true);
    END IF;

    PERFORM 1 FROM public.credit_lots WHERE purchase_id = v_purchase.id FOR UPDATE;
    SELECT COALESCE(SUM(credits_remaining), 0) INTO v_unused
      FROM public.credit_lots WHERE purchase_id = v_purchase.id;
    UPDATE public.credit_lots SET credits_remaining = 0
      WHERE purchase_id = v_purchase.id;
    v_balance := public.credits_recompute(v_purchase.account_id);

    UPDATE public.credit_accounts
       SET lifetime_granted = GREATEST(lifetime_granted - v_unused, 0),
           recovery_owed = recovery_owed + GREATEST(v_purchase.credits - v_unused, 0)
     WHERE wholesaler_id = v_purchase.account_id;
    UPDATE public.credit_purchases
       SET status = 'refunded', receipt_json = COALESCE(receipt_json, '{}'::jsonb)
           || jsonb_build_object('refund_notification', p_notification)
     WHERE id = v_purchase.id;
    INSERT INTO public.credit_ledger (
        account_id, delta, kind, reference_type, reference_id,
        idempotency_key, balance_after, metadata
    ) VALUES (
        v_purchase.account_id, -v_unused, 'adjustment', 'purchase', v_purchase.id::text,
        'apple-refund:' || p_transaction_id, v_balance,
        jsonb_build_object('provider', 'apple', 'spent_credits', v_purchase.credits - v_unused)
    );
    RETURN jsonb_build_object('ok', true, 'removed', v_unused,
        'recovery_owed', v_purchase.credits - v_unused);
END;
$$;

REVOKE ALL ON FUNCTION public.record_apple_credit_refund(TEXT, JSONB)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_apple_credit_refund(TEXT, JSONB)
    TO service_role;

COMMIT;
