# /upgrade — bring the engine up to date now

The engine keeps itself current: every time the brain opens it checks OakSpin's shelf (at most
once a day). With `upgrade: auto` in `aios.yml` it installs a newer engine when there is no unsaved
work, then says in one line what changed. With `upgrade: ask` it only says one is waiting. A brain
that is never opened is never updated; nothing runs on a schedule. This command is the manual
version, for "do it now" and for ask-mode brains.

Every install is checked first: the release list must be signed by OakSpin's key, the engine must
match that list, and the version must be newer than the one installed. The updater does the
checking; the owner's part is one yes.

1. Run `sh .aios/tools/upgrade.sh --check`. If it says the engine is current, say so and stop. If it
   says OakSpin has not set up online releases, say that no update is published yet and stop.
2. Read the owner the "what changed" lines in plain words.
3. **Ask: "Install it now?" and wait.** Nothing installs without an explicit yes in this chat.
   A "later" or no answer means stop here; say it will be offered again next time.
4. **The first signed install only** (and on a brain installed without the key, `verify: none`): the check prints OakSpin's key fingerprint (`SHA256:...`).
   Read it to the owner, who compares it with the one in their welcome kit or from OakSpin. On
   their yes to the fingerprint, step 5 adds `--pin-key <that fingerprint>`; from then on the key
   is pinned in the brain and never asked about again. If the fingerprints differ, stop: tell the
   owner not to install, and tell OakSpin.
5. Make sure there is no unsaved work (run `/save` if there is), then run
   `sh .aios/tools/upgrade.sh --yes` (plus `--pin-key SHA256:...` the first time). It replaces only
   OakSpin's parts, runs migrations and the checks, saves and pushes. If anything fails it puts every
   file back as it was and nothing is saved: tell OakSpin.
6. Report in one line: engine version now, and the one change most likely to matter to them.
