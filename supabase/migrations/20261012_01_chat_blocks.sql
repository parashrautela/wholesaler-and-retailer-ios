-- Blocking in chat. Either side of a conversation can block the other: the
-- wholesaler blocks a store, or a store (owner or staff) blocks a wholesaler.
-- A block covers the pair — every conversation between that wholesaler and
-- that store — so a blocked party cannot reopen contact about another design.
-- While any block stands, neither side can send into those conversations; the
-- trigger below enforces that for every write path (iOS RPC and web inserts).
-- Blocks are visible to app operators in Supabase alongside content reports.

BEGIN;

CREATE TABLE IF NOT EXISTS public.chat_blocks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    blocker_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    blocker_side TEXT NOT NULL CHECK (blocker_side IN ('wholesaler', 'employee')),
    -- The conversation the block was made from; also the fallback scope when
    -- the conversation has no store attached.
    conversation_id UUID REFERENCES public.conversations(id) ON DELETE CASCADE,
    wholesaler_id UUID,
    retailer_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS chat_blocks_pair_side
    ON public.chat_blocks (wholesaler_id, retailer_id, blocker_side)
    WHERE retailer_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS chat_blocks_conversation_side
    ON public.chat_blocks (conversation_id, blocker_side)
    WHERE retailer_id IS NULL;

ALTER TABLE public.chat_blocks ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.chat_blocks FROM PUBLIC, anon, authenticated;
GRANT SELECT, DELETE ON TABLE public.chat_blocks TO service_role;

-- Blocks that apply to a conversation, from either side.
CREATE OR REPLACE FUNCTION public.chat_blocks_for(p_conversation UUID)
RETURNS SETOF public.chat_blocks
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
    SELECT b.*
      FROM public.conversations c
      JOIN public.chat_blocks b
        ON (c.retailer_id IS NOT NULL
            AND b.retailer_id = c.retailer_id
            AND b.wholesaler_id = c.wholesaler_id)
        OR (c.retailer_id IS NULL AND b.conversation_id = c.id)
     WHERE c.id = p_conversation;
$$;

REVOKE ALL ON FUNCTION public.chat_blocks_for(UUID) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.chat_block(p_conversation UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_side TEXT := public.chat_my_side(p_conversation);
    v_conv public.conversations%ROWTYPE;
BEGIN
    IF v_user IS NULL OR v_side IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'error', 'NOT_FOUND');
    END IF;

    SELECT * INTO v_conv FROM public.conversations WHERE id = p_conversation;

    IF NOT EXISTS (SELECT 1 FROM public.chat_blocks_for(p_conversation) WHERE blocker_side = v_side) THEN
        INSERT INTO public.chat_blocks (blocker_id, blocker_side, conversation_id, wholesaler_id, retailer_id)
        VALUES (v_user, v_side, p_conversation, v_conv.wholesaler_id, v_conv.retailer_id);
    END IF;

    RETURN jsonb_build_object('ok', true);
END;
$$;

REVOKE ALL ON FUNCTION public.chat_block(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.chat_block(UUID) TO authenticated;

-- Lifts this side's block. The other side's block, if any, stays.
CREATE OR REPLACE FUNCTION public.chat_unblock(p_conversation UUID)
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

    DELETE FROM public.chat_blocks
     WHERE id IN (SELECT id FROM public.chat_blocks_for(p_conversation) WHERE blocker_side = v_side);

    RETURN jsonb_build_object('ok', true);
END;
$$;

REVOKE ALL ON FUNCTION public.chat_unblock(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.chat_unblock(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.chat_block_state(p_conversation UUID)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
    v_side TEXT := public.chat_my_side(p_conversation);
BEGIN
    IF auth.uid() IS NULL OR v_side IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'error', 'NOT_FOUND');
    END IF;

    RETURN jsonb_build_object(
        'ok', true,
        'blocked_by_me',   EXISTS (SELECT 1 FROM public.chat_blocks_for(p_conversation) WHERE blocker_side = v_side),
        'blocked_by_them', EXISTS (SELECT 1 FROM public.chat_blocks_for(p_conversation) WHERE blocker_side <> v_side)
    );
END;
$$;

REVOKE ALL ON FUNCTION public.chat_block_state(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.chat_block_state(UUID) TO authenticated;

-- The caller's conversations that they (their side) have blocked, so the
-- chat list can stop previewing the blocked party's messages.
CREATE OR REPLACE FUNCTION public.chat_my_blocked_threads()
RETURNS JSONB
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
    SELECT COALESCE(jsonb_agg(c.id), '[]'::jsonb)
      FROM public.conversations c
     WHERE public.chat_my_side(c.id) IS NOT NULL
       AND EXISTS (SELECT 1 FROM public.chat_blocks_for(c.id) b
                    WHERE b.blocker_side = public.chat_my_side(c.id))
       AND (c.wholesaler_id = auth.uid()
            OR c.retailer_id IN (SELECT id FROM public.retailers WHERE user_id = auth.uid())
            OR (c.employee_id IS NOT NULL AND c.employee_id = public.my_employee_id()));
$$;

REVOKE ALL ON FUNCTION public.chat_my_blocked_threads() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.chat_my_blocked_threads() TO authenticated;

-- No new messages between a blocked pair, whichever client writes them.
CREATE OR REPLACE FUNCTION public.chat_reject_blocked_message()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM public.chat_blocks_for(NEW.conversation_id)) THEN
        RAISE EXCEPTION 'CHAT_BLOCKED' USING ERRCODE = 'P0001';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS chat_reject_blocked_message ON public.messages;
CREATE TRIGGER chat_reject_blocked_message
    BEFORE INSERT ON public.messages
    FOR EACH ROW EXECUTE FUNCTION public.chat_reject_blocked_message();

COMMENT ON TABLE public.chat_blocks IS
    'Chat blocks between a wholesaler and a store. While a row exists neither side can message the other.';

COMMIT;
