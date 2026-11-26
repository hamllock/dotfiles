#!/usr/bin/env python3
"""lc - tiny LeetCode backend for the Quickshell LeetCode window (LeetCode.qml).

LeetCode has no official API; this uses the same endpoints as the website.
Every command prints one JSON object on stdout.

  lc.py fetch  <slug|daily>   problem info; creates ~/leetcode/<id>-<slug>/solution.cpp
  lc.py run    <slug>         run solution against <dir>/tests.txt
  lc.py submit <slug>         submit solution
  lc.py list   '<json>'       browse problems: {difficulty,status,tags,orderBy,sortOrder,skip,limit}
  lc.py random '<json>'       random free problem matching the same filters
  lc.py search <query>        search the problem list
  lc.py whoami                check the login
  lc.py lang   [slug]         show / set the solution language (one of LANGS)

Login: the Cookie header string (needs LEETCODE_SESSION and csrftoken) from
~/.config/lc/cookie, falling back to the one leetcode.nvim saved.
Config: ~/.config/lc/config.json, e.g. {"lang": "cpp", "root": "~/leetcode"}.
"""
import html
import json
import os
import re
import sys
import time

import requests

BASE = "https://leetcode.com"
CONF_DIR = os.path.expanduser("~/.config/lc")
COOKIE_FILES = [os.path.join(CONF_DIR, "cookie"), os.path.expanduser("~/.cache/nvim/leetcode/cookie")]
UA = "Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0"

LANG_EXT = {"cpp": "cpp", "python3": "py", "java": "java", "c": "c", "rust": "rs",
            "golang": "go", "javascript": "js", "typescript": "ts", "php": "php"}
# languages the dashboard offers: the ones nvim has a language server for
# (clangd, pyright, typescript-tools, intelephense, rust-analyzer via rustaceanvim)
LANGS = ["cpp", "c", "python3", "javascript", "typescript", "rust", "php"]

# Local-only prelude for C++ so clangd understands the file. Everything between the
# markers is stripped before the code is sent to LeetCode (which already provides
# these headers and the ListNode/TreeNode types).
LOCAL_BEGIN = "// @lc-local-begin  (editor-only; stripped before run/submit)"
LOCAL_END = "// @lc-local-end"
CPP_PRELUDE = "#include <bits/stdc++.h>\nusing namespace std;\n"
# Rust: LeetCode wraps `impl Solution` itself; locally it needs the struct, a main and the
# list/tree types (LeetCode only shows those as comments). Cargo.toml lets rust-analyzer in.
RUST_PRELUDE = "#![allow(dead_code)]\nstruct Solution;\nfn main() {}\n"
RUST_LISTNODE = ("#[derive(PartialEq, Eq, Clone, Debug)]\npub struct ListNode { pub val: i32, pub next: Option<Box<ListNode>> }\n"
                 "impl ListNode { #[inline] fn new(val: i32) -> Self { ListNode { next: None, val } } }\n")
RUST_TREENODE = ("#[derive(Debug, PartialEq, Eq)]\npub struct TreeNode { pub val: i32, "
                 "pub left: Option<std::rc::Rc<std::cell::RefCell<TreeNode>>>, pub right: Option<std::rc::Rc<std::cell::RefCell<TreeNode>>> }\n"
                 "impl TreeNode { #[inline] pub fn new(val: i32) -> Self { TreeNode { val, left: None, right: None } } }\n")
CPP_LISTNODE = ("struct ListNode {\n    int val; ListNode *next;\n    ListNode() : val(0), next(nullptr) {}\n"
                "    ListNode(int x) : val(x), next(nullptr) {}\n    ListNode(int x, ListNode *n) : val(x), next(n) {}\n};\n")
CPP_TREENODE = ("struct TreeNode {\n    int val; TreeNode *left; TreeNode *right;\n"
                "    TreeNode() : val(0), left(nullptr), right(nullptr) {}\n"
                "    TreeNode(int x) : val(x), left(nullptr), right(nullptr) {}\n"
                "    TreeNode(int x, TreeNode *l, TreeNode *r) : val(x), left(l), right(r) {}\n};\n")


def out(obj):
    print(json.dumps(obj, separators=(",", ":")))


def config():
    cfg = {"lang": "cpp", "root": "~/leetcode"}
    try:
        with open(os.path.join(CONF_DIR, "config.json")) as f:
            cfg.update(json.load(f))
    except (OSError, ValueError):
        pass
    cfg["root"] = os.path.expanduser(cfg["root"])
    return cfg


