"""Per-type build table for the HUSK monsters (monster-assets).

Sizes come from SPEC §7 / briefs/monster-assets.md. The Brood Titan's *fight* model is 60 m (the
lead's skyline walker is a separate 90 m scene, see TITAN_SKYLINE). `yaw` turns the raw Tripo mesh
so it faces +Y in Blender = −Z in Godot (measured, see status/monster-assets.md).
"""
from collections import OrderedDict

#: metres; `axis` is which extent of the finished mesh must hit the number (±5 % in the test).
SIZES = {
    "ripper":     {"axis": "length", "m": 6.0},    # SPEC §7 "6 m long, insectoid"
    "mantis":     {"axis": "height", "m": 14.0},
    "spitter":    {"axis": "height", "m": 12.0},
    "harrier":    {"axis": "span",   "m": 16.0},   # SPEC §7 "16 m wingspan"
    "juggernaut": {"axis": "height", "m": 22.0},
    "titan":      {"axis": "height", "m": 60.0},   # fight model (skyline walker is 90 m)
    "hive":       {"axis": "height", "m": 60.0},
}
TITAN_SKYLINE_SCALE = 1.5   # 60 m fight model x1.5 = 90 m on the distant ring (lead note)

#: Blender yaw (degrees about +Z) that turns the raw input to face +Y.
YAW = {"ripper": -90.0, "mantis": 180.0, "spitter": 0.0, "harrier": 90.0,
       "juggernaut": 180.0, "titan": 180.0, "hive": 0.0}

#: Triangle budgets: LOD0 is what the player fights, LOD1 shows past LOD_DIST_M.
TRIS = {
    "ripper":     (20000, 6000),
    "mantis":     (30000, 8000),
    "spitter":    (40000, 10000),
    "harrier":    (30000, 8000),
    "juggernaut": (45000, 12000),
    "titan":      (150000, 60000),
    "titan_skyline": (10000, 10000),
    "hive":       (60000, 15000),
}
LOD_DIST_M = 120.0
#: Texture budget per type: (albedo px, orm/normal px).
TEX = {"ripper": (2048, 1024), "mantis": (2048, 1024), "spitter": (2048, 1024),
       "harrier": (2048, 1024), "juggernaut": (2048, 1024), "titan": (4096, 2048),
       "titan_skyline": (1024, 1024), "hive": (4096, 2048)}

#: Only these cast shadows (brief): the rest are cheap enough that a shadow pass is not worth it.
SHADOW_CASTERS = ("juggernaut", "titan", "hive")

#: The look pass (lead look r1). ART.md §1 wants charcoal chitin with thin acid veins that pop
#: against warm mid-tones at every distance; measured on the user's dusk screenshot the monsters
#: were 2-4.6x too bright and half-metallic, so they reflected the warm sky and read brown.
#:   emission_energy — the vein strength written to `<type>_rig.json` (the GLB now bakes a neutral
#:     1.0, see mon_emit.EMISSION_ENERGY). Big close-up bodies take less than 80 m swarmers.
#:   metallic_cap / roughness_floor — chitin is wet and dielectric, never a mirror.
#:   rim_color / rim_gain — the acid outline that keeps a silhouette readable against the sky. The
#:     harrier flies against dusk, so its rim is the cool sky tint instead of acid.
#: `albedo_gain` is NOT here: it is measured per build (median albedo luminance -> #1B2430).
ACID_RIM = (0.608, 1.0, 0.227)
COOL_RIM = (0.561, 0.655, 0.769)
LOOK = {
    "ripper":        {"emission_energy": 2.0, "metallic_cap": 0.15, "roughness_floor": 0.35,
                      "rim_color": ACID_RIM, "rim_gain": 0.60},
    "mantis":        {"emission_energy": 2.0, "metallic_cap": 0.15, "roughness_floor": 0.35,
                      "rim_color": ACID_RIM, "rim_gain": 0.60},
    "spitter":       {"emission_energy": 2.0, "metallic_cap": 0.15, "roughness_floor": 0.35,
                      "rim_color": ACID_RIM, "rim_gain": 0.60},
    "harrier":       {"emission_energy": 1.6, "metallic_cap": 0.12, "roughness_floor": 0.40,
                      "rim_color": COOL_RIM, "rim_gain": 0.75},
    "juggernaut":    {"emission_energy": 2.0, "metallic_cap": 0.18, "roughness_floor": 0.35,
                      "rim_color": ACID_RIM, "rim_gain": 0.55},
    "titan":         {"emission_energy": 2.2, "metallic_cap": 0.18, "roughness_floor": 0.35,
                      "rim_color": ACID_RIM, "rim_gain": 0.55},
    "titan_skyline": {"emission_energy": 2.2, "metallic_cap": 0.18, "roughness_floor": 0.35,
                      "rim_color": ACID_RIM, "rim_gain": 0.80},
    "hive":          {"emission_energy": 1.1, "metallic_cap": 0.10, "roughness_floor": 0.40,
                      "rim_color": ACID_RIM, "rim_gain": 0.45},
}
#: Hit flash and attack tell (lead r5 item 2). `flash_energy` used to be the shader default of 4.0
#: for every type — a flat white add 2.4x the monster's own emission, so a missile salvo turned a
#: mantis into a beige ghost. It is per type now, and the shader weights it toward the rim and the
#: veins instead of the whole carapace. The tell only reaches the emission mask plus a thin rim.
FLASH = {
    "ripper": 1.00, "mantis": 0.90, "spitter": 0.95, "harrier": 1.05,
    "juggernaut": 0.85, "titan": 0.75, "titan_skyline": 0.75, "hive": 0.80,
}
#: The tell only reaches texels the emission mask covers plus a thin rim, so it can be driven hard
#: without touching the carapace: `probe_flash` measures the median at 1.02-1.33x of neutral (gate
#: 1.5x) while the veins and cores visibly flare. At 2.6 the tell was correct but unreadable.
TELL = {
    "ripper": 5.0, "mantis": 5.0, "spitter": 5.0, "harrier": 5.0,
    "juggernaut": 5.0, "titan": 5.0, "titan_skyline": 5.0, "hive": 5.0,
}
#: The hive's four pod bulbs glow this much hotter than its veins, and `pod_mask_tex` (RGBA, one
#: channel per pod, written by mon_hive) is what the shader multiplies — so flow can burst a pod
#: and its light goes out with it (look r1, fix 3).
POD_BOOST = 2.3
POD_MASK_PX = 1024
POD_MASK_DILATE = 3

