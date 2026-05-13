---
description: Distill PR review comments into categorized, severity-sorted playbooks (maintainers only).
---

You are regenerating two playbooks used by `/ubi-review`:
- **`playbook.md`** — rules from ubicloud's own PR review comments (the primary playbook).
- **`playbook-extra.md`** — rules from Jeremy Evans's review comments on his popular OSS repos (sequel, roda, rodauth, forme, …). Optional; only produced if Jeremy's comment data is available.

This is a **maintainer command** that should be run from inside a clone of the `ubi-reviewer` source repo, because it writes the playbooks back into the working tree to be committed.

## Prerequisite

The operator is responsible for fetching comments **before** running this command:

```sh
gh auth login                              # if not already
scripts/fetch-pr-comments.sh               # writes data/pr-comments.jsonl
scripts/fetch-jeremy-comments.sh           # writes data/jeremy-pr-comments.jsonl (optional)
```

If `data/pr-comments.jsonl` is missing or empty, stop and tell the operator to run the fetch script first. **Do not run the fetch scripts yourself.** If only `data/pr-comments.jsonl` exists, generate `playbook.md` and skip `playbook-extra.md` (note this in the report).

## Steps

1. **Verify location.** Confirm the working directory contains `.claude-plugin/plugin.json` with `"name": "ubi-reviewer"`. If not, stop and tell the operator to `cd` into their clone of the ubi-reviewer repo.

2. **Load all comments.** Read `data/pr-comments.jsonl`. Each line is `{pr?, kind, path?, diff_hunk?, body, user, created_at, html_url}` where `kind` is one of:
   - **`inline`** — comment on a specific diff line. Includes `path` and `diff_hunk` for code context. Authored by *any* reviewer.
   - **`conversation`** — comment on the PR conversation tab. No code context. Authored by **Jeremy Evans only** (filtered at fetch time).
   - **`summary`** — body of a PR review (approve / request changes). No code context. Authored by **Jeremy Evans only**.
   - **`description`** — body of a PR opened by Jeremy. Indicates the framing/justification he uses for his own changes. No code context. **Jeremy Evans only.**
   - **`commit`** — a git commit message authored by Jeremy. No `pr` field. **Jeremy Evans only.** These are extremely numerous (thousands), so treat them as a corpus of his "voice" — they show what he considers worth recording (test additions, refactors with reasoning, fix descriptions). Many will be terse; cluster broadly rather than per-message.

   Use **every** comment — do not filter by length, author, kind, or perceived value. The non-inline kinds lack `diff_hunk`, so the rule's "How to spot" guidance has to be derived from the body alone — that's fine, just acknowledge in the rule when the original feedback was architectural rather than line-level.

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

   **Author weighting:** comments authored by **Jeremy Evans** (`jeremyevans` on GitHub) are treated as **major or higher** by default — promote to blocker if the comment is about correctness, security, or testing rigor. Demote to minor only if Jeremy explicitly hedges ("nice to have", "minor", "not blocking", "optional", "if you want", "feel free to ignore"). This applies to all kinds (inline / conversation / summary / description / commit). For summary entries especially, watch for an overall verdict tone — if Jeremy used the review to request changes broadly, the rules derived from it are blocker-grade. For commit and description entries, the body is Jeremy's *self*-narration; weight commit-message patterns (e.g. "always include a test", "explain *why* in the body") as major when they show up consistently across many commits.

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

7. **Generate `playbook-extra.md` from Jeremy's external comments.** If `data/jeremy-pr-comments.jsonl` exists and is non-empty, repeat steps 2–6 against that file with these adjustments:
   - Each line additionally has a `repo` field (e.g. `jeremyevans/sequel`). Include the repo in the example links: `[sequel#1234](https://github.com/jeremyevans/sequel/pull/1234)`.
   - Every entry is authored by Jeremy (filtered at fetch time), so the author weighting in step 4 always applies.
   - **Number rules `E1, E2, …`** (E for "external") so they don't collide with the main playbook's `R*` numbering.
   - Default every rule to **major** severity. Promote to blocker for correctness/security/testing issues. Demote to minor only when Jeremy explicitly hedges in the comment ("nice to have", "minor", "not blocking", "optional", "if you want", "feel free to ignore").
   - Cluster carefully: many of Jeremy's external comments are framework-specific (Sequel internals, Roda routing tree, Rodauth feature wiring). Keep rules that translate to general code quality / patterns ubicloud uses. Move framework-trivia rules into a closing "Framework-specific (informational)" section rather than the main severity buckets.
   - Use this header:

     ```markdown
     # Ubicloud Reviewer Playbook — Extras (Jeremy Evans patterns)

     _Generated from N comments by jeremyevans across <list of repos>. Last updated: YYYY-MM-DD._

     ## How to use this playbook
     These rules are derived from Jeremy Evans's reviews on his own OSS projects
     (Sequel, Roda, Rodauth, Forme, …). They represent his coding standards as
     applied outside ubicloud. `/ubi-review` walks them alongside the main
     playbook; cite the rule number (E1, E2, …) when flagging an issue.
     ```

8. **Report back.** After writing the playbook(s), summarize:
   - For `playbook.md`: comments ingested **broken down by kind** (inline / conversation / summary / description / commit); rules extracted by severity; non-actionable count; how many were promoted to major/blocker due to Jeremy authorship.
   - For `playbook-extra.md` (if generated): comments ingested per source repo and by kind; rules extracted by severity; framework-specific count.
   - If `playbook-extra.md` was skipped, say so and link to `scripts/fetch-jeremy-comments.sh`.
   - Suggested next step: `git diff playbook*.md`, review, commit, push.
