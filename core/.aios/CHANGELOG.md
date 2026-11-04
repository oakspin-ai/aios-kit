# What changed in the engine

One plain-English entry per engine version, newest first. The updater reads the entry for the
version it installs and tells the owner in one line what changed.

## 0.1.4
- Saves from GitHub come in reliably when the Claude app opens, even while the app is checking
  GitHub at the same moment.
- When two devices each add a decision, an action or a filed meeting to the brain's logs, both are
  kept instead of stopping to ask OakSpin.

## 0.1.3
- Your brain saves more reliably. Work left unsaved when the Claude app closes is saved when it next
  opens, and a save made on GitHub itself now joins the saves made on this computer.
- On a computer where Git has no name or email set, saves and updates from other devices now work.

## 0.1.2
- Your brain now works on Windows computers. It finds Python under its Windows names, saves notes
  in any language, and keeps your private folder off-limits however Windows writes its name.
  Nothing changes on a Mac.

## 0.1.1
- First signed OakSpin release. Nothing changes in how your brain works. From now on it checks
  for signed OakSpin updates when it opens and installs them.

## 0.1.0
- First OakSpin AI-OS engine. Your brain now has an installer, saves itself, keeps one line of
  history, screens documents before reading them, and can update itself from signed OakSpin
  releases once OakSpin publishes them.
- Your brain also keeps `profile.md`, `rules.md` (your industry's rules first), `knowledge/`,
  `templates/` and a weekly feedback log, and runs your industry pack's checks on every save.
