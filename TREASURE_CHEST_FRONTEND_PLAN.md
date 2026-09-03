# Treasure Chest — Frontend Implementation Plan

**For:** an AI coding agent (or developer) implementing the client side.
**Backend status:** already built and tested. Do not modify it.
**Covers:** iOS app (`wholesaler ios`) and web app (`Jewel-India-Frontend`).

---

# 0. What you need to know before touching anything

## 0.1 What this feature is

Wholesalers have a credit wallet called the **Treasure Chest**. AI actions cost
credits. The backend already:

- holds the ledger (Supabase, five tables, append-only history)
- charges the wholesaler when a Chamak generation starts
- refunds automatically when a generation fails
- grants 100 free credits when a wholesaler's onboarding is verified

**Your job is only the client side:** show the balance, show what things cost,
handle "not enough credits" gracefully, and send two new HTTP headers.

## 0.2 The one thing that will break if you get it wrong

The AI pipeline now **requires an `Authorization` header** on the Chamak
endpoints once metering is switched on. Both the iOS app and the web app
currently send no such header. **If you ship the credit UI without also
shipping the auth headers, every Chamak generation will fail with 401.**

Auth headers are Task 1 on both platforms. Do them first.

## 0.3 Repositories

| Repo | Path | Role |
|---|---|---|
| iOS app | `wholesaler ios` | SwiftUI, iOS 26, Supabase Swift SDK |
| Web app | `Jewel-India-Frontend` | Next.js App Router, JS (not TS), `@supabase/ssr` |
| AI pipeline | `ai-pipeline` | FastAPI. **Already done — do not edit.** |

---

# 1. The backend contract (authoritative)

Everything in this section already exists. Treat it as fixed.

## 1.1 Supabase — reading the wallet

### `credits_wallet()` — RPC, no arguments

Reads `auth.uid()` internally, so it can only ever return the caller's own
wallet. Call it with the normal authenticated client.

```jsonc
{
  "ok": true,
  "available": 90,               // spendable credits right now
  "lifetime_granted": 100,
  "lifetime_spent": 10,
  "lifetime_expired": 0,
  "expiring_soon": 12,           // credits expiring within 7 days
  "next_expiry": "2026-09-22T00:00:00Z",  // nullable
  "low_balance": false,          // available <= threshold
  "low_balance_threshold": 20,
  "recovery_owed": 0
}
```

Returns `{"ok": false, "error": "NOT_AUTHENTICATED"}` if there is no session.

### `credit_prices` — table, read directly

Publicly readable where `is_active`. **The rate card. Never hardcode a price in
client code** — the whole point of this table is that prices change without an
App Store release.

| Column | Type | Notes |
|---|---|---|
| `feature_key` | text (PK) | `chamak.generate`, `chamak.reroll`, … |
| `credits` | int | what it costs |
| `label` | text | display name, e.g. "Chamak Fusion" |
| `description` | text | one line for the rate card |
| `sort_order` | int | display order |
| `is_active` | bool | |

Seeded rows:

| `feature_key` | credits | label |
|---|---:|---|
| `chamak.analyze` | 0 | Chamak Analysis |
| `chamak.generate` | 10 | Chamak Fusion |
| `chamak.generate_custom` | 12 | Chamak Fusion (your photos) |
| `chamak.reroll` | 6 | Try Again |
| `product.upload` | 0 | Product Upload |
| `product.reprocess` | 0 | Reprocess Product |

> ⚠️ `product.*` is 0 **for now**. It will become non-zero later. Write the UI so
> a zero-cost feature shows no cost chip and a non-zero one does — automatically,
> driven by the data. Do not special-case "uploads are free".

### `credit_ledger` — table, read own rows

The transaction history. Ordered `created_at DESC`, paginate it.

| Column | Type | Notes |
|---|---|---|
| `id` | uuid | |
| `delta` | int | **negative** for spend/expiry, **positive** for grant/refund |
| `kind` | text | `grant` \| `debit` \| `refund` \| `expiry` \| `adjustment` |
| `feature_key` | text, nullable | what was bought |
| `reference_type` | text, nullable | `chamak_generation` \| `product` \| `purchase` |
| `reference_id` | text, nullable | join key — use it to show a thumbnail |
| `balance_after` | int | balance immediately after this row |
| `metadata` | jsonb | `{allocations, ai_cost_paise, attempt, reason, …}` |
| `created_at` | timestamptz | |

