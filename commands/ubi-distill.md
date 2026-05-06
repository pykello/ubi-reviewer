---
description: Distill past ubicloud PR review comments into a reviewer playbook (maintainers only).
---

You are regenerating the playbook used by `/ubi-review`. This is a **maintainer command** that should be run from inside a clone of the `ubi-reviewer` source repo, because it writes back to `playbook.md` which gets committed and shared with the team.

## Steps

1. **Verify location.** Confirm the working directory contains `.claude-plugin/plugin.json` with `"name": "ubi-reviewer"`. If not, stop and tell the user to `cd` into their clone of the ubi-reviewer repo before running this.

2. **Fetch comments if missing or stale.** Check whether `data/pr-comments.jsonl` exists and was modified within the last 7 days. If not, run `scripts/fetch-pr-comments.sh` (it requires `gh auth login`). If the user passed an argument like `--limit 500`, forward it.

3. **Read and analyze the comments.** Load `data/pr-comments.jsonl`. Each line is `{pr, path, diff_hunk, body, user, created_at, html_url}`. Skip comments that are:
   - Replies in a thread (often start with `@username` — they're conversation, not guidance)
   - Praise without instruction ("LGTM", "nice", "thanks")
   - Author self-notes ("I'll fix this", "todo")
   - Trivially specific ("rename this var to `foo`" with no general principle)

4. **Cluster into rules.** Group remaining comments by underlying principle. Look for recurring themes — the same critique appearing across multiple PRs is the strongest signal. Examples of clusters you might find: testing patterns, error handling, naming conventions, framework-specific idioms (Sequel, Roda), security guidelines, performance pitfalls, commit/PR hygiene.

5. **Write `playbook.md`** with this structure:

   ```markdown
   # Ubicloud Reviewer Playbook

   _Generated from N PR review comments. Last updated: YYYY-MM-DD._

   ## How to use this playbook
   You are reviewing changes to the ubicloud repository. For each rule below,
   check whether the diff violates it. When you flag an issue, cite the rule
   number and link to one of the example PRs.

   ## Rules

   ### R1. <Short imperative title>
   **Rule:** <one-sentence rule, imperative voice>
   **Why:** <rationale, ideally drawn from the comments themselves>
   **How to spot:** <what pattern in a diff should trigger this>
   **Examples:** <PR #123, PR #456> (link via the html_url)

   ### R2. ...
   ```

   Aim for **15–30 high-signal rules**. Better to have fewer strong rules than many weak ones. Each rule should be something a reviewer would actually flag.

6. **Report back.** After writing `playbook.md`, summarize:
   - How many comments were ingested
   - How many rules were extracted
   - Any clusters you noticed but excluded (and why)
   - Suggested next step: `git diff playbook.md`, review, commit, push

Remember: the playbook is **shared with the team**, so be conservative. A noisy rule wastes everyone's time. When in doubt, leave it out.
