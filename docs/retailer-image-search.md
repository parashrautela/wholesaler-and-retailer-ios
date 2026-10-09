# Retailer image search — native iOS

In the retailer admin app, open Wishlists → Discover. Tap the photo icon, choose a reference photo and jewellery category, then tap **Search by photo**. No image editing or material/weight form is required. Employees and wholesalers do not receive this control. Search results never select or publish a product; existing add/remove controls remain explicit.

The native app sends one bounded JPEG and category to its own authenticated backend at `/api/retailer/image-search`. The backend requires a verified retailer account, searches published supplier products, and returns ranked product IDs. The app displays only IDs present in its permitted marketplace snapshot. The endpoint is rate limited and responses use no-store. No customer photo is stored or sent to Jev or an external inference provider. Only anonymized comparison measurements go to TypeSafe/Jev.

The backend runs pinned CLIP image encoding locally with ONNX Runtime. Catalogue vectors are computed and cached before queries, refreshed in the background, and reused. Queries encode only the reference photo. The backend shortlists up to 12 candidates using CLIP, then asks Jev to judge each pair from locally computed visual measurements. Only Jev’s similar decisions are shown; uncertain and different are excluded. The app honors this decision instead of applying the old 0.90 CLIP cutoff again. Legacy backend responses retain the old cutoff. Cosine scores and Jev probabilities are not measured accuracy percentages. Category changes, refresh, cancellation, leaving the screen and account changes invalidate stale results. The photo is held in memory and cleared when leaving the screen.

Photos are limited to 10 MB and 50 million source pixels, resized to at most 1024 pixels before upload. An ephemeral URLSession has bounded timeouts. A backend still preparing its index returns a retryable readiness error rather than a false empty result.

## Verification

Run `tests/catalogue-image-search/run.sh` to check the production native transport with a controlled HTTP fixture: image bounds, multipart/category/authentication, permitted-ID filtering, strong cutoff, cancellation and deployment/readiness errors. Build the JewelIndia scheme for iOS Simulator.

Actual backend testing against 362 published catalogue images placed the original reference first (1.0000) and its app-sized JPEG first (0.9914). Warm query computation was about 45 ms locally; this excludes upload, authentication and network latency and is not a production response-time guarantee. Labelled different-angle jewellery pairs are still needed to measure broader retrieval quality.

The backend release must be deployed and its catalogue index ready. An app build/update is required; Git push does not install the update on an iPhone or publish TestFlight. Live signed-in retailer testing remains a distribution check.
