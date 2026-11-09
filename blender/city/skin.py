"""Kit skin mode: which blockout structures city-kit covers with Tripo architecture.

`data/map/kit_assign.json` (city-kit owns it) maps a layout structure to a kit model fitted over
the blockout box. Every structure it covers keeps its collision and occluders but emits NO render
mesh, so the player sees the kit model instead of the procedural box
(briefs/city-kit.md step 7, reviews/city-build-lead.md 12:10).

`build_city.py --blockout` ignores the file and emits everything, which is what the geometry
checks and the blockout captures want.

The file is written by another unit and may be absent, half-written or shaped differently from
what we expect while that unit iterates, so parsing is deliberately tolerant: a row we cannot
read is reported and skipped, never silently treated as "skinned" or "not skinned".
"""
import json
import os
import re

from lib import common

ASSIGN_PATH = os.path.join(common.ROOT, "data", "map", "kit_assign.json")
_TILE_RE = re.compile(r"^t-?\d+_-?\d+$")

# Keys the assignment rows have been seen/written with, most specific first.
_ID_KEYS = ("building", "target_id", "structure", "target", "id")
_KIND_KEYS = ("kind", "target_kind", "type")
_ROW_KEYS = ("assign", "assignments", "entries", "rows", "buildings", "pieces", "cover",
             "far_lod", "ring", "skin", "placed")
# Row kinds, mapped onto what this build can actually mute.
_KIND_ALIASES = {
    "building": "building", "tower": "building", "block": "building",
    "deck_edge": "deck", "parapet": "deck", "railing": "deck",
    "deck": "deck_full", "platform": "deck_full", "deck_full": "deck_full",
    "skybridge": "deck_full", "skydeck": "deck_full",
    "viaduct_edge": "viaduct", "viaduct": "viaduct",
    "barrier": "viaduct", "pylon": "viaduct",
    # city-kit r2 item 1: a Tripo prop fitted over one arena cover box.
    "cover": "cover", "cover_piece": "cover", "prop_cover": "cover",
    # city-kit r2 item 2: their far LOD covers this whole 200 m tile, so my box proxy stands down.
    "far_lod": "far", "far": "far", "hlod": "far", "tile": "far", "far_tile": "far",
    # city-build r8 item 3: one box of the 96-box skyline ring is covered by a kit far model.
    "ring": "ring", "skyline": "ring", "skyline_ring": "ring",
}
_SET_OF = {"building": "buildings", "deck": "decks", "deck_full": "decks_full",
           "viaduct": "viaducts", "cover": "cover", "far": "far", "ring": "ring"}
# A far-LOD row only stands my proxy down once city-kit says its own far mesh passed the hole
# gate (reviews/city-build-r8.md item 4). Without the field the row is held, not honoured.
_GATE_PASS = {"pass", "passed", "ok", "true", "yes"}
# Kinds city-kit uses for ADDITIVE decoration (a model placed beside my geometry, not over it).
# They are readable and deliberate, so they are not "skipped" rows — they simply skin nothing.
_IGNORED_KINDS = {"roof", "street", "market", "pipe_rack", "prop", "detail", "sign", "decal"}
COVER_SEP = "#"   ## an arena cover piece is addressed as "<arena>#<index>", e.g. "A1#3"


