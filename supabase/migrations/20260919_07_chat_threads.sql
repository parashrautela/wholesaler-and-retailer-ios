-- The chat list, for whichever side is asking.
--
-- The list needs things the caller cannot read directly: a wholesaler has no
-- SELECT on `retailers`, and a store must not learn who supplies a design
-- before ordering (the marketplace keeps suppliers private). So this answers
-- with what each side may see: the wholesaler gets the store's name and who
-- asked; the store gets the design only.

BEGIN;

CREATE OR REPLACE FUNCTION public.chat_threads()
RETURNS JSONB
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
    WITH mine AS (
        SELECT c.*,
               CASE WHEN c.wholesaler_id = auth.uid() THEN 'wholesaler' ELSE 'employee' END AS side
          FROM public.conversations c
         WHERE (c.wholesaler_id = auth.uid() AND COALESCE(c.is_visible_to_wholesaler, true))
            OR (c.retailer_id IN (SELECT id FROM public.retailers WHERE user_id = auth.uid()))
            OR (c.employee_id IS NOT NULL AND c.employee_id = public.my_employee_id()
                AND COALESCE(c.is_visible_to_employee, true))
    )
    SELECT COALESCE(jsonb_agg(row ORDER BY (row->>'last_at') DESC NULLS LAST), '[]'::jsonb)
      FROM (
        SELECT jsonb_build_object(
            'id',            m.id,
            'side',          m.side,
            'product_id',    m.product_id,
            'product_title', p.title,
            'product_image', COALESCE(p.processed_image_url, p.image_url, p.raw_image_url),
            'store_name',    CASE WHEN m.side = 'wholesaler' THEN r.business_name END,
            'asked_by',      CASE WHEN m.side = 'wholesaler' THEN COALESCE(e.full_name, r.full_name) END,
            'last_message',  lm.content,
            'last_from',     lm.sender_type,
            'last_at',       COALESCE(lm.created_at, m.created_at),
            'unread',        (SELECT count(*) FROM public.messages u
                               WHERE u.conversation_id = m.id
                                 AND u.sender_type <> m.side
                                 AND NOT COALESCE(u.is_read, false))
        ) AS row
          FROM mine m
          LEFT JOIN public.products  p ON p.id = m.product_id
          LEFT JOIN public.retailers r ON r.id = m.retailer_id
          LEFT JOIN public.employees e ON e.id = m.employee_id
          LEFT JOIN LATERAL (
              SELECT content, sender_type, created_at FROM public.messages
               WHERE conversation_id = m.id ORDER BY created_at DESC LIMIT 1
          ) lm ON true
      ) rows;
$$;

REVOKE ALL ON FUNCTION public.chat_threads() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.chat_threads() TO authenticated;

COMMIT;
