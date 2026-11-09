"""Isometric massing views: extruded building boxes, deck plates and the Spire.

Split out of preview.py so each file stays readable; `iso()` writes
captures/layout_iso_{sw,ne,top}.png.
"""
from __future__ import annotations

import math
import os
import sys

import warnings

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

# mpl3d overflows a float while auto-scaling the margins of a 1.4 km axis; the drawing is
# correct, and the warning would otherwise hide real ones.
warnings.filterwarnings("ignore", category=RuntimeWarning, module="mpl_toolkits.mplot3d")
from mpl_toolkits.mplot3d.art3d import Poly3DCollection  # noqa: E402

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mapconst as C  # noqa: E402

TIER_SHADE = {"A": "#3b4a5a", "B": "#4d6070", "C": "#6b8296", "D": "#93a8bb", "E": "#e8c33a"}
# height ramp for the street views (lead r1 point 7): the mass is read by how high it goes,
# not by which tier the generator rolled, so a canyon of 176 m towers looks like one
HEIGHT_RAMP = ((0.0, "#33414f"), (48.0, "#4d6070"), (96.0, "#17a2a2"),
               (160.0, "#d63fa8"), (232.0, "#e8c33a"), (400.0, "#fff3c4"))


def height_colour(top: float) -> str:
    """Colour for a mass of this absolute height, interpolated along HEIGHT_RAMP."""
    stops = HEIGHT_RAMP
    if top <= stops[0][0]:
        return stops[0][1]
    for (z0, c0), (z1, c1) in zip(stops, stops[1:]):
        if top <= z1:
            f = (top - z0) / (z1 - z0)
            a = [int(c0.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4)]
            b = [int(c1.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4)]
            return "#" + "".join(f"{int(a[i] + (b[i] - a[i]) * f):02x}" for i in range(3))
    return stops[-1][1]
BG = "#0d1117"
GRID = "#1d2530"


def crown_detail(deck: dict, colour: str) -> list:
    """The Crown's stepped rim, its four fins and its central core, as extra faces.

    MAP §4 makes the Crown a disc with a stepped rim; a flat polygon would hide the only
    silhouette detail the boss arena has.
    """
    centre = None
    if deck.get("rim_steps") or deck.get("fins") or deck.get("core"):
        ring = deck["polygon"]
        centre = (sum(p[0] for p in ring) / len(ring), sum(p[1] for p in ring) / len(ring))
    if centre is None:
        crown_detail.shades = []
        return []
    cx, cy = centre
    out: list = []
    shades: list[float] = []
    for step in deck.get("rim_steps", [])[1:]:
        top = step["z"] + step["rise"]
        out.append([(cx + step["r"] * math.cos(t), cy + step["r"] * math.sin(t), top)
                    for t in [i * math.pi / 12 for i in range(24)]])
        shades.append(1.15)
    for fin in deck.get("fins", []):
        rad = math.radians(fin["angle_deg"])
        reach = deck.get("rim_steps", [{"r": 150.0}])[0]["r"] + fin["reach"] / 2
        fx, fy = cx + reach * math.cos(rad), cy + reach * math.sin(rad)
        hw = fin["width"] / 2
        for i in range(4):
            a = [(fx - hw, fy - hw), (fx + hw, fy - hw), (fx + hw, fy + hw), (fx - hw, fy + hw)]
            x0, y0 = a[i]
            x1, y1 = a[(i + 1) % 4]
            out.append([(x0, y0, deck["z"]), (x1, y1, deck["z"]),
                        (x1, y1, deck["z"] + fin["height"]), (x0, y0, deck["z"] + fin["height"])])
            shades.append(0.8)
    core = deck.get("core")
    if core:
        r = core["r"]
        for i in range(12):
            t0, t1 = i * math.pi / 6, (i + 1) * math.pi / 6
            out.append([(cx + r * math.cos(t0), cy + r * math.sin(t0), core["z"]),
                        (cx + r * math.cos(t1), cy + r * math.sin(t1), core["z"]),
                        (cx + r * math.cos(t1), cy + r * math.sin(t1), core["z"] + core["height"]),
                        (cx + r * math.cos(t0), cy + r * math.sin(t0), core["z"] + core["height"])])
            shades.append(0.9)
    crown_detail.shades = shades
    return out


