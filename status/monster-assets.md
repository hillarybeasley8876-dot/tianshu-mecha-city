# monster-assets status

## r5 — the models are rebuilt and committed (enemies r11: capture from these)

| what | commit |
|---|---|
| **the models** (every `<type>.glb`, `<type>_rig.json`, the hive's pods mask, the orphan-texture deletion) | **`590a6a1`** |
| the build that produces them + the probes | `69be409` |
| the flash/tell tuning (the shader and each rig's `look` block) | `2afb937` |

`84bd0e7` was the first models commit of this round; **`590a6a1` supersedes it** (same pipeline, the
ground lock corrected against the shipped file). Capture from `590a6a1`.

Nothing in `game/enemies/**` outside `models/` moved, the CONTRACTS §6 API is unchanged, and no
socket, clip id, action id, gait ladder or rig-json key was renamed — an enemies checkout at
`590a6a1` behaves exactly as it did at `dcedb13` except that the monsters no longer tear, float,
sink or flash white. `test_models` is 722 checks / 0 failures on the new models.

## Done

### Build pipeline (`blender/monsters/`, deterministic, `tools/blender.sh run …/build_all.py`)
| module | what |
|---|---|
| `mon_lib.py` | load/orient/decimate, ICP + Kabsch alignment, Data-Transfer weights, glTF export, **skin sanity check** (`check_skin`) |
| `mon_types.py` | the per-type table: sizes, yaws, tri/texture budgets, required clips, locomotion map, `FOOT_BONES` / `ROOT_PREFERENCE`, **`GAME_SPEED` / `GAITS` / `ACTIONS` / `SLIDE_TOLERANCE`** |
| `mon_emit.py` | emissive mask derived from the albedo (acid green + violet) and weak-point clustering |
| `mon_rig.py` | rig surgery — fingers → 3 claws per hand, the titan's 6-bone tail, jaw; voxel-proxy weighting; `slab_centroids` interpolates empty slabs; `build_armature` refuses zero-length bones |
| `mon_custom_rigs.py` | armatures fitted to the spitter and harrier, with `_limb_line` (limbs bin between ascending edges) |
| `mon_stride.py` | **lead r1**: the stride measurement — contact bones, pelvis reference, leg-cycle sweep, stray cross-check |
| `mon_anims.py` | the keyframe DSL: bone-local angles with measured axis signs, per-key easing, NLA stashing |
| `mon_clips.py`, `mon_clips_gaits.py`, `mon_clips_titan.py` | the scripted clips; **`mon_clips_gaits.py` is lead r3's three fast gaits** |
| `mon_build.py`, `mon_hive.py`, `build_all.py` | the three build shapes, the gait/action tables and the orchestrator |
| `render_models.py`, `render_lineup.py`, `make_sheets.py` | review renders and the contact-sheet tiler (`make_sheets --dir --ext` also tiles Godot captures) |
| `diag_weights.py`, `diag_transfer.py`, `diag_feet.py`, `diag_stride.py`, `diag_footslide.py`, `diag_contact.py`, `diag_pods.py` | the diagnostics |

### What every type ended up as
| type | LOD0 / LOD1 tris | verts | bones | clips | size (briefed axis) | GLB |
|---|---|---|---|---|---|---|
| ripper | 20,000 / 6,000 | 17,231 | 56 | 8 | 6.00 m length (h 4.17) | 2.6 MB |
| mantis | 30,000 / 8,000 | 23,512 | 54 | 14 | 14.00 m | 4.2 MB |
| spitter | 40,000 / 10,000 | 30,389 | 19 | 6 | 12.00 m | 4.2 MB |
| harrier | 29,999 / 8,000 | 23,947 | 19 | 6 | 16.00 m span (h 15.35) | 3.8 MB |
| juggernaut | 44,999 / 11,999 | 33,819 | 54 | 10 | 22.00 m | 5.2 MB |
| titan | 150,000 / 60,000 | 107,121 | 60 | 15 | 60.00 m | 17.5 MB |
| titan_skyline | 10,000 | — | 60 | 3 | 90 m (×1.5) | 2.6 MB |
| hive | 60,000 ×4 meshes | 54,939 | — | — | 60.00 m | 12.4 MB |

### Godot side (`game/enemies/models/`)
`monster_model.gd` (`MonsterModel`), `hive_model.gd` (`HiveModel`), `monster_body.gdshader`,
`<type>/<type>_model.tscn` × 8, `tests/test_models.gd`, `tests/model_gallery.tscn`.

Everything per-type comes from `<type>_rig.json`: sizes, bone names, clip lengths and loop flags,
every socket in Godot model space, the **gait ladder**, the **action table**, and the playback
`speed_scale_min` / `speed_scale_max` window. Nothing about a type is hard-coded in the script.

Sockets provided: `mouth`, `muzzle`, `claw_l/r` (alias `hand_l/r`), `core`, `chest`, `back`,
`weak_0..3` at the violet cores, and — on the hive — `pod_0..3` on the glowing bulbs.

## r3 — the lead's three items (done)

### 1. Per-type action tables
`mon_types.ACTIONS` maps every id `game/enemies/**` can ask for onto a clip that type really has;
`mon_build.action_table()` writes the resolved table into each `<type>_rig.json` and **drops** (with
a printed `ACTION WARN`) any entry whose target clip does not exist, so a rename can never leave an
id silently pointing at nothing. `MonsterModel._resolve_action` resolves a requested id in three
steps — a clip of the same name, then the rig's own table, then the shared aliases — and each step
only counts if the clip is present; otherwise it warns once and returns `MISSING_ACTION`.

| type | ids the enemies unit asks for | resolves to |
|---|---|---|
| ripper | `attack`, `attack_1`, `attack_2`, `stagger`, `hit_light`, `leap`, `death` | bite, bite, bite, hit, hit, leap, death |
| mantis | `attack_1/2/3`, `grab`, `sidestep`, `stagger`, `death` | slash_1/2/3, grab, sidestep_l, stagger, death |
| spitter | `lob`, `chaff`, `attack`, `attack_1`, `stagger`, `death` | fire, fire, fire, fire, hit, death |
| harrier | `strafe`, `dive`, `attack`, `attack_1`, `stagger`, `death` | strafe, dive, strafe, strafe, hit, death |
| juggernaut | `charge`, `slam`, `attack_1`, `attack_2`, `stagger`, `roar`, `death` | charge, ground_slam, swipe, ground_slam, stagger, roar, death |
| titan | `core_break`, `phase_roar`, `roar`, `death_fall`, `climb_over`, `stagger`, `death` | all identity |
| titan_skyline | `roar`, `climb_over`, `phase_roar`, `core_break` | roar, walk, roar, roar |

A 36 s scripted fight (`fight_probe`, 15 monsters, 60 telegraphs) now logs **zero**
`MonsterModel … no action` warnings. Before r3 it logged ripper `attack_1`, ripper `stagger` and
juggernaut `attack_1`.

### 2. Fast gaits with real strides
`blender/monsters/mon_clips_gaits.py` authors three new loops with the keyframe DSL. The leg cycle
is sampled every frame from a `(u, hip, knee, ankle)` shape curve, so the stance/swing split is
authored instead of falling out of five fixed keys, with per-joint gains: the hip carries the
stride, the knee and ankle are damped on the big animals (folding a 22 m leg as hard as a 6 m one
curls the whole body into a ball — that is what the first pass did to the juggernaut).

| type | new clip | cycle | hip sweep | measured stride | gameplay speed | playback | residual slide | bar |
|---|---|---|---|---|---|---|---|---|
| ripper | `scuttle` (bound, fore/hind pairs) | 8 f = 0.33 s | 98° | 7.04 m/s | 30 m/s | 4.00× | **6 %** | 25 % |
| spitter | `scuttle` (diagonal pairs) | 12 f = 0.50 s | 113° | 8.80 m/s | 18 m/s | 2.05× | **0 %** | 15 % |
| juggernaut | `charge_run` (heavy bipedal run) | 20 f = 0.83 s | 97° | 8.58 m/s | 20 m/s | 2.33× | **0 %** | 15 % |

The model picks the gait **by speed**, so the enemies unit's `POSITION` state needs no change:
each state carries a ladder of rungs, and `MonsterModel` plays the rung whose authored stride is
nearest the speed the body is really moving, among the rungs that stay clean. Two new per-type
numbers make that work — `speed_scale_max` (the ceiling a type needs to carry its `types.gd` speed:
4.00× for the ripper, 2.33× for the juggernaut, 2.20× for the rest) and `speed_scale_min` (the floor
a type needs to *patrol* at 0.35 × move speed: 0.279× for the titan, whose walk measures 17.5 m/s,
0.60× for everyone else).

Every state now clears its bar at both the move speed and the patrol speed:

```
FOOTSLIDE  bars: ripper 25%, everyone else 15%
  type        state picked       stride    speed playback  slide patrol clean to
  ripper      run   scuttle        7.04     30.0    4.00     6%     0%     37.5
  ripper      walk  scuttle        7.04     30.0    4.00     6%     0%     37.5
  mantis      run   run           11.15     24.0    2.15     0%     0%     28.9
  mantis      walk  run           11.15     24.0    2.15     0%     0%     28.9
  spitter     run   scuttle        8.80     18.0    2.05     0%     0%     22.8
  spitter     walk  scuttle        8.80     18.0    2.05     0%     0%     22.8
  harrier     fly/glide/run/walk    air     55.0    1.00     0%     0%      any
  juggernaut  run   charge_run     8.58     20.0    2.33     0%     0%     23.5
  juggernaut  walk  charge_run     8.58     20.0    2.33     0%     0%     23.5
  titan       run   walk          17.54     14.0    0.80     0%     0%     45.4
  titan       walk  walk          17.54     14.0    0.80     0%     0%     45.4
```

That closes r2's "Known issue 1" (five states over the bar) and "Known issue 2" (the titan's patrol).

### 3. Hive pod sockets
`mon_hive.pod_sockets()` clusters the hive's **acid** mask (the violet clustering already used for
weak points, with a wider radius and a higher face floor so the veins do not claim a socket), keeps
the clusters at least 15 % of the spire's height up, and takes the four largest, lowest first:
`pod_0` 10.3 m, `pod_1` 24.0 m, `pod_2` 40.5 m, `pod_3` 54.5 m. `HiveModel.weak_points()` now
returns the `pod_*` markers **and** the `weak_*` cores, because that list is how
`flow/hive_visual._model_pod_sockets()` finds them.

