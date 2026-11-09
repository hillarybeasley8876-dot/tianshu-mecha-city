"""The Tianshu hero skeleton and the region -> bone chain map (hero-v3, brief step 2).

Every joint below is MEASURED, not guessed: `blender/hero3/diag_limbs.py` slices each labelled limb
piece along its own axis and reports the centroid and the mean radius per slice, and a joint is where
a limb is thinnest (ankle r 0.54, waist r 0.90, neck r 0.43) or where it bulges (knee r 0.85).
Positions are in the final 16 m frame: origin between the feet on the ground, facing +Y, crest at
z = 16.0 (CONTRACTS §2).

The mesh is a posed reconstruction and is slightly asymmetric (the left hand sits 0.5 m closer to the
spine than the right), so each joint is the mean of the measured right value and the mirrored left
value: the mech is a machine and a symmetric rig keeps the animation and the IK honest. The residual
is printed by segment.py as BIND.

Bone names follow the existing contract (`Pelvis`, `Spine01`, `Spine02`, `Head`, `L_/R_Clavicle`,
`Upperarm`, `Forearm`, `Hand`, `Thigh`, `Calf`, `Foot`) so camera, weapon and melee code that asks
for those names keeps working.
"""

## bone: (name, parent, head, tail). Vectors in metres, Blender Z up, +Y forward.
BONES = [
    ("Root", None, (0.0, 0.0, 0.0), (0.0, 0.0, 0.80)),
    ("Pelvis", "Root", (0.0, 0.10, 8.60), (0.0, 0.05, 10.68)),
    ("Spine01", "Pelvis", (0.0, 0.05, 10.68), (0.0, 0.20, 11.90)),
    ("Spine02", "Spine01", (0.0, 0.20, 11.90), (0.0, 0.15, 13.45)),
    ("Neck", "Spine02", (0.0, 0.15, 13.45), (0.0, 0.05, 13.85)),
    ("Head", "Neck", (0.0, 0.05, 13.85), (0.0, -0.15, 15.70)),
    ("R_Clavicle", "Spine02", (0.55, -0.05, 13.30), (2.30, -0.55, 13.25)),
    ("R_Upperarm", "R_Clavicle", (2.30, -0.55, 13.25), (3.45, -0.63, 10.93)),
    ("R_Forearm", "R_Upperarm", (3.45, -0.63, 10.93), (4.31, 0.25, 8.34)),
    ("R_Hand", "R_Forearm", (4.31, 0.25, 8.34), (4.24, 0.62, 6.79)),
    ("L_Clavicle", "Spine02", (-0.55, -0.05, 13.30), (-2.30, -0.55, 13.25)),
    ("L_Upperarm", "L_Clavicle", (-2.30, -0.55, 13.25), (-3.45, -0.63, 10.93)),
    ("L_Forearm", "L_Upperarm", (-3.45, -0.63, 10.93), (-4.31, 0.25, 8.34)),
    ("L_Hand", "L_Forearm", (-4.31, 0.25, 8.34), (-4.24, 0.62, 6.79)),
    ("R_Thigh", "Pelvis", (1.23, 0.40, 8.60), (2.30, -0.25, 4.65)),
    ("R_Calf", "R_Thigh", (2.30, -0.25, 4.65), (2.90, -0.68, 2.77)),
    ("R_Foot", "R_Calf", (2.90, -0.68, 2.77), (2.95, 0.20, 0.50)),
    ("R_Toe", "R_Foot", (2.95, 0.20, 0.50), (2.95, 2.90, 0.30)),
    ("L_Thigh", "Pelvis", (-1.23, 0.40, 8.60), (-2.30, -0.25, 4.65)),
    ("L_Calf", "L_Thigh", (-2.30, -0.25, 4.65), (-2.90, -0.68, 2.77)),
    ("L_Foot", "L_Calf", (-2.90, -0.68, 2.77), (-2.95, 0.20, 0.50)),
    ("L_Toe", "L_Foot", (-2.95, 0.20, 0.50), (-2.95, 2.90, 0.30)),
    ("BackFrame", "Spine02", (0.0, -1.10, 12.60), (0.0, -2.30, 13.40)),
]

