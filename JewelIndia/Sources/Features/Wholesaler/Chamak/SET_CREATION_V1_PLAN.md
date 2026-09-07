# Set Creation — V1 Plan (5 phases)

**Goal of V1: find out if this actually works before building a feature
around it.** Not to ship. We stop the moment we learn it can't work.

Full production design is in `CHAMAK_SET_CREATION_SPEC.md`. That's V2 — ignore
it until Phase 1 passes.

**Repos involved** (three separate places, only one is this repo):
| Piece | Where |
|---|---|
| Pipeline / backend | Railway — `ai-pipeline-production-3f9a` |
| Web app | `Jewel-India-Frontend` (Next.js) |
| iOS app | this repo |

Each phase has a **GATE**. Don't start the next phase until the gate passes.

---

## Phase 1 — Hand test in AI Studio. No code at all. (~30 min)

**Why first:** we do not need to build anything to answer "can the model do
this". Google AI Studio already has two upload boxes and a prompt box, it's
free, and it runs the same model the pipeline uses. Building an interface to
answer this question would cost a week and teach us nothing extra.

**Do this:**
1. Open Google AI Studio, select **Gemini 2.5 Flash Image** (= Nano Banana).
2. Get **3 pairs** of real jewelry photos — necklace + jhumka, shot
   separately. Use real messy wholesaler photos, not clean stock shots. Messy
   is what the app will actually receive.
3. Per pair: upload both, paste the prompt below, generate.
4. Score with the scorecard below.

**Prompt to paste:**

```
You are a luxury jewelry catalogue photographer.

I am giving you two photographs of two separate, real pieces of jewelry from
a jeweler's inventory: Image 1 and Image 2.

Create ONE photorealistic photograph showing BOTH pieces together, staged as
a matched set for a catalogue.

MOST IMPORTANT RULE - copy each piece exactly:
- Reproduce every detail of each piece exactly as shown in its photo.
- Do NOT redesign, improve, simplify or embellish either piece.
- Do NOT merge or blend the two pieces together into one object.
- Do NOT change one piece to match the other. If the two pieces do not match
  each other, keep them not matching. That is intentional.
- Keep the exact same number of beads, pearls, drops and stones on each
  piece. Keep the same metal colour and the same stone colours.
- Do NOT add any third piece of jewelry. Only these two pieces, nothing else.
- If a piece is a pair of earrings, show both earrings, identical to each
  other and identical to the photo.

STAGING:
Display the necklace on a deep teal velvet display bust. Place the earrings
on matching small velvet earring stands beside it at the base. Behind them, a
softly blurred backdrop of maroon silk with warm gold bokeh lights. Warm,
rich, showroom mood.

- Both pieces in one single scene, with one light source and one camera.
- NOT a side-by-side collage. NOT two photos pasted together.
- Correct real-world size relationship between the two pieces.
- Both pieces fully visible, nothing cropped off or hidden behind a prop.

PHOTO SPEC:
- Portrait orientation, catalogue quality.
- Soft even studio lighting, realistic metal highlights and stone sparkle.
- Sharp focus on both pieces.
- No price tags, no text, no watermarks, no logos.
- No hands, no people, no faces.
- True-to-life colour.
```

**Scorecard — score every output out of 5. Zoom in. Be strict.**

| # | Check | Pass? |
|---|---|---|
| 1 | Both pieces in ONE scene — not a collage, not two photos stuck together | |
| 2 | **Count the beads / pearls / drops on each piece. Same number as source?** | |
| 3 | Same metal colour and stone colours as source? | |
| 4 | Only the 2 pieces — no third item added to "complete the set"? | |
| 5 | Size relationship between the two pieces looks right? | |

Check 2 is the one that decides everything. A wholesaler will spot a 9-pearl
jhumka that came back with 11, and that makes the image useless to them.

**GATE:**
- 5/5 on **2 of 3 pairs** → build it. Go to Phase 2.
- Failing mostly on **check 2** → prompt wording won't fix this. Go to
  "If Phase 1 fails" at the bottom before writing any code.
- Failing on **checks 1 or 4** → that's a wording problem. Retune and retry.

---

## Phase 2 — Database + storage (~half a day)

