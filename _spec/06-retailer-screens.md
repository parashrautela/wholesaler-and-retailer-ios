# 06 — Retailer Flow: Screen-by-Screen Inventory

Source root: `/Users/parashrautela/Documents/jewel india /Jewel-India-Frontend`
Backend: Supabase `https://ljxgwiuvdpuarvdszjts.supabase.co` · Site: `https://app.jewelindia.shop`

---

## 0. SCOPING VERDICT — is the employee dashboard part of the retailer product?

**YES. A verified retailer lands on `/dashboard/employee` by default, NOT `/dashboard/retailer`.**

Evidence, `lib/supabase/middleware.js` lines 25–48 (`getRetailerDestination`):

```js
if (retailer.verification_status === "verified") {
  const viewMode = request?.cookies.get("jewel_view_mode")?.value;
  if (viewMode === "retailer") {
    return "/dashboard/retailer";
  }
  return "/dashboard/employee";
}
```

Identical logic in `lib/actions/auth.js` lines 41–65 (server-action `getRetailerDestination`, reads the cookie via `next/headers`).

Reinforced by a hard guard, `lib/supabase/middleware.js` lines 92–96:

```js
if (pathname.startsWith("/dashboard/retailer")) {
  const viewMode = request.cookies.get("jewel_view_mode")?.value;
  if (role === "retailer" && viewMode !== "retailer") {
    return redirect("/dashboard/employee");
  }
```

And `app/onboard-retailer/submitted/page.jsx` line 29–31: once `verification_status === "verified"`, the submitted page redirects to **`/dashboard/employee`**.

Consequences for the iOS port:

- The cookie `jewel_view_mode` is `httpOnly`, `path=/`, `sameSite=lax`, `secure` in prod, `maxAge = 604800` (7 days). It is **never set at signup**, so a brand-new verified retailer has no cookie → default destination is the employee dashboard.
- The only way to reach `/dashboard/retailer` is to POST `/api/auth/toggle-view` with `{"mode":"retailer"}` (the "Take me to dashboard" button in the employee bottom nav), or to already hold the cookie.
- Going the other way (`{"mode":"employee"}`) additionally **auto-provisions a "virtual employee" row** for the retailer (see §13.1).
- Therefore §13–§18 (employee dashboard) are inventoried at full detail as part of the retailer-facing product.

Non-goal check: `role === "employee"` users (created by a retailer via AddEmployeeModal) share these employee screens but are a distinct login. Screens are identical except the `isRetailer` flag (badge + "Take me to dashboard" pill).

### 0.1 Full ordered route map of the retailer flow

| # | Route | File | Auth |
|---|---|---|---|
| 1 | `/join/[code]` | `app/join/[code]/page.jsx` | public |
| 2 | `/join/[code]` (404) | `app/join/[code]/not-found.jsx` | public |
| 3 | `/onboard-retailer` | `app/onboard-retailer/page.jsx` | session, no role gate |
| 4 | `/onboard-retailer/step2` | `app/onboard-retailer/step2/page.jsx` | session |
| 5 | `/onboard-retailer/step3` | `app/onboard-retailer/step3/page.jsx` | session |
| 6 | `/onboard-retailer/submitted` | `app/onboard-retailer/submitted/page.jsx` | session + retailer row |
| 7 | `/dashboard/employee` | `app/dashboard/employee/page.jsx` | verified retailer, no `jewel_view_mode=retailer` |
| 8 | `/dashboard/employee/wholesaler-gallery` | `.../wholesaler-gallery/page.jsx` | same |
| 9 | `/dashboard/employee/playground` | `.../playground/page.jsx` | same |
| 10 | `/dashboard/employee/playground/review` | `.../playground/review/page.jsx` | same |
| 11 | `/dashboard/retailer` | `app/dashboard/retailer/page.jsx` | verified retailer + `jewel_view_mode=retailer` |
| 12 | `/dashboard/retailer?modal=add-employee` | `components/retailer/AddEmployeeModal.jsx` | same |
| 13 | `/dashboard/retailer/employees` | `.../employees/page.jsx` | same |
| 14 | `/dashboard/retailer/catalogue` | `.../catalogue/page.jsx` | same |
| 15 | `/dashboard/retailer/catalogue/upload` | `.../catalogue/upload/page.jsx` | same |
| 16 | `/dashboard/retailer/catalogue/upload/success` | `.../upload/success/page.jsx` | same (**unreachable**, see §11.6) |
| 17 | `/dashboard/retailer/your-taste` | `.../your-taste/page.jsx` | same |
| 18 | `/dashboard/retailer/theme` | `.../theme/page.jsx` | same |
| 19 | `/get-app` | `app/get-app/page.jsx` | public |

### 0.2 Global "no sort control" note

