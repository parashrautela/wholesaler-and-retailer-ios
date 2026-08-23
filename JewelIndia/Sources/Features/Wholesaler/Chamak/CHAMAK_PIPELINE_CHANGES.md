# Chamak Pipeline — Change Tracker

Living doc for the chamak fix effort. We go phase by phase (matching the user's
mental model of the flow, not the raw 4-stage backend split). Frontend changes
land first; each phase also records what it assumes/needs from the backend
(external AI pipeline service — **not** in this repo, hit via
`AppConfig.aiPipelineURL`). Once all frontend phases are sorted, we take this
doc to the backend as the spec of what it needs to deliver.

Status legend: `[ ]` planned · `[~]` in progress · `[x]` done · `[B]` blocked on backend

---

## Phase 1 — Image Input → Analysis Report → Sliders → Notes

**User-facing goal:** wholesaler uploads/picks two designs (one strong, one
that needs upgrading), sees a readable analysis of what the AI found, tunes
sliders that are genuinely tied to the images they fed in, and can leave a
free-text note before fusing.

### Frontend changes (this repo)

- [x] **Analysis report section** — `analysisReportSection` in
      `ChamakSliderFormView.swift`, placed between `comparisonHeader` and
      `contentFlagBanner`. Shows detected jewelry type
      (`analysis.jewelryType`) and readable strengths lists for each image
      (`analysis.image1Strengths`, `analysis.image2Strengths`) via a shared
      `reportColumn(title:items:color:)` helper. These fields already arrive
      from the backend today but were previously never rendered as text —
      only fed into slider labels.
- [x] **Defensive slider pairing** — `Stage1Analysis.dynamicAttributes` in
      `ChamakModels.swift`. No longer pairs `image1Strengths[idx]` with
      `image2Weaknesses[idx]` purely by array index with a fake
      `"Alternative styling"` fallback. Now only emits a slider for indices
      where both arrays have a real entry
      (`idx < min(image1Strengths.count, image2Weaknesses.count)`). A new
      `unmatchedImage1Strengths` property captures any leftover strengths,
      and the report section renders them under an "Other Design 1
      Highlights" column instead of dropping them — extends the original
      plan (which only said "surface in the report") with an explicit,
      separately-labeled column.

  **Status note:** found already implemented in the working tree
  (uncommitted) partway through this session — not yet confirmed who/what
  applied it. Verified via `git diff` to match this spec, and now also
  build-verified (`xcodebuild`, 0 errors, no new warnings) — still pending
  explicit user confirmation of authorship before considering it closed.

### Backend contract this phase assumes (external AI pipeline — not in this repo)

- `Stage1Analysis` already returns `jewelry_type`, `image1_strengths`,
  `image1_weaknesses`, `image2_strengths`, `image2_weaknesses` as
  plain string arrays — no backend change needed for the report itself.
- **Open ask for backend, not yet implemented anywhere:** `image1_strengths`
  and `image2_weaknesses` should ideally be returned as equal-length,
  index-aligned arrays (same attribute at the same index on both sides), or
  restructured as a single list of `{attribute, image1_value, image2_value}`
  objects so alignment isn't assumed by array position. Until that lands,
  the frontend fix above is a mitigation (hides broken labels), not a root
  fix for misaligned data.

### Notes / open questions

- Weaknesses are read but intentionally *not* shown in the report (kept
  positive/actionable) — sliders already surface the weakness side. Revisit
  if the user wants a fuller report.

---

## Backlog — closed out (build-verified)

Came up while auditing stage 1 image input; deferred out of Phase 1's
initial scope, now implemented on explicit go-ahead:

- [x] **Silent failure on image decode/upload** — `ChamakCatalogPickerView.swift`,
      both `PhotosPickerItem` `.onChange` handlers. A failed
      `loadTransferable` or `ImageNormalizer.jpeg` now sets `showPickError`
      and shows an alert ("Photo Couldn't Be Loaded") instead of silently
      leaving the slot empty.