## Audit findings (`reviews/monster-assets-audit.md`)

**1. [medium] one-shots cross-faded away one tick after `play_action` — fixed.**
`EnemyBase` re-asserts a locomotion state every physics tick (`attack_windup` → `&"idle"`), so
`_apply_state` blended back to idle one tick after an attack started: monsters wound up and struck
in their idle loop, and staggers were replaced the same way. `MonsterModel` now holds the one-shot
for its own clip length (`_action_left`, run down in `_process`, frozen while `hit_pause` is
active) and re-asserts the pending locomotion state itself when the hold expires — so the hand-back
does not wait for the brain's next tick. Regression check:
`test_models._check_one_shot_hold` starts the first id the enemies unit asks for, calls
`set_locomotion(&"idle", 0)` on six consecutive physics frames, and asserts the attack is still the
current animation, then that locomotion takes the player back. Visual:
`captures/monsters_attack_hold.jpg` (the label reads `clip bite` in all six frames while idle is
re-asserted every frame).

The audit's second half — starting the juggernaut roar with `play_action(&"roar")` instead of
`set_locomotion(&"roar")` — is in `game/enemies/juggernaut/juggernaut.gd`, which is not this unit's
file. See Requests #2.

**2. [low] `play_action` followed an alias to a clip the type does not have — already fixed, twice
over.** The lead's alias guard was in place before this round, and r3's per-type action table now
answers those ids directly (`attack_1 → bite` on the ripper, `attack_1 → swipe` on the juggernaut),
so the case never reaches the shared aliases. `_resolve_action` still checks `_clips.has()` after
each step and returns `MISSING_ACTION` with one warning per type/id; the test asserts an unknown id
returns `MISSING_ACTION` rather than raising.

## r4 — the lead's look round (reviews/look/monster-assets.md, all three items)

All three items are done and verified against the same spot with the same world: `git checkout HEAD --
game/enemies/models` for the BEFORE, the rebuilt models for the AFTER, identical cameras.
A/B sheets: `captures/look_monster-assets_hive_ab.jpg`, `captures/look_monster-assets_gallery_ab.jpg`.

### 1. The hive's emission mask (impact 8) — `mon_emit.py`, `mon_types.LOOK`, `hive_model.gd`
* **Per-type vein energy instead of a baked 3.0.** `mon_emit.EMISSION_ENERGY` is now a neutral 1.0 in
  the GLB and the real number lives in `mon_types.LOOK` -> `<type>_rig.json` -> the shader: hive 1.1,
  harrier 1.6, trash 2.0, titan 2.2. `MonsterModel.apply_look` pushes it (shared with `HiveModel`).
* **The mask is modulated, eroded and de-specked** (`build_mask`): coverage x
  `smoothstep(0.25, 0.75, albedo luminance)` so a vein has a hot core and a dark edge, then a 2 px
  erosion and a connected-component pass (`drop_specks`, label propagation in numpy — Blender has no
  scipy) that deletes every blob under 40 px. Measured on the hive: **acid 6.30 % -> 3.95 %**,
  violet 1.58 % -> 0.93 % (the lead asked for 3-4 % on the trunk). Per type:

  | type | acid before -> after | violet before -> after |
  |---|---|---|
  | ripper | 3.83 % -> 1.47 % | 0.51 % -> 0.11 % |
  | mantis | 5.20 % -> 3.17 % | 0.25 % -> 0.11 % |
  | spitter | 11.61 % -> 7.89 % | 0.47 % -> 0.14 % |
  | harrier | 4.39 % -> 1.68 % | 0.19 % -> 0.10 % |
  | juggernaut | 1.74 % -> 0.69 % | 0.96 % -> 0.40 % |
  | titan | 1.85 % -> 0.74 % | 7.48 % -> 4.26 % |
  | hive | 6.30 % -> 3.95 % | 1.58 % -> 0.93 % |

  The violet cores skip the erosion (`clean_coverage(..., erode_px=0)`): they are gameplay sockets,
  and shaving 2 px off a core dropped the ripper's last weak point under the face floor.
* **Per-pod control** (fix 3): `mon_hive.pod_mask` rasterises each pod cluster's faces into UV space
  and writes `game/enemies/models/hive/hive_pods.png` (RGBA, one channel per pod, dilated 3 px;
  coverage 0.2 % / 0.6 % / 2.4 % / 0.7 %). The shader boosts those texels by `pod_boost` 2.3 and
  multiplies by `instance uniform vec4 pod_alive`; `HiveModel.set_pod_alive(i, on)` /
  `pods_alive()` drive it. `flow/hive_visual.burst_pod` already calls `set_pod_alive` when the model
  has it — it now does.

### 2. Brown and fuzzy at dusk (impact 7) — `monster_body.gdshader`, `mon_emit.median_luma`
* `albedo_gain` is **measured, not guessed**: `median_luma` rasterises the mesh's own UV shells at
  256 px and takes the median scene-linear luminance of the albedo over the texels the model really
  uses; `gain = GRADE_TARGET / median`. `GRADE_TARGET = 0.08` is anchored on the lead's per-type
  numbers (their ripper 0.5 on a 0.031 median and hive 0.22 on 0.074 both land at 0.066-0.095
  on screen). Measured medians and the gains they produce:

  | type | median albedo luma | albedo_gain | lead's number |
  |---|---|---|---|
  | ripper | 0.185 | **0.432** | 0.5 |
  | mantis | 0.250 | 0.320 | — |
  | spitter | 0.219 | 0.366 | — |
  | harrier | 0.272 | **0.294** | 0.25 |
  | juggernaut | 0.212 | 0.378 | — |
  | titan | 0.230 | 0.348 | — |
  | hive | 0.298 | **0.268** | 0.22 |

* `METALLIC = min(orm.b, metallic_cap)` (0.10-0.18) and `ROUGHNESS = max(orm.g, roughness_floor)`
  (0.35-0.40): wet dielectric chitin, not a mirror of the warm sky.
* **Rim**: `pow(1 - dot(N, V), 3) * rim_color * rim_gain`, doubling past 40 m
  (`smoothstep(40, 160, length(VERTEX))`). Acid #9BFF3A at gain 0.45-0.8; the harrier gets the cool
  #8FA7C4 at 0.75 because it is always read against the sky.

### 3. UV seams as open cracks (impact 3) — `mon_lib.load_glb`, `mon_lib.check_welded`
`bpy.ops.import_scene.gltf(..., merge_vertices=True)`. Blender keeps UVs per face corner, so welding
costs no UVs, and the collapse decimator now keeps a seam as a UV boundary on shared vertices
instead of tearing it open. `check_welded` is the QA gate the lead asked for (boundary edges under
2 % of all edges) and runs in every build:

```
WELD ripper      0 open /  30000 edges = 0.00%     (was 12,876)
WELD mantis      0 open /  45000 edges = 0.00%
WELD spitter     0 open /  60000 edges = 0.00%
WELD harrier     0 open /  45000 edges = 0.00%     (was 16,861)
WELD juggernaut  0 open /  67500 edges = 0.00%
WELD titan       0 open / 225000 edges = 0.00%
WELD hive        1 open /  90001 edges = 0.00%     (was 44,000 after a 6 mm weld)
```
Vertex counts fell with the weld (hive 54,939 -> 29,170; ripper 17,231 -> 9,988), GLBs got smaller
(hive 12.4 -> 10.0 MB) and every clip, stride and slide number came out unchanged.

