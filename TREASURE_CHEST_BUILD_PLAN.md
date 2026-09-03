# Treasure Chest — Complete Build & Monetisation Plan

**Status: plan only. No code written.**
**Audience: you (business decisions), your tech team (build), and as the reference for what we're actually shipping.**

Companion doc: `TREASURE_CHEST_RESEARCH.md` (the research behind these decisions).

---

# Part 0 — Read this first

There is **one constraint** that shapes every other decision in this document, so
it goes at the top rather than buried in a payments section.

> **Apple does not allow you to sell credits inside the iOS app using Razorpay.**

Credits that unlock AI features inside the app are "digital content" under App
Store Review Guideline 3.1.1. Selling them in-app **must** go through Apple's own
in-app purchase system, where Apple takes 15–30%. On the India App Store you also
**cannot link to, or even mention, an outside way to pay**. No "buy on our
website" button. No browser hand-off.

This is not a technical limit we can engineer around — apps get rejected, and apps
that sneak it in get pulled.

**So Razorpay is absolutely usable — just not from a button inside the iOS app.**
It works perfectly for:

- your web dashboard (`app.jewelindia.shop`)
- payment links sent over WhatsApp, email, or by your sales team
- any purchase that happens outside the app

And this turns out to fit Indian B2B extremely well, because that is how
wholesalers actually buy things — through a person, over WhatsApp, with a proper
GST invoice. **Part 3 builds the whole money flow around that.**

---

# Part 1 — What we're building, in plain language

## 1.1 The whole thing in one paragraph

Every wholesaler gets a wallet called the **Treasure Chest**. It holds credits.
AI actions — mainly Chamak design fusion — cost credits. New wholesalers get a
free grant so they can try everything without paying. When they run low, they buy
more: through your Razorpay page, through a payment link your team sends them, or
(later) directly in the app through Apple. Every credit in and out is recorded in
a permanent ledger, so you can always answer "where did my credits go" and you can
always see your own real margin per generation.

## 1.2 A day in the life — the full journey

This is the story the whole build has to support. Read it once and the rest of the
document will make sense.

**Day 1 — Rajesh signs up.**
Rajesh runs a wholesale jewellery business in Jaipur. He completes onboarding,
uploads his documents, and gets verified. The moment verification lands,
**100 free credits** appear in his Treasure Chest — enough for 10 Chamak fusions.
He sees a banner: *"100 credits added — welcome gift. Valid 30 days."*

**Day 1 — He tries Chamak.**
He opens Chamak, picks two designs from his catalogue. The analysis screen shows
what's strong about each — **this costs him nothing**. He likes what he sees,
adjusts the sliders, writes a note, and the button says **"Fuse · 10 credits"**.
He taps. A toast appears: *"−10 credits · 90 left"*. Forty seconds later he has a
new design image.

**Day 3 — A generation fails.**
The pipeline errors out. Rajesh sees a clear failure message, and in his
transaction history: *"Refunded — generation failed · +10"*. He didn't have to ask.

**Day 12 — He runs low.**
Balance hits 18 credits. A banner on his home screen: *"Running low — 18 credits
left, about 1 more fusion."* The balance pill in the corner turns amber.

**Day 12 — He buys.**
He taps "Top Up". The app shows him the packs — and here's where the Apple
constraint bites. Two possible worlds:

- *If we've shipped Apple IAP:* he buys right there, Apple charges his card,
  credits land in seconds.
- *If we haven't:* the app shows the packs and says "contact your account
  manager". Your team sends him a Razorpay payment link on WhatsApp. He pays by
  UPI. A webhook fires, credits land, he gets a GST invoice by email.

**Day 12 — Credits land.**
600 credits appear. His GST invoice arrives with your GSTIN on it, so his
accountant can claim the input tax credit. He goes back to Chamak.

**Day 40 — His free credits expire.**
He never used the last 12 of his welcome grant. A ledger row appears:
*"Expired · −12 (welcome credits)"*. His 600 purchased credits are untouched —
**purchased credits never expire.**

## 1.3 What is deliberately NOT metered

Free forever, no credits, no limits:

- Chat with retailers
- Orders (creating, viewing, updating)
- Inviting retailers
- Browsing and editing your catalogue
- **The Chamak analysis screen** (only the fusion costs)
- Viewing and downloading anything you already generated

**Why this matters:** chat, orders and invites are what make the marketplace
valuable. Metering them would shrink the marketplace in order to shrink your AI
bill. That is a bad trade in both directions.

---

# Part 2 — The money: what a credit costs and what things cost

## 2.1 What one credit is worth

> **1 credit = ₹10** (sticker rate)

Fixed, published, printed inside the app. It never changes. Discounts are given
as **bonus credits on larger packs**, never by moving the rate.

Why fixed: "₹4,999 → 600 credits" reads as generous. "₹4,999 → credits worth
₹6,000" reads as a scheme. Indian B2B buyers are sharp about points schemes.

## 2.2 The rate card — what each action costs

| Action | Credits | = ₹ at sticker | Notes |
|---|---:|---:|---|
| **Chamak — analysis** | **0** | **₹0** | Always free. This is the hook. |
| **Chamak — fusion** | **10** | ₹100 | The main product |
| Chamak — fusion with custom uploaded photos | 12 | ₹120 | Extra upload + processing |
| Chamak — re-roll (same inputs, new result) | 6 | ₹60 | Analysis already paid for |
| Product upload — within free daily allowance | 0 | ₹0 | The existing daily limit stays |
| Product upload — beyond allowance | 2 | ₹20 | |
| Reprocess an existing product | 1 | ₹10 | |
| Viewing / downloading past results | 0 | ₹0 | Never charge twice |

