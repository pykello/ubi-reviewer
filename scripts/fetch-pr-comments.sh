#!/usr/bin/env bash
# Fetch PR review activity from a GitHub repo. Three review surfaces:
#   1. Inline review comments   — repos/{R}/pulls/comments     (ALL authors)
#   2. PR conversation comments — repos/{R}/issues/comments    (filtered to $JE_USER)
#   3. PR review summaries      — repos/{R}/pulls/{n}/reviews  (filtered to $JE_USER)
#
# Inline comments are kept from every author to maximize signal across reviewers.
# Conversation comments and review summaries are filtered to Jeremy Evans — his
# commentary carries authoritative weight for the playbook's severity heuristics.
# Bot comments (user.type == "Bot") are always excluded.
#
# Usage:
#   scripts/fetch-pr-comments.sh [--repo OWNER/REPO] [--limit N] [--out PATH]
#                                [--je-user LOGIN] [--full]
#
# Defaults:
#   repo    = ubicloud/ubicloud
#   limit   = 2000  (per surface, on first seed; incrementals are uncapped)
#   je-user = jeremyevans
#   out     = data/pr-comments.jsonl
#
# Output JSONL fields:
#   { pr, kind, path?, diff_hunk?, body, user, created_at, html_url }
#   kind ∈ "inline" | "conversation" | "summary"
#   path and diff_hunk are only present for kind == "inline".

set -euo pipefail

REPO="ubicloud/ubicloud"
LIMIT_PER_SURFACE=2000
OUT="data/pr-comments.jsonl"
JE_USER="jeremyevans"
FULL=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --limit) LIMIT_PER_SURFACE="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --je-user) JE_USER="$2"; shift 2 ;;
    --full) FULL=1; shift ;;
    -h|--help) sed -n '2,26p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

if ! gh auth status >/dev/null 2>&1; then
  echo "gh is not authenticated. Run 'gh auth login' first." >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT")"
if [[ "$FULL" -eq 1 ]]; then : > "$OUT"; fi
[[ -f "$OUT" ]] || : > "$OUT"

# Migrate legacy rows that predate the `kind` field — they were inline-only.
if [[ -s "$OUT" ]]; then
  jq -c 'if has("kind") then . else . + {kind: "inline"} end' "$OUT" > "$OUT.tmp" && mv "$OUT.tmp" "$OUT"
fi

before_count=$(wc -l < "$OUT" | tr -d ' ')

max_created_at() {
  local kind=$1
  if [[ ! -s "$OUT" ]]; then echo ""; return; fi
  jq -rs --arg k "$kind" \
    'map(select(.kind == $k) | .created_at) | (max // "")' "$OUT"
}

append_bounded() {
  local filtered=$1 cur=$2 cap=$3
  [[ -z "$filtered" ]] && { echo "$cur"; return; }
  local n
  n=$(printf '%s\n' "$filtered" | wc -l | tr -d ' ')
  local remaining=$((cap - cur))
  if (( n > remaining )); then
    printf '%s\n' "$filtered" | head -n "$remaining" >> "$OUT"
    echo "$cap"
  else
    printf '%s\n' "$filtered" >> "$OUT"
    echo $((cur + n))
  fi
}

# Inline: keep ALL authors (broad reviewer signal). Bot comments excluded.
JQ_INLINE='
  .[]
  | select(.user.type != "Bot")
  | {
      pr: (.pull_request_url | capture("/pulls/(?<n>[0-9]+)") | .n | tonumber),
      kind: "inline",
      path: .path, diff_hunk: .diff_hunk,
      body: .body, user: .user.login,
      created_at: .created_at, html_url: .html_url
    }
'

# Conversation: $JE_USER only; only PR URLs (issue conversation excluded).
JQ_CONVO='
  .[]
  | select(.user.login == $user)
  | select(.html_url | test("/pull/"))
  | {
      pr: (.html_url | capture("/pull/(?<n>[0-9]+)") | .n | tonumber),
      kind: "conversation",
      body: .body, user: .user.login,
      created_at: .created_at, html_url: .html_url
    }
