# 02 — Auth & Session: complete map of the Next.js web app (for exact SwiftUI parity)

Source of truth: `/Users/parashrautela/Documents/jewel india /Jewel-India-Frontend`
All file paths below are relative to that root. Every string in quotes is copied verbatim from source.

---

## 0. Environment, clients, and the middleware entry point

### 0.1 Env vars (`.env`)

| Key | Value |
|---|---|
| `NEXT_PUBLIC_API_URL` | `https://ai-pipeline-production-3f9a.up.railway.app` |
| `NEXT_PUBLIC_SITE_URL` | `https://app.jewelindia.shop` |
| `NEXT_PUBLIC_SUPABASE_URL` | `https://ljxgwiuvdpuarvdszjts.supabase.co` |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxqeGd3aXV2ZHB1YXJ2ZHN6anRzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE0MzczNTksImV4cCI6MjA4NzAxMzM1OX0.7tLGTSHxwc5MyY5qaYO1sbHZmdPNrE0ZI2Wr-zeS-_I` |
| `SUPABASE_SERVICE_ROLE_KEY` | present in `.env` — **server-only**, must never ship in the iOS binary |

`lib/utils/url.js → getURL()` resolves the redirect base as
`NEXT_PUBLIC_SITE_URL ?? VERCEL_PROJECT_PRODUCTION_URL ?? NEXT_PUBLIC_VERCEL_URL ?? VERCEL_URL ?? "http://localhost:3000"`,
prefixes `https://` if no scheme, strips a trailing `/`. In production it is always `https://app.jewelindia.shop`.

### 0.2 Supabase clients

| File | Client | Key | Notes |
|---|---|---|---|
| `lib/supabase/client.js` | `createBrowserClient(URL, ANON_KEY)` from `@supabase/ssr` | anon | 8 lines, no options. Browser/PKCE cookie owner. |
| `lib/supabase/server.js` | `createServerClient(URL, ANON_KEY, {cookies:{getAll,setAll}})`, wrapped in React `cache()` | anon | `setAll` is wrapped in `try{}catch{}` — "setAll called from Server Component — safe to ignore" |
| `lib/supabase/admin.js` | `createClient(URL, SUPABASE_SERVICE_ROLE_KEY)` from `@supabase/supabase-js` | **service role** | 6 lines. Bypasses RLS. |
| `lib/supabase/middleware.js` | `createServerClient(URL, ANON_KEY, …)` bound to `NextRequest` cookies | anon | exports `updateSession(request)` |

`lib/supabase/queries.js → getAuthUser()` = `cache(async () => (await createClient()).auth.getUser() → user ?? null)`.
Called once in `app/layout.jsx` and passed into `<AuthProvider initialUser={…}>`.

### 0.3 There is NO `middleware.js` — it is `proxy.js` (Next.js 16)

`proxy.js` (root, 21 lines):

```js
import { updateSession } from "./lib/supabase/middleware";
async function proxy(request) { return await updateSession(request); }
export default proxy;
export const config = {
  matcher: [
    "/((?!api|_next/static|_next/image|favicon.ico|robots.txt|sitemap.xml|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)",
  ],
};
```

**`/api/**` is explicitly excluded from the proxy** (comment: "middleware destroys POST FormData streams"). API route handlers do their own auth.

### 0.4 `next.config.mjs` redirects (these fire outside the proxy)

```js
async redirects() {
  return [
    { source: '/',       destination: '/entry_page/signin', permanent: false },  // 307
    { source: '/signin', destination: '/entry_page/signin', permanent: true  },  // 308
    { source: '/signup', destination: '/entry_page/signup', permanent: true  },  // 308
  ];
}
```

Consequences that matter for the iOS port:
- **`app/page.jsx` (the "Celestique" marketing storefront) is unreachable** — `/` always redirects. Do not port it.
- Every `redirect("/signin")` / `redirect("/signup")` in the codebase (e.g. `signOut()`, proxy §1 `!user`) actually lands on `/entry_page/signin` / `/entry_page/signup`.
- Also: `serverActions.allowedOrigins: ['app.jewelindia.shop', '*.jewelindia.shop', 'localhost:3000']` — a native iOS client cannot satisfy the Server-Action origin/Next-Action-ID protocol at all (see §4 class C).

### 0.5 App shell — `components/auth/AuthProvider.jsx`

Client context. `useState(initialUser)`, then in a `useEffect` with empty deps:
`supabase.auth.onAuthStateChange((_event, session) => setUser(session?.user ?? null))`, unsubscribes on unmount.
`useAuth()` throws `"useAuth() must be called inside <AuthProvider>. Make sure AuthProvider wraps your component tree."` when the context is null.
→ iOS equivalent: an `@Observable AuthStore` subscribing to `supabase.auth.authStateChanges`.

---

## 1. The shared auth chrome — `components/auth/AuthLayout.jsx`

Every auth screen except `/employee-login` and `/select-role` renders inside this. Exact values:

- Root: `display:flex; height:100vh; width:100%; overflow:hidden`
- **Left image panel**: `width: 62%`, `height: 100%`, `flexShrink: 0`, class `hidden md:block` (hidden < 768px → **on iPhone this panel does not exist**; it should appear on iPad ≥768pt).
  Default image `https://res.cloudinary.com/dcs0vuzwg/image/upload/v1774883373/authImg_ivftu7.png`, `alt="Jewellery"`, `objectFit: cover`, `priority`.
  Every auth page passes this exact same `imageSrc`.
- **Right panel**: `flex-1 w-full max-w-[520px] bg-white h-screen overflow-y-auto flex flex-col px-6 md:px-12 py-8 md:pt-12`, scrollbar hidden.
- **Logo row**: `display:flex; alignItems:center; gap:12px; marginBottom:32px`
  - Square: `48×48`, `background: #6B4F4F`, `borderRadius: 10px`, centered text `"JI"` — `color #FFFFFF`, `fontWeight 700`, `fontSize 15px`, `letterSpacing 0.02em`
  - Wordmark: `"Jewels India"` — `fontWeight 700`, `fontSize 17px`, `color #111111`, `letterSpacing 0.01em`
- **Heading (`title`)**: `fontFamily: Georgia, serif`, `fontSize: 44px`, `fontWeight: 700`, `color: #111111`, `lineHeight: 1.1`, `margin: 0 0 8px`
- **Subheading (`subtitle`)**: `fontSize: 15px`, `color: #888888`, `margin: 0 0 36px`, `lineHeight: 1.5`, `fontWeight: 400`
- **Children wrapper**: `display:flex; flexDirection:column; flex:1`

Fonts loaded in `app/layout.jsx` via `next/font/google`: `Bodoni_Moda` → `--font-bodoni`, `Jost` → `--font-jost`, `Manrope` → `--font-manrope-var`. Body class: `font-sans antialiased text-celestique-dark`.
Note: AuthLayout's heading uses literal `Georgia, serif`, **not** the Bodoni variable.

Design tokens referenced by `/select-role` (`app/globals.css` `@theme`):
`--color-celestique-taupe:#E6DFD3`, `--color-celestique-cream:#F5F2EB`, `--color-celestique-dark:#111111`, `--color-celestique-light:#ffffff`, `--color-celestique-muted:#8C857B`, `--color-celestique-border:#D9D0C5`.

---

## 2. Screen-by-screen specification

### 2.1 `/entry_page` — pure redirect

`app/entry_page/page.jsx` (5 lines): `redirect("/entry_page/signup")`. No UI.

---

### 2.2 `/entry_page/signup` — **Entry screen** (identity capture; this is the app's real front door)

Files: `app/entry_page/signup/page.jsx` + `components/auth/EntryForm.jsx`
Document title: `"Get Started — Celestique"`

**Copy**
| Slot | Exact string |
|---|---|
| Heading | `Welcome` |
| Subheading | `Sign in to explore Jewellery all over India` |
| Field label | `Email or Phone number` |
| Field placeholder | `Enter` |
| Divider | `OR` |
| Google button (idle) | `Google` |
| Google button (busy) | `Redirecting...` |
| Submit (idle) | `Continue` |
| Submit (busy) | `Checking...` |
| Legal | `By continuing, you agree to our ` + **`Terms of Service`** + ` and ` + **`Privacy Policy`** (both bold `#333333`, underlined, `cursor:pointer`, **no href — dead links**) |

