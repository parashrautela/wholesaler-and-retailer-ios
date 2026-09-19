-- Orders and chat: the writes.
--
-- `orders`, `conversations` and `messages` have SELECT policies only. The web
-- writes through server routes with the service role; the iOS app wrote to
-- the tables directly, so every write matched zero rows — and an UPDATE that
-- matches nothing is not an error, which is why Accept "did nothing".
--
-- These functions are the signed-in door. Who the caller is comes from the
-- tables (wholesalers / retailers / employees), never from
-- user_metadata.role, which accounts created on iOS do not reliably carry.
-- The tables stay closed to direct writes.

BEGIN;

-- The caller's employees row, if they are active staff.
CREATE OR REPLACE FUNCTION public.my_employee_id()
RETURNS UUID
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
    SELECT id FROM public.employees
     WHERE auth_user_id = auth.uid() AND status = 'active' LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.my_employee_id() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.my_employee_id() TO authenticated;

-- ── Orders ─────────────────────────────────────────────────────────────────
-- An order only moves forward, and each side moves only its own steps:
--   wholesaler: pending → accepted | rejected
--               accepted → in_production | packed
--               in_production → packed
--               packed → dispatched
--   store:      dispatched → received → completed
-- A store owner may act on any of the store's orders; staff only on the ones
-- they placed.

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
        -- Same answer as a missing order: don't confirm that the id exists.
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
        -- A second tap, or the other side got there first.
        IF v_order.status = p_status THEN
            RETURN jsonb_build_object('ok', true, 'status', v_order.status, 'unchanged', true);
        END IF;
        RETURN jsonb_build_object('ok', false, 'error', 'INVALID_TRANSITION',
                                  'from', v_order.status, 'to', p_status);
    END IF;

    UPDATE public.orders SET
        status           = p_status,
        updated_at       = now(),
        rejection_reason = CASE WHEN p_status = 'rejected'
                                THEN COALESCE(NULLIF(btrim(p_reason), ''), 'No reason provided.')
                                ELSE rejection_reason END,
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

REVOKE ALL ON FUNCTION public.order_set_status(UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.order_set_status(UUID, TEXT, TEXT) TO authenticated;

-- ── Chat ───────────────────────────────────────────────────────────────────
-- A conversation is a store asking a wholesaler about one design. It is
-- opened from the store side only; one per (design, asker).

CREATE OR REPLACE FUNCTION public.chat_open(p_product UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
    v_user       UUID := auth.uid();
    v_retailer   UUID := public.my_retailer_id();
    v_employee   UUID := public.my_employee_id();
    v_wholesaler UUID;
    v_conv       UUID;
BEGIN
    IF v_user IS NULL OR v_retailer IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'error', 'NO_STORE');
    END IF;

    SELECT wholesaler_id INTO v_wholesaler FROM public.products WHERE id = p_product;
    IF v_wholesaler IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'error', 'PRODUCT_NOT_FOUND');
    END IF;

    -- One at a time per asker, so a double tap can't open two threads.
    PERFORM pg_advisory_xact_lock(hashtextextended('chat:' || v_user::text || p_product::text, 0));

    SELECT id INTO v_conv FROM public.conversations
     WHERE product_id = p_product AND retailer_id = v_retailer
       AND employee_id IS NOT DISTINCT FROM v_employee
     LIMIT 1;

    IF v_conv IS NULL THEN
        -- conversations.wholesaler_id references profiles, which older
        -- wholesaler accounts may lack (the web heals this the same way).
        INSERT INTO public.profiles (id, email, role)
        VALUES (v_wholesaler, 'wholesaler_' || left(v_wholesaler::text, 8) || '@jewelindia.com', 'wholesaler')
        ON CONFLICT (id) DO NOTHING;

        INSERT INTO public.conversations (product_id, wholesaler_id, employee_id, retailer_id)
        VALUES (p_product, v_wholesaler, v_employee, v_retailer)
        RETURNING id INTO v_conv;
    ELSE
        UPDATE public.conversations SET is_visible_to_employee = true WHERE id = v_conv;
    END IF;

    RETURN jsonb_build_object('ok', true, 'conversation_id', v_conv);
END;
$$;

REVOKE ALL ON FUNCTION public.chat_open(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.chat_open(UUID) TO authenticated;

-- Which side of a conversation the caller is on, or NULL if neither.
-- `messages.sender_type` knows two sides; a store owner writes as the store.
CREATE OR REPLACE FUNCTION public.chat_my_side(p_conversation UUID)
RETURNS TEXT
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
    SELECT CASE
        WHEN c.wholesaler_id = auth.uid() THEN 'wholesaler'
        WHEN EXISTS (SELECT 1 FROM public.retailers r
                      WHERE r.id = c.retailer_id AND r.user_id = auth.uid()) THEN 'employee'
        WHEN c.employee_id IS NOT NULL AND c.employee_id = public.my_employee_id() THEN 'employee'
    END
    FROM public.conversations c WHERE c.id = p_conversation;
$$;

REVOKE ALL ON FUNCTION public.chat_my_side(UUID) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.chat_send(p_conversation UUID, p_content TEXT)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
    v_side TEXT := public.chat_my_side(p_conversation);
    v_text TEXT := btrim(COALESCE(p_content, ''));
    v_id   UUID;
BEGIN
    IF auth.uid() IS NULL OR v_side IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'error', 'NOT_FOUND');
    END IF;
    IF v_text = '' OR length(v_text) > 4000 THEN
        RETURN jsonb_build_object('ok', false, 'error', 'INVALID_CONTENT');
    END IF;

    INSERT INTO public.messages (conversation_id, sender_type, sender_id, content)
    VALUES (p_conversation, v_side, auth.uid(), v_text)
    RETURNING id INTO v_id;

    -- A reply brings a hidden thread back for whoever hid it.
    UPDATE public.conversations
       SET updated_at = now(), is_visible_to_wholesaler = true, is_visible_to_employee = true
     WHERE id = p_conversation;

    RETURN jsonb_build_object('ok', true, 'message_id', v_id);
END;
$$;

REVOKE ALL ON FUNCTION public.chat_send(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.chat_send(UUID, TEXT) TO authenticated;

-- Marks the OTHER side's messages read — never your own.
CREATE OR REPLACE FUNCTION public.chat_mark_read(p_conversation UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
    v_side TEXT := public.chat_my_side(p_conversation);
BEGIN
    IF auth.uid() IS NULL OR v_side IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'error', 'NOT_FOUND');
    END IF;
    UPDATE public.messages SET is_read = true
     WHERE conversation_id = p_conversation AND sender_type <> v_side AND NOT COALESCE(is_read, false);
    RETURN jsonb_build_object('ok', true);
END;
$$;

REVOKE ALL ON FUNCTION public.chat_mark_read(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.chat_mark_read(UUID) TO authenticated;

-- The store's threads: staff see their own, the owner sees the whole store's.
-- (The existing SELECT policies already say exactly this; nothing to add.)

COMMIT;
