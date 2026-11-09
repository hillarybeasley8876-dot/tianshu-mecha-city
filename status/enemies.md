# enemies status

## Done
- `types.gd` (`EnemyTypes`) — per-archetype table (HP / stability / decay / stagger / immunity /
  size / mass / speed / sight / engage / **nav agent class**), armour per hurtbox part, weak-point
  ×2.5, staggered ×1.8 and ×1.35, display names, `nav_class` / `nav_map_for` / `map_ready`.
- `status_component.gd` (`StatusComponent`) — stability pool with delay + decay, stagger, immunity,
  marks 0–2 (2 hits per mark, 5 s), primed 5 s, slow/pull hooks for the Undertow well, combo
  scaling (hits 1–6 = 100 %, −6 %/hit, floor 55 %, reset 1.5 s, suspended while staggered), and
  `clear_prime() -> bool` for the COLLAPSE detonators (CONTRACTS §4 — emits `primed_changed`).
- `enemy_base.gd` (`EnemyBase`, `CharacterBody3D`, group `&"enemy"`, layer `Layers.ENEMY`, mask
  `Layers.MASK_CHARACTER`) — `take_hit`, `hit_pause`, knockback by mass, death → collapse → 30 s
  wreck → dissolve, `is_alive`, `get_team() = 1`, `is_executable` / `execute_hit` (14 m, ±60°),
  `hud_state`, `recycle` / `reclaim` for pooling, `set_ai_enabled`. **`begin_telegraph` emits
  `Events.enemy_telegraph(self, attack.id, attack.kind)`** as well as the local signal.
- `damage.gd`, `visuals.gd` — the damage maths and everything that touches the model, split out of
  `EnemyBase` (594 → 501 lines) so the monster root stays readable.
- `brain.gd` (`EnemyBrain`) — HSM idle → alert → approach ⇄ position → attack (telegraph → active
  → recover) → reposition; staggered; dead. Attack tokens ≤ 3 melee / ≤ 2 ranged with a 0.8 s
  re-grant delay, pack separation, last-known-position hunting, idle patrol, crowd escape, and a
  self-profiler the AI test turns on.
- `perception.gd` — sight cone (plus peripheral awareness inside 25 % of sight range), LOS ray on
  `MASK_SIGHT`, hearing (`Events.weapon_fired` ≤ 400 m), chained pack alert at 120 m, last known
  position.
- `locomotion.gd` — navmesh agents on the archetype's **agent-class map** (bound at spawn, retried
  every 0.5 s until the world provides one), 3D flyer steering with obstacle whiskers, wedged/crowded
  unstick.
- `strike.gd`, `blast.gd`, `enemy_projectile*.gd`, `enemy_shockwave.gd`, `spore_chaff.gd` — arc
  sweeps, area damage, pooled shots on `ENEMY_SHOT` querying `MASK_ENEMY_ATTACK`, jumpable slam ring
  in group `&"enemy_shockwave"`, chaff cloud in group `&"chaff"`.
- **Projectile metadata is honest in every state** (lead note from melee-defense): typed fields
  behind the `&"hit"` / `&"owner"` / `&"reflectable"` contract, published on `launch`, fully
  withdrawn on `deactivate`, `&"owner"` withdrawn the moment the shooter leaves the tree. A pooled
  shot sits on no collision layer with its process stopped, and both come back on relaunch — the
  catch field freezes a caught round, and without that a recycled shot never flew again.
- Archetypes — `ripper` (pack flanker, leap-bite), `mantis` (3-hit parryable combo, red grab,
  sidestep when aimed at), `spitter` (150–300 m stand-off, high ground, acid arcs, chaff),
  `harrier` (flyer, strafing runs, dive bomb), `juggernaut` (charge, slam ring, breakable front
  plates, ×2.5 back weak point). All numbers follow **SPEC §7.1** (see Tuning choices).
- **Telegraph language** — SPEC §7.1 floors enforced in `EnemyAttack.make`: parryable ≥ 400 ms,
  unblockable ≥ 600 ms. The tell is carried by **shape as well as colour**: a compact white
  **diamond** over a parryable attack, a wide red **inverted wedge** over an unblockable, both
  unshaded, depth-test-free and turned to the camera. Unblockables also play their own sound id,
  `telegraph_unblockable`.
- Placeholder bodies (`<type>/placeholder/<type>_placeholder.tscn` + `placeholder/monster_model.gd`
  + `body_parts.gd`) implementing the final model API; `body_builder.gd` loads
  `enemies/models/<type>/<type>_model.tscn` instead the moment monster-assets ships it. Ripper legs
  are now thigh + knee + shin so the pack reads at a glance.
- `spawner.gd` / `spawner.tscn` (`EnemySpawner`) — `spawn`, `alive_count`, ripper pooling,
  `--no-enemies` and `--enemies=type:n,...` at 150–250 m on reachable navmesh ground **per agent
  class**, leash for monsters stranded on unreachable geometry.
- Tests — `tests/test_status.gd`, `tests/test_ai.gd`, `tests/test_spawner.gd`,
  `tests/test_projectile.gd`, `tests/test_main_spawn.gd`, `tests/test_audit.gd`,
  `tests/test_fight.gd`; fixtures `tests/dummy_player.gd`,
  `tests/gallery.tscn` (captures), `tests/ai_demo.tscn` (movie), `tests/fight_probe.tscn` +
  `fight_timeline.json` (real-build integration).
- **Navigation queries are gated and self-silencing** (lead note 02:40). Godot 4.7.2 logs an engine
  error for *every* path query between disconnected navmesh islands
  (`_query_task_build_path_corridor`, "It's not expect to not find the most reachable polygons") and
  answers it with a degenerate start→end path instead of an empty one. Three changes:
  `EnemySpawner` no longer proves reachability with a path query at all (on-mesh + same-level is the
  cheap test that catches the case that mattered); `EnemyLocomotion._set_goal` only hands the agent
  a goal projected onto its own map and on its own level; and the first *failed* corridor silences
  path queries for the whole unit for 60 s, after which monsters steer directly. A failed corridor
  looks exactly like a straight successful path (two corners, `is_target_reachable() == true`), so
  the corroboration is a scenery ray along the path: a real two-corner path is a straight walkable
  tube and never has scenery across it.
- **The dissolve never reaches a zero scale** (lead note, melee r6): `enemy_base.gd` hid the wreck
  and finished the dissolve on the frame `k` reaches 1, instead of writing `scale = (0,0,0)` — a
  degenerate basis, and the only `--nan-watch` source left in fights.
- **The juggernaut roars, and it can actually charge** (lead r10, from monster-assets r4).
  `juggernaut.gd` used to call `set_locomotion(&"roar")` on *every* windup tick — no locomotion row
  answers `roar`, so it resolved to idle and the 2.75 s clip never played. It now plays
  `play_action(&"roar")` once per charge windup (latched in `begin_telegraph`), and
  `attack_started` re-arms the `charge` clip the brain played before the roar, so the dash does not
  slide 260 m in a roar pose. **The windup timing is untouched (0.7 s)** — the roar owns the windup,
  the charge clip owns the dash.
  Finding while verifying it: the charge itself was **unreachable**. `EnemyBrain._approach` only let
  a monster commit inside `engage_range × 1.2` (juggernaut: 48 m) while the charge's `range_min` is
  80 m, so by the time the brute was allowed to swing it was always inside the charge's own minimum
  range — it never charged once in a 36 s fight. `_standoff_ready()` now also commits an attack whose
  `range_min` deliberately sits *outside* the engage ring (only the juggernaut's charge qualifies;
  a ripper still closes to 21 m before it leaps).
- `EnemyBase.action_plays` (id → count) — the funnel every `play_action` goes through, so a test or
  the fight probe can prove a one-shot fired exactly once. `fight_probe` prints a **model trace**
  (`FIGHT t … <type> action <id> ×n clip=<AnimationPlayer clip>`) from it.
- **r11 — a monster is born where it is sent** (`spawner.gd:85-107`). `spawn()` used to
  `add_child(enemy)` and only then move it, so `EnemyBase._ready` (collision on, body, model, nav
  agent, brain) ran with the new monster standing on the **spawner's own origin**: the hero at world
  (0,0,0) and the titan on its `AddSpawner` took that body as their floor for one tick and inherited
  the jump to the spawn point as platform velocity. The monster's local transform is now set
  **before** `add_child`, so it is at its spawn point from the moment it enters the tree whatever
  the spawner's own transform is; a pooled ripper still gets `global_transform` before `recycle()`
  re-arms its collision.
