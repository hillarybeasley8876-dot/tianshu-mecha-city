#!/usr/bin/env python3
"""Turn the sourced CC0 tracks into the adaptive score's clips (dossier §6.3).

The score is one AudioStreamInteractive whose clips are switched bar-synced from
`Audio.music_intensity()`. Real tracks do not share one tempo or key, so instead of the vertical
stem layering the synthesised score used, each clip is one full mix and the graph crossfades
between clips on their own bars — the fallback the brief allows.

Each track is trimmed to a whole number of its own bars, its tail is equal-power crossfaded into
its head so it loops without a click, and every clip is loudness-matched so a transition never
jumps in level. `game/audio/music/clips.json` records the per-clip bpm/bar count the director needs.

    tools/sfx/run.sh music_tracks.py
"""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy import signal as sg

import analyse_music as AM
import dsp
from dsp import SR

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "art" / "audio_src"
OUT = ROOT / "game" / "audio" / "music"
TARGET_LUFS = -20.0
TARGET_TP = -1.5
XFADE_BARS = 2.0


def track(folder: str, name: str) -> Path:
    path = SRC / folder / name
    if not path.is_file():
        raise FileNotFoundError(f"missing music source {path}")
    return path


def load_track_credits() -> dict[str, dict[str, str]]:
    """Map `folder/file` -> {title, page, licence, author}, from the oga_fetch sidecars.

    The manifest and CREDITS_AUDIO.md must name the track the clip actually came from, with that
    track's own page — so the credit is read from the fetch record rather than retyped. A track
    unpacked from a zip has no download URL to join on; a folder whose sidecar holds exactly one
    node (oga_bossmetal) is used whole.
    """
    out: dict[str, dict[str, str]] = {}
    for sidecar in sorted(SRC.glob("*/oga_sources.json")):
        folder = sidecar.parent.name
        entries = json.loads(sidecar.read_text())
        for entry in entries:
            rec = {"title": str(entry.get("title", "")).split(" | ")[0].strip(),
                   "page": str(entry.get("page", "")),
                   "licence": "+".join(str(x) for x in entry.get("licences", [])) or "CC0",
                   "author": str(entry.get("author", "unknown"))}
            for url in entry.get("files", []):
                name = Path(url.split("?")[0]).name.replace("%23", "_").replace("%20", "_")
                out[f"{folder}/{name}"] = rec
        if len(entries) == 1 and entries[0].get("files"):
            rec = {"title": str(entries[0].get("title", "")).split(" | ")[0].strip(),
                   "page": str(entries[0].get("page", "")),
                   "licence": "+".join(str(x) for x in entries[0].get("licences", [])) or "CC0",
                   "author": str(entries[0].get("author", "unknown"))}
            for member in sorted((SRC / folder).glob("*")):
                if member.suffix.lower() in {".ogg", ".wav", ".mp3", ".flac"}:
                    out.setdefault(f"{folder}/{member.name}", rec)
    return out


TRACK_CREDITS = load_track_credits()


def track_credit(folder: str, filename: str) -> dict[str, str]:
    """The recorded credit for one source track; raises if the sidecar does not name it."""
    rec = TRACK_CREDITS.get(f"{folder}/{filename}")
    if rec is None:
        raise KeyError(f"no oga_sources.json record for {folder}/{filename}")
    return rec


# clip -> (folder, file, mood note). Tempo and key come from analyse_music.py, not from guesswork.
CLIPS: dict[str, tuple[str, str, str]] = {
    "explore": ("oga_music", "covert_operations.mp3",
                "tense exploration — espionage pulse, C major, 96 BPM"),
    "tension": ("oga_music", "technological_menace.wav",
                "pre-contact tension — cold synth bed, C major, 110 BPM"),
    "combat": ("oga_music", "epic_combat.ogg",
               "contact — driving orchestral action, D minor, 129 BPM"),
    "boss": ("oga_bossmetal", "boss_battle_2_metal_loop.wav",
             "boss — symphonic metal, E major, 146 BPM"),
    "spire_cleared": ("oga_music", "heroic_pressure_-_extended_-_starninjas_0.ogg",
                      "spire down — short heroic lift, D major, 120 BPM"),
    "victory": ("oga_music", "ForgottenVictory.ogg",
                "victory — full orchestral fanfare, F major, 140 BPM"),
}

