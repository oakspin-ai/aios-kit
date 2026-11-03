# Medical pack

Version 0, 2026-10-29. Not yet installed for anyone.

For doctors first, starting with doctors who work in hospitals. Nurses, hospital teams, clinic
owners and other medical roles come later, each after their own design-partner interviews.

| File | Use |
| --- | --- |
| [rules.md](rules.md) | Rules pasted into the brain at install |
| `onboarding.md` | Steps from first call to week three. OakSpin's own; not published |
| `evidence.md` | Why each part exists, how sure we are, and the source of each rule. OakSpin's own; not published |
| [starter/](starter/) | Templates, teaching and protocol folders, copied once at install |
| [engine/](engine/) | The patient-data check, installed in `.aios/industry/` and replaced on upgrade |

## What the brain is for
It holds the doctor's own knowledge: their standard wording, protocols, teaching material and
patient handouts. It never holds patient records; those stay in the hospital's own system.

## Not covered yet
- Clinic owners, nurses and hospital administration: no interviews yet.
- ChatGPT installs: unverified; the core assumes Claude.
- Any clinical decision support: out of scope (see rules).
