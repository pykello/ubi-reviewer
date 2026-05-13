#!/usr/bin/env bash
# Fetch PR review activity authored by Jeremy Evans across his popular OSS repos.
# Captures five review surfaces, all filtered to user.login == $USER:
#   1. Inline review comments   — repos/{R}/pulls/comments
#   2. PR conversation comments — repos/{R}/issues/comments  (filtered to /pull/ URLs)
#   3. PR review summaries      — repos/{R}/pulls/{n}/reviews (per reviewed PR)
#   4. PR descriptions          — search/issues?q=is:pr+author:$USER (PR body)
#   5. Commit messages          — repos/{R}/commits?author=$USER
#
# Usage:
#   scripts/fetch-jeremy-comments.sh [--repos R1,R2,...] [--user LOGIN]
#                                    [--limit N] [--out PATH] [--full]
#
# Defaults:
#   repos = jeremyevans/sequel,jeremyevans/roda,jeremyevans/rodauth,jeremyevans/forme
#   user  = jeremyevans
#   limit = 1000000  (effectively unlimited; bound by API not the cap)
#   out   = data/jeremy-pr-comments.jsonl
#
# Behavior:
#   - First run (or --full): seeds each surface up to $LIMIT comments per repo.
#   - Subsequent runs: per-(repo, kind) `since=<max created_at>` filter; for
#     summaries, restrict PR search to `updated:>=<date>`. Dedupes globally by
#     html_url at the end.
#
# Output JSONL fields:
#   { repo, pr, kind, path?, diff_hunk?, body, user, created_at, html_url }
#   kind ∈ "inline" | "conversation" | "summary" | "description" | "commit"
#   path and diff_hunk are only present for kind == "inline".
#   pr is absent for kind == "commit".

set -euo pipefail

DEFAULT_REPOS="jeremyevans/sequel,jeremyevans/roda,jeremyevans/rodauth,jeremyevans/forme"
REPOS_CSV="$DEFAULT_REPOS"
USER="jeremyevans"
LIMIT_PER_REPO=1000000
OUT="data/jeremy-pr-comments.jsonl"
FULL=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repos) REPOS_CSV="$2"; shift 2 ;;
    --user) USER="$2"; shift 2 ;;
    --limit) LIMIT_PER_REPO="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --full) FULL=1; shift ;;
    -h|--help) sed -n '2,29p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

IFS=',' read -ra REPOS <<<"$REPOS_CSV"

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

# Returns max created_at for (repo, kind), or empty string if none.
max_created_at() {
  local repo=$1 kind=$2
  if [[ ! -s "$OUT" ]]; then echo ""; return; fi
  jq -rs --arg r "$repo" --arg k "$kind" \
    'map(select(.repo == $r and .kind == $k) | .created_at) | (max // "")' "$OUT"
}

# Append filtered jsonl to OUT, capped by remaining slots; echo new count.
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

JQ_INLINE='
  .[]
  | select(.user.login == $user)
  | {
      repo: $repo, kind: "inline",
      pr: (.pull_request_url | capture("/pulls/(?<n>[0-9]+)") | .n | tonumber),
      path: .path, diff_hunk: .diff_hunk,
      body: .body, user: .user.login,
      created_at: .created_at, html_url: .html_url
    }
'

JQ_CONVO='
  .[]
  | select(.user.login == $user)
  | select(.html_url | test("/pull/"))
  | {
      repo: $repo, kind: "conversation",
      pr: (.html_url | capture("/pull/(?<n>[0-9]+)") | .n | tonumber),
      body: .body, user: .user.login,
      created_at: .created_at, html_url: .html_url
    }
'

# Paginated fetch from an endpoint that supports `since` + sort/direction.
# Args: repo path-suffix jq-program kind
fetch_paged() {
  local repo=$1 path=$2 jqp=$3 kind=$4
  local since
  since=$(max_created_at "$repo" "$kind")
  local direction extra cap
  if [[ -n "$since" ]]; then
    direction="asc"; extra="&since=$since"; cap=999999
    echo "[$repo $kind] incremental since $since..." >&2
  else
    direction="desc"; extra=""; cap=$LIMIT_PER_REPO
    echo "[$repo $kind] full seed (up to $cap)..." >&2
  fi
  local collected=0 page=1 per_page=100
  while [[ $collected -lt $cap ]]; do
    local batch rows filtered
    batch=$(gh api -H "Accept: application/vnd.github+json" \
      "repos/$repo/$path?per_page=$per_page&sort=created&direction=$direction&page=$page$extra" 2>/dev/null) || break
    rows=$(jq 'length' <<<"$batch")
    [[ "$rows" -eq 0 ]] && break
    filtered=$(jq -c --arg user "$USER" --arg repo "$repo" "$jqp" <<<"$batch")
    collected=$(append_bounded "$filtered" "$collected" "$cap")
    [[ "$rows" -lt "$per_page" ]] && break
    page=$((page + 1))
  done
  echo "[$repo $kind] +$collected" >&2
}

