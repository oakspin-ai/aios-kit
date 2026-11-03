# Industry packs

A pack holds only what differs for one industry. Everything shared stays in [core](../core/README.md).

| Pack | Status | Evidence |
| --- | --- | --- |
| [Medical](medical/README.md) | Version 0, 2026-10-29; no installs yet | One design-partner interview plus desk research |

## What a pack contains
| File | Purpose |
| --- | --- |
| `README.md` | Who the pack is for, its status and what it does not cover yet |
| `rules.md` | Industry rules pasted into the brain's `rules.md`; their sources are in `evidence.md` |
| `onboarding.md` | How to onboard people from this industry, step by step. OakSpin's own: the release tool never publishes it |
| `evidence.md` | Each pack choice and rule, its source and whether it is firm or a hypothesis. OakSpin's own: never published |
| `starter/` | Files copied into the brain once, on install: templates, folders. The owner's from then on |
| `engine/` | Checks and other engine files, installed in `.aios/industry/` and replaced on every upgrade. A `.py` file with a `scan_text(text)` function runs on every save |

## Adding a pack
Start from real conversations with people in the industry. Save each one as a dated source note
in `docs/sources/`, then record every pack choice in `evidence.md` with its status. Promote a
hypothesis to firm only with law, safety reasons or repeated partner evidence.
