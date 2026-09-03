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

---

## Phase 4 — Chamak 2.0: a second pipeline on OpenAI, alongside Nano Banana

**Goal:** keep the existing pipeline as **Chamak 1.0** (Nano Banana via
kie.ai) and add **Chamak 2.0** (OpenAI image API) as a parallel option,
surfaced as two cards on the wholesaler home screen. Prompt-compilation
logic stays byte-identical between them — the only difference is which
image model renders the result.

Nothing in this phase is implemented. Backend is a handoff spec (not in
this repo); iOS is a plan pending explicit go-ahead.

### Do this FIRST — it may make Phase 4 unnecessary

The motivation for Chamak 2.0 is "Chamak 1.0 only seems to reference
Design 1." **That premise is unverified**, and there's a cheaper
explanation worth eliminating before building a second pipeline:

- kie.ai's Nano Banana **does** accept multiple images (`image_urls` is an
  array) — so "the vendor can't do two images" is not established.
- OpenAI's own prompting guidance for multi-image edits says to reference
  inputs **by index** in the prompt text ("put the bird from Image 1 on
  the elephant in Image 2"). Our compiled prompt says "Design 1"/"Design
  2" — words that mean nothing positionally to the model, which sees an
  ordered array of unlabeled images.
- **Test:** edit the existing 1.0 prompt so the feature-blend lines
  explicitly say *Image 1* and *Image 2* (matching array order), re-run,
  and see whether Design 2 finally shows up. One prompt edit, no new
  infrastructure.

Also still-untested from Phase 3: whether the backend actually sends two
URLs at all, and whether image *ordering* biases the result (an "edit"
endpoint may treat image 1 as the canvas). Rule those out before
concluding the model is at fault.

### Verified capability findings (Aug 2026 docs; no live API calls made)

- **Multi-image input: supported.** `POST https://api.openai.com/v1/images/edits`
  takes an array of reference images, `maxItems: 16` per the OpenAPI
  spec. OpenAI's canonical example composes four references into one
  output. Caveat: multi-image *consumption* is shown by example, not
  guaranteed by spec — it does not promise equal weighting.
- **2K output: only on `gpt-image-2`.** Constraints: both edges multiples
  of 16, aspect ratio ≤ 3:1, max edge 3840px, total pixels 655,360–8,294,400.
  `2048x2048` is legal but sits in OpenAI's **"experimental"** band
  (>2,560×1,440px). Safer non-experimental picks: `1536x1536` or
  `2048x1152`. On `gpt-image-1` / `1.5` / `mini` the ceiling is a 1536px
  long edge — 2K genuinely unavailable, and those models retire Oct–Dec
  2026. **Pin `gpt-image-2` explicitly**; the API default is `gpt-image-1.5`.
- **Cost/latency regression is real.** gpt-image-2 `high` at 1024² ≈
  **$0.21/image** + ~$0.016 for two refs; 2048² high ≈ **$0.43**. Median
  latency ~33s. That is roughly **5–10× the cost and 3–6× the latency** of
  kie.ai Nano Banana (~$0.03–0.06). Price 2.0's credits accordingly.

### Architecture

One shared prompt compiler, two renderers, selected by a column on the row:

```
iOS card tap → INSERT chamak_generations(pipeline='chamak_1'|'chamak_2')
  → POST /api/chamak/analyze {generation_id}    [Stage 1 vision — shared, unchanged]
  → sliders + note → row UPDATE
  → POST /api/chamak/generate {generation_id}
       └─ backend SELECTs the row
          ├─ compile_prompt(row)        ← IDENTICAL code path for both
          └─ switch row.pipeline
               ├─ 'chamak_1' → kie.ai Nano Banana (existing)
               └─ 'chamak_2' → OpenAI /v1/images/edits
          → upload result to `chamak-outputs`
          → UPDATE output_image_url, compiled_prompt_text, model_id, status='done'
```

**The backend learns the model by reading `pipeline` off the row it
already loads by `generation_id`** — *not* from a new field in the POST
body. The row is already the channel for form JSON and note text, so
keeping it there means quota/idempotency logic stays in one place,
`regenerate` can't silently run a different engine over the other
engine's Stage 1 analysis, and the gallery can attribute every image.
**HTTP bodies stay exactly `{"generation_id": "<uuid>"}` — zero
networking-layer changes in iOS.**

### Database

```sql
ALTER TABLE public.chamak_generations
  ADD COLUMN IF NOT EXISTS pipeline TEXT NOT NULL DEFAULT 'chamak_1';

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conrelid = 'public.chamak_generations'::regclass
                   AND conname  = 'chamak_generations_pipeline_check') THEN
    ALTER TABLE public.chamak_generations
      ADD CONSTRAINT chamak_generations_pipeline_check
      CHECK (pipeline IN ('chamak_1','chamak_2'));
  END IF;
END $$;

ALTER TABLE public.chamak_generations
  ADD COLUMN IF NOT EXISTS model_id TEXT;   -- exact model actually invoked; no CHECK

CREATE INDEX IF NOT EXISTS idx_chamak_generations_pipeline
  ON public.chamak_generations(pipeline, created_at DESC);

NOTIFY pgrst, 'reload schema';
```

The CHECK is separate on purpose: `ADD COLUMN IF NOT EXISTS` skips its
*entire* clause on re-run, so an inline CHECK would silently never land
on a partially-migrated table.

**Non-breaking for both clients.** `NOT NULL DEFAULT` means the existing
iOS insert and the web dashboard's differently-named insert both keep
working untouched and backfill as `'chamak_1'`. `ChamakGeneration` uses
explicit `CodingKeys`, and Swift's synthesized `init(from:)` ignores
unknown JSON keys — already-shipped builds decode the new columns fine.
RLS is table-level, so both columns inherit it.

Rejected alternatives: **don't** reuse `prompt_version` as the
discriminator (it's client-hardcoded, user-visible in the gallery and
result screens, and conflates prompt revision with engine); **don't** name
it `mode` (claimed by `CHAMAK_SET_CREATION_SPEC.md`); **don't**
drop/rename `source_image_*_url` (non-optional Swift `let`s), and the
dashboard's mirror triggers must stay `BEFORE INSERT` or the NOT NULLs
fire.

### Backend spec (Railway — handoff, not written here)

**Env vars:** `OPENAI_API_KEY` (already set), `OPENAI_IMAGE_MODEL=gpt-image-2`,
`OPENAI_IMAGE_SIZE=1536x1536`, `OPENAI_IMAGE_QUALITY=high`,
`OPENAI_OUTPUT_FORMAT=png`, `OPENAI_TIMEOUT_SECONDS=180`.

**Transport — multipart with downloaded bytes (recommended).** Download
both Supabase objects, then POST `multipart/form-data` to
`https://api.openai.com/v1/images/edits` with `Authorization: Bearer
$OPENAI_API_KEY` and repeated parts literally named **`image[]`** (that's
OpenAI's own curl form), plus `model`, `prompt`, `size`, `quality`,
`output_format`, `n=1`.

- **Set an explicit filename and `Content-Type: image/jpeg` on each
  part.** Streaming Supabase bytes without them yields
  `application/octet-stream` → hard 400. This is the single most likely
  first failure.
- Do **not** send `response_format` (DALL·E-only → 400). Do **not** send
  `input_fidelity` with gpt-image-2 (always high automatically).
- Downscale references to ≤1024px long edge — the input token budget caps
  around 1,536 tokens, so larger buys nothing.

**JSON-with-URLs alternative — do not build on it yet.** The spec defines
`images: [{"image_url": "<url>"}]` on `application/json`, which would skip
downloading entirely. Two blockers: (a) another OpenAI doc page states
edits are multipart-only, contradicting the spec; (b) the JSON schema's
`size` appears to be a hard enum of `auto|1024x1024|1536x1024|1024x1536`
— **if true, JSON mode cannot do 2K at all.** Unconfirmed; verify with one
live curl before adopting.

**Response:** always base64 — read `data[0].b64_json`, decode, upload to
the `chamak-outputs` bucket under `{wholesaler_uid}/…`. `data[0].url` is
never populated for GPT-image models; never write a code path that reads
it. Log `usage.input_tokens_details` on the first runs to get real cost
numbers.

**Row write on success:** `output_image_url`, `compiled_prompt_text`,
`model_id`, `status='done'`, `completed_at=now()`. On failure:
`status='failed'` plus a surfaced message (the commit `94e84bb` "surface
pipeline failures" contract).

**Errors:** retry only rate-429 / 5xx with backoff honouring `Retry-After`.
Never retry `image_generation_user_error` / `moderation_blocked` — those
are terminal, surface them to the user. Never retry billing 429s
(`credit_balance_exhausted`, `*_spend_limit_exceeded`).

**Two hard prerequisites:** (1) **API Organization Verification** must be
completed or every call 403s; (2) rate limits are TPM+IPM only — **Tier 1
= 5 images/min is unusable**; Tier 3 (50 IPM) is the realistic floor.

**Async, not inline.** iOS's generate POST has `timeoutInterval = 90` and
gpt-image-2 at high/2K can exceed that. The handler must accept, enqueue,
and return promptly; iOS already polls the row for completion.

### iOS changes — PLAN ONLY, not applied

| File | Change |
|---|---|
| `Chamak/ChamakModels.swift` | New `enum ChamakPipeline: String, Identifiable, Sendable { case chamak1 = "chamak_1", chamak2 = "chamak_2" }` with `displayName`, `creditFeatureKey`. Optionally add `let pipeline: ChamakPipeline?` + CodingKey to `ChamakGeneration` (**optional**, so pre-migration rows still decode). |
| `Networking/ChamakAPI.swift` | Add `let pipeline: String` to `CreateGenerationPayload`; add a `pipeline:` param to `createGeneration`. **Nothing else** — both HTTP bodies and all error handling stay untouched. |
| `Chamak/ChamakViewModel.swift` | Add `var pipeline: ChamakPipeline = .chamak1`; pass it at the `createGeneration` call. `resetToPicker()` keeps it; `openGalleryItem` restores it from the row. |
| `Chamak/ChamakFlowCoordinator.swift` | Add `let pipeline: ChamakPipeline`; seed `vm.pipeline` in `.task`. |
| `WholesalerHomeView.swift` | **Load-bearing:** replace `@State var isShowingChamak: Bool` with `@State var chamakPipeline: ChamakPipeline?`, and `.fullScreenCover(isPresented:)` with `.fullScreenCover(item:)` — a Bool can't distinguish which of two cards was tapped. Also add an `else` for nil `session.user`; today that presents an empty, inescapable cover. |
| `WholesalerHomeView.swift` (`ChamakCard`) | Parameterize with `pipeline` + a compact flag. Title becomes `Text(pipeline.displayName)` (currently a literal `"Chamak"`). At half width the internals must scale: `.cirka(32)` → ~22, `ChamakNecklace` 120pt → ~70 or drop, `Spacing.xl` → `.md`, `minHeight: 220`, shorter body copy. Wrap both cards in an `HStack(spacing: Spacing.base)`. |
| Credits | `chamak.generate` is hardcoded in four places (`WholesalerHomeView.swift` ×2, `ChamakSliderFormView.swift`, `ChamakCatalogPickerView.swift`). Make them `pipeline.creditFeatureKey`; add `chamak2.generate` / `chamak2.reroll` to the rate card and a `displayTitle` case in `TreasureChestModels.swift`. The home banner divides the wallet by one cost to say "about N more fusions" — that's now ambiguous across two prices, reword it. |
| `Chamak/ChamakGalleryView.swift` | `fetchWholesalerGallery` returns all rows unfiltered, so 1.0 and 2.0 outputs will interleave indistinguishably. Add a badge next to the existing `statusBadge`, or a filter. |
| Copy | Hardcoded "Chamak" strings in `ChamakCatalogPickerView.swift` and `ChamakGeneratingView.swift` will misreport which pipeline is running. |

**Smallest shippable slice:** the migration + the two `ChamakAPI` lines +
the enum + the `fullScreenCover(item:)` swap + a compact card. Gallery
attribution and per-pipeline pricing can follow.

### Risks / open questions

1. **The premise may be wrong** — nothing has verified that kie.ai
   actually ignores Design 2, and `CHAMAK_SET_CREATION_SPEC.md` itself
   notes the Nano Banana call "has never been verified working end-to-end."
   Run the indexed-prompt test on 1.0 first.
2. **JSON-mode `size` enum** — if it really excludes 2K, then the
   URL-passing shortcut and 2K output are mutually exclusive. Unconfirmed;
   one live curl settles it. Multipart is the safe default.
3. **Doc conflict on URL input** — the OpenAPI spec defines
   `ImageRefParam.image_url`, but a separate OpenAI page says edits are
   multipart-only. Keep a bytes fallback regardless.
4. **gpt-image-2 input tokenization is officially undocumented** — the
   ~$0.016–0.025-per-two-refs figure is community reverse-engineering, not
   OpenAI's. Read `usage.input_tokens_details` from the first real call
   before quoting a price to anyone.
5. **Moderation rejections on jewelry-on-a-person photos** are a realistic
   recurring failure, and the `moderation` param is documented on
   `/generations` only — on edits there may be no lever. Budget for it as
   a user-visible outcome, not an edge case.
6. **Cost/latency regression is real** — 2.0 at high quality is ~5.7× the
   price and ~3× the latency of 1.0. Two identical-looking home cards will
   not communicate that; the credits capsule has to.
7. **Unverified:** the exact `quality` enum on edits (one doc render
   omitted `high`/`auto`), and whether `gpt-image-2` on `/images/edits`
   works first try (the endpoint's summary string omits it, though the
   model enum and model page include it). Smoke-test both.
8. **No live API calls were made** in any of this research — everything
   above is from documentation only.


---

## Phase 4 — EXECUTION PLAN (decided)

> ### ⚠️ SCOPE CORRECTION — read this before the plan below
>
> The plan that follows was written assuming we would first run prompt
> experiments **on Chamak 1.0** (steps E1/E2/E3) and only then build 2.0.
> **That sequencing is superseded.** The user's requirement is:
>
> **Chamak 1.0 is FROZEN. We are only ADDING Chamak 2.0 alongside it.**
>
> What this changes:
> - **Dropped:** E1/E2/E3 — the ordering, indexing, and note-precedence
>   experiments that would have modified 1.0's prompt. 1.0 keeps its current
>   prompt, model, and behavior exactly as-is.
> - **Moved:** all three prompt corrections (index binding, symmetric
>   treatment, slider-over-note precedence) now ship **inside 2.0's prompt
>   from day one**, rather than being proven on 1.0 and ported.
> - **Kept:** steps A1 and B1 — both are strictly read-only and change
>   nothing. A1 (`SELECT` the deployed compiled prompt) matters because 2.0's
>   prompt should start from the text 1.0 *actually* sends, which this doc
>   and the live row have been observed to disagree about. B1 (OpenAI
>   Organization Verification + rate tier) has multi-day lead time and gates
>   everything downstream regardless.
> - **Kept:** the Stage 1 request-side logging spec, but scoped so the
>   `chamak_1` branch stays byte-identical — logging is additive
>   observability, not a behavior change.
>
> **Accepted cost of this sequencing, stated plainly:** 2.0 changes both the
> renderer *and* the prompt at once. If 2.0 produces good blends, we won't
> know which change was responsible. If it doesn't, we've spent money and
> still need the diagnosis. This is a deliberate trade for speed and for
> keeping a working pipeline untouched — not an oversight.
>
> **One genuinely shared touch point:** the iOS poll ceiling
> (`ChamakViewModel.swift`, 40 attempts × 2.5s = 100s) is used by both
> pipelines. OpenAI's ~33s median with a long tail needs a wider window, but
> raising it globally would delay how fast 1.0's *failures* surface. Make the
> ceiling depend on `pipeline` so 1.0's timing is bit-for-bit unchanged.

Produced by a judge panel: four rival sequencing strategies drafted
independently, scored by three judges (risk-of-wasted-work, time-to-signal,
technical-correctness), then synthesized. The judges caught five concrete
errors in the drafts, all corrected below — notably that an OpenAI
Organization-Verification 403 blocks the whole `gpt-image` family (so
`gpt-image-1.5` is NOT a fallback for it), and that moving the backend to
202-accept requires widening the iOS *polling* budget, not the request
timeout.

# THE PLAN: diagnose 1.0 on the cheap pipeline, unblock 2.0 in parallel, build 2.0 last

**Decision:** Run the free diagnosis of Chamak 1.0 and the OpenAI wire-validation as two parallel tracks starting today; build Chamak 2.0 only after the prompt is proven — because 2.0 swaps *only* the renderer, so a prompt/ordering bug is inherited at ~6x cost and ~3x latency, while the OpenAI org-verification gate has a multi-day lead time that must start now regardless.

Two tracks. Track A costs nothing and answers "why is 1.0 broken". Track B costs ~$0.25 and answers "can 2.0 ship at all". Neither blocks the other.

---

## Stage 0 — Today, both tracks, ~45 min total

**A1. Read the deployed prompt.** *(USER — Supabase SQL editor, read-only, 5 min)*
```sql
select id, created_at, status, prompt_version, source_image_1_url, source_image_2_url,
       note_text, wholesaler_form_json, left(compiled_prompt_text, 6000)
from public.chamak_generations order by created_at desc limit 5;
```
**Signal:** does the compiled prompt say "Design 1/2" or "Image 1/2"? `CHAMAK_PIPELINE_CHANGES.md` contradicts itself (template uses "Image 1" at :178-282; :483 claims "Design 1"), so Theory A is currently *unknown in both directions*. This one query kills or confirms it. Also confirms two distinct URLs exist (collapses Theory B to the backend→vendor hop) and whether slider weights reach the text at all.

**B1. Check OpenAI prereqs.** *(USER — OpenAI dashboard, 5 min)* Organization Verification status + rate tier. Unverified → start it now; it gates the whole gpt-image family, so **gpt-image-1.5 is NOT a fallback for a 403** (it is only a fallback for a 400-unknown-model). Tier 1 = 5 img/min is unusable; request Tier 3.

**B2. One instrumented curl.** *(USER — laptop, 10 min, ~$0.21)* Download the *failing generation's own* `source_image_1_url`/`source_image_2_url` to `/tmp/d1.png`, `/tmp/d2.png`, then:
```bash
curl -sS -D /tmp/h.txt -w '\nHTTP %{http_code} in %{time_total}s\n' \
  https://api.openai.com/v1/images/edits \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -F 'model=gpt-image-2' \
  -F 'image[]=@/tmp/d1.png;type=image/png' \
  -F 'image[]=@/tmp/d2.png;type=image/png' \
  -F 'size=1536x1536' \
  -F 'prompt=Fuse into one jewelry piece: silhouette and structure from image 2, stone work and metal finish from image 1. Studio product shot, white background.' \
  -o /tmp/out.json
```
No `quality`, no `n` — the quality enum on `/edits` is unverified and would make a 400 unattributable; add them on the second call. Decode separately with python/base64 from `data[0].b64_json` (`url` is never populated).
**Decode table:** 403 → verification gate (B1 is the fix, no model swap helps). 400 on model → gpt-image-2 not on `/edits`; pin `gpt-image-1.5` at 1536 and treat `/v1/responses` as a *separate integration*, not a one-flag retry. 400 naming the image part → the `;type=` requirement is real; re-run without it to confirm, then hard-code it in the spec. 400 on size → step down to 1024. 429 → read `x-ratelimit-limit-images` from `/tmp/h.txt`. **`time_total` is the schedule number.**

**B3. Freeze the surviving parameters** (model, size, quality, transport, measured latency) into a scratch note. Everything downstream quotes it; nothing re-guesses it.

---

## Stage 1 — The one Railway deploy *(USER deploys; I write the spec)*

**S1. Bundle three changes into a single backend deploy** — the backend is spec-only, so minimize round trips:
1. **Request-side log, permanent, both pipelines:** `CHAMAK_REQ gen=<id> variant=<v> model=<m> images=<n> urls=[...]` plus vendor status + first 500 chars of response. Closes Theory B forever, for free, on every future generation.
2. **Backend MUST overwrite `prompt_version` at compile time.** `ChamakAPI.swift:130` hardcodes `prompt_version: "v1.0-chamak"` at INSERT. Without this, every experiment row is mislabeled and the whole diagnostic log is fiction.
3. **Per-row prompt variant**, read off a column — *not* a Railway env var. An env var flips the prompt for every live wholesaler on each test run and makes concurrent A/B impossible.

---

## Stage 2 — Experiments, one variable per run *(USER runs in-app; I keep the log)*

Control fixture: the failing pair, sliders 100% toward Design 2, empty note. Every run differs by exactly one thing. Log at `/Users/parashrautela/Documents/jewel india /wholesaler ios/set-creation/CHAMAK_DIAG_LOG.md`.

**E1 — ordering (Theory C).** Two in-app runs, **sliders symmetric at 50/50, no note**, swap which photo goes in slot 1. Symmetry is load-bearing: with an asymmetric prompt, swapping the files also inverts what the prompt asks for, and the result cannot distinguish canvas-dominance from prompt-obedience. Zero code, runnable today. Output follows slot 1 both times → positional/canvas dominance.

**E2 — indexing (Theory A).** Only if A1 showed "Design 1/2". Variant `v1.1-index`: an index-binding header ("You are given exactly 2 reference images in order; IMAGE 1 is the first array element…") and every "Design N" → "Image N". Nothing else changes.

**E3 — note precedence.** Variant `v1.2-constraints`, shipped separately from v1.1 so attribution survives: (a) quarantine the note as delimited **data** — `STYLING NOTE, quoted verbatim: <<<NOTE … NOTE>>>` — not as another instruction; (b) emit a **RESOLVED CONSTRAINTS** block *after* the note section so the sliders get the last word, listing each attribute at ≤0.15/≥0.85 and explicitly voiding "use image N as truth source" style requests. Re-run with the exact adversarial note.

### 🛑 STOP AND REASSESS — after E1/E2/E3
- **Fixed by E2** → prompt was the bug. Ship v1.1 to 1.0 now; 2.0 becomes an optional quality upgrade, not a rescue.
- **Log shows `images=1`** → transport bug. Stop all prompt work, fix the array.
- **E1 order-dominant, 2 images sent, indexing no effect** → vendor semantics. 2.0 is justified; proceed to Stage 3 with the proven prompt.
- **B1 returned unverified/Tier 1** → 2.0 cannot ship regardless; Stage 3 waits.

---

## Product decision (recommendation, take it now — it shapes E3)

**Sliders own structure; the note owns everything else.** Sliders are the only precise, quantified input the wholesaler gives; a free-text note is inherently ambiguous and today silently annihilates a deliberate 100% setting, which reads as the app ignoring the user. Note governs metal tone, stone color, mood, styling. Ship a `note_mode` escape hatch (`NOT NULL DEFAULT 'styling_only'` + CHECK) *after* E3 proves the mechanism — not before.

---

## Stage 3 — Build 2.0 on the proven prompt

**S2.** *(USER, Supabase)* `ALTER TABLE chamak_generations ADD COLUMN IF NOT EXISTS pipeline TEXT NOT NULL DEFAULT 'chamak_1', ADD COLUMN IF NOT EXISTS model_id TEXT;` Then, inside `BEGIN … ROLLBACK`, run a dashboard-shaped INSERT (dashboard column names only) to prove the mirror triggers still fire, leaving nothing behind.

**S3.** *(I write the spec)* `chamak_2` branch using the frozen B3 parameters; prompt **byte-identical** to 1.0's. **Mandatory:** `/api/chamak/generate` returns 202 immediately and renders in a background task — `ChamakAPI.swift:276` is a 90s synchronous timeout that on the slow tail throws *after* the server has already debited credits, showing the wholesaler a failure they paid for.

**S4.** *(I edit, on go-ahead)* Raise `ChamakViewModel.swift:286` from `attempts < 40` (2.5s = 100s ceiling) to ~180s before 2.0 ships — 202 moves the whole render into the polling window. **Keep the single `chamak.generate` credit key for v1:** `cost(for:)` reads a server price table, so a client-side `chamak2.generate` with no server row returns nil and `WholesalerHomeView.swift:71` silently falls back to `?? 10` while the server charges something else. Land the server price row first.

**S5.** *(I edit, on go-ahead)* `ChamakPipeline` enum; one field on `CreateGenerationPayload`; `WholesalerHomeView.swift:13/57/207` Bool → `.fullScreenCover(item:)`. Pass `pipeline` **as a parameter to subviews** the way `wholesalerID` already is — `@State private var vm = ChamakViewModel()` at `ChamakFlowCoordinator.swift:6` cannot take an instance member in its initializer.

**Flagging honestly:** "2K" becomes 1536x1536 for v1. 2048 is in OpenAI's experimental band and the API defaults to a 1536-capped model unless pinned. That is a change to the product promise, not a footnote.

---

## Right now, this session

Run **A1** and **B1** — both are five minutes, zero code, zero risk, and they gate everything else. Paste the A1 output back; I will read the compiled prompt, create `set-creation/CHAMAK_DIAG_LOG.md`, and draft the Stage 1 Railway spec. No Swift file gets touched until you give an explicit go-ahead at S4.
