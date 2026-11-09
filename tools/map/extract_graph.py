#!/usr/bin/env python3
"""extract_graph.py - transcribe the dossier's §4.7 node table and §4.8 edge table into
`data/map/level_graph.json` (format: dossier §5.1, meta: docs/MAP.md §1).

Usage: uv run --with networkx python3 tools/map/extract_graph.py
"""
from __future__ import annotations

import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mapconst as C  # noqa: E402

BIDIR = "↔"
ONEWAY = "→"


def read_section_tables(md: str, heading: str) -> list[list[list[str]]]:
    """Return every markdown table under `heading`, as lists of cell-lists (header dropped)."""
    lines = md.splitlines()
    start = next(i for i, ln in enumerate(lines) if ln.startswith(heading))
    tables: list[list[list[str]]] = []
    current: list[list[str]] | None = None
    for ln in lines[start + 1:]:
        if ln.startswith("#"):
            break
        if not ln.lstrip().startswith("|"):
            if current:
                tables.append(current)
                current = None
            continue
        cells = [c.strip() for c in ln.strip().strip("|").split("|")]
        if set("".join(cells)) <= set("-: "):          # separator row
            continue
        if current is None:
            current = []                               # header row: skipped
            continue
        current.append(cells)
    if current:
        tables.append(current)
    return tables


def num(text: str) -> float:
    """Parse a signed dossier number ('-560', '+0', '4.4'); returns float."""
    return float(text.replace("+", "", 1) if text.startswith("+") else text)


def parse_nodes(md: str) -> list[dict]:
    tables = read_section_tables(md, "### 4.7 Node list")
    rows = [r for t in tables for r in t if len(r) >= 9]
    nodes = []
    for r in rows:
        nid, name, district, layer, x, y, z, ntype, arena = r[:9]
        if nid == "id":
            continue
        if district not in C.DISTRICTS:
            raise ValueError(f"node {nid}: unknown district {district!r}")
        if ntype not in C.NODE_TYPES:
            raise ValueError(f"node {nid}: unknown type {ntype!r}")
        if layer not in C.LAYER_DATUMS:
            raise ValueError(f"node {nid}: unknown layer {layer!r}")
        node = {"id": nid, "name": name, "district": district, "layer": layer,
                "pos": [num(x), num(y), num(z)], "type": ntype}
        if arena:
            node["arena"] = arena
        nodes.append(node)
    return nodes


def parse_edges(md: str) -> list[dict]:
    tables = read_section_tables(md, "### 4.8 Edge list")
    rows = [r for t in tables for r in t if len(r) >= 8]
    edges = []
    for r in rows:
        src, direction, dst, kind = r[0], r[1], r[2], r[3]
        if src == "from":
            continue
        if direction not in (BIDIR, ONEWAY):
            raise ValueError(f"edge {src}-{dst}: bad direction glyph {direction!r}")
        if kind not in C.EDGE_KINDS:
            raise ValueError(f"edge {src}-{dst}: kind {kind!r} not in the palette")
        edges.append({"from": src, "to": dst, "kind": kind,
                      "bidir": direction == BIDIR, "tags": []})
    return edges


def apply_graph_overrides(edges: list[dict]) -> tuple[int, int]:
    """Merge the hand-authored graph levers in overrides.json into the transcribed edges.

    `graph.edge_tags` (`'<from>><to>'`) declares what the dossier's table cannot: a `stairs` run
    taller than one 32 m flight needs its landing count, so C8 can check the flights and
    build_layout can build the landings. `graph.extra_edges` adds an edge the dossier's §4.8
    table does not have - the r8 lever for a route that has to exist in 3D (lead, r8 item 2:
    A6's third inbound route onto the Sky Garden).
    """
    with open(C.OVERRIDES_JSON, encoding="utf-8") as fh:
        graph_rules = json.load(fh)["graph"]
    keyed = {f"{e['from']}>{e['to']}": e for e in edges}
    for key, tags in graph_rules["edge_tags"].items():
        if key not in keyed:
            raise ValueError(f"overrides graph.edge_tags: no edge {key!r}")
        keyed[key]["tags"] = list(tags)
    added = 0
    for extra in graph_rules.get("extra_edges", []):
        key = f"{extra['from']}>{extra['to']}"
        if key in keyed:
            raise ValueError(f"overrides graph.extra_edges: {key!r} is already in the dossier")
        edge = {"from": extra["from"], "to": extra["to"], "kind": extra["kind"],
                "bidir": bool(extra.get("bidir", False)), "tags": list(extra.get("tags", []))}
        if edge["kind"] not in C.EDGE_KINDS:
            raise ValueError(f"overrides graph.extra_edges: kind {edge['kind']!r} not in palette")
        edges.append(edge)
        added += 1
    return len(graph_rules["edge_tags"]), added


def main() -> int:
    with open(C.DOSSIER, encoding="utf-8") as fh:
        md = fh.read()
    nodes = parse_nodes(md)
    edges = parse_edges(md)
    tagged, added = apply_graph_overrides(edges)
    ids = [n["id"] for n in nodes]
    dupes = {i for i in ids if ids.count(i) > 1}
    if dupes:
        raise ValueError(f"duplicate node ids: {sorted(dupes)}")
    known = set(ids)
    for e in edges:
        for end in (e["from"], e["to"]):
            if end not in known:
                raise ValueError(f"edge {e['from']}-{e['to']}: unknown node {end}")
    os.makedirs(C.DATA_DIR, exist_ok=True)
    graph = {"meta": C.meta(), "nodes": nodes, "edges": edges}
    with open(C.GRAPH_JSON, "w", encoding="utf-8") as fh:
        json.dump(graph, fh, indent=1, ensure_ascii=False)
        fh.write("\n")
    print(f"wrote {os.path.relpath(C.GRAPH_JSON, C.ROOT)}: "
          f"{len(nodes)} nodes, {len(edges)} edges "
          f"({sum(1 for e in edges if e['bidir'])} bidirectional, {tagged} tag overrides, "
          f"{added} extra edges)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
