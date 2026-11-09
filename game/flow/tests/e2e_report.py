#!/usr/bin/env python3
"""E2E pacing + frametime report (flow unit, r3 brief item 3).

Reads one `tools/godot.sh drive` run of `res://flow/tests/e2e_city.json`:

  * the drive log, for the `E2EMARK` phase marks (flow clock + wall stamp), the drive's own
    `FRAMETIME` line and its error count;
  * the telemetry CSV (`--log=`), whose `t` column is one row per rendered frame — differencing it
    gives the per-frame times the phases are cut from.

Phase boundaries are the marks' flow-clock times plus the 0.5 s `FlowDebug.ARM_DELAY` that separates
the two clocks. Both clocks are Engine-scaled, so a slow-mo second is a second in both.

    python3 game/flow/tests/e2e_report.py tmp/flow/e2e.log tmp/flow/e2e.csv
"""
from __future__ import annotations

import csv
import sys
from typing import NamedTuple

ARM_DELAY = 0.5


class Mark(NamedTuple):
    name: str
    t: float       # flow clock
    wall: int      # ms since engine start
    state: str


class Phase(NamedTuple):
    name: str
    start: float   # drive clock
    end: float
    wall_s: float


def read_marks(path: str) -> list[Mark]:
    marks: list[Mark] = []
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if not line.startswith("E2EMARK "):
                continue
            parts = line.split()
            state = ""
            for p in parts:
                if p.startswith("state="):
                    state = p.split("=", 1)[1]
            marks.append(Mark(parts[1], float(_field(parts, "t=")), int(_field(parts, "wall=")), state))
    return marks


def _field(parts: list[str], key: str) -> str:
    for p in parts:
        if p.startswith(key):
            return p.split("=", 1)[1]
    return "0"


def read_phases(marks: list[Mark], end_t: float) -> list[Phase]:
    out: list[Phase] = []
    for i, m in enumerate(marks):
        nxt = marks[i + 1] if i + 1 < len(marks) else None
        end = (nxt.t if nxt else end_t) + ARM_DELAY
        wall = ((nxt.wall - m.wall) if nxt else 0) / 1000.0
        out.append(Phase(m.name, m.t + ARM_DELAY, end, wall))
    return out


def read_frames(path: str) -> list[tuple[float, float]]:
    rows: list[tuple[float, float]] = []
    with open(path, newline="", encoding="utf-8", errors="replace") as fh:
        for row in csv.DictReader(fh):
            try:
                rows.append((float(row["t"]), 0.0))
            except (KeyError, TypeError, ValueError):
                continue
    return [(rows[i][0], (rows[i][0] - rows[i - 1][0]) * 1000.0) for i in range(1, len(rows))]


def pct(values: list[float], p: float) -> float:
    if not values:
        return 0.0
    s = sorted(values)
    return s[min(int(p * len(s)), len(s) - 1)]


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    marks = read_marks(sys.argv[1])
    frames = read_frames(sys.argv[2])
    if not marks or not frames:
        print("no marks or no frames — was this a drive run with --log=?")
        return 1
    phases = read_phases(marks, frames[-1][0])
    print("%-14s %8s %8s %8s %8s %8s %7s" % ("PHASE", "game s", "wall s", "p50 ms", "p95 ms",
                                             "p99 ms", "frames"))
    for ph in phases:
        window = [ms for t, ms in frames if ph.start <= t < ph.end and ms > 0.0]
        print("%-14s %8.1f %8.1f %8.1f %8.1f %8.1f %7d"
              % (ph.name, ph.end - ph.start, ph.wall_s, pct(window, 0.5), pct(window, 0.95),
                 pct(window, 0.99), len(window)))
    total = [ms for _, ms in frames if ms > 0.0]
    print("%-14s %8.1f %8.1f %8.1f %8.1f %8.1f %7d"
          % ("ALL", frames[-1][0], 0.0, pct(total, 0.5), pct(total, 0.95), pct(total, 0.99),
             len(total)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
