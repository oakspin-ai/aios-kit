# Clients, prospects and partners

One folder per business, created by `/client` from `.aios/templates/client/`. `meta.yml` is where things stand now; `ledger.md` is what happened; `memory/` holds durable facts.

`pipeline.md` in this folder is generated from every `meta.yml` at each save and never edited by hand: it shows clients, in play, waiting on them, partners and past, with each row's as-of date and a ⚠ flag when a card is more than two weeks old, a next action or follow-up is overdue, or the card has no date. Set `waiting_on` on a card when the next move is theirs.
