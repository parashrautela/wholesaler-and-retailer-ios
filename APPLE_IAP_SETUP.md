# App Store credit purchases

The iOS app now uses StoreKit 2 for credit top-ups. The old Razorpay top-up
screen remains only for debug previews. The release onboarding flow already
skips its old Razorpay fee screen.

## Custom credit amounts

The standard StoreKit products below have fixed quantities and App Store prices.
Do not show a free-form credit field until the amount can be fulfilled by an
approved Apple purchase with the exact displayed price. A 5,000-credit option
is the standard Starter pack. Truly arbitrary quantities and prices would
require Apple Advanced Commerce API access and a separate implementation;
Apple grants that access per app.

## App Store Connect work

1. In **Business → Agreements**, the Account Holder must accept the Paid Apps
   Agreement and complete the required banking and tax details.
2. Open **Apps → JewelIndia → Monetization → In-App Purchases**. Create four
   **Consumable** products with these exact Product IDs and quantities:

   | Reference name | Product ID | Credits |
   | --- | --- | ---: |
   | Starter Credits | `com.jewelindia.credits.starter` | 5,000 |
   | Popular Credits | `com.jewelindia.credits.popular` | 10,000 |
   | Pro Credits | `com.jewelindia.credits.pro` | 25,000 |
   | Bulk Credits | `com.jewelindia.credits.bulk` | 50,000 |

   Choose each product's App Store price, localization, availability, and
   review screenshot. The iOS screen displays Apple's localized price. Do not
   change the credit amounts without updating the server product table and
   App Store product descriptions together.
3. In **App Store Server Notifications**, configure **Version 2** with this
   production URL:

   `https://ljxgwiuvdpuarvdszjts.supabase.co/functions/v1/apple-iap-notifications`

   Use the same URL for sandbox notifications if App Store Connect asks for
   one. The endpoint verifies Apple's signed payload before changing any
   credits.
4. Submit the consumables with the next iOS app version. Apple's first
   consumable purchase must be reviewed with a new app version.

## Backend release order

1. Apply `supabase/migrations/20260926_01_apple_iap_credits.sql` to the same
   Supabase project used by the app. It creates the product mapping and the
   service-role-only purchase and refund functions.
2. Deploy `apple-iap` and `apple-iap-notifications` Supabase Edge Functions.
   The former requires an authenticated user token and verifies Apple's
   signed StoreKit transaction. The latter accepts only Apple's verified
   notification payloads. Their `verify_jwt = false` gateway settings are in
   `supabase/config.toml` because each handler performs its own validation.
3. Upload an iOS build containing this code. Do not offer the products to
   customers until the backend functions are deployed and a sandbox purchase
   has credited the correct account exactly once.

## Purchase safety

- StoreKit uses the signed-in Supabase user ID as `appAccountToken`. The server
  checks that token before granting credits.
- The server verifies Apple's JWS certificate chain and bundle ID, then records
  the transaction and credit grant atomically. Replayed transaction IDs cannot
  grant twice.
- Purchased credits are granted with no expiry. The app finishes a StoreKit
  transaction only after the backend confirms the grant. Unfinished purchases
  are retried after sign-in and from the top-up screen.
- App Store refund notifications remove unused credits and record any already
  spent portion as `recovery_owed`.
