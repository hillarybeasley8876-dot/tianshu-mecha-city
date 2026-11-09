# Godot 4.7.2 for 天枢 TIANSHU: capabilities, architecture and budgets (research dossier v1)

Key: `godot-tech`. Date: 2026-11-01. Audience: the lead (Claude Opus), who turns this into briefs for MiniMax-M78 workers.
Engine: `/opt/homebrew/bin/godot` = **4.7.2.stable.official.ed1daf0bf**, Forward+, Metal. Machine [L]: MacBook Pro 14" (MacBookPro18,4), M1 Max, 10 CPU cores (8P+2E), 24-core GPU, 32 GB, macOS 27.2; Godot reports "Apple M1 Max (Apple7), Metal 4.0". New windows open on screen 0, the built-in XDR panel (3024×1964, **120 Hz**, scale 2.0, HDR capable); screens 1–2 are external 60 Hz panels.

Conventions
- `[Sx]` = source (list in §10). **[L]** = I verified it on this machine with a throwaway project (`tmp/research/godot-tech/proj/`, scripts listed in §9). **(estimate)** = my recommendation or derivation, not a sourced fact.
- Scale: hero 16 m, physics 120 Hz, hero gravity 56 m/s² (SPEC §2). One tick = 8.33 ms.
- [L] timings were taken while other agents loaded the machine (load average 9–24): treat them as upper bounds and re-measure on the real scene.

---

## 0. The fourteen rules (read these if nothing else)

1. **Stay on Forward+ / Metal.** Native since 4.4, "at least as fast as Vulkan and in many cases much faster on Apple hardware" [S4]. Compositor compute effects work on Metal in 4.7.2 [L].
2. **GPU timings read 0.0 on Metal in 4.7** [L]: a known limitation, fixed only in 4.8 and not backported [S59]. Measure with frame time (`--disable-vsync`), the Metal HUD (`MTL_HUD_ENABLED=1` [S64]) or Xcode Instruments.
3. **Cap the frame rate.** The window lands on a 120 Hz panel and physics interpolation is off. Set `application/run/max_fps = 60` so every frame runs exactly 2 ticks (estimate, §2.6).
4. **The hero and enemies are `CharacterBody3D`.** `RigidBody3D` is only for debris and wrecks. Jolt clamps rigid bodies at **500 m/s** (`physics/jolt_physics_3d/limits/max_linear_velocity`) [S55][L], so 900 m/s gatling rounds can never be rigid bodies.
5. **Projectiles are data, not nodes.** Use packed arrays plus a per-tick ray or sphere segment, drawn by one `MultiMesh` buffer write. 600 bullets cost **0.28 ms per tick** in GDScript [L].
6. **City collision comes from Blender name suffixes.** `-colonly` gives a trimesh StaticBody3D, `-convcolonly` gives convex, `-occonly` gives an occluder, `-noimp` removes the node. I verified each one on 4.7.2 [L][S9]. Never use `WorldBoundaryShape3D`: Jolt caps it at 2000 m and 4.7 flipped its sign [S5][S8].
7. **Bake navmeshes offline, from colliders only, one map per agent class.** The full 1.6 km city bakes in 0.5 s (medium agent); the `LAYERS` partition took **175 s** [L].
8. **Wait for nav sync before querying** (~17 physics frames for a 9k-polygon region [L][S16]), then budget **~0.7 ms per cross-map path query** [L]: stagger and cache.
9. **Pre-instance every VFX scene once at load.** Ubershaders plus precompilation remove most stutter, but effects first spawned in gameplay still compile then [S25]. Watch `PIPELINE_COMPILATIONS_*`.
10. **Lights are clustered: 512 elements per view, shared by omni lights, spot lights, area lights, decals and probes** [S23][S31]. Shadowed positional lights get 88 atlas slots and are cached until the light or a caster moves [S23]. Use `shadow_caster_mask` to keep enemies out of omni shadows (estimate).
11. **No `AreaLight3D` in gameplay views.** In Forward+, one visible area light adds cost to every rendered object [S23]. Fake neon with emissive materials plus omni or spot lights.
12. **The directional shadow defaults are wrong for a city.** Max distance is 100 m by default [L]. Use 500 m with splits 0.05/0.15/0.40 (estimate), and split building meshes into chunks so they do not land in all 4 PSSM splits [S23].
13. **Post-processing needs no engine patch.** Use a full-rect `canvas_item` shader for radial blur, chromatic aberration, flashes and speed lines. Use a full-screen quad for depth effects. Use `CompositorEffect` only for pre-tonemap or compute work [S32][S38][S39][L].
14. **Screenshots and movies need a window.** `--headless` uses a dummy renderer: `--write-movie` crashed there with signal 11 [L]. Headless is for import, checks, physics and navigation tests only.

---

## 1. What changed in 4.4 → 4.7 that matters here

### 1.1 Feature changes by area

| Area | Version | Change | What we do with it |
|---|---|---|---|
| Metal | 4.4 | Native Metal backend (Apple Silicon only) replaces MoltenVK; MetalFX upscaling added [S4] | Keep `driver.macos="metal"`. MetalFX Spatial (=3) and Temporal (=4) exist only in the `scaling_3d/mode.macos`/`.ios` overrides [L][S55] |
| Stutter | 4.4 | Ubershaders and pipeline precompilation at load time [S4][S25] | Pre-instance VFX; see §4.5 |
| Stutter | 4.5 | **Shader baker** export option. The TPS demo loaded up to 20× faster on Metal/D3D12 [S3]. Not available with `--headless` exports [S25] | Enable in the macOS export preset; export from a windowed editor |
| Physics | 4.4 / 4.6 | Jolt built in (4.4), then the default for new projects (4.6) [S4][S2] | Already set in `project.godot` |
| Physics | 4.4 / 4.5 | 3D physics interpolation (4.4), moved to the SceneTree (4.5) [S4][S3] | Off per CONTRACTS; see §2.6 |
| Physics | 4.7 | Jolt `WorldBoundaryShape3D.plane.d` sign flipped; Jolt SoftBody3D mass and stiffness changed [S5] | Don't use either |
| Navigation | 4.4 | Map sync moved to a background thread; refactor and faster heap [S4] | Expect sync latency |
| Navigation | 4.5 | Region sync is also async by default; navmesh merge order changed [S3][S7] | §3.4 |
| Animation | 4.4 | `LookAtModifier3D`, `RetargetModifier3D`, `SpringBoneSimulator3D`, animation markers [S4] | Head and sensor tracking; antennas and cables |
| Animation | 4.5 | `BoneConstraint3D` plus `AimModifier3D`, `CopyTransformModifier3D`, `ConvertTransformModifier3D` [S3] | Hydraulic pistons (two bones aiming at each other) |
| Animation | 4.6 | **IK returns**: `IKModifier3D`, `TwoBoneIK3D`, `ChainIK3D`, `SplineIK3D`, `IterateIK3D` (`FABRIK3D`, `CCDIK3D`, `JacobianIK3D`), `BoneTwistDisperser3D`, `LimitAngularVelocityModifier3D` [S2][S57] | Foot planting, weapon grips; §2.8 |
| Animation | 4.7 | BlendSpace1D/2D `sync_mode` enum replaces the `sync` bool. New `CYCLIC_MUTABLE` and `CYCLIC_CONSTANT` modes keep walk and run cycles phase-locked [S5][S63] | Locomotion blend spaces |
| Rendering | 4.4 | AgX tonemapper, LightmapGI shadowmask, Light3D `shadow_caster_mask` [S4] | AgX for neon HDR; caster masks |
| Rendering | 4.5 | **Stencil buffer**: material `stencil_mode` Outline / X-Ray / Custom; SMAA 1x; specular occlusion; bent normals [S3][S52] | Enemy highlight (§6.6) |
| Rendering | 4.6 | SSR overhaul with half-res option; octahedral reflection probes; glow now before tonemap with **Screen** blend as default; AgX `agx_white`/`agx_contrast` exposed; better LOD decimation ("component pruning") [S2] | Re-tune glow; LODs |
| Rendering | 4.6 | **Defaults changed**: glow intensity 0.8→0.3 and new glow levels; volumetric fog blending "more physically accurate", brighter; `MeshInstance3D.skeleton` default `".."`→`""` [S6] | Set `skeleton` explicitly on scripted rigs |
| Rendering | 4.7 | **AreaLight3D**, **HDR output** (macOS/Metal included), clearcoat fix, per-pass environment UBOs (faster), 3D particle scale and rotation controls, nearest-neighbour 3D scaling [S1][S58] | HDR optional; no area lights in gameplay |
| GI | 4.5–4.7 | **No new GI technique.** Still SDFGI, VoxelGI, LightmapGI, SSIL and ReflectionProbe [S26][S1][S2][S3] | §4.3 |
| Import | 4.5 / 4.6 | Batch import editing; glTF "naming version" for non-joint skeleton nodes (4.5); LOD component pruning and 2× faster Betsy RGB compression (4.6) [S3][S7][S2] | Default `gltf/naming_version=2` [L] |
| Input | 4.5 | SDL3 gamepad driver [S3] | |
| Input | 4.7 | Gyro and accelerometer from pads (`get_joy_gyroscope`, experimental). `ignore_joypad_on_unfocused_application`. Keyboard and mouse events now carry `DEVICE_ID_KEYBOARD`=16 / `DEVICE_ID_MOUSE`=32 [S1][S5][S46][L] | Turn the ignore setting on (several game windows run at once) |
| Scripting, tools | 4.5–4.7 | `OS.add_logger` (4.5); Instruments/Tracy tracing and ObjectDB snapshots (4.6); `Tween.tween_await()` and `Control` offset transforms (4.7) [S3][S2][S1] | HUD juice, leak hunting |

