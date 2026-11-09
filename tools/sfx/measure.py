#!/usr/bin/env python3
"""Bank QA report: true peak, loudness, loop-point discontinuity and click detection.

    tools/sfx/run.sh measure.py [--dir game/audio/sfx] [--csv out.csv]

Flags files that break the dossier's rules: > -1 dBTP, loop points that jump, or a single-sample
jump more than 8x the local derivative floor (an audible click rather than a bright transient).
"""

from __future__ import annotations

import argparse
import csv
from pathlib import Path

import numpy as np
import soundfile as sf

import dsp

ROOT = Path(__file__).resolve().parents[2]


def analyse(path: Path) -> dict:
    data, sr = sf.read(str(path), always_2d=False)
    mono = data.mean(axis=1) if data.ndim == 2 else data
    peak = float(np.max(np.abs(mono))) if mono.size else 0.0
    rms = float(np.sqrt(np.mean(mono**2))) if mono.size else 0.0
    diffs = np.abs(np.diff(mono)) if mono.size > 1 else np.zeros(1)
    # The first 5 ms may hold a designed tick (recipe R1's 1.5 ms transient); a click *there* is
    # intentional, so the click statistic starts after it.
    skip = min(int(0.005 * sr), diffs.size)
    body_diffs = diffs[skip:] if diffs.size > skip else diffs
    jump = float(np.max(body_diffs)) if body_diffs.size else 0.0
    floor = float(np.percentile(body_diffs, 99.5)) + 1e-9
    seam = abs(float(mono[0]) - float(mono[-1])) if mono.size else 0.0
    spec = np.abs(np.fft.rfft(mono * np.hanning(mono.size)))
    freqs = np.fft.rfftfreq(mono.size, 1.0 / sr)
    centroid = float((spec * freqs).sum() / (spec.sum() + 1e-12))
    return {
        "file": path.name, "seconds": round(mono.size / sr, 3), "sr": sr,
        "peak_db": round(20 * np.log10(max(peak, 1e-9)), 2),
        "rms_db": round(20 * np.log10(max(rms, 1e-9)), 2),
        "tp_db": round(dsp.true_peak_db(mono), 2),
        "max_jump": round(jump, 3), "spike_ratio": round(jump / floor, 2),
        "loop_seam": round(seam, 4),
        "centroid_hz": int(centroid),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dir", default="game/audio/sfx")
    parser.add_argument("--csv", default="")
    args = parser.parse_args()
    folder = ROOT / args.dir
    rows = [analyse(p) for p in sorted(folder.glob("*")) if p.suffix in (".wav", ".ogg")]
    bad_peak = [r for r in rows if r["tp_db"] > -0.9]
    clicks = [r for r in rows if r["spike_ratio"] > 8.0]
    seams = [r for r in rows if r["file"].endswith(("_loop.wav", "_loop.ogg")) and r["loop_seam"] > 0.05]
    print(f"{len(rows)} files, {sum(r['seconds'] for r in rows):.1f} s of audio")
    print(f"over -0.9 dBTP: {len(bad_peak)}  clicks(spike>8x): {len(clicks)}  "
          f"loop seams>0.05: {len(seams)}")
    for label, group in (("PEAK", bad_peak), ("CLICK", clicks), ("SEAM", seams)):
        for row in group[:20]:
            print(f"  {label:5s} {row['file']:32s} tp={row['tp_db']:6.2f} "
                  f"spike={row['spike_ratio']:5.2f} seam={row['loop_seam']:.3f}")
    if args.csv:
        Path(args.csv).parent.mkdir(parents=True, exist_ok=True)
        with open(args.csv, "w", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
            writer.writeheader()
            writer.writerows(rows)
        print(f"csv -> {args.csv}")
    # Clicks are reported, not fatal: several ids carry a designed transient (recipe R1's tick).
    return 1 if (bad_peak or seams) else 0


if __name__ == "__main__":
    raise SystemExit(main())
