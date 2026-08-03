# 05 — Wholesaler Screen Inventory (Web → SwiftUI port spec)

Source app: `/Users/parashrautela/Documents/jewel india /Jewel-India-Frontend`
Next.js 16.1.6 / React 19.2.3 / Tailwind v4 / Supabase Auth+DB+Storage.
All copy below is verbatim from source. All hex/px values are literal from source.

Backend endpoints referenced:
- Supabase: `https://ljxgwiuvdpuarvdszjts.supabase.co`
- AI pipeline (`NEXT_PUBLIC_API_URL`): `https://ai-pipeline-production-3f9a.up.railway.app`
- Site (`NEXT_PUBLIC_SITE_URL`): `https://app.jewelindia.shop`

---

## 0. Global shell, routing and design tokens

### 0.1 Route guard / entry order (`proxy.js` → `lib/supabase/middleware.js`)

Next 16 uses `proxy.js` (not `middleware.js`). Matcher excludes `api`, `_next/static`, `_next/image`, `favicon.ico`, `robots.txt`, `sitemap.xml`, and any `.svg/.png/.jpg/.jpeg/.gif/.webp` path.

Wholesaler-relevant rules:
- `/dashboard/**` with no user → redirect `/signup`.
- `/dashboard/**` with user but no `user_metadata.role` → redirect `/onboard`.
- `/dashboard/wholesaler/**` and role ≠ `wholesaler` → `/dashboard/retailer` (retailer), `/dashboard/employee` (employee), else `/`.
- `/dashboard/wholesaler/**`: reads `wholesalers.verification_status` for `user_id`.
  - no row → `/onboard`
  - `banned` → `supabase.auth.signOut()` then `/entry_page/signup?error=banned`
  - anything ≠ `verified` → `/onboard/submitted`
- `/` with wholesaler user → `getWholesalerDestination`: no row → `/onboard`; `banned` → signOut + `/entry_page/signup?error=banned`; `verified` → `/dashboard/wholesaler`; otherwise `/onboard/submitted`.
- `lib/actions/auth.js#getWholesalerDestination` (used by `signIn`) differs slightly: `verified && has_visited_dashboard` → `/dashboard/wholesaler`; `verified && !has_visited_dashboard` → `/onboard/submitted` (so a freshly-approved wholesaler sees the "Verification Complete!" screen once).
- `/dashboard` (bare) → hard `redirect("/dashboard/wholesaler/add-product")` (`app/dashboard/page.jsx`).

**Encounter order for a wholesaler:** signup → `/onboard` → `/onboard/step2` → `/onboard/step3` → `/onboard/submitted` (waits for admin verification) → `/dashboard/wholesaler` → add-product / catalogue / orders / queries / add-retailer / upload-history.

### 0.2 Design tokens (`app/globals.css` `@theme` block)

```
--font-serif:   "Cirka", var(--font-bodoni), ui-serif, Georgia, Cambria, serif
--font-sans:    "Manrope", var(--font-jost), ui-sans-serif, system-ui, sans-serif
--font-cirka:   "Cirka", serif
--font-gilda:   "Gilda Display", serif
--font-manrope: "Manrope", sans-serif
--font-switzer: "Switzer", ui-sans-serif, system-ui, sans-serif
--font-gilroy:  "Gilroy", ui-sans-serif, system-ui, sans-serif
--font-sfpro:   "SF Pro", ui-sans-serif, system-ui, sans-serif
--font-satoshi: "Satoshi", sans-serif

--color-celestique-taupe:  #E6DFD3
--color-celestique-cream:  #F5F2EB
--color-celestique-dark:   #111111
--color-celestique-light:  #ffffff
--color-celestique-muted:  #8C857B
--color-celestique-border: #D9D0C5

:root { --background: #FEFEFE; --foreground: #111111 }
body  { background:#FEFEFE; overflow-x: clip; -webkit-font-smoothing: antialiased }
html, body { max-width:100vw; overflow-x:hidden }
```

`.theme-wholesaler` (applied on `app/onboard/layout.jsx` and `app/dashboard/wholesaler/layout.jsx`):
- body/button/input/select/textarea → `"Manrope"`
- h1–h6 and any `font-cirka` class → `"Cirka", serif !important`

Font files loaded via `@font-face` from `/fonts/TTF/`: Cirka (300 woff2 Light, 400 ttf Regular, 700 woff2 Bold), Gilda Display 400, Manrope 200/300/400/500/600/700/800 (ttf), Switzer 400, Gilroy 400/500/600/700 (woff2), "SF Pro" 400 (`/fonts/TTF/SF Pro.woff2`), Satoshi 300/400/500/700/900.

### 0.3 Global animation utilities (must be reproduced in SwiftUI)