**There is no sort control anywhere in the entire retailer flow.** Not on the retailer catalogue, not on Your Taste, not on the marketplace (wholesaler gallery), not on employees. Every list is server-ordered `created_at DESC` (or, on the employee home, a deterministic LCG shuffle). Do not build a sort UI for parity.

---

## 1. SCREEN — Referral landing `/join/[code]`

**Files**
- `app/join/[code]/page.jsx` (server, 54 lines)
- `app/join/[code]/JoinLandingClient.jsx` (client, 56 lines)
- `app/join/[code]/joinLanding.module.css` (128 lines)
- Validated by `app/api/referral/validate/route.js`
- Link produced by `components/wholesaler/referral/ReferralManager.jsx` + `app/api/referral/generate/route.js`

**Purpose** — The public entry point a retailer arrives through when a verified wholesaler shares a referral link. Stores the referral code in `sessionStorage` and forwards to signup.

### 1.1 Server behaviour

```js
const baseUrl = process.env.NEXT_PUBLIC_SITE_URL?.replace(/\/$/, "") || "http://localhost:3000";
const res = await fetch(`${baseUrl}/api/referral/validate?code=${encodeURIComponent(code)}`, { cache: "no-store" });
if (res.ok) { const json = await res.json(); if (json.valid) referralData = json; }
if (!referralData) notFound();
```

`generateMetadata` → title `"You've been invited — Jewel India"`, description `` `Join via referral code ${code} to get started as a retailer.` ``

Middleware allows this route pre-auth (`preAuthRoutes` includes `"/join"`, `lib/supabase/middleware.js` line 239).

### 1.2 `GET /api/referral/validate?code=<code>` contract

Success `200`:
```json
{ "valid": true, "code": "PJ-a8k3x2", "wholesaler_name": "…", "business_name": "…", "business_logo_url": "…|null" }
```
Failures (all cause `notFound()`):

| status | body `reason` | trigger |
|---|---|---|
| 400 | `"no_code"` (+ `error: "Referral code is required."`) | missing `code` |
| 404 | `"not_found"` | no `referral_links` row |
| 404 | `"inactive"` | `is_active === false` |
| 404 | `"maxed_out"` | `max_uses !== null && uses_count >= max_uses` |
| 404 | `"wholesaler_not_found"` | wholesaler row missing |
| 404 | `"inactive"` | wholesaler `verification_status !== "verified"` |
| 500 | `"db_error"` / `"server_error"` | Supabase error |

Reads: `referral_links (id, wholesaler_id, code, is_active, uses_count, max_uses)`, `wholesalers (full_name, business_name, business_logo_url, verification_status)`.

### 1.3 Layout & exact styles (from `joinLanding.module.css`)

- `.pageContainer` — `min-height:100vh; width:100vw; display:flex; align-items:center; justify-content:center; padding:24px; overflow-y:auto; font-family:'Inter', sans-serif;` background image `https://res.cloudinary.com/dcs0vuzwg/image/upload/v1777318931/invitation_bg_vlguu6.svg`, `background-size:cover; background-position:center`.
- `.card` — `width:380px; background:#FFFFFF; border-radius:16px; border:2px solid #FFFFFF; box-shadow:0 12px 40px rgba(0,0,0,0.15); overflow:hidden; flex column`.
  - `@media (max-width:1024px)` → `width:420px`
  - `@media (max-width:900px)` → `width:85%`
  - `@media (max-width:768px)` → `width:92%; max-width:420px`
- `.imageSection` — `position:relative; width:100%; aspect-ratio:3/4; min-height:380px`.
- `.cardImage` — `https://res.cloudinary.com/dcs0vuzwg/image/upload/v1777318932/Group_128_1_b9ydgb.png`, `object-fit:cover`.
- `.badge` — top `12px` left `12px`, `background:rgba(255,255,255,0.7); backdrop-filter:blur(4px); color:#111; font-size:13px; font-weight:500; padding:4px 12px; border-radius:20px`. Text: **"Referral"**
- `.textOverlay` — `bottom:20px; left:20px; right:20px`.
- `.name` — `font-family:'Playfair Display', Georgia, serif; font-size:clamp(36px,8vw,48px); font-weight:700; color:#FFFFFF; margin:0 0 4px 0; line-height:1.1`. Value = `wholesalerName.split(" ")[0]`, else `businessName`, else literal `"Your partner"`.
- `.subtitle` — `font-size:clamp(15px,3vw,18px); font-weight:300; color:#FFFFFF`. Text: **"thinks you belong here"**
- `.buttonSection` — `background:#FFFFFF; padding:16px; border-top:1px solid #E5E7EB`.
- `.ctaButton` — `width:100%; height:52px; background:#111; color:#FFF; border:none; border-radius:10px; font-size:16px; gap:4px; transition:opacity 0.2s`; `:hover { opacity:0.85 }`. Two spans: `"Get"` (`font-weight:400`) + `"Started"` (`font-weight:700`) → renders as **"Get Started"**.

### 1.4 Interactions

