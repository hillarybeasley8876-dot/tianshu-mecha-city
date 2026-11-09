#!/usr/bin/env python3
"""Markdown table of the r4 capture batch, from tmp/trailer/r4/results.json.

    tools/trailer/batch_table.py            # every unit
    tools/trailer/batch_table.py hud feel   # two units

Emits one row per command: unit, id, exit code, wall time, engine errors, and the output paths.
The "what the image shows" column is written by hand in status/trailer.md after looking at the
sheets -- this tool only prints the machine facts.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RESULTS = ROOT / "tmp/trailer/r4/results.json"


def shorten(cmd: str, width: int = 92) -> str:
    cmd = cmd.replace("tools/godot.sh ", "").replace(str(ROOT) + "/", "").replace("$HOME/m/mecha-city/", "")
    return cmd if len(cmd) <= width else cmd[: width - 1] + "…"


def main() -> int:
    rows = json.loads(RESULTS.read_text())
    units = sys.argv[1:] or sorted({r["unit"] for r in rows}, key=lambda u: [r["unit"] for r in rows].index(u))
    for unit in units:
        mine = [r for r in rows if r["unit"] == unit]
        if not mine:
            continue
        print(f"\n#### {unit}\n")
        print("| id | command | exit | s | engine errors | outputs |")
        print("|---|---|---|---|---|---|")
        for r in mine:
            outs = r["outputs"]
            names = ", ".join(f"`{Path(o).name}`" for o in outs[:6])
            if len(outs) > 6:
                names += f" … (+{len(outs) - 6})"
            errs = r["error_lines"][0][:80] if r["error_lines"] else "none"
            if r["drive_errors"] is not None:
                errs = f"DRIVE errors={r['drive_errors']}; " + errs
            print(f"| {r['id']} | `{shorten(r['cmd'])}` | {r['exit']} | {r['secs']:.0f} | {errs} | {names} |")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
