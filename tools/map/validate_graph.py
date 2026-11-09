#!/usr/bin/env python3
"""validate_graph.py - checks C1-C11 on data/map/level_graph.json.

Port of the reference validator in ref/research/level-design-vertical.md §5.4, with our
constants (docs/MAP.md §1), plus C3 (start coverage) and C11 (route distinctness).

Usage: uv run --with networkx python3 tools/map/validate_graph.py
"""
from __future__ import annotations

import itertools
import json
import math
import os
import statistics
import sys

import networkx as nx

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mapconst as C  # noqa: E402

FAIL: list[str] = []
NOTES: list[str] = []

# Accepted exceptions (docs/MAP.md §4 "General"): the lead reviewed these findings and took
# them, so they are reported as a NOTE with the reason instead of failing the run.
ACCEPTED = {
    "C11 A4->A5": "the L3 rail alternative (A4-M3-M5-W4-A5) is only 0.7 s slower and is the "
                  "second route in practice; MAP §4 accepts it",
}


def t_edge(kind: str, h: float, dz: float) -> float:
    """Edge travel time, dossier §5.3, with our v_boost / g (MAP §1)."""
    if kind in ("path", "rail", "tunnel"):
        return h / C.V_BOOST
    if kind == "ramp":
        return math.hypot(h, dz) / 40.0
    if kind in ("edgejump", "stairs") and dz > 0:
        return 2.0 * math.ceil(dz / C.FREE_CLIMB) + h / 45.0
    if kind in ("drop", "edgejump", "stairs"):
        return h / 45.0 + math.sqrt(2 * abs(dz) / C.G_FALL) + 0.3
    if kind == "lift":
        return 3 + abs(dz) / 16 + h / C.V_BOOST
    if kind == "vcat":
        return 1.5 + abs(dz) / 60 + h / 80
    if kind == "lcat":
        return 1 + math.hypot(h, dz) / 120
    if kind == "vent":
        return 1 + abs(dz) / 40 + h / 45
    raise ValueError(f"unknown edge kind {kind!r}")


def declared_steps(tags: list[str]) -> int | None:
    """Flight count from a 'steps:N' edge tag (set in overrides.json)."""
    for tag in tags:
        if tag.startswith("steps:"):
            return int(tag.split(":", 1)[1])
    return None


def load() -> tuple[dict, dict]:
    with open(C.GRAPH_JSON, encoding="utf-8") as fh:
        graph = json.load(fh)
    nodes = {n["id"]: n for n in graph["nodes"]}
    if len(nodes) != len(graph["nodes"]):
        FAIL.append("C1 duplicate node ids")
    return graph, nodes


def check_schema(graph: dict, nodes: dict) -> nx.DiGraph:
    """C1 (schema, kinds, datum) + C8 (jump physics) + the timed digraph."""
    directed = nx.DiGraph()
    for nid in nodes:
        directed.add_node(nid)
    for node in nodes.values():
        datums = C.LAYER_DATUMS.get(node["layer"])
        if datums is None:
            FAIL.append(f"C1 {node['id']}: unknown layer {node['layer']!r}")
        elif min(abs(node["pos"][2] - d) for d in datums) > C.ON_DATUM_TOL and \
                "offdatum" not in node.get("tags", []):
            FAIL.append(f"C1 {node['id']}: z {node['pos'][2]} off datum for {node['layer']}")
    for edge in graph["edges"]:
        kind, tags = edge["kind"], edge.get("tags", [])
        if kind not in C.EDGE_KINDS:
            FAIL.append(f"C1 {edge['from']}-{edge['to']}: kind {kind!r} not in palette")
            continue
        ends = [(edge["from"], edge["to"])]
        if edge["bidir"]:
            ends.append((edge["to"], edge["from"]))
        for a, b in ends:
            if a not in nodes or b not in nodes:
                FAIL.append(f"C1 unknown node {a}->{b}")
                continue
            pa, pb = nodes[a]["pos"], nodes[b]["pos"]
            h = math.hypot(pb[0] - pa[0], pb[1] - pa[1])
            dz = pb[2] - pa[2]
            if kind == "edgejump" and dz > C.FREE_CLIMB:
                if not (dz < C.HARD_STEP and "skill" in tags):
                    FAIL.append(f"C8 {a}->{b} edgejump dz {dz:.0f} > {C.FREE_CLIMB:.0f} m "
                                f"and not a tagged skill lip")
            if kind == "stairs" and dz > 0 and dz > C.FREE_CLIMB:
                flights = declared_steps(tags)
                if flights is None:
                    FAIL.append(f"C8 {a}->{b} stairs rise {dz:.0f} m: declare the landing count "
                                f"in overrides.json graph.edge_tags ('<from>><to>': ['steps:N'])")
                elif dz / flights > C.FREE_CLIMB:
                    FAIL.append(f"C8 {a}->{b} stairs rise {dz:.0f} m over {flights} flights = "
                                f"{dz / flights:.1f} m per flight (> {C.FREE_CLIMB:.0f} m)")
            if kind == "drop" and dz >= 0:
                FAIL.append(f"C8 {a}->{b} drop is not downward (dz {dz:+.0f})")
            if kind == "ramp" and h > 0 and abs(math.degrees(math.atan2(dz, h))) > C.MAX_RAMP_DEG:
                FAIL.append(f"C8 {a}->{b} ramp grade "
                            f"{abs(math.degrees(math.atan2(dz, h))):.1f}° > {C.MAX_RAMP_DEG}°")
            directed.add_edge(a, b, t=t_edge(kind, h, dz), kind=kind)
    return directed