**Input field styling (inline)**: `id="identity"`, `type="text"`, `autoComplete="username"`, `required`.
`width:100%; height:52px; border:1.5px solid #D9D0C5; borderRadius:8px; padding:0 14px; fontSize:14px; color:#111111; background:#FAFAFA; outline:none; boxSizing:border-box; transition:border-color 0.2s; marginBottom:20px`.
onFocus → `borderColor:#111111`; onBlur → `borderColor:#D9D0C5`.
Label: `display:block; fontSize:13px; fontWeight:600; color:#333333; marginBottom:8px; letterSpacing:0.01em`.

**Error row**: `display:flex; alignItems:flex-start; gap:8px; marginBottom:12px`; a `5×5` dot `borderRadius:50%` `background:#EF4444` `marginTop:5px`; text `fontSize:12px; color:#DC2626; fontWeight:500`.

**Google button**: `width:100%; height:52px; border:1px solid #E0E0E0; borderRadius:8px; background:#FFFFFF; gap:10px; fontSize:14px; fontWeight:500; color:#111111`. Disabled while `googleLoading` → `opacity:0.6; cursor:not-allowed`. Hover → `background:#F5F5F5`. Inline 18×18 4-path Google "G" SVG with fills `#4285F4`, `#34A853`, `#FBBC05`, `#EA4335`.

**OR divider**: two `flex:1; height:1px; background:#E0E0E0` rules with `margin:16px 0`, label `OR` — `fontSize:11px; color:#999999; fontWeight:500; letterSpacing:0.05em`, `gap:12px`.

**Continue button**: `width:100%; height:56px; borderRadius:8px; fontSize:15px; fontWeight:600; letterSpacing:0.02em; color:#FFFFFF; marginBottom:16px`.
Enabled background `#1A1A1A` (hover `#333333`); **disabled/loading background `#BBBBBB`, `cursor:not-allowed`**.
`disabled = loading || !identity.trim()`.
Legal paragraph: `fontSize:13px; color:#888888; lineHeight:1.5; margin:0 0 32px`.
Layout: top cluster, then `<div style={{flex:1}}/>` spacer, then the button pinned toward the bottom.

**Mount effects** (`useEffect` on `searchParams`):
- `?error=banned` → error text set to `"Your account has been banned. Please use a different number or email."`
- any other `?error=<x>` → `decodeURIComponent(x)`, falling back to the raw value if decoding throws.
- `?ref=<code>` → `sessionStorage.setItem("referral_code", ref)`
- `?role=<r>` → `sessionStorage.setItem("referral_role", role)`

**Validation (client, before any network call)**
1. `if (!identity.trim()) return;` — silent no-op.
2. `isEmail = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(identity.trim())`
3. If not email → `validateIndianMobile()` (see §3). On failure: error `"Please enter a valid 10-digit Indian mobile number."`, `loading=false`, abort. On success the identity is replaced by the E.164 form `+91XXXXXXXXXX`.

**Network sequence on Continue**
1. `POST /api/auth/check-user` body `{ identity: normalizedIdentity }`
   - `!res.ok` → error = `checkData.error || "Something went wrong. Please try again."`
   - `exists === true && provider === "google"` → sets error `"You signed up with Google. Redirecting..."` (shown in the red error slot even though it is a success path), `googleLoading = true`, then `initiateGoogleOAuth(window.location.origin + "/auth/callback" + (referral_role ? "?role=" + referral_role : ""))`. On OAuth error → show it, `googleLoading=false`.
   - `exists === true` (non-google) → `sessionStorage.setItem("auth_identity", normalizedIdentity)` then `router.push("/entry_page/signin?identity=" + encodeURIComponent(normalizedIdentity))`
   - `exists === false` → step 2.
2. `POST /api/auth/send-otp` body `{ identity: normalizedIdentity }`
   - `!res.ok` → error = `otpData.error || "Failed to send OTP. Please try again."`
   - ok → `sessionStorage.auth_identity = normalizedIdentity`, `sessionStorage.otp_sent_at = new Date().toISOString()`, then
     `router.push("/entry_page/signup/verify-otp?role=" + (searchParams.role || sessionStorage.referral_role || "wholesaler"))`
3. Any thrown exception in the whole block → `"Network error. Please check your connection and try again."`, `loading=false`.

**States**: idle · loading ("Checking...", button grey+disabled) · google-redirecting ("Redirecting...", google button 60% opacity) · error (red dot + message, cleared on every keystroke) · disabled (empty input).
**Note the loading-state leak**: on the two success paths (`router.push`) `loading` is never reset — the button stays "Checking..." until the route changes. Reproduce or fix deliberately.

---

### 2.3 `/entry_page/signin` — **Password sign-in for an existing identity**

Files: `app/entry_page/signin/page.jsx` + `components/auth/SignInForm.jsx`
Document title: `"Welcome Back — Celestique"`

**Copy**
| Slot | Exact string |
|---|---|
| Heading | `Welcome` |
| Subheading | `Sign in to explore Jewellery all over India` |
| Identity label | `Email or Phone number` |
| Identity "change" action | `Change` |
| Password label | `Password` |
| Password placeholder | `Enter your password` |
| Link | `Forgot Password?` → `/forgot-password` |
| Checkbox label | `Remember me` |
| Submit (idle) | `Continue` |
| Submit (busy) | `Signing in...` |
| Legal | `By continuing, you agree to our Terms of Service and Privacy Policy.` (`Terms of Service` / `Privacy Policy` are `<a href="#">`, underlined `#374151`) |

**Identity is read-only**, rendered as a chip, not an input:
`h-[48px] w-full px-[12px] border-[1.5px] border-[#E5E7EB] bg-[#F9FAFB] rounded-[8px]`, value `text-[15px] text-[#111827] font-medium truncate`.
If `identity` is all digits (`/^\d+$/`) a `+91` prefix span is rendered before it (`text-[#111827] text-[15px] font-medium`). NB: identities arriving from EntryForm are already `+91…` so they contain a `+` and this prefix does **not** show; it only shows if a bare digit string was stored.
`Change` button (`text-[13px] text-[#374151] font-semibold`, hover underline) → `sessionStorage.removeItem("auth_identity")` + `router.push("/entry_page/signup")`.

**Identity resolution on mount**
1. `?identity=` present → `setIdentity(decodeURIComponent(urlIdentity))`.
2. else `sessionStorage.getItem("auth_identity")`.
3. If neither → `router.replace("/entry_page/signup")`.

`?error=<x>` seeds the error state (decoded, raw fallback).

**Password input**: `id/name="password"`, `type` toggles password/text, `required`, `autoComplete="current-password"`, `h-[48px] w-full border-[1.5px] border-[#E5E7EB] bg-white rounded-[8px] px-[12px] pr-[40px] text-[15px] text-[#111827] placeholder:text-[#9CA3AF]`. Eye toggle button at `right-[12px]`, `20×20` heroicons eye / eye-slash, `text-[#9CA3AF]`, `tabIndex={-1}`.

**Remember me**: `14×14` checkbox, `rounded-[3px] border border-[#E5E7EB]`, label `text-[14px] text-[#6B7280]`. **Purely cosmetic — `rememberMe` state is never read or sent anywhere.**

**Submit button**: `w-full h-[48px] bg-[#1F2937] hover:bg-[#111827] text-white text-[14px] font-bold rounded-[12px]`, `disabled:opacity-70 disabled:cursor-not-allowed`, `id="signin-btn"`. `disabled = loading` only (an empty password is blocked by the HTML `required`).

**Error display**: `flex items-start gap-2 animate-fade-in -mt-[4px]`, 1×1 (`w-1 h-1`) red-500 dot at `mt-1.5`, `text-[12px] text-red-600`.

**Call**: builds `FormData` from the form, then `formData.set("email", identity)`, then calls the **Server Action** `signIn(formData)` (`lib/actions/auth.js`). Only errors return; success throws a redirect. See §4-C1 for the exact logic iOS must reimplement.

**Error strings surfaced here**: whatever `supabase.auth.signInWithPassword` returns (`error.message`, e.g. `"Invalid login credentials"` — verbatim from GoTrue, not remapped) and, for employees, `"Your account has been deactivated by the store administrator."`.

**States**: idle · loading (`Signing in...`, 70% opacity) · error · redirect-on-success (no success UI).

