# 03 — App Shell & Navigation

Source of truth: `/Users/parashrautela/Documents/jewel india /Jewel-India-Frontend`
Every value below was read from the actual files listed in §0. Nothing is inferred from filenames.

---

## 0. Files read for this document

| File | Role |
|---|---|
| `app/layout.jsx` | Root layout, fonts, metadata, PWA meta, `AuthProvider` |
| `proxy.js` | Next.js 16 middleware entry (`proxy` replaces `middleware.js`) |
| `lib/supabase/middleware.js` | ALL route guards / redirect logic |
| `next.config.mjs` | Route redirects (`/`, `/signin`, `/signup`), PWA, image hosts |
| `app/manifest.js` | Dual PWA manifest (admin host vs storefront host) |
| `app/dashboard/page.jsx` | Bare `/dashboard` → redirect |
| `app/dashboard/wholesaler/layout.jsx` | Wholesaler shell |
| `app/dashboard/retailer/layout.jsx` | Retailer shell |
| `app/dashboard/employee/layout.jsx` + `components/employee/EmployeeLayout.jsx` + `EmployeeTopNav.jsx` | Employee-view shell (reachable **from the retailer shell**) |
| `app/onboard/layout.jsx`, `app/onboard-retailer/layout.jsx` | Onboarding shells |
| `components/wholesaler/Sidebar.jsx` | Wholesaler rail + mobile bottom nav + logout modal |
| `components/retailer/RetailerSidebar.jsx` | Retailer drawer + top bar + bottom nav + popover |
| `components/onboard/OnboardLayout.jsx`, `OnboardNavbar.jsx`, `StepIndicator.jsx`, `LeftPanel.jsx` | Onboarding chrome |
| `components/shared/BusinessProfileModal.jsx`, `ConfirmationModal.jsx`, `FullImageViewer.jsx`, `ProtectedImage.jsx` | Shared modal / image primitives |
| `components/retailer/AddEmployeeModal.jsx` | URL-param modal pattern |
| `components/retailer/RetailerThemeClient.jsx` | Store-theme picker + LockedModal + ClaimModal |
| `context/ThemeContext.jsx`, `context/OnboardContext.jsx`, `context/RetailerOnboardContext.jsx` | Client state providers |
| `lib/config/themePreference.js`, `lib/config/catalogueCategories.js` | Theme + category config |
| `lib/actions/auth.js`, `components/auth/SignOutButton.jsx`, `components/auth/AuthProvider.jsx` | Sign-out / session |
| `app/api/auth/toggle-view/route.js` | Retailer ⇄ Employee view-mode switch |
| `lib/cache/retailerEmployee.js` | Cached shell data (sidebar profile, theme, badges) |
| `app/globals.css` | Shell-relevant tokens, animations, skeletons, responsive rules |
| `app/global-error.jsx` | Global error boundary |
| `app/dashboard/**/loading.jsx` (5 files) | Route-level skeletons |
| `components/product/MinimalHeader.jsx`, `BackToDashboardButton.jsx` | Per-page chrome on product routes |

---

## 1. Route map (complete, with guards)

### 1.1 Public / pre-auth
```
/                          → next.config redirect (307) to /entry_page/signin   [see §2.3 conflict note]
/entry_page                (page.jsx)
/entry_page/signin
/entry_page/signup
/entry_page/signup/verify-otp        (pre-auth, guard-exempt)
/entry_page/signup/set-password      (pre-auth, guard-exempt)
/forgot-password
/update-password
/select-role                         (requires session)
/employee-login                      (public, guard-exempt)
/join/[code]                         (public referral landing; has not-found.jsx)
/auth/callback                       (route handler, guard-exempt)
/get-app
/sentry-example-page
/signin  → 308 permanent → /entry_page/signin
/signup  → 308 permanent → /entry_page/signup
```

### 1.2 Wholesaler onboarding (`theme-wholesaler`)
```
/onboard                 Step 1 of 3 — Identity
/onboard/step2           Step 2 of 3 — Business
/onboard/step3           Step 3 of 3 — Documents
/onboard/submitted       Verification status (step "4 of 3")
```

### 1.3 Retailer onboarding (`theme-retailer`)
```
/onboard-retailer                Step 1 of 3 — Identity
/onboard-retailer/step2          Step 2 of 3 — Store
/onboard-retailer/step3          Step 3 of 3 — Documents
/onboard-retailer/submitted      Verification status (own chrome, NOT OnboardLayout)
```

### 1.4 Wholesaler dashboard (`theme-wholesaler`, guarded)
```
/dashboard                              → redirect("/dashboard/wholesaler/add-product")
/dashboard/wholesaler                   Home   (metadata title "Wholesaler Dashboard")
/dashboard/wholesaler/add-product       Add/Upload   (title "Add Product — Celestique")
/dashboard/wholesaler/add-product/success
/dashboard/wholesaler/add-retailer      Invite Retailer   (title "Add Retailer — Jewel India")
/dashboard/wholesaler/catalogue         Catalogue   (title "My Catalogue — Celestique")
/dashboard/wholesaler/catalogue?category=<slug>
/dashboard/wholesaler/orders            Orders   (title "Orders — Wholesaler Dashboard")
/dashboard/wholesaler/orders?tab=new|active|completed|rejected
/dashboard/wholesaler/queries           Chat    (title "Queries — Wholesaler Dashboard")
/dashboard/wholesaler/upload-history    Uploads Today (title "Upload History — Celestique")
/dashboard/wholesaler/edit-product/[id]         (title "Edit Product — Celestique")
/dashboard/wholesaler/edit-product/[id]?from=upload-history
/dashboard/my-uploads                   Legacy "MY UPLOADS" page (NOT in any nav; title "My Uploads — Celestique")
```

### 1.5 Retailer dashboard (`theme-retailer`, guarded)
```
/dashboard/retailer                       Dashboard   (layout metadata "Retailer Dashboard")
/dashboard/retailer?modal=add-employee    Add-Employee modal (URL-driven)
/dashboard/retailer/employees             Employees
/dashboard/retailer/catalogue             Catalogue
/dashboard/retailer/catalogue/upload      Upload Design
/dashboard/retailer/catalogue/upload/success
/dashboard/retailer/your-taste            Your Taste  (title "Your Taste | Retailer Dashboard")
/dashboard/retailer/theme                 Store Theme (title "Store Theme — Retailer Dashboard")
```

### 1.6 Employee view (retailer toggles into it; `theme-employee`)
```
/dashboard/employee                        Home
/dashboard/employee/wholesaler-gallery     Catalogue
/dashboard/employee/messages               Queries
/dashboard/employee/orders                 Orders
/dashboard/employee/designs
/dashboard/employee/likes
/dashboard/employee/save
/dashboard/employee/curated
/dashboard/employee/playground             (nav bar HIDDEN)
/dashboard/employee/playground/review
/dashboard/employee/questionnaire          (nav bar HIDDEN)
```

---

## 2. Guards / auth gating

### 2.1 Entry point
`proxy.js` (Next.js 16 renamed `middleware.js` → `proxy.js`):
```js
export const config = { matcher: [
  "/((?!api|_next/static|_next/image|favicon.ico|robots.txt|sitemap.xml|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)"
]};
```
API routes are deliberately excluded ("middleware destroys POST FormData streams"). All logic lives in `lib/supabase/middleware.js → updateSession(request)`.

### 2.2 Exact guard rules (`lib/supabase/middleware.js`)

Session source: `supabase.auth.getUser()`. Role source: `user.user_metadata.role` ∈ `"wholesaler" | "retailer" | "employee"`.
View mode cookie: **`jewel_view_mode`** (`httpOnly`, `sameSite: "lax"`, `path: "/"`, `maxAge: 604800` = 7 days, `secure` in production).

**A. `pathname.startsWith("/dashboard")`**
1. no user → `/signup` (→308→`/entry_page/signup`)
2. no role → `/onboard`

**B. `/dashboard/retailer*`**
- role === "retailer" && `jewel_view_mode !== "retailer"` → `/dashboard/employee`
- role === "wholesaler" → `/dashboard/wholesaler`; role === "employee" → `/dashboard/employee`; otherwise → `/`
- `retailers` row missing → `/onboard-retailer`
- `verification_status === "banned"` → `signOut()` then `/entry_page/signup?error=banned`
- `verification_status !== "verified"` → `/onboard-retailer/submitted`

**C. `/dashboard/employee*`**
- allowed when role === "employee" OR (role === "retailer" && `jewel_view_mode !== "retailer"`)
- else wholesaler → `/dashboard/wholesaler`; retailer → `/dashboard/retailer`; else `/`
- `employees` row missing or `status !== "active"`: retailer → `/dashboard/retailer`; otherwise `signOut()` + `/employee-login?error=deactivated`

**D. `/dashboard/wholesaler*`**
- role !== "wholesaler" → retailer:`/dashboard/retailer`, employee:`/dashboard/employee`, else `/`
- `wholesalers` row missing → `/onboard`
- `banned` → `signOut()` + `/entry_page/signup?error=banned`
- not `verified` → `/onboard/submitted`

**E. `/` when authenticated** — role-based destination:
- wholesaler: `getWholesalerDestination()` → no row `/onboard`; banned `/entry_page/signup?error=banned`; verified `/dashboard/wholesaler`; else `/onboard/submitted`
- retailer: `getRetailerDestination()` → no row `/onboard-retailer`; banned same; verified + `jewel_view_mode==="retailer"` → `/dashboard/retailer`, verified otherwise → `/dashboard/employee`; else `/onboard-retailer/submitted`
- employee → `/dashboard/employee`

**F. `/employee-login` when authenticated** → role dashboard.
**G. `/select-role` without user** → `/entry_page/signup`.
**H. Guard-exempt prefixes** (returned unchanged): `/entry_page/signup/verify-otp`, `/entry_page/signup/set-password`, `/auth/callback`, `/join`, `/employee-login`.
**I. `/entry_page/signin` and `/entry_page/signup` when authenticated** → same role destinations as E.

Note the middleware's `getWholesalerDestination` for verified users returns `/dashboard/wholesaler` immediately, while the server-action version in `lib/actions/auth.js` additionally requires `has_visited_dashboard === true`, otherwise it routes to `/onboard/submitted`. **Two different rules for the same state.**

### 2.3 Redirect conflict (flag)
`next.config.mjs` declares `{ source: '/', destination: '/entry_page/signin', permanent: false }`. Section E of the middleware also handles `/`. Config redirects run only when middleware passes the request through, so an authenticated user hitting `/` is redirected by the middleware, and an anonymous user falls through to `/entry_page/signin`. The native app must replicate the *effective* behaviour: unauthenticated → sign-in; authenticated → role destination.

### 2.4 Client session
`components/auth/AuthProvider.jsx` wraps the whole tree at root; it takes `initialUser` from the server (`getAuthUser()` in `app/layout.jsx`) and subscribes to `supabase.auth.onAuthStateChange`, exposing `{ user }` via `useAuth()`. Throws `"useAuth() must be called inside <AuthProvider>. Make sure AuthProvider wraps your component tree."` when unwrapped.