def check_topology(directed: nx.DiGraph, nodes: dict) -> nx.Graph:
    """C2 strong connectivity, C4 dead ends, C5 loops, C6 node redundancy."""
    if nx.number_strongly_connected_components(directed) != 1:
        biggest = max(nx.strongly_connected_components(directed), key=len)
        for nid in sorted(set(nodes) - biggest):
            FAIL.append(f"C2 {nid} is not strongly connected to the main component")
    undirected = nx.Graph(directed.to_undirected())
    dead = sorted(n for n in undirected if undirected.degree(n) == 1)
    for nid in dead:
        if nodes[nid]["type"] not in ("reward", "start", "boss"):
            FAIL.append(f"C4 unrewarded dead end {nid} ({nodes[nid]['type']})")
    if len(dead) > 0.15 * len(nodes):
        FAIL.append(f"C4 {len(dead)} dead ends = {100 * len(dead) / len(nodes):.0f}% of nodes (> 15%)")
    loops = undirected.number_of_edges() - undirected.number_of_nodes() + \
        nx.number_connected_components(undirected)
    if loops < 3:
        FAIL.append(f"C5 only {loops} independent loops")
    if loops < 10:
        NOTES.append(f"C5 {loops} loops is below the 10-loop target for {len(nodes)} nodes")
    for a, b in nx.bridges(undirected):
        for x, y in ((a, b), (b, a)):
            if nodes[x].get("arena") not in (None, "BOSS") and \
                    nodes[y]["type"] not in ("reward", "start"):
                FAIL.append(f"C5 arena node {x} sits on bridge edge {a}-{b}")
    start = start_node(nodes)
    root = next(iter(undirected[start]))
    without_start = undirected.copy()
    without_start.remove_node(start)
    arenas = arena_members(nodes)
    for cut in nx.articulation_points(without_start):
        trimmed = without_start.copy()
        trimmed.remove_node(cut)
        for aid, members in arenas.items():
            if aid == "BOSS" or cut in members or cut == root:
                continue
            if not any(nx.has_path(trimmed, root, m) for m in members if m in trimmed):
                FAIL.append(f"C6 removing {cut} isolates arena {aid}")
    return undirected


def start_node(nodes: dict) -> str:
    return next(nid for nid, n in nodes.items() if n["type"] == "start")


def arena_members(nodes: dict) -> dict[str, set[str]]:
    out: dict[str, set[str]] = {}
    for nid, node in nodes.items():
        if node.get("arena"):
            out.setdefault(node["arena"], set()).add(nid)
    return out


