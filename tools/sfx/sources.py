"""Recorded CC0 source layers: load, cache, and provenance for the manifest.

Dossier rule 11 (`ref/research/audio-music.md` §0): synthesise UI, alarms, beams, charges, servo,
saber, sub and whooshes — but metal, debris, explosions and creature bases are *recorded*. This
module is the only place the bank reads `art/audio_src/`, so every recording used by a rendered
file can be traced back to its pack, author and licence.
"""

from __future__ import annotations

import functools
import re
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy import signal as sg

from dsp import SR, exp_env, fade, frames

SRC_ROOT = Path(__file__).resolve().parents[2] / "art" / "audio_src"


@dataclass(frozen=True)
class Pack:
    """One downloaded archive: where it lives, who made it, under what licence."""

    key: str
    folder: str
    title: str
    licence: str
    author: str
    url: str


PACKS: dict[str, Pack] = {p.key: p for p in [
    Pack("kenney_scifi", "kenney_scifi", "Kenney — Sci-Fi Sounds", "CC0-1.0", "Kenney",
         "https://kenney.nl/assets/sci-fi-sounds"),
    Pack("kenney_digital", "kenney_digital", "Kenney — Digital Audio", "CC0-1.0", "Kenney",
         "https://opengameart.org/content/63-digital-sound-effects-lasers-phasers-space-etc"),
    Pack("oga_scifi50", "oga_scifi50", "OGA — 50 CC0 Sci-Fi SFX", "CC0-1.0", "rubberduck",
         "https://opengameart.org/content/50-cc0-sci-fi-sfx"),
    Pack("oga_sfx100", "oga_sfx100", "OGA — 100 CC0 SFX", "CC0-1.0", "rubberduck",
         "https://opengameart.org/content/100-cc0-sfx"),
    Pack("oga_sfx100v2", "oga_sfx100v2", "OGA — 100 CC0 SFX #2", "CC0-1.0", "rubberduck",
         "https://opengameart.org/content/100-cc0-sfx-2"),
    Pack("oga_creature", "oga_creature", "OGA — 80 CC0 Creature SFX", "CC0-1.0", "rubberduck",
         "https://opengameart.org/content/80-cc0-creature-sfx"),
    Pack("oga_moresounds", "oga_moresounds", "OGA — 202 More Sound Effects", "CC0-1.0", "OwlishMedia",
         "https://opengameart.org/content/202-more-sound-effects"),
    Pack("oga_swishes", "oga_swishes", "OGA — Swishes Sound Pack", "CC0-1.0", "artisticdude",
         "https://opengameart.org/content/swishes-sound-pack"),
    # The page's author field reads "Ben Jaszczak, et al. (Submitted by bart)" and its Attribution
    # Instructions name all four recordists; credit the people who made the sounds, not the uploader.
    Pack("oga_firearm", "oga_firearm", "OGA — The Free Firearm Sound Library", "CC0-1.0",
         "Ben Jaszczak, Brian Nelson, Kevin Heras, Matthew Nanney (submitted to OGA by bart)",
         "https://opengameart.org/content/the-free-firearm-sound-library"),
]}

USED: dict[str, set[str]] = {}
CURRENT: list[str] = []


def reset() -> None:
    """Clear the per-render pack log; build.py calls this around each sound id."""
    CURRENT.clear()


def _note_use(pack_key: str, name: str) -> None:
    USED.setdefault(pack_key, set()).add(name)
    CURRENT.append(pack_key)


def credit(pack_key: str) -> tuple[str, str, str, str]:
    """(title, url, licence, author) for the manifest columns."""
    p = PACKS[pack_key]
    return p.title, p.url, p.licence, p.author


@functools.lru_cache(maxsize=512)
def _files(pack_key: str) -> tuple[str, ...]:
    folder = SRC_ROOT / PACKS[pack_key].folder
    return tuple(sorted(p.name for p in folder.iterdir()
                        if p.suffix.lower() in {".ogg", ".wav", ".mp3", ".flac"}))


def pick(pack_key: str, pattern: str, seed: int = 0) -> str:
    """Deterministically choose one member matching `pattern` (a regex on the file name)."""
    names = [n for n in _files(pack_key) if re.search(pattern, n)]
    if not names:
        raise FileNotFoundError(f"{pack_key}: nothing matches /{pattern}/")
    name = names[seed % len(names)]
    _note_use(pack_key, name)
    return name


@functools.lru_cache(maxsize=512)
def load(pack_key: str, name: str) -> np.ndarray:
    """Decode one source file to mono float64 at SR, peak-normalised."""
    path = SRC_ROOT / PACKS[pack_key].folder / name
    data, rate = sf.read(str(path), dtype="float64", always_2d=True)
    mono = data.mean(axis=1)
    if rate != SR:
        g = np.gcd(int(rate), SR)
        mono = sg.resample_poly(mono, SR // g, rate // g)
    return mono / (np.max(np.abs(mono)) + 1e-12)


def take(pack_key: str, pattern: str, seed: int = 0, *, length: float | None = None,
         start: float = 0.0) -> np.ndarray:
    """Load a chosen recording, optionally windowed to `length` from `start`."""
    buf = load(pack_key, pick(pack_key, pattern, seed))
    if start > 0.0:
        buf = buf[frames(start):]
    if length is not None:
        n = frames(length)
        buf = buf[:n] if buf.size >= n else np.pad(buf, (0, n - buf.size))
    return buf.copy()


def onset(buf: np.ndarray, threshold: float = 0.06) -> int:
    """First sample above `threshold`, so a layer can be aligned to its transient."""
    loud = np.flatnonzero(np.abs(buf) > threshold)
    return int(loud[0]) if loud.size else 0


def align(buf: np.ndarray, threshold: float = 0.06) -> np.ndarray:
    """Trim leading near-silence: recorded layers must land on the beat of the composite."""
    i = onset(buf, threshold)
    return buf[max(0, i - frames(0.002)):]


def shifted(buf: np.ndarray, semitones: float) -> np.ndarray:
    """Pitch-shift by resampling (changes length); the mech/creature size knob."""
    if abs(semitones) < 1e-3:
        return buf
    ratio = 2.0 ** (semitones / 12.0)
    n_out = max(8, int(round(buf.size / ratio)))
    return sg.resample(buf, n_out)


def loopable(buf: np.ndarray, length: float, fade_s: float = 0.08) -> np.ndarray:
    """Crossfade the tail into the head so a recorded bed loops without a click."""
    n = frames(length)
    if buf.size < n:
        reps = int(np.ceil(n / max(buf.size, 1)))
        buf = np.tile(buf, reps)
    buf = buf[: n + frames(fade_s)]
    f = frames(fade_s)
    out = buf[:n].copy()
    out[:f] = buf[:f] * np.linspace(0.0, 1.0, f) + buf[n:n + f] * np.linspace(1.0, 0.0, f)
    return out


def envelope_out(buf: np.ndarray, tail: float = 0.08) -> np.ndarray:
    """Guarantee a click-free end on a recording cut mid-file."""
    return fade(buf, 0.0, tail)


def norm(buf: np.ndarray, peak: float = 1.0) -> np.ndarray:
    """Peak-normalise a processed layer, so composite gains mean the same for every source."""
    m = float(np.max(np.abs(buf)))
    return buf * (peak / m) if m > 1e-9 else buf


def grain(buf: np.ndarray, tau: float) -> np.ndarray:
    """Impose a decay on a recording that has none (gunshot tails are near-constant level)."""
    return buf * exp_env(buf.size, tau, 0.002)