class Skin:
    """Structure ids whose render mesh is suppressed.

    `buildings`  — the whole building (city-kit fits a tower/megablock/house over the box).
    `decks`      — the deck's parapet ring only; city-kit lays railings along the edge polyline.
    `decks_full` — the whole deck slab as well (a kit station/platform model covers it).
    `viaducts`   — the viaduct's barriers and pylons; the drivable deck slab always stays.
    `cover`      — one arena cover piece ("A1#3"): the box and its white cap stop rendering, the
                   collider and the breakable prop slot stay.
    `far`        — a 200 m tile id ("t-1_3") whose HLOD proxy stands down because city-kit's own
                   far LOD covers it. Nothing here is dropped from the export; `city.gd` reads the
                   list and hides the proxy. A row only lands here with `"gate": "pass"`; the rest
                   are counted in `far_held` and my proxy stays up.
    `ring`       — an index into `city_layout.json["skyline"]`: that far ring box is dropped from
                   `skyline.glb` because a kit far model stands there instead (r8 item 3).
    Collision and occluders are untouched in every case.
    """

    def __init__(self, active: bool = False, source: str = "") -> None:
        self.active = active
        self.source = source
        self.buildings: set = set()
        self.decks: set = set()
        self.decks_full: set = set()
        self.viaducts: set = set()
        self.cover: set = set()
        self.far: set = set()
        self.ring: set = set()
        self.far_held: int = 0
        self.probe: list = []
        self.skipped: int = 0

    def note(self, b) -> None:
        """Remember a skinned building's footprint for `skin_probe.gd`.

        The probe has to cover EVERY skinned building, including the ones whose roof a breach cut
        away — those have no rooftop prop slot to raycast at, and dropping them would leave
        exactly the two cases that failed in lead r7 unchecked.
        """
        if not self.building(b["id"]):
            return
        cx, cy = b["center"]
        w, d = b["size"]
        z0 = float(b["base_z"])
        self.probe.append({"id": b["id"], "centre": [float(cx), float(cy), z0 + float(b["height"])],
                           "base_z": z0, "size": [float(w), float(d)],
                           "yaw_deg": float(b["rot"])})

    def building(self, bid: str) -> bool:
        return self.active and bid in self.buildings

    def deck(self, did: str) -> bool:
        """True when the parapet render must go (an edge row or a whole-deck row)."""
        return self.active and (did in self.decks or did in self.decks_full)

    def deck_full(self, did: str) -> bool:
        return self.active and did in self.decks_full

    def viaduct(self, vid: str) -> bool:
        return self.active and vid in self.viaducts

    def cover_piece(self, arena: str, index: int) -> bool:
        return self.active and ("%s%s%d" % (arena, COVER_SEP, index)) in self.cover

    def far_tile(self, tile_id: str) -> bool:
        return self.active and tile_id in self.far

    def ring_box(self, index: int) -> bool:
        return self.active and index in self.ring

    def count(self) -> int:
        return (len(self.buildings) + len(self.decks) + len(self.decks_full)
                + len(self.viaducts) + len(self.cover) + len(self.far) + len(self.ring))

    def resolve(self, lay) -> None:
        """Sort the ids against the layout and report the ones that match nothing.

        A railing row may name a deck OR a viaduct, and an id that matches neither is a stale row
        (the layout moved under city-kit), so it must be reported rather than silently ignored —
        a silently ignored row leaves a procedural box where a kit model is standing.
        """
        if not self.active:
            return
        deck_ids = {d["id"] for d in lay.decks}
        via_ids = {v["id"] for v in lay.viaducts}
        for sid in sorted(self.decks):
            if sid in via_ids:
                self.viaducts.add(sid)
        self.decks -= self.viaducts
        known = {b["id"] for b in lay.buildings} | deck_ids | via_ids
        stale = sorted((self.buildings | self.decks | self.decks_full | self.viaducts) - known)
        for bucket in ("buildings", "decks", "decks_full", "viaducts"):
            getattr(self, bucket).difference_update(stale)
        stale += self._stale_cover(lay)
        stale += self._stale_ring(lay)
        self._check_far(lay)
        if stale:
            print("SKIN: %d assignment ids match nothing in the layout and were dropped: %s%s"
                  % (len(stale), ", ".join(stale[:6]), " ..." if len(stale) > 6 else ""))
        if self.far_held:
            print("SKIN: %d far-LOD rows held (no \"gate\": \"pass\"); those tiles keep their "
                  "HLOD proxy" % self.far_held)

    def _stale_ring(self, lay) -> list:
        """A ring row indexes `city_layout.json["skyline"]`, so an index past the end is stale."""
        n = len(lay.skyline)
        stale = sorted(i for i in self.ring if i < 0 or i >= n)
        self.ring -= set(stale)
        return ["skyline[%d]" % i for i in stale]

    def _stale_cover(self, lay) -> list:
        """A cover row is only good if that arena really has that many cover pieces."""
        sizes = {a["id"]: len(a.get("cover", [])) for a in lay.arenas}
        stale = []
        for cid in sorted(self.cover):
            arena, _, idx = cid.partition(COVER_SEP)
            if arena not in sizes or not idx.isdigit() or int(idx) >= sizes[arena]:
                stale.append(cid)
        self.cover -= set(stale)
        return stale

    def _check_far(self, lay) -> None:
        """Far-LOD rows name 200 m tiles, not structures, so they are checked for shape only:
        the tile set is only known once the geometry has been bucketed (after this)."""
        bad = sorted(t for t in self.far if not _TILE_RE.match(t))
        self.far -= set(bad)
        for t in bad:
            print("SKIN: far-LOD row %r is not a tile id (expected t<i>_<j>), dropped" % t)

    def to_json(self) -> dict:
        """What the Godot side needs: the placer only places models for structures that are
        actually skinned, and `city.gd --blockout` warns when the city was built skinned."""
        return {"active": self.active, "source": self.source,
                "buildings": sorted(self.buildings), "decks": sorted(self.decks),
                "decks_full": sorted(self.decks_full), "viaducts": sorted(self.viaducts),
                "cover": sorted(self.cover), "far_tiles": sorted(self.far),
                "far_tiles_held": self.far_held, "ring": sorted(self.ring),
                "probe": self.probe}


