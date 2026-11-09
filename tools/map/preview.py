#!/usr/bin/env python3
"""preview.py - render the layout so the composition can be judged from pictures.

captures/layout_plan.png        2,400 px top view, coloured by layer, heights labelled
captures/layout_iso_{sw,ne,top}.png   massing / layering / silhouettes
captures/layout_section_ns.png  S->N section through X ~ 0, like the dossier §4.3

Usage: uv run --with numpy --with shapely --with matplotlib python3 tools/map/preview.py
"""
from __future__ import annotations

import json
import math
import os
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
from matplotlib.patches import Circle, Polygon as MplPoly, Rectangle  # noqa: E402

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import geom  # noqa: E402
import hive_rule  # noqa: E402
import mapconst as C  # noqa: E402
from massing import TIER_SHADE, iso  # noqa: E402

PLAN_PX = 2400
BG = "#0d1117"
GRID = "#1d2530"


def load() -> dict:
    with open(C.LAYOUT_JSON, encoding="utf-8") as fh:
        return json.load(fh)


def poly2d(points: list[list[float]], **kw):
    return MplPoly([(p[0], p[1]) for p in points], closed=True, **kw)


def deck_patches(ax, layout, alpha: float = 0.55, lw: float = 0.6) -> None:
    for deck in layout["decks"]:
        colour = C.LAYER_COLOR[C.layer_of_z(deck["z"])]
        ax.add_patch(poly2d(deck["polygon"], facecolor=colour, edgecolor=colour,
                            alpha=alpha, linewidth=lw, zorder=3))
        for hole in deck.get("holes", []):
            ax.add_patch(poly2d(hole, facecolor=BG, edgecolor=colour, alpha=0.9,
                                linewidth=lw * 0.6, zorder=3.1))
        for col in deck.get("columns", []):
            ax.add_patch(Circle((col[0], col[1]), 9, facecolor="none", edgecolor=colour,
                                linewidth=0.5, zorder=3.2))


def corridor_lines(ax, layout, lw_scale: float = 0.06) -> None:
    for group, dash in (("streets", None), ("viaducts", (0, (6, 3))), ("rails", (0, (2, 2))),
                        ("tunnels", (0, (1, 3)))):
        for item in layout[group]:
            colour = C.LAYER_COLOR[C.layer_of_z(item["z"])]
            xs = [p[0] for p in item["points"]]
            ys = [p[1] for p in item["points"]]
            ax.plot(xs, ys, color=colour, linewidth=max(0.8, item["width"] * lw_scale),
                    linestyle=dash if dash else "-", alpha=0.95, zorder=4,
                    solid_capstyle="round")