def check_layers(directed: nx.DiGraph, nodes: dict) -> list[tuple[int, int, int, int]]:
    """C7: >= 4 up and >= 4 down links per band, and an internal way up/down per district."""
    z = lambda n: nodes[n]["pos"][2]  # noqa: E731
    bands = []
    for lo, hi in ((-40, 0), (0, 32), (32, 80), (80, 128)):
        up = sum(1 for a, b in directed.edges
                 if z(a) <= lo + 16 and z(b) >= hi - 16 and z(b) > z(a))
        down = sum(1 for a, b in directed.edges
                   if z(b) <= lo + 16 and z(a) >= hi - 16 and z(b) < z(a))
        if up < 4 or down < 4:
            FAIL.append(f"C7 band {lo}->{hi}: up {up} down {down} (need 4/4)")
        for district in C.DISTRICTS:
            members = [n for n in nodes if nodes[n]["district"] == district]
            sub = directed.subgraph(members)
            lows = [n for n in members if z(n) <= lo + 16]
            highs = [n for n in members if z(n) >= hi - 16]
            if not lows or not highs or set(lows) == set(highs):
                continue
            has_up = any(nx.has_path(sub, a, b) for a in lows for b in highs)
            has_down = any(nx.has_path(sub, b, a) for a in lows for b in highs)
            if not (has_up and has_down):
                FAIL.append(f"C7 district {district} band {lo}->{hi} lacks a way "
                            f"{'down' if has_up else 'up'}")
        bands.append((lo, hi, up, down))
    return bands


def check_arena_entries(directed: nx.DiGraph, nodes: dict) -> None:
    """C9: >= 3 entry edges from >= 2 layers; the boss has exactly 1 entry and >= 1 exit."""
    for aid, members in arena_members(nodes).items():
        ins = [(a, b) for a, b in directed.edges if b in members and a not in members]
        outs = [(a, b) for a, b in directed.edges if a in members and b not in members]
        layers = {nodes[a]["layer"] for a, _ in ins}
        if aid == "BOSS":
            if len(ins) != 1:
                FAIL.append(f"C9 boss has {len(ins)} entries (want exactly 1 gated entry)")
            if not outs:
                FAIL.append("C9 boss has no exit")
            continue
        if len(ins) < 3 or len(layers) < 2:
            FAIL.append(f"C9 {aid}: {len(ins)} entries on {len(layers)} layer(s) "
                        f"{sorted(layers)} (need >= 3 on >= 2)")


def check_travel(directed: nx.DiGraph, nodes: dict) -> dict:
    """C3 start coverage <= 90 s and C10 arena/arena, arena/boss, node/arena budgets."""
    dist = dict(nx.all_pairs_dijkstra_path_length(directed, weight="t"))
    start = start_node(nodes)
    reach = dist[start]
    for nid, node in nodes.items():
        if node["type"] == "boss":
            continue
        if nid not in reach:
            FAIL.append(f"C3 {nid} unreachable from START")
        elif reach[nid] > 90:
            FAIL.append(f"C3 {nid} is {reach[nid]:.1f}s from START (> 90 s)")
    arenas = arena_members(nodes)
    ids = [k for k in arenas if k != "BOSS"]

    def crossing(a: str, b: str) -> float:
        return min(dist[x].get(y, math.inf) for x in arenas[a] for y in arenas[b])

    pairs = [crossing(a, b) for a, b in itertools.permutations(ids, 2)]
    gate = {a: crossing(a, "BOSS") for a in ids}
    nearest = max(min(min(dist[n].get(m, math.inf) for m in arenas[k]) for k in ids)
                  for n in nodes if nodes[n]["type"] != "boss")
    if max(pairs) > 45:
        FAIL.append(f"C10 arena->arena worst {max(pairs):.1f}s (> 45 s)")
    if statistics.median(pairs) > 30:
        FAIL.append(f"C10 arena->arena median {statistics.median(pairs):.1f}s (> 30 s)")
    if max(gate.values()) > 30:
        FAIL.append(f"C10 arena->boss gate worst {max(gate.values()):.1f}s (> 30 s) "
                    f"at {[a for a, v in gate.items() if v == max(gate.values())]}")
    if nearest > 25:
        FAIL.append(f"C10 node->nearest arena worst {nearest:.1f}s (> 25 s)")
    return {"start_max": max(v for k, v in reach.items() if nodes[k]["type"] != "boss"),
            "arena_max": max(pairs), "arena_median": statistics.median(pairs),
            "gate": gate, "nearest": nearest, "dist": dist, "ids": ids,
            "arenas": arenas}


