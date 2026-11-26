#!/usr/bin/env bash
# Prints the last year of GitHub contributions for the gh-authenticated user as
# compact JSON: {"login","total","weeks":[[{"d":date,"c":count,"l":level 0-4},...],...]}
# Cached for 30 min in ~/.cache/quickshell/dash/contrib.json; pass --force to refresh.
CACHE_DIR="${QS_CACHE_DASH:-$HOME/.cache/quickshell/dash}"
CACHE="$CACHE_DIR/contrib.json"
mkdir -p "$CACHE_DIR"

if [[ "$1" != "--force" && -s "$CACHE" ]] && [[ $(( $(date +%s) - $(stat -c %Y "$CACHE") )) -lt 1800 ]]; then
    cat "$CACHE"; exit 0
fi

out=$(gh api graphql -f query='
query {
  viewer {
    login
    contributionsCollection {
      contributionCalendar {
        totalContributions
        weeks { contributionDays { date contributionCount contributionLevel } }
      }
    }
  }
}' --jq '
  .data.viewer as $v
  | {
      login: $v.login,
      total: $v.contributionsCollection.contributionCalendar.totalContributions,
      weeks: [ $v.contributionsCollection.contributionCalendar.weeks[]
               | [ .contributionDays[]
                   | { d: .date, c: .contributionCount,
                       l: ({NONE:0,FIRST_QUARTILE:1,SECOND_QUARTILE:2,THIRD_QUARTILE:3,FOURTH_QUARTILE:4}[.contributionLevel]) } ] ]
    }' 2>/dev/null)

if [[ -n "$out" ]]; then
    printf '%s\n' "$out" > "$CACHE.tmp" && mv "$CACHE.tmp" "$CACHE"
    printf '%s\n' "$out"
elif [[ -s "$CACHE" ]]; then
    cat "$CACHE"              # offline: serve stale data
else
    echo '{"error":"gh api failed (offline or not logged in?)"}'
fi