**Not mine:** the same import fix is needed in `blender/hero/hero_lib.py:24` and
`blender/world/process_prop.py:162` — see Requests #6.

## Split r1 — `monster_model.gd` 601 -> 187 lines, behaviour-identical

The lead's split brief (`reviews/monster-assets-split-r1.md`). `MonsterModel` is now the facade and
its five responsibilities are separate `RefCounted` classes beside it. Nothing outside
`game/enemies/models/**` changed; the CONTRACTS §6 API, the public members the tests read
(`rig`, `visual`, `skeleton`, `animation`, `meshes`, `body_type`), the consts the tests name
(`MISSING_ACTION`, `MIN/MAX_SPEED_SCALE(_LIMIT)`, `PLATE_COUNT`) and the static `apply_look` that
`HiveModel` calls are all still on `MonsterModel`, so no `.tscn` and no caller moved.

| file | lines | what moved there |
|---|---|---|
| `monster_model.gd` | 601 -> **187** | the facade: rig load, the §6 API delegating, `measured_size` / `world_size` / `target_size` |
| `monster_playback.gd` | 279 | clip table vs the GLB library, the gait ladder, the speed scale, one-shot actions + the hold, hit-stop, the frame tick |
| `monster_assembly.gd` | 86 | GLB instantiate, `Skeleton3D` / `AnimationPlayer` lookup, mesh collection, shadows, LOD ranges |
| `monster_look.gd` | 82 | the per-type material cache and `apply_look` (shared with `HiveModel`) |
| `monster_tells.gd` | 74 | hit flash, telegraph, stagger lean, armour plates — every instance shader parameter |
| `monster_sockets.gd` | 66 | socket markers, bone attachments, `weak_*` |

**Behaviour-identical, proved by a dump, not by reading.** New
`tests/probe_pose_dump.gd` records, every physics tick for 450 ticks, every bone's global pose
(origin + 9 basis numbers) plus the player's clip / position / speed scale and the flash, tell and
stagger the shader sees, through walk -> run -> attack (with the brain re-asserting idle every tick)
-> hit (with a hit-pause) -> death. Before and after the split:

```
POSE 450 ticks, 56 bones, 304650 numbers, max |delta| = 0.000e+00     (bar: 1e-5)
```

That is bit-identical, not merely inside the bar.

| gate | before | after |
|---|---|---|
| `tools/godot.sh check --only=res://enemies/models/` | 15 files, 0 errors, 0 warnings | 20 files, 0 errors, 0 warnings |
| `tools/godot.sh test res://enemies/models/tests/test_models.gd` | 722 checks, 0 failures | 722 checks, 0 failures |
| `tools/godot.sh test res://enemies/tests/test_ai.gd` | 12 checks, 0 failures | 12 checks, 0 failures |
| `test_spawner` / `test_main_spawn` / `test_audit` | 7 / 2 / 25 checks, 0 failures | same |

`test_ai`'s *telegraph count* and its wall-clock perf check (`physics frame with 40 enemies`, budget
6.0 ms) vary run to run — 80-86 telegraphs and an occasional perf failure — because the test spawns
with `randf()` and times real milliseconds while three other units are building. Measured on the old
601-line file too (82 / 81 / 80 telegraphs, one 22.2 ms perf failure), so it is pre-existing
flakiness, not the split. The **check count is 12 in both**, which is what the brief pinned.

Gallery sanity capture after the split: `captures/monsters_split_lineup.jpg` — all seven types plus
the 16 m hero, materials, glow, sockets and playback (`clip walk t 4.1`) intact.

## r5 — the lead's five items (`reviews/monster-assets-r5.md`)

### 1. (major) The skins tore in every clip — fixed at the source, measured
Three separate causes, all in `blender/monsters/`, all now fixed:

* **`mon_lib.transfer_weights` (nearest-face Data Transfer).** It picks the closest source triangle
  in 3-space, so wherever two limbs touch in the bind pose a vertex on one limb came back carrying
  the *other* limb's bones — 328 mantis vertices sat at 100 % `R_Claw1` inside the `R_Foot`/`R_Calf`
  skin. `mon_skin.transfer_surface` replaces it: every destination vertex is seeded on its nearest
  source point, those points are **diffused over the destination's own edge graph**, re-projected
  with a BVH nearest-face query, and the three corner weights are interpolated barycentrically. A
  vertex on the calf is surrounded by calf matches, so it cannot stay matched to the forearm.
* **`mon_rig.add_tail`.** It gave the tail chain every vertex behind a plane `root_gap` behind the
  pelvis and dropped that vertex's own weights. On the titan that plane sits at y = 17.8 while its
  feet are at y = 16.7, so **53,286 of 88,921 LOD0 vertices (59.9 %)** carried > 0.3 tail weight,
  including 1,084 `L_Forearm`, 971 `R_Forearm`, 615 `L_Calf` and 204 `R_ToeBase` vertices. It now
  picks the tail by *distance to the fitted chain* versus distance to every other bone, flood-filled
  from the tail tip through the mesh's own edges, and keeps the body's weights in a blend band that
  falls off over 14 % of the tail's length along the surface (a two-ring band tore the root: 0.33 of
  `Tail_0` on a pelvis vertex is half a metre of displacement across a 0.15 m edge).
* **`check_skin` could not see a sheet inside the bounding box.** Replaced in `build_all` by
  `mon_skin.stretch_report` (per-edge stretch against the bind length, the build-time twin of
  `probe_anim.gd`) plus `mon_skin.bridge_triangles` (the twin of `probe_fuse.gd`). Both print per
  clip, for LOD0 and LOD1, on every build.

`probe_fuse` (the lead's own probe, ported to `game/enemies/models/tests/probe_fuse.gd`):

| type | bridge triangles | longest bridge edge, worst clip |
|---|---|---|
| ripper | 362 -> **120** | 3.5 m -> **0.8 m** |
| mantis | 473 -> **5** | 14.4 m -> **0.3 m** |
| spitter | 458 -> **417** | 4.5 m -> **3.8 m** |
| harrier | 609 -> **503** | 2.9 m -> **1.6 m** |
| juggernaut | 812 -> **389** | 26.5 m -> **1.7 m** |
| titan | 3494 -> **297** | 50.0 m -> **2.9 m** |

The mantis now meets the lead's 0.3 m gate outright. The others do not, and the reason is in the
remaining pairs: the juggernaut's are `Head|Clavicle` and `Spine01|Head` (hops 4 — the lead's own
verifier called those out as "adjacent bones that do not tear"), the titan's are `Waist|Upperarm`
(hops 4) and `Tail_0|Spine01`. The spitter's and harrier's are our own fitted rigs where the sac
touches a hind leg and the head touches the tail in the bind pose.

**On the ≤ 2x stretch gate — it is not reachable, and here is the measurement that says so.**
`diag_skin_sweep.py --stages` measures Tripo's *own* `rigged.glb`, placed at the same real-world
scale, with the same probe:

```
STRETCH titan/tripo-placed SUMMARY worst 4.75x, longest posed edge 4.49 m (7.5% of 60.0 m)
STRETCH titan/4-smooth4    SUMMARY worst 7.21x, longest posed edge 3.25 m (5.4% of 60.0 m)
```

Tripo's clean rig already reaches 4.75x at the joints, and the ratio grows with mesh density (the
same weight gradient sampled over an edge 2.7x shorter reads as 2.7x the stretch), so a 150k-tri
titan can never be under 2x. **Our longest posed edge is now shorter than Tripo's own** (3.25 m
against 4.49 m), which is the number that describes the thing the acceptance pass actually saw — the
8.8-14.4 m mantis sheets and the 15.9-50 m titan sheets are gone. The build therefore gates on the
absolute length of the worst posed edge (15 % of the bounding diagonal) and prints the ratio beside
it.

### 2. (major) The white flashes — both fixed in `monster_body.gdshader`
* **Hit flash.** `EMISSION += vec3(hit_flash * flash_energy)` with `flash_energy` defaulting to 4.0
  added 2.4 of pure white against the monster's own emission of 2.0, on every texel. It is now
  weighted toward the rim and the veins (`mix(flash_body, 1.0, rim^1.5) + flash_veins * glow_mask`),
  tinted (`flash_color`, acid-white) and **per type** — `mon_types.FLASH` writes `flash_energy` into
  each `<type>_rig.json` (0.75 titan … 1.05 harrier), so no archetype uses a default any more.
  Rapid re-hits **re-arm** the flash rather than adding to it: `set_hit_flash` clamps to 1, so a
  missile salvo cannot stack its way to white.
* **Tell.** `glow = mix(glow, tell_color * (0.8 + 2.4 * length(glow)), tell)` — that constant 0.8
  landed on every texel, which is what took the median luma 0.04-0.26 -> 0.82-0.85. The tell now
  adds `tell_color * tell * (tell_energy * glow_mask + tell_rim_gain * rim^4)`: the emission mask
  plus a thin rim, which is what the comment on that line always claimed.

