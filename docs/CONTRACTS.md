# MECHA CITY — CONTRACTS (lead-owned)

Read with `docs/PLAN.md` (units, waves) and `docs/SPEC.md` (design numbers). This file defines what every
unit may rely on and must provide. Changing a contract is the lead's job: put requests in your status file.

## 1. Repo layout and ownership

| Path | Owner | What |
|---|---|---|
| `docs/**`, `game/project.godot`, `game/main.*`, `game/core/**`, `tools/*.sh`, `tools/*.py`, `tools/workers/**`, `tools/tripo/**`, `tools/concept/**`, `blender/lib/**`, `blender/tools/**`, `art/**`, `briefs/**`, `reviews/**`, `status/**`, `ref/**`, `data/hero_motions.json` | lead | contracts, autoloads, shared types, sandbox, shared Blender lib, process docs, concept images and raw Tripo downloads (git-ignored binaries) |
| `tools/godot.sh`, `tools/godot_import.sh`, `tools/blender.sh`, `tools/slots.py`, `tools/import_doctor.py`, `tools/suites.sh`, `tools/suites.txt`, `tools/owners.py`, `tools/scrub_check.py`, `tools/pck_list.py`, `game/tools/**`, `game/core/tests/**`, `game/core/input_setup.gd`, `game/core/pad_input.gd`, `game/core/input_quad.gd`, `game/export_presets.cfg`, `README.md`, `.gitignore`, `status/tooling.md` | tooling | wrappers and slot pool, test host + fixtures, capture/autoplay/perf probes, the suite list, packaging (preset, README, PCK inspector), InputSetup/PadInput/F3 input quad |
| `game/player/mech/**`, `game/player/player_mech.tscn`, `game/player/model/placeholder/**` | mech-move | PlayerMech root, locomotion, energy, damage pipeline, component loader |
| `game/player/camera/**`, `game/player/aim/**` | camera-aim | camera rig (3rd/1st person), lock-on, AimSystem |
| `game/player/model/hero3/**`, `blender/hero3/**` | hero-v3 | the hero mech model (rig, sockets, animations, wings, weapons); replaced hero-asset's `hero/**` |
| `game/combat/weapons/**`, `game/combat/projectiles/**` | weapons | beam rifle, gatling, railgun, missiles, shot framework |
| `game/combat/melee/**`, `game/combat/defense/**` | melee-defense | saber combos, dash slash, finishers, shield block, perfect parry |
| `game/combat/skills/**` | skills | barrier, feather drones, gravity slam, grapple anchor, overdrive, ultimate |
| `game/fx/**` | feel | FeelDirector, FeelEvent table, post-process, VFX library, decals |
| `game/enemies/**` | enemies | EnemyBase, AI, navigation use, archetypes, spawner |
| `game/enemies/boss/**` | boss | the Brood Titan fight (carved out of enemies) |
| `game/enemies/models/**`, `blender/monsters/**`, `data/monster_motions/**` | monster-assets | rigged monster model scenes + animation libraries |
| `game/ui/**` | hud | HUD, cockpit overlay, menus, damage numbers |
| `game/audio/**` (incl. the `Audio` autoload body), `tools/sfx/**`, `art/audio_src/**` | audio | sound bank, music, mixing, the SFX build tools and their source records |
| `blender/city/**`, `game/world/city/**`, `game/world/city.tscn`, `game/world/city.gd`, `game/world/city/tools/**`, `tools/city/**`, `data/vistas.json`, `data/vistas.proposed.json` | city-build | procedural city geometry, collision, navmesh, tiles, the offline bake/check tools and the vista solves |
| `game/world/art/**`, `game/world/props/**`, `game/world/post/**`, `blender/props/**`, `game/assets/**`, `tools/textures/**`, `data/props_list.json` | city-art | materials, shaders, environment, props, landmark dressing, the post stack and the shared CC0 texture library |
| `game/world/kit/**`, `tools/citykit/**`, `blender/citykit/**`, `data/map/kit_assign.json` | city-kit | the Tripo kit assets, their processing/QA tools and the layout→kit assignment |
| `tools/map/**`, `data/map/**` | city-layout | the layout solver, the district rules and the level graph |
| `game/world/traversal/**` | traversal | the connector runtime (lifts, vents, vcats, lcats, stairs, edgejumps) |
| `game/trailer/**`, `tools/trailer/**` | trailer | the trailer stages, camera rigs and render pipeline |
| `game/flow/**` | flow | encounters, objectives, boss fight script, title/victory flow |

