"""The hand fixes in data/map/overrides.json, applied to a built layout (never to the output).

`layout.drop` / `layout.move` / `layout.retier` / `layout.extra_*` / `layout.skyline` are the
five levers; every hand change to the city goes through this file so `build_layout.py` can
always regenerate the layout from the graph. Two of them have to land at different times:

* `layout.move` on a corridor has to be applied to `parts` BEFORE the stages that read the
  corridors, otherwise the decks and setbacks are cut for the old route
  (`apply_corridor_moves`);
* everything else is applied to the finished layout (`apply`), last, so it wins over every
  stage.
"""
from __future__ import annotations


def apply_corridor_moves(parts: dict, overrides: dict) -> int:
    """Hand-routed corridor polylines, applied to the corridor records themselves."""
    moved = 0
    for move in overrides["layout"].get("move", []):
        for group in ("streets", "viaducts", "rails", "tunnels"):
            for item in parts[group]:
                if item.get("id") == move["id"]:
                    item.update(move["to"])
                    moved += 1
    return moved


def apply(layout: dict, overrides: dict) -> int:
    """Hand fixes from data/map/overrides.json `layout` (never edit the output by hand)."""
    rules = overrides["layout"]
    touched = 0
    drop = set(rules.get("drop", []))
    if drop:
        for key in ("buildings", "connectors", "streets", "viaducts", "rails", "tunnels",
                    "decks", "landmarks", "arenas"):
            layout[key] = [i for i in layout[key] if i.get("id") not in drop]
        layout["anchors"] = [a for a in layout["anchors"] if a.get("on") not in drop]
    for move in rules.get("move", []):
        for key in ("buildings", "decks", "landmarks", "connectors", "streets", "viaducts",
                    "rails", "tunnels"):
            for item in layout[key]:
                if item.get("id") == move["id"]:
                    item.update(move["to"])
                    touched += 1
    # The 96 skyline-ring towers are pure backdrop 700-900 m out and are the LAST draw on the
    # shared rng stream, so any change upstream re-rolls all of them (lead, r9: dropping 33 lots
    # moved every one by 590 m on average). `layout.skyline` in overrides.json pins the ring the
    # player has already seen; delete the block to let it re-roll.
    if rules.get("skyline"):
        layout["skyline"] = [dict(row) for row in rules["skyline"]]
        touched += len(rules["skyline"])
    for change in rules.get("retier", []):
        for b in layout["buildings"]:
            if b["id"] == change["id"]:
                b.update({k: v for k, v in change.items() if k != "id"})
                touched += 1
    layout["connectors"].extend(rules.get("extra_connectors", []))
    layout["buildings"].extend(rules.get("extra_buildings", []))
    return touched + len(drop) + len(rules.get("extra_connectors", [])) + \
        len(rules.get("extra_buildings", []))
