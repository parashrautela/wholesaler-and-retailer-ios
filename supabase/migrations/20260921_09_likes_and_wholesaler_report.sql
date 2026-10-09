-- Likes on wholesaler designs, and the weekly/monthly report built from them.
--
-- Anyone in a store — the owner, the owner in Employee View, active staff —
-- can heart a design. One like per person per design. The wholesaler never
-- sees who liked what; they see counts in their report.

BEGIN;

CREATE TABLE IF NOT EXISTS public.product_likes (
    product_id  UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    user_id     UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
    retailer_id UUID NOT NULL REFERENCES public.retailers(id) ON DELETE CASCADE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (product_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_product_likes_product_time
    ON public.product_likes (product_id, created_at DESC);

ALTER TABLE public.product_likes ENABLE ROW LEVEL SECURITY;

-- People see their own hearts, to draw them filled. Writes go through
-- toggle_product_like only.
DROP POLICY IF EXISTS "own likes" ON public.product_likes;
CREATE POLICY "own likes" ON public.product_likes
    FOR SELECT TO authenticated USING (user_id = auth.uid());

CREATE OR REPLACE FUNCTION public.toggle_product_like(p_product UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
    v_user     UUID := auth.uid();
    v_retailer UUID := public.my_retailer_id();
BEGIN
    IF v_user IS NULL OR v_retailer IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'error', 'NO_STORE');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.products WHERE id = p_product) THEN
        RETURN jsonb_build_object('ok', false, 'error', 'NOT_FOUND');
    END IF;

    DELETE FROM public.product_likes WHERE product_id = p_product AND user_id = v_user;
    IF FOUND THEN
        RETURN jsonb_build_object('ok', true, 'liked', false);
    END IF;

    INSERT INTO public.product_likes (product_id, user_id, retailer_id)
    VALUES (p_product, v_user, v_retailer)
    ON CONFLICT DO NOTHING;
    RETURN jsonb_build_object('ok', true, 'liked', true);
END;
$$;

REVOKE ALL ON FUNCTION public.toggle_product_like(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.toggle_product_like(UUID) TO authenticated;

-- ── The wholesaler's report ────────────────────────────────────────────────
-- p_period: 'week' = the last 7 days, 'month' = the last 30, each compared
-- with the period before it. Only the caller's own designs are counted.

CREATE OR REPLACE FUNCTION public.wholesaler_report(p_period TEXT DEFAULT 'week')
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
    v_user  UUID := auth.uid();
    v_len   INTERVAL := CASE WHEN p_period = 'month' THEN INTERVAL '30 days' ELSE INTERVAL '7 days' END;
    v_to    TIMESTAMPTZ := now();
    v_from  TIMESTAMPTZ := now() - v_len;
    v_prev  TIMESTAMPTZ := now() - 2 * v_len;
    v_out   JSONB;
BEGIN
    IF v_user IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'error', 'NOT_AUTHENTICATED');
    END IF;

    WITH mine AS (
        SELECT id, title, COALESCE(processed_image_url, image_url, raw_image_url) AS image
          FROM public.products WHERE wholesaler_id = v_user
    ),
    likes AS (
        SELECT l.product_id, l.retailer_id, l.created_at
          FROM public.product_likes l JOIN mine m ON m.id = l.product_id
         WHERE l.created_at >= v_prev
    ),
    views AS (
        SELECT e.product_id, e.retailer_id, e.created_at
          FROM public.store_events e JOIN mine m ON m.id = e.product_id
         WHERE e.event = 'design.viewed' AND e.created_at >= v_prev
    ),
    ords AS (
        SELECT o.* FROM public.orders o
         WHERE o.wholesaler_id = v_user
           AND (o.created_at >= v_from OR o.accepted_at >= v_from
                OR o.completed_at >= v_from OR o.rejected_at >= v_from
                OR (o.created_at >= v_prev AND o.created_at < v_from))
    ),
    asks AS (
        SELECT c.id, c.retailer_id, msg.created_at
          FROM public.conversations c
          JOIN public.messages msg ON msg.conversation_id = c.id AND msg.sender_type = 'employee'
         WHERE c.wholesaler_id = v_user AND msg.created_at >= v_prev
    ),
    top_liked AS (
        SELECT m.id, m.title, m.image, count(*) AS n
          FROM likes l JOIN mine m ON m.id = l.product_id
         WHERE l.created_at >= v_from
         GROUP BY m.id, m.title, m.image
         ORDER BY n DESC, m.title
         LIMIT 5
    ),
    top_viewed AS (
        SELECT m.id, m.title, m.image, count(*) AS n
          FROM views v JOIN mine m ON m.id = v.product_id
         WHERE v.created_at >= v_from
         GROUP BY m.id, m.title, m.image
         ORDER BY n DESC, m.title
         LIMIT 1
    ),
    reach AS (
        SELECT retailer_id, created_at FROM likes
        UNION ALL SELECT retailer_id, created_at FROM views
        UNION ALL SELECT retailer_id, created_at FROM ords
        UNION ALL SELECT retailer_id, created_at FROM asks
    )
    SELECT jsonb_build_object(
        'ok', true,
        'period', CASE WHEN p_period = 'month' THEN 'month' ELSE 'week' END,
        'from', v_from,
        'to', v_to,
        'likes',       (SELECT count(*) FROM likes WHERE created_at >= v_from),
        'likes_prev',  (SELECT count(*) FROM likes WHERE created_at <  v_from),
        'top_liked',   COALESCE((SELECT jsonb_agg(jsonb_build_object(
                           'product_id', id, 'title', title, 'image', image, 'likes', n))
                           FROM top_liked), '[]'::jsonb),
        'views',       (SELECT count(*) FROM views WHERE created_at >= v_from),
        'views_prev',  (SELECT count(*) FROM views WHERE created_at <  v_from),
        'top_viewed',  (SELECT jsonb_build_object('product_id', id, 'title', title, 'image', image, 'views', n)
                          FROM top_viewed),
        'orders_new',       (SELECT count(*) FROM ords WHERE created_at >= v_from),
        'orders_new_prev',  (SELECT count(*) FROM ords WHERE created_at <  v_from),
        'orders_accepted',  (SELECT count(*) FROM ords WHERE accepted_at  >= v_from),
        'orders_completed', (SELECT count(*) FROM ords WHERE completed_at >= v_from),
        'orders_rejected',  (SELECT count(*) FROM ords WHERE rejected_at  >= v_from),
        'questions',        (SELECT count(*) FROM asks WHERE created_at >= v_from),
        'questions_prev',   (SELECT count(*) FROM asks WHERE created_at <  v_from),
        'conversations',    (SELECT count(DISTINCT id) FROM asks WHERE created_at >= v_from),
        'stores',       (SELECT count(DISTINCT retailer_id) FROM reach WHERE created_at >= v_from AND retailer_id IS NOT NULL),
        'stores_prev',  (SELECT count(DISTINCT retailer_id) FROM reach WHERE created_at <  v_from AND retailer_id IS NOT NULL)
    ) INTO v_out;

    RETURN v_out;
END;
$$;

REVOKE ALL ON FUNCTION public.wholesaler_report(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.wholesaler_report(TEXT) TO authenticated;

COMMIT;