### 2.5 Sign-out
`lib/actions/auth.js`:
- `signOut()` → `supabase.auth.signOut()` → `revalidatePath("/", "layout")` → `redirect("/signin")` (which 308s to `/entry_page/signin`).
- `onboardSignOut()` → redirect `/entry_page/signup`.
- `terminalUserExit(actionRoute)` → signs out only if `actionRoute.includes("/entry_page")`, then redirects to `actionRoute`.
`components/onboard/OnboardNavbar.jsx` signs out **client-side** (`createClient().auth.signOut()`) then `router.push(backRoute || '/signup')`.

---

## 3. Root layout (`app/layout.jsx`)

- `<html lang="en">`; `<head>` loads **one external stylesheet**: `https://cdn.jsdelivr.net/npm/bootstrap-icons@1.13.1/font/bootstrap-icons.min.css`.
- `<body suppressHydrationWarning className="${bodoni.variable} ${jost.variable} ${manrope.variable} font-sans antialiased text-celestique-dark">`.
- Google fonts via `next/font/google`: **Bodoni Moda** → `--font-bodoni`; **Jost** → `--font-jost`; **Manrope** → `--font-manrope-var`. Subsets `["latin"]`.
- `generateMetadata()` is host-dependent. `isAdmin = host.includes("app.jewelindia.shop") || host.includes("admin")`.
  - Admin: title `"Jewel India Admin"`, description `"Retailer dashboard for managing your Jewel India store"`, `appleWebApp.title = "Jewel India Admin"`, apple icons `/icons/admin-icon-{72,96,128,152,192}x*.png`.
  - Storefront: title `"Celestique | Timeless Jewelry"`, description `"A celestial touch for timeless moments."`, `appleWebApp.title = "Jewel India"`, icons `/icons/icon-*.png`.
  - Both: `manifest: "/manifest.webmanifest"`, `appleWebApp.capable = true`, `statusBarStyle: "default"`.
- PWA manifest (`app/manifest.js`): Admin → name `"Jewel India Admin"`, short_name `"JI Admin"`, `start_url: "/dashboard"`, `display: "standalone"`, **`orientation: "landscape"`**, `background_color: "#ffffff"`, `theme_color: "#2E2833"`, categories `["business","productivity"]`. Storefront → name `"Jewel India"`, `start_url: "/"`, `orientation: "portrait"`, `theme_color: "#6B4F4F"`, categories `["shopping","lifestyle"]`.

**iOS note:** the wholesaler/retailer admin app is the `app.jewelindia.shop` variant → brand colour `#2E2833`, admin icon set.

---

## 4. WHOLESALER SHELL

### 4.1 Layout (`app/dashboard/wholesaler/layout.jsx`)
```jsx
<div className="theme-wholesaler" style={{ display:"flex", minHeight:"100vh" }}>
  <Sidebar />
  <main className="wholesaler-main-content">{children}</main>
</div>
```
`.wholesaler-main-content` (globals.css): `flex:1; min-height:100vh; min-width:0; margin-left:0; padding-bottom:72px;` and `@media (min-width:768px) { margin-left:70px; padding-bottom:0; }`.
Layout metadata: title `"Wholesaler Dashboard"`, description `"Manage your catalogue, orders, and queries."`.

### 4.2 Desktop icon rail (`components/wholesaler/Sidebar.jsx`)

Container `<aside className="wholesaler-sidebar">` — `position:fixed; top:0; left:0; height:100vh; width:70px; backgroundColor:#f5f5f3; flex column; align-items:center; justify-content:space-between; padding:24px 0; overflow:hidden; z-index:50`.
Hidden entirely at `max-width: 767px`.

Icon stack: `margin-top:96px; margin-bottom:auto; gap:32px`. At `max-height:680px` → `margin-top:32px !important; gap:16px !important`.

**Nav items (exact order, labels, icons, hrefs):**

| # | Label (`name`, also the `title=` tooltip) | Icon URL (Cloudinary SVG, 28×28) | Destination |
|---|---|---|---|
| 1 | `Home` | `…/v1777013959/home_logo_q3xekq.svg` | `/dashboard/wholesaler` |
| 2 | `Add/Upload` | `…/v1777013959/upload_logo_hfdz8a.svg` | `/dashboard/wholesaler/add-product` |
| 3 | `Add Retailer` | `…/v1777013959/add_retailer_logo_aonkud.svg` | `/dashboard/wholesaler/add-retailer` |
| 4 | `Catalogue` | `…/v1777013959/catalogue_logo_baed4n.svg` | `/dashboard/wholesaler/catalogue` |
| 5 | `Orders` | `…/v1777013960/PACKAGE_LOGO_ekya2x.svg` | `/dashboard/wholesaler/orders` |
| 6 | `Chat` | `…/v1777013960/chatLOGO_j1mnkx.svg` | `/dashboard/wholesaler/queries` |

(Full prefix: `https://res.cloudinary.com/dcs0vuzwg/image/upload/`.)

Item box: `44×44`, `border-radius:8px`, `transition: all 0.15s ease`, `background: transparent`.
**Active-state styling:** `opacity: 1` + `filter: brightness(0)` (icon forced to pure black).
**Inactive:** `opacity: 0.35` + `filter: grayscale(1)`.
**Hover (`.sidebar-item:hover`)**: `opacity:0.7 !important; background-color: rgba(0,0,0,0.06) !important`.
**Active predicate:** `Home` uses `pathname === "/dashboard/wholesaler"` (exact); every other item uses `pathname.startsWith(item.href)`.

Bottom of rail: a single **logo button = LOGOUT trigger** — `44×44`, `background:#2e2833`, `border-radius:12px`, no border, `title="Logout"`, image `…/v1777013959/jewel_logo_rhgin9.svg` at 28×28. Hover: `opacity:0.9; transform: scale(1.05)`. There is **no profile block, no notification bell, no view-mode toggle** in the wholesaler rail.

### 4.3 Mobile floating bottom nav (`≤767px`)
`.wholesaler-bottom-nav`: `position:fixed; bottom:20px; left:50%; transform:translateX(-50%); width:90vw; max-width:400px; height:60px; background:rgba(255,255,255,0.85); backdrop-filter:blur(20px); border:1px solid rgba(255,255,255,0.5); border-radius:100px; box-shadow:0 8px 32px rgba(0,0,0,0.1), 0 1.5px 4px rgba(0,0,0,0.06); justify-content:space-around; padding:0 12px; z-index:100`.

**Order is re-shuffled vs the rail** — `[navItems[0], navItems[3], navItems[1], navItems[4], navItems[5]]`:
`Home` → `Catalogue` → `Add/Upload` → `Orders` → `Chat`, then the **More** button. Icons render at 24×24.
`.bottom-nav-item`: `44×44`, `border-radius:50%`, `transition: all 0.2s ease`.
Active: `background: rgba(0,0,0,0.05)` + `filter: brightness(0) !important`, inline `opacity:1`. Inactive inline `opacity:0.45; filter:grayscale(1)`.
More button: `36×36`, `border-radius:50%`, `background:#2e2833`, logo 22×22, `title="More Options"`; gets `.active` class while the popover is open.

**More popover** (`isMoreOpen`):
- Backdrop `.bottom-nav-popover`: full-screen, `background: rgba(0,0,0,0.1)`, `backdrop-filter: blur(2px)`, `z-index:99`; tap closes.
- Panel `.bottom-nav-popover-content`: `position:fixed; bottom:90px; left:50%; translateX(-50%); width:200px; background:#ffffff; border:1px solid rgba(0,0,0,0.08); border-radius:16px; box-shadow:0 12px 30px rgba(0,0,0,0.15); padding:8px; gap:4px; animation: popoverFadeIn 0.25s cubic-bezier(0.16,1,0.3,1)` (from `opacity:0, translate(-50%,10px)`).
- Rows (`.popover-item`: `padding:12px 16px; border-radius:10px; color:#374151; font-size:14px; font-weight:500; gap:12px`; hover `#f3f4f6`):
  1. **"Invite Retailer"** → `/dashboard/wholesaler/add-retailer`, icon `add_retailer_logo_aonkud.svg` 20×20 with `filter: brightness(0)`.
  2. **"Logout"** (`.popover-logout`, color `#ef4444`, hover bg `#fef2f2`) — closes popover and opens the logout modal. Icon: 20×20 inline stroke-`#ef4444` "log-out" glyph (`M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4`, `polyline 16 17 21 12 16 7`, `line 21,12 → 9,12`).

Note: **"Add Retailer" is NOT in the mobile 5-item bar** — it only exists in the More popover (labelled "Invite Retailer" there, "Add Retailer" in the rail).

### 4.4 Logout confirmation modal (inline in `Sidebar.jsx`)
- Backdrop: `rgba(0,0,0,0.4)`, `backdrop-filter: blur(4px)`, `z-index:1000`, `animation: fadeIn 0.2s ease-out`; click-outside closes.
- Card: `background:#ffffff; border-radius:20px; padding:32px; width:360px; max-width:90%; box-shadow:0 20px 25px -5px rgba(0,0,0,0.1), 0 10px 10px -5px rgba(0,0,0,0.04); animation: scaleUp 0.2s cubic-bezier(0.34,1.56,0.64,1)` (from `scale(0.95) opacity 0`).
- Icon: `56×56` circle, `background:#fef2f2`, margin-bottom `20px`, 24×24 log-out glyph stroked `#ef4444` at `stroke-width:2.5`.
- Title: **"Confirm Logout"** — `18px / 600 / #111827`, `font-family: Inter, sans-serif`, margin `0 0 8px 0`.
- Body: **"Are you sure you want to logout?"** — `14px / #6b7280 / line-height 1.5`, margin `0 0 24px 0`.
- Buttons row, `gap:12px`, both `flex:1`, `padding:12px`, `border-radius:10px`, `font-size:14px`, `font-weight:500`:
  - **"Cancel"** — `border:1px solid #e5e7eb`, `background:#ffffff`, `color:#374151`; hover `#f9fafb`.
  - **"Logout"** — `background:#2e2833`, `color:#ffffff`, no border; hover `opacity:0.9`. Calls `await signOut()`.