### `credit_lots` — table, read own rows

Only needed if you show an "expiring soon" breakdown. `credits_remaining`,
`expires_at` (null = never expires), `source`.

### RLS reality

Clients can **only SELECT**. There is no INSERT/UPDATE/DELETE policy on any
credit table for any client role, and the mutating RPCs (`spend_credits`,
`grant_credits`, `refund_credits`) are `service_role`-only. **Do not attempt to
write credits from the client — it will fail, and it is meant to.**

## 1.2 AI pipeline — the Chamak endpoints

Base URL: `AI_PIPELINE_URL` on iOS (`AppConfig.aiPipelineURL`),
`NEXT_PUBLIC_API_URL` on web.

### Request headers — both changed

| Header | Required | Value |
|---|---|---|
| `Authorization` | **Yes** | `Bearer <supabase access token>` |
| `Content-Type` | Yes | `application/json` |
| `Idempotency-Key` | **Yes (see §2.3)** | a UUID generated **per user action** |

Affected endpoints:

- `POST /api/chamak/analyze` — body `{"generation_id": "<uuid>"}`
- `POST /api/chamak/generate` — body `{"generation_id": "<uuid>"}`
- `GET  /api/chamak/{generation_id}` — needs `Authorization` (no body, no idempotency key)

`POST /process` (product upload) is **unchanged** — no auth needed yet. Leave it.

### Response codes you must handle

| Code | Meaning | What the client does |
|---|---|---|
| `202` | Accepted, work queued | proceed as today |
| **`401`** | Missing/expired/invalid token | refresh session; if that fails, send them to sign in |
| **`402`** | **Not enough credits** | **open the top-up sheet — see below** |
| `404` | Generation not found, or not theirs | generic "not found" error |
| `429` | Rate limited | "Too many requests, wait a moment" |
| **`503`** | Credit ledger unreachable | "Couldn't reach your Treasure Chest. Try again." — **retryable** |
| other | pipeline error | existing error handling |

### The 402 body — decode this exactly

```jsonc
{
  "detail": {
    "error": "INSUFFICIENT_CREDITS",
    "message": "You do not have enough credits for this.",
    "required": 10,
    "balance": 4,
    "short_by": 6
  }
}
```

Note `detail` is an **object** here. Every other error returns `detail` as a
**string**. Existing error-parsing code assumes a string — it must handle both
or it will render "unknown error" for the single most important case.

---

# 2. Non-negotiable rules

These are the rules that stop this feature from leaking money or confusing
users. Follow them on both platforms.

### 2.1 Never hardcode a price
Read `credit_prices`. If the fetch fails, hide the cost chip rather than
guessing a number. A wrong price on a button is worse than no price.

### 2.2 The local balance is display-only
The server is the truth. Refetch the wallet:
- when the wallet screen opens
- when a credit-spending flow is entered
- after every successful generation
- after returning from a purchase

Never compute the new balance client-side by subtracting. Show what the server
last told you.

### 2.3 Idempotency keys — get this exactly right

The key identifies **one user intention**, not one HTTP request.

| Event | Key behaviour |
|---|---|
| User taps "Fuse" | **generate a new UUID**, store it |
| That request fails and is retried (network error, 503, user taps retry on the same screen) | **reuse the stored UUID** |
| Request succeeds | **clear the stored UUID** |
| User taps "Try Again" / re-roll | **generate a new UUID** |

Reusing a key means the server returns the original result without charging
again. Generating a new key means a genuine new charge. Get this backwards and
you either double-charge people or give away free re-rolls.

> The iOS `regenerate` path reuses the **same** `chamak_generations` row, which
> is exactly why the key must come from the client. The server prices a re-roll
> at 6 credits automatically by checking the ledger — you do not send a price or
> a feature key.

### 2.4 A 402 must not mark the generation failed
Existing code calls `updateStatus(.failed)` on any non-2xx. A 402 means "you
couldn't afford it yet" — the row must stay in `awaiting_input` so they can top
up and continue. **Skip the failure write for 402.**

### 2.5 Preserve flow state through the top-up
When the insufficient-credits sheet appears, the wholesaler's slider values,
note text and selected designs **must survive**. They top up and land back
exactly where they were. Losing their inputs at the moment you ask for money is
the worst possible time to lose them.