| Class | Keyframes | Timing |
|---|---|---|
| `.animate-fade-in-up` | `fadeInUp`: opacity 0→1, translateY 10px→0 | 0.5s cubic-bezier(0.16,1,0.3,1) forwards |
| `.animate-fade-in` | `fadeIn`: opacity 0→1 | 0.4s ease-out forwards |
| `.animate-scale-in` | `scaleIn`: scale .98→1 + opacity | 0.4s cubic-bezier(0.16,1,0.3,1) |
| `.skeleton-shimmer` | bg `#E6DFD3` + `::after` gradient `transparent 40% / rgba(245,242,235,0.7) 50% / transparent 60%` translateX -100%→100% | 1.6s ease-in-out infinite |
| `.catalogue-skeleton-bg` | linear-gradient(90deg,#f0f0f0 25%,#e0e0e0 50%,#f0f0f0 75%), size 200% 100%, background-position 200%→-200% | 1.5s infinite |
| `.card-enter` / `.is-visible` | `cardEnter`: opacity 0→1, translateY 28px→0 | 0.55s cubic-bezier(0.16,1,0.3,1) |
| `.onboard-page-transition` | `onboardFadeIn`: opacity 0→1, translateY 8px→0 | 350ms cubic-bezier(0.16,1,0.3,1) |
| `.animate-check-draw` | `checkDraw`: stroke-dashoffset 24→0 (dasharray 24) | 350ms cubic-bezier(0.4,0,0.2,1) |
| `.animate-ripple-green` | `rippleGreen`: scale .9→1.06→1, box-shadow 0→6px rgba(34,197,94,.15)→10px transparent | 600ms cubic-bezier(0.16,1,0.3,1) |
| `.animate-pulse-amber` | `pulseAmber`: opacity .7↔1, scale 1↔1.05 | 2s infinite ease-in-out |
| `.animate-spin-slow` | `spinClockHand` rotate 0→360 | 8s linear infinite |
| `.animate-shake-red` | `softShake` translateX ±1.5px + scale 1.03 at 20/40/60/80% | 500ms cubic-bezier(0.36,0.07,0.19,0.97) |
| `.animate-step-fade` | `stepFadeIn`: opacity 0→1, translateY 6px→0 | 400ms cubic-bezier(0.16,1,0.3,1) |
| `.scrollbar-hide`, `.custom-scrollbar` | hides scrollbars | — |

`@media (prefers-reduced-motion: reduce)` disables `.onboard-page-transition`, `.progress-bar-transition`, and all six onboarding timeline animations.

### 0.4 Dashboard chrome — `Sidebar` (`components/wholesaler/Sidebar.jsx`, 518 lines)

Rendered by `app/dashboard/wholesaler/layout.jsx` inside `<div className="theme-wholesaler" style={{display:flex,minHeight:100vh}}>`, with `<main className="wholesaler-main-content">`.

`.wholesaler-main-content`: `flex:1; min-height:100vh; min-width:0; margin-left:0; padding-bottom:72px`; at `min-width:768px` → `margin-left:70px; padding-bottom:0`.

**Desktop rail (≥768px)** — `position:fixed; top:0; left:0; height:100vh; width:70px; background:#f5f5f3; padding:24px 0; z-index:50`, icons stack `margin-top:96px`, `gap:32px` (at `max-height:680px` → `margin-top:32px; gap:16px`). Each item 44×44, radius 8px, `opacity: active?1:0.35`, `filter: active? brightness(0) : grayscale(1)`, transition `all 0.15s ease`; hover `opacity .7, background rgba(0,0,0,0.06)`.

Nav items (label = `title` attr, icon = remote SVG):
1. `Home` → `/dashboard/wholesaler` — icon `…/v1777013959/home_logo_q3xekq.svg`
2. `Add/Upload` → `/dashboard/wholesaler/add-product` — `…/upload_logo_hfdz8a.svg`
3. `Add Retailer` → `/dashboard/wholesaler/add-retailer` — `…/add_retailer_logo_aonkud.svg`
4. `Catalogue` → `/dashboard/wholesaler/catalogue` — `…/catalogue_logo_baed4n.svg`
5. `Orders` → `/dashboard/wholesaler/orders` — `…/PACKAGE_LOGO_ekya2x.svg`
6. `Chat` → `/dashboard/wholesaler/queries` — `…/chatLOGO_j1mnkx.svg`

Active rule: Home = exact path match; all others = `pathname.startsWith(href)`.

Bottom of rail: 44×44 button `background:#2e2833`, radius 12px, `title="Logout"`, icon `…/jewel_logo_rhgin9.svg`; hover `opacity .9; scale(1.05)`. Opens logout modal.

**Mobile floating nav (<768px)** — desktop rail `display:none`. `.wholesaler-bottom-nav`: fixed `bottom:20px; left:50%; translateX(-50%); width:90vw; max-width:400px; height:60px; background:rgba(255,255,255,0.85); backdrop-filter:blur(20px); border:1px solid rgba(255,255,255,0.5); border-radius:100px; box-shadow:0 8px 32px rgba(0,0,0,0.1), 0 1.5px 4px rgba(0,0,0,0.06); padding:0 12px; z-index:100`.
Order: Home, Catalogue, Add/Upload, Orders, Chat, then a 36×36 round `#2e2833` "More Options" button (jewel logo 22×22).
Items 44×44 round, `opacity: active?1:0.45`; `.active` → `background rgba(0,0,0,0.05); filter:brightness(0)`.

**More popover** (`.bottom-nav-popover-content`): fixed `bottom:90px`, width 200px, white, radius 16px, `box-shadow:0 12px 30px rgba(0,0,0,0.15)`, padding 8px, animation `popoverFadeIn 0.25s cubic-bezier(0.16,1,0.3,1)` (opacity 0→1, translate(-50%,10px)→(-50%,0)). Backdrop `rgba(0,0,0,0.1)` + `blur(2px)`, tap closes.
Items: `Invite Retailer` (→ `/dashboard/wholesaler/add-retailer`, icon add_retailer, `filter:brightness(0)`), and `Logout` (red `#ef4444`, hover bg `#fef2f2`) which opens the confirm modal.

**Logout confirmation modal**: overlay `rgba(0,0,0,0.4)` + `backdrop-filter:blur(4px)`, `animation: fadeIn 0.2s ease-out`; card white, radius 20px, padding 32px, width 360px (max-width 90%), `box-shadow:0 20px 25px -5px rgba(0,0,0,0.1), 0 10px 10px -5px rgba(0,0,0,0.04)`, `animation: scaleUp 0.2s cubic-bezier(0.34,1.56,0.64,1)` (scale .95→1, opacity 0→1).
- Icon: 56×56 circle `#fef2f2`, logout glyph stroke `#ef4444`.
- Title: **"Confirm Logout"** — 18px/600/`#111827`, Inter.
- Body: **"Are you sure you want to logout?"** — 14px/`#6b7280`, line-height 1.5.
- Buttons row (gap 12px): **"Cancel"** (white, border `#e5e7eb`, text `#374151`, hover bg `#f9fafb`) and **"Logout"** (bg `#2e2833`, white, hover opacity .9) → `await signOut()` server action → `supabase.auth.signOut()` + `redirect("/signin")`.
- Clicking the overlay closes without logging out.

---

## 1. `/onboard` — Onboarding Step 1 (Identity)

**Files:** `app/onboard/page.jsx`, `app/onboard/layout.jsx`, `components/onboard/OnboardLayout.jsx`, `OnboardNavbar.jsx`, `LeftPanel.jsx`, `StepIndicator.jsx`, `step1/Step1Container.jsx`, `step1/IdentityForm.jsx`, `step1/AadharUpload.jsx`, `components/onboard/ImageUploadBox.jsx`, `context/OnboardContext.jsx`.
**Purpose:** collect the wholesaler's legal name, Aadhaar number and both Aadhaar card photos before business details.
**Document title:** `"Step 1 of 3 — Onboarding"`.

### Layout
`OnboardLayout`: full page `bg-#FFFFFF`, `text-#374151`, `font-sans antialiased`. Main = `max-w-[1100px] mx-auto px-[clamp(16px,3vw,48px)] pt-[clamp(24px,3vw,40px)] pb-2`, flex column on mobile / row centered on `md`, gap `8`/`clamp(24px,1vw,48px)`. Left column `w-full md:w-[340px] shrink-0 pt-2`; right column `w-full md:w-[500px] min-h-[400px]`.
Page wrapper has class `onboard-page-transition` (350ms fade+rise on every step navigation).

**OnboardNavbar** (`border-b #E0E0E0`, `px-[clamp(16px,3vw,48px)] py-[clamp(6px,0.8vw,12px)]`, shadow-sm):
- Left button: chevron-left + **"Back"** (`#374151`, `clamp(12px,1.4vw,14px)`, hover `bg-gray-100`, radius full). **Side effect: signs the user out** (`supabase.auth.signOut()`), then `router.push(backRoute || '/signup')`. Step 1 `backRoute="/signup"`.
- Right button: person icon + **"Sign out"** → signOut then `/signup`.

**LeftPanel**:
- Logo row: `/jewelLogo.svg` (`w-[clamp(28px,3vw,36px)]`) + **"Jewels India"** (`clamp(15px,1.6vw,18px)`, extrabold, `#111827`, tracking-wide).
- H1 (`clamp(16px,1.8vw,23px)`, extrabold, `#111827`, `whitespace-nowrap`, leading 1.2): **"Let me get to know you"**
- P (`clamp(13px,1.3vw,14px)`, `#9CA3AF`, medium): **"We need a few details to verify who you are. This keeps your account and your business safe."**

**StepIndicator** (`currentStep=1, totalSteps=3`):
- Label: **"Step 1"** (extrabold `#111827`) + **" of 3"** — 13px, `#9CA3AF`, uppercase, tracking-widest.
- Track: `h-[6px] bg-#E5E7EB rounded-full`; fill `bg-#111827`, `transition: width 800ms cubic-bezier(0.25,1,0.5,1), box-shadow 400ms ease-out`.
- Width math: `((step-1)/3)*100` → step1 0%, step2 33.33%, step3 66.67%, step4 100%.
- Initial width read from `sessionStorage["onboarding_last_step"]` (else `step-1`), then animated to target on next `requestAnimationFrame`. Writes `onboarding_last_step = currentStep` on mount.
- Micro-pop at 850ms: label goes `scale(1.01) opacity .95 color #6B7280` (transition `transform 400ms cubic-bezier(0.34,1.56,0.64,1), opacity 400ms ease`).

### Fields & validation (state lives in `OnboardContext`, memory-only — **not persisted**; a page refresh wipes steps 1–2)

| Field | Label | Placeholder | Input rules | Error copy (shown only after a failed Next) |
|---|---|---|---|---|
| `name` | **"Name*"** | **"Parash Rautela"** | keystrokes filtered by `/^[A-Za-z\s]*$/` (letters + spaces only); valid if `trim().length > 0` | **"Name is required"** |
| `aadhar` | **"Aadhar Number*"** | **"**** **** ****"** (literal `&#42;` × 12 in 3 groups) | digits only, sliced to 12, auto-formatted `#### #### ####`; valid if 12 digits | **"Enter a valid 12-digit Aadhar number"** |
| `frontImage` | **"Aadhar Front*"** | — | file required, `accept="image/jpeg, image/png, image/webp"` | **"Please upload Aadhar Front"** |
| `backImage` | **"Aadhar Back*"** | — | same | **"Please upload Aadhar Back"** |

Input style: `bg-#F5F5F5 rounded-[8px] px-[clamp(10px,1.5vw,16px)] py-[clamp(8px,1.2vw,14px)] text-[clamp(13px,1.4vw,15px)] text-#374151 placeholder:#9CA3AF`; focus `ring-2 ring-black/10`; error state swaps to `border-[1.5px] border-#EF4444`. Error text 12px `#EF4444`. Label 13px semibold `#374151`. Form column is `w-84` (21rem = 336px), gap-6.

### `ImageUploadBox` (shared by steps 1/2/3)
- Tile: `w-full bg-#EEF4FF rounded-[12px] aspect-square`, hover `bg-blue-50`, cursor pointer (click only opens picker when empty).
- Border states: empty `border-[1.5px] dashed #2563EB`; error `border-[1.5px] dashed #EF4444`; filled `border-[2px] solid #22C55E`.
- Empty content: 48×48 circle, `border-2` `#2563EB` (or `#EF4444` on error), 26×26 plus glyph.
- Filled: `<img>` `object-cover` (or `object-contain p-4` when `objectFit="contain"` — used for the business logo). PDF (`application/pdf`) renders a red 42×42 doc icon + truncated filename (11px, `#6B7280`, max-w 120px).
- Remove button: top-right 7×7 (28px) white circle, shadow-sm, 14px ✕, `z-10`; clears the file and resets the `<input>`.
- Preview uses `URL.createObjectURL` and revokes on change/unmount.
- Error text under tile: 12px `#EF4444`.

### Footer / CTA (inline in `Step1Container` — note `step1/Step1Footer.jsx` exists but is NOT used)
- Legal note, 7px black bold, leading-relaxed:
  **"*Your documents are encrypted and only used for verification."** / newline / **"We never share them."**
- Button **"Next"** — `w-full md:w-[140px]`, extrabold, `rounded-[10px]`, `px-4 py-[clamp(10px,1.2vw,14px)]`, `text-[clamp(13px,1.4vw,15px)]`, tracking-wide.
  - Enabled: `bg-#000000 text-white`, hover `bg-black/90`.
  - Disabled: `bg-#D1D5DB text-white cursor-not-allowed` — disabled until name + 12-digit Aadhaar + both images are present.
  - Click while invalid sets `submitAttempted=true` → all inline errors + red borders appear at once (button is `disabled` so this path is only reachable if the disabled attribute is bypassed; visually the primary feedback is the greyed button).
- Container: `animate-fade-in-up`.

### States
initial (empty, Next disabled) · valid (Next black) · error (per-field red border + message, upload tiles red-dashed) · filled (green solid border on tiles). No loading/network state on this step — navigation is purely client-side `router.push('/onboard/step2')`.

---

## 2. `/onboard/step2` — Business details

**Files:** `app/onboard/step2/page.jsx`, `components/onboard/step2/{Step2Container,BusinessForm,BusinessLogoUpload,Step2Footer}.jsx`.
**Purpose:** capture business name, location and logo — the identity retailers see.
**Document title:** `"Step 2 of 3 — Onboarding"`. `backRoute="/onboard"` (Back still signs out).

- H1: **"Tell us about your business"**
- Sub: **"This is how retailers will find and recognise you on the platform."**
- StepIndicator: **"Step 2"** of 3 → bar animates 33.33% → 66.67%? No: target for step 2 = `((2-1)/3)*100 = 33.33%`, animating up from step-1's 0%.

### Fields

| Field | Label | Placeholder | Validation | Error copy |
|---|---|---|---|---|
| `businessName` | **"Business name*"** | **"Pc jewellers"** | `trim().length >= 2` | **"Business name is required"** |
| `selectedState` | **"State*"** | native `<select>` first option **"select"** (disabled, `value=""`) | must be non-empty | **"Please select a state"** |
| `selectedCity` | **"City*"** | **"select"** | free-text input; must be non-empty; **disabled until a state is chosen** | **"Please enter a city"** |
| `logoImage` | **"Business Logo"** (no asterisk but mandatory) | — | file required | **"Please upload your business logo"** |

State options (28 entries, exact order): `Andhra Pradesh, Arunachal Pradesh, Assam, Bihar, Chhattisgarh, Goa, Gujarat, Haryana, Himachal Pradesh, Jharkhand, Karnataka, Kerala, Madhya Pradesh, Maharashtra, Manipur, Meghalaya, Mizoram, Nagaland, Odisha, Punjab, Rajasthan, Sikkim, Tamil Nadu, Telangana, Tripura, Uttar Pradesh, Uttarakhand, West Bengal`.
(Union territories are absent. `cities` exists in context but is never populated — city is free text.)

Select styling: `appearance-none bg-#FFFFFF rounded-[8px] border-#E5E7EB`, custom chevron-down 12–16px positioned right (`#374151` when a value is set, `#9CA3AF` when empty). Error → `border-#EF4444`.
City disabled style: `bg-#F9FAFB border-#E5E7EB cursor-not-allowed opacity-80`.
Business-name column is `w-full md:w-[58%] md:flex-none` with an empty spacer column on md+.

Logo tile: `ImageUploadBox` with `objectFit="contain"`, `aspect-square`, column width `md:w-[58%]`.
Under the logo, 8px/8.5px black bold: **"*Your documents are encrypted and only used for verification."** / **"We never share them."**

**Step2Footer**: **"Next"** button, same enabled/disabled palette as step 1, plus `md:translate-x-[46px]` offset, `transition-all`. Enabled only when all four fields valid. On click when invalid → `setSubmitAttempted(true)` (reveals errors). On valid → `router.push('/onboard/step3')`.

Container animation: `animate-fade-in-up`.

---

## 3. `/onboard/step3` — Documents + submit

**Files:** `app/onboard/step3/page.jsx`, `components/onboard/step3/{Step3Container,DocumentUpload,Step3Footer}.jsx`, `app/api/onboard/submit/route.js`.
**Purpose:** upload PAN + GST and POST the entire onboarding payload.
**Document title:** `"Step 3 of 3 — Onboarding"`. `backRoute="/onboard/step2"`, `textMarginTop="md:mt-[18px]"`.

- H1: **"Almost there one last step"**
- Sub: **"Upload your PAN and GST certificate so we can verify your business. This is a one-time process."**
- StepIndicator: **"Step 3"** of 3, bar target 66.67%.

### Fields
| Field | Label | Accept | Error copy |
|---|---|---|---|
| `panFile` | **"PAN Card*"** | `image/jpeg, image/png, image/webp, application/pdf` | **"Please upload your PAN Card"** |
| `gstFile` | **"GST Certificate*"** | same | **"Please upload your GST Certificate"** |

Two equal columns, `gap-[clamp(8px,3vw,24px)]`. Under the PAN tile only: 8/8.5px black bold **"*Your documents are encrypted and only used for verification."** / **"We never share them."**
Container `mt-10 gap-8 animate-fade-in-up`.

### Submit
Button label **"Submit"**; while submitting shows a spinning 16×16 SVG + **"Submitting..."**, background `bg-#6B7280`, `cursor-wait`; disabled when `!isFormValid || isSubmitting`. Same size/offset as step 2 (`md:w-[140px]`, `md:translate-x-[46px]`).

Client pre-processing (`Step3Footer.compressImage`) — applies to **image files only** (`file.type.startsWith("image/")`; PDFs pass through untouched):
- Canvas resize to fit `MAX_WIDTH=1200 × MAX_HEIGHT=1200` (aspect preserved), re-encoded `image/jpeg` quality **0.7**, filename preserved.

`POST /api/onboard/submit` — `multipart/form-data`, same-origin, Node runtime:
```
name           : string
aadhar         : string   // spaces stripped, 12 digits
businessName   : string
state          : string
city           : string
aadharFront    : File (compressed)
aadharBack     : File (compressed)
panCard        : File (compressed if image)
gstCertificate : File (compressed if image)
businessLogo   : File (compressed)
```
Server: verifies session (`401 {error:"Unauthorized — <msg>"}` if not), uploads with the service-role client to buckets/paths
`aadhaar-documents/{uid}/aadhaar-front-{ts}`, `aadhaar-documents/{uid}/aadhaar-back-{ts}`, `pan-documents/{uid}/pan-card-{ts}`, `gst-documents/{uid}/gst-certificate-{ts}`, `business-logos/{uid}/business-logo-{ts}` (`upsert:true`), then upserts `wholesalers` on conflict `user_id`:
```
user_id, email, full_name, aadhar_number, business_name, state, city,
aadhaar_front_url, aadhaar_back_url, pan_card_url, gst_certificate_url,
business_logo_url, verification_status: "pending"
```
Returns `{ success:true, data:<wholesaler row> }`, or `{error: <db message>}` 500.

### Error states
- Non-JSON HTML response (e.g. 413): thrown message **`Server returned error status ${res.status}. Files might still be too large.`**
- JSON error: `result.error` or fallback **"Submission failed"**.
- Rendered above the footer as: `mb-4 p-4 bg-red-50 text-red-600 border border-red-200 rounded-[10px] text-sm font-medium` containing the raw message. `isSubmitting` resets to false so the user can retry.
- Success → `router.push("/onboard/submitted")`.

---

## 4. `/onboard/submitted` — Verification status (also the post-approval gate)

**Files:** `app/onboard/submitted/page.jsx` (server), `components/onboard/submitted/{VerificationTimeline,SubmittedFooter}.jsx`.
**Purpose:** show verification state and, once verified, hand off to the dashboard.
**Document title:** `"Verification Status — Celestique"`.

**Data read:** `supabase.from("wholesalers").select("verification_status, notification_message, rejection_reason, rejected_documents").eq("user_id", user.id).single()`. No user → `redirect("/entry_page/signin")`. `status === "banned"` → `redirect("/entry_page/signup?error=banned")`.

**Header/sub (all statuses):** description is always **"we're reviewing your details"**; heading varies.

| `verification_status` | Heading | Body paragraph | Button | Route on button | Tracker word |
|---|---|---|---|---|---|
| `pending` (default) | **"You're all submitted!"** | **"We'll verify your documents in 24–48 hours and notify you on your number once you're approved."** | **"I Understand"** | `/entry_page/signup` | "Under Verification" |
| `on_hold` | **"You're all submitted!"** | `notification_message` or **"Your account is on hold pending further review."** | **"I Understand"** | `/entry_page/signup` | "On Hold" |
| `rejected` | **"Application Rejected"** | `rejection_reason` (falls back to `notification_message`, then **"There was an issue with your submission. Please click below to resubmit your documents."**) | **"Resubmit"** | `/onboard` | "Rejected" |
| `resubmission_required` | **"Resubmission Required"** | same as above | **"Resubmit"** | `/onboard` | "Action Needed" |
| `verified` | **"Verification Complete!"** | **"You're verified! You can now access your full dashboard."** | **"Go to Dashboard"** | `/dashboard/wholesaler` | "Verified" |

Navbar `backRoute` is `null` for `resubmission_required | rejected | verified` (Back button still renders and falls back to `/signup` after signing out); otherwise `/entry_page/signin`.

**StepIndicator** is rendered with `currentStep={4} totalSteps={3}` → label becomes **"Verification Progress"** (extrabold `#111827`, tracking-wider), bar 100%, and after 800ms gains `shadow-[0_0_8px_rgba(17,24,39,0.25)]`.

### VerificationTimeline (two steps, max-w 340px, centered, `mt-6 mb-2`)
Session guard: `sessionStorage["onboard_submitted_visited"] === "true"` → skip all animation and render both steps as `done` immediately. Otherwise sets the flag and runs:
- t=50ms → step1 `active`
- t=300ms → step1 `done`, step2 `active`
- t=600ms → step2 `done`

Step 1 — circle 28×28: pending `border-2 #E5E7EB`, active `border-2 #111827` on white, done `bg-#22C55E border-#22C55E` with the drawn white check (`animate-check-draw`). Connector `w-[2px] h-[34px]`, `scale-y-0 → scale-y-100` over 500ms, colour `#22C55E` when done.
Label: **"Details Submitted"** (14.5px; done → `text-emerald-700 font-bold`, else `#9CA3AF` medium). Sub-label: **"Under Review"** (11.5px `#9CA3AF`) — the `submittedAt` prop is never passed.

Step 2 — label before done is **"Verification Status"** with sub **"Awaiting Analysis"**. When done, config by status:
| status | circle | label | label colour | sub | motion |
|---|---|---|---|---|---|
| `verified` | `border-2 #22C55E bg-#22C55E` white check | **"Verification Approved"** | `#22C55E` bold | **"Completed"** | `animate-ripple-green` |
| `rejected` | `border-2 #EF4444 bg-#FEF2F2` warn triangle | **"Application Rejected"** | `#EF4444` bold | **"Pending Review"** | `animate-shake-red` |
| `resubmission_required` | same red | **"Revision Required"** | `#EF4444` bold | **"Pending Review"** | `animate-shake-red` |
| `banned` | `border-red-700 bg-red-950` ✕ | **"Access Suspended"** | `red-700` bold | **"Pending Review"** | `animate-shake-red` (unreachable — page redirects first) |
| `on_hold` | `border-amber-500 bg-amber-50/50` clock | **"Application On Hold"** | `amber-700` bold | **"Pending Review"** | `animate-pulse-amber` + `animate-spin-slow` hand |
| `pending`/default | same amber | **"Under Verification"** | `amber-700` bold | **"Pending Review"** | same |

### Rejection panel (only for `rejected` / `resubmission_required`)
Replaces the grey paragraph. `mt-8 p-5 bg-red-50/40 border border-red-200/60 rounded-2xl`:
- Icon chip `p-2 bg-red-100/70 text-red-600 rounded-xl` (warning triangle).
- H4 14.5px bold `text-red-950`: **"Application Rejected"** or **"Revision Required"**.
- P 13.5px `text-red-800/90`: `rejection_reason` or **"There was an issue with your submission. Please check the details below and resubmit."**
- If `rejected_documents[]` non-empty: divider + H5 12px bold uppercase tracking-wider `text-red-950/70`: **"Items to Resubmit:"**, then a list of chips (13px, `text-red-900` semibold, `bg-red-100/30 border-red-200/50 rounded-xl px-3.5 py-2`, red ✕ 16px).
  Document key → display name map:
  `aadhaar_front`/`aadhaar_front_url` → **"Aadhaar Card (Front)"**; `aadhaar_back`/`_url` → **"Aadhaar Card (Back)"**; `pan_card`/`_url` → **"PAN Card"**; `gst_certificate`/`_url` → **"GST Certificate"**; `business_logo`/`_url` → **"Business Logo"**; unknown keys → underscores→spaces + Title Case.
- Otherwise (pending/on_hold/verified) the body paragraph renders centered, 14px, `#9CA3AF`, `mt-6`.

### SubmittedFooter
- Left text block, 13px: **"Need help in the meantime? Call us on"** (`#9CA3AF`), then **"9897453396"** (bold `#111827`) + **" — we're happy to assist."** (`#9CA3AF`).
- Right button: black `rounded-[10px] px-[clamp(24px,3vw,40px)] py-[clamp(10px,1.2vw,14px)]`, extrabold. Label = status label above; while the transition is pending it reads **"Loading..."** and the button is `disabled:opacity-50`.
- Action: server action `terminalUserExit(actionRoute)` — **signs the user out only when the route contains `/entry_page`**, then redirects. So "Go to Dashboard" and "Resubmit" keep the session.

---

## 5. `/dashboard/wholesaler` — Home

**Files:** `app/dashboard/wholesaler/page.jsx` (server), `loading.jsx`, `components/wholesaler/{HeroUploadSection,UploadButton,OverviewSection,StatCard,CatalogueSection,CategoryCard}.jsx`, `lib/config/catalogueCategories.js`.
**Purpose:** landing screen — upload CTA, four KPIs, category shortcuts.
**Layout metadata:** `title: "Wholesaler Dashboard"`, `description: "Manage your catalogue, orders, and queries."`

### Server data reads
1. `wholesalers` by `email` (`maybeSingle`), fallback by `user_id`; selects `id, has_visited_dashboard, business_name, full_name, last_checked_orders_at`.
   `businessName = business_name || full_name || email.split("@")[0] || ""`.
   Side effect: if `!has_visited_dashboard` → `update({has_visited_dashboard:true}).eq("user_id", user.id)`.
2. `products` count: `select("*", {count:"exact", head:true}).eq("wholesaler_id", user.id)` → **Live Products**.
3. `orders` count: same shape `.eq("wholesaler_id", user.id).eq("status","pending")` → **New Orders**; `hasNewOrders = count > 0`.
4. `conversations` `select("id, messages!inner(id)").eq("wholesaler_id",user.id).eq("messages.sender_type","employee").eq("messages.is_read",false)` → `chatsCount = rows.length`; `hasNewChats = >0`.
5. `GET {NEXT_PUBLIC_API_URL}/api/upload-usage?wholesaler_id={uuid}` (`cache:"no-store"`) → `{used, limit}`; on failure `used=0, limit=Infinity` (console error, no UI).

### Screen content
- Sticky header (`top-0 z-50`, white, `px-4 md:px-10 py-6`): H1 **"Home"** — 24px bold `#111`.
- **HeroUploadSection** (`px-4 md:px-10 pt-6 pb-4`):
  - **"Welcome"** — `#6B7280`, `text-xs md:text-sm`, `font-sfpro`.
  - Business name (or literal **"Welcome"** if blank) — `#1F2937`, `text-xl md:text-2xl`, medium, `font-sfpro`.
  - Banner: `h-[160px] md:h-[180px] rounded-xl border-#F3E8D6 bg-#FFFDF9 shadow-sm`, background image `/image/heroframee.png` (`fill`, `priority`, `object-cover object-right md:object-center opacity-80`).
  - CTA **"Upload Now"** (`UploadButton`) — black pill `rounded-lg px-5 py-2.5 text-sm font-medium text-white shadow-md`, upload glyph 16px, hover `#2a2a2a`, `active:scale-[0.97]`, 200ms → `/dashboard/wholesaler/add-product`. Positioned bottom-center of the banner.
- **OverviewSection** (`px-4 md:px-6 py-6 md:py-10`, inner `max-w-7xl`):
  - H2 **"Insights"** — `font-cirka text-4xl text-celestique-dark mb-6`.
  - Grid `1 / md:2 / lg:4`, gap-4. Card (`BottomStatCard`): `rounded-xl border-#e5e5e5 bg-white py-5 px-6`, hover `shadow-md scale-[1.02]` 200ms, focus ring amber-500; value in `font-cirka text-[48px] medium text-gray-900`; title row = 16px icon + 14px `text-gray-700` medium; right chevron 16px.
    | Title | Value | Href | Badge |
    |---|---|---|---|
    | **"Live Products"** | products count | `/dashboard/wholesaler/catalogue` | none |
    | **"New Orders"** | pending orders count | `/dashboard/wholesaler/orders?tab=new` | red ping dot when >0 |
    | **"New Chat"** | unread conversations | `/dashboard/wholesaler/queries` | red ping dot when >0 |
    | **"Uploads Today"** | `"{used}/{limit}"`, or just `"{used}"` when limit is Infinity | `/dashboard/wholesaler/upload-history` | none |
    Badge = 8×8: `animate-ping bg-red-400 opacity-75` behind `bg-red-500` dot, offset `-mt-6 ml-1`.
    Live Products icon is a remote SVG `…/v1777024605/live_products_nfjmtr.svg`; the other three are inline stroke icons (bag, chat bubble, upload arrow).
  - **Chamak card** (`mt-6`): `rounded-2xl bg-gradient-to-r from-#bb8651 to-#f6e0a7 p-6 md:p-8 border-#e4cc8f/30 min-h-[220px] md:min-h-[200px]`, hover `shadow-lg scale-[1.01]`.
    - H3 **"Chamak"** — `font-cirka text-3xl md:text-4xl text-white font-bold`.
    - P **"Review products with low engagement and Replace with better designs"** — `font-manrope text-xs md:text-sm text-white/95`.
    - Chip **"Coming soon"** — black box, border `#e4cc8f`, `rounded-lg px-5 py-2.5`, `shadow-[0px_4px_4px_rgba(0,0,0,0.25)]` + inner `shadow-[inset_2px_2px_4px_rgba(228,204,143,0.3)]`, `font-manrope text-sm semibold`. **Non-interactive (no handler).**
    - Right: `/image/chamak_necklace.png` masked by `/image/chamak_mask.svg` (mask-size 100% 100%, centered, no-repeat), 180×220 → md 220×260 → lg 240×280.
- **CatalogueSection** (`px-4 md:px-6 py-8 md:py-12`, `max-w-7xl`):
  - H2 **"My Catalogue"** — `font-cirka text-4xl md:text-3xl text-celestique-dark`.
  - P **"See and manage all your catalogue categories from one place."** — `text-celestique-muted font-gilroy medium`.
  - Grid `1 / sm:2 / lg:5`, gap-5. Each `CategoryCard`: `h-[339px] rounded-xl shadow-sm`, image `fill object-cover`, hover `scale-105` over 500ms; top gradient `from-celestique-dark/30 to-transparent` over the top half; centered label `font-serif medium text-xl text-white tracking-wide` at `top-6`. Link → `/dashboard/wholesaler/catalogue?category={slug}`. On image error → gradient fallback class.
  - Categories (name / slug / image / fallback gradient):
    1. Necklace / `necklace` / `/image/neclace.svg` / from-purple-100 to-violet-200
    2. Haram / `haram` / `/image/haram_svg.svg` / from-orange-100 to-amber-200
    3. Pendants / `pendants` / `/image/pendants.svg` / from-sky-100 to-blue-200
    4. Mangalsutras / `mangalsutras` / `/image/mangalsutra.svg` / from-red-100 to-rose-200
    5. Chains / `chains` / `https://res.cloudinary.com/dcs0vuzwg/image/upload/v1777351896/chains_tqfmhp.svg` / from-slate-100 to-gray-200
    6. Bangles / `bangles` / `/image/bangles.svg` / from-yellow-100 to-amber-200
    7. Rings / `rings` / `/image/rings.svg` / from-rose-100 to-pink-200
    8. Earrings / `earrings` / `/image/earrings.svg` / from-orange-100 to-amber-200
    9. Nosepins / `nosepins` / `/image/nosepins.svg` / from-teal-100 to-emerald-200
  - Tenth tile — **"View All"**: dashed `border-2 border-celestique-border`, `h-[339px]`, arrow glyph `→` (`text-3xl text-celestique-muted`) over label **"View All"** (`text-sm font-gilroy medium`); hover → `border-celestique-dark bg-celestique-cream`, text `celestique-dark`. Link `/dashboard/wholesaler/catalogue`.

### Loading state (`app/dashboard/wholesaler/loading.jsx`)
`animate-pulse` skeleton: 32px×192px bar, 16px×256px bar, then a `1/sm:2/lg:3/xl:4` grid of 8 cards (`rounded-[16px] border-gray-200`, `aspect-square bg-gray-100`, two text bars 75% / 50%).

### Notes
- `WeeklyReviewBanner` is **imported but never rendered** (dead): would show "Weekly review", "Review products with low engagement and Replace with better designs", CTA "Review now".
- Empty state: there is none — counts render as `0`.

---

## 6. `/dashboard/wholesaler/add-product` — AI upload flow ★ (most complex screen)

**Files:** `app/dashboard/wholesaler/add-product/page.jsx` (server), `components/product/AddProductForm.jsx` (689 lines), `components/product/{ImageUpload,BackToDashboardButton}.jsx`, `components/ui/{Select,Toggle,Input,InputWithSuffix}.jsx`, `lib/hooks/useUploadUsage.js`, `lib/api/products.js`, `lib/actions/products.js`.
**Purpose:** create one product: image + metadata; kick off the background AI pipeline.
**Document title:** `"Add Product — Celestique"`. No user → `redirect("/signin")`.

### Page chrome
- Sticky header `border-b #e5e5e5 px-4 md:px-10 py-2.5` containing `BackToDashboardButton`: chevron-left 16px + **"Back to dashboard"** (label hidden below `md`), `text-sm #374151` hover `#111827`, `font-sfpro`, `router.push("/dashboard/wholesaler")`.
- Main: `px-4 py-6` / `md:max-w-[640px] md:mx-auto md:px-8 md:py-8` / `lg:max-w-[880px] lg:px-10 lg:py-10`, gaps 6/8/10.
- Footer `border-t #e5e5e5 px-4 md:px-10 py-4 font-gilroy`: left **"All Rights Reserved © Jewels India"** (`text-sm #6B7280`), right **"Crafted with ❤️ in blr"** (`text-sm #374151`).

### Header block
- H1 **"Add new product"** — `text-[28px] md:text-4xl font-semibold #111827 font-cirka`.
- P **"Enter the details below to create a sparkling new listing."** — `text-base #6B7280 font-gilroy medium`.

### Daily-limit banner (three variants, driven by `useUploadUsage(userId)`)
Hook: `GET {API}/api/upload-usage?wholesaler_id=…` on mount; `{used, limit, resetsAt}`; default `{used:0, limit:Infinity, resetsAt:null}`; **fails open** (errors keep previous state, uploads not blocked); `isLimitReached = used >= limit`; exposes `refetch()`.
1. **Loading** (`isLoading`): `bg-gray-50 border-gray-100 rounded-xl p-4 animate-pulse` with a 16px/33% bar and a 6px full-width bar.
2. **Limit reached**: `bg-#FFFDF5 border-#FBEFBE rounded-xl p-4 animate-fade-in`, ⚠️ glyph (`text-amber-600 text-lg`),
   - H4 **"Daily upload limit reached"** (`text-sm semibold #856404 font-gilroy`)
   - P **"You have used all {limit} uploads for today."** + when `resetsAt` present, appended **" Resets at {h:mm AM/PM}."** (`toLocaleTimeString([], {hour:'numeric',minute:'2-digit'})`; the ISO string is sanitised: `+00:00Z`/`+00:00` → `Z`).
   - Right chip **"{used} / {limit} Used"** (`text-xs bold #856404 bg-#FBEFBE/60 rounded-full px-2.5 py-1`).
3. **Normal progress**: white card `border-#e5e5e5 rounded-xl p-4`, row **"Daily Upload Progress"** (`#374151` medium) / **"{used} / {limit} uploads used today"** (`#6B7280` medium); track `bg-gray-100 h-1.5 rounded-full` with black fill `width: min(100, used/limit*100)%`, `transition-all duration-500 ease-out`.
4. If `limit` is falsy or `Infinity` → no banner at all.

### Section 1 — Product image
- Badge `1`: 26×26 black circle, white 12px text (`NumberIndicator`), offset `md:-ml-10`.
- H2 **"Product image"** — `text-[20px] md:text-3xl font-semibold #111827 font-gilroy font-bold`.
- P **"Upload a clear image. We'll remove the background first, then enhance it."** — `text-sm #6B7280 font-gilroy`.
- Tips heading **"Get the best result from your photo:"** (`font-bold #374151 mb-2`), then the same three items as an ordered list on `md+` and a bulleted list on mobile:
  1. **"Place the jewellery on a background that contrasts with the product."**
  2. **"Upload a clear well-lit photo."**
  3. **"Keep only the product in the frame"**
- **ImageUpload** (`id="image"`), right column `md:max-w-[430px]`:
  - Dropzone `w-full md:w-[420px] h-[200px] md:h-[240px] border-2 border-dashed rounded-[10px]`.
    - Idle: `border-#3B82F6 bg-#F1F5F9`, hover `border-#2563EB bg-#F8FAFC`.
    - Drag-over: `border-#2563EB bg-#EFF6FF`.
    - Error: `border-red-500 bg-red-50`, hover `bg-red-50/70`.
  - Empty content: 48×48 dashed circle `#3B82F6` + 24px plus icon.
  - With preview: `<img>` `max-h-full max-w-full object-contain` inside `p-4`; clicking the zone no longer opens the picker.
  - Action row below (only with a preview, `w-full md:w-[420px] justify-center gap-4 mt-3`):
    - **"Change Image"** — black `rounded-md px-3.5 py-2 text-sm font-gilroy semibold`, upload glyph 16px.
    - **"Remove"** — transparent, `text-red-500` hover `red-600`, trash glyph 16px; revokes the object URL and clears the input.
  - Hidden input `accept="image/jpeg,image/png,image/webp"`. Drag & drop supported (`onDrop` takes `dataTransfer.files[0]`).
  - Error text under: `text-xs semibold text-red-500 font-gilroy mt-1.5 animate-fade-in text-center`.

### Section 2 — Essential details
- Badge `2`, H2 **"Essential details"** (`text-[20px] md:text-3xl semibold #111827 font-gilroy`).
- P **"Add the key information that helps retailers understand and find this peice."** (typo "peice" is in the source; `<br>` before "understand" on md+).
- **Product Title** (`Input id="title"`), label **"Product Title"**, placeholder **"eg. Vintage gold Necklace"**. Input: `h-11 border-#e5e5e5 rounded-lg px-3 text-sm #111827`, placeholder `#9CA3AF font-gilroy semibold`, focus `border-#3B82F6 ring-1 #3B82F6`; error → `border-red-500 ring-red-500`.
- Custom `Select` (headless: a hidden native `<select>` plus a button + popup list). Button `h-11 border rounded-lg px-3 text-sm font-gilroy semibold`; open → `border-#3B82F6 ring-1`; chevron rotates 180° over 200ms. Popup: absolute, `mt-1 w-full bg-white border-#e5e5e5 rounded-lg shadow-lg`, `max-h-60 overflow-y-auto py-1`, item `px-3 py-2.5 text-sm`, selected item `bg-#F3F4F6 #111827 semibold`, hover `bg-#F9FAFB`. Closes on outside mousedown. On this screen every select passes `placeholder="select"` with `placeholderClassName="text-black"` (so the unselected placeholder is black, not grey).
  | id | Label | Options (value → label) |
  |---|---|---|
  | `jewellery_type` | **"Type"** | necklace→Necklace, rings→Rings, earrings→Earrings, haram→Haram, pendant→Pendant, bangles→Bangles, nosepins→Nosepins, mangalsutra→Mangalsutra |
  | `category` | **"Material Category"** | gold→Gold, silver→Silver, diamond→Diamond, platinum→Platinum, gemstone→Gemstone, pearl→Pearl |
  | `style` | **"Style Aesthetic"** | traditional→Traditional, modern→Modern, fusion→Fusion, antique→Antique, minimalist→Minimalist, bridal→Bridal |
  | `size` | **"Size"** | xs→XS, s→S, m→M, l→L, xl→XL, freesize→Free Size |
  | `metalPurity` | **"Purity"** | 24k→24K (999), 22k→22K (916), 18k→18K (750), 14k→14K (585), 925→925 Silver, 950pt→950 Platinum |
  Layout: Type + Material Category in one row (2 cols md+), then Style + Size + Purity (3 cols md+); stacked on mobile.

### Section 3 — Specifications
- Badge `3`, H2 **"Specifications"**.
- P **"Add weight and stone details so retailers know exactly what they're getting."**
- Three `InputWithSuffix` (`type="number" min="0" step="0.01" placeholder="0.00"`, suffix **"g"**): **"Gross Weight"** (`grossWeight`), **"Stone Weight"** (`stoneWeight`), **"Net Weight"** (`netWeight`). Suffix cell: `h-11 px-3 bg-#F9FAFB text-sm #6B7280 border-l #e5e5e5`. Wrapper focus-within `border-#3B82F6 ring-1`; error → red.
- Stock toggle row (`py-4 justify-between`):
  - **"Available in Stock"** — `text-sm bold #111827 font-gilroy`
  - **"Is this piece ready to shift right away?"** — `text-sm #6B7280 font-gilroy`
  - `Toggle` (`role="switch"`): 44×24 track, on `bg-#22C55E`, off `bg-#E5E7EB`, 20px white knob, `translate-x-5` / `translate-x-0.5`, 200ms ease-in-out, focus ring `#22C55E`.
- When `stockAvailable === false` a **"Production time"** field appears with `animate-fade-in` (`InputWithSuffix id="makeToOrderDays" type="number" min="0" placeholder="eg. 14"` suffix **"days"**, `md:max-w-md`). Turning the toggle ON clears any `makeToOrderDays` error.

### Validation (all run on submit; `errors` object keyed by field id)
| Condition | Error copy |
|---|---|
| no image (only when NOT "upload later") | **"Please upload a product image."** |
| empty/whitespace title | **"Product title is required."** |
| no jewellery_type | **"Please select a jewellery type."** |
| no category | **"Please select a material category."** |
| no style | **"Please select a style aesthetic."** |
| no size | **"Please select a size."** |
| no metalPurity | **"Please select a purity."** |
| grossWeight empty/NaN/≤0 | **"Gross weight must be greater than 0."** |
| stoneWeight `""`/NaN/<0 | **"Stone weight must be 0 or greater."** |
| netWeight empty/NaN/≤0 | **"Net weight must be greater than 0."** |
| `!stockAvailable` and makeToOrderDays empty/NaN/≤0 | **"Production time must be greater than 0 days."** |

On any error: banner error message set to **"Please correct the fields highlighted in red below."**, and after 50ms `document.getElementById(firstErrorKey).scrollIntoView({behavior:"smooth", block:"center"})` + `.focus()`. (Field order for "first error" is the insertion order above; the image error anchors to `id="image"`.) Editing a field clears just that field's error.
**Note:** net/gross/stone weights are NOT cross-validated (net > gross is accepted).

### Error banner
`border border-red-200 bg-red-50 p-4 rounded-lg animate-fade-in`: 32×32 red circle with **"!"**, H3 **"Submission Error"** (`text-sm medium text-red-900`), P = the current error message (`text-sm text-red-700`).

### Submit area
Mobile (`md:hidden`, `pb-10`, gap-3, stacked full-width pills `py-3.5 rounded-full font-gilroy text-base`):
1. **"Submit"** — black; when `isLimitReached` → `bg-gray-300 text-gray-500 cursor-not-allowed` and `disabled`.
2. **"Save & Upload Later"** — white, `border border-black`, hover `bg-gray-50` (never disabled — even at the daily limit).
3. Disclaimer, 10px bold black, centered: **"*By submitting, you allow us to display your product details and images to retailers on the platform."** (with a `<br>` after "and").

Desktop (`hidden md:flex justify-end gap-3`): the same disclaimer at 8px bold (max-w 500px, `mt-6.5`), then **"Save & Upload Later"** (`px-7 py-3 rounded-lg border-black`), then **"Submit"** (`px-7 py-3 rounded-lg bg-black`, disabled style as above).

### Submit pipeline — status machine
`status ∈ {"idle","uploading","saving","done","error"}`. While `uploading|saving|done` the **entire form is replaced** by a centered overlay (`min-h-[50vh] animate-fade-in`): 40×40 spinner (`border-[1.5px] border-celestique-taupe border-t-black rounded-full animate-spin`) + caption `text-sm font-gilroy text-gray-500 uppercase tracking-widest`:
- `uploading` → **"Uploading Image..."**
- `saving` → **"Saving metadata..."**
- `done` → **"Redirecting..."**

**Path A — "Submit" (image required):**
1. `status="uploading"`; `uploadProduct({file, title, jewellery_type, wholesaler_id})` →
   `POST {NEXT_PUBLIC_API_URL}/process`, `multipart/form-data`, fields `file`, `title` (falls back to the Type label), `jewellery_type`, `wholesaler_id`. No `Content-Type` header set.
   Response `{ message, product_id, raw_image_url }`.
   Error mapping (thrown `Error` carries `.status`):
   - 413 → **"File exceeds 10 MB limit."**
   - 415 → **"Unsupported file type. Use JPEG, PNG or WebP."**
   - 429 → `body.detail` or **"Daily upload limit reached. Please try again tomorrow."**
   - other → `body.detail` or **`Upload failed (${status})`**
2. `status="saving"`; server action `saveProduct({product_id, …})` → `supabase.from("products").update({...}).eq("id", product_id).select("id")`.
   Written columns: `wholesaler_id` (auth uid), `wholesaler_email`, `title` (fallback = Type label, else `"Untitled"`), `jewellery_type`, `category`, `style`, `size`, `stock_available` (bool), `make_to_order_days` (parseInt|null), `metal_purity`, `net_weight`/`gross_weight`/`stone_weight` (parseFloat|null), `raw_image_url`; `processed_image_url` and `generated_image_urls` only when non-empty (here both null); `is_published` only if defined (Path A omits it → DB default).
   Failure copies: **"Not authenticated"**, `error.message`, or **"Save blocked: 0 rows updated. Have you run the RLS hotfix SQL in your Supabase dashboard? See SUPABASE_SETUP.sql Step 0."**
3. `status="done"` → `await refetchUsage()` → `router.push("/dashboard/wholesaler/add-product/success")`.
4. On any throw: if `err.status === 429` → refetch usage and set error **"Daily upload limit reached. Please try again tomorrow."**; else `err.message`. `status="error"`, form re-rendered with the banner (all entered values preserved).

**Path B — "Save & Upload Later":**
- With an image selected: identical upload + `saveProduct`, but with `is_published: false`, then `router.push("/dashboard/wholesaler/catalogue")`.
- Without an image: skips the pipeline entirely; `insertProduct(...)` server action inserts a new `products` row (`raw_image_url:null, processed_image_url:null, generated_image_urls:[], is_published:false`) and returns `{success, product_id}`; then → catalogue.
- Validation still runs for every non-image field.

**IMPORTANT for the port:** this screen performs **no polling and shows no AI progress**. The 5s/5-min polling helper (`pollForResult`) and the 5-stage `ProcessingView` component exist in the codebase but are **not wired into add-product** (`ProcessingView` is imported nowhere). The user is told results arrive later (see §7). Polling is only used by the catalogue re-upload flow (§8.4).

`handleReset()` exists (resets form/image/errors/status to idle) but no control calls it.

---

## 7. `/dashboard/wholesaler/add-product/success` — Submitted confirmation

**Files:** `app/dashboard/wholesaler/add-product/success/page.jsx`, `components/product/{MinimalHeader,SubmittedPage}.jsx`, `components/auth/SignOutButton.jsx`.
**Purpose:** confirm the upload and set the 24-hour expectation.
**Document title:** `"Submitted — Celestique"`. No user → `/signin`.

- `MinimalHeader`: fixed full-width, white, `border-b #E5E5E5`, `h-[60px] md:h-[64px] lg:h-[68px]`, `px-4 md:px-8 lg:px-12`, right-aligned; shows `user.email` (14px `#555`, hidden below `md`) + `SignOutButton` (form posting the `signOut` server action; default styling `bg-#0A0A0A text-white px-6 py-3 rounded-xl text-[15px] medium`, label **"Sign out"**).
- Body (centered, `min-h-dvh px-4 py-20`, white):
  - H1 **"Submitted"** — `text-[40px] md:text-[48px] lg:text-[54px]`, `#000000`, `font-family: Georgia, 'Playfair Display', serif`, weight normal, `mb-6`.
  - P (16px / lg 17px, `#6B6B6B`, line-height 1.6, max-w 320/420/480):
    **"Your design is in good hands. We've received your photo and details. Our AI is getting to work you'll see your studio-ready images within 24 hours."**
  - Button **"Back to dashboard"** — `bg-#0A0A0A text-#FFFFFF`, `max-w-[160px] lg:max-w-[320px]`, `py-[18px] lg:py-[16px]`, `rounded-[14px] md:rounded-[16px]`, 16px semibold, `shadow-[0px_6px_16px_rgba(0,0,0,0.25)]` → `router.push("/dashboard/wholesaler")`.
- No loading/error/empty states.

---

## 8. `/dashboard/wholesaler/catalogue` — My Catalogue

**Files:** `app/dashboard/wholesaler/catalogue/page.jsx` (server), `loading.jsx`, `components/wholesaler/catalogue/CatalogueClient.jsx` (477 lines), `CatalogueGrid.jsx` (729 lines — includes its own `ProductDetailModal`), `app/api/catalogue/products/route.js`, `components/shared/{ProtectedImage,FullImageViewer}.jsx`.
**Purpose:** browse / filter / paginate own products, toggle stock & publish, edit, and re-run the AI pipeline.
**Document title:** `"My Catalogue — Celestique"`.

### Server-side first page
Guards: no user → `/signin`; no `role` → `/select-role`; role ≠ wholesaler → `/`.
`searchParams.category` (default `"all"`, lower-cased). Query on `products` (count exact) `.eq("wholesaler_id", user.id)`; category filter uses `.in("jewellery_type", [baseSlug, baseSlug+"s"])` where `baseSlug = category.replace(/s$/,'')`. Order `created_at desc`, `range(0, 19)` — **LIMIT = 20**.
Selected columns: `id,title,jewellery_type,category,style,size,stock_available,make_to_order_days,metal_purity,net_weight,gross_weight,stone_weight,raw_image_url,processed_image_url,generated_image_urls,image_url,wholesaler_email,created_at`.

### Client behaviour (`CatalogueClient`)
- **Module-level cache** `productsCache {data,count,category,filters,page}` survives navigation within the SPA session; state initialises from it when the category matches.
- Refetches through `GET /api/catalogue/products?category=&page=&limit=20&weight[]=&availability[]=&purity[]=` whenever `page | filters | activeCategory` change and the cache does not match (or the list is empty). URL is updated with `window.history.replaceState` (deliberately not the Next router).
- `isLoading` → skeleton grid; `isError` → error block; both reset per fetch.
- **Scroll behaviour**: the filter bar is `sticky top-0 z-40`; a passive scroll listener with a 10px dead-zone hides it (`-translate-y-full`) when scrolling down past 150px and shows it (`translate-y-0`) when scrolling up — `transition-transform duration-300 ease-in-out`.
- Choosing a category resets all filters, sets page 1, closes dropdowns, and after 100ms `document.getElementById("product-grid").scrollIntoView({behavior:"smooth", block:"start"})`.
- Page change: `window.scrollTo({top:0, behavior:"smooth"})`.

### Screen content
- Page background `#f9f9f9`; main `max-w-[1280px] mx-auto px-6 pb-24`.
- H1 **"My Catalogue"** — 32px bold `#111`, `mt-[32px] mb-[8px]`.
- P **"See and manage all your catalogue categories from one place."** — 15px `#666`.
- **Category rail** (horizontal scroll, `scrollbar-hide`): 9 category tiles + a **"View All"** tile.
  - Tile: 72×72 (sm 90×90), `rounded-[12px] overflow-hidden`, image `object-cover`; active → `scale-110 ring-2 ring-#111 ring-offset-1 shadow-lg z-10` (300ms ease-out). Caption 12px `#666` truncated to tile width; active caption `margin-top:8px; color:#111; font-weight:600`.
  - "View All" tile: `bg-#111` (hover `#222`) with **"View All"** (13px bold white) and **"→"** (16px); caption **"All Products"**.
  - Tapping the active category toggles back to `all`.
- **Filter bar** (`id="product-grid"`) — three pill dropdowns:
  | id | Pill label | Options |
  |---|---|---|
  | `weight` | **"Weight"** | "0-2 g", "2-4 g", "4-6 g", "6-10 g", "10-20 g", "20-35 g", "35-50 g", "50-75 g", "75-100 g", "100+ g" |
  | `availability` | **"Availability"** | "In stock", "Within 5 days", "Within 15 days", "Within 30 days", "More than 30 days" |
  | `purity` | **"Purity"** | "24K (999)", "22K (916)", "18K (750)", "14K (585)", "925 Silver", "950 Platinum" |
  - Pill: `px-[18px] py-[10px] rounded-full border text-[14px] medium`; idle white/`#333`/border `#ddd` hover `#f2f2f2`; active or open → `bg-#111 text-white`.
  - With ≥2 selections the label becomes **"{Label} · {n}"**; with ≥1 selection the chevron is replaced by a **"×"** hit-area (`aria-label="Clear filter"`) that clears that group.
  - Dropdown panel: desktop `absolute top-[calc(100%+8px)] min-w-[260px] rounded-[14px] shadow-[0_4px_20px_rgba(0,0,0,0.1)] border-#eee max-h-[300px]`; mobile becomes a bottom sheet `fixed bottom-0 inset-x-0 rounded-t-[20px] shadow-[0_-4px_20px_rgba(0,0,0,0.15)] max-h-[80vh]` with a `bg-black/45 backdrop-blur-xs` backdrop and a **"×"** close button (`aria-label="Close"`).
  - Panel header shows the group label (14px `#999`). Rows: 16px `#111` label + 24×24 checkbox (`rounded-[6px]`; checked `bg-#111 border-#111` with white tick).
  - Server filter semantics (`/api/catalogue/products`): weight → `or(and(net_weight.gte.min,net_weight.lte.max) …)`, `"100+ g"` → `net_weight.gte.100`; availability → `stock_available.eq.true` / `and(stock_available.eq.false, make_to_order_days.lte.5|15|30)` / `…gt.30`; purity → mapped to `24k|22k|18k|14k|925|950pt` via `.in("metal_purity", …)`; also supports `size[]` (not exposed in UI). `limit` clamped to ≤50, `page` ≥1.

### 8.1 Grid states (`CatalogueGrid`)
- **Error**: centered `py-20`, P **"Something went wrong. Please try again."** (14px `#666`), button **"Retry"** (`border-#ddd rounded-full px-4 py-2`) → refetch current category/page/filters.
- **Loading**: `grid grid-cols-2 md:grid-cols-4 gap-[16px]` of 8 `CatalogueCardSkeleton` (`min-h-[300px]`, `catalogue-skeleton-bg` blocks: square image, 80% bar, 50% bar, pill + small bar).
- **Empty**: centered `py-16` — Cloudinary illustration `…/v1775076102/image_1613_bslbzg.png` (220px wide), H3 **"Nothing here yet"** (18px bold `#111`), P **"You haven't added any {displayName} to your catalogue. Upload your first design."**, button **"Upload design"** (`bg-#111 text-white rounded-full px-[28px] py-[12px]`) → `/dashboard/wholesaler/add-product`.
  ⚠️ `displayName` comes from `getActiveCatName()`, which returns **"All Categories"** for the unfiltered view, so the unfiltered empty state literally reads *"You haven't added any All Categories to your catalogue."* (source bug — reproduce or fix deliberately).
- **Populated**: `grid grid-cols-2 lg:grid-cols-4 gap-[16px]`.

### 8.2 Product card (`CatalogueProductCard`, memoised)
- `article` `bg-celestique-light rounded-xl border-#eee shadow-[0_2px_12px_rgba(0,0,0,0.07)]`, hover `shadow-[0_8px_24px_rgba(0,0,0,0.12)] -translate-y-[2px]`, `active:scale-[0.98]`, 200ms. Whole card opens the detail modal.
- Image: `aspect-square bg-#f9f9f9 rounded-t-xl`, rendered through `ProtectedImage` (canvas). Source priority `processed_image_url → generated_image_urls[0] → image_url → raw_image_url`. On error/no URL: grey block with gem glyph + chip **"No Image"** (10px bold uppercase, `bg-gray-100`).
- Body `border-t #eee p-3 md:p-4`: title (14px bold `#111`, truncate) = `title` or capitalised `jewellery_type` or **"Jewelry Piece"**; sub-label = capitalised `jewellery_type` (11px `#aaaaaa`); right edit icon button (16px pencil, `title="Edit Product"`, stops propagation) → `/dashboard/wholesaler/edit-product/{id}`.
- Bottom row: stock toggle 36×20 (`bg-#22c55e` on / `#e0e0e0` off, 16px knob, `translate-x-4`) + label **"In stock"** / **"Out of stock"** (12px `#999`), and net weight `"{n}g"` on the right when present.
- Toggle is **optimistic**: sets local state, `PATCH /api/products/{id}` with `{"in_stock": bool}`; on failure it silently reverts (no toast). Disabled while in-flight.

### 8.3 Product detail modal (defined inside `CatalogueGrid.jsx`)
Backdrop `rgba(0,0,0,0.4)` + `backdrop-blur-sm`, click-outside closes. Panel: white `rounded-[24px] shadow-[0_16px_40px_rgba(0,0,0,0.12)] max-w-[1000px] max-h-[90vh]`, flex column on mobile / row on md.
- **Left (58%)**: main image `aspect-square bg-#F5F5F5 rounded-[16px]`, `ProtectedImage` `object-contain mix-blend-multiply`, hover `scale-[1.02]` + an expand glyph chip (`w-9 h-9 bg-white/85`). Click → `FullImageViewer`. Empty: gem glyph + **"No Image Found"** (14px `#999`).
  Thumbnail strip: first 4 unique images (`processed_image_url || image_url || raw_image_url` then `...generated_image_urls`), 64→72px, `rounded-[10px]`, active thumb `border-[#111] opacity-30`.
- **Right (42%, p-8)**: top-right icon buttons **Edit** (`aria-label="Edit"` → `/dashboard/wholesaler/edit-product/{id}`) and **Close** (`aria-label="Close"`).
  - H2 = title (20px bold `#1A1A1A`), sub `"{Category} • {SKU}"` (14px `#888`) where `SKU = product.sku || "JWL-" + last 6 chars of id, uppercased`, category default **"Jewellery"**.
  - Stock line: dot + **"In stock"** (`#22c55e`) or **"Out of stock"** (`#ef4444`), `|`, then net weight (`"{n}g"`, default **"20g"**).
  - Specifications card `bg-#F8F8F8 rounded-[12px] p-5`: H3 **"Specifications"**, rows **"Purity"** (`product.purity || metal_purity || "24K"`), **"Gross weight"**, **"Stone weight"**, **"Net weight"** — each value `"{n}g"` or **"-"**.
  - CTA button (full width, `border-#111`, hover inverts): label is
    - **"Daily upload limit reached"** when `isLimitReached` (also disabled), else
    - **"Upload Image to AI"** when the product has no images, else **"Re-upload to AI"**.
  - Publish row: **"Publish to Retailer"** (15px semibold) + 50×28 iOS-style switch (`bg-#34C759` on / `#E5E5EA` off, 24px knob, `translate-x-[22px]`, 300ms). Optimistic; `PATCH /api/products/{id}` `{"is_published": bool}`; reverts on failure. Initial value `product.is_published ?? true`.
  - `handleShare` exists (Web Share API, else clipboard + `alert("Link copied!")` for `{origin}/dashboard/wholesaler/products/{id}`) but **no button invokes it**. `savesCount/likesCount/viewsCount` fallbacks ("1.2k"/"3.4k"/"12.5k") are computed but never rendered.

**`FullImageViewer`** (shared): full-screen `bg-black/95 backdrop-blur-xl`, `z-[300]`, `touch-action:none`. Header: **"Back"** pill (white/10, blur) and a counter **"{i+1} / {n}"**. Left/right 56×56 chevron buttons (wrap-around). Bottom thumbnail strip (72×72, active `border-white scale-105`). Desktop-only zoom control (`hidden md:flex`, bottom-right): **−** / range slider `min=1 max=4 step=0.1` / **+** / **"{z.toFixed(1)}x"**. Gestures: pinch-zoom 1–4×, one-finger pan when zoomed (bounds `(zoom-1)*200`), horizontal swipe >60px (with |dy|<40) to change image, double-tap (<300ms) to zoom to 2.5× centred on the tap or reset. Keys: ←/→ navigate, Esc closes. Body scroll locked while open.
**`ProtectedImage`**: renders into a `<canvas>` (`lib/utils/imageProtection.js`), blocks context menu on the canvas AND globally on `document` while mounted, and swallows ⌘/Ctrl+S. Port note: on iOS, replicate as a non-savable image view (disable long-press save / drag).

### 8.4 Re-upload to AI (the only polling flow in the app)
Confirmation dialog (`z-[60]`, `bg-black/60 backdrop-blur-xs`, card `rounded-[24px] p-6 max-w-md animate-fade-in`, click-outside cancels):
- Amber 48×48 warning circle.
- H4 **"Upload Image to AI"** (no existing images) or **"Re-upload to AI?"**.
- P **"Select a base photo below to start the AI processing pipeline for this product."** (no images) / **"This will clear the current processed results. You can optionally replace the base image below."**
- Label **"Base Photo Selection"** (12px semibold).
- Dropzone `h-[140px] border-2 dashed rounded-[16px] bg-#F9F9F9` (drag-over → `border-#1a1a1a bg-#f5f5f5`), image glyph, copy **"Drag new image here, or browse"** (12px semibold `#333`) and **"JPEG, PNG, or WebP is required."** (no images) / **"JPEG, PNG, or WebP. Leave blank to keep current photo."** (11px `#888`). Input `accept="image/jpeg,image/png,image/webp"`.
- With a file chosen: preview + badge **"New Base Photo"** (`bg-#1A1A1A`, 10px) + a red 32×32 remove button (`title="Remove file"`).
- Buttons: **"Cancel"** (outline pill) and the primary pill — **"Upload & Process"** when there are no existing images or a new file is chosen, otherwise **"Re-upload"**; disabled when `!hasImages && !newImageFile`.

Execution (`handleReprocess`), with the main image area replaced by a spinner panel showing the current status text (16px bold) plus the fixed sub-line **"This may take up to a minute"**:
1. `"Initiating re-upload..."`
2. `"Clearing old images..."` → server action `clearProductImages(id)` → `products.update({processed_image_url:null, generated_image_urls:[]})` scoped by `wholesaler_id`.
3. `"Queueing AI pipeline..."` → `reprocessProduct(productId, wholesalerId, file)` →
   `POST {API}/process/{productId}` — with a file: `multipart` `{file, wholesaler_id}`; without: JSON `{"wholesaler_id": uuid}`.
   429 → `body.detail` or **"Daily upload limit reached. Please try again tomorrow."**; else `body.detail` or **`Reprocessing failed (${status})`**.
4. `"AI processing in progress..."` → `pollForResult(productId, onBgRemoved)`:
   - loop every **5000 ms**, deadline **300000 ms (5 min)**;
   - each tick, until it fires once: `HEAD {SUPABASE_URL}/storage/v1/object/public/plant-images/products/temp/reve_{productId}.png` — on 2xx the status text becomes `"Background removed, enhancing..."`;
   - each tick: `GET {API}/product/{productId}` (`cache:"no-store"`); resolves when `generated_image_urls` is a non-empty array (returns up to 4 URLs);
   - timeout throws **"Timed out waiting for processed images (5 min). Please retry."**
5. `"Processing complete!"` → parent state updated with `processed_image_url = variantUrls[0]` and `generated_image_urls = variantUrls`; local file/preview cleared; after **1500 ms** the overlay closes.
- **Failure**: non-429 errors also raise a native `alert(err.message)`; the panel switches to the error state — red 48×48 circle, **"Reprocessing Failed"** (16px bold red), the message (12px `#666`), and a black pill **"Close"** that dismisses the overlay.

### 8.5 Pagination
Shown only when `!isLoading && !isError && totalPages > 1 && products.length > 0`. `totalPages = ceil(totalCount/20)`.
- **"← Previous"** / **"Next →"** (14px `#666`, hover `#111`, `disabled:opacity-30 cursor-not-allowed`).
- Numbers: always 1, last, and current ±1; positions 2 and `last-1` collapse to **"..."** (`#999`). Active number = 32×32 `bg-#111 text-white rounded-full`; others hover `bg-#eee`.

### 8.6 Route-level loading
`catalogue/loading.jsx` is byte-identical to the dashboard `loading.jsx` skeleton (§5).

---

## 9. `/dashboard/wholesaler/edit-product/[id]` — Edit product

**Files:** `app/dashboard/wholesaler/edit-product/[id]/page.jsx`, `components/product/EditProductForm.jsx` (447 lines).
**Purpose:** edit metadata of an existing product (image is read-only here).
**Document title:** `"Edit Product — Celestique"`.

**Server:** no user → `/signin`; missing `id` → `/dashboard/wholesaler/catalogue`; `products.select("*").eq("id",id).eq("wholesaler_id",user.id).single()`; error/not found → `/dashboard/wholesaler/catalogue`.
`searchParams.from === "upload-history"` changes the header back-link to `/dashboard/wholesaler/upload-history` with label **"Back to uploads"**; otherwise `/dashboard/wholesaler` + **"Back to dashboard"**.

**Chrome:** same sticky header/footer as add-product, plus on the right `user.email` (13px `#6B7280 font-sfpro`, hidden <md) and `SignOutButton`.

**Content:**
- H1 **"Edit product"**, P **"Update the details below for your existing listing."**
- Read-only image preview: 200×200 `rounded-xl bg-#F5F5F5 border-#e5e5e5`, `next/image fill object-cover mix-blend-multiply`, source `processed_image_url || generated_image_urls[0] || raw_image_url`. Empty: gem glyph + **"No Image Uploaded"** (12px medium `font-gilroy`).
- Section badge `1` **"Essential details"**, helper **"Update the key information that helps retailers understand and find this piece."** (note: "piece" spelled correctly here, unlike add-product).
- Same field set/labels/placeholders/options as add-product; selects here use the default grey placeholder (`placeholderClassName` not overridden).
- Section badge `2` **"Specifications"**, helper **"Update weight and stone details so retailers know exactly what they're getting."**; same three weight inputs, the same stock toggle rows (**"Available in Stock"** / **"Is this piece ready to shift right away?"**) and the conditional **"Production time"** field.
- Validation: identical rules and identical error strings to add-product (minus the image rule); banner message identical (**"Please correct the fields highlighted in red below."**), same scroll-to-first-error behaviour.
- Error banner heading here is **"Update Error"** (not "Submission Error").
- Buttons: mobile — full-width black pill **"Save Changes"**; desktop — **"Cancel"** (`router.back()`) and **"Save Changes"** (`px-7 py-3 rounded-lg bg-black`).
- Submit: `status="saving"` → full-screen spinner with **"Updating product..."**, then `"done"` → **"Redirecting..."**, then `router.push("/dashboard/wholesaler/catalogue")`. `saveProduct` is called **without** image fields, so `raw_image_url` is written as `undefined` (omitted) — images are untouched.
- Initial values are hydrated from the row (`make_to_order_days`, weights → `.toString()`).

---

## 10. `/dashboard/wholesaler/upload-history` — Uploads Today

**Files:** `app/dashboard/wholesaler/upload-history/page.jsx` (server), `components/wholesaler/upload-history/UploadHistoryClient.jsx`.
**Purpose:** review today's uploads/enhancements and remaining daily quota.
**Document title:** `"Upload History — Celestique"`. No user → `/signin`.

**Server data:**
1. `GET {API}/api/upload-usage?wholesaler_id=…` → `used` (default 0), `limit` (default **20**), `resets_at || resetsAt`.
2. Cycle window: `end = new Date(resetsAt)` (after stripping a doubled `+00:00Z` suffix), `start = end - 24h`. If unparsable → fallback midnight-UTC to next midnight-UTC.
3. `GET {API}/api/upload-history?wholesaler_id=…&start_date={ISO}&limit=100` → array of product-ish records. Any failure logs and yields `[]` (silently empty UI).

**Chrome:** page `bg-#FDFDFD`; sticky header with `BackToDashboardButton` (**"Back to dashboard"** → `/dashboard/wholesaler`); main `max-w-[1200px] mx-auto` with responsive padding.

**Header block:** H1 **"Uploads Today"** (`text-3xl md:text-4xl semibold #111827 font-cirka`); P **"Manage and review the items you have uploaded and generated today."** (`text-sm text-gray-500 font-gilroy`).

**Quota panel** (hidden only if `limitCount === Infinity`): `rounded-2xl border p-5`; normal `bg-white border-#e5e5e5`; at/over limit `bg-#FFFDF5 border-#FBEFBE text-#856404`.
- Row: **"Daily Upload Quota"** / **"{used} / {limit} Used"** (both `text-sm bold font-gilroy`).
- Track `bg-gray-100 h-2 rounded-full`, fill black (amber-500 when limit reached), `width: min(100, used/limit*100)%`, `transition-all duration-500 ease-out`.
- Right block when `resetsAt`: **"Quota Resets At"** (11px bold uppercase `text-gray-400`) + local `h:mm AM/PM`.

**Empty state:** white card `rounded-[24px] border-#e5e5e5 py-20`: 64×64 grey circle with 📸, H3 **"No uploads today"** (18px bold), P **"You haven't uploaded any product listings today. Upload your first design to see it here!"** (14px `text-gray-500`), black pill **"Upload design"** → `/dashboard/wholesaler/add-product`.

**HistoryCard** (`rounded-[20px] border-#e5e5e5 shadow-[0_4px_20px_rgba(0,0,0,0.03)]`, hover `shadow-[0_8px_30px_rgba(0,0,0,0.06)] -translate-y-0.5`, 300ms; left 45% image pane on md+):
- View toggle (only when not processing and not a re-upload): segmented pill in `bg-gray-100 p-1 rounded-full` with **"AI Enhanced"** and **"Original Photo"**; active = white pill + shadow-sm.
- Image area `min-h-[220px]`, `ProtectedImage` `object-contain max-h-[250px]`.
  - **Processing** (`!activeEnhancedImage`): `animate-pulse` block with a 40×40 spinner and **"Processing in background..."** (14px semibold `text-gray-500 font-gilroy`).
  - Fallback strings: **"No enhanced image available"** / **"No original image available"** (14px `text-gray-400`).
  - `activeEnhancedImage = generated_image_urls[activeVariantIndex] || image_url || processed_image_url`; `rawImage = raw_image_url || activeEnhancedImage`.
- Right pane: title (20px bold, from `title` or capitalised `jewellery_type`, else **"Jewelry Piece"**) and **"Uploaded today at {h:mm AM/PM}"** (12px `text-gray-400`) using `triggered_at || created_at` for re-uploads.
- Badges (top-right): **"Re-uploaded"** (blue: `text-blue-800 bg-blue-50 border-blue-200`) when `is_reuploaded`; then **"Processing"** (amber) or **"Enhancement Completed"** (green) — 11px bold, `rounded-full px-3 py-1`.
- Spec chips (`bg-gray-50 border-gray-100 rounded-lg px-3 py-1.5`, caption 10px bold uppercase `text-gray-400` over value 12px semibold): **"Type"**, **"Material"**, **"Purity"**, **"Net Weight"** (value `"{n} g"`), **"Style"** (each only when the field exists) and always **"Stock Status"** → **"In Stock"** (green) or **"Make to Order"** (grey).
- **"AI Variations"** (10px bold uppercase, only when enhanced view + variants exist): row of 40×40 thumbnails, active `border-black scale-105 shadow-sm`, others `border-gray-200`.
- Actions (`border-t pt-5`, two equal buttons): **"Edit Product"** (black, `rounded-xl py-2.5 text-sm semibold`) → `/dashboard/wholesaler/edit-product/{id}?from=upload-history`; **"View in Catalogue"** (white, `border-gray-200`) → `/dashboard/wholesaler/catalogue`.

**UNEXTRACTABLE:** the exact JSON shape of `GET /api/upload-history` — it is produced by the external Railway service; the client only reads `id, title, jewellery_type, category, metal_purity, net_weight, style, stock_available, created_at, triggered_at, is_reuploaded, raw_image_url, image_url, processed_image_url, generated_image_urls`.

---

## 11. `/dashboard/wholesaler/orders` — Orders

**Files:** `app/dashboard/wholesaler/orders/page.jsx` (server, `dynamic="force-dynamic"`, `revalidate=0`), `components/wholesaler/orders/OrdersClient.jsx` (464 lines), `components/shared/{ConfirmationModal,BusinessProfileModal}.jsx`, `components/employee/OrderDetailModal.jsx`, `app/api/orders/[id]/route.js`.
**Purpose:** triage retailer orders through the fulfilment funnel.
**Document title:** `"Orders — Wholesaler Dashboard"`.

**Server:** no user → `/entry_page/signin`; `wholesalers.select("id").eq("user_id")` missing → `/entry_page/signin`.
Side effect: `wholesalers.update({last_checked_orders_at: now}).eq("id", wholesaler.id)` on every visit.
Fetch (service-role client, bypasses RLS on joins):
```
orders.select(`*,
  products ( id, title, raw_image_url, processed_image_url, generated_image_urls,
             jewellery_type, metal_purity, net_weight, category, make_to_order_days ),
  employees ( id, auth_user_id ),
  retailers ( id, business_name, city, state, created_at, email, full_name )`)
 .eq("wholesaler_id", user.id)
 .eq("is_visible_to_wholesaler", true)
 .order("created_at", {ascending:false})
```

**Header:** back link **"Back to home"** (absolute left, 13px medium, chevron) → `/dashboard/wholesaler`; H1 **"Orders"** (36px `font-serif #111827 tracking-wide`); P **"Review and respond to orders from retailers."** (13px `text-gray-500`).

**Tabs** (segmented, `bg-#f4f5f7 rounded-full p-1`, horizontally scrollable): each `px-5 py-2 rounded-full text-[13px] medium`; active `bg-white text-black shadow-[0_1px_3px_rgba(0,0,0,0.1)]`. Every tab carries a count chip (`min-w-[20px] h-[20px] rounded-full text-[10px]`).
| id | Label | Statuses counted/filtered |
|---|---|---|
| `new` | **"New Orders"** | `pending` |
| `active` | **"Active Orders"** | `accepted`, `in_production`, `packed`, `dispatched` |
| `completed` | **"Completed"** | `received`, `completed` |
| `rejected` | **"Rejected"** | `rejected` |
Tab state syncs to `?tab=` via `router.replace(..., {scroll:false})` and reacts to back/forward. Deep link `?tab=new` is used by the dashboard "New Orders" stat card. Invalid/absent tab → `new`.

**Empty state:** `py-24 border-t border-gray-200`, P **"No orders found in this category."** (14px medium `text-gray-400`).

**Order card** (`flex-col md:flex-row gap-8 py-10 border-b border-gray-200`):
- Left: 240px square (`bg-gray-50 border-gray-100 rounded-sm`), `ProtectedImage` of `generated_image_urls[0] || processed_image_url || raw_image_url`; fallback text **"No Image"** (12px `text-gray-400`).
- H3 = capitalised `products.jewellery_type` or **"Item"** (26px bold `#111827`).
- Status badge (top-right, 13px medium):
  - `pending` → hourglass icon + **"Respond in next 18 hours"** (`#d97706`)
  - `accepted` | `in_production` → **"In Production"** (`text-purple-600`)
  - `packed` → **"Packed"** (`text-orange-600`)
  - `dispatched` → **"Dispatched"** (`text-indigo-600`)
  - `received` | `completed` → **"Completed"** (`text-green-600`)
  - `rejected` → **"Rejected"** (`text-red-600`)
- Sub-meta: `"{Category} • SKU #{first id segment uppercased} Q1"` (12px `text-gray-500`). Category default **"Jewellery"**.
- Customisation box (`bg-#fafafa border dashed border-gray-300 rounded-[6px] p-4`): the note text (13px `text-gray-600`) plus a **"Read More"** button (10px semibold uppercase, bottom-right) — **the button has no handler**. If no note: 80px-tall box with italic **"No customization notes provided."** (12px `text-gray-400`).
- Meta line 1: **"Make to order "** + bold `"{n} days"` or **"N/A"** + `|` + the retailer's `business_name` (or **"Unknown Retailer"**) rendered as an underlined clickable that opens the business modal.
- Meta line 2: **"Deliver to: "** + bold `"{city}, {state}"` (defaults **"Unknown City"**, **"State"**).
- Actions (bottom-right on md+):
  - `pending` → **"Reject order"** (red outline `border-#fca5a5 text-#ef4444`, hover `bg-red-50`) and **"Confirm order"** (`bg-#111827` white).
  - `in_production` → **"Mark as Packed"** (`bg-orange-600`).
  - `packed` → **"Dispatch Order"** (`bg-indigo-600`).
  - any status not in `[pending, accepted, in_production, packed]` → **"View Details"** (grey outline) opening `OrderDetailModal`.
  - `rejected` → additionally **"Delete Order"** (`bg-red-600`).
  All buttons `px-6 py-2.5 text-[13px] font-medium rounded-[6px]`.

**Confirmation modals** (`ConfirmationModal`: `z-[100]`, backdrop `bg-black/40 backdrop-blur-sm`, card `max-w-sm rounded-[24px] p-8`, 56×56 tinted icon circle, title 22px bold, message 14px `text-gray-500`, stacked buttons `py-3.5 rounded-xl`, confirm colour by variant: danger `bg-red-600`, primary `bg-#111827`, success `bg-emerald-600`; cancel `bg-gray-50 text-gray-600`):
| Trigger | Title | Message | Confirm | Cancel | Variant |
|---|---|---|---|---|---|
| Confirm order | **"Confirm Order?"** | **"Are you sure you want to accept and start production for this order?"** | **"Yes, Proceed"** | **"Cancel"** | primary |
| Mark as Packed | **"Mark as Packed?"** | **"Has this order been fully packed and prepared for shipping?"** | **"Yes, Proceed"** | **"Cancel"** | primary |
| Dispatch | **"Dispatch Order?"** | **"Are you sure you want to mark this order as dispatched?"** | **"Yes, Proceed"** | **"Cancel"** | success |
| Delete rejected order | **"Delete Order?"** | **"Are you sure you want to delete this rejected order? This action cannot be undone."** | **"Yes, Delete"** | **"No, Keep it"** | danger (default) |

**Reject dialog** (custom, `z-[60]`, backdrop `bg-black/40 backdrop-blur-sm`, card `max-w-md rounded-[20px] p-6 animate-fade-in-up`):
- H2 **"Reject Order"** (18px extrabold), P **"Please provide a reason for rejecting this request."** (13px `text-gray-500`).
- Textarea `h-32 border-gray-200 rounded-[12px] p-4 text-[14px] resize-none`, placeholder **"E.g., Out of stock for this material..."**.
- Buttons **"Cancel"** and **"Confirm Rejection"** (`bg-red-600` white, shadow-md).
- Empty reason → native `alert("Please provide a rejection reason.")`.

**Mutations:**
- `PATCH /api/orders/{id}` body `{status}` (+ `rejection_reason` when rejecting). Server sets `updated_at` plus the matching timestamp column (`rejected_at`/`accepted_at`/`production_at`/`packed_at`/`dispatched_at`/`received_at`/`completed_at`) and defaults the reason to **"No reason provided."**. Ownership is enforced by comparing `orders.wholesaler_id` to `auth.uid`; failures return `401 Unauthorized`, `403 "Forbidden: Wholesaler record not found"` / `403 "Forbidden: You do not own this order"`, `404 "Order not found"`.
- `DELETE /api/orders/{id}` — soft delete: sets `is_visible_to_wholesaler:false` for wholesalers (`is_visible_to_employee` for the other side).
- Client errors surface as `alert(err.message)` with messages **"Failed to update status"** / **"Failed to delete order"**.

**Global busy state:** while any mutation is in flight, a full-screen `z-[100] bg-white/50 backdrop-blur-sm` overlay with a 40×40 black spinner.

**BusinessProfileModal** (opened from the retailer name): `z-[300]`, backdrop `bg-black/20 backdrop-blur-sm`, card `max-w-[500px] rounded-[24px] animate-fade-in-up`. 80×80 gradient avatar (`from-#e8dec9 to-#c9b48a`) with the initial; name 24px; green chip **"Verified"**; **"Member since {Month YYYY}"** (default string **"February 2026"** if no `created_at`); rows for location (default **"Bandra, Mumbai"** when both city/state missing), `email`, and **"Contact: {full_name}"**; footer button **"Back to orders"** (`bg-#111827`). Body scroll locked.

**OrderDetailModal** (`components/employee/OrderDetailModal.jsx`, used with `isEmployee={false}` — the prop is ignored): `z-[200]`, `max-w-5xl rounded-[16px]`, image pane with thumbnails + `FullImageViewer`, **"SKU #…"** heading, hard-coded **"In stock"** line, two purely local toggles **"Available in stock"** and **"Publish to Collection"** (no persistence), and a **"Specifications"** box with rows **"Purity"**, **"Gross weight"**, **"Net weight"**, **"Stone weight"** (fallback values `18 KT`, `10g`, `9.8g`, `0.2g`; fallback Unsplash image if the product has none).

---

## 12. `/dashboard/wholesaler/queries` — Queries (chat)

**Files:** `app/dashboard/wholesaler/queries/page.jsx` (server), `app/dashboard/employee/messages/MessagesClient.jsx` (shared), `components/chat/{ConversationList,ChatWindow,MessageBubble}.jsx`, `lib/hooks/useRealtimeMessages.js`, `app/api/chat/**`.
**Purpose:** two-pane inbox for retailer-employee ↔ wholesaler product enquiries.
**Document title:** `"Queries — Wholesaler Dashboard"`, description `"Manage retailer inquiries and respond to potential leads."`

**Server:** guards as in Orders. Query (service-role):
```
conversations.select(`*,
  product:product_id(title, processed_image_url, raw_image_url),
  employee:employee_id(full_name, retailer_id),
  retailer:retailer_id(business_name),
  wholesaler_profile:wholesaler_id(email),
  messages(id, content, is_read, sender_type, created_at)`)
 .eq("wholesaler_id", user.id).eq("is_visible_to_wholesaler", true)
 .order("updated_at", {ascending:false})
```
Then per conversation: sort messages desc, `last_message = newest content`, `has_unread = any(!is_read && sender_type==="employee")`, and the `messages` array is stripped before sending to the client. Rendered as `<MessagesClient currentUserType="wholesaler" />`.

**Shell:** `h-screen overflow-hidden`; header row with a 36×36 round back button (`gradient from-gray-50 to-gray-200 border-gray-300`, calls `window.history.back()`) and centered H1 **"Queries"** (`text-[24px] md:text-[30px] font-serif #111827`). Panel: `max-w-6xl mx-auto`, card `rounded-[16px] border-gray-200 shadow-sm`. Below `md` only one pane shows at a time (list until a conversation is selected).
Module-level cache (`messagesCache`) with a **30 s TTL** restores conversations and the active id across navigations.
Transient state: while auto-creating a conversation (only reachable from the retailer side) — spinner + **"Opening conversation..."**.

**ConversationList** (`w-full md:w-[320px] border-r`):
- Header: H2 **"Queries"** (16px bold) + sub **"Manage retailer inquiries and respond to potential leads."** (11px `text-gray-400`).
- Filters: **"All"** and **"Unread"** pills (`rounded-full text-[12px]`; active `bg-gray-900 text-white`); the Unread pill carries a count chip when >0.
- Empty: chat glyph + **"No queries yet"** (13px semibold) + **"Queries from retailers will appear here."** (11px).
- Row (`px-5 py-4 border-b`, active `bg-gray-50`): product title (13px semibold, truncate; default **"Product Enquiry"**), optional **"Unread"** badge (`bg-blue-600` white, 9px uppercase tracking-widest), `from: {retailer.business_name || employee.full_name || "Retailer"}` (11px), last-message preview (12px, truncate), and a clock icon + relative time: **"just now"**, **"{n} minute(s) ago"**, **"{n} hour(s) ago"**, **"{n} day(s) ago"**, else `toLocaleDateString("en-IN",{month:"short",day:"numeric"})`.

**ChatWindow** (`bg-#FAFAFA`):
- No selection: chat glyph + **"Select a query to view details"** (16px semibold) + **"Click on a query from the list to read and respond"** (13px `text-gray-400`).
- Header 72px: mobile-only back arrow; 40×40 avatar circle (gradient `from-blue-100 to-indigo-100`, blue initial); partner name = `employee.full_name || "Employee"`, sub = `retailer.business_name || "Retailer"`; product mini-card (hidden <sm) with 32×32 thumb, caption **"Regarding"** and the product title; **"Delete Chat"** button (red, `title="Hide conversation from your list"`).
  - Delete flow: native `confirm("Are you sure you want to delete this conversation from your list? It will still be visible to the other party.")` → `DELETE /api/chat/conversations/{id}` (soft: `is_visible_to_wholesaler:false`) → `window.location.reload()`; on failure `alert("Error hiding conversation: " + message)`.
- Message area: loading → 24×24 spinner; error → the error string in red 13px; empty → **"No messages yet"** (14px semibold) + **"Send a message to start the conversation."** (12px).
- `MessageBubble`: own messages right-aligned `bg-#111827` white `rounded-[16px] rounded-br-[4px]`; others white with `border-gray-100`, `rounded-bl-[4px]`; max-width 75% (md 65%); timestamp 10px `toLocaleTimeString("en-IN",{hour:"2-digit",minute:"2-digit",hour12:true})`; own messages show a read receipt (blue filled check when `is_read`, grey outline check otherwise).
- Composer (hidden for `currentUserType === "retailer"`): auto-growing textarea, placeholder **"Type a message..."**, `min-h-[40px] max-h-[120px]`, wrapper `bg-gray-50 border-gray-200 rounded-[16px]`; Enter sends, Shift+Enter newlines; 48×48 round send button `bg-#111827` (spinner while sending, disabled when empty/sending); hint **"Press Enter to send, Shift+Enter for new line"** (10px `text-gray-400`). Failure → `alert("Failed to send message. Please try again.")` and the text is restored into the input.
- Realtime (`useRealtimeMessages`): initial `GET /api/chat/messages?conversation_id=…`, then a Supabase channel `messages:{conversationId}` subscribing to `INSERT` and `UPDATE` on `public.messages` filtered by `conversation_id=eq.{id}`. Auto-scrolls to bottom on every change.
- Read receipts: when the unread count (messages whose `sender_type !== "wholesaler"`) changes and is >0, `PATCH /api/chat/messages/read` `{conversation_id}` marks all `sender_type="employee"` messages read.
- Sending: `POST /api/chat/messages` `{conversation_id, content}` → server derives `sender_type:"wholesaler"`, inserts, and bumps `conversations.updated_at`. Errors: 400 `"conversation_id and content are required"`, 401 `"Unauthorized"`, 403 `"Forbidden to send message in this conversation"`, 404 `"Conversation not found"`.

---

## 13. `/dashboard/wholesaler/add-retailer` — Referral

**Files:** `app/dashboard/wholesaler/add-retailer/page.jsx`, `addRetailer.module.css`, `components/wholesaler/referral/ReferralManager.jsx`, `referralManager.module.css`, `app/api/referral/generate/route.js`.
**Purpose:** generate and share referral links that bind new retailers to this wholesaler.
**Document title:** `"Add Retailer — Jewel India"`, description `"Generate referral links to invite retailers."`

**Server guards:** no user → `/entry_page/signin`; `role !== "wholesaler"` → `/`; `wholesalers` row missing **or `verification_status !== "verified"`** → `/onboard/submitted`.
**Data:** `referral_links.select("id, code, uses_count, max_uses, is_active, created_at").eq("wholesaler_id", wholesaler.id).order("created_at", desc)`; each mapped to `link = "{NEXT_PUBLIC_SITE_URL}/join/{code}"`.

**Layout** (`.container`: `padding 48px 64px; max-width 1000px; margin 0 auto; font-family Inter` — 32px/40px at ≤1024px, 24px/20px at ≤768px):
- H1 **"Referral"** — `clamp(28px,4vw,36px)` 700 `#111111`, letter-spacing -0.02em.
- P **"Grow your retailer network by sharing a simple invite link. Every signup is automatically linked to you."** — `clamp(14px,2vw,15px)` `#6B7280`.
- **3-step flow** (row on desktop with two dashed SVG arcs `M15,30 Q50,-10 85,30`, stroke `#D1D5DB` 1.5 dashed `6,6`, positioned `left:16.66%` / `left:50%`, `top:clamp(30px,4vw,45px)`; at ≤768px it stacks with a vertical 2px dashed divider and the arcs hide). Step icons `clamp(60px,8vw,90px)` from Cloudinary.
  1. **"1. Share the link"** — **"Invite retailers by sending them a unique link."** (icon `…/v1777306586/LINK_spu884.svg`)
  2. **"2. Signup"** — **"They join using your link and get linked to your account."** (`…/v1777306586/signup_vlrosz.svg`)
  3. **"3. Retailer shop setup"** — **"Retailers complete their store setup and go live."** (`…/v1777306585/retailerShop_iashfb.svg`)
- **ReferralManager**:
  - H2 **"Link to referral program"** (`clamp(20px,3vw,24px)` 700).
  - P **"Create and share your referral link to start onboarding retailers instantly."**
  - Read-only input, `height 56px; background #F3F4F6; radius 8px`, placeholder **"Generate a link to see it here..."** (padding right 88px when filled / 48px when empty). Inside on the right: a copy icon button (disabled + `opacity .3` until a link exists, `title="Copy link"`) and, when filled, a ✕ clear button (`title="Clear link"`). After copying, a green **"Copied!"** (12px `#16A34A`) appears for **2000 ms**.
  - Button **"Generate Link"** (56px tall, `background #111`, white, radius 8px, 15px/600, link glyph inverted to white); while pending the label is **"Generating..."** and it is disabled (`opacity .7`).
  - Under the button, right-aligned 11px `#9CA3AF` 600: **"*Your links are secure and used only for"** / **"tracking referrals."**
  - Error line (13px `#DC2626`, `margin-top 12px`): API `error` string, or **"Network error. Please try again."**, or fallback **"Failed to generate link."**
  - **"PREVIOUS LINK"** section (12px 600 uppercase `#6B7280`, letter-spacing .05em) — rendered when `links.length > 0`, listing only links created within the last 30 days (`ceil(diff/86400000) <= 30`). Each row (`padding 16px 0`, bottom border `#E5E7EB` except last): 8px green dot `#22C55E`, chip **"Active"** (`bg #DCFCE7`, `#16A34A`, radius 16px, 13px/600) — **hard-coded, not derived from `is_active`** — the URL in monospace `#4B5563` (ellipsised), a copy button (swaps to **"Copied!"** for 2 s), and a date chip `dd/Mon/yyyy` (`bg #F3F4F6`, `#6B7280`, radius 20px). On ≤768px the row wraps and the URL moves to its own line (`order:3`).
  - `POST /api/referral/generate` body `{}` → `{id, code, link, max_uses, uses_count, is_active, created_at}`. Code format `{up-to-4 business initials or "JW"}-{6 chars from "abcdefghijklmnpqrstuvwxyz23456789"}`; 5 retries on unique-violation (`23505`).
    Errors: 401 **"Unauthorized — please sign in."**, 403 **"Only wholesalers can generate referral links."**, 403 **"Only verified wholesalers can generate referral links."**, 404 **"Wholesaler record not found."**, 500 **"Could not generate a unique code. Please try again."**
  - Clipboard fallback uses a hidden `<textarea>` + `document.execCommand("copy")`.
  - No empty state beyond hiding the PREVIOUS LINK block; no loading skeleton.

---

## 14. `/dashboard/my-uploads` — legacy portfolio view (⚠️ broken)

**Files:** `app/dashboard/my-uploads/page.jsx`, `components/product/WholesalerUploads.jsx`, `lib/api/supabase-products.js`.
**Purpose (intended):** editorial grid of every processed piece the wholesaler has uploaded.
**Document title:** `"My Uploads — Celestique"`. Guards: no user → `/signin`; no role → `/select-role`; role ≠ wholesaler → `/`.

**Defect to be aware of before porting:** the page calls `getProductsByWholesaler(user.email)` — a **string** — but the function signature destructures `{wholesaler_id, email, category, page, limit}`. So `email` is `undefined`, the function returns `{data: [], count: 0}`, and `WholesalerUploads` receives an object (not an array): `products.length` is `undefined`, so the count renders blank and the component always falls into its empty state. Nothing in the wholesaler navigation links here (it is reachable only by typing the URL). Treat as dead/legacy unless the product owner wants it revived.

Copy (for completeness):
- Header links: **"← Upload Studio"** → `/dashboard/wholesaler/add-product`; **"/ MY UPLOADS"**; user email; `SignOutButton`.
- Hero: **"/ YOUR PORTFOLIO"**, H1 **"My Uploads"** (`font-serif text-5xl md:text-7xl uppercase`), email, big count + **"pieces uploaded"**.
- Card: `aspect-4/5` image with prev/next arrows and dot indicators over `generated_image_urls` (fallback `processed_image_url`), a variant chip `"{i+1} / {n}"`, status badge **"Live"** (when `stock_available`) or **"Made to Order"**; meta = title / capitalised type + **" Piece"**, category, `metal_purity` + `" · {net_weight}g net"`, **"Uploaded {dd Mon yyyy}"**.
- Empty: gem glyph, H2 **"No pieces yet"**, P **"Your uploaded jewelry will appear here once your first piece is processed."**

---

## 15. Appendix A — components that exist but are NOT part of the live wholesaler flow

Do not port these unless explicitly asked:
- `components/product/ProcessingView.jsx` — the 5-stage AI progress UI (stages **"Upload" / "Bg Removal" / "4 Variants" / "Saving" / "Complete"**; variants **"Stone — Classic" / "Dark navy-blue stone"**, **"Velvet — Boutique" / "Burgundy velvet cushion"**, **"Marble — Editorial" / "White Carrara marble"**, **"Charcoal — Dramatic" / "Deep charcoal gradient"**; headings **"Uploading your image"** / **"Preparing for Reve AI pipeline"**, **"Removing background"** / **"Isolating the jewellery piece"**; chips **"Reve AI — Background Removed"**, **"Nanobana AI — 4 Variants"**, **"Generating concurrently"**, **"{n} / 4 generated"**, **"Saving metadata"**, **"Background removed. Generating styled variants"**, **"{n} variant(s) saved"** / **"Available in catalogue"**, links **"Download V{n}"**, button **"Add Another Product"**). **Imported nowhere.** It is the best available reference if the iOS app is meant to show live AI progress.
- `components/product/{Hero,ProductCard,ProductDetailModal}.jsx` — used only by the public `app/page.jsx` marketing/discovery page. `Hero` is the only GSAP+Lenis usage in the app (Lenis `duration:1.1`, easing `t => Math.min(1, 1.001 - 2^(-10t))`, `gsap.ticker.lagSmoothing(0)`, ScrollTrigger pinned timeline `start:"top top" end:"+=120%" scrub:true pin:true anticipatePin:1`, animating `clip-path: inset(20% 15% 20% 15% round 32px) → inset(0 round 0)`, `scale .9→1`, title `scale 1.5 + blur(20px) + opacity 0`, inner img `scale 1→1.15`).
- `components/onboard/IdentityForm.jsx` (root copy — superseded by `step1/IdentityForm.jsx`; placeholder differs: `"•••• •••• •••• **** **** ****"`).
- `components/onboard/step1/Step1Footer.jsx` (superseded by the inline footer in `Step1Container`; its legal line is the 12px `#9CA3AF` variant).
- `components/wholesaler/WeeklyReviewBanner.jsx` (imported by the dashboard page but never rendered).
- `components/wholesaler/orders/orders.module.css` (558 lines) and `components/wholesaler/queries/queries.module.css` (547 lines) — **referenced by no file**; the live Orders/Queries screens are Tailwind-only. Ignore them.

## 16. Appendix B — network contract summary (wholesaler surface)

| Call | Method | Payload | Used by |
|---|---|---|---|
| `/api/onboard/submit` | POST multipart | name, aadhar, businessName, state, city, aadharFront, aadharBack, panCard, gstCertificate, businessLogo | §3 |
| `{API}/process` | POST multipart | file, title, jewellery_type, wholesaler_id → `{message, product_id, raw_image_url}` | §6 |
| `{API}/process/{id}` | POST multipart or JSON | `{file, wholesaler_id}` or `{wholesaler_id}` | §8.4 |
| `{API}/product/{id}` | GET | → product row incl. `generated_image_urls` | §8.4 polling |
| `{SUPABASE}/storage/v1/object/public/plant-images/products/temp/reve_{id}.png` | HEAD | existence probe for bg-removed intermediate | §8.4 |
| `{API}/api/upload-usage?wholesaler_id=` | GET | → `{used, limit, resets_at}` | §5, §6, §8, §10 |
| `{API}/api/upload-history?wholesaler_id=&start_date=&limit=100` | GET | → array | §10 |
| `/api/catalogue/products` | GET | category, page, limit, weight[], availability[], purity[], size[] → `{data, count}` | §8 |
| `/api/products/{id}` | PATCH | `{in_stock}` and/or `{is_published}` → `{success, product}` | §8.2, §8.3 |
| `/api/orders/{id}` | PATCH / DELETE | `{status, rejection_reason?}` / soft-hide | §11 |
| `/api/chat/messages` | GET / POST | `?conversation_id` / `{conversation_id, content}` | §12 |
| `/api/chat/messages/read` | PATCH | `{conversation_id}` | §12 |
| `/api/chat/conversations/{id}` | DELETE | soft-hide | §12 |
| `/api/referral/generate` | POST | `{}` (optional `{max_uses}`) → link object | §13 |
| Server actions | — | `saveProduct`, `insertProduct`, `clearProductImages`, `signOut`, `terminalUserExit` | §3, §6, §8, §9 |
| Supabase Realtime | WS | channel `messages:{conversationId}`, INSERT+UPDATE on `public.messages` | §12 |

Polling constants: `POLL_INTERVAL_MS = 5000`, `POLL_TIMEOUT_MS = 300000`, storage bucket `plant-images`.
