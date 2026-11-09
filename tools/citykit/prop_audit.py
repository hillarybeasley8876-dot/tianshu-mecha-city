"""Join the props mesh probe with `blender/props/prop_table.py`'s budgets into the audit table the
r10 brief asks for.

  tools/godot.sh test res://world/kit/tests/probe_props.gd -- --timeout=1200 > tmp/.../probe.log
  python3 tools/citykit/prop_audit.py tmp/.../probe.log [--verdicts=path.json] [--md]

Columns: budget (tris / budget), size (longest side against the table's size_m), open edges (count
and the largest hole), flipped faces, and the visual verdict read off the clay q34 sheet. The verdict
is the one thing a machine cannot measure, so it is supplied as a JSON map of prop -> text; without
it the column reads "-".

Exit 1 if any prop busts its triangle budget by more than 2 % or its target size by more than 10 %,
so this doubles as a gate.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from typing import Dict, List, Optional

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__)))), "blender", "props"))

from prop_table import prop  # noqa: E402

TRIS_BUDGET_TOLERANCE = 1.02
SIZE_TOLERANCE = 0.10
LINE = re.compile(
    r"^PROBE (?P<name>\S+) tris (?P<tris>\d+) verts (?P<verts>\d+) welded (?P<welded>\d+)"
    r" \| longest (?P<longest>[-\d.]+) target (?P<target>[-\d.]+) \((?P<delta>[+-]\d+)%\)"
    r" base_y (?P<base_y>[-\d.]+) size (?P<size>[-\d.,]+)"
    r" \| open (?P<open>\d+) \((?P<open_pct>[\d.]+)%\) nonmanifold (?P<nonmanifold>\d+)"
    r" holes (?P<holes>\d+) largest_hole (?P<largest_hole>[\d.]+) m at \([^)]*\)"
    r" \| shells (?P<shells>\d+) small (?P<small>\d+) floating (?P<floating>\d+)"
    r" \(largest (?P<floating_tris>\d+) tris\)"
    r" \| flip (?P<flip>\d+) \((?P<flip_pct>[\d.]+)%\) vol (?P<volume>[-\d.]+) m3"
    r" \| degenerate (?P<degenerate>\d+) zero_uv (?P<zero_uv>\d+)"
    r" \| albedo (?P<albedo>\S+)$")


def parse(path: str) -> Dict[str, Dict[str, str]]:
    rows: Dict[str, Dict[str, str]] = {}
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            found = LINE.match(line.strip())
            if found:
                rows[found.group("name")] = found.groupdict()
    return rows


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("log")
    ap.add_argument("--verdicts", default="")
    ap.add_argument("--md", action="store_true", help="markdown table (default)")
    ap.add_argument("--csv", action="store_true")
    args = ap.parse_args()
    rows = parse(args.log)
    if not rows:
        print("prop_audit: no PROBE lines in %s" % args.log)
        return 2
    verdicts: Dict[str, str] = {}
    if args.verdicts and os.path.exists(args.verdicts):
        with open(args.verdicts, "r", encoding="utf-8") as handle:
            verdicts = json.load(handle)

    bad: List[str] = []
    out: List[List[str]] = []
    for name in sorted(rows):
        row = rows[name]
        spec = prop(name)
        tris = int(row["tris"])
        longest = float(row["longest"])
        if tris > spec.budget * TRIS_BUDGET_TOLERANCE:
            bad.append("%s %d tris over the %d budget" % (name, tris, spec.budget))
        if abs(longest / max(spec.size_m, 1e-6) - 1.0) > SIZE_TOLERANCE:
            bad.append("%s longest %.2f m against the table's %.1f m" % (name, longest, spec.size_m))
        if abs(float(row["base_y"])) > 0.05 and name != "koi_dragon":
            bad.append("%s base_y %.3f m (not standing on y=0)" % (name, float(row["base_y"])))
        out.append([
            name,
            "%d / %d" % (tris, spec.budget),
            "%.2f / %.1f m (%s%%)" % (longest, spec.size_m, row["delta"]),
            "%s (%.2f%%), largest hole %.2f m" % (row["open"], float(row["open_pct"]),
                                                 float(row["largest_hole"])),
            "%s (%.2f%%)" % (row["flip"], float(row["flip_pct"])),
            verdicts.get(name, "-"),
        ])

    header = ["prop", "budget", "size", "open edges", "flipped", "visual verdict"]
    if args.csv:
        print(",".join(header))
        for line in out:
            print(",".join('"%s"' % c for c in line))
    else:
        print("| " + " | ".join(header) + " |")
        print("|" + "|".join(["---"] * len(header)) + "|")
        for line in out:
            print("| " + " | ".join(line) + " |")
    print("\n%d props audited, %d over budget" % (len(out), len(bad)), file=sys.stderr)
    for line in bad:
        print("OVER %s" % line, file=sys.stderr)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
