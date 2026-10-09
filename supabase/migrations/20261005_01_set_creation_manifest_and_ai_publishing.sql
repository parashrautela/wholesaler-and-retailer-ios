-- Set Creation source manifest & AI-only product publishing fields and constraints
BEGIN;

-- 1. Chamak Generations: add set_source_manifest to track server-validated pieces
ALTER TABLE public.chamak_generations
    ADD COLUMN IF NOT EXISTS set_source_manifest JSONB;

-- 2. Products: add AI processing provenance and publication verification
ALTER TABLE public.products
    ADD COLUMN IF NOT EXISTS ai_processing_state TEXT NOT NULL DEFAULT 'none' CHECK (ai_processing_state IN ('none', 'pending', 'ready', 'failed')),
    ADD COLUMN IF NOT EXISTS ai_processing_run_id UUID,
    ADD COLUMN IF NOT EXISTS ai_verified_output_urls TEXT[] NOT NULL DEFAULT '{}',
    ADD COLUMN IF NOT EXISTS ai_completed_at TIMESTAMPTZ;

-- Change default of is_published to false
ALTER TABLE public.products
    ALTER COLUMN is_published SET DEFAULT false;

-- 3. Backfill existing products with generated images or processed images so legitimate existing AI products remain valid
UPDATE public.products
   SET ai_processing_state = 'ready',
       ai_verified_output_urls = generated_image_urls,
       ai_completed_at = COALESCE(created_at, now())
 WHERE ai_processing_state = 'none'
   AND generated_image_urls IS NOT NULL
   AND cardinality(generated_image_urls) > 0;

UPDATE public.products
   SET ai_processing_state = 'ready',
       ai_verified_output_urls = ARRAY[processed_image_url],
       ai_completed_at = COALESCE(created_at, now())
 WHERE ai_processing_state = 'none'
   AND (generated_image_urls IS NULL OR cardinality(generated_image_urls) = 0)
   AND processed_image_url IS NOT NULL
   AND processed_image_url <> '';

-- Ensure any existing published products with images are marked verified so adding the constraint does not fail
UPDATE public.products
   SET ai_processing_state = 'ready',
       ai_verified_output_urls = CASE
           WHEN generated_image_urls IS NOT NULL AND cardinality(generated_image_urls) > 0 THEN generated_image_urls
           WHEN processed_image_url IS NOT NULL AND processed_image_url <> '' THEN ARRAY[processed_image_url]
           WHEN image_url IS NOT NULL AND image_url <> '' THEN ARRAY[image_url]
           ELSE '{}'
       END,
       ai_completed_at = COALESCE(created_at, now())
 WHERE is_published = true
   AND (ai_processing_state = 'none' OR cardinality(ai_verified_output_urls) = 0)
   AND (
       (generated_image_urls IS NOT NULL AND cardinality(generated_image_urls) > 0)
       OR (processed_image_url IS NOT NULL AND processed_image_url <> '')
       OR (image_url IS NOT NULL AND image_url <> '')
   );

-- 4. Publication invariant: only verified AI outputs can be published
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'products_ai_publication_check'
    ) THEN
        ALTER TABLE public.products
            ADD CONSTRAINT products_ai_publication_check
            CHECK (
                NOT is_published
                OR (ai_processing_state = 'ready' AND cardinality(ai_verified_output_urls) > 0)
            );
    END IF;
END $$;

COMMIT;