#: Clips that are *meant* to leave the floor (lead r5 item 3). They get one vertical offset for the
#: whole clip from `mon_ground`, so the arc survives but its lowest point still lands on y = 0;
#: every other grounded clip is pinned frame by frame. The harrier flies, so it gets neither.
GROUND_CONST = ("leap", "dive", "death", "death_fall", "climb_over", "beam_breath", "summon")
#: Which input carries the rig. "tripo" = rigged.glb has the skeleton, "none" = we build one.
RIG_SOURCE = {"ripper": "tripo", "mantis": "tripo", "juggernaut": "tripo", "titan": "tripo",
              "spitter": "own", "harrier": "own", "hive": "static"}

#: Clips every type must end up with, in the brief's order. Ids Tripo already gives us are kept;
#: the rest are scripted in mon_anims.py.
REQUIRED = OrderedDict([
    ("ripper", ["idle", "walk", "run", "scuttle", "leap", "bite", "hit", "death"]),
    ("mantis", ["idle", "walk", "run", "slash_1", "slash_2", "slash_3", "grab", "sidestep_l",
                "sidestep_r", "threat", "hit", "stagger", "death"]),
    ("spitter", ["idle", "walk", "scuttle", "fire", "hit", "death"]),
    ("harrier", ["fly", "glide", "dive", "strafe", "hit", "death"]),
    ("juggernaut", ["idle", "walk", "charge_run", "charge", "ground_slam", "swipe", "roar", "hit",
                    "stagger", "death"]),
    ("titan", ["idle", "walk", "roar", "stomp", "swipe", "beam_breath", "summon", "hit", "stagger",
               "death", "tail_sweep", "climb_over", "phase_roar", "core_break", "death_fall"]),
    ("titan_skyline", ["idle", "walk", "roar"]),
])

#: Locomotion loops: clip id -> the state name EnemyBase drives with set_locomotion().
LOCOMOTION = {
    "ripper": {"idle": "idle", "walk": "walk", "run": "run"},
    "mantis": {"idle": "idle", "walk": "walk", "run": "run"},
    "spitter": {"idle": "idle", "walk": "walk", "run": "walk"},
    "harrier": {"idle": "glide", "walk": "fly", "run": "fly", "fly": "fly", "glide": "glide"},
    "juggernaut": {"idle": "idle", "walk": "walk", "run": "charge"},
    "titan": {"idle": "idle", "walk": "walk", "run": "walk"},
    "titan_skyline": {"idle": "idle", "walk": "walk", "run": "walk"},
}

