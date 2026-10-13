-- Objectionable-content filter for chat (App Review 1.2). New messages are
-- checked against an operator-editable list of whole words/phrases; a match
-- refuses the message on every write path (iOS RPC and web inserts). Operators
-- add or remove terms in Supabase; reports and blocks cover what slips past.

BEGIN;

CREATE TABLE IF NOT EXISTS public.chat_blocked_terms (
    term TEXT PRIMARY KEY CHECK (term = lower(btrim(term)) AND term <> ''),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.chat_blocked_terms ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.chat_blocked_terms FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, DELETE ON TABLE public.chat_blocked_terms TO service_role;

-- A starting list of slurs and abuse in English and romanised Hindi. Matched
-- as whole words, so ordinary words that contain them are unaffected.
INSERT INTO public.chat_blocked_terms (term) VALUES
    ('fuck'), ('fucking'), ('fucker'), ('motherfucker'), ('shit'), ('bitch'),
    ('bastard'), ('asshole'), ('cunt'), ('dick'), ('pussy'), ('whore'), ('slut'),
    ('nigger'), ('faggot'), ('retard'), ('rape'), ('kill you'),
    ('chutiya'), ('chutiye'), ('madarchod'), ('behenchod'), ('bhenchod'),
    ('bhosdike'), ('bhosdiwale'), ('gaand'), ('gandu'), ('randi'), ('harami'),
    ('kamina'), ('lund'), ('lauda'), ('lavda')
ON CONFLICT (term) DO NOTHING;

CREATE OR REPLACE FUNCTION public.chat_reject_objectionable_message()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
    v_text TEXT := lower(COALESCE(NEW.content, ''));
BEGIN
    IF EXISTS (
        SELECT 1 FROM public.chat_blocked_terms t
         WHERE v_text ~ ('\m' || regexp_replace(t.term, '([.*+?^${}()|\[\]\\])', '\\\1', 'g') || '\M')
    ) THEN
        RAISE EXCEPTION 'CHAT_CONTENT_REJECTED' USING ERRCODE = 'P0001';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS chat_reject_objectionable_message ON public.messages;
CREATE TRIGGER chat_reject_objectionable_message
    BEFORE INSERT ON public.messages
    FOR EACH ROW EXECUTE FUNCTION public.chat_reject_objectionable_message();

COMMENT ON TABLE public.chat_blocked_terms IS
    'Whole words/phrases refused in chat messages. Lower-case; edit from Supabase.';

COMMIT;
