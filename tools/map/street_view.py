"""Street-level render: a pinhole camera at eye height, so density can be judged.

matplotlib's 3D axes can only orbit the map centre, so this projects the city itself: a
camera at a chosen point (the player start at H0 by default, looking at the Spire), a 55 deg
vertical field of view, faces sorted back to front, one Lambert term from a fixed sun. It is
a blockout read, not a beauty render - it answers "does this feel like a city from the
street".

Usage: uv run --with numpy --with shapely --with matplotlib python3 tools/map/street_view.py
"""
from __future__ import annotations

import json
import math
import os
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
from matplotlib.patches import Polygon as MplPoly  # noqa: E402

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import geom  # noqa: E402
import mapconst as C  # noqa: E402
from massing import height_colour, shade  # noqa: E402

BG = "#0b0f14"
SUN = (0.42, -0.36, 0.83)          # direction to the sun, normalised below
NEAR = 8.0
FAR = 2600.0


def _norm(v):
    length = math.sqrt(sum(c * c for c in v)) or 1.0
    return tuple(c / length for c in v)


class Camera:
    """Pinhole camera: world -> camera space -> screen, with a vertical FOV."""

    def __init__(self, pos, look, fov_deg: float, width: int, height: int) -> None:
        self.pos = tuple(float(v) for v in pos)
        look = tuple(float(v) for v in look)
        self.fwd = _norm(tuple(look[i] - self.pos[i] for i in range(3)))
        world_up = (0.0, 0.0, 1.0)
        self.right = _norm((self.fwd[1] * world_up[2] - self.fwd[2] * world_up[1],
                            self.fwd[2] * world_up[0] - self.fwd[0] * world_up[2],
                            self.fwd[0] * world_up[1] - self.fwd[1] * world_up[0]))
        self.up = (self.right[1] * self.fwd[2] - self.right[2] * self.fwd[1],
                   self.right[2] * self.fwd[0] - self.right[0] * self.fwd[2],
                   self.right[0] * self.fwd[1] - self.right[1] * self.fwd[0])
        self.tan = math.tan(math.radians(fov_deg) / 2)
        self.aspect = width / height
        self.width, self.height = width, height

    def project(self, point):
        """Return (x_px, y_px, depth) or None when the point is behind the camera."""
        rel = tuple(point[i] - self.pos[i] for i in range(3))
        depth = sum(rel[i] * self.fwd[i] for i in range(3))
        if depth < NEAR or depth > FAR:
            return None
        sx = sum(rel[i] * self.right[i] for i in range(3)) / (depth * self.tan * self.aspect)
        sy = sum(rel[i] * self.up[i] for i in range(3)) / (depth * self.tan)
        return ((sx + 1) * 0.5 * self.width, (1 - sy) * 0.5 * self.height, depth)


def faces(layout: dict) -> list[tuple[list[tuple[float, float, float]], str, float]]:
    """Every visible face as (corners, base colour, depth key): buildings, decks, Spire."""
    out: list[tuple[list[tuple[float, float, float]], str, float]] = []
    for b in layout["buildings"]:
        cx, cy = b["center"]
        w, d = b["size"]
        base, top = b["base_z"], b["base_z"] + b["height"]
        rad = math.radians(b.get("rot", 0.0))
        corners = []
        for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            x, y = sx * w / 2, sy * d / 2
            corners.append((cx + x * math.cos(rad) - y * math.sin(rad),
                            cy + x * math.sin(rad) + y * math.cos(rad)))
        colour = height_colour(top)
        for i in range(4):
            x0, y0 = corners[i]
            x1, y1 = corners[(i + 1) % 4]
            out.append(([(x0, y0, base), (x1, y1, base), (x1, y1, top), (x0, y0, top)],
                        colour, (x0 + x1) / 2))
        out.append(([(p[0], p[1], top) for p in corners], colour, cx))
    carriers = {b["id"]: b for b in layout["buildings"]}
    for deck in layout["decks"]:
        colour = C.LAYER_COLOR[C.layer_of_z(deck["z"])]
        out.append(([(p[0], p[1], deck["z"]) for p in deck["polygon"]], colour, deck["z"]))
        # the fascia, so a slab reads as a slab and not as a painted line
        ring = deck["polygon"]
        for i in range(len(ring)):
            x0, y0 = ring[i]
            x1, y1 = ring[(i + 1) % len(ring)]
            out.append(([(x0, y0, deck["z"] - deck["thickness"]),
                         (x1, y1, deck["z"] - deck["thickness"]),
                         (x1, y1, deck["z"]), (x0, y0, deck["z"])],
                        colour, deck["z"]))
        out += _supports(deck, carriers)
    for z0, z1, r in ((0.0, 80.0, 70.0), (80.0, 160.0, 54.0), (160.0, 224.0, 44.0),
                      (224.0, 360.0, 26.0)):
        corners = [(-r, 120 - r), (r, 120 - r), (r, 120 + r), (-r, 120 + r)]
        for i in range(4):
            x0, y0 = corners[i]
            x1, y1 = corners[(i + 1) % 4]
            out.append(([(x0, y0, z0), (x1, y1, z0), (x1, y1, z1), (x0, y0, z1)],
                        "#ffd166", 0.0))
    return out