- [x] **Duplicate-image guard** — `ChamakDesignItem` gained a `contentHash`
      (SHA256 of the normalized bytes, `ChamakModels.swift`), set only for
      direct uploads (catalogue picks already have a reliable `product.id`).
      `canStartAnalysis` now blocks when both slots are custom uploads with
      matching hashes — two uploads of the literal same photo used to pass
      silently because random UUIDs made `id` always differ.
- [x] **Partial-upload recovery** — `reviseAndRetry()` now routes to
      `.catalogPicker` (not always `.sliderForm`) when `stage1AnalysisJSON`
      doesn't exist yet, i.e. the failure happened during upload/analysis
      rather than generation. Selected designs are left untouched either
      way, so `startVisionAnalysis`'s existing "skip upload if `imageURL`
      is already set" check means only the slot that actually failed gets
      re-uploaded on retry.

  **Bug found and fixed while doing this**: `reviseAndRetry()` (added in
  Phase 2) unconditionally sent every `.failed` state to `.sliderForm`.
  That's correct for a stage 3/4 (generation) failure, but `.failed` is
  also reachable from a stage 1 (upload/analysis) failure — where no
  analysis exists yet, so the slider form would have rendered with no real
  data. Fixed as part of this same change (see above).
- **No feedback on denied Photos permission** — investigated, not changed:
  the app uses SwiftUI's `PhotosPicker`, which runs out-of-process and
  doesn't require photo library permission for basic selection — there
  isn't actually a "permission denied" state to surface here. Leaving this
  off rather than building handling for a state that can't occur.
- [x] **Quota gate before stage 1 analysis** — `startVisionAnalysis` now
      checks quota and shows the same "Daily AI Quota Reached" alert
      (`showQuotaAlert`) used elsewhere, before spending an analysis call.
      Needed its own `.alert` modifier added to `ChamakCatalogPickerView.swift`
      too — `showQuotaAlert` previously only had a listener on the result
      screen, so setting it while still on the picker would have done
      nothing visible.

---

## Phase 2 — Generate → Result (prompt compilation + fusion)