def cookies():
    for path in COOKIE_FILES:
        try:
            raw = open(path).read().strip()
        except OSError:
            continue
        jar = {}
        for part in raw.split(";"):
            if "=" in part:
                k, v = part.strip().split("=", 1)
                jar[k] = v
        if jar.get("LEETCODE_SESSION") and jar.get("csrftoken"):
            return jar
    return None


def session(slug=None, auth=False):
    s = requests.Session()
    s.headers.update({"User-Agent": UA, "Content-Type": "application/json", "Origin": BASE,
                      "Referer": f"{BASE}/problems/{slug}/" if slug else BASE})
    jar = cookies()
    if jar:
        s.cookies.update(jar)
        s.headers["x-csrftoken"] = jar["csrftoken"]
    elif auth:
        raise SystemExit(out({"error": "Not signed in: put your LeetCode Cookie header in ~/.config/lc/cookie"}))
    return s


def gql(s, query, variables=None):
    r = s.post(f"{BASE}/graphql", json={"query": query, "variables": variables or {}}, timeout=20)
    r.raise_for_status()
    data = r.json()
    if data.get("errors"):
        raise RuntimeError(data["errors"][0].get("message", "GraphQL error"))
    return data["data"]


# ---------------------------------------------------------------------------- problems
Q_QUESTION = """query($slug:String!){ question(titleSlug:$slug){
  questionId questionFrontendId title titleSlug content difficulty isPaidOnly acRate
  likes dislikes exampleTestcaseList metaData topicTags{name} codeSnippets{langSlug code}
  hints } }"""
Q_DAILY = "query{activeDailyCodingChallengeQuestion{question{titleSlug}}}"


IMG_CACHE = os.path.expanduser("~/.cache/lc/img")


def image_size(path):
    """(w, h) of a PNG/GIF/JPEG/WebP file from its header, or None."""
    import struct
    try:
        with open(path, "rb") as f:
            head = f.read(32)
            if head[:8] == b"\x89PNG\r\n\x1a\n":
                return struct.unpack(">II", head[16:24])
            if head[:6] in (b"GIF87a", b"GIF89a"):
                return struct.unpack("<HH", head[6:10])
            if head[:4] == b"RIFF" and head[8:12] == b"WEBP":
                f.seek(12); chunk = f.read(30)
                if chunk[:4] == b"VP8X":
                    w = int.from_bytes(chunk[12:15], "little") + 1
                    h = int.from_bytes(chunk[15:18], "little") + 1
                    return w, h
                return None
            if head[:2] == b"\xff\xd8":
                f.seek(2)
                while True:
                    marker = f.read(2)
                    if len(marker) < 2 or marker[0] != 0xFF:
                        return None
                    length = struct.unpack(">H", f.read(2))[0]
                    if marker[1] in (0xC0, 0xC1, 0xC2):
                        f.read(1)
                        h, w = struct.unpack(">HH", f.read(4))
                        return w, h
                    f.seek(length - 2, 1)
    except (OSError, struct.error):
        pass
    return None


def fix_images(content, s):
    """Qt's rich text can't fetch remote images here, so download them into
    ~/.cache/lc/img and point <img> at the local file, sized to at most 640px wide."""
    import hashlib
    os.makedirs(IMG_CACHE, exist_ok=True)

    def repl(m):
        tag = m.group(0)
        src = re.search(r'src="([^"]+)"', tag)
        if not src:
            return tag
        url = html.unescape(src.group(1))
        if url.startswith("//"):
            url = "https:" + url
        elif url.startswith("/"):
            url = BASE + url
        ext = os.path.splitext(url.split("?")[0])[1][:5] or ".png"
        local = os.path.join(IMG_CACHE, hashlib.sha1(url.encode()).hexdigest()[:16] + ext)
        if not os.path.exists(local):
            try:
                r = s.get(url, timeout=15)
                r.raise_for_status()
                with open(local, "wb") as f:
                    f.write(r.content)
            except requests.RequestException:
                return tag
        w = re.search(r"width:\s*([\d.]+)px", tag)
        h = re.search(r"height:\s*([\d.]+)px", tag)
        size = (float(w.group(1)), float(h.group(1)) if h else None) if w else image_size(local)
        attrs = ""
        if size and size[0]:
            scale = min(1.0, 640 / size[0])
            attrs = f' width="{int(size[0] * scale)}"' + (f' height="{int(size[1] * scale)}"' if size[1] else "")
        return f'<p align="center"><img src="file://{local}"{attrs}></p>'
    return re.sub(r"<img[^>]*>", repl, content or "")


