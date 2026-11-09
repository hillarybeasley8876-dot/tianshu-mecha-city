#!/usr/bin/env python3
"""Band balance of one or more rendered bank files, in the r1 listening-pass bands.

    tools/sfx/run.sh bands.py last_stand boss_kill kill_large_01 ...

Prints 20-80 / 80-250 / 250-1k / 1-4k / 4-16k RMS in dBFS plus the tilt (loudest minus quietest),
which is the number the r1 pass tuned the bank against: a composite whose 4-16 kHz band sits more
than ~20 dB under its low end reads as a thump rather than a hit.
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy import signal as sg

BANDS = ((20, 80), (80, 250), (250, 1000), (1000, 4000), (4000, 16000))
SFX = Path(__file__).resolve().parents[2] / "game" / "audio" / "sfx"


def band_db(x: np.ndarray, rate: int) -> list[float]:
    freqs, psd = sg.welch(x, rate, nperseg=8192)
    out = []
    for lo, hi in BANDS:
        mask = (freqs >= lo) & (freqs < hi)
        out.append(10.0 * np.log10(float(psd[mask].sum()) + 1e-20))
    return out


def main() -> int:
    print(f"{'file':<26} {'20-80':>7} {'80-250':>7} {'250-1k':>7} {'1-4k':>7} {'4-16k':>7} "
          f"{'tilt':>6}")
    for name in sys.argv[1:]:
        path = SFX / (name if name.endswith(".wav") else name + ".wav")
        data, rate = sf.read(str(path), always_2d=False)
        mono = data.mean(axis=1) if data.ndim == 2 else data
        levels = band_db(np.asarray(mono, dtype=np.float64), rate)
        tilt = max(levels) - min(levels)
        print(f"{path.name:<26} " + " ".join(f"{v:7.1f}" for v in levels) + f" {tilt:6.1f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
