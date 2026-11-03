# Migrations

One script per engine version that changes where the owner's files live or what the brain keeps,
named for that version (`0.2.0.sh`). There are none yet. The updater runs every script whose version is newer than
the installed one and no newer than the engine being installed, oldest first, after the engine
folder is replaced and before the checks. Scripts come only from the verified engine.

Rules for a migration:

- It may create, move or change files **inside the brain only**. The updater runs it with a
  throwaway home folder and temp folder, so writing to the owner's home, private folder or
  documents folder does nothing useful and must not be relied on.
- It never deletes the owner's content and never edits the meaning of a fact.
- It is safe to run twice.
- A non-zero exit aborts the upgrade, and the updater then puts every file in the brain back as it
  was, including any file the migration created anywhere in the brain.

Test each one on a sample brain before release. Key rotation (a release list signed by the old key
that names a new key) is not built yet; when it is, it belongs in the updater, not in a migration.