### 1.2 Metal on this machine: status and known issues

| Item | Status | Source |
|---|---|---|
| Visual Profiler GPU times, `viewport_get_measured_render_time_gpu` | Always 0 on Metal in 4.4–4.7 ("timestamp-based timing… not compatible with TBDR GPUs"). Fixed in 4.8 via #121392, not backported | [S59][L] |
| First-run shader compile slow (MTLCompilerService) | Open issue | [S60] |
| Pipeline-creation deadlock on macOS 26 with many CanvasShaderRD variants | Open, 4.8 milestone. Reproduced on an M1 Pro running macOS 26.6.2. Avoid generating huge numbers of canvas shader variants | [S61] |
| Metal needs macOS 13+; 4.7 crashed on macOS 12 | Fixed | [S62] |
| Depth prepass | Disabled on Apple GPUs by default (`rendering/driver/depth_prepass/disable_for_vendors="PowerVR,Mali,Adreno,Apple"`), because these GPUs "do not benefit from the depth prepass due to their unique architecture" | [S55][L] |
| HDR output | `display/window/hdr/request_hdr_output` (default false); `DisplayServer.window_is_hdr_output_supported()` returned true on all 3 screens | [S58][L] |

### 1.3 Class names verified in 4.7.2 [L]

152 of the 154 classes I cited exist. The two misses are internal names: `JoltPhysicsDirectSpaceState3D` and `GodotPhysicsServer3D` (`JoltPhysicsServer3D` is exposed). Confirmed, among others: `AreaLight3D`, `DrawableTexture2D`, `Compositor`/`CompositorEffect` (no built-in effects ship), `ShapeCast3D`, `AnimatableBody3D`, every Navigation* 3D class, `AStar3D`, all GPU particle collision and attractor nodes, `RibbonTrailMesh`/`TubeTrailMesh`, `Decal`, `FogVolume`, `VoxelGI`, `LightmapGI`, all `Occluder3D` types, `AnimationNodeExtension`, `EditorScenePostImport(Plugin)`, `GLTFDocumentExtension`, `MovieWriter`, `VirtualJoystick`.

`ClassDB.get_inheriters_from_class("SkeletonModifier3D")` returns 22 classes: every modifier named in §1.1 and §2.8, plus `ConvertTransformModifier3D`, `XRBodyModifier3D`, `XRHandModifier3D`, `PhysicalBoneSimulator3D` and the deprecated `SkeletonIK3D`.

All 42 methods and signals cited below also exist (`ClassDB.class_has_method`/`class_has_signal`), e.g. `AnimationMixer.advance`, `NavigationServer3D.bake_from_source_geometry_data_async`, `GPUParticles3D.emit_particle`, `GeometryInstance3D.set_instance_shader_parameter`, `NavigationAgent3D.link_reached`.

---

## 2. Architecture for a fast 16 m mech

### 2.1 Body types

| Thing | Node | Why |
|---|---|---|
| Hero, ground enemies, Titan "feet" | `CharacterBody3D` (Jolt) | Full control of velocity and snap; `move_and_slide` adds sliding on top of `move_and_collide` collision detection [S45] |
| Flyers (Harrier) | `CharacterBody3D`, `motion_mode = FLOATING` | Floating mode has "no notion of floor or ceiling… speed will always be constant" [S45] |
| Debris, wrecked props | `RigidBody3D`, sleeping enabled | Jolt sleeps them after 0.5 s below 0.03 m/s (defaults [L]) |
| Maglev trains, moving decks | `AnimatableBody3D` | Kinematic platforms. `platform_on_leave` handles the hand-off [S45] |
| Hurtboxes, triggers | `Area3D` | Under Jolt, areas always report static bodies [S7] |

### 2.2 Hero `CharacterBody3D`: 4.7.2 defaults [L] vs. recommendation

| Property | Default | Recommended (estimate unless noted) | Reason |
|---|---|---|---|
| Collision | — | One `CapsuleShape3D`, r 3.5–4.0 m, h 14 m, centred 7.5 m up | Rounded bottom rides curbs (§2.3); stays inside the 16 m silhouette |
| `floor_max_angle` | 45° | 40° | Matches level-design walk slopes |
| `floor_snap_length` | 0.1 m | **1.5–2.0 m** | At 44 m/s on a 30° downslope the ground drops 0.18 m per tick. The extra margin covers crests |
| `floor_constant_speed` | false | true | Skating speed stays constant on ramps [S45] |
| `safe_margin` | 0.001 m | 0.01–0.02 m | Larger margin "helps with consistently detecting walls and floors" [S45]; test for `is_on_floor()` flicker |
| `max_slides` / `wall_min_slide_angle` | 6 / 15° | keep | |
| `floor_block_on_wall`, `floor_stop_on_slope` | true / true | keep | |
| `motion_mode` | GROUNDED | GROUNDED; switch to FLOATING in flight mode | |
| `up_direction` | +Y | keep | |

### 2.3 Steps, curbs and slopes

- `CharacterBody3D` has **no step-height property** (property list checked [L]). Community controllers add one with raycasts or `test_move` [S67].
- A capsule climbs a step of height *h* without help when the contact normal still counts as floor: *h* ≤ r·(1 − cos `floor_max_angle`). For r = 4 m: **1.17 m at 45°**, 1.43 m at 50° (estimate; derived geometry).
- Rule for city-blockout (estimate): walk paths have no steps above 1.0 m; steps above that get a bevelled `-colonly` proxy at ≤ 35°.
- Where real steps are needed (stairs-like terraces up to 2.5 m), add a step-up pass (estimate). It runs when the body is on the floor, `get_wall_normal()` is roughly horizontal and the horizontal motion was blocked:
  1. `test_move(transform, up × 2.5 m)`
  2. `test_move` the raised transform by the horizontal motion
  3. Cast down 3 m and accept if the landing normal is ≤ 40°
  4. Lerp the visual root over 4 ticks so the camera does not pop