---

### 2.4 `/entry_page/signup/verify-otp` — **8-digit OTP**

Files: `app/entry_page/signup/verify-otp/page.jsx` + `components/auth/OtpForm.jsx`
Document title: `"Verify OTP — Celestique"`

**Heading is a two-line JSX node**: `Create a` / `Wholesaler Account`, each span `text-[28px] sm:text-[32px] md:text-[44px]` (overrides AuthLayout's 44px at small widths). `subtitle = null`.
**The heading is hard-coded "Wholesaler Account" even when `?role=retailer`.**

**Constants**: `OTP_VALIDITY_SECONDS = 60`, `RESEND_COOLDOWN_SECONDS = 30`, `MAX_RESENDS = 5`.

**Copy**
| Slot | Exact string |
|---|---|
| Sub-line | `The 8-digit OTP has been sent to you at` + `<br/>` + `{identity}` + `Edit` button |
| Wrong-OTP error | `Invalid OTP! 2 attempts remaining` — **hard-coded, the "2" never changes** |
| Incomplete-code error | `Please enter the complete 8-digit code.` |
| Generic verify error | `Invalid OTP. Please try again or resend.` (used when the API returns no `error`) |
| Locked banner | `All 5 resend attempts used. Priority locked.` |
| Timer | `OTP valid for ` + `MM:SS` (`00:00` when expired) |
| Resend (idle) | `Resend OTP` |
| Resend (busy) | `Sending…` (U+2026) |
| Info note | `Only wholesalers accounts will be verified. Retailers will require an invite to sign in.` |
| Submit (idle) | `Continue` |
| Submit (busy) | `Verifying...` |
| Legal | `By continuing, you agree to our Terms of Service and Privacy Policy.` |

**Layout / styling**
- Container `-mt-1 text-left w-full max-w-[400px]`; sub-line block `mb-[32px]`, text `text-[14px] text-[#9CA3AF] leading-[1.5]`, identity in `text-[#111827]`, `Edit` = `ml-[6px] font-bold text-[#111827]` hover underline → `router.replace("/entry_page/signup")`.
- 8 boxes in a row (`flex justify-between sm:gap-[4px] md:gap-[8px]`) with a literal `-` separator between index 3 and 4 (`text-[#D1D5DB] text-[20px] font-light mx-[2px]`).
- Each box: `flex-1 max-w-[32px] sm:max-w-[36px] md:max-w-[40px] aspect-4/5 text-center text-[16px] md:text-[18px] font-medium rounded-[8px] border-[1.5px] bg-white`, focus border `#374151`.
  Normal: `border-[#D1D5DB] text-[#111827]`. **Wrong-OTP: `border-[#DC2626] text-[#DC2626]`.**
  `type="text" inputMode="numeric" maxLength={1}`, `id={"otp-digit-"+i}`, `autoFocus` on index 0.
- Error text `text-[13px] font-bold text-[#DC2626]` with `mt-[12px]`.
- Locked banner: `border border-red-200 bg-red-50 px-4 py-3`, text `text-[11px] uppercase tracking-[0.1em] text-red-600`.
- Timer row `flex flex-col gap-[6px]`; label `text-[13px] text-[#9CA3AF]`, digits `text-[#111827] font-bold tabular-nums font-mono`.
- Resend button when `otpSecondsLeft > 0`: `text-[#D1D5DB] cursor-default text-[13px]`; when 0: `text-[#111827] font-bold hover:underline`.
- Info note wrapper `pt-[40px] md:pt-[60px]`, text `text-[12px] text-[#9CA3AF]`.
- Submit `w-full h-[48px] bg-[#1F2937] hover:bg-[#111827] text-white text-[14px] font-bold rounded-[12px] disabled:opacity-70`, `id="otp-verify-btn"`.

**Input behaviour**
- `handleDigitChange`: strips non-digits, keeps the **last** char (`.slice(-1)`), clears error + wrong-OTP flag, auto-advances focus while `index < 7`.
- `handleKeyDown`: `Backspace` on an empty box → focus previous; `ArrowLeft`/`ArrowRight` move focus.
- `handlePaste` (bound on the row container): strips non-digits, takes first 8, fills boxes, focuses `min(pasted.length, 7)`.

**Mount / restore** (`sessionStorage`)
- no `auth_identity` → `router.replace("/entry_page/signup")` and abort.
- `otp_locked_until` in the future → `lockedUntil` set, `remainingResends = 0`, `showStopwatch = false`, early return. If in the past → key removed.
- `otp_remaining_resends` → parsed int into state.
- `otp_sent_at` → `remaining = 60 - floor((now - sentAt)/1000)`; `>0` → countdown resumes; `<=0` → `otpSecondsLeft = 0`, stopwatch hidden.

**Verify** — `POST /api/auth/verify-otp` with `{ identity, token, referralCode: sessionStorage.referral_code }`
- failure → `isWrongOtp = true`, stopwatch hidden and interval cleared, error set, **all 8 boxes cleared and focus returns to box 0**, `verifying = false`.
- success + `data.isNewUser` → `router.push("/entry_page/signup/set-password?role=" + (urlRole || sessionStorage.referral_role || "wholesaler"))`
- success + returning user + `data.userRole === "retailer"` → reads `document.cookie` for `jewel_view_mode`; `"retailer"` → `/dashboard/retailer`, otherwise `/dashboard/employee`.
  **Bug to be aware of: the cookie is set `httpOnly:true`, so `document.cookie` can never see it → this branch always lands on `/dashboard/employee`.**
- success + any other role → `router.push("/dashboard/wholesaler")`.
- `verifying` is never reset on success (button stays "Verifying..." through navigation).

**Resend** — guard `if (!identity || resendCooldown > 0 || remainingResends <= 0 || lockedUntil) return;`
`POST /api/auth/send-otp` `{ identity }`.
- `!ok && data.locked` → `lockedUntil` + `sessionStorage.otp_locked_until`, `remainingResends = 0`, `sessionStorage.otp_remaining_resends = "0"`.
- `!ok && data.cooldown` → `resendCooldown = data.waitSeconds || 30`.
- both → `error = data.error`, `resending = false`.
- ok → `sessionStorage.otp_sent_at = now`, `remainingResends = data.remainingResends ?? max(0, prev-1)` (mirrored to sessionStorage), `otpSecondsLeft = 60`, stopwatch shown, wrong-OTP cleared, boxes cleared, focus box 0, `resendCooldown = 30`.

**Button disabled rules**
- Submit: `!otpComplete || verifying` where `otpComplete = digits.every(Boolean)`.
- Resend: `resending || otpSecondsLeft > 0 || remainingResends <= 0` (note: **`resendCooldown` is not in the disabled expression**, only in the handler guard).
- Whole timer/resend block is hidden when `isLocked`.

---

### 2.5 `/entry_page/signup/set-password`

Files: `app/entry_page/signup/set-password/page.jsx` + `components/auth/SetPasswordForm.jsx`
Document title: `"Create Password — Celestique"`

Heading node: `Set Password` — `text-[26px] md:text-[28px] xl:text-[36px] font-bold block mb-[10px] xl:mb-[12px] tracking-normal`. `subtitle = null`.

**Copy**
| Slot | Exact string |
|---|---|
| Sub-line | `Password must contain at least 8 characters and include a capital letter, a small letter, a number and a special character` |
| Label 1 | `Password` |
| Label 2 | `Confirm Password` |
| Both placeholders | `••••••••••` (10 × U+2022) |
| Mismatch error | `Passwords do not match` |
| Rule 1 | `At least 8 characters` |
| Rule 2 | `1 uppercase letter (A–Z)` (en-dash) |
| Rule 3 | `1 lowercase letter (a–z)` (en-dash) |
| Rule 4 | `1 number (0–9) and 1 special character (!@#$%^&*...)` (en-dash) |
| API fallback error | `Failed to set password. Please try again.` |
| Info note | `Only wholesalers accounts will be verified. Retailers will require an invite to sign in.` |
| Submit (idle) | `Continue` |
| Submit (busy) | `Verifying...` |
| Legal | `By continuing, you agree to our Terms of Service and Privacy Policy.` |

**Client rule predicates** (`RULES` array, ids `length`, `upper`, `lower`, `special`):
```
length : p.length >= 8
upper  : /[A-Z]/.test(p)
lower  : /[a-z]/.test(p)
special: /[0-9]/.test(p) && /[!@#$%^&*()\-_=+[\]{};:'",.<>/?\\|`~]/.test(p)
```
`canSubmit = allRulesPassed && password === confirm && password.length > 0`.

**Checklist rendering**: `flex flex-col gap-[8px] xl:gap-[10px]`; passed = filled circle `#16A34A` r=8 with a white check path `M4.5 8.5L7 11L12.5 5.5` (stroke 1.5); failed = hollow circle stroke `#D1D5DB` strokeWidth 1.5 r=7; icon `14×14` (`xl:16×16`). Label `text-[12px] xl:text-[13px]`, `#16A34A` when passed else `#6B7280`, `transition-colors duration-300`.

