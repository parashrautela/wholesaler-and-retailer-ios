# 01 — Design System Spec (Jewel India Web → SwiftUI iOS)

**Source of truth:** `/Users/parashrautela/Documents/jewel india /Jewel-India-Frontend`
**Extraction date:** 2026-08-03
**Stack:** Next.js 16.1.6 · React 19.2.3 · Tailwind CSS v4 (CSS-first, **no `tailwind.config.*` file exists** — all tokens live in `app/globals.css` `@theme`)
**PostCSS:** `postcss.config.mjs` → plugin `@tailwindcss/postcss` only. No `tailwindcss-animate`, no `tw-animate-css`.

---

## 0. File inventory (everything that carries styling)

### Global stylesheet
| File | Lines | Contents |
|---|---|---|
| `app/globals.css` | 525 | 22 `@font-face` rules, `@theme` token block, `:root`, `body`, 13 `@keyframes`, ~25 utility classes, 3 theme-font-mapping blocks, 2 `prefers-reduced-motion` blocks, 2 media queries |

### CSS Modules (exactly 6, all read in full)
| File | Scope |
|---|---|
| `app/dashboard/wholesaler/add-retailer/addRetailer.module.css` | Add-Retailer flow diagram page |
| `app/join/[code]/joinLanding.module.css` | Public invite landing card |
| `components/employee/employeeTopNav.module.css` | Employee top nav bar |
| `components/wholesaler/orders/orders.module.css` | Orders list + retailer modal |
| `components/wholesaler/queries/queries.module.css` | Queries split-panel chat |
| `components/wholesaler/referral/referralManager.module.css` | Referral link generator |

### Inline `<style>` blocks with `@keyframes` (NOT in globals.css)
| File | Keyframes defined |
|---|---|
| `components/wholesaler/Sidebar.jsx:403,407,505` | `fadeIn`, `scaleUp`, `popoverFadeIn` |
| `components/retailer/RetailerSidebar.jsx:392` | `popoverFadeIn` |
| `components/employee/EmployeeLayout.jsx:17,22` | `pulse`, `fadeIn` |

---

## 1. Color tokens

### 1.1 Canonical `@theme` tokens (`app/globals.css` lines 191–196)

These are the ONLY named design-system colors. Tailwind v4 emits them as CSS vars on `:root` AND generates utilities `bg-celestique-*`, `text-celestique-*`, `border-celestique-*`, etc.

| Token name | Tailwind utility stem | **Exact hex** | RGB | SwiftUI |
|---|---|---|---|---|
| `--color-celestique-taupe` | `celestique-taupe` | **`#E6DFD3`** | 230, 223, 211 | `Color(red: 0.902, green: 0.875, blue: 0.827)` |
| `--color-celestique-cream` | `celestique-cream` | **`#F5F2EB`** | 245, 242, 235 | `Color(red: 0.961, green: 0.949, blue: 0.922)` |
| `--color-celestique-dark` | `celestique-dark` | **`#111111`** | 17, 17, 17 | `Color(red: 0.067, green: 0.067, blue: 0.067)` |
| `--color-celestique-light` | `celestique-light` | **`#ffffff`** | 255, 255, 255 | `Color.white` |
| `--color-celestique-muted` | `celestique-muted` | **`#8C857B`** | 140, 133, 123 | `Color(red: 0.549, green: 0.522, blue: 0.482)` |
| `--color-celestique-border` | `celestique-border` | **`#D9D0C5`** | 217, 208, 197 | `Color(red: 0.851, green: 0.816, blue: 0.773)` |

### 1.2 `:root` / body (lines 199–214)

```css
:root {
  --background: #FEFEFE;
  --foreground: var(--color-celestique-dark);   /* → #111111 */
}
@theme inline {
  --color-background: var(--background);
  --color-foreground: var(--foreground);
}
body {
  background: #FEFEFE;
  color: var(--foreground);        /* #111111 */
  overflow-x: clip;
  -webkit-font-smoothing: antialiased;
}
```

- **App background = `#FEFEFE`** (NOT pure white). Utility stems `bg-background` / `text-foreground` generated but effectively unused in favour of literals.
- `app/layout.jsx:84` sets `<body className="… font-sans antialiased text-celestique-dark">` → default text color `#111111`, default family = `--font-sans`.

### 1.3 Alpha variants of celestique tokens actually used in JSX

Tailwind `/NN` = opacity percent applied to the token color.

| Utility | Base hex | Alpha | Occurrences |
|---|---|---|---|
| `text-celestique-dark` | `#111111` | 1.00 | 60 |
| `text-celestique-dark/60` | `#111111` | 0.60 | 21 |
| `text-celestique-dark/40` | `#111111` | 0.40 | 13 |
| `text-celestique-dark/30` | `#111111` | 0.30 | 8 |
| `text-celestique-dark/50` | `#111111` | 0.50 | 4 |
| `text-celestique-dark/80` | `#111111` | 0.80 | 1 |
| `text-celestique-dark/35` | `#111111` | 0.35 | 1 |
| `text-celestique-dark/25` | `#111111` | 0.25 | 1 |
| `text-celestique-dark/20` | `#111111` | 0.20 | 1 |
| `bg-celestique-dark` | `#111111` | 1.00 | 19 |
| `bg-celestique-dark/90` | `#111111` | 0.90 | 2 |
| `bg-celestique-dark/80` | `#111111` | 0.80 | 1 |
| `bg-celestique-dark/60` | `#111111` | 0.60 | 1 |
| `bg-celestique-dark/30` | `#111111` | 0.30 | 2 |
| `border-celestique-dark` | `#111111` | 1.00 | 15 |
| `border-celestique-dark/10` | `#111111` | 0.10 | 16 |
| `border-celestique-dark/20` | `#111111` | 0.20 | 4 |
| `border-celestique-dark/15` | `#111111` | 0.15 | 2 |
| `border-celestique-dark/8` | `#111111` | 0.08 | 2 |
| `border-celestique-dark/5` | `#111111` | 0.05 | 1 |
| `border-celestique-dark/50` | `#111111` | 0.50 | 1 |
| `border-celestique-dark/60` | `#111111` | 0.60 | 1 |
| `text-celestique-cream` | `#F5F2EB` | 1.00 | 15 |
| `bg-celestique-cream` | `#F5F2EB` | 1.00 | 12 |
| `bg-celestique-cream/90` | `#F5F2EB` | 0.90 | 4 |
| `bg-celestique-cream/85` | `#F5F2EB` | 0.85 | 5 |
| `bg-celestique-cream/80` | `#F5F2EB` | 0.80 | 4 |
| `border-celestique-taupe` | `#E6DFD3` | 1.00 | 16 |
| `bg-celestique-taupe/20` | `#E6DFD3` | 0.20 | 7 |
| `bg-celestique-taupe/10` | `#E6DFD3` | 0.10 | 3 |
| `bg-celestique-taupe/5` | `#E6DFD3` | 0.05 | 1 |
| `bg-celestique-taupe` | `#E6DFD3` | 1.00 | 1 |
| `text-celestique-taupe` | `#E6DFD3` | 1.00 | 2 |
| `text-celestique-muted` | `#8C857B` | 1.00 | 3 |
| `border-celestique-border` | `#D9D0C5` | 1.00 | 1 |
| `border-celestique-border/30` | `#D9D0C5` | 0.30 | 2 |
| `bg-celestique-light` | `#ffffff` | 1.00 | 1 |
| `from-celestique-dark/30` | `#111111` | 0.30 | 1 |
| `divide-celestique-dark/0` | `#111111` | 0.00 | 1 |

**Reality check:** celestique tokens are used ~240 times total, but raw hex literals are used **~1,400+ times**. The celestique palette is essentially the *retailer/storefront/product-card* language; the *wholesaler dashboard* is almost entirely built on the raw grey/blue palette in §1.4.

### 1.4 De-facto palette — raw hex literals, by frequency

Counted across every `.jsx`/`.js`/`.css` under `app/` + `components/`. This is what the app actually renders.

#### Greys (the dominant neutral ramp — Tailwind v3 grey values used as literals)
| Hex | Count | Role |
|---|---|---|
| `#111827` | 164 | **Primary text** (headings, values, active nav) |
| `#6B7280` | 98 | **Secondary text / muted label** |
| `#9CA3AF` | 87 | **Tertiary text / placeholder / disabled label** |
| `#374151` | 67 | **Body text / form labels / dark buttons** |
| `#E5E7EB` | 43 | **Default hairline border / divider** |
| `#4B5563` | 30 | Body text alt / badge text |
| `#F9FAFB` | 26 | Subtle fill (input suffix, hover row) |
| `#E5E5E5` | 21 | Input border (UI kit) |
| `#F5F5F5` | 21 | Panel fill |
| `#D1D5DB` | 20 | Stronger border / disabled fill |
| `#F9F9F9` | 15 | Panel fill alt |
| `#1F2937` | 15 | Dark button fill |
| `#FAFAFA` | 14 | Page fill (employee shell, auth input bg) |
| `#F3F4F6` | 13 | Chat bubble / chip fill |
| `#F8F8F8` | 7 | Panel fill alt |
| `#F0F0F0` | 9 | Skeleton base |
| `#E0E0E0` | 8 | Auth divider / Google button border |
| `#FCFCFC` | 4 | Panel fill alt |

#### Blacks / near-blacks
| Hex | Count | Role |
|---|---|---|
| `#111` | 51 | Shorthand for `#111111` (CSS-module buttons, titles) |
| `#111111` | 34 | Celestique dark / auth heading |
| `#1A1A1A` | 29 | **Auth primary CTA fill** |
| `#000000` | 15 | Pure black (Chamak badge, UploadButton) |
| `#2E2833` | 4 | **Sidebar logo tile + logout button + PWA admin `theme_color`** |
| `#2A2A2A` | 4 | UploadButton hover |
| `#333333` | 4 | Auth CTA hover / auth label |
| `#2C1F18` | 4 | Deep brown accent |

#### Brand brown (auth + storefront PWA)
| Hex | Count | Role |
|---|---|---|
| `#6B4F4F` | 28 | **"JI" logo tile fill (AuthLayout), storefront PWA `theme_color`** |
| `#3D3232` | 2 | Gradient start (avatar) |
| `#A38686` | 1 | Gradient end (avatar) |
| `#4A3B32` | 3 | Brown text |

#### Semantic — success
| Hex | Count | Role |
|---|---|---|
| `#22C55E` | 15 | Toggle ON fill, focus ring |
| `#16A34A` | 9 | "Delivered" status text, verified badge |
| `#DCFCE7` | 6 | Success chip bg |
| `#166534` | 4 | Success chip text |
| `#10B981` | 4 | Emerald accent |

#### Semantic — danger
| Hex | Count | Role |
|---|---|---|
| `#EF4444` | 37 | **Error text / logout icon stroke / error dot** |
| `#DC2626` | 15 | Reject button, error paragraph |
| `#FEE2E2` | 3 | Logout hover bg (employee nav) |
| `#FEF2F2` | 6 | Danger hover bg / warning icon circle bg |

#### Semantic — warning / amber
| Hex | Count | Role |
|---|---|---|
| `#B45309` | 8 | "In production" / urgent status text, modal avatar glyph |
| `#FEF3C7` | 7 | Amber chip bg ("Employee View Active") |
| `#F59E0B` | 3 | Amber border |
| `#D97706` | 2 | Query card "from" text, pulsing dot |
| `#856404` | 4 | Legacy warning text |
| `#FBEFBE` | 3 | Pale amber border |

#### Semantic — info / blue
| Hex | Count | Role |
|---|---|---|
| `#3B82F6` | 18 | **Focus border + focus ring (UI kit inputs/selects)** |
| `#2563EB` | 6 | Unread badge fill |
| `#EFF6FF` | 4 | Info panel bg |
| `#E0E7FF` | 4 | Info chip |
| `#EEF2FF` | (module) | Wholesaler chat bubble bg |
| `#93C5FD` | 2 | Info border |
| `#007AFF` | 4 | iOS system blue (already-iOS-native) |

#### Gold / Chamak gradient family
| Hex | Role |
|---|---|
| `#bb8651` → `#f6e0a7` | Chamak card `bg-gradient-to-r` (OverviewSection) |
| `#B8895A` → `#F5E6C8` | Weekly Review banner `bg-gradient-to-r` |
| `#e8dec9` → `#c9b48a` | `bg-gradient-to-br` accent |
| `#e4cc8f` | Chamak badge border (`border-[#e4cc8f]`, card border at `/30`) |
| `rgba(228,204,143,0.3)` | Chamak badge inset shadow |
| `#FDF7EC` → `#F2E3C6` | Orders modal avatar `linear-gradient(135deg, …)` |

#### Purple (employee avatar only)
`linear-gradient(135deg, #6366F1 0%, #A855F7 100%)` — `employeeTopNav.module.css .avatar`

#### Other literals ≥3 occurrences
`#FFFFFF` (36), `#FFF` (20), `#666` (17), `#999` (15), `#EEE` (12), `#6E6E6E` (12), `#A8A8A8` (8), `#888` (6), `#DDD` (5), `#696969` (4), `#333` (5), `#E0DBD2` (4), `#F0F2F5` (3, retailer shell bg), `#FCE7F3` (3)

### 1.5 Gradients used (exact)
| Class / CSS | Where |
|---|---|
| `bg-gradient-to-r from-[#bb8651] to-[#f6e0a7]` | Chamak "Coming soon" card, `OverviewSection.jsx:59` |
| `bg-gradient-to-r from-[#B8895A] to-[#F5E6C8]` | `WeeklyReviewBanner.jsx` |
| `bg-gradient-to-r from-white/30 via-white/55 to-white/30` | ×4 (shimmer sweeps) |
| `bg-gradient-to-t from-black to-[#3c3c3c]` | ×2 |
| `bg-gradient-to-b from-[#2a2a2a] to-[#111]` | ×2 |
| `bg-gradient-to-b from-[#2a2a2a] to-[#000]` | ×1 |
| `bg-gradient-to-tr from-[#FAF9F6] via-[#F5F2EB] to-[#EAE5D9]` | ×1 |
| `bg-gradient-to-tr from-[#3D3232] to-[#A38686]` | ×1 |
| `bg-gradient-to-tr from-[#3D3232] to-[#6B4F4F]` | ×1 |
| `bg-gradient-to-t from-black/90 via-black/40 to-transparent` | ×1 |
| `bg-gradient-to-br from-[#e8dec9] to-[#c9b48a]` | ×1 |
| `bg-linear-to-b from-celestique-dark/30 to-transparent` | `CategoryCard.jsx` name scrim (top 50% of card) |
| `bg-linear-to-br ${category.gradient}` | `CategoryCard.jsx` image-error fallback |
| `linear-gradient(135deg, #6366F1 0%, #A855F7 100%)` | `employeeTopNav.module.css .avatar` |
| `linear-gradient(135deg, #FDF7EC, #F2E3C6)` | `orders.module.css .avatar` |
| `linear-gradient(105deg, transparent 40%, rgba(245,242,235,0.7) 50%, transparent 60%)` | `.skeleton-shimmer::after` |
| `linear-gradient(90deg, #f0f0f0 25%, #e0e0e0 50%, #f0f0f0 75%)` | `.catalogue-skeleton-bg` |

**Note:** codebase mixes Tailwind v4's `bg-linear-to-*` and the legacy `bg-gradient-to-*` spelling. Both currently compile.