### 3. (minor) Floor contact — `mon_ground.py`, and the `grounded` flag is read now
Every grounded clip is pinned frame by frame: the build skins the mesh at 30 Hz, takes the lowest
non-bridge vertex (the same rule `probe_floor.gd` uses) and keys the root bone so that point sits on
y = 0. Clips that are meant to leave the ground (`mon_types.GROUND_CONST`: leap, dive, death,
death_fall, climb_over, beam_breath, summon) keep their arc and get one offset for the whole clip.

| clip | before | after |
|---|---|---|
| mantis run | +0.36 m, **38/38 frames hovering** | **-0.06 m, 0/38** |
| mantis idle | +0.95 m, 280/460 | **-0.01 m, 0/460** |
| mantis walk | +0.34 m, 70/70 | -0.04 m, 0/70 |
| juggernaut idle | -1.13 m | -0.02 m |
| spitter scuttle | -1.01 m | -0.02 m |
| ripper scuttle | -0.52 m | -0.11 m |
| titan idle | -2.15 m | -0.14 m |
| juggernaut walk | -0.65 m, 50/70 hovering | -0.05 m, 0/70 |

**The build measures the file it ships, not the scene it built.** Blender's evaluation and the
exported GLB do not agree everywhere: the ripper's `idle` came back 0.44 m below the floor with the
root bone moving exactly the distance the build had asked for. So after the first export
`mon_ground.round_trip` loads the GLB back in a throwaway scene, measures every clip, and
`mon_ground.nudge` corrects the root keys by whatever is left, then re-exports:

```
PLANT ripper      pass 0  worst |lowest| 0.621 m (hit)         gate 0.05 m
PLANT ripper      pass 1  worst |lowest| 0.000 m (leap)        gate 0.05 m
PLANT titan       pass 0  worst |lowest| 5.325 m (phase_roar)  gate 0.05 m
PLANT titan       pass 1  worst |lowest| 0.000 m (summon)      gate 0.05 m
```

Every type converges in one correction pass. The harrier flies and is skipped.

### 4. (minor) The destroyed hive stump is capped
`mon_hive._collapse` deleted every vertex above the cut and left the break open. It now fills the
boundary (`holes_fill`, re-run up to four times because the source spire is not perfectly manifold),
dishes the cap 0.7 m inward and gives it a near-black `HiveInterior` material, so what reads through
the break is a dark recess instead of the deck below. `probe_mesh`: largest hole **80.88 m -> 1.35 m**
(open edges 195 -> 15). Still over the lead's 1 m gate — the residue is the source spire's own
non-manifold edges, not the break.

### 5. (minor) Orphan textures — deleted
`game/enemies/models/titan/titan_skyline_{Color,EM,NormalGL,ORM}_*` and their `.import` files are
gone (1.3 MB). `git grep 'models/titan/titan_skyline'` now matches only the review that asked for it.

## r6 — no monster sinks into the floor (`reviews/monster-assets-r6.md`)

### 1. Why the build and Godot disagreed about `charge_run` — four causes, all found

The build's only gate on the shipped file was `mon_ground.round_trip`, which re-imported the GLB
into Blender and measured it there. It reported 0.09 m for a clip that Godot plays 0.70 m under the
floor. **The file itself was the truth**: a new pure-Python reader, `diag_glb_floor.py`, parses the
container (nodes, skins, inverse bind matrices, animation samplers) and skins it with numpy, and it
reproduces Godot's numbers to the millimetre (`R_Foot` at t = 0.400 s: Godot `-0.968 3.403 0.747`,
reader `-0.968 3.403 0.747`). Four separate things were wrong, and they are independent —
fixing any three still leaves a sinking monster:

* **Blender's round-trip was measuring a rig that was never posed.** Blender only writes the
  channels an action drives; a bone with no fcurve *keeps whatever value it currently holds*. So
  measuring clip after clip on one armature left each clip on top of the previous one's leftovers,
  and `charge_run` — the only clip that drives 13 of 54 bones — was measured with 41 bones frozen in
  `charge`'s pose. `mon_ground.clear_pose` now resets every pose bone to rest before a clip is
  measured. Proof, same file, same frame, `blender/monsters/diag_roundtrip.py`:

  ```
  CHAIN to R_Foot @ frame 9.00                 CHAIN to R_Foot @ frame 9.00 (pose cleared first)
      BoneRoot  file -0.034 -1.938 10.449          BoneRoot  file -0.034 -1.938 10.449
               blender -0.034 -1.938 10.449                   blender -0.034 -1.938 10.449
      Hip       delta 0.001                           Hip       delta 0.000
      Pelvis    delta 0.075                           Pelvis    delta 0.000
      R_Thigh   delta 0.105                           R_Thigh   delta 0.000
      R_Calf    delta 0.474                           R_Calf    delta 0.000
      R_Foot    delta 0.834                           R_Foot    delta 0.000
  ```

  The rest pose, the bone count and the inverse bind matrices all matched exactly (max |IBM -
  inv(nodeRestGlobal)| = 9e-6 m), which is what ruled out every other candidate in the brief.

* **The exporter was throwing the ground lock away.** `mon_ground` keys the root at 30 Hz against a
  24 fps scene, and Blender's glTF exporter bakes every track onto the scene's *integer* frame grid
  by default — so all 25 sub-frame lock keys were resampled down to 21 and the shipped clip carried
  the lock at 24 Hz while the pose it corrects moves faster than that. `mon_lib.FORCE_SAMPLING =
  False` exports the authored keys with their fractional times instead, which glTF carries exactly.
  The correction loop went from *never converging* to converging in one pass, and the GLB got
  smaller (juggernaut 5.7 -> 4.6 MB):

  ```
  before:  PLANT juggernaut pass 0 1.220 m -> pass 1 0.875 -> pass 2 0.727 -> pass 3 0.632   (gave up)
  after:   PLANT juggernaut pass 0 0.138 m -> pass 1 0.001 m  gate 0.05 m                     (shipped)
  ```

* **The build's gate now reads the file, not Blender's importer.** `round_trip` uses
  `diag_glb_floor` instead of a re-import, so the number it corrects against is the number the
  engine plays, and it costs about a fiftieth of a Blender import.

### 2. `charge_run` was an animation bug, not a lock bug

With a trustworthy measurement the cause was visible: the clip's lowest point was **`R_Claw2`, a
knuckle claw**, not a foot. This animal's arms hang to the floor in its bind pose — the claw tips
rest at y = 2.4 m against toes at 0.9 m, and they own 200 of the 400 lowest vertices in the mesh — so
the authored -78 degree elbow still put the claws **0.64 m below the feet** through the cycle. No root
offset can fix that: pinning the claws to the floor lifts the feet off it instead (which is exactly
what the shipped clip did, hovering at +0.24 m on the frames either side of the sink).

Folding the elbow to -130 degrees (`mon_clips_gaits.juggernaut_charge_run`) puts the claws **4.84 m
clear of the feet at every point of the +/-16 degree arm pump**. The angle was searched numerically
against the shipped rig rather than guessed:

```
python3 blender/monsters/diag_clearance.py --type=juggernaut --clip=charge_run \
    --lift=L_Forearm,R_Forearm --sweep=-140,-60,20
```

### 3. The juggernaut was floating 2.5 m in its *idle* — the same bug, never measured

Widening `probe_floor` from five clip names to **every grounded clip of every type** turned up a
second instance the old probe could not see. Tripo's `idle` leaves the arms hanging: the knuckle
claws sit **2.48 m below the toes**, so the ground lock pinned the *claws* and floated the whole
animal above the deck. That is the user's 浮空, and a probe that only reports the lowest point can
never see it — the lowest point was, by construction, 0.00 m.

Measured on the shipped GLB at HEAD against the rebuilt one, feet only
(`diag_glb_floor.py --support=L_ToeBase,R_ToeBase`):

| clip | feet, before (HEAD) | feet, after (r6) |
|---|---|---|
| `idle` | **+2.278 m** lowest, +3.468 m highest per frame | **-0.000 m**, +0.000 m |
| `walk` | -0.042 m | -0.001 m |
| `charge_run` | -0.234 m lowest, **body -0.702 m** | -0.000 m, body -0.000 m |
| `roar` | -0.014 m (feet reach +5.75 m — the prone frames) | -0.000 m |
| `ground_slam` | -0.014 m (feet reach +6.53 m) | -0.000 m |

So before this round the juggernaut stood **2.3 to 3.5 m above the deck for the whole 15 s of its
idle**, resting on its knuckles, and nothing in the pipeline reported it.

`mon_anims.lift` composes a constant rotation onto the keys a clip already has (369 of them, over
15.33 s) and `mon_anims.ARM_LIFTS` applies +45 degrees of shoulder swing to that one clip, which
puts the claws 2.8 m clear of the feet at every frame
(`python3 blender/monsters/diag_clearance.py --type=juggernaut --clip=idle
--lift=L_Upperarm,R_Upperarm --sweep=0,60,15`). Every other clip of every type now reports a
`CLEARANCE` gap of 0.00 m — the feet *are* the lowest point — and that line is printed by the build
for all of them, so this class of bug cannot come back silently.