### 2.6 Don't invent a purchase flow on iOS
Apple forbids selling credits in-app through anything but Apple's own IAP.
Until IAP is built (a later phase), the iOS top-up CTA says
**"Contact your account manager to add credits"** — no link, no web URL, no
mention of a website. This is an App Store rejection risk, not a preference.

### 2.7 Never charge twice for something already generated
Viewing, re-downloading, or opening the gallery is always free. No credit call.

---

# 3. iOS implementation

**Repo:** `wholesaler ios` · **Target:** `JewelIndia/Sources/`

## 3.0 Conventions to match

Read these before writing any view — the app has a strict design system ported
from the web app, and new screens must look native to it.

| Thing | Where | Use |
|---|---|---|
| Colours | `Design/Palette.swift` | `Palette.cream` `#F5F2EB`, `.taupe` `#E6DFD3`, `.dark` `#111111`, `.muted` `#8C857B`, `.border` `#D9D0C5`, `.statusPending` `#F59E0B` (amber — use for low-balance state) |
| Fonts | `Design/Typography.swift` | `.cirka(34)` section headings · `.manrope(13, weight:)` · `.gilroy(14, weight: .medium)` body · `.sfPro(13)` small |
| Spacing | `Design/Layout.swift` | `Spacing.base` 16, `.lg` 20, `.xl` 24, `.xxl` 32 · `Radius.xl` 12 |
| Press effect | `WholesalerHomeView.swift` | `PressableButtonStyle()` — already defined, reuse it |
| State | throughout | `@Observable` + `@MainActor` classes, **not** `ObservableObject` |

Existing card components to match visually: `StatCard`, `ChamakCard`,
`CategoryCard` (all in `WholesalerHomeView.swift`).

---

## TASK i1 — Send auth + idempotency headers (do this first)

**File:** `JewelIndia/Sources/Networking/ChamakAPI.swift`

### Add a helper

```swift
/// Attaches the caller's Supabase session to a pipeline request.
///
/// The pipeline verifies this token and refuses to spend credits without it.
/// `requireLiveSession` already proves a session exists for the RLS writes —
/// this is the same session, now also needed by the HTTP hop.
private static func authorized(
    _ url: URL,
    idempotencyKey: String? = nil
) async throws -> URLRequest {
    var request = URLRequest(url: url)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    guard let session = try? await SupabaseManager.client.auth.session else {
        throw ChamakError(message: """
            Your session isn't active on this device. \
            Please sign out and sign in again.
            """)
    }
    request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

    if let idempotencyKey {
        request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
    }
    return request
}
```

### Update three call sites

1. `triggerStage1Analysis(generationID:)` — add `idempotencyKey` parameter, use `authorized(...)`
2. `submitFormAndGenerate(...)` — add `idempotencyKey` parameter, use `authorized(...)`
3. `fetchGeneration(generationID:)` — if it hits `GET /api/chamak/{id}`, add the header

### Add a typed error for 402

```swift
struct InsufficientCreditsError: LocalizedError {
    let required: Int
    let balance: Int
    let shortBy: Int
    var errorDescription: String? { "You need \(shortBy) more credits." }
}
```

### Rewrite the error branch

The current code does this, which breaks on 402 because `detail` is an object:

```swift
let detail = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
let message = (detail?["detail"] as? String) ?? ...
```

Replace with logic that:
1. checks `http.statusCode == 402` → parse `detail` **as a dictionary**, throw `InsufficientCreditsError`, and **do not** call `updateStatus(.failed)`
2. checks `401` → session error message
3. otherwise → existing behaviour, but tolerate `detail` being either a string or an object

**Acceptance:** with metering on and a funded wallet, a fusion still works. With an
empty wallet, `InsufficientCreditsError` is thrown and the generation row stays
`awaiting_input`, not `failed`.

---

## TASK i2 — Credits models + API layer

**New file:** `JewelIndia/Sources/Networking/CreditsAPI.swift`

```swift
enum CreditsAPI {
    static func fetchWallet() async throws -> CreditWallet          // rpc("credits_wallet")
    static func fetchRateCard() async throws -> [CreditPrice]       // credit_prices, is_active, sort_order
    static func fetchLedger(limit: Int, before: Date?) async throws -> [CreditLedgerEntry]
}
```

