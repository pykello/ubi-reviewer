---
description: Review the current branch (or a given PR) against the ubicloud reviewer playbook.
argument-hint: "[PR number or empty for current branch]"
---

Run a code review on changes in the ubicloud repository, using both general code review skills and the rules in the playbook at `${CLAUDE_PLUGIN_ROOT}/playbook.md`.

## Determine what to review

- If the user passed a PR number as an argument (`$ARGUMENTS`), fetch its diff with `gh pr diff <number>` and the metadata with `gh pr view <number> --json title,body,baseRefName,headRefName,author`.
- Otherwise, review the current branch's diff against its merge base with `main`:
  - `base=$(git merge-base HEAD origin/main 2>/dev/null || git merge-base HEAD main)`
  - `git diff $base...HEAD`
  - Also list the changed files with `git diff --name-only $base...HEAD` and the commit messages with `git log $base..HEAD --oneline`.

If neither succeeds (no PR number, not in a git repo, no main branch), stop and tell the user.

## Run the review

Delegate the actual review to the `ubi-reviewer` subagent. Pass it:
- The diff (full, as a single block)
- The list of changed files
- The PR title/body or recent commit messages for context

The subagent will read the playbook itself and produce structured findings.

## Present results

Relay the subagent's findings to the user verbatim. Do not add your own opinions or summaries beyond what the subagent reported. If the subagent flagged zero issues, say so plainly — don't pad.
