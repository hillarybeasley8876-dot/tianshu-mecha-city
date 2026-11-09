#!/usr/bin/env python3
"""Turn a probe_stage.gd scout log into the camera specs tools/trailer/scout_shots.sh shoots.

    tools/godot.sh test res://trailer/probe_stage.gd -- --stage=res://trailer/stages.json \
        --skip-menu --stub=flow > tmp/trailer/scout.log
    tools/trailer/scout_cams.py tmp/trailer/scout.log --stages A6_garden,H0_pier

Writes tmp/trailer/scout_cams.json: {stage: {"spawn": "x,y,z", "cams": "name:x,y,z:lx,ly,lz:fov;..."}}.
The camera positions come from the log, so the stills are exactly the frames that were scored.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
STAGE_RE = re.compile(r"STAGE (\S+) hero=\((-?[\d.]+),(-?[\d.]+),(-?[\d.]+)\)")
CAM_RE = re.compile(
    r"\s+CAM (\S+) (\S+).*pos=(-?[\d.]+),(-?[\d.]+),(-?[\d.]+)"
    r" look=(-?[\d.]+),(-?[\d.]+),(-?[\d.]+) fov=([\d.]+)"
)


def parse(log: Path) -> dict[str, dict[str, object]]:
    stages: dict[str, dict[str, object]] = {}
    current: str | None = None
    for line in log.read_text().splitlines():
        m = STAGE_RE.match(line)
        if m:
            current = m.group(1)
            stages[current] = {"spawn": ",".join(m.group(2, 3, 4)), "cams": []}
            continue
        m = CAM_RE.match(line)
        if m and current:
            name, pos, look, fov = m.group(2), m.group(3, 4, 5), m.group(6, 7, 8), m.group(9)
            stages[current]["cams"].append(  # type: ignore[union-attr]
                "%s:%s:%s:%s" % (name, ",".join(pos), ",".join(look), fov.split(".")[0])
            )
    for s in stages.values():
        s["cams"] = ";".join(s["cams"])  # type: ignore[arg-type]
    return stages


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("log", type=Path)
    ap.add_argument("--stages", default="", help="comma-separated subset (default: all)")
    ap.add_argument("--out", type=Path, default=ROOT / "tmp/trailer/scout_cams.json")
    args = ap.parse_args()

    stages = parse(args.log)
    if args.stages:
        wanted = [s for s in args.stages.split(",") if s]
        missing = [s for s in wanted if s not in stages]
        if missing:
            print("scout_cams: not in the log: %s" % ", ".join(missing), file=sys.stderr)
            return 2
        stages = {s: stages[s] for s in wanted}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(stages, indent=1))
    print("%d stages -> %s" % (len(stages), args.out))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