**This table lives in the database, not in the app code.** It's a `credit_prices`
table the app reads at runtime. Changing a price is a database update, not an app
release through Apple review. This is important and non-negotiable.

## 2.3 Why ₹100 for a fusion is the right number

Don't price against what the AI costs you. Price against what the wholesaler's
alternative costs:

| Their alternative | Cost | Time |
|---|---|---|
| Professional jewellery product shoot | ₹200 – ₹500 per piece | Days, needs the physical piece |
| Design sampling to test a variation | ₹2,000 – ₹15,000 | Weeks |
| **Chamak fusion** | **₹100** | **~1 minute, from photos they already have** |

At ₹100 it is an obvious yes. And because the price is anchored to *photographer
cost* rather than *token cost*, it stays correct even when AI gets 10× cheaper —
which it will. **That price stability is where your margin expansion comes from.**

## 2.4 Your margin

⚠️ **The COGS column is a placeholder.** Replace with your real AI vendor bill
before finalising anything. The structure is right; the numbers are guesses.

| Action | Assumed COGS | You charge | Gross margin |
|---|---:|---:|---:|
| Chamak fusion | ~₹8 | ₹77 – ₹100 | **~90%** |
| Chamak re-roll | ~₹6 | ₹46 – ₹60 | ~88% |
| Product upload (paid) | ~₹12 | ₹15 – ₹20 | ~30% |
| Free tier upload | ~₹12 | ₹0 | **−₹12 (acquisition cost)** |

Read that last row deliberately. **The free daily upload allowance is a marketing
expense, not a bug.** It's what keeps catalogues growing, and catalogues are the
product. Budget for it.

## 2.5 The packs

**On web / Razorpay** (prices exclusive of GST — your buyers are GST-registered
and reclaim it):

| Pack | Price | + 18% GST | Credits | Bonus | Effective ₹/credit | Fusions |
|---|---:|---:|---:|---:|---:|---:|
| Starter | ₹499 | ₹589 | 50 | — | ₹9.98 | 5 |
| **Popular** ⭐ | ₹1,999 | ₹2,359 | 220 | +10% | ₹9.09 | 22 |
| Pro | ₹4,999 | ₹5,899 | 600 | +20% | ₹8.33 | 60 |
| Bulk | ₹9,999 | ₹11,799 | 1,300 | +30% | ₹7.69 | 130 |

**On iOS via Apple** (inclusive of everything, marked up to absorb Apple's cut —
Apple explicitly permits different prices on different platforms):

| Pack | App price | Credits | What actually reaches you |
|---|---:|---:|---:|
| Starter | ₹699 | 50 | ~₹503 |
| Popular | ₹2,900 | 220 | ~₹2,088 |
| Pro | ₹6,900 | 600 | ~₹4,968 |
| Bulk | ₹13,900 | 1,300 | ~₹10,008 |

*Math: Apple's India price is tax-inclusive. Remove 18% GST, then Apple keeps 15%
under the Small Business Program (you qualify — it's for developers under
$1M/year). ₹699 ÷ 1.18 = ₹592, less 15% = ~₹503.*

Compare: the ₹499 web pack nets you ~₹489 after Razorpay fees. The ₹699 Apple pack
nets ~₹503. **Priced this way, Apple's cut is fully absorbed and you net slightly
more per iOS sale** — the wholesaler simply pays more for the convenience of
buying at 11pm without talking to anyone. That's a fair trade and a normal one.

## 2.6 Free credits — the growth loops

| Grant | Credits | When | Expires | Anti-abuse |
|---|---:|---|---|---|
| **Welcome** | **100** | Onboarding **verified** (not just submitted) | 30 days | One per business; unique phone |
| Referral — retailer joins | 25 | Invited retailer completes onboarding | 90 days | Uses existing `referral_links`; monthly cap |
| Referral — first order | 50 | That retailer places their first order | 90 days | Hard to fake |
| Feedback on a result | 2 | Submits Chamak feedback | 90 days | Once per generation |
| Support goodwill | manual | Bad result, outage | 90 days | Admin only, audited |

**The welcome grant is the single most important number here.** 100 credits ≈ 10
fusions ≈ ₹1,000 of sticker value ≈ maybe ₹80 of real cost to you. It's a cheap,
high-conviction bet that once a wholesaler sees ten good designs, they'll pay.

## 2.7 Expiry rules

| Type | Expires? |
|---|---|
| **Purchased credits** | **Never** |
| Welcome grant | 30 days |
| Referral / promo / goodwill | 90 days |
| Subscription credits (later phase) | End of billing month, 1-month rollover |

**Purchased credits must never expire.** A wholesaler who paid ₹5,000 and lost
₹800 to expiry will tell the entire market — and in this trade, that travels fast.
The breakage revenue is small; the reputational damage is not. Also: prepaid
credits are legally **vouchers** under Indian GST, and expiring paid value invites
consumer-protection questions you don't want.

The expired-credits display still gets built — free credits will populate it.

**Spending order: expiring-soonest first.** So free credits get used before
purchased ones, and nothing expires that could have been spent.

---

# Part 3 — How money actually comes in (Razorpay)

## 3.1 What you have vs what's needed

You mentioned you have a Razorpay page. Razorpay has three different products and
they matter differently here:

