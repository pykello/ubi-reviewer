# ubi-reviewer

A Claude Code plugin that reviews ubicloud code changes, guided by a playbook of rules distilled from past PR review comments.

## Install (team members)

```sh
# In Claude Code
/plugin marketplace add <git-url-of-this-repo>
/plugin install ubi-reviewer@ubi-reviewer
```

Then, from inside an ubicloud checkout:

```
/ubi-review            # review current branch vs main
/ubi-review 1234       # review PR #1234
```

## How it works

- **`commands/ubi-review.md`** — the user-facing slash command. Determines what diff to review, then delegates to the subagent.
- **`agents/ubi-reviewer.md`** — the reviewer subagent. Reads `playbook.md`, walks the diff, produces structured findings.
- **`playbook.md`** — a curated set of rules distilled from past PR review comments. Shared with the whole team via this repo.
- **`commands/ubi-distill.md`** — a maintainer command that regenerates the playbook from the latest PR comments.
- **`scripts/fetch-pr-comments.sh`** — fetches review comments from the GitHub API into `data/pr-comments.jsonl`.

## Maintaining the playbook

The playbook is the heart of this plugin. Refresh it periodically:

```sh
git clone <this-repo>
cd ubi-reviewer
gh auth login                              # if not already
# In Claude Code, from inside this repo:
/ubi-distill
git diff playbook.md                       # review the changes
git commit -am "Refresh playbook (NN comments)"
git push
```

Team members re-installing or updating the plugin pick up the new playbook.

By default `scripts/fetch-pr-comments.sh` pulls the most recent 2000 review comments from `ubicloud/ubicloud`. Override:

```sh
scripts/fetch-pr-comments.sh --limit 500
scripts/fetch-pr-comments.sh --repo other-org/other-repo
```

## Layout

```
ubi-reviewer/
├── .claude-plugin/
│   ├── marketplace.json    # so users can /plugin marketplace add
│   └── plugin.json         # plugin manifest
├── agents/
│   └── ubi-reviewer.md     # the reviewer subagent
├── commands/
│   ├── ubi-review.md       # /ubi-review — run a review
│   └── ubi-distill.md      # /ubi-distill — regenerate playbook
├── scripts/
│   └── fetch-pr-comments.sh
├── data/                   # gitignored: fetched comments
├── playbook.md             # the curated rules (committed)
└── README.md
```

## Development notes

- The plugin uses `${CLAUDE_PLUGIN_ROOT}` to reference `playbook.md`, so the agent works correctly when installed as a plugin (cached outside the user's working directory).
- Distillation runs inside the Claude Code session — no separate API key needed.
- `data/pr-comments.jsonl` is gitignored; only the curated playbook is committed.