### 4.5 Per-page chrome inside the wholesaler shell (not in the layout)
| Route | Chrome |
|---|---|
| `/dashboard/wholesaler` | `<header className="sticky top-0 z-50 flex items-center justify-between bg-white px-4 md:px-10 py-6">` containing `<h1 className="text-[24px] font-bold text-[#111]">Home</h1>` |
| `/dashboard/wholesaler/add-product` | `header sticky top-0 z-50 border-b border-[#e5e5e5] bg-white px-4 md:px-10 py-2.5` with only `<BackToDashboardButton />`. Footer: `"All Rights Reserved © Jewels India"` (left) and `"Crafted with ❤️ in blr"` (right) |
| `/dashboard/wholesaler/edit-product/[id]` | Same sticky header + right side: `user.email` (`13px #6B7280`, `hidden md:inline`) and `<SignOutButton />`. Back label is `"Back to uploads"` → `/dashboard/wholesaler/upload-history` when `?from=upload-history`, else `"Back to dashboard"` → `/dashboard/wholesaler` |
| `/dashboard/wholesaler/upload-history` | Same sticky header with `<BackToDashboardButton />` only |
| `/dashboard/wholesaler/catalogue` | No header bar. `h1 "My Catalogue"` (`32px bold #111`) + `p "See and manage all your catalogue categories from one place."` (`15px #666`); category chip row; **sticky filter bar** that hides on scroll-down (`translate-y-full` when `window.scrollY` increases past 150px, 10px dead-zone) |
| `/dashboard/wholesaler/orders` | Tab set: `[{id:"new",label:"New Orders"},{id:"active",label:"Active Orders"},{id:"completed",label:"Completed"},{id:"rejected",label:"Rejected"}]`, synced to `?tab=` via `router.replace(..., {scroll:false})` |
| `/dashboard/wholesaler/queries` | Renders `MessagesClient` with `currentUserType="wholesaler"` (no local header) |
| `/dashboard/my-uploads` | Own sticky header: back link `"← Upload Studio"` → `/dashboard/wholesaler/add-product`, breadcrumb `"/ MY UPLOADS"`, `SignOutButton` |

`BackToDashboardButton` — chevron-left 16×16 + label, `text-sm text-[#374151] hover:text-[#111827] font-sfpro`; **label is `hidden md:inline`, so on phones it is an icon-only back arrow**.
`MinimalHeader` (used by product flows) — `fixed top-0 w-full z-50 justify-end bg-white border-b border-[#E5E5E5] h-[60px] md:h-[64px] lg:h-[68px] px-4 md:px-8 lg:px-12`, shows `userEmail` (14px `#555`, `hidden md:block`) + `SignOutButton`.
`SignOutButton` default styling: `bg-[#0A0A0A] text-white px-6 py-3 rounded-xl text-[15px] font-medium`, label **"Sign out"**.

### 4.6 Wholesaler home → shell-level destinations
`OverviewSection` stat cards (title → href):
- `"Live Products"` → `/dashboard/wholesaler/catalogue`
- `"New Orders"` → `/dashboard/wholesaler/orders?tab=new` (red badge when `pendingCount > 0`)
- `"New Chat"` → `/dashboard/wholesaler/queries` (badge when unread conversations exist)
- `"Uploads Today"` → `/dashboard/wholesaler/upload-history`; value is `"{used}/{limit}"` or just `"{used}"` when limit is `Infinity`
Section heading `"Insights"` (`font-cirka text-4xl`). Promo card: `"Chamak"` / `"Review products with low engagement and Replace with better designs"` / pill `"Coming soon"` (disabled, non-interactive).
`HeroUploadSection`: eyebrow `"Welcome"`, then business name (falls back to `"Welcome"`), banner with `UploadButton` → `"Upload Now"` → `/dashboard/wholesaler/add-product`.
`CatalogueSection`: heading `"My Catalogue"`, sub `"See and manage all your catalogue categories from one place."`, 9 `CategoryCard`s → `/dashboard/wholesaler/catalogue?category=<slug>` + a dashed **"View All"** card (`→`) → `/dashboard/wholesaler/catalogue`.

---

## 5. RETAILER SHELL

### 5.1 Layout (`app/dashboard/retailer/layout.jsx`)
```jsx
<div className="theme-retailer flex min-h-screen bg-[#F0F2F5]">
  <RetailerSidebar retailer={retailerData} />
  <main className="flex-1 min-w-0 ml-0 lg:ml-[200px] pt-0 md:pt-[60px] lg:pt-0 pb-[92px] md:pb-0 min-h-screen flex flex-col transition-all duration-300">
    {children}
  </main>
  <Suspense fallback={null}><AddEmployeeModal /></Suspense>
</div>
```
- `retailerData = getRetailerSidebarProfile(user.id)` → `{ full_name, business_name, business_logo_url }` from `retailers`, `unstable_cache` revalidate **300 s**.
- `AddEmployeeModal` is `next/dynamic` with `loading: () => null` — only fetched when `?modal=add-employee`.
- Layout metadata: title `"Retailer Dashboard"`, description `"Manage your store and employees."`.

### 5.2 Nav items (`NAV_ITEMS` in `RetailerSidebar.jsx`)
All icons are **inline SVG, 18×18, `stroke-width:2`, round caps** unless noted.

| # | Label | Icon | Destination |
|---|---|---|---|
| 1 | `Dashboard` | 4 filled rounded squares (`rect` 8×8, `rx 1.5`, `fill:currentColor`) | `/dashboard/retailer` |
| 2 | `Employees` | two-person "users" glyph | `/dashboard/retailer/employees` |
| 3 | `Catalogue` | 4 outlined 7×7 squares | `/dashboard/retailer/catalogue` |
| 4 | `Your Taste` | heart outline | `/dashboard/retailer/your-taste` |
| 5 | `Store Theme` | circle + arcs ("contrast/theme" glyph) | `/dashboard/retailer/theme` |

Active predicate: `Dashboard` exact (`pathname === "/dashboard/retailer"`), all others `startsWith`.

### 5.3 Desktop / tablet drawer
`<aside>`: `fixed top-0 left-0 h-dvh z-50 flex flex-col w-[200px] bg-white border-r border-gray-100 transition-transform duration-300 lg:translate-x-0 overflow-y-auto overflow-x-hidden overscroll-contain hidden md:flex`, inline `padding: 20px 16px 24px 16px`. Off-canvas when closed (`-translate-x-full`); permanently visible at `lg` (≥1024px).
A `wheel` + `touchmove` listener on the aside **prevents scroll chaining** (`e.preventDefault()` when not scrollable or at an edge).

Contents, top → bottom:
1. Close button (`lg:hidden`) — 20×20 "X", `aria-label="Close navigation menu"`.
2. **"New Employee"** link → `?modal=add-employee` (`scroll={false}`): `w-full h-[44px] rounded-[10px] text-[14px] font-semibold text-[#3B82F6] bg-[#DBEAFE] mb-6`, class `lg:flex hidden`.
3. **Profile block** (`.sidebar-profile`, `mb-7 px-1`): avatar 36×36 `rounded-full border-2 border-gray-100`; `retailerName` (`14px font-bold #111111`, fallback **"User"**); `businessName` (`12px #6B7280`, fallback **"Business"**). Logo fallback `https://res.cloudinary.com/dcs0vuzwg/image/upload/v1777013959/jewel_logo_rhgin9.svg`.
4. **Nav list**: each row `h-[42px] rounded-[10px] px-3 gap-3`, `prefetch={true}`.
   - Active: `bg-[#F3F4F6] text-[#111111]`, icon wrapper `text-[#111111]`, label `font-semibold`.
   - Inactive: `text-[#6B7280]`, icon `text-[#9CA3AF]`, label `font-medium`; hover `bg-gray-50 text-[#374151]`.
   - Label size `14px`.
5. Illustration `https://res.cloudinary.com/dcs0vuzwg/image/upload/v1777301517/retailer_profile_gucmsl.svg` 110×110, `lg:block hidden`, `pointer-events-none`, `mb-5`.
6. **"EMPLOYEE VIEW"** button — `13px font-bold tracking-wider`, `text-[#6B7280] hover:text-[#3B82F6]`, users icon at `opacity-60`. Action: `POST /api/auth/toggle-view` `{ "mode": "employee" }` → on `res.ok` **hard navigation** `window.location.href = "/dashboard/employee"`. Failure path is an empty `catch` — **no error UI**.
7. **"LOG OUT"** — `<form action={signOut}>` submit button, `13px font-bold tracking-wider`, `text-[#6B7280] hover:text-[#111111]`, log-out glyph at `opacity-60`. No confirmation dialog (unlike wholesaler).

Compact height rule `@media (max-height: 780px)`: `.sidebar-profile { margin-bottom:12px }`, `.sidebar-new-emp { margin-bottom:12px; height:38px }`, `.sidebar-nav-item { height:36px }`.

### 5.4 Tablet top bar (768–1023px only: `hidden md:flex lg:hidden`)
`fixed top-0 left-0 right-0 h-[60px] bg-white border-b border-gray-100 z-40 px-4`:
- Left: hamburger button (24×24 three lines, `stroke-width:2.5`, `aria-label="Open navigation menu"`, min hit box 44×44, `active:scale-95`) + 28×28 round logo + business name (`14px font-bold #111111`, `truncate max-w-[140px]`).
- Right: **"New Employee"** → `?modal=add-employee`: `h-[36px] px-3.5 rounded-[8px] text-[12px] font-semibold text-[#3B82F6] bg-[#DBEAFE]`.
- Drawer backdrop when open: `fixed inset-0 bg-black/40 backdrop-blur-[2px] z-50 hidden md:block lg:hidden animate-fade-in`.

### 5.5 Mobile floating bottom nav (`≤767px`)
`.retailer-bottom-nav` is `display:none` above 767px. Same glass geometry as the wholesaler bar, except `bottom: calc(20px + env(safe-area-inset-bottom, 0px))`.
**Order (re-shuffled):** `Dashboard`, `Catalogue`, `Employees`, `Your Taste`, then **More** (business logo avatar 28×28 `rounded-full border-2`; border `black` when open, `gray-100` when closed).
Item styling: 44×44 circle; active `background: rgba(0,0,0,0.05)` + inline `opacity:1` + icon `text-[#111111]`; inactive inline `opacity:0.45` + icon `text-[#9CA3AF]`. `.bottom-nav-item svg { color:#111111 }`.
**Store Theme is absent from the bar** — it lives only in the More popover.

**More popover** (`bottom: calc(90px + env(safe-area-inset-bottom))`, width 200px, backdrop `rgba(0,0,0,0.15)` blur 2px):
1. **"Store Theme"** → `/dashboard/retailer/theme` (icon `text-[#9CA3AF]`).
2. **"Employee View"** — `POST /api/auth/toggle-view {mode:"employee"}` → `window.location.href="/dashboard/employee"`; failure is silently swallowed (`// silent`).
3. **"Logout"** — `<form action={signOut}>`, `.popover-logout` red `#ef4444`, hover `#fef2f2`.

### 5.6 Per-page chrome inside the retailer shell
| Route | Header copy |
|---|---|
| `/dashboard/retailer` | `h1 "Dashboard"` (28px bold `#111111`) + `"Welcome back! Here's your store overview"` (14px `#6B7280`) |
| `/dashboard/retailer/employees` | `h1 "Employees"` (`clamp(28px,3vw,32px)` extrabold `#111827`) + `"Welcome back! Here's an overview of your employees"` |
| `/dashboard/retailer/catalogue` | `h1 "Catalogue ({total})"` + `"Welcome back! look what all you have to offer"` + primary CTA **"Upload Design"** → `/dashboard/retailer/catalogue/upload` (`bg-[#111827] text-white rounded-[10px] px-6 py-3 h-[48px]`) |
| `/dashboard/retailer/theme` | `h1 "Store Theme"` (22px bold) + `"Select the store theme you think justifies your product and vision"` (13px `#6B7280`) |
| `/dashboard/retailer/your-taste` | Rendered by `YourTasteClient` (`force-dynamic`, `revalidate = 0`) |