`useEffect` on mount and again on click:
```js
sessionStorage.setItem("referral_code", code);
sessionStorage.setItem("referral_role", "retailer");
```
Click → `router.push(`/entry_page/signup?ref=${encodeURIComponent(code)}&role=retailer`)`.

The `referral_code` session value is later read in `RetailerStep3Footer` and posted as `referralCode` (§5.5). **iOS port: this must become a persisted app-level value (Keychain/UserDefaults) surviving the whole signup + 3-step onboarding.**

### 1.5 States

- **Loading** — none. Server-rendered; no skeleton, no spinner.
- **Empty** — n/a.
- **Error / invalid** — `notFound()` → §2.
- **Disabled** — none. The CTA is always enabled.
- **Animations** — none except the CSS `opacity` hover transition. No entrance animation.

---

## 2. SCREEN — Invalid invite `/join/[code]` not-found

**File** `app/join/[code]/not-found.jsx` (64 lines, all inline styles, no Tailwind)

- Container: `minHeight:100vh; backgroundColor:#F5F2EB; flex column; align/justify center; padding:24px; fontFamily:var(--font-jost, sans-serif); textAlign:center`.
- Icon disc: `56×56; borderRadius:50%; backgroundColor:#FEE2E2; marginBottom:20px`. Inner SVG `24×24`, `stroke #DC2626`, `strokeWidth 2`: circle r=10, line 12,8→12,12, line 12,16→12.01,16 (alert-circle).
- H1: `fontSize:22px; fontWeight:700; color:#111111; marginBottom:8px` — **"Invalid or Expired Invite"**
- P: `fontSize:14px; color:#6B7280; maxWidth:340px; lineHeight:1.6; marginBottom:28px` —
  **"This referral link is no longer valid — it may have expired, been deactivated, or already reached its usage limit."**
- Link → `/entry_page/signup`: `height:44px; padding:0 24px; backgroundColor:#1A1A1A; color:#FFFFFF; borderRadius:8px; fontSize:14px; fontWeight:600; gap:8px` — **"Go to Sign Up"**

No loading/empty/error/disabled variants. No animations.

---

## 3. SHARED — Retailer onboarding chrome

Used by screens §4, §5, §6. Files: `components/onboard/OnboardLayout.jsx`, `OnboardNavbar.jsx`, `LeftPanel.jsx`, `StepIndicator.jsx`, `ImageUploadBox.jsx`. Wrapper: `app/onboard-retailer/layout.jsx`.

### 3.1 `app/onboard-retailer/layout.jsx`

```jsx
<div className="theme-retailer min-h-screen flex flex-col">
  <RetailerOnboardProvider>
    <div className="onboard-page-transition flex-1 flex flex-col w-full">{children}</div>
  </RetailerOnboardProvider>
</div>
```

- `.theme-retailer` forces **`font-family: "Satoshi", var(--font-satoshi), sans-serif !important`** on the container, `button`, `input`, `select`, `textarea`, `h1`–`h6`, `[class*="font-cirka"]`, `.title-font`, `.cirka-title` (`app/globals.css` 313–328). The entire retailer surface is Satoshi — no serif.
- `.onboard-page-transition` — `animation: onboardFadeIn 350ms cubic-bezier(0.16, 1, 0.3, 1) forwards`; keyframes `from { opacity:0; transform:translateY(8px) } to { opacity:1; transform:translateY(0) }`. Disabled under `prefers-reduced-motion: reduce`.

### 3.2 `RetailerOnboardContext` (`context/RetailerOnboardContext.jsx`)

In-memory only (`useState`; **no persistence** — a refresh wipes every field and every picked file).

| Step | Field | Initial |
|---|---|---|
| 1 | `name` | `""` |
| 1 | `aadhar` | `""` |
| 1 | `frontImage` | `null` (File) |
| 1 | `backImage` | `null` (File) |
| 2 | `businessName` | `""` |
| 2 | `selectedState` | `""` |
| 2 | `selectedCity` | `""` |
| 2 | `cities` | `[]` (declared, **never used**) |
| 2 | `logoImage` | `null` (File) |
| 3 | `panFile` | `null` (File\|PDF) |
| 3 | `gstFile` | `null` (File\|PDF) |
| — | `isSubmitting` | `false` |
| — | `submitError` | `null` |

Throws `"useRetailerOnboard must be used within RetailerOnboardProvider"` outside the provider.

### 3.3 `OnboardLayout`

```
<div className="min-h-screen bg-[#FFFFFF] flex flex-col font-sans antialiased text-[#374151]">
  <OnboardNavbar backRoute={…} />
  <main className="flex-1 w-full max-w-[1100px] mx-auto px-[clamp(16px,3vw,48px)] pt-[clamp(24px,3vw,40px)] pb-2
                   flex flex-col md:flex-row md:justify-center md:items-start gap-8 md:gap-[clamp(24px,1vw,48px)]">
    <div className="w-full md:w-[340px] shrink-0 pt-2 flex flex-col items-center md:items-start text-center md:text-left">
      <LeftPanel … />
    </div>
    <div className="w-full md:w-[500px] flex flex-col items-center md:items-start min-h-[400px]">{children}</div>
  </main>
</div>
```