- **r11 — enemy fire that misses is felt** (`near_miss.gd`, `EnemyNearMiss`; wired into
  `enemy_projectile.gd`). One `Feel.play(&"near_miss", closest_point, strength)` per live enemy shot
  that passes within `EnemyNearMiss.RADIUS` (6 m of clear air off the player's hurtbox surface)
  without damaging the player, fired the moment the round is past its closest approach. No physics
  query (cached hurtbox capsules + `Geometry3D`), no second rate limiter (the FEEL row's own 0.25 s
  cooldown is the 4/s limit). No near miss for a hurtbox contact, a blast that reaches the player, a
  round the barrier ate, a round the catch field held, or a reflected round.
- **r11 — `test_ai` measures SPEC §7.1's case** (`attack_token_pool.gd`, `test_ai.gd`). "Full attack
  tokens" is now the lead's definition (r16 Round 2, and the wording the lead put in SPEC §7.1):
  **the pool at capacity** — every slot of that kind held, or shut by the 0.8 s re-grant delay,
  while another monster of that kind is still asking. `AttackTokenPool` tracks askers
  (`askers`, `asking`, `slot_state`, `cooldown_left`, `at_capacity`) and `test_ai` logs, per kind,
  the share of the window in each of the four states plus the at-capacity share and the mean asker
  count. The gate is 25–35 s with ≥ 80 % at capacity, both FAILs (the old 18–50 s window and the
  "fall back to the whole window" warning are gone), and the attack-damage rows are re-tuned to it.
- **r12 — a monster that loses sight of the player searches, then goes home** (lead brief, Request
  21). The brain had no answer for "I cannot see the player any more": perception held the target
  for `LOSE_MEMORY` (10 s) and the monster chased the *real* position for all of it, and the moment
  the target was dropped `_approach` fell back to the remembered point's stand-off ring and
  **circled it — moving, silent and blind — for the rest of the monster's life**. `_idle`'s patrol,
  the only thing that walks a monster back into view, was unreachable because the remembered point
  never expired. New `enemies/brain_search.gd` (`EnemyBrainSearch`, split out so `brain.gd` stays
  under 400 lines): walk to the last known position, sweep the horizon from there, widen the search
  in rings (45/90/150 m, six bearings each, rotated by the monster's own flank offset), and after
  `SEARCH_TIME` (8 s — the spawner's own `LEASH_AFTER` tolerance) **give up**: drop the memory
  (`Perception.forget`) and walk back to the arena anchor, where the patrol takes over.
  `Perception` grew the memory age (`hunt_age`) and a gunshot now refreshes where a monster that is
  *already* hunting thinks the player is, instead of being ignored because it was alerted once.
  `EnemyBrain._face_sensibly` looks at what it is hunting out to half its sight range — a
  juggernaut (engage 40 m, sight 400 m) used to stare at its own feet from 120 m out and lose the
  player it was closing on. `EnemySpawner` puts a monster that has fought the player, gone blind
  and is out of the fight **back into it**: on a ring point it can actually see the player from,
  turned to face them. The old distance test was twice the engage ring, which for the spitter's
  300 m stand-off band means "never far from anything" — that is how one sat silent in the sandbox
  trench for a whole run.
- **r12 — the `test_ai` flake, root-caused** (the lead saw 1 of 5 runs fail and the line was never
  captured). Not load, and not the LOS bug: the incoming-damage reading is a sample of a heavily
  quantised damage source and two things were feeding it noise. **(a)** the spitter's spore-chaff
  cloud does 0 damage but took one of the two RANGED tokens and `release` then shut the whole kind
  for the 0.8 s re-grant delay, so a chaff puff denied a real acid arc and *how many puffs landed in
  the window was pure chance*; `EnemyAttack.is_utility()` marks it, the brain runs utility moves for
  free and a utility row never competes with a damaging one that is ready. **(b)** `choose_attack`
  is a weighted pick over the **whole** table and could see neither range nor cooldown, so the row
  it returned was regularly out of range or still on cooldown — attacks were firing against their
  own frame data. `_ready_to_attack` now leaves the rows it cleared in `_options`, `_begin_attack`
  falls back to a weighted pick over those, and a damaging attack that cannot get a token stands
  down instead of swinging without one. With the slots no longer wasted the true incoming rate is
  higher than the rows were tuned for, so the balance window also went 20 s → 40 s (one harrier
  dive bomb is 755 damage and one juggernaut slam 970; a 20 s window that caught three instead of
  none read 113 DPS high — a spread wider than the whole SPEC band). The per-weapon **hit count**
  is now printed next to the DPS so the quantisation is visible instead of mysterious. **No damage
  row was changed**: the old numbers were tuned against a measurement that was silently depressed
  by chaff puffs eating volley slots.

## In progress / next
Nothing outstanding for this brief. r12 (lead brief, 2026-11-06) is closed: the LOS-loss defect is
fixed with a FAIL-on-old / PASS-on-new pair for all five archetypes, and the `test_ai` flake is
root-caused and gone (10/10 sequential runs). r11 is closed the same way, and so are the 2026-11-02
robustness round (`reviews/enemies-audit.md`, 13 findings), the nav-query/dissolve round and lead
r10. Follow-ups for the lead are under **Requests**; the windowed runs this round could not make are
under **Captures needed**.

## How to verify (exact commands)
```
tools/godot.sh check --only=res://enemies/
tools/godot.sh test res://enemies/tests/test_audit.gd -- --timeout=300
tools/godot.sh test res://enemies/tests/test_fight.gd -- --timeout=400
tools/godot.sh test res://enemies/tests/test_status.gd
tools/godot.sh test res://enemies/tests/test_ai.gd -- --timeout=400
tools/godot.sh test res://enemies/tests/test_spawner.gd -- --enemies=ripper:4,mantis:1 --timeout=300
tools/godot.sh test res://enemies/tests/test_spawner.gd -- --no-enemies --timeout=300
tools/godot.sh test res://enemies/tests/test_projectile.gd -- --timeout=300
tools/godot.sh test res://enemies/tests/test_main_spawn.gd -- --sandbox --enemies=ripper:6 --timeout=300
tools/godot.sh test res://enemies/tests/test_main_spawn.gd -- --sandbox --no-enemies --timeout=300
tools/godot.sh test res://enemies/tests/test_main_spawn.gd -- --sandbox --enemies=ripper:4 --stub=enemies --timeout=300
```
r11's two new suites (the first boots the real `main.tscn`, so it needs the flags):
```
tools/godot.sh test res://enemies/tests/test_spawn_safety.gd -- --sandbox --no-enemies --timeout=400
tools/godot.sh test res://enemies/tests/test_near_miss.gd -- --timeout=300
for i in 1 2 3 4 5; do tools/godot.sh test res://enemies/tests/test_ai.gd -- --timeout=400 2>&1 \
  | grep -E 'BALANCE tokens|BALANCE incoming|dies in|^PASS|^FAIL'; done
grep -rn --include='*.gd' --exclude-dir=tests near_miss game/enemies
```
r12's LOS-loss suite and the flake gate (the balance window is 40 s now, so `test_ai` needs 500 s):
```
tools/godot.sh test res://enemies/tests/test_los_loss.gd -- --timeout=600
for i in $(seq 1 10); do tools/godot.sh test res://enemies/tests/test_ai.gd -- --timeout=500 2>&1 \
  | grep -E 'BALANCE incoming|dies in|AI TEST|^PASS|^FAIL'; done
tools/suites.sh --only=enemies_status,enemies_projectile,enemies_audit,enemies_spawner_mix,\
enemies_spawner_none,main_spawn_r6,main_spawn_none,main_spawn_stub,enemies_fight,enemies_ai,\
enemies_los_loss,enemies_near_miss,enemies_spawn_safety,models,boss,boss_city,flow
```
The r11 drive and movie are under **Captures needed**: `tools/godot.sh drive|movie` refuse without
the lead's `MC_WINDOW_OK=1`, and this round is headless-only.

Lead r10 (the charge/roar, follow camera, `--nan-watch` and the model trace):
```
tools/godot.sh drive --scene=res://enemies/tests/fight_probe.tscn \
  --timeline=res://enemies/tests/fight_timeline.json --out=enemies_r10_roar \
  --shots=1,12,26 --sandbox --stub=hud --nan-watch --probe-cam=follow --enemies=juggernaut:1
```
Real fight (6 stills, framed by the probe on live events):
```
tools/godot.sh drive --scene=res://enemies/tests/fight_probe.tscn \
  --timeline=res://enemies/tests/fight_timeline.json --out=enemies_rig \
  --shots=14,24,34 --sandbox --stub=hud --enemies=ripper:8,mantis:2,spitter:2,harrier:2,juggernaut:1
```
Movies (`enemies_fight.avi` = the shipping third-person rig, `enemies_fight_cam.avi` = the probe's
follow camera, which is the one worth watching — the rig sits close behind the mech and hides the
pack):
```
tools/godot.sh movie --movie=$HOME/m/mecha-city/captures/enemies_fight.avi \
  --scene=res://enemies/tests/fight_probe.tscn --timeline=res://enemies/tests/fight_timeline.json \
  --sandbox --stub=hud --enemies=ripper:8,mantis:2,spitter:2,harrier:2,juggernaut:1
tools/godot.sh movie --movie=$HOME/m/mecha-city/captures/enemies_fight_cam.avi \
  --scene=res://enemies/tests/fight_probe.tscn --timeline=res://enemies/tests/fight_timeline.json \
  --sandbox --stub=hud --probe-cam=follow --enemies=ripper:8,mantis:2,spitter:2,harrier:2,juggernaut:1
```
Gallery captures (one per pose; `solo` takes `--enemy=<type>` and `--yaw=<deg>`):
```
tools/godot.sh shot --scene=res://enemies/tests/gallery.tscn --pose=solo --enemy=ripper --yaw=180 \
  --out=enemies --warm=60 --cams=ripper:9,4.5,13:0,3,0:55
tools/godot.sh shot --scene=res://enemies/tests/gallery.tscn --pose=pack --out=enemies --warm=150 \
  --cams=pack:58,34,-14:0,8,-60:55
```
Note: `tools/godot.sh shot --scene res://…` (space form) is not parsed by `capture.gd`; use `--scene=`.

## Evidence
- **Lead r12, 2026-11-06** — the LOS-loss defect and the `test_ai` flake. Commits **`0119fc50`**
  (the search behaviour) and **`3bf3a1ef`** (the flake's root cause); logs `tmp/enemies/r12_*.log`.
  The FAIL-on-old runs were made by restoring the pre-r12 `brain.gd` / `perception.gd` /
  `spawner.gd` / `boss_brain.gd` from `HEAD~1` over mine, running the **final** test file, and
  putting mine back (`git stash` is never used on this tree).

  **1. A monster that loses sight of the player parked blind forever.**
  `res://enemies/tests/test_los_loss.gd` — **51 checks, 0 failures** on the new brain, **61 checks,
  37 failures** on the old one, with the same test file. One of each archetype is fought in the
  sandbox and the player is taken out of its line of sight three ways: behind a 700 × 200 × 20 m
  cover block the test drops into the world's `NavigationRegion3D` and **re-bakes** (so the navmesh
  routes around it like any other building), onto the roof of the north-east tower (200 m up a
  sheer face, so no ground monster can path there), and into the trench. A fourth pass repeats the
  cover case with the spawner's leash on.

  | archetype | old brain | new brain |
  |---|---|---|
  | ripper | blind 13.2 s of a 24 s window, state never left `approach`/`position` | searches, then walks home; blind ≤ 8 s |
  | mantis | same, 13.2 s | same fix, blind ≤ 8 s |
  | spitter | same, 13.2 s | same fix, blind ≤ 8 s |
  | harrier | same, 13.2 s (cover); on the roof it flies up and re-finds the player on both | same fix, blind ≤ 8 s |
  | juggernaut | same, 13.2 s | same fix, blind ≤ 8 s |

  The gates are the brief's own list, and the numbers come from the AI rather than being invented:
  `REACT_MAX` 6 s = `test_ai.STUCK_TIME` (the brief's "never idle more than 6 s"), `GIVEUP_MAX` 14 s
  = `EnemySpawner.LEASH_AFTER` (8 s, the same tolerance the spawner gives a monster that is out of
  the fight) + 6 s to walk home, `STILL_MAX` 6 s and `MOVE_EPS` 2 m sampled every 0.5 s are
  `test_ai`'s own stuck check verbatim. Deadlines are measured from the moment perception actually
  drops the target, so the 10 s of `LOSE_MEMORY` is the AI's own memory and not a grace period the
  suite hands out.

  | check | old | new |
  |---|---|---|
  | answers losing the player within 6 s (search / re-path / go home) | **10 FAIL** (cover + leashed, all 5) | 0 |
  | gives up or re-finds the player within 14 s of going blind | **14 FAIL** | 0 |
  | is never still for 6 s | 0 | 0 |
  | the spawner puts a blind, far monster back in the fight | **5 FAIL** | 0 |
  | the whole pack is back on the player 14 s after it steps out | 1 FAIL (`away`, spitter) | 0 |

  **2. The `test_ai` flake.** The lead saw 1 of 5 runs fail with the line uncaptured; a 10-run
  sweep reproduced it (`tmp/enemies/r12_ai_10runs.log` run 7: `FAIL a player who never defends dies
  in 25-35 s (SPEC 25-35) — 23.1 s at 434 DPS`). It was not load — the failing run's own AI-off
  physics baseline was 5.29 ms and the sim is `--fixed-fps`, so the physics steps are identical
  whatever the machine does — and not the LOS bug: the roster trace shows every monster holding a
  live target throughout. Two causes, both in the attack gate:

  - the spitter's **chaff cloud** (0 damage) took one of the two RANGED tokens and `release` then
    shut the whole kind for `REGRANT_DELAY` (0.8 s), so a puff denied a real acid arc. The lob is
    320 damage and the window caught 10–17 of them, i.e. the single biggest damage source swung by
    112 DPS on chance alone;
  - `choose_attack` is a weighted pick over the **whole** table and could see neither range nor
    cooldown, so attacks were firing out of range and on cooldown.

  | build | incoming DPS (SPEC band 286–400) | time to death (SPEC 25–35 s) | runs outside the band |
  |---|---|---|---|
  | pre-r12 brain, 20 s window (`r12_ai_10runs.log`) | 326–434 | 23.1–30.7 s | **1 of 10** |
  | + utility/availability fix, 20 s window (`r12_ai_probe.log`) | 402–597 | 16.8–24.9 s | **6 of 6** |
  | + 40 s balance window (`r12_ai_probe3.log`) | 354–386 | 25.9–28.2 s | 0 of 6 |
  | **final build** (`r12_ai_10runs_final.log`) | **356–376** | **26.6–28.1 s** | **0 of 10** |

  The middle row is the honest part: fixing the token leak *raised* the true incoming rate (the old
  rows were tuned against a measurement that chaff puffs were silently depressing), which is why
  the window had to grow as well. One harrier dive bomb is 755 damage and one juggernaut slam 970,
  so a 20 s window that caught three dive bombs instead of none read 113 DPS high — a spread wider
  than the whole 114 DPS band. **No damage row was changed.**

  Final 10 sequential runs, each 14 checks / 0 failures (`tmp/enemies/r12_ai_10runs_final.log`):

  | run | incoming DPS | dies in | at capacity | hits |
  |---|---|---|---|---|
  | 1 | 363 | 27.6 s | 100 % | 111 |
  | 2 | 363 | 27.6 s | 100 % | 112 |
  | 3 | 359 | 27.9 s | 100 % | 108 |
  | 4 | 376 | 26.6 s | 100 % | 111 |
  | 5 | 366 | 27.3 s | 100 % | 110 |
  | 6 | 364 | 27.5 s | 99 % | 110 |
  | 7 | 374 | 26.7 s | 100 % | 110 |
  | 8 | 356 | 28.1 s | 100 % | 111 |
  | 9 | 373 | 26.8 s | 100 % | 113 |
  | 10 | 360 | 27.8 s | 100 % | 109 |

  **Suite at the end of r12** (`tools/suites.sh`, 17 rows):
  `enemies_status` 90/0 · `enemies_projectile` 22/0 · `enemies_audit` 25/0 · `enemies_spawner_mix`
  9/0 · `enemies_spawner_none` 6/0 · `main_spawn_r6` 6/0 · `main_spawn_none` 2/0 ·
  `main_spawn_stub` 2/0 · `enemies_fight` 13/0 · `enemies_ai` 14/0 · `enemies_los_loss` 58/0 ·
  `enemies_near_miss` 17/0 · `enemies_spawn_safety` 10/0 · `models` 722/0 · `boss` 135/0 ·
  `boss_city` 20/0 · `flow` 252/0 → **SUITES 17 rows, 17 green, 0 known, 0 red**.
  `check --only=res://enemies/` → **109 files, 0 failed, 0 engine errors, 0 warnings**
  (HEAD baseline at the start of the round: 107 files, 0/0/0).
  The one `other_err` in `enemies_spawner_mix` is that suite's own deliberate
  `push_error("unknown enemy type 'dragon'")`, as it has always been.

  AI script cost with 40 enemies is **0.81–0.87 ms/frame** across the ten runs. The wall-clock
  physics numbers in those runs (4.6–9.3 ms against the 6 ms budget) are not a result: this box was
  running the suite itself, its AI-off baseline was 2.7–8.2 ms against a clean 2.43–2.69, and
  `test_ai`'s own three-regime judge handled it — every run passed on the marginal-cost gate.
- **Lead r11, 2026-11-06** — the three findings, each with a FAIL-on-old / PASS-on-new pair. Logs in
  `tmp/enemies/r11_*.log`; the tree at the start of the round was `c75628c` + `b7edc83b` (dispatch
  note), with monster-assets' models at `590a6a1` and feel r5's near_miss path already landed. This
  round's commits are **`a6269a7e`** (the three fixes), **`9da69a9b`** (the hurtbox-transform cache
  fix below) and **`69cd9673`** (the roster trace); the tip is **`69cd9673`** and flow r5 can run its
  titan tracker on top of it.

  **1. A new monster existed at the spawner's origin before it was placed.**
  Cause: `spawner.gd:92-94` did `add_child(enemy)` and only then `enemy.global_transform = …`, so
  `EnemyBase._ready` (collision on at :59, body and model :79-80, nav agent :82, brain :86) ran with
  the monster standing on the spawner's own origin — world (0,0,0) for main's, the titan's feet for
  the `AddSpawner`. Fix: the **local** transform is set before `add_child`
  (`enemy.transform = global_transform.affine_inverse() * xf`), so `add_child` resolves the global one
  and the monster is at its spawn point from the moment it enters the tree, whatever the spawner's
  own transform is. A pooled ripper still gets `global_transform` before `recycle()` re-arms it.
  `spawn(type, at)` is unchanged and every caller lands where it landed before.

  | what | old `spawner.gd` (HEAD) | new |
  |---|---|---|
  | `test_spawn_safety` (real `main.tscn --sandbox`, hero on the spawner origin) | **7 of 10 checks FAIL** | **10 checks, 0 failures** |
  | ripper ×2 under the hero | moved **9788 m** at **19929 m/s**, and 3834 m at 7878 m/s | ≤ 0.1 m, < 1 m/s |
  | mantis / spitter / harrier / juggernaut | moved **6.97 / 7.41 / 7.41 / 10.02 m** at 0 m/s (the teleport the acceptance probe's `flung` count missed) | ≤ 0.1 m, < 1 m/s |
  | spawner under a translated, rotated parent | the stander was thrown **8066 m** at 16132 m/s; every monster entered the tree at the spawner's origin | every monster is at its spawn point at `SceneTree.node_added`, the stander does not move |

  The FAIL run is `tmp/enemies/r11_spawn_OLD.log` (`git show HEAD:game/enemies/spawner.gd` restored
  over mine for the run, then mine put back); the PASS run is the same suite on the new file. The
  numbers reproduce the r15 acceptance probe (`15979 m/s / 7846 m`, `16866 / 8285`, and the 7–10 m
  teleports for the other three types).

  **2. Nothing in the game called `near_miss`.**
  Cause: the FEEL row existed (`docs/FEEL.md:45`, `fx/events/near_miss.tres`, audio has three
  variants and `near_miss_flyby` aliased to it) but only the feel gallery fired it. Fix:
  `game/enemies/near_miss.gd` (`EnemyNearMiss`) + a `Tracker` per pooled shot in
  `enemy_projectile.gd`. The rule is juice §11.3 at the closest point of the path, with no physics
  query: the player's hurtbox capsules are cached (`Geometry3D.get_closest_points_between_segments`)
  and the test is vector maths on the segment the shot already swept. `RADIUS` is 6 m of **clear air
  off the hurtbox surface** — a surface distance on purpose, because a 16 m mech's hurtbox is a 6 m
  capsule and "6 m from its centre" is inside the player.

  | case (through `EnemyProjectilePool.spawn`) | expected | measured |
  |---|---|---|
  | flat pass at 0.5 R (3 m of clear air) | 1 | 1, reported at 3.0 m, 0.1 s before the round expires |
  | flat pass at 1.5 R (9 m) | 0 | 0 |
  | direct hit on the hurtbox | 0 | 0 (and the dummy took the hit) |
  | acid lob whose blast damages the dummy | 0 | 0 (and the dummy took the hit) |
  | reflected round | 0 | 0 |
  | round the catch field held, then let go | 0 | 0 |
  | the same pooled round reused | 1 more | 1 (the pool handed back the same node) |
  | two passes 0.1 s apart | 2 | 2, both distances ≤ R |

  `test_near_miss` — **17 checks, 0 failures** on the new code; on the old behaviour (the
  `Feel.play` line removed, nothing else changed) the same suite is **3 failures** — "0 calls" for
  the 0.5 R pass, the reuse and the pair (`tmp/enemies/r11_nearmiss_OLD.log`). `Feel.event_requested`
  is what is counted, i.e. this unit's own calls, before the director's 0.25 s row cooldown.

  One bug found by re-reading my own code before committing, with its own FAIL/PASS pair: the first
  version cached the hurtbox **volumes** (world-space capsules) alongside the node references for
  `REFRESH_FRAMES`, and a mech at 60 m/s covers 15 m inside that window — a stale volume would have
  invented misses behind a moving player and missed the ones in front of it. Only the node
  references are cached now; every transform is read per call. The check is "a player that moves
  into the round's path still gets its near miss": the round passes 1.5 R from where the dummy
  starts and 0.5 R from where it is when the round arrives — **0 calls** with the volume cached,
  1 call without.

  **3. `test_ai` passed on a time-to-death outside SPEC's band.**
  Cause: two of them. (a) the gate was 18–50 s and the measurement fell back to the whole window
  when the "all 3 + 2 held at once" share was too low, so it printed `dies in 22.2 s` and called it
  ok; (b) that share could only ever be a peak — `release` shuts a whole kind for
  `REGRANT_DELAY` and `request` refuses while anyone still holds one — so it sat at 4–14 %.
  Fix: the lead's definition (r16 Round 2, and the wording now in SPEC §7.1) — **the pool at
  capacity**: every slot of that kind held, or shut by the re-grant delay, while another monster of
  that kind is still asking. `AttackTokenPool` now records askers and answers `askers`, `asking`,
  `cooldown_left`, `slot_state` and `at_capacity`; `test_ai` logs the four state shares per kind,
  the at-capacity share and the mean asker count, and gates 25–35 s **and** ≥ 80 % at capacity, both
  as FAILs. The measurement runs on a **pressure pack** (see Tuning choices) because SPEC's case only
  exists when the pool is the limiter.

  | run | melee at capacity | ranged at capacity | incoming | dies in | verdict |
  |---|---|---|---|---|---|
  | old gate, old damage rows (`tmp/enemies/r11_ai_base.log`) | 14 % "all five held" | — | 450 DPS | **22.2 s** | `ok … 18-50 s` (passed a number SPEC forbids) |
  | new gate, old damage rows | 100 % | 100 % | 444 DPS | **22.5 s** | **FAIL** |
  | new gate, re-tuned damage rows | 100 % | 100 % | 312–393 DPS | 25.5–32.0 s | PASS ×5 |

  Five consecutive runs of the final build (`tmp/enemies/r11_ai_5runs_final.log`), each 14 checks /
  0 failures:

  | run | melee at capacity (mean askers) | ranged at capacity (mean askers) | incoming DPS | dies in | physics, 40 enemies |
  |---|---|---|---|---|---|
  | 1 | 100 % (9.7) | 100 % (5.6) | 333 | 30.1 s | 2.616 ms |
  | 2 | 100 % (10.0) | 100 % (5.1) | 351 | 28.5 s | 2.857 ms |
  | 3 | 100 % (10.2) | 100 % (5.1) | 350 | 28.6 s | 2.861 ms |
  | 4 | 100 % (9.7) | 100 % (5.3) | 312 | 32.0 s | 2.821 ms |
  | 5 | 100 % (9.7) | 100 % (5.8) | 393 | 25.5 s | 2.888 ms |

  Per-kind state shares, run 1 (`BALANCE tokens …`, printed every run): melee `at_limit 15 %
  delay_shut 85 % free_asking 0 % free_idle 0 %`; ranged `at_limit 36 % delay_shut 64 %
  free_asking 0 % free_idle 0 %`. The same block on the *scenario* mix (2 spitters, 2 harriers,
  before the pressure pack) read `ranged at capacity 42 %  mean askers 0.5` — that is the number
  that showed the pack, not the pool, was short.

  The TTK and PERF lines are unchanged by this round: every archetype is still inside its SPEC §7.1
  band (ripper 0.40 s, harrier 3.00, spitter 5.00, mantis 8.00, juggernaut 25.71 on its armoured
  body) and physics with 40 enemies is 2.6–2.9 ms against the 6 ms budget on a quiet machine.

  **Suite run at the end of r11** (`tmp/enemies/r11_suites.log`, `tmp/enemies/r11_consumers.log`):

  | suite | result |
  |---|---|
  | `check --only=res://enemies/` | **107 files, 0 failed, 0 engine errors, 0 warnings** (HEAD baseline: 102 files, 0/0/0) |
  | `test_audit` | 25 checks, 0 failures |
  | `test_fight` | 13 checks, 0 failures, 0 engine errors |
  | `test_status` | 90 checks, 0 failures |
  | `test_projectile` | 22 checks, 0 failures |
  | `test_spawner` (`--enemies=ripper:4,mantis:1` / `--no-enemies`) | 9 / 6 checks, 0 failures |
  | `test_main_spawn` (`--enemies=ripper:6` / `--no-enemies` / `--stub=enemies`) | 6 / 2 / 2 checks, 0 failures |
  | `test_spawn_safety` (new) | 10 checks, 0 failures |
  | `test_near_miss` (new) | 17 checks, 0 failures |
  | `test_ai` ×5 | 14 checks, 0 failures each |
  | `enemies/boss/tests/test_boss.gd` | 135 checks, 0 failed |
  | `flow/tests/test_flow.gd --sandbox --flow --spawn=0,1,60` | 252 checks, 0 failed |
  | `combat/defense/tests/test_defense.gd` | 144 checks, 0 failed |
  | `combat/skills/tests/test_skills.gd` | 275 checks, 0 failed |

- **Lead r10, 2026-11-03** (roar + no zero scale on a dying monster). Log `tmp/enemies/r10_roar.log`,
  captures `captures/enemies_r10_roar_t1_0.jpg` (charge windup, red unblockable tell on the HUD
  vignette, brute 200 m out and closing) and `captures/enemies_r10_roar_t12_0.jpg`.

  | what | check | old code | fixed |
  |---|---|---|---|
  | charge windup roar | `test_audit` "r10 #1 …" ×3 + the probe's model trace | `set_locomotion(&"roar")` → idle, clip never played | `roar ×1 clip=roar` per windup |
  | charge reachable | `test_ai` telegraph log, 19-monster mix | **0 charges in 36 s** | `TELEGRAPH 0.27s juggernaut#18 juggernaut_charge (unblockable)` |
  | dying-monster scale | `test_audit` ×3 + `--nan-watch` in 3 probe runs | 40 NANWATCH reports per fight | **0 NANWATCH**, smallest scale 0.001 |

  Probe trace of one charge (solo juggernaut, `--nan-watch`, `DRIVE done t=36.0 errors=0
  warnings=2`, both warnings audio-unit sound ids — Requests):
  ```
  FIGHT 11.75s telegraph juggernaut juggernaut_charge (unblockable)
  FIGHT 11.76s juggernaut action charge ×3 clip=charge   ← the brain's attack clip
  FIGHT 11.77s juggernaut action roar   ×2 clip=roar     ← the windup roar, once
  FIGHT 12.46s juggernaut action charge ×4 clip=charge   ← 0.7 s later: the dash
  ```
  Suite after the change: `check --only=res://enemies/` **88 files, 0 failed, 0 errors, 0
  warnings**; `test_audit` **25 checks, 0 failures**; `test_ai` **12 checks, 0 failures**, 79
  telegraphs, **physics 3.39 ms with 40 enemies** (budget 6.0, quiet machine); `test_fight` 13/0;
  `test_status` 90/0; `test_projectile` 22/0; `test_spawner` 9/0; `test_main_spawn` 6/0.
- **Nav path-query errors + dissolve zero-scale, 2026-11-02** (lead notes 02:40 and melee r6).
  Real city fight, `fight_probe` + `fight_timeline.json`, 15 monsters, 36 s: **54 engine errors → 0**
  (46 of them were `_query_task_build_path_corridor`, 40 from the spawner's reachability query and
  6 from the agent's own). Same run after the fix: `DRIVE done t=36.0 errors=0`, 30 telegraphs,
  20 hits taken, 1 stagger, 1 kill, and the only error left in the whole log is
  `res://world/art/detail/facade_signs.gd:138` (city-art's file, not mine). Sandbox fight with
  `--nan-watch`: **0 errors, 0 NANWATCH lines**. Logs `tmp/enemies/navfix10.log`,
  `tmp/enemies/fight_final_city.log`, `tmp/enemies/navfix13.log`.

  | what | check | old code | fixed |
  |---|---|---|---|
  | spawner reachability query | `test_fight` "an off-mesh centre still spawns on the ground" | ring point 500 m in the air | on the navmesh |
  | failed-corridor detection | `test_fight` "a two-corner path through a wall reads as a failed corridor" / "across open ground is left alone" | no detection at all | scenery ray tells them apart |
  | breaker | `test_fight` "one failed query silences the unit's path queries" | 54 errors per fight | 0 |
  | breaker false positives | `test_fight` "a healthy navmesh never trips the breaker" (30 s, 15 monsters, 518-polygon navmesh) | — | never trips |
  | dissolve scale | `test_audit` ×3 + `test_fight` "3 monsters died and dissolved" | smallest scale 0.00000, \|det\| 0, **11 466 degenerate transforms** in one fight | 0 |

  `res://enemies/tests/test_fight.gd` — **13 checks, 0 failures**: a 30 s scripted fight (full SPEC
  mix, dummy player running a 90 m arc then hovering 300 m over the deck for 12 s so the leash has
  to relocate monsters, 3 kills so death → wreck → dissolve → pool runs inside the window) asserting
  **0 engine errors** through `res://tools/error_counter.gd` and 0 degenerate transforms through its
  own scan, plus the breaker's logic against a wall.
  `res://enemies/tests/test_audit.gd` — **21 checks, 0 failures** (18 + the 3 dissolve ones).
  Both new gates were run against the old code and failed there.
- **Robustness round, 2026-11-02** (`reviews/enemies-audit.md`, 13 findings, commit `6f96ae3`).
  All 13 fixed; the 6 high findings plus #7/#9/#12 have checks in the new
  `res://enemies/tests/test_audit.gd` (now **21 checks**). Each check was verified to fail
  against the old code before it was kept:

  | finding | check | old code | fixed |
  |---|---|---|---|
  | #1 knockback integrator | 18 m/s hit on a ripper | **115.4 m** of travel | 4.1 m (peak |v| 14.5) |
  | #2/#3 dissolve latch | `dissolved` in 3 s | **210 times** | 1 |
  | #4 steer_dir normalisation | steer at a 150 m corner | **240 m/s** (speed 30) | 30.0 m/s |
  | #5 leash / reachability | goal 8 m above the navmesh | unreachable | reachable |
  | #6/#8 Undertow pull | 120 m/s² for 0.5 s | **0.0 m** of drift | 4.0 m (8.8 vs a 4.8 m settle baseline) |
  | #7 attack-start turn | rotation in the attack-start tick | **51.3°** | ≤ 1.9° |
  | #9 pull inherits a slow | factor after a pull | 0.05 | 1.0 |
  | #12 aim fallback | aim with no live target | the shooter's own origin | remembered point |

  Scripted fight with `--nan-watch` (`fight_probe`, 15 monsters, 36 s): **0 NANWATCH lines**, 56
  telegraphs, 12 perfect dodges, 1 ring jumped, 11 hits taken, `alive=15`. The only engine errors are
  the pre-existing `audio/event_router.gd on_simple` arity mismatch (12, all the same line) — see
  Requests #1. Log: `tmp/enemies/fight_nan.log`, captures `captures/enemies_rig_t14/24/34_0.jpg`.

- `check --only=res://enemies/` → **48 files, 0 failed, 0 engine errors, 0 warnings**.
- **SPEC §7.1 balance model**, printed by `test_ai.gd` every run and asserted:

  | archetype | HP | part | ×armour | TTK @1,000 DPS | band | |
  |---|---|---|---|---|---|---|
  | ripper | 400 | body | ×1.00 | 0.40 s | ≤ 0.5 | ok |
  | harrier | 3,000 | body | ×1.00 | 3.00 s | 2–4 | ok |
  | spitter | 5,000 | body | ×1.00 | 5.00 s | 4–6 | ok |
  | mantis | 8,000 | body | ×1.00 | 8.00 s | 6–10 | ok |
  | juggernaut | 9,000 | body | ×0.35 | 25.71 s | 20–30 | ok |

  The juggernaut's band is deliberately its **armoured body** case: the ×0.15 front plate is what
  stops the player cheesing it (60 s) and the ×2.5 back point is the reward for flanking (3.6 s),
  which is the whole fight.
- **Incoming damage**: the original 20-run measurement (min 21.8 s, max 39.4 s, median 30.1 s) was
  taken **before** the robustness round, when ground monsters closed at the 60 m/s cap because of the
  steering bug. Re-measured after the fix: 5 runs at 348–440 DPS → 22.7–28.7 s, median 24.8 s. See
  Known issues. Per-attack split is printed each run (typically ripper_leap_bite 80–100,
  ripper_bite 45–75, harrier_dive_bomb 58–131, spitter_acid_lob 25–75 DPS).
- `test_status.gd` → **90 checks, 0 failures, PASS** (incl. `clear_prime` signal sequence).
- `test_projectile.gd` → **22 checks, 0 failures, PASS**.
- `test_ai.gd` → **12 checks, 0 failures, PASS**, `SCENARIO complete at 12.0 s (ceiling 25 s)`,
  **sim wall 11 s** on a quiet machine, AI scripts **0.45–0.52 ms/frame**, physics **4.6 ms** with
  40 enemies (AI-off baseline 3.0 ms, marginal cost 1.6 ms). Cleanest readings on an unloaded box:
  **3.0–5.8 ms** against the 6 ms budget.
- `test_spawner.gd` → **9 checks, 0 failures** with `--enemies=ripper:4,mantis:1`, 3 with
  `--no-enemies`: stand-off, exact mix, agent classes, unknown type refused, ripper pooling.
- `test_main_spawn.gd` → **6 / 2 / 2 checks, 0 failures** across `--enemies=ripper:6`,
  `--no-enemies` and `--stub=enemies` **from the real `main.tscn`**.
- `tools/godot.sh run res://main.tscn 25 --sandbox --enemies=ripper:6` → 60 fps, **0 errors**.
- Real fight, `main.tscn` + `PlayerMech` + camera rig, 15 monsters, 36 s: damage, knockback,
  perfect dodge, stagger, kills and **death** all observed through the player's own pipeline
  (`Events.player_damaged` / `perfect_dodge` / `player_died` / `hit_landed`). Across runs:
  16–24 hits for 4 700–10 300 damage, 3–13 perfect dodges, 0–7 staggers, 0–6 kills, and one run
  where the player died at 32 s with 9 monsters left. Juggernaut slams went from 0–1 per fight to
  **5 per fight** after the range/weight fix.
- Captures: `captures/enemies_fight_pack.jpg`, `_telegraph_glint`, `_telegraph_red`, `_perfect_dodge`,
  `_big_hit`, `_shockwave`. Gallery: `captures/enemies_telegraph_parry.jpg` (white diamond) and
  `enemies_telegraph_red.jpg` (red inverted wedge) are the two shape cues side by side.
  Movies: `captures/enemies_fight.avi` (shipping rig) and `enemies_fight_cam.avi` (probe follow
  camera — the one worth watching), both 37 s.
- `melee-defense` suite re-run against the reworked projectile: `test_defense.gd` **67 checks, 0
  failed** — no regression on the catch field / Mirror Guard side.

## Known issues
- **The juggernaut is starved of attack tokens in a big mix.** With 8 rippers attacking constantly
  the 3 melee tokens are always held, and the pool is first-come-first-served, so in the 15-monster
  probe fight the brute spends the whole 36 s in `approach` at ~130 m without ever committing (the
  charge change did not help there — it never gets a token). Solo or in a small mix it charges
  normally. A priority rule (a 22 m brute outranks a 6 m ripper for a slot) would fix it; it is a
  fairness-vs-spectacle call, so it is a Request rather than a silent change.
- **`test_audit`'s #5 leash check is load-sensitive.** It failed once on this box (`moved 5.0 m`
  instead of > 50 m) while the machine was busy and passed on the re-run and in every run since;
  it depends on 8 s of wall-clock physics to notice a stranded monster.
- **The city's baked navmesh is shattered, so monsters steer directly there.** `world/city/nav/
  index.json` reports 2 005 islands for the small class (20 403 polys), 856 for medium (9 567) and
  260 for large (3 353), with the biggest island only 10–14 % of the polygons — so roughly a
  quarter of all path queries fail, and a cross-street path mostly does not exist. The unit now
  costs 0 engine errors there (was 54 per fight) because the first failure silences path queries
  for 60 s and the pack steers straight at the player, which is what the engine's degenerate path
  made it do anyway — but monsters walk into buildings instead of around them until the bake is
  fixed. See Requests #14. In the sandbox (518 polys, one island) pathing is unaffected: `test_fight`
  asserts the breaker never trips on a healthy navmesh.
- **The breaker is a heuristic.** A failed corridor and a straight successful path are the same
  shape (two corners, both ends on the mesh, `is_target_reachable() == true`), and neither the path
  metadata nor `query_path` tells them apart, so the tie-breaker is a scenery ray along the path.
  A navmesh that is walkable but has a prop standing in it can therefore read as a failure — which
  costs one 60 s window of direct steering, not correctness. `test_fight` checks both directions
  (wall ⇒ failure, open ground ⇒ not).
- **The spawner no longer proves reachability with a path query**, because that query is what the
  engine errors on. A ring point is now accepted if it projects onto the map within 60 m and sits
  within 12 m of the player's own level. Two islands at the *same* level can still strand a monster;
  the leash notices after 8 s (`is_target_reachable()` is true on a degenerate path, so the leash
  measures distance instead) and puts it back.
- **Approaches are now honestly slow** (audit #4 fallout). Ground monsters used to close at the
  60 m/s cap because a far nav corner was read as a speed multiplier; they now move at their tuned
  18–30 m/s. Against a stationary player nothing changed (`test_ai`: all 12 monsters engaged inside
  25 s), but in the scripted fight — where the probe mech sprints away — a spitter (18 m/s) ends up
  340–490 m out and takes ~20 s to re-enter its 150–300 m band. It keeps lobbing from wherever it
  is. That is the correct reading of SPEC §7 (artillery loses a fleeing target), but it is the one
  visible behaviour change from this round.
- **Melee knockback is still applied twice**, once by `EnemyBase.take_hit` (mass-scaled) and once by
  `MeleeStrike.shove` (`game/combat/melee/melee_strike.gd:69-72`, not my file). With the integrator
  fixed the second copy only decays at the brain's steering rate, so it adds roughly K²/240 m — about
  a third on top of the intended K²/80. I added `EnemyBase.handles_own_knockback() -> true` as the
  contract for the caller to test. See Requests #12.
- **The perf number needs a quiet machine.** This box runs at load average 12–90 from the other
  units. `test_ai.gd` prints the AI-script cost, the ai_on physics min/mean/peak and an ai_off
  baseline every run, and picks its verdict from the baseline: clean (≤ 2.8 ms) gates the absolute
  frame time, mildly loaded (≤ 6 ms) gates the AI's marginal cost, and above that — where 40 idle
  bodies already cost more than the whole budget — the number is printed but not gated, with the
  reason. Clean readings: 3.0–5.8 ms with 40 enemies against a 2.4–3.0 ms baseline.
- **`res://audio/event_router.gd:70` throws on every hit** (audio unit, in flight): it reads
  `hit.source_kind`, which is not a field on `HitInfo`, and its `perfect_dodge` listener fails the
  same way. `res://player/mech/mech_dash.gd:60` reads `_dash_tick` off a Nil. `res://ui/**` throws
  too (`hud.gd:82`, `widgets/callouts.gd:69`, `widgets/tutorial.gd:70`) — recording the movie with
  the HUD instanced produced 20 367 errors, all from those widgets. Every number above is from a
  `--stub=hud` run or a HUD-free test; with the HUD stubbed and the audio/mech fixes pending, my
  runs are 0 errors.
- The juggernaut lands few *charges* now, by design: charge needs 80 m, so inside that it slams.
- Placeholder bodies are primitives, as briefed: the juggernaut's arms are plain boxes and the
  mantis reads as a slab at 60 m. Size, colour and silhouette are right; shape detail waits for the
  Tripo models.
- **The incoming rate is measured on a pressure pack, and it still swings ±8 % run to run.** The
  window is only accumulated while the pool is at capacity (SPEC §7.1's case, the lead's definition),
  which is now 100 % of the 20 s sample in every run — but *which* monsters hold the slots still
  moves the rate: five consecutive runs gave 333 / 351 / … DPS around a median of ~335, i.e. a player
  who never defends dies in **28–31 s**, inside the SPEC's 25–35 s with the gate tightened to exactly
  that. Attack damage is the lever (the rows were re-tuned ×0.86 against r10's values for this); the
  physics is not.
- **"Full attack tokens" needs a pack that over-subscribes the pool.** With the brief's scenario mix
  (12 rippers, 2 mantis, 2 spitters, 2 harriers, 1 juggernaut) the melee kind is at capacity 100 % of
  the window (10 askers for 3 slots) but the **ranged kind is not**: two spitters and two harriers
  cycle slower than the two ranged slots hand out, so the pool is not the limiter and it sat at
  capacity 40–95 % of the window (mean askers 0.5–1.7). The balance phase therefore spawns its own
  **pressure pack** — the same mix plus two more spitters and two more harriers, all placed in their
  SPEC §7 bands on bearings with clear sight of the dummy — which puts both kinds at capacity 100 %
  of the window (mean askers ~10 melee / ~5 ranged). Because the pool caps how many attacks land,
  this measures the cap instead of raising it. The scenario checks above it still run on the brief's
  19-monster mix.
- ~~**A monster that loses sight of the player can park blind for the rest of the fight.**~~
  **CLOSED in r12** — see Evidence. Found while instrumenting the ranged askers: a spitter spawned on
  an unlucky bearing lands in the sandbox's -30 m trench, the trench wall blocks its line of sight,
  and the brain then circled the remembered point's stand-off ring forever — moving, silent and
  blind. `EnemyBrainSearch` now walks to the last known position, sweeps the horizon, widens the
  search in rings and gives up to the arena anchor; the spawner puts a blind, far monster back into
  the fight on a ring point it can see the player from. `test_los_loss.gd` is the gate (37 failures
  on the old brain, 0 on the new one). `test_ai` still places its ranged monsters on clear bearings —
  that is about measuring the pool at capacity, not about working around this any more.
- The spitter's acid lob does not lead a moving target: 14 lobs, 0 hits in one run where the player
  ran the whole time (it lands reliably on a standing target — `test_projectile.gd`). Artillery
  leading is a design question, not a bug.
- `tests/test_ai.gd` is 594 lines (481 before r11, 583 after it, 594 after r12's hit counts). It is
  under the 600-line gate but only just, and the next change to it should split the perf phase
  (`_measure_perf` / `_sample_physics` / `_judge_perf`, ~60 lines) into its own file first.
- `enemies/brain.gd` is 413 lines after r12 (it was 383). The search half was split out into
  `enemies/brain_search.gd` this round because it was the one block with almost no shared state. The
  rest is one cohesive state machine whose phases (`_attack` → `_phase_telegraph` → `_phase_active`
  → `_phase_recover` → `_finish_attack`, plus `interrupt`) all mutate the same `state` / `phase` /
  `_phase_left` / `_hit_done` / `_token` / `_cooldowns`, so cutting it into a second RefCounted
  would mean the new object reaching back into the brain for six fields — trading readability for a
  line count. Under the 600-line gate; flagging it rather than churning it inside a bug round.
- **`test_los_loss`'s check count varies run to run** (51–58): a monster that reaches the player and
  never loses the target skips its three behavioural checks and prints a `note` instead. The gate is
  "0 failures", which is stable; only the count moves.

## Tuning choices (numbers the docs left open)
- **SPEC §7.1 is the source of truth** for HP, attack damage and telegraph floors; the numbers are
  in `EnemyTypes` (`PLAYER_DPS`, `TTK_BAND`, `TTK_PART`, `balance_report()`) and asserted by
  `test_ai.gd`. `data/balance/balance.csv` and `tools/balance.py`, which SPEC §7.1 names as the
  thing that "keeps it honest", do not exist — see Requests.
- Attack damage/impact/cooldowns per archetype (`EnemyAttack` rows in each archetype script). The
  damage column was raised 25 % in the robustness round and is now **×0.86 of the r10 values** (r11),
  because the r11 gate measures the pool's cap instead of a peak: ripper leap 125 / bite 100, mantis
  280 / 225 / 565 / grab 970, spitter lob 320, harrier strafe 160 / dive 755, juggernaut charge 1295 /
  slam 970 / swipe 665. Impact (stability damage) is untouched, so stagger behaviour is unchanged.
- `EnemyTypes.PHASE_MIN_TELEGRAPH` 0.40 s, `PHASE_MIN_UNBLOCKABLE` 0.60 s, enforced in
  `EnemyAttack.make` so no table can ship an unreadable windup.
- Juggernaut: charge `range_min` 80 m (was 40 — inside that it re-charged instead of closing, so
  the slam fired once in three fights), slam `range_max` 70 m / weight 1.8 / cooldown 5 s, swipe
  weight 0.8.
- Monster speeds 30 / 24 / 18 / 55 / 20 m/s and sight 320–450 m.
- `Perception.LOSE_MEMORY` 10 s, `SIGHT_INTERVAL` 0.12 s, peripheral awareness at 25 % of sight.
- `EnemyBrain` ALERT_TIME 0.25 s, REPOSITION_TIME 0.9 s, ARRIVE_TOLERANCE 1.2.
- `EnemyLocomotion` REPATH_DISTANCE 8 m, UNSTICK_AFTER 1.0 s, BIND_RETRY 0.5 s, whisker range 30 m
  every 0.15 s.
- `EnemySpawner` SPAWN_TRIES 12, LEASH_AFTER 8 s.
- `EnemyShockwave` SPEED 60 m/s, band 6 m, CLEAR_HEIGHT 6 m (the mech's jump apex is 8 m; at the
  original 9 m the ring could not be jumped at all).
- `EnemyBase` EXECUTE_RANGE 14 m / ±60° (Core Rend 7 m at the dossier's 8 m scale, ×2).
- `fight_probe.gd` DODGE_LEAD 0.06 s, JUMP_LEAD 30 m, SHOT_RANGE 55 m, RING_SHOT_RADIUS 28 m.
- `test_ai.gd` RUN_MIN 12 s (early exit), PERF_BUSY_MS 2.8 (every clean baseline on this box is
  2.43–2.69 ms), PERF_BUSY_MARGIN_MS 9.0, DPS_WARM 6 s, **DPS_SAMPLE 40 s** (20 s before r12 — see
  Evidence), DEATH_MIN/MAX 25/35 s, CAPACITY_MIN 0.80.
- **`test_ai`'s pressure pack** (r11): the balance phase clears the scenario's 19 monsters and spawns
  12 rippers + 2 mantis + **4 spitters + 4 harriers** + 1 juggernaut, so both token kinds are
  over-subscribed and the pool is the limiter — which is what SPEC §7.1's "full attack tokens" means.
  The ranged monsters are placed at fixed offsets in their SPEC §7 bands (spitters at 180–230 m,
  harriers at 60–110 m) on bearings with clear sight of the dummy; the melee mix keeps the spawner's
  own 150–250 m ring. The scenario checks (engagement, stuck, telegraphs, ≤3 melee / ≤2 ranged) still
  run on the brief's own 19-monster mix, unchanged.
- **`EnemyNearMiss.RADIUS` is 6 m of clear air off the hurtbox surface** (lead decision, r16 Round 2),
  and the strength ramps 1.0 → 0.5 from a graze to the edge of the radius. A lob is treated exactly
  like a flat round — it fires at its closest approach — with one extra rule: a shot that ends
  without ever receding (a burst the player's cover ate) gets its beat when the round is pooled, and
  a round whose blast reached the player never gets one. The 4/s limit is the FEEL row's own 0.25 s
  cooldown; this unit adds no limiter.
- `docs/ART.md` and `docs/MAP.md` named by the brief do not exist yet; placeholder colours come from
  the brief itself (#1B1E24 carapace / #9BFF3A acid glow / #B04CFF weak point), plus two documented
  additions: a rim light on the near-black carapace so the silhouette reads against a bright city,
  and an amber tell while staggered (juice §7 "amber = in finisher range").

## Captures needed (windowed runs — this round is headless-only)
`tools/godot.sh drive|movie` refuse without the lead's `MC_WINDOW_OK=1`, so these are written but not
run. Every number they are meant to confirm is already covered headlessly (above); what they add is
pixels and the `DRIVE done … errors=0` line on the real build.

**r12 — the windowed fight capture for this round.** The LOS-loss behaviour is proved headlessly by
`test_los_loss.gd`; what a window adds is seeing a monster sweep the horizon and walk home, and the
real-build error line for the new brain states.

```
# r12 #1 — the search and the walk home. The probe's follow camera, a wall between the mech and the
# pack: monsters should be seen sweeping the horizon at the last known position (12-18 s), then
# peeling off toward their anchor (20-26 s).
tools/godot.sh drive --scene=res://enemies/tests/fight_probe.tscn \
  --timeline=res://enemies/tests/fight_timeline.json --out=enemies_r12_search \
  --shots=6,14,22,30 --sandbox --stub=hud --nan-watch --probe-cam=follow \
  --enemies=ripper:6,mantis:2,spitter:2,harrier:2,juggernaut:1
# r12 #2 — the same fight as a movie, which is the only way to judge whether "it stopped, looked
# around and gave up" reads as intent rather than as a statue.
tools/godot.sh movie --movie=$HOME/m/mecha-city/captures/enemies_r12_search.avi \
  --scene=res://enemies/tests/fight_probe.tscn --timeline=res://enemies/tests/fight_timeline.json \
  --sandbox --stub=hud --probe-cam=follow \
  --enemies=ripper:6,mantis:2,spitter:2,harrier:2,juggernaut:1
```

```
# 1. the spawn probe: 10 trials, every one under 1 m/s and 0.1 m (the acceptance repro)
tools/godot.sh drive --scene=res://enemies/tests/spawn_probe.tscn \
  --timeline=res://enemies/tests/spawn_probe.json --sandbox --god --quality=low

# 2. the r11 fight: stills at t=14/24/34 plus the near-miss lines and the summary count
tools/godot.sh drive --scene=res://enemies/tests/fight_probe.tscn \
  --timeline=res://enemies/tests/fight_timeline.json --out=enemies_r11 \
  --shots=14,24,34 --sandbox --stub=hud --nan-watch \
  --enemies=ripper:8,mantis:2,spitter:2,harrier:2,juggernaut:1

# 3. the near-miss movie (harrier strafes are flat 220 m/s rounds: the readable flyby)
tools/godot.sh movie --movie=$HOME/m/mecha-city/captures/enemies_r11_near_miss.avi \
  --scene=res://enemies/tests/fight_probe.tscn --timeline=res://enemies/tests/fight_timeline.json \
  --sandbox --stub=hud --enemies=harrier:2,spitter:2
```
What to look for, and where:
- (1) `SPAWN trial=… max_speed=… moved=…` ×10 then
  `SPAWN PROBE done trials=10 flung=0 worst_speed=… worst_moved=…`. At the r15 baseline the same ten
  trials printed 15979 m/s / 7846 m and 16866 / 8285 for the two rippers under the hero.
- (2) `FIGHT <t>s near_miss <attack> <d> m` per call, and
  `FIGHT SUMMARY … near_miss=<n> played_by_director=<m>` beside the director's own count; every
  distance must be ≤ 6 m. Stills land in `captures/enemies_r11_t14_0.jpg` etc.
- (3) the near-miss timestamps from (2) are the scrub points in the movie — the flyby plays at the
  closest point of the round's path, so the sound is where the round went past.

## Requests (to the lead / other units)
1. ~~**`res://audio/event_router.gd:70` errors on every hit**~~ — **CLOSED (r11 re-check).**
   `source_kind` no longer appears anywhere under `game/audio/` or `game/core/`, `mech_dash.gd` now
   reads `l._dash_t` (its own field) and the HUD widgets have been rewritten. My last three
   `main.tscn` suites report `TEST ERRORS 0 (known 0, warnings 4)` — the four warnings are the post
   stack's own (`world/post/effects/post_lens.gd:93`). Nothing of this is left for audio, mech-move
   or hud.
2. **SPEC §7.1 names `data/balance/balance.csv` + `tools/balance.py`** as what keeps the balance
   honest; neither exists. My table lives in `EnemyTypes` (`TTK_BAND`, `TTK_PART`,
   `balance_report()`) and is asserted by `test_ai.gd`, so the numbers are checked — but they are
   checked inside my folder. Worth promoting to the shared file so the weapons and skills units
   tune against the same table.
3. ~~Audio: the unblockable telegraph plays `Audio.play(&"telegraph_unblockable", pos)`~~ — **CLOSED
   (r11 re-check).** `telegraph_unblockable` is in `audio/tables/table_enemies.gd` and the manifest
   (`audio/sfx/telegraph_unblockable.wav`), as are `near_miss` (3 variants) and `near_miss_flyby`
   (aliased to it).
4. Weapons unit: for the ×1.8 staggered bonus `HitInfo.weapon` must be one of
   `EnemyTypes.CHARGED_WEAPONS` = `rifle_stage1 / rifle_stage2 / charge_slash / zenith_lance`
   (agreed with the lead's r1 note); anything else counts as "other" (×1.35). `rifle.gd` currently
   stamps `beam_rifle` for both charge stages, so a charged rifle shot gets ×1.35 today — please
   stamp `rifle_stage1` / `rifle_stage2`. `charge_slash` (melee table) and `zenith_lance` already
   match. Ripper HP is now 400, so one 700-damage stage-1 shot kills it.
5. Two `class_name` collisions with other units, worked around by renaming mine:
   `ShockwaveRing` (feel, `fx/vfx/shockwave_fx.gd`) → mine is `EnemyShockwave`;
   `ChaffCloud` (weapons, `combat/weapons/tests/chaff_cloud.gd`) → mine is `SporeChaff`.
   Worth a line in CONTRACTS §2 that `class_name` is project-global.
6. Weapons unit: the spore chaff cloud is in group `&"chaff"` with `covers(point) -> bool` and
   `consume_missile() -> bool` (4 charges) — please spend a charge instead of tracking a missile
   inside it. Its `&"owner"` is withdrawn when the spitter dies, same as the projectiles'.
   `EnemyProjectile.reflect(velocity, by)` sends a caught round back at 135 %
   (skills-catalog §4.7) and moves it to `Layers.PLAYER_SHOT`.
7. Melee-defense: `catch_field._freeze` stops a caught round's physics process, so a round held
   longer than `EnemyProjectile.LIFETIME` (6 s) never expires and stays out of the pool. `reflect`
   and a relaunch both restore the process, so throwing it back is fine — but please release or
   throw within the lifetime, or say the word and I will add a pool-side watchdog.
8. Melee-defense: `is_executable(by)` / `execute_hit(by, damage)` are live on every monster —
   staggered, alive, within 14 m and ±60° in front.
9. Skills unit: `EnemyBase.status` exposes `apply_slow(factor, s)`, `apply_pull(accel, s)`,
   `prime(s)`, `is_primed()` and the new **`clear_prime() -> bool`** (emits `primed_changed`;
   COLLAPSE uses it per CONTRACTS §4).
10. Monster-assets: `game/enemies/models/ripper/` now holds `ripper.glb` + textures, but not the
    `ripper_model.tscn` that CONTRACTS §6 names and `EnemyBodyBuilder` looks for
    (`res://enemies/models/<type>/<type>_model.tscn`), so the placeholder still runs. Please ship the
    wrapper scene with the contract API — `set_locomotion(state, speed)`, `play_action(id) -> float`,
    `socket(name)`, `hit_pause(s)`, `set_hit_flash(v)` — plus the two I use beyond the contract:
    `set_telegraph(kind, 0..1)` and `set_stagger(bool)`. **`set_telegraph` is load-bearing for
    accessibility**: it must show a distinct *shape* per kind (compact upright diamond = parryable,
    wide inverted wedge = unblockable), not only a colour, per SPEC §7.1. `break_plate()` is also
    called on the juggernaut. My placeholder implementation in
    `placeholder/monster_model.gd` is the reference if it helps.
11. City unit: `world.nav_map(class)` (CONTRACTS §7) is wired and used — `EnemyLocomotion` binds each
   monster to its class map and retries every 0.5 s until one exists, and `EnemySpawner` places each
   type on its own map. Everything falls back to the default map today. The sandbox's navmesh stops
   well short of the 150–250 m spawn ring, so there the spawner uses its ground-ray fallback by
   design; the city should bake far enough out for the ring to land on the mesh.
12. Melee-defense (audit #1, second half): `MeleeStrike.shove` adds `hit.knockback` to the receiver's
   `velocity`, but `EnemyBase.take_hit` already applies it, scaled by mass. Please skip the shove
   when `receiver.has_method(&"handles_own_knockback")` — I added that method for exactly this. Until
   then a melee hit on a monster carries ~1.3× its intended push: my test measures `take_hit` alone
   at 4.13 m for an 18 m/s hit (the intended K²/80 = 4.05 m), and the extra shove adds roughly
   another 1.35 m on top in the real game.
13. ~~Audio unit: `perfect_dodge` is bound through `on_simple` with the wrong arity~~ — **CLOSED
   (r11 re-check).** `audio.gd:113-117` now `unbind`s the signal's own argument count, so
   `on_simple(id)` receives one argument whatever the signal carries.

14. **City-build / lead: the baked navmesh is thousands of disconnected islands.** `world/city/nav/
    index.json`: small 2 005 islands / 20 403 polys (biggest 14 %), medium 856 / 9 567 (11.5 %),
    large 260 / 3 353 (10 %), plus 4 196 / 2 411 / 1 095 polygons dropped and "Navigation region
    synchronization had 37 edge error(s)". Consequence for my unit: about a quarter of all path
    queries fail, which in Godot 4.7.2 is one engine error each (`_query_task_build_path_corridor`,
    "It's not expect to not find the most reachable polygons") plus a degenerate start→end path that
    `is_target_reachable()` still calls reachable. I no longer issue failing queries (0 errors, was
    54 per 36 s fight), but monsters steer straight at the player instead of around buildings until
    the bake is connected — the nav links only attach 18/23/6 of 48 per class today. Two engine
    notes for the record: (a) the error is an `ERR_PRINT` where an empty path is the documented
    result, so *any* caller that queries across islands gets it, not just mine; (b)
    `map_get_closest_point_owner` answers `false` and `map_get_closest_point` returns `(0,0,0)` for
    every point while a map has regions but no synced polygons — the iteration id is already
    non-zero then, which is why `EnemyTypes.nav_query_ready` asks `world.nav_ready(cls)` when the
    world has one.
15. ~~Lead: `facade_signs.gd:138` assigns an untyped array to `Array[Vector2]`~~ — **CLOSED (r11
   re-check).** `AXES` is now declared `const AXES: Array[Vector2]` and every `axes.append(AXES[i])`
   is typed, so the drive error is gone.
16. Lead (r10 follow-up): the attack-token pool is first-come-first-served, so in the full 15-monster
    probe mix 8 rippers hold all 3 melee slots and the juggernaut never commits once in 36 s (it sits
    in `approach` at ~130 m). Its charge is now reachable and it charges normally solo or in a small
    mix. If the brute is meant to be a set piece, the pool needs a priority rule — say the word and I
    will add one (e.g. a holder with `mass_kg` ≥ 8 outranks a ripper for the next freed slot, still
    capped at 3).
17. ~~Audio unit: `juggernaut_slam` and `enemy_telegraph` are unknown sound ids~~ — **CLOSED (r11
    re-check).** `juggernaut_slam` is aliased to `jugg_slam` (`table_aliases.gd:69`) and both it and
    `telegraph_unblockable` have manifest rows with files.
18. **Tooling (r11): two new suites to add to `tools/suites.sh`.**
    `res://enemies/tests/test_spawn_safety.gd -- --sandbox --no-enemies --timeout=400` (10 checks, 0
    failures, 4 warnings from the post stack) and
    `res://enemies/tests/test_near_miss.gd -- --timeout=300` (17 checks, 0 failures, 0 errors).
    Neither is expected red. Both run under the strict host with no allow-list entries.
19. **mech-move (r11 item 1 follow-up): the hero still treats monsters as a moving floor.**
    `player_mech.tscn:6-7` sets `collision_layer = 4` / `collision_mask = 15` and nothing anywhere
    sets `platform_floor_layers`, so it is the engine default (every layer) — a monster that walks
    under the mech carries it, and before this round a monster that *spawned* under it threw it at
    16 km/s. The spawn half is fixed on my side (the per-tick trace is in the r11 evidence above);
    the "a monster moving under the hero carries it" half is a `platform_floor_layers` that excludes
    `Layers.ENEMY` (`player_mech.gd:102-108` sets none today). Not my file; the trace and the
    numbers are above if you want them.
20. **Lead / flow (r11 item 3): what the balance change does to SPEC §7.1's other row.** "A median
    run finishes a hive at 30–60 % HP" is measured against the *unsaturated* case, and enemy attack
    damage is now ×0.86 of r10's, so a hive fight that never saturates the pool lands roughly 14 %
    less damage than before: a player who takes every hit in a hive now ends it nearer 40–70 % HP
    than 30–60 %. If flow measures that row, the share rows `test_ai` prints
    (`BALANCE tokens <kind> at_limit / delay_shut / free_asking / free_idle`, plus the at-capacity
    share and the mean asker count) are the same numbers it needs — say the word and I will print
    them from a flow-driven fight instead of the sandbox.
21. ~~**Lead (r11 finding): a monster that loses sight of the player parks blind forever.**~~
    **CLOSED in r12** (commits `0119fc50`, `3bf3a1ef`). The "go and look" rule asked for here turned
    out to need more than `desired_point`: the remembered point never expired, so `_idle`'s patrol
    was unreachable and there was no terminal state at all. It is now a whole `SEARCH` → `RETURN` →
    `IDLE` branch (`enemies/brain_search.gd`) plus a leash that puts a blind, far monster back in the
    fight. Gate: `tests/test_los_loss.gd`.
22. **Lead / tooling (r12): I added one row to `tools/suites.txt`.** `enemies_los_loss |
    res://enemies/tests/test_los_loss.gd | --timeout=600`, next to `enemies_ai`. `suites.sh`'s
    coverage check fails the whole run for an unlisted `test_*.gd`, so a new suite cannot land
    without a row and the file is not one of the paths my brief hands me. One line, nothing else in
    the file touched — move it wherever you want it to live.
23. **Lead (r12): enemy damage rows are unchanged, but the *reason* they are right has changed.**
    `test_ai`'s incoming-damage gate now measures a pool whose slots are no longer wasted on the
    spitter's chaff puff and whose attacks can no longer fire out of range or on cooldown, over a
    40 s window instead of 20 s. The reading moved from 326–434 DPS (one run in ten outside SPEC's
    band) to 356–376 DPS, ten runs out of ten inside it, with no damage number edited. If you would
    rather the rows carry the whole retune explicitly, the factor is ×0.73 of the current values —
    but the current numbers already sit mid-band with ±14 % of headroom, so I left them alone.
24. **Lead (r12): `EnemySpawner`'s leash now moves monsters that are blind as well as stranded.**
    The blind branch only fires for a monster that has *already* fought the player
    (`perception.is_alerted()`), has had no target for `LEASH_AFTER` (8 s) and is more than
    `min(engage_range × 2, 120 m)` from them; it lands on a ring point it can see the player from and
    is turned to face them. That is a teleport, the same one the stranded branch has always used. If
    you would rather it walked, say so — it would need the monster to know where the player is, which
    is the one thing honest perception will not give it.
