# Treasure Chest — Credits Wallet & Monetisation Research

Status: **research / design only. Nothing implemented.**
Scope: wholesaler iOS app + Supabase + the external AI pipeline service.

---

## 0. What we're actually building

A **prepaid credit wallet** ("Treasure Chest") that becomes the single meter for
every AI action on the platform. Three jobs, in order of difficulty:

1. **Ledger** — an auditable, tamper-proof record of every credit in and out. (hard, backend)
2. **Meter** — every premium flow debits before it runs, refunds when it fails. (medium, cross-cutting)
3. **Store** — wholesalers buy more. (easy code, hard business/compliance)

Most teams build 3 → 2 → 1 and end up with a wallet that can be cheated and
can't be audited. We should build 1 → 2 → 3.

---

## 1. Where we are today (verified against the code, not assumed)

| Fact | Evidence | Why it matters |
|---|---|---|
| A quota system **already exists** — daily upload limit | `WholesalerAPI.fetchUploadUsage` → `GET {AI_PIPELINE}/api/upload-usage` returning `{used, limit, resetsAt}`, `429` on exceed | Credits are an *upgrade* to something live, not a new concept for users. Don't throw it away — it becomes the free tier. |
| Chamak piggybacks on that same daily upload quota | `ChamakAPI.checkQuota` calls `fetchUploadUsage` and treats `limit ?? 10` | An AI fusion currently costs the same as a photo upload. That's economically wrong — fusion is far more expensive to run. |
| **The AI pipeline is unauthenticated HTTP** | `_spec/04-data-contracts.md:1326` — "The **entire AI pipeline** … unauthenticated HTTP" | ⚠️ **Blocking.** Anyone with the URL can run generations for free. A credit system in front of an open endpoint is decoration. |
| The admin APIs are also unauthenticated + service-role | `_spec/04-data-contracts.md:1369` | Anyone could grant themselves credits once an admin grant endpoint exists. |
| Quota checks **fail open** | `fetchUploadUsage` returns `.unknown` (unlimited) on any error; web hook "fails open so uploads are never blocked" | Fine for a courtesy limit. Fatal for money. Credit checks must **fail closed**. |
| No payment rails anywhere | No StoreKit, no Razorpay, no `.entitlements` file; `project.yml` packages = Supabase + GoogleSignIn only | Everything in §7 is greenfield. |
| No push notification infrastructure | No `UNUserNotificationCenter`, no `aps-environment`, no entitlements | The "notify below threshold" requirement can't be a push in v1. In-app banner first. |
| Supabase with per-row RLS is the app's real backend | `SUPABASE_CHAMAK_MIGRATION.sql`, all `*API.swift` | The ledger belongs here, behind `SECURITY DEFINER` functions. |
| A premium surface is already designed on the retailer side | `_spec/03-shell-and-navigation.md:539` — ClaimModal: "Unlock premium components, custom layouts, and a royal theme" | Monetisation hook #2 already has UI. See §11. |
| Referral infrastructure exists | `referral_links` table, `InviteRetailerSheet.swift` | Free acquisition loop to pay out in credits. See §4.3. |

**Read this table as one sentence:** we already have a meter, we already have a
place to put the ledger, and we have zero enforcement and zero payment rails.

---

## 2. What is a credit?

### 2.1 Naming
"Credits" is generic. This is a jewellery platform for Indian wholesalers —
the currency should feel native:

