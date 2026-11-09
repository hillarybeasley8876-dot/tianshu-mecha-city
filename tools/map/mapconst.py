"""Shared constants for the city-layout tools (MAP.md §1, SPEC §4).

Every number the checks and the generator must agree on lives here, so a tuning change
is one edit and both validators and the generator follow it.
"""
from __future__ import annotations

import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DOSSIER = os.path.join(ROOT, "ref", "research", "level-design-vertical.md")
DATA_DIR = os.path.join(ROOT, "data", "map")
GRAPH_JSON = os.path.join(DATA_DIR, "level_graph.json")
LAYOUT_JSON = os.path.join(DATA_DIR, "city_layout.json")
DISTRICT_RULES_JSON = os.path.join(DATA_DIR, "district_rules.json")
OVERRIDES_JSON = os.path.join(DATA_DIR, "overrides.json")
CAPTURE_DIR = os.path.join(ROOT, "captures")

# --- MAP §1 tuning constants (SPEC §4 numbers, not the dossier's guesses) ---
H = 16.0                 # mech height
CAPSULE_R = 4.0
J = 40.0                 # boost-jump apex
FREE_CLIMB = 0.8 * J     # 32 m
HARD_STEP = 1.2 * J      # 48 m
AMBIGUITY = (FREE_CLIMB, HARD_STEP)  # 33-47 m: only when tagged `skill`
R_MIN = 150.0
R_MAX = 250.0
V_BOOST = 42.0
V_ASSAULT = 84.0
DODGE = 24.0
G_FALL = 25.5
CEILING = 260.0
HALF = 700.0
SKYLINE_HALF = 900.0
ON_DATUM_TOL = 2.0

# --- geometry rules (MAP §4 general + dossier §3.2) ---
FLOOR_MODULE = 4.0
SETBACK = 4.0            # building -> corridor edge
# Corridor widths come from OUR dodge (24 m), MAP §4 "General" (revised after r1):
# an avenue is two lanes that can each be dodged across plus the 2 x 4 m shoulder = 56 m.
AVENUE_MIN, AVENUE_MAX = 56.0, 72.0
STREET_MIN, STREET_MAX = 36.0, 48.0
ALLEY_MIN, ALLEY_MAX = 24.0, 32.0
ARCADE_CLEAR = 32.0     # podium-through opening: length of the hole along the street
MAX_RAMP_DEG = 20.0
UNDER_DECK_CLEAR = 24.0
TUNNEL_CLEAR_MIN = 32.0
SQUEEZE_CLEAR = 24.0
COVER_SPACING = (40.0, 60.0)
COVER_NEAR = 60.0        # every arena sample within this of full cover >= 20 m
FULL_COVER_H = 20.0
OPEN_COVER_MAX = 8.0     # an arena marked `open_cover` (the Crown) carries low cover only
KEEP_CLEAR = 12.0        # the sphere kept clear at every connector endpoint (lead, r4)
ARENA_DECK_CLEAR = 32.0  # C13: 32 m of headroom under anything inside an arena polygon
ARENA_SURFACE_MIN = 1500.0  # a deck this big inside an arena is a surface of its own
SOFT_SHARE = (0.30, 0.40)
MAX_STRAIGHT_STREET = 300.0
SPIRE_VISIBILITY = 0.80
ANCHORS_PER_ARENA = 8
ANCHOR_RANGE = 120.0
SPIRE_HEIGHT = 360.0

LAYERS = ("L0", "L1", "L2", "L3", "L4", "L5")
LAYER_Z = {"L0": -40.0, "L1": 0.0, "L2": 32.0, "L3": 80.0, "L4": 128.0, "L5": 224.0}
# Sub-datums: the dossier's node list uses L1+ (terrace shelves) and L2+ (flyovers),
# and treats L4 as the whole 128-176 rooftop band.
LAYER_DATUMS = {
    "L0": [-40.0], "L1": [0.0], "L1+": [16.0], "L2": [32.0], "L2+": [48.0, 56.0],
    "L3": [80.0], "L4": [128.0, 144.0, 160.0, 176.0], "L5": [224.0],
}
# preview colours by layer (MAP brief: L0 dark blue, L1 grey, L2 teal, L3 orange, L4 magenta, Crown gold)
LAYER_COLOR = {
    "L0": "#1b3a6b", "L1": "#9aa0a6", "L2": "#17a2a2", "L3": "#e8862a",
    "L4": "#d63fa8", "L5": "#e8c33a",
}
EDGE_KINDS = ("path", "ramp", "edgejump", "stairs", "lift", "vcat", "lcat", "vent", "rail",
              "drop", "tunnel")
NODE_TYPES = ("start", "arena", "hub", "path", "connector", "landmark", "reward", "boss")
DISTRICTS = ("D1", "D2", "D3", "D4", "D5", "D6", "D7")
TIERS = ("A", "B", "C", "D", "E")


def meta() -> dict:
    """The `meta` block written into level_graph.json (MAP §1 + dossier §5.1)."""
    return {
        "units": "m", "up": "Z", "H": H, "J": J, "R_min": R_MIN, "R_max": R_MAX,
        "v_boost": V_BOOST, "g": G_FALL, "capsule_r": CAPSULE_R, "capsule_h": H,
        "free_climb": FREE_CLIMB, "hard_step": HARD_STEP, "dodge": DODGE,
        "v_assault": V_ASSAULT, "ceiling": CEILING, "half": HALF,
        "skyline_half": SKYLINE_HALF, "floor_module": FLOOR_MODULE,
    }


def layer_of_z(z: float) -> str:
    """Nearest datum layer for a height (used to colour things in the previews)."""
    best = min(LAYER_Z.items(), key=lambda kv: abs(kv[1] - z))
    return best[0]