- Wallet: `try await db.rpc("credits_wallet").execute().value`
- Rate card: `db.from("credit_prices").select().eq("is_active", value: true).order("sort_order")`
- Ledger: `db.from("credit_ledger").select().order("created_at", ascending: false).limit(limit)`
  — RLS scopes all three to the signed-in wholesaler automatically; do **not** add a `wholesaler_id` filter.

**New file:** `JewelIndia/Sources/Features/Wholesaler/TreasureChest/TreasureChestModels.swift`

`CreditWallet`, `CreditPrice`, `CreditLedgerEntry` — `Decodable, Sendable`, snake_case
`CodingKeys` matching §1.1. Follow the style of `UploadUsage` in
`WholesalerModels.swift`.

Add to `CreditLedgerEntry` a computed `displayTitle` that turns
`(kind, feature_key)` into human text:

| kind | text |
|---|---|
| `debit` | the price row's `label` (e.g. "Chamak Fusion") |
| `grant` + source `welcome` | "Welcome gift" |
| `grant` + purchase | "Credits purchased" |
| `refund` | "Refunded — generation failed" |
| `expiry` | "Credits expired" |
| `adjustment` | "Adjustment" |

**Acceptance:** all three decode against the live schema without a decoding error.

---

## TASK i3 — Shared wallet state

**New file:** `JewelIndia/Sources/Features/Wholesaler/TreasureChest/CreditStore.swift`

```swift
@MainActor @Observable
final class CreditStore {
    private(set) var wallet: CreditWallet?
    private(set) var rateCard: [String: CreditPrice] = [:]   // keyed by feature_key
    private(set) var isLoading = false
    private(set) var lastRefreshed: Date?

    func refresh() async
    func cost(for featureKey: String) -> Int?   // nil when unknown → hide the chip
}
```

Inject once at the shell level so the pill, the home card and the Chamak flow
all read the same instance:

```swift
// WholesalerShell.swift
@State private var credits = CreditStore()
// on TabView:
.environment(credits)
```

**Acceptance:** exactly one `CreditStore` exists per session; balance is
identical everywhere it is displayed.

---

## TASK i4 — Balance pill in the toolbar

**New file:** `.../TreasureChest/CreditBalancePill.swift`

Placement: `Navigation/WholesalerShell.swift`, inside `profileMenu`'s
`ToolbarItemGroup(placement: .topBarTrailing)`, **before** the existing profile
menu button so the logo stays rightmost.

Design:
- capsule, `Palette.cream` fill, 1px `Palette.border` stroke
- small coin/chest SF Symbol + the number in `.manrope(13, weight: .semibold)`
- when `wallet.low_balance` is true: `Palette.statusPending` border and text
- tap → opens the Treasure Chest screen
- while `wallet == nil`: render a fixed-width redacted placeholder, **never** "0"
  (showing 0 before load reads as "you have no credits")

**Acceptance:** visible on all five wholesaler tabs; turns amber below the
threshold; never flashes 0 on launch.

---

## TASK i5 — Home screen card

**File:** `JewelIndia/Sources/Features/Wholesaler/WholesalerHomeView.swift`
**New file:** `.../TreasureChest/TreasureChestCard.swift`

Current order: `hero` → `insights` → `catalogueSection`.
New order: `hero` → **`treasureChestCard`** → `insights` → `catalogueSection`.

Do **not** make it a fifth `StatCard`. It is a wallet, not a KPI, and must read
differently:

- full-width card, `Radius.xl` (12), 1px `Palette.border`
- warm gradient ground (cream → a faint gold tint), distinct from the white KPI cards
- balance in `.cirka(34)`, label "Credits available" in `.gilroy(14, weight: .medium)` `Palette.muted`
- when `expiring_soon > 0`: a thin amber line — "12 credits expire in 5 days"
- trailing **"Top Up"** button, `PressableButtonStyle()`
- whole card tappable → Treasure Chest screen

Add `.treasureChest` to `WholesalerShell.HomeRoute` and a
`navigationDestination` case, matching how `.uploadHistory` is wired.

**Acceptance:** appears between hero and Insights; visually distinct from
`StatCard`; both card tap and Top Up push the wallet screen.

---

## TASK i6 — The Treasure Chest screen