def _boxes(ax, layout) -> None:
    """Extruded building boxes, one Poly3DCollection for the whole city."""
    faces, colours = [], []
    for b in layout["buildings"]:
        cx, cy = b["center"]
        w, d = b["size"]
        base, top = b["base_z"], b["base_z"] + b["height"]
        colour = TIER_SHADE[b["tier"]]
        rad = math.radians(b.get("rot", 0.0))
        corners = [(-w / 2, -d / 2), (w / 2, -d / 2), (w / 2, d / 2), (-w / 2, d / 2)]
        pts = [(cx + x * math.cos(rad) - y * math.sin(rad),
                cy + x * math.sin(rad) + y * math.cos(rad)) for x, y in corners]
        for i in range(4):
            x0, y0 = pts[i]
            x1, y1 = pts[(i + 1) % 4]
            faces.append([(x0, y0, base), (x1, y1, base), (x1, y1, top), (x0, y0, top)])
            colours.append(shade(colour, 0.5 + 0.2 * i))
        faces.append([(p[0], p[1], top) for p in pts])
        colours.append(shade(colour, 1.3))
    ax.add_collection3d(Poly3DCollection(faces, facecolors=colours, edgecolors="none"))


def shade(hex_colour: str, factor: float) -> tuple[float, float, float]:
    hex_colour = hex_colour.lstrip("#")
    rgb = [int(hex_colour[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(min(1.0, v * factor) for v in rgb)


def _slabs(ax, layout) -> None:
    """Decks and viaducts as thin plates at their own height."""
    faces, colours = [], []
    for deck in layout["decks"]:
        colour = C.LAYER_COLOR[C.layer_of_z(deck["z"])]
        faces.append([(p[0], p[1], deck["z"]) for p in deck["polygon"]])
        colours.append(shade(colour, 0.95))
        for col in deck.get("columns", []):
            faces.append([(col[0] - 10, col[1] - 10, 0), (col[0] + 10, col[1] - 10, 0),
                          (col[0] + 10, col[1] + 10, 0), (col[0] - 10, col[1] + 10, 0)])
            colours.append(shade(colour, 0.4))
        faces.extend(crown_detail(deck, colour))
        colours.extend([shade(colour, f) for f in crown_detail.shades])
    for via in layout["viaducts"]:
        for i in range(len(via["points"]) - 1):
            (x0, y0), (x1, y1) = via["points"][i], via["points"][i + 1]
            nx, ny = -(y1 - y0), (x1 - x0)
            norm = math.hypot(nx, ny) or 1.0
            hw = via["width"] / 2
            faces.append([(x0 + nx / norm * hw, y0 + ny / norm * hw, via["z"]),
                          (x1 + nx / norm * hw, y1 + ny / norm * hw, via["z"]),
                          (x1 - nx / norm * hw, y1 - ny / norm * hw, via["z"]),
                          (x0 - nx / norm * hw, y0 - ny / norm * hw, via["z"])])
            colours.append(C.LAYER_COLOR["L2"])
        for pier in via.get("piers", []):
            faces.append([(pier[0] - 6, pier[1] - 6, 0), (pier[0] + 6, pier[1] - 6, 0),
                          (pier[0] + 6, pier[1] + 6, 0), (pier[0] - 6, pier[1] + 6, 0)])
            colours.append(shade(C.LAYER_COLOR["L2"], 0.5))
    ax.add_collection3d(Poly3DCollection(faces, facecolors=colours, edgecolors="none",
                                         alpha=0.9))


def _spire(ax, layout) -> None:
    """The weenie as real mass: a stepped, tapering tower plus the collar, roof ring and
    crown, so it sorts against the buildings instead of hiding behind its own decks."""
    shaft = next(lm for lm in layout["landmarks"] if lm["kind"] == "spire")
    cx, cy, _ = shaft["pos"]
    faces, colours = [], []
    steps = ((0.0, 80.0, 70.0), (80.0, 160.0, 54.0), (160.0, 224.0, 44.0),
             (224.0, 300.0, 34.0), (300.0, 360.0, 20.0))
    for z0, z1, r in steps:
        corners = [(cx - r, cy - r), (cx + r, cy - r), (cx + r, cy + r), (cx - r, cy + r)]
        for i in range(4):
            x0, y0 = corners[i]
            x1, y1 = corners[(i + 1) % 4]
            faces.append([(x0, y0, z0), (x1, y1, z0), (x1, y1, z1), (x0, y0, z1)])
            colours.append(shade("#ffd166", 0.45 + 0.2 * i))
        faces.append([(p[0], p[1], z1) for p in corners])
        colours.append(shade("#ffe9a8", 1.0))
    for z, rad in ((80.0, 152.0), (160.0, 104.0)):
        faces.append([(cx + rad * math.cos(t), cy + rad * math.sin(t), z)
                      for t in [i * math.pi / 12 for i in range(24)]])
        colours.append(shade("#ffd166", 0.7))
    tower = Poly3DCollection(faces, facecolors=colours, edgecolors="none")
    tower.set_zorder(8)          # the weenie is drawn over the plates it passes through
    ax.add_collection3d(tower)
    ax.plot([cx, cx], [cy, cy], [360, 415], color="#8be9fd", linewidth=1.6, alpha=0.7,
            linestyle=(0, (2, 4)), zorder=9)      # tether, clipped to the view (real top 900 m)


def iso(layout: dict, view: str) -> str:
    """3D massing view: boxes for buildings, plates for decks, polylines for corridors."""
    elev, azim = {"sw": (26, -125), "ne": (26, 55), "top": (78, -60)}[view]
    fig = plt.figure(figsize=(20, 14), dpi=120)
    fig.patch.set_facecolor(BG)
    ax = fig.add_subplot(111, projection="3d")
    ax.set_facecolor(BG)
    half = layout["bounds"]["half"]
    _boxes(ax, layout)
    _slabs(ax, layout)
    _spire(ax, layout)
    for group in ("streets", "rails", "tunnels"):
        for item in layout[group]:
            colour = C.LAYER_COLOR[C.layer_of_z(item["z"])]
            ax.plot([p[0] for p in item["points"]], [p[1] for p in item["points"]],
                    [item["z"]] * len(item["points"]), color=colour, linewidth=1.4,
                    alpha=0.9)
    for arena in layout["arenas"]:
        ring = [(p[0], p[1]) for p in arena["polygon"]] + [tuple(arena["polygon"][0][:2])]
        z = max(arena["tiers"])
        ax.plot([p[0] for p in ring], [p[1] for p in ring], [z] * len(ring),
                color="#ff6b6b", linewidth=2.2)
    for hive in layout["hives"]:
        ax.plot([hive["pos"][0]], [hive["pos"][1]], [hive["pos"][2]], marker="X",
                markersize=12, color="#c56bff")
    ring_faces = []
    for item in layout["skyline"]:
        cx, cy = item["center"]
        w, d, h = item["size"][0], item["size"][1], item["height"]
        ring_faces.append([(cx - w / 2, cy - d / 2, 0), (cx + w / 2, cy - d / 2, 0),
                           (cx + w / 2, cy + d / 2, 0), (cx - w / 2, cy + d / 2, 0),
                           (cx - w / 2, cy - d / 2, 0)])
        ring_faces.append([(cx - w / 2, cy - d / 2, h), (cx + w / 2, cy - d / 2, h),
                           (cx + w / 2, cy + d / 2, h), (cx - w / 2, cy + d / 2, h)])
        for i, (sx, sy) in enumerate(((-1, -1), (1, -1), (1, 1), (-1, 1))):
            nx, ny = ((1, -1), (1, 1), (-1, 1), (-1, -1))[i]
            ring_faces.append([(cx + sx * w / 2, cy + sy * d / 2, 0),
                               (cx + nx * w / 2, cy + ny * d / 2, 0),
                               (cx + nx * w / 2, cy + ny * d / 2, h),
                               (cx + sx * w / 2, cy + sy * d / 2, h)])
    ax.add_collection3d(Poly3DCollection(ring_faces, facecolors="#1b222b",
                                         edgecolors="none", alpha=0.45))
    ax.set_xlim(-half, half)
    ax.set_ylim(-half, half)
    ax.set_zlim(0, 420)
    ax.view_init(elev=elev, azim=azim)
    ax.set_box_aspect((1, 1, 0.55))
    ax.set_xlabel("X east (m)", color="#7d8b9a", fontsize=10)
    ax.set_ylabel("Y north (m)", color="#7d8b9a", fontsize=10)
    ax.set_zlabel("Z up (m)", color="#7d8b9a", fontsize=10)
    ax.tick_params(colors="#4d5a68", labelsize=8)
    for pane in (ax.xaxis, ax.yaxis, ax.zaxis):
        pane.set_pane_color((0.05, 0.07, 0.09, 1.0))
        pane._axinfo["grid"]["color"] = GRID
    ax.set_title(f"MECHA CITY layout — isometric {view.upper()} "
                 f"(Spire 360 m, tether to 900 m)", color="#dfe7ef", fontsize=20)
    path = os.path.join(C.CAPTURE_DIR, f"layout_iso_{view}.png")
    fig.subplots_adjust(left=0.02, right=0.98, top=0.94, bottom=0.03)
    fig.savefig(path, facecolor=BG)
    plt.close(fig)
    return path