Two-column at `md` (≥768px), stacked below.

### 3.4 `OnboardNavbar`

`<header className="w-full bg-[#FFFFFF] border-b border-[#E0E0E0] px-[clamp(16px,3vw,48px)] py-[clamp(6px,0.8vw,12px)] flex items-center justify-between shadow-sm z-10">`

- **Left "Back" button** — chevron-left SVG `clamp(14px,1.5vw,16px)` `#374151`, label **"Back"** at `clamp(12px,1.4vw,14px)`, `font-medium`, `tracking-wide`, pill `px-3 py-1.5 rounded-full hover:bg-gray-100`.
  **Destructive**: `handleBack` calls `supabase.auth.signOut()` then `router.push(backRoute || '/signup')`. Pressing Back at any onboarding step **signs the user out**.
- **Right "Sign out" button** — user-circle SVG + label **"Sign out"**, same type scale. Also `signOut()` then `router.push('/signup')` (hardcoded `/signup`, not `/entry_page/signup`).

`backRoute` per step: step1 → `/entry_page/signup`, step2 → `/onboard-retailer`, step3 → `/onboard-retailer/step2`.

### 3.5 `LeftPanel`

- Logo row: `<img src="/jewelLogo.svg" alt="Jewels India Logo" className="w-[clamp(28px,3vw,36px)] h-auto object-contain shrink-0" />` + span **"Jewels India"** `clamp(15px,1.6vw,18px)` `font-extrabold` `#111827` `tracking-wide`. Gap `12px`.
- Container gap `16px` mobile / `18px` at `md`; `max-w-[320px]`.
- H1: `text-[clamp(16px,1.8vw,23px)] tracking-tight whitespace-nowrap leading-[1.2] font-extrabold text-[#111827]`.
- P: `text-[clamp(13px,1.3vw,14px)] text-[#9CA3AF] leading-relaxed font-medium`.
- `textMarginTop` prop applies an extra class (step3 passes `md:mt-[18px]`).

### 3.6 `StepIndicator`

- Progress % = `((step - 1) / totalSteps) * 100`, clamped ≥0; `step >= 4` → `100`.
  With `totalSteps = 3`: step1 = 0%, step2 = 33.33%, step3 = 66.67%, step4 (submitted) = 100%.
- Initial width read from `sessionStorage["onboarding_last_step"]` so the bar animates *from* the previous step; falls back to `getPercentageForStep(currentStep - 1)`. Writes `onboarding_last_step` = current step on mount.
- Label row `text-[13px] text-[#9CA3AF] font-semibold uppercase tracking-widest`:
  - `currentStep <= totalSteps` → `<span className="font-extrabold text-[#111827]">Step {n}</span> of 3` → **"Step 1 of 3"**, **"Step 2 of 3"**, **"Step 3 of 3"**
  - else → **"Verification Progress"** (`font-extrabold text-[#111827] tracking-wider`)
- Track: `w-full h-[6px] bg-[#E5E7EB] rounded-full overflow-hidden`. Fill: `bg-[#111827] rounded-full`, `transition: width 800ms cubic-bezier(0.25, 1, 0.5, 1), box-shadow 400ms ease-out`.
- Micro-interaction: at **850 ms** the label gets `scale-[1.01] opacity-95 text-[#6B7280]` with `transform 400ms cubic-bezier(0.34,1.56,0.64,1), opacity 400ms ease`, `transform-origin: left center`.
- On step 4 only: at **800 ms** the fill gains `shadow-[0_0_8px_rgba(17,24,39,0.25)]`.
- Container gap `14px` (`gap-3.5`), `select-none`.

### 3.7 `ImageUploadBox` (all 5 uploads in onboarding use it)

Props: `label`, `image`, `onUpload`, `onRemove`, `error`, `objectFit = "cover"`, `accept = "image/jpeg, image/png, image/webp"`, `aspectRatio = "aspect-square"`.

- Label span: `text-[13px] font-semibold text-[#374151]`. Container gap `8px`.
- Drop area: `w-full bg-[#EEF4FF] rounded-[12px] hover:bg-blue-50 transition-colors cursor-pointer aspect-square relative overflow-hidden flex items-center justify-center` plus border state:
  - has image → `border-[2px] border-solid border-[#22C55E]`
  - error → `border-[1.5px] border-dashed border-[#EF4444]`
  - default → `border-[1.5px] border-dashed border-[#2563EB]`
