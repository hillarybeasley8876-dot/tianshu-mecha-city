#!/usr/bin/env python3
"""Measure a movie capture's audio: loudness, true peak, band balance, per-section activity.

Used as the objective half of the listening pass — this environment cannot play audio back, so the
reel and the demo captures are judged from integrated loudness, spectral tilt and where energy sits
in time, and the fixes are re-measured afterwards.

    tools/sfx/run.sh measure_movie.py captures/audio_reel.avi [--sections=0,12,20]
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy import signal as sg

BANDS = ((20, 80), (80, 250), (250, 1000), (1000, 4000), (4000, 16000))
LUFS_RE = re.compile(r"I:\s*(-?\d+\.?\d*)\s*LUFS")
LRA_RE = re.compile(r"LRA:\s*(-?\d+\.?\d*)\s*LU")
PEAK_RE = re.compile(r"Peak:\s*(-?\d+\.?\d*)\s*dBFS")


def extract(path: Path) -> tuple[np.ndarray, int]:
    """Decode the capture's audio track to mono float64."""
    with tempfile.TemporaryDirectory() as tmp:
        wav = Path(tmp) / "a.wav"
        subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(path),
                        "-vn", "-ac", "2", "-ar", "48000", str(wav)], check=True)
        data, rate = sf.read(str(wav), dtype="float64", always_2d=True)
    return data.mean(axis=1), rate


def ebur128(path: Path) -> dict[str, float]:
    """Integrated loudness, range and true peak via ffmpeg's ebur128 filter."""
    result = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", str(path),
                             "-af", "ebur128=peak=true", "-f", "null", "-"],
                            capture_output=True, text=True, check=False)
    summary = result.stderr.split("Summary:")[-1]
    out: dict[str, float] = {}
    for key, pattern in (("lufs_i", LUFS_RE), ("lra", LRA_RE), ("true_peak", PEAK_RE)):
        found = pattern.search(summary)
        if found:
            out[key] = float(found.group(1))
    return out


def band_db(x: np.ndarray, rate: int) -> list[float]:
    """RMS level per octave-ish band, in dBFS."""
    freqs, psd = sg.welch(x, rate, nperseg=8192)
    levels = []
    for lo, hi in BANDS:
        mask = (freqs >= lo) & (freqs < hi)
        power = float(psd[mask].sum())
        levels.append(10.0 * np.log10(power + 1e-20))
    return levels


def section_activity(x: np.ndarray, rate: int, window: float = 0.5) -> np.ndarray:
    """RMS per `window` seconds, in dBFS — the shape of the reel over time."""
    step = int(window * rate)
    usable = x[: x.size - (x.size % step)] if x.size >= step else x
    blocks = usable.reshape(-1, step) if usable.size else np.zeros((1, step))
    rms = np.sqrt((blocks ** 2).mean(axis=1))
    return 20.0 * np.log10(rms + 1e-9)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("path", type=Path)
    ap.add_argument("--window", type=float, default=0.5)
    args = ap.parse_args()
    if not args.path.is_file():
        print(f"missing capture {args.path}", file=sys.stderr)
        return 1
    x, rate = extract(args.path)
    loud = ebur128(args.path)
    levels = band_db(x, rate)
    print(f"{args.path.name}: {x.size / rate:.1f} s, {rate} Hz")
    print("  LUFS-I %(lufs_i)s  true peak %(true_peak)s dBTP  LRA %(lra)s LU" % loud)
    print("  bands 20-80/80-250/250-1k/1-4k/4-16k: "
          + " / ".join(f"{v:.1f}" for v in levels))
    tilt = max(levels) - min(levels)
    print(f"  spectral tilt (max-min band): {tilt:.1f} dB")
    activity = section_activity(x, rate, args.window)
    quiet = np.flatnonzero(activity < activity.max() - 40.0)
    print(f"  windows below (peak-40 dB): {quiet.size}/{activity.size}"
          + (f"  at {[round(float(i) * args.window, 1) for i in quiet[:12]]} s" if quiet.size else ""))
    print("  activity dBFS per %.1fs: " % args.window
          + " ".join(f"{v:.0f}" for v in activity))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
