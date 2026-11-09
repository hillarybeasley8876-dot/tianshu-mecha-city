#!/usr/bin/env python3
"""Licence records on disk: the evidence that a shipped pack or track is CC0 and who made it.

`tools/sfx/oga_fetch.py` writes an `oga_sources.json` sidecar next to each downloaded pack, holding
what the OpenGameArt node itself states — its licence, its author field, who submitted it and its
Attribution Instructions. An archive that is not on OGA carries its own `License*.txt` instead
(Kenney — Sci-Fi Sounds). This module reads both and joins them to a manifest source, by the page
URL first (so a pack unpacked under a different folder name still joins) and by folder second.

Used only by `tools/sfx/credits_check.py`.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC_ROOT = ROOT / "art" / "audio_src"


def norm_licence(text: str) -> str:
    """`CC0 1.0`, `CC0-1.0` and `CC0` all normalise to a comparable token."""
    return re.sub(r"[^A-Za-z0-9]", "", text).upper()


def is_third_party(licence: str) -> bool:
    """True for a licence cell that names a downloaded pack rather than our own work."""
    return norm_licence(licence).startswith(("CC0", "CCBY"))


def strip_parens(text: str) -> str:
    return re.sub(r"\([^)]*\)", " ", text)


def rel(path: Path) -> str:
    """Repo-relative when possible; an absolute path when the tree root is not an ancestor."""
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def _sidecar_record(path: Path, entry: dict) -> dict:
    return {"path": rel(path), "licences": entry.get("licences", []),
            "author": str(entry.get("author", "")), "submitted_by": str(entry.get("submitted_by", "")),
            "attribution": str(entry.get("attribution", "")), "title": str(entry.get("title", "")),
            "recorded": str(entry.get("recorded", ""))}


def load_records() -> tuple[dict[str, dict], dict[str, dict], list[str]]:
    """(by source URL, by pack folder, notes about what could not be read)."""
    by_url: dict[str, dict] = {}
    by_folder: dict[str, dict] = {}
    notes: list[str] = []
    if not SRC_ROOT.is_dir():
        return by_url, by_folder, [f"no {rel(SRC_ROOT)}/ — licence records unchecked"]
    for folder in sorted(p for p in SRC_ROOT.iterdir() if p.is_dir()):
        sidecar = folder / "oga_sources.json"
        if sidecar.is_file():
            try:
                entries = json.loads(sidecar.read_text())
            except json.JSONDecodeError as exc:
                notes.append(f"{rel(sidecar)}: unreadable ({exc})")
                continue
            by_folder[folder.name] = {"path": rel(sidecar), "entries": entries}
            for entry in entries:
                by_url[str(entry.get("page", ""))] = _sidecar_record(sidecar, entry)
            continue
        licences = sorted(folder.glob("License*.txt")) + sorted(folder.glob("LICENCE*.txt"))
        if licences:
            path = licences[0]
            text = path.read_text(errors="replace")
            names = re.findall(r"(?:Created/distributed by|Author)\s*:?\s*([^\n(]+)", text)
            by_folder[folder.name] = {"path": rel(path), "entries": [{
                "licences": ["CC0"] if "CC0" in text or "Creative Commons Zero" in text
                             else re.findall(r"License:\s*\(?([^)\n]+)", text),
                "author": names[0].strip() if names else "", "submitted_by": "",
                "attribution": "", "title": folder.name, "recorded": ""}]}
    return by_url, by_folder, notes


def record_for(url: str, folder: str, by_url: dict[str, dict],
               by_folder: dict[str, dict]) -> dict | None:
    """The record proving a source's licence: by page URL first, then by pack folder."""
    if url in by_url:
        return by_url[url]
    entry = by_folder.get(folder)
    if entry and len(entry["entries"]) == 1:
        rec = dict(entry["entries"][0])
        rec["path"] = entry["path"]
        return rec
    return None


def record_text(rec: dict) -> str:
    """Everything the record states about the work, for the author cross-check."""
    return " ".join([str(rec.get("author", "")), str(rec.get("submitted_by", "")),
                     str(rec.get("attribution", "")), str(rec.get("title", ""))]).lower()


def creator_text(rec: dict) -> str:
    """What the record states about who *made* the work — deliberately excluding the submitter.

    An OGA node names both its author and the account that uploaded it, and on a page whose author
    is plain text (The Free Firearm Sound Library) the uploader is the only linked name. Crediting
    the uploader is the exact mistake this split exists to catch.
    """
    return " ".join([str(rec.get("author", "")), str(rec.get("attribution", "")),
                     str(rec.get("title", ""))]).lower()


def author_named(credit: str, record: dict) -> bool:
    """A credit must name only people the record names, and at least one who made the work."""
    text, creators = record_text(record), creator_text(record)
    names = [n.strip() for n in strip_parens(credit).split(",") if n.strip()]
    return bool(names) and all(n.lower() in text for n in names) and any(
        n.lower() in creators for n in names)
