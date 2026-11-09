#!/usr/bin/env python3
"""The time-of-day A/B for a take: the SAME take, the SAME camera, N times of day, as stills.

    tools/trailer/tod_ab.py --spec game/trailer/shots.json --take s02_city --tods 0.0,0.35,0.6,0.85
    tools/trailer/tod_ab.py --spec game/trailer/showcase.json --take all --reuse

Each arm is one `tools/godot.sh drive` of the take's own timeline, camera and flags with `--tod`
swapped, screenshotting the MIDPOINT of every cut window that uses the take — so the A/B is made on the
frames the edit actually shows. Writes `tmp/trailer/r6/tod/<take>_tod<X>_t<T>.jpg` and a labelled grid
per take in `tmp/trailer/r6/`.

r6: this is the A/B re-run on the city-art r16b sky (real clouds, a warm peach horizon, no hatch).
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from stills import drive_stills, sheet  # noqa: E402
from takes import load_spec, shot_times, take_args, take_by_id  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
OUTDIR = ROOT / "tmp/trailer/r6/tod"
SHEETS = ROOT / "tmp/trailer/r6"
LOGS = ROOT / "tmp/trailer/r6/logs"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--spec", type=Path, default=ROOT / "game/trailer/shots.json")
    ap.add_argument("--take", default="", help="take id, a comma list, or `all`")
    ap.add_argument("--tods", default="0.0,0.35,0.6,0.85")
    ap.add_argument("--max-shots", type=int, default=3)
    ap.add_argument("--reuse", action="store_true", help="skip an arm whose raw stills already exist")
    ap.add_argument("--no-sheet", action="store_true")
    args = ap.parse_args()

    spec = load_spec(args.spec)
    ids = [t["id"] for t in spec["takes"]] if args.take == "all" else args.take.split(",")
    if not ids or ids == [""]:
        raise SystemExit("tod_ab: --take is required (an id, a comma list, or `all`)")

    bad: list[str] = []
    for take_id in ids:
        take = take_by_id(spec, take_id)
        times = shot_times(spec, take_id, args.max_shots)
        if not times:
            print(f"tod_ab: {take_id} has no cut window — skipping")
            continue
        rows: list[tuple[str, list[Path]]] = []
        for tod in args.tods.split(","):
            frames = drive_stills(take_args(take, tod=tod), times, f"{take_id}_tod{tod}",
                                  OUTDIR, LOGS, args.reuse)
            if len(frames) != len(times):
                print(f"tod_ab: {take_id} tod={tod} produced {len(frames)}/{len(times)} frames")
                bad.append(f"{take_id}@{tod}")
            if frames:
                rows.append((f"tod {tod}", frames))
        if rows and not args.no_sheet:
            sheet(rows, SHEETS / f"tod_{take_id}.jpg")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
