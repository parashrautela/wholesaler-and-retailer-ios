-- Identity documents (Aadhaar, PAN, GST) must not be readable by anyone with
-- a link. Make their buckets private and narrow the old "Public read" policy
-- to business logos, which the apps display publicly. Owners keep "Users can
-- read own docs" / "Users can upload own docs" (own folder only); admins get
-- short-lived signed URLs from the admin-fetch-submission-detail function.

BEGIN;

UPDATE storage.buckets
   SET public = false
 WHERE id IN ('aadhaar-documents', 'pan-documents', 'gst-documents');

DROP POLICY IF EXISTS "Public read" ON storage.objects;

CREATE POLICY "Public read business logos"
    ON storage.objects FOR SELECT
    TO public
    USING (bucket_id = 'business-logos');

COMMIT;
