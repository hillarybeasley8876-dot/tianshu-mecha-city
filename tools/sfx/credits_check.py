#!/usr/bin/env python3
"""Prove the audio credits name exactly what ships — file by file, in both directions.

    tools/sfx/run.sh credits_check.py

Four facts have to agree: the audio files under `game/`, `game/audio/audio_manifest.csv`,
`game/audio/CREDITS_AUDIO.md` and the pack/music tables in `status/audio.md`. This script joins
them and exits non-zero on any disagreement:

  * a shipped file with no manifest row, or a manifest row whose file is gone
  * a manifest source with no CREDITS row, or a CREDITS row with a different licence
  * a CREDITS row (or a status table row) that no shipped file names
  * a `sources.PACKS` entry nothing uses
  * a shipped third-party source with no licence record on disk, or one credited to somebody its
    record does not name

Licence records are the sidecars `tools/sfx/oga_fetch.py` writes into `art/audio_src/<pack>/`
(joined by the source URL) plus an archive's own `License*.txt`. Without `art/audio_src/` — a
clean checkout — the record section says so and fails; it never crashes.
"""

from __future__ import annotations

import ast
import csv
import json
import re
import sys
from pathlib import Path

from credits_records import (SRC_ROOT, author_named, is_third_party, load_records,
                             norm_licence, record_for)

ROOT = Path(__file__).resolve().parents[2]
GAME = ROOT / "game"
MANIFEST = GAME / "audio" / "audio_manifest.csv"
CREDITS = GAME / "audio" / "CREDITS_AUDIO.md"
STATUS = ROOT / "status" / "audio.md"
SOURCES_PY = Path(__file__).resolve().parent / "sources.py"
AUDIO_EXT = {".wav", ".ogg", ".mp3", ".flac"}

Problems = list[str]


def export_excludes() -> list[str]:
    """The globs `game/export_presets.cfg` keeps out of the shipped .app."""
    conf = GAME / "export_presets.cfg"
    if not conf.is_file():
        return []
    for line in conf.read_text().splitlines():
        if line.startswith("exclude_filter="):
            return [p.strip() for p in line.split("=", 1)[1].strip('"').split(",") if p.strip()]
    return []


def shipped_files() -> list[str]:
    """Every audio file the export would carry, as a path relative to `game/`."""
    globs = export_excludes()
    out = []
    for path in sorted(GAME.rglob("*")):
        if path.suffix.lower() not in AUDIO_EXT or ".godot" in path.parts:
            continue
        rel = path.relative_to(GAME).as_posix()
        if any(Path(rel).match(g) or g.strip("*/") in rel for g in globs):
            continue
        out.append(rel)
    return out


def read_manifest() -> list[dict[str, str]]:
    with MANIFEST.open(newline="") as handle:
        return list(csv.DictReader(handle))


def read_packs() -> dict[str, dict[str, str]]:
    """`sources.PACKS` without importing it — this script must run with no third-party deps."""
    tree = ast.parse(SOURCES_PY.read_text())
    packs: dict[str, dict[str, str]] = {}
    for node in ast.walk(tree):
        if not (isinstance(node, ast.Call) and getattr(node.func, "id", "") == "Pack"):
            continue
        fields = [a.value for a in node.args if isinstance(a, ast.Constant)]
        if len(fields) >= 6:
            packs[str(fields[0])] = {"folder": str(fields[1]), "title": str(fields[2]),
                                     "licence": str(fields[3]), "author": str(fields[4]),
                                     "url": str(fields[5])}
    return packs


def table_rows(text: str, header_cell: str) -> list[list[str]]:
    """Every body row of the first markdown table whose header starts with `header_cell`."""
    rows: list[list[str]] = []
    inside = False
    for line in text.splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")] if "|" in line else []
        if not inside:
            inside = bool(cells) and cells[0].lower() == header_cell.lower()
            continue
        if not cells or set("".join(cells)) <= set("-: "):
            if rows:
                break
            continue
        rows.append(cells)
    return rows


def link_text(cell: str) -> tuple[str, str]:
    """`[Name](url)` -> ("Name", "url"); a plain cell -> (cell, "").

    The match is greedy so a link label may itself contain brackets — the boss track's OGA title is
    "Boss Battle #2 [Symphonic Metal]".
    """
    m = re.match(r"\[(.+)\]\(([^)]+)\)\s*$", cell.strip())
    return (m.group(1), m.group(2)) if m else (cell.strip().strip("`"), "")


def read_credits() -> tuple[dict[str, dict], dict[str, dict], Problems]:
    """CREDITS_AUDIO.md -> (pack rows by name, music rows by track URL, problems)."""
    text = CREDITS.read_text()
    packs: dict[str, dict] = {}
    for cells in table_rows(text, "Pack"):
        if len(cells) < 3:
            continue
        name, url = link_text(cells[0])
        packs[name] = {"url": url, "author": cells[1], "licence": cells[2], "used_for": cells[3]
                       if len(cells) > 3 else ""}
    music: dict[str, dict] = {}
    for cells in table_rows(text, "Clip"):
        if len(cells) < 4:
            continue
        title, url = link_text(cells[1])
        music[url] = {"clip": cells[0].strip("`"), "title": title, "author": cells[2],
                      "licence": cells[3]}
    problems: Problems = []
    if not packs:
        problems.append("CREDITS_AUDIO.md: no `| Pack |` table found")
    if not music:
        problems.append("CREDITS_AUDIO.md: no `| Clip |` music table found")
    return packs, music, problems


