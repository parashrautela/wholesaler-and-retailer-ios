-- Retailer monetisation, step 3: Customer Wishlist.
--
-- A store keeps a list of its customers; each customer has one or more
-- boards (mood boards); each board holds designs from the marketplace.
-- `retailer_selections` is untouched — that is the store's own shortlist,
-- which staff browse as their catalogue.
--
-- Both the store owner and its active staff work with customers on the shop
-- floor, so every policy goes through my_retailer_id().

BEGIN;

-- The store the caller belongs to: their own if they are a retailer,
-- otherwise the one that employs them. SECURITY DEFINER so the policies
-- below don't recurse through retailers/employees RLS.
CREATE OR REPLACE FUNCTION public.my_retailer_id()
RETURNS UUID
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
    SELECT COALESCE(
        (SELECT id FROM public.retailers WHERE user_id = auth.uid() LIMIT 1),
        (SELECT retailer_id FROM public.employees
          WHERE auth_user_id = auth.uid() AND status = 'active' LIMIT 1)
    );
$$;

REVOKE ALL ON FUNCTION public.my_retailer_id() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.my_retailer_id() TO authenticated;

-- ── Customers ──────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.retailer_customers (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    retailer_id UUID NOT NULL DEFAULT public.my_retailer_id()
                REFERENCES public.retailers(id) ON DELETE CASCADE,
    name        TEXT NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 120),
    phone       TEXT CHECK (phone IS NULL OR length(phone) <= 20),
    note        TEXT CHECK (note IS NULL OR length(note) <= 1000),
    created_by  UUID DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_retailer_customers_retailer
    ON public.retailer_customers (retailer_id, created_at DESC);

-- ── Boards ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.customer_boards (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID NOT NULL REFERENCES public.retailer_customers(id) ON DELETE CASCADE,
    retailer_id UUID NOT NULL DEFAULT public.my_retailer_id()
                REFERENCES public.retailers(id) ON DELETE CASCADE,
    title       TEXT NOT NULL CHECK (length(btrim(title)) BETWEEN 1 AND 80),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_customer_boards_customer
    ON public.customer_boards (customer_id, created_at);

-- ── Designs on a board ─────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.customer_board_items (
    board_id    UUID NOT NULL REFERENCES public.customer_boards(id) ON DELETE CASCADE,
    product_id  UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    retailer_id UUID NOT NULL DEFAULT public.my_retailer_id()
                REFERENCES public.retailers(id) ON DELETE CASCADE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (board_id, product_id)
);

-- ── RLS: a store sees and edits only its own rows ──────────────────────────

ALTER TABLE public.retailer_customers   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_boards      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_board_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "store manages its customers" ON public.retailer_customers;
CREATE POLICY "store manages its customers" ON public.retailer_customers
    FOR ALL TO authenticated
    USING (retailer_id = public.my_retailer_id())
    WITH CHECK (retailer_id = public.my_retailer_id());

-- A board must also belong to a customer of the same store, or a guessed
-- customer id could be used to hang a board off another store's customer.
DROP POLICY IF EXISTS "store manages its boards" ON public.customer_boards;
CREATE POLICY "store manages its boards" ON public.customer_boards
    FOR ALL TO authenticated
    USING (retailer_id = public.my_retailer_id())
    WITH CHECK (
        retailer_id = public.my_retailer_id()
        AND EXISTS (SELECT 1 FROM public.retailer_customers c
                     WHERE c.id = customer_id AND c.retailer_id = public.my_retailer_id())
    );

DROP POLICY IF EXISTS "store manages its board items" ON public.customer_board_items;
CREATE POLICY "store manages its board items" ON public.customer_board_items
    FOR ALL TO authenticated
    USING (retailer_id = public.my_retailer_id())
    WITH CHECK (
        retailer_id = public.my_retailer_id()
        AND EXISTS (SELECT 1 FROM public.customer_boards b
                     WHERE b.id = board_id AND b.retailer_id = public.my_retailer_id())
    );

-- ── Every customer starts with one board ───────────────────────────────────

CREATE OR REPLACE FUNCTION public.customer_default_board()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
    INSERT INTO public.customer_boards (customer_id, retailer_id, title)
    VALUES (NEW.id, NEW.retailer_id, 'Wishlist');
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_customer_default_board ON public.retailer_customers;
CREATE TRIGGER trg_customer_default_board
    AFTER INSERT ON public.retailer_customers
    FOR EACH ROW EXECUTE FUNCTION public.customer_default_board();

COMMIT;
