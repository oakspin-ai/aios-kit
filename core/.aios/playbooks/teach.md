# /teach: teach the brain a task

Turns a task the owner wishes they did not have to do into a skill: a real Claude skill that shows
up when the owner types / in a new chat, and starts on its own when they ask for it in plain words.

1. Ask the owner to describe the task the way they would tell a new hire: when it comes up, what a
   good result looks like, what goes wrong, who is involved, which files or tools it touches, and
   the words they would use to ask for it.
2. Name it the way the owner says it ("chase-quotes", not "follow-up-automation"). Copy
   `.aios/templates/skill.md` to `.claude/skills/<name>/SKILL.md`. The `description` line is what
   makes Claude pick the skill: one sentence on what it does, then the owner's own trigger phrases.
3. Write the steps in plain English. A step that sends, posts or changes something outside the
   brain says so, and runs on its own only if `company/permissions.md` allows it; otherwise it
   drafts and asks. Nothing in a taught task spends money or deletes. If the owner wants the task
   to run without asking, read back the permission line (what, where, limits) and add it on a yes.
4. **Check it against the quality bar before saving.** A skill is not done until every line is true:
   - **No baked-in numbers.** Lead times, prices, discounts, thresholds and dates are read from the
     company files by name (e.g. `company/services.md`, "custom lead time"). If the number is not in
     a file yet, ask the owner for it; write it there only with their answer, as a confirmed fact,
     and point the skill at it. Never fill in a number the owner did not give.
   - **Every judgement word is defined.** "Tight", "overdue", "big order", "quiet customer": each
     gets a number or a rule in "What its judgement words mean".
   - **It checks what can collide.** Other orders in the queue, stock on hand vs on order, what is
     already promised to someone else, the latest version of a price or policy.
   - **It uses the owner's voice** by reading `.claude/skills/voice/SKILL.md` before drafting.
   - **It keeps its promises visible.** Any date, amount or commitment it gives goes on
     `memory/follow-ups.md` with a check date.
   - **It has a worked example** from the owner's real files, run end to end.
5. Run it once on real material with the owner watching. Fix what the run shows. Save.
6. Add a row to `skills/README.md` (name, when to use it, what to say). Tell the owner in one line:
   "Your new skill is ready. In a new chat, type / to see it, or just ask for it in your own words."