def load(blockout: bool = False, path: str = ASSIGN_PATH) -> Skin:
    if blockout:
        print("SKIN off (--blockout): every procedural render mesh is emitted")
        return Skin(False, "--blockout")
    if not os.path.isfile(path):
        print("SKIN off: %s does not exist yet (city-kit), nothing is skinned" % path)
        return Skin(False, "")
    try:
        with open(path) as fh:
            raw = json.load(fh)
    except (OSError, ValueError) as exc:
        print("SKIN off: %s is not readable JSON (%s); nothing is skinned" % (path, exc))
        return Skin(False, "")
    skin = Skin(True, os.path.relpath(path, common.ROOT))
    for row in _rows(raw):
        _add(skin, row)
    print("SKIN %s: %d buildings, %d deck edges, %d whole decks, %d viaducts, %d cover pieces, "
          "%d far-LOD tiles (%d held), %d ring boxes (%d rows skipped)"
          % (path, len(skin.buildings), len(skin.decks), len(skin.decks_full),
             len(skin.viaducts), len(skin.cover), len(skin.far), skin.far_held,
             len(skin.ring), skin.skipped))
    if skin.count() == 0:
        skin.active = False
    return skin


def _rows(raw) -> list:
    """Every assignment row in the file, whatever shape the file has."""
    if isinstance(raw, list):
        return raw
    if not isinstance(raw, dict):
        return []
    out = []
    for key in _ROW_KEYS:
        v = raw.get(key)
        if isinstance(v, list):
            out.extend(v)
        elif isinstance(v, dict):
            # {"D7_w000": {...}} — the id is the key.
            out.extend([dict(r, id=k) if isinstance(r, dict) else {"id": k, "kit": r}
                        for k, r in v.items()])
    return out or ([raw] if any(k in raw for k in _ID_KEYS) else [])


def _add(skin: Skin, row) -> None:
    if not isinstance(row, dict):
        skin.skipped += 1
        return
    if row.get("hide") is False or row.get("skinned") is False:
        return                                  # an explicit opt-out, not a skip
    kind_raw = next((str(row[k]) for k in _KIND_KEYS if isinstance(row.get(k), str)), "building")
    kind = _KIND_ALIASES.get(kind_raw.lower())
    if kind is None:
        if kind_raw.lower() not in _IGNORED_KINDS:
            skin.skipped += 1
        return
    if kind == "far" and not _gate_pass(row):
        skin.far_held += 1
        return
    if kind == "ring":
        index = _ring_id(row)
        if index is None:
            skin.skipped += 1
            return
        skin.ring.add(index)
        return
    sid = _row_id(row) if kind != "cover" else _cover_id(row)
    if not sid:
        skin.skipped += 1
        return
    getattr(skin, _SET_OF[kind]).add(sid)


def _gate_pass(row) -> bool:
    """A far-LOD row must carry its own hole-gate verdict (reviews/city-build-r8.md item 4).

    city-kit adds `"gate": "pass"` per model once their far mesh passes the gate; until then my
    HLOD proxy stays up rather than leaving a hole in the far band.
    """
    gate = row.get("gate", row.get("hole_gate", row.get("status")))
    if isinstance(gate, bool):
        return gate
    return isinstance(gate, str) and gate.strip().lower() in _GATE_PASS


def _ring_id(row):
    """A ring row indexes `city_layout.json["skyline"]`; `"id": "12"` is accepted too.

    Returns the int index, or None when the row names no index at all. Index 0 is a real row, so
    None (not falsiness) is the "unreadable" answer.
    """
    index = row.get("index", row.get("ring_index", row.get("i")))
    if isinstance(index, int) and not isinstance(index, bool):
        return index
    if isinstance(index, str) and index.strip().lstrip("-").isdigit():
        return int(index.strip())
    sid = _row_id(row)
    return int(sid) if sid.lstrip("-").isdigit() else None


def _row_id(row) -> str:
    return next((str(row[k]) for k in _ID_KEYS if isinstance(row.get(k), str)), "")


def _cover_id(row) -> str:
    """A cover row is addressed by `arena` + `index` (city-kit r2 item 1); `"id": "A1#3"` and
    the "A1:3" spelling are accepted too, because the file belongs to another unit."""
    arena = row.get("arena") or row.get("arena_id") or row.get("zone")
    index = row.get("index", row.get("cover_index", row.get("i")))
    if isinstance(arena, str) and arena and isinstance(index, int) and index >= 0:
        return "%s%s%d" % (arena, COVER_SEP, index)
    sid = _row_id(row).replace(":", COVER_SEP)
    return sid if COVER_SEP in sid else ""
