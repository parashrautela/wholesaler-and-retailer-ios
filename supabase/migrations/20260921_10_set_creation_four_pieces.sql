-- Set Creation takes two to four pieces. Slots 3 and 4 are new; the price
-- goes up by the same 80 credits a piece the two-piece price implies.

BEGIN;

ALTER TABLE public.chamak_generations
    ADD COLUMN IF NOT EXISTS source_image_3_url TEXT,
    ADD COLUMN IF NOT EXISTS source_image_4_url TEXT;

INSERT INTO public.credit_prices (feature_key, credits, label, description, sort_order, audience) VALUES
    ('chamak.set_creation_3', 240, 'Set Creation · 3 pieces', 'Three pieces staged as one set', 23, 'all'),
    ('chamak.set_creation_4', 320, 'Set Creation · 4 pieces', 'Four pieces staged as one set', 24, 'all')
ON CONFLICT (feature_key) DO NOTHING;

COMMIT;