def _supports(deck: dict, carriers: dict) -> list:
    """What holds this deck up, drawn: its columns, its carrier towers' upper shafts, and
    the pier legs under a viaduct (lead r1 point 7 - no floating slabs in the preview)."""
    out = []
    for col in deck.get("columns", []):
        top = deck["z"] - deck["thickness"]
        out.append(([(col[0] - 10, col[1] - 10, 0), (col[0] + 10, col[1] - 10, 0),
                     (col[0] + 10, col[1] + 10, top), (col[0] - 10, col[1] + 10, top)],
                    "#2a3340", col[0]))
    for ident in deck.get("supported_by", []):
        b = carriers.get(ident)
        if b is None or b.get("landmark"):
            continue                     # the Spire is drawn as its own stepped mass
        cx, cy = b["center"]
        w, d = b["size"]
        top = deck["z"]
        out.append(([(cx - w / 2, cy - d / 2, b["base_z"]), (cx + w / 2, cy - d / 2, b["base_z"]),
                     (cx + w / 2, cy - d / 2, top), (cx - w / 2, cy - d / 2, top)],
                    "#3a4756", cx))
    for pier in deck.get("piers", []):
        out.append(([(pier[0] - 12, pier[1] - 12, deck["z"] - pier[2]),
                     (pier[0] + 12, pier[1] - 12, deck["z"] - pier[2]),
                     (pier[0] + 12, pier[1] - 12, deck["z"]),
                     (pier[0] - 12, pier[1] - 12, deck["z"])], "#2a3340", pier[0]))
    return out


def lambert(corners) -> float:
    """One diffuse term from the face normal against a fixed sun."""
    ax, ay, az = (corners[1][i] - corners[0][i] for i in range(3))
    bx, by, bz = (corners[2][i] - corners[0][i] for i in range(3))
    nx, ny, nz = ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx
    length = math.sqrt(nx * nx + ny * ny + nz * nz) or 1.0
    dot = abs((nx * SUN[0] + ny * SUN[1] + nz * SUN[2]) / length)
    return 0.42 + 0.72 * dot


def render(layout: dict, pos, look, fov: float, path: str, title: str,
           width: int = 1800, height: int = 1000) -> str:
    cam = Camera(pos, look, fov, width, height)
    fig = plt.figure(figsize=(width / 100, height / 100), dpi=100)
    fig.patch.set_facecolor(BG)
    ax = fig.add_axes((0, 0, 1, 1))
    ax.set_xlim(0, width)
    ax.set_ylim(height, 0)
    ax.set_facecolor(BG)
    ax.axis("off")
    ground = [(-3000, -3000, 0), (3000, -3000, 0), (3000, 3000, 0), (-3000, 3000, 0)]
    quad = [cam.project(p) for p in ground]
    if all(quad):
        ax.add_patch(MplPoly([(p[0], p[1]) for p in quad], closed=True,
                             facecolor="#141a21", edgecolor="none", zorder=0))
    drawn = []
    for corners, colour, _key in faces(layout):
        projected = [cam.project(p) for p in corners]
        if any(p is None for p in projected):
            continue
        depth = sum(p[2] for p in projected) / len(projected)
        drawn.append((depth, [(p[0], p[1]) for p in projected], colour, corners))
    drawn.sort(key=lambda item: -item[0])
    for depth, points, colour, corners in drawn:
        lam = lambert(corners) * min(1.0, 1.35 - depth / 2400.0)
        ax.add_patch(MplPoly(points, closed=True, facecolor=shade(colour, lam),
                             edgecolor="none"))
    ax.text(24, height - 26, title, color="#dfe7ef", fontsize=15)
    ax.text(24, 30, f"camera {tuple(int(v) for v in pos)} -> {tuple(int(v) for v in look)}"
                    f"   fov {fov:.0f} deg   faces {len(drawn)}",
            color="#7d8b9a", fontsize=11)
    fig.savefig(path, facecolor=BG)
    plt.close(fig)
    return path


def main() -> int:
    with open(C.LAYOUT_JSON, encoding="utf-8") as fh:
        layout = json.load(fh)
    start = layout["player_start"]["pos"]
    eye = (start[0], start[1], start[2] + 20.0)
    os.makedirs(C.CAPTURE_DIR, exist_ok=True)
    shots = [
        (eye, (0.0, 120.0, 200.0), 55.0, "layout_street_h0.png",
         "Street level from the Insertion Pier (H0, eye 20 m) toward the Spire"),
        ((-80.0, -500.0, 156.0), (0.0, 120.0, 200.0), 50.0, "layout_street_skygarden.png",
         "Sky Garden deck (+156) toward the Spire across the Financial towers (vista V6)"),
        # Spire Avenue S runs (0,-120)-(0,-420): stand at its south end and look up it
        ((0.0, -400.0, 20.0), (0.0, 330.0, 170.0), 58.0, "layout_street_spire_ave.png",
         "Spire Avenue at 20 m looking north up the civic canyon to the Spire"),
        # the Megablock Canyon is arena A4, x 405-515 / y 220-620, floor at +32
        ((460.0, 250.0, 52.0), (440.0, 640.0, 170.0), 62.0, "layout_street_canyon.png",
         "Megablock Canyon floor (+32, eye 52) north to Block 9 (vista V4)"),
        # from the Crown deck itself: what the boss fight looks out on, due north over the
        # Civic Quarter (lead r2 point 6 - this is the view the whole fight frames)
        ((0.0, 268.0, 232.0), (0.0, 640.0, 120.0), 62.0, "layout_crown_north.png",
         "Crown deck north rim (+232) looking north over the Civic Quarter"),
        # D7 street level, looking up at the Sky Garden strung between its carriers
        ((188.0, -405.0, 22.0), (-60.0, -450.0, 160.0), 62.0,
         "layout_street_skygarden_up.png",
         "D7 street at 22 m looking up at the Sky Garden (+144) and its carrier towers"),
    ]
    for pos, look, fov, name, title in shots:
        path = os.path.join(C.CAPTURE_DIR, name)
        render(layout, pos, look, fov, path, title)
        print(f"wrote {os.path.relpath(path, C.ROOT)} ({os.path.getsize(path) / 1e6:.2f} MB)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
