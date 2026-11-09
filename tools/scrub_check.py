#!/usr/bin/env python3
"""Public-release scrub: list every tracked file that leaks a personal or machine path, by owner.

    python3 tools/scrub_check.py             # all hits, grouped by CONTRACTS §1 owner
    python3 tools/scrub_check.py --mine      # only tooling's own files (the gate)
    python3 tools/scrub_check.py --strict    # exit 1 on any hit anywhere

Looks for the internal ys-api host, an absolute `/Users/<name>` home path, and a hard-coded
`~/m/mecha-city` / `$HOME/m/mecha-city` repo root. Owners come from docs/CONTRACTS.md §1 via
tools/owners.py, so a hit always names the unit that has to fix it. No secrets are printed, only the
file, the line and the matched pattern.
"""
import re
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import owners  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
PATTERNS = [
    ("internal-endpoint", re.compile(r"xaminim", re.I)),
    ("home-path", re.compile(r"/Users/[A-Za-z0-9._-]+")),
    ("repo-root", re.compile(r"(?:~|\$HOME)/m/mecha-city")),
]
SKIP_SUFFIX = (".png", ".jpg", ".jpeg", ".glb", ".fbx", ".blend", ".webp", ".icns", ".pck",
               ".wav", ".ogg", ".mp3", ".ttf", ".otf", ".pyc", ".bin", ".exr", ".hdr")
## Deliberate exceptions, each with its reason. Nothing else may hard-code a machine path.
ALLOW = {
    ("tools/slots.py", "repo-root"):
        "the slot pool is machine-wide on purpose: workers hold these flock locks across checkouts, so "
        "moving it into a checkout would let two imports of one tree overlap (brief item 1)",
    ("tools/scrub_check.py", "repo-root"):
        "this file: the docstring names the shape it searches for",
    ("tools/scrub_check.py", "internal-endpoint"):
        "this file: the pattern that finds the internal host",
}


def owner_of(path: str, rows) -> str:
    base = path[:-7] if path.endswith(".import") else (path[:-4] if path.endswith(".uid") else path)
    hits = [(n, o) for g, o, n, rx in rows if rx.match(base)]
    if not hits:
        return "<unowned>"
    best = max(n for n, _ in hits)
    winners = sorted({o for n, o in hits if n == best})
    return winners[0] if len(winners) == 1 else "<ambiguous>"


def main() -> int:
    mine = "--mine" in sys.argv
    strict = "--strict" in sys.argv
    rows = [(g, o, n, owners.to_regex(g)) for g, o, n in owners.parse_table()]
    files = subprocess.run(["git", "-C", str(ROOT), "ls-files"],
                           capture_output=True, text=True, check=True).stdout.split("\n")
    by_owner: dict[str, list[str]] = defaultdict(list)
    for f in (x for x in files if x):
        if f.endswith(SKIP_SUFFIX):
            continue
        p = ROOT / f
        try:
            text = p.read_text(encoding="utf-8", errors="strict")
        except (UnicodeDecodeError, OSError):
            continue
        owner = owner_of(f, rows)
        if mine and owner != "tooling":
            continue
        for i, line in enumerate(text.splitlines(), 1):
            for name, rx in PATTERNS:
                if rx.search(line) and (f, name) not in ALLOW:
                    by_owner[owner].append("%s:%d [%s]" % (f, i, name))
    total = 0
    for owner in sorted(by_owner):
        hits = by_owner[owner]
        total += len(hits)
        print("%s: %d hit(s)" % (owner, len(hits)))
        for h in hits:
            print("  " + h)
    print("scrub: %d hit(s) in %d unit(s)%s" % (total, len(by_owner), " (tooling only)" if mine else ""))
    if strict:
        return 1 if total else 0
    return 1 if by_owner.get("tooling") else 0


if __name__ == "__main__":
    sys.exit(main())