# Fetch PR review summaries (per-PR endpoint, since not supported there).
fetch_summaries() {
  local repo=$1
  local since
  since=$(max_created_at "$repo" "summary")

  local q="is:pr reviewed-by:$USER repo:$repo"
  if [[ -n "$since" ]]; then
    q="$q updated:>=${since:0:10}"
    echo "[$repo summary] incremental: PRs updated since ${since:0:10}..." >&2
  else
    echo "[$repo summary] full seed: PRs reviewed by $USER (cap $LIMIT_PER_REPO PRs)..." >&2
  fi

  # Get PR numbers. Search caps at 1000 results; we further bound with awk.
  local pr_numbers
  pr_numbers=$(gh api --paginate -X GET 'search/issues' \
    -f "q=$q" --jq '.items[].number' 2>/dev/null \
    | awk -v n="$LIMIT_PER_REPO" 'NR<=n')

  local scanned=0 added=0
  for pr in $pr_numbers; do
    local reviews filtered
    reviews=$(gh api "repos/$repo/pulls/$pr/reviews?per_page=100" 2>/dev/null) || continue
    filtered=$(jq -c --arg user "$USER" --arg repo "$repo" --argjson pr "$pr" '
      .[]
      | select(.user.login == $user)
      | select(.body != null and (.body | length) > 0)
      | {
          repo: $repo, kind: "summary",
          pr: $pr,
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
  echo "[$repo summary] scanned $scanned PRs, added $added review bodies" >&2
}

fetch_descriptions() {
  local repo=$1
  local since
  since=$(max_created_at "$repo" "description")

  local q="is:pr author:$USER repo:$repo"
  if [[ -n "$since" ]]; then
    q="$q created:>=${since:0:10}"
    echo "[$repo description] incremental: PRs created since ${since:0:10}..." >&2
  else
    echo "[$repo description] full seed: PRs authored by $USER (cap $LIMIT_PER_REPO)..." >&2
  fi

  local lines
  lines=$(gh api --paginate -X GET 'search/issues' -f "q=$q" \
    --jq '.items[]
          | select(.body != null and (.body | length) > 0)
          | {
              pr: .number,
              kind: "description",
              body: .body,
              user: .user.login,
              created_at: .created_at,
              html_url: .html_url
            }' 2>/dev/null \
    | jq -c --arg repo "$repo" '. + {repo: $repo}' \
    | awk -v n="$LIMIT_PER_REPO" 'NR<=n')
  if [[ -n "$lines" ]]; then
    local n
    n=$(printf '%s\n' "$lines" | wc -l | tr -d ' ')
    printf '%s\n' "$lines" >> "$OUT"
    echo "[$repo description] +$n" >&2
  else
    echo "[$repo description] +0" >&2
  fi
}

fetch_commits() {
  local repo=$1
  local since
  since=$(max_created_at "$repo" "commit")
  local cap=$LIMIT_PER_REPO
  local extra=""
  if [[ -n "$since" ]]; then
    extra="&since=$since"; cap=999999
    echo "[$repo commit] incremental since $since..." >&2
  else
    echo "[$repo commit] full seed: commits by $USER (cap $LIMIT_PER_REPO)..." >&2
  fi

  local collected=0 page=1 per_page=100
  while [[ $collected -lt $cap ]]; do
    local batch rows filtered
    batch=$(gh api -H "Accept: application/vnd.github+json" \
      "repos/$repo/commits?per_page=$per_page&author=$USER&page=$page$extra" 2>/dev/null) || break
    rows=$(jq 'length' <<<"$batch")
    [[ "$rows" -eq 0 ]] && break
    filtered=$(jq -c --arg user "$USER" --arg repo "$repo" '
      .[]
      | select(.commit.message != null and (.commit.message | length) > 0)
      | {
          repo: $repo,
          kind: "commit",
          body: .commit.message,
          user: $user,
          created_at: .commit.author.date,
          html_url: .html_url
        }
    ' <<<"$batch")
    collected=$(append_bounded "$filtered" "$collected" "$cap")
    [[ "$rows" -lt "$per_page" ]] && break
    page=$((page + 1))
  done
  echo "[$repo commit] +$collected" >&2
}

for REPO in "${REPOS[@]}"; do
  fetch_paged "$REPO" "pulls/comments"  "$JQ_INLINE" "inline"
  fetch_paged "$REPO" "issues/comments" "$JQ_CONVO"  "conversation"
  fetch_summaries "$REPO"
  fetch_descriptions "$REPO"
  fetch_commits "$REPO"
done

# Dedup globally by html_url.
jq -cs 'unique_by(.html_url) | .[]' "$OUT" > "$OUT.tmp" && mv "$OUT.tmp" "$OUT"

after_count=$(wc -l < "$OUT" | tr -d ' ')
added=$((after_count - before_count))
echo "Wrote $after_count comments to $OUT (+$added new)" >&2
echo "Breakdown:" >&2
jq -rs 'group_by([.repo, .kind])
        | map({k: (.[0].repo + " / " + .[0].kind), n: length})
        | sort_by(-.n) | .[] | "  \(.k): \(.n)"' "$OUT" >&2
