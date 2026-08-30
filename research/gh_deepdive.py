#!/usr/bin/env python3
"""Deep-dive shortlisted repos: fetch repo metadata (license, pushed_at),
latest commit date on default branch, and recursive file tree (filtered to
swift/plist/project files). Output JSON to stdout."""
import json, ssl, sys, time, urllib.request, urllib.parse

_CTX = ssl.create_default_context(); _CTX.check_hostname=False; _CTX.verify_mode=ssl.CERT_NONE

def api(url, tries=3):
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers={"Accept":"application/vnd.github+json","User-Agent":"caraoke-research"})
            with urllib.request.urlopen(req, timeout=30, context=_CTX) as r:
                return json.load(r)
        except Exception as e:
            if i == tries-1:
                return {"error": str(e)}
            time.sleep(1)

REPOS = [
    "praveetgupta/driveverse",
    "tcastellanza/synced-lyrics",
    "josephbinu06/LiveLyrics",
    "linkzhong/apple-music-widget",
    "aviwad/LyricFever",
    "1998code/iOS16-Live-Activities",
    "batikansosun/iOS-16-Live-Activities-Dynamic-Island",
    "apple/sample-food-truck",
    "aws-samples/aws-serverless-fullstack-swift-apple-carplay-example",
    "mikonyaa/LiveActivityDynamicIslandKit",
    "simonberner/ladi-simulator",
    "below/CarSample",
    "gastonmorixe/swiftui-carplay-ui-demo",
    "Kaiede/SwiftCarUI",
    "asecretcompany/yourpods-source",
]

out = []
for repo in REPOS:
    meta = api(f"https://api.github.com/repos/{repo}")
    if meta.get("error"):
        print(json.dumps({"repo": repo, "error": meta["error"]})); continue
    lic = meta.get("license") or {}
    default_branch = meta.get("default_branch") or "main"
    # latest commit on default branch
    commit = api(f"https://api.github.com/repos/{repo}/commits?sha={default_branch}&per_page=1")
    commit_date = None
    if isinstance(commit, list) and commit:
        commit_date = commit[0].get("commit", {}).get("committer", {}).get("date")
    # tree
    tree_url = f"https://api.github.com/repos/{repo}/git/trees/{default_branch}?recursive=1"
    tree = api(tree_url)
    files = []
    if isinstance(tree, dict) and "tree" in tree:
        for t in tree["tree"]:
            p = t.get("path","")
            if t.get("type") == "blob" and (p.endswith((".swift", ".plist", ".pbxproj", ".xcconfig", ".entitlements", ".json")) or "Info.plist" in p):
                files.append(p)
    rec = {
        "repo": repo,
        "html_url": meta.get("html_url"),
        "license": lic.get("spdx_id") or lic.get("name") or "NONE",
        "license_url": lic.get("url"),
        "default_branch": default_branch,
        "pushed_at": meta.get("pushed_at"),
        "last_commit_date": commit_date,
        "stars": meta.get("stargazers_count"),
        "description": (meta.get("description") or "")[:200],
        "archived": meta.get("archived"),
        "files": files[:120],
    }
    out.append(rec)
    print(json.dumps(rec), flush=True)
    time.sleep(0.3)