| Product | What it is | Good for | Enough on its own? |
|---|---|---|---|
| **Payment Page** | Hosted page, no code | Quick start, self-serve | ⚠️ **Not by itself** — see below |
| **Payment Links** | One-off link per customer, sent on WhatsApp/SMS/email | **Sales-assisted B2B — the best fit for phase 1** | ✅ Yes, with webhooks |
| **Checkout / Orders API** | Integrated into your web dashboard | The proper long-term self-serve flow | ✅ Yes, best experience |

### ⚠️ The problem with a plain Payment Page

**A generic payment page does not tell you who paid.** Someone pays ₹4,999 — but
which wholesaler's account gets 600 credits? Without solving that, you're matching
payments to accounts by hand, and it breaks the moment you have volume.

Three ways to solve it, in increasing order of robustness:

1. **Payment Page + required custom field** — "Registered mobile number". You match
   that against the account. Works, but wholesalers mistype phone numbers
   constantly, and then it's a support ticket.
2. **Payment Link with `notes`** — your system generates a link carrying
   `notes: { wholesaler_id: "<uuid>", pack: "pro" }`. The webhook reads it back and
   credits the right account automatically. **Clean, and cheap to build.**
3. **Checkout with a server-created Order** — your web backend creates the Razorpay
   Order with the same `notes`, and the user never touches identity fields at all.
   **Bulletproof. The long-term answer.**

**Recommendation: build #2 first, #3 when the web dashboard is ready.**

## 3.2 The three routes money can take

| Route | How | Apple-safe? | Build effort | Best for |
|---|---|---|---|---|
| **A. Sales-assisted link** | Wholesaler asks → your team generates a Razorpay Payment Link → WhatsApp → they pay by UPI → webhook credits them | ✅ Yes | **Low** | **Phase 1. Start here.** |
| **B. Web self-serve** | They log into `app.jewelindia.shop`, pick a pack, Razorpay Checkout | ✅ Yes | Medium | Phase 3 |
| **C. In-app Apple IAP** | Buy inside the iOS app via StoreKit | ✅ Yes | Medium-high | Phase 4 |

**Route A is genuinely how Indian B2B buys.** It's not a compromise — a wholesaler
spending ₹10,000 wants to talk to a person, ask about a discount, and get a proper
invoice. And it needs almost no build: generate a link, receive a webhook, grant
credits. **You could be taking money within a couple of weeks of starting.**

## 3.3 The technical payment sequence (Route A / B)

```
1. Wholesaler wants credits
       ↓
2. Your system creates a Razorpay Payment Link (or Order) via the Razorpay API
   - amount, currency INR
   - notes: { wholesaler_id, pack_key, credits }
   - customer: name, email, phone
       ↓
3. A row is written to credit_purchases: status = 'pending'
       ↓
4. Link goes to the wholesaler (WhatsApp / email / on-screen checkout)
       ↓
5. They pay — UPI, card, or netbanking
       ↓
6. Razorpay fires a WEBHOOK to your endpoint:
   POST /razorpay-webhook   event: payment.captured
   Header: X-Razorpay-Signature
       ↓
7. ⭐ Your endpoint VERIFIES THE SIGNATURE (HMAC-SHA256, webhook secret)
   ↳ Invalid signature → reject. This is the security boundary.
       ↓
8. Check provider_txn_id against credit_purchases (UNIQUE)
   ↳ Already processed → return 200, do nothing. (Razorpay retries webhooks.)
       ↓
9. Inside ONE transaction:
   - credit_purchases.status = 'paid'
   - create a credit_lot (credits, expires_at = NULL)
   - insert a credit_ledger row (kind='grant')
   - update credit_accounts.balance_cached
       ↓
10. Generate + email the GST invoice
       ↓
11. Wholesaler's app refreshes → new balance. Done.
```

**Two things in that flow are the whole security model:**

- **Step 7 — signature verification.** Without it, anyone who finds your webhook
  URL can POST a fake "payment succeeded" and mint themselves unlimited credits.
- **Step 8 — the unique transaction id.** Razorpay retries webhooks on any
  non-200. Without this check, one payment grants credits three times.

**Your Razorpay Key Secret must never appear in the iOS app.** Anything shipped in
an app binary is readable. Keys live server-side only — a Supabase Edge Function.

## 3.4 The Apple IAP sequence (Route C, phase 4)

```
1. Wholesaler taps a pack in the app
       ↓
2. StoreKit 2 shows Apple's payment sheet — Apple takes the money
       ↓
3. App receives a signed transaction from Apple
       ↓
4. App sends it to YOUR server for verification
       ↓
5. ⭐ Server verifies with Apple's App Store Server API
   ↳ NEVER trust the client's word that a purchase happened
       ↓
6. Same as steps 8–9 above: dedupe on transaction id, grant credits atomically
       ↓
7. App finishes the transaction with StoreKit
```

Plus **App Store Server Notifications V2** — Apple tells your server when a user
gets a refund, and you claw the credits back.

## 3.5 GST and invoicing — this part is not optional

- **AI/SaaS services attract 18% GST.**
- **Your buyers are GST-registered businesses.** They want a tax invoice carrying
  your GSTIN so they can claim input tax credit. That makes your service
  effectively 18% cheaper for them and it is a genuine selling point.
- **Collect the buyer's GSTIN and state at purchase.** Place of supply decides the
  tax type: same state → CGST + SGST; different state → IGST. Get this wrong and
  their accountant rejects the invoice.
- **Prepaid credits are vouchers under GST**, which affects *when* tax is due —
  possibly at sale, not at redemption. **Get a CA to confirm.** It changes your
  revenue recognition, not just your paperwork.