### 1.6 PWA theme colors (`app/manifest.js`)
| App | `background_color` | `theme_color` | orientation |
|---|---|---|---|
| Admin (`app.jewelindia.shop`) — **this is the wholesaler app** | `#ffffff` | **`#2E2833`** | `landscape` |
| Storefront | `#ffffff` | `#6B4F4F` | `portrait` |

> ⚠️ Admin manifest declares `orientation: "landscape"` and `start_url: "/dashboard"`. Flag for the iOS port: the real dashboard is used portrait on mobile (there is a mobile bottom nav) — the manifest value appears to be a bug.

---

## 2. Typography

### 2.1 `@font-face` inventory — every rule in `globals.css`, with file format

| # | `font-family` | `font-weight` | File | **Format** | Size | iOS OK? |
|---|---|---|---|---|---|---|
| 1 | `Cirka` | 300 | `/fonts/TTF/Cirka-Light.woff2` | **woff2** | 19,024 B | ❌ convert |
| 2 | `Cirka` | 400 | `/fonts/TTF/Cirka-Regular.ttf` | truetype | 64,356 B | ✅ |
| 3 | `Cirka` | 700 | `/fonts/TTF/Cirka-Bold.woff2` | **woff2** | 18,384 B | ❌ convert |
| 4 | `Gilda Display` | 400 | `/fonts/TTF/GildaDisplay-Regular.woff2` | **woff2** | 28,348 B | ❌ convert |
| 5 | `Manrope` | 200 | `/fonts/TTF/Manrope-ExtraLight.ttf` | truetype | 96,700 B | ✅ |
| 6 | `Manrope` | 300 | `/fonts/TTF/Manrope-Light.ttf` | truetype | 96,728 B | ✅ |
| 7 | `Manrope` | 400 | `/fonts/TTF/Manrope-Regular.ttf` | truetype | 96,832 B | ✅ |
| 8 | `Manrope` | 500 | `/fonts/TTF/Manrope-Medium.ttf` | truetype | 96,904 B | ✅ |
| 9 | `Manrope` | 600 | `/fonts/TTF/Manrope-SemiBold.ttf` | truetype | 96,936 B | ✅ |
| 10 | `Manrope` | 700 | `/fonts/TTF/Manrope-Bold.ttf` | truetype | 96,800 B | ✅ |
| 11 | `Manrope` | 800 | `/fonts/TTF/Manrope-ExtraBold.ttf` | truetype | 97,524 B | ✅ |
| 12 | `Switzer` | 400 | `/fonts/TTF/Switzer-Regular.woff2` | **woff2** | 16,704 B | ❌ convert |
| 13 | `Gilroy` | 400 | `/fonts/TTF/Gilroy-Regular.woff2` | **woff2** | 24,932 B | ❌ convert |
| 14 | `Gilroy` | 500 | `/fonts/TTF/Gilroy-Medium.woff2` | **woff2** | 45,568 B | ❌ convert |
| 15 | `Gilroy` | 600 | `/fonts/TTF/Gilroy-SemiBold.woff2` | **woff2** | 26,252 B | ❌ convert |
| 16 | `Gilroy` | 700 | `/fonts/TTF/Gilroy-Bold.woff2` | **woff2** | 44,552 B | ❌ convert |
| 17 | `SF Pro` | 400 | `/fonts/TTF/SF Pro.woff2` (note the space in the filename) | **woff2** | 815,292 B | ❌ / see note |
| 18 | `Satoshi` | 300 | `/fonts/TTF/Satoshi-Light.woff2` | **woff2** | 22,728 B | ❌ convert |
| 19 | `Satoshi` | 400 | `/fonts/TTF/Satoshi-Regular.woff2` | **woff2** | 25,352 B | ❌ convert |
| 20 | `Satoshi` | 500 | `/fonts/TTF/Satoshi-Medium.woff2` | **woff2** | 25,492 B | ❌ convert |
| 21 | `Satoshi` | 700 | `/fonts/TTF/Satoshi-Bold.woff2` | **woff2** | 25,216 B | ❌ convert |
| 22 | `Satoshi` | 900 | `/fonts/TTF/Satoshi-Black.woff2` | **woff2** | 23,332 B | ❌ convert |

**All 22 rules use `font-style: normal` and `font-display: swap`. There are NO italic faces anywhere.**

**Orphan file:** `public/fonts/TTF/Cirka-Variable.woff2` (27,072 B) exists on disk but is **referenced by zero `@font-face` rules and zero source files**. Do not ship it.

### 2.2 ⚠️ iOS CoreText: families needing `.woff2 → .ttf/.otf` conversion

CoreText / `CTFontManagerRegisterFontsForURL` cannot load `.woff2`. Every family below must be converted before bundling:

| Family | Faces needing conversion | Notes |
|---|---|---|
| **Gilda Display** | 1 / 1 — **100% woff2** | Free on Google Fonts → download the original TTF instead of converting. |
| **Switzer** | 1 / 1 — **100% woff2** | Fontshare (Indian Type Foundry) ships OTF/TTF — re-download rather than convert. |
| **Gilroy** | 4 / 4 — **100% woff2** | Commercial (Radomir Tinkov). Convert or re-license the OTFs. **This is the single most-used custom family in the wholesaler dashboard (64 occurrences).** |
| **Satoshi** | 5 / 5 — **100% woff2** | Fontshare ships OTF/TTF — re-download. |
| **SF Pro** | 1 / 1 — **100% woff2** | ⚠️ **Do NOT bundle.** On iOS use the system font (`.SF Pro` = `Font.system` / `-apple-system`). Bundling Apple's SF Pro is a licence violation, and the 815 KB file is redundant. |
| **Cirka** | 2 / 3 woff2 (Light 300 + Bold 700). Regular 400 is already `.ttf`. | Commercial (Pangram Pangram). Must obtain/convert Light + Bold. |
| **Manrope** | 0 / 7 — **all TTF** ✅ | Ships as-is. Also loaded a *second* time via `next/font/google` (see §2.4). |

**Summary of woff2-only families (nothing usable on iOS without conversion):**
`Gilda Display`, `Switzer`, `Gilroy`, `Satoshi`, `SF Pro`.
**Partially woff2:** `Cirka` (Light + Bold only).
**Clean:** `Manrope`.

### 2.3 `@theme` font tokens (`globals.css` lines 181–189)

```css
--font-serif:   "Cirka", var(--font-bodoni), ui-serif, Georgia, Cambria, serif;
--font-sans:    "Manrope", var(--font-jost), ui-sans-serif, system-ui, sans-serif;
--font-cirka:   "Cirka", serif;
--font-gilda:   "Gilda Display", serif;
--font-manrope: "Manrope", sans-serif;
--font-switzer: "Switzer", ui-sans-serif, system-ui, sans-serif;
--font-gilroy:  "Gilroy", ui-sans-serif, system-ui, sans-serif;
--font-sfpro:   "SF Pro", ui-sans-serif, system-ui, sans-serif;
--font-satoshi: "Satoshi", sans-serif;
```

→ generates utilities `font-serif`, `font-sans`, `font-cirka`, `font-gilda`, `font-manrope`, `font-switzer`, `font-gilroy`, `font-sfpro`, `font-satoshi`, and exposes each as a raw CSS var (used as `style={{ fontFamily: "var(--font-gilda)" }}` in employee components).

### 2.4 Google fonts loaded via `next/font` (`app/layout.jsx:1–20`)

```js
Bodoni_Moda → --font-bodoni   (subsets: ["latin"])
Jost         → --font-jost     (subsets: ["latin"])
Manrope      → --font-manrope-var (subsets: ["latin"])
```
`<body className={`${bodoni.variable} ${jost.variable} ${manrope.variable} font-sans antialiased text-celestique-dark`}>`

- `--font-bodoni` is only reachable as the **2nd fallback of `font-serif`** — it renders only if Cirka fails.
- `--font-jost` is only the **2nd fallback of `font-sans`** — renders only if Manrope fails.
- `--font-manrope-var` is declared but **never referenced by any token or class** (dead).
- ⚠️ **Manrope is therefore loaded twice**: 7 local TTFs + a Google variable font.

**iOS mapping:** Bodoni Moda and Jost are Google Fonts, not present in `public/fonts/`. They are pure fallbacks — for iOS parity you can safely **omit both**, since Cirka and Manrope are always available in-bundle.

### 2.5 Theme-scoped font remapping (`globals.css` 310–359)

Three `.theme-*` classes override family for whole subtrees.

#### `.theme-retailer` — **entirely Satoshi**
Selector list: `.theme-retailer`, `… button`, `… input`, `… select`, `… textarea`, `… h1`–`h6`, `… [class*="font-cirka"]`, `… .title-font`, `… .cirka-title`
```css
font-family: "Satoshi", var(--font-satoshi), sans-serif !important;
```
Applied at: `app/dashboard/retailer/layout.jsx:28`, `app/onboard-retailer/layout.jsx:10`, `app/onboard-retailer/submitted/page.jsx:62`

#### `.theme-wholesaler` — **Manrope body / Cirka display** ← THE APP BEING PORTED
```css
.theme-wholesaler, … button, input, select, textarea {
  font-family: "Manrope", var(--font-sans), sans-serif;    /* no !important */
}
.theme-wholesaler h1..h6, [class*="font-cirka"], .title-font, .cirka-title {
  font-family: "Cirka", serif !important;                   /* !important */
}
```
Applied at: **`app/dashboard/wholesaler/layout.jsx:10`** and `app/onboard/layout.jsx:6`

> **Critical for the iOS port:** inside the wholesaler dashboard, **every `h1`–`h6` is forcibly Cirka** regardless of what utility class is on it — `!important` beats `font-gilroy`, `font-sfpro`, etc. So `AddProductForm.jsx:323` `<h1 className="… font-cirka">Add new product</h1>` and `UploadHistoryClient.jsx:227` `<h1 … font-cirka>Uploads Today</h1>` are Cirka twice over. Meanwhile `HeroUploadSection.jsx:12` `<h1 … font-sfpro>{displayName}</h1>` renders **Cirka, not SF Pro** — the `!important` wins.
> Body/button/input text is Manrope (non-`!important`), so `font-gilroy` utilities on non-heading elements **do** win → Gilroy is the real form font.

#### `.theme-employee` — **Manrope body / Gilda Display display**
```css
.theme-employee, … button, input, select, textarea { font-family: "Manrope", var(--font-sans), sans-serif; }
.theme-employee h1..h6, [class*="font-gilda"], [class*="font-gilda-display"], .title-font, .gilda-title {
  font-family: "Gilda Display", serif !important;
}
```
Applied at: `app/employee-login/page.jsx:12`, `components/employee/EmployeeLayout.jsx:13`

### 2.6 Where each family is ACTUALLY used

