#!/usr/bin/env python3
"""Sweep a take's camera and look at the frames: which rig films this beat.

    # bearings — the take's own rig, its lens rotated around the hero
    tools/trailer/rig_sweep.py --spec game/trailer/showcase.json --take m3_spitter \
        --bearings 0,45,90,135,180,225 --at 3.0,7.5

    # whole configurations — any rig patch, from a JSON list of {"label", "rig"} objects
    tools/trailer/rig_sweep.py --spec game/trailer/showcase.json --take g4_flight \
        --configs tmp/trailer/r6/g4.json --at 1.0,4.0,7.0

A `--bearings` arm rotates `pos_hero` to that bearing (same distance, height and lens) and keeps the
spawn wedge on the far side of the hero, so the sweep changes one thing. A `--configs` arm merges its
`rig` object over the take's rig. Either way each arm is one `tools/godot.sh drive` screenshotting
`--at`, and the result is one labelled sheet per take in `tmp/trailer/r6/`.

r6 use: the spitter's acid cloud, the flight segment's out-of-frame mech and the drop's orange wall are
all "the lens is on the wrong side / too far / too low" problems, and this is how the fix gets picked on
frames instead of on a hunch.
"""
from __future__ import annotations

import argparse
import copy
import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from stills import drive_stills, sheet  # noqa: E402
from takes import load_spec, shot_times, take_args, take_by_id  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
OUTDIR = ROOT / "tmp/trailer/r6/sweep"
SHEETS = ROOT / "tmp/trailer/r6"
LOGS = ROOT / "tmp/trailer/r6/logs"


def rotate(rig: dict, bearing: float) -> dict:
    """The take's rig with its lens moved to `bearing`, keeping distance, height and fov."""
    out = copy.deepcopy(rig)
    pos = out.get("pos_hero")
    if not pos:
        raise SystemExit("rig_sweep: --bearings needs a rig with pos_hero (use --configs for a chase)")
    dist = math.hypot(pos[0], pos[2])
    a = math.radians(bearing)
    out["pos_hero"] = [round(dist * math.cos(a), 2), pos[1], round(dist * math.sin(a), 2)]
    return out


def rotate_cam(cam: dict, pivot: list[float], bearing: float) -> dict:
    """A keyframed trailer camera with every key's position rotated around `pivot`."""
    out = copy.deepcopy(cam)
    a = math.radians(bearing)
    for k in out.get("keys", []):
        p = k["pos"]
        dx, dz = p[0] - pivot[0], p[2] - pivot[2]
        r = math.hypot(dx, dz)
        base = math.atan2(dz, dx)
        k["pos"] = [round(pivot[0] + r * math.cos(base + a), 1), p[1],
                    round(pivot[2] + r * math.sin(base + a), 1)]
    return out


def load_rig(take: dict) -> dict:
    rig = take.get("rig")
    if isinstance(rig, str):
        rig = json.loads((ROOT / "game" / rig.replace("res://", "")).read_text())
    if not rig:
        raise SystemExit("rig_sweep: the take has no camera rig to sweep")
    return rig


def arm_args(take: dict, rig: dict, tod: str, pack: str, arc: str,
             bearing: float | None) -> list[str]:
    """The take with `rig` swapped in and its pack / spawn wedge overridden, ready for a drive."""
    take2 = copy.deepcopy(take)
    take2["rig"] = rig
    flags: list[str] = []
    for f in take2.get("flags", []):
        if f.startswith("--trailer-pack=") and pack:
            flags.append(f"--trailer-pack={pack}")
        elif f.startswith("--trailer-pack-arc="):
            width = f.split("=", 1)[1].split(",")[-1]
            if arc:
                flags.append(f"--trailer-pack-arc={arc}")
            elif bearing is not None:
                flags.append(f"--trailer-pack-arc={(bearing + 180.0) % 360.0:g},{width}")
            else:
                flags.append(f)
        else:
            flags.append(f)
    take2["flags"] = flags
    return take_args(take2, tod=tod or None)