**Inputs**: `h-[44px] xl:h-[48px] border-[1.5px] border-[#E5E7EB] rounded-[8px] bg-white px-[14px] xl:px-[16px] pr-10 text-[14px] xl:text-[15px] text-[#111827]`, focus border `#374151`, `autoComplete="new-password"`, independent eye toggles (`18×18`, `xl:20×20`, `text-[#9CA3AF]`). Mismatch text `text-[12px] text-[#DC2626] mt-2 font-medium`, shown only while `confirm` is non-empty.

**Submit** `w-full h-[48px] xl:h-[52px] bg-[#1F2937] hover:bg-[#111827] text-white text-[14px] xl:text-[15px] font-semibold rounded-[10px] xl:rounded-[12px] disabled:opacity-70`, `id="set-password-btn"`, `disabled = !canSubmit || loading`.

**Call**: role = `?role=` || `sessionStorage.referral_role` || `"wholesaler"`.
`POST /api/auth/set-password` body `{ password, role }`.
On success: removes `auth_identity`, `otp_sent_at`, `otp_remaining_resends`, `otp_locked_until` from sessionStorage, then
`router.push(role === "retailer" ? "/onboard-retailer" : "/onboard")`.

---

### 2.6 `/forgot-password`

Files: `app/forgot-password/page.jsx` + `components/auth/ForgotPasswordForm.jsx`
Metadata: title `"Forgot Password - Jewel India"`, description `"Reset your password"`.
Heading `Reset your password`; subheading `Enter your email to receive a password reset link.`

**Form state (idle)**
| Slot | Exact string |
|---|---|
| Label | `Email address` |
| Placeholder | `Enter your email` |
| Submit (idle) | `Send reset link` |
| Submit (busy) | `Sending reset link...` |
| Secondary link | `Back to sign in` → `/signin` (308 → `/entry_page/signin`) |

**Success state** (replaces the whole form): 12×12 `rounded-full bg-green-100` circle with a `w-6 h-6 text-green-600` check (`M5 13l4 4L19 7`), then
- `h3` `Check your email` (`text-lg font-medium text-gray-900`)
- `p` `We've sent a password reset link to your email address. Please check your inbox.` (`text-sm text-gray-500`)
- link `Return to sign in` → `/signin` (`h-[48px] bg-white border-[1.5px] border-[#E5E7EB] text-[#1F2937] text-[14px] font-bold rounded-[12px]`)

**Errors** (from the `requestPasswordReset` Server Action): `Email is required`, `Server error while verifying email.`, `No account found with this email address.`, or the raw Supabase `error.message`.

Input: `h-[48px] w-full border-[1.5px] border-[#E5E7EB] bg-white rounded-[8px] px-[12px] text-[15px] text-[#111827] placeholder:text-[#9CA3AF]`, `type="email"`, `required`. Submit `w-full h-[48px] bg-[#1F2937] rounded-[12px] text-white text-[14px] font-bold disabled:opacity-70`, `disabled = loading`.

---

### 2.7 `/update-password`

Files: `app/update-password/page.jsx` + `components/auth/UpdatePasswordForm.jsx`
Metadata: title `"Update Password - Jewel India"`, description `"Update your password"`.
Heading `Set new password`; subheading `Please enter your new password below.`
Reached from the emailed reset link → `/auth/callback?next=/update-password`.

| Slot | Exact string |
|---|---|
| Label 1 | `New Password` |
| Placeholder 1 | `Enter new password` |
| Label 2 | `Confirm Password` |
| Placeholder 2 | `Confirm new password` |
| Mismatch error | `Passwords do not match.` (with trailing period — different from the SetPassword screen) |
| Length error (server) | `Password must be at least 6 characters long.` |
| Submit (idle) | `Update password` |
| Submit (busy) | `Updating...` |

Both inputs `required minLength={6}`, `h-[48px] border-[1.5px] border-[#E5E7EB] rounded-[8px] px-[12px] text-[15px]`; the first has `pr-[40px]` and a single eye toggle that flips **both** fields' `type`.

**Success state**: green check circle, `h3` `Password updated!`, `p` `Your password has been changed successfully.`, primary link **`Continue to Dashboard` → `/signin`** (label and destination disagree; 308 → `/entry_page/signin`).

Call: Server Action `updatePassword(password)`.

---

### 2.8 `/select-role`

Files: `app/select-role/page.jsx` (server) + `components/auth/SelectRoleForm.jsx`
Metadata: title `"Choose Your Role — Celestique"`, description `"Tell us whether you're a wholesaler or a retailer to personalise your experience."`
**Does not use AuthLayout** — it is the only Celestique-token screen in the auth flow.

Server-side gate: `getAuthUser()`; `!user` → `redirect("/signin")`; `user_metadata.role === "wholesaler"` → `redirect("/dashboard/wholesaler")`; `=== "retailer"` → `redirect("/")`.

**Copy**
| Slot | Exact string |
|---|---|
| Heading | `How will you use Celestique?` (`font-serif text-3xl text-celestique-dark`) |
| Sub | `Select your role so we can tailor your experience.` (`text-[10px] uppercase tracking-[0.2em] text-celestique-dark/60`) |
| Sub line 2 | `This cannot be changed later.` (`text-[9px] tracking-[0.1em] text-celestique-dark/40`) |
| Card 1 title | `Wholesaler` |
| Card 1 body | `Upload jewellery products, manage your catalogue, and connect with retailers.` |
| Card 2 title | `Retailer` |
| Card 2 body | `Browse the full jewellery catalogue, discover designs, and source from wholesalers.` |
| Empty-selection error | `Please choose a role to continue.` |
| Invalid-role error (server) | `Invalid role.` |
| Not-authed error (server) | `Not authenticated.` |
| Button | `Complete Selection` |
| Footer | `Signed in as {user.email}` (`text-[9px] uppercase tracking-[0.2em] text-celestique-dark/40`) |

Layout: `min-h-screen flex items-center justify-center bg-celestique-cream px-4`, inner `max-w-md`; a `16×16` bordered square holding an `8×8` gem path `M6.5 2h11l4 6-9.5 14L2.5 8l4-6z`; card `bg-celestique-cream border border-celestique-taupe` with a `border-b` header `px-8 py-10 text-center` and `p-8` body.
Role buttons: `w-full text-left flex items-start gap-6 p-6 border transition-all duration-300`; selected `border-celestique-dark bg-celestique-taupe/10`, unselected `border-celestique-taupe hover:border-celestique-dark/50 hover:bg-celestique-taupe/5`. Square (not round) radio `w-4 h-4 border`, filled with a `w-1.5 h-1.5 bg-celestique-cream` square when selected. Icon in a `p-3 border` box (heroicons briefcase / shopping-bag, `w-6 h-6`, strokeWidth 1.5).
Error paragraph: `text-[10px] uppercase tracking-[0.1em] text-red-800 bg-red-50 border border-red-200 px-4 py-3 text-center`.
`Button` (`components/ui/Button.jsx`): `h-14 px-10 w-full text-[11px] uppercase tracking-widest font-bold`, primary `bg-celestique-dark text-celestique-cream`, `disabled:opacity-50`; while `loading` the label goes invisible and a `w-5 h-5 border-2 border-celestique-taupe border-t-celestique-cream rounded-full animate-spin` spinner overlays it. `disabled = !selected` (plus loading).

**Call**: Server Action `setUserRole(selected)`. On success → `wholesaler` ? `router.push("/dashboard/wholesaler")` : `router.push("/")`.

---

