"""Material roles for the city blockout (city-build). Names are the city-art contract:
ART.md 4 / brief 2. Colours are the ART.md 2 palette so the blockout already reads warm;
city-art replaces every one of these materials in Godot BY NAME.

UVs are in metres everywhere except `mc_window`, whose faces get 0..1 per window cell.
"""
import sys
import os

sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender"))

from lib import mats  # noqa: E402

# role -> (colour, roughness, metallic, emission colour or None, emission strength)
ROLES = {
    "mc_stone": ((0.851, 0.831, 0.780), 0.62, 0.0, None, 0.0),       # pale limestone  #D9D4C7
    "mc_concrete": ((0.663, 0.631, 0.588), 0.78, 0.0, None, 0.0),    # warm concrete   #A9A196
    "mc_glass": ((0.110, 0.149, 0.200), 0.12, 0.85, None, 0.0),      # dark glass      #1C2633
    "mc_panel_white": ((0.929, 0.937, 0.949), 0.35, 0.0, None, 0.0),  # white panel    #EDEFF2
    "mc_metal": ((0.549, 0.576, 0.608), 0.34, 0.9, None, 0.0),       # brushed steel   #8C939B
    "mc_bronze": ((0.690, 0.478, 0.290), 0.30, 0.85, None, 0.0),     # bronze accent   #B07A4A
    "mc_road": ((0.180, 0.180, 0.190), 0.85, 0.0, None, 0.0),
    "mc_deck": ((0.560, 0.545, 0.510), 0.70, 0.0, None, 0.0),
    "mc_terracotta": ((0.557, 0.290, 0.212), 0.72, 0.0, None, 0.0),  # Old Town roofs  #8E4A36
    # Emissive window cells: UV 0..1 per cell, so the shader can light random cells at dusk.
    "mc_window": ((0.055, 0.075, 0.105), 0.14, 0.6, (1.0, 0.812, 0.541), 1.6),
    "mc_up_accent": ((0.243, 0.902, 1.0), 0.30, 0.0, (0.243, 0.902, 1.0), 6.0),  # "up" cyan
    "mc_water": ((0.180, 0.353, 0.431), 0.08, 0.2, None, 0.0),       # canal water     #2E5A6E
}
ROLE_ORDER = list(ROLES.keys())

# District material identity (ART.md 4). Returns the roles a district leans on, in draw order.
DISTRICT_ROLES = {
    "D1": ("mc_concrete", "mc_metal", "mc_panel_white"),
    "D2": ("mc_concrete", "mc_panel_white", "mc_metal"),
    "D3": ("mc_terracotta", "mc_stone", "mc_concrete"),
    "D4": ("mc_stone", "mc_panel_white", "mc_bronze"),
    "D5": ("mc_concrete", "mc_panel_white", "mc_glass"),
    "D6": ("mc_metal", "mc_concrete", "mc_metal"),
    "D7": ("mc_glass", "mc_metal", "mc_panel_white"),
}


def build_materials():
    """Create every role material once; returns {role: bpy.types.Material}."""
    out = {}
    for role, (color, rough, metal, emit_color, emit) in ROLES.items():
        out[role] = mats.pbr(role, color=color, roughness=rough, metallic=metal,
                             emission=emit_color, emission_strength=emit)
    return out
