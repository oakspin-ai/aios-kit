# /week — the weekly review

1. Read every `clients/*/meta.yml` and `memory/follow-ups.md`. List: promises overdue; clients with no movement in 14 days; next actions with no date.
2. Read `memory/receipts/upgrade-check.json`. If the engine was updated this week, one line at the top of the review says so with what changed. If the last check is older than seven days, or its result is `deferred-unsaved-work`, `failed-rolled-back`, `bad-signature` or `digest-mismatch`, say so plainly and **offer** `/upgrade`; if it is `available` or `needs-key`, say a newer engine is waiting and offer it. Never run `/upgrade` unasked: it installs only after the owner's yes. Then read `memory/decisions.md` and last week's review in `memory/reviews/` if present. Read `inbox/review/` and list what is still waiting on the owner. Read this week's rows in `memory/actions.md` and list everything the brain did on its own, each with the permission that allowed it; anything that does not match a line in `company/permissions.md` goes at the top as a problem. Ask once whether any permission should be added or taken off.
3. **Unconfirmed facts.** Read the company fact tables (`company/*.md`) and each client's
   `meta.yml`. List facts marked `imported` or `inferred`, facts with no date, and facts that
   disagree with each other. Ask the owner about the top five at most, one at a time, most costly
   first (prices and terms before names). Write each answer with today's date and `confirmed`;
   move what is no longer true to a "History" note in the same file with its old date, never
   delete it. Say how many are left for next week.
4. **What went well.** From the follow-up list and the action log, say two things that went well
   this week, with what shows it, then one pattern worth changing and one concrete habit for next
   week. Ask the owner what the files cannot see before drawing a conclusion; their answer beats
   the files. Say what you could not read.
5. Ask the owner, one at a time, about anything the files cannot see: calls, texts, DMs, handshakes. Silence in the files is not silence in real life. Write the answers as `confirmed` facts.
6. Write `memory/reviews/YYYY-MM-DD.md`: what moved, what is stuck, the habit picked, the three things for next week, each with a date and an owner. Decisions taken during the review go to `memory/decisions.md`.
7. Close finished follow-ups (DONE with date) and add new ones.
8. Report in the house style: one line, three bullets, the one risk, next week's first action. Then save (`sh .aios/hooks/autosave.sh`).
