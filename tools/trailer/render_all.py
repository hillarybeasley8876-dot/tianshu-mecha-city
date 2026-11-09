#!/usr/bin/env python3
"""Render every take the cut needs, from game/trailer/shots.json.

    tools/trailer/render_all.py             # only the takes that are missing
    tools/trailer/render_all.py --force     # re-render everything
    tools/trailer/render_all.py --only s03  # one take

Each take is a `tools/godot.sh movie` run through tools/trailer/record.sh (which is where the
1920x1080 capture size comes from). Takes are long and share the machine-wide heavy slots, so this
is resumable: a take whose .avi already exists is skipped unless --force.
"""
from __future__ import annotations

import argparse
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from takes import load_spec, take_args  # noqa: E402  (sibling module, not a package)

ROOT = Path(__file__).resolve().parents[2]
RECORD = ROOT / "tools/trailer/record.sh"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--spec", type=Path, default=ROOT / "game/trailer/shots.json")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--only", default="")
    ap.add_argument("--outdir", type=Path, default=None,
                    help="override the spec's take directory (the v2 re-cut renders into its own)")
    args = ap.parse_args()

    spec = load_spec(args.spec)
    takes = spec["takes"]
    # Godot resolves a relative --write-movie path against res://, so the take directory has
    # to be absolute before it reaches the recorder (a relative --outdir silently wrote
    # nothing and the MJPEG writer failed every frame).
    outdir = (args.outdir.resolve() if args.outdir else
              ROOT / spec.get("dir", "captures/trailer/shots"))
    logdir = ROOT / spec.get("logdir", "captures/trailer/logs")
    if args.only:
        wanted = args.only.split(",")
        takes = [t for t in takes if any(w in t["id"] for w in wanted)]
    if not takes:
        print("render_all: nothing to render")
        return 0

    failed: list[str] = []
    for r in takes:
        out = outdir / f"{r['id']}.avi"
        if out.exists() and not args.force:
            print(f"render_all: skip {r['id']} (have {out.stat().st_size // 1_000_000} MB)")
            continue
        out.parent.mkdir(parents=True, exist_ok=True)
        log = logdir / f"{r['id']}.csv"
        log.parent.mkdir(parents=True, exist_ok=True)
        # record.sh takes the timeline as its second POSITIONAL (`--timeline=` is built there), so the
        # first element of take_args is dropped and the bare path handed over instead.
        args_for_take = take_args(r, log=log)
        cmd = [str(RECORD), str(out), r["timeline"]] + args_for_take[1:]
        print(f"render_all: {r['id']} -> {out.name}  ({' '.join(cmd[3:])})", flush=True)
        t0 = time.time()
        code = subprocess.run(cmd).returncode
        print(f"render_all: {r['id']} exit {code} in {time.time() - t0:.0f}s", flush=True)
        if code != 0:
            failed.append(r["id"])
    if failed:
        print("render_all: FAILED " + ", ".join(failed), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