Retailer dashboard quick-action cards (shell-relevant destinations):
- **"Add New Employee"** / `"Create employee accounts and login credentials"` → `?modal=add-employee`
- **"Upload Design"** / `"Add new jewellery designs to your private catalogue"` → `/dashboard/retailer/catalogue`
- `EmployeePortalCard`: title **"Employee portal"**, copyable URL `"{origin}/employee-login"` (protocol stripped for display), placeholder **"Loading..."**, copy button tooltip toggles `"Copy URL"` → `"Copied!"` (2 s, green `#16A34A` tick), open-in-new-tab button 44×44 black circle (`aria-label="Open employee login page in new tab"`), footnote `"Employee access for catalogue and order management."`
- `Employee Directory` card header: `h2 "Employee Directory"`

---

## 6. EMPLOYEE-VIEW SHELL (entered from the retailer shell)

`app/dashboard/employee/layout.jsx` (server): requires session else `redirect("/entry_page/signin")`; `ensureVirtualEmployee(user)`; else redirect. Loads in parallel: `getEmployeeRetailerShell(retailer_id)` → `{ businessName }` (fallback `"Your Store"`), `getEmployeeUnreadQueries(employee.id)` → bool, `getEmployeeLatestOrderUpdate(employee.id)` → ISO string|null, theme (cookie first, DB fallback). Metadata: title `"Employee Dashboard — Jewel India"`, description `"View your store designs, browse wholesaler products, and manage messages."`.

`EmployeeLayout`: wraps in `<ThemeProvider initialTheme={selectedTheme}>`, root `div.theme-employee` with `min-height:100vh; background:#FAFAFA`.
Nav bar hidden when pathname includes `/dashboard/employee/playground` or `/dashboard/employee/questionnaire`.

**"Employee View Active" badge** (only when `isRetailer`): `position:fixed; top:16px; right:16px; z-index:99999; background:#FEF3C7; border:1px solid #F59E0B; color:#B45309; padding:8px 16px; border-radius:30px; font-size:12px; font-weight:700; letter-spacing:0.05em; text-transform:uppercase; box-shadow:0 10px 15px -3px rgba(245,158,11,0.1), 0 4px 6px -4px rgba(245,158,11,0.1); pointer-events:none; animation: fadeIn 0.3s ease-out`. Leading dot `6×6`, `#D97706`, `animation: pulse 1.5s infinite`. Text: **"Employee View Active"**.

**Bottom pill nav** (`EmployeeTopNav.jsx`, exported as `EmployeeBottomNav`): `fixed bottom-5 left-1/2 -translate-x-1/2 z-[100] max-w-[95vw] sm:max-w-max`, `background: rgba(255,255,255,0.55)`, `backdrop-filter: blur(20px)`, `border:1px solid rgba(255,255,255,0.45)`, `border-radius:100px`, `padding:6px`, `box-shadow:0 8px 32px rgba(0,0,0,0.10), 0 1.5px 4px rgba(0,0,0,0.06)`.

| Label | Icon | Destination |
|---|---|---|
| `Home` | inline house SVG 17×17 | `/dashboard/employee` |
| `Catalogue` | CSS-masked SVG `…/v1778318363/catalogue_icon_rf0pjq.svg` 17×17 | `/dashboard/employee/wholesaler-gallery` |
| `Queries` | CSS-masked SVG `…/v1778318363/query_icon_p7xfqk.svg` 17×17 | `/dashboard/employee/messages` |
| `Orders` | inline box SVG 17×17 | `/dashboard/employee/orders` |

Active: `font-weight:600; color:#111827; background: rgba(255,255,255,0.85); box-shadow:0 1px 6px rgba(0,0,0,0.08)`; inactive `font-weight:500; color:#6b7280`, icon `opacity:0.7`. Text labels are `hidden sm:inline` (icon-only on phones).
**Notification dots:** `h-2 w-2` red (`bg-red-500` with white border) plus `animate-ping` halo (`bg-red-400 opacity-75`), positioned `-top-1 -right-1`. Shown for `Queries` when `hasUnreadQueries`, and for `Orders` when `hasUnreadOrders` — computed client-side against `localStorage["employee_orders_last_checked"]`; visiting `/dashboard/employee/orders` writes `new Date().toISOString()` and clears the dot.
**Retailer-only escape button:** gradient `linear-gradient(135deg, #3B82F6, #1D4ED8)`, white, `border-radius:100px`, `box-shadow:0 4px 12px rgba(29,78,216,0.2)`; label **"Take me to dashboard"** (`hidden lg:inline`) / **"Dashboard"** (`inline lg:hidden`). Action: `POST /api/auth/toggle-view {mode:"retailer"}` → `window.location.href="/dashboard/retailer"`.

### 6.1 View-mode API contract (`POST /api/auth/toggle-view`)
Request body: `{"mode": "employee"}` or `{"mode": "retailer"}`.
Responses: `200 {"success":true,"activeView":"employee"|"retailer"}`; `401 {"error":"Unauthenticated"}`; `403 {"error":"Forbidden: Only retailers can toggle views"}`; `404 {"error":"Retailer profile not found"}`; `400 {"error":"Invalid mode"}`; `500 {"error":"Failed to query employees table: …"}` / `{"error":"Failed to auto-provision virtual employee profile: …"}` / `{"error":"Internal Server Error: …"}`.
Side effect for `mode:"employee"`: auto-provisions an `employees` row `{auth_user_id, retailer_id, full_name (retailer.full_name || user_metadata.full_name || "Admin Owner"), email: user.email, designation:"Admin", status:"active", is_system_generated:true}` if none with `designation === "Admin"` exists. Then sets cookie `jewel_view_mode`.

---

## 7. ONBOARDING SHELLS

### 7.1 Wrappers
`app/onboard/layout.jsx` → `<div className="theme-wholesaler min-h-screen flex flex-col"><OnboardProvider><div className="onboard-page-transition flex-1 flex flex-col w-full">{children}</div></OnboardProvider></div>`
`app/onboard-retailer/layout.jsx` → identical but `theme-retailer` + `RetailerOnboardProvider`.
`.onboard-page-transition` = `onboardFadeIn 350ms cubic-bezier(0.16,1,0.3,1)` (opacity 0→1, translateY 8px→0); disabled under `prefers-reduced-motion: reduce`.

### 7.2 `OnboardLayout`
Root: `min-h-screen bg-[#FFFFFF] flex flex-col font-sans antialiased text-[#374151]`.
`<main>`: `flex-1 w-full max-w-[1100px] mx-auto px-[clamp(16px,3vw,48px)] pt-[clamp(24px,3vw,40px)] pb-2 flex flex-col md:flex-row md:justify-center md:items-start gap-8 md:gap-[clamp(24px,1vw,48px)]`.
Left column `w-full md:w-[340px] shrink-0 pt-2`; right column `w-full md:w-[500px] min-h-[400px]`.

### 7.3 `OnboardNavbar`
`header`: `w-full bg-[#FFFFFF] border-b border-[#E0E0E0] px-[clamp(16px,3vw,48px)] py-[clamp(6px,0.8vw,12px)] flex items-center justify-between shadow-sm z-10`.
- Left **"Back"**: chevron-left `clamp(14px,1.5vw,16px)` + label `#374151 font-medium text-[clamp(12px,1.4vw,14px)] tracking-wide`, pill hover `bg-gray-100`, `px-3 py-1.5 rounded-full`. **Signs the user out** then `router.push(backRoute || '/signup')`.
- Right **"Sign out"**: person icon + label, same type scale. Signs out then `router.push('/signup')`.

### 7.4 `LeftPanel`
`img src="/jewelLogo.svg"` at `w-[clamp(28px,3vw,36px)]` + wordmark **"Jewels India"** (`clamp(15px,1.6vw,18px)`, `font-extrabold`, `#111827`, `tracking-wide`).
`h1` heading `clamp(16px,1.8vw,23px)`, `tracking-tight`, `whitespace-nowrap`, `leading-[1.2]`, `font-extrabold`, `#111827`.
`p` description `clamp(13px,1.3vw,14px)`, `#9CA3AF`, `leading-relaxed`, `font-medium`. Container `max-w-[320px]`, `gap-4 md:gap-[18px]`.

**Exact per-step copy:**

| Route | heading | description | backRoute |
|---|---|---|---|
| `/onboard` | "Let me get to know you" | "We need a few details to verify who you are. This keeps your account and your business safe." | `/signup` |
| `/onboard/step2` | "Tell us about your business" | "This is how retailers will find and recognise you on the platform." | `/onboard` |
| `/onboard/step3` | "Almost there one last step" | "Upload your PAN and GST certificate so we can verify your business. This is a one-time process." | `/onboard/step2` (+`textMarginTop="md:mt-[18px]"`) |
| `/onboard/submitted` | dynamic (see below) | "we're reviewing your details" | `/entry_page/signin`, or `null` for `resubmission_required` / `rejected` / `verified` |
| `/onboard-retailer` | "Let me get to know you" | same as wholesaler step 1 | `/entry_page/signup` |
| `/onboard-retailer/step2` | "Tell us about your store" | "This is how wholesalers will find and recognise your retail store on the platform." | `/onboard-retailer` |
| `/onboard-retailer/step3` | "Almost there — one last step" | "Upload your PAN and GST certificate so we can verify your business. This is a one-time process." | `/onboard-retailer/step2` |

Page metadata titles: `"Step 1 of 3 — Onboarding"`, `"Step 2 of 3 — Onboarding"`, `"Step 3 of 3 — Onboarding"`, `"Verification Status — Celestique"`; retailer variants `"Step N of 3 — Retailer Onboarding"`.

### 7.5 `StepIndicator`
Props `currentStep` (1–4), `totalSteps` (always `3` in practice).
Label: `13px`, `#9CA3AF`, `font-semibold uppercase tracking-widest`.
- `currentStep <= totalSteps` → `<span class="font-extrabold text-[#111827]">Step {n}</span> of {total}`
- `currentStep > totalSteps` (i.e. the submitted page passes `currentStep={4} totalSteps={3}`) → **"Verification Progress"**, `font-extrabold #111827 tracking-wider`.
Micro-interaction: after **850 ms** the label pops to `scale(1.01) opacity 0.95 text-[#6B7280]` with `transform 400ms cubic-bezier(0.34,1.56,0.64,1)`.
Track: `w-full h-[6px] bg-[#E5E7EB] rounded-full overflow-hidden`; fill `bg-[#111827] rounded-full`, `transition: width 800ms cubic-bezier(0.25,1,0.5,1), box-shadow 400ms ease-out`.
Width formula: `step >= 4 → 100%`, else `((step - 1) / totalSteps) * 100` → **0 %, 33.33 %, 66.67 %, 100 %**.
Initial width is read from `sessionStorage["onboarding_last_step"]` (so the bar animates *from* the previous step); the current step is written back on mount. At `currentStep === 4` a completion glow `shadow-[0_0_8px_rgba(17,24,39,0.25)]` is applied after **800 ms**.
`prefers-reduced-motion` disables `.progress-bar-transition`.

