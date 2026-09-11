# Set Creation — superseded staging folder

The SQL and Python that used to live here were written against **Google's
Gemini API** (`google-genai` SDK, inline image bytes). That was wrong.

"Nano Banana" in this project is **`api.nanobananaapi.ai`** — a third-party
wrapper with a completely different contract:

| | Google Gemini (what was assumed) | nanobananaapi.ai (reality) |
|---|---|---|
| Images | inline bytes | **public URLs**, fetched by the vendor |
| Call style | synchronous | **async: submit → poll → download** |
| Prompt cap | ~64k tokens | **5000 chars, hard** |
| `type` value | n/a | `"IMAGETOIAMGE"` (vendor's own typo) |

Both files were deleted rather than left to mislead. The real, working
implementation lives in the actual repos:

| What | Where |
|---|---|
| Migration | `ai-pipeline/migrations/005_set_creation.sql` |
| Multi-image client | `ai-pipeline/app/services/ai.py` → `NanobanaClient.compose_set()` |
| Prompt + runner | `ai-pipeline/app/services/chamak.py` → `run_set_creation_generation()` |
| Route | `ai-pipeline/app/main.py` → `POST /api/set-creation/generate` |
| Web UI | `Jewel-India-Frontend/components/wholesaler/set-creation/` |

Design docs that are still current:
- `JewelIndia/Sources/Features/Wholesaler/Chamak/CHAMAK_SET_CREATION_SPEC.md`
- `JewelIndia/Sources/Features/Wholesaler/Chamak/SET_CREATION_V1_PLAN.md`
  (phases 1–4 are now done; the iOS port is the remaining piece)