def clean_html(content):
    """Drop LeetCode's inline styles: they use the site's CSS variables
    (color: var(--text-secondary) ...), which Qt can't resolve and renders as black.
    The window styles these elements itself (classes are kept)."""
    return re.sub(r'\s+style="[^"]*"', "", content)


def problem_dir(cfg, q):
    return os.path.join(cfg["root"], f"{q['questionFrontendId']}-{q['titleSlug']}")


def find_dir(cfg, slug):
    try:
        for name in os.listdir(cfg["root"]):
            if name.split("-", 1)[-1] == slug:
                return os.path.join(cfg["root"], name)
    except OSError:
        pass
    return None


def cmd_fetch(arg):
    cfg = config()
    s = session(arg)
    slug = arg
    if arg == "daily":
        slug = gql(s, Q_DAILY)["activeDailyCodingChallengeQuestion"]["question"]["titleSlug"]
        s.headers["Referer"] = f"{BASE}/problems/{slug}/"
    q = gql(s, Q_QUESTION, {"slug": slug})["question"]
    if not q:
        return out({"error": f"No problem called '{slug}'"})
    if q["isPaidOnly"] and not q["content"]:
        return out({"error": f"{q['title']} is a Premium problem"})

    meta = json.loads(q["metaData"] or "{}")
    params = [p["name"] for p in meta.get("params", [])] or ["input"]
    lang = cfg["lang"]
    snippet = next((c["code"] for c in q["codeSnippets"] or [] if c["langSlug"] == lang), "")

    d = problem_dir(cfg, q)
    os.makedirs(d, exist_ok=True)
    path = os.path.join(d, f"solution.{LANG_EXT.get(lang, lang)}")
    if not os.path.exists(path):
        header = []
        if lang == "cpp":
            body = CPP_PRELUDE
            if "ListNode" in snippet:
                body += CPP_LISTNODE
            if "TreeNode" in snippet:
                body += CPP_TREENODE
            header = [LOCAL_BEGIN, body.rstrip("\n"), LOCAL_END, ""]
        elif lang == "rust":
            body = RUST_PRELUDE
            if "ListNode" in snippet:
                body += RUST_LISTNODE
            if "TreeNode" in snippet:
                body += RUST_TREENODE
            header = [LOCAL_BEGIN, body.rstrip("\n"), LOCAL_END, ""]
            cargo = os.path.join(d, "Cargo.toml")
            if not os.path.exists(cargo):
                with open(cargo, "w") as f:
                    f.write(f'[package]\nname = "lc{q["questionFrontendId"]}"\nversion = "0.1.0"\nedition = "2021"\n\n'
                            '[[bin]]\nname = "solution"\npath = "solution.rs"\n')
        elif lang == "php":
            # intelephense needs the opening tag; LeetCode rejects it, so it's local-only
            header = [LOCAL_BEGIN, "<?php", LOCAL_END, ""]
        cm = "#" if lang == "python3" else "//"
        header += [f"{cm} {q['questionFrontendId']}. {q['title']} ({q['difficulty']})",
                   f"{cm} {BASE}/problems/{q['titleSlug']}/", ""]
        with open(path, "w") as f:
            f.write("\n".join(header) + "\n" + snippet.rstrip() + "\n")
    tests_path = os.path.join(d, "tests.txt")
    if not os.path.exists(tests_path):
        with open(tests_path, "w") as f:
            f.write("\n".join(q["exampleTestcaseList"] or []) + "\n")
    with open(tests_path) as f:
        lines = [l for l in f.read().splitlines()]
    n = max(1, len(params))
    lines = [l for l in lines if l.strip() != ""]
    cases = ["\n".join(lines[i:i + n]) for i in range(0, len(lines), n)]

    info = {
        "id": q["questionFrontendId"], "questionId": q["questionId"], "slug": q["titleSlug"],
        "title": q["title"], "difficulty": q["difficulty"], "acRate": round(q["acRate"] or 0),
        "likes": q["likes"], "tags": [t["name"] for t in q["topicTags"]], "params": params,
        "hints": [re.sub(r"<[^>]+>", "", html.unescape(h)) for h in q["hints"] or []],
        "content": clean_html(fix_images(q["content"], s)), "dir": d, "file": path, "tests": cases,
        "lang": lang, "url": f"{BASE}/problems/{q['titleSlug']}/",
    }
    with open(os.path.join(d, ".problem.json"), "w") as f:
        json.dump(info, f)
    out(info)