A **separate table**, not a change to `chamak_generations`. V1 is a
throwaway experiment; keeping it isolated means zero risk to the live Fusion
feature, no migration on a production table, and we can drop the whole thing
if it doesn't work out. It gets merged into `chamak_generations` with a
`mode` column later, when it graduates (that's the V2 spec).

One row per attempt. That's what makes this a tuning tool — you can compare
prompt v3 against prompt v7 on the same photo pair.

```sql
CREATE TABLE public.set_creation_tests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_by UUID REFERENCES auth.users(id),
    necklace_image_url TEXT NOT NULL,
    jhumka_image_url   TEXT NOT NULL,
    prompt_text        TEXT NOT NULL,
    output_image_url   TEXT,
    status TEXT NOT NULL DEFAULT 'queued'
        CHECK (status IN ('queued','generating','done','failed')),
    error_text TEXT,
    score INT,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

**Important correction to the original idea:** the images do **not** go into
the database. They go into a Supabase **Storage bucket**; the table stores
only the URLs. Storing image bytes in Postgres is slow and expensive.

Also: output does **not** need a second table. Same row, `output_image_url`
column. One row = one complete experiment (inputs + prompt + result + score).

`prompt_text` is stored per row on purpose — when a result is good, we need
to know exactly which prompt produced it.

**Bucket:** reuse `chamak-outputs`, or make `set-creation-tests` if you'd
rather keep experiment junk out of the real bucket.

**GATE:** manually insert a row and upload an image to the bucket. Confirm you
can read both back.

---

## Phase 3 — Backend endpoint (~1–2 days)

Deliberately dumb. One endpoint, one model call.

`POST /api/set-creation/generate` taking `{ test_id }`:
1. Read the two image URLs and `prompt_text` off the row.
2. **Download both images as bytes.** Nano Banana will not fetch a URL for
   you — this is the single most likely thing to silently break.
3. Send both images + the prompt to the model, **explicitly requesting image
   output** (not text — a wrong response-mode config makes the call "succeed"
   with a written description instead of a picture).
4. Save the returned image to the bucket, write `output_image_url` and
   `status = done`. On any failure write `status = failed` + `error_text`.

**Image order matters** — Image 1 must be the necklace, Image 2 the jhumka,
matching what the prompt calls them.

**Skipped in V1:** no analysis stage, no content checking, no jewelry-type
detection, no credits, no idempotency. Two photos in, one photo out.

**GATE:** call the endpoint with curl using a row you made by hand in Phase 2.
An image lands in the bucket and the row goes to `done`. This proves the
plumbing works *before* any UI exists.

---

## Phase 4 — Small internal web page (~1–2 days)

In `Jewel-India-Frontend`. **Internal tool, not a wholesaler feature.** Put it
on an unlisted route.

The page:
- Upload box 1 → necklace
- Upload box 2 → jhumka
- **A big editable text box holding the prompt, pre-filled with the current
  one**
- Generate button
- Result image
- A list of past attempts with their images, prompts and scores

**The editable prompt box is the whole point of this phase.** Prompt tuning
takes 30–50 iterations. If the prompt lives in code, every iteration is a
deploy. If it lives in a text box, every iteration is: edit, click, look.
Seconds instead of minutes. This is why web-first is the right call — an iOS
build cycle would make this agonising.

**GATE:** run 5–10 real photo pairs through it, tuning the prompt as you go.
Score each with the Phase 1 scorecard. When you have a prompt that scores 5/5
consistently, **that frozen prompt text is the deliverable of V1.**

---

## Phase 5 — Port into the iOS app (~1–2 days)

Only after Phase 4 produces a frozen, proven prompt.

Almost everything already exists — the two-slot picker with photo upload is
built and working, so "can a wholesaler upload two different pieces" is
already a solved problem in this repo.

- Add `mode` to `chamak_generations` (`fusion` / `set_creation`, defaulting to
  `fusion` so nothing breaks).
- Two-button toggle at the top of the existing picker: **Fuse Designs** /
  **Set Creation**.
- In Set Creation mode: skip the analysis step and the slider screen entirely.
  Pick 2 photos → Generate → result.
- Reuse the existing waiting and result screens untouched. They'll say
  "Fusing Designs", which is wrong but cosmetic. Fix in V2.

**Flow:** pick 2 photos → Generate → result. Three screens, all already built.

---

## Separately: verify the existing Fusion pipeline

Not a blocker for Phases 1–4, because Phase 3 builds a fresh endpoint that
doesn't touch Fusion's code path. But it **is** a blocker for Phase 5, since
that's when Set Creation starts sharing `chamak_generations` and the app's
polling logic.

Run one normal Fusion generation and check the row: is `compiled_prompt_text`
filled? Is `output_image_url` filled? Is `status` = `done`? If not, that's an
existing Fusion bug that will break Set Creation the same way.

---

## What V1 deliberately does NOT have

All specced in `CHAMAK_SET_CREATION_SPEC.md` for V2. Don't let it creep in:

- 4 backdrop presets (V1 = velvet bust only)
- Wholesaler-facing styling note box
- Stage 1 content checking / jewelry-type detection
- Credits and pricing
- Reroll behaviour
- Real-world size hints per jewelry type
- Gallery badges, mode-aware labels, "Piece 1/2" wording

**And: do not put this in front of a paying wholesaler until Phase 4 scores
consistently.** Wholesaler feedback comes at the end of Phase 4 — send them
the web link, no TestFlight needed.

---

## If Phase 1 fails

If the model can't hold bead and stone counts, more prompt wording won't fix
it. Test these with the same 3 pairs and the same scorecard:

**Option A — cut out and paste.** Background-remove each piece, then composite
both onto a backdrop with normal image editing. Pieces are never regenerated,
so counts are perfect by definition. Expect this to look good on flat-lay
backdrops and wrong on the velvet bust — a necklace lying flat can't be
convincingly pasted onto a bust, because it needs to hang and drape.

**Option B — cut out, paste, then let the model relight it.** Same as A, but
feed the rough composite back to the model at low strength so it only fixes
edges, shadows and colour temperature instead of redrawing the pieces. More
backend work, but the only option that plausibly gets correct counts *and* the
velvet bust look.

Score both, pick a winner, then resume at Phase 2.
