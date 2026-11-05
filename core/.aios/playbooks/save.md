# /save — save now, by hand

Saving is automatic: when a session ends, the brain runs its checks, saves, folds any side branch
into main and pushes to GitHub. On a phone or in a cloud session, a save that changes how the brain
itself works (its rules, what runs automatically, the engine, skills, permissions, what stays
private) is pushed on its own and waits for the owner's yes on the main computer instead. This command does the same thing on demand, for when the owner
wants to be sure, or when a window was closed hard and the automatic save did not get to run.

1. Run `sh .aios/hooks/autosave.sh` and show its last line to the owner.
2. If it says "Not saved", read the check output, remove the private item it names, and run it
   again. Never override the check.
3. If it says it could not reach GitHub, say so plainly, with the reason it gives; the next save will
   push. If it says GitHub did not accept this computer's login, the save is on this computer only
   and will not go up by itself: with the owner's yes, run `gh auth setup-git`, then save again. If
   GitHub's tool is missing or that does not work, tell the owner to contact OakSpin.
   If it says it backed up earlier saves, say how many went up. If it prints nothing, there was
   nothing new and nothing waiting.
4. If it says the save waits for a yes on the main computer, say so in one line: it is safe, and
   it joins the rest once the owner says yes there.
5. Report in one line: saved and backed up, saved locally only, waiting for a yes, or not saved and why.
