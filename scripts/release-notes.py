#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Writes release.json for a published build: what the phone shows and compares
when it looks for updates (scripts/build-rootfs.sh, scripts/package.sh).

  release-notes.py TAG CHANNEL TIME ASTRA_DIR DEVICE_DIR OUT

CHANNEL is "stable" (a manual build) or "prerelease" (an automatic one). The
changelog lists the commits of astra and of this repository since the previous
build the same phones would update from: the previous release of any kind for
the pre-release channel, the previous stable release for the stable one. It
finds that build's commits in its ota.json, or in its release notes. Needs
GH_TOKEN and GITHUB_REPOSITORY (as in GitHub Actions).
"""
import json
import os
import re
import subprocess
import sys
import urllib.request

MAX_NOTES = 60


def get(url, accept):
    headers = {"Accept": accept, "User-Agent": "astra-release-notes"}
    if os.environ.get("GH_TOKEN"):
        headers["Authorization"] = "Bearer " + os.environ["GH_TOKEN"]
    return json.load(urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=30))


def api(path):
    return get("https://api.github.com/repos/%s/%s" % (os.environ["GITHUB_REPOSITORY"], path), "application/vnd.github+json")


def fetch(url):
    return get(url, "application/octet-stream")


def previous_commits(channel):
    """The astra and device commits of the build this one follows, or (None, None)."""
    try:
        releases = api("releases?per_page=50")
    except Exception as e:  # first release, or the API is down: no changelog range
        print("release-notes: cannot list releases: %s" % e, file=sys.stderr)
        return None, None
    for r in releases:
        if r.get("draft") or (channel == "stable" and r.get("prerelease")):
            continue
        for asset in r.get("assets", []):
            if asset["name"] == "ota.json":
                try:
                    m = fetch(asset["url"])
                    return m.get("astra") or None, m.get("device_commit") or None
                except Exception as e:
                    print("release-notes: %s: %s" % (asset["url"], e), file=sys.stderr)
        found = re.search(r"from astra ([0-9a-f]{7,40}) and \S+ ([0-9a-f]{7,40})", r.get("body") or "")
        if found:
            return found.group(1), found.group(2)
    return None, None


def log(repo, since):
    head = subprocess.run(["git", "-C", repo, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
    span = ["%s..HEAD" % since] if since else ["-n", "15"]
    out = subprocess.run(["git", "-C", repo, "log", "--no-merges", "--format=%s"] + span,
                         capture_output=True, text=True)
    if out.returncode != 0:  # the previous commit is not in this history (rewritten): the latest ones
        out = subprocess.run(["git", "-C", repo, "log", "--no-merges", "--format=%s", "-n", "15"],
                             capture_output=True, text=True)
    notes = [line.strip() for line in out.stdout.splitlines() if line.strip()]
    return head, [n for n in notes if not n.startswith("CI:")]


def main():
    tag, channel, when, astra_dir, device_dir, out = sys.argv[1:7]
    astra_prev, device_prev = previous_commits(channel)
    astra_head, astra_notes = log(astra_dir, astra_prev)
    device_head, device_notes = log(device_dir, device_prev)
    notes = (astra_notes + device_notes)[:MAX_NOTES]
    release = {"tag": tag, "channel": channel, "time": int(when), "notes": notes,
               "astra": astra_head, "device_commit": device_head}
    with open(out, "w") as f:
        json.dump(release, f, indent=1, ensure_ascii=False)
    print("release-notes: %s (%s), %d changes" % (tag, channel, len(notes)))


if __name__ == "__main__":
    main()
