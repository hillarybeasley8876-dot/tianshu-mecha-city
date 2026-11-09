#!/usr/bin/env python3
"""Drive a take and keep its stills: the shared half of the trailer's A/B probes.

`tod_ab.py` (which time of day) and `rig_sweep.py` (which camera bearing) both do the same thing —
run the take's own timeline through `tools/godot.sh drive`, screenshot a list of times, and turn the
window's backing-store frames into comparable 16:9 stills — so that lives here once.

    from stills import drive_stills, letter
"""
from __future__ import annotations

import subprocess
import time
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
GODOT = ROOT / "tools/godot.sh"
STILL_W = 1280


def letter(t: float) -> str:
    """The filename suffix autoplay gives a shot at t (2.43 -> `t2_4`; it writes one decimal)."""
    return f"t{t:.1f}".replace(".", "_")


def shrink(src: Path, dst: Path) -> Path | None:
    """Centre-crop to 16:9 and downscale — a still is the window's backing store (16:10), not 16:9."""
    if not src.exists():
        return None
    im = Image.open(src).convert("RGB")
    w, h = im.size
    target_h = round(w * 9 / 16)
    if h > target_h:
        im = im.crop((0, (h - target_h) // 2, w, (h - target_h) // 2 + target_h))
    im.resize((STILL_W, round(STILL_W * 9 / 16)), Image.LANCZOS).save(dst, quality=90)
    return dst


def drive_stills(args: list[str], times: list[float], tag: str, outdir: Path, logdir: Path,
                 reuse: bool = False) -> list[Path]:
    """One windowed drive, `--shots` at `times`, returning the 16:9 stills it produced (or [])."""
    outdir.mkdir(parents=True, exist_ok=True)
    logdir.mkdir(parents=True, exist_ok=True)
    raw = [outdir / f"{tag}_{letter(t)}.jpg" for t in times]
    small = [outdir / f"{tag}_{letter(t)}_16x9.jpg" for t in times]
    if not (reuse and all(p.exists() for p in raw)):
        log = logdir / f"{tag}.txt"
        cmd = [str(GODOT), "drive", *args, "--shots=" + ",".join(str(t) for t in times),
               f"--out={tag}", f"--outdir={outdir}"]
        print(f"stills: {tag}  shots={times}", flush=True)
        t0 = time.time()
        with log.open("w") as fh:
            code = subprocess.run(cmd, stdout=fh, stderr=subprocess.STDOUT).returncode
        lines = log.read_text().splitlines()
        done = [l for l in lines if "DRIVE done" in l]
        errs = [l for l in lines if l.startswith("ERROR") or "SCRIPT ERROR" in l]
        print(f"stills: {tag} exit {code} in {time.time() - t0:.0f}s  "
              f"{(done or errs or [''])[-1]}", flush=True)
        if code != 0:
            return []
    else:
        print(f"stills: {tag} reuse", flush=True)
    return [p for r, s in zip(raw, small) if (p := shrink(r, s))]


def sheet(rows: list[tuple[str, list[Path]]], out: Path) -> None:
    """A labelled grid: one row per label, one column per still."""
    if not rows:
        return
    cols = min(len(files) for _l, files in rows)
    grid = [f"{label}=" + ",".join(str(p) for p in files[:cols]) for label, files in rows]
    subprocess.run(["python3", str(ROOT / "tools/trailer/grid.py"), "-o", str(out),
                    "--cols", str(cols), *grid], check=False)