### 7.6 Onboarding contexts
`OnboardContext` / `RetailerOnboardContext` are structurally identical (both `"use client"`, `useState`-based, no persistence):
`name, aadhar, frontImage, backImage` (step 1) · `businessName, selectedState, selectedCity, cities, logoImage` (step 2) · `panFile, gstFile` (step 3) · `isSubmitting, submitError`.
Hooks throw `"useOnboard must be used within OnboardProvider"` / `"useRetailerOnboard must be used within RetailerOnboardProvider"`.
**All state is lost on refresh** — the web flow relies on staying in one SPA session.

### 7.7 Submitted / verification screens
Wholesaler `/onboard/submitted` derives copy from `wholesalers.verification_status`:

| status | heading | paragraph | button | route |
|---|---|---|---|---|
| `pending` | "You're all submitted!" | "We'll verify your documents in 24–48 hours and notify you on your number once you're approved." | "I Understand" | `/entry_page/signup` |
| `on_hold` | "You're all submitted!" | `notification_message` ?? "Your account is on hold pending further review." | "I Understand" | `/entry_page/signup` |
| `rejected` | "Application Rejected" | `rejection_reason` ?? "There was an issue with your submission. Please click below to resubmit your documents." | "Resubmit" | `/onboard` |
| `resubmission_required` | "Resubmission Required" | same fallback as above | "Resubmit" | `/onboard` |
| `verified` | "Verification Complete!" | "You're verified! You can now access your full dashboard." | "Go to Dashboard" | `/dashboard/wholesaler` |
| `banned` | — | — | — | server `redirect("/entry_page/signup?error=banned")` |

Tracker strings: `"Under Verification"`, `"On Hold"`, `"Rejected"`, `"Action Needed"`, `"Verified"`.
Rejection panel: `bg-red-50/40 border border-red-200/60 rounded-2xl p-5`, title **"Application Rejected"** / **"Revision Required"**, sub-list header **"Items to Resubmit:"**; document key → label map: `aadhaar_front`→"Aadhaar Card (Front)", `aadhaar_back`→"Aadhaar Card (Back)", `pan_card`→"PAN Card", `gst_certificate`→"GST Certificate", `business_logo`→"Business Logo" (plus the `_url` suffixed variants).

Retailer `/onboard-retailer/submitted` uses **its own chrome** (not `OnboardLayout`): `theme-retailer` root, a header with `/jewelLogo.svg` + "Jewels India" + `OnboardSignOutButton`, main `max-w-[800px]`, `StepIndicator currentStep={4}`.
Headings: `pending` → "Application under review"; `rejected` → "Application Rejected"; `on_hold` → "Application On Hold"; `resubmission_required` → "Action Required"; default "Status Update".
Bodies: pending → "We've received your business details and documents. Our team is verifying your application right now. This usually takes 24-48 hours."; rejected → `rejection_reason` ?? "Unfortunately, your application did not meet our requirements."; on_hold → "Your application requires manual review and is currently on hold. We will reach out shortly."; resubmission_required → "We need you to update some information or re-upload documents before we can proceed."
Known defect to NOT copy: the logo width is `w-[wrap(24px,3vw,28px)]` — `wrap()` is not a CSS function, so the class is inert.

---

## 8. MODAL PATTERNS

Five distinct patterns exist. They must map to different iOS presentations.

### 8.1 Inline state modal — `ConfirmationModal` (`components/shared/ConfirmationModal.jsx`)
Props: `isOpen, onClose, onConfirm, title, message, confirmText = "Confirm", cancelText = "Cancel", variant = "danger" | "primary" | "success"`.
Overlay: `fixed inset-0 z-[100] flex items-center justify-center p-4`; backdrop `bg-black/40 backdrop-blur-sm` (click = close).
Card: `bg-white w-full max-w-sm rounded-[24px] shadow-2xl animate-in fade-in zoom-in duration-200`, `p-8 text-center`.
Icon puck `w-14 h-14 rounded-full mb-6`, SVG `w-7 h-7`, `stroke-width 2`:
- `danger`: `bg-red-50` / `text-red-600` / trash glyph; confirm `bg-red-600 hover:bg-red-700 shadow-red-200`
- `primary`: `bg-blue-50` / `text-blue-600` / info glyph; confirm `bg-[#111827] hover:bg-black shadow-gray-200`
- `success`: `bg-emerald-50` / `text-emerald-600` / check-circle glyph; confirm `bg-emerald-600 hover:bg-emerald-700 shadow-emerald-200`
Title `22px font-bold #111827 mb-2`; message `14px text-gray-500 leading-relaxed mb-8 px-2`.
Buttons stack vertically (`flex-col gap-3`): confirm `w-full py-3.5 text-white text-[15px] font-bold rounded-xl active:scale-[0.98]`; cancel `w-full py-3.5 bg-gray-50 text-gray-600 text-[15px] font-bold rounded-xl hover:bg-gray-100 active:scale-[0.98]`.
Real usages (wholesaler orders): `{title:"Confirm Order?", message:"Are you sure you want to accept and start production for this order?", variant:"primary"}`, `{title:"Mark as Packed?", message:"Has this order been fully packed and prepared for shipping?", variant:"primary"}`, `{title:"Dispatch Order?", message:"Are you sure you want to mark this order as dispatched?", variant:"success"}`.

### 8.2 Detail sheet — `BusinessProfileModal`
`fixed inset-0 z-[300] p-4`; backdrop `bg-black/20 backdrop-blur-sm` (click = close). Card `bg-white max-w-[500px] rounded-[24px] shadow-[0_20px_60px_-15px_rgba(0,0,0,0.1)] animate-fade-in-up`.
Locks page scroll on mount (`document.body.style.overflow = "hidden"` → `"unset"` on unmount).
Avatar 80×80 circle, `bg-gradient-to-br from-[#e8dec9] to-[#c9b48a]`, initial glyph `32px font-serif #5c4a2e font-bold tracking-widest`.
Name `24px font-medium text-gray-800`; **"Verified"** pill `11px font-bold text-green-600 bg-green-50 px-1.5 py-0.5 rounded uppercase` with 10×10 tick.
`"Member since {Month YYYY}"` — 14px gray-500. **Fallbacks baked in:** joined date defaults to `"February 2026"`, location defaults to `"Bandra, Mumbai"`, name defaults to `"Unknown Business"`. Rows: location (pin icon), `business.email` (envelope), `"Contact: {full_name}"` (person). All `14px text-gray-700 font-medium`, icon 18×18 gray-500.
Footer button: **"Back to orders"** — `px-6 py-2.5 bg-[#111827] text-white text-[13px] font-medium rounded-[8px] hover:bg-black`.

### 8.3 URL-param modal — `AddEmployeeModal`
Opened purely by the query string: `searchParams.get("modal") === "add-employee"`; closed with `router.replace(pathname, { scroll:false })`. Deep-linkable and back-button dismissible.
Overlay `fixed inset-0 z-[100] bg-black/40 backdrop-blur-sm p-4`; card `bg-white max-w-[480px] rounded-[16px] border border-white shadow-[0_10px_40px_rgba(0,0,0,0.1)] p-6 sm:p-8 max-h-[90vh] overflow-y-auto overscroll-contain`, close "X" 24×24 at `top-6 right-6`.
Header: **"Add New Employee"** (24px bold `#111827`) / **"New Member, New Access"** (15px `#9CA3AF`).
Error banner: `mb-4 p-3 bg-red-50 text-red-600 text-[13px] font-medium rounded-lg border border-red-100`.
**Step 1** fields (labels `13px font-bold #111827 uppercase tracking-wide`; inputs `h-[56px] bg-[#F8F8F8] rounded-[12px] px-[20px] 15px font-medium`, focus → `bg-white border-gray-100`):
- `Employee Name` placeholder `"Eg. parash"`
- `Mobile No` placeholder `"Eg. 9834874****"`, numeric, `maxLength 10`, digits-only sanitiser
- `Email Id` placeholder `"Eg. Parashe@gmail.com"`
- `Designation` placeholder `"Eg. Sales"`
CTA **"Set Password"** (`h-[52px] px-8 bg-black text-white font-bold text-[16px] rounded-[12px] shadow-[0_4px_14px_rgba(0,0,0,0.3)]`), disabled while loading → label **"Loading..."**, `disabled:opacity-70 disabled:cursor-not-allowed`. Calls `POST /api/employees/generate-email` `{full_name}` → `{email}`.
Validation copy: `"Please fill all fields."`, `"Please enter a valid 10-digit Indian mobile number."`, `"Failed to generate email."`, `"Something went wrong."`
**Step 2**: read-only `Login Email` (`bg-[#F9FAFB] rounded-[10px] h-[56px] 15px font-bold`), hint `"*this is your employees email"`; `Set Password` and `Confirm Password` (both `type="text"`, placeholder `"Eg. 9834874****"`). Errors: `"Please enter a password."`, `"Passwords do not match."` (also renders inline under the field, `12px font-semibold text-red-500`, ring `ring-2 ring-red-400`). Footer note `"Set them to access the employee account"` + CTA **"Save password"** (`h-[48px] px-6 bg-black rounded-[12px]`).
**Step 3**: read-only Login Email + Login Password each with a copy button (icon `https://res.cloudinary.com/dcs0vuzwg/image/upload/v1777306236/retailerProfile_COPY_szewo3.svg`, 20×20, `navigator.clipboard.writeText`); hints `"*this is your employees EMAIL"` and `"*this is your employees login PASSWORD"`; footer note **"Save these before you close."** + CTA **"Create"** → **"Saving..."** while loading. Calls `POST /api/employees/create` with `{full_name, phone, personal_email, designation, login_email, password_plain, status:"inactive"}`; on success `closeModal()` + `router.refresh()`, else shows `data.error || "Failed to save employee."`.

