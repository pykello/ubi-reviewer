#!/usr/bin/env bash
# Fetch PR review comments authored by Jeremy Evans across his popular OSS repos.
#
# Usage:
#   scripts/fetch-jeremy-comments.sh [--repos R1,R2,...] [--user LOGIN]
#                                    [--limit N] [--out PATH] [--full]
#
# Defaults:
#   repos = jeremyevans/sequel, jeremyevans/roda, jeremyevans/rodauth, jeremyevans/forme
#   user  = jeremyevans
#   limit = 1000 (per repo, applies on first seed only)
#   out   = data/jeremy-pr-comments.jsonl
#
# Behavior:
#   - First run (or --full): seeds up to $LIMIT comments per repo, newest first.
#   - Subsequent runs: per-repo `since=<max created_at>` filter, appends only
#     new comments. Dedupes globally by html_url at the end.
#
# Output JSONL fields:
#   { repo, pr, path, diff_hunk, body, user, created_at, html_url }
#
# Only comments authored by $user are kept (these are the review patterns we
# care about — Jeremy as the reviewer of his own projects).

set -euo pipefail

DEFAULT_REPOS="jeremyevans/sequel,jeremyevans/roda,jeremyevans/rodauth,jeremyevans/forme"
REPOS_CSV="$DEFAULT_REPOS"
USER="jeremyevans"
LIMIT_PER_REPO=1000
OUT="data/jeremy-pr-comments.jsonl"
FULL=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repos) REPOS_CSV="$2"; shift 2 ;;
    --user) USER="$2"; shift 2 ;;
    --limit) LIMIT_PER_REPO="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --full) FULL=1; shift ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

IFS=',' read -ra REPOS <<<"$REPOS_CSV"

if ! gh auth status >/dev/null 2>&1; then
  echo "gh is not authenticated. Run 'gh auth login' first." >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT")"

JQ_PROJECT='
  .[]
  | select(.user.login == $user)
  | {
      repo: $repo,
      pr: (.pull_request_url | capture("/pulls/(?<n>[0-9]+)") | .n | tonumber),
      path: .path,
      diff_hunk: .diff_hunk,
      body: .body,
      user: .user.login,
      created_at: .created_at,
      html_url: .html_url
    }
'

if [[ "$FULL" -eq 1 ]]; then
  : > "$OUT"
fi
[[ -f "$OUT" ]] || : > "$OUT"

before_count=$(wc -l < "$OUT" | tr -d ' ')

for REPO in "${REPOS[@]}"; do
  since=""
  if [[ -s "$OUT" ]]; then
    since=$(jq -rs --arg r "$REPO" 'map(select(.repo == $r) | .created_at) | (max // "")' "$OUT")
  fi

  if [[ -n "$since" ]]; then
    echo "[$REPO] incremental since $since..." >&2
    direction="asc"
    extra="&since=$since"
    cap=999999
  else
    echo "[$REPO] full seed (up to $LIMIT_PER_REPO comments by $USER)..." >&2
    direction="desc"
    extra=""
    cap=$LIMIT_PER_REPO
  fi

  collected=0
  page=1
  per_page=100
  while [[ $collected -lt $cap ]]; do
    batch=$(gh api -H "Accept: application/vnd.github+json" \
      "repos/$REPO/pulls/comments?per_page=$per_page&sort=created&direction=$direction&page=$page$extra" 2>/dev/null)
    rows=$(jq 'length' <<<"$batch")
    [[ "$rows" -eq 0 ]] && break

    filtered=$(jq -c --arg user "$USER" --arg repo "$REPO" "$JQ_PROJECT" <<<"$batch")
    if [[ -n "$filtered" ]]; then
      fcount=$(printf '%s\n' "$filtered" | wc -l | tr -d ' ')
      remaining=$((cap - collected))
      if [[ $fcount -gt $remaining ]]; then
        printf '%s\n' "$filtered" | head -n "$remaining" >> "$OUT"
        collected=$cap
      else
        printf '%s\n' "$filtered" >> "$OUT"
        collected=$((collected + fcount))
      fi
    fi

    [[ "$rows" -lt "$per_page" ]] && break
    page=$((page + 1))
  done
  echo "[$REPO] +$collected" >&2
done

# Dedup by html_url across all repos.
jq -cs 'unique_by(.html_url) | .[]' "$OUT" > "$OUT.tmp" && mv "$OUT.tmp" "$OUT"

after_count=$(wc -l < "$OUT" | tr -d ' ')
added=$((after_count - before_count))
echo "Wrote $after_count comments to $OUT (+$added new)" >&2