### 2.4 Gravity and flight

- Apply the hero's gravity (56 m/s²) in script and leave `physics/3d/default_gravity` at 9.8 m/s² for props. Debris gets `gravity_scale` 2–3 so falling chunks read at mech scale (estimate).
- Per-tick motion at 120 Hz: walk 18 m/s = 0.15 m, boost 44 m/s = 0.37 m, assault boost 110 m/s = 0.92 m, dash peak 84 m/s = 0.70 m. Character motion is collision-tested along the whole step, so tunnelling is a rigid-body problem, not a hero problem (estimate). Thin railings should still get ≥ 1 m thick `-colonly` proxies [S41].

### 2.5 Collision and Jolt settings (4.7.2 defaults [L])

| Setting | Default | Keep / change |
|---|---|---|
| `physics/common/physics_ticks_per_second` | 60 | 120 (already set). The docs recommend 120/180/240 multiples for fast objects [S41] |
| `max_physics_steps_per_frame` | 8 | Keep. Below 15 fps the game slows rather than spirals [S55] |
| `jolt.../simulation/velocity_steps / position_steps` | 10 / 2 | keep |
| `.../motion_queries/use_enhanced_internal_edge_removal` | true | Keep: it removes ghost bumps when sliding across adjacent collider triangles [S8] |
| `.../queries/enable_ray_cast_face_index` | false | Keep (+25 % ConcavePolygonShape memory if enabled) [S8] |
| `.../limits/max_linear_velocity` | 500 m/s | Keep (rigid bodies only) [S55] |
| `.../limits/world_boundary_shape_size` | 2000 m | Irrelevant if we never use WorldBoundary (rule 6) |
| `.../limits/max_bodies` | 10240 | Enough |
| `physics/3d/run_on_separate_thread` | false | Keep: Jolt errors lose node context when enabled [S55] |

City collision should be boxes wherever possible, `-colonly` trimesh for decks and ramps, and `-convcolonly` for props. "Primitive shapes often have the best performance and reliability" [S9]. Never scale collision shapes; change their extents [S41].

### 2.6 Frame pacing with 120 Hz physics and no interpolation

Physics interpolation exists so that "smooth motion is seen even when physics ticks do not coincide with rendered frames" [S55], and CONTRACTS turns it off. The built-in screen runs at 120 Hz [L]. With vsync on, any frame rate between 60 and 120 gives an alternating 1/2 ticks-per-frame cadence, which judders (estimate).

Fix: `application/run/max_fps = 60`, which gives exactly 2 ticks per frame (with vsync, `max_fps` cannot exceed the refresh rate [S55]). Alternative: enable `physics/common/physics_interpolation`. It disables `physics_jitter_fix` automatically, but it requires `reset_physics_interpolation()` on every teleport [S55][S54].

### 2.7 Projectiles and hit detection

| Weapon (SPEC) | Method | Per-tick cost [L] |
|---|---|---|
| P1 rifle (hitscan, 280/440/600 m) | One `intersect_ray` per shot, `collide_with_areas = true`, mask = enemy hurtboxes + world | 0.59 µs per ray |
| P2 gatling (900 m/s, up to 600 live) | Packed `pos`/`vel` arrays. Each tick, ray from p to p + v·dt (7.5 m). One `MultiMesh.buffer` assignment per tick | **0.28 ms per tick for 600** (sim + rays + buffer) |
| S3 missiles (12 locks, 120→200 m/s) | Packed arrays plus `cast_motion` with a 0.6–1.0 m sphere. Proportional navigation a = N·Vc·λ̇ with **N = 3** [S66]. Turn-rate cap 180–360°/s, arming delay 0.15 s (estimate) | 1.33 µs per sweep |
| Saber arcs, slams, Zenith Lance (800 m × 16 m) | `intersect_shape` or `ShapeCast3D` with a box per active frame. `ShapeCast3D.max_results` defaults to 32 [L]: raise it to 64 for crowds | — |
| Enemy acid lobs | Ballistic packed sim plus segment rays (catchable) | as gatling |

- MultiMesh buffer layout: 12 floats per instance (row-major `Transform3D`), 16 with colour, 20 with colour and custom data [S56].
- Set `MultiMesh.custom_aabb` so the engine never recomputes bounds [S48]. Split tracers into ≤ 4 MultiMeshes by region, because a MultiMesh is culled all-or-nothing [S43][S22].
- Tracers: one quad stretched along velocity, length = v × 1/60 s (15 m at 900 m/s) (estimate).
- Missile smoke: **one** pooled `GPUParticles3D` fed with `emit_particle(xform, vel, color, custom, flags)` at every missile each tick (Forward+ only) [S51]. Do not create one emitter per missile (estimate).
- Enemy movement: 40 capsules (r 4, h 16) doing `move_and_slide` cost **0.63 ms per tick** (15.7 µs each) [L], i.e. 1.26 ms per 60 fps frame. Enemies beyond 300 m tick AI at 30 Hz and snap to the navmesh instead of sliding (estimate).

### 2.8 Animation and procedural rig (the "handsome mechanism")

- **AnimationTree:** `deterministic` defaults to true [L]. `callback_mode_process` is Physics, Idle (default) or Manual [S63]. For **local hit-stop**, put each actor's tree in `MANUAL` and call `advance(dt × local_time_scale)` from `_physics_process`. Set `Skeleton3D.modifier_callback_mode_process` to Physics so IK follows (estimate; method and property verified [L][S63]). Locomotion: BlendSpace2D with `sync_mode = SYNC_MODE_CYCLIC_MUTABLE`, so footsteps stay phase-locked across blends [S63].
- **Modifier stack per mech** (children of `Skeleton3D`, executed in tree order; parent bones above child bones [S63]):

| Modifier | Use |
|---|---|
| `TwoBoneIK3D` | Leg IK on slopes and decks. Deterministic; needs a pole target [S63] |
| `LookAtModifier3D` | Head/sensor tracking of the lock target. Use `use_angle_limitation`, and `duration` 0.08–0.15 s with an ease (estimate). Its `relative` default changed to false in 4.7 [S5] |
| `AimModifier3D` | Pistons: cylinder bone aims at rod bone and vice versa. Smooth, no Euler flips [S63] |
| `CopyTransformModifier3D` / `BoneTwistDisperser3D` | Armour plates following limbs; forearm twist spread [S63] |
| `SpringBoneSimulator3D` | Antennae, cables, cloth skirts. Returns to pose, unlike physical bones [S63] |
| `LimitAngularVelocityModifier3D` | Last in the stack, to stop IK snapping during dash cancels [S57][S63] |
| `ModifierBoneTarget3D` | Exposes a bone as a target for other modifiers [S63] |

- `IterateIK3D` defaults: `max_iterations` 4, `angular_delta_limit` 2°, deterministic off. Off means results carry over between frames [S63].

---

## 3. Navigation in a vertical city

### 3.1 Agent classes (CONTRACTS §7) → navmesh parameters

`agent_radius` is rounded up to whole cells. My r 9 m at a 2 m cell printed "agent_radius is ceiled to cell_size voxel units and loses precision" [L]. Pick radii that are exact multiples of the cell size. Each navigation map must use the same cell size and height as its meshes (`NavigationServer3D.map_set_cell_size/height`); otherwise the `navmesh_cell_size_mismatch` warning fires [L][S12].

| Class (who) | `agent_radius` / `height` / `max_climb` / `max_slope` | `cell_size` / `cell_height` | Map cell size |
|---|---|---|---|
| small (Ripper) | 1.5 / 6 / 1.0 / 40° | 0.5 / 0.25 | 0.5 / 0.25 |
| medium (Mantis, Spitter) | 4.0 / 16 / 2.0 / 40° | 1.0 / 0.5 | 1.0 / 0.5 |
| large (Juggernaut) | 9.0 / 22 / 3.0 / 35° | **1.5** / 0.75 (9 = 6 cells) | 1.5 / 0.75 |