### 8.4 Full-screen media viewer — `FullImageViewer`
`fixed inset-0 z-[300] bg-black/95 backdrop-blur-xl select-none`, `touch-action: none`; locks body scroll while open.
Header (z-`320`, `pointer-events-none` container): **"Back"** pill button — `px-5 py-3 rounded-full bg-white/10 hover:bg-white/15 border border-white/10 backdrop-blur-md text-white text-[14px] font-medium active:scale-95` with a 18×18 left-arrow; right side counter `"{index+1} / {images.length}"` in `px-4 py-2 rounded-full bg-white/5 border border-white/5 text-[13px] text-white/60 tracking-wider`.
Chevron buttons: `w-14 h-14 rounded-full bg-white/5 hover:bg-white/10 border border-white/10 backdrop-blur-md text-white/80`, positioned `left-6 md:left-10` / `right-6 md:right-10`, `aria-label="Previous Image"` / `"Next Image"`; both wrap around (index 0 → last).
Image stage: `max-w-[90vw] max-h-[85vh] md:max-h-[88vh] aspect-square`, `transform: scale(zoom) translate(panX, panY)`, `transition-transform duration-200 ease-out`, cursor `zoom-in` / `grab`.
Placeholder while `currentImageUrl` is falsy: **"Loading Premium Design..."** (`text-white/40 text-[14px]`).
Gestures: one-finger horizontal swipe changes image (thresholds `|Δx| > 60 && |Δy| < 40`); two-finger pinch zoom clamped to `[1, 4]`; double-tap (<300 ms) → zoom `2.5` centred on tap, or reset; pan bounds `±(zoom-1)*200` px.
Keyboard: `ArrowLeft` prev, `ArrowRight` next, `Escape` close.
Thumbnail strip footer: gradient `from-black/90 via-black/40 to-transparent`, thumbs `72×72 rounded-[12px] bg-[#222] border-[2.5px]`; active `border-white scale-105 shadow-2xl opacity-100`, inactive `border-transparent opacity-45 hover:opacity-80 active:scale-95`; `aria-label="Thumbnail {n}"`.
Zoom slider overlay (`hidden md:flex`, desktop/tablet only): `bottom-4 right-12 bg-black/40 border border-white/10 backdrop-blur-md px-4 py-3 rounded-full`, minus button `−`, `<input type="range" min=1 max=4 step=0.1>` width `120px`, plus button `+`, readout `"{zoom.toFixed(1)}x"` (`11px text-white/70`).
Renders nothing when `!isOpen || !images || images.length === 0`.

### 8.5 Theme modals — `RetailerThemeClient`
**LockedModal**: overlay `rgba(0,0,0,0.55)` + `blur(6px)`; card `max-w-[340px] rounded-[24px]` with the theme image as background and gradient `linear-gradient(to top, rgba(0,0,0,0.82) 0%, rgba(0,0,0,0.3) 55%, rgba(0,0,0,0.1) 100%)`. Lock ring `w-16 h-16 rounded-full bg-white/15 border border-white/30`. Copy: title = theme name (`font-serif 28px`), **"This theme is coming in"**, badge **"✦ Version 2.0"**, body **"We're crafting this experience with care. Stay tuned — it will be worth the wait."**, CTA **"Got it"** (white pill, `13px font-bold`).
**ClaimModal**: overlay `rgba(0,0,0,0.65)` + `blur(8px)`; card `max-w-[340px] rounded-[24px] bg-black border border-white/10`, decorative `✦ ✦ ✦` in amber. Title **"Claim your palatial theme experience"** (`font-serif 24px`), body **"Unlock premium components, custom layouts, and a royal theme tailored for your store."**, CTA **"CLAIM"** on `bg-gradient-to-r from-amber-500 via-amber-600 to-yellow-500`, disabled during claim showing a spinner + **"Applying Theme..."**; secondary **"Cancel"** (`11px uppercase tracking-wider text-white/40`).
Success state after **1000 ms**: emerald tick circle `w-16 h-16 bg-emerald-500/10 border border-emerald-500/30`, **"Success!"** (emerald-400), **"{Theme} theme applied successfully"**; auto-dismiss after a further **1500 ms**, then writes the preference and `UPDATE retailers SET selected_theme = <id> WHERE user_id = <uid>`.

### 8.6 The wholesaler logout modal (§4.4) is a sixth, hand-rolled variant — different geometry (360 px, radius 20, horizontal buttons) from `ConfirmationModal`. iOS should unify these onto one alert component.

---

## 9. THEME SYSTEM

There are **two independent "theme" concepts**. Do not conflate them.

### 9.1 Role typography themes (CSS classes, applied by layouts)
Set in `app/globals.css`; the class is put on the layout root.

| Class | Applied by | Body / control font | Heading font |
|---|---|---|---|
| `.theme-wholesaler` | `app/dashboard/wholesaler/layout.jsx`, `app/onboard/layout.jsx` | `"Manrope", var(--font-sans), sans-serif` | `"Cirka", serif !important` (also `[class*="font-cirka"]`, `.title-font`, `.cirka-title`) |
| `.theme-retailer` | `app/dashboard/retailer/layout.jsx`, `app/onboard-retailer/layout.jsx`, retailer submitted page | `"Satoshi", var(--font-satoshi), sans-serif !important` **for everything incl. headings** | Satoshi (Cirka classes are overridden to Satoshi) |
| `.theme-employee` | `components/employee/EmployeeLayout.jsx` | `"Manrope", var(--font-sans), sans-serif` | `"Gilda Display", serif !important` |

### 9.2 Store themes (retailer-selectable, drives the employee-facing storefront look)
`lib/config/themePreference.js`:
```js
export const THEME_STORAGE_KEY = "retailer_selected_theme";
export const THEME_COOKIE_MAX_AGE = 60 * 60 * 24 * 365;   // 31 536 000 s
const APPLICABLE_THEME_IDS = new Set(["indian", "maharaja"]);
export function normalizeThemeId(themeId, fallback = "indian") { … }
```
**Only `indian` and `maharaja` are applicable.** The picker lists four:

| id | name | locked | card image |
|---|---|---|---|
| `indian` | "Indian" | false | `…/v1778837501/selected_er11az.svg` |
| `maharaja` | "Maharaja" | false (ships in CLAIM state) | `…/v1778837496/locked1_sc4thy.svg` |
| `utsav` | "Utsav" | **true** | `…/v1778837497/locked2_k8imhv.svg` |
| `neelam` | "Neelam" | **true** | `…/v1778837499/locked3_jztkzz.svg` |

All four share subtext **"Discover designs selected with precision, blending craftsmanship and ethnic style"**.
Card: `aspect-ratio 4/5`, `rounded-[18px]`, bottom gradient `linear-gradient(to top, rgba(0,0,0,0.65) 0%, rgba(0,0,0,0.08) 50%, transparent 75%)`; selected shadow `0 0 0 3px #111, 0 12px 32px rgba(0,0,0,0.18)`, unselected `0 4px 20px rgba(0,0,0,0.10)`; hover `scale(1.03)` on the image over `700ms`.
Badges (top-left): locked → `"🔒 Locked"` (`bg-white/20 backdrop-blur-md border border-white/30`, 10px bold uppercase tracking-widest); selected → `"✓ Selected"` (white pill, `#111` text); otherwise → `"✦ Claim"` (`bg-gradient-to-r from-amber-500 to-yellow-500`, white, extrabold).
Grid: `grid-cols-1 sm:grid-cols-2 gap-5 max-w-[780px]`; page bg `#F0F2F5`, `px-6 md:px-10 py-10`.

**Persistence — three places, written together:**
1. `localStorage["retailer_selected_theme"] = <id>`
2. `document.cookie = "retailer_selected_theme=<id>; path=/; max-age=31536000; SameSite=Lax"`
3. Supabase `retailers.selected_theme` (client-side `update` in `RetailerThemeClient`)

**Read order:** `app/dashboard/employee/layout.jsx` reads the cookie first (`normalizeThemeId(cookie, null)`); if absent it falls back to `getEmployeeRetailerTheme(retailer_id)` (DB, `maybeSingle`, normalised). `ThemeContext` re-reads `localStorage` on the client and overrides the SSR value. `getRetailerTheme(userId)` (cached 300 s) returns `data?.selected_theme || "indian"` **without normalisation**.

`context/ThemeContext.jsx` exposes `{ theme, setTheme }` with default `"indian"`; `setTheme` normalises, sets state, writes localStorage + cookie. Consumers: `EmployeeHomeClient`, `SelectionReviewClient`, `ProductInfoModal`. **There is no dark mode anywhere in this app.**

### 9.3 Shell design tokens (`app/globals.css` `@theme`)
```
--color-celestique-taupe : #E6DFD3
--color-celestique-cream : #F5F2EB
--color-celestique-dark  : #111111
--color-celestique-light : #ffffff
--color-celestique-muted : #8C857B
--color-celestique-border: #D9D0C5
--background: #FEFEFE   --foreground: var(--color-celestique-dark)
body { background:#FEFEFE; overflow-x: clip; -webkit-font-smoothing: antialiased }
html, body { max-width: 100vw; overflow-x: hidden }
```
Font stacks: `--font-serif: "Cirka", var(--font-bodoni), ui-serif, Georgia, Cambria, serif`; `--font-sans: "Manrope", var(--font-jost), ui-sans-serif, system-ui, sans-serif`; plus `--font-cirka`, `--font-gilda` ("Gilda Display"), `--font-manrope`, `--font-switzer`, `--font-gilroy`, `--font-sfpro` ("SF Pro"), `--font-satoshi`.
Local `@font-face` families: **Cirka** (300 woff2, 400 ttf, 700 woff2), **Gilda Display** 400, **Manrope** 200/300/400/500/600/700/800 (ttf), **Switzer** 400, **Gilroy** 400/500/600/700, **SF Pro** 400 (`/fonts/TTF/SF Pro.woff2`), **Satoshi** 300/400/500/700/900.

Shell animations:
```
fadeInUp   0.5s cubic-bezier(0.16,1,0.3,1)   → .animate-fade-in-up   (opacity 0→1, translateY 10px→0)
fadeIn     0.4s ease-out                     → .animate-fade-in
scaleIn    0.4s cubic-bezier(0.16,1,0.3,1)   → .animate-scale-in     (scale .98→1)
delay-100 / delay-200 / delay-300            → animation-delay 100/200/300 ms
cardEnter  0.55s cubic-bezier(0.16,1,0.3,1)  → .card-enter.is-visible (translateY 28px→0)
onboardFadeIn 350ms                          → .onboard-page-transition
checkDraw 350ms cubic-bezier(0.4,0,0.2,1)    → .animate-check-draw  (stroke-dashoffset 24→0)
rippleGreen 600ms                            → .animate-ripple-green
pulseAmber 2s infinite                       → .animate-pulse-amber
spinClockHand 8s linear infinite             → .animate-spin-slow
softShake 500ms                              → .animate-shake-red
stepFadeIn 400ms                             → .animate-step-fade
```
All of the above (plus `.progress-bar-transition`) are neutralised under `@media (prefers-reduced-motion: reduce)`.
Utilities: `.scrollbar-hide` / `.custom-scrollbar` (hide scrollbars), `.bg-grain` (inline SVG fractal-noise at `opacity 0.05`), `canvas.protected-image { user-select:none; -webkit-user-drag:none; -webkit-touch-callout:none }`.

---

## 10. SKELETON / LOADING / EMPTY / ERROR STATES

