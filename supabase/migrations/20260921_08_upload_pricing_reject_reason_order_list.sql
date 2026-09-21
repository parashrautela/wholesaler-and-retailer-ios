-- 1. Product uploads are priced per studio image: ₹20 an image at 10 credits
--    per rupee = 200 credits each. The uploader picks the count (2 is the
--    base); the AI pipeline charges `product.images_<n>` before generating.
-- 2. A rejection must say why. The server no longer fills in a stand-in.
-- 3. wholesaler_orders(): the Orders list with what a wholesaler may not read
--    directly — the design and the store that asked for it.

BEGIN;

INSERT INTO public.credit_prices (feature_key, credits, label, description, sort_order, audience) VALUES
    ('product.images_1', 200, 'Upload · 1 studio image',  '₹20 per image', 51, 'wholesaler'),
    ('product.images_2', 400, 'Upload · 2 studio images', '₹20 per image', 52, 'wholesaler'),
    ('product.images_3', 600, 'Upload · 3 studio images', '₹20 per image', 53, 'wholesaler'),
    ('product.images_4', 800, 'Upload · 4 studio images', '₹20 per image', 54, 'wholesaler')
ON CONFLICT (feature_key) DO NOTHING;

-- ── Reject needs a reason ──────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.order_set_status(p_order UUID, p_status TEXT, p_reason TEXT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
    v_user   UUID := auth.uid();
    v_order  public.orders%ROWTYPE;
    v_side   TEXT;
    v_ok     BOOLEAN;
    v_reason TEXT := NULLIF(btrim(COALESCE(p_reason, '')), '');
BEGIN
    IF v_user IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'error', 'NOT_AUTHENTICATED');
    END IF;

    SELECT * INTO v_order FROM public.orders WHERE id = p_order FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'error', 'NOT_FOUND');
    END IF;

    IF v_order.wholesaler_id = v_user THEN
        v_side := 'wholesaler';
    ELSIF EXISTS (SELECT 1 FROM public.retailers
                   WHERE id = v_order.retailer_id AND user_id = v_user) THEN
        v_side := 'store';
    ELSIF v_order.employee_id IS NOT NULL AND v_order.employee_id = public.my_employee_id() THEN
        v_side := 'store';
    ELSE
        RETURN jsonb_build_object('ok', false, 'error', 'NOT_FOUND');
    END IF;

    v_ok := CASE v_side
        WHEN 'wholesaler' THEN
            (v_order.status = 'pending'       AND p_status IN ('accepted', 'rejected'))
         OR (v_order.status = 'accepted'      AND p_status IN ('in_production', 'packed'))
         OR (v_order.status = 'in_production' AND p_status = 'packed')
         OR (v_order.status = 'packed'        AND p_status = 'dispatched')
        ELSE
            (v_order.status = 'dispatched'    AND p_status = 'received')
         OR (v_order.status = 'received'      AND p_status = 'completed')
    END;

    IF NOT COALESCE(v_ok, false) THEN
        IF v_order.status = p_status THEN
            RETURN jsonb_build_object('ok', true, 'status', v_order.status, 'unchanged', true);
        END IF;
        RETURN jsonb_build_object('ok', false, 'error', 'INVALID_TRANSITION',
                                  'from', v_order.status, 'to', p_status);
    END IF;

    IF p_status = 'rejected' AND (v_reason IS NULL OR length(v_reason) > 500) THEN
        RETURN jsonb_build_object('ok', false, 'error', 'REASON_REQUIRED');
    END IF;

    UPDATE public.orders SET
        status           = p_status,
        updated_at       = now(),
        rejection_reason = CASE WHEN p_status = 'rejected' THEN v_reason ELSE rejection_reason END,
        accepted_at      = CASE WHEN p_status = 'accepted'      THEN now() ELSE accepted_at END,
        rejected_at      = CASE WHEN p_status = 'rejected'      THEN now() ELSE rejected_at END,
        production_at    = CASE WHEN p_status = 'in_production' THEN now() ELSE production_at END,
        packed_at        = CASE WHEN p_status = 'packed'        THEN now() ELSE packed_at END,
        dispatched_at    = CASE WHEN p_status = 'dispatched'    THEN now() ELSE dispatched_at END,
        received_at      = CASE WHEN p_status = 'received'      THEN now() ELSE received_at END,
        completed_at     = CASE WHEN p_status = 'completed'     THEN now() ELSE completed_at END
     WHERE id = p_order;

    RETURN jsonb_build_object('ok', true, 'status', p_status);
END;
$$;

-- ── The wholesaler's orders, with the design and the store ─────────────────

CREATE OR REPLACE FUNCTION public.wholesaler_orders()
RETURNS JSONB
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
    SELECT COALESCE(jsonb_agg(row ORDER BY (row->>'created_at') DESC), '[]'::jsonb)
      FROM (
        SELECT to_jsonb(o) || jsonb_build_object(
            'product_title', p.title,
            'product_image', COALESCE(p.processed_image_url, p.image_url, p.raw_image_url),
            'product_type',  p.jewellery_type,
            'store_name',    COALESCE(NULLIF(r.business_name, ''), r.full_name),
            'store_city',    NULLIF(concat_ws(', ', NULLIF(r.city, ''), NULLIF(r.state, '')), ''),
            'placed_by',     CASE WHEN o.employee_id IS NOT NULL THEN e.full_name ELSE r.full_name END,
            'placed_by_staff', o.employee_id IS NOT NULL
        ) AS row
          FROM public.orders o
          LEFT JOIN public.products  p ON p.id = o.product_id
          LEFT JOIN public.retailers r ON r.id = o.retailer_id
          LEFT JOIN public.employees e ON e.id = o.employee_id
         WHERE o.wholesaler_id = auth.uid()
           AND COALESCE(o.is_visible_to_wholesaler, true)
      ) rows;
$$;

REVOKE ALL ON FUNCTION public.wholesaler_orders() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.wholesaler_orders() TO authenticated;

COMMIT;