def plan(layout: dict) -> str:
    """Top view: layers in their colours, buildings tier-shaded with heights on C/D/E."""
    fig, ax = plt.subplots(figsize=(24, 24), dpi=100)
    fig.patch.set_facecolor(BG)
    ax.set_facecolor(BG)
    half = layout["bounds"]["half"]
    ax.set_xlim(-half - 40, half + 40)
    ax.set_ylim(-half - 40, half + 40)
    ax.set_aspect("equal")
    for step in range(-900, 901, 100):
        ax.axhline(step, color=GRID, linewidth=0.5, zorder=0)
        ax.axvline(step, color=GRID, linewidth=0.5, zorder=0)
    ax.add_patch(Rectangle((-half, -half), 2 * half, 2 * half, fill=False,
                           edgecolor="#5a6675", linewidth=2, zorder=1))
    ax.add_patch(Rectangle((-900, -900), 1800, 1800, fill=False, edgecolor="#2a323d",
                           linewidth=1, zorder=1))

    terr = layout["terrain"]
    ax.add_patch(poly2d(terr["plateau"]["polygon"], facecolor="#182233", edgecolor="none",
                        zorder=1.5))
    ax.add_patch(poly2d(terr["canal"]["polygon"], facecolor="#12324d", edgecolor="#1d4f74",
                        linewidth=1.2, zorder=1.6))
    if terr["docks"]["polygon"]:
        ax.add_patch(poly2d(terr["docks"]["polygon"], facecolor="#173a52", edgecolor="none",
                            zorder=1.7))
    crest = terr["escarpment"]["crest"]
    ax.plot([p[0] for p in crest], [p[1] for p in crest], color="#8a6a3a", linewidth=3,
            zorder=2)
    for lip in terr["escarpment"]["lips"]:
        ax.add_patch(Circle(lip["pos"], lip["width"] / 2, facecolor="none",
                            edgecolor="#e0b060", linewidth=2, zorder=6))

    corridor_lines(ax, layout)
    deck_patches(ax, layout)
    for b in layout["buildings"]:
        shade = TIER_SHADE[b["tier"]]
        ax.add_patch(_rot_rect(b, facecolor=shade, edgecolor="#0d1117", linewidth=0.7,
                               zorder=5, alpha=0.95))
    for b in layout["buildings"]:
        if b["tier"] in ("C", "D", "E"):
            ax.text(b["center"][0], b["center"][1], f"{b['base_z'] + b['height']:.0f}",
                    color="#dfe7ef", fontsize=7, ha="center", va="center", zorder=9)

    for arena in layout["arenas"]:
        ax.add_patch(poly2d(arena["polygon"], facecolor="none", edgecolor="#ff6b6b",
                            linewidth=2.4, zorder=7))
        c = _centroid(arena["polygon"])
        ax.text(c[0], c[1] - 18, arena["id"], color="#ff9c9c", fontsize=22, ha="center",
                zorder=9, weight="bold")
        for cover in arena["cover"]:
            ax.add_patch(Circle(cover["center"][:2], 5.0,
                                facecolor="#ff6b6b" if not cover["soft"] else "none",
                                edgecolor="#ff9c9c", linewidth=0.4, alpha=0.5, zorder=6.5))
        for sock in arena.get("spawn_sockets", []):
            ax.plot(sock["pos"][0], sock["pos"][1], marker="^", markersize=13,
                    color="#7cf5c8", markeredgecolor="#0d1117", zorder=10.5)
    for lm in layout["landmarks"]:
        ax.plot(lm["pos"][0], lm["pos"][1], marker="*", markersize=26, color="#ffd166",
                zorder=10, markeredgecolor="#0d1117")
        ax.text(lm["pos"][0] + 22, lm["pos"][1] + 14, lm["kind"], color="#ffd166",
                fontsize=13, zorder=10)
    for hive in layout["hives"]:
        # the open ground (lead r6) and the assault ring where cover gives way to firing lines
        for radius, style in ((hive_rule.OPEN_R, "-"), (hive_rule.ASSAULT_R, ":")):
            ax.add_patch(Circle((hive["pos"][0], hive["pos"][1]), radius, fill=False,
                                edgecolor="#c56bff", linewidth=1.1, linestyle=style,
                                alpha=0.8, zorder=9.5))
        ax.plot(hive["pos"][0], hive["pos"][1], marker="X", markersize=20, color="#c56bff",
                zorder=10)
        ax.text(hive["pos"][0], hive["pos"][1] - hive_rule.ASSAULT_R - 16,
                f"{hive['id']} {hive['pos'][2]:+.0f}", color="#c56bff", fontsize=12,
                ha="center", zorder=10)
    for item in layout["skyline"]:
        ax.add_patch(Rectangle((item["center"][0] - item["size"][0] / 2,
                                item["center"][1] - item["size"][1] / 2),
                               item["size"][0], item["size"][1], facecolor="#1a2028",
                               edgecolor="#242c36", linewidth=0.4, zorder=1.2))
    start = layout["player_start"]
    ax.plot(start["pos"][0], start["pos"][1], marker="P", markersize=22, color="#4ade80",
            zorder=11)
    ax.text(start["pos"][0], start["pos"][1] - 40, "START", color="#4ade80", fontsize=15,
            ha="center", zorder=11)
    _sky_overlay(ax, layout)
    _graph_overlay(ax)
    _legend(ax, layout)
    ax.set_title("MECHA CITY — Escarpment City around the Spire: layout plan "
                 f"(1,400 x 1,400 m playable, seed {layout['meta']['seed']})",
                 color="#dfe7ef", fontsize=26, pad=18)
    ax.tick_params(colors="#5a6675", labelsize=11)
    path = os.path.join(C.CAPTURE_DIR, "layout_plan.png")
    fig.subplots_adjust(left=0.04, right=0.99, top=0.95, bottom=0.04)
    fig.savefig(path, facecolor=BG)          # no tight bbox: the brief asks for 2,400 px
    plt.close(fig)
    return path


def _rot_rect(b: dict, **kw):
    cx, cy = b["center"]
    w, d = b["size"]
    rad = math.radians(b.get("rot", 0.0))
    corners = [(-w / 2, -d / 2), (w / 2, -d / 2), (w / 2, d / 2), (-w / 2, d / 2)]
    pts = [(cx + x * math.cos(rad) - y * math.sin(rad),
            cy + x * math.sin(rad) + y * math.cos(rad)) for x, y in corners]
    return MplPoly(pts, closed=True, **kw)


