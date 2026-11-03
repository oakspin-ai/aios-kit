# Your company brain: what you got and how it grows

Written for the owner of %%COMPANY%%. Print it if you like.

## What this is

A private place where your business is written down in plain files, and an AI that reads those
files to answer questions, draft messages, file meetings and run the small jobs you would rather not do. It lives
in your own account. OakSpin installs it and can be removed at any time. The knowledge
stays yours.

## Claude or Codex: same brain, two ways in

| | If you use Claude | If you use Codex |
|---|---|---|
| Open | the brain folder in Claude | the brain folder in Codex |
| Commands | `/start`, `/week`, `/save` | `$start`, `$week`, `$save`, or just say it |
| Saving | automatic when you close the session | say "save" before you close the window |
| Install | the installer sets up Claude if you lack it | the installer skips Claude and starts Codex |

The files, rules and playbooks are identical either way.

## Talk to it, do not type

Everything you tell the brain can be spoken. Click the microphone in your AI app's message box (Claude or Codex), on the
laptop or the phone, and say what you mean. Brain-dump style is fine: it sorts the words into the
right files.

## What it does this week

- **Answers questions about your business** from what you told it in the interview and what you let
  it read: services, prices, customers, who does what.
- **Files your meetings when you ask.** Type `/meeting` (or say "file that meeting"): it files what
  you tell it, or what a recording says, to the right client or operations folder, with promises
  pulled out and dated. You confirm; it does not guess. Nothing files meetings on a schedule yet.
- **Runs three skills** set up from the three things you said you wish you did not have to do. They draft and you approve, until you tell one it may go ahead on its own.
- **Works from your laptop or your phone.** Saving happens on its own when a session ends, so a
  change on one shows on the other next time you open it.

## How it grows

Every meeting filed, every question answered, every correction you make gets written down. Next
month it knows more than this month. Over a year it becomes the place a new hire reads on day one.
That only happens if chats end with `/learned`.

## What stays private

- Your business numbers are welcome: sales, costs, margins, invoices. Bank and card numbers,
  passwords, contracts you have not chosen to share and anything personal go in the private folder
  at `%%PRIVATE%%`. The brain never opens it. Payroll is your call; it asks.
- Before it reads anything from outside (your website, emails, files) it tells you what it will read
  and waits for your yes.
- Documents you want it to know about: drag them into the chat, or put them in your documents
  folder at `%%DOCUMENTS%%`. It checks each file for passwords and account numbers before reading
  (text, Word, spreadsheets and PDFs), and asks before reading any file it cannot check, such as a
  photo or scan of paper. That check misses things (some ID numbers, staff personal details), so
  give every file a quick look before you add it.
- If something that looks like a password or card number gets pasted in, it stops and refuses to
  save it. That is a backstop, not a promise; do not rely on it.
- Your words go to the AI provider you use (Claude from Anthropic, or Codex from OpenAI) the same way a chat would. Ask
  OakSpin for the one-page note on what that provider keeps.
- If something private gets in by mistake, tell OakSpin the same day. There is a procedure to remove
  it from the history, not just the file.

## What is yours and what is OakSpin's

- **Yours:** everything about your business in these files. Take it anywhere, any time.
- **OakSpin's:** the engine underneath (the folder called `.aios`): the interview, the playbooks,
  the checks. You are licensed to use it. If we part ways, what is installed keeps working with
  your own AI account; updates, tuning and support stop. [Who owns what](.aios/OWNERSHIP.md) has
  the details.

Updates take care of themselves: each time your brain opens it checks for a newer engine from
OakSpin and installs it, then tells you in one line what changed. If your brain says it was
installed without OakSpin's key, the first update waits until you confirm the key's fingerprint
once with OakSpin. Before anything installs it checks that the release is signed by OakSpin's key (the fingerprint you confirmed, pinned in your brain), that it matches OakSpin's published release list, and that it is newer than what you have; if an update fails partway, every file goes back as it was. Your files are never touched by an upgrade, and OakSpin never needs a key to your account to ship one. If you would rather be asked first, say "ask me before upgrading" and the brain switches the setting; then only /upgrade, after your yes, installs.

## What you can rename

Your brain folder and its private GitHub copy are yours: rename them any time. The command names
stay as they are so the guide keeps matching. The kit we install from is OakSpin's,
not something in your account; you never need to touch it.

## One line of history

Your brain has one owner and one timeline. Every save lands on the main line and goes to your private GitHub copy. There are no side branches and no pull requests to approve. If you ever see one, the automatic save folds it back in. One exception keeps you safe: if a save from your phone or a cloud session changes how the brain itself works (its rules, its settings, its skills, what it may do without asking), your main computer tells you what it would change and waits for your yes. Everyday notes never wait.

## Three things that break it

1. Closing a chat without `/learned`. The files are saved automatically, but what you decided in the
   conversation is not written down until you ask.
2. Treating a guess as a fact. Anything the brain imported or inferred shows as a question until you
   confirm it. Answer the questions.
3. Pasting private things in. See above.

## The seven commands

Questions need no command; just ask. `/start` interview · `/meeting` file a meeting ·
`/learned` capture what a chat taught · `/client` add or update a client · `/week` weekly review ·
`/teach` teach it a task · `/upgrade` bring the engine up to date. Saving is automatic; `/save` does it on demand. The command card has one
line on each. Your pipeline page, `clients/pipeline.md`, is rebuilt from the client cards at
every save, so it can never drift from them; a row is flagged when its card is more than two
weeks old or something on it is overdue.