**Precedence: the most specific row wins** (the longest literal prefix before the first wildcard). A file
with no row, or two rows of equal specificity, is a bug in this table: `python3 tools/owners.py` reports
both and exits 1. `.import` and `.uid` sidecars belong to their source file.

Tests live in `<your folder>/tests/test_*.gd` (`extends Node`, run with `tools/godot.sh test`).

## 2. Conventions
- Godot: Y up, -Z forward, metres, seconds, radians in code (degrees only in tuning tables). Blender: Z up,
  exported with +Y up (`blender/lib/export.py`). Hero mech is **16 m** tall (feet to crest top).
- Physics 120 Hz (Jolt), no physics interpolation. Use `_physics_process` for simulation.
- GDScript static typing; resource tuning in `*.tres` or a `const` table at the top of the owning script.
- No unit writes `Engine.time_scale` (only `Feel`). No unit edits another unit's files; integration happens
  through the APIs below, signals in `Events`, groups and optional component scenes.
- Performance budget (M1 Max, 1600×900, high): 60 fps in the busiest fight; ≤ 3,500 draw calls; ≤ 6 M
  rendered triangles; ≤ 40 active enemies with AI; ≤ 600 live projectiles; ≤ 16 shadow-casting lights.

## 3. Core API (game/core, autoloads)
- **Events** (`core/events.gd`): the signal bus. Emit semantic events; never call other units directly
  when a signal fits. Signal list is in the file.
- **Game** (`core/game.gd`): `player`, `world`, `camera_rig`, `hud`; `register_player(p)`;
  `mark_world_built()` / `world_built()`; launch flags `flag(name)`, `has_flag(name)`, `stubbed(part)`,
  `spawn_transform(fallback)`. Flags: `--sandbox --skip-menu --spawn=x,y,z[,yaw] --god --no-enemies
  --enemies=type:n,... --seed=N --quality=low|medium|high --stub=world,player,camera,feel,hud,flow,boss --flow --boss-test`.
  `--sandbox` is FREE PLAY for unit tests: the flow stays idle (no drop-in, tutorial, spires, waves or prompts;
  the hero stands on the sandbox `PlayerSpawn`; no skyline titan) unless `--flow` (or `--boss-test`) is given — flow's own runs use
  `--sandbox --flow`. Without `--sandbox` the full demo flow runs (`--skip-menu` skips only the title).
- **Feel** (`core/feel.gd`): only owner of time scale. `play(event_id, at, strength)` (data-driven, rows of
  `docs/FEEL.md`), `hit_stop(s, scale)` (global, rate-limited), `local_hit_stop(actors, s)`,
  `slow_mo(scale, s, in, out, witch)`, `shake(trauma, origin)`, `shake_floor(trauma, s)` (held minimum trauma), `flash(color, s)`, `fov_kick(deg, s)`,
  `post(effect, strength, s)`, `rumble(weak, strong, s)`, `is_witch_time()`, `player_time_comp()`.
- **Shader globals** live in `game/project.godot` [shader_globals] (lead-owned; ask in your status for a new one):
  `fx_opacity`, `fx_pixel_scale` (feel), `mc_time`, `mc_lit_fraction`, `mc_infection`, `mc_hive0..3`,
  `mc_hive_levels` (city-art). Code only `global_shader_parameter_set`s them — never `_add` at runtime.
- **Export safety**: runtime code never names `tests/` classes and never enumerates `res://` with `DirAccess`
  (use `ResourceLoader.list_directory()` or an index file).
