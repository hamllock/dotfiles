#!/usr/bin/env bash
# Prints today's LeetCode daily problem as JSON {title, slug, difficulty, id, date}
# using LeetCode's public GraphQL endpoint (no login needed). Cached until the daily
# rolls over (00:00 UTC) in ~/.cache/quickshell/dash/leetcode_daily.json.
CACHE_DIR="${QS_CACHE_DASH:-$HOME/.cache/quickshell/dash}"
CACHE="$CACHE_DIR/leetcode_daily.json"
mkdir -p "$CACHE_DIR"
today=$(date -u +%F)

if [[ -s "$CACHE" ]] && grep -q "\"date\":\"$today\"" "$CACHE" && grep -q '"tags"' "$CACHE"; then cat "$CACHE"; exit 0; fi

out=$(curl -s --max-time 10 https://leetcode.com/graphql \
    -H 'Content-Type: application/json' -H 'Referer: https://leetcode.com' \
    -d '{"query":"query{activeDailyCodingChallengeQuestion{date question{title titleSlug difficulty questionFrontendId acRate topicTags{name}}}}"}' \
  | jq -c '.data.activeDailyCodingChallengeQuestion | select(. != null)
           | {date, title: .question.title, slug: .question.titleSlug,
              difficulty: .question.difficulty, id: .question.questionFrontendId,
              acRate: (.question.acRate | floor), tags: [.question.topicTags[].name]}' 2>/dev/null)

if [[ -n "$out" ]]; then printf '%s\n' "$out" > "$CACHE"; echo "$out"
elif [[ -s "$CACHE" ]]; then cat "$CACHE"
else echo '{}'; fi