| Family | Reachable via | Real usage sites |
|---|---|---|
| **Manrope** | `font-sans` (49 occ., incl. `<body>` default), `.theme-wholesaler`/`.theme-employee` base, `font-manrope` (2 explicit) | **The default body font of the entire app.** Explicit: `OverviewSection.jsx:65` (Chamak description), `OverviewSection.jsx:70` ("Coming soon" badge). |
| **Cirka** | `font-serif` (75 occ.), `font-cirka` (7 sites), `.theme-wholesaler h1–h6 !important` | `OverviewSection.jsx:20` `"Insights"` @ `text-4xl`; `OverviewSection.jsx:62` `"Chamak"` @ `text-3xl md:text-4xl font-bold leading-none tracking-normal text-white`; `CatalogueSection.jsx:11` `"My Catalogue"` @ `text-4xl md:text-3xl`; `StatCard.jsx:26` the stat **value** @ `text-[48px] font-medium leading-tight text-gray-900`; `UploadHistoryClient.jsx:227` `"Uploads Today"`; `AddProductForm.jsx:323` `"Add new product"`; `EditProductForm.jsx:209` `"Edit product"`. Plus every `font-serif` usage in product/storefront components. |
| **Gilroy** | `font-gilroy` — **64 occurrences across 11 files** | **The wholesaler form/UI-kit font.** Every label, input, placeholder, select option, suffix and error message in `components/ui/*`. `EmployeeLoginForm.jsx:34` sets it inline: `fontFamily: "'Gilroy', 'SF Pro', system-ui, sans-serif"`. Also `CatalogueSection.jsx:14`, `:35`. |
| **Gilda Display** | `font-gilda` / `var(--font-gilda)`, `.theme-employee h1–h6 !important` | Employee area only: `SelectionReviewClient.jsx:368` (`clamp(24px, 4vw, 38px)`), `:529` (`text-[28px]`), `ProductInfoModal.jsx:264` (`clamp(24px, 4vw, 38px)`). |
| **Satoshi** | `.theme-retailer * !important` | Retailer dashboard + retailer onboarding **only**. Zero explicit `font-satoshi` classes. |
| **SF Pro** | `font-sfpro` — 4 sites | `edit-product/[id]/page.jsx:48` (user email @ `text-[13px] text-[#6B7280]`), `HeroUploadSection.jsx:11` ("Welcome" @ `text-xs md:text-sm`), `HeroUploadSection.jsx:12` (⚠️ an `<h1>` → overridden to Cirka), `BackToDashboardButton.jsx:11` (`text-sm text-[#374151]`). |
| **Switzer** | `font-switzer` token exists | **ZERO usages.** `@font-face` + `@theme` token are dead. **Do not port Switzer.** |
| Bodoni Moda | `--font-bodoni` (fallback #2 of `font-serif`) | Never rendered while Cirka loads. |
| Jost | `--font-jost` (fallback #2 of `font-sans`) | Never rendered while Manrope loads. |

### 2.7 ⚠️ Families REFERENCED but NEVER LOADED (silent fallbacks)

These appear in `font-family` declarations but have **no `@font-face` rule and no `next/font` import**. On the web they fall through to a generic; you must decide the iOS equivalent explicitly.

| Declared family | Where | What actually renders |
|---|---|---|
| `'Inter', sans-serif` | `joinLanding.module.css:10`, `addRetailer.module.css:4`, `referralManager.module.css:3`, `Sidebar.jsx:311` + `:324` (logout modal `<h3>` + `<p>`) | Falls back to the browser's generic `sans-serif`. On iOS Safari → **SF Pro**. iOS port: use `Font.system` or Manrope. |
| `'DM Sans', sans-serif` | `orders.module.css:7`, `queries.module.css:7` | Falls back to generic `sans-serif` → SF Pro on iOS. |
| `'Playfair Display', Georgia, serif` | `joinLanding.module.css:62` (`.name`) | Falls back to **Georgia** (present on iOS). |
| `Georgia, serif` | `AuthLayout.jsx:41` (the 44px `<h1>`), `orders.module.css:34` `.title`, `orders.module.css:165` `.productName`, `queries.module.css:12` `.title` | Georgia — available on iOS. |
| `monospace` | `referralManager.module.css:126` `.urlText` | Generic monospace → SF Mono on iOS. |

### 2.8 Font weights present per family

| Family | Weights with a real file |
|---|---|
| Cirka | 300, 400, 700 |
| Gilda Display | 400 |
| Manrope | 200, 300, 400, 500, 600, 700, 800 |
| Switzer | 400 |
| Gilroy | 400, 500, 600, 700 |
| SF Pro | 400 |
| Satoshi | 300, 400, 500, 700, 900 |

**Weight utility frequency across the app:**
`font-bold` (700) ×267 · `font-medium` (500) ×175 · `font-semibold` (600) ×137 · `font-extrabold` (800) ×35 · `font-normal` (400) ×17 · `font-light` (300) ×8

> ⚠️ **Synthetic-bold risk on iOS.** `font-extrabold` (800) is used 35×, but only **Manrope** has an 800 face. Gilroy (max 700), Cirka (max 700), Gilda Display (only 400) and SF Pro (only 400) will be **synthesised** by the browser. Reproduce exactly: on iOS, either clamp to the nearest real weight or apply a synthetic stroke — do not silently use a different real weight.
> Same issue: `font-medium` (500) on Cirka and Gilda Display (no 500 face → synthesised/rounded to 400).

---

## 3. Type scale (measured from real usage)

### 3.1 Arbitrary pixel sizes (`text-[Npx]`) — these dominate
| Size | Count | Typical role |
|---|---|---|
| `14px` | 153 | Body / button label / table cell |
| `13px` | 148 | Secondary body / meta |
| `12px` | 121 | Caption / badge / helper |
| `10px` | 66 | Micro-label (uppercase tracked) |
| `15px` | 64 | Emphasised body |
| `11px` | 42 | Micro caption / Button component label |
| `9px` | 41 | Micro-badge (ProductCard stock, "View Details") |
| `16px` | 22 | Large body |
| `8px` | 20 | Ultra-micro |
| `20px` | 14 | Sub-heading |
| `22px` | 12 | Sub-heading |
| `18px` | 11 | Sub-heading |
| `13.5px` | 11 | — |
| `28px` | 10 | Page heading (mobile) |
| `24px` | 9 | Section heading |
| `32px` | 8 | Page heading |
| `48px` | 4 | **StatCard value** |
| `54px` | 4 | Display |
| `44px` / `42px` / `40px` / `38px` / `36px` / `30px` / `26px` / `17px` / `14.5px` / `11.5px` / `8.5px` / `7px` | 2–4 each | — |

### 3.2 Named Tailwind sizes (v4 defaults)
| Class | Count | rem / px | line-height |
|---|---|---|---|
| `text-sm` | 67 | 0.875rem / **14px** | 1.25rem (20px) |
| `text-xs` | 24 | 0.75rem / **12px** | 1rem (16px) |
| `text-lg` | 16 | 1.125rem / **18px** | 1.75rem (28px) |
| `text-3xl` | 13 | 1.875rem / **30px** | 2.25rem (36px) |
| `text-4xl` | 11 | 2.25rem / **36px** | 2.5rem (40px) |
| `text-xl` | 10 | 1.25rem / **20px** | 1.75rem (28px) |
| `text-base` | 6 | 1rem / **16px** | 1.5rem (24px) |
| `text-2xl` | 3 | 1.5rem / **24px** | 2rem (32px) |
| `text-7xl` | 2 | 4.5rem / **72px** | 1 |
| `text-5xl` | 2 | 3rem / **48px** | 1 |
| `text-6xl` | 1 | 3.75rem / **60px** | 1 |

### 3.3 🐞 Invalid class `text-s` (renders as **inherited size**, i.e. 16px)
Not a Tailwind class. Two live sites — reproduce as **16px**, not 14px:
- `components/wholesaler/StatCard.jsx:40` → `<span className="text-s font-medium text-gray-700">{title}</span>` (the "Live Products" / "New Orders" / "New Chat" / "Uploads Today" labels)
- `components/wholesaler/CatalogueSection.jsx:14` → `<p className="mt-2 text-s text-celestique-muted font-gilroy font-medium">See and manage all your catalogue categories from one place.</p>`

### 3.4 Letter-spacing (tracking)
| Class | Value | Count |
|---|---|---|
| `tracking-wide` | `0.025em` | 55 |
| `tracking-[0.2em]` | `0.2em` | 43 |
| `tracking-widest` | `0.1em` | 41 |
| `tracking-tight` | `-0.025em` | 25 |
| `tracking-wider` | `0.05em` | 19 |
| `tracking-[0.15em]` | `0.15em` | 15 |
| `tracking-[0.1em]` | `0.1em` | 11 |
| `tracking-[0.3em]` | `0.3em` | 10 |
| `tracking-[0.25em]` | `0.25em` | 6 |
| `tracking-tighter` | `-0.05em` | 4 |
| `tracking-[0.02em]` | `0.02em` | 3 |
| `tracking-normal` | `0em` | 2 |
| `tracking-[0.12em]` | `0.12em` | 2 |
| `tracking-[0.18em]` | `0.18em` | 1 |

> The **uppercase + wide-tracking micro-label** is the signature of the celestique language: `text-[9px]`/`text-[10px]`/`text-[11px]` + `uppercase` + `tracking-widest`(0.1em) or `tracking-[0.2em]`/`[0.3em]` + `font-bold`. In SwiftUI: `.kerning()` (absolute pt) — at 10px, `0.2em` = **2.0 pt kerning**; at 9px, `0.3em` = **2.7 pt**; at 11px, `0.1em` = **1.1 pt**.

### 3.5 Line-height
| Class | Value | Count |
|---|---|---|
| `leading-relaxed` | 1.625 | 62 |
| `leading-tight` | 1.25 | 30 |
| `leading-none` | 1 | 14 |
| `leading-snug` | 1.375 | 8 |
| `leading-[1.2]` | 1.2 | 8 |
| `leading-[1.1]` | 1.1 | 3 |
| `leading-[1.6]` | 1.6 | 2 |
| `leading-[1.5]` | 1.5 | 2 |
| `leading-loose` | 2 | 1 |

---

## 4. Spacing scale

Tailwind v4 `--spacing: 0.25rem` → `N` = `N × 4px`.

### 4.1 `gap-*`
| Class | px | Count |
|---|---|---|
| `gap-2` | 8 | 100 |
| `gap-3` | 12 | 96 |
| `gap-4` | 16 | 83 |
| `gap-1.5` | 6 | 58 |
| `gap-6` | 24 | 55 |
| `gap-1` | 4 | 31 |
| `gap-5` | 20 | 28 |
| `gap-8` | 32 | 24 |
| `gap-2.5` | 10 | 14 |
| `gap-10` | 40 | 12 |
| `gap-0` | 0 | 8 |
| `gap-16` | 64 | 3 |
| `gap-12` | 48 | 3 |
| `gap-[8px]` / `gap-[16px]` / `gap-[6px]` / `gap-[4px]` | literal | 4/2/2/1 |
| `gap-[clamp(…)]` | responsive | 17 |

### 4.2 `px-*`
`px-4` (16px) ×86 · `px-6` (24px) ×69 · `px-8` (32px) ×45 · `px-3` (12px) ×35 · `px-10` (40px) ×22 · `px-5` (20px) ×21 · `px-2` (8px) ×16 · `px-[clamp(…)]` ×16 · `px-1` (4px) ×15 · `px-12` (48px) ×11 · `px-2.5` (10px) ×9 · `px-1.5` (6px) ×7 · `px-7` (28px) ×6 · `px-3.5` (14px) ×6 · `px-[20px]` ×5

### 4.3 `py-*`
`py-4` (16px) ×35 · `py-3` (12px) ×30 · `py-2.5` (10px) ×29 · `py-1.5` (6px) ×29 · `py-2` (8px) ×27 · `py-6` (24px) ×20 · `py-[clamp(…)]` ×20 · `py-8` (32px) ×19 · `py-1` (4px) ×18 · `py-0.5` (2px) ×15 · `py-10` (40px) ×11 · `py-3.5` (14px) ×10 · `py-5` (20px) ×8 · `py-16` (64px) ×6 · `py-32` (128px) ×5

**De-facto spacing ladder for the port: 2 · 4 · 6 · 8 · 10 · 12 · 14 · 16 · 20 · 24 · 28 · 32 · 40 · 48 · 64 pt.**

### 4.4 Fixed control heights
| Class | px | Count | Used by |
|---|---|---|---|
| `h-10` | 40 | 27 | small buttons |
| `h-12` | 48 | 16 | medium buttons |
| `h-11` | 44 | 14 | **UI-kit Input / Select / InputWithSuffix — the canonical field height** |
| `h-9` | 36 | 9 | compact controls |
| `h-14` | 56 | 7 | **`Button` component** |
| `52px` (inline) | 52 | — | Auth text field + Google button (`EntryForm`), `joinLanding .ctaButton` |
| `56px` (inline) | 56 | — | Auth primary CTA, `referralManager .input` / `.generateButton` |
| `44px` (inline) | 44 | — | Sidebar nav item, bottom-nav item, `queries .replyInput` |
| `64px` (module) | 64 | — | `employeeTopNav .navbar` |
| `60px` (inline) | 60 | — | Mobile floating bottom nav |
| `70px` (inline) | 70 | — | **Desktop sidebar width** |
| `72px` | 72 | — | `.wholesaler-main-content` `padding-bottom` (bottom-nav offset) |

---

## 5. Corner radii

### 5.1 Frequency
| Class | Resolved | Count |
|---|---|---|
| `rounded-full` | 9999px | **200** |
| `rounded-[10px]` | 10px | 45 |
| `rounded-[8px]` | 8px | 43 |
| `rounded-[12px]` | 12px | 36 |
| `rounded-[16px]` | 16px | 29 |
| `rounded-xl` | 0.75rem = **12px** | 28 |
| `rounded-lg` | 0.5rem = **8px** | 24 |
| `rounded-[6px]` | 6px | 21 |
| `rounded-2xl` | 1rem = **16px** | 20 |
| `rounded-[24px]` | 24px | 13 |
| `rounded-sm` | 0.25rem = **4px** | 11 |
| `rounded-md` | 0.375rem = **6px** | 10 |
| `rounded-[20px]` | 20px | 10 |
| `rounded-[14px]` | 14px | 9 |
| `rounded-[4px]` | 4px | 8 |
| `rounded-r-[16px]` | 16px right | 2 |
| `rounded-l-xl` | 12px left | 2 |
| `rounded-[2px]` | 2px | 2 |
| `rounded-t-xl` / `rounded-t-[20px]` / `rounded-none` / `rounded-br-[4px]` / `rounded-bl-[4px]` / `rounded-[3px]` / `rounded-[32px]` | — | 1 each |

**Effective radius ladder: 0 · 2 · 4 · 6 · 8 · 10 · 12 · 14 · 16 · 20 · 24 · 32 · full.**
8, 10 and 12 are the workhorses. `rounded-full` at 200 uses is mostly pills, avatars and dots.

> ⚠️ Tailwind v4 renamed the radius scale. `rounded-sm` here = **4px** (v3's `rounded`), not v3's 2px. `rounded` bare no longer exists.

### 5.2 Radii declared in CSS modules
`joinLanding .card` 16px · `.badge` 20px · `.ctaButton` 10px
`orders .productImage` 8px · `.tabsContainer`/`.tabBtn`/`.tabBadge`/`.filterBtn`/`.btnCloseModal` 999px · `.btn` 8px · `.modalContent` 16px (mobile: `20px 20px 0 0`) · `.avatar` 50%
`queries .leftPanel` `14px 0 0 14px` · `.rightPanel` `0 14px 14px 0` · `.cardSelected` 10px · `.cardBadge` 6px · `.filterTab` 999px · `.replyInput`/`.sendBtn` 10px · **`.bubbleRetailer` `4px 16px 16px 16px`** · **`.bubbleWholesaler` `16px 4px 16px 16px`** · `.navLinkActive::after` `2px 2px 0 0`
`referralManager .input`/`.generateButton` 8px
`employeeTopNav .avatar`/`.logoutBtn` 50%

---

## 6. Shadows

### 6.1 Named Tailwind shadows (v4 defaults) — resolved values
| Class | Count | Exact CSS |
|---|---|---|
| `shadow-sm` | 55 | `0 1px 3px 0 rgb(0 0 0 / 0.1), 0 1px 2px -1px rgb(0 0 0 / 0.1)` |
| `shadow-md` | 25 | `0 4px 6px -1px rgb(0 0 0 / 0.1), 0 2px 4px -2px rgb(0 0 0 / 0.1)` |
| `shadow-lg` | 21 | `0 10px 15px -3px rgb(0 0 0 / 0.1), 0 4px 6px -4px rgb(0 0 0 / 0.1)` |
| `shadow-2xl` | 17 | `0 25px 50px -12px rgb(0 0 0 / 0.25)` |
| `shadow-xl` | 5 | `0 20px 25px -5px rgb(0 0 0 / 0.1), 0 8px 10px -6px rgb(0 0 0 / 0.1)` |
| `shadow-none` | 2 | `0 0 #0000` |
| `shadow-inner` | 4 | ⚠️ **VERIFY** — Tailwind v4 replaced `shadow-inner` with the `inset-shadow-*` scale. These 4 uses may be emitting nothing. Confirm against the built CSS before porting. |
| `shadow-black/20` ×2, `shadow-red-200`, `shadow-gray-200`, `shadow-emerald-500/10`, `shadow-emerald-200`, `shadow-amber-950/40`, `shadow-amber-500/20` | 1–2 | colored `shadow-sm` variants |

> ⚠️ Tailwind v4 shifted the shadow scale by one step. `shadow-sm` here = what v3 called `shadow`; v3's old `shadow-sm` is now `shadow-xs`.

### 6.2 Arbitrary shadows (exact strings, most-used first)
| Value | Count |
|---|---|
| `0 2px 12px rgba(0,0,0,0.05)` | 5 |
| `0px 2.182px 3.382px 0px rgba(0,0,0,0.25), inset -1.091px -1.091px 2.291px 0px rgba(0,0,0,0.25), inset 2.182px 2.182px 4.691px 0px rgba(255,255,255,0.25)` | 4 |
| `0 4px 20px rgba(0,0,0,0.04)` | 4 |
| `0 4px 14px rgba(0,0,0,0.15)` | 4 |
| `0 10px 40px rgba(0,0,0,0.1)` | 4 |
| `0 2px 10px rgba(0,0,0,0.03)` | 3 |
| `0px 2px 4px rgba(0,0,0,0.25)` | 2 |
| `0 8px 32px rgba(0,0,0,0.08)` | 2 |
| `0 8px 30px rgba(0,0,0,0.08)` | 2 |
| `0 4px 20px rgba(0,0,0,0.08)` | 2 |
| `0 30px 60px rgba(0,0,0,0.12)` | 2 |
| `0 2px 4px rgba(0,0,0,0.2)` | 2 |
| `0 16px 40px rgba(0,0,0,0.12)` | 2 |
| `inset 2px 2px 4px rgba(228,204,143,0.3)` | 1 (Chamak badge inner glow) |
| `0px 6px 16px rgba(0,0,0,0.25)` · `0px 4px 4px rgba(0,0,0,0.25)` · `0 8px 30px rgba(0,0,0,0.06)` · `0 8px 24px rgba(0,0,0,0.12)` · `0 4px 20px rgba(0,0,0,0.1)` · `0 4px 20px rgba(0,0,0,0.03)` · `0 4px 14px rgba(0,0,0,0.3)` · `0 2px 12px rgba(0,0,0,0.07)` · `0 20px 60px -15px rgba(0,0,0,0.1)` · `0 20px 50px rgba(0,0,0,0.3)` · `0 1px 3px rgba(0,0,0,0.1)` · `0 10px 30px rgba(255,255,255,0.05)` · `0 0 8px rgba(17,24,39,0.25)` · `0 -4px 20px rgba(0,0,0,0.15)` | 1 each |

### 6.3 Shadows declared inline / in modules
| Shadow | Where |
|---|---|
| `0 12px 40px rgba(0,0,0,0.15)` | `joinLanding .card` |
| `0 1px 2px 0 rgba(0,0,0,0.05)` | `employeeTopNav .navbar` |
| `0 1px 3px rgba(0,0,0,0.08)` | `orders .tabBtnActive` |
| `0 10px 25px rgba(0,0,0,0.1)` | `orders .modalContent` |
| `0 2px 8px rgba(0,0,0,.06)` | `queries .cardSelected` |
| `0 20px 25px -5px rgba(0,0,0,0.1), 0 10px 10px -5px rgba(0,0,0,0.04)` | `Sidebar.jsx:266` logout modal |
| `0 8px 32px rgba(0,0,0,0.1), 0 1.5px 4px rgba(0,0,0,0.06)` | **Mobile floating bottom nav** (both Sidebar + RetailerSidebar) |
| `0 12px 30px rgba(0,0,0,0.15)` | `.bottom-nav-popover-content` |
| `0 10px 15px -3px rgba(245,158,11,0.1), 0 4px 6px -4px rgba(245,158,11,0.1)` | `EmployeeLayout.jsx:42` "Employee View Active" chip |

---

## 7. Borders

| Class | Width | Count |
|---|---|---|
| `border` | 1px | **905** |
| `border-2` | 2px | 33 |
| `border-4` | 4px | 2 |
| `border-b-0` | 0 | 2 |
| `border-b-2` | 2px | 1 |

Non-integer widths appear only in CSS modules: **`1.5px`** — `orders .card` bottom border, `queries .filterTab` / `.leftPanel` / `.rightPanel` / `.cardSelected` / `.replyInput`, and the auth text field (`EntryForm.jsx:149`, `1.5px solid #D9D0C5`).

**Default border colors (by frequency):** `#E5E7EB` (21× as `border-[#E5E7EB]`, 43× overall), `#E5E5E5` (17×, the UI-kit field border), `border-celestique-dark/10` (16×), `border-celestique-taupe` (16×), `#EEE` (11×), `#111` (10×), `#A8A8A8` (8×), `#3B82F6` (7×, focus).

**Dashed border:** `border-2 border-dashed border-celestique-border` — the "View All" catalogue card (`CatalogueSection.jsx:29`), hover → `border-celestique-dark` + `bg-celestique-cream`. Also `2px dashed #D1D5DB` for `addRetailer .verticalArrow`.

---

## 8. Animation & motion

### 8.1 All `@keyframes` in `app/globals.css` — with the exact utility that drives them

| # | Keyframe | Definition | Driving class | **Duration** | **Timing function** | Fill / iteration |
|---|---|---|---|---|---|---|
| 1 | `fadeInUp` | `from {opacity:0; transform:translateY(10px)} to {opacity:1; transform:translateY(0)}` | `.animate-fade-in-up` | **0.5s** | **`cubic-bezier(0.16, 1, 0.3, 1)`** | `forwards` |
| 2 | `fadeIn` | `from {opacity:0} to {opacity:1}` | `.animate-fade-in` | **0.4s** | `ease-out` | `forwards` |
| 3 | `scaleIn` | `from {transform:scale(0.98); opacity:0} to {transform:scale(1); opacity:1}` | `.animate-scale-in` | **0.4s** | **`cubic-bezier(0.16, 1, 0.3, 1)`** | `forwards` |
| 4 | `shimmer` | `0% {transform:translateX(-100%)} 100% {transform:translateX(100%)}` | `.skeleton-shimmer::after` | **1.6s** | `ease-in-out` | `infinite` |
| 5 | `catalogue-shimmer` | `0% {background-position:200% 0} 100% {background-position:-200% 0}` | `.catalogue-skeleton-bg` | **1.5s** | *(none specified → `ease`)* | `infinite` |
| 6 | `cardEnter` | `from {opacity:0; transform:translateY(28px)} to {opacity:1; transform:translateY(0)}` | `.card-enter.is-visible` | **0.55s** | **`cubic-bezier(0.16, 1, 0.3, 1)`** | `forwards` |
| 7 | `onboardFadeIn` | `from {opacity:0; transform:translateY(8px)} to {opacity:1; transform:translateY(0)}` | `.onboard-page-transition` | **350ms** | **`cubic-bezier(0.16, 1, 0.3, 1)`** | `forwards` |
| 8 | `checkDraw` | `from {stroke-dashoffset:24} to {stroke-dashoffset:0}` | `.animate-check-draw` (also sets `stroke-dasharray:24; stroke-dashoffset:24`) | **350ms** | **`cubic-bezier(0.4, 0, 0.2, 1)`** | `forwards` |
| 9 | `rippleGreen` | `0% {scale(0.9); box-shadow:0 0 0 0 rgba(34,197,94,0.4)}` → `50% {scale(1.06); box-shadow:0 0 0 6px rgba(34,197,94,0.15)}` → `100% {scale(1); box-shadow:0 0 0 10px rgba(34,197,94,0)}` | `.animate-ripple-green` | **600ms** | **`cubic-bezier(0.16, 1, 0.3, 1)`** | `forwards` |
| 10 | `pulseAmber` | `0%,100% {opacity:0.7; scale(1)}` → `50% {opacity:1; scale(1.05)}` | `.animate-pulse-amber` | **2s** | `ease-in-out` | `infinite` |
| 11 | `spinClockHand` | `from {rotate(0deg)} to {rotate(360deg)}` | `.animate-spin-slow` (+ `transform-origin: center`) | **8s** | `linear` | `infinite` |
| 12 | `softShake` | `0%,100% {translateX(0) scale(1)}` → `20%,60% {translateX(-1.5px) scale(1.03)}` → `40%,80% {translateX(1.5px) scale(1.03)}` | `.animate-shake-red` | **500ms** | **`cubic-bezier(0.36, 0.07, 0.19, 0.97)`** | `both` |
| 13 | `stepFadeIn` | `from {opacity:0; transform:translateY(6px)} to {opacity:1; transform:translateY(0)}` | `.animate-step-fade` | **400ms** | **`cubic-bezier(0.16, 1, 0.3, 1)`** | `forwards` |

**Signature easing curve: `cubic-bezier(0.16, 1, 0.3, 1)`** — used by 6 of 13 keyframes plus the popover. This is the "ease-out-expo"-like curve. SwiftUI equivalent: a custom `Animation.timingCurve(0.16, 1, 0.3, 1, duration:)`.

### 8.2 Animation delay utilities (`globals.css:244–246`)
```css
.delay-100 { animation-delay: 100ms; }
.delay-200 { animation-delay: 200ms; }
.delay-300 { animation-delay: 300ms; }
```

### 8.3 Keyframes defined inline in components (NOT global)

| Keyframe | File | Definition | Applied as |
|---|---|---|---|
| `fadeIn` | `Sidebar.jsx:403` | `from{opacity:0} to{opacity:1}` | logout-modal overlay, `animation: "fadeIn 0.2s ease-out"` |
| `scaleUp` | `Sidebar.jsx:407` | `from{scale(0.95); opacity:0} to{scale(1); opacity:1}` | logout-modal card, `animation: "scaleUp 0.2s cubic-bezier(0.34, 1.56, 0.64, 1)"` ← **overshoot/spring curve** |
| `popoverFadeIn` | `Sidebar.jsx:505` & `RetailerSidebar.jsx:392` | `from{opacity:0; transform:translate(-50%,10px)} to{opacity:1; transform:translate(-50%,0)}` | `.bottom-nav-popover-content`, **`0.25s cubic-bezier(0.16, 1, 0.3, 1) forwards`** |
| `pulse` | `EmployeeLayout.jsx:17` | `0%{scale(0.95); opacity:0.5} 50%{scale(1.1); opacity:1} 100%{scale(0.95); opacity:0.5}` | 6×6px dot, `pulse 1.5s infinite` |
| `fadeIn` | `EmployeeLayout.jsx:22` | `from{opacity:0; translateY(-8px)} to{opacity:1; translateY(0)}` | "Employee View Active" chip, `fadeIn 0.3s ease-out` |

### 8.4 Animation utilities in use
| Class | Count | Source |
|---|---|---|
| `animate-fade-in` | 40 | globals.css (0.4s ease-out) |
| `animate-spin` | 16 | Tailwind built-in (`1s linear infinite`, 360°) |
| `animate-pulse` | 12 | Tailwind built-in (`2s cubic-bezier(0.4,0,0.6,1) infinite`, opacity 1↔0.5) |
| `animate-fade-in-up` | 7 | globals.css (0.5s) |
| `animate-ping` | 2 | Tailwind built-in (`1s cubic-bezier(0,0,0.2,1) infinite`, scale 1→2 + opacity 1→0) — StatCard "new" badge |
| `animate-step-fade` | 2 | globals.css |
| `animate-shake-red` | 2 | globals.css |
| `animate-spin-slow` / `animate-ripple-green` / `animate-pulse-amber` / `animate-check-draw` | 1 each | globals.css |
| 🐞 `animate-slide-in-right` | **3** | **NO DEFINITION ANYWHERE.** Dead class → those panels appear instantly with no animation. Sites: `SelectionReviewClient.jsx:566`, `ProductInfoModal.jsx:431`, `ProductInfoModal.jsx:710`. |
| 🐞 `animate-in fade-in zoom-in duration-200` | 1 | `tailwindcss-animate` syntax; that plugin is **not installed**. `ConfirmationModal.jsx:51` → **no animation**. |

> For iOS parity you must decide: reproduce the *current broken behaviour* (no animation) or the *intended* one. Recommend reproducing current behaviour and flagging to the user.

### 8.5 Transition utilities
| Class | Count |
|---|---|
| `transition-colors` | 174 |
| `transition-all` | 140 |
| `transition-opacity` | 30 |
| `transition-transform` | 28 |
| `transition` (all) | 24 |
| `transition-shadow` | 17 |

**Durations:** `duration-300` ×50 · `duration-200` ×22 · `duration-700` ×21 · `duration-500` ×11 · `duration-1000` ×2. Tailwind default (no `duration-*`) = **150ms**, default easing = `cubic-bezier(0.4, 0, 0.2, 1)`.
**Easing overrides:** `ease-in-out` ×19 · `ease-out` ×9.

### 8.6 Interaction transforms
| Class | Count | Meaning |
|---|---|---|
| `hover:scale-105` | 11 | 1.05× |
| `active:scale-[0.98]` | 7 | 0.98× press |
| `active:scale-95` | 6 | 0.95× press |
| `active:scale-90` | 5 | 0.90× press |
| `hover:scale-[1.02]` | 4 | StatCard hover |
| `hover:scale-[1.01]` | 4 | Chamak card hover |
| `hover:scale-[1.03]` | 2 | |
| `active:scale-[0.99]` | 2 | |
| `active:scale-[0.97]` | 1 | UploadButton |
| `hover:translate-x-2` / `hover:translate-x-1` | 1 each | arrow nudge |
| `hover:scale-110` | 1 | |
| `active:translate-y-0.5` | 1 | **`Button` component press (2px down)** |

### 8.7 Reduced motion (`globals.css` 377–386 and 484–495)
Two separate `@media (prefers-reduced-motion: reduce)` blocks:
```css
/* block 1 */
.onboard-page-transition { animation: none !important; opacity: 1 !important; transform: none !important; }
.progress-bar-transition { transition: none !important; }

/* block 2 */
.animate-check-draw, .animate-ripple-green, .animate-pulse-amber,
.animate-spin-slow, .animate-shake-red, .animate-step-fade {
  animation: none !important; transform: none !important; stroke-dashoffset: 0 !important;
}
```
> ⚠️ `.animate-fade-in`, `.animate-fade-in-up`, `.animate-scale-in`, `.skeleton-shimmer`, `.card-enter`, `.catalogue-skeleton-bg` are **NOT** covered by reduced-motion. The iOS port should respect `UIAccessibility.isReduceMotionEnabled` more thoroughly than the web does.

---

## 9. Global utility classes defined in `globals.css`

### 9.1 `.skeleton-shimmer` (lines 253–269) — the primary loading state
```css
.skeleton-shimmer {
  position: relative;
  overflow: hidden;
  background: #E6DFD3;                 /* celestique-taupe */
}
.skeleton-shimmer::after {
  content: '';
  position: absolute;
  inset: 0;
  background: linear-gradient(105deg, transparent 40%, rgba(245,242,235,0.7) 50%, transparent 60%);
  animation: shimmer 1.6s ease-in-out infinite;
}
```
Sweep is a **105° diagonal** band from 40%→60%, peaking at 50% with `#F5F2EB` @ 70% alpha, translating `-100%` → `+100%` over 1.6s.

### 9.2 `.catalogue-skeleton-bg` (lines 276–280) — grey-scale variant
```css
background: linear-gradient(90deg, #f0f0f0 25%, #e0e0e0 50%, #f0f0f0 75%);
background-size: 200% 100%;
animation: catalogue-shimmer 1.5s infinite;
```

### 9.3 `.custom-scrollbar` / `.scrollbar-hide` (lines 283–291)
```css
.custom-scrollbar, .scrollbar-hide { -ms-overflow-style: none; scrollbar-width: none; }
.custom-scrollbar::-webkit-scrollbar, .scrollbar-hide::-webkit-scrollbar { display: none; }
```
Both names hide the scrollbar entirely — `.custom-scrollbar` does NOT style one. iOS: `.scrollIndicators(.hidden)`.
`AuthLayout.jsx:18` reimplements the same thing with arbitrary variants: `[&::-webkit-scrollbar]:hidden [-ms-overflow-style:none] [scrollbar-width:none]`.
`orders.module.css:484` does it again for `.tabsLeft`.

### 9.4 `.card-enter` / `.is-visible` (lines 298–303) — scroll-reveal
```css
.card-enter { opacity: 0; }
.card-enter.is-visible { animation: cardEnter 0.55s cubic-bezier(0.16, 1, 0.3, 1) forwards; }
```
Driven by an `IntersectionObserver` in `ProductCard.jsx:55–70`:
- `threshold: 0.1`, `rootMargin: "0px 0px -40px 0px"`
- stagger delay = `(index % 3) * 100` ms → **0 / 100 / 200 ms per grid column**
- observer disconnects after first intersection (one-shot)

### 9.5 `.bg-grain` (lines 306–308)
Inline SVG data-URI noise:
```
<svg viewBox='0 0 200 200'><filter id='noiseFilter'>
  <feTurbulence type='fractalNoise' baseFrequency='0.65' numOctaves='3' stitchTiles='stitch'/>
</filter><rect width='100%' height='100%' filter='url(#noiseFilter)' opacity='0.05'/></svg>
```
→ fractal noise, `baseFrequency 0.65`, `numOctaves 3`, **`opacity 0.05`**, tiled.

### 9.6 `canvas.protected-image` (lines 498–502)
```css
user-select: none; -webkit-user-drag: none; -webkit-touch-callout: none;
```
Product images are rendered to a `<canvas>` (`components/shared/ProtectedImage`) to block save/drag. iOS: disable long-press context menu on product images.

### 9.7 Global overflow guard (lines 505–508)
```css
html, body { max-width: 100vw; overflow-x: hidden; }
```

### 9.8 `.wholesaler-main-content` (lines 511–523) — **the dashboard shell metric**
```css
.wholesaler-main-content {
  flex: 1;
  min-height: 100vh;
  min-width: 0;
  margin-left: 0;
  padding-bottom: 72px;      /* clearance for the floating bottom nav */
}
@media (min-width: 768px) {
  .wholesaler-main-content { margin-left: 70px; padding-bottom: 0; }
}
```
**iOS: content inset 72pt bottom on compact width; 70pt leading rail on regular width.**

---

## 10. Component design specs

### 10.1 `components/ui/Button.jsx`

**Base (all variants):**
```
group relative inline-flex items-center justify-center
text-[11px] uppercase tracking-widest font-bold
transition-all focus-visible:outline-none
disabled:pointer-events-none disabled:opacity-50
h-14 px-10 w-full shadow-sm active:translate-y-0.5
```
→ **height 56px, horizontal padding 40px, full width, 11px uppercase, letter-spacing 0.1em, weight 700, `shadow-sm`, press = translateY(+2px), radius = 0 (square corners — no `rounded-*`).**

| Variant | Idle | Hover |
|---|---|---|
| `primary` (default) | `bg-celestique-dark` `#111111` + `text-celestique-cream` `#F5F2EB` | `bg-celestique-dark/90` (`#111111` @ 90%) + `shadow-md` |
| `outline` | `border-2 border-celestique-dark` (2px `#111111`), transparent bg, `text-celestique-dark` | fill `#111111`, text `#F5F2EB`, `shadow-md` |
| `ghost` | transparent, `text-celestique-dark` | `bg-celestique-taupe/20` (`#E6DFD3` @ 20%) |

**States:**
- **Disabled** (`disabled` prop OR `loading`): `pointer-events: none`, **opacity 0.5**.
- **Loading:** children wrapper gets `opacity-0 invisible` with `transition-all duration-300`; an absolutely-positioned, inset-0, centered spinner appears — `w-5 h-5` (**20×20px**), `border-2` (2px), `border-celestique-taupe` (`#E6DFD3`) with `border-t-celestique-cream` (`#F5F2EB` top), `rounded-full`, `animate-spin` (1s linear infinite).
- **Submit affordance:** when `type === "submit"`, a `&rarr;` (→ U+2192) glyph is appended inside the flex row (`gap-3` = 12px) with `transition-transform group-hover:translate-x-1` (**4px nudge on hover**).
- Children row: `flex items-center justify-center gap-3` (12px).

### 10.2 `components/ui/GoogleButton.jsx`
Wraps `Button variant="outline" className="relative"`. Default label text: **`"Continue with Google"`**. Content = `<span className="flex items-center gap-3 text-current">` + label + a 16×16 Google "G" path drawn in `currentColor` (single-color, inherits the outline variant's text color, so it flips to cream on hover).

### 10.3 `components/ui/Input.jsx`
```
wrapper: flex flex-col gap-1 w-full            /* 4px label→field gap */
label:   text-sm font-semibold text-[#374151] font-gilroy
input:   h-11 w-full border rounded-lg px-3 text-sm text-[#111827]
         placeholder:text-[#9CA3AF] placeholder:font-gilroy placeholder:font-semibold
         focus:outline-none transition-colors font-gilroy font-semibold
```
- **Field: 44px tall, 8px radius, 12px horizontal padding, 14px Gilroy SemiBold (600), text `#111827`.**
- **Placeholder: `#9CA3AF`, Gilroy SemiBold 600** (same weight as the value — unusual, reproduce exactly).
- **Idle border:** `border-[#e5e5e5]` (1px `#E5E5E5`).
- **Focus (no error):** `focus:border-[#3B82F6]` + `focus:ring-1 focus:ring-[#3B82F6]` → **1px border + 1px outer ring, both `#3B82F6`**.
- **Error:** `border-red-500` + `focus:border-red-500` + `focus:ring-1 focus:ring-red-500` (Tailwind `red-500` = `#EF4444` in v4's oklch palette; the codebase's literal equivalent is `#EF4444`).
- **Error message:** `<p className="text-xs font-semibold text-red-500 font-gilroy mt-0.5 animate-fade-in">` → **12px, weight 600, `#EF4444`, 2px top margin, fades in over 0.4s ease-out**.

### 10.4 `components/ui/InputWithSuffix.jsx`
Same label + wrapper as Input. Field is a **flex row inside a single bordered, `overflow-hidden`, `rounded-lg` (8px) container**:
- input: `h-11 flex-1 px-3 text-sm text-[#111827]` + `bg-transparent font-gilroy font-semibold`, placeholder `#9CA3AF` Gilroy 600.
- suffix: `h-11 flex items-center px-3 bg-[#F9FAFB] text-sm text-[#6B7280] border-l border-[#e5e5e5] font-gilroy font-semibold` → **44px tall, 12px padding, fill `#F9FAFB`, text `#6B7280`, 1px left divider `#E5E5E5`**.
- Focus is `focus-within:` on the container: `border-[#3B82F6]` + `ring-1 ring-[#3B82F6]`; error → red-500 equivalents.
- **Helper text** (only when no error): `<p className="text-xs text-[#9CA3AF] mt-0.5 font-gilroy">` → 12px, `#9CA3AF`, Gilroy regular (no weight class → 400).
- Error text identical to Input's.

### 10.5 `components/ui/Select.jsx` (custom dropdown, not a native `<select>`)
A visually hidden native `<select className="hidden">` is kept for form semantics; the visible control is a `<button>`.

- **Trigger:** `w-full h-11 border rounded-lg px-3 flex items-center justify-between text-sm transition-colors font-gilroy font-semibold` → 44px, 8px radius, 12px padding.
- **Trigger states:**
  - idle: `border-[#e5e5e5]`, hover `hover:border-[#d1d5db]`
  - open: `border-[#3B82F6] ring-1 ring-[#3B82F6]`
  - error: `border-red-500 focus:border-red-500 focus:ring-1 focus:ring-red-500`
- **Value text:** selected → `text-[#111827]`; unselected → `placeholderClassName`, **default `"text-[#9CA3AF]"`**.
- **Default placeholder string: `"select"`** (lowercase — verbatim).
- **Chevron:** `h-4 w-4` (16×16) `text-[#6B7280]`, `transition-transform duration-200`, **`rotate-180` when open**. Path `d="M5.23 7.21a.75.75 0 011.06.02L10 11.168l3.71-3.938a.75.75 0 111.08 1.04l-4.25 4.5a.75.75 0 01-1.08 0l-4.25-4.5a.75.75 0 01.02-1.06z"` on a 20×20 viewBox.
- **Menu:** `absolute z-50 top-full left-0 w-full mt-1 bg-white border border-[#e5e5e5] rounded-lg shadow-lg overflow-hidden` → 4px below trigger, full width, 8px radius, 1px `#E5E5E5`, `shadow-lg`. Inner scroller `max-h-60 overflow-y-auto py-1` → **max height 240px, 4px vertical padding**.
- **Option row:** `w-full text-left px-3 py-2.5 text-sm transition-colors font-gilroy` → 12px × 10px padding, 14px.
  - selected: `bg-[#F3F4F6] text-[#111827] font-semibold`
  - unselected: `text-[#374151] hover:bg-[#F9FAFB] font-medium`
- **Dismiss:** `mousedown` listener on `document` closes on outside click.
- `onChange` is synthesised as `{ target: { id, name: id, value } }`.

### 10.6 `components/ui/Toggle.jsx`
```
row:   flex items-center gap-3                                  /* 12px, label BEFORE switch */
label: text-sm text-[#374151] cursor-pointer                    /* also toggles on click */
track: relative inline-flex h-6 w-11 shrink-0 rounded-full
       transition-colors duration-200 ease-in-out
       focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-[#22C55E]
knob:  h-5 w-5 rounded-full bg-white shadow-sm ring-0 mt-0.5
       transition duration-200 ease-in-out
```
- **Track 44×24px, pill.** ON `bg-[#22C55E]`; OFF `bg-[#E5E7EB]`.
- **Knob 20×20px white, `shadow-sm`, `mt-0.5` (2px top offset).** ON → `translate-x-5` (**20px**); OFF → `translate-x-0.5` (**2px**).
- Focus: 2px ring `#22C55E` with 2px offset.
- `role="switch"` + `aria-checked`.

### 10.7 `components/auth/AuthLayout.jsx`
Full-viewport 2-pane split, inline styles (not Tailwind for the geometry).
```
outer: display:flex; height:100vh; width:100%; overflow:hidden
left:  position:relative; width:62%; height:100%; flexShrink:0
       className="hidden md:block"   → hidden below 768px
       <Image fill style={{objectFit:"cover"}} priority>
       default src: https://res.cloudinary.com/dcs0vuzwg/image/upload/v1774883373/authImg_ivftu7.png
right: flex-1 w-full max-w-[520px] bg-white h-screen overflow-y-auto flex flex-col
       px-6 md:px-12 py-8 md:pt-12 box-border
       + hidden scrollbar ([&::-webkit-scrollbar]:hidden [-ms-overflow-style:none] [scrollbar-width:none])
```
→ **Right pane: max-width 520px, white, 24px horizontal padding (48px ≥768px), 32px vertical (48px top ≥768px).**

**Logo row:** `display:flex; alignItems:center; gap:12px; marginBottom:32px`
- Tile: **48×48px, `background:#6B4F4F`, `borderRadius:10px`**, centered.
- Tile glyph: `"JI"` — `color:#FFFFFF; fontWeight:700; fontSize:15px; letterSpacing:0.02em`
- Wordmark: `"Jewels India"` — `fontWeight:700; fontSize:17px; color:#111111; letterSpacing:0.01em`

**Heading (`title` prop):** `fontFamily:"Georgia, serif"; fontSize:44px; fontWeight:700; color:#111111; lineHeight:1.1; margin:"0 0 8px"`
**Subtitle (`subtitle` prop):** `fontSize:15px; color:#888888; margin:"0 0 36px"; lineHeight:1.5; fontWeight:400`
**Form slot:** `display:flex; flexDirection:column; flex:1` (lets children push a CTA to the bottom).

> Georgia is used for the 44px auth heading, NOT Cirka — the auth route is outside all three `.theme-*` scopes.

### 10.8 `components/auth/EntryForm.jsx` — the auth field/CTA language

**Label:** `display:block; fontSize:13px; fontWeight:600; color:#333333; marginBottom:8px; letterSpacing:0.01em` — copy: **`"Email or Phone number"`**

**Text field** — placeholder **`"Enter"`**:
```
width:100%; height:52px; border:1.5px solid #D9D0C5; borderRadius:8px;
padding:0 14px; fontSize:14px; color:#111111; background:#FAFAFA;
outline:none; boxSizing:border-box; transition:border-color 0.2s; marginBottom:20px
onFocus  → borderColor #111111
onBlur   → borderColor #D9D0C5
```
> Note `#D9D0C5` is `--color-celestique-border` used as a raw literal.

**Error row:** `flex; alignItems:flex-start; gap:8px; marginBottom:12px`
- dot: `5×5px; borderRadius:50%; background:#EF4444; flexShrink:0; marginTop:5px`
- text: `fontSize:12px; color:#DC2626; fontWeight:500; margin:0`

**"OR" divider:** `flex; alignItems:center; gap:12px; margin:16px 0`; two `flex:1; height:1px; background:#E0E0E0` rules; center label `"OR"` @ `fontSize:11px; color:#999999; fontWeight:500; letterSpacing:0.05em`

**Google button:** `width:100%; height:52px; border:1px solid #E0E0E0; borderRadius:8px; background:#FFFFFF; gap:10px; fontSize:14px; fontWeight:500; color:#111111`; hover `background:#F5F5F5`; disabled `opacity:0.6; cursor:not-allowed`. Icon 18×18 **full-color** Google mark (`#4285F4`, `#34A853`, `#FBBC05`, `#EA4335`). Label: **`"Google"`**, loading label **`"Redirecting..."`**.

**Primary CTA:**
```
width:100%; height:56px; borderRadius:8px; border:none;
fontSize:15px; fontWeight:600; letterSpacing:0.02em; color:#FFFFFF;
transition:background 0.2s; marginBottom:16px
enabled  → background #1A1A1A;  hover #333333
disabled → background #BBBBBB;  cursor:not-allowed   (disabled when loading OR field empty)
```
Label **`"Continue"`**; loading label **`"Checking..."`**.

**Legal footer:** `fontSize:13px; color:#888888; lineHeight:1.5; margin:"0 0 32px"` — copy verbatim: `"By continuing, you agree to our Terms of Service and Privacy Policy"` with `"Terms of Service"` and `"Privacy Policy"` as `fontWeight:700; color:#333333; textDecoration:underline`.

**Error strings (verbatim):**
- `"Your account has been banned. Please use a different number or email."`
- `"Please enter a valid 10-digit Indian mobile number."`
- `"Something went wrong. Please try again."`
- `"You signed up with Google. Redirecting..."`
- `"Failed to send OTP. Please try again."`
- `"Network error. Please check your connection and try again."`

### 10.9 `components/wholesaler/Sidebar.jsx`

**Desktop rail (`.wholesaler-sidebar`, inline styles):**
```
position:fixed; top:0; left:0; height:100vh; width:70px;
backgroundColor:#f5f5f3;  ← NOTE: #f5f5f3, not celestique-cream #F5F2EB
display:flex; flexDirection:column; alignItems:center;
justifyContent:space-between; padding:24px 0; overflow:hidden; zIndex:50
```
**Icon stack:** `marginTop:96px; marginBottom:auto; gap:32px`. At `@media (max-height: 680px)`: `marginTop:32px !important; gap:16px !important`.

**Nav item:** `44×44px; borderRadius:8px; transition:all 0.15s ease; backgroundColor:transparent`
- inactive: `opacity:0.35; filter:grayscale(1)`
- active: `opacity:1; filter:brightness(0)` (renders the SVG solid black)
- hover: `opacity:0.7 !important; background-color:rgba(0,0,0,0.06) !important`
- icon `<Image width={28} height={28} objectFit:contain>`
- **Active detection:** Home uses `pathname === href` (exact); all others `pathname.startsWith(href)`.

**Nav items (order, label = `title` tooltip, href, remote icon):**
| # | `name` | `href` | icon URL |
|---|---|---|---|
| 1 | `"Home"` | `/dashboard/wholesaler` | `…/v1777013959/home_logo_q3xekq.svg` |
| 2 | `"Add/Upload"` | `/dashboard/wholesaler/add-product` | `…/v1777013959/upload_logo_hfdz8a.svg` |
| 3 | `"Add Retailer"` | `/dashboard/wholesaler/add-retailer` | `…/v1777013959/add_retailer_logo_aonkud.svg` |
| 4 | `"Catalogue"` | `/dashboard/wholesaler/catalogue` | `…/v1777013959/catalogue_logo_baed4n.svg` |
| 5 | `"Orders"` | `/dashboard/wholesaler/orders` | `…/v1777013960/PACKAGE_LOGO_ekya2x.svg` |
| 6 | `"Chat"` | `/dashboard/wholesaler/queries` | `…/v1777013960/chatLOGO_j1mnkx.svg` |

(All under `https://res.cloudinary.com/dcs0vuzwg/image/upload/`.)

**Bottom logo/logout button:** `44×44px; backgroundColor:#2e2833; borderRadius:12px`, `title="Logout"`, icon `jewel_logo_rhgin9.svg` @ 28×28. Hover: `opacity:0.9 !important; transform:scale(1.05)`; transition `transform 0.15s ease, opacity 0.15s ease`. Wrapper has `marginBottom:8px`.

**Mobile floating bottom nav (`@media max-width: 767px`)** — rail is `display:none`:
```
position:fixed; bottom:20px; left:50%; transform:translateX(-50%);
width:90vw; max-width:400px; height:60px;
background:rgba(255,255,255,0.85);
backdrop-filter:blur(20px); -webkit-backdrop-filter:blur(20px);
border:1px solid rgba(255,255,255,0.5);
border-radius:100px;
box-shadow:0 8px 32px rgba(0,0,0,0.1), 0 1.5px 4px rgba(0,0,0,0.06);
align-items:center; justify-content:space-around; padding:0 12px; z-index:100
```
→ **iOS: a 60pt-tall pill, 20pt from the bottom, 90% width capped at 400pt, `.ultraThinMaterial` blur ≈20, 1px white-50% hairline, radius 50 (fully rounded).**

**Bottom nav item:** `44×44px; borderRadius:50%; transition:all 0.2s ease`. Inactive `opacity:0.45; filter:grayscale(1)`; active `opacity:1; filter:brightness(0)` **plus** `.bottom-nav-item.active { background: rgba(0,0,0,0.05); filter: brightness(0) !important; }`. Icons 24×24.

**Bottom-nav item ORDER (reordered vs the rail!):** Home, Catalogue, Add/Upload, Orders, Chat — i.e. `navItems[0], [3], [1], [4], [5]`. **"Add Retailer" is NOT in the bottom bar** — it lives in the "More" popover.

**"More" trigger:** `36×36px; borderRadius:50%; backgroundColor:#2e2833`, `title="More Options"`, jewel logo @ 22×22.

**More popover:**
- Scrim: `position:fixed; inset 0; background:rgba(0,0,0,0.1); backdrop-filter:blur(2px); z-index:99`
- Content: `position:fixed; bottom:90px; left:50%; translateX(-50%); width:200px; background:#ffffff; border:1px solid rgba(0,0,0,0.08); border-radius:16px; box-shadow:0 12px 30px rgba(0,0,0,0.15); padding:8px; gap:4px;` `animation: popoverFadeIn 0.25s cubic-bezier(0.16,1,0.3,1) forwards`
- `.popover-item`: `gap:12px; padding:12px 16px; border-radius:10px; color:#374151; font-size:14px; font-weight:500; transition:background-color 0.15s ease`; hover `background:#f3f4f6`
- `.popover-logout`: `color:#ef4444`; hover `background:#fef2f2`
- Items: **`"Invite Retailer"`** (→ `/dashboard/wholesaler/add-retailer`, icon `add_retailer_logo_aonkud.svg` @ 20×20 with `filter: brightness(0)`) and **`"Logout"`** (inline 20×20 SVG, `stroke="#ef4444"`, `strokeWidth="2.5"`, round caps/joins).

**Logout confirmation modal:**
- Overlay: `position:fixed; inset 0; backgroundColor:rgba(0,0,0,0.4); backdropFilter:blur(4px); zIndex:1000; animation:"fadeIn 0.2s ease-out"`; click-outside closes.
- Card: `backgroundColor:#ffffff; borderRadius:20px; padding:32px; width:360px; maxWidth:90%; boxShadow:"0 20px 25px -5px rgba(0,0,0,0.1), 0 10px 10px -5px rgba(0,0,0,0.04)"; textAlign:center; animation:"scaleUp 0.2s cubic-bezier(0.34, 1.56, 0.64, 1)"`
- Icon circle: `56×56px; backgroundColor:#fef2f2; borderRadius:50%; marginBottom:20px`; inner 24×24 logout SVG `stroke="#ef4444" strokeWidth="2.5"`.
- Title: **`"Confirm Logout"`** — `fontSize:18px; fontWeight:600; color:#111827; margin:"0 0 8px 0"; fontFamily:"Inter, sans-serif"`
- Body: **`"Are you sure you want to logout?"`** — `fontSize:14px; color:#6b7280; margin:"0 0 24px 0"; lineHeight:1.5; fontFamily:"Inter, sans-serif"`
- Buttons row `gap:12px; width:100%`, each `flex:1; padding:12px; borderRadius:10px; fontSize:14px; fontWeight:500`:
  - **`"Cancel"`** — `border:1px solid #e5e7eb; backgroundColor:#ffffff; color:#374151`; hover bg `#f9fafb`
  - **`"Logout"`** — `border:none; backgroundColor:#2e2833; color:#ffffff`; hover `opacity:0.9`

### 10.10 `components/wholesaler/StatCard.jsx` (exported as `BottomStatCard`)
```
container: flex-1 flex flex-col justify-center rounded-xl border border-[#e5e5e5]
           bg-white py-5 px-6 relative transition-all duration-200
           hover:shadow-md hover:scale-[1.02]
           focus:outline-none focus:ring-2 focus:ring-amber-500 focus:border-transparent
           + when href: "hover:bg-gray-50 cursor-pointer"
```
→ **12px radius, 1px `#E5E5E5` border, white fill, 20px vertical / 24px horizontal padding, hover lifts to `shadow-md` and scales 1.02 over 200ms.**

- Row: `flex flex-row items-center justify-between`
- **Value:** `font-cirka text-[48px] font-medium leading-tight text-gray-900` → **48px Cirka weight 500 (synthesised — Cirka has no 500), line-height 1.25, color `#111827`** (Tailwind `gray-900`).
- **"New" badge** (`showBadge`): `relative flex h-2 w-2 -mt-6 ml-1` (8×8px, offset **−24px** up, 4px left) containing:
  - ping layer: `animate-ping absolute inline-flex h-full w-full rounded-full bg-red-400 opacity-75`
  - dot: `relative inline-flex rounded-full h-2 w-2 bg-red-500`
- Title row: `flex flex-row items-center gap-2 mt-1` (8px gap, 4px top)
  - icon slot: `text-gray-700 w-4 h-4 flex items-center justify-center` (16×16, `#374151`)
  - 🐞 title: `text-s font-medium text-gray-700` → **`text-s` is invalid → inherits 16px**, weight 500, `#374151`
- Chevron: inline 16×16 SVG, `fill="black"`, `className="text-gray-400"` (the class is inert — `fill` is a hard attribute, so it renders **black**, not `#9CA3AF`).

**Instances (`OverviewSection.jsx`), verbatim titles and hrefs:**
| title | href | icon | badge |
|---|---|---|---|
| `"Live Products"` | `/dashboard/wholesaler/catalogue` | remote `live_products_nfjmtr.svg` 16×16 | — |
| `"New Orders"` | `/dashboard/wholesaler/orders?tab=new` | inline lock/bag SVG `w-4 h-4 text-gray-700 strokeWidth={2}` | `hasNewOrders` |
| `"New Chat"` | `/dashboard/wholesaler/queries` | inline chat SVG | `hasNewChats` |
| `"Uploads Today"` | `/dashboard/wholesaler/upload-history` | inline upload SVG | — |

Uploads value string: `` `${usedUploads}/${uploadLimit}` `` when a finite limit exists, else `` `${usedUploads}` ``.

### 10.11 `components/wholesaler/OverviewSection.jsx` (layout + Chamak card)
- Section: `px-4 md:px-6 py-6 md:py-10`; inner `mx-auto max-w-7xl` (**1280px**)
- Heading: `<h2 className="font-cirka text-4xl text-celestique-dark mb-6">` — copy **`"Insights"`** → **36px Cirka, `#111111`, 24px bottom margin**
- Grid: `grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 w-full` → 1 / 2 / 4 columns, 16px gutter
- **Chamak card** (`mt-6`):
```
relative w-full overflow-hidden rounded-2xl
bg-gradient-to-r from-[#bb8651] to-[#f6e0a7]
p-6 md:p-8 flex flex-row items-center justify-between
border border-[#e4cc8f]/30
transition-all duration-200 hover:shadow-lg hover:scale-[1.01]
min-h-[220px] md:min-h-[200px]
```
  - Left column: `flex flex-col gap-3 z-10 max-w-[60%] sm:max-w-[65%] md:max-w-[70%]`
  - Title **`"Chamak"`**: `font-cirka text-3xl md:text-4xl text-white font-bold leading-none tracking-normal`
  - Body **`"Review products with low engagement and Replace with better designs"`**: `font-manrope text-xs md:text-sm text-white/95 leading-relaxed font-medium`
  - Badge **`"Coming soon"`**: outer `relative border border-[#e4cc8f] bg-black px-5 py-2.5 rounded-lg shadow-[0px_4px_4px_rgba(0,0,0,0.25)]`; label `font-manrope text-sm font-semibold text-white tracking-wide`; plus an absolutely-positioned inner glow `rounded-lg shadow-[inset_2px_2px_4px_rgba(228,204,143,0.3)]`
  - Right art: `absolute right-0 top-0 bottom-0 w-[45%] md:w-[35%]`, inner box `w-[180px] h-[220px] md:w-[220px] md:h-[260px] lg:w-[240px] lg:h-[280px]`, `right-[-10px] md:right-[-20px]`, **CSS mask** `url('/image/chamak_mask.svg')` with `maskSize:100% 100%`, `maskRepeat:no-repeat`, `maskPosition:center`; image `/image/chamak_necklace.png` `object-cover object-right`.

### 10.12 `components/wholesaler/CatalogueSection.jsx` + `CategoryCard.jsx`
- Section `px-4 md:px-6 py-8 md:py-12`; inner `mx-auto max-w-7xl`; header `mb-8 text-left`
- Heading **`"My Catalogue"`**: `font-cirka text-4xl text-celestique-dark md:text-3xl` (⚠️ **larger on mobile (36px) than on desktop (30px)** — inverted, reproduce as-is)
- Sub-copy **`"See and manage all your catalogue categories from one place."`**: `mt-2 text-s text-celestique-muted font-gilroy font-medium` → 🐞 16px (invalid `text-s`), `#8C857B`, Gilroy 500
- Grid: `grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-5` → 1 / 2 / 5 columns, **20px gutter**
- **`CategoryCard`:** `group relative w-full h-[339px] rounded-xl shadow-sm hover:shadow-md transition-shadow duration-200 overflow-hidden`
  - Image `fill sizes="280px" object-cover transition-transform duration-500 group-hover:scale-105`
  - Error fallback: `h-full w-full bg-linear-to-br ${category.gradient ?? "from-amber-100 to-yellow-200"}` + same hover scale
  - Scrim: `absolute inset-x-0 top-0 h-1/2 bg-linear-to-b from-celestique-dark/30 to-transparent`
  - Label: `absolute top-6 left-4 right-4` → `font-serif font-medium text-xl text-white tracking-wide text-center w-full` (**Cirka 500 synthesised, 20px, white, 0.025em**)
- **"View All" card:** `group flex w-full h-[339px] items-center justify-center rounded-xl border-2 border-dashed border-celestique-border bg-white hover:border-celestique-dark hover:bg-celestique-cream transition-all duration-200`; glyph `→` @ `text-3xl text-celestique-muted group-hover:text-celestique-dark`; label **`"View All"`** @ `mt-1 text-sm font-gilroy font-medium`
- **Categories (`lib/config/catalogueCategories.js`) — exact `name` / `slug` / `image` / `gradient`:**
| name | slug | image | fallback gradient |
|---|---|---|---|
| `Necklace` | `necklace` | `/image/neclace.svg` | `from-purple-100 to-violet-200` |
| `Haram` | `haram` | `/image/haram_svg.svg` | `from-orange-100 to-amber-200` |
| `Pendants` | `pendants` | `/image/pendants.svg` | `from-sky-100 to-blue-200` |
| `Mangalsutras` | `mangalsutras` | `/image/mangalsutra.svg` | `from-red-100 to-rose-200` |
| `Chains` | `chains` | `https://res.cloudinary.com/dcs0vuzwg/image/upload/v1777351896/chains_tqfmhp.svg` | `from-slate-100 to-gray-200` |
| `Bangles` | `bangles` | `/image/bangles.svg` | `from-yellow-100 to-amber-200` |
| `Rings` | `rings` | `/image/rings.svg` | `from-rose-100 to-pink-200` |
| `Earrings` | `earrings` | `/image/earrings.svg` | `from-orange-100 to-amber-200` |
| `Nosepins` | `nosepins` | `/image/nosepins.svg` | `from-teal-100 to-emerald-200` |

Deep link format: `/dashboard/wholesaler/catalogue?category=${slug}`.

### 10.13 `components/wholesaler/HeroUploadSection.jsx` + `UploadButton.jsx`
- Section `px-4 md:px-10 pt-6 pb-4`; header block `mb-4`
- Eyebrow **`"Welcome"`**: `text-[#6B7280] text-xs md:text-sm font-sfpro mb-1`
- `<h1 className="text-[#1F2937] text-xl md:text-2xl font-medium font-sfpro">{displayName}</h1>` — ⚠️ **inside `.theme-wholesaler`, the `h1` rule forces Cirka `!important`, so `font-sfpro` loses.** Renders **Cirka 500 @ 20px / 24px ≥768px, `#1F2937`.**
- `displayName` = `businessName?.trim() || "Welcome"`
- Banner: `relative overflow-hidden h-[160px] md:h-[180px] rounded-xl border border-[#F3E8D6] shadow-sm bg-[#FFFDF9]`; background `/image/heroframee.png` `fill priority object-cover object-right md:object-center opacity-80`; content `relative z-10 h-full flex flex-col justify-end items-center px-6 md:px-10 pb-6`
- **`UploadButton`** → `/dashboard/wholesaler/add-product`:
```
inline-flex items-center gap-2 rounded-lg cursor-pointer bg-black
px-5 py-2.5 text-sm font-medium text-white shadow-md
hover:bg-[#2a2a2a] active:scale-[0.97] transition-all duration-200
```
  Icon: 16×16 upload SVG `strokeWidth="2"` round caps. Label **`"Upload Now"`**.

### 10.14 `components/wholesaler/WeeklyReviewBanner.jsx`
`section px-6 pb-10`, inner `mx-auto max-w-7xl`.
Card: `w-full h-[160px] rounded-2xl px-8 py-6 flex items-center justify-between overflow-hidden relative bg-gradient-to-r from-[#B8895A] to-[#F5E6C8]`
- Heading **`"Weekly review"`** — `text-3xl font-semibold text-white` (h2 → forced Cirka in wholesaler theme)
- Body **`"Review products with low engagement and Replace with better designs"`** — `text-sm text-white/80 max-w-md`
- CTA **`"Review now"`** — `bg-black text-white px-5 py-2.5 rounded-lg font-medium shadow-md w-max flex items-center hover:scale-105 transition-all duration-200 mt-1` + 16×16 arrow SVG `ml-2 strokeWidth={2}`
- Decorative arrow: `absolute right-0 top-1/2 -translate-y-1/2 opacity-20 pointer-events-none`, remote `arrow_logo_h8purb.svg`, `w-48 h-48 object-contain`

### 10.15 `components/product/ProductCard.jsx`

**`ProductCardSkeleton`** — must match the card box exactly:
```
<article className="flex flex-col">
  <div className="relative aspect-4/5 w-full mb-6 skeleton-shimmer" />
  <div className="flex items-center justify-between border-b border-celestique-dark/10 pb-2 mt-2 gap-4">
    <div className="h-2 w-2/3 skeleton-shimmer" />
    <div className="h-2 w-1/5 skeleton-shimmer" />
  </div>
  <div className="h-2 w-1/3 skeleton-shimmer mt-3" />
</article>
```
→ 4:5 image block, 24px gap, then two 8px bars (66.6% / 20%) on a 1px `#111111`@10% underline with 8px bottom padding, then an 8px bar at 33.3% width, 12px down.

**Card root:** `group flex flex-col card-enter cursor-pointer`, `role="button"`, `tabIndex={0}`, Enter/Space opens the modal, `aria-label={`View details for ${product.title || product.jewellery_type || "jewellery piece"}`}`.

**Image container:** `relative aspect-4/5 w-full overflow-hidden mb-6`
- **Loading state:** while `activeUrl && !imgError && !imgLoaded` → `<div className="absolute inset-0 z-10 skeleton-shimmer" />`
- **Loaded image:** `w-full h-full object-cover mix-blend-multiply transition-all duration-700 group-hover:scale-105` + `opacity-100`/`opacity-0` crossfade. **`mix-blend-multiply` is essential to the look** — product cut-outs multiply into the page background. SwiftUI: `.blendMode(.multiply)`.
- **Error / no-URL state:** `absolute inset-0 flex flex-col items-center justify-center gap-2 bg-celestique-taupe/20 text-celestique-dark/25` with a `w-8 h-8` gem SVG (`d="M6.5 2h11l4 6-9.5 14L2.5 8l4-6z"`) and the label **`"No Image"`** @ `text-[9px] uppercase tracking-widest font-bold`.
- **Hover overlay:** `absolute inset-0 z-10 flex items-end justify-center pb-6 opacity-0 group-hover:opacity-100 transition-opacity duration-300 pointer-events-none`; pill **`"View Details"`** @ `text-[9px] uppercase tracking-[0.3em] font-bold bg-celestique-dark text-celestique-cream px-4 py-2` (square, no radius).
- **Stock badge** (only after `imgLoaded`): `absolute top-4 left-4 z-20`, `text-[9px] font-bold uppercase tracking-[0.2em] text-celestique-dark bg-celestique-cream/85 backdrop-blur-md px-3 py-1.5`
  - `product.stock_available` → **`"In Stock"`**
  - else `product.make_to_order_days` → **`"Made to Order"`**
  - else nothing
- **Variant arrows** (when >1 variant): `absolute left-4|right-4 top-1/2 -translate-y-1/2 w-8 h-8 bg-celestique-cream/80 backdrop-blur-md flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity hover:bg-celestique-cream text-celestique-dark z-20`; glyphs `←` / `→`; `aria-label="Previous variant"` / `"Next variant"`.
- **Variant dots:** `absolute bottom-4 left-0 right-0 flex justify-center gap-2 opacity-0 group-hover:opacity-100 transition-opacity`; each `w-1.5 h-1.5 transition-colors` (**6×6px square, not round**); active `bg-celestique-dark`, inactive `bg-celestique-dark/30 hover:bg-celestique-dark/60`; `aria-label={`View variant ${i+1}`}`.

**Meta block:** `flex items-center justify-between border-b border-celestique-dark/10 pb-2 mt-2`
- Title: `font-sans text-[10px] uppercase tracking-widest font-bold text-celestique-dark line-clamp-1` → **Manrope 700, 10px, 0.1em, single-line clamp**. Fallback string: `` `${Capitalized(jewellery_type) || "Jewellery"} Piece` ``
- Category: `text-[10px] uppercase tracking-widest text-celestique-dark/50 shrink-0 ml-2`
- Byline (when `wholesaler_email`): `text-[9px] tracking-widest uppercase text-celestique-dark/35 mt-2`, copy `` `By ${wholesaler_email.split("@")[0]}` ``

**Variant source order:** `generated_image_urls[]` if non-empty, else `[processed_image_url || image_url || raw_image_url]` filtered for truthiness.

---

## 11. CSS-module specs (verbatim values)

### 11.1 `components/wholesaler/orders/orders.module.css`
| Selector | Key properties |
|---|---|
| `.page` | `padding: 36px 40px; min-height:100vh; background:#fff; font-family:'DM Sans', sans-serif` (**DM Sans never loaded → generic sans**) |
| `.backLink` | `flex; gap:4px; color:#6B7280; 14px; 500; margin-bottom:24px; transition:color 0.15s`; hover `#111827` |
| `.headerText` | `text-align:center; margin-bottom:24px` |
| `.title` | `font-family:Georgia, serif; 32px; 700; #111827; margin:0 0 6px` |
| `.subtitle` | `15px; #6B7280; 400` |
| `.tabsContainer` | `flex; justify-content:space-between; margin-bottom:32px; background:#F9FAFB; padding:6px; border-radius:999px; width:fit-content` |
| `.tabBtn` | `gap:8px; padding:8px 16px; radius:999px; 14px/500; #6B7280; transparent; transition:all 0.15s` |
| `.tabBtnActive` | `background:#fff; #111827; 600; box-shadow:0 1px 3px rgba(0,0,0,0.08)` |
| `.tabBadge` | `background:#E5E7EB; color:#4B5563; 12px/600; padding:2px 8px; radius:999px` |
| `.filterBtn` | `gap:6px; padding:8px 16px; radius:999px; 14px/500; #374151; #fff; 1px solid #D1D5DB; margin-left:auto`; hover bg `#F9FAFB` |
| `.card` | `flex row; padding:32px 0; border-bottom:1.5px solid #E5E7EB; gap:32px; align-items:flex-start`; `:last-child` no border |
| `.productImage` | `230×230px; radius:8px; object-fit:cover; background:#F3F4F6` |
| `.productName` | `Georgia, serif; 24px; 700; #111827; margin:0 0 4px` |
| `.productMeta` | `13px; #6B7280; margin:0 0 24px` |
| `.detailsGrid` | `grid; grid-template-columns:140px 1fr; row-gap:12px; align-items:baseline` |
| `.detailLabel` | `14px; #9CA3AF; 500` |
| `.detailValue` | `14px; #111827; 600` — `.detailValue.normal` → `400` |
| `.retailerLink` | `underline; #111827; 500`; hover `#4B5563` |
| `.cardActions` | `flex column; justify-content:space-between; align-items:flex-end; align-self:stretch; min-width:220px` |
| `.statusIndicator` | `gap:6px; 14px; 600` |
| `.statusSubtext` | `12px; #9CA3AF; margin-top:4px; 400; text-align:right` |
| **Status color variants** | `.statusUrgentAmber` `#B45309` · `.statusUrgentRed` `#DC2626` · `.statusProductionAmber` `#B45309` · `.statusPackedTeal` `#0D9488` · `.statusDeliveredGreen` `#16A34A` |
| `.buttonsStack` | `flex column; gap:12px; width:100%` |
| `.btn` | `padding:10px 16px; radius:8px; 14px/600; gap:8px; transition:all 0.15s` |
| `.btnReject` | `#fff; 1px solid #DC2626; #DC2626`; hover bg `#FEF2F2` |
| `.btnPrimary` | `#1F2937 fill + border; #fff`; hover `#111827` |
| `.btnOutline` | `#fff; 1px solid #D1D5DB; #374151`; hover `#F9FAFB` |
| `.modalOverlay` | `fixed inset 0; rgba(0,0,0,0.4); z-index:100; centered; padding:24px` |
| `.modalContent` | `#fff; radius:16px; max-width:480px; box-shadow:0 10px 25px rgba(0,0,0,0.1); overflow:hidden` |
| `.modalTop` | `padding:32px 32px 24px; gap:20px` |
| `.avatar` | `80×80px; radius:50%; linear-gradient(135deg,#FDF7EC,#F2E3C6); 28px/700; #B45309` |
| `.modalTitle` | `22px; 700; #111827` |
| `.verifiedBadge` | `gap:4px; #16A34A; 13px/600` |
| `.memberSince` | `13px; #6B7280` |
| `.modalDivider` | `height:1px; background:#E5E7EB; margin:0 32px` |
| `.contactList` | `padding:24px 32px; gap:16px` |
| `.contactRow` | `gap:12px; #374151; 15px; line-height:1.4` |
| `.modalBottom` | `padding:24px 32px; justify-content:flex-end` |
| `.btnCloseModal` | `#1F2937; #fff; padding:10px 24px; radius:999px; 14px/600`; hover `#111827` |

**Responsive:**
- `@media (max-width:1024px)`: `.page` padding `24px`; `.card` gap 24px / padding `24px 0`; `.productImage` 160×160; `.productName` 20px; `.detailsGrid` cols `120px 1fr`, row-gap 8px; `.cardActions` min-width 180px; `.tabsContainer` width 100%
- `@media (max-width:767px)`: `.page` padding 16px; `.title` 26px; `.subtitle` 14px; `.tabsContainer` padding 0 / transparent / radius 0 / mb 24px; `.tabsRow` column, gap 16px; `.tabsLeft` horizontal scroll `width:100vw; margin-left:-16px; padding:0 16px`, scrollbars hidden; `.tabBtn` `background:#F9FAFB; white-space:nowrap; border:1px solid #E5E7EB`; `.tabBtnActive` `border-color:#D1D5DB`; `.filterBtn` full-width centered; `.card` column, gap 16px; `.productImage` `width:100%; height:200px`; `.cardActions` column/left-aligned, gap 16px; `.statusSubtext` left-aligned; `.buttonsStack` full width; **modal becomes a bottom sheet** — `.modalOverlay` `align-items:flex-end; padding:0`; `.modalContent` `border-radius:20px 20px 0 0; max-width:100%`; `.modalTop/.contactList/.modalBottom` horizontal padding 20px

### 11.2 `components/wholesaler/queries/queries.module.css`
| Selector | Key properties |
|---|---|
| `.page` | `padding:36px 40px; min-height:100vh; #fff; font-family:'DM Sans', sans-serif` |
| `.title` | `Georgia, serif; 32px; 700; #111827; margin:0 0 6px` |
| `.subtitle` | `15px; #9CA3AF; margin:0 0 20px; 400` |
| `.filters` | `flex; gap:8px; margin-bottom:24px` |
| `.filterTab` | `padding:6px 18px; radius:999px; 13px/600; 1.5px solid #E5E7EB; #fff; color:#9CA3AF; transition:all 0.15s`; hover border `#D1D5DB` |
| `.filterTabActive` | `border-color:#374151; color:#111827` |
| `.splitPanel` | `flex; height:calc(100vh - 200px); min-height:480px` |
| `.leftPanel` | `width:380px; 1.5px solid #E5E7EB; radius:14px 0 0 14px; #fff; overflow-y:auto` |
| `.rightPanel` | `flex:1; 1.5px solid #E5E7EB; border-left:none; radius:0 14px 14px 0; #fff; overflow:hidden` |
| `.card` | `padding:18px 20px; border-bottom:1px solid #F3F4F6; transition:background 0.12s, border-color 0.12s`; hover `#FAFAFA` |
| `.cardSelected` | `1.5px solid #374151; radius:10px; margin:4px 6px; box-shadow:0 2px 8px rgba(0,0,0,.06)` |
| `.cardBadge` | `absolute top:14px right:14px; 11px/600; padding:3px 10px; radius:6px; letter-spacing:0.01em; text-transform:lowercase` |
| `.badgeUnread` | `background:#2563EB; color:#fff` |
| `.badgeReplied`, `.badgeRead` | `background:#F3F4F6; color:#6B7280` |
| `.cardProduct` | `15px; 700; #111827; margin:0 0 4px; padding-right:80px` |
| `.cardFrom` | `12px; **#D97706**; margin:0 0 10px; 500` |
| `.cardPreview` | `13px; #4B5563; 2-line clamp (`-webkit-line-clamp:2`); line-height:1.45` |
| `.cardTimestamp` | `12px; #9CA3AF; gap:4px; justify-content:flex-end` |
| `.clockIcon` | `13×13px; opacity:0.6` |
| **Empty state** `.emptyState` | `flex column centered; flex:1; text-align:center; padding:40px` |
| `.emptyIcon` | `64×64px; margin-bottom:20px; **opacity:0.35**` |
| `.emptyHeading` | `17px; 700; #111827; margin:0 0 6px` |
| `.emptyCaption` | `14px; #9CA3AF` |
| `.detailHeader` | `padding:20px 24px; border-bottom:1px solid #E5E7EB; flex-shrink:0` |
| `.detailProductName` | `18px; 700; #111827` |
| `.detailContactName` | `14px; 700; #111827; gap:6px; justify-content:flex-end` |
| `.detailStore` | `12px; #9CA3AF; margin:2px 0 0` |
| `.timestampDesktop` | `gap:4px; #9CA3AF; 12px; 400` (mobile variant hidden and vice-versa) |
| `.chatArea` | `flex:1; overflow-y:auto; padding:24px; flex column; gap:16px` |
| `.chatTimestamp` | `center; 12px; #9CA3AF; margin:8px 0` |
| **`.bubbleRetailer`** | `background:#F3F4F6; color:#374151; padding:14px 18px; **radius:4px 16px 16px 16px**; max-width:75%; 14px; line-height:1.55; align-self:flex-start` |
| **`.bubbleWholesaler`** | `background:#EEF2FF; color:#374151; padding:14px 18px; **radius:16px 4px 16px 16px**; max-width:75%; 14px; line-height:1.55; align-self:flex-end` |
| `.replyBar` | `padding:16px 24px; border-top:1px solid #E5E7EB; gap:12px; #fff; flex-shrink:0` |
| `.paperclipBtn` | `opacity:0.45; transition:opacity 0.15s`; hover `0.7` |
| `.replyInput` | `flex:1; height:44px; 1.5px solid #E5E7EB; radius:10px; padding:0 16px; 14px; #111827; #fff; transition:border-color 0.15s`; focus border `#9CA3AF`; **placeholder `#9CA3AF`** |
| `.sendBtn` | `gap:6px; padding:10px 20px; radius:10px; background:#374151; #fff; 14px/600`; hover `#1F2937` |
| `.backBtn` | `display:none` desktop; mobile `flex; gap:6px; 14px/600; #374151; margin-bottom:12px` |

**Responsive:**
- `@media (max-width:1024px)`: `.page` 24px; `.leftPanel` 270px; `.card` `12px 14px`; `.cardProduct` 14px; `.cardPreview` 12px; `.detailProductName` 16px; `.detailContactName` 13px
- `@media (max-width:767px)`: `.page` `16px` with `padding-bottom:0`; `.title` 26px; `.subtitle` 13px; `.splitPanel` column, `height:auto`; `.leftPanel` full width, radius 14px, `overflow:visible`; `.leftPanelHidden`/`.rightPanelHidden` → `display:none` (**master/detail becomes a stack navigator**); `.rightPanel` `position:fixed; inset 0; z-index:50; border-radius:0; border:none`; `.card` `14px 16px`; `.cardTimestamp` 11px; bubbles `max-width:85%`; `.replyBar` **fixed to bottom**, `padding:12px 16px`, `padding-bottom: calc(12px + env(safe-area-inset-bottom, 0px))`, `z-index:51`; `.chatArea` `padding-bottom:80px`; `.detailHeader` column, gap 8px, padding 16px, `align-items:stretch`

> **iOS:** the `env(safe-area-inset-bottom)` handling in `.replyBar` maps directly to `.safeAreaInset(edge: .bottom)` / `.ignoresSafeArea(.keyboard)`.

### 11.3 `components/wholesaler/referral/referralManager.module.css`
| Selector | Key properties |
|---|---|
| `.container` | `width:100%; font-family:'Inter', sans-serif` (**Inter never loaded**) |
| `.header` | `margin-bottom:64px` |
| `.title` | `font-size: clamp(20px, 3vw, 24px); 700; #111; margin:0 0 8px 0; letter-spacing:-0.01em` |
| `.subtitle` | `clamp(13px, 1.5vw, 14px); #6B7280; margin:0 0 24px 0; line-height:1.5` |
| `.inputRow` | `flex; align-items:flex-start; gap:16px` |
| `.input` | `width:100%; **height:56px**; background:#F3F4F6; border:none; radius:8px; padding:0 88px 0 16px; 15px; #374151; outline:none` |
| `.inputEmpty` | `padding: 0 48px 0 16px` (narrower right inset when there's nothing to copy) |
| `.actionButtons` | `absolute; right:12px; top:50%; translateY(-50%); gap:8px` |
| `.buttonContainer` | `flex column; align-items:flex-end; min-width:220px` |
| `.generateButton` | `gap:8px; height:56px; width:100%; background:#111; #FFF; radius:8px; 15px/600; transition:opacity 0.2s` |
| **`.generateButton:disabled`** | `cursor:not-allowed; **opacity:0.7**` |
| `.secureText` | `11px; #9CA3AF; 600; margin-top:8px; text-align:right; line-height:1.4` |
| `.prevTitle` | `12px; 600; #6B7280; text-transform:uppercase; letter-spacing:0.05em; margin-bottom:16px` |
| `.linkRow` | `flex; padding:16px 0; background:#FFFFFF`; `:not(:last-child)` → `border-bottom:1px solid #E5E7EB` |
| `.urlText` | `clamp(12px, 1.5vw, 14px); #4B5563; **font-family:monospace**; flex:1; ellipsis truncation` |
| `@media (max-width:768px)` | `.inputRow` column/stretch; `.buttonContainer` centered, `min-width:100%`; `.secureText` centered; `.linkRow` wrap + gap 12px + padding `12px 0`; `.urlText` `min-width:100%; order:3; margin-top:4px`; `.dateBadge` `margin-left:auto` |

> ⚠️ `.dateBadge` is styled only inside the ≤768px media query — it has **no base rule** in this file. UNEXTRACTABLE: its desktop appearance is defined elsewhere (inline in the JSX) or not at all.

### 11.4 `app/dashboard/wholesaler/add-retailer/addRetailer.module.css`
| Selector | Key properties |
|---|---|
| `.container` | `padding:48px 64px; max-width:1000px; font-family:'Inter', sans-serif; margin:0 auto` |
| `.header` | `margin-bottom:56px` |
| `.title` | `clamp(28px, 4vw, 36px); 700; #111111; margin:0 0 12px 0; letter-spacing:-0.02em` |
| `.subtitle` | `clamp(14px, 2vw, 15px); #6B7280; line-height:1.5` |
| `.flowContainer` | `flex; justify-content:space-between; align-items:flex-start; position:relative; margin-bottom:80px` |
| `.step` | `flex:1; text-align:center; z-index:1` |
| `.stepIcon` | `clamp(60px, 8vw, 90px)` square; `margin:0 auto 16px` |
| `.stepTitle` | `clamp(14px, 2vw, 15px); 600; #111; margin:0 0 8px 0` |
| `.stepDesc` | `clamp(12px, 1.5vw, 13px); #6B7280; padding:0 10%; line-height:1.5` |
| `.arrow` | `absolute; top:clamp(30px, 4vw, 45px); width:33.33%; height:30px; z-index:0; overflow:visible` |
| `.arrow1` / `.arrow2` | `left:16.66%` / `left:50%` |
| `.verticalArrow` | desktop `display:none`; ≤768px `display:block; width:2px; height:32px; border-left:2px dashed #D1D5DB; margin:8px auto` |
| `@media (max-width:1024px)` | `.container` padding `32px 40px` |
| `@media (max-width:768px)` | `.container` padding `24px 20px`; `.flowContainer` column, centered, gap 8px; `.step` `width:100%; max-width:300px`; `.arrow` hidden |

### 11.5 `app/join/[code]/joinLanding.module.css`
| Selector | Key properties |
|---|---|
| `.pageContainer` | `min-height:100vh; width:100vw; flex centered; background-image:url('https://res.cloudinary.com/dcs0vuzwg/image/upload/v1777318931/invitation_bg_vlguu6.svg'); background-size:cover; background-position:center; font-family:'Inter', sans-serif; overflow-y:auto; padding:24px; box-sizing:border-box` |
| `.card` | `width:380px; #FFFFFF; radius:16px; **border:2px solid #FFFFFF**; box-shadow:0 12px 40px rgba(0,0,0,0.15); overflow:hidden; flex column` |
| `.imageSection` | `relative; width:100%; aspect-ratio:3/4; min-height:380px` |
| `.cardImage` | `100%/100%; object-fit:cover; display:block` |
| `.badge` | `absolute top:12px left:12px; background:rgba(255,255,255,0.7); backdrop-filter:blur(4px); color:#111; 13px/500; padding:4px 12px; radius:20px` |
| `.textOverlay` | `absolute; bottom:20px; left:20px; right:20px` |
| `.name` | `font-family:'Playfair Display', Georgia, serif; clamp(36px, 8vw, 48px); 700; #FFFFFF; margin:0 0 4px 0; line-height:1.1` |
| `.subtitle` | `clamp(15px, 3vw, 18px); **300**; #FFFFFF` |
| `.buttonSection` | `#FFFFFF; padding:16px; border-top:1px solid #E5E7EB` |
| `.ctaButton` | `width:100%; height:52px; background:#111; #FFF; radius:10px; 16px; gap:4px; transition:opacity 0.2s`; hover `opacity:0.85` |
| `.ctaTextRegular` / `.ctaTextBold` | `font-weight:400` / `font-weight:700` (mixed-weight CTA label) |
| Responsive | `≤1024px` `.card` 420px · `≤900px` 85% · `≤768px` `92%; max-width:420px` |

### 11.6 `components/employee/employeeTopNav.module.css`
| Selector | Key properties |
|---|---|
| `.navbar` | `position:sticky; top:0; z-index:50; **height:64px**; #ffffff; border-bottom:1px solid #E5E7EB; flex space-between; padding:0 24px; box-shadow:0 1px 2px 0 rgba(0,0,0,0.05)` |
| `.logo` | `height:32px; width:auto` |
| `.navLinks` | `flex; gap:32px; height:100%` |
| `.navLink` | `relative; height:100%; 15px/500; color:#6B7280; transition:color 0.2s; no underline`; hover `#111827` |
| `.navLinkActive` | `#111827; 600`; `::after` → `absolute bottom:-1px; width:100%; height:2px; background:#111827; border-radius:2px 2px 0 0` |
| `.rightSection` | `flex; gap:16px` |
| `.userInfo` | `flex column; align-items:flex-end` |
| `.userName` | `14px; 600; #111827; line-height:1.2` |
| `.storeName` | `12px; #6B7280; line-height:1.2` |
| `.avatar` | `36×36px; radius:50%; **linear-gradient(135deg, #6366F1 0%, #A855F7 100%)**; white; 600; 14px; text-transform:uppercase` |
| `.logoutBtn` | `36×36px; radius:50%; color:#6B7280; background:transparent; transition:all 0.2s`; hover `background:#FEE2E2; color:#DC2626` |

---

## 12. Breakpoints & responsive strategy

### 12.1 Tailwind v4 defaults (used via `sm:` `md:` `lg:` prefixes)
| Prefix | min-width |
|---|---|
| `sm:` | 40rem = **640px** |
| `md:` | 48rem = **768px** |
| `lg:` | 64rem = **1024px** |
| `xl:` | 80rem = **1280px** |
| `2xl:` | 96rem = **1536px** |

### 12.2 Hand-written media queries (all of them)
| Query | Where |
|---|---|
| `@media (min-width: 768px)` | `globals.css:518` — `.wholesaler-main-content { margin-left:70px; padding-bottom:0 }` |
| `@media (prefers-reduced-motion: reduce)` | `globals.css:377`, `globals.css:484` |
| `@media (max-width: 1024px)` | `addRetailer`, `joinLanding`, `orders`, `queries`, `Sidebar.jsx:384` |
| `@media (max-width: 900px)` | `joinLanding` |
| `@media (max-width: 768px)` | `addRetailer`, `joinLanding`, `referralManager` |
| `@media (max-width: 767px)` | `orders`, `queries`, `Sidebar.jsx:413`, `RetailerSidebar.jsx` |
| `@media (max-height: 680px)` | `Sidebar.jsx:389` — compress the icon stack |
| `@media (max-height: 780px)` | `RetailerSidebar.jsx` — compress profile/nav rows |

> ⚠️ Note the **768 vs 767 mismatch**: some modules break at `≤768px` and others at `≤767px`, while Tailwind's `md:` fires at `≥768px`. At exactly 768px CSS width the layout is inconsistent. Reproduce the wholesaler behaviour using `≤767` (mobile) / `≥768` (regular) as the primary split.

**iOS size-class mapping:** compact width (iPhone portrait) ⇒ the `≤767px` rules — no sidebar, floating pill bottom nav, 72pt bottom inset, stacked order cards, full-screen chat detail, bottom-sheet modals. Regular width (iPad / iPhone landscape) ⇒ the `≥768px` rules — 70pt leading rail, side-by-side split panels.

### 12.3 `env(safe-area-inset-bottom)` usage
| Where | Value |
|---|---|
| `queries.module.css:539` `.replyBar` | `padding-bottom: calc(12px + env(safe-area-inset-bottom, 0px))` |
| `RetailerSidebar.jsx` `.retailer-bottom-nav` | `bottom: calc(20px + env(safe-area-inset-bottom, 0px))` |
| `RetailerSidebar.jsx` `.bottom-nav-popover-content` | `bottom: calc(90px + env(safe-area-inset-bottom, 0px))` |
| ⚠️ `Sidebar.jsx` (wholesaler) `.wholesaler-bottom-nav` | plain `bottom: 20px` — **no safe-area handling.** On a notched iPhone the web bar sits 20px from the true bottom edge, overlapping the home indicator. Decide whether the iOS port copies the bug or fixes it. |

---

## 13. Backdrop blur / material

| Class / property | Resolved blur | Count |
|---|---|---|
| `backdrop-blur-md` | 12px | 29 |
| `backdrop-blur-sm` | 8px | 20 |
| `backdrop-blur-[2px]` | 2px | 6 |
| `backdrop-blur-xs` | 4px | 3 |
| `backdrop-blur-2xl` | 40px | 2 |
| `backdrop-blur-xl` | 24px | 1 |
| `backdrop-blur-lg` | 16px | 1 |
| `backdrop-filter: blur(20px)` | 20px | Mobile bottom nav (both sidebars) |
| `backdrop-filter: blur(4px)` | 4px | Logout modal overlay; `joinLanding .badge` |
| `backdrop-filter: blur(2px)` | 2px | `.bottom-nav-popover` scrim |

SwiftUI: `.ultraThinMaterial` ≈ blur(20) + white 85%; `.regularMaterial` for the 12px cases; `.thinMaterial` for 8px.

---

## 14. Known defects / parity decisions to flag to the user

| # | Issue | Files | Impact on port |
|---|---|---|---|
| 1 | **`text-s` is not a Tailwind class** — renders inherited 16px | `StatCard.jsx:40`, `CatalogueSection.jsx:14` | The 4 dashboard stat labels and the catalogue sub-copy are 16px, not 14px. Reproduce as 16pt or ask whether to fix. |
| 2 | **`animate-slide-in-right` has no keyframe definition** | `SelectionReviewClient.jsx:566`, `ProductInfoModal.jsx:431`, `:710` | Those slide-over panels currently appear instantly. |
| 3 | **`animate-in fade-in zoom-in` requires `tailwindcss-animate`, not installed** | `ConfirmationModal.jsx:51` | Confirmation modal has no entrance animation. |
| 4 | **`shadow-inner` (×4) may not exist in Tailwind v4** | 4 sites | Verify against built CSS before porting. |
| 5 | **`font-sfpro` on an `<h1>` inside `.theme-wholesaler` is overridden to Cirka** | `HeroUploadSection.jsx:12` | The dashboard's business-name header is Cirka, not SF Pro. |
| 6 | `CatalogueSection` heading is **larger on mobile than desktop** (`text-4xl md:text-3xl`) | `CatalogueSection.jsx:11` | Likely a typo; reproduce as-is unless told otherwise. |
| 7 | **StatCard chevron** uses `fill="black"` attribute + inert `className="text-gray-400"` | `StatCard.jsx:9,11` | Chevron renders black, not grey. |
| 8 | **Wholesaler mobile bottom nav has no `env(safe-area-inset-bottom)`** | `Sidebar.jsx:420` | Overlaps the home indicator on notched devices. |
| 9 | **Manrope is downloaded twice** (7 local TTFs + Google variable) | `globals.css`, `app/layout.jsx:17` | Bundle only the local TTFs on iOS. |
| 10 | `Cirka-Variable.woff2` is on disk but referenced nowhere | `public/fonts/TTF/` | Do not ship. |
| 11 | **`Switzer` font is loaded and tokenised but used zero times** | `globals.css:92,186` | Do not port. |
| 12 | **`SF Pro.woff2` (815 KB) is self-hosted** | `public/fonts/TTF/SF Pro.woff2` | Replace with the iOS system font. Do not bundle. |
| 13 | `Inter`, `DM Sans`, `Playfair Display` declared but never loaded | 6 sites (see §2.7) | Choose explicit iOS substitutes. |
| 14 | **Admin PWA manifest declares `orientation: "landscape"`** | `app/manifest.js:18` | Contradicts the mobile-first bottom nav; likely a bug. |
| 15 | Breakpoint inconsistency at exactly 768px (`≤768` vs `≤767` vs `md:≥768`) | multiple modules | Pick one split for iOS. |
| 16 | `prefers-reduced-motion` covers only 8 of 20+ animations | `globals.css:377,484` | iOS should honour Reduce Motion for all of them. |
| 17 | `.dateBadge` styled only inside a media query, no base rule | `referralManager.module.css:158` | UNEXTRACTABLE: desktop appearance not defined in CSS. |

---

## 15. UNEXTRACTABLE items

- **UNEXTRACTABLE: `.dateBadge` desktop styling** — `referralManager.module.css` defines it only inside `@media (max-width: 768px)`. No base rule exists in any stylesheet; whatever it looks like above 768px comes from inline JSX styles in `components/wholesaler/referral/` (not in scope for this pass) or nothing at all.
- **UNEXTRACTABLE: exact rendered glyphs for `Inter` / `DM Sans` / `Playfair Display`** — no font files and no CDN link exist for these, so their rendered appearance depends entirely on the viewing device's generic-family default. Metrics cannot be derived from the repo.
- **UNEXTRACTABLE: the built CSS for `shadow-inner`** — the `.next/` build output was not parsed; whether Tailwind v4 emits anything for this class must be confirmed by inspecting a fresh build.
- **UNEXTRACTABLE: bootstrap-icons glyph inventory** — `app/layout.jsx:80` loads `https://cdn.jsdelivr.net/npm/bootstrap-icons@1.13.1/font/bootstrap-icons.min.css` from a CDN. Which `bi-*` icons are used, and their glyph shapes, are not derivable from the local repo; they must be enumerated from JSX (`class="bi bi-…"`) and matched to SF Symbols separately.
- **UNEXTRACTABLE: raster/vector assets hosted on Cloudinary** — all sidebar nav icons, the auth hero image, the invite background and several stat icons live at `res.cloudinary.com/dcs0vuzwg/...`. Their exact artwork must be downloaded; only the URLs are recorded here.