# Cap each clip so a loop does not outstay itself; explore keeps the longest bed.
MAX_BARS = {"explore": 40, "tension": 32, "combat": 40, "boss": 24,
            "spire_cleared": 12, "victory": 32}


def load(path: Path) -> np.ndarray:
    data, rate = sf.read(str(path), dtype="float64", always_2d=True)
    mono = data.mean(axis=1)
    if rate != SR:
        g = np.gcd(int(rate), SR)
        mono = sg.resample_poly(mono, SR // g, rate // g)
    return mono


def trim_to_bars(x: np.ndarray, bpm: float, max_bars: int) -> tuple[np.ndarray, int]:
    """Cut to a whole number of bars that fits inside the source."""
    bar = 4.0 * 60.0 / bpm
    bars = int(min(max_bars, max(4, x.size / SR / bar)))
    n = int(bars * bar * SR)
    return x[:n], bars


def seamless(x: np.ndarray, bpm: float) -> np.ndarray:
    """Equal-power crossfade of the last XFADE_BARS into the head, then drop them."""
    bar = 4.0 * 60.0 / bpm
    f = int(XFADE_BARS * bar * SR)
    if f * 3 > x.size:
        f = x.size // 4
    head, body, tail = x[:f], x[f:x.size - f], x[x.size - f:]
    theta = np.linspace(0.0, np.pi / 2, f)
    return np.concatenate([head * np.sin(theta) + tail * np.cos(theta), body])


def loudness_gain(path: Path, buffer: np.ndarray) -> float:
    """Measure integrated loudness with ffmpeg and return the gain to reach TARGET_LUFS."""
    probe = OUT / "_loudness_probe.wav"
    sf.write(str(probe), buffer, SR, subtype="PCM_16")
    result = subprocess.run(
        ["ffmpeg", "-hide_banner", "-nostats", "-i", str(probe),
         "-af", "ebur128=peak=true", "-f", "null", "-"],
        capture_output=True, text=True, check=False)
    probe.unlink(missing_ok=True)
    integrated = None
    for line in result.stderr.splitlines():
        if "I:" in line and "LUFS" in line:
            try:
                integrated = float(line.split("I:")[1].split("LUFS")[0])
            except ValueError:
                continue
    if integrated is None:
        return 1.0
    gain = 10.0 ** ((TARGET_LUFS - integrated) / 20.0)
    peak = float(np.max(np.abs(buffer))) * gain
    ceiling = 10.0 ** (TARGET_TP / 20.0)
    return gain * min(1.0, ceiling / peak) if peak > ceiling else gain


def write_clip(name: str, folder: str, filename: str, note: str) -> dict:
    path = track(folder, filename)
    credit = track_credit(folder, filename)
    mono = load(path)
    bpm = AM.tempo(mono)
    body, bars = trim_to_bars(mono, bpm, MAX_BARS[name])
    body = seamless(body, bpm)
    body = body * loudness_gain(path, body)
    out = OUT / f"{name}_mix.ogg"
    dsp.write_ogg(out, body)
    entry = {"clip": name, "file": out.name, "bpm": bpm, "bar_beats": 4, "beat_count": bars * 4,
             "bars": bars, "seconds": round(body.size / SR, 2), "source": f"{folder}/{filename}",
             "title": credit["title"], "page": credit["page"], "licence": credit["licence"],
             "author": credit["author"], "note": note}
    print(f"  {out.name:28s} {entry['seconds']:6.1f}s  {bpm:5.1f} BPM  {bars:3d} bars  {note}")
    return entry


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    entries = [write_clip(name, folder, filename, note)
               for name, (folder, filename, note) in CLIPS.items()]
    manifest = OUT / "clips.json"
    manifest.write_text(json.dumps(entries, indent=2) + "\n")
    print(f"{len(entries)} clips -> {manifest.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