def sweep_cam(args, take: dict) -> int:
    """The `cam` half of the sweep: a static/keyframed trailer camera turned around the landing point."""
    if not args.pivot:
        raise SystemExit("rig_sweep: --cam-bearings needs --pivot=x,y,z")
    pivot = [float(v) for v in args.pivot.split(",")]
    cam = json.loads((ROOT / "game" / take["cam"].replace("res://", "")).read_text())
    times = [round(float(t), 1) for t in args.at.split(",")] if args.at \
        else shot_times(json.loads(args.spec.read_text()), take["id"], 3)
    rows: list[tuple[str, list[Path]]] = []
    for b in [float(x) for x in args.cam_bearings.split(",") if x]:
        out = OUTDIR / f"cam_{take['id']}_b{int(b):03d}.json"
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(rotate_cam(cam, pivot, b), separators=(",", ":")))
        take2 = copy.deepcopy(take)
        take2["cam"] = str(out)
        cells: list[Path] = []
        for t in times:
            cells += drive_stills(take_args(take2, tod=args.tod or None), [t],
                                  f"{take['id']}_b{int(b):03d}", OUTDIR, LOGS, args.reuse)
        if cells:
            rows.append((f"b{int(b):03d}", cells))
    sheet(rows, SHEETS / f"sweep_{take['id']}.jpg")
    print(f"rig_sweep: {take['id']} cam bearings {args.cam_bearings} about {pivot} at {times}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--spec", type=Path, default=ROOT / "game/trailer/shots.json")
    ap.add_argument("--take", required=True)
    ap.add_argument("--bearings", default="", help="comma list of lens bearings around the hero")
    ap.add_argument("--cam-bearings", default="",
                    help="rotate a keyframed `cam` take's keys around --pivot (the landing point)")
    ap.add_argument("--pivot", default="", help="x,y,z the --cam-bearings rotation turns about")
    ap.add_argument("--configs", type=Path, default=None,
                    help='JSON list of {"label": ..., "rig": {...}} patches over the take\'s rig')
    ap.add_argument("--at", default="", help="shot times; default = the take's cut-window midpoints")
    ap.add_argument("--tod", default="")
    ap.add_argument("--pack", default="", help="override --trailer-pack, e.g. `60,spitter:1,ripper:6`")
    ap.add_argument("--arc", default="", help="override --trailer-pack-arc centre,width")
    ap.add_argument("--reuse", action="store_true")
    ap.add_argument("--tag", default="", help="extra tag on every still (so two sweeps do not collide)")
    args = ap.parse_args()

    spec = load_spec(args.spec)
    take = take_by_id(spec, args.take)
    if args.cam_bearings:
        return sweep_cam(args, take)
    base = load_rig(take)
    times = [round(float(t), 1) for t in args.at.split(",")] if args.at \
        else shot_times(spec, take["id"], 3)

    arms: list[tuple[str, dict, float | None]] = []
    for b in [float(x) for x in args.bearings.split(",") if x]:
        arms.append((f"b{int(b):03d}", rotate(base, b), b))
    if args.configs:
        for i, cfg in enumerate(json.loads(args.configs.read_text())):
            rig = copy.deepcopy(base)
            rig.update(cfg.get("rig", {}))
            arms.append((str(cfg.get("label", f"cfg{i}")), rig, None))
    if not arms:
        raise SystemExit("rig_sweep: pass --bearings or --configs")

    extra = f"_{args.tag}" if args.tag else ""
    rows: list[tuple[str, list[Path]]] = []
    for label, rig, bearing in arms:
        cells: list[Path] = []
        for t in times:
            cells += drive_stills(arm_args(take, rig, args.tod, args.pack, args.arc, bearing),
                                  [t], f"{take['id']}_{label}{extra}", OUTDIR, LOGS, args.reuse)
        if cells:
            rows.append((label, cells))
    sheet(rows, SHEETS / f"sweep_{take['id']}{extra}.jpg")
    print(f"rig_sweep: {take['id']} arms={[a[0] for a in arms]} at {times}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
