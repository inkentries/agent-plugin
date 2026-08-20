# Memory on the git-notes carrier

By default (`store_in_git_notes = true`) `memory add` also writes the entry to
`refs/notes/inkentry` on `HEAD`. Those notes stay on this machine until the
pre-push hook is installed (`inkentry hooks install --pre-push`), because
`git push` does not push `refs/notes/*`. Graceful no-op outside a git repo.

To check those notes by hand with stock git, point it at the `inkentry` ref.
Plain `git notes show` reads git's default `commits` ref and reports "no note
found", which is a false negative:

```bash
git notes --ref=inkentry show HEAD    # notes on the current commit
git notes --ref=inkentry list         # every commit carrying inkentry notes
# equivalently
GIT_NOTES_REF=refs/notes/inkentry git notes show HEAD
```
