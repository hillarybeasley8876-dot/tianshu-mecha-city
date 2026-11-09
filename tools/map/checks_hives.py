"""L4 sub-check: every Hive Spire stands on ground it can be assaulted from (lead, r6).

Split out of checks_arena.py the way checks_sockets.py is, and measuring through
`hive_rule.verify` - the same function the generator's late repair uses, reading the written JSON
and never the generator's geometry. A hive that fails here is one flow's E2E bot cannot shoot:
r3 found 0 of 48 candidate firing positions at hive_a2 and hive_a5.
"""
from __future__ import annotations

import hive_rule
from hive_rule import verify

FAIL: list[str] = []


def check_l4_hives(layout: dict) -> dict:
    """Open ground, shootable pods, approach routes - per spire, with the numbers printed."""
    out: dict[str, dict] = {}
    tree, items = hive_rule.solids(layout)
    for hive in layout["hives"]:
        report = verify(layout, hive, tree, items)
        x, y, z = report["pos"]
        for problem in report["problems"]:
            FAIL.append(f"L4 {hive['id']} at ({x:.0f},{y:.0f},{z:+.0f}) in {hive['arena']}: "
                        f"{problem}")
        out[hive["id"]] = {
            "pos": (x, y, z), "arena": hive["arena"], "open": not report["blocked"],
            "positions": report["positions"], "worst": report["worst"],
            "per_pod": report["per_pod"], "routes": report["routes"],
            "route_ids": report["route_ids"][:4]}
    return out


def report(rows: dict) -> str:
    """One line per spire for the validator's summary."""
    return "  ".join(
        f"{k} {v['arena']}@({v['pos'][0]:.0f},{v['pos'][1]:.0f},{v['pos'][2]:+.0f}) "
        f"open {'y' if v['open'] else 'n'} pods {v['worst']}/{v['positions']} "
        f"routes {v['routes']}" for k, v in sorted(rows.items()))
