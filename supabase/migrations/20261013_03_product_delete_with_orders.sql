-- Deleting a design that has orders hit the orders_product_id_fkey constraint
-- and the apps showed the raw database error. Orders keep no copy of the
-- design, so it must stay; refuse the delete up front with a message the apps
-- can show as-is (they display the error text), pointing at the publish
-- toggle that hides a design from retailers instead.

BEGIN;

CREATE OR REPLACE FUNCTION public.products_block_delete_with_orders()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM public.orders WHERE product_id = OLD.id) THEN
        RAISE EXCEPTION 'This design has orders, so it can''t be deleted. To hide it from retailers, open the design and turn off "Publish to Retailer".'
            USING ERRCODE = 'P0001';
    END IF;
    RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS products_block_delete_with_orders ON public.products;
CREATE TRIGGER products_block_delete_with_orders
    BEFORE DELETE ON public.products
    FOR EACH ROW EXECUTE FUNCTION public.products_block_delete_with_orders();

COMMIT;