### 2.9 `/employee-login`

Files: `app/employee-login/page.jsx` + `components/auth/EmployeeLoginForm.jsx`
Metadata: title `"Employee Login — Jewels India"`, description `"Employee access to catalogue and order management."`
Own layout (not AuthLayout): outer `theme-employee flex flex-col md:flex-row w-full min-h-screen bg-white p-4`; left image `w-full h-[40vh] md:w-[60%] lg:w-[65%] md:h-[calc(100vh-2rem)]` with
`https://res.cloudinary.com/dcs0vuzwg/image/upload/v1778315194/emp_invite_image_tlmjyv.svg`, `alt="Employee Invite"`, `objectFit:cover`; right column `md:w-[40%] lg:w-[35%] px-[20px] pt-[16px] md:px-[24px] lg:px-[40px]`, inner `max-w-[400px] mx-auto`.

| Slot | Exact string |
|---|---|
| Heading | `The catalogue` / `is waiting.` (explicit `<br/>`; `Georgia, 'Bodoni Moda', serif`, weight 400, `lineHeight 1.15`, `letterSpacing -0.01em`, `text-[1.6rem] md:text-[1.8rem] lg:text-[2.5rem]`, wrapper `mb-[160px]`) |
| Label 1 | `Email` |
| Placeholder 1 | `Enter` |
| Label 2 | `Password` |
| Placeholder 2 | `••••••••••••` (12 × U+2022) |
| Submit (idle) | `Get Started` |
| Submit (busy) | `Signing in...` |

Form font: `'Gilroy', 'SF Pro', system-ui, sans-serif`. Labels `13px / #6B7280 / weight 500 / letterSpacing 0.01em`.
Inputs `h-[48px] border-[1.5px] border-[#E5E7EB] rounded-[6px] text-[15px] text-[#111827]`, focus border `#111`; email `px-[14px]`, password `pl-[14px] pr-[44px]` with an eye toggle (`aria-label` `"Hide password"` / `"Show password"`).
Error block: `padding:10px 14px; background:#FEF2F2; border:1px solid #FECACA; borderRadius:8px; marginBottom:16px`, `6×6` `#EF4444` dot, text `13px #DC2626`.
Submit `h-[44px] text-[15px] font-semibold tracking-[0.02em] rounded-[8px]`; enabled `bg-black text-white hover:bg-[#222222]`; **disabled `bg-[#E5E7EB] text-[#9CA3AF] cursor-not-allowed`**; `disabled = loading || !(email.trim() && password.trim())`; `id="employee-login-btn"`.
Calls the same `signIn` Server Action with native `email` + `password` fields.
Proxy sends `?error=deactivated` here when a logged-in employee's record is missing/inactive — **this form never reads `?error`, so that message is silently dropped.** (iOS should show it.)

---

### 2.10 `/auth/callback` — OAuth + email-link exchange (`app/auth/callback/route.js`, GET)

Query handling, in order:
1. `?error=` present → redirect `${origin}/entry_page/signup?error=${error_description ?? error}`.
2. `?code=` present → `supabase.auth.exchangeCodeForSession(code)`.
   - `isNewUser = Date.now() - new Date(user.created_at) < 60000` (60 s window).
   - `role = user.user_metadata?.role`; if absent **and not new**, fall back to `profiles.role` (`.maybeSingle()`).
   - **No role** → `requestedRole = (searchParams.role === "retailer") ? "retailer" : "wholesaler"`; `auth.updateUser({data:{role:requestedRole}})`; `supabaseAdmin.from("profiles").upsert({id,email: user.email || user.phone, role}, {onConflict:"id"})`; redirect to `/onboard-retailer` or `/onboard`.
   - `?next=` present → redirect `${origin}${next}` (this is how `/update-password` is reached).
   - role `wholesaler` → back-fill metadata role if missing, then `getWholesalerDestination(user.id)` (the **auth.js** variant, which *does* consider `has_visited_dashboard`); if the destination contains `error=banned`, `signOut()` first; redirect `${origin}${dest}`.
   - role `retailer` → back-fill metadata role if missing, redirect `${origin}/` (deliberately delegating to the proxy/config redirect chain).
3. Exchange failed → `${origin}/entry_page/signup?error=${exchangeError.message}`.
4. No code, no error → `${origin}/entry_page/signup?error=oauth`.

**Google OAuth start** — `lib/actions/oauth.js` (client-side, explicitly **not** `"use server"`):
```js
supabase.auth.signInWithOAuth({
  provider: "google",
  options: { redirectTo, queryParams: { access_type: "offline", prompt: "consent" } },
})
```
then `window.location.href = data.url`. `redirectTo` is always `${window.location.origin}/auth/callback` plus `?role=<referral_role>` when a referral role is in sessionStorage.

---

### 2.11 `/` (homepage) — dead in production

