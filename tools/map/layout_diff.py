#!/usr/bin/env python3
"""layout_diff.py - what one build changed against another, per top-level key (lead, r8 item 5).

`build_layout.py` threads one `random.Random` through every stage, so a change that draws a
number re-rolls everything after it. r8's rule is that every 3D fix is a cut or a filter that
draws nothing, and this is the proof: it prints, per key, the ids ADDED, REMOVED and CHANGED,
with the fields that changed, so "nothing else moved" is a statement that can be checked.

Two keys are matched by content rather than by id, because their ids are positional:

* `arenas[].cover` - `<arena>#<index>` renumbers whenever a piece is inserted, so pieces are
  matched on (centre, size, soft) rounded to a metre;
* `hives` - matched on position, because a spire may move.

Usage: uv run --with numpy --with shapely --with networkx python3 tools/map/layout_diff.py <old> <new>
"""
from __future__ import annotations

import json
import math
import sys

KEYS = ("streets", "viaducts", "rails", "tunnels", "decks", "buildings", "connectors",
        "landmarks", "anchors", "skyline", "sky_waypoints")
ARENAS = ("cover", "spawn_sockets")
ROUND = 1.0


def load(path: str) -> dict:
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def _round(value):
    if isinstance(value, float):
        return round(value / ROUND) * ROUND
    if isinstance(value, list):
        return [_round(v) for v in value]
    if isinstance(value, dict):
        return {k: _round(v) for k, v in value.items()}
    return value


def _fields(a: dict, b: dict) -> list[str]:
    """The field names that differ between two records, ignoring key order."""
    out = []
    for key in sorted(set(a) | set(b)):
        if _round(a.get(key)) != _round(b.get(key)):
            out.append(key)
    return out


def by_id(rows: list[dict]) -> dict[str, dict]:
    return {r["id"]: r for r in rows if "id" in r}


def diff_list(old: list[dict], new: list[dict], label: str) -> dict:
    a, b = by_id(old), by_id(new)
    added = sorted(set(b) - set(a))
    removed = sorted(set(a) - set(b))
    changed = {k: _fields(a[k], b[k]) for k in sorted(set(a) & set(b)) if _fields(a[k], b[k])}
    return {"key": label, "added": added, "removed": removed, "changed": changed,
            "total": len(b)}


def diff_cover(old: list[dict], new: list[dict]) -> dict:
    """Cover matched per arena by content: its ids are positional (`<arena>#<index>`)."""
    out: dict[str, dict] = {}
    old_by = {a["id"]: a.get("cover", []) for a in old}
    for arena in new:
        aid = arena["id"]
        key = lambda p: (tuple(_round(p["center"])), tuple(_round(p["size"])), p.get("soft"),
                         p.get("kind"))
        before = {key(p) for p in old_by.get(aid, [])}
        after = {key(p) for p in arena.get("cover", [])}
        out[aid] = {"added": len(after - before), "removed": len(before - after),
                    "kept": len(after & before), "total": len(after),
                    "was": len(old_by.get(aid, []))}
    return out


def diff_hives(old: list[dict], new: list[dict]) -> list[str]:
    a = {h["id"]: h["pos"] for h in old}
    rows = []
    for hive in new:
        was = a.get(hive["id"])
        now = hive["pos"]
        if was is None:
            rows.append(f"{hive['id']} ADDED at {now}")
        elif [round(v, 1) for v in was] != [round(v, 1) for v in now]:
            rows.append(f"{hive['id']} moved {math.dist(was, now):.0f} m: {was} -> {now}")
        else:
            rows.append(f"{hive['id']} unchanged at {now}")
    for hid in sorted(set(a) - {h["id"] for h in new}):
        rows.append(f"{hid} REMOVED")
    return rows


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    old, new = load(sys.argv[1]), load(sys.argv[2])
    print(f"layout_diff  {sys.argv[1]}  ->  {sys.argv[2]}")
    print(f"  meta.revision {old['meta'].get('revision')} -> {new['meta'].get('revision')}")
    moved = 0
    for key in KEYS:
        row = diff_list(old.get(key, []), new.get(key, []), key)
        n = len(row["added"]) + len(row["removed"]) + len(row["changed"])
        moved += n
        flag = "" if not n else "   <-- changed"
        print(f"\n{key:14s} {row['total']:5d} rows{flag}")
        if row["added"]:
            print(f"   added   {len(row['added']):4d}  {row['added'][:8]}")
        if row["removed"]:
            print(f"   removed {len(row['removed']):4d}  {row['removed'][:8]}")
        for ident, fields in list(row["changed"].items())[:12]:
            print(f"   changed        {ident}: {fields}")
        if len(row["changed"]) > 12:
            print(f"   ... and {len(row['changed']) - 12} more changed")
    print("\narenas")
    for aid, row in sorted(diff_cover(old.get("arenas", []), new.get("arenas", [])).items()):
        print(f"   {aid} cover {row['was']:4d} -> {row['total']:4d}  "
              f"(+{row['added']} new centres, -{row['removed']} gone, {row['kept']} kept)")
    for arena in new.get("arenas", []):
        was = next((a for a in old.get("arenas", []) if a["id"] == arena["id"]), {})
        if len(arena.get("spawn_sockets", [])) != len(was.get("spawn_sockets", [])):
            print(f"   {arena['id']} sockets {len(was.get('spawn_sockets', []))} -> "
                  f"{len(arena['spawn_sockets'])}")
    print("\nhives")
    for row in diff_hives(old.get("hives", []), new.get("hives", [])):
        print(f"   {row}")
    print(f"\n{moved} id-level changes across {len(KEYS)} keyed lists")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
