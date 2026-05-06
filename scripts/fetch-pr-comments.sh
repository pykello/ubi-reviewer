#!/usr/bin/env bash
# Fetch PR review comments from a GitHub repo and save them as JSONL.
#
# Usage:
#   scripts/fetch-pr-comments.sh [--repo OWNER/REPO] [--limit N] [--out PATH]
#
# Defaults: repo=ubicloud/ubicloud, limit=2000, out=data/pr-comments.jsonl
#
# Each output line is a JSON object with fields:
#   { pr, path, diff_hunk, body, user, created_at, html_url }
# Bot comments (user.type == "Bot") are excluded.

set -euo pipefail

REPO="ubicloud/ubicloud"
LIMIT=2000
OUT="data/pr-comments.jsonl"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --limit) LIMIT="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

if ! gh auth status >/dev/null 2>&1; then
  echo "gh is not authenticated. Run 'gh auth login' first." >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT")"
: > "$OUT"

echo "Fetching up to $LIMIT review comments from $REPO..." >&2

# /pulls/comments lists review comments across the repo. We page manually so we
# can stop as soon as we have $LIMIT comments without SIGPIPE-ing gh mid-stream.
page=1
per_page=100
while :; do
  batch=$(gh api -H "Accept: application/vnd.github+json" \
    "repos/$REPO/pulls/comments?per_page=$per_page&sort=created&direction=desc&page=$page" 2>/dev/null)
  rows=$(jq 'length' <<<"$batch")
  [[ "$rows" -eq 0 ]] && break

  jq -c '
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
  ' <<<"$batch" >> "$OUT"

  current=$(wc -l < "$OUT" | tr -d ' ')
  if [[ "$current" -ge "$LIMIT" ]]; then
    # Trim any overage from the last batch
    head -n "$LIMIT" "$OUT" > "$OUT.tmp" && mv "$OUT.tmp" "$OUT"
    break
  fi
  [[ "$rows" -lt "$per_page" ]] && break
  page=$((page + 1))
done

count=$(wc -l < "$OUT" | tr -d ' ')
echo "Wrote $count comments to $OUT" >&2