- **Through Apple, Apple is the merchant of record.** The wholesaler gets an Apple
  receipt, not your GST invoice, and **cannot claim input tax credit**. On ₹5,000
  that's ~₹900 of real cost to them. This is exactly why serious buyers will
  prefer Razorpay — and why Route A stays valuable even after IAP ships.

## 3.6 Razorpay running costs

| Item | Typical |
|---|---|
| UPI | Effectively **0%** — zero-MDR is mandated in India for UPI P2M |
| Cards / netbanking / wallets | **~2%** + 18% GST on that fee |
| Settlement to your bank | **T+2** business days (standard) |
| Refunds | Free to issue; the original fee is usually not returned |

Since most Indian B2B pays by UPI, **your effective payment cost is close to zero**
— compared to Apple's 15%. That's a real reason to push volume to Razorpay.

## 3.7 Refunds, chargebacks, disputes

| Situation | Handling |
|---|---|
| They bought by mistake, credits unused | Refund via Razorpay, remove the lot, ledger row `kind='adjustment'` |
| They bought and already spent the credits | Balance cannot go negative (enforced by the database). Clamp at 0, flag the account `recovery_owed`, block **further purchases** but not usage. **You need to sign off on this policy.** |
| Apple-initiated refund | App Store Server Notification V2 → same claw-back path |
| Chargeback / dispute | Razorpay dashboard; same claw-back; consider blocking the account |
| Generation failed | **Automatic credit refund, no money involved.** Different thing entirely. |

---

# Part 4 — How it gets built

## 4.1 The system, end to end

```
   ┌────────────────┐        ┌────────────────┐        ┌──────────────────┐
   │   iOS app      │        │   Web app      │        │  Your sales team │
   │ (this repo)    │        │ app.jewelindia │        │   (WhatsApp)     │
   └───────┬────────┘        └───────┬────────┘        └────────┬─────────┘
           │  reads balance          │  buys credits            │ sends link
           │  spends credits         │                          │
           ▼                         ▼                          ▼
   ┌──────────────────────────────────────────────────────────────────────┐
   │                         SUPABASE  (source of truth)                  │
   │  ┌────────────────┐  ┌──────────────┐  ┌───────────────────────────┐ │
   │  │ credit_accounts│  │ credit_lots  │  │ credit_ledger (append-only)│ │
   │  └────────────────┘  └──────────────┘  └───────────────────────────┘ │
   │  ┌────────────────┐  ┌────────────────────┐                          │
   │  │ credit_prices  │  │ credit_purchases   │                          │
   │  └────────────────┘  └────────────────────┘                          │
   │                                                                      │
   │  RPCs (SECURITY DEFINER — the only way credits ever move):           │
   │    spend_credits()   refund_credits()   grant_credits()              │
   │                                                                      │
   │  Edge Functions:                                                     │
   │    razorpay-webhook    apple-iap-verify    expire-credits (cron)     │
   └────────────┬─────────────────────────────────────────┬───────────────┘
                │ mints a one-time job token              │ webhook
                ▼                                         ▼
   ┌────────────────────────────┐              ┌────────────────────┐
   │  AI PIPELINE (separate     │              │     RAZORPAY       │
   │  repo — not ours)          │              │                    │
   │  ⚠️ must verify job token  │              └────────────────────┘
   └────────────────────────────┘
```

## 4.2 Database — five tables

```sql
-- One row per wholesaler. balance_cached is for fast reads; lots are the truth.
credit_accounts (
  wholesaler_id           uuid PRIMARY KEY REFERENCES auth.users(id),
  balance_cached          int NOT NULL DEFAULT 0 CHECK (balance_cached >= 0),
  lifetime_granted        int NOT NULL DEFAULT 0,
  lifetime_spent          int NOT NULL DEFAULT 0,
  low_balance_threshold   int NOT NULL DEFAULT 20,
  low_balance_notified_at timestamptz,
  recovery_owed           int NOT NULL DEFAULT 0,
  updated_at              timestamptz NOT NULL DEFAULT now()
)

-- Every grant creates a lot. Spending consumes lots expiring-soonest-first.
credit_lots (
  id                uuid PRIMARY KEY,
  account_id        uuid NOT NULL REFERENCES credit_accounts,
  source            text NOT NULL,   -- welcome|purchase|referral|promo|refund|admin|subscription
  credits_granted   int  NOT NULL,
  credits_remaining int  NOT NULL CHECK (credits_remaining >= 0),
  granted_at        timestamptz NOT NULL DEFAULT now(),
  expires_at        timestamptz,     -- NULL = never (all purchased credits)
  purchase_id       uuid REFERENCES credit_purchases,
  note              text
)

-- APPEND ONLY. Never UPDATE. Never DELETE. This is the audit trail.
credit_ledger (
  id              uuid PRIMARY KEY,
  account_id      uuid NOT NULL,
  lot_id          uuid,
  delta           int  NOT NULL,     -- +grant / -spend / +refund / -expiry
  kind            text NOT NULL,     -- grant|debit|refund|expiry|adjustment
  feature_key     text,              -- 'chamak.generate', 'product.upload', ...
  reference_type  text,              -- 'chamak_generation' | 'product' | 'purchase'
  reference_id    text,
  idempotency_key text UNIQUE,       -- ⭐ prevents EVERY double-charge bug
  balance_after   int NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),
  metadata        jsonb              -- ⭐ real AI cost goes here, for your margin data
)

-- The rate card. The app READS this. Prices are never hardcoded in Swift.
credit_prices (
  feature_key   text PRIMARY KEY,    -- 'chamak.generate'
  credits       int  NOT NULL,
  label         text NOT NULL,       -- 'Chamak Fusion'
  description   text,
  is_active     bool NOT NULL DEFAULT true,
  updated_at    timestamptz
)

-- Money in, both rails.
credit_purchases (
  id              uuid PRIMARY KEY,
  account_id      uuid NOT NULL,
  provider        text NOT NULL,     -- razorpay|apple|manual
  provider_txn_id text UNIQUE,       -- ⭐ prevents receipt replay & webhook retries
  pack_key        text NOT NULL,
  credits         int  NOT NULL,
  amount_inr      numeric(10,2),
  gst_inr         numeric(10,2),
  buyer_gstin     text,
  buyer_state     text,
  invoice_number  text UNIQUE,
  status          text NOT NULL,     -- pending|paid|failed|refunded|chargeback
  receipt_json    jsonb,
  created_at      timestamptz,
  settled_at      timestamptz
)
```