def read_status() -> tuple[list[str], list[str]]:
    """The pack names and music track titles `status/audio.md` still claims."""
    if not STATUS.is_file():
        return [], []
    text = STATUS.read_text()
    packs = [link_text(c[0])[0] for c in table_rows(text, "Pack") if c]
    tracks = [link_text(c[1])[0] for c in table_rows(text, "Clip") if len(c) > 1]
    return packs, tracks


def read_own_sources() -> set[str]:
    """The `registry.SOURCES` labels that mean "our own work", so they need no licence record."""
    tree = ast.parse((Path(__file__).resolve().parent / "registry.py").read_text())
    titles: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign) and getattr(node.targets[0], "id", "") == "SOURCES":
            for value in node.value.values:
                if isinstance(value, ast.Tuple) and value.elts:
                    titles.add(str(value.elts[0].value))
    return titles


def split_cell(cell: str) -> list[str]:
    return [p.strip() for p in cell.split(" + ") if p.strip()]


def check_used_for(name: str, cell: str, ids: set[str], problems: Problems, stats: dict) -> None:
    """A CREDITS "Used for" cell must state the real id count and name only ids that layer the pack.

    This is what keeps the prose honest: `tools/sfx/run.sh credits_check.py` is the only place the
    id → pack mapping is computed, so the cell has to agree with it rather than with memory.
    """
    m = re.match(r"(\d+)\s+ids", cell)
    if not m:
        problems.append(f"used_for: CREDITS row “{name}” does not start with its id count")
        stats["used_for"] += 1
    elif int(m.group(1)) != len(ids):
        problems.append(f"used_for: CREDITS row “{name}” claims {m.group(1)} ids, "
                        f"{len(ids)} layer it")
        stats["used_for"] += 1
    for token in re.findall(r"`([^`]+)`", cell):
        if token not in ids:
            problems.append(f"used_for: CREDITS row “{name}” names `{token}`, "
                            f"which does not layer it")
            stats["used_for"] += 1