- **Empty state** — centered `w-12 h-12 rounded-full border-2` ring, `#2563EB` normally / `#EF4444` on error, containing a `26×26` plus icon (`M12 4v16m8-8H4`, strokeWidth 2). No text.
- **Filled (image)** — `<img>` `w-full h-full object-cover`, or with `objectFit="contain"` → `w-full h-full object-contain p-4`. Preview via `URL.createObjectURL`, revoked on change.
- **Filled (PDF)** — red `42×42` document icon (`text-red-500`, strokeWidth 1.5) + filename span `text-[11px] font-medium text-[#6B7280] text-center max-w-[120px] truncate px-2`.
- **Remove button** — `absolute top-2 right-2 w-7 h-7 bg-white rounded-full shadow-sm text-[#6B7280] hover:text-black z-10`, `14×14` X icon strokeWidth 3. Clears `input.value` too.
- Clicking the box only opens the picker **when empty** (`if (!hasImage && inputRef.current) inputRef.current.click()`). To replace a file the user must remove it first.
- Error text: `text-[12px] text-[#EF4444] mt-1`.

**iOS note:** no client-side file-size or dimension validation, no camera-vs-library choice, no crop. `accept` is the only filter.

---

## 4. SCREEN — Onboarding Step 1 `/onboard-retailer`

**Files** `app/onboard-retailer/page.jsx` · `components/onboard-retailer/step1/RetailerStep1Container.jsx` · `RetailerIdentityForm.jsx` · `RetailerAadharUpload.jsx`

**Metadata** `{ title: "Step 1 of 3 — Retailer Onboarding" }`

**Purpose** — Collect the retailer's personal identity + Aadhaar card images. Nothing is sent to the server here; everything stays in React context until Step 3 submits.

### 4.1 Copy (verbatim)

- LeftPanel heading: **"Let me get to know you"**
- LeftPanel description: **"We need a few details to verify who you are. This keeps your account and your business safe."**
- Step indicator: **"Step 1 of 3"**
- Field label: **"Name*"** · placeholder **"Priya Sharma"**
- Field label: **"Aadhar Number*"** · placeholder **"**** **** ****"** (literal asterisks, `**** **** ****`)
- Upload labels: **"Aadhar Front*"** and **"Aadhar Back*"**
- Fine print (two lines, `<br />`): **"*Your documents are encrypted and only used for verification."** / **"We never share them."**
- Primary button: **"Next"**

### 4.2 Layout

`RetailerStep1Container` root: `flex flex-col gap-5 w-full mt-4`. Sits inside `<div className="flex flex-col w-full max-w-[500px] mx-auto md:mx-0 mt-8 md:mt-0">` which also holds the StepIndicator.

- `RetailerIdentityForm` root: `flex flex-col gap-6 w-84` (**`w-84` = 21rem = 336px fixed** — note this is narrower than the 500px column and is NOT responsive).
- Aadhaar uploads row: `flex flex-row gap-[clamp(8px,1.5vw,24px)] w-full`, two `flex-1 min-w-0` cells → always side-by-side, even on mobile.
- Footer row: `flex flex-col md:flex-row gap-[clamp(16px,2vw,32px)] w-full items-start`; left cell = fine print (`flex-1 min-w-0 w-full md:w-auto`), right cell = button (`flex-1 … flex justify-end mt-2 md:mt-0`).
- Fine print type: `text-[7px] md:text-[7px] text-black font-bold leading-relaxed pr-2` — **7px**, deliberate.

### 4.3 Inputs — exact styling

Both inputs share:
```
w-full bg-[#F5F5F5] rounded-[8px] outline-none
px-[clamp(10px,1.5vw,16px)] py-[clamp(8px,1.2vw,14px)]
text-[clamp(13px,1.4vw,15px)] text-[#374151] placeholder:text-[#9CA3AF] transition-shadow
```
- normal: `border-none focus:ring-2 focus:ring-black/10`
- error: `border-[1.5px] border-[#EF4444]`

Labels: `text-[13px] font-semibold text-[#374151]`, `htmlFor` = `retailer-name` / `retailer-aadhar`. Field group gap `4px` (`gap-1`).

### 4.4 Input masking / restriction

- **Name** — keystrokes rejected unless the whole value matches `/^[A-Za-z\s]*$/`. Letters and spaces only; digits, hyphens, apostrophes and all non-ASCII (incl. Devanagari) are silently dropped.
- **Aadhar** — `e.target.value.replace(/\D/g,"").slice(0,12)` then `.replace(/(\d{4})(?=\d)/g, "$1 ").trim()` → renders as `1234 5678 9012`. Max 12 digits.

### 4.5 Validation (fires only after first failed "Next")

`submitAttempted` starts `false`; `handleNext` sets it `true` when invalid.