The heights and climbs are estimates; align them with the enemies brief. The 4.7.2 `NavigationMesh` defaults are cell 0.25 m, `agent_radius` 0.5, `agent_height` 1.5, `agent_max_climb` 0.25 and `parsed_geometry_type` = BOTH [L]. All of these are wrong at our scale.

### 3.2 Baking pipeline and measured cost [L]

Test geometry: a synthetic 1.6 × 1.6 km city of 544 box colliders (400 towers 60–300 m tall, sky decks at +100 m, five +40 m elevated roads with ramps). Baked headless, collision only.

| Bake | Partition | Time | Polygons |
|---|---|---|---|
| medium, full map | WATERSHED (default) | **504–532 ms** | 9,041 |
| medium, full map | MONOTONE | 434 ms | 6,103 |
| medium, full map | **LAYERS** | **175,211 ms** | 6,013 |
| large (2.0 m cells), full map | WATERSHED | 123 ms | 6,761 |
| small, full map | WATERSHED | 2,262–2,321 ms | 9,280 |
| small, 400 m chunk | WATERSHED | 116 ms | 636 |
| medium, 400 m chunk | WATERSHED | 28 ms | 596 |

Parsing the 544 colliders took 1–2 ms. The docs suggest monotone or layers "are a lot faster" [S15]. At our scale, layers was ~330× slower. Use WATERSHED, or MONOTONE when fewer polygons matter.

Pipeline:
1. Set `geometry_parsed_geometry_type = STATIC_COLLIDERS` and `geometry_collision_mask = world layer`. Visual meshes must be read back from the GPU, which stalls rendering [S11][S15]. Headless parsing of `ArrayMesh` still works but warns [L].
2. Bake in a tool script (`--headless -s`) and save `.res` per class. City-blockout owns this step (estimate).
3. Use `NavigationObstacle3D` with `affect_navigation_mesh`/`carve_navigation_mesh` or `add_projected_obstruction()` to cut roofs and solid blocks [S18].
4. For destruction or runtime changes, re-bake one 400 m chunk with `bake_from_source_geometry_data_async` (a thread). Use `filter_baking_aabb` plus `border_size` so chunk seams line up [S11]. Parsing always runs on the main thread [S11].

### 3.3 Links for jumps, ledges and lifts

- `NavigationLink3D` connects the polygons nearest its two ends within `link_connection_radius`. The default is 1.0 m. A link with no polygon in range is disabled [S13].
- At our radii, set `map_set_link_connection_radius(map, 1.5 × cell + agent_radius)`: ≈ 2.25 m for small, 5 m for medium, 11 m for large (estimate).
- **A link does no movement.** On `NavigationAgent3D.link_reached`, game code plays the leap, climb or lift and moves the body [S13][L].
- Use `travel_cost` 2–4 on jump links so agents prefer walking (estimate; default 1.0, `enter_cost` 0 [L]). Generate links from the Blender markers `edgejump/drop/vcat…` from the level-design dossier, one per traversal edge.

### 3.4 Sync, queries and budgets

- Navigation changes apply at the next sync, in the middle of the physics frame [S16]. With async region iterations (4.5 default), a freshly set 9k-polygon region took **17 physics frames (≈0.14 s at 120 Hz)** before queries returned paths [L].
- Gate first queries on `map_get_iteration_id(map) > 0` **and** `region_get_iteration_id(rid) > 0` [S14][L].
- Random cross-city `map_get_path` (corridor funnel) averaged **0.70 ms** and ~62 points per path [L]. Rules (estimate):
  - ≤ 6 path queries per tick.
  - Re-path only when the target moved more than 15 m, or every 0.5–1.0 s with a random phase [S15].
  - Use `NavigationPathQueryParameters3D` with `included_regions` (chunk filter) and `path_search_max_polygons` (default 4096 [L]) for far targets [S17].
  - Unreachable targets are the slow case [S15].
- Merging: in the test map, 8,492 of 18,631 edges merged by vertex and 0 by edge connection [L]. Keep regions aligned so vertices weld, because edge connections are costly [S15].

### 3.5 Avoidance (RVO)

- Enable it only on crowd types (Ripper packs). Avoidance "has no information from navigation meshes or physics" [S14].
- Defaults [L]: `neighbor_distance` 50, `max_neighbors` 10, `time_horizon_agents` 1.0 s, `max_speed` **10** (must be set per type), `use_3d_avoidance` false.
- Set `radius` to the body radius. Put each size class on its own `avoidance_layers` bit and give big brutes a higher `avoidance_priority` (estimate).
- The agent needs a `target_position` even if used only for avoidance, otherwise the safe velocity is zero [S14].

### 3.6 Flyers (no navmesh)

- Steering: seek/arrive on a target point at 60–120 m altitude plus separation.
- Sphere-cast 60 m ahead each tick (r 8 m). On a hit, steer along the hit normal.
- Long routes use `AStar3D` over a sparse graph of sky markers exported from Blender (estimate; `AStar3D` exists [L]).
- Optional 3D RVO between flyers: `use_3d_avoidance = true` (separate simulation from 2D agents [S14]).

---

## 4. Performance budget for a 1.5 km city on M1 Max

### 4.1 Measured micro-benchmarks [L]

Setup: Forward+/Metal, 1600×900 windowed, vsync off, sun with 4-split shadows over 600 m, AgX tonemapper, glow on. "Frame" is wall time per frame, which includes the GPU when vsync is off. GPU time itself is unavailable (rule 2).

| Scene | Draw calls | Primitives | Frame ms | Render-thread CPU ms |
|---|---|---|---|---|
| Empty (sun, environment) | 0 | 0 | 4.22 | 0.10 |
| 1,000 boxes, unique materials | 1,625 | 19.5 k | 4.72 | 0.50 |
| 3,000 boxes, unique materials | 4,886 | 58.6 k | 7.36 | 1.37 |
| Same, sun shadows off | 2,701 | 32.4 k | 7.41 | 1.02 |
| 3,000 boxes, one shared material (auto-instancing) | 17 | 58.6 k | 3.44 | 0.49 |
| 10,000 boxes, one shared material | 16 | 192 k | 3.78 | 1.12 |
| MultiMesh, 100,000 boxes | 4 | 4.8 M | 4.20 | 0.13 |
| 3,000 × 2,400-tri meshes, 64 materials ("city-like") | 931 | 12.3 M | 4.31 | 0.79 |
| … + 64 omni lights without shadows | 931 | 12.3 M | 4.27 | 0.79 |
| … + 16 static shadowed omni lights | 931 | 12.3 M | 4.26 | 0.84 (VRAM 124→184 MB) |
| … + 20 GPUParticles3D × 2,000 | 971 | 12.5 M | 4.90 | 0.91 |
| … + SSAO + SSR + volumetric fog | 931 | 12.3 M | 5.37 | 0.89 (VRAM 240 MB) |

How to read it:
- Unique materials are the real CPU cost: 3,000 unique objects added ~3 ms per frame.
- Forward+ automatic instancing (same mesh plus same material) collapses draws [S19].
- Static shadowed omni lights are nearly free after their first render, because positional shadows are cached [S23].
- The GPU has headroom at 1600×900.

Physics and navigation [L]: see §2.7 and §3.2–3.4.

### 4.2 Budget (CONTRACTS §2 refined)

