#!/usr/bin/env python3
"""Track new supported release representatives missing from KDockW's GitHub matrix.

The workflow checks upstream release dates for families currently eligible
for the GitHub package matrix. Fedora 45 is experimental for v0.5.0, so Fedora
is not release-watched until its compatibility is confirmed and the owner
re-enables it. Manual compatibility targets in ``targets.tsv`` do not create
release-watch gaps.
Packages are published only as GitHub Release assets after the required matrix
passes; no external package repository is contacted.

The watcher keeps one GitHub issue per missing distro/version. If a required
data source is unreachable, the run is partial and makes no issue changes.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TARGETS_FILE = ROOT / "tests/distro/release-targets.txt"
USER_AGENT = "kdockw-distro-release-watch (https://github.com/thicking/kdockw)"
HTTP_TIMEOUT = 20
EOL_API = "https://endoflife.date/api/{distro}.json"
LABEL = "distro-release"
LABEL_COLOR = "0E8A16"
LABEL_DESCRIPTION = "New distro release missing from the KDockW GitHub package matrix"
POLICY_LINK = (
    "See the [Distribution Support Policy]"
    "(https://github.com/thicking/kdockw/blob/main/docs/releasing/"
    "distribution-support-policy.md)."
)
MARKER_RE = re.compile(r"<!--\s*distro-release:([\w-]+):([\d.]+):github\s*-->")
TARGET_PATTERNS = {
    "fedora": re.compile(r"^fedora-(\d+)$"),
    "ubuntu": re.compile(r"^ubuntu-(\d+(?:\.\d+)*)$"),
    "debian": re.compile(r"^debian-(\d+(?:\.\d+)*)$"),
}
DISTROS = (
    ("ubuntu", "Ubuntu", "ubuntu"),
    ("debian", "Debian", "debian"),
)


def warn(message: str) -> None:
    print(f"warning: {message}", file=sys.stderr)


def version_key(version: str) -> tuple[int, ...]:
    parts = []
    for chunk in version.split("."):
        match = re.match(r"\d+", chunk)
        if not match:
            break
        parts.append(int(match.group()))
    return tuple(parts)


def fetch_json(url: str, what: str) -> object | None:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(request, timeout=HTTP_TIMEOUT) as response:
            return json.load(response)
    except (urllib.error.URLError, TimeoutError, OSError, ValueError) as exc:
        warn(f"failed to fetch {what}: {exc}")
        return None


def eol_candidates(distro: str) -> dict[tuple[int, ...], tuple[str, str]] | None:
    """Released cycles from endoflife.date: version key -> display/date."""
    data = fetch_json(EOL_API.format(distro=distro), f"endoflife.date {distro}")
    if not isinstance(data, list):
        return None
    today = date.today().isoformat()
    result: dict[tuple[int, ...], tuple[str, str]] = {}
    for entry in data:
        if not isinstance(entry, dict):
            continue
        cycle = str(entry.get("cycle", ""))
        released = str(entry.get("releaseDate", ""))
        if not released or released > today:
            continue
        # Ubuntu LTS releases use the April YY.04 cadence; interim YY.10
        # releases are deliberately outside the required package matrix.
        if distro == "ubuntu" and not re.fullmatch(r"\d+\.04", cycle):
            continue
        key = version_key(cycle)
        if key:
            result[key] = (cycle, released)
    return result


def parse_targets(path: Path) -> dict[str, set[tuple[int, ...]]]:
    """Read required release target IDs, not optional manual targets."""
    versions = {slug: set() for slug in TARGET_PATTERNS}
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        target_id = stripped
        for slug, pattern in TARGET_PATTERNS.items():
            match = pattern.fullmatch(target_id)
            if match:
                versions[slug].add(version_key(match.group(1)))
                break
    return versions


@dataclass(frozen=True)
class Gap:
    distro: str
    slug: str
    version: str
    released: str

    @property
    def key(self) -> str:
        return f"{self.slug}:{self.version}:github"

    @property
    def title(self) -> str:
        return f"Distro release: {self.distro} {self.version} in GitHub package matrix"

    @property
    def marker(self) -> str:
        return f"<!-- distro-release:{self.key} -->"


def build_body(gap: Gap) -> str:
    return "\n".join(
        (
            f"**{gap.distro} {gap.version}** has been released, but KDockW does not "
            "build a package for it in the GitHub matrix yet.",
            "",
            f"- Upstream release date: {gap.released}",
            "- Add or update its package metadata row in `tests/distro/targets.tsv`.",
            "- Add its ID to `tests/distro/release-targets.txt` and update the README.",
            "- Run package build and Distro E2E before making it a required release target.",
            "",
            gap.marker,
            "",
            f"> {POLICY_LINK}",
        )
    )


def detect(targets: dict[str, set[tuple[int, ...]]]) -> tuple[list[Gap], bool]:
    gaps: list[Gap] = []
    incomplete = False
    for api_name, display_name, target_slug in DISTROS:
        candidates = eol_candidates(api_name)
        if candidates is None:
            incomplete = True
            continue
        tracked = targets.get(target_slug, set())
        if not tracked:
            warn(f"no {display_name} package targets found in tests/distro/targets.tsv")
            incomplete = True
            continue
        newest_tracked = max(tracked)
        newest_date = candidates.get(newest_tracked, ("", ""))[1]
        for version_key_value, (version, released) in sorted(candidates.items()):
            if version_key_value in tracked or version_key_value <= newest_tracked:
                continue
            if newest_date and released <= newest_date:
                continue
            gaps.append(Gap(display_name, target_slug, version, released))
    return gaps, incomplete


def gh_available() -> bool:
    try:
        return subprocess.run(
            ["gh", "--version"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        ).returncode == 0
    except FileNotFoundError:
        return False


def list_issues(repo: str) -> list[dict] | None:
    if not gh_available():
        warn("gh CLI not found; cannot inspect existing issues")
        return None
    command = [
        "gh", "issue", "list", "--label", LABEL, "--state", "all", "--limit", "200",
        "--json", "number,title,state,body",
    ]
    if repo:
        command += ["--repo", repo]
    try:
        result = subprocess.run(command, capture_output=True, text=True, check=True)
        return json.loads(result.stdout)
    except (subprocess.CalledProcessError, json.JSONDecodeError) as exc:
        warn(f"gh issue list failed: {exc}")
        return None


def gh_write(args: list[str], repo: str) -> bool:
    command = ["gh", *args] + (["--repo", repo] if repo else [])
    try:
        result = subprocess.run(command, capture_output=True, text=True)
    except FileNotFoundError:
        warn("gh CLI not found; cannot perform issue update")
        return False
    if result.returncode:
        warn(f"gh {' '.join(args[:2])} failed: {result.stderr.strip()}")
        return False
    return True


def reconcile(gaps: list[Gap], repo: str, dry_run: bool) -> int:
    issues = list_issues(repo)
    if issues is None:
        if not dry_run:
            return 1
        issues = []
    by_title = {issue["title"]: issue for issue in issues}
    open_by_marker = {}
    for issue in issues:
        match = MARKER_RE.search(issue.get("body") or "")
        if match and issue.get("state") == "OPEN":
            open_by_marker[":".join(match.groups())] = issue

    failures = 0
    wanted = {gap.key for gap in gaps}
    for marker_key, issue in open_by_marker.items():
        if marker_key in wanted:
            continue
        number, title = issue["number"], issue["title"]
        comment = "The GitHub package matrix now includes this target, or the release data changed. Closing."
        if dry_run:
            print(f"[dry-run] would comment + close issue #{number} ({title})")
            continue
        ok = gh_write(["issue", "comment", str(number), "--body", comment], repo)
        ok &= gh_write(["issue", "close", str(number)], repo)
        failures |= not ok

    for gap in gaps:
        body = build_body(gap)
        issue = by_title.get(gap.title)
        if issue is None:
            if dry_run:
                print(f"[dry-run] would create issue {gap.title!r}\n{body}")
                continue
            if not gh_write(["issue", "create", "--title", gap.title, "--label", LABEL, "--body", body], repo):
                failures = 1
            continue
        if issue.get("state") != "OPEN" or issue.get("body", "") == body:
            continue
        if dry_run:
            print(f"[dry-run] would update issue #{issue['number']} {gap.title!r}")
        elif not gh_write(["issue", "edit", str(issue["number"]), "--body", body], repo):
            failures = 1
    return int(bool(failures))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", ""))
    parser.add_argument("--targets", type=Path, default=TARGETS_FILE)
    parser.add_argument("--dry-run", action="store_true", help="print actions without changing GitHub issues")
    args = parser.parse_args()

    try:
        targets = parse_targets(args.targets)
    except (OSError, ValueError) as exc:
        warn(f"cannot parse package targets: {exc}")
        return 1
    gaps, incomplete = detect(targets)
    for gap in gaps:
        print(f"actionable: {gap.distro} {gap.version} in GitHub package matrix")
    if not gaps:
        print("No released distro version is missing from the GitHub package matrix.")
    if incomplete:
        warn("upstream release data was incomplete; no GitHub issues were changed")
        return 1
    return reconcile(gaps, args.repo, args.dry_run)


if __name__ == "__main__":
    sys.exit(main())