| Rule | Predicate | Error copy | Colour |
|---|---|---|---|
| Name required | `name.trim().length === 0` | **"Name is required"** | `#EF4444`, `text-[12px]` |
| Aadhaar 12 digits | `aadhar.replace(/\s/g,"").length !== 12` | **"Enter a valid 12-digit Aadhar number"** | same |
| Front image | `!frontImage` | **"Please upload Aadhar Front"** | via `ImageUploadBox.error` |
| Back image | `!backImage` | **"Please upload Aadhar Back"** | via `ImageUploadBox.error` |

`isFormValid = isNameValid && isAadharValid && frontImage !== null && backImage !== null`.
There is **no Aadhaar checksum (Verhoeff) validation** — length only.

### 4.6 "Next" button states

```
w-full md:w-[140px] font-extrabold rounded-[10px]
px-4 py-[clamp(10px,1.2vw,14px)] text-[clamp(13px,1.4vw,15px)]
transition-colors tracking-wide
```
- **enabled** → `bg-[#000000] text-white hover:bg-black/90 cursor-pointer`
- **disabled** (`!isFormValid`) → `bg-[#D1D5DB] text-white cursor-not-allowed`, `disabled` attribute set

Enabled click → `router.push("/onboard-retailer/step2")`.
Disabled click → nothing fires (native `disabled`), so **the inline error messages can never appear on this screen** — `setSubmitAttempted(true)` in the else-branch is unreachable. Errors on Step 1 are dead code in practice. (Step 2 and Step 3 have the same structure and the same dead branch.) **iOS parity decision needed:** either replicate the "disabled button, no errors" behaviour, or fix it — flag to the user.

### 4.7 States

- **Loading** — none.
- **Empty** — the default state (upload boxes show the blue `+` ring).
- **Error** — see §4.5 (unreachable in practice).
- **Success** — navigation only, no toast.
- **Disabled** — the Next button until all four fields are satisfied.
- **Animations** — page-level `onboard-page-transition` fade-up 350 ms; StepIndicator bar animates 0% → 0% (no visible change on step 1 unless returning from step 2); upload box border colour transition on fill.

### 4.8 Data

Reads: nothing. Writes: React context only. No network call.

---

## 5. SCREEN — Onboarding Step 2 `/onboard-retailer/step2`

**Files** `app/onboard-retailer/step2/page.jsx` · `components/onboard-retailer/step2/RetailerStep2Container.jsx` · `RetailerBusinessForm.jsx` · `RetailerBusinessLogoUpload.jsx` · `RetailerStep2Footer.jsx`

**Metadata** `{ title: "Step 2 of 3 — Retailer Onboarding" }`

### 5.1 Copy (verbatim)

- Heading: **"Tell us about your store"**
- Description: **"This is how wholesalers will find and recognise your retail store on the platform."**
- Step indicator: **"Step 2 of 3"**
- Label **"Store name*"** · placeholder **"Priya Jewellers"**
- Label **"State*"** · first `<option>` **"select"** (`value=""`, `disabled`)
- Label **"City*"** · placeholder **"select"**
- Upload label: **"Store Logo"** (no asterisk, but it *is* required)
- Fine print: **"*Your documents are encrypted and only used for verification."** / **"We never share them."**
- Button: **"Next"**

### 5.2 Layout

- Container: `flex flex-col gap-[clamp(12px,1.5vw,20px)] w-full mt-4`.
- Form block gap: `clamp(16px,2vw,24px)`.
- Store-name row: name cell is `w-full md:w-[58%] md:flex-none`, plus a `flex-1 min-w-0 hidden md:block` spacer.
- State + City row: `flex flex-row gap-[clamp(8px,1.5vw,24px)] w-full`, both `flex-1 min-w-0` — side-by-side at all widths.
- Logo + button row: `flex flex-col md:flex-row gap-[clamp(8px,1.5vw,24px)] items-start`; logo cell `w-full md:w-[58%] md:flex-none`, button cell `flex-1 min-w-0 w-full flex items-end justify-end self-stretch`.
- Fine print here is `text-[8px] md:text-[8.5px] tracking-tight text-[#000000] font-bold leading-relaxed pr-2 w-full wrap-break-word`, `mt-3`.

### 5.3 Controls — exact styling

**Store name input** — identical recipe to Step 1 inputs (`bg-[#F5F5F5] rounded-[8px]`, etc.), label gap `8px` (`gap-2`).

**State `<select>`** — different recipe (white, bordered):
```
w-full appearance-none bg-[#FFFFFF] rounded-[8px] border outline-none
px-[clamp(10px,1.5vw,16px)] py-[clamp(8px,1.2vw,14px)]
text-[clamp(13px,1.4vw,15px)] text-[#374151] transition-shadow cursor-pointer
```
- normal border `#E5E7EB` + `focus:ring-2 focus:ring-black/10`; error border `#EF4444`
- Custom chevron: absolutely positioned right, `px-4`, `clamp(12px,1.5vw,16px)` square, colour `#374151` when a state is chosen else `#9CA3AF`, `pointer-events-none`.
- Changing state also runs `setSelectedCity("")`.

