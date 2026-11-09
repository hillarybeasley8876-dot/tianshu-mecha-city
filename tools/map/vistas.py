"""Vista cameras: keep the lead's framed views open, and report what each one hits first.

`data/vistas.json` is lead-owned (ART.md §8). Two jobs here:

1. `slots()` turns each camera->look ray into height caps the fill must respect, so no tower
   is ever parked in front of a camera. The slot is a narrow corridor along the ray; inside
   it a mass may not rise above the ray, which is what keeps V1's view of the Spire across
   the canal, V4's view of Block 9 up the canyon, and so on.
2. `first_hit()` / `check()` answer, per vista, what the camera actually hits first. The
   subject (Spire, Block 9, stacks, pagoda) must be the first major hit, or the framing must
   be a deliberate canyon - something tall flanking the ray rather than across it.
"""
from __future__ import annotations

import json
import math
import os
import sys

from shapely.geometry import LineString, Point, Polygon
from shapely.strtree import STRtree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import geom  # noqa: E402
import mapconst as C  # noqa: E402

VISTAS_JSON = os.path.join(C.ROOT, "data", "vistas.json")
SLOT_HALF = 36.0        # half width of the kept-clear view slot
SLOT_STEP = 26.0        # sampling along the ray
SLOT_MARGIN = 6.0       # how far below the ray a mass must stay
CANYON_FLANK = 120.0    # a first hit this far off the ray axis is framing, not blockage
CAMERA_KEEPOUT = 30.0   # m: the sphere round a camera nothing may stand in (lead, r7)
CAMERA_MARGIN = 2.0     # m: a mass within the sphere stays this far under the lens
CAMERA_FLOOR = 6.0      # m: a slab this thick right under the lens is the floor, not a blocker

# What each vista is for: the landmark that must be the first major thing in the frame.
SUBJECTS = {"V1": "spire", "V2": "spire", "V3": "spire", "V4": "block9", "V5": "stacks",
            "V6": "spire", "V7": "spire", "V8": None}

# Landmark volumes, as (footprint, base z, top z). The Spire is a tapering shaft; the
# stacks are four cylinders; the pagoda and Block 9 are prisms.
def landmark_boxes() -> list[tuple[Polygon, float, float, str]]:
    out: list[tuple[Polygon, float, float, str]] = []
    for step, (z0, z1, r) in enumerate(((0.0, 80.0, 70.0), (80.0, 160.0, 54.0),
                                        (160.0, 224.0, 44.0), (224.0, 360.0, 26.0))):
        out.append((geom.rect((0.0, 120.0), (r * 2, r * 2)), z0, z1, "spire"))
    out.append((geom.rect((330.0, 250.0), (130.0, 130.0)), 32.0, 232.0, "block9"))
    out.append((geom.rect((-520.0, 430.0), (64.0, 64.0)), 32.0, 128.0, "pagoda"))
    for x, y in ((540, -120), (600, -80), (650, -150), (580, -190)):
        out.append((Point(x, y).buffer(22.0), 0.0, 144.0, "stacks"))
    return out


def load() -> list[dict]:
    with open(VISTAS_JSON, encoding="utf-8") as fh:
        return json.load(fh)["vistas"]


def ray(vista: dict) -> tuple[tuple[float, float, float], tuple[float, float, float]]:
    pos = tuple(float(v) for v in vista["pos_blender"])
    look = tuple(float(v) for v in vista["look_blender"])
    return pos, look


def slots(vistas: list[dict], half: float = SLOT_HALF, step: float = SLOT_STEP,
          margin: float = SLOT_MARGIN) -> list[tuple[Polygon, float]]:
    """(footprint, highest top allowed inside it) along every vista ray."""
    caps: list[tuple[Polygon, float]] = []
    for vista in vistas:
        pos, look = ray(vista)
        span = math.dist(pos[:2], look[:2])
        if span < 1.0:
            continue
        stations = max(2, int(span / step))
        for i in range(stations):
            f = (i + 0.5) / stations
            x = pos[0] + (look[0] - pos[0]) * f
            y = pos[1] + (look[1] - pos[1]) * f
            z = pos[2] + (look[2] - pos[2]) * f
            caps.append((Point(x, y).buffer(half), z - margin))
    return caps