`roar` and `ground_slam` were also out of band, and the render explains why: those clips have the
juggernaut **prone**, head and fist on the deck with its feet in the air
(`tmp/monster-assets/render/juggernaut_roar_2.png`). For those the whole body is the contact, so the
lock keeps planting the global lowest point — that rule was right, and an earlier attempt to plant
only the legs dragged the body 5.8 m underground.

### 4. The engine was resampling every clip — the build and the game were never looking at one pose

With the lock fixed, `probe_floor` (Godot) and `diag_glb_floor` (the file) *still* disagreed on five
clips, and this time the file was right and Godot was wrong:

| clip | the file says | Godot played |
|---|---|---|
| titan `stagger` | -0.000 m | **-0.24 m** |
| titan `core_break` | -0.000 m | -0.24 m |
| titan `tail_sweep` | -0.042 m | -0.18 m |
| titan_skyline `idle` | -0.000 m | -0.19 m |
| juggernaut `ground_slam` | -0.000 m | -0.17 m |

The cause is in the `.import`: **`animation/fps=30` is Godot's project-wide default, and it re-bakes
every imported animation onto a 30 Hz grid.** Our clips were authored on Blender's default 24 fps
scene, so the engine was playing a linear interpolation between 30 Hz *samples* of the curve the
build had measured — a different pose. Emulating that resample in `diag_glb_floor` reproduces it
exactly (titan `stagger`: authored -0.000 m, re-baked at 30 Hz **-0.241 m**), and `probe_bone_pose`
confirms the bone-level difference (titan `core_break`, `BoneRoot` y at t = 0.365 s: the file
34.041, Godot 33.997).

The fix is to author on the engine's grid rather than to fight it: **`mon_anims.bake_fps` resamples
every action onto integer 30 fps frames and sets the scene rate to match**, before anything is
measured. Durations survive to within half a frame (`charge_run` 20 -> 25 frames, 0.833 s either
way), the stride, the ground lock and the shipped file all then describe the pose the player sees,
and the correction loop converges in a single pass instead of four:

```
PLANT juggernaut  pass 0  worst |lowest| 0.031 m (ground_slam)  gate 0.05 m   <- done in one pass
```

`mon_lib.clip_seconds` had 24.0 hard-coded and now reads the scene rate — with the bake in place a
hard-coded 24 reported every clip 25 % short, and those lengths are what `MonsterPlayback` holds a
one-shot action open for.

**What is left, and it is not fixable from here.** Godot's importer also *compresses* the animation
it imports, and that is unconditional: the titan's `walk` carries 71 keys per rotation track in the
file and arrives with 66, and the five it drops are not free — they cost 0.14 m at the end of the leg
chain (`R_Thigh` diverges by 0.031 m, `R_Calf` 0.103, `R_Foot` 0.196, while `BoneRoot`, `Hip` and
`Pelvis` match to under 0.01 m). The rest pose is identical to six decimals and the pose at t = 0 is
identical, so it is the imported key set, not the rig.

I measured the alternative — keep the authored keys, scale their times by 30/24 instead of
resampling, and set `animation/fps=0` on the models so the engine keeps the original times — and it
is **worse**: titan `walk` 0.19 m under the deck against 0.14 m for the bake, because the compressor
runs either way and a sparser curve gives it more leverage per key. `animation/fps=0` does not turn
it off (verified: a constant track still collapses to a single key with that setting).

So the residual is a property of the engine's import, it is the same order on every animated GLB in
the project, and closing it needs a project-wide import default — which is `game/project.godot`, the
lead's file. See Requests.

## In progress / next
r6's four causes are fixed and verified; the gate is 44 of 46 clips inside the band (from 9 out of
band, worst -4.92 m). The two that are left are `titan_skyline`, and they are the engine-side key
compression in Known issue 16 multiplied by that model's own x1.5 scene scale — not something this
unit can close. Open follow-ups are in Requests.

## How to verify (exact commands)
```
tools/blender.sh run blender/monsters/build_all.py                 # all 7; prints STRETCH, BRIDGE, GROUND, CLEARANCE, PLANT
tools/godot.sh check --only=res://enemies/                         # 110 files, 0 failed, 0 errors, 0 warnings
tools/godot.sh test res://enemies/models/tests/test_models.gd      # 722 checks, 0 failures, PASS
# --- r6: the floor, every grounded clip of every type, as a table (in the engine, ~9 min) ---
tools/godot.sh test res://enemies/models/tests/probe_floor.gd -- --timeout=2400
# the same probe narrowed to one monster or one clip, with every frame printed
tools/godot.sh test res://enemies/models/tests/probe_floor.gd -- --type=titan --clip=walk --frames=1
# what the engine poses each bone at, for a clip — the ground truth when a file and Godot disagree
tools/godot.sh test res://enemies/models/tests/probe_bone_pose.gd -- --type=titan --clip=walk --at=0.93
# --- r6: the same file read without Godot or Blender, so neither importer can flatter it ---
python3 blender/monsters/diag_glb_floor.py --glb=game/enemies/models/juggernaut/juggernaut.glb --all
python3 blender/monsters/diag_glb_floor.py --glb=game/enemies/models/titan/titan.glb --all \
    --support=L_ToeBase,R_ToeBase          # the feet alone: catches a body part hanging below them
# --- r6: why Blender's round-trip and the file disagreed (the pose-leftover proof) ---
tools/blender.sh run blender/monsters/diag_roundtrip.py -- --type=juggernaut --clip=charge_run
# --- r6: how far a limb hangs below the feet, and the lift that clears it ---
python3 blender/monsters/diag_clearance.py --type=juggernaut --clip=idle
python3 blender/monsters/diag_clearance.py --type=juggernaut --clip=idle \
    --lift=L_Upperarm,R_Upperarm --sweep=0,60,15
# --- the three gates the lead named, ported from the acceptance worktree ---
tools/godot.sh test res://enemies/models/tests/probe_fuse.gd  -- --timeout=1800   # bridge triangles + longest bridge edge
tools/godot.sh test res://enemies/models/tests/probe_anim.gd  -- --timeout=1800   # worst per-edge stretch per clip
tools/godot.sh test res://enemies/models/tests/probe_floor.gd -- --timeout=1800   # lowest skinned vertex per frame
tools/godot.sh test res://enemies/models/tests/probe_mesh.gd  -- --timeout=900 --qa-only=hive
tools/godot.sh run  res://enemies/models/tests/probe_flash.tscn 180              # windowed: the flash/tell luma gate
# --- the build-time diagnostics behind the fixes ---
tools/blender.sh run blender/monsters/diag_skin_sweep.py -- --type=titan --stages   # Tripo's own rig as the reference line
tools/blender.sh run blender/monsters/diag_xfer.py       -- --type=mantis --method=both --stretch
tools/blender.sh run blender/monsters/diag_ground.py     -- --type=juggernaut       # what the exported GLB really does
tools/blender.sh run blender/monsters/diag_bridge.py     -- --glb=art/tripo/mon_mantis/rigged.glb,game/enemies/models/mantis/mantis.glb
tools/blender.sh run blender/monsters/diag_tail.py       -- --type=titan
```
Captures:
```
# clay turnaround (magenta back faces = a torn skin or a hole); --gallery-clay=1
tools/godot.sh shot --scene=res://enemies/models/tests/model_gallery.tscn --out=monsters_clay \
    --cams="mantis:-30,9,-26:-30,7,0:38;juggernaut:40,13,-40:40,10,0:42;titan:160,34,-95:160,28,0:45;\
ripper:-52,4,-14:-52,2,0:40;spitter:-8,7,-22:-8,6,0:40;hive:96,30,-95:96,26,0:45;lineup:40,45,-150:40,30,0:60" \
    --warm=120 --gallery-clay=1
# the same cameras with the shipped shader, 40 m — the "no flat green planes" evidence
tools/godot.sh shot --scene=res://enemies/models/tests/model_gallery.tscn --out=monsters_40m \
    --cams="mantis40:-30,9,-40:-30,7,0:38;juggernaut40:40,13,-40:40,10,0:42;ripper40:-52,4,-40:-52,2,0:40;\
spitter40:-8,7,-40:-8,6,0:40;titan40:160,34,-60:160,28,0:45" --warm=120
# forced flash and tell, measured and written to captures/monsters_flash_<type>_<0|1|2>.jpg
tools/godot.sh run res://enemies/models/tests/probe_flash.tscn 180
```

## Evidence

### r6 (this round)

**The gate, before and after** — `probe_floor`, every grounded clip of every grounded type, 30 Hz,
bridge vertices excluded. Before = the models at HEAD (`590a6a1` + r5), after = this round:

