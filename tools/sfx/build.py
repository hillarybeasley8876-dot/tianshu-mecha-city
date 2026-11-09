#!/usr/bin/env python3
"""Render the whole sound bank to game/audio/sfx/ and write game/audio/audio_manifest.csv.

    tools/sfx/run.sh build.py [--only=id,id] [--manifest-only]

Deterministic: every sound is seeded from its own id hash, so re-running reproduces the bank.
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
import time
import zlib
from pathlib import Path

import numpy as np

import dsp
import music_tracks
import sources as src_mod
from registry import REGISTRY, SOURCES

ROOT = Path(__file__).resolve().parents[2]
SFX_DIR = ROOT / "game" / "audio" / "sfx"
MANIFEST = ROOT / "game" / "audio" / "audio_manifest.csv"
BANKS = ["bank_hero", "bank_weapons", "bank_melee", "bank_skills", "bank_enemies", "bank_world"]
# Manifest licence string for a sourced CC0 track; the record itself only says "CC0".
TRACK_LICENCE = "CC0-1.0"


def load_banks() -> None:
    """Import every bank module so its sound() calls fill the registry."""
    for name in BANKS:
        __import__(name)


def base_seed(sound_id: str) -> int:
    return zlib.crc32(sound_id.encode()) & 0xFFFF


def render(row, seed: int) -> np.ndarray:
    """Render one variant and record which recorded packs it actually pulled from.

    The per-row pack set is what makes the manifest honest: a file that layers a CC-BY recording
    must say so even though its base source is synthesis.
    """
    src_mod.reset()
    buffer = row.render(seed)
    if buffer.ndim != 1:
        raise ValueError(f"{row.sound_id}: render must return mono, got {buffer.shape}")
    row.packs.update(src_mod.CURRENT)
    row.rendered = True
    return dsp.finalize(buffer, row.peak_db, 0.01 if row.loop else 0.02)


def discover_packs(row) -> None:
    """Learn a row's pack set by rendering it, without writing a file.

    `--manifest-only` and `--only=<id>` render nothing (or one id), but both rewrite every row — so
    without this the packs column would be emptied for every id they did not render. Rendering
    here is what makes every mode write exactly what a full build writes.
    """
    if row.rendered:
        return
    for variant in range(row.variants):
        src_mod.reset()
        row.render(base_seed(row.sound_id) + variant * 977)
        row.packs.update(src_mod.CURRENT)
    row.rendered = True


def write_row(row, seed: int, variant: int) -> tuple[str, float]:
    buffer = render(row, seed)
    ext = "ogg" if row.ogg else "wav"
    name = f"{row.sound_id}.{ext}" if row.variants == 1 else f"{row.sound_id}_{variant + 1:02d}.{ext}"
    path = SFX_DIR / name
    if row.ogg:
        dsp.write_ogg(path, buffer)
    else:
        loop = (0.0, (buffer.size - 8) / dsp.SR) if row.loop else None
        dsp.write_wav(path, buffer, loop)
    return name, buffer.size / dsp.SR


def music_and_voice_rows() -> list[dict]:
    """Rows for the files that are not part of the SFX bank: music clips, stingers, AI voice.

    The adaptive clips are sourced CC0 tracks (tools/sfx/music_tracks.py). Each clip row names the
    track it came from and that track's own OGA page, both read from the fetch record, so a row can
    be joined to exactly one row of the CREDITS_AUDIO.md music table.
    """
    rows: list[dict] = []
    synth = SOURCES["SYNTH"]
    mmx = SOURCES["MMX"]
    music_dir = ROOT / "game" / "audio" / "music"
    clip_credit: dict[str, dict] = {}
    clips_json = music_dir / "clips.json"
    if clips_json.is_file():
        for entry in json.loads(clips_json.read_text()):
            folder, filename = str(entry["source"]).split("/", 1)
            clip_credit[str(entry["file"])] = {"folder": folder, "file": filename,
                                               "note": str(entry.get("note", ""))}
    for path in sorted(music_dir.glob("*.ogg")) + sorted((music_dir / "stingers").glob("*.ogg")):
        rel = path.relative_to(ROOT / "game")
        credit = clip_credit.get(path.name)
        if credit is not None:
            rec = music_tracks.track_credit(credit["folder"], credit["file"])
            source, url, licence, author = rec["title"], rec["page"], TRACK_LICENCE, rec["author"]
            layers = f"music clip — {credit['note']}"
        else:
            source, url, licence, author = synth
            layers = "music cue (synthesised stinger / silent beat clock)"
        rows.append({"id": path.stem, "file": str(rel), "source": source, "source_url": url,
                     "licence": licence, "author": author,
                     "layers_used": layers, "modified": "Y"})
    voice_dir = ROOT / "game" / "audio" / "voice"
    for path in sorted(voice_dir.glob("*.ogg")):
        rel = path.relative_to(ROOT / "game")
        rows.append({"id": path.stem, "file": str(rel), "source": mmx[0], "source_url": mmx[1],
                     "licence": mmx[2], "author": mmx[3],
                     "layers_used": "voice (radio EQ + ring mod + hiss)", "modified": "Y"})
    return rows


def manifest_rows() -> list[dict]:
    rows = []
    for sound_id in sorted(REGISTRY):
        row = REGISTRY[sound_id]
        discover_packs(row)
        label, url, licence, author = row.credits()
        for name in row.files:
            rows.append({
                "id": sound_id, "file": f"audio/sfx/{name}", "source": label,
                "source_url": url, "licence": licence, "author": author,
                "layers_used": row.layers, "modified": row.modified,
            })
    rows.extend(music_and_voice_rows())
    return rows


def write_manifest() -> None:
    rows = manifest_rows()
    with MANIFEST.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)
    print(f"manifest: {len(rows)} files -> {MANIFEST.relative_to(ROOT)}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", default="")
    parser.add_argument("--manifest-only", action="store_true")
    args = parser.parse_args()
    load_banks()
    if args.manifest_only:
        write_manifest()
        return 0
    wanted = {s for s in args.only.split(",") if s}
    SFX_DIR.mkdir(parents=True, exist_ok=True)
    total_files = 0
    started = time.time()
    for sound_id in sorted(REGISTRY):
        if wanted and sound_id not in wanted:
            continue
        row = REGISTRY[sound_id]
        seed = base_seed(sound_id)
        for variant in range(row.variants):
            name, seconds = write_row(row, seed + variant * 977, variant)
            total_files += 1
            print(f"  {name:34s} {seconds:5.2f}s  {row.layers}")
    print(f"rendered {total_files} files in {time.time() - started:.1f}s "
          f"from {len(REGISTRY)} ids")
    write_manifest()
    return 0


if __name__ == "__main__":
    sys.exit(main())