### 10.1 Route-level skeletons (`loading.jsx`) — exact markup
Only five exist. All use Tailwind `animate-pulse` (opacity 1 → .5 → 1 over 2 s, `cubic-bezier(0.4,0,0.6,1)`).

**`app/dashboard/wholesaler/loading.jsx`** and **`app/dashboard/wholesaler/catalogue/loading.jsx`** (byte-identical):
```
div.flex.flex-col.gap-6.p-8.animate-pulse
  div h-8 bg-gray-200 rounded w-48            ← title bar
  div h-4 bg-gray-100 rounded w-64            ← subtitle bar
  div.grid.grid-cols-1.sm:grid-cols-2.lg:grid-cols-3.xl:grid-cols-4.gap-6.mt-4
    ×8: div.rounded-[16px].border.border-gray-200.bg-white
          div.aspect-square.bg-gray-100
          div.p-4.flex.flex-col.gap-2
            div h-4 bg-gray-100 rounded w-3/4
            div h-3 bg-gray-50  rounded w-1/2
```

**`app/dashboard/retailer/loading.jsx`**:
```
div.flex.flex-col.gap-8.p-10.animate-pulse
  div.flex.flex-col.gap-1 → h-8 bg-gray-200 w-56 ; h-4 bg-gray-100 w-72 mt-2
  grid 1/sm:2/lg:4 gap-6 → ×4 div h-28 bg-white rounded-[16px] border border-gray-100 shadow-sm
  div h-64 bg-white rounded-[16px] border border-gray-100
```

**`app/dashboard/retailer/catalogue/loading.jsx`**:
```
div.flex.flex-col.gap-8.p-10.animate-pulse
  row: [h-8 bg-gray-200 w-56 ; h-4 bg-gray-100 w-40 mt-1]  ⟷  h-12 w-40 bg-gray-200 rounded-[10px]
  grid 1/sm:2/lg:3 gap-6 → ×6 div aspect-[4/5] bg-white rounded-[12px] border border-gray-100
```

**`app/dashboard/retailer/employees/loading.jsx`**:
```
div.flex.flex-col.gap-4.p-10.animate-pulse
  h-8 bg-gray-200 rounded w-48
  h-4 bg-gray-100 rounded w-64
  div.mt-4 → h-[52px] bg-gray-200 rounded-[12px] w-full mb-4 ; h-[300px] bg-gray-100 rounded-[16px] w-full
```

**Routes with NO `loading.jsx`** (they will show the previous screen until ready): `/dashboard/wholesaler/orders`, `/queries`, `/add-product`, `/add-retailer`, `/upload-history`, `/edit-product/[id]`, `/dashboard/retailer/your-taste`, `/dashboard/retailer/theme`, and every `/dashboard/employee/*` route.

### 10.2 Inline skeletons / shimmers
- `.skeleton-shimmer` — `background:#E6DFD3` with a `::after` sweep `linear-gradient(105deg, transparent 40%, rgba(245,242,235,0.7) 50%, transparent 60%)`, `shimmer 1.6s ease-in-out infinite` (translateX −100% → 100%).
- `.catalogue-skeleton-bg` — `linear-gradient(90deg,#f0f0f0 25%,#e0e0e0 50%,#f0f0f0 75%)`, `background-size:200% 100%`, `catalogue-shimmer 1.5s infinite` (background-position 200% → −200%).
- `/dashboard/retailer/employees` client fallback while `isLoading`: `h-[52px] bg-gray-200 rounded-[12px]` + `h-[300px] bg-gray-100 rounded-[16px]` inside `animate-pulse` (mirrors its `loading.jsx`).
- `AddEmployeeModal` disabled buttons: `disabled:opacity-70 disabled:cursor-not-allowed`, labels swap to `"Loading..."` / `"Saving..."`.
- `ClaimModal` spinner: `svg.animate-spin h-4 w-4` + `"Applying Theme..."`.

### 10.3 Error surfaces
- **`app/global-error.jsx`** — `"use client"`, calls `Sentry.captureException(error)` in an effect, renders its own `<html><body>` with Next's built-in `<NextError statusCode={0} />`. **No branded error screen exists.** UNEXTRACTABLE: the exact user-visible string is produced by `next/error` at runtime (generic "Application error"), not by this repo.
- No `error.jsx` boundaries exist anywhere under `app/`.
- `app/join/[code]/not-found.jsx` is the only 404 UI.
- Retailer catalogue/employees pages render an inline banner: `rounded-[10px] border border-red-200 bg-red-50 px-4 py-3 text-[12px] text-red-600 font-medium` (catalogue) / `p-4 bg-red-50 text-red-600 border border-red-200 rounded-[10px] text-sm font-medium` (employees).
- `EmployeeTable` delete/toggle failures use a raw `alert(err.message)`; `OrdersClient` delete failure also uses `alert(err.message)`. **There is no toast system in the repo** — no `sonner`, `react-hot-toast`, or custom toaster. UNEXTRACTABLE: toast copy, because toasts do not exist.
- View-mode toggle failures are silently swallowed in both the retailer sidebar and the employee nav (`// TODO: add proper error handling`, `// silent`).

### 10.4 Empty states in the shell
- `RetailerSidebar`: name → `"User"`, business → `"Business"`, logo → jewel logo SVG.
- `HeroUploadSection`: business name → `"Welcome"`.
- `getEmployeeRetailerShell`: business name → `"Your Store"`.
- `BusinessProfileModal`: `"Unknown Business"`, `"February 2026"`, `"Bandra, Mumbai"`.
- `EmployeePortalCard`: URL placeholder `"Loading..."`.
- `FullImageViewer`: `"Loading Premium Design..."`; renders `null` for an empty image array.
- `getRetailerDashboardData` with no retailer row returns all-zero counts and `recentEmployees: []`.

---

## 11. `ProtectedImage` (global side effects — critical for the port)

`components/shared/ProtectedImage.jsx` renders a `<canvas role="img" aria-label={alt} draggable="false">` (not an `<img>`), drawn via `lib/utils/imageProtection.renderProtectedImage`.
While **any** `ProtectedImage` is mounted it installs *document-wide* listeners:
- `document.addEventListener("contextmenu", preventDefault)` — right-click disabled on the **entire page**
- `window.addEventListener("keydown", …)` — blocks `Cmd/Ctrl + S` (and `Cmd/Ctrl + Shift + S`)
- canvas-local `contextmenu` prevention
Inline style: `userSelect:none, WebkitUserDrag:none, touchCallout:none`; optional `width`/`height` in px.
Used by every product/design surface (catalogue grid, product cards, order rows, upload history, employee gallery, viewers).

---

## 12. iOS MAPPING

Target: iOS 26 SwiftUI, **Liquid Glass floating `TabView`**. Both roles already use a floating translucent pill bar on mobile web (`rgba(255,255,255,0.85)` + `blur(20px)` + `border-radius:100px`), so the native tab bar is a *closer* match than the desktop rail. Build from the **mobile web IA**, not the desktop sidebar.

### 12.1 Recommended WHOLESALER tab set (5 tabs)

| # | Tab | SF Symbol | Root destination | Justified by |
|---|---|---|---|---|
| 1 | **Home** | `house` | `/dashboard/wholesaler` | Item 1 in both rail and bottom bar; exact-match active rule |
| 2 | **Catalogue** | `square.grid.2x2` | `/dashboard/wholesaler/catalogue` | Item 2 in the mobile bar; also the target of 3 home entry points (stat card, category cards, View All) |
| 3 | **Upload** | `arrow.up.circle` (or `plus.circle`) | `/dashboard/wholesaler/add-product` | Centre item in the mobile bar; also `UploadButton` "Upload Now" and `/dashboard` → this route |
| 4 | **Orders** | `shippingbox` | `/dashboard/wholesaler/orders` | Mobile bar item 4; has a badge source (`pendingOrdersCount`) |
| 5 | **Chat** | `bubble.left.and.bubble.right` | `/dashboard/wholesaler/queries` | Mobile bar item 5; has a badge source (unread conversations) |

Everything else becomes a push or a sheet (§12.3). "Add Retailer" is deliberately **not** a tab — on mobile web it is already demoted into the More popover.
iOS 26 `TabView` `.searchable` role is not applicable (no global search in the web shell).

### 12.2 Recommended RETAILER tab set (4 tabs + profile menu)

| # | Tab | SF Symbol | Root destination | Justified by |
|---|---|---|---|---|
| 1 | **Dashboard** | `square.grid.2x2.fill` | `/dashboard/retailer` | Bottom-bar item 1; exact-match active rule |
| 2 | **Catalogue** | `square.grid.2x2` | `/dashboard/retailer/catalogue` | Bottom-bar item 2 (promoted above Employees on mobile) |
| 3 | **Employees** | `person.2` | `/dashboard/retailer/employees` | Bottom-bar item 3 |
| 4 | **Your Taste** | `heart` | `/dashboard/retailer/your-taste` | Bottom-bar item 4 |

The web More popover (avatar-triggered) becomes a **profile menu in the navigation bar's trailing position** (the retailer's business logo as the button), containing: *Store Theme*, *Employee View*, *Log Out*. This preserves the exact web grouping — Store Theme is a settings-class destination, not a primary tab.

**Employee View is a mode switch, not a tab.** Native equivalent: switching `jewel_view_mode` should swap the entire root scene (a second `TabView` with Home / Catalogue / Queries / Orders) with a cross-dissolve, exactly as `window.location.href` does a hard reload on the web. Keep the persistent **"EMPLOYEE VIEW ACTIVE"** banner as a non-interactive capsule pinned top-trailing (`#FEF3C7` / border `#F59E0B` / text `#B45309`, radius 30, 12 pt bold uppercase) and keep the gradient **"Take me to dashboard"** button — in native, put it in the employee scene's toolbar rather than inside the tab bar.

### 12.3 Item-by-item placement