## The 7 blade drones hang off the back frame on their own bones. `mount` is the frame root they
## pivot about and `tip` is the blade point, both measured from the drone pieces' own centroids and
## extents (segment.py prints DRONE rows for each).
DRONES = [
    {"name": "Drone_1", "mount": (-1.10, -2.10, 13.10), "tip": (-7.30, -2.00, 11.40)},
    {"name": "Drone_2", "mount": (-1.30, -2.05, 13.30), "tip": (-5.40, -1.60, 9.95)},
    {"name": "Drone_3", "mount": (-1.50, -2.00, 13.60), "tip": (-6.20, -2.00, 13.60)},
    {"name": "Drone_4", "mount": (-1.20, -1.95, 13.90), "tip": (-4.25, -2.20, 15.45)},
    {"name": "Drone_5", "mount": (0.60, -2.20, 12.60), "tip": (1.90, -2.90, 11.10)},
    {"name": "Drone_6", "mount": (0.30, -2.25, 13.20), "tip": (1.20, -3.00, 14.60)},
    {"name": "Drone_7", "mount": (-0.40, -2.20, 13.40), "tip": (-2.60, -2.60, 17.40)},
]

## Weapon bones: the saber lives in the right hand and never leaves it (brief step 3), the shield on
## the left forearm. `saber_r` is the socket the melee unit reads; the bone exists so the blade can be
## keyframed with the hand.
WEAPONS = [
    ("R_Saber", "R_Hand", (4.24, 0.62, 6.79), (4.10, 1.10, 5.20)),
    ("L_Shield", "L_Forearm", (-4.10, 0.10, 9.10), (-4.90, 0.30, 8.30)),
]

## Labelled Tripo part -> the bone chain its faces are distributed over, nearest segment wins. The
## switch between two consecutive bones therefore happens on their perpendicular bisector, which is
## the "plane perpendicular to the bone at the joint" the brief asks for. Parts not listed keep their
## own single bone (see SINGLE).
REGION_CHAIN = {
    "tripo_part_0": ["Pelvis", "Spine01", "Spine02", "Neck"],     ## chest + abdomen + tassets
    "tripo_part_1": ["L_Thigh", "L_Calf", "L_Foot", "L_Toe"],
    "tripo_part_2": ["R_Thigh", "R_Calf", "R_Foot", "R_Toe"],
    "tripo_part_3": ["R_Clavicle", "R_Upperarm", "R_Forearm", "R_Hand"],
    "tripo_part_4": ["L_Clavicle", "L_Upperarm", "L_Forearm", "L_Hand"],
    "tripo_part_5": ["Neck", "Head"],                             ## head + helm crest
    "tripo_part_13": ["Pelvis"],                                  ## left hip / tasset armour
}

## Part -> the one bone that part becomes (rigid plate, no internal joint).
REGION_SINGLE = {
    "tripo_part_10": "Drone_6",
    "tripo_part_15": "Drone_5",
    "tripo_part_6": "Drone_7",
    "tripo_part_8": "BackFrame",
    "tripo_part_7": "BackFrame",
    "tripo_part_9": "Drone_1",
    "tripo_part_11": "Drone_2",
    "tripo_part_12": "Drone_3",
    "tripo_part_14": "Drone_4",
}


def bone_map() -> dict:
    """name -> {"parent", "head", "tail"} for every bone, weapons and drones included."""
    out = {}
    for name, parent, head, tail in BONES + WEAPONS:
        out[name] = {"parent": parent, "head": tuple(head), "tail": tuple(tail)}
    for drone in DRONES:
        out[drone["name"]] = {"parent": "BackFrame", "head": tuple(drone["mount"]),
                              "tail": tuple(drone["tip"])}
    return out