`app/page.jsx` is the "Celestique" storefront (`revalidate = 60`) with `getAllProducts()`, empty state `No pieces yet` / `Our artisans are currently crafting new designs.`, `[ SIGN IN ]` link, `SignOutButton`. Because `next.config.mjs` redirects `/` → `/entry_page/signin` (307), **this page never renders**. Its in-page gate (`!role → /select-role`, `wholesaler → /dashboard/wholesaler/add-product`) is likewise unreachable.
For iOS: the launch route is the entry screen (§2.2 if unauthenticated after the proxy's auth-route rule; see §5).

---

## 3. Shared validators — `lib/utils/credentials.js`

```js
// email (used in EntryForm, check-user, send-otp, verify-otp, signIn)
/^[^\s@]+@[^\s@]+\.[^\s@]+$/

// isValidEmailFormat() — stricter, used only by employee credential generation
/^[a-z0-9](?:[a-z0-9._%+-]{0,62}[a-z0-9])?@[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.[a-z]{2,24}$/i

// validateIndianMobile(input) -> { valid, normalized }
digits = String(input).replace(/\D/g, "")
/^[6-9]\d{9}$/     -> { valid:true, normalized:`+91${digits}` }
/^0[6-9]\d{9}$/    -> { valid:true, normalized:`+91${digits.slice(1)}` }
/^91[6-9]\d{9}$/   -> { valid:true, normalized:`+${digits}` }
otherwise          -> { valid:false, normalized:null }
```
Server password regex (set-password route):
`/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[!@#$%^&*()_+\-=\[\]{};':"\\|,.<>\/?]).{8,}$/`

---

## 4. Every backend call, with (A)/(B)/(C) classification for iOS

**(A)** = reproducible on-device with the Supabase Swift SDK + anon key.
**(B)** = needs a server (service-role key or Next-only primitive) → iOS must call `https://app.jewelindia.shop<path>`.
**(C)** = Next Server Action, not addressable over HTTP → logic must be reimplemented client-side.

### A — direct Supabase SDK calls

| # | Call | Where | Exact SDK usage |
|---|---|---|---|
| A1 | `auth.signInWithPassword({email\|phone, password})` | `signIn` action | branch on `/^[^\s@]+@[^\s@]+\.[^\s@]+$/`: email → `{email, password}`, else `{phone: identity, password}` |
| A2 | `auth.signOut()` | many | plain |
| A3 | `auth.getUser()` | everywhere | plain |
| A4 | `auth.updateUser({password})` | `updatePassword` action | |
| A5 | `auth.updateUser({data:{role}})` | `setUserRole`, callback, set-password route | metadata write |
| A6 | `auth.updateUser({password, data:{role}})` | set-password route | combined |
| A7 | `auth.resetPasswordForEmail(email, {redirectTo:"https://app.jewelindia.shop/auth/callback?next=/update-password"})` | `requestPasswordReset` | iOS should instead use a custom scheme / universal link redirect |
| A8 | `auth.signInWithOtp({email, options:{shouldCreateUser:true}})` / `({phone, options:{shouldCreateUser:true}})` | send-otp route | **Callable directly from iOS.** Only the rate-limit bookkeeping around it needs a server. |
| A9 | `auth.verifyOtp({email, token, type:"email"})` / `({phone, token, type:"sms"})` | verify-otp route | **Callable directly from iOS** |
| A10 | `auth.exchangeCodeForSession(code)` | `/auth/callback` | Swift SDK handles this inside `session(from: url)` |
| A11 | `auth.signInWithOAuth({provider:.google, redirectTo, queryParams:{access_type:"offline", prompt:"consent"}})` | `oauth.js` | use ASWebAuthenticationSession |
| A12 | `auth.onAuthStateChange(...)` | AuthProvider | `authStateChanges` stream |
| A13 | `from("profiles").select("role").eq("id", uid).single()` | signIn, getUserRole | RLS: own row |
| A14 | `from("profiles").upsert({id, email, role}, {onConflict:"id"})` | `setUserRole` (anon client) | works under RLS for own row |
| A15 | `from("wholesalers").select("verification_status, has_visited_dashboard").eq("user_id", uid).single()` | auth.js + proxy | proxy variant selects only `verification_status` in the dashboard guard |
| A16 | `from("retailers").select("verification_status").eq("user_id", uid).single()` | auth.js + proxy | |
| A17 | `from("employees").select("status").eq("auth_user_id", uid).single()` | signIn + proxy | |
| A18 | `from("employees").select("id, status").eq("auth_user_id", uid).single()` | `validateEmployeeAccess` | |
| A19 | `from("employees").select("id, retailer_id, designation").eq("auth_user_id", uid)` | `validateEmployeeAccess` retailer branch | |
| A20 | `from("retailers").select("id, full_name").eq("user_id", uid).single()` | toggle-view route | the *query* is class A; the cookie write is not |
| A21 | `from("employees").insert({auth_user_id, retailer_id, full_name, email, designation:"Admin", status:"active", is_system_generated:true})` (fallback insert without `is_system_generated`) | toggle-view route | |
| A22 | `from("wholesalers").update({has_visited_dashboard:true}).eq("user_id", uid)` | `app/dashboard/wholesaler/page.jsx` | fires on first dashboard render; the "first visit" routing rule depends on it |

**Count A = 22**

### B — server-required HTTPS endpoints (`https://app.jewelindia.shop…`)

| # | Endpoint | Why server-only | Request | Response |
|---|---|---|---|---|
| B1 | `POST /api/auth/check-user` | `supabaseAdmin.auth.admin.listUsers` (service role) | `{"identity":"<email or +91XXXXXXXXXX>"}` | 200 `{"exists":bool,"provider":"google"\|null,"isEmail":bool,"isPhone":bool}` · 400 `{"error":"Identity is required"}` · 400 `{"error":"Please enter a valid email address or 10-digit Indian mobile number."}` · 500 `{"error":"Server error. Please try again."}` |
| B2 | `POST /api/auth/send-otp` | reads/writes `otp_rate_limits` via service role | `{"identity":"…"}` | 200 `{"success":true,"remainingResends":<0-4>,"lastSentAt":"<ISO>"}` · 429 `{"error":"Too many OTP requests. Please try again after 24 hours.","locked":true,"lockedUntil":"<ISO>"}` · 429 `{"error":"Please wait <n> seconds before requesting another OTP.","cooldown":true,"waitSeconds":<n>}` · 429 `{"error":"You have exhausted all OTP resend attempts. Try again after 24 hours.","locked":true,"lockedUntil":"<ISO>"}` · 400 identity errors as B1 · 500 `{"error":"<supabase error.message>"}` or `{"error":"Server error. Please try again."}` |
| B3 | `POST /api/auth/verify-otp` | referral bookkeeping on `referral_links` via service role | `{"identity":"…","token":"12345678","referralCode":"<code>\|null}` | 200 `{"success":true,"userId":"<uuid>","isNewUser":bool,"userRole":"wholesaler"\|"retailer"\|"employee"\|undefined}` · 400 `{"error":"Identity and token are required."}` · 401 `{"error":"Invalid OTP. Please check the code and try again."}` · 500 `{"error":"Server error. Please try again."}` |
| B4 | `POST /api/auth/set-password` | `supabaseAdmin.from("profiles").upsert` | `{"password":"…","role":"wholesaler"\|"retailer"}` | 200 `{"success":true}` · 400 `{"error":"Password is required."}` · 400 `{"error":"Password must be at least 8 characters and include 1 uppercase, 1 lowercase, 1 number, and 1 special character."}` · 401 `{"error":"Session expired. Please restart the signup process."}` · 500 `{"error":"<updateUser error.message>"}` / `{"error":"Server error. Please try again."}` |
| B5 | `POST /api/auth/toggle-view` | sets the **httpOnly** `jewel_view_mode` cookie; constructs its client with `SUPABASE_SERVICE_ROLE_KEY \|\| ANON_KEY` | `{"mode":"employee"}` or `{"mode":"retailer"}` | 200 `{"success":true,"activeView":"employee"\|"retailer"}` · 401 `{"error":"Unauthenticated"}` · 403 `{"error":"Forbidden: Only retailers can toggle views"}` · 404 `{"error":"Retailer profile not found"}` · 400 `{"error":"Invalid mode"}` · 500 `{"error":"Failed to query employees table: <msg>"}` / `{"error":"Failed to auto-provision virtual employee profile: <msg>"}` / `{"error":"Internal Server Error: <msg>"}` |
| B6 | `GET /auth/callback?code=…[&next=…][&role=…][&error=…&error_description=…]` | server-side code exchange + admin `profiles` upsert; returns **302 redirects**, not JSON | query only | 302 `Location:` one of `/onboard`, `/onboard-retailer`, `/onboard/submitted`, `/dashboard/wholesaler`, `/`, `<next>`, `/entry_page/signup?error=…` |

**Count B = 6**

Notes for iOS on B:
- All of B1–B5 are `POST` with `Content-Type: application/json`.
- B4 and B5 authenticate **via the Supabase session cookies** that `@supabase/ssr` writes (`sb-ljxgwiuvdpuarvdszjts-auth-token…`). A native client sending only an `Authorization: Bearer` header will hit `401 {"error":"Session expired. Please restart the signup process."}` / `401 {"error":"Unauthenticated"}`.
  → **Blocker to resolve with the user:** either (a) forward the session as cookies from iOS, or (b) add `Authorization` header support server-side, or (c) for B4 replace it with A6 + A14 on-device (the only thing lost is the service-role `profiles` upsert, which the anon client can usually do for its own row), and for B5 replace the httpOnly cookie with a client-side view-mode preference.
- B3 (`verify-otp`) can be replaced on-device by A9 + a local `isNewUser` computation (`user.userMetadata["role"] == nil`) **only if** referral-usage counting is moved elsewhere; `referral_links` writes require service role.
- B2's rate limiting is server state; if iOS calls A8 directly it bypasses the 5-resend / 24 h lockout entirely.

### C — Next Server Actions (not HTTP-callable; reimplement in Swift)

| # | Action | File | Logic iOS must reproduce |
|---|---|---|---|
| C1 | `signIn(formData)` | `lib/actions/auth.js:95` | 1) `identity = formData.email`; email-regex test → `signInWithPassword({email\|phone, password})`. 2) on error return `{error: error.message}`. 3) `role = user.user_metadata.role`, else `profiles.role` (`.single()`), else `null`. 4) `wholesaler` → `getWholesalerDestination` (C4); if dest contains `error=banned` → `signOut()`; redirect. 5) `retailer` → `getRetailerDestination` (C5); same banned handling; redirect. 6) `employee` → `employees.select("status").eq("auth_user_id", uid).single()`; if a row exists and `status !== "active"` → `signOut()` + return `{error:"Your account has been deactivated by the store administrator."}`; else redirect `/dashboard/employee` (a **missing** employee row still redirects to the dashboard). 7) fallthrough `roleDestination(role)`: `wholesaler→/dashboard/wholesaler`, `retailer→/dashboard/retailer`, `employee→/dashboard/employee`, otherwise `/select-role` — reachable only when `role` is null. |
| C2 | `signOut()` | `auth.js:156` | `auth.signOut()` + `revalidatePath("/","layout")` + `redirect("/signin")` → i.e. back to the entry/sign-in screen. |
| C3 | `terminalUserExit(actionRoute)` | `auth.js:170` | if `actionRoute.includes("/entry_page")` → `auth.signOut()`; then navigate to `actionRoute`. Callers (`/onboard/submitted`): `{label:"I Understand", route:"/entry_page/signup"}` (default), `{label:"Resubmit", route:"/onboard"}`, `{label:"Go to Dashboard", route:"/dashboard/wholesaler"}`. |
| C4 | `getWholesalerDestination(userId)` | `auth.js:17` | `wholesalers.select("verification_status,has_visited_dashboard").eq("user_id",uid).single()`; no row → `/onboard`; `banned` → `/entry_page/signup?error=banned`; `verified && has_visited_dashboard` → `/dashboard/wholesaler`; `verified && !has_visited_dashboard` → `/onboard/submitted`; anything else → `/onboard/submitted`. |
| C5 | `getRetailerDestination(userId)` | `auth.js:41` | `retailers.select("verification_status").eq("user_id",uid).single()`; no row → `/onboard-retailer`; `banned` → `/entry_page/signup?error=banned`; `verified` → cookie `jewel_view_mode === "retailer"` ? `/dashboard/retailer` : `/dashboard/employee`; else → `/onboard-retailer/submitted`. |
| C6 | `requestPasswordReset(email)` | `auth.js:181` | `!email` → `{error:"Email is required"}`; **admin `listUsers({page:1,perPage:1000})`** to prove existence (→ this half is class **B**-ish: iOS cannot do it with the anon key; either drop the existence pre-check and call A7 directly, or add an endpoint); missing → `{error:"No account found with this email address."}`; list error → `{error:"Server error while verifying email."}`; then A7 with `redirectTo` = `${SITE_URL}/auth/callback?next=/update-password`. |
| C7 | `updatePassword(password)` | `auth.js:217` | `!password \|\| length < 6` → `{error:"Password must be at least 6 characters long."}`; else `auth.updateUser({password})`; error → `{error: error.message}`; else `{success:true}`. |
| C8 | `setUserRole(role)` | `lib/actions/role.js:9` | role not in `["wholesaler","retailer"]` → `{error:"Invalid role."}`; `getUser()` null → `{error:"Not authenticated."}`; `updateUser({data:{role}})`; then `profiles.upsert({id,email,role},{onConflict:"id"})`; returns `{success:true, role}`. |
| C9 | `signUp(formData)` | `auth.js:68` | **DEAD CODE — no component imports it.** Kept for reference: validates role in `["wholesaler","retailer"]` else `{error:"Please select a role (Wholesaler or Retailer)."}`, then `auth.signUp({email,password,options:{data:{role}, emailRedirectTo:`${getURL()}/auth/callback`}})`. Do not port. |
| C10 | `onboardSignOut()` | `auth.js:163` | **DEAD CODE — no importers.** `signOut()` + redirect `/entry_page/signup`. |
| C11 | `getUserRole()` | `role.js:39` | **DEAD CODE — no importers.** metadata role else `profiles.role`. |
| C12 | `updateSession(request)` — the proxy | `lib/supabase/middleware.js` | Next-only primitive. Its entire rule set must become the iOS router; see §5. |
| C13 | `validateEmployeeAccess(supabase)` | `lib/utils/auth-check.js` | Server-side guard used by `/api/orders/*`, `/api/chat/*`, etc. Returns `{user, role, employeeId, retailerId}` or `{error, status}`: `401 "Unauthenticated"`; employee w/ missing or non-`active` record → `403 "Forbidden: Inactive or missing employee record"`; retailer in `jewel_view_mode === "employee"` with no employee rows → `403 "Forbidden: Virtual employee profile not provisioned"`; no `is_system_generated === true` and no `designation === "Admin"` row → `403 "Forbidden: Admin context not found"`; any other role → `403 "Forbidden: Role not authorized for employee resources"`; thrown → `500 "Internal Server Error"`. (Note the `select` omits `retailer_id` in the employee branch, so `retailerId` is `undefined` there — a live bug.) |