| Name | Case for | Case against |
|---|---|---|
| **Ratti** | Traditional Indian gemstone weight unit. Every jeweller knows it. "50 Ratti in your Treasure Chest" reads perfectly. | Real-world meaning may confuse (it's a weight, not money). |
| **Karat / Carat** | Universally understood in the trade, connotes value and purity. | "24 karat" has a fixed cultural meaning — a balance of 137 karat reads odd. |
| **Chamak** | Already the brand of the flagship AI feature. Self-reinforcing. | Overloads a feature name with a currency name — confusing when Chamak costs Chamak. |
| **Credits** | Zero explanation needed, matches every SaaS. | Forgettable. |

**Recommendation: "Ratti", with "credits" as the subtitle everywhere for the first
release** (`50 Ratti` / `50 credits`). If it doesn't land in user testing, the
fallback costs one string file.

### 2.2 Pegged or opaque?
Do we say "1 credit = ₹1"?

- **Pegged (1:1 with ₹)** — total transparency, trusted by B2B buyers, trivially
  understood. But you can never discount without discounting cash, and every
  price change is visible as a price rise.
- **Opaque (credits float)** — lets you run bonus packs, promos, referral payouts
  and price changes without touching the rupee price. Standard for AI products.
  Risk: Indian B2B buyers are sharp about "points" schemes and read them as a trick.

**Recommendation: opaque, but with a published, in-app rate card.** A fixed sticker
rate of **1 credit = ₹10** and a visible "what things cost" table inside the
Treasure Chest. Bonus credits on larger packs give you the discount lever without
ever changing the sticker rate. Transparency without rigidity.

### 2.3 Unit economics — the numbers that decide everything

⚠️ **These are placeholders.** I don't have your actual AI vendor bill. The
structure is right; the numbers must be replaced with real COGS before pricing.

**Cost side (assumed, per action):**

| Action | What it runs | Assumed COGS |
|---|---|---|
| Product upload | Background removal (`reve_*`) + 4 AI variants + storage | ₹6 – ₹18 |
| Chamak fusion | Stage-1 vision analysis + Stage-2 image generation | ₹4 – ₹12 |
| Reprocess / re-roll | 1 generation call | ₹2 – ₹6 |
| Storage + bandwidth | Supabase, per product lifetime | ~₹0.5 |

**Price side (proposed rate card):**

| Feature | Credits | Sticker (₹10/cr) | Effective at biggest pack (₹7.7/cr) | Gross margin @ mid COGS |
|---|---|---|---|---|
| Product upload — **within free daily allowance** | 0 | ₹0 | ₹0 | negative (acquisition cost) |
| Product upload — beyond allowance | 2 | ₹20 | ₹15 | ~40 – 60% |
| Reprocess existing product | 1 | ₹10 | ₹7.7 | ~50% |
| **Chamak fusion** | 10 | ₹100 | ₹77 | ~85 – 90% |
| Chamak re-roll (same inputs, new output) | 6 | ₹60 | ₹46 | ~85% |
| Chamak with custom uploaded photos | 12 | ₹120 | ₹92 | ~88% |

**Why 10 credits (₹100) for a Chamak fusion is defensible, not greedy:** a
professional jewellery product shoot in India runs ₹200 – ₹500 *per piece*, takes
days, and needs the physical piece in hand. Chamak produces a sellable design
visual in minutes from photos they already have. ₹100 is an obvious yes. The
anchor to use in the UI is *photographer cost*, never *token cost*.

**The margin question that actually matters:** at these numbers the business is
not selling AI at a markup — it's selling **speed and catalogue velocity**. Price
against the alternative (a photographer, a designer, a sampling run), not against
the API bill. That also means the pricing survives the API bill dropping 10×.

---

## 3. "Currency within each flow" — the credit map

This is the heart of the request. Every flow, what it costs, when it debits.

| # | Flow | Entry point | Cost | Debit moment | Refund policy |
|---|---|---|---|---|---|
| 1 | **Add Product** (AI pipeline) | `AddProductView` / upload tab | 0 within free daily allowance, then 2 | On successful `POST /process` accept (job queued) | Auto-refund if pipeline returns failure or times out |
| 2 | **Reprocess product** | `ProductDetailSheet` → reprocess | 1 | On accept | Auto-refund on failure |
| 3 | **Chamak — Stage 1 analysis** | `ChamakCatalogPickerView` → continue | **0 (free)** | — | — |
| 4 | **Chamak — fusion generate** | `ChamakSliderFormView` → Generate | 10 (12 with custom photos) | On `submitFormAndGenerate` accept | Auto-refund when row flips to `failed`, or content flag rejects it |
| 5 | **Chamak — re-roll** | `ChamakResultView` → try again | 6 | On accept | Auto-refund on failure |
| 6 | **Chamak gallery / download** | `ChamakGalleryView` | 0 | — | Never charge twice for something already paid for |
| 7 | Catalogue browse / edit / delete | — | 0 | — | — |
| 8 | Orders, chat, invite retailer | — | 0 | — | Never meter communication — it kills the marketplace |
| 9 | *(future)* Priority queue | subscription perk | — | — | — |
| 10 | *(future)* Bulk upload (10+ at once) | — | 2/product, 15% off at 20+ | On batch accept | Per-item refund |

**Three rules that keep this coherent:**

1. **Never meter what creates network value.** Chat, orders, invites, browsing —
   free forever. Metering these shrinks the marketplace to shrink the AI bill.
   Wrong trade.
2. **Analysis is free, generation is paid.** Stage 1 is the hook — it shows the
   wholesaler something genuinely useful (what's strong/weak about their designs)
   at zero cost, and creates the desire for Stage 2. This is the single most
   important pricing decision in the list.
3. **Costs live on the server, not in Swift.** A `credit_prices` table the app
   reads. Hardcoding `10` in `ChamakViewModel` means a price change ships through
   App Review. Non-negotiable.

---

## 4. Credit lifecycle: available / used / expired

The brief asks for available, used, and expired. That implies **lots**, not a
single integer balance.

### 4.1 Lots (a.k.a. buckets)
Each grant is a lot: `{credits_granted, credits_remaining, granted_at, expires_at, source}`.

`available_balance = Σ credits_remaining WHERE expires_at > now()`

Spending consumes lots **expiring-soonest first (FIFO by expiry)**. This is both
user-friendly (nothing expires that could have been used) and margin-friendly.

### 4.2 Expiry policy — and a pushback
The brief says expired credits must be displayed. Before building it, decide
*whether we want expiry at all*:

| Source | Proposed expiry | Reasoning |
|---|---|---|
| Welcome grant | 30 days | Forces activation. This is its whole job. |
| Promo / referral / support goodwill | 60 – 90 days | Costs us nothing to grant, shouldn't sit as an open liability forever. |
| **Purchased packs** | **12 months, or never** | ⚠️ See below. |
| Subscription monthly allowance | End of billing month, with a 1-month rollover cap | Standard, understood. |

⚠️ **Expiring purchased credits in Indian B2B is a trust landmine.** A wholesaler
who paid ₹5,000 and lost ₹800 to expiry tells the entire market. It also has legal
texture: prepaid credits are **vouchers under Indian GST** and expiry of paid
value invites consumer-protection questions. The revenue from breakage is small;
the reputational cost in a tight-knit trade is not.

**Recommendation: purchased credits never expire. Only free credits expire.** Keep
the `expires_at` column and the expired-credits UI (the brief asks for it, and
promo credits will populate it) — just set purchased lots to `NULL`.

### 4.3 Ways to earn credits without paying
Each of these is a growth loop, and each needs an anti-abuse rule:

| Grant | Amount | Trigger | Abuse guard |
|---|---|---|---|
| Welcome | 100 (≈10 Chamak runs) | Onboarding **verified**, not merely submitted | Tie to verified status + unique phone. One per business, not per account. |
| Referral — retailer signs up | 25 | Invited retailer completes onboarding | Existing `referral_links` tracking; cap per month |
| Referral — retailer's first order | 50 | First order placed | Naturally hard to fake |
| Feedback on a Chamak result | 2 | `chamak_feedback` submitted | Once per generation (FK already unique-able) |
| Support goodwill | manual | Bad generation, outage | Admin-only, audited, rate-limited |
| Streak / volume | 10 | 25 products uploaded in a month | Cheap retention lever |

The welcome grant is the most important number here. 100 credits ≈ 10 Chamak runs
≈ ₹1,000 of sticker value ≈ maybe ₹80 of real COGS. That is a cheap, high-conviction
activation bet.

---

## 5. Data model (Supabase)

```sql
-- One per wholesaler. Cached balance for fast reads; lots are the truth.
credit_accounts (
  wholesaler_id       uuid PK REFERENCES auth.users(id),
  balance_cached      int NOT NULL DEFAULT 0 CHECK (balance_cached >= 0),
  lifetime_granted    int NOT NULL DEFAULT 0,
  lifetime_spent      int NOT NULL DEFAULT 0,
  low_balance_threshold int NOT NULL DEFAULT 20,
  low_balance_notified_at timestamptz,
  updated_at          timestamptz
)

-- Every grant is a lot. FIFO-by-expiry consumption.
credit_lots (
  id, account_id, source ('welcome'|'purchase'|'subscription'|'referral'|'promo'|'refund'|'admin'),
  credits_granted int, credits_remaining int CHECK (credits_remaining >= 0),
  granted_at, expires_at NULL, purchase_id NULL, note
)

-- Append-only. Never UPDATE, never DELETE. This is the audit trail.
credit_ledger (
  id, account_id, lot_id NULL,
  delta int,                        -- +grant / -debit / +refund / -expiry
  kind ('grant'|'debit'|'refund'|'expiry'|'adjustment'),
  feature_key NULL,                 -- 'chamak.generate', 'product.upload', ...
  reference_type NULL,              -- 'chamak_generation' | 'product'
  reference_id NULL,
  idempotency_key text UNIQUE,      -- ⭐ this column prevents every double-charge bug
  balance_after int,
  created_at, metadata jsonb
)

-- Server-side rate card. The app renders costs FROM here.
credit_prices (
  feature_key PK, credits int, label, description,
  is_active bool, effective_from
)

-- Purchases, both rails.
credit_purchases (
  id, account_id,
  provider ('apple'|'razorpay'|'manual'),
  provider_txn_id text UNIQUE,      -- ⭐ prevents receipt replay
  pack_key, credits int,
  amount_inr numeric, gst_inr numeric,
  status ('pending'|'paid'|'failed'|'refunded'|'chargeback'),
  receipt_json jsonb, created_at, settled_at
)
```

**RLS:** `SELECT` own rows only, on all five tables. **No client `INSERT`/`UPDATE`
anywhere.** Every mutation goes through `SECURITY DEFINER` functions. If the iOS
app can write to `credit_lots`, the currency is worthless.

---

## 6. Enforcement — where the debit actually happens

### 6.1 The atomic debit
```
spend_credits(feature_key, reference_id, idempotency_key) RETURNS (ok, balance, error)
```
Inside one transaction:
1. `SELECT ... FROM credit_ledger WHERE idempotency_key = $x` → if found, return the
   original result. **Idempotent replay, not a second charge.**
2. Look up cost from `credit_prices` (**server decides the price, never the client**).
3. `SELECT ... FROM credit_lots WHERE account = $me AND credits_remaining > 0
   AND (expires_at IS NULL OR expires_at > now()) ORDER BY expires_at NULLS LAST FOR UPDATE`
4. If `Σ remaining < cost` → return `INSUFFICIENT_CREDITS`. **No negative balance is
   representable** — the `CHECK (>= 0)` constraints are the backstop, the row lock
   is the mechanism.
5. Decrement lots FIFO, insert ledger row(s), update `balance_cached`.
6. Return new balance.

`FOR UPDATE` is what makes double-tap, two-devices, and race conditions safe. Not
optimistic checks in Swift.

### 6.2 ⚠️ The blocking problem: the pipeline is open
Debiting in Supabase and then calling an unauthenticated pipeline means the debit
is **advisory**. Anyone who watches the network traffic once can call
`POST {AI_PIPELINE}/api/chamak/generate` forever, free.

Two fixes, in order of correctness:

**A. Job tokens (correct).** `spend_credits` mints a single-use, short-TTL token
(HMAC or a row in `credit_jobs`). The app passes it to the pipeline. The pipeline
verifies and marks it consumed before doing any work. No token, no generation.
Requires a change in the pipeline repo — **which is not this repo**, so this is a
cross-team dependency and should be raised now, not at implementation time.

**B. Route through Supabase Edge Functions (interim).** The app calls an Edge
Function with its JWT; the function debits and then calls the pipeline from the
server side. The pipeline URL stops being something the client ever sees. Weaker
(the pipeline is still open if the URL leaks) but ships without touching their repo.

**Doing neither means the credit system is a UI, not a control.** Worth saying
plainly to whoever owns the pipeline.

### 6.3 Refunds
Chamak failures are real and current (this branch exists to surface them). So:

- **Debit when work starts, auto-refund when it fails.** A backend job (or a
  Postgres trigger on `chamak_generations.status → 'failed'`) calls
  `refund_credits(reference_id, reason)` with idempotency key `refund:{generation_id}`.
- Refund into a **new lot** with the original lot's expiry (or +30 days if that
  already passed). Never resurrect a spent lot.
- Show it in history: **"Refunded — generation failed · +10"**. Visible refunds
  build more trust than invisible reservations.
- Never refund from the client. The client asking for a refund is a free-credits API.

*Alternative considered:* reserve-then-capture (hold credits, capture on success).
Cleaner in theory, but "10 credits on hold" is confusing to a non-technical
wholesaler, and it doubles the state machine. Debit + visible refund is the right
call for this audience.

---

## 7. Buying credits — the rails, and the App Store reality

This is where the project gets genuinely hard, and it's mostly not code.

### 7.1 Apple's rules
Credits that unlock digital features **inside the app** are digital content.
Under App Store Review Guideline 3.1.1, selling them in the app **must** use
StoreKit in-app purchase (consumables). Apple takes 30%, or **15% under the Small
Business Program** (<$1M/year — you almost certainly qualify).

Outside the US, the app also **may not link to or mention an external way to buy**.
No "buy on our website", no browser hand-off. (The 2025 US anti-steering injunction
permits external links on the US storefront — it does not apply to the India
storefront, which is the one that matters here.)

### 7.2 The India / GST angle — this is the decisive one
- AI services attract **18% GST**.
- Prepaid credits are **vouchers** under GST; for a single-purpose voucher, tax
  is due at issuance, not redemption. Get this reviewed by a CA — it changes when
  you recognise revenue.
- **Your buyers are GST-registered businesses.** They want a tax invoice with your
  GSTIN so they can claim input tax credit. That makes the purchase effectively
  18% cheaper for them.
- **Through Apple IAP, Apple is the merchant of record.** The wholesaler receives
  an Apple receipt, not your GST invoice, and **cannot claim input tax credit**.
  For a ₹5,000 purchase that's ~₹900 of real, felt cost.

So the serious buyer *wants* to pay you directly, and Apple's rules say you can't
tell them that inside the app. That tension defines the design.

### 7.3 Recommended: dual rail
| Rail | Where | Price | Invoice | Apple cut |
|---|---|---|---|---|
| **StoreKit consumables** | iOS app | Higher (absorbs 15–30%) | Apple receipt | 15–30% |
| **Razorpay** | Web dashboard (`app.jewelindia.shop`) | Lower, GST invoice with GSTIN | Yours | 0% (≈2% gateway) |

Apple permits different prices on different platforms. The app sells IAP and never
mentions the web. Wholesalers who buy in volume will find the web store through
sales conversations, email, and WhatsApp — which is how B2B actually buys anyway.

*Note on the pure-web option:* shipping the app with **no** purchase at all and
selling only on web is what Slack/Notion do and is fully compliant — but a
wholesaler who runs out of credits at 11pm has no way to continue, and that is
exactly the moment they'd have paid. Worth the IAP work.

### 7.4 Proposed packs
| Pack | ₹ (web, +GST) | Credits | Bonus | ₹/credit | Chamak runs |
|---|---|---|---|---|---|
| Starter | 499 | 50 | — | 10.00 | 5 |
| Popular ⭐ | 1,999 | 220 | +10% | 9.09 | 22 |
| Pro | 4,999 | 600 | +20% | 8.33 | 60 |
| Bulk | 9,999 | 1,300 | +30% | 7.69 | 130 |

iOS prices sit one Apple price-tier up to absorb the commission.

### 7.5 Subscriptions — the bigger prize
One-off packs give lumpy revenue. Monthly plans that *grant* credits give
predictable revenue and much better retention:

| Plan | ₹/month | Credits/month | Extras |
|---|---|---|---|
| Chandi (Silver) | 999 | 120 | — |
| Sona (Gold) | 2,499 | 350 | Priority queue, higher daily upload allowance |
| Heera (Diamond) | 6,999 | 1,000 | Priority, dedicated support, early features |

Subscription credits expire monthly (1-month rollover cap); top-ups don't. Razorpay
Subscriptions / UPI Autopay on web; StoreKit auto-renewables on iOS.

**Recommendation: ship top-up packs first, subscriptions in a later phase.** Packs
teach you the actual consumption curve, which is what you need to price a plan
correctly. Guessing plan sizes before you have that data is how you end up with a
₹999 plan that costs you ₹1,400 to serve.

### 7.6 Prerequisites that are not code
Registered entity · GSTIN · Razorpay KYC · Apple Developer **Organization** account
(D-U-N-S) · Paid Applications Agreement with Indian banking + tax forms · Terms of
service covering credits, expiry, refunds · a CA's opinion on voucher GST timing.
**These have multi-week lead times and should start in parallel with Phase 1.**

---

## 8. UI surfaces

### 8.1 Persistent — the balance pill
A small balance pill in the toolbar next to the profile menu, on every wholesaler
screen (`WholesalerShell.profileMenu` sits there already). Tapping opens the
Treasure Chest. This is the literal answer to "currency within each flow" —
the balance is never more than a glance away.

### 8.2 Home — the wallet card
`WholesalerHomeView` today: hero → Insights (4 `StatCard`s) → ChamakCard → catalogue.

The wallet is **not** a KPI, so it shouldn't be a fifth `StatCard`. Put a distinct
Treasure Chest card **between the hero and "Insights"**: chest artwork, large
available balance, a thin expiring-soon line when relevant, and a "Top Up" button.
Amber/gold accents (`Palette.statusPending` #F59E0B is already the amber token)
against the cream/taupe palette — it should read as *treasure*, distinct from the
monochrome KPI cards.

### 8.3 Treasure Chest screen
Pushed from the card or the pill:
- **Hero:** available balance, big, in the Cirka display face used for section titles.
- **Three stats:** Available · Used (lifetime) · Expired. Plus "X expiring in Y days" when true.
- **Buy Credits** — primary CTA, opens the pack sheet.
- **Rate card** — "What things cost", read live from `credit_prices`. Builds trust and doubles as feature discovery.
- **Transaction history** — grouped by date, `+`/`−` with feature icon, and for
  Chamak rows a thumbnail of the generated image. Filter chips: All / Spent / Added / Expired.
  Paginated; the ledger grows forever.

### 8.4 In-flow treatment
- **Cost chip** on `ChamakCard` — "10 credits" — visible *before* entry.
- **Confirmation on the action button**, not a modal: `Generate` → **"Fuse · 10 credits"**.
  One tap, cost stated. A confirm dialog on every generation would be exhausting.
- **Post-action toast**: "−10 credits · 90 left". Immediate, dismissible.
- **Insufficient balance sheet**: not an alert. A sheet showing what they're short
  by, the packs, and the top-up CTA — recovery inline, without losing the flow
  state they already filled in. Their sliders and note must survive the purchase.
- The existing `showQuotaAlert` in `ChamakViewModel` is the seam this replaces.

### 8.5 Low-balance notification
Requirement: notify below a threshold. Reality: no push infrastructure exists.
- **v1:** in-app banner on home + a badge on the balance pill, fired once per
  threshold crossing (`low_balance_notified_at` prevents nagging; reset when
  topped back up).
- **v2:** local notification.
- **v3:** APNs push — needs entitlements, a capability, an APNs key, and a backend
  sender. Meaningful work; don't scope it into v1.
- Threshold default 20 credits, but make it **dynamic**: "less than 2 Chamak runs"
  is a better trigger than a fixed number, and it survives price changes.

---

## 9. Edge cases and failure modes

| Case | Handling |
|---|---|
| Double-tap Generate | `idempotency_key = 'chamak:' + generation_id`, UNIQUE. Second call returns the first result. |
| App killed mid-generation | Debit already committed server-side. Refund is a **backend** trigger on `status → failed`, never client-driven. |
| Two devices, same account | Server is truth. Local balance is display-only, refetched on wallet open, on flow entry, and after every debit. |
| Offline | Show last known balance with an "as of" timestamp. Block spend actions rather than optimistically allowing them. |
| Credits expire between debit and refund | Refund into a fresh lot; original expiry, or +30 days if already past. |
| Apple/Razorpay refund or chargeback after credits spent | Balance can't go negative (CHECK). Clamp at 0 and flag the account as `recovery_owed`; block further purchases until settled rather than blocking usage. **Needs a policy decision.** |
| Price change mid-session | App shows cost from `credit_prices`; server re-reads at debit time. On mismatch, server wins and the client refreshes the displayed cost. |
| Welcome-grant farming | Grant on **verified** onboarding, unique phone, one per business entity. |
| Admin grants | Audited ledger rows with `kind='adjustment'` + operator id. ⚠️ Must be behind real auth — today's admin APIs have none. |
| Free daily allowance timezone | Currently pipeline-owned via `resetsAt`. Keep IST, and make sure the wallet UI and the allowance UI don't contradict each other. |
| Ledger growth | Index `(account_id, created_at DESC)`. Paginate. Consider monthly rollup rows after a year. |

---

## 10. What could go wrong strategically

1. **Metering kills usage.** Today Chamak is effectively free; the day it costs
   ₹100, usage may fall 80%. Mitigation: generous welcome grant, free Stage-1
   analysis, and instrument the drop-off before and after so you can tell
   "priced too high" from "wasn't valuable anyway".
2. **We meter something that shouldn't be metered.** Uploads are how the catalogue
   grows, and the catalogue is the product. Charging for uploads may cost more in
   marketplace liquidity than it earns. **Keep the free daily allowance generous.**
3. **The pipeline stays open** and credits become theatre. See §6.2.
4. **We build the store before knowing the consumption curve.** Ship the ledger and
   free grants first, watch real usage for 3–4 weeks, *then* price.

---

## 11. Adjacent monetisation levers (not credits)

Worth listing because they may out-earn credits with less machinery:

| Lever | Status | Note |
|---|---|---|
| **Retailer premium themes** | UI already designed — the ClaimModal in `_spec/03-shell-and-navigation.md:539` | "Unlock premium components, custom layouts, and a royal theme." A ready-made paid surface on the retailer side. |
| Order commission | Orders flow exists | Highest ceiling, highest friction — needs payments between parties. |
| Featured placement in retailer catalogues | Catalogue exists | Classic marketplace ad revenue. Wholesalers pay in **credits** — ties the two systems together elegantly. |
| Verified / Premium wholesaler badge | Verification status exists | Pure margin, no COGS. |
| Retailer seat licensing | `employees` table exists | Per-seat SaaS on the retailer side. |

**Featured placement paid for in credits is the strongest of these** — it gives
credits a second sink that costs us nothing to serve, which improves blended
margin across the whole currency.

---

## 12. Phasing

| Phase | What | Depends on | Rough size |
|---|---|---|---|
| **0** | Pipeline auth / job tokens (§6.2) | **External pipeline team** | Blocking, not ours |
| **1** | Ledger + RPCs + rate card + read-only wallet UI (balance, history, stats). Free grants only, nothing metered. | Supabase only | Backend-heavy |
| **2** | Meter Chamak: cost chips, debit, auto-refund, insufficient sheet. Instrument everything. | 0, 1 | Medium |
| **3** | Web purchase via Razorpay + GST invoicing. App just shows balance rising. | Entity, GSTIN, KYC | Medium |
| **4** | StoreKit consumables in-app. | Apple org account, agreements | Medium |
| **5** | Subscriptions, referral payouts, low-balance push, featured placement. | 1–4 + real usage data | Large |

**Phases 1 and 2 are worth shipping even if the store never launches** — the
ledger and the meter are what let you understand your own cost structure. That's
the real first deliverable.

---

## 13. Open questions — need your call

1. **Who pays?** Wholesalers only, or retailers too? Everything above assumes
   wholesalers only.
2. **Free allowance:** do credits *replace* the daily upload limit, or stack on top
   of it? (I've assumed stack — free allowance stays, credits handle overflow + premium.)
3. **Actual COGS per generation?** Every number in §2.3 is a placeholder until we
   see the AI vendor bill. What's the vendor, what's the per-call cost?
4. **Who owns the AI pipeline repo, and can we get auth added?** This gates Phase 0.
5. **Business readiness:** registered entity, GSTIN, Razorpay account, Apple
   Developer *Organization* account — which of these exist today?
6. **Is the web dashboard still the primary surface?** If wholesalers mostly use
   the web app, purchase belongs there first and iOS IAP can wait.
7. **Peg to ₹ or opaque credits?** (Recommended: opaque + published rate card.)
8. **Do purchased credits expire?** (Recommended: no. Only free ones.)
9. **Refund policy on a *bad but successful* generation** — the image renders, but
   it's ugly. Auto-refund via the feedback flow, manual on support request, or
   never? This will be the single most common support ticket.
10. **Naming:** Ratti / Karat / Chamak / Credits?