def mid_point(path: list[str], nodes: dict) -> tuple[float, float]:
    """Horizontal position at the middle of a node path (used by C11)."""
    lengths = [math.dist(nodes[a]["pos"][:2], nodes[b]["pos"][:2])
               for a, b in zip(path, path[1:])]
    half, walked = sum(lengths) / 2.0, 0.0
    for (a, b), seg in zip(zip(path, path[1:]), lengths):
        if walked + seg >= half and seg > 0:
            f = (half - walked) / seg
            pa, pb = nodes[a]["pos"], nodes[b]["pos"]
            return (pa[0] + (pb[0] - pa[0]) * f, pa[1] + (pb[1] - pa[1]) * f)
        walked += seg
    return tuple(nodes[path[len(path) // 2]]["pos"][:2])


def check_distinctness(directed: nx.DiGraph, nodes: dict, stats: dict) -> int:
    """C11: the two fastest edge-disjoint arena-to-arena routes differ in layer mix,
    or their mid-route points are >= 150 m apart."""
    checked = 0
    for a, b in itertools.combinations(sorted(stats["ids"]), 2):
        for src, dst in itertools.product(sorted(stats["arenas"][a]), sorted(stats["arenas"][b])):
            trimmed = directed.copy()
            paths = []
            for _ in range(2):
                if not nx.has_path(trimmed, src, dst):
                    break
                path = nx.dijkstra_path(trimmed, src, dst, weight="t")
                paths.append(path)
                trimmed.remove_edges_from(list(zip(path, path[1:])))
            if len(paths) < 2:
                FAIL.append(f"C11 {a}->{b}: no second edge-disjoint route from {src}")
                break
            layers = [{nodes[n]["layer"].rstrip("+") for n in p} for p in paths]
            if layers[0] != layers[1]:
                checked += 1
                break
            gap = math.dist(mid_point(paths[0], nodes), mid_point(paths[1], nodes))
            if gap < 150.0:
                message = (f"C11 {a}->{b}: routes share layers {sorted(layers[0])} "
                           f"and pass {gap:.0f} m apart (< 150 m)")
                if f"C11 {a}->{b}" in ACCEPTED:
                    NOTES.append(f"{message} - ACCEPTED: {ACCEPTED[f'C11 {a}->{b}']}")
                else:
                    FAIL.append(message)
            checked += 1
            break
    return checked


def main() -> int:
    graph, nodes = load()
    directed = check_schema(graph, nodes)
    undirected = check_topology(directed, nodes)
    bands = check_layers(directed, nodes)
    check_arena_entries(directed, nodes)
    stats = check_travel(directed, nodes)
    pairs = check_distinctness(directed, nodes, stats)
    loops = undirected.number_of_edges() - undirected.number_of_nodes() + \
        nx.number_connected_components(undirected)
    dead = sum(1 for n in undirected if undirected.degree(n) == 1)
    print(f"nodes {len(nodes)} · edges {directed.number_of_edges()} directed "
          f"({len(graph['edges'])} listed) · loops {loops} · dead ends {dead} "
          f"({100 * dead / len(nodes):.0f}%)")
    print("layer links up/down: " + "  ".join(
        f"{label}: {u}/{d}" for label, (_, _, u, d)
        in zip(("L0<->L1", "L1<->L2", "L2<->L3", "L3<->L4"), bands)))
    print(f"start coverage worst {stats['start_max']:.1f}s · arena->arena worst "
          f"{stats['arena_max']:.1f}s median {stats['arena_median']:.1f}s · "
          f"node->arena worst {stats['nearest']:.1f}s")
    print("arena->boss gate: " + "  ".join(f"{a} {t:.1f}s" for a, t in sorted(stats["gate"].items())))
    print(f"route distinctness pairs checked {pairs}/{len(list(itertools.combinations(sorted(stats['ids']), 2)))}")
    for note in NOTES:
        print(f"NOTE {note}")
    if FAIL:
        print(f"FAIL ({len(FAIL)})")
        for f in FAIL:
            print(f"  {f}")
        return 1
    print("PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