| Resource | Budget | Basis |
|---|---|---|
| Draw calls (`RENDER_TOTAL_DRAW_CALLS_IN_FRAME`) | ≤ 3,500 at the busiest view; aim < 2,000 | [L]: 4.9 k draws cost ~3 ms CPU (estimate) |
| Unique materials in view | ≤ 150; share materials and trim sheets | "The fewer different materials in the scene, the faster the rendering will be" [S49] |
| Primitives monitor | ≤ 20 M. It counts vertices or indices across depth and shadow passes, "typically double or triple the original vertex count" [S47] | [L] 12.3 M was cheap; replaces the "6 M triangles" wording (estimate) |
| Clustered elements per view (lights + decals + probes) | ≤ 400 of 512 | [S23][S55]; leaves margin before pop-in |
| Shadowed positional lights in frustum | ≤ 16 (atlas holds 88) | CONTRACTS; [S23] |
| Directional lights | 1 (max 8; each extra one shares the atlas) | [S23] |
| Area lights | 0 in gameplay; ≤ 1 in title or victory shots | [S23] |
| Live GPU particles | ≤ 60 k | [L] 40 k cost ~0.6 ms (estimate) |
| Decals | ≤ 150 visible, ring buffer of 256 | Decal cost is mostly screen coverage [S31] (estimate) |
| Enemies with full AI + `move_and_slide` | ≤ 40 | [L] 1.26 ms per frame |
| Projectiles | ≤ 600 bullets + 48 missiles | [L] |
| VRAM | Watch `RENDER_VIDEO_MEM_USED`; unified 32 GB, keep < 6 GB (estimate) | [S47] |

### 4.3 Lighting and shadows at city scale

- **Sun (DirectionalLight3D).** Defaults [L]: PSSM 4 splits at 0.1/0.2/0.5, `max_distance` 100 m, fade start 0.8, pancake 20 m, bias 0.1, normal bias 2.0. Use (estimate):
  - `directional_shadow_max_distance` 500
  - splits 0.05 / 0.15 / 0.40 (25 / 75 / 200 / 500 m)
  - `blend_splits` off
  - Raise `pancake_size` only if 300 m towers lose shadows [S23]
  - Atlas: keep 4096, 16-bit (project already sets this) [S55]
- Objects present in all 4 splits are drawn 5 times [S23]. Cut buildings into ≤ 60 m chunks at export (estimate).
- **Omni and spot lights.** Muzzle flashes and explosions get no shadows, a ≤ 0.25 s life, `distance_fade` on, and `light_volumetric_fog_energy = 0`. Short-lived lights ghost in volumetric fog [S24]. Use `light_bake_mode = DISABLED` for short effects [S26].
- Static shadowed lamps stay cached unless a caster moves inside them [S23]. Set their `shadow_caster_mask` to exclude the enemy and player render layers (estimate; property exists [L]).
- Spot shadows fail above 89° [S23].
- **GI.** There is nothing new in 4.5–4.7.
  - SDFGI defaults: 4 cascades, 0.2 m min cell, 204.8 m reach [L]. City estimate: 6 cascades and a 0.6 m min cell, on the high preset only. SDFGI suits large structures but moving emitters don't contribute [S26].
  - SSIL works as a cheap complement [S26].
  - Set `gi_mode` Disabled on enemies and debris [S26].
- **Volumetric fog.** The default length is 64 m [L]. Set 250–400 m with detail spread 2–3, and add depth fog for the far skyline. Volumetric fog has finite range [S24]. The 4.6 blending change makes fog brighter than older tutorials suggest [S6].
- **AA and upscaling.**
  - The project currently runs FXAA (`screen_space_aa=1`) **and** TAA. Together they set a −0.75 mip bias, which makes textures grainy in motion [S36]. Switch to TAA alone (=0).
  - SMAA (=2) is the option for a non-temporal low preset [S35][L].
  - At 2560×1440 (3.69 MPix [S36]) or fullscreen on the built-in 3024×1964 panel, try `scaling_3d/mode.macos = 4` (MetalFX Temporal) at 0.67–0.75. That renders 1715×964–1920×1080 at 1440p [S36][S55].
  - FSR 2.2 at 1.0 is the quality option when headroom allows [S35].
- **Tonemapping.** AgX defaults: `agx_white` 16.29, `agx_contrast` 1.25 [L]. Glow default blend is Screen, intensity 0.3 [L][S6].

### 4.4 Culling stack

1. **Occlusion.** Enabled in `project.godot`. Bake from `-occonly` facade and deck proxies. Only `MeshInstance3D` sources are baked automatically [S20]. Don't move occluders. Buffer ≈ 512 rays × 10 logical cores [S55][S20].
2. **HLOD.** Per 100 m block, detail meshes end at 300 m (margin 30) and a merged block mesh begins at 300 m, fade mode Disabled (estimate; mechanism [S21]). Use `visibility_parent` for nesting [S21].
3. **Mesh LOD.** On by default for glTF [L]. The 1-pixel threshold is "perceptually lossless" [S22]. Try `mesh_lod_threshold` 2.0 on the medium preset (estimate).
4. **Shadow casters.** `cast_shadow` off for small props, decals and particles. Visibility ranges also apply to GPUParticles3D [S21].
5. Keep the map centred: ±800 m is far inside the 4096–8192 m single-precision guidance for third-person 3D [S42].

### 4.5 How to measure (and what lies)

- **In game:** `Performance.get_monitor()` with `TIME_PROCESS`, `TIME_PHYSICS_PROCESS`, `TIME_NAVIGATION_PROCESS`, `RENDER_TOTAL_DRAW_CALLS_IN_FRAME`, `RENDER_TOTAL_PRIMITIVES_IN_FRAME`, `RENDER_VIDEO_MEM_USED`, `NAVIGATION_3D_*`, and `PIPELINE_COMPILATIONS_{CANVAS,MESH,SURFACE,DRAW,SPECIALIZATION}` [S47][L]. Per-subsystem counters go through `Performance.add_custom_monitor("Game/Enemies", callable)` [S47].
- `RenderingServer.get_rendering_info()` returns 0 until 2 frames have rendered [S56]. CPU render time comes from `viewport_set_measure_render_time` + `viewport_get_measured_render_time_cpu` + `get_frame_setup_time_cpu` [L].
- **GPU on Metal:** use frame time with `--disable-vsync`, `MTL_HUD_ENABLED=1 godot …` [S64], or the Xcode Metal frame debugger [S59].
- **Shader stutter:** any rise in `PIPELINE_COMPILATIONS_DRAW` during gameplay is a stutter. `SURFACE` rising mid-game means a feature was first seen late, e.g. an omni-shadow mode, a ReflectionProbe, VoxelGI or SDFGI [S25]. Fix it with a hidden warm-up instance of every VFX scene under the player at load [S25].
- **Depth prepass experiment** (estimate): set `rendering/driver/depth_prepass/disable_for_vendors = "PowerVR,Mali,Adreno"` (Apple removed). Compare frame time in the densest street view. Keep the change only if it is faster [S55].

### 4.6 Pitfalls

- A `MultiMesh` spread over the whole map is never culled: split it per region [S43].
- Alpha-blended or depth-prepass materials are never auto-instanced [S19].
- Mesh LOD is chosen from the AABB point nearest the camera. Give `GPUParticles3D` a generated visibility AABB [S22][S28].
- `amount_ratio` does not save GPU time [S51]. `GPUParticles3D.fixed_fps` defaults to 30 [L]: raise it to 60 for fast or colliding sparks [S28].
- Changing MSAA level, toggling SDFGI, or adding the first ReflectionProbe or VoxelGI mid-game triggers pipeline compiles [S25]. Do it only in menus.

---

## 5. Headless / CI usage

