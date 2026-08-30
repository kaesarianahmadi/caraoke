#!/usr/bin/env python3
"""Search GitHub repositories for Swift/SwiftUI projects using ActivityKit,
WidgetKit, MusicKit, and CarPlay. Collects: name, url, license, pushed_at,
stars, description. Output: JSON lines to stdout."""
import json
import ssl
import sys
import urllib.request
import urllib.parse

_CTX = ssl.create_default_context()
_CTX.check_hostname = False
_CTX.verify_mode = ssl.CERT_NONE

QUERIES = {
    "activitykit": "ActivityKit Live Activity language:Swift",
    "widgetkit": "WidgetKit SwiftUI language:Swift",
    "musickit": "MusicKit Apple Music language:Swift",
    "carplay": "CarPlay Swift language:Swift",
    "combined": "ActivityKit WidgetKit MusicKit CarPlay language:Swift",
}

def api(url):
    req = urllib.request.Request(url, headers={"Accept": "application/vnd.github+json",
                                              "User-Agent": "caraoke-research"})
    with urllib.request.urlopen(req, timeout=30, context=_CTX) as r:
        return json.load(r)

def main():
    for key, q in QUERIES.items():
        url = "https://api.github.com/search/repositories?q=" + urllib.parse.quote(q) + \
              "&sort=stars&order=desc&per_page=15"
        try:
            data = api(url)
        except Exception as e:
            print(f"ERROR {key}: {e}", file=sys.stderr)
            continue
        print(f"### QUERY: {key} ({data.get('total_count', '?')} total)", file=sys.stderr)
        for item in data.get("items", []):
            lic = item.get("license") or {}
            rec = {
                "query": key,
                "name": item["full_name"],
                "url": item["html_url"],
                "license": lic.get("spdx_id") or lic.get("name") or "NONE",
                "license_url": lic.get("url"),
                "pushed_at": item.get("pushed_at"),
                "stars": item.get("stargazers_count"),
                "description": (item.get("description") or "")[:160],
                "default_branch": item.get("default_branch"),
            }
            print(json.dumps(rec))

if __name__ == "__main__":
    main()