def camera_zones(radius: float = CAMERA_KEEPOUT
                 ) -> list[tuple[Polygon, float, float, str]]:
    """(disc, z0, z1, id): the sphere round every camera, as a plan disc and its z band.

    Lead, r7: a camera standing inside a cover piece sees nothing but cover (V4 and V6 both
    did). Every stage that places a solid takes these as a keep-out, and `in_sphere` is what
    the validator checks the finished layout with.
    """
    out: list[tuple[Polygon, float, float, str]] = []
    for vista in load():
        pos, _ = ray(vista)
        out.append((Point(pos[0], pos[1]).buffer(radius, quad_segs=24),
                    pos[2] - radius, pos[2] + radius, vista["id"]))
    return out


def camera_caps(radius: float = CAMERA_KEEPOUT) -> list[tuple[Polygon, float]]:
    """(disc, highest top allowed inside it) for the stages that place mass, not cover.

    Cover is small and plentiful, so it simply misses the whole sphere (`camera_zones`). A
    building or a deck is not: capping everything within 30 m of a camera to `pos_z - 30`
    would dig a 60 m pit in the Old Town. What matters is that the lens is never inside or
    behind a mass, so within the disc nothing may rise above the lens.
    """
    out: list[tuple[Polygon, float]] = []
    for vista in load():
        pos, _ = ray(vista)
        out.append((Point(pos[0], pos[1]).buffer(radius, quad_segs=24),
                    pos[2] - CAMERA_MARGIN))
    return out


def in_sphere(layout: dict, radius: float = CAMERA_KEEPOUT) -> dict[str, list[str]]:
    """Ids of the solids breaking each camera's keep-out, under the two rules above.

    Cover may not enter the sphere at all; a building, a deck or a column may not rise above
    the lens inside it. Landmarks are exempt - a camera is deliberately placed on its own set
    piece (V1 stands on the Insertion Pier). The slab a camera stands on is exempt too.
    """
    items: list[tuple[Polygon, float, float, str, str]] = []
    for b in layout["buildings"]:
        if b.get("landmark"):
            continue
        items.append((geom.rect(tuple(b["center"]), tuple(b["size"]), b.get("rot", 0.0)),
                      b["base_z"], b["base_z"] + b["height"], b["id"], "mass"))
    for arena in layout["arenas"]:
        for i, piece in enumerate(arena["cover"]):
            c = piece["center"]
            items.append((geom.rect((c[0], c[1]), (piece["size"][0], piece["size"][1])),
                          c[2], c[2] + piece["size"][2], f"{arena['id']}#{i}", "cover"))
    for deck in layout["decks"]:
        items.append((geom.poly(deck["polygon"]), deck["z"] - deck["thickness"], deck["z"],
                      deck["id"], "mass"))
        for i, col in enumerate(deck.get("columns", [])):
            items.append((geom.rect((col[0], col[1]), (20.0, 20.0)), 0.0, deck["z"],
                          f"{deck['id']}#col{i}", "mass"))
    out: dict[str, list[str]] = {}
    for vista in load():
        pos, _ = ray(vista)
        disc = Point(pos[0], pos[1]).buffer(radius, quad_segs=24)
        hits: list[str] = []
        for poly, z0, z1, ident, kind in items:
            if z1 <= pos[2] + 0.5 and z0 >= pos[2] - CAMERA_FLOOR:
                continue                  # the floor the camera stands on
            over = z1 > pos[2] - radius if kind == "cover" else z1 > pos[2] - CAMERA_MARGIN
            if over and z0 < pos[2] + radius and poly.intersects(disc):
                hits.append(ident)
        if hits:
            out[vista["id"]] = sorted(hits)
    return out


def occluders(layout: dict) -> list[tuple[Polygon, float, float, str, str]]:
    """Everything a vista ray can hit: (footprint, z0, z1, id, kind)."""
    out: list[tuple[Polygon, float, float, str, str]] = []
    for poly, z0, z1, ident in landmark_boxes():
        out.append((poly, z0, z1, ident, "landmark"))
    for b in layout["buildings"]:
        if b.get("landmark"):
            continue                      # already in as a landmark volume
        out.append((geom.rect(tuple(b["center"]), tuple(b["size"]), b["rot"]),
                    b["base_z"], b["base_z"] + b["height"], b["id"], "building"))
    for deck in layout["decks"]:
        area = geom.poly(deck["polygon"])
        for hole in deck.get("holes", []):
            area = area.difference(geom.poly(hole))
        out.append((area, deck["z"] - deck["thickness"], deck["z"], deck["id"], "deck"))
    return out