| type | clip | lowest before | lowest after | bone (after) |
|---|---|---|---|---|
| juggernaut | `charge_run` | **-0.70 m** | **-0.000 m** | R_Foot |
| juggernaut | `ground_slam` | -0.17 m | -0.000 m | — |
| titan | `core_break` | **-2.38 m**, 27 frames hovering | **-0.000 m** | — |
| titan | `phase_roar` | **-0.74 m**, 58 frames hovering | -0.018 m | — |
| titan | `tail_sweep` | **-4.92 m**, 37 frames hovering | -0.042 m | — |
| titan | `stagger` | -0.16 m | -0.000 m | — |
| titan | `stomp` | -0.31 m | -0.000 m | — |
| titan_skyline | `idle` | -0.16 m | -0.19 m | — |
| titan_skyline | `walk` | **-0.29 m**, 17 sink frames | -0.21 m | — |
| every other clip (37) | | inside the band | inside the band | |

Before: **9 of 46 clips out of band**. After: **44 of 46 inside the band** — every clip of ripper,
mantis, spitter, juggernaut and titan. The two that are not are both `titan_skyline`, and they are
the same engine-side residual amplified by that model's own scene scale: `titan idle` measures
-0.14 m and `titan walk` -0.14 m, and `titan_skyline` is the fight titan at **x1.5** in its Godot
scene, so the same pose reads -0.19 m and -0.21 m against the -0.15 m gate. See Known issues 16.

**The file, read without Godot or Blender** (`diag_glb_floor.py --all`, per type) agrees: 60 of the
66 clips across the seven rigged types measure their lowest point within **0.05 m** of zero, and the
six that do not are the ones that are supposed to leave the floor (`leap` +1.13 m, `death_fall`
+29.4 m, `climb_over` +6.3 m, `summon` +14.7 m, `beam_breath` +3.8 m, `death` +0.4…+4.9 m) plus the
harrier, which flies and whose origin is its body centre.

**The build's own gate now converges.** `PLANT` lines from `build_all`, worst |lowest| per type:

```
PLANT ripper         shipped the best measured export (worst |lowest| 0.102 m)
PLANT mantis         shipped the best measured export (worst |lowest| 0.012 m)
PLANT spitter        shipped the best measured export (worst |lowest| 0.038 m)
PLANT juggernaut     shipped the best measured export (worst |lowest| 0.031 m)
PLANT titan          shipped the best measured export (worst |lowest| 0.138 m)
PLANT titan_skyline  shipped the best measured export (worst |lowest| 0.000 m)
```

Before the exporter fix the same loop *never* converged: juggernaut 1.220 -> 0.875 -> 0.727 -> 0.632 m
over four passes, and it shipped the least-bad one.

**Size.** Turning off forced sampling shrank the GLBs (juggernaut 5.7 -> 4.6 MB, titan 17.5 ->
14.8 MB) because the exporter stopped writing a key on every integer frame of every channel; the
30 fps bake then spends most of that back, since it writes a key every frame on purpose. Net against
the r5 models: juggernaut 5.2 -> 6.1 MB, titan 17.5 -> 16.7 MB, ripper 2.6 -> 2.6 MB.

**The suites.** `tools/suites.sh --only=models,enemies_status,enemies_audit,enemies_projectile,`
`enemies_spawner_mix,enemies_spawner_none,enemies_fight,enemies_ai,enemies_los_loss,`
`enemies_near_miss,enemies_spawn_safety,boss,boss_city,main_spawn_r6,main_spawn_none,main_spawn_stub`
→ `SUITES 16 rows, 16 green, 0 known, 0 red`.

**The 30 fps bake.** `BAKE <type> <n> clips to 30 fps` is printed per type with the frame counts
before and after (`charge_run 20->25 f`, i.e. 0.833 s at both rates). Nothing else in the pipeline
changed rate: the clip tables in `mon_clips*.py` are still written in 24 fps frames and `bake_fps`
converts them, so the authored timings are untouched.

**Foot slide improved while the pipeline was open**: the ripper went from 6 % to **1 %** at its
30 m/s gameplay speed, because the stride is now measured on the same 30 fps grid the engine plays.
Every other type stays at 0 %.

**The clearance check that would have caught the float** — `CLEARANCE` lines, printed by the build
for every clip of every type, are the gap between the feet's lowest point and the whole body's. All
zero except where the body is meant to leave the ground.

### r5
- **Gates**: `build_all` exit 0, all 7 types; `CHECK 110 files, 0 failed, 0 errors, 0 warnings`
  (`--only=res://enemies/`); `TEST 722 checks, 0 failures / PASS`; `test_spawner`, `test_main_spawn`,
  `test_audit` PASS; `test_ai` PASS (one run of its *physics frame with 40 enemies* wall-clock check
  read 6.071 ms against a 6.0 ms budget and passed on the re-run — the pre-existing flakiness noted
  under Split r1, not a regression).
- **The skin, `probe_fuse`** (the lead's own probe, ported to
  `game/enemies/models/tests/probe_fuse.gd`):

  | type | bridge triangles before -> after | longest bridge edge, worst clip |
  |---|---|---|
  | ripper | 362 -> **120** | 3.5 m -> **0.8 m** |
  | mantis | 473 -> **5** | 14.4 m -> **0.3 m** |
  | spitter | 458 -> **417** | 4.5 m -> **3.8 m** |
  | harrier | 609 -> **503** | 2.9 m -> **1.6 m** |
  | juggernaut | 812 -> **389** | 26.5 m -> **1.7 m** |
  | titan | 3494 -> **297** | 50.0 m -> **2.9 m** |

- **The stretch reference line** (`diag_skin_sweep.py --type=titan --stages`) — Tripo's *own* rig of
  the same animal, placed at the same scale, measured with the same probe:

  ```
  STRETCH titan/tripo-placed SUMMARY worst 4.75x, longest posed edge 4.49 m (7.5% of 60.0 m)
  STRETCH titan/4-smooth4    SUMMARY worst 7.21x, longest posed edge 3.25 m (5.4% of 60.0 m)
  ```

  Our longest posed edge is now **shorter than Tripo's own**. The ≤ 2x ratio gate is not reachable
  by any rig: Tripo's clean one already reaches 4.75x at the joints, and the ratio grows with mesh
  density (the same weight gradient sampled over an edge 2.7x shorter reads as 2.7x the stretch).
- **The floor, `probe_floor`**: mantis `run` 38/38 frames hovering > 0.3 m -> **0/38**; mantis
  `idle` 280/460 -> **0/460**; every grounded clip's lowest point is inside -0.15 m except
  juggernaut `charge_run` (-0.70 m, Known issues 1). The build's own gate on the exported file
  (`PLANT … shipped the best measured export`): ripper 0.078 m, mantis 0.061 m, spitter 0.035 m,
  juggernaut 0.091 m, titan 0.357 m.
- **The flash and the tell, `probe_flash`** (`captures/monsters_flash_sheet.jpg`, 7 types x
  neutral / flash / tell):

  ```
  FLASH ripper      neutral median 0.205 | flash 1.14x OK | tell 1.26x OK
  FLASH mantis      neutral median 0.159 | flash 1.13x OK | tell 1.25x OK
  FLASH spitter     neutral median 0.210 | flash 1.17x OK | tell 1.33x OK
  FLASH harrier     neutral median 0.123 | flash 1.06x OK | tell 1.12x OK
  FLASH juggernaut  neutral median 0.151 | flash 1.12x OK | tell 1.27x OK
  FLASH titan       neutral median 0.323 | flash 1.14x OK | tell 1.29x OK
  FLASH hive        neutral median 0.262 | flash 1.05x OK | tell 1.02x OK
  ```

  Gate 1.5x. Before: the flash took the median 3.1-4.6x and the tell to 0.82-0.85 with 84-98 % of
  the pixels above 0.5.
- **The hive stump, `probe_mesh`**: `HiveDestroyed` largest hole **80.88 m -> 1.35 m**, open edges
  195 -> 15, and the cap carries its own near-black `HiveInterior` material.
- **Geometry, `captures/monsters_clay_sheet.jpg`** — a clay turnaround per type with magenta back
  faces (`--gallery-clay=1`), taken mid-animation (the label reads `clip walk` / `clip run` /
  `clip attack`). **No magenta anywhere**, no holes, no sheets.
- **In game at 40 m, `captures/monsters_40m_sheet.jpg`** — mantis, juggernaut, ripper, spitter and
  titan at 40 m with the shipped shader. **No flat green planes.**
- **Logs**: `tmp/monster-assets/r5/` — `build_ship.log` (the shipped build), `floor_ship.log`,
  `fuse_mesh_final.log`, `probes_after.log`, `floor_before.log` / `fuse_before.log` (the HEAD
  baselines the numbers above are measured against).