def _centroid(points: list[list[float]]) -> tuple[float, float]:
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    return sum(xs) / len(xs), sum(ys) / len(ys)


def _sky_overlay(ax, layout: dict) -> None:
    """The flyer routing graph, in thin violet (MAP §3 sky graph, lead r2 point 4)."""
    nodes = {n["id"]: n for n in layout.get("sky_waypoints", [])}
    for a, b in layout.get("sky_edges", []):
        if a not in nodes or b not in nodes:
            continue
        pa, pb = nodes[a]["pos"], nodes[b]["pos"]
        ax.plot([pa[0], pb[0]], [pa[1], pb[1]], color="#8b5cf6", linewidth=0.9,
                alpha=0.7, zorder=7.5)
    for node in nodes.values():
        x, y, _z = node["pos"]
        ax.plot(x, y, marker=".", markersize=3.4, color="#c4b5fd", zorder=7.6)


def _graph_overlay(ax) -> None:
    """Graph nodes and edges on top of the plan, so a route can be traced by eye."""
    with open(C.GRAPH_JSON, encoding="utf-8") as fh:
        graph = json.load(fh)
    nodes = {n["id"]: n for n in graph["nodes"]}
    for edge in graph["edges"]:
        a, b = nodes[edge["from"]]["pos"], nodes[edge["to"]]["pos"]
        ax.plot([a[0], b[0]], [a[1], b[1]], color="#ffffff", linewidth=0.9, alpha=0.55,
                linestyle="-" if edge["bidir"] else (0, (3, 2)), zorder=8)
    for node in graph["nodes"]:
        x, y, z = node["pos"]
        colour = {"start": "#4ade80", "arena": "#ff6b6b", "boss": "#ff2e63",
                  "reward": "#ffd166", "hub": "#7ad7f0"}.get(node["type"], "#dfe7ef")
        ax.plot(x, y, marker="o", markersize=7, color=colour, markeredgecolor="#0d1117",
                markeredgewidth=0.8, zorder=9)
        ax.text(x + 12, y + 8, node["id"], color="#c7d1dc", fontsize=9, zorder=9)


def _legend(ax, layout: dict) -> None:
    half = layout["bounds"]["half"]
    rows = [("L0 -40 tunnels", C.LAYER_COLOR["L0"]),
            ("L1 0 streets", C.LAYER_COLOR["L1"]),
            ("L2 +32 viaduct/plateau", C.LAYER_COLOR["L2"]),
            ("L3 +80 skyrail/decks", C.LAYER_COLOR["L3"]),
            ("L4 +128..176 roofs", C.LAYER_COLOR["L4"]),
            ("Crown +224", C.LAYER_COLOR["L5"])]
    # inside the frame: the axes are clipped to the playable square, so a legend parked
    # outside it is cut off
    left = -half + 24
    ax.add_patch(Rectangle((left - 12, half - 300), 640, 292, facecolor="#0d1117",
                           edgecolor="#2a323d", alpha=0.86, zorder=11.5))
    for i, (label, colour) in enumerate(rows):
        ax.add_patch(Rectangle((left, half - 44 - i * 40), 34, 26, facecolor=colour,
                               edgecolor="none", zorder=12))
        ax.text(left + 44, half - 30 - i * 40, label, color="#dfe7ef", fontsize=15, zorder=12)
    tiers = ", ".join(f"{t}: {TIER_SHADE[t]}" for t in ("A", "B", "C", "D"))
    ax.text(left, half - 296, f"buildings by tier  {tiers}\n"
                       f"{len(layout['buildings'])} buildings · "
                       f"{len(layout['decks'])} decks · "
                       f"{len(layout['connectors'])} connectors · "
                       f"{sum(len(a['cover']) for a in layout['arenas'])} cover pieces\n"
                       "numbers on tier C/D/E buildings = roof height in m\n"
                       f"green triangles = arena spawn sockets, "
                       f"{sum(len(a.get('spawn_sockets', [])) for a in layout['arenas'])} "
                       "on the arena fight tiers (r5)\n"
                       f"violet = sky graph, {len(layout.get('sky_waypoints', []))} waypoints / "
                       f"{len(layout.get('sky_edges', []))} edges (flyer routing)",
            color="#9fb0c0", fontsize=14, zorder=12, va="top")