**Count C = 13** (of which C9/C10/C11 are dead code; 10 live).

**Totals: A = 22, B = 6, C = 13 (10 live).**

---

## 5. SESSION + ROUTING STATE MACHINE

### 5.1 Where session state lives

| Store | Key | Written by | Notes |
|---|---|---|---|
| Cookie (Supabase) | `sb-ljxgwiuvdpuarvdszjts-auth-token*` | `@supabase/ssr` | iOS: Keychain-backed SDK session |
| Cookie (app) | `jewel_view_mode` = `"employee"` \| `"retailer"` | `POST /api/auth/toggle-view` only | `path:"/"`, `httpOnly:true`, `secure: NODE_ENV==="production"`, `sameSite:"lax"`, `maxAge: 604800` (7 days). **Never set at login, never cleared on sign-out.** |
| `sessionStorage` | `auth_identity` | EntryForm (both branches) | cleared by SetPasswordForm and by `Change` on the sign-in screen |
| `sessionStorage` | `otp_sent_at` (ISO) | EntryForm, OtpForm resend | drives the 60 s countdown across reloads |
| `sessionStorage` | `otp_remaining_resends` (string int) | OtpForm | |
| `sessionStorage` | `otp_locked_until` (ISO) | OtpForm | 24 h lockout |
| `sessionStorage` | `referral_code` | EntryForm (`?ref=`), JoinLandingClient | sent as `referralCode` to verify-otp |
| `sessionStorage` | `referral_role` | EntryForm (`?role=`), JoinLandingClient (`"retailer"`) | picks the signup branch |
| `localStorage` | `employee_orders_last_checked` | EmployeeTopNav | badge state, not auth |

`jewel_view_mode` semantics: **absent ⇒ treated as employee mode for a verified retailer.** Only the literal `"retailer"` sends a retailer to `/dashboard/retailer`. `RetailerSidebar` (two places) posts `{mode:"employee"}` then `window.location.href = "/dashboard/employee"`; `EmployeeTopNav.handleSwitchToAdmin` posts `{mode:"retailer"}` then `window.location.href = "/dashboard/retailer"`. UI labels: `Employee View` / `EMPLOYEE VIEW`.

### 5.2 `verification_status` domain

`WHOLESALERS_TABLE.sql`: `text default 'pending' check (verification_status in ('pending','verified','rejected','on_hold','resubmission_required','banned'))`.
UNEXTRACTABLE: no `retailers` DDL exists in this repo — the retailer status domain is inferred from `lib/supabase/middleware.js:46` (`// pending, on_hold, rejected, resubmission_required`) plus `verified` and `banned` handled explicitly. Confirm against the live DB before relying on it.
UNEXTRACTABLE: the `employees.status` domain — only `"active"` is referenced in code; the allowed set is not in this repo.

### 5.3 Proxy rules, in exact source order (`lib/supabase/middleware.js`)

Preamble: build the request-bound client, `const { data: { user } } = await supabase.auth.getUser()`, `pathname = request.nextUrl.pathname`. `role = user.user_metadata?.role`.

**§1 `pathname.startsWith("/dashboard")`**
- `!user` → `/signup` (→308→ `/entry_page/signup`)
- `!role` → `/onboard`
- `…/dashboard/retailer`:
  - `role === "retailer" && jewel_view_mode !== "retailer"` → `/dashboard/employee`
  - `role !== "retailer"`: `wholesaler` → `/dashboard/wholesaler`; `employee` → `/dashboard/employee`; otherwise → `/`
  - no retailer row → `/onboard-retailer`
  - `verification_status === "banned"` → `signOut()` + `/entry_page/signup?error=banned`
  - `verification_status !== "verified"` → `/onboard-retailer/submitted`
- `…/dashboard/employee`:
  - `isRetailerInEmployeeMode = (role === "retailer" && jewel_view_mode !== "retailer")`
  - `role !== "employee" && !isRetailerInEmployeeMode`: `wholesaler` → `/dashboard/wholesaler`; `retailer` → `/dashboard/retailer`; otherwise → `/`
  - employee row missing or `status !== "active"`: if `role === "retailer"` → `/dashboard/retailer`; else `signOut()` + `/employee-login?error=deactivated`
- `…/dashboard/wholesaler`:
  - `role !== "wholesaler"`: `retailer` → `/dashboard/retailer`; `employee` → `/dashboard/employee`; otherwise → `/`
  - no wholesaler row → `/onboard`
  - `banned` → `signOut()` + `/entry_page/signup?error=banned`
  - `!== "verified"` → `/onboard/submitted`
  - **note:** unlike C4, the proxy does **not** consult `has_visited_dashboard` here, so a verified wholesaler may sit on `/dashboard/wholesaler` even before the first-visit flag flips.