- **Clocks** (critic P0 #1; `Feel`): physics ticks 120×/s of REAL time, each tick's delta is scaled by
  `Engine.time_scale`. Use `Feel.real_delta(delta)` / `Feel.real_now()` (unscaled game clock, correct in
  fixed-fps tests and movies) for ALL input timing (tap/hold, double-tap, buffers, chords) and camera springs;
  `Feel.locomotion_delta(delta)` for player movement (never slowed by witch time or global hit-stops);
  `Feel.player_delta(delta)` for player timers, fire rates, cooldowns, EN/OD, i-frames, parry windows and
  the hero AnimationTree (full speed in witch time, frozen by global hit-stops); plain `delta` for the world
  (enemies, projectiles, VFX). `CharacterBody3D.move_and_slide()` integrates with the scaled physics delta:
  scale the player's velocity by `Feel.real_delta(1.0)` before it and divide after.
- **PadInput** (`core/pad_input.gd`, autoload): the only owner of gamepad buttons + the fire trigger (shift
  layer on RB, L3+R3 chord, latching, D-pad tap/hold). Units never read joypad buttons directly.
  Exception: the F3 debug input quad (`core/input_quad.gd`, tooling) reads raw key, mouse and pad events to
  flip on the frame an input lands (press-to-photon measurement); it drives nothing in the game.
- **Settings** (`core/settings.gd`): `get_value(key)`, `set_value(key, v)`, signal `changed(key)`; accessibility
  keys `fx_flash fx_chromatic fx_radial_blur fx_speed_lines rumble photosensitive damage_numbers hold_to_toggle`
  (feel/hud/camera/input units honour them).
- **Feel.post ids**: `chromatic` (px RGB split), `radial_blur`, `vignette` (red damage edge), `speedlines`,
  `desaturate`, `bw_frame`; the FeelDirector reads `Game.player.velocity` itself for speed lines.
- **VFX library** (fx unit, group `&"vfx_library"`, `spawn(kind, pos, normal, scale)`): kinds include
  `spark_bullet spark_beam missile_blast kill_small kill_large shockwave_ring dust_ring dust_puff debris land_crater
  scorch_ring steam thruster_burst impact_star impact_glow` + persistent `emitter(&"fire_loop"|&"smoke_column")`.
  Global shader parameter `fx_pixel_scale` (owned by VfxLibrary, refreshed from the active camera) gives
  screen-space size floors — use it in any custom VFX shader instead of VIEWPORT_SIZE (0 in offscreen captures).
- **Audio** (`audio/audio.gd`, body owned by the audio unit): `play(id, at=INF, volume_db=0, pitch=1)`,
  `music_intensity(0..1)`, `stinger(id)`. Sound ids are snake_case events (`beam_rifle_fire`, ...).
- **Types**: `HitInfo` (damage packet, see file), `Hurtbox` (Area3D receiver, `apply(hit)`), `Targetable`
  (Marker3D lock point, group `&"targetable"`), `Layers` (physics bits + masks).
- **InputSetup** (`core/input_setup.gd`): action names are the contract (move_*, look_*, jump, descend,
  boost, assault, fire, aim, melee, guard, missiles, anchor, rift_step, fins, burst, well, reload,
  weapon_next/prev, overdrive, lock_on, lock_prev/next, camera_toggle, pause, debug_toggle); semantics in the file header and SPEC §3.
  Units read actions, never raw keys.
- **main.tscn** instances optional parts if their scene exists: world (`world/city.tscn`, else the core
  sandbox), `player/player_mech.tscn`, `player/camera/camera_rig.tscn`, `fx/feel_director.tscn`,
  `ui/hud.tscn`, `flow/game_flow.tscn`.
- **Sandbox** (`core/sandbox/sandbox.tscn`): 900 m grey-box range (decks, ramps, 90 m sky bridge, trench,
  cover, plateaus, pillars, runway), navmesh baked at load, `PlayerSpawn` marker at (0, 1, 60).

## 4. Actors (player and enemies)
Every damageable actor root implements: `take_hit(hit: HitInfo) -> void` (writes `hit.final_amount`,
emits the right Events), `is_alive() -> bool`, `get_team() -> int` (0 player, 1 monsters),
`hit_pause(seconds: float) -> void` (local hit-stop: freeze own animation + motion, visual vibration).
Hurtboxes (class `Hurtbox`) on `PLAYER_HURTBOX` / `ENEMY_HURTBOX`; lock points (class `Targetable`).
Attacks query with `Layers.MASK_PLAYER_ATTACK` / `MASK_ENEMY_ATTACK`, then call `hurtbox.apply(hit)`.
Enemy status (enemies unit, `enemies/status_component.gd`, reached as `enemy.status`): `add_mark_hit(n)`,
`consume_marks() -> int`, `prime(s)`, `is_primed()`, `clear_prime()` (emits `primed_changed`; COLLAPSE uses it). **COLLAPSE detonators** (rifle stage 2, burst, missiles,
plunge, charged wave) call `get_tree().call_group(&"prime_detonators", &"detonate_primes", center, radius,
source)`; the skills unit's SkillSystem joins that group and resolves the COLLAPSE.
Hit markers: every player component that lands hits exposes `last_hit_usec`, `last_hit_kind`
(`&"normal"|&"weak"|&"kill"|&"stagger"`) in `hud_state()`.

## 5. Player = PlayerMech + components (plugin architecture)
`player/player_mech.tscn` (mech-move) is a `CharacterBody3D` (class `PlayerMech`, group `&"player"`). On
`_ready` it registers with `Game.register_player(self)`, instances its model and then every component
scene that exists, as children, in this order:
`player/aim/aim_system.tscn`, `combat/weapons/weapon_system.tscn`, `combat/melee/melee_system.tscn`,
`combat/defense/defense_system.tscn`, `combat/skills/skill_system.tscn`.
Components get the player with `get_parent() as PlayerMech` and use ONLY this API:

| PlayerMech API (mech-move provides) | Meaning |
|---|---|
| `velocity`, `is_grounded()`, `is_flying()`, `is_boosting()`, `move_state() -> StringName` | read state |
| `move_input() -> Vector2`, `facing() -> Basis` | stick/WASD input, body facing |
| `energy`, `energy_max`, `consume_energy(x) -> bool`, `add_energy(x)`, `drain_energy(x, big_move)` | EN gauge (boost, skills); drain = per-frame costs |
| `can_cancel(tag: StringName = &"any") -> bool` | movement state allows a cancel into `tag` (dash/guard/skill/melee) |
| `hp`, `hp_max`, `heal(x)` | armour points |
| `lunge_to(point, speed, max_time)` | melee dash toward a point (stops on contact/obstacle); may be re-issued every tick to home — each call restarts the timer, so pass the REMAINING time |
| `apply_impulse(v)`, `lock_movement(s, allow_turn)`, `set_strafe_aim(on)`, `reset_dash_chain()` | combat movement control (Rift Step resets the dash chain) |
| `invulnerable_for(s)`, `is_invulnerable()` | i-frames (dodge, finishers, ultimate) |
| `add_damage_filter(callable)` | `func(hit: HitInfo) -> bool` (true = consumed: block/parry/barrier) |
| `model() -> Node3D` | the HeroModel API below |
| `aim() -> Node` | the AimSystem (camera-aim) or null |
| `telemetry() -> Dictionary` | flat numbers/strings for tools/autoplay.gd |
| `debug_teleport(pos: Array, yaw_deg: float)` | tools |

**CameraRig** (camera-aim, `player/camera/camera_rig.tscn`, registers `Game.camera_rig = self`):
`yaw_basis() -> Basis` (horizontal camera orientation: movement is relative to it), `camera() ->
Camera3D`, `is_first_person() -> bool`, `set_first_person(on)`, `look_dir() -> Vector3`,
`request_cinematic(shots: Array, duration: float, clock: StringName = &"real")` (cinematics; `&"player"`
advances the shots on `Feel.player_delta` so an execution's cut freezes with its hit-stops, `&"real"` for
presentation beats), `end_cinematic()` (ENDS the cinematic now: shots cancelled, held FOV released, arm + look
restored — callers never need anything else),
`set_override_fov(deg, s)`, `add_trauma(t)`, `lock_to(target)`, `occluder_fade(amount)` (+ group
`&"camera_dither"`: occluders implement `set_fade(amount)` or a `fade` instance shader parameter). Mouse wheel =
weapon swap; lock switching = flick or `lock_prev/lock_next`.
`eye_residual() -> float`: read-only telemetry, the metres between the first-person camera and the model's raw `cockpit`
socket, recorded inside `_follow` in the tick that places the camera (an outside sampler reads a frame late).
**Large-target framing**: when the hard-lock target's actor implements `framing_height() -> float` (the boss: 60)
and it is ≥ 30 m, the rig lengthens the arm (≈ 64 m), lifts the pivot (≈ +14 m) and raises the tracked pitch by
≈ +12° (clamped to stay above the hero's feet), keeping BOTH the hero and the locked point (a core) in frame, easing
back when the lock drops. `framing_height()` is a METHOD on the actor.
Cinematic shot = `{offset: Vector3, look: Vector3 (same frame, default 0), fov: float, t: float}` in the **duel
frame**: origin = midpoint of player and target, −Z = direction player → target (flattened), +Y up, +X right.
E.g. `(36, 10, 0)` = side view of both, `(-14, 22, 40)` = over the player's shoulder behind them. The rig resolves
every shot against collision (sphere cast from the origin, `MASK_SIGHT` + both actors' AABBs inflated 3 m) so the
camera is never inside geometry or an actor; it restores arm length and look control when the cinematic ends.
Until it exists, mech-move uses its own debug follow camera (`player/mech/debug_camera.gd`) only when
`Game.camera_rig == null`.

**hud_state()**: every player component (PlayerMech, AimSystem, WeaponSystem, MeleeSystem, DefenseSystem,
SkillSystem) implements `hud_state() -> Dictionary` with the keys documented at the top of its script;
the HUD polls these each frame (no other coupling).

**AimSystem** (camera-aim, `player/aim/aim_system.gd`): `aim_point() -> Vector3` (crosshair hit or point
at 1,500 m), `aim_dir_from(from: Vector3) -> Vector3`, `hard_target() -> Targetable`, `soft_target() ->
Targetable`, `targets_in_view(max_count: int, max_range: float) -> Array[Targetable]` (missiles),
`camera() -> Camera3D`, `is_first_person() -> bool`.

**HeroModel** (hero-asset; mech-move ships a placeholder with the same API under
`player/model/placeholder/`): a `Node3D` scene `player/model/hero/hero_model.tscn` with
`set_locomotion(state: StringName, speed: float, input_local: Vector2)`, `play_action(id: StringName,
blend: float = 0.08) -> float` (returns the clip length; ids in SPEC §Animation), `set_aim(point: Vector3,
weight: float)`, `socket(name: StringName) -> Node3D` (`muzzle_r`, `hand_r`, `hand_l`, `shield_l`,
`saber_r`, `back`, `wing_l`, `wing_r`, `missile_l`, `missile_r`, `cockpit`, `chest`), `set_thrusters(level:
float)`, `set_wings(open: float)`, `set_overdrive(on: bool)`, `hit_pause(s)`.
Model origin = between the feet at y = 0, facing −Z; PlayerMech places the model node 7.5 m below its body
origin (capsule centre). Cockpit eye ≈ 12 m.

## 6. Enemies
`enemies/enemy_base.gd` (class `EnemyBase`, `CharacterBody3D`, group `&"enemy"`) owns HP, poise/stagger,
hit reactions, death, team 1, perception, nav. Archetype scenes `enemies/<type>/<type>.tscn`; spawner API
`enemies/spawner.gd` (class `EnemySpawner`): `spawn(type: StringName, at: Transform3D) -> EnemyBase`,
`alive_count()`. Enemy attacks build `HitInfo` with `parryable`/`unblockable` set honestly and telegraph
per SPEC §Enemies. Model scenes come from `enemies/models/<type>/<type>_model.tscn` (monster-assets) with
`set_locomotion(state, speed)`, `play_action(id) -> float`, `socket(name)`, `hit_pause(s)`,
`set_hit_flash(v)`; until they exist enemies use placeholder meshes with the same API.

**Anchor nodes** (group `&"anchor_node"`, Marker3D with a `normal` meta): Skyhook works on ANY surface it hits;
anchor nodes are magnets — a shot within 8° of the reticle and ≤ 120 m snaps to the node, and they are
placed where the level design wants traversal (rooftop edges, skybridge undersides, crane booms).

**Crown rim**: city-build exports the Crown's outer rim as separate segments (StaticBody3D, group
`&"crown_rim_segment"`, meta `angle_deg`); the boss breaks them in phase 2 (hide + debris + collision off).
**Groups for the HUD**: hive spires join `&"hive_spire"` (flow), the boss joins `&"boss"` and implements
`hud_state()` (name, hp, hp_max, phase, cores: [{name, hp, hp_max, broken}]) (boss unit). The HUD sets
`Game.hud = self` in its `_ready`.
**Tutorial prompts** (flow drives, hud draws): `Game.hud.prompt(id: StringName, action: StringName = &"", line:
String = "")` queues one contextual prompt (known ids — move, look, dash, boost, jump, hover, fire, lock, melee,
guard, missiles, skills — fill action/line from the HUD's own table); the HUD dismisses it when the verb is
performed, or the flow calls `Game.hud.dismiss_prompt(id)`. The HUD shows NO prompt it was not asked for.

## 7. World / city
`world/city.tscn` root script calls `Game.mark_world_built()` when geometry and navmeshes are ready. It
provides markers: `PlayerSpawn` (Marker3D), group `&"spawn_zone"` (Area3D with `zone_id`), group
`&"arena"` (Area3D with `arena_id`), group `&"landmark"`. Static geometry on `Layers.WORLD`; breakables on
`PROPS`. Navmeshes per agent class: `small` (r 1.5 m), `medium` (r 4 m), `large` (r 9 m) — NavigationRegion3D
nodes in group `&"nav_<class>"` on their own navigation maps (`world.nav_map(class) -> RID`). Map data
contract: `docs/MAP.md` + `data/map/*.json`. Flyers route through the sky graph: `world.sky_path(from, to)
-> PackedVector3Array` (AStar3D over `sky_waypoints`, markers in group `&"sky_waypoint"`); `[from, to]` when the
map has no sky graph (sandbox).
**Environment hooks** (city-art): one TimeOfDay node in group `&"time_of_day"` — `set_progress(p: float)`
(0 = start, 1 = boss; tweens itself over ~4 s), `set_storm(amount: float, seconds: float)`, `lightning_at(pos:
Vector3)`; infection creep nodes in group `&"infection"` — `set_intensity(site_id: StringName, value: float,
seconds: float)` (site ids = layout `hives[].id`). Callers use `call_group`, so a missing environment is a no-op.
**Art integration**: `world/city.tscn` instances `res://world/art/environment.tscn` (city-art) as a child and has
no sky/sun/WorldEnvironment of its own; the environment's root applies the `mc_*` materials to its parent's
tiles on ready (`McMaterials.apply_to(get_parent())`) and owns sky, sun, fog, GI and post.

## 8. Evidence every unit produces
`tools/godot.sh check` clean for your folder; tests in `<folder>/tests/`; for anything visible, captures
(`tools/godot.sh shot/drive`) into `captures/<unit>_*.jpg` and the paths in your status file.
