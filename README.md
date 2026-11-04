# AI-OS kit

Created 2026-10-29; the engine's version is in `core/.aios/VERSION`. Runs on Mac and on Windows 10/11 (in Git Bash).
This is what OakSpin installs as a design partner's own private brain repository: one shared core
plus one industry pack. Offer terms live in [services](../../company/services.md); this kit grants
no install, send or spend authority.

| Part | What it holds |
| --- | --- |
| [install.sh](install.sh) | The installer: builds a brain from `core/` and one pack, wires its checks, makes the private and documents folders outside it |
| [core/](core/README.md) | What every brain gets: assistant instructions (`AGENTS.md`), profile, house rules, knowledge, templates, weekly feedback log, and the engine in `core/.aios/` (interview, playbooks, saving, document screening, checks, updater) |
| [industries/](industries/README.md) | One pack per industry: firm rules, starter files and engine checks, plus OakSpin's own onboarding steps and evidence (never published) |

The engine came from another company's AI-OS starter kit, adapted to this layout and rebranded;
what came over, what changed and what was left out is in the
[port record](../../docs/sources/2026-10-29-aios-starter-port.md).

## Install (local copy of the kit)
From a checkout of this repository, in a setup session with the partner:

```sh
AIOS_DEV=1 AIOS_SOURCE=toolkits/aios sh toolkits/aios/install.sh "Partner's practice" --industry medical
```

It copies `core/` to `~/<short-name>-brain`, lays the pack's `starter/` files on top once, puts the
pack's `engine/` files in `.aios/industry/` (its checks run on every save), pastes the Rules section
of the pack's `rules.md` under "Industry rules" in the brain's `rules.md`, and writes
`industry: medical` to `aios.yml`. Then follow the pack's onboarding notes (`onboarding.md`, OakSpin's own).
Design-partner installs follow [playbooks/aios-install.md](../../playbooks/aios-install.md), which lives
in the brain, not the kit, so the release never publishes it.

`AIOS_DEV=1` installs from a local copy without a signed release (OakSpin's tests). It marks the
brain `verify: none`: it takes no engine update until the owner confirms OakSpin's key fingerprint
once, and says so at every session start. A partner's brain installs from a signed release (below).

The core assumes Claude Code (it edits files, runs git and uses session hooks); Codex works with
manual saves (`core/AGENTS.md`). ChatGPT is unverified; see [open questions](../../company/open-questions.md).

## Releases and updates
Signed releases are published to [oakspin-ai/aios-kit](https://github.com/oakspin-ai/aios-kit), one tag
per engine version (`v0.1.1` was the first, 2026-11-03). Its `releases.json` names the latest one.

1. **Public kit repository:** [oakspin-ai/aios-kit](https://github.com/oakspin-ai/aios-kit), named
   in both `core/.aios/release.conf` (`repo=`) and `install.sh` (`KIT_REPO=`); a test checks they match.
   Only the release tool writes to it.
2. **Release-signing key:** made with `python3 tools/aios_release.py --keygen` at
   `~/.oakspin/aios-release-key.pem` on the owner's machine (override with `AIOS_RELEASE_KEY`). Its
   public half is [release-key.pub](release-key.pub). Its fingerprint, for every welcome kit's
   `--key`, is `SHA256:fa40f9f8d1c363aafbe38e3573fb3230`. The private key never goes in Git or a
   chat. Keep one offline backup: without it no installed brain can take another update, and there
   is no built-in way to move a brain to a new key (it would be a hand repair on each brain).
3. **Release token** (`AIOS_RELEASE_TOKEN`): a fine-grained GitHub token for `oakspin-ai/aios-kit`
   only, with Contents read and write. It is made when the first release is published and is never
   stored in Git.

Each release:
- Copies everything this folder tracks except each pack's `evidence.md` and `onboarding.md`:
  OakSpin's own intelligence, kept here and never published (owner's decision, 2026-10-30;
  `PRIVATE` in `tools/aios_release.py`).
- Needs a newer `core/.aios/VERSION` and its entry in `core/.aios/CHANGELOG.md`. Any change in this
  folder makes `--check` report the published kit out of date until the next release.
- Prints the install line customers get. It checks the installer's own SHA-256 before running it,
  because the installer runs before it can check any signature; a plain `curl ... | sh` would run
  whatever the public repository holds.

`python3 tools/aios_release.py` signs and publishes the kit at its version, and each brain's
updater (`core/.aios/tools/upgrade.sh`) installs only a newer kit whose release list is signed by
the pinned key and whose files match the list's digest, replacing `.aios/` and the pack's engine
files and leaving the owner's files alone. A brain checks for a newer release at most once a day, when a
session starts; with no release list it changes nothing.

## Tests
`tests/test_aios_*.py` and `tests/test_patient_data_guard.py`. They install throwaway brains in
temporary folders.

## Not in the kit yet
Cut after the port's one review (owner's decision, 2026-10-29), each to come back through its own
review: a Live Review page for the partner, the helper tools behind the weekly review (tidy-up,
coaching notes, fact freshness, job receipts), and scheduled jobs (meeting sweep, follow-up
drafts). Today `/week` does those checks by reading the files, and `/meeting` files meetings when
asked. The AI-OS cases in `tests/test_live_review.py`, `tests/test_live_review_page.py` and
`tests/test_review_receipts.py` skip until a kit Live Review returns.

## Rules for changing the kit
- Change `core/` only for something every industry needs. Industry-specific choices go in the pack.
- Bump `core/.aios/VERSION` and add a plain-English `core/.aios/CHANGELOG.md` entry for every
  engine change that ships.
- Every pack choice names its source and status in that pack's `evidence.md`: firm (law, safety
  or repeated partner evidence) or hypothesis (one partner or desk research).
- Design-partner feedback comes back as dated source notes in `docs/sources/` first, then into
  the pack's evidence table.