**New files:**
- `.../TreasureChest/TreasureChestView.swift`
- `.../TreasureChest/TransactionHistoryView.swift`

Sections, top to bottom:

1. **Balance hero** — `available` in `.cirka(48)`, "credits available" beneath.
2. **Three stats row** — Available · Used (`lifetime_spent`) · Expired
   (`lifetime_expired`). Reuse `StatCard`'s visual language at smaller scale.
3. **Expiring notice** — only when `expiring_soon > 0`.
4. **Top Up button** — see rule §2.6. Opens a sheet that lists the packs
   (hardcoded display only, for now) and ends with
   "Contact your account manager to add credits." **No web link.**
5. **"What things cost"** — the rate card from `CreditStore`, rows with `label`,
   `description`, and `credits`. **Skip rows where `credits == 0`** — a list
   saying "Product Upload — 0 credits" is noise.
6. **Recent activity** — last 20 ledger entries, "See all" → `TransactionHistoryView`.

`TransactionHistoryView`: grouped by day, `+`/`−` with colour (green for
positive, `Palette.dark` for negative), `displayTitle`, time, and
`balance_after` in small muted text. Filter chips: All / Spent / Added /
Expired. Paginate at 50 with infinite scroll.

Empty state: "No activity yet. Your credits will appear here as you use them."

**Acceptance:** pull-to-refresh works; history paginates past 50; a failed
generation shows both the original −10 and the +10 refund.

---

## TASK i7 — Wire credits into the Chamak flow

**Files:** `Chamak/ChamakViewModel.swift`, `ChamakSliderFormView.swift`,
`ChamakResultView.swift`, `ChamakFlowCoordinator.swift`, `WholesalerHomeView.swift` (`ChamakCard`)

### 7a. Delete the old quota system

`ChamakAPI.checkQuota` calls `WholesalerAPI.fetchUploadUsage`, which hits
`GET /api/upload-usage` — **a route that does not exist on the pipeline.** It
always fails and falls back to "unlimited". It is dead code pretending to be a
limit.

Remove: `ChamakAPI.checkQuota`, `ChamakViewModel.remainingQuota`,
`.totalQuota`, `.showQuotaAlert`, and the quota alert in the views.
Replace with `CreditStore` + the 402 path.

### 7b. Idempotency key on the view model

```swift
/// Identifies one user intention, not one request — see the plan, §2.3.
/// Kept across retries so a retry cannot double-charge; regenerated when the
/// wholesaler deliberately asks for a new result.
private var pendingGenerateKey: String?
```

- `submitFormAndGenerate`: `if pendingGenerateKey == nil { pendingGenerateKey = UUID().uuidString }`
- on success: `pendingGenerateKey = nil`
- on failure: **leave it set** (a retry reuses it)
- `regenerate`: `pendingGenerateKey = UUID().uuidString` — always new

### 7c. Cost chips

- `ChamakCard` on home: small chip showing `credits(for: "chamak.generate")`, hidden if nil or 0
- `ChamakSliderFormView` primary button: **"Fuse · 10 credits"** — one tap, cost stated.
  **Do not add a confirmation dialog**; a dialog on every generation is exhausting.
- `ChamakResultView` re-roll button: **"Try Again · 6 credits"** (`chamak.reroll`)

### 7d. Handle 402

Catch `InsufficientCreditsError` in `submitFormAndGenerate` and `regenerate`:

```swift
step = .sliderForm          // stay put — do NOT go to .failed
insufficientCredits = error // drives the sheet
```

### 7e. Insufficient credits sheet

**New file:** `.../TreasureChest/InsufficientCreditsSheet.swift`

A **sheet**, not an alert (`.presentationDetents([.medium])`):

- "You need **6 more credits** to fuse this design."
- current balance vs required
- pack list (display only) + "Contact your account manager to add credits"
- secondary "Close" → returns to the slider form with **all inputs intact**

**Acceptance:** with an empty wallet, tapping Fuse opens the sheet; closing it
returns to the form with slider values and note text unchanged; no generation
row is marked failed.

### 7f. Post-success feedback

After a successful generation, refresh the wallet and show a brief toast:
**"−10 credits · 90 left"**. Non-blocking, auto-dismissing.

---

## TASK i8 — Low balance banner

**File:** `WholesalerHomeView.swift`

