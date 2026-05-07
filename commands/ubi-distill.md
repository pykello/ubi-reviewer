---
description: Distill ubicloud PR review comments into a categorized, severity-sorted playbook (maintainers only).
---

You are regenerating `playbook.md`, used by `/ubi-review`. This is a **maintainer command** that should be run from inside a clone of the `ubi-reviewer` source repo, because it writes back to `playbook.md` which gets committed and shared with the team.

## Prerequisite

The operator is responsible for fetching comments **before** running this command:

```sh
gh auth login                          # if not already
scripts/fetch-pr-comments.sh           # writes data/pr-comments.jsonl
```

If `data/pr-comments.jsonl` is missing or empty, stop and tell the operator to run the fetch script first. **Do not run the fetch script yourself.**

## Steps

1. **Verify location.** Confirm the working directory contains `.claude-plugin/plugin.json` with `"name": "ubi-reviewer"`. If not, stop and tell the operator to `cd` into their clone of the ubi-reviewer repo.

2. **Load all comments.** Read `data/pr-comments.jsonl`. Each line is `{pr, path, diff_hunk, body, user, created_at, html_url}`. Use **every** comment — do not filter by length, author, or perceived value. The goal is full coverage of the team's review patterns.

3. **Categorize every comment.** Assign each comment to a topical category. Suggested categories (extend as the data demands):
   - Correctness / bugs
   - Security
   - Concurrency / race conditions
   - Database / Sequel idioms
   - Performance (N+1, hot paths)
   - Testing patterns
   - Error handling
   - Naming and readability
   - API / Roda routing conventions
   - Logging / observability
   - Commit / PR hygiene
   - Style nits

   Comments that are pure conversation (replies, "thanks", "done", "@user can you…") with no actionable principle can be grouped under a single **"Non-actionable"** category and surfaced in a closing note — but do not silently drop them. The operator should be able to see how many were skipped and why.

4. **Assign severity per rule.** Each derived rule gets one of:
   - **blocker** — correctness, security, data-integrity, or a recurring violation that maintainers consistently push back on
   - **major** — likely problem, non-trivial regression, or a clear team standard
   - **minor** — style preference, naming nit, small ergonomic improvement

   **Author weighting:** comments authored by **Jeremy Evans** (`jeremyevans` on GitHub) are treated as **major or higher** by default — promote to blocker if the comment is about correctness, security, or testing rigor. Demote to minor only if Jeremy explicitly hedges ("nice to have", "minor", "not blocking", "optional", "if you want", "feel free to ignore").

5. **Cluster into rules.** Group comments by underlying principle. Recurrence across PRs strengthens severity. **Do not cap the number of rules** — produce as many as the data warrants. A long playbook is fine if every rule is grounded in real comments.

6. **Write `playbook.md`** with this structure:

   ```markdown
   # Ubicloud Reviewer Playbook

   _Generated from N PR review comments. Last updated: YYYY-MM-DD._

   ## How to use this playbook
   You are reviewing changes to the ubicloud repository. Walk **every** rule
   below and check whether the diff violates it. When you flag an issue, cite
   the rule number and link to one of the example PRs.

   ## Blocker

   ### R1. <Short imperative title> — <Category>
   **Severity:** blocker
   **Rule:** <one-sentence rule, imperative voice>
   **Why:** <rationale, drawn from the comments>
   **How to spot:** <pattern in a diff that should trigger this>
   **Examples:** [PR #123](url), [PR #456](url)

   ### R2. ...

   ## Major

   ### R<n>. ...

   ## Minor

   ### R<n>. ...

   ## Non-actionable (excluded)
   _<count> comments were classified as conversation/non-actionable and not turned into rules. Examples of what was skipped: …_
   ```

   Sort top-level by severity (blocker → major → minor). Within a severity, order by recurrence (most-cited first). Number rules sequentially across the whole document (R1, R2, … R_N) so `/ubi-review` can cite them stably.

7. **Report back.** After writing `playbook.md`, summarize:
   - How many comments were ingested
   - How many rules were extracted, broken down by severity (blocker / major / minor)
   - How many comments fell into "Non-actionable"
   - How many of the rules were promoted to major/blocker because Jeremy Evans authored or co-signed them
   - Suggested next step: `git diff playbook.md`, review, commit, push
