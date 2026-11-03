# /meeting — file a meeting by hand

Use this command to file a meeting, recorded or not, or to add what a recording missed. Nothing
files meetings on its own yet.

1. Ask who it was with and when, if not given. Work from what the owner tells you; mark it
   "owner's notes".
2. Pull out: decisions and why; promises (who, what, by when); new facts (numbers, needs,
   objections); the single next step; the next meeting if booked.
3. Screen: nothing from the private list in `company/access.md` gets written. Say "not saved here"
   for those and move on.
4. Route it with the table below.
5. Facts carry source, date and status `confirmed`. Promises with dates go in `memory/follow-ups.md`.
6. Add a row to `memory/filed-meetings.md` (date, title, attendees, where it was filed) so the
   same meeting is never filed twice.
7. Offer to draft any recap or follow-up message. Drafts only; the owner sends.
8. Report: one line on the outcome, then decisions, what we owe, what they owe, next step.

## Routing

| Who was in the meeting | Where it goes |
|---|---|
| A contact or email domain that matches a client or prospect folder | `clients/<name>/` (ledger row, facts, meta) |
| A person listed in `company/people.md` (teammate, contractor) | `memory/operations/<date>-<topic>.md` and `memory/decisions.md` for decisions |
| A supplier or partner named in `company/tools.md` or `company/customers.md` | `memory/operations/` |
| Nobody the brain knows | `inbox/<date>-<title>.md` with a one-line question to the owner: who is this and where should it live? |
| The owner alone (a voice memo) | `memory/imported/<date>-memo.md` |
