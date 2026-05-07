# ubi-reviewer

A Claude Code plugin that reviews ubicloud code changes, guided by a playbook of rules distilled from past PR review comments.

## Install (team members)

```sh
# In Claude Code
/plugin marketplace add <git-url-of-this-repo>
/plugin install ubi-reviewer@ubi-reviewer
/reload-plugins
```

Then, from inside an ubicloud checkout:

```
/ubi-reviewer:ubi-review           # review current branch vs main
/ubi-reviewer:ubi-review 1234       # review PR #1234
```

### Fetching the latest playbook

The playbook (`playbook.md`) is what gives the reviewer its team-specific judgment. Maintainers refresh it periodically and push to this repo. To pull the latest playbook into your local plugin install, run **inside Claude Code**:

```
/plugin marketplace update ubi-reviewer
/plugin install ubi-reviewer@ubi-reviewer    # reinstall to pick up the new playbook
```

You can verify the version you have by checking the timestamp at the top of the rendered playbook (the reviewer prints "_Generated from N comments. Last updated: YYYY-MM-DD._"). If `/ubi-review` ever cites a rule number that's higher than what your playbook contains, you're behind — refresh.

## How it works

- **`commands/ubi-review.md`** — the user-facing slash command. Determines what diff to review, then delegates to the subagent.
- **`agents/ubi-reviewer.md`** — the reviewer subagent. Reads `playbook.md`, walks every rule against the diff, produces structured findings.
- **`playbook.md`** — a curated set of rules distilled from past PR review comments, sorted by severity. Shared with the whole team via this repo.
- **`commands/ubi-distill.md`** — a maintainer command that regenerates the playbook from `data/pr-comments.jsonl`.
- **`scripts/fetch-pr-comments.sh`** — fetches review comments from the GitHub API into `data/pr-comments.jsonl`.

## Maintaining the playbook

The playbook is the heart of this plugin. Refresh it periodically:

```sh
git clone <this-repo>
cd ubi-reviewer
gh auth login                              # if not already

scripts/fetch-pr-comments.sh

# 2. In Claude Code, from inside this repo:
/ubi-distill

# 3. Review and ship the change.
git diff playbook.md
git commit -am "Refresh playbook (NN comments)"
git push
```

Note: `/ubi-distill` does **not** call the fetch script — it expects `data/pr-comments.jsonl` to already exist. Run `fetch-pr-comments.sh` yourself first.

By default `scripts/fetch-pr-comments.sh` pulls the most recent 2000 review comments from `ubicloud/ubicloud` on first run, then incrementally fetches only new comments on subsequent runs (using the GitHub API's `since` filter and deduping by `html_url`). Override:

```sh
scripts/fetch-pr-comments.sh --limit 500
scripts/fetch-pr-comments.sh --repo other-org/other-repo
scripts/fetch-pr-comments.sh --full           # force full refetch from scratch
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
- Comments authored by **Jeremy Evans** (`jeremyevans`) are weighted to **major or higher** severity by the distill command unless he explicitly hedges ("nice to have", "not blocking", etc.). Encoded in `commands/ubi-distill.md`.
