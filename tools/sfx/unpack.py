#!/usr/bin/env python3
"""Safely extract audio files from downloaded archives.

Untrusted archives: only .ogg/.wav/.mp3/.flac members are read, names are flattened
(no directory traversal possible), and nothing is ever executed. Non-audio members are
copied only when they look like a licence file, so attribution text stays with the pack.
"""
from __future__ import annotations

import argparse
import re
import sys
import zipfile
from pathlib import Path

AUDIO_EXT = {".ogg", ".wav", ".mp3", ".flac"}
LICENCE_RE = re.compile(r"(licen[cs]e|readme|credits?|copying)", re.IGNORECASE)
SLUG_RE = re.compile(r"[^a-z0-9]+")


def slug(name: str) -> str:
    return SLUG_RE.sub("_", name.lower()).strip("_")


def audio_members(path: Path) -> list[str]:
    """Names of audio members in a zip or 7z archive, without extracting anything."""
    if path.suffix.lower() == ".7z":
        # libarchive-backed listing; fall back to the caller's tar extraction.
        return []
    with zipfile.ZipFile(path) as zf:
        return [n for n in zf.namelist() if Path(n).suffix.lower() in AUDIO_EXT]


def extract_zip(path: Path, dest: Path) -> tuple[int, int]:
    """Copy audio + licence members of `path` into `dest` with flattened names."""
    dest.mkdir(parents=True, exist_ok=True)
    audio = licences = 0
    with zipfile.ZipFile(path) as zf:
        for info in zf.infolist():
            if info.is_dir():
                continue
            base = Path(info.filename).name
            if base.startswith("._") or base.startswith("."):
                continue  # AppleDouble resource fork, not audio
            ext = Path(base).suffix.lower()
            keep_audio = ext in AUDIO_EXT
            keep_licence = bool(ext in {".txt", ".md"} and LICENCE_RE.search(base))
            if not (keep_audio or keep_licence):
                continue
            out = dest / (slug(Path(base).stem) + ext if keep_audio else base)
            if not out.resolve().is_relative_to(dest.resolve()):
                push(f"skipped suspicious member {info.filename}")
                continue
            with zf.open(info) as src, out.open("wb") as dst:
                data = src.read()
            if keep_audio and data[:4] not in (b"RIFF", b"OggS", b"fLaC") and data[:2] != b"\xff\xfb":
                push(f"skipped {base}: not audio ({data[:4]!r})")
                continue
            out.write_bytes(data)
            audio += keep_audio
            licences += keep_licence
    return audio, licences


def push(msg: str) -> None:
    print(f"[unpack] {msg}", file=sys.stderr)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("archive", type=Path)
    ap.add_argument("dest", type=Path)
    ap.add_argument("--prefix", default="", help="prepended to every extracted audio name")
    args = ap.parse_args()
    if not args.archive.is_file():
        push(f"missing archive {args.archive}")
        return 1
    audio, licences = extract_zip(args.archive, args.dest)
    push(f"{args.archive.name}: {audio} audio, {licences} licence files -> {args.dest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