When `wallet.low_balance` is true, show a dismissible banner above the Treasure
Chest card: amber, "Running low — 18 credits left, about 1 more fusion."

Compute "about N more fusions" as `available / cost(for: "chamak.generate")`.

The backend already prevents nagging: `low_balance_notified_at` is cleared when
the balance rises back above the threshold. Client side, just don't re-show it
in the same session after dismissal.

> **Push notifications are out of scope.** The app has no APNs setup —
> no entitlements file, no capability, no push key. Do not add one. In-app
> banner only.

---

# 4. Web implementation

**Repo:** `Jewel-India-Frontend` · Next.js App Router, plain JS, `@supabase/ssr`

## TASK w1 — Auth + idempotency headers (do this first)

**File:** `lib/api/chamak.js`

Both `triggerAnalysis` and `triggerGenerate` currently send no auth header.

```js
import { createClient } from "@/lib/supabase/client";

async function authHeaders(idempotencyKey) {
  const supabase = createClient();
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) throw new Error("Your session has expired. Please sign in again.");

  const headers = {
    "Content-Type": "application/json",
    Authorization: `Bearer ${session.access_token}`,
  };
  if (idempotencyKey) headers["Idempotency-Key"] = idempotencyKey;
  return headers;
}
```

Add an `idempotencyKey` argument to both functions and pass it through.

**Also fix the error parsing.** Current code:

```js
const msg = body.detail || body.message || `... (${res.status})`;
```

On a 402 `body.detail` is an **object**, so this renders `[object Object]`.
Handle it:

```js
if (res.status === 402 && body.detail?.error === "INSUFFICIENT_CREDITS") {
  const err = new Error(body.detail.message);
  err.status = 402;
  err.insufficientCredits = body.detail;   // { required, balance, short_by }
  throw err;
}
const detail = typeof body.detail === "string" ? body.detail : body.detail?.message;
```

**Acceptance:** a funded account still generates; an empty one throws an error
carrying `insufficientCredits`.

---

## TASK w2 — Credits data layer

**New file:** `lib/supabase/credits-queries.js`

Mirror the style of `lib/supabase/chamak-queries.js`:

```js
export async function fetchWallet()                    // supabase.rpc("credits_wallet")
export async function fetchRateCard()                  // credit_prices, is_active, order sort_order
export async function fetchLedger({ limit = 50, offset = 0 })
```

**New file:** `context/CreditsContext.jsx` (matching the existing `context/` pattern)
— provider exposing `{ wallet, rateCard, refresh, costOf(featureKey) }`.

Mount it in the wholesaler dashboard layout so the header badge and the Chamak
page share one source.

---

## TASK w3 — Wallet UI

| File | What |
|---|---|
| `components/wholesaler/TreasureChestCard.jsx` | new — balance card for the dashboard overview |
| `components/wholesaler/CreditBadge.jsx` | new — balance pill for the header/sidebar |
| `app/dashboard/wholesaler/treasure-chest/page.jsx` | new — full wallet page |
| `components/wholesaler/OverviewSection.jsx` | edit — insert the card above the KPI grid |
| `components/wholesaler/Sidebar.jsx` | edit — add a "Treasure Chest" nav entry |

Same content as iOS Task i6: balance hero, three stats, expiring notice, rate
card (skipping zero-cost rows), transaction history with filters and pagination.

Match the existing wholesaler dashboard styling (Tailwind, the `celestique`
palette tokens in `app/globals.css`).

**Difference from iOS:** the web **may** show a real "Buy Credits" button, because
Apple's rules do not apply here. Wire it to Task w4 when that ships; until then
point it at the same "contact your account manager" copy.

---

## TASK w4 — Buy credits with Razorpay *(later phase — do not build yet)*

Listed so it is not designed out of the architecture. Requires backend work that
does not exist yet:

1. `app/api/credits/create-order/route.js` — server-side Razorpay Order with
   `notes: { wholesaler_id, pack_key, credits }`
2. `app/api/credits/webhook/route.js` — verifies `X-Razorpay-Signature` (HMAC-SHA256,
   webhook secret), dedupes on `provider_txn_id`, calls `grant_credits` with the
   service-role client
3. Checkout page + GSTIN/state capture for the tax invoice

**Do not implement this from this document.** The webhook is security-critical
and needs its own spec.

---

## TASK w5 — Chamak flow integration