**29 state options, exact order** (`INDIAN_STATES`, `RetailerBusinessForm.jsx` 3–9):
`Andhra Pradesh, Arunachal Pradesh, Assam, Bihar, Chhattisgarh, Goa, Gujarat, Haryana, Himachal Pradesh, Jharkhand, Karnataka, Kerala, Madhya Pradesh, Maharashtra, Manipur, Meghalaya, Mizoram, Nagaland, Odisha, Punjab, Rajasthan, Sikkim, Tamil Nadu, Telangana, Tripura, Uttar Pradesh, Uttarakhand, West Bengal, Delhi`
(Not alphabetical at the end — Delhi is last. Union territories other than Delhi are absent. No "Ladakh"/"J&K".)

**City** — a **free-text `<input>`**, not a dropdown, despite the `"select"` placeholder and the unused `cities` context array:
```
w-full rounded-[8px] border outline-none px-[clamp(10px,1.5vw,16px)] py-[clamp(8px,1.2vw,14px)]
text-[clamp(13px,1.4vw,15px)] text-[#374151] placeholder:text-[#9CA3AF] transition-shadow
```
- `disabled={!selectedState}` → `bg-[#F9FAFB] border-[#E5E7EB] cursor-not-allowed opacity-80`
- enabled → `bg-[#FFFFFF] border-[#E5E7EB] focus:ring-2 focus:ring-black/10`
- error → `bg-[#FFFFFF] border-[#EF4444]`

**Store logo** — `ImageUploadBox` with `objectFit="contain"` and `aspectRatio="aspect-square"`; contained images get `p-4` padding.

### 5.4 Validation

`isFormValid = businessName.trim().length >= 2 && selectedState !== "" && selectedCity !== "" && logoImage !== null`

| Rule | Error copy |
|---|---|
| `businessName.trim().length < 2` | **"Store name is required"** |
| `selectedState === ""` | **"Please select a state"** |
| `selectedCity === ""` | **"Please enter a city"** |
| `!logoImage` | **"Please upload your store logo"** |

All `text-[12px] text-[#EF4444]`. Same unreachable-error situation as §4.6.

### 5.5 Button

`RetailerStep2Footer` — same base classes as Step 1's Next plus `transition-all` and a horizontal nudge: `transform translate-x-0 md:translate-x-[46px]` (the button is pushed 46px right on desktop). Enabled → `router.push("/onboard-retailer/step3")`.

### 5.6 States & data

- Loading / success / error toasts: none. No network calls.
- **Disabled**: City input until a state is chosen; Next until all four are valid.
- Animations: page fade-up; StepIndicator bar 0% → 33.33% over 800 ms.

---

## 6. SCREEN — Onboarding Step 3 `/onboard-retailer/step3`

**Files** `app/onboard-retailer/step3/page.jsx` · `components/onboard-retailer/step3/RetailerStep3Container.jsx` · `RetailerDocumentUpload.jsx` · `RetailerStep3Footer.jsx`
**API** `app/api/onboard-retailer/submit/route.js`

**Metadata** `{ title: "Step 3 of 3 — Retailer Onboarding" }`

### 6.1 Copy (verbatim)

- Heading: **"Almost there — one last step"**
- Description: **"Upload your PAN and GST certificate so we can verify your business. This is a one-time process."**
- `textMarginTop="md:mt-[18px]"` on the LeftPanel text block (step-3 only).
- Step indicator: **"Step 3 of 3"**
- Upload labels: **"PAN Card*"**, **"GST Certificate*"**
- Fine print (under the PAN box only): **"*Your documents are encrypted and only used for verification."** / **"We never share them."**
- Button: **"Submit"** → while posting **"Submitting..."**

### 6.2 Layout

- Container `flex flex-col gap-8 w-full mt-10`.
- Uploads row `flex flex-row gap-[clamp(8px,3vw,24px)] w-full`, two `flex-1 min-w-0` cells — always side-by-side.
- Footer block `mt-8 w-full`; button wrapper `w-full flex justify-end`.

### 6.3 Upload boxes

Both use `ImageUploadBox` with **`accept="image/jpeg, image/png, image/webp, application/pdf"`** (PDF allowed here only). PDF renders the red doc icon + truncated filename.

Errors: **"Please upload your PAN Card"**, **"Please upload your GST Certificate"**.

### 6.4 Submit button

```
w-full md:w-[160px] font-extrabold rounded-[10px]
px-4 py-[clamp(10px,1.2vw,14px)] text-[clamp(13px,1.4vw,15px)]
transition-all tracking-wide
```
- enabled (`isFormValid && !isSubmitting`) → `bg-[#000000] text-white hover:bg-black/90 cursor-pointer`
- disabled → `bg-[#D1D5DB] text-white cursor-not-allowed`
- `disabled={!isFormValid || isSubmitting}`
- Label swaps to **"Submitting..."**; **no spinner**, text only.