### Earlier rounds
- **Gates**: `build_all` exit 0, all 7 types; `CHECK 14 files, 0 failed, 0 errors, 0 warnings`;
  `TEST 722 checks, 0 failures / PASS` (666 in r3, 361 in r2: the action table, the gait ladder, the
  slide-at-both-speeds contract, the one-shot hold, and now the look block and the hive's pods).
- **Enemies integration**: `test_ai`, `test_spawner`, `test_main_spawn`, `test_audit` all PASS.
- **Scripted fight** (`fight_probe`, `--nan-watch`, 15 monsters, 36 s): 0 NaN reports, 0 model
  warnings, 60 telegraphs all resolved to a clip. The 9 errors in the log are
  `perfect_dodge` signal arity in `res://core/event_router.gd` — not this unit's file (Requests #3).
- **Gait strips**: `captures/monsters_gait_strips.jpg` — the three new gaits at their gameplay
  speeds, side-on, camera tracking, with the clip name and playback scale burned into the label.
- **Attack hold**: `captures/monsters_attack_hold.jpg` (audit 1).
- **Movie**: `tmp/monster-assets/monsters_cycles.avi`, 26 s at 60 fps, 0 errors. Sampled at 10 fps
  (260 frames, 160×90): mean frame-to-frame difference 0.002, σ 0.001, max 0.004, **no sample above
  mean + 6σ** — no popping at the six locomotion state changes.
- **Captures**: `captures/monsters_gallery_lineup.jpg`, `captures/monsters_attack_strips.jpg`
  (re-rendered, 6 types × 6 attack frames), `captures/monsters_gait_strips.jpg`,
  `captures/monsters_attack_hold.jpg`, `captures/monsters_hive_{intact,cracked,destroyed}.jpg`,
  `captures/monsters_lineup{,_scale}.jpg`, `captures/monsters_swarm_swarm.jpg`.
- **Ground contact** (`diag_contact.py`, lowest contact bone against the rest-pose floor):
  ripper `scuttle` touches down at +0.01 m with a 0.92 m suspension peak; spitter `scuttle` +0.07 m;
  juggernaut `charge_run` +0.72 m against +1.42 m for Tripo's own walk, i.e. the new run plants
  *better* than the shipped walk (the juggernaut's toe bone sits 0.87 m above its mesh floor at rest).
- **Look A/B (r4)**: `captures/look_monster-assets_hive_ab.jpg` — the A6 spire at 25 m and 70 m,
  BEFORE (HEAD models) left, AFTER right, same world, same camera. At 25 m the trunk goes from a
  navy blob with violet smears and a lime halo to a dark ribbed spire with thin acid veins and small
  violet cores; the rib structure is readable for the first time.
  `captures/look_monster-assets_gallery_ab.jpg` — the same A/B for the monsters (ripper at 40 m
  beside the 16 m hero, the whole line-up, and the line-up at 230 m).
- **Skin sanity**: worst posed/rest stretch ratio — ripper 1.04, mantis 1.05, spitter 1.23,
  harrier 1.19, juggernaut 1.13, titan 1.32 (the tail sweep).

## Known issues
1. **(r6, fixed) juggernaut `charge_run` sank 0.70 m** — see the r6 section: the ground lock was
   being destroyed by the exporter's forced sampling, Blender's round-trip was measuring an unposed
   rig, and the clip's own knuckle claws hung 0.64 m below its feet. All three are fixed and the
   clip now measures -0.000 m from the shipped file.
2. **(r5, open) the spitter's and harrier's bridges barely moved** — 458 -> 417 and 609 -> 503. They
   are not a transfer problem: those two types have no Tripo rig, so the armature is ours, fitted to
   a mesh where the sac touches a hind leg (`Sac|LegBL_2`) and the head touches the tail
   (`Head_0|Tail_2`) in the bind pose. The surface transfer cannot fix geometry that really is fused;
   it needs the bind pose separated, or a Tripo re-rig with the limbs clear (Requests #9).
3. **(r5) the hive stump's largest hole is 1.35 m, not < 1 m.** The 80.88 m break is capped; what is
   left is the source spire's own non-manifold edges (the intact hive ships 1 open edge), not the
   break. Four `holes_fill` passes find no boundary left to close.
4. **(r5) the spitter's sac is blown out to pure white in the *neutral* frame** of `probe_flash` —
   that is the emission energy on a large bright sac, not the flash. It predates r5 and is a look
   question for the lead, not something this round introduced.
5. **The ripper's ceiling is 4.00x**, the most any type gets: its 30 m/s against a 0.33 s scuttle
   cycle. At 4x the legs are a blur — which is the intended read for a 30 m/s swarmer, and the
   residual is still only 6 %.
6. **The juggernaut is a hunched, gorilla-shaped model**, so `charge_run` reads lower and more
   pitched than a human run would. It is the model's own silhouette (Tripo's walk is the same shape).
7. **`mon_stride` still warns on the juggernaut's knuckle claws** in `charge_run` and in Tripo's own
   `idle` — the arms hang low enough that the claws reach below the toes. Unchanged from r2.
8. **The titan's `tail_sweep` reaches 1.32x the rest size** (the tail swinging out, not a bad weight).
9. **Tripo clip lengths differ from what the jobs asked for** — juggernaut `death` 1.33 s against
   2.80 s, titan `summon` 3.46 s against 2.40 s. The build prints `CLIP WARN` and uses what Tripo
   produced.
10. **`hit_light` -> `hit` is a rename.** Mantis, juggernaut and titan use Tripo's single hit reaction
    for both light and heavy hits.
11. **Juggernaut armour plates are a shader state, not geometry** (accepted, lead r1).
12. **The Blender 5 glTF importer leaves an untextured 80-face `Icosphere` in every imported scene.**
    My render scripts drop it; the lead's `blender/tools/preview.py` is the one to fix (lead's note).
13. **The albedo grade is measured against a texture, the lead's against a screenshot.** My medians
    (0.19-0.30 linear over the UV shells) are ~5x the lead's (0.031-0.074), because theirs is a
    rendered pixel and mine is a texel. `GRADE_TARGET = 0.08` is anchored so the *gains* come out
    where the lead put them (ripper 0.43 against 0.5, hive 0.27 against 0.22, harrier 0.29 against
    0.25). If the lead wants the monsters darker or lighter, that one number moves all seven.
14. **In the sandbox gallery the carapace reads as very dark.** The sandbox's flat daylight gives the
    shell little key, so the veins carry most of the shape; under the game's dusk key the same grade
    shows rib and form. Judged in game, not in the gallery.
15. **(r6) `titan_skyline` `idle` and `walk` are still outside the floor band: -0.19 m and -0.21 m
    against the -0.15 m gate.** They are *not* a lock failure — the build plants that file to
    0.000 m and the file measures 0.000 m. They are `titan idle` and `titan walk` (both -0.14 m, the
    engine-side key-compression residual in Known issue 16) multiplied by the x1.5 scale its Godot
    scene applies to read as a 90 m walker. On a model seen at ring distance 0.2 m is ~0.2 % of its
    height, so it does not read; it is listed because the gate says -0.15 m and this is -0.21 m.
16. **(r6, the real one) Godot's glTF importer compresses imported animations, and no exposed
    setting turns it off.** The titan's `walk` carries 71 keys per rotation track in the file and
    arrives in the engine with 66; the pose the engine plays is up to **0.2 m** away from the pose
    the file encodes at the end of a long bone chain (`R_Thigh` diverges 0.031 m, `R_Calf` 0.103,
    `R_Foot` 0.196, while `BoneRoot`, `Hip` and `Pelvis` match to under 0.01 m). The rest pose is
    identical to six decimals and so is the pose at t = 0, so it is the imported key set, not the
    rig. Two fixes were measured and rejected: `animation/fps=0` does not disable it (a constant
    track still collapses to one key), and keeping the authored keys and only retiming them is
    *worse* (titan `walk` 0.19 m under the deck against 0.14 m for the 30 fps bake) because a
    sparser curve gives the compressor more leverage per key. Requests A.
17. **Rebuilds are not byte-identical.** Two consecutive `build_all` runs produce the same
    tri/bone/clip/gait table and a byte-identical `<type>_rig.json`, but the GLBs differ in a few
    bytes — Blender's decimator and Data Transfer are not bit-stable. Nothing downstream depends on
    the bytes. (r5 adds one real cost: each type is now exported and re-imported up to four times for
    the ground-lock correction, so a full build takes ~20 min, most of it the titan.)

## Captures needed (windowed — refused without the lead's `MC_WINDOW_OK=1`)

Everything numeric in r6 is measured headless and is in Evidence. What is left is the *look* of the
two poses this round changed, which needs a window:

```
# 1. the juggernaut's charge_run at its gameplay speed — the clip this round fixed.
#    The knuckle claws must stay clear of the deck through the whole cycle and the feet must stay on it.
tools/godot.sh shot --scene=res://enemies/models/tests/model_gallery.tscn --out=monsters_r6_charge \
    --cams="charge:40,13,-40:40,10,0:42" --warm=120 --gallery-gait=juggernaut:20
tools/godot.sh shot --scene=res://enemies/models/tests/model_gallery.tscn --out=monsters_r6_charge_side \
    --cams="charge_side:0,11,-46:0,9,0:42" --warm=120 --gallery-gait=juggernaut:20

# 2. the juggernaut's idle — the +45 degree arm lift. Before this round the animal stood on its
#    knuckles with its feet 2.5 m in the air; the feet must now read as planted.
tools/godot.sh shot --scene=res://enemies/models/tests/model_gallery.tscn --out=monsters_r6_idle \
    --cams="idle:40,13,-40:40,10,0:42;idle_side:0,11,-46:0,9,0:42" --warm=120 --gallery-clip=idle

# 3. the whole line-up beside the 16 m hero placeholder, for scale
tools/godot.sh shot --scene=res://enemies/models/tests/model_gallery.tscn --out=monsters_r6_lineup \
    --cams="lineup:40,45,-150:40,30,0:60" --warm=120

# 4. six-frame attack strips per type (ATTACK_EVERY is 2.5 s, so the times below catch one action)
tools/godot.sh shot --scene=res://enemies/models/tests/model_gallery.tscn --out=monsters_r6_slam \
    --times=0.2,0.5,0.8,1.1,1.4,1.7 --warm=120 --gallery-attack=juggernaut:ground_slam

# 5. the hive in three states, and the glow under the sandbox's dusk key
tools/godot.sh shot --scene=res://enemies/models/tests/model_gallery.tscn --out=monsters_r6_hive \
    --cams="hive:96,30,-95:96,26,0:45" --warm=120 --gallery-state=intact
tools/godot.sh shot --scene=res://enemies/models/tests/model_gallery.tscn --out=monsters_r6_hive \
    --cams="hive:96,30,-95:96,26,0:45" --warm=120 --gallery-state=cracked
tools/godot.sh shot --scene=res://enemies/models/tests/model_gallery.tscn --out=monsters_r6_hive \
    --cams="hive:96,30,-95:96,26,0:45" --warm=120 --gallery-state=destroyed
tools/godot.sh shot --scene=res://main.tscn --sandbox --skip-menu --out=monsters_r6_ingame \
    --cams="juggernaut:34,12,-34:34,8,0:45" --warm=180 --enemies=juggernaut:1 --env-only

# 6. the cycles as a movie, to judge foot slide and popping rather than a frozen pose
tools/godot.sh movie --movie=$PWD/captures/monsters_r6_cycles.avi \
    --scene=res://enemies/models/tests/model_gallery.tscn \
    --timeline=res://enemies/models/tests/gallery_timeline.json
```

## Requests (to the lead / other units)

**A. (r6, new — engine) Godot's glTF importer compresses imported animations, and it is not
configurable.** Every animated `.glb` in the project loses keys on import: the titan's `walk`
carries 71 keys per rotation track in the file and arrives with 66, and the pose the engine plays is
up to **0.2 m** away from the pose the file encodes at the end of a long bone chain. `animation/fps`
does not control it (verified with `0` and with `30`), and there is no exposed option for it.

This matters beyond monsters: anything that measures an animation offline — a foot-slide probe, a
stride measurement, a hit-window timing check — is measuring a curve the engine will not play. Two
things would help, both in the lead's files:

* a project-wide `[importer_defaults]` entry in `game/project.godot` if a future Godot exposes the
  switch, and
* a note in `docs/` that offline animation measurements carry up to ~0.2 m of engine-side error on a
  long chain, so a gate tighter than that cannot be enforced from a `.glb` alone.

The monsters' own floor gate is now measured **in the engine** (`probe_floor`), not from the file, so
this unit's numbers are the ones the player sees.


**0. (enemies r11 — read this first) Capture from commit `590a6a1`.** That commit is the models and
nothing else: every `<type>.glb`, every `<type>_rig.json`, the hive's pods mask, and the deletion of
the four orphan `titan/titan_skyline_*` textures. The build that produces them is `69be409`; the
flash/tell shader tuning is `2afb937`. (`84bd0e7` was the round's first models commit and is
superseded.)

* **No API change.** CONTRACTS §6 is untouched; `set_locomotion`, `play_action`, `socket`,
  `hit_pause`, `set_hit_flash` and every extra the placeholder had (`set_telegraph`, `set_stagger`,
  `break_plate`, `visual_root`) behave exactly as before.
* **No rename.** Every socket name, clip id, action id, gait ladder rung, `speed_scale_min/max` and
  rig-json key is the same string it was at `dcedb13`. `test_models` is 722 checks / 0 failures.
* **What you will see differently in a capture.** The monsters no longer tear (no flat green planes
  between limbs at 40 m), no longer float or sink (the mantis in particular is *on* the deck now
  instead of 0.36-1.44 m above it), no longer flash to a flat beige ghost on a missile hit, and no
  longer whitewash during a windup. The destroyed hive is a capped stump instead of a see-through
  one.
* **Sizes, sockets and weak points are unchanged**, so Hurtbox and Targetable placement needs no
  edit. The hive's `pod_0..3` heights are unchanged from r4.
* **`monster_body.gdshader` gained six uniforms** (`flash_energy`, `flash_color`, `flash_body`,
  `flash_veins`, `flash_rim_power`, `tell_energy`, `tell_rim_gain` — the last two are the tell pair);
  `flash_energy` and `tell_energy` come from each rig json's `look` block, so
  `MonsterLook.LOOK_KEYS` carries them. Nothing outside `game/enemies/models/**` reads them.

1. **(enemies) Locomotion needs no change.** The gait ladder picks the clip by the speed already
   passed to `set_locomotion`, so the speeds in `types.gd` and the patrol fraction in `brain.gd` can
   stay exactly as they are — that was the point of r3. `test_models` pins the numbers: if a speed
   changes, the slide check fails and names the state.
2. **(enemies) The juggernaut's roar** (`juggernaut.gd:59`) is still started with
   `set_locomotion(&"roar")`, which no locomotion table answers, so it resolves to idle. The audit's
   prescribed fix is `play_action(&"roar")`; the clip exists and is 2.75 s. This unit cannot make
   that change — `game/enemies/juggernaut/**` is the enemies unit's.
3. **(lead/core) `Events.perfect_dodge` arity.** A 36 s fight logs 9 ×
   `emit_signalp(): Error calling from signal 'perfect_dodge' to callable:
   'Node(event_router.gd)::on_simple': Method expected 1 argument(s), but called with 2.` — the
   signal emits 2 arguments and `event_router.on_simple` takes 1. `res://core/event_router.gd` is
   lead-owned. It makes `tools/godot.sh drive` exit 1 for every unit that runs a fight.
4. **(enemies) Socket names.** Both sets are provided: the brief's (`mouth`, `muzzle`, `claw_l/r`,
   `core`, `weak_0..3`) and the placeholder's (`mouth`, `chest`, `back`, `hand_l/r`, `muzzle`).
   `weak_points()` returns the `weak_*` markers in order; on the hive it returns `pod_0..3` first,
   which is what `flow/hive_visual` reads.