def first_hit(layout: dict, pos: tuple[float, float, float],
              look: tuple[float, float, float]) -> dict | None:
    """The nearest thing the ray actually passes through, 2.5D, with its distance."""
    items = occluders(layout)
    tree = STRtree([i[0] for i in items])
    line = LineString([(pos[0], pos[1]), (look[0], look[1])])
    total = line.length
    best: dict | None = None
    for idx in tree.query(line):
        poly, z0, z1, ident, kind = items[idx]
        if not poly.intersects(line):
            continue
        for part in getattr(poly.intersection(line), "geoms", [poly.intersection(line)]):
            if part.is_empty:
                continue
            coords = list(getattr(part, "coords", [])) or [(part.x, part.y)]
            for px, py in coords:
                t = 0.0 if total == 0 else line.project(Point(px, py)) / total
                z = pos[2] + (look[2] - pos[2]) * t
                if z0 - 0.5 < z < z1 + 0.5:
                    dist = t * total
                    if best is None or dist < best["dist"]:
                        best = {"id": ident, "kind": kind, "dist": round(dist, 1),
                                "z": round(z, 1), "offset": round(part.distance(
                                    Point(pos[0], pos[1])), 1)}
    return best


def flank_height(layout: dict, pos: tuple[float, float, float],
                 look: tuple[float, float, float], band: float = CANYON_FLANK) -> float:
    """Tallest mass within `band` of the ray in its first third: the canyon walls, if any."""
    line = LineString([(pos[0], pos[1]), (look[0], look[1])])
    near = line.interpolate(min(line.length, 260.0))
    tallest = 0.0
    for b in layout["buildings"]:
        box = geom.rect(tuple(b["center"]), tuple(b["size"]), b["rot"])
        if box.distance(near) <= band:
            tallest = max(tallest, b["base_z"] + b["height"])
    return tallest


def check(layout: dict) -> tuple[list[dict], list[str]]:
    """Per vista: the first hit, and whether the subject reads (or the framing is a canyon)."""
    rows: list[dict] = []
    problems: list[str] = []
    for vista in load():
        pos, look = ray(vista)
        subject = SUBJECTS.get(vista["id"])
        hit = first_hit(layout, pos, look)
        span = math.dist(pos[:2], look[:2])
        row = {"id": vista["id"], "subject": subject or "panorama",
               "hit": hit["id"] if hit else None, "kind": hit["kind"] if hit else None,
               "dist": hit["dist"] if hit else None, "span": round(span, 1),
               "flank": round(flank_height(layout, pos, look), 1)}
        if subject is None:
            row["verdict"] = "panorama" if hit is None else f"panorama, near {hit['id']}"
        elif hit is None:
            row["verdict"] = "subject clear (nothing on the ray)"
        elif hit["id"] == subject or hit["kind"] == "landmark":
            row["verdict"] = f"subject first ({hit['id']} at {hit['dist']:.0f} m)"
        elif hit["dist"] < 0.25 * span:
            row["verdict"] = f"BLOCKED by {hit['id']} at {hit['dist']:.0f} m"
            problems.append(f"L8 {vista['id']} ({vista['desc']}): {hit['kind']} {hit['id']} "
                            f"stands {hit['dist']:.0f} m in front of the camera, "
                            f"{row['flank']:.0f} m flanks")
        else:
            row["verdict"] = (f"framed past {hit['id']} at {hit['dist']:.0f} m "
                              f"({row['flank']:.0f} m canyon walls)")
        rows.append(row)
    for ident, hits in sorted(in_sphere(layout).items()):
        problems.append(f"L8 {ident}: {len(hits)} solids stand inside the "
                        f"{CAMERA_KEEPOUT:.0f} m camera sphere: {', '.join(hits[:6])}")
    return rows, problems


def report(rows: list[dict]) -> None:
    print("vistas (data/vistas.json, lead-owned):")
    for row in rows:
        print(f"  {row['id']} subject {row['subject']:9s} span {row['span']:6.0f} m  "
              f"first hit {str(row['hit']):22s} at {str(row['dist']):>6s} m  "
              f"flank {row['flank']:5.0f} m  -> {row['verdict']}")
