# Chamak — Set Creation Mode (spec, not yet built)

Companion to `CHAMAK_PIPELINE_CHANGES.md`. Same convention: frontend changes
land in this repo, the backend half is a spec to hand to the external AI
pipeline service on Railway (`AppConfig.aiPipelineURL`).

Status legend: `[ ]` planned · `[~]` in progress · `[x]` done · `[B]` blocked on backend

---

## What this mode is

The wholesaler uploads **two photographs of two different, real pieces** from
their own inventory — e.g. a temple necklace and a pair of jhumka drop
earrings. The pipeline returns **one photorealistic set photograph** in which
both pieces appear together, professionally staged, as a jeweler would display
a matched set in a showroom or catalogue spread.

Both pieces are reproduced **exactly**. Nothing is blended, redesigned, or
harmonized.

## How it differs from Chamak Fusion (existing mode)

This is the inverse operation, and several of Fusion's assumptions actively
break it:

| | Fusion (built) | Set Creation (this doc) |
|---|---|---|
| Input | Two designs, same category | Two designs, **different** categories, deliberately |
| Output | One **new** piece with blended DNA | **Both** original pieces, one staged scene |
| `type_mismatch` | Warns the user, degrades to motif-grafting | Is the **expected** input |
| Stage 2 (middle screen) | Per-attribute blend sliders | Backdrop preset + note. Sliders are meaningless here |
| Background | Template forbids props: *"no props, no hands, no mannequins, no busts"* | Template **requires** them — velvet bust, earring stands, backdrop |
| Number of pieces in frame | 1 | Exactly 2 |

Because of the last two rows, the Fusion base prompt cannot be reused or
parameterised into this — it needs its own template.

## Product decisions taken (confirmed with the wholesaler)

1. **Preserve both pieces exactly, even when they clash.** The AI must not
   restyle one piece to match the other. If a wholesaler pairs a plain modern
   necklace with a heavy temple jhumka, that mismatch ships as-is — it's the
   wholesaler's commercial decision, not the pipeline's to correct. This is
   the single most important constraint in the whole mode.
2. **One combined set shot per generation.** No multi-image lookbook, no
   alternate angles. Keeps the existing single `output_image_url` column, so
   no array-column schema change is needed.
3. **A few preset backdrops**, plus the existing free-text note. Not a fixed
   house style, not a full matrix of independent controls.

---

## Backend spec (external AI pipeline — not in this repo)

### Routing

Reuse the existing `/api/chamak/analyze` and `/api/chamak/generate` endpoints.
The backend branches on the new `mode` column read off the `chamak_generations`
row, rather than the client hitting different routes. Keeps credit checks,
idempotency handling and the 402 contract in exactly one place.

### Stage 1 for `set_creation` — lighter than Fusion's

Fusion's stage 1 derives strengths/weaknesses arrays to build sliders. This
mode has no sliders, so that work is wasted spend. Stage 1 here needs only:

- `content_flag` — unchanged, same enum, same blocking behaviour.
- `image1_type` / `image2_type` — **new, per-image**. Today `Stage1Analysis`
  returns a single `jewelry_type` for both images, which is meaningless when
  the two images are deliberately different categories. Return these as
  additional fields alongside the existing ones so the Fusion decode path is
  untouched; the client decodes them as optional.
