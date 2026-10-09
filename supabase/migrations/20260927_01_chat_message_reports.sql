-- In-app reporting for chat messages. Reports are submitted only through the
-- participant-checking RPC and are reviewed by the app team in Supabase.

BEGIN;

CREATE TABLE IF NOT EXISTS public.user_content_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    reported_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    conversation_id UUID REFERENCES public.conversations(id) ON DELETE SET NULL,
    message_id UUID REFERENCES public.messages(id) ON DELETE SET NULL,
    message_snapshot TEXT NOT NULL,
    reason TEXT NOT NULL CHECK (reason IN ('spam', 'harassment', 'inappropriate', 'scam', 'other')),
    details TEXT,
    status TEXT NOT NULL DEFAULT 'new' CHECK (status IN ('new', 'in_review', 'actioned', 'dismissed')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    reviewed_at TIMESTAMPTZ,
    UNIQUE (reporter_id, message_id)
);

ALTER TABLE public.user_content_reports ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.user_content_reports FROM PUBLIC, anon, authenticated;
GRANT SELECT, UPDATE ON TABLE public.user_content_reports TO service_role;

CREATE OR REPLACE FUNCTION public.chat_report_message(
    p_conversation UUID,
    p_message UUID,
    p_reason TEXT,
    p_details TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_side TEXT;
    v_message public.messages%ROWTYPE;
    v_inserted UUID;
BEGIN
    IF v_user IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'error', 'NOT_AUTHENTICATED');
    END IF;

    v_side := public.chat_my_side(p_conversation);
    IF v_side IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'error', 'NOT_FOUND');
    END IF;

    SELECT * INTO v_message
      FROM public.messages
     WHERE id = p_message AND conversation_id = p_conversation;
    IF NOT FOUND OR v_message.sender_id = v_user OR COALESCE(v_message.sender_type, '') = v_side THEN
        RETURN jsonb_build_object('ok', false, 'error', 'NOT_FOUND');
    END IF;

    IF p_reason IS NULL OR p_reason NOT IN ('spam', 'harassment', 'inappropriate', 'scam', 'other') THEN
        RETURN jsonb_build_object('ok', false, 'error', 'INVALID_REASON');
    END IF;

    INSERT INTO public.user_content_reports (
        reporter_id, reported_user_id, conversation_id, message_id,
        message_snapshot, reason, details
    ) VALUES (
        v_user, v_message.sender_id, p_conversation, p_message,
        left(v_message.content, 4000), p_reason, left(nullif(btrim(p_details), ''), 1000)
    )
    ON CONFLICT (reporter_id, message_id) DO NOTHING
    RETURNING id INTO v_inserted;

    RETURN jsonb_build_object(
        'ok', true,
        'already_reported', v_inserted IS NULL
    );
END;
$$;

REVOKE ALL ON FUNCTION public.chat_report_message(UUID, UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.chat_report_message(UUID, UUID, TEXT, TEXT) TO authenticated;

COMMENT ON TABLE public.user_content_reports IS
    'User reports of chat content. App operators review new reports from Supabase.';

COMMIT;