def load(slug):
    cfg = config()
    d = find_dir(cfg, slug)
    if not d or not os.path.exists(os.path.join(d, ".problem.json")):
        raise SystemExit(out({"error": f"Fetch '{slug}' first"}))
    info = json.load(open(os.path.join(d, ".problem.json")))
    code = open(info["file"]).read()
    code = re.sub(re.escape(LOCAL_BEGIN) + r".*?" + re.escape(LOCAL_END) + r"\n?", "", code, flags=re.S)
    return info, code.strip() + "\n"


def poll(s, ident, timeout=60):
    t0 = time.time()
    while time.time() - t0 < timeout:
        r = s.get(f"{BASE}/submissions/detail/{ident}/check/", timeout=20)
        r.raise_for_status()
        d = r.json()
        if d.get("state") == "SUCCESS":
            return d
        time.sleep(1)
    raise RuntimeError("LeetCode took too long to judge this")


def error_text(d):
    return (d.get("full_compile_error") or d.get("compile_error") or d.get("full_runtime_error")
            or d.get("runtime_error") or "")


def post(s, url, payload):
    r = s.post(url, json=payload, timeout=20)
    if r.status_code == 429:
        raise RuntimeError("Rate limited by LeetCode - wait a few seconds")
    if r.status_code in (401, 403):
        raise RuntimeError("LeetCode rejected the login (cookie expired?) - refresh ~/.config/lc/cookie")
    r.raise_for_status()
    return r.json()


def cmd_run(slug):
    info, code = load(slug)
    s = session(slug, auth=True)
    tests = open(os.path.join(info["dir"], "tests.txt")).read().strip("\n")
    res = post(s, f"{BASE}/problems/{slug}/interpret_solution/",
               {"lang": info["lang"], "question_id": info["questionId"], "typed_code": code, "data_input": tests})
    d = poll(s, res["interpret_id"])

    n = max(1, len(info["params"]))
    lines = [l for l in tests.splitlines() if l.strip() != ""]
    inputs = [lines[i:i + n] for i in range(0, len(lines), n)]
    answers, expected = d.get("code_answer") or [], d.get("expected_code_answer") or []
    stdout = d.get("std_output_list") or []
    compare = d.get("compare_result") or ""
    cases = []
    for i, inp in enumerate(inputs):
        cases.append({
            "input": inp,
            "output": answers[i] if i < len(answers) else "",
            "expected": expected[i] if i < len(expected) else "",
            "stdout": stdout[i] if i < len(stdout) else "",
            "passed": compare[i] == "1" if i < len(compare) else False,
        })
    ok = d.get("run_success") and d.get("correct_answer")
    out({"kind": "run", "status": ("Accepted" if ok else d.get("status_msg") or "Error"),
         "ok": bool(ok), "runtime": d.get("status_runtime", ""), "memory": d.get("status_memory", ""),
         "error": error_text(d), "cases": cases, "params": info["params"]})


def cmd_submit(slug):
    info, code = load(slug)
    s = session(slug, auth=True)
    res = post(s, f"{BASE}/problems/{slug}/submit/",
               {"lang": info["lang"], "question_id": info["questionId"], "typed_code": code})
    d = poll(s, res["submission_id"], timeout=90)
    failing = None
    if d.get("last_testcase"):
        failing = {"input": d["last_testcase"].split("\n"), "output": d.get("code_output", ""),
                   "expected": d.get("expected_output", ""), "stdout": d.get("std_output", "")}
    pct = lambda v: round(v, 1) if isinstance(v, (int, float)) else None
    out({"kind": "submit", "status": d.get("status_msg") or "Error",
         "ok": d.get("status_msg") == "Accepted", "runtime": d.get("status_runtime", ""),
         "runtimePct": pct(d.get("runtime_percentile")), "memory": d.get("status_memory", ""),
         "memoryPct": pct(d.get("memory_percentile")), "passed": d.get("total_correct"),
         "total": d.get("total_testcases"), "error": error_text(d), "failing": failing,
         "params": info["params"], "submissionId": res["submission_id"]})


