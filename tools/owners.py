#!/usr/bin/env python3
"""Map every tracked file to its CONTRACTS.md §1 owner.

    python3 tools/owners.py            # per-owner counts, then uncovered and ambiguous paths
    python3 tools/owners.py --quiet    # only the problems
    python3 tools/owners.py --owner X  # just that owner's file count

The table is read from docs/CONTRACTS.md §1 so there is one source of truth. Each row is
`| `glob`, `glob` | owner | what |`. Precedence: THE MOST SPECIFIC ROW WINS, where specificity is the
length of the literal prefix before the first wildcard; two rows matching one file with the same
specificity are reported as ambiguous. `.import` and `.uid` sidecars belong to their source file.
Exit 1 when anything is uncovered or ambiguous.
"""
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTRACTS = ROOT / "docs" / "CONTRACTS.md"


def parse_table() -> list[tuple[str, str, str]]:
    """-> [(glob, owner, literal_prefix_len)] in table order."""
    text = CONTRACTS.read_text(encoding="utf-8")
    m = re.search(r"^## 1\..*?$(.*?)^## ", text, re.S | re.M)
    if not m:
        sys.exit("owners: no '## 1.' section in %s" % CONTRACTS)
    rows = []
    for line in m.group(1).splitlines():
        if not line.startswith("|"):
            continue
        cols = [c.strip() for c in line.strip("|").split("|")]
        if len(cols) < 2 or cols[1] in ("Owner", "---"):
            continue
        owner = cols[1]
        for glob in re.findall(r"`([^`]+)`", cols[0]):
            rows.append((glob, owner, len(re.split(r"[*?]", glob)[0])))
    if not rows:
        sys.exit("owners: the §1 table has no rows")
    return rows


def to_regex(glob: str) -> re.Pattern:
    out, i = [], 0
    while i < len(glob):
        if glob.startswith("**", i):
            out.append(".*")
            i += 2
        elif glob[i] == "*":
            out.append("[^/]*")
            i += 1
        elif glob[i] == "?":
            out.append("[^/]")
            i += 1
        else:
            out.append(re.escape(glob[i]))
            i += 1
    return re.compile("^" + "".join(out) + "$")


def main() -> int:
    args = sys.argv[1:]
    quiet = "--quiet" in args
    only = args[args.index("--owner") + 1] if "--owner" in args else ""
    rows = [(g, o, n, to_regex(g)) for g, o, n in parse_table()]
    files = subprocess.run(["git", "-C", str(ROOT), "ls-files"],
                           capture_output=True, text=True, check=True).stdout.split("\n")
    files = [f for f in files if f]
    counts: Counter = Counter()
    uncovered, ambiguous = [], []
    for f in files:
        base = f[:-7] if f.endswith(".import") else (f[:-4] if f.endswith(".uid") else f)
        hits = [(n, o) for g, o, n, rx in rows if rx.match(base)]
        if not hits:
            uncovered.append(f)
            continue
        best = max(n for n, _ in hits)
        winners = {o for n, o in hits if n == best}
        if len(winners) > 1:
            ambiguous.append((f, sorted(winners)))
            continue
        counts[winners.pop()] += 1
    if only:
        print("%s: %d files" % (only, counts[only]))
        return 0
    if not quiet:
        print("OWNED %d files in %d units" % (sum(counts.values()), len(counts)))
        for owner, n in counts.most_common():
            print("  %6d  %s" % (n, owner))
    for f in uncovered:
        print("UNCOVERED %s" % f)
    for f, owners in ambiguous:
        print("AMBIGUOUS %s -> %s" % (f, ", ".join(owners)))
    print("owners: %d tracked, %d uncovered, %d ambiguous"
          % (len(files), len(uncovered), len(ambiguous)))
    return 1 if (uncovered or ambiguous) else 0


if __name__ == "__main__":
    sys.exit(main())