**Row-level security on all five: the app can `SELECT` its own rows and nothing
else. No client `INSERT`. No client `UPDATE`. Ever.** If the iOS app can write to
`credit_lots`, the currency is worthless — anyone who extracts the anon key from
the app binary can mint credits.

## 4.3 The three functions that move credits

Everything goes through these. They run `SECURITY DEFINER` (elevated) and are the
only path by which any number changes.

### `spend_credits(feature_key, reference_id, idempotency_key)`

One transaction:

1. **Check the idempotency key.** Already seen? Return the original result. This is
   what makes a double-tap, a network retry, and an app relaunch all safe.
2. **Look up the price from `credit_prices`.** The server decides the price. The
   client's opinion about cost is never trusted.
3. **Lock the wholesaler's lots** — `SELECT ... FOR UPDATE`, ordered by expiry,
   soonest first, skipping expired ones.
4. **Not enough?** Return `INSUFFICIENT_CREDITS`. Nothing changes.
5. **Enough?** Decrement lots in order, write ledger rows, update the cached
   balance.
6. **Mint a one-time job token** for the AI pipeline (see 4.4).
7. Return new balance + token.

The row lock in step 3 is what makes this safe against double-taps, two devices,
and race conditions. Not a check in Swift — a lock in the database.

**Negative balances are impossible by construction:** the `CHECK (>= 0)`
constraints are the backstop and the row lock is the mechanism.

### `refund_credits(reference_id, reason)`

- Called **by the backend**, never by the app. (A client that can request refunds
  is a free-credits API.)
- Triggered when `chamak_generations.status` flips to `failed`, or on a pipeline
  timeout.
- Idempotency key `refund:{generation_id}` — can't double-refund.
- Refunds into a **new lot** with the original expiry (or +30 days if that's
  already past). Never resurrects a spent lot.
- Shows in history as *"Refunded — generation failed · +10"*. **Visible refunds
  build far more trust than invisible reservations.**

### `grant_credits(account, credits, source, expires_at, reference)`

- Called by the Razorpay webhook, the Apple verifier, the welcome-grant trigger,
  referral triggers, and admin support actions.
- Always idempotent on a key.
- Admin use writes an operator id into `metadata` — every goodwill grant is
  attributable to a person.

## 4.4 ⚠️ The security problem that blocks everything

**Right now the AI pipeline is unauthenticated HTTP.** Your own spec says so
(`_spec/04-data-contracts.md:1326`). Anyone who watches the app's network traffic
once can call `POST {AI_PIPELINE}/api/chamak/generate` directly, forever, free.

**Deducting credits in Supabase and then calling an open endpoint means the
deduction is advisory.** The credit system would be a user interface, not a
control. Whoever owns that pipeline needs to hear this now, not during
implementation.

Two fixes:

**Option A — Job tokens (correct).**
`spend_credits` mints a single-use, short-lived token. The app passes it to the
pipeline. **The pipeline verifies the token and marks it consumed before doing any
work.** No token, no generation. Requires a change in the pipeline repo — a
cross-team dependency to raise immediately.

**Option B — Route through Supabase (interim).**
The app calls a Supabase Edge Function with its login token; the function deducts
credits and then calls the pipeline server-side. The pipeline URL stops being
something the app ever knows. Weaker (still open if the URL leaks) but ships
without touching their repo.

**Also fix while you're there:** the admin APIs have no authentication either
(`_spec/04-data-contracts.md:1369`). Once an admin "grant credits" endpoint
exists, that becomes a way for anyone to mint money.

## 4.5 What gets built in the iOS app

New files (roughly):

| File | Purpose |
|---|---|
| `Features/Wholesaler/TreasureChest/TreasureChestView.swift` | The wallet screen |
| `Features/Wholesaler/TreasureChest/TreasureChestModels.swift` | Balance, lot, ledger entry, price types |
| `Features/Wholesaler/TreasureChest/TransactionHistoryView.swift` | The ledger list |
| `Features/Wholesaler/TreasureChest/InsufficientCreditsSheet.swift` | The recovery sheet |
| `Features/Wholesaler/TreasureChest/CreditBalancePill.swift` | Toolbar balance chip |
| `Features/Wholesaler/TreasureChest/TreasureChestCard.swift` | Home screen card |
| `Networking/CreditsAPI.swift` | Calls the RPCs |
| *(phase 4)* `Networking/StoreKitManager.swift` | Apple purchases |

Changes to existing files:

| File | Change |
|---|---|
| `Navigation/WholesalerShell.swift` | Balance pill in the toolbar, next to the profile menu |
| `Features/Wholesaler/WholesalerHomeView.swift` | Treasure Chest card between hero and Insights |
| `Features/Wholesaler/Chamak/ChamakViewModel.swift` | Replace `showQuotaAlert` with real credit checks |
| `Features/Wholesaler/Chamak/ChamakSliderFormView.swift` | Button becomes "Fuse · 10 credits" |
| `Features/Wholesaler/Chamak/ChamakResultView.swift` | Re-roll shows its cost |
| `Features/Wholesaler/AddProductForm.swift` | Cost shown once past the free allowance |
| `Core/Copy.swift` | All the new strings |

**Two rules for the iOS side:**

1. **Never hardcode a credit price.** Read `credit_prices`. Otherwise a price change
   needs an App Store release.
2. **The local balance is display only.** Refetch on wallet open, on flow entry, and
   after every spend. The server is always right.

---

# Part 5 — What the wholesaler actually sees

## 5.1 The balance pill — everywhere

A small pill in the top-right toolbar, beside the existing profile menu, on every
wholesaler screen. Shows the number. Turns amber when low. Tapping opens the
Treasure Chest.

**This is the "currency in every flow" piece** — the balance is never more than a
glance away.

## 5.2 The home screen card

Today: hero → Insights (4 stat cards) → Chamak card → catalogue.

The wallet is **not** a KPI, so it shouldn't become a fifth stat card. It gets its
own card **between the hero and "Insights"**: treasure chest artwork, the balance
large, a thin "X expiring in Y days" line when relevant, and a **Top Up** button.
Gold/amber accents against the cream palette so it reads as *treasure*, visibly
different from the monochrome KPI cards.

## 5.3 The Treasure Chest screen

| Section | Content |
|---|---|
| **Balance hero** | Available credits, large, in the display face used for section headers |
| **Three stats** | Available · Used (lifetime) · Expired. Plus "X expiring in Y days" when true |
| **Top Up** | Primary button → pack sheet (or "contact your account manager" pre-IAP) |
| **What things cost** | The live rate card. Builds trust and doubles as feature discovery |
| **History** | Grouped by date, +/− with a feature icon, Chamak rows show a thumbnail of the result. Filters: All / Spent / Added / Expired. Paginated |

## 5.4 Inside each flow

| Moment | Treatment |
|---|---|
| Before entering Chamak | Cost chip on the Chamak card: **"10 credits"** |
| The action button | **"Fuse · 10 credits"** — one tap, cost stated. **Not** a confirm dialog; a dialog on every generation is exhausting |
| Right after | Toast: **"−10 credits · 90 left"** |
| Not enough credits | A **sheet**, not an alert: how short they are, the packs, top-up CTA. **Their sliders and note must survive** — they come straight back to where they were |
| Generation failed | Failure message **+** the refund visible in history |
| Running low | Home banner + amber pill, fired **once per threshold crossing** (`low_balance_notified_at` stops the nagging, resets on top-up) |

## 5.5 Low balance notification — a scoping note

Your brief asks for a notification below a threshold. **The app has no push
notification infrastructure today** — no entitlements file, no APNs setup, nothing.
So:

- **v1: in-app banner + amber pill.** Ships with everything else, costs nothing extra.
- **v2:** local notification.
- **v3:** real push — needs an entitlements file, the Push Notifications capability,
  an APNs key, and a backend sender. **This is real work; don't let it get scoped
  into v1 by accident.**

Default threshold: 20 credits — but make it *dynamic*: **"less than 2 fusions
left"** is a better trigger than a fixed number and it survives price changes.

---

# Part 6 — Who needs to do what

Three checklists. **Yours has the longest lead times, so start it first** — most
of it can run in parallel with the build, but none of it can be rushed at the end.

## 6.1 ✅ YOUR checklist (business — start now)

