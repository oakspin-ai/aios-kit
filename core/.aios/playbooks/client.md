# /client — add or update a client, prospect or partner

1. Check `clients/` for an existing folder by business name, contact or domain. Update it rather than creating a second one.
2. New: copy `.aios/templates/client/` to `clients/<name>/`. Fill `CLAUDE.md` with durable facts (who they are, what they buy, how to work with them), `meta.yml` with where things stand now, and a first dated row in `ledger.md`.
3. Unknown names or details are recorded as unknown, never invented.
4. A prospect becomes a client only when the owner says a signed agreement or a paid deposit exists; record which and the date in `meta.yml`.
5. Every change to `meta.yml` gets a dated `ledger.md` row in the same save. Set `status_updated` to today, and `waiting_on` when the next move is theirs. `clients/pipeline.md` rebuilds itself from the cards at the save; never edit it.
6. Report the folder and what is still unknown. Then save (`sh .aios/hooks/autosave.sh`).