**User-facing goal (in the wholesaler's own words):** "if I have uploaded
the image and given my preference from the toggle and given the additional
prompt too, what I'm looking forward to is a good image which I can use as
a reference which should be having all the things which I mention with
respect to the toggle values which I have selected." On the backend: the
two images, the toggle (slider) values, and the wholesaler's free-text
prompt should club up into one unique compiled prompt — sliders as the
primary/structural "base" instructions, the note as a secondary "flavor"
add-on that doesn't override the base.

### Frontend changes (this repo) — done, build-verified

- [x] **Self-describing slider payload** — new `WeightedAttribute` struct
      and `WholesalerFormInput.attributeContext: [WeightedAttribute]` in
      `ChamakModels.swift`. Built by `ChamakViewModel.buildAttributeContext()`
      and sent alongside the existing `sliderWeights` dict (additive, not a
      replacement — the old `attr_0`-style dict still goes out unchanged, so
      nothing breaks if the backend hasn't been updated yet). Each entry
      pairs a weight with the actual attribute name and both images'
      feature text, so the backend doesn't have to re-derive which
      attribute `attr_0` means from `stage1_analysis_json` independently —
      removes the risk of client/backend index drift silently corrupting
      the compiled prompt.
- [x] **Adjust & Retry** — `ChamakViewModel.reviseAndRetry()`, a pure
      navigation call (`step = .sliderForm`, no network, no quota spent)
      wired to the result screen's former "Regenerate" button
      (`ChamakResultView.swift`). Previously that button silently resubmitted
      the exact same sliders/note with no way to change them first
      (`vm.regenerate`, still present and unchanged — just no longer the
      button's action). Now the wholesaler lands back on the slider form
      pre-filled with their last weights/note and can actually adjust
      before retrying.
- [x] **Full traceability card** — `promptInfoCard` in `ChamakResultView.swift`
      expanded beyond just a 4-line-truncated compiled prompt (which would've
      cut off inside the ROLE section of the elaborated template below) into
      a complete record per generation: Generation ID, created timestamp,
      toggle values used (rendered as "`{attribute}`: `{weight}`% toward
      Design 1/2", from `attributeContext`), the additional note, and the
      full untruncated compiled prompt. Source images are already shown
      separately above it via the existing `sourceDesignsRow`. All of this
      reads data that was already being saved — no backend change needed for
      the UI side, only for `compiled_prompt_text` itself to start actually
      being populated.

### Backend spec (external AI pipeline — not in this repo)

**Where things live**, per the wholesaler's own proposed split:

| Piece | Lives in | Notes |
|---|---|---|
| Base prompt template (fixed skeleton, below) | **Railway env var** `CHAMAK_BASE_PROMPT_TEMPLATE` | Edited directly in Railway's dashboard; no code change to reword it. Trade-off accepted knowingly: editing it restarts the service, no built-in version history — fine as a starting point, a DB-backed version table is a possible later upgrade, not a redo. |
| Slider weights + attribute context + note | **Supabase**, `chamak_generations.wholesaler_form_json` | Already implemented (this repo, above) — no schema change needed, it's the same JSONB column, just richer content. |
| Final assembled prompt (after filling in the template) | **Supabase**, `chamak_generations.compiled_prompt_text` | **This column already exists and is already unused** (`ChamakModels.swift`, `SUPABASE_CHAMAK_MIGRATION.sql`) — write the fully-assembled prompt here *before* calling the image model, not after. Gives a permanent per-generation audit trail ("what exact prompt produced this image"). The result screen already has a card built to display this (`ChamakResultView.swift` → `promptInfoCard`) — populating the column makes it show up in-app with zero additional frontend work. |
| Image generation | External call to Nano Banana (Gemini 2.5 Flash Image), fed the compiled prompt + both source images | Not in this repo; output saved to `output_image_url`. |

**Base prompt template** (the literal `CHAMAK_BASE_PROMPT_TEMPLATE` value — `{{ }}` is a placeholder marker, adapt to whatever templating the backend uses). Elaborated beyond the minimal first draft to explicitly lock down real jewelry-generation failure modes (metal-color drift, floating/extra gemstones, warped filigree, wrong component count for the category, hallucinated hallmark stamps) rather than leaving them to chance:

```
ROLE
You are a master jewelry designer and CAD visualization expert AI,
specializing in photorealistic product photography. You are given two
reference photographs of an existing {{jewelry_type}} — Image 1 ("Strengths"
reference) and Image 2 ("Upgrade" reference) — supplied by a jewelry
wholesaler.

TASK
Generate ONE new, entirely original {{jewelry_type}} that could physically
exist and be fabricated by a jeweler — synthesizing specific design
elements from Image 1 and Image 2 exactly as weighted in the FEATURE BLEND
section below. This is not a collage, not a side-by-side composite, and
not a simple crossfade or overlay of the two photos — it is a single,
structurally coherent piece of jewelry that draws its design DNA from
both references.

CATEGORY LOCK
The output must remain a {{jewelry_type}} in form and function — correct
wearable proportions, correct component count (e.g. a matched pair if
earrings, a single continuous body if a bangle, a clasp and complete chain
run if a necklace), and physically plausible construction throughout.

{{type_mismatch_clause}}

{{near_identical_clause}}

FEATURE BLEND (apply first — this defines the structure; resolve overall
silhouette and proportions before surface detail, and surface detail
before fine micro-detail):
{{feature_blend_lines}}

MATERIAL & CRAFTSMANSHIP FIDELITY
- Keep metal color, finish, and tone consistent with the blended source
  material(s) — do not invent a different metal (e.g. do not turn yellow
  gold into white gold or silver) unless a feature line above explicitly
  calls for it.
- Gemstone count, cut, and placement must be deliberate and symmetric
  where the design calls for symmetry — no floating, disconnected, or
  extra/missing stones, no impossible settings.
- Filigree, engraving, and repoussé motifs (where present) must be sharp,
  continuous, and structurally attached — no melted, warped, or
  discontinuous metalwork.
- Any clasps, hinges, posts, or fastenings must be anatomically correct
  and consistent with how a real {{jewelry_type}} would be worn.

STYLING NOTE (apply only after the FEATURE BLEND above — this adds flavor,
it does not override structure; if any part of this note conflicts with
the feature blend, the feature blend wins and only the compatible parts of
the note should be applied):
{{styling_note_section}}

PHOTOGRAPHY & OUTPUT SPEC
- Single product photograph, plain seamless neutral background (soft
  light gray or white), no props, no hands, no mannequins, no busts.
- No price tags, no text, no watermarks, no logos, no hallmark stamps
  unless explicitly part of the design itself.
- Soft, even studio lighting with realistic material-accurate highlights
  and shadows (metal specular highlights, gemstone brilliance/fire as
  appropriate to the stone type) — no blown-out highlights, no harsh
  unmotivated shadows.
- Sharp focus across the entire piece, front-facing or three-quarter
  product angle, centered composition, accurate true-to-life color.
- The final image must be indistinguishable from a real photograph of a
  physically fabricable, sellable {{jewelry_type}} — ready for immediate
  use in a wholesale catalogue.

The final image must be a single coherent, wearable, physically plausible
{{jewelry_type}} — not a collage, not a duplicate of either original, and
not an average/blur of both.
```

Design notes on this template:
- The "no price tags/text/watermarks" line isn't generic boilerplate — it's
  a direct response to a real test image (raw inventory photo with a
  weight-spec tag in frame) that should never leak into a finished fused
  result.
- `{{type_mismatch_clause}}` (inserted only when `stage1_analysis_json.type_mismatch == true`):
  *"Image 1 and Image 2 depict different jewelry categories. Use Image 1's
  silhouette and category as the base form; treat Image 2 purely as a
  source of decorative motifs, materials, or stone-setting style to graft
  onto that silhouette — do not attempt to merge two incompatible physical
  structures (e.g. do not turn a ring into a pendant)."* — this must match
  what the slider screen's warning banner already tells the wholesaler
  (`ChamakSliderFormView.swift` → `warningBanners`, *"The AI will
  synthesize motifs onto the primary silhouette"*). If the real compiled
  prompt doesn't say this, the UI is promising behavior the pipeline
  doesn't deliver.
- `{{near_identical_clause}}` (new — inserted only when
  `stage1_analysis_json.near_identical == true`, the counterpart flag to
  `type_mismatch` that the first draft of this template left unhandled):
  *"Image 1 and Image 2 are very similar in design. Rather than producing a
  near-duplicate of either, use the FEATURE BLEND weights below to
  intentionally push toward a refined, elevated variation — subtle but
  deliberate, not imperceptible."*
- Precedence is explicit, not implied: FEATURE BLEND is primary/structural,
  STYLING NOTE is explicitly secondary and must not override it.

**`{{feature_blend_lines}}`** — one line per entry in `attribute_context`,
built from its `weight` (0 = pure Image 1, 1 = pure Image 2, matching the
slider's left/right layout — Design 1 label sits left, Design 2 right):

| Weight range | Instruction |
|---|---|
| ≤ 0.15 | "Use Image 1's version almost entirely (`{image1_feature}`)." |
| 0.15–0.4 | "Favor Image 1's version (`{image1_feature}`), light influence from Image 2 (`{image2_feature}`)." |
| 0.4–0.6 | "Blend evenly between Image 1 (`{image1_feature}`) and Image 2 (`{image2_feature}`)." |
| 0.6–0.85 | "Favor Image 2's version (`{image2_feature}`), light influence from Image 1 (`{image1_feature}`)." |
| ≥ 0.85 | "Use Image 2's version almost entirely (`{image2_feature}`)." |

**`{{styling_note_section}}`** — omitted entirely if the note is empty, otherwise:
```
STYLING NOTE (apply only after the blend above — must not override the
structural blend or add elements that contradict it):
{{wholesaler_note}}
```

### Worked example

Input — 3 slider attributes plus a note:

| Attribute | Design 1 | Design 2 | Weight |
|---|---|---|---|
| Chain thickness | delicate thin chain | bold thick chain | 0.2 |
| Stone setting | bezel-set rubies | prong-set emeralds | 0.8 |
| Pendant size | small teardrop pendant | large statement pendant | 0.5 |

Note: *"Keep 22k yellow gold texture, add delicate emerald droplets at bottom edge"*

Fully assembled `compiled_prompt_text` that results (assuming no type
mismatch and not near-identical, so both conditional clauses are omitted):

```
ROLE
You are a master jewelry designer and CAD visualization expert AI,
specializing in photorealistic product photography. You are given two
reference photographs of an existing necklace — Image 1 ("Strengths"
reference) and Image 2 ("Upgrade" reference) — supplied by a jewelry
wholesaler.

TASK
Generate ONE new, entirely original necklace that could physically exist
and be fabricated by a jeweler — synthesizing specific design elements
from Image 1 and Image 2 exactly as weighted in the FEATURE BLEND section
below. This is not a collage, not a side-by-side composite, and not a
simple crossfade or overlay of the two photos — it is a single,
structurally coherent piece of jewelry that draws its design DNA from
both references.

CATEGORY LOCK
The output must remain a necklace in form and function — correct wearable
proportions, correct component count, and physically plausible
construction throughout.

FEATURE BLEND (apply first — this defines the structure; resolve overall
silhouette and proportions before surface detail, and surface detail
before fine micro-detail):
- Chain thickness: Favor Image 1's version (delicate thin chain), light influence from Image 2 (bold thick chain).
- Stone setting: Favor Image 2's version (prong-set emeralds), light influence from Image 1 (bezel-set rubies).
- Pendant size: Blend evenly between Image 1 (small teardrop pendant) and Image 2 (large statement pendant).

MATERIAL & CRAFTSMANSHIP FIDELITY
- Keep metal color, finish, and tone consistent with the blended source
  material(s) — do not invent a different metal (e.g. do not turn yellow
  gold into white gold or silver) unless a feature line above explicitly
  calls for it.
- Gemstone count, cut, and placement must be deliberate and symmetric
  where the design calls for symmetry — no floating, disconnected, or
  extra/missing stones, no impossible settings.
- Filigree, engraving, and repoussé motifs (where present) must be sharp,
  continuous, and structurally attached — no melted, warped, or
  discontinuous metalwork.
- Any clasps, hinges, posts, or fastenings must be anatomically correct
  and consistent with how a real necklace would be worn.

STYLING NOTE (apply only after the FEATURE BLEND above — this adds flavor,
it does not override structure; if any part of this note conflicts with
the feature blend, the feature blend wins and only the compatible parts of
the note should be applied):
Keep 22k yellow gold texture, add delicate emerald droplets at bottom edge

PHOTOGRAPHY & OUTPUT SPEC
- Single product photograph, plain seamless neutral background (soft
  light gray or white), no props, no hands, no mannequins, no busts.
- No price tags, no text, no watermarks, no logos, no hallmark stamps
  unless explicitly part of the design itself.
- Soft, even studio lighting with realistic material-accurate highlights
  and shadows (metal specular highlights, gemstone brilliance/fire as
  appropriate to the stone type) — no blown-out highlights, no harsh
  unmotivated shadows.
- Sharp focus across the entire piece, front-facing or three-quarter
  product angle, centered composition, accurate true-to-life color.
- The final image must be indistinguishable from a real photograph of a
  physically fabricable, sellable necklace — ready for immediate use in a
  wholesale catalogue.

The final image must be a single coherent, wearable, physically plausible
necklace — not a collage, not a duplicate of either original, and not an
average/blur of both.
```

### Notes / open questions

- Model target confirmed as Nano Banana (Gemini 2.5 Flash Image) — template
  wording above is a strong starting point but may need light,
  model-specific tuning once actually wired up on the backend.
- `sliderWeights` (the old opaque `attr_0`-keyed dict) is still sent
  alongside `attributeContext` for now — safe to drop once the backend
  confirms it's reading `attributeContext` instead.
- Note duplication (`wholesaler_form_json.note` vs. top-level `note_text`,
  both set from the same value today) was raised and deliberately **not**
  changed — plausibly intentional denormalization (audit blob vs. flat
  queryable column). Open question for whoever owns the backend: which one
  does prompt compilation actually read? Not a client-side fix either way.

---

## Phase 3 — Verify the actual Nano Banana call, output count, output resolution

**Goal:** confirm the two source images + `compiled_prompt_text` are actually
reaching Nano Banana correctly (nothing observed working end-to-end yet —
see diagnosis checklist below), then add two new Chamak-only knobs: how many
output images per generation, and what resolution they come out at.

### Diagnosis checklist (backend — not in this repo, not yet verified)

No source access to the Railway service from this session, so this is a
checklist to verify against the real code/logs, not a confirmed diagnosis:

1. **Images must be sent as actual bytes, not URL strings** — Nano Banana
   doesn't fetch arbitrary external URLs; the backend must download each
   image from its Supabase Storage URL first, then send the bytes inline
   (or via the model's own file-upload mechanism if one exists).
2. **Image order must match what the compiled prompt calls "Image 1" and
   "Image 2"** — the template is full of position-dependent instructions
   ("favor Image 2's version..."); swapped order silently misapplies every
   one of them.
3. **The request must explicitly ask for image output**, not text — if the
   response-mode config is missing/wrong, the call can "succeed" with a
   text description instead of a picture.
4. **The response must be parsed and re-uploaded** to the `chamak-outputs`
   bucket to produce `output_image_url` — if this silently fails, status
   shows `done` but `output_image_url` stays empty and the result screen's
   image card hangs on its loading placeholder forever (a real gap
   identified earlier in this doc).
5. A valid API key for the model is configured in Railway.

Next step to actually verify (not yet done): trigger one real generation
from the app, then check Railway's logs for that request, and/or run the
Phase 2 verification SELECT query against `chamak_generations` to see how
far the row actually got (`compiled_prompt_text` populated? `status`?
`output_image_url` populated?).

### New Railway variables

| Variable | Value today | Purpose |
|---|---|---|
| `CHAMAK_OUTPUT_COUNT` | `1` | How many output images per generation. No native "generate N candidates in one call" parameter was found for this model, so the backend should implement this as **N separate calls** with the same compiled prompt + same 2 source images, not a single multi-candidate request. |
| `CHAMAK_OUTPUT_RESOLUTION` | current default (observed ~720p or lower today) | Requested output resolution/quality for Chamak's generation call specifically. |

Explicitly decided **not** to add a model-selection variable — stays on
whatever model the pipeline already uses today, same as Stage 1. One
consequence worth having on record: this caps the *ceiling* `CHAMAK_OUTPUT_RESOLUTION`
can actually reach at whatever that existing model natively supports —
the variable controls resolution up to that ceiling, it doesn't guarantee
a specific target resolution regardless of value.

**Scoping risk for `CHAMAK_OUTPUT_RESOLUTION` being "Chamak only":** if the
backend's Chamak generation call shares a helper function with the other
`/process` (raw → catalogue photo) pipeline, this must be passed in as an
explicit override argument at the Chamak call site — changing that shared
function's default/global resolution would silently affect `/process` too.

**Schema implication for `CHAMAK_OUTPUT_COUNT` > 1:** `chamak_generations.output_image_url`
is a single `TEXT` column today. Supporting multiple outputs needs a new,
additive column (e.g. `output_image_urls TEXT[]`) — keep writing the first
result to the existing `output_image_url` column too, so nothing currently
reading it breaks. Actually building a "pick your favorite of N" picker in
the app is a separate frontend step, not scheduled here.

**Cost compounds, not adds:** raising output count and resolution together
multiplies, not adds — e.g. going from 1 output at today's resolution to 3
outputs at a much higher resolution could be roughly a 6x per-generation
cost jump. Worth deciding whether that's still 1 wholesaler credit or
should scale with it before flipping both variables at once.
