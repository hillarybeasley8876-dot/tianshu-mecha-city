#!/usr/bin/env python3
"""Render a listening reel of chosen bank ids to one file, so a round can be judged without a window.

    tools/sfx/run.sh reel.py <out.wav> <slot> [<slot> ...]

A slot is `id` (that id's first variant), `id:layer1+layer2` (the ids summed, for a moment that is
really several rows at once), or `id@gain_db`. Slots are separated by 0.6 s of silence and each is
preceded by a short spoken-free marker tone, so a listener can find the slot by ear.

This is NOT a game capture: it is the exact PCM the bank ships, laid out in order. It exists because
`tools/godot.sh movie` needs a window the user's machine may not be free for, and because a bank
change should be audible on its own before it is judged inside a mix.
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import soundfile as sf

ROOT = Path(__file__).resolve().parents[2]
SFX = ROOT / "game" / "audio" / "sfx"
VOICE = ROOT / "game" / "audio" / "voice"
STINGERS = ROOT / "game" / "audio" / "music" / "stingers"
GAP_S = 0.6
MARK_S = 0.12
MARK_HZ = 1000.0
SR = 44100


def load(sound_id: str) -> np.ndarray:
    """Find a bank file by id in the sfx, voice or stinger folder (one variant or the _01 stem)."""
    for folder in (SFX, VOICE, STINGERS):
        for name in (f"{sound_id}.wav", f"{sound_id}_01.wav", f"{sound_id}.ogg"):
            path = folder / name
            if path.exists():
                data, rate = sf.read(str(path), always_2d=False)
                mono = data.mean(axis=1) if data.ndim == 2 else data
                if rate != SR:
                    raise SystemExit(f"{name}: {rate} Hz, expected {SR}")
                return np.asarray(mono, dtype=np.float64)
    raise SystemExit(f"reel: no bank file for id '{sound_id}'")


def marker() -> np.ndarray:
    n = int(MARK_S * SR)
    t = np.arange(n) / SR
    return np.sin(2 * np.pi * MARK_HZ * t) * np.exp(-t / 0.03) * 0.12


def main() -> int:
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    out = Path(sys.argv[1])
    slots = sys.argv[2:]
    gap = np.zeros(int(GAP_S * SR))
    pieces: list[np.ndarray] = [gap]
    report: list[str] = []
    for slot in slots:
        gain_db = 0.0
        body = slot
        if "@" in slot:
            body, gain_txt = slot.split("@", 1)
            gain_db = float(gain_txt)
        layers = [load(part) for part in body.split("+")]
        n = max(layer.size for layer in layers)
        buf = np.zeros(n)
        for layer in layers:
            buf[: layer.size] += layer
        buf *= 10.0 ** (gain_db / 20.0)
        peak = float(np.max(np.abs(buf))) or 1.0
        rms = float(np.sqrt(np.mean(buf**2)))
        pieces += [marker(), gap * 0.0, buf, gap]
        report.append(f"  {slot:<44} {n / SR:5.2f}s  peak {20 * np.log10(peak):6.2f} dBFS  "
                      f"rms {20 * np.log10(rms + 1e-12):6.2f} dBFS")
    audio = np.concatenate(pieces)
    # -1 dBFS ceiling so the reel itself never clips, whatever the slots sum to.
    peak = float(np.max(np.abs(audio))) or 1.0
    audio = audio / peak * (10.0 ** (-1.0 / 20.0))
    out.parent.mkdir(parents=True, exist_ok=True)
    sf.write(str(out), np.stack([audio, audio], axis=1), SR, subtype="PCM_16")
    print(f"reel -> {out}  {audio.size / SR:.2f}s stereo {SR} Hz, peak -1.0 dBFS")
    print("\n".join(report))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
