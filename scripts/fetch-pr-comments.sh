#!/usr/bin/env bash
# Fetch PR review comments from a GitHub repo and save them as JSONL.
#
# Usage:
#   scripts/fetch-pr-comments.sh [--repo OWNER/REPO] [--limit N] [--out PATH] [--full]
#
# Defaults: repo=ubicloud/ubicloud, limit=2000, out=data/pr-comments.jsonl
#
# Behavior:
#   - First run (no existing $OUT): fetches the most recent $LIMIT comments.
#   - Subsequent runs: passes the newest stored created_at as `since` to the
#     GitHub API and appends only newer comments. Use --full to force a
#     refetch from scratch.
#
# Each output line is a JSON object with fields:
#   { pr, path, diff_hunk, body, user, created_at, html_url }
# Bot comments (user.type == "Bot") are excluded.

set -euo pipefail

REPO="ubicloud/ubicloud"
LIMIT=2000
OUT="data/pr-comments.jsonl"
FULL=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --limit) LIMIT="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --full) FULL=1; shift ;;
    -h|--help)
      sed -n '2,17p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

if ! gh auth status >/dev/null 2>&1; then
  echo "gh is not authenticated. Run 'gh auth login' first." >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT")"

JQ_PROJECT='
  .[]
  | select(.user.type != "Bot")
  | {
      pr: (.pull_request_url | capture("/pulls/(?<n>[0-9]+)") | .n | tonumber),
      path: .path,
      diff_hunk: .diff_hunk,
      body: .body,
      user: .user.login,
      created_at: .created_at,
      html_url: .html_url
    }
'

since=""
if [[ "$FULL" -eq 1 || ! -s "$OUT" ]]; then
  : > "$OUT"
  echo "Full fetch: up to $LIMIT review comments from $REPO..." >&2
else
  # Find the newest created_at we already have. The file may be in any order
  # (initial seed is desc, increments are asc), so scan all lines.
  since=$(jq -rs 'map(.created_at) | max' "$OUT")
  echo "Incremental fetch since $since from $REPO..." >&2
fi

before_count=$(wc -l < "$OUT" | tr -d ' ')

if [[ -n "$since" ]]; then
  # Incremental: ascending order, no LIMIT cap (volume should be small).
  page=1
  per_page=100
  while :; do
    # since is inclusive, so the most recent stored comment will come back; we
    # dedup at the end.
    batch=$(gh api -H "Accept: application/vnd.github+json" \
      "repos/$REPO/pulls/comments?per_page=$per_page&sort=created&direction=asc&since=$since&page=$page" 2>/dev/null)
    rows=$(jq 'length' <<<"$batch")
    [[ "$rows" -eq 0 ]] && break
    jq -c "$JQ_PROJECT" <<<"$batch" >> "$OUT"
    [[ "$rows" -lt "$per_page" ]] && break
    page=$((page + 1))
  done
else
  # Initial seed: descending order, capped at LIMIT.
  page=1
  per_page=100
  while :; do
    batch=$(gh api -H "Accept: application/vnd.github+json" \
      "repos/$REPO/pulls/comments?per_page=$per_page&sort=created&direction=desc&page=$page" 2>/dev/null)
    rows=$(jq 'length' <<<"$batch")
    [[ "$rows" -eq 0 ]] && break
    jq -c "$JQ_PROJECT" <<<"$batch" >> "$OUT"

    current=$(wc -l < "$OUT" | tr -d ' ')
    if [[ "$current" -ge "$LIMIT" ]]; then
      head -n "$LIMIT" "$OUT" > "$OUT.tmp" && mv "$OUT.tmp" "$OUT"
      break
    fi
    [[ "$rows" -lt "$per_page" ]] && break
    page=$((page + 1))
  done
fi

# Dedup by html_url, keep first occurrence, preserve order.
jq -cs 'unique_by(.html_url) | .[]' "$OUT" > "$OUT.tmp" && mv "$OUT.tmp" "$OUT"

after_count=$(wc -l < "$OUT" | tr -d ' ')
added=$((after_count - before_count))
echo "Wrote $after_count comments to $OUT (+$added new)" >&2