`isFormValid = panFile !== null && gstFile !== null`.

### 6.5 Client-side image compression (`browser-image-compression`)

`compressImage(file, namePrefix)` in `RetailerStep3Footer.jsx`:
- **PDFs are skipped** (`if (file.type === "application/pdf") return file`).
- Base options: `{ maxSizeMB: 1, maxWidthOrHeight: 1200, useWebWorker: true, fileType: "image/jpeg", initialQuality: 0.7 }`
- If `namePrefix` contains `logo` → `maxSizeMB: 0.5`, `maxWidthOrHeight: 800`
- If `namePrefix` contains `pan` or `gst` → `maxSizeMB: 1.5`, `maxWidthOrHeight: 1600`
- Result re-wrapped as `new File([compressed], `${namePrefix}.jpg`, { type: "image/jpeg" })`
- On any failure: `console.warn` and **fall back to the original file** (no user-visible error).
- All five files compressed in parallel via `Promise.all` with prefixes `aadharFront`, `aadharBack`, `panCard`, `gstCert`, `logo`.

**iOS port:** replicate with `UIImage` JPEG re-encode at quality 0.7, longest edge 1200 (logo 800, PAN/GST 1600), and a size ceiling; skip PDFs.

### 6.6 Submission — `POST /api/onboard-retailer/submit`

`multipart/form-data`, exact field names:

| Field | Value |
|---|---|
| `name` | `name` (context) |
| `aadhar` | `aadhar` **with spaces**, e.g. `"1234 5678 9012"` |
| `businessName` | `businessName` |
| `state` | `selectedState` |
| `city` | `selectedCity` |
| `referralCode` | `sessionStorage.getItem("referral_code")` — appended **only if truthy** |
| `aadharFront` | compressed `aadharFront.jpg` |
| `aadharBack` | compressed `aadharBack.jpg` |
| `panCard` | compressed `panCard.jpg` or original PDF |
| `gstCertificate` | compressed `gstCert.jpg` or original PDF |
| `businessLogo` | compressed `logo.jpg` |

### 6.7 Server behaviour (route handler, `runtime = "nodejs"`)

1. `supabase.auth.getUser()` → on failure `401 { error: "Unauthorized — <message|Please sign in again>" }`.
2. If `referralCode`, look up `referral_links` by `code`; accept if `is_active && (max_uses === null || uses_count < max_uses)` → `referredBy = link.wholesaler_id`, `linkId = link.id`. Invalid codes are **silently ignored** (submission still succeeds).
3. `uploadFile(bucket, path, file)` × 5 in parallel, `upsert: true`, `timestamp = Date.now()`:

| Field | Bucket | Path |
|---|---|---|
| `aadharFront` | `aadhaar-documents` | `<uid>/aadhaar-front-<ts>` |
| `aadharBack` | `aadhaar-documents` | `<uid>/aadhaar-back-<ts>` |
| `panCard` | `pan-documents` | `<uid>/pan-card-<ts>` |
| `gstCertificate` | `gst-documents` | `<uid>/gst-certificate-<ts>` |
| `businessLogo` | `business-logos` | `<uid>/business-logo-<ts>` |

Each returns `getPublicUrl(path).publicUrl`. **Upload failure returns `null` and is logged only** — the row is still written with a null URL, no user-facing error.

4. `supabaseAdmin.from("retailers").upsert({…}, { onConflict: "user_id" })` with columns:
`user_id, email (= user.email), full_name, aadhar_number, business_name, state, city, aadhaar_front_url, aadhaar_back_url, pan_card_url, gst_certificate_url, business_logo_url, referred_by, referral_code, verification_status: "pending"`.
DB error → `500 { error: <dbError.message> }` (raw Postgres message surfaced to the client).
5. If `linkId`: read `uses_count`, write `uses_count + 1` (read-modify-write, **not atomic**).
6. Success → `200 { success: true, data: <retailer row> }`.
7. Uncaught → `500 { error: <err.message || "Internal server error"> }`.

### 6.8 Client error state

```jsx
{submitError && (
  <div className="mb-4 p-4 bg-red-50 text-red-600 border border-red-200 rounded-[10px] text-sm font-medium">
    {submitError}
  </div>
)}
```
`submitError` = `data.error` from the response, else the thrown message, else literal **"An unexpected error occurred. Please try again."**
On failure `setIsSubmitting(false)` (button re-enables). On success the code does **not** reset `isSubmitting` — it navigates to `/onboard-retailer/submitted`.

### 6.9 States summary

- **Initial** — two empty blue dashed upload boxes, Submit grey/disabled.
- **Loading** — Submit reads "Submitting...", disabled; no spinner, no overlay, no progress bar despite potentially large uploads.
- **Error** — red banner above the button.
- **Success** — client-side route push, no toast.
- **Animations** — page fade-up; bar 33.33% → 66.67%.