| Task | Command | Headless? |
|---|---|---|
| Import | `godot --headless --path game --import` [S33] | yes |
| Script, test or check | `godot --headless --fixed-fps 120 --path game -s res://tools/test_host.gd -- …` (args after `--` come from `OS.get_cmdline_user_args()`) [S33] | yes. Use `_initialize()` plus a deferred first frame, because nodes are not inside the tree during `_init` [L] |
| Navmesh bake | `-s` tool script, colliders only | yes [L] |
| Screenshot | Windowed. `await RenderingServer.frame_post_draw`, then `get_viewport().get_texture().get_image()` [S53][L] | **no** (dummy renderer) |
| Movie | `godot --path game --write-movie /abs/out.png --fixed-fps 60 --quit-after N --resolution 1600x900` [S34][S33]. PNG+WAV or AVI; OGV only from editor builds [S34] | **no**: crashed with signal 11 in headless [L] |
| GPU perf | Windowed, `--disable-vsync`, optionally `MTL_HUD_ENABLED=1` | no |
| Export with shader baker | Windowed editor export. "Not supported when exporting… using --headless" [S25] | no |

**Input simulation.**
- `Input.action_press(action, strength)` only drives `is_action_pressed`/`just_pressed`; it does not call `_input`. Use `Input.parse_input_event(ev)` to generate `_input` calls, e.g. `InputEventAction`, `InputEventKey`, `InputEventMouseMotion` with `relative` [S46].
- In 4.7, mark synthetic key and mouse events `device = InputEvent.DEVICE_ID_KEYBOARD` (16) or `DEVICE_ID_MOUSE` (32) if code filters on device [S5][L].
- Input accumulation (default on) merges motion events per frame [S46]. Read the accumulated mouse delta once per physics tick.

**Determinism checklist** (estimate unless cited):
- `--fixed-fps N` disables real-time sync [S33]. Use it for every test, with 120 Hz physics.
- Seed every `RandomNumberGenerator` from `--seed`. Never read wall time (`Time.get_ticks_*`) in gameplay.
- Set `GPUParticles3D.use_fixed_seed` for capture shots [L].
- Leave `AnimationTree.deterministic = true` (default) [L].
- Jolt is deterministic when API calls happen in the same order [S65]. Do not spawn bodies from unordered dictionaries.
- Navigation sync is asynchronous by default [S55]. In tests, set `navigation/world/map_use_async_iterations=false` and `region_use_async_iterations=false` before asserting paths.

---

## 6. Post-process recipes in stock 4.7

### 6.1 Where to hook

| Hook | Sees | Use for |
|---|---|---|
| `CanvasLayer` (layer 50, below the HUD) > full-rect `ColorRect`, `canvas_item` shader with `hint_screen_texture` [S39] | Final tonemapped 3D + 2D below it | Radial blur, chromatic aberration, flash, vignette, impact frames, speed lines (juice dossier §4 already has the shader) |
| `MeshInstance3D` QuadMesh 2×2 (flip faces) with `POSITION = vec4(VERTEX.xy, 1.0, 1.0)`, child of the camera, `extra_cull_margin` max [S38] | Linear HDR scene + `hint_depth_texture` (reversed-Z: 1 = near) + `hint_normal_roughness_texture` [S38][S39] | Depth-aware shock-wave rings, scan pulse, fog-of-war tint |
| `CompositorEffect` on `Camera3D.compositor` (callbacks Pre/Post Opaque, Post Sky, Pre/Post Transparent) [S32][L] | Raw render buffers before upscaling ("internal size") [S32] | Compute effects, pre-tonemap bloom tricks. Verified working on Metal: red→gray readback [L] |
| `Environment` adjustments, glow map, colour-correction LUT [S37] | — | Grading, low-HP desaturation |

### 6.2 Radial blur, chromatic aberration, flash

Use the juice dossier shader (8 taps, `filter_linear_mipmap`). Notes:
- Hide the node when all strengths are 0. A visible full-screen pass costs fill rate (estimate).
- The compute compositor template reads and writes the same image, so blurs need a copy pass (estimate). That is why the canvas path is the default.

### 6.3 Speed lines (two layers)

- **Screen layer, no screen read (cheapest).** Draw in polar UV: `a = atan(d.y, d.x)`, `r = length(d)`; lines = `step(0.92, noise(vec2(a * 40.0, TIME * 6.0)))`. Mask with `smoothstep(0.45, 0.8, r)` and set opacity to 0.35 × speed factor above 70 % of boost (numbers from juice dossier; estimate).
- **World layer.** One `GPUParticles3D` parented to the camera: 300 streak quads, `transform_align = Y_TO_VELOCITY`, emitted 40–80 m ahead and moving at −speed. This sells flight parallax (estimate; alignment option from [S27]).

### 6.4 Heat haze (thrusters, explosions) (sketch, estimate)

```glsl
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D noise_tex : repeat_enable;   // NoiseTexture2D, seamless
uniform float strength = 0.012;                 // UV offset at the centre
uniform float scroll = 1.6;                     // UV/s upward
void fragment() {
    vec2 n = texture(noise_tex, UV * 2.0 + vec2(0.0, -TIME * scroll)).rg * 2.0 - 1.0;
    float mask = smoothstep(0.0, 0.35, 1.0 - length(UV - 0.5) * 2.0);
    ALBEDO = textureLod(screen_tex, SCREEN_UV + n * strength * mask, 0.0).rgb;
    ALPHA = mask;
}
```

Put it on billboard quads or particles behind the nozzles. The 3D screen texture is captured after the opaque pass, so haze will not refract smoke or other transparents [S39].

### 6.5 Cockpit HUD (first person)

- Use a `SubViewport` with:
  - `disable_3d = true` and `transparent_bg = true`
  - `size` 1024×512 (estimate)
  - `render_target_update_mode = UPDATE_ALWAYS` (default `WHEN_VISIBLE`=2 [L]) [S53]