**§2 `pathname === "/"` and `user`** — `!role` → `/onboard`; `wholesaler` → proxy-local `getWholesalerDestination` (no `has_visited_dashboard` check: no row → `/onboard`, `banned` → `signOut()` + `/entry_page/signup?error=banned`, `verified` → `/dashboard/wholesaler`, else → `/onboard/submitted`); `retailer` → proxy-local `getRetailerDestination` (no row → `/onboard-retailer`, `banned` → `signOut()` + `?error=banned`, `verified` → cookie `"retailer"` ? `/dashboard/retailer` : `/dashboard/employee`, else → `/onboard-retailer/submitted`); `employee` → `/dashboard/employee`. Query params from the destination string are re-attached to the redirect URL.
*(In practice the config-level `/` → `/entry_page/signin` redirect also fires; either ordering yields the same final destination for an authenticated user because `/entry_page/signin` is an auth route handled by §5 with the identical rules. An unauthenticated user always ends at `/entry_page/signin`.)*

**§2a `pathname === "/employee-login"` and `user`** — `employee` → `/dashboard/employee`; `wholesaler` → `/dashboard/wholesaler`; `retailer` → `/dashboard/retailer`; otherwise → `/`.

**§3 `pathname.startsWith("/select-role") && !user`** → `/entry_page/signup`.

**§4 pre-auth allowlist — returned untouched** (prefix match):
`/entry_page/signup/verify-otp`, `/entry_page/signup/set-password`, `/auth/callback`, `/join`, `/employee-login`.
*(`/employee-login` appears here **after** §2a, so §2a still wins for authenticated users.)*

**§5 auth routes** `["/entry_page/signin", "/entry_page/signup"]` matched as `pathname === r || pathname.startsWith(r + "?")` **and** `user` present:
`!role` → `/onboard`; `wholesaler` → proxy-local `getWholesalerDestination`; `retailer` → proxy-local `getRetailerDestination`; `employee` → `/dashboard/employee`; fallback → `/`.
(`?error=banned` triggers `signOut()` before redirecting.)
Note: `pathname.startsWith(r + "?")` can never match — `pathname` excludes the query string — so query-carrying auth URLs are matched only by the `pathname === r` clause, which does hold. Harmless.

**§6 otherwise** — pass through (`/onboard*`, `/onboard-retailer*`, `/forgot-password`, `/update-password`, `/get-app`, `/dashboard`-less routes are **not** session-gated by the proxy).

### 5.4 Destination table — role × verification_status

Applies to `/` and to the auth routes (proxy §2 / §5) and to `signIn` (C1/C4/C5).
"post-login" = the C4/C5 variant used by `signIn` and `/auth/callback`; "proxy" = the middleware-local variant.

| role | row / status | `jewel_view_mode` | proxy destination | post-login (`signIn`) destination |
|---|---|---|---|---|
| *(none)* | — | any | `/onboard` | `/select-role` (via `roleDestination`) |
| wholesaler | no `wholesalers` row | any | `/onboard` | `/onboard` |
| wholesaler | `pending` / `on_hold` / `rejected` / `resubmission_required` | any | `/onboard/submitted` | `/onboard/submitted` |
| wholesaler | `verified`, `has_visited_dashboard = false` | any | `/dashboard/wholesaler` | `/onboard/submitted` |
| wholesaler | `verified`, `has_visited_dashboard = true` | any | `/dashboard/wholesaler` | `/dashboard/wholesaler` |
| wholesaler | `banned` | any | `signOut()` → `/entry_page/signup?error=banned` | `signOut()` → same |
| retailer | no `retailers` row | any | `/onboard-retailer` | `/onboard-retailer` |
| retailer | `pending` / `on_hold` / `rejected` / `resubmission_required` | any | `/onboard-retailer/submitted` | `/onboard-retailer/submitted` |
| retailer | `verified` | `"retailer"` | `/dashboard/retailer` | `/dashboard/retailer` |
| retailer | `verified` | absent or `"employee"` | `/dashboard/employee` | `/dashboard/employee` |
| retailer | `banned` | any | `signOut()` → `/entry_page/signup?error=banned` | `signOut()` → same |
| employee | `employees.status === "active"` | n/a | `/dashboard/employee` | `/dashboard/employee` |
| employee | `status !== "active"` | n/a | on `/dashboard/*`: `signOut()` → `/employee-login?error=deactivated` | `signOut()` + `{error:"Your account has been deactivated by the store administrator."}` |
| employee | no `employees` row | n/a | on `/dashboard/*`: `signOut()` → `/employee-login?error=deactivated` | **still redirects to `/dashboard/employee`** (the `if (employeeData && …)` guard skips a missing row), which the proxy then bounces to `/employee-login?error=deactivated` |

### 5.5 Happy-path flows (what the iOS coordinator must implement)

**New wholesaler (OTP)**
`/entry_page/signup` → B1 `{exists:false}` → B2 → `/entry_page/signup/verify-otp?role=wholesaler` → B3 `{isNewUser:true}` → `/entry_page/signup/set-password?role=wholesaler` → B4 → `/onboard` → (onboarding, out of scope) → `/onboard/submitted` → admin verifies → next login → `/dashboard/wholesaler`.

**New retailer via referral**
`/join/<code>` → sets `referral_code` + `referral_role="retailer"` → `/entry_page/signup?ref=<code>&role=retailer` → … → verify-otp (B3 increments `referral_links.uses_count`, deactivating the link when `uses_count >= max_uses`; `max_uses === null` = unlimited) → set-password with `role=retailer` → `/onboard-retailer`.

**Returning password user**
`/entry_page/signup` → B1 `{exists:true, provider:null}` → `/entry_page/signin?identity=…` → C1 → role/status destination per §5.4.

**Returning Google user**
`/entry_page/signup` → B1 `{exists:true, provider:"google"}` → A11 → Google → B6 `/auth/callback?code=…` → role destination.

**Password reset**
`/entry_page/signin` → `/forgot-password` → C6 → email → `/auth/callback?code=…&next=/update-password` → `/update-password` → C7 → success card → `Continue to Dashboard` → `/signin` → `/entry_page/signin`.

**Retailer ↔ employee view switch**
`/dashboard/retailer` "Employee View" → B5 `{mode:"employee"}` (auto-provisions an `employees` row with `designation:"Admin"`, `status:"active"`, `is_system_generated:true` if absent) → hard navigation to `/dashboard/employee`.
`/dashboard/employee` "switch to admin" → B5 `{mode:"retailer"}` → hard navigation to `/dashboard/retailer`.

---

## 6. Known defects / decisions the iOS port must make explicitly

1. `OtpForm` wrong-OTP message is hard-coded `"Invalid OTP! 2 attempts remaining"` and ignores the real remaining count.
2. `OtpForm`'s returning-retailer branch reads `document.cookie["jewel_view_mode"]`, but that cookie is `httpOnly` → always falls through to `/dashboard/employee`.
3. `EntryForm` shows `"You signed up with Google. Redirecting..."` styled as an error (red dot, `#DC2626`).
4. `SignInForm`'s `Remember me` checkbox is inert.
5. `UpdatePasswordForm` success CTA reads `Continue to Dashboard` but links to `/signin`.
6. Both `check-user` and `requestPasswordReset` enumerate users with `listUsers({page:1, perPage:1000})` — silently wrong past 1000 users.
7. `verify-otp` uses `type:"email"` for email and `type:"sms"` for phone; for phone it passes `identity.trim().toLowerCase()` (already `+91…`) as `phone`.
8. `signIn` redirects an employee with **no** `employees` row straight to `/dashboard/employee`, which the proxy then bounces to `/employee-login?error=deactivated` — a redirect loop of one hop with an error the login form never renders.
9. Password rules differ per screen: set-password ≥8 with 4 classes (client + server regex), update-password only `minLength 6` / `< 6` server check.
10. `jewel_view_mode` is never cleared on sign-out, so it leaks across accounts on a shared browser. On iOS, scope it per user id.
11. Terms of Service / Privacy Policy links are `href="#"` or plain spans everywhere — no destination exists.
12. Dead code, do not port: `signUp`, `onboardSignOut`, `getUserRole`, and `app/page.jsx`.
13. `validateEmployeeAccess` returns `retailerId: employee.retailer_id` from a `select("id, status")` that never fetched `retailer_id` → always `undefined` for direct employees.