#: The bones the stride measurement treats as ground contacts (lead r1: "the lowest bone of each
#: leg"). Automatic lowest-leaf detection cannot do this job: the titan's tail tip hangs lower than
#: its toes, and a biped's calf twist bones and knuckle claws sit in the same band as its feet
#: (`diag_feet.py` is the evidence). One representative bone per contact limb — a forefoot's other
#: toes are the same contact and would only weight it twice.
FOOT_BONES = {
    "ripper": ("tripo::0_Left_Limb_4", "tripo::1_Right_Limb_4", "bone_23", "bone_34"),
    "mantis": ("L_ToeBase", "R_ToeBase"),
    "spitter": ("LegFL_2", "LegFR_2", "LegBL_2", "LegBR_2"),
    "harrier": ("LegL_1", "LegR_1"),          # never planted — the harrier flies
    "juggernaut": ("L_ToeBase", "R_ToeBase"),
    "titan": ("L_ToeBase", "R_ToeBase"),
    "titan_skyline": ("L_ToeBase", "R_ToeBase"),
}

#: The body reference for the root-space measurement, most preferred first. Tripo puts the walk's
#: travel on the pelvis, not on the technical root bone, so the pelvis is what a planted foot is
#: measured against.
ROOT_PREFERENCE = ("Hip", "Pelvis", "tripo::Root", "Root", "Spine_0", "BoneRoot")

#: Ground speeds `game/enemies/types.gd` drives each type at (mirror of that table; the model has to
#: carry exactly these). Only used to size the playback-scale ceiling and the gait ladder.
GAME_SPEED = {"ripper": 30.0, "mantis": 24.0, "spitter": 18.0, "harrier": 55.0,
              "juggernaut": 20.0, "titan": 14.0, "titan_skyline": 14.0}

#: Residual foot slide each type is allowed at its gameplay speed (lead r3; a swarmer's legs are a
#: blur at 30 m/s whatever we do, so it gets the looser bar).
SLIDE_TOLERANCE = {"ripper": 0.25}
SLIDE_DEFAULT = 0.15
#: `brain.gd` drives `walk` at this fraction of the move speed while patrolling, so a gait has to be
#: playable that slowly too — the titan's 17.5 m/s walk needs a 0.28x playback to patrol at 4.9 m/s.
PATROL_FRACTION = 0.35
#: The lowest playback any clip may be slowed to, whatever a rig asks for.
SPEED_SCALE_FLOOR = 0.25

#: Gait ladders: per locomotion state, the clips the model may pick from, slowest first. The model
#: plays the first one whose clean maximum covers the real ground speed and the last one above it,
#: so a walking patrol keeps the Tripo loop and a 30 m/s chase switches to the authored scuttle
#: without the enemies unit having to change state (lead r3).
GAITS = {
    "ripper": {"idle": ["idle"], "walk": ["walk", "run", "scuttle"], "run": ["run", "scuttle"]},
    "mantis": {"idle": ["idle"], "walk": ["walk", "run"], "run": ["walk", "run"]},
    "spitter": {"idle": ["idle"], "walk": ["walk", "scuttle"], "run": ["walk", "scuttle"]},
    "harrier": {"idle": ["glide"], "walk": ["fly"], "run": ["fly"], "fly": ["fly"],
                "glide": ["glide"]},
    "juggernaut": {"idle": ["idle"], "walk": ["walk", "charge_run"],
                   "run": ["walk", "charge_run"]},
    "titan": {"idle": ["idle"], "walk": ["walk"], "run": ["walk"]},
    "titan_skyline": {"idle": ["idle"], "walk": ["walk"], "run": ["walk"]},
}

#: Every action id `game/enemies/**` can ask for, mapped onto the clip this type actually has
#: (lead r3). Ids the type has as a clip of the same name do not need an entry. The build drops any
#: entry whose target is missing and says so, so a rename can never leave a silent dead id.
ACTIONS = {
    "ripper": {"attack": "bite", "attack_1": "bite", "attack_2": "bite", "stagger": "hit",
               "hit_light": "hit"},
    "mantis": {"attack": "slash_1", "attack_1": "slash_1", "attack_2": "slash_2",
               "attack_3": "slash_3", "sidestep": "sidestep_l", "hit_light": "hit"},
    "spitter": {"attack": "fire", "attack_1": "fire", "lob": "fire", "chaff": "fire",
                "stagger": "hit", "hit_light": "hit"},
    "harrier": {"attack": "strafe", "attack_1": "strafe", "stagger": "hit", "hit_light": "hit"},
    "juggernaut": {"attack": "swipe", "attack_1": "swipe", "attack_2": "ground_slam",
                   "slam": "ground_slam", "hit_light": "hit"},
    "titan": {"attack": "swipe", "attack_1": "swipe", "hit_light": "hit"},
    "titan_skyline": {"climb_over": "walk", "phase_roar": "roar", "core_break": "roar"},
}

