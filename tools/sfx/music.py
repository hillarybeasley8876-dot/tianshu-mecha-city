"""Music stem synthesis for the adaptive score (ref/research/audio-music.md §6.2).

Grid: 140 BPM, 4/4, D minor, 16-bar loops (27.43 s). Every stem is a whole number of bars and its
note tails are wrapped into the head, so each clip loops seamlessly and stays bar-synced inside the
AudioStreamInteractive graph.

    tools/sfx/run.sh music.py
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np

import dsp
import recipes as R

BPM = 140.0
BEAT = 60.0 / BPM           # 0.428571 s
BAR = BEAT * 4              # 1.714286 s
BARS = 16
LOOP = BAR * BARS           # 27.43 s
SR = dsp.SR

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "game" / "audio" / "music"

# D natural minor, two octaves (D3..C5).
SCALE = {"D3": 146.83, "E3": 164.81, "F3": 174.61, "G3": 196.00, "A3": 220.00, "Bb3": 233.08,
         "C4": 261.63, "D4": 293.66, "E4": 329.63, "F4": 349.23, "G4": 392.00, "A4": 440.00,
         "Bb4": 466.16, "C5": 523.25, "D5": 587.33, "D2": 73.42, "A2": 110.0, "Bb2": 116.54,
         "F2": 87.31, "C3": 130.81, "G2": 98.0}


def note(name: str, octave_shift: int = 0) -> float:
    return SCALE[name] * (2.0 ** octave_shift)


def place(buffer: np.ndarray, sound: np.ndarray, at_s: float) -> np.ndarray:
    """Add `sound` at `at_s`, folding anything past the loop end back to the head.

    Wrapping (rather than truncating) is what keeps a stem's note tails continuous across the loop
    point, so a clip can repeat forever without a click.
    """
    n = buffer.size
    start = dsp.frames(at_s) % n
    head = min(sound.size, n - start)
    buffer[start:start + head] += sound[:head]
    tail = sound.size - head
    if tail > 0:
        folded = tail % n
        buffer[:folded] += sound[head:head + folded]
    return buffer


# --- instruments ------------------------------------------------------------------------------------
def pad_voice(freq: float, length: float, detune: float = 0.008, voices: int = 3) -> np.ndarray:
    """Slow detuned saw stack through a one-pole low-pass: the harmonic bed."""
    n = dsp.frames(length)
    x = np.arange(n) / SR
    out = np.zeros(n)
    for i in range(voices):
        f = freq * (1.0 + detune * (i - voices // 2))
        for h in range(1, 9):
            out += np.sin(2 * np.pi * f * h * x + i) / (h**1.3)
    out /= voices
    env = np.minimum(x / 0.6, 1.0) * np.minimum((length - x) / 0.6, 1.0)
    return dsp.lowpass(out * env, 1400.0)


def pluck(freq: float, length: float, bright: float = 1.0) -> np.ndarray:
    """Short saw pluck for pulses and arpeggios."""
    n = dsp.frames(length)
    x = np.arange(n) / SR
    tone = sum(np.sin(2 * np.pi * freq * h * x) / h for h in range(1, 12))
    env = np.exp(-x / (length * 0.35))
    return dsp.lowpass(tone * env, 3500.0 * bright) * 0.5


def bass_voice(freq: float, length: float, drive_amount: float = 2.4) -> np.ndarray:
    """Distorted analog bass: sine + sub, tanh driven (dossier §6.4 prompt language)."""
    n = dsp.frames(length)
    x = np.arange(n) / SR
    tone = np.sin(2 * np.pi * freq * x) + 0.4 * np.sin(2 * np.pi * freq * 2 * x)
    env = np.minimum(x / 0.01, 1.0) * np.exp(-x / (length * 0.6))
    return np.tanh(drive_amount * tone * env) * 0.5


def brass(freq: float, length: float) -> np.ndarray:
    """Saw stack with a filter swell: stabs and fanfares."""
    n = dsp.frames(length)
    x = np.arange(n) / SR
    tone = sum(np.sin(2 * np.pi * freq * h * x) / (h**0.9) for h in range(1, 14))
    swell = np.minimum(x / 0.09, 1.0)
    cutoff = 700.0 + 2600.0 * swell
    env = swell * np.exp(-np.maximum(x - 0.15, 0.0) / (length * 0.45))
    return dsp.lowpass(tone * env, cutoff) * 0.4


def choir(freq: float, length: float) -> np.ndarray:
    """Formant-ish vowel pad: three band-passed sines, slow vibrato."""
    n = dsp.frames(length)
    x = np.arange(n) / SR
    vib = 1.0 + 0.004 * np.sin(2 * np.pi * 4.6 * x)
    tone = np.zeros(n)
    for h in (1, 2, 3, 4, 5):
        tone += np.sin(2 * np.pi * freq * h * vib * x) / h
    breath = dsp.noise_band(n, 700.0, 2600.0, R.rng(int(freq))) * 0.12
    env = np.minimum(x / 0.9, 1.0) * np.minimum((length - x) / 0.9, 1.0)
    return dsp.lowpass(tone + breath, 2200.0) * env * 0.35


def kick(seed: int = 1, hard: float = 1.0) -> np.ndarray:
    return R.sub_thump(0.28, 110.0 * hard, 42.0, seed) * 0.9


def snare(seed: int = 2) -> np.ndarray:
    n = dsp.frames(0.2)
    r = R.rng(seed)
    noise = dsp.noise_band(n, 900.0, 6000.0, r) * dsp.exp_env(n, 0.05)
    body = np.sin(2 * np.pi * 190.0 * np.arange(n) / SR) * dsp.exp_env(n, 0.03)
    return noise * 0.7 + body * 0.5


def hat(seed: int = 3, open_hat: bool = False) -> np.ndarray:
    length = 0.18 if open_hat else 0.05
    n = dsp.frames(length)
    noise = dsp.highpass(dsp.white(n, R.rng(seed)), 7000.0)
    return noise * dsp.exp_env(n, 0.04 if open_hat else 0.012) * 0.35


def taiko(seed: int = 4) -> np.ndarray:
    n = dsp.frames(0.4)
    r = R.rng(seed)
    tone = R.sub_thump(0.35, 95.0, 50.0, seed) * 0.8
    skin = dsp.noise_band(n, 200.0, 1800.0, r) * dsp.exp_env(n, 0.05) * 0.5
    return dsp.mix(tone, skin)


def anvil(seed: int = 5) -> np.ndarray:
    """Industrial hit: the AC6/Transformers flavour note in the combat stems."""
    return R.metal_ting(420.0, 0.6, ratios=(1.0, 2.76, 5.4), amps=(1.0, 0.5, 0.25),
                        taus=(0.25, 0.15, 0.08), seed=seed) * 0.5


# --- stems -------------------------------------------------------------------------------------------
def stem_victory() -> np.ndarray:
    """4-bar fanfare in D major-ish resolution (D minor with a raised third on the last chord)."""
    out = np.zeros(dsp.frames(BAR * 4))
    melody = [(0.0, "D4", 1.0), (1.0, "F4", 1.0), (2.0, "A4", 1.0), (3.0, "D5", 2.0)]
    for offset, name, length in melody:
        place(out, brass(note(name), BEAT * length), offset * BEAT)
    place(out, choir(note("D4"), BAR * 2.0), BAR * 2.0)
    place(out, taiko(7), 0.0)
    place(out, taiko(8), 3.0 * BEAT)
    return out


def stem_defeat() -> np.ndarray:
    """4-bar descending fall: the player died."""
    out = np.zeros(dsp.frames(BAR * 4))
    for i, name in enumerate(["D4", "C4", "Bb3", "A3"]):
        place(out, brass(note(name), BEAT * 1.2) * (1.0 - 0.15 * i), i * BEAT)
    place(out, pad_voice(note("D2"), BAR * 4.0), 0.0)
    place(out, R.sub_thump(1.2, 70.0, 30.0, 3), 3.0 * BEAT)
    return out


def stem_spire_cleared() -> np.ndarray:
    """2-bar lift played over the held clip (hold_previous / RETURN_TO_HOLD)."""
    out = np.zeros(dsp.frames(BAR * 2))
    for offset, name in ((0.0, "A4"), (0.5, "D5")):
        place(out, brass(note(name), BEAT * 1.0), offset * BEAT)
    place(out, anvil(9), 0.0)
    place(out, R.metal_ting(1174.66, 1.4, seed=12) * 0.5, 0.5 * BEAT)
    return out


def stem_stinger_stagger() -> np.ndarray:
    out = np.zeros(dsp.frames(BAR))
    place(out, brass(note("Bb3"), BEAT * 1.5), 0.0)
    place(out, taiko(13), 0.0)
    place(out, anvil(14), 0.25 * BEAT)
    return out


def stem_stinger_kill_large() -> np.ndarray:
    out = np.zeros(dsp.frames(BAR * 0.75))
    place(out, R.sub_thump(0.6, 80.0, 34.0, 15), 0.0)
    place(out, brass(note("D3"), BEAT * 0.8), 0.0)
    place(out, taiko(16), 0.0)
    return out


def stem_stinger_boss_phase() -> np.ndarray:
    out = np.zeros(dsp.frames(BAR * 2))
    for i in range(8):
        place(out, taiko(20 + i) * (0.5 + 0.06 * i), i * BEAT * 0.5)
    place(out, brass(note("D3"), BAR), BAR)
    place(out, R.charge_riser(BAR * 2, 21, False, 110.0, 440.0) * 0.4, 0.0)
    return out


STINGERS = {"stinger_stagger": stem_stinger_stagger,
            "stinger_kill_large": stem_stinger_kill_large,
            "stinger_boss_phase": stem_stinger_boss_phase,
            "stinger_spire_cleared": stem_spire_cleared,
            "stinger_victory": stem_victory,
            "stinger_defeat": stem_defeat}


def render(buffer: np.ndarray, peak_db: float = -3.0) -> np.ndarray:
    return dsp.finalize(buffer, peak_db, fade_out=0.0)


def write_metronome() -> None:
    """One silent bar at 140 BPM: the beat clock the music director reads (dossier §6.3).

    AudioStreamInteractive exposes no playback position, so the director polls this player's
    position instead. Silence keeps it out of the mix at volume -80 dB.
    """
    bar = np.zeros(dsp.frames(BAR))
    dsp.write_ogg(OUT / "metronome.ogg", bar)


def main() -> int:
    """Render the stingers and the silent beat clock. The score itself is real CC0 tracks now —
    see tools/sfx/music_tracks.py, which writes game/audio/music/<clip>_mix.ogg + clips.json."""
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "stingers").mkdir(parents=True, exist_ok=True)
    write_metronome()
    count = 1
    for name, builder in STINGERS.items():
        audio = render(builder(), -4.0)
        path = OUT / "stingers" / f"{name}.ogg"
        dsp.write_ogg(path, audio)
        count += 1
        print(f"  stingers/{path.name:20s} {audio.size / SR:5.2f}s")
    print(f"{count} cue files at {BPM:.0f} BPM, D minor (the adaptive clips are sourced tracks)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