def check() -> dict:
    problems: Problems = []
    stats = {"files": 0, "rows": 0, "sources": 0, "no_record": 0, "bad_author": 0,
             "file_to_credit": 0, "credit_to_file": 0, "unused_pack": 0, "used_for": 0}
    files = shipped_files()
    stats["files"] = len(files)
    on_disk = set(files)
    rows = read_manifest()
    stats["rows"] = len(rows)
    packs = read_packs()
    own = read_own_sources()
    credit_packs, credit_music, credit_problems = read_credits()
    problems.extend(credit_problems)
    status_packs, status_tracks = read_status()
    by_url, by_folder, notes = load_records()
    problems.extend(notes)
    have_records = SRC_ROOT.is_dir()

    by_title = {p["title"]: p for p in packs.values()}
    music_by_title = {m["title"]: m for m in credit_music.values()}
    row_for_file: dict[str, list[dict]] = {}
    for row in rows:
        row_for_file.setdefault(row["file"], []).append(row)

    # --- every shipped file has a manifest row, and every row has a file -------------------
    for rel in files:
        if rel not in row_for_file:
            problems.append(f"file→credit: {rel} ships with no manifest row")
            stats["file_to_credit"] += 1
    for row in rows:
        if row["file"] not in on_disk:
            problems.append(f"credit→file: manifest row {row['id']} names missing {row['file']}")
            stats["credit_to_file"] += 1

    # --- every source the manifest names is credited, licensed and recorded ---------------
    used: dict[str, dict] = {}
    for row in rows:
        if row["file"] not in on_disk:
            continue
        for title in split_cell(row["source"]):
            entry = used.setdefault(title, {"files": [], "ids": set(), "url": "", "licence": "",
                                            "author": "", "folder": ""})
            entry["files"].append(row["file"])
            entry["ids"].add(row["id"])
    stats["sources"] = len(used)
    for title, entry in sorted(used.items()):
        pack = by_title.get(title)
        music = music_by_title.get(title)
        if title in own:
            entry.update(url="", licence="ours", author="", folder="")
            continue
        if pack is None and music is None:
            problems.append(f"file→credit: source “{title}” has no CREDITS_AUDIO.md row "
                            f"({len(entry['files'])} files)")
            stats["file_to_credit"] += 1
            continue
        want_url = pack["url"] if pack else next(
            u for u, m in credit_music.items() if m["title"] == title)
        want_lic = pack["licence"] if pack else music["licence"]
        want_author = pack["author"] if pack else music["author"]
        entry.update(url=want_url, licence=want_lic, author=want_author,
                     folder=pack["folder"] if pack else "")
        for row in (row_for_file[f][0] for f in entry["files"]):
            if want_url not in split_cell(row["source_url"]):
                problems.append(f"file→credit: {row['file']} source “{title}” "
                                f"does not carry its page {want_url}")
                stats["file_to_credit"] += 1
            if norm_licence(want_lic) not in [norm_licence(c) for c in split_cell(row["licence"])]:
                problems.append(f"file→credit: {row['file']} source “{title}” licence "
                                f"{row['licence']} != {want_lic}")
                stats["file_to_credit"] += 1
            if want_author.lower() not in row["author"].lower():
                problems.append(f"file→credit: {row['file']} source “{title}” author "
                                f"{row['author']} does not name {want_author}")
                stats["file_to_credit"] += 1
            break
        if not is_third_party(want_lic):
            continue
        rec = record_for(want_url, entry["folder"], by_url, by_folder) if have_records else None
        if rec is None:
            problems.append(f"no_record: “{title}” ({len(entry['files'])} shipped files) has no "
                            f"licence record for {want_url}")
            stats["no_record"] += 1
            continue
        entry["record"] = rec
        licences = [norm_licence(x) for x in rec.get("licences", [])]
        if not any(x.startswith("CC0") for x in licences):
            problems.append(f"no_record: “{title}” record {rec['path']} says {rec.get('licences')}, "
                            f"not CC0")
            stats["no_record"] += 1
        # The manifest's author cell holds every pack's author at once; only the *expected*
        # author of this source is checked against the record (the cell is checked above).
        credit_author = credit_packs[title]["author"] if title in credit_packs else want_author
        for who in {credit_author, want_author}:
            if not author_named(who, rec):
                problems.append(f"bad_author: “{title}” credited to “{who}”, which "
                                f"{rec['path']} does not name")
                stats["bad_author"] += 1

    # --- nothing is credited that no shipped file names -----------------------------------
    for name in sorted(credit_packs):
        if name not in used:
            problems.append(f"credit→file: CREDITS row “{name}” is named by no shipped file")
            stats["credit_to_file"] += 1
        else:
            check_used_for(name, credit_packs[name]["used_for"], used[name]["ids"],
                           problems, stats)
    for url, music in sorted(credit_music.items()):
        if music["title"] not in used:
            problems.append(f"credit→file: CREDITS music row “{music['title']}” "
                            f"({url}) is named by no shipped file")
            stats["credit_to_file"] += 1
    for name in status_packs:
        if name not in used:
            problems.append(f"credit→file: status/audio.md pack row “{name}” "
                            f"is named by no shipped file")
            stats["credit_to_file"] += 1
    for name in status_tracks:
        if name not in used:
            problems.append(f"credit→file: status/audio.md music row “{name}” "
                            f"is named by no shipped file")
            stats["credit_to_file"] += 1
    for key, pack in sorted(packs.items()):
        if pack["title"] not in used:
            problems.append(f"unused_pack: sources.PACKS “{key}” ({pack['title']}) "
                            f"is layered by no shipped file")
            stats["unused_pack"] += 1
    return {"problems": problems, "stats": stats, "used": used, "rows": rows,
            "row_for_file": row_for_file, "credit_packs": credit_packs,
            "credit_music": credit_music, "files": files}


def report(result: dict) -> None:
    """Print the per-file and per-source listings the summary line summarises."""
    used, rows = result["used"], result["rows"]
    row_for_file, credit_music = result["row_for_file"], result["credit_music"]
    music_titles = {m["title"] for m in credit_music.values()}
    print("## shipped files")
    for rel in result["files"]:
        entries = row_for_file.get(rel, [])
        titles = sorted({t for e in entries for t in split_cell(e["source"])})
        licences = sorted({c for e in entries for c in split_cell(e["licence"])})
        credited = [t for t in titles if t in credit_music or t in result["credit_packs"]]
        print(f"{rel}  ->  {'; '.join(titles) or '(none)'}  ->  "
              f"{'; '.join(credited) or '(own work)'}  ->  {'; '.join(licences) or '(none)'}")
    print("\n## credited sources")
    for title, entry in sorted(used.items()):
        if title in read_own_sources():
            continue
        rec = entry.get("record")
        kind = "track" if title in music_titles else "pack"
        where = (f"record {rec['path']} says {'/'.join(rec.get('licences', [])) or '?'} by "
                 f"{rec.get('author') or '?'}" if rec else "NO RECORD")
        print(f"{kind} {title} — {len(entry['files'])} files, {len(entry['ids'])} ids "
              f"({', '.join(sorted(entry['ids']))}) — {where}")


def main() -> int:
    result = check()
    report(result)
    problems, stats = result["problems"], result["stats"]
    print("\n## problems" if problems else "\n## problems: none")
    for line in problems:
        print(f"  {line}")
    print(f"files={stats['files']} rows={stats['rows']} sources={stats['sources']} "
          f"unmatched file→credit={stats['file_to_credit']} "
          f"credit→file={stats['credit_to_file']} no_record={stats['no_record']} "
          f"bad_author={stats['bad_author']} unused_pack={stats['unused_pack']} "
          f"used_for={stats['used_for']}")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