### Legal & financial entity
- [ ] **Registered business entity** — Pvt Ltd / LLP / Proprietorship. Needed for Razorpay and for Apple.
- [ ] **Business PAN**
- [ ] **GSTIN** — required to issue tax invoices. Without it your buyers can't claim input tax credit, which makes you 18% more expensive than a competitor who has one.
- [ ] **Current account** for settlements
- [ ] **A CA engaged** on two specific questions: (a) GST treatment of prepaid credits as vouchers — is tax due at sale or at redemption? (b) revenue recognition for unspent credits (they're a liability, not revenue).

### Razorpay
- [ ] **KYC completed, account in live mode** — needs PAN, GSTIN, bank proof, address proof, business proof
- [ ] **Live API keys generated** — Key ID + **Key Secret**
- [ ] ⚠️ **Key Secret handed to the tech team through a secure channel, never over WhatsApp/email, and NEVER put in the mobile app**
- [ ] **Webhook secret** generated and shared the same way
- [ ] **Public policy pages live** — Razorpay requires these before activation: Terms of Service, Refund/Cancellation Policy, Privacy Policy, Contact page. **All three must specifically cover credits**: that they're prepaid, that purchased credits don't expire, that free ones do, and what happens on refund.

### Pricing sign-off
- [ ] **Your real AI cost per generation** — this is the number I'm missing and every margin figure in Part 2 is a placeholder until you supply it. Get it from your AI vendor's billing.
- [ ] **Confirm 1 credit = ₹10**
- [ ] **Confirm the rate card** (fusion = 10, re-roll = 6, upload = 2…)
- [ ] **Confirm the four packs and their bonus percentages**
- [ ] **Confirm the welcome grant = 100 credits / 30 days**
- [ ] **Confirm: purchased credits never expire** (my strong recommendation)

### Apple (only if you want in-app buying — phase 4)
- [ ] **Apple Developer Program, Organization account** — needs a D-U-N-S number, which can take 1–2 weeks on its own
- [ ] **Paid Applications Agreement** signed in App Store Connect
- [ ] **Indian banking + tax forms** completed in App Store Connect
- [ ] **Enrol in the Small Business Program** — this is what takes Apple's cut from 30% to 15%. Easy to miss and it doubles your net.

### Operations
- [ ] **Who handles "my credits didn't arrive"?** — name a person and a response time
- [ ] **Invoice numbering series** decided (e.g. `JI/25-26/0001`)
- [ ] **Refund policy signed off** — specifically: what happens when someone gets a money refund after spending the credits (see 3.7)
- [ ] **Bad-result policy** — the image generated fine but they don't like it. Auto-refund via feedback? Manual on request? Never? **This will be your single most common support ticket.**
- [ ] **Who can issue goodwill credits**, and up to what limit

## 6.2 ✅ TECH checklist

### 🔴 AI pipeline team (separate repo — **THE BLOCKER**)
Raise this first. Everything else can be built while it's in progress, but nothing
can safely go live without it.

- [ ] **Add authentication to the pipeline.** It's currently open HTTP.
- [ ] **Accept and verify a one-time job token** on `/api/chamak/generate` and `/process`; refuse to work without one
- [ ] **Mark tokens consumed** so they can't be replayed
- [ ] **Report actual AI cost/tokens back per generation** — this is how you learn your true margin (bill flat, track real cost)
- [ ] **Report failures clearly and promptly** so automatic refunds trigger
- [ ] **Add authentication to the admin APIs** — currently anyone can call them with service-role powers

### Supabase / backend
- [ ] 5 tables + indexes + RLS (`SELECT` own only, no client writes)
- [ ] `spend_credits()` — with idempotency key, `FOR UPDATE` locking, FIFO-by-expiry, server-side pricing
- [ ] `refund_credits()` — backend-only
- [ ] `grant_credits()` — idempotent
- [ ] Trigger: **welcome grant on onboarding verification**
- [ ] Trigger: **auto-refund when `chamak_generations.status → 'failed'`**
- [ ] `pg_cron` job: **expire lots** — writing a visible ledger row, never silently zeroing
- [ ] Edge Function: **`razorpay-webhook`** — signature verification + `provider_txn_id` dedupe + atomic grant
- [ ] Edge Function: **`create-payment-link`** — creates the Razorpay link with `notes.wholesaler_id`
- [ ] Edge Function: **job token minting + verification**
- [ ] *(phase 4)* Edge Function: **`apple-iap-verify`** + App Store Server Notifications V2 handler
- [ ] Seed `credit_prices` with the rate card
- [ ] Invoice generation + email

### iOS (this repo)
- [ ] `CreditsAPI.swift` — balance, history, rate card, spend
- [ ] Treasure Chest screen + models + history list
- [ ] Balance pill in `WholesalerShell` toolbar
- [ ] Treasure Chest card on `WholesalerHomeView`
- [ ] Cost chips + `"Fuse · 10 credits"` button in the Chamak flow
- [ ] Insufficient-credits sheet **that preserves flow state**
- [ ] Low balance banner + amber pill
- [ ] Replace `ChamakViewModel.showQuotaAlert` with real credit handling
- [ ] Handle offline: show last known balance with an "as of" time, block spending
- [ ] *(phase 4)* StoreKit 2 consumables + server verification
- [ ] ⚠️ **Never hardcode a price. Never trust the local balance. Never call refund from the client.**

### Web (`app.jewelindia.shop`)
- [ ] Buy-credits page with Razorpay Checkout
- [ ] Server-side order creation carrying `notes.wholesaler_id`
- [ ] **GSTIN + state collection at checkout** (needed for a valid invoice)
- [ ] The same wallet view as the app, so balances never disagree
- [ ] Invoice download

### Internal tools
- [ ] Admin: view any wallet, issue goodwill credits (**behind real auth**)
- [ ] Reconciliation view: Razorpay settlements vs `credit_purchases`
- [ ] Margin dashboard: credits charged vs actual AI cost, per generation and per wholesaler

## 6.3 ✅ What the WHOLESALER needs

Deliberately short — friction here costs you sales.

**To use credits:**
- [ ] A verified account (which unlocks the 100 free credits)
- [ ] Nothing else. Free credits are automatic.

**To buy credits:**
- [ ] A payment method — UPI, card, or netbanking
- [ ] **Their GSTIN**, if they want to claim input tax credit (optional, but most will)
- [ ] **Their state**, for correct tax on the invoice
- [ ] The phone/email on their account matching the payment, so it links automatically

**What they need to understand** (this is a communication job, not a build job):
- Credits are prepaid, like a recharge
- **Purchased credits never expire.** Free ones do — say this loudly and early
- What each action costs, before they tap
- Failed generations are refunded automatically, no ticket needed
- The invoice arrives by email

---

# Part 7 — Build order

| Phase | What | Blocked by | Ship-able alone? |
|---|---|---|---|
| **0** | 🔴 **Pipeline authentication + job tokens** | Pipeline team | Prerequisite for going live |
| **1** | Ledger, RPCs, rate card, wallet UI (balance + history + stats). **Free grants only — nothing metered, nothing sold.** | — | ✅ Yes |
| **2** | **Meter Chamak.** Cost chips, spending, auto-refunds, insufficient sheet. Instrument everything. | 0, 1 | ✅ Yes |
| **3** | **Razorpay money in** — payment links + webhook + GST invoices. Sales-assisted (Route A). | 1, 2, your KYC | ✅ Yes |
| **4** | Web self-serve checkout, then in-app Apple IAP | 3, Apple account | ✅ Yes |
| **5** | Subscriptions, referral payouts, push notifications, featured placement | 1–4 + real usage data | — |

**Two things about this order:**

**Phases 1 and 2 are worth shipping even if you never sell a single credit.** The
ledger tells you your real cost per wholesaler and your real margin per
generation. Right now you don't have that number, and you can't price anything
correctly without it.

**Don't build the store before you know the consumption curve.** Ship 1 and 2,
watch three to four weeks of real usage, *then* finalise pack sizes. Guessing how
much wholesalers consume is how you end up with a ₹999 plan that costs ₹1,400 to
serve.

---

# Part 8 — What it costs you to run

| Item | Cost |
|---|---|
| AI generation | **Your COGS — the number I still need** |
| Razorpay — UPI | ~0% (zero-MDR mandated in India) |
| Razorpay — cards/netbanking | ~2% + 18% GST on the fee |
| Apple IAP | 15% (Small Business Program) |
| Supabase | Already paying; the ledger is small |
| Free welcome grants | 100 credits × new signups × your COGS |
| Free daily upload allowance | Existing cost, unchanged |
| Support | Real. Budget a person's time from day one of taking money |

**Blended, if most volume goes through UPI on Razorpay, your payment cost is close
to zero.** That's a strong argument for keeping Route A (sales-assisted links)
alive permanently, even after in-app purchase ships.

---

# Part 9 — What can go wrong

| Risk | Severity | Handling |
|---|---|---|
| **Pipeline stays unauthenticated** | 🔴 Critical | Credits become decoration. Phase 0 is not optional. |
| **Webhook signature not verified** | 🔴 Critical | Anyone can mint credits with a fake webhook. Non-negotiable. |
| **Razorpay Key Secret ends up in the app** | 🔴 Critical | App binaries are readable. Server-side only. |
| Webhook retried, credits granted twice | 🟠 High | `provider_txn_id UNIQUE` |
| Double-tap charges twice | 🟠 High | `idempotency_key UNIQUE` |
| **Usage collapses once metering starts** | 🟠 High | Today Chamak is effectively free. Generous welcome grant, free analysis, and **instrument before and after** so you can tell "priced too high" from "wasn't that valuable". |
| **Metering uploads shrinks catalogues** | 🟠 High | Catalogues are the product. Keep the free daily allowance generous. |
| GST treatment wrong | 🟠 High | CA sign-off before the first sale |
| Refund after credits spent | 🟡 Medium | Clamp at zero, `recovery_owed` flag — **needs your policy decision** |
| Welcome-grant farming | 🟡 Medium | Grant on *verified* onboarding, unique phone, one per business |
| Balances disagree between app and web | 🟡 Medium | Single source of truth in Supabase, refetch aggressively |
| Ledger grows large | 🟢 Low | Index `(account_id, created_at DESC)`, paginate, roll up after a year |

---

# Part 10 — Decisions I need from you

Ordered by how much they block the work.

### 🔴 Blocking
1. **What does one Chamak generation actually cost you?** Every margin number in
   this document is a placeholder until you give me the real AI vendor figure.
2. **Who owns the AI pipeline repo, and can they add authentication?** This gates
   going live. If the answer is "no" or "not soon", we ship Option B in 4.4 instead.
3. **Which of these exist today** — registered entity, GSTIN, Razorpay KYC completed
   in live mode, Apple Developer Organization account?

### 🟠 Needed before building
4. **Do credits replace the daily upload limit, or sit on top of it?** I've assumed
   on top — free allowance stays, credits handle overflow and premium features.
5. **Which Razorpay product is your existing page** — Payment Page, Payment Link, or
   a Checkout integration? This decides how much of Part 3 already exists.
6. **Is the web dashboard still actively used by wholesalers?** If most of them live
   on the web, purchase belongs there first and Apple IAP can wait a long time.
7. **Sign off the rate card and packs** in Part 2.

### 🟡 Needed before launch
8. **Refund policy when money is refunded after the credits were spent** (3.7).
9. **Bad-result policy** — generation succeeded, they don't like it. Auto-refund via
   the feedback flow, manual on request, or nothing? This will be your most common
   support ticket, so decide it before it arrives.
10. **Do purchased credits expire?** My strong recommendation is no. Confirm.
11. **Naming** — Ratti / Karat / Credits? "50 Ratti in your Treasure Chest" reads
    beautifully for a jewellery platform, and every jeweller knows the unit.

---

# Appendix — The one-page summary

| Question | Answer |
|---|---|
| **What is a credit worth?** | ₹10, fixed |
| **What does a Chamak fusion cost?** | 10 credits (₹100) |
| **What's free?** | Analysis, chat, orders, invites, browsing, re-downloads, and a daily upload allowance |
| **What do new users get?** | 100 credits, valid 30 days |
| **Do purchased credits expire?** | No. Only free ones do |
| **How do they pay?** | Razorpay — payment link over WhatsApp first, web checkout later, Apple IAP last |
| **Why not Razorpay inside the app?** | Apple forbids it for digital goods. Not a technical limit |
| **Where does the truth live?** | Supabase — an append-only ledger, behind functions the app cannot bypass |
| **Can the balance go negative?** | No. Prevented by database constraints, not by app logic |
| **What happens when a generation fails?** | Automatic refund, visible in history, no ticket |
| **What's the biggest risk?** | The AI pipeline is unauthenticated. Fix that first |
| **What's the biggest unknown?** | Your real cost per generation |
