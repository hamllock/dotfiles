#!/usr/bin/env python3
"""LeetCode stats for the dash: solved counts + a GitHub-style 53-week submission
calendar for one user, from LeetCode's public GraphQL endpoint (no login needed).

Prints JSON: {login, solved:{all,easy,medium,hard}, totals:{...}, activeDays,
              total, weeks:[[{d, c, l}] x <=7] x 53}
Cached for 30 min in ~/.cache/quickshell/dash/leetcode_stats.json; --force refreshes.
"""
import datetime as dt
import json
import os
import sys
import time
import urllib.request

USER = os.environ.get("LEETCODE_USER", "hamllock")
CACHE = os.path.expanduser("~/.cache/quickshell/dash/leetcode_stats.json")
MAX_AGE = 1800


def gql(query, variables):
    req = urllib.request.Request(
        "https://leetcode.com/graphql",
        data=json.dumps({"query": query, "variables": variables}).encode(),
        headers={"Content-Type": "application/json", "Referer": "https://leetcode.com",
                 "User-Agent": "Mozilla/5.0"},
    )
    with urllib.request.urlopen(req, timeout=12) as r:
        return json.load(r)["data"]


def level(c):
    return 0 if c <= 0 else 1 if c == 1 else 2 if c <= 3 else 3 if c <= 6 else 4


def build():
    today = dt.date.today()
    this_year, last_year = today.year, today.year - 1
    q = """query($u:String!,$y1:Int!,$y2:Int!){
      matchedUser(username:$u){ username
        submitStatsGlobal{acSubmissionNum{difficulty count}}
        a:userCalendar(year:$y1){submissionCalendar}
        b:userCalendar(year:$y2){submissionCalendar} }
      allQuestionsCount{difficulty count} }"""
    d = gql(q, {"u": USER, "y1": last_year, "y2": this_year})
    u = d["matchedUser"]
    if not u:
        return {"error": f"LeetCode user '{USER}' not found"}

    per_day = {}
    for key in ("a", "b"):
        cal = json.loads((u.get(key) or {}).get("submissionCalendar") or "{}")
        for ts, n in cal.items():
            day = dt.datetime.fromtimestamp(int(ts), dt.timezone.utc).date()
            per_day[day] = per_day.get(day, 0) + int(n)

    # 53 columns, Sunday-first, last column ends today (same shape as GitHub's)
    start = today - dt.timedelta(days=(today.weekday() + 1) % 7 + 52 * 7)
    weeks, day = [], start
    while day <= today:
        if not weeks or day.weekday() == 6:
            weeks.append([])
        c = per_day.get(day, 0)
        weeks[-1].append({"d": day.isoformat(), "c": c, "l": level(c)})
        day += dt.timedelta(days=1)

    solved = {x["difficulty"].lower(): x["count"] for x in u["submitStatsGlobal"]["acSubmissionNum"]}
    totals = {x["difficulty"].lower(): x["count"] for x in d["allQuestionsCount"]}
    in_range = [c for w in weeks for c in w]
    return {
        "login": u["username"],
        "solved": solved,
        "totals": totals,
        "total": sum(c["c"] for c in in_range),
        "activeDays": sum(1 for c in in_range if c["c"] > 0),
        "weeks": weeks,
    }


def main():
    force = "--force" in sys.argv
    if not force and os.path.exists(CACHE) and time.time() - os.path.getmtime(CACHE) < MAX_AGE:
        print(open(CACHE).read().strip())
        return
    try:
        out = json.dumps(build(), separators=(",", ":"))
        os.makedirs(os.path.dirname(CACHE), exist_ok=True)
        with open(CACHE + ".tmp", "w") as f:
            f.write(out)
        os.replace(CACHE + ".tmp", CACHE)
        print(out)
    except Exception as e:  # offline: serve stale data if we have it
        if os.path.exists(CACHE):
            print(open(CACHE).read().strip())
        else:
            print(json.dumps({"error": f"LeetCode request failed: {e}"}))


main()