| Web item / route | iOS placement | Notes |
|---|---|---|
| `/dashboard/wholesaler` | **Tab 1 root** | Sticky `h1 "Home"` → large `.navigationTitle("Home")` |
| `/dashboard/wholesaler/catalogue` | **Tab 2 root** | Category chip row → horizontal scroll; filter bar → toolbar + `.presentationDetents` sheet |
| `/dashboard/wholesaler/catalogue?category=x` | Tab 2 root with selection state | Deep link from home category cards |
| `/dashboard/wholesaler/add-product` | **Tab 3 root** | Multi-step form; keep back-chevron affordance only as a nav-stack pop |
| `.../add-product/success` | **Push** on Tab 3 | Terminal screen; pop back to root on dismiss |
| `/dashboard/wholesaler/orders` | **Tab 4 root** | 4 tabs → segmented `Picker` bound to the same 4 ids; `.badge(pendingCount)` on the tab |
| `/dashboard/wholesaler/queries` | **Tab 5 root** | Conversation list; `.badge(unreadCount)` |
| a conversation | **Push** on Tab 5 | Web uses a two-pane list/detail; iPhone = push, iPad = `NavigationSplitView` |
| `/dashboard/wholesaler/add-retailer` | **Sheet** from the profile menu ("Invite Retailer") | Matches its More-popover demotion; `.medium` detent |
| `/dashboard/wholesaler/upload-history` | **Push** from Home's "Uploads Today" stat card | Never in the nav bar on web |
| `/dashboard/wholesaler/edit-product/[id]` | **Push** from Catalogue / Upload History | Back label already varies by origin (`Back to dashboard` / `Back to uploads`) — mirror with distinct nav titles |
| Logout (rail logo button / popover row) | **Confirmation dialog** (`.confirmationDialog`) | Copy verbatim: title "Confirm Logout", message "Are you sure you want to logout?", destructive "Logout", "Cancel" |
| `/dashboard/retailer` | **Tab 1 root** | |
| `?modal=add-employee` | **Sheet** (`.sheet` with `.large` detent, 3-step flow) | URL-driven on web → make it a deep-linkable route in iOS too |
| `/dashboard/retailer/employees` | **Tab 3 root** | Table → `List` with swipe actions (§12.4) |
| `/dashboard/retailer/catalogue` | **Tab 2 root** | "Upload Design" → toolbar `+` button |
| `/dashboard/retailer/catalogue/upload` | **Sheet** (full-height) | Form with up to 5 images |
| `.../upload/success` | Screen inside the same sheet | Dismiss returns to Catalogue |
| `/dashboard/retailer/your-taste` | **Tab 4 root** | |
| `/dashboard/retailer/theme` | **Push** from the profile menu | Not a tab on mobile web either |
| Theme Locked / Claim dialogs | **Sheets** (`.presentationDetents([.height(420)])`, `.presentationBackground(.thinMaterial)`) | Image-backed cards; keep the 1 s claim + 1.5 s success timing |
| Employee View toggle | **Root scene swap** | See §12.2 |
| Log Out (retailer) | **Confirmation dialog** | Web has none — adding one is a deliberate, safe deviation; flag to the user |
| `/onboard*`, `/onboard-retailer*` | **Separate `NavigationStack` outside the TabView** | Gated flow; no tab bar. `StepIndicator` → custom `ProgressView` with the exact 0/33.33/66.67/100 % steps |
| `/onboard/submitted`, `/onboard-retailer/submitted` | Terminal screen in that stack | Status-driven copy in §7.7 |
| `FullImageViewer` | **`.fullScreenCover`** | Native pinch/pan/double-tap; drag-to-dismiss replaces the tap-backdrop-to-close |
| `BusinessProfileModal` | **Sheet**, `.presentationDetents([.medium])` | CTA "Back to orders" |
| `ConfirmationModal` | **`.alert` / `.confirmationDialog`** | 3 variants map to `.destructive` / default / default-with-tint |

### 12.4 Web-only interactions that cannot translate 1:1

| # | Web interaction | Where | Proposed native equivalent |
|---|---|---|---|
| 1 | **Hover** reveals meaning: sidebar icons brighten (`opacity .35→.7`, bg `rgba(0,0,0,0.06)`), popover rows tint `#f3f4f6`, cards raise shadow, catalogue images `scale(1.05)`, theme cards `scale(1.03)` | Every shell surface | Replace with press states: `.buttonStyle(.plain)` + `scaleEffect(0.97)` on press, `.hoverEffect(.highlight)` for iPad pointer/trackpad only. Never gate information behind hover. |
| 2 | **`title=` tooltips** are the only labels for the wholesaler rail icons ("Home", "Add/Upload", "Add Retailer", "Catalogue", "Orders", "Chat", "Logout", "More Options") | `Sidebar.jsx` | Always-visible tab labels in the native tab bar + `.accessibilityLabel` on every icon button. |
| 3 | **Fixed 70 px desktop icon rail** / **200 px retailer drawer** | Both dashboards | Rail → 5-item Liquid Glass `TabView`. Drawer → tab bar + trailing profile menu. On iPad use `TabView(.sidebarAdaptable)` so the 200 px drawer form returns naturally in regular width. |
| 4 | **Hamburger drawer with off-canvas slide + backdrop** (768–1023 px only) | `RetailerSidebar` | Not needed on iPhone; on iPad it becomes the adaptable sidebar. Do not ship a custom hamburger. |
| 5 | **Right-click suppression + `Cmd/Ctrl+S` blocking + canvas-rendered images** (`ProtectedImage`) | All product imagery | No right-click on iOS. Equivalent protections: render into a `Canvas`/`Image` with `.contextMenu` omitted, disable `UIDragInteraction`, set `isUserInteractionEnabled` appropriately, and add screenshot-detection telemetry if the anti-copy intent must be preserved. **Cannot be replicated exactly** — flag to the user. |
| 6 | **Desktop-only zoom slider** in `FullImageViewer` (`hidden md:flex`, range 1→4 step 0.1, `−` / `+` buttons, `"{n}x"` readout) | Image viewer | Drop the slider; native `MagnifyGesture` with the same `[1,4]` clamp + double-tap-to-2.5× already covers it. Keep the "{n}x" readout only if the user wants parity. |
| 7 | **Mouse-drag panning while zoomed** (`e.buttons === 1`) | Image viewer | `DragGesture` (already implemented for touch); identical bounds `±(zoom−1)×200`. |
| 8 | **Keyboard navigation** in the viewer (`←`, `→`, `Esc`) | Image viewer | Swipe left/right (already present) + swipe-down / drag-to-dismiss; keep hardware-keyboard support via `.onKeyPress` for iPad. |
| 9 | **Scroll-direction-driven sticky filter bar** (hides after 150 px of downward scroll, 10 px dead-zone) | Wholesaler catalogue | `.toolbarVisibility(.automatic, for: .navigationBar)` with a scroll-linked hide, or a persistent filter button in the toolbar. Simpler and more predictable natively. |
| 10 | **Wheel/touchmove scroll-chaining prevention** on the retailer drawer | `RetailerSidebar` `useEffect` | Not applicable — UIKit scroll views do not chain. Delete. |
| 11 | **`?modal=add-employee` URL-driven modal** + browser Back to dismiss | Retailer shell | `.sheet(isPresented:)` driven by a deep-link route so `jewelindia://retailer?modal=add-employee` still works; swipe-down replaces Back. |
| 12 | **Copy-to-clipboard buttons** with hover tooltips ("Copy URL" → "Copied!") | `EmployeePortalCard`, `AddEmployeeModal` step 3 | `UIPasteboard` + a brief inline confirmation label (2 s, `#16A34A` tick) — no hover tooltip. |
| 13 | **"Open in new tab"** for the employee portal (`window.open(..., "_blank")`) | `EmployeePortalCard` | `ShareLink` or `SFSafariViewController`; there are no tabs. |
| 14 | **Hard page reload as a mode switch** (`window.location.href` after `toggle-view`) | Both view toggles | Root-scene swap with a cross-dissolve + a token/cookie refresh; keep the 7-day `jewel_view_mode` persistence in the Keychain/UserDefaults. |
| 15 | **`title=`-only More button ("More Options")** and avatar-as-menu-trigger | Both bottom bars | Native `Menu` with a labelled avatar button; add `.accessibilityLabel("More options")`. |
| 16 | **Multi-file `<input type="file" multiple>` picker (5-image cap)** | Retailer catalogue upload, wholesaler add-product | `PhotosPicker(maxSelectionCount: 5)` + `.fileImporter` for PAN/GST PDFs. |
| 17 | **`env(safe-area-inset-bottom)` hand-tuned pill offsets** (`bottom: calc(20px + inset)`, popover `calc(90px + inset)`) | Retailer bottom nav | Native tab bar handles the safe area; delete all manual offsets, including `pb-[92px]` / `padding-bottom:72px` main-content padding. |
| 18 | **Bootstrap Icons webfont from a CDN** loaded in `<head>` | Root layout | Replace with SF Symbols. UNEXTRACTABLE: which glyphs are actually used — the stylesheet is loaded globally but no `bi-*` class appears in the shell files read here. |
| 19 | **Cloudinary-hosted SVG nav icons** (wholesaler rail, employee nav masks) | Both shells | Bundle as local assets / SF Symbols. The `WebkitMaskImage` recolouring trick used by the employee nav has no direct SwiftUI analogue — use `.renderingMode(.template)`. |
| 20 | **No drag-and-drop anywhere** | — | Confirmed: no `onDragStart` / `onDrop` / `draggable=true` handlers exist in the shell files. Nothing to translate. |

### 12.5 Chrome elements the iOS app must still carry

| Web chrome | Present for | iOS home |
|---|---|---|
| Logo (`jewel_logo_rhgin9.svg`) as logout trigger | Wholesaler | Move logout to the profile menu; the logo should **not** be a destructive control natively |
| Business logo + retailer name + business name | Retailer | Nav-bar trailing avatar → profile menu header |
| "New Employee" CTA (`#3B82F6` on `#DBEAFE`) | Retailer (drawer + tablet bar) | Toolbar `+` on the Employees tab **and** a Dashboard quick action |
| Sign-out | Both | Profile menu, destructive role |
| Notification dots (Queries / Orders) | Employee view | `.badge()` on the tab items |
| Order/chat count badges | Wholesaler home stat cards | Keep as stat cards **and** mirror onto tab badges |
| "Employee View Active" banner | Retailer-in-employee-mode | Persistent capsule + a distinct tint on the root scene |
| Footer "All Rights Reserved © Jewels India" / "Crafted with ❤️ in blr" | Add-product / edit-product pages | Move into Settings → About; do not put a footer on scrolling forms |

---

## 13. Open items / flags for the user

1. **`signOut()` redirects to `/signin`**, which only resolves because of a permanent redirect in `next.config.mjs`. Native should go straight to the sign-in screen.
2. **Two different "verified wholesaler" destinations** — middleware sends verified wholesalers to `/dashboard/wholesaler`; `lib/actions/auth.js` requires `has_visited_dashboard` first. Confirm which is intended before implementing the launch router.
3. **`OnboardNavbar`'s "Back" button signs the user out.** It is labelled "Back" but destroys the session. On iOS a back chevron must not sign out — confirm the intended behaviour.
4. **Retailer sidebar is `hidden md:flex`** — below 768 px the drawer never renders, so phone users reach Store Theme / Employee View / Logout only through the More popover.
5. **`utsav` and `neelam` themes are unreachable** (`APPLICABLE_THEME_IDS` allows only `indian`/`maharaja`); their cards exist purely to show the LockedModal.
6. **No toast system, no `error.jsx` boundaries, no dark mode** anywhere in the web app.
7. UNEXTRACTABLE: the runtime text of `app/global-error.jsx` (rendered by `next/error`, not by this repo).
8. UNEXTRACTABLE: which Bootstrap Icons glyphs the app uses — the CDN stylesheet is loaded globally but no `bi-*` class appears in any shell file read for this document.
9. UNEXTRACTABLE: the visual design of the Cloudinary nav icons (remote SVGs, not in the repo) — they must be downloaded or re-drawn as SF Symbols.
