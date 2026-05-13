# ubi-reviewer

A Claude Code plugin that reviews ubicloud code changes, guided by two playbooks of rules distilled from PR review comments:

- **`playbook.md`** — distilled from ubicloud's own PR review comments.
- **`playbook-extra.md`** — distilled from Jeremy Evans's review comments on his popular OSS repos (Sequel, Roda, Rodauth, Forme, …) — code patterns ubicloud actually uses.

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

### Fetching the latest playbooks

The playbooks (`playbook.md`, `playbook-extra.md`) are what give the reviewer its team-specific judgment. Maintainers refresh them periodically and push to this repo. To pull the latest into your local plugin install, run **inside Claude Code**:

```
/plugin marketplace update ubi-reviewer
/plugin install ubi-reviewer@ubi-reviewer    # reinstall to pick up the new playbooks
```

You can verify the version you have by checking the timestamp at the top of each playbook ("_Generated from N comments. Last updated: YYYY-MM-DD._"). If `/ubi-review` ever cites a rule number (R* or E*) that's higher than what your playbook contains, you're behind — refresh.

## How it works

- **`commands/ubi-review.md`** — the user-facing slash command. Determines what diff to review, then delegates to the subagent.
- **`agents/ubi-reviewer.md`** — the reviewer subagent. Reads both playbooks, walks every rule against the diff, produces structured findings.
- **`playbook.md`** — rules distilled from ubicloud's PR review comments (rule numbers `R1, R2, …`).
- **`playbook-extra.md`** — rules distilled from Jeremy Evans's reviews across his OSS repos (rule numbers `E1, E2, …`).
- **`commands/ubi-distill.md`** — a maintainer command that regenerates both playbooks from the JSONL data files.
- **`scripts/fetch-pr-comments.sh`** — fetches ubicloud's PR review comments into `data/pr-comments.jsonl`.
- **`scripts/fetch-jeremy-comments.sh`** — fetches Jeremy Evans's review comments across his popular OSS repos into `data/jeremy-pr-comments.jsonl`.

## Maintaining the playbooks

The playbooks are the heart of this plugin. Refresh them periodically:

```sh
git clone <this-repo>
cd ubi-reviewer
gh auth login                              # if not already

# 1. Fetch comments. First runs are full; subsequent runs are incremental.
scripts/fetch-pr-comments.sh               # ubicloud → data/pr-comments.jsonl
scripts/fetch-jeremy-comments.sh           # jeremyevans's OSS repos → data/jeremy-pr-comments.jsonl

# 2. In Claude Code, from inside this repo:
/ubi-distill

# 3. Review and ship the change.
git diff playbook.md playbook-extra.md
git commit -am "Refresh playbooks (NN comments)"
git push
```

Note: `/ubi-distill` does **not** call the fetch scripts — it expects the JSONL files to already exist. Run them yourself first. If `data/jeremy-pr-comments.jsonl` is absent, `/ubi-distill` will skip `playbook-extra.md` and proceed with only the main playbook.

### Five "review surfaces"

Both fetch scripts capture comments from five GitHub surfaces and write them to JSONL with a `kind` field that distinguishes them:

| `kind` | Endpoint | Has code context? |
|---|---|---|
| `inline` | `repos/{R}/pulls/comments` | yes (`path`, `diff_hunk`) |
| `conversation` | `repos/{R}/issues/comments` (filtered to PR URLs) | no |
| `summary` | `repos/{R}/pulls/{n}/reviews` (per reviewed PR) | no |
| `description` | `search/issues?q=is:pr+author:JE` (PR body) | no |
| `commit` | `repos/{R}/commits?author=JE` (commit messages) | no, no `pr` either |

Inline comments come from every reviewer; the other four surfaces are filtered to Jeremy Evans at fetch time. This is intentional — broad reviewer signal where the comment is anchored to a specific line, and Jeremy's authoritative voice everywhere else (including how he frames his own changes in PR descriptions and commit messages).

### `fetch-pr-comments.sh` (ubicloud)

Fetches from `ubicloud/ubicloud` by default. Incremental per surface via `since` (and `updated:>=<date>` for summaries, `created:>=<date>` for descriptions, `since=` for commits). Dedup by `html_url`. Default `--limit` is effectively unlimited (1M); first seed grabs everything the API will give us.

```sh
scripts/fetch-pr-comments.sh
scripts/fetch-pr-comments.sh --repo other-org/other-repo
scripts/fetch-pr-comments.sh --limit 5000
scripts/fetch-pr-comments.sh --je-user jeremyevans
scripts/fetch-pr-comments.sh --full          # force full refetch from scratch
```

### `fetch-jeremy-comments.sh` (Jeremy Evans's OSS repos)

Fetches every surface filtered to `jeremyevans` across his popular repos. Defaults to `jeremyevans/sequel`, `jeremyevans/roda`, `jeremyevans/rodauth`, `jeremyevans/forme`. Per-(repo, kind) incremental tracking; default `--limit` is effectively unlimited.

```sh
scripts/fetch-jeremy-comments.sh
scripts/fetch-jeremy-comments.sh --repos jeremyevans/sequel,jeremyevans/erubi
scripts/fetch-jeremy-comments.sh --limit 5000
scripts/fetch-jeremy-comments.sh --full
```

Note: GitHub's Search API caps results at 1000 per query, which bounds `summary` and `description` surfaces. The other surfaces are unbounded.

## Layout

```
ubi-reviewer/
├── .claude-plugin/
│   ├── marketplace.json    # so users can /plugin marketplace add
│   └── plugin.json         # plugin manifest
├── agents/
│   └── ubi-reviewer.md         # the reviewer subagent
├── commands/
│   ├── ubi-review.md           # /ubi-review — run a review
│   └── ubi-distill.md          # /ubi-distill — regenerate both playbooks
├── scripts/
│   ├── fetch-pr-comments.sh    # fetch ubicloud PR review comments
│   └── fetch-jeremy-comments.sh # fetch Jeremy Evans's comments across his OSS repos
├── data/                       # gitignored: fetched comments
├── playbook.md                 # main rules (R1..R_N), committed
├── playbook-extra.md           # Jeremy Evans patterns (E1..E_M), committed
└── README.md
```

## Development notes

- The plugin uses `${CLAUDE_PLUGIN_ROOT}` to reference the playbooks, so the agent works correctly when installed as a plugin (cached outside the user's working directory).
- Distillation runs inside the Claude Code session — no separate API key needed.
- `data/*.jsonl` is gitignored; only the curated playbooks are committed.
- Comments authored by **Jeremy Evans** (`jeremyevans`) are weighted to **major or higher** severity by the distill command unless he explicitly hedges ("nice to have", "not blocking", etc.). This applies both inside `playbook.md` (his comments on ubicloud) and to every rule in `playbook-extra.md` (his comments on his own OSS repos). Encoded in `commands/ubi-distill.md`.
