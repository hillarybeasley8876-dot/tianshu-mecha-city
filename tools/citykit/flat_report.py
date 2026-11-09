#!/usr/bin/env python3
"""The lead's r4 flatness gate, as one table: r3 export next to the shipped one.

    python3 tools/citykit/flat_report.py                    # the five models the review names
    python3 tools/citykit/flat_report.py t01 b01 --lod      # any ids, plus their _lod.glb

`blender/citykit/export_r3.py` writes the r3 baseline (collapse, clear the glTF's custom split
normals, smooth 40, no planar pass, no weighted normals) to tmp/city-kit/r3/<id>_r3.glb; this reads
that and the shipped `game/world/kit/<id>/<id>.glb` and prints the two numbers the review asks for:

* **truly flat** — share of surface area whose every welded neighbour is within 1 degree of the
  triangle's own plane. This is the number `planar.flatten()` used to *claim* and not deliver.
* **shading deviation** — area-weighted angle between the stored NORMAL attribute and the geometric
  face normal, plus the share of area more than 30 degrees off. A mesh decimated after its normals
  were built keeps normals that belong to no face it still has; that is the cover-tier fault.
"""
from __future__ import annotations

import os
import sys
from typing import List

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from meshqa import report  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
KIT = os.path.join(ROOT, "game", "world", "kit")
R3 = os.path.join(ROOT, "tmp", "city-kit", "r3")
#: The models lead review r4 names for the flatness gate.
GATE_IDS = ("t01", "b01", "m01", "o01", "k06")


def row(path: str) -> dict:
    return report(path) if os.path.exists(path) else {}


def main(argv: List[str]) -> int:
    lod = "--lod" in argv
    ids = [a for a in argv if not a.startswith("-")] or list(GATE_IDS)
    print("%-10s %-6s %8s %8s %8s   %8s %8s"
          % ("model", "tier", "flat1%", "flat3%", "tris", "dev deg", ">30deg%"))
    for i in ids:
        suffix = "_lod" if lod else ""
        a = row(os.path.join(R3, "%s_r3.glb" % i))
        b = row(os.path.join(KIT, i, "%s%s.glb" % (i, suffix)))
        for tag, r in (("r3", a), ("r5", b)):
            if not r:
                print("%-10s %-6s (missing)" % (i, tag))
                continue
            print("%-10s %-6s %8.1f %8.1f %8d   %8.1f %8.1f"
                  % (i, tag, r["flat1"], r["flat3"], r["tris"], r["dev_mean"], r["dev_over"]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
