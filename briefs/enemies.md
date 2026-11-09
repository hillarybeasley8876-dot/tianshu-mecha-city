# Brief: enemies — EnemyBase, 5 monster archetypes, spawner (placeholder bodies, final APIs)

## Goal
Monsters that create tension and are satisfying to fight: readable silhouettes, honest telegraphs,
parryable vs unblockable attacks, stagger → execution windows, marks and primes from the kit, packs that
flank, artillery that forces movement, flyers that force vertical play, a brute that demands respect.
Models come later from Tripo (monster-assets unit); you build the behaviour with placeholder bodies that
already use the final model API (CONTRACTS §6).

## Read first
`docs/CONTRACTS.md` (all), `docs/SPEC.md` §6–8, `docs/FEEL.md` (kill/stagger rows, local hit-stop),
`ref/research/skills-catalog.md` §4.1, §4.6, §4.7 (stability, marks, primed, combo scaling, execution
trigger), `ref/research/juice-impact.md` §7 (hit reactions) and §11 (telegraph timing ≥ 250 ms + buffer),
`game/core/**`, the sandbox (`core/sandbox/sandbox.gd`: navmesh agent r 3 m).

## You own
`game/enemies/**` except `game/enemies/models/**`.

## Build
1. **EnemyBase** (`enemies/enemy_base.gd`, `class_name EnemyBase`, `CharacterBody3D`, group `&"enemy"`,
   layer `Layers.ENEMY`, mask `Layers.MASK_CHARACTER`): HP, armour per hurtbox part, **StatusComponent**
   (stability with delay/decay per skills-catalog §4.6 table, stagger + immunity, marks 0–2 with 5 s
   decay, primed 5 s, slow/pull hooks for the Undertow well, combo scaling 100 % → −6 %/hit → 55 % floor
   reset 1.5 s), `take_hit` (weak points ×2.5 where SPEC says, staggered targets ×1.8 melee/charged/×1.35
   other, emits `Events.hit_landed`, `enemy_staggered`, `enemy_killed`, calls `Feel.play` kill rows),
   `hit_pause(s)` (freeze motion/anim, visual vibration of the model per juice §2 Sakurai rules),
   knockback with mass per type, death (ragdoll-free: collapse animation/placeholder tween + wreck that
   stays 30 s, dissolve), `is_alive`, `get_team() = 1`, `is_executable(by: Node3D) -> bool` and
   `execute_hit(...)` hooks used by melee-defense, `hud_state()` (hp, hp_max, stability, stability_max,
   staggered, marks, primed, name).
2. **AI**: small hierarchical state machine per archetype (idle/patrol → alert → approach/position →
   attack (telegraph → active → recover) → reposition; staggered; dead). Perception: sight cone + LOS
   ray (`Layers.MASK_SIGHT`) + hearing (Events.weapon_fired within 400 m) + pack alert sharing (120 m).
   Navigation: NavigationAgent3D on the world nav map; flyers use 3D steering (seek/arrive/orbit +
   obstacle avoidance raycasts), no navmesh. Avoidance between pack members. Attack tokens: at most 3
   melee attackers + 2 ranged volleys at the player at once (fairness, tension waves).
3. **Archetypes** (SPEC §7 table; tune attacks with honest telegraphs ≥ 350 ms, glint white = parryable,
   red glow = unblockable): `ripper` (pack flanker, leap-bite), `mantis` (3-hit parryable combo + red
   grab, sidestep when aimed at), `spitter` (keeps 150–300 m, lobs acid arcs = projectiles with
   `reflectable` meta for the catch field, spore-chaff cloud node in group `&"chaff"` that eats missiles),
   `harrier` (flyer strafing runs + dive bomb), `juggernaut` (charge, ground-slam shockwave ring you jump
   over, breakable front plates, back weak point). Enemy projectiles: pooled, on `Layers.ENEMY_SHOT`,
   query `Layers.MASK_ENEMY_ATTACK`, carry `HitInfo` + metadata `reflectable: bool`, `owner: Node`.
4. **Placeholder bodies** (`enemies/<type>/placeholder/`): primitive-built silhouettes at the right size
   and colours (dark carapace #1B1E24 with acid-green #9BFF3A glow lines, violet #B04CFF weak points),
   implementing the monster model API (`set_locomotion`, `play_action`, `socket`, `hit_pause`,
   `set_hit_flash`). Each archetype scene loads `enemies/models/<type>/<type>_model.tscn` instead when
   that file exists.
5. **EnemySpawner** (`enemies/spawner.gd`, class `EnemySpawner`): `spawn(type, at)`, `alive_count()`,
   pooling for rippers; honours `--no-enemies` and `--enemies=type:n,...` (spawns those around the player
   at 150–250 m on the navmesh when the world is built).

## Done when
- `tools/godot.sh check --only=res://enemies/` → 0 errors.
- `tools/godot.sh test res://enemies/tests/test_status.gd`: stability/stagger/immunity/marks/primed/combo
  scaling numbers exactly as the tables; weak-point and staggered multipliers; kill emits the events once.
- `tools/godot.sh test res://enemies/tests/test_ai.gd`: in the sandbox, 12 rippers + 2 mantis + 2 spitters
  + 2 harriers + 1 juggernaut spawned against a stationary dummy player node (group "player", take_hit
  counter): all reach attack range or position within 25 s, never more than 3 simultaneous melee
  attackers, every attack is preceded by its telegraph event (log them), no enemy stuck > 6 s (position
  delta), 0 engine errors, physics frame time with 40 enemies < 6 ms (measure).
- Captures `captures/enemies_*.jpg`: each archetype's placeholder (3/4 view, next to a 16 m scale
  pillar), a pack flanking, a telegraph (glint and red glow), a stagger, a wreck. One movie of the AI test.
