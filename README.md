# Jewel India iOS

Open `JewelIndia.xcodeproj` and run the `JewelIndia` scheme. Build configuration comes from `Config.xcconfig`; `SITE_URL` must point to the deployed Next.js app that serves the invitation and auth APIs. Supabase URL/anon key belong to the same shared project. Never put a service-role credential in this app.

## Invitation flow

Home and Orders inject the shared observable `CreditStore` into `InviteRetailerSheet` with `.environment(credits)`. Nested invitation history receives that same store. The Orders debug preview supplies its own store.

The “How it works” guide appears on first opening, including when invitation settings cannot load. “Don’t show me again” starts selected, remains toggleable, and is saved per account after the backend accepts the preference. A local account-scoped cache preserves that accepted preference during a later API outage. Generation waits for real server settings and only happens on the explicit button; no device-generated codes or fabricated balances are used.

If `/api/referral/manage` returns HTML 404/405, the app now explains that the invitation service needs an update. That is a server deployment problem; rebuilding Xcode alone cannot fix it. As audited on 3 October 2026, the configured production API route and new database functions are missing. Follow [the shared release handoff](../plans/invitation-referrals-release.md) and [the web README](../Jewel-India-Frontend/README.md) before releasing this flow.

API contract: authenticated GET/POST/DELETE `/api/referral/manage`, POST `/api/referral/generate`, plus existing validation/claim. Code generation reserves only `gift - 1000` from eligible balance, persists a per-account retry key, and refreshes the wallet. Admin verification later settles the gift and reward once.

Purchased-credit preservation (migration 018) keeps original paid lot/receipt links and units, removes expiry through an audited trusted operation, and shows them in the bonus balance. Gifts and referral bonuses also do not expire.

## Local verification

```sh
xcodebuild -project JewelIndia.xcodeproj -scheme JewelIndia -sdk iphonesimulator -configuration Debug -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO build
```

Debug preview arguments: `-JewelPeek invite-card`, `invite-guide`, `invite-gift`, and `wholesaler` for the real Home entry point. Visual previews do not prove a live signed-in API or credit settlement. Before release, test a real verified wholesaler generating a code, retailer onboarding, and approval in both admin clients against the deployed backend.