**Files:** `components/wholesaler/chamak/ChamakPage.jsx`,
`ChamakSliderForm.jsx`, `ChamakResultStep.jsx`

Same as iOS Task i7:
- idempotency key per user action (`crypto.randomUUID()`), stored in component
  state, reused on retry, regenerated on re-roll
- cost on the buttons, read from the rate card
- catch `err.insufficientCredits` → modal, **preserve the form state**
- refresh the wallet after a successful generation

---

# 5. How to verify

## 5.1 Prerequisites

Ask the repo owner to confirm before testing:
1. Migration `004_credits_treasure_chest.sql` has been run
2. `SUPABASE_JWT_SECRET` is set on the pipeline
3. `CREDITS_ENABLED` — **its current value**, because it changes expected behaviour

## 5.2 With `CREDITS_ENABLED=false`

Everything must work exactly as before. Wallet screens show real balances (the
welcome grants are real), but no generation is ever charged and no 402 appears.
This is the safe state to build against.

## 5.3 With `CREDITS_ENABLED=true`

| Scenario | Expected |
|---|---|
| Fuse with enough credits | 202, balance drops by 10, ledger shows a `debit` |
| Fuse with 4 credits | **402**, sheet opens showing "6 more", **no** row marked `failed`, form state intact |
| Tap Fuse twice fast | charged **once** (same idempotency key) |
| Fuse, then Try Again | **two** charges: 10 then 6 |
| Generation fails server-side | refund appears in history within seconds |
| Sign out, sign in, reopen wallet | same balance |
| Airplane mode | last known balance with an "as of" time; spend actions blocked, not silently attempted |

## 5.4 Manual backend checks

```sql
-- someone's wallet
select * from credit_accounts where wholesaler_id = '<uuid>';

-- their history, newest first
select created_at, kind, delta, feature_key, balance_after
from credit_ledger where account_id = '<uuid>'
order by created_at desc limit 20;

-- prove no double-charge: this must return zero rows
select idempotency_key, count(*) from credit_ledger
group by idempotency_key having count(*) > 1;
```

---

# 6. Order of work

Ship in this order. Steps 1–2 are safe to deploy any time; step 3 depends on the
backend flag being flipped, which is the repo owner's call.

| # | Work | Why this order |
|---|---|---|
| 1 | **i1 + w1** — auth & idempotency headers | Everything else 401s without them |
| 2 | **i2, i3, i4, i5, i6** and **w2, w3** — read-only wallet UI | Safe: shows real balances, charges nothing |
| 3 | **i7, i8, w5** — metering, 402 handling, cost chips | Only meaningful once `CREDITS_ENABLED=true` |
| 4 | **w4** — Razorpay purchase | Separate spec, security-critical |

---

# 7. Guardrails — do NOT do these

1. **Do not modify anything in `ai-pipeline/`.** It is built and tested.
2. **Do not write to any `credit_*` table from a client.** It will fail by design.
3. **Do not hardcode credit prices.** Read `credit_prices`.
4. **Do not add a purchase link, button, or web URL to the iOS app.** App Store rejection risk (§2.6).
5. **Do not add push notification capability.** Explicitly out of scope (Task i8).
6. **Do not mark a generation `failed` on a 402.** It stays `awaiting_input`.
7. **Do not compute balances client-side.** Refetch from the server.
8. **Do not reuse an idempotency key across a deliberate re-roll** — that gives away free generations.
9. **Do not generate a new idempotency key on a retry** — that double-charges.
10. **Do not keep `ChamakAPI.checkQuota`** or `fetchUploadUsage` for Chamak. The endpoint it calls does not exist.

---

# 8. Open questions to raise, not guess

If you hit any of these, ask rather than deciding:

1. **Is `CREDITS_ENABLED` currently true or false?** It changes what "correct" looks like.
2. **Pack prices and names for the top-up sheet** — the display-only list needs confirmed numbers.
3. **`product.upload` pricing** — currently 0 and expected to change. Build the UI data-driven so it needs no code change when it does.
4. **`chamak.generate_custom` (12 credits)** — the backend currently charges plain
   `chamak.generate` for every fusion; nothing yet distinguishes custom-photo runs.
   If that distinction is wanted, it needs a backend change first. **Do not try
   to send a feature key from the client** — the server chooses the price deliberately.
