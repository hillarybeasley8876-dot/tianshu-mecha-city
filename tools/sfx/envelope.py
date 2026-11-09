#!/usr/bin/env python3
"""RMS envelope of a rendered bank file in fixed windows — the shape of a sound over time.

    tools/sfx/run.sh envelope.py boss_kill[,last_stand] [window_s]

Listening without a window means reading the envelope: where the energy is, whether the intended
arc (cry -> sub -> impacts -> debris -> tail) is actually there, and whether anything is a single
undifferentiated block.
"""
import sys
from pathlib import Path
import numpy as np
import soundfile as sf

SFX = Path(__file__).resolve().parents[2] / "game" / "audio" / "sfx"
window = float(sys.argv[2]) if len(sys.argv) > 2 else 0.25
for name in sys.argv[1].split(","):
    path = SFX / (name if name.endswith(".wav") else name + ".wav")
    data, sr = sf.read(str(path), always_2d=False)
    mono = data.mean(axis=1) if data.ndim == 2 else data
    step = int(window * sr)
    usable = mono[: mono.size - (mono.size % step)]
    blocks = usable.reshape(-1, step)
    rms = 20 * np.log10(np.sqrt((blocks ** 2).mean(axis=1)) + 1e-12)
    print(f"\n{name}  {mono.size / sr:.2f}s  window {window}s")
    top = rms.max()
    for i, v in enumerate(rms):
        bar = "#" * max(0, int(round((v - (top - 40)) / 1.2)))
        print(f"  {i * window:5.2f}s {v:7.1f} dB |{bar}")