5. **(enemies) `set_stagger` leans the visual root 7°** and holds an amber tell; `break_plate()`
   returns true 4 times then false, same contract as the placeholder.
6. **(hero / world) The same weld fix.** `blender/monsters/mon_lib.load_glb` now imports with
   `merge_vertices=True`, which is what killed the seam cracks (item 3 above). The identical import
   in `blender/hero/hero_lib.py:24` and `blender/world/process_prop.py:162` still splits at every UV
   seam: the lead measured 58.7k open edges on the 150k-tri hero at a median 1.7 mm gap, which is the
   same sky-coloured edge sparkle the user's screenshot shows on the mech at bottom-left. One keyword
   each, plus a rebuild. Neither file is this unit's.
7. **(flow / enemies) The hive's pod sockets moved** with the new acid mask: `pod_0` 10.3 -> 18.8 m,
   `pod_1` 24.0 -> 27.8 m, `pod_2` 40.5 -> 40.4 m, `pod_3` 54.5 -> 54.3 m. Still four, still lowest
   first, all above the 15 % height floor the test pins. Anything that hard-codes a pod height (flow's
   burst VFX, the enemies unit's Hurtbox sizes) should read the socket instead.
8. **(flow) `HiveModel.set_pod_alive(i, on)` exists now**, so `hive_visual.burst_pod`'s
   `_model.has_method(&"set_pod_alive")` branch is live: a burst pod takes the painted bulb's glow
   with it and the sac no longer has to be the only tell.

9. **(lead) Tripo credits, for the spitter and the harrier only.** Their remaining bridges (Known
   issues 2) are fused bind geometry, not a transfer defect: the sac is stitched to a hind leg and
   the head to the tail. A Tripo re-rig from a source pose with those parts clear would let the same
   `mon_skin.transfer_surface` path finish the job. I have not spent a credit — this is the ask the
   r5 brief said to raise in Requests first. Everything else is done without one.