- `near_identical` — still returned. Not a hard block (per decision 1, it's
  the wholesaler's call), but the client shows a soft advisory: staging the
  same piece twice as a "set" is almost certainly a mistake.

`image1_strengths` / `image1_weaknesses` / `image2_strengths` /
`image2_weaknesses` should be skipped entirely for this mode.

### New Railway env vars

| Variable | Purpose |
|---|---|
| `CHAMAK_SET_PROMPT_TEMPLATE` | The base template below. Same rationale as `CHAMAK_BASE_PROMPT_TEMPLATE` — editable in the Railway dashboard without a code deploy. |
| `CHAMAK_SET_BACKDROP_SCENES` | JSON map of backdrop preset id → scene prose (table below). Kept server-side deliberately: the client sends only a stable id like `velvet_bust`, so the wording can be retuned without shipping an app update. |

### `CHAMAK_SET_PROMPT_TEMPLATE`

```
ROLE
You are a luxury jewelry catalogue photographer and set stylist AI. You are
given two reference photographs supplied by a jewelry wholesaler: Image 1 —
a {{image1_type}}, and Image 2 — a {{image2_type}}. These are two distinct,
real, physical pieces from the wholesaler's own inventory.

TASK
Produce ONE photorealistic set photograph in which BOTH pieces
appear together, staged as a single coordinated presentation, exactly as a
jeweler would display a set in a showroom or a catalogue spread.

IDENTITY LOCK — HIGHEST-PRIORITY CONSTRAINT, OVERRIDES EVERYTHING BELOW
Reproduce each piece EXACTLY as it appears in its reference photograph.
- Do not redesign, upgrade, simplify, embellish, or "improve" either piece.
- Do not merge, fuse, or blend the two pieces into a single object.
- Do not make the two pieces match each other. If they differ in style,
  metal tone, stone color, motif language, or era, that difference must be
  preserved faithfully. The wholesaler has deliberately chosen these two
  specific pieces; a mismatch between them is intentional and is NOT an
  error for you to correct.
- Preserve exactly: silhouette, component count, motif and engraving
  detail, gemstone color/cut/count/placement, bead and pearl drops, metal
  color and finish, and the internal proportions of each piece.
- Do not add any third piece of jewelry — no ring, bangle, maang tikka,
  nose ring, bracelet or additional chain — to "complete" the set. Exactly
  the two given pieces appear in frame, and nothing else.
- If a piece is a matched pair (e.g. earrings), render both members of the
  pair, identical to each other and identical to the reference.

STAGING
{{backdrop_scene}}

- Present the {{image1_type}} as the hero element and the {{image2_type}}
  as the secondary element, in a balanced, intentional composition — NOT a
  side-by-side collage, NOT a grid, NOT two separate photographs pasted
  together. One continuous scene, one consistent light source, one shared
  perspective and one shared depth of field across both pieces.
- Scale the two pieces relative to each other at true real-world
  proportion. Do not enlarge the smaller piece to fill space.
- Both pieces must be fully visible and unobstructed — nothing important
  cropped out of frame, and nothing hidden behind a prop.
- Display props are permitted and expected where the staging calls for
  them: velvet busts, earring stands, trays, fabric, stone surfaces. Human
  models are not — no hands, no necks, no faces, no mannequin heads with
  facial features.

PHOTOGRAPHY & OUTPUT SPEC
- Single photograph, portrait orientation, catalogue-ready.
- Soft, even, motivated studio lighting with material-accurate specular
  highlights on the metal and correct brilliance and fire in the
  gemstones. The backdrop must not cast a color tint that shifts the
  apparent metal color or stone color of either piece away from its
  reference.
- Sharp focus on both pieces. Background falloff should be gentle and
  photographic, never masking detail on the jewelry itself.
- No price tags, no weight-spec tags, no text, no watermarks, no logos, no
  hallmark stamps unless already present in the reference photograph.
- True-to-life color throughout.

{{styling_note_section}}

The final image must read as one real photograph of these two exact pieces,
professionally staged together — immediately usable in a wholesale catalogue.
```

### `{{backdrop_scene}}` — preset id to scene prose

Four presets. The first two are modelled directly on reference images the
wholesaler supplied.

| Preset id | Client label | Scene prose |
|---|---|---|
| `velvet_bust` | Velvet Bust | "Display the necklace on a deep teal velvet display bust. Place the earrings on matching small velvet earring stands flanking it at the base. Behind, a softly out-of-focus backdrop of draped maroon silk with warm gold bokeh highlights. Rich, warm, showroom-luxury mood." |
| `dark_slate` | Dark Slate | "Lay both pieces on a dark charcoal slate stone surface with visible natural texture and subtly chipped edges. Dramatic directional side lighting, deep shadows, cool moody contrast against the warm metal." |
| `festive` | Festive | "Stage against draped maroon and gold silk with warm bokeh lights and marigold accents just out of focus. Festive Indian wedding-season mood, warm golden-hour tone." |
| `clean_studio` | Clean Studio | "Place both pieces on a seamless soft light-grey studio sweep with a gentle contact shadow beneath each. Neutral, even, high-key lighting. Clean, minimal, e-commerce catalogue neutral." |

### `{{styling_note_section}}`

Omitted entirely when the note is empty. Otherwise:

```
STYLING NOTE (applies to STAGING ONLY — backdrop, arrangement, lighting and
mood. It must NOT modify either piece of jewelry. If any part of this note
asks for a change to the design, metal, stones, or construction of either
piece, ignore that part entirely and apply only the staging-related
remainder):
{{wholesaler_note}}
```

This precedence line is deliberately stricter than Fusion's equivalent. In
Fusion the note is secondary to the blend but may still shape the piece; here
it must never touch the pieces at all, or it defeats decision 1. A wholesaler
writing *"make the earrings gold instead of silver"* must get silver earrings
and a restyled backdrop.

### `compiled_prompt_text`

Written to the same column, before the image model is called, exactly as
specified for Fusion. `ChamakResultView`'s traceability card already renders
it — no extra frontend work to surface it.

### Credits

New feature key `chamak.set_creation`, priced in the same credit-costs
table the existing keys come from. `chamak.reroll` is reused unchanged for
re-rolls.

---

## Database migration

Additive only, no backfill risk — every existing row is a fusion.

```sql
ALTER TABLE public.chamak_generations
  ADD COLUMN IF NOT EXISTS mode TEXT NOT NULL DEFAULT 'fusion'
  CHECK (mode IN ('fusion', 'set_creation'));

ALTER TABLE public.chamak_generations
  ADD COLUMN IF NOT EXISTS set_backdrop TEXT;
```

`set_backdrop` holds the preset id, null for fusion rows. Kept as its own
column rather than buried in `wholesaler_form_json` so set generations stay
queryable by backdrop — useful for spotting which presets actually get used.

---

## Frontend changes (this repo)

### New files

- [ ] **`ChamakSetStylingView.swift`** — replaces the slider screen for this
      mode. A 2x2 grid of backdrop preset cards (label + small visual swatch),
      the existing note field, the credit-cost banner, and a Generate button.
      Structurally a much simpler `ChamakSliderFormView`.

### Modified files

- [ ] **`ChamakModels.swift`**
      - `ChamakMode: String, Codable` — `fusion` / `setCreation`.
      - `SetBackdrop: String, CaseIterable, Codable` — the four preset ids
        plus client-side display labels.
      - `Stage1Analysis` — add optional `image1Type` / `image2Type`. Optional
        so Fusion responses, which won't carry them, still decode.
      - `ChamakGeneration` — add `mode` and `setBackdrop`. `mode` decoded with
        a `fusion` fallback so pre-migration rows in the gallery don't fail to
        decode.
      - `SetCreationInput: Codable` — `{ backdrop, note }`, written to
        `wholesaler_form_json`.
- [ ] **`ChamakViewModel.swift`**
      - `var mode: ChamakMode`, `var selectedBackdrop: SetBackdrop`.
      - New `Step` case `.setStyling`.
      - `startPolling`'s `.awaitingInput` branch routes to `.setStyling` when
        mode is `setCreation`, `.sliderForm` otherwise. Skips
        `setupSlidersFromAnalysis` in set mode.
      - `submitSetAndGenerate(...)` mirroring `submitFormAndGenerate`,
        including the same idempotency-key and 402 handling.
      - `reviseAndRetry()` — its `stage1AnalysisJSON != nil` check must also
        route by mode, or a set-mode retry lands on the slider screen.
      - `resetToPicker()` — reset `selectedBackdrop`, leave `mode` alone so
        the wholesaler stays in the mode they chose.
- [ ] **`ChamakFlowCoordinator.swift`** — `.setStyling` case.
- [ ] **`ChamakCatalogPickerView.swift`** — a two-option mode selector at the
      top ("Fuse Designs" / "Set Creation"), with the header title and
      subtitle switching per mode. Slot labels change too: Fusion's
      "Strengths"/"Upgrade" framing is wrong here, where the slots are just
      "Piece 1" and "Piece 2".
- [ ] **`ChamakAPI.swift`** — `mode` in `CreateGenerationPayload`;
      `submitSetAndGenerate` writing `wholesaler_form_json` + `set_backdrop`
      and hitting `/api/chamak/generate`.
- [ ] **`ChamakGeneratingView.swift`** — the label is hardcoded
      `"Generating Fused Design 3"`, and `ChamakStatus.generating.displayLabel`
      is `"Fusing Designs"`. Both are wrong in set mode; make them
      mode-aware. `"Chamak 4-Stage AI Pipeline"` is also inaccurate here
      (set mode is effectively 3 stages — analyze, compile, render).
- [ ] **`ChamakResultView.swift`** — `promptInfoCard` reads
      `wholesalerFormJSON?.attributeContext`, which is empty in set mode, so
      the toggle-values section silently vanishes. Show the backdrop preset
      instead. `sourceDesignsRow`'s "Design 1/2" badges should read
      "Piece 1/2" in set mode.
- [ ] **`ChamakGalleryView.swift`** — the gallery now mixes both modes; needs
      a small badge per row so a fusion and a set are distinguishable at a
      glance.
- [ ] **`TreasureChestModels.swift`** — a `case "chamak.set_creation"` in
      `displayTitle`, or the ledger renders the raw key via the
      `featureKey?.capitalized` fallback.
- [ ] **`SUPABASE_CHAMAK_MIGRATION.sql`** — the two `ALTER TABLE`s above.

### Deliberately unchanged

- `canStartAnalysis`'s duplicate-image guard stays as-is. Staging the
  identical piece twice as a "set" is meaningless in either mode.
- The upload path, `ImageNormalizer` handling, quota gate, insufficient-credits
  sheet, feedback sheet and signed-URL logic are all mode-agnostic already.

---

## Risks / open items

- **The Nano Banana call has never been verified working end-to-end** (see
  Phase 3 of `CHAMAK_PIPELINE_CHANGES.md` — `compiled_prompt_text` may still
  be unpopulated, `output_image_url` may never be written). Shipping a second
  mode onto unverified plumbing means a failure can't be attributed to either
  the new mode or the existing pipeline. Verifying one real Fusion generation
  end-to-end first would remove that ambiguity cheaply.
- **Identity preservation is the hard part of this mode, and it's a model
  capability question, not a prompt question.** Image models routinely drift
  on fine repeating detail — bead counts, filigree, the exact number of
  pearl drops. The IDENTITY LOCK section is written to push hard against
  that, but it should be tested against a real pair of reference photos
  before this is promised to wholesalers as faithful-to-inventory.
- **"Add a third piece to complete the set" is a strong model prior** and the
  most likely single failure mode after identity drift. Called out explicitly
  in the template; worth checking first in test outputs.
- Portrait orientation is hardcoded in the template. If the catalogue needs
  square for listing thumbnails, that becomes a fifth env var rather than a
  template edit.