'

fetch_paged() {
  # Args: path-suffix jq-program kind
  local path=$1 jqp=$2 kind=$3
  local since
  since=$(max_created_at "$kind")
  local direction extra cap
  if [[ -n "$since" ]]; then
    direction="asc"; extra="&since=$since"; cap=999999
    echo "[$kind] incremental since $since..." >&2
  else
    direction="desc"; extra=""; cap=$LIMIT_PER_SURFACE
    echo "[$kind] full seed (up to $cap)..." >&2
  fi
  local collected=0 page=1 per_page=100
  while [[ $collected -lt $cap ]]; do
    local batch rows filtered
    batch=$(gh api -H "Accept: application/vnd.github+json" \
      "repos/$REPO/$path?per_page=$per_page&sort=created&direction=$direction&page=$page$extra" 2>/dev/null) || break
    rows=$(jq 'length' <<<"$batch")
    [[ "$rows" -eq 0 ]] && break
    filtered=$(jq -c --arg user "$JE_USER" "$jqp" <<<"$batch")
    collected=$(append_bounded "$filtered" "$collected" "$cap")
    [[ "$rows" -lt "$per_page" ]] && break
    page=$((page + 1))
  done
  echo "[$kind] +$collected" >&2
}

fetch_summaries() {
  local since
  since=$(max_created_at "summary")

  local q="is:pr reviewed-by:$JE_USER repo:$REPO"
  if [[ -n "$since" ]]; then
    q="$q updated:>=${since:0:10}"
    echo "[summary] incremental: PRs updated since ${since:0:10}..." >&2
  else
    echo "[summary] full seed: PRs reviewed by $JE_USER (cap $LIMIT_PER_SURFACE)..." >&2
  fi

  local pr_numbers
  pr_numbers=$(gh api --paginate -X GET 'search/issues' \
    -f "q=$q" --jq '.items[].number' 2>/dev/null \
    | awk -v n="$LIMIT_PER_SURFACE" 'NR<=n')

  local scanned=0 added=0
  for pr in $pr_numbers; do
    local reviews filtered
    reviews=$(gh api "repos/$REPO/pulls/$pr/reviews?per_page=100" 2>/dev/null) || continue
    filtered=$(jq -c --arg user "$JE_USER" --argjson pr "$pr" '
      .[]
      | select(.user.login == $user)
      | select(.body != null and (.body | length) > 0)
      | {
          pr: $pr,
          kind: "summary",
          body: .body, user: .user.login,
          created_at: .submitted_at, html_url: .html_url
        }
    ' <<<"$reviews")
    if [[ -n "$filtered" ]]; then
      local n
      n=$(printf '%s\n' "$filtered" | wc -l | tr -d ' ')
      printf '%s\n' "$filtered" >> "$OUT"
      added=$((added + n))
    fi
    scanned=$((scanned + 1))
  done
  echo "[summary] scanned $scanned PRs, added $added review bodies" >&2
}

fetch_paged "pulls/comments"  "$JQ_INLINE" "inline"
fetch_paged "issues/comments" "$JQ_CONVO"  "conversation"
fetch_summaries

# Dedup by html_url.
jq -cs 'unique_by(.html_url) | .[]' "$OUT" > "$OUT.tmp" && mv "$OUT.tmp" "$OUT"

after_count=$(wc -l < "$OUT" | tr -d ' ')
added=$((after_count - before_count))
echo "Wrote $after_count comments to $OUT (+$added new)" >&2
echo "Breakdown:" >&2
jq -rs 'group_by(.kind)
        | map({k: .[0].kind, n: length})
        | sort_by(-.n) | .[] | "  \(.k): \(.n)"' "$OUT" >&2