Q_LIST = """query($skip:Int!,$limit:Int!,$f:QuestionListFilterInput){
  questionList(categorySlug:"", limit:$limit, skip:$skip, filters:$f){
    total: totalNum
    data{ questionFrontendId title titleSlug difficulty isPaidOnly status acRate topicTags{name} } } }"""


def list_filters(arg):
    """JSON filter object from the window: {difficulty, status, tags, orderBy, sortOrder}."""
    try:
        opts = json.loads(arg or "{}")
    except ValueError:
        opts = {}
    f = {}
    if opts.get("difficulty"):
        f["difficulty"] = opts["difficulty"]          # EASY / MEDIUM / HARD
    if opts.get("status"):
        f["status"] = opts["status"]                  # NOT_STARTED / AC / TRIED
    if opts.get("tags"):
        f["tags"] = opts["tags"]                      # topic slugs, all must match
    if opts.get("search"):
        f["searchKeywords"] = opts["search"]
    f["orderBy"] = opts.get("orderBy") or "FRONTEND_ID"   # FRONTEND_ID / AC_RATE
    f["sortOrder"] = opts.get("sortOrder") or "ASCENDING"
    return f, int(opts.get("skip", 0)), int(opts.get("limit", 50))


def row(x):
    return {"id": x["questionFrontendId"], "slug": x["titleSlug"], "title": x["title"],
            "difficulty": x["difficulty"], "paid": x["isPaidOnly"], "status": x["status"],
            "acRate": round(x["acRate"] or 0), "tags": [t["name"] for t in x["topicTags"]][:3]}


def cmd_list(arg):
    f, skip, limit = list_filters(arg)
    d = gql(session(), Q_LIST, {"skip": skip, "limit": limit, "f": f})["questionList"]
    out({"total": d["total"], "skip": skip, "results": [row(x) for x in d["data"]]})


def cmd_random(arg):
    """A random free problem matching the filters (prefers ones you haven't solved)."""
    import random
    f, _, _ = list_filters(arg)
    s = session()
    total = gql(s, Q_LIST, {"skip": 0, "limit": 1, "f": f})["questionList"]["total"]
    if not total:
        return out({"error": "No problems match these filters"})
    for _ in range(6):
        x = gql(s, Q_LIST, {"skip": random.randrange(total), "limit": 1, "f": f})["questionList"]["data"]
        if x and not x[0]["isPaidOnly"] and x[0]["status"] != "ac":
            return out(row(x[0]))
    out(row(x[0]) if x else {"error": "No free problem found, try again"})


def cmd_search(query):
    cmd_list(json.dumps({"search": query, "limit": 25}))


def cmd_lang(arg):
    path = os.path.join(CONF_DIR, "config.json")
    try:
        with open(path) as f:
            data = json.load(f)
    except (OSError, ValueError):
        data = {}
    if arg:
        if arg not in LANGS:
            return out({"error": f"unsupported language {arg}"})
        data["lang"] = arg
        os.makedirs(CONF_DIR, exist_ok=True)
        with open(path + ".tmp", "w") as f:
            json.dump(data, f, indent=2)
        os.replace(path + ".tmp", path)
    out({"lang": data.get("lang", config()["lang"]), "langs": LANGS})


def cmd_whoami():
    s = session()
    u = gql(s, "query{userStatus{isSignedIn username}}")["userStatus"]
    out({"signedIn": u["isSignedIn"], "username": u["username"]})


def main():
    if len(sys.argv) < 2:
        return out({"error": __doc__})
    cmd, arg = sys.argv[1], " ".join(sys.argv[2:])
    try:
        {"fetch": lambda: cmd_fetch(arg or "daily"), "run": lambda: cmd_run(arg),
         "submit": lambda: cmd_submit(arg), "search": lambda: cmd_search(arg),
         "list": lambda: cmd_list(arg), "random": lambda: cmd_random(arg),
         "whoami": cmd_whoami, "lang": lambda: cmd_lang(arg)}.get(cmd, lambda: out({"error": f"unknown command {cmd}"}))()
    except requests.RequestException as e:
        out({"error": f"Network error: {e}"})
    except RuntimeError as e:
        out({"error": str(e)})


main()