- It holds the diegetic `Control` HUD. Its `ViewportTexture` goes on the canopy and dash meshes: unshaded, emissive, alpha.
- Cockpit meshes: `ignore_occlusion_culling = true` (the docs' first-person model case [S20]), `cast_shadow` off, their own render layer (estimate).
- The flat HUD stays a normal `CanvasLayer` on top. SubViewports receive input only through a `SubViewportContainer`; this HUD is display-only [S53].
- In 4.7, `Control` offset transforms let hit markers bounce inside containers [S1].

### 6.6 Enemy highlight and hit flash

- **Lock target outline / through-wall silhouette.** On the base StandardMaterial3D, set `stencil_mode = Outline` or `X-Ray` (also `stencil_color`, `stencil_outline_thickness`, default 0.01 m [L]). These modes add a preconfigured stencil `next_pass` [S52].
  - Stencil materials render in the transparent pass, so apply this to ≤ 3 enemies at once (estimate) [S52].
  - Outlines need welded, smooth-shaded vertices [S52]. Check Tripo meshes for gaps at UV seams and fall back to the fresnel overlay if they show.
- **Hit flash plus fresnel without duplicating materials.** Use one shared `material_overlay` ShaderMaterial with `instance uniform float hit_flash` and `instance uniform vec4 highlight`, set per enemy through `set_instance_shader_parameter()`. Verified on Metal: per-instance flash worked on overlays and on main materials [L].

```glsl
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, fog_disabled;
instance uniform float hit_flash = 0.0;
instance uniform vec4 highlight = vec4(0.0);   // rgb + strength
void fragment() {
    float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
    ALBEDO = vec3(1.0, 0.25, 0.1) * hit_flash + highlight.rgb * highlight.a * fres;
}
```

The overlay is an extra pass, so assign it only while `hit_flash > 0` or a highlight is active (estimate).

---

## 7. Project settings and node choices checklist

Current `game/project.godot` values that should stay: Jolt, 120 Hz, interpolation off, Forward+, Metal, TAA, occlusion culling on, directional shadow 4096.

```ini
[application]
run/max_fps=60                                   ; §2.6: exactly 2 ticks/frame on the 120 Hz panel (estimate)
[input_devices]
joypads/ignore_joypad_on_unfocused_application=true   ; 4.7: several game windows run at once [S1]
[rendering]
anti_aliasing/quality/screen_space_aa=0          ; TAA only; FXAA+TAA = -0.75 mip bias [S36]
anti_aliasing/quality/use_taa=true
scaling_3d/mode.macos=0                          ; 1440p/fullscreen preset: 4 (MetalFX Temporal) @ 0.75
textures/default_filters/anisotropic_filtering_level=3   ; 8x (currently 16x) (estimate)
limits/cluster_builder/max_clustered_elements=512 ; keep; budget ≤ 400 in view [S55]
lights_and_shadows/positional_shadow/atlas_size=4096  ; quadrants 4/4/16/64 = 88 slots [S23]
environment/volumetric_fog/volume_size=64        ; defaults; 96 on high (estimate)
environment/volumetric_fog/volume_depth=64
rendering_device/pipeline_cache/enable=true      ; default; on-disk pipeline cache speeds up later runs [S55]
[physics]
jolt_physics_3d/simulation/allow_sleep=true      ; default
[navigation]
3d/default_cell_size=1.0                         ; medium map; small/large maps call map_set_cell_size
3d/default_cell_height=0.5
3d/default_link_connection_radius=5.0            ; medium; per map otherwise (estimate)
```

Nodes and settings per system:
- **Hero:** CharacterBody3D, capsule r 4 / h 14, snap 1.5–2.0 m, 40° max floor angle.
- **Enemies:** CharacterBody3D. NavigationAgent3D for ground types (`path_desired_distance` = 1.5 × radius, `target_desired_distance` = 2 × radius, `max_speed` set) (estimate). FLOATING mode for flyers.
- **Projectiles:** managers holding packed arrays plus MultiMeshInstance3D (custom AABB). One pooled GPUParticles3D per effect type, fed with `emit_particle`.
- **Debris:** RigidBody3D with `gravity_scale` 2–3.
- **Moving platforms:** AnimatableBody3D.
- **Camera:** `SpringArm3D` for collision; Camera3D `near` 0.1, `far` 4000 (default far is 4000 [L]).
- **Sun:** DirectionalLight3D with max distance 500 and splits 0.05/0.15/0.40. **Environment:** AgX tonemapper; glow at Screen blend, intensity 0.3–0.6.
- **Culling:** OccluderInstance3D baked from `-occonly`. Visibility ranges for HLOD blocks.
- **Decals:** distance fade begin 150 m / length 30 m and `normal_fade` 0.3 (estimate; defaults 40/10 m and 0 [L]).
- **Post:** CanvasLayer FX at layer 50; CompositorEffect only for compute.
- **Import:** keep `generate_lods`, `create_shadow_meshes` and `nodes/use_node_type_suffixes` on (all defaults [L]). A post-import script (`EditorScenePostImport._post_import(scene)` [S10]) assigns collision layers and masks, puts navmesh source colliders on the world layer, and reads Blender extras.

---

## 8. Do / Don't for M78 coding agents

**Do**
1. Simulate gameplay in `_physics_process` at 120 Hz. Read input once per tick.
2. Keep bullets and missiles in `PackedVector3Array`/`PackedFloat32Array`. Push one `MultiMesh.buffer` per tick, using 12/16/20 floats per instance [S56].
3. Use `PhysicsDirectSpaceState3D.intersect_ray/cast_motion/intersect_shape` in code, reusing one query-parameters object (estimate).
4. Set `collide_with_areas = true` on attack queries that must hit `Hurtbox` areas (default false [L]).
5. Gate navigation on both iteration IDs; stagger re-paths; cache paths for 0.5–1 s. React to `link_reached` with scripted traversal [S13].
6. Instance one hidden copy of every VFX and projectile scene at level load to precompile pipelines [S25].
7. Use `set_instance_shader_parameter` for per-enemy tints and flashes; share materials.
8. Name Blender helpers with suffixes (`-colonly`, `-convcolonly`, `-occonly`, `-noimp`) and keep collision proxies primitive [S9].
9. Report `Performance` monitors (draw calls, primitives, pipeline compilations, nav time) in every `perf` capture.
10. Give every `NavigationMesh` an agent radius that is a multiple of its cell size, and set its map's cell size to match.

**Don't**
1. Don't use `RigidBody3D`, `Area3D` or a node per bullet. Don't use rigid bodies above 500 m/s [S55].
2. Don't use `WorldBoundaryShape3D` (Jolt size cap; 4.7 sign flip) [S5][S8].
3. Don't bake navmeshes from visual meshes at runtime [S15], and don't use the `LAYERS` partition [L].
4. Don't call `map_get_path` or `set_target_position` for every agent every frame [S15].
5. Don't add `AreaLight3D` or shadowed omni lights on moving rigs in gameplay, and keep PCSS (`light_size` > 0) to a handful of lights [S23].
6. Don't enable FXAA together with TAA [S36]. Don't toggle MSAA or SDFGI during play [S25].
7. Don't scale collision shapes or navmesh source nodes [S41][S15].
8. Don't rely on defaults changed in 4.6/4.7. Set `MeshInstance3D.skeleton`, `LookAtModifier3D.relative` and BlendSpace `sync_mode` explicitly [S6][S5].
9. Don't read `Time.get_ticks_*` or unseeded randomness in gameplay code (determinism).
10. Don't put `hint_screen_texture` materials on many overlapping objects. Each one counts as transparent, and the 3D capture happens only once [S39].

---

## 9. Locally verified (scripts in `/Users/minimax/m/mecha-city/tmp/research/godot-tech/proj/`)

| Script | Proved |
|---|---|
| `check.gd`, `check2–7.gd` | Class existence (§1.3); 4.7.2 setting defaults and default properties quoted throughout; stencil properties; 42 methods/signals; device-ID constants; screens (120 Hz built-in, HDR) |
| `navbench.gd`, `navbench2.gd` | Bake times (§3.2), headless mesh parsing, sync latency, path query cost |
| `physbench.gd`, `bulletbench.gd` | Ray, sweep and `move_and_slide` costs; 600-bullet cost; MultiMesh buffer empty in headless |
| `renderbench.gd`, `renderbench2.gd` | §4.1 table; Metal GPU time = 0 |
| `compositor_check.gd` + `gray_effect.gd`; `overlay_check2.gd` | Compute `CompositorEffect` on Metal; shared overlay + per-instance uniforms |
| `make_glb.gd`, `read_import.gd` | `-colonly` → StaticBody3D + ConcavePolygonShape3D; `-col` → MeshInstance3D + child StaticBody3D; `-convcolonly` → ConvexPolygonShape3D; `-occonly` → OccluderInstance3D; `-navmesh` → NavigationRegion3D; `-noimp` removed. Defaults `generate_lods=true`, `create_shadow_meshes=true`, `animation/fps=30`, `gltf/naming_version=2` |
| `movie_headless.gd` | `--headless --write-movie` crashes |

---

## 10. Sources

- [S1] Godot 4.7 release — https://godotengine.org/releases/4.7/
- [S2] Godot 4.6 release — https://godotengine.org/releases/4.6/
- [S3] Godot 4.5 release — https://godotengine.org/releases/4.5/
- [S4] Godot 4.4 release — https://godotengine.org/releases/4.4/
- [S5] Upgrading 4.6→4.7 — https://docs.godotengine.org/en/4.7/tutorials/migrating/upgrading_to_godot_4.7.html
- [S6] Upgrading 4.5→4.6 — https://docs.godotengine.org/en/4.7/tutorials/migrating/upgrading_to_godot_4.6.html
- [S7] Upgrading 4.4→4.5 — https://docs.godotengine.org/en/4.7/tutorials/migrating/upgrading_to_godot_4.5.html
- [S8] Using Jolt Physics — https://docs.godotengine.org/en/4.7/tutorials/physics/using_jolt_physics.html
- [S9] Node type customization (suffixes) — https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_3d_scenes/node_type_customization.html
- [S10] Import configuration / import scripts — https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_3d_scenes/import_configuration.html
- [S11] Using navigation meshes — https://docs.godotengine.org/en/4.7/tutorials/navigation/navigation_using_navigationmeshes.html
- [S12] Support different actor types — https://docs.godotengine.org/en/4.7/tutorials/navigation/navigation_different_actor_types.html
- [S13] Using NavigationLinks — https://docs.godotengine.org/en/4.7/tutorials/navigation/navigation_using_navigationlinks.html
- [S14] Using NavigationAgents — https://docs.godotengine.org/en/4.7/tutorials/navigation/navigation_using_navigationagents.html
- [S15] Optimizing navigation performance — https://docs.godotengine.org/en/4.7/tutorials/navigation/navigation_optimizing_performance.html
- [S16] Using NavigationServer — https://docs.godotengine.org/en/4.7/tutorials/navigation/navigation_using_navigationservers.html
- [S17] NavigationPathQueryObjects — https://docs.godotengine.org/en/4.7/tutorials/navigation/navigation_using_navigationpathqueryobjects.html
- [S18] Using NavigationObstacles — https://docs.godotengine.org/en/4.7/tutorials/navigation/navigation_using_navigationobstacles.html
- [S19] Optimizing 3D performance — https://docs.godotengine.org/en/4.7/tutorials/performance/optimizing_3d_performance.html
- [S20] Occlusion culling — https://docs.godotengine.org/en/4.7/tutorials/3d/occlusion_culling.html
- [S21] Visibility ranges (HLOD) — https://docs.godotengine.org/en/4.7/tutorials/3d/visibility_ranges.html
- [S22] Mesh LOD — https://docs.godotengine.org/en/4.7/tutorials/3d/mesh_lod.html
- [S23] 3D lights and shadows — https://docs.godotengine.org/en/4.7/tutorials/3d/lights_and_shadows.html
- [S24] Volumetric fog — https://docs.godotengine.org/en/4.7/tutorials/3d/volumetric_fog.html
- [S25] Reducing stutter from pipeline compilations — https://docs.godotengine.org/en/4.7/tutorials/performance/pipeline_compilations.html
- [S26] Introduction to global illumination — https://docs.godotengine.org/en/4.7/tutorials/3d/global_illumination/introduction_to_global_illumination.html
- [S27] 3D particle trails — https://docs.godotengine.org/en/4.7/tutorials/3d/particles/trails.html
- [S28] 3D particle collisions — https://docs.godotengine.org/en/4.7/tutorials/3d/particles/collision.html
- [S29] Particle sub-emitters — https://docs.godotengine.org/en/4.7/tutorials/3d/particles/subemitters.html
- [S30] 3D particle attractors — https://docs.godotengine.org/en/4.7/tutorials/3d/particles/attractors.html
- [S31] Using decals — https://docs.godotengine.org/en/4.7/tutorials/3d/using_decals.html
- [S32] The Compositor — https://docs.godotengine.org/en/4.7/tutorials/rendering/compositor.html
- [S33] Command line tutorial — https://docs.godotengine.org/en/4.7/tutorials/editor/command_line_tutorial.html
- [S34] Creating movies — https://docs.godotengine.org/en/4.7/tutorials/animation/creating_movies.html
- [S35] 3D antialiasing — https://docs.godotengine.org/en/4.7/tutorials/3d/3d_antialiasing.html
- [S36] Resolution scaling — https://docs.godotengine.org/en/4.7/tutorials/3d/resolution_scaling.html
- [S37] Environment and post-processing — https://docs.godotengine.org/en/4.7/tutorials/3d/environment_and_post_processing.html
- [S38] Advanced post-processing — https://docs.godotengine.org/en/4.7/tutorials/shaders/advanced_postprocessing.html
- [S39] Screen-reading shaders — https://docs.godotengine.org/en/4.7/tutorials/shaders/screen-reading_shaders.html
- [S40] Ray-casting — https://docs.godotengine.org/en/4.7/tutorials/physics/ray-casting.html
- [S41] Troubleshooting physics issues — https://docs.godotengine.org/en/4.7/tutorials/physics/troubleshooting_physics_issues.html
- [S42] Large world coordinates — https://docs.godotengine.org/en/4.7/tutorials/physics/large_world_coordinates.html
- [S43] Optimization using MultiMeshes — https://docs.godotengine.org/en/4.7/tutorials/performance/using_multimesh.html
- [S44] Overview of renderers — https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html
- [S45] CharacterBody3D — https://docs.godotengine.org/en/4.7/classes/class_characterbody3d.html
- [S46] Input — https://docs.godotengine.org/en/4.7/classes/class_input.html
- [S47] Performance — https://docs.godotengine.org/en/4.7/classes/class_performance.html
- [S48] MultiMesh — https://docs.godotengine.org/en/4.7/classes/class_multimesh.html
- [S49] GPU optimization — https://docs.godotengine.org/en/4.7/tutorials/performance/gpu_optimization.html
- [S50] PhysicsDirectSpaceState3D — https://docs.godotengine.org/en/4.7/classes/class_physicsdirectspacestate3d.html
- [S51] GPUParticles3D — https://docs.godotengine.org/en/4.7/classes/class_gpuparticles3d.html
- [S52] Standard Material 3D (stencil, grow, next pass) — https://docs.godotengine.org/en/4.7/tutorials/3d/standard_material_3d.html
- [S53] Using Viewports — https://docs.godotengine.org/en/4.7/tutorials/rendering/viewports.html
- [S54] Physics interpolation quick start — https://docs.godotengine.org/en/4.7/tutorials/physics/interpolation/physics_interpolation_quick_start_guide.html
- [S55] ProjectSettings — https://docs.godotengine.org/en/4.7/classes/class_projectsettings.html
- [S56] RenderingServer — https://docs.godotengine.org/en/4.7/classes/class_renderingserver.html
- [S57] Inverse Kinematics Returns to Godot 4.6 (blog) — https://godotengine.org/article/inverse-kinematics-returns-to-godot-4-6/
- [S58] HDR output arrives in Godot 4.7 (blog) — https://godotengine.org/article/hdr-output-arrives-in-godot-4-7/
- [S59] GH #102968 Metal GPU profiling/frametime does not work (fixed in 4.8, no backport) — https://github.com/godotengine/godot/issues/102968
- [S60] GH #106757 First load extremely slow due to Metal shader compilation — https://github.com/godotengine/godot/issues/106757
- [S61] GH #123481 macOS 26 Metal pipeline-creation deadlock — https://github.com/godotengine/godot/issues/123481
- [S62] GH #120621 4.7 crash on macOS 12; Metal requires macOS 13+ — https://github.com/godotengine/godot/issues/120621
- [S63] Class reference XML at tag 4.7.2-stable (TwoBoneIK3D, IterateIK3D, AimModifier3D, ModifierBoneTarget3D, LimitAngularVelocityModifier3D, BoneTwistDisperser3D, SpringBoneSimulator3D, LookAtModifier3D, CopyTransformModifier3D, AnimationNodeBlendSpace2D, AnimationMixer, Skeleton3D, AreaLight3D) — https://github.com/godotengine/godot/tree/4.7.2-stable/doc/classes
- [S64] Apple: Monitoring your Metal app's graphics performance (MTL_HUD_ENABLED) — https://developer.apple.com/documentation/xcode/monitoring-your-metal-apps-graphics-performance
- [S65] Jolt Physics architecture: deterministic simulation — https://jrouwe.github.io/JoltPhysics/
- [S66] Palumbo, Blauwkamp, Lloyd, "Basic Principles of Homing Guidance", JHU APL Tech. Digest 29(1) — https://secwww.jhuapl.edu/techdigest/content/techdigest/pdf/V29-N01/29-01-Palumbo_Principles_Rev2018.pdf
- [S67] godot-proposals #2751 automatic stair step-up for CharacterBody — https://github.com/godotengine/godot-proposals/issues/2751