def section(layout: dict, x_band: float = 120.0) -> str:
    """S->N section through X ~ 0, heights to scale (compare the dossier §4.3 sketch)."""
    fig, ax = plt.subplots(figsize=(22, 9), dpi=100)
    fig.patch.set_facecolor(BG)
    ax.set_facecolor(BG)
    terr = layout["terrain"]
    crest = terr["escarpment"]["crest"]
    ax.plot([-700, 700], [0, 0], color="#2b3644", linewidth=1.4)
    north = [(p[0], p[1]) for p in crest if abs(p[0]) <= x_band]
    if north:
        ax.plot([max(y for _, y in north)] * 2, [0, 32], color="#8a6a3a", linewidth=3)
        ax.plot([-700, max(y for _, y in north)], [32, 32], color="#8a6a3a", linewidth=2,
                linestyle=(0, (4, 3)))
    canal_y = max(p[1] for p in terr["canal"]["polygon"] if abs(p[0]) <= x_band)
    ax.add_patch(Rectangle((-700, -16), canal_y + 700, 16, facecolor="#12324d",
                           edgecolor="none"))
    for b in layout["buildings"]:
        cy = b["center"][1]
        if abs(b["center"][0]) > x_band:
            continue
        depth = b["size"][1]
        ax.add_patch(Rectangle((cy - depth / 2, b["base_z"]), depth, b["height"],
                               facecolor=TIER_SHADE[b["tier"]], edgecolor="none",
                               alpha=0.9))
    band = geom.poly([[-x_band, -900], [x_band, -900], [x_band, 900], [-x_band, 900]])
    for deck in layout["decks"]:
        area = geom.poly(deck["polygon"])
        for hole in deck.get("holes", []):
            area = area.difference(geom.poly(hole))
        cut = area.intersection(band)
        if cut.is_empty or cut.area < 200.0:
            continue
        lo, hi = cut.bounds[1], cut.bounds[3]
        ax.add_patch(Rectangle((lo, deck["z"] - deck["thickness"]), hi - lo,
                               deck["thickness"],
                               facecolor=C.LAYER_COLOR[C.layer_of_z(deck["z"])],
                               edgecolor="none"))
    for group in ("streets", "viaducts", "rails", "tunnels"):
        for item in layout[group]:
            hits = [p[1] for p in item["points"] if abs(p[0]) <= x_band]
            if len(hits) < 2:
                continue
            ax.plot([min(hits), max(hits)], [item["z"], item["z"]],
                    color=C.LAYER_COLOR[C.layer_of_z(item["z"])], linewidth=3)
    ax.plot([120, 120], [0, 360], color="#ffd166", linewidth=7)
    ax.plot([120, 120], [360, 420], color="#8be9fd", linewidth=2, linestyle=(0, (2, 4)))
    ax.text(132, 396, "light tether continues to +900 m", color="#8be9fd", fontsize=10)
    for z, label in ((-40, "L0"), (0, "L1"), (32, "L2"), (80, "L3"), (144, "L4"),
                     (224, "Crown"), (360, "Spire top")):
        ax.axhline(z, color=GRID, linewidth=0.8)
        ax.text(-690, z + 6, f"{label} {z:+d}", color="#7d8b9a", fontsize=11)
    ax.set_xlim(-700, 700)
    ax.set_ylim(-60, 420)
    ax.set_xlabel("Y north (m)  —  S at left, N at right", color="#7d8b9a")
    ax.set_ylabel("Z up (m)", color="#7d8b9a")
    ax.tick_params(colors="#4d5a68")
    ax.set_title("MECHA CITY layout — S→N section through X ≈ 0 "
                 f"(everything within ±{x_band:.0f} m of the Spire axis, heights to scale)",
                 color="#dfe7ef", fontsize=18)
    path = os.path.join(C.CAPTURE_DIR, "layout_section_ns.png")
    fig.savefig(path, facecolor=BG, bbox_inches="tight")
    plt.close(fig)
    return path


def main() -> int:
    layout = load()
    os.makedirs(C.CAPTURE_DIR, exist_ok=True)
    paths = [plan(layout)]
    paths += [iso(layout, view) for view in ("sw", "ne", "top")]
    paths.append(section(layout))
    for p in paths:
        print(f"wrote {os.path.relpath(p, C.ROOT)} "
              f"({os.path.getsize(p) / 1e6:.2f} MB)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
