#!/usr/bin/env python3
"""Measure tempo, key and loop length of the candidate music tracks.

The adaptive score is one bar-synced AudioStreamInteractive graph (dossier §6.3), so the chosen
explore / combat / boss / victory pieces have to be described with a BPM and a bar count the graph
can quantise to. This prints those numbers plus a rough key estimate for family matching.

    tools/sfx/run.sh analyse_music.py [file ...]
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy import signal as sg

SR = 44100
ROOT = Path(__file__).resolve().parents[2]
DEFAULT = sorted((ROOT / "art" / "audio_src" / "oga_music").glob("*"))
DEFAULT += sorted((ROOT / "art" / "audio_src" / "oga_bossmetal").glob("*"))
NOTE_NAMES = ("C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B")
# Krumhansl major / minor profiles, used only to rank the 24 candidates.
MAJOR = np.array([6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88])
MINOR = np.array([6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17])


def read(path: Path, seconds: float = 90.0) -> np.ndarray:
    data, rate = sf.read(str(path), dtype="float64", always_2d=True)
    mono = data.mean(axis=1)
    if rate != SR:
        g = np.gcd(int(rate), SR)
        mono = sg.resample_poly(mono, SR // g, rate // g)
    return mono[: int(seconds * SR)]


def onset_envelope(x: np.ndarray, hop: int = 512) -> np.ndarray:
    """Spectral flux: the standard cheap onset detector, good enough for a tempo estimate."""
    win = 2048
    frames_n = 1 + (x.size - win) // hop
    window = np.hanning(win)
    prev = np.zeros(win // 2 + 1)
    flux = np.zeros(frames_n)
    for i in range(frames_n):
        spec = np.abs(np.fft.rfft(x[i * hop:i * hop + win] * window))
        flux[i] = np.maximum(spec - prev, 0.0).sum()
        prev = spec
    flux -= sg.medfilt(flux, 31)
    return np.maximum(flux, 0.0)


def tempo(x: np.ndarray) -> float:
    hop = 512
    env = onset_envelope(x, hop)
    env = (env - env.mean()) / (env.std() + 1e-9)
    corr = np.correlate(env, env, mode="full")[env.size - 1:]
    fps = SR / hop
    lo, hi = int(fps * 60 / 200), int(fps * 60 / 60)   # 60-200 BPM lag window
    lag = lo + int(np.argmax(corr[lo:hi]))
    bpm = 60.0 * fps / lag
    while bpm < 80.0:
        bpm *= 2.0
    while bpm > 170.0:
        bpm /= 2.0
    return round(bpm, 1)


def chroma(x: np.ndarray) -> np.ndarray:
    win, hop = 8192, 4096
    out = np.zeros(12)
    window = np.hanning(win)
    for i in range(0, max(x.size - win, 1), hop):
        spec = np.abs(np.fft.rfft(x[i:i + win] * window))
        freqs = np.fft.rfftfreq(win, 1.0 / SR)
        with np.errstate(divide="ignore", invalid="ignore"):
            midi = 69 + 12 * np.log2(np.where(freqs > 0, freqs, 1e-9) / 440.0)
        bins = np.mod(np.round(midi).astype(int), 12)
        for b in range(12):
            out[b] += spec[(bins == b) & (freqs > 55) & (freqs < 2000)].sum()
    return out / (out.sum() + 1e-12)


def key(x: np.ndarray) -> str:
    c = chroma(x)
    best, name = -2.0, "?"
    for i in range(12):
        for profile, mode in ((MAJOR, "maj"), (MINOR, "min")):
            score = float(np.corrcoef(np.roll(profile, i), c)[0, 1])
            if score > best:
                best, name = score, f"{NOTE_NAMES[i]} {mode}"
    return f"{name} ({best:.2f})"


def main() -> int:
    paths = [Path(a) for a in sys.argv[1:]] or [p for p in DEFAULT if p.suffix != ".zip"]
    print(f"{'file':44s} {'secs':>7s} {'bpm':>6s} {'bars@4/4':>9s}  key")
    for path in paths:
        try:
            x = read(path)
        except Exception as exc:  # noqa: BLE001 - report and keep going
            print(f"{path.name:44s}  unreadable: {exc}")
            continue
        if x.size < SR * 4:
            continue
        bpm = tempo(x)
        seconds = sf.info(str(path)).duration
        bars = seconds * bpm / 60.0 / 4.0
        print(f"{path.name:44s} {seconds:7.1f} {bpm:6.1f} {bars:9.2f}  {key(x)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
