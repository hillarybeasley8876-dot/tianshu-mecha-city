# flow status

## Captures needed (windowed — the lead runs these when the user OKs the screen)

Every one of these is refused by `tools/godot.sh` without `MC_WINDOW_OK=1`. Nothing in the r5b round
below depends on them: all four items are gated headless.

```bash
# 1. The three hive collapses on film — 8 frames 0.25 s apart through the REAL FlowHiveCollapse,
#    one sheet per hive. This is the windowed proof of r5b item 2 (the headless gate is
#    res://flow/tests/test_collapse_camera.gd, 50 checks).
cd ~/m/mecha-city
tools/godot.sh drive --timeline=res://flow/tests/collapse_film_drive.json --skip-menu --god \
  --nan-watch --flow-script=res://flow/tests/collapse_film.json --out=flow_r5b_collapse

# 2. The same three collapses as a MOVIE (the brief asks for one).
tools/godot.sh movie --movie=$HOME/m/mecha-city/captures/flow_r5b_collapse.avi \
  --timeline=res://flow/tests/collapse_film_drive.json --skip-menu --god --nan-watch \
  --flow-script=res://flow/tests/collapse_film.json --out=flow_r5b_movie

# 3. The whole city run: drop-in → tutorial → three hives → death/respawn → boss gate → catapult →
#    victory. 17 captures, the E2ECAMREPORT tally, and the three collapses in context.
tools/godot.sh drive --timeline=res://flow/tests/e2e_city_drive.json --skip-menu --god \
  --nan-watch --spire-hp-scale=0.05 --flow-script=res://flow/tests/e2e_city.json --out=flow_r5b_city

# 4. The bot's real-kit assault, for the r5 remainder (does the LEVEL_BAND/STAND_LIFT fix let it
#    finish a hive unaided?). 150 s, hive 2 only.
tools/godot.sh drive --timeline=res://flow/tests/assault_city_drive.json --skip-menu --god \
  --nan-watch --spire-hp-scale=0.05 --flow-script=res://flow/tests/assault_city.json --out=flow_r5b_assault
```

## Done — r5b (lead brief `reviews/flow-r5b.md`)

Three commits. Every new gate was run against HEAD first; the numbers in each section are the FAIL
count on HEAD and the PASS count after.

| # | commit | what |
|---|---|---|
| 1 | `ccd8f19` | the saved WIP from 11-05, finished: the E2E bot stands ON the floor it found |
| 2 | `79a1c9c` | the hive collapse films — the lens is solved against the city, not assumed |
| 3 | `120dab3` | `die` writes the HP; the mech announces the death |

`tools/godot.sh check` → **802 files, 0 failed, 0 engine errors, 0 warnings** (49 under `res://flow/`).
No file in `game/flow/**` is over 600 lines (the longest is `game_flow.gd` at 589).

| suite | command | result |
|---|---|---|
| flow | `test res://flow/tests/test_flow.gd -- --sandbox --flow --spawn=0,1,60` | **252 checks, 0 failed** |
| idle | `test res://flow/tests/test_flow_idle.gd -- --sandbox --spawn=0,1,60` | **8 checks, 0 failed** |
| collapse camera | `test res://flow/tests/test_collapse_camera.gd` | **62 checks, 0 failed** |
| die once | `test res://flow/tests/test_die_once.gd` | **9 checks, 0 failed** |
| boss | `test res://enemies/boss/tests/test_boss.gd` | **135 checks, 0 failed** |
| boss, city | `test res://enemies/boss/tests/test_boss_city.gd` | **20 checks, 0 failed** |

### 1 — the saved WIP, re-applied and finished (`ccd8f19`)

`tmp/lead/wip/flow/tracked.patch` applied clean against HEAD and is still needed: both of its hunks
fix the same real defect, and the E2E bot's "finish a hive with the real kit" work (the r5 remainder,
item 1 of "In progress" below) cannot be finished without them.

* **A mech's ORIGIN is its capsule CENTRE.** `FlowAssaultTargets.firing_spot` and
  `FlowDebugView._stand` both placed it `floor + 2 m`, so the solver pushed it out downward, it slid
  to whatever was below, and the r5 A2 beat spent its whole window on a stand 24 m **under** the hive
  with the aim 28° off. They now lift by `STAND_LIFT` (9.5 m) and the capsule's own half height + 2 m.
* **`LEVEL_BAND` (30 m).** A floor that far below or above the weak point is another LEVEL of the
  city: the line can be clear from there and the shot still never land, because the bot aims the rig
  by hand and the pitch it needs is outside what it accepts.

`game/flow/tests/e2e_city_drive.json` (the 900 s end cap for the `e2e_city` run) was restored from
`tmp/lead/wip/flow/untracked/` in the same commit. Whether the fix actually lets the bot finish a hive
unaided is a windowed question — **capture 4** under "Captures needed".

### 2 — the hive collapse films (`79a1c9c`)

**Two causes, both found by measurement, neither of them a guess.**

1. **The offset was built in WORLD axes and read in the DUEL FRAME.** `hive_collapse.gd` computed
   `back * 46 + side * 22 + UP * 20` from the world-space hero → hive direction and handed it to
   `request_cinematic`, which multiplies it by the duel frame's basis (CONTRACTS §5). With the aim
   lock released the frame's −Z is the hero's **FACING**, so the offset was rotated by the hero's yaw.
   Worked through at A5 with the hero 70 m east of the hive and facing it: the intended eye is 113 m
   from the spire; the one the rig got was **68 m** away and 90° round, inside a building. That is
   the trailer's m6 segment.
2. **Nothing checked the placement against the city.**

**New `game/flow/flow_collapse_shot.gd` (`FlowCollapseShot`, 222 lines).** It solves the stand:

* **Family one — `hero_side`:** behind and beside the hero on the axis the player was already
  fighting along. This is the composition the beat wants (the mech small in the foreground, the spire
  beyond it), so it is tried first at every level.
* **Family two — `ring`:** a ring round the spire itself, bearings walked outwards from the hero's
  own side, for a hive whose hero-side is walled in.
* Each candidate is **sphere-checked** for clear air (`PROBE` 3 m, `Layers.MASK_SIGHT`), **ray-checked**
  to the spire's foot and top, and **frustum-checked** (base and top inside the frame with `EDGE` 0.10
  of margin, so the ±3° of trauma shake cannot swing them out between ticks).
* **Three levels** give up one requirement each — the hero in frame, then the clear line to the spire.
  Clear air and the spire in frame are never given up. If even that fails, an overhead stand, and a
  `push_warning` naming the site.

**FlowHiveCollapse now takes the lens itself, with an EMPTY cinematic shot list.** That is the hook:
`CameraCinematic.request` still makes the cinematic active — so the rig stops following the hero, stops
writing its own transform and keeps advancing only the shake — but `_apply` is never called, so the
camera unit's collision resolve never runs either. **That resolve is why the obvious fix was not
enough:** it pulls the lens back along a ray from the duel frame's origin (the hero), so it can only
ever place a camera the hero can see. A survey of **1,344 stands** round A2 found **42** that can see
the hive at all, and every one of them is across the Interchange Knot. Flow places the lens, and
re-checks it every tick (re-solving up to 8 times if the hero walks into it).

Two smaller fixes in the same commit: a missing FX library no longer frees the collapse node at 1.35 s
and cuts the last 0.65 s of the beat (headless runs and `--stub=fx` lost it), and
`FlowHiveSpire._frame_the_fall` is gone — it locked the hero onto the spire for a duel frame nothing
reads any more.

**Gate: new `game/flow/tests/test_collapse_camera.gd`** (346 lines). It loads the real city, the real
`CameraRig`, the real `AimSystem` and the shipped `VfxLibrary`, and runs the real collapse at the real
`&"hive_site"` markers (A2, A5, A6 as city-layout r8 leaves them) — four hero bearings each, the last
one **walking** at 12 m/s, which is what proves the shot is pinned to the world. Every frame of the 2 s
shot is judged three ways: the lens outside every collider, the spire's base and top inside the
frustum, and a clear ray from the lens to both.

```
HEAD:  TEST 50 checks, 11 failed
       6 runs have the lens inside geometry for EVERY frame (A2 b2/b3, A5 b0, A6 b0/b2/b3)
       4 runs lose the spire's base or top out of frame for every frame
after: TEST 62 checks, 0 failed (slowest solve 2.0 ms)
       A2 b0-b3  240 frames  buried=0 clipped=0 blocked=0  ring stand
       A5 b0-b3  240 frames  buried=0 clipped=0 blocked=0  hero_side (b0,b1) / ring (b2,b3)
       A6 b0-b3  240 frames  buried=0 clipped=0 blocked=0  hero_side stand
```

The extra 12 checks (62, not 50) are a cost gate: the solve runs on the frame the core dies, in the
middle of the reward beat, so a sweep that costs a frame is a visible hitch. **The slowest solve of
the twelve runs is 2.0 ms**, against a 25 ms budget.

**Two things the gate taught, both now in the code:**

* The hero has to stand on **the hive's own deck**, not on whatever a downward ray from 300 m finds.
  A2 is a five-tier interchange (`tiers: [0, 16, 32, 56, 80]`) and the ray lands on a deck 48 m above
  the hive. The test's floor probe now starts 12 m above the hive's foot.
* The layout sets a hive's `tier` a few metres **inside** the deck slab it stands on — 3 m at A5 and
  A6, 3 m at A2. A ray to the very foot of the trunk therefore grazes that slab and stops short from
  every stand at every height. The line-of-sight test aims `FlowCollapseShot.FOOT` (8 m) up the trunk;
  the **framing** test still wants the true foot in frame. This is stated in both the solver and the
  test so the two cannot drift apart.

### 3 — `die` announces once (`120dab3`)

`FlowDebug.die` wrote `hp = 0` **and** emitted `Events.player_died`, because `--god` zeroes the damage
in `PlayerMech` and the real path cannot land. `MechDamage.sync()` runs at the top of every physics
tick and announces a death it sees reach 0 hp, so one debug death announced twice.

**Honest note on the gate:** mech-move r7b item 8 already collapsed the *observable* double emission
with its `_died_seen` latch, so `die.once` passes on HEAD too. What was still wrong is that flow was
the one doing the announcing. The emit is gone; flow writes the HP and the mech's latch announces it
on the next tick.

**Gate: new `game/flow/tests/test_die_once.gd`** — the REAL `PlayerMech` beside a `FlowDebug` in the
core sandbox, counting emissions across a `die`, a revive performed the way
`FlowProgress._restore_player` does it, and a second `die` (which is what proves the latch releases).

```
HEAD:  TEST 9 checks, 1 failed   die.silent_on_the_spot: flow announced the death itself
after: TEST 9 checks, 0 failed
```

**Evidence.** Every run in the table above is on disk: `tmp/flow/r5b/{collapse_camera,test_flow,
test_flow_idle,test_die_once,test_boss,test_boss_city}.log`. The A2 stand survey (1,344 samples, the
42/1,020/975 result) was a scratch probe and has been deleted; it is one `for` loop over
`FlowCollapseShot.ray_clear` and is quoted in Request 8 with the exact grid so it can be re-run.


## Done — r5 pass 1 (lead brief `reviews/flow-r5.md`, items 1–6)

Six commits, in the brief's order. Every new check was run against HEAD first: the numbers in each
section are the FAIL count on HEAD and the PASS count after.

| # | commit | what |
|---|---|---|
| 0 | `24c949e` | the E2E report split out of `flow_debug.gd` (457 → 423 lines), and `kill_spire` / `clear_arena` counted as fallbacks |
| 1 | `d670a58` | a death before the district opens is no longer a soft-lock |
| 6 | `273d643` | a respawn no longer re-arms the arenas the player finished |
| 5 | `f39b168` | falling out of the world is a respawn; PAUSE → ABORT goes back to the title |
| 2 | `409f6a9` | BOSS starts on a real touchdown; the boss checkpoints save probed points |
| 3+4 | `5129b4c` | the titan stays on its deck; a boss death gets exactly one respawn (boss status: `545d785`) |

`tools/godot.sh check` → **741 files, 0 failed, 0 engine errors, 0 warnings**.
`tools/godot.sh test res://flow/tests/test_flow.gd -- --sandbox --flow --spawn=0,1,60` → **240 checks,
0 failed** (194 at the start of the round). `test_flow_idle.gd` → 8 checks, 0 failed.
`tools/godot.sh test res://enemies/boss/tests/test_boss.gd` → **135 checks, 0 failed**.
`…/test_boss_city.gd` → **20 checks, 0 failed**.

### B2 (r16 conflict map) — `_restore_player`, posted for mech-move

**This is the committed version, as of `409f6a9`, `game/flow/flow_progress.gd:285-297`.** mech-move's
test should mirror this, not a working copy.

```gdscript
func _restore_player(at: Transform3D) -> void:
	var player := Game.player
	if player == null:
		return
	player.set(&"velocity", Vector3.ZERO)
	player.global_transform = Transform3D(at.basis.orthonormalized(), at.origin)
	player.set(&"hp", player.get(&"hp_max"))
	player.call(&"heal", float(player.get(&"hp_max")))
	player.call(&"add_energy", float(player.get(&"energy_max")))
	player.call(&"invulnerable_for", RESPAWN_GRACE)
	var rig := Game.camera_rig
	if rig != null and is_instance_valid(rig) and rig.has_method(&"snap_to_player"):
		rig.call(&"snap_to_player")
```

`set("hp")` **then** `heal()` stays a full revive — that pair is what releases `_revive()` in
`player_mech.gd:357-372`, and I have not changed it. What r5 added is the two lines around it:
`global_transform` (was `global_position`) so the checkpoint's facing is restored, and
`snap_to_player()` so the rig does not ease across the city for 1.5 s after RETRY. Both are outside
mech-move's predicate. **Any later change to this function will be posted here again.**

### 1 — a death before the district opens (`d670a58`)

The only `&"start"` save was in `_enter_district`, so a death in the Container Yard — a real fight,
two ripper waves and a mantis — closed the GAME_OVER page and did nothing else: HP 0, no HUD,
`game_over` for good, and `take_hit` ignores an HP-0 hero so the page could never come back.

* `_enter_tutorial` writes SPEC §7.1's start checkpoint (resume state `tutorial`) as the tutorial
  starts; `_enter_district` still overwrites it with the district state.
* `_on_respawned` resumes a `tutorial` checkpoint **as the tutorial** (`maxi(..., S.TUTORIAL)`, was
  `S.DISTRICT`) — the old clamp meant `arena_cleared` was ignored for ever after a yard death.
  `FlowTutorialDirector.resume()` re-teaches only the verbs this run has not shown yet, because
  brief §4 says every verb is taught once.
* `FlowProgress.respawn(fallback_at, fallback_state)` can no longer be refused: with no checkpoint it
  `push_error`s and restarts at the drop-in landing.
* `_restore_player` applies the checkpoint's whole transform and calls `camera_rig.snap_to_player()`.

**Gate:** `suite_states._tutorial_death` — die in the yard, RETRY, be back in `tutorial` with full
HP/EN, i-frames, the camera snapped, then clear A1 and reach `district`. **21 checks fail on HEAD**
(including the whole downstream run, which never recovers), 0 after.

### 6 — a respawn no longer re-arms cleared arenas (`273d643`)

`respawn()` called `reset_arena()` on every arena and `FlowCheckpoint` stored only `spires_down`.
Both district checkpoints are written *inside* the arena just won, so the respawn teleport crossed the
zone edge and `_on_arena_entered` restarted wave 1 within 0.3 s.

* `FlowCheckpoint.arenas_done` through `make` / `to_dict` / `from_dict`.
* `respawn()` keeps those, plus the arena of every hive in `spires_down`, done and empty
  (`EncounterDirector.keep_arena_done`, which never announces a clear); only the rest rewind.
* The "every arena restarts" claim is gone from the `respawn` doc comment — no spec or brief asked
  for it.

**Gate:** `suite_states` clears the yard, resets the arena so the hive checkpoint records none, dies
elsewhere and respawns: the fallen hive's arena is done, idle and empty, and stays quiet for 4 s.
**2 checks fail on HEAD**, 0 after.

### 5 — out of the world, and PAUSE → ABORT (`f39b168`)

* **New `game/flow/flow_bounds.gd` (`FlowBounds`).** The open U4/U5/U6 tunnel ends drop the mech to
  −3,000 m and nothing noticed. `reason(player)` answers "" or a readable string: the feet below
  −120 m (the lowest floor in the city is the −40 tunnel deck) or past `bounds.half` from
  `world/city/layout.json`, with the margin in the text. `GameFlow._check_bounds()` runs every physics
  tick outside the title, the scripted drop-in, the boss fight (the Crown has its own catch) and the
  victory beat, and answers with the same respawn RETRY uses. `FlowBounds.half_height` is cached
  against the hero, because this is 120 Hz.
* **`FlowGameFlow.abort_to_title()`.** ABORT emitted `quit_game`, which had no listener, so the page
  stayed up and the tree stayed paused. Now: unpause, close the page, `FlowProgress.reset_run()`
  (spires stand, 0/3, no checkpoint, arenas re-armed), `BossDirector.abort_fight()` if a fight is on,
  and the title. Wired to hud r6's `abort_to_title`; **until that signal lands** flow also answers
  `quit_game`, and only while `page == PAUSE` *and* the tree is paused, so QUIT elsewhere still quits
  the app (lead r16 decision 3).

**Gate:** `suite_states._fall_out` (teleport to −200, respawn within a few ticks, full HP/EN, right
state; height alone and standing near the edge are not out of the world, past the bounds is) and
`suite_states._abort` (title, unpaused, 0/3, no checkpoint, spires whole, arenas re-armed).
**8 checks fail on HEAD**, 0 after.

### 2 — BOSS starts on a real touchdown (`409f6a9`)

* **New `game/flow/crown_deck.gd` (`FlowCrownDeck`).** `crown_gate.tick()` fired on
  `y >= 224 and is_grounded()`; the S4 arc crosses deck tiles, so the capsule reads a floor for 44 of
  the flight's frames and the gate fired mid-air at (0.76, 225.11, −190.33). `touched_down()` is the
  probed answer: not in the catapult's LOCKED flight, the feet on WORLD within 3 m, and no collider
  overlapping the capsule.
* **Probed checkpoints.** All three boss phases save `FlowCrownDeck.fight_point()` through the new
  `FlowProgress.save_at()` — a point on the fighting floor, a capsule's half height up, faced at the
  Crown centre. `boss_p2` used to save 145 m away, wherever the hero stood.
* **Placement (lead r16 decisions 1 and 2).** The pad drops the spawn zone's 20 m lift, so it stands
  ON the S4 ring at y 160 instead of floating inside a Crown rib at 180. The landing is the probed
  fighting-floor point on the S4 side (r 65, clear of the Ø80 core), not the `B1` zone box centre.
  The arc is a Catmull-Rom through four points — pad, a gate out past the r 150 rim and under the
  deck's underside, an apex above the fins, the landing — so it never crosses the Crown deck.
* The pad re-arms (`monitoring = true` in `_end_flight`) and the `HINT` is cleared when the fight
  starts and on a boss respawn.

**Gate:** `suite_catapult._arc_clears_the_deck` (121 samples, 0 crossings, against the deck's own
numbers with the 15 m capsule), `_no_crown_mid_flight` (the gate stays shut in the air over the deck
and opens exactly once on a real touchdown), `suite_states._boss` (`boss_p1`, `boss_p2` and the RETRY
all stand on the probed point; no `CATAPULT` in the objective line). **6 checks fail on HEAD**, 0 after.

### 3 and 4 — the titan and the boss respawn (`5129b4c`)

Fully written up, with the per-tick numbers, in **`status/boss.md` → "2026-11-05 — flow r5 items 3 and
4"**. In one line each: the `AddSpawner` is a sibling of the titan, its `platform_floor_layers` drops
the ENEMY bit, summon points step 45 m clear of its body and `_stay_on_the_deck` bounds the height
(20 summons: **149.5 m → 0.13 m** in one tick); and `BossDirector` no longer listens to
`Events.player_died` at all — the restore is `restore_for_phase(phase)`, the duck-typed hook
`FlowProgress.respawn` calls.

## Done — r5 pass 2 (lead brief `reviews/flow-r5.md`, items 7, 8 and 9)

| # | commit | what |
|---|---|---|
| 7 | `509efc4`, `3ec8915` | the pods come out of the collision hull; the bot fires the shot it judges |
| 8 | `3043ffd`, `48758cb` | a `shot` blocks until it is saved; the report flags duplicates and empty frames; the collapse is filmed |
| 9 | `3043ffd` | the flow-cost gate can fail; SPEC §8.1's title shot |

### 7 — three of every hive's four pods sat inside its own hull

`HiveCollision` is a convex hull of a concave, spined trunk and stands 4–17 m outside the mesh the
player sees along the pod bearings, while the pods are solved 1 m inside the skin. A one-hit shot — a
rifle tap, a gatling round — stopped on invisible air, so **3,500 of the hive's 20,000 HP was
reachable** and the E2E bot never fired at a hive at all.

* **`FlowHiveSurface.skin_shape()`** is flow's own collision: the visible skin decimated by vertex
  clustering at a 1.2 m lattice, **60,000 → 12,377 triangles** (`HIVECOLL trunk shot collision: 12377
  triangles (the skin is 60000)`), two-sided so the GLB's winding cannot let a shot through.
  monster-assets r5 does not carry the shrink-wrapped `HiveCollision` this asked for (flow request 4),
  so flow builds its own.
* **The trunk is its own `StaticBody3D` with no `take_hit`.** `ShotQuery.deliver` treats any collider
  that answers `take_hit` as a receiver and emits `hit_landed` plus a hit marker even when
  `final_amount` comes back 0, so leaving the collision on the spire node drew a white X and a "230"
  on every trunk tap while the HP did not move. The weak points are Hurtboxes and still route to the
  spire. **This is flow's half of the 0-damage-hit request; weapons/hud own the other half.**
* **The bot judges the line by the shot it fires.** `FlowAssaultTargets.lands_on()` is
  `ShotQuery.ray_hits` from the `muzzle_r` socket, `MASK_PLAYER_ATTACK`, areas on, and the TAP's real
  `max_hits` — along `WeaponContext.aim_dir_from(muzzle)`, the direction that points at the
  **crosshair**. Three separate defects were in the way of that: the old test was a `MASK_SIGHT` ray
  to the target's CENTRE (which the target's own body always blocks, 0 of 576 ring lines); the first
  fix cast from the LENS, 42 m from the muzzle and behind a different set of walls; and a ray aimed at
  the centre was clear while the real shot, 6 m off at 90 m, grazed past a 6.07 m hurtbox. Target
  *picking* still aims at the centre (`stand_lands_on`) — there is no crosshair at a candidate stand.
* **The bot taps** (0.08 s of hold, was 0.65 s of charge). A tap is `max_hits` 1, which is the
  player-facing gate; a bot that proves the fight with charges would hide exactly this defect.
* The aim cone tightened with it: **4° is exactly a 6.07 m hurtbox's angular radius at 90 m**, so the
  bot was firing at the edge of its own target. 2.0°, and the crosshair tolerance 30 m → 12 m.
* The firing ring reaches in to 40 m and up to 55 m as well, because at A2 the Interchange Knot blocks
  every line from the old 70/100/140 m ring.

**Gates.** `suite_spires._pods_are_the_first_hit` casts `MASK_PLAYER_ATTACK` with areas and bodies
and **nothing excluded**, and wants the pod's Hurtbox FIRST — the old probe masked `ENEMY_HURTBOX`
only and excluded the spire's own RID, so it could never see the hull that was burying them:

```
HEAD:  TEST FAIL every pod's Hurtbox is the FIRST collider a one-hit shot meets from the open side: got 1, want 4
after: TEST 247 checks, 0 failed, 0 skipped
```

`assault_city` in the city, real weapons, no fallback — **the gate the brief asks for
(`assault_city` ends `spires=1`, 0 today)**:

```
E2EWEAPONS spires=1 bot_kills=1 debug_fallbacks=0 [] scripted_clears=1 [&"A1"]
DRIVE done t=150.1 errors=2      (both hero-v3's hero3_glow shader, not flow's)
```

### 8 — captures that show their beat, and the collapse on film

* **A `shot` is a BLOCK.** It waits until the .jpg is on disk, so the next beat cannot run in the same
  tick. The old fixed 0.9 s hold let the script walk on while the capture was still waiting for the
  rig, which is how `e_spire0_collapse` and `f_game_over` came out byte-identical and
  `k_spire2_collapse` == `l_boss_gate_vista` == `m_catapult_pad`. `_settle` also stops waiting for the
  follow spring while a cinematic owns the lens (`camera_rig.is_cinematic()`), where that wait never
  succeeded and just burned 2.5 s a beat.
* **The report says what the frames are**, not only that the lens was not inside a wall:
  `E2ECAMREPORT DUPLICATE a == b` for byte-identical frames (md5 of the saved file) and
  `E2ECAMREPORT NO-SUBJECT x` for a frame with neither the hero nor a lock point in the frustum, plus
  a `distinct=/duplicates=/no_subject=` tally.
* **`film_collapse [spire, frames, gap]`** films a hive's collapse for the trailer: 8 frames 0.25 s
  apart through the real `FlowHiveCollapse`, by `kill_spire` or by a real kill (the same code path).

**Gates.** `e2e_city` — **17 distinct md5s**, the brief's number:

```
E2ECAMREPORT captures=17 clean=16 buried=1 won=true
E2ECAMREPORT distinct=17 duplicates=0 no_subject=1
E2ECAMREPORT NO-SUBJECT h_spire1_pods (neither the hero nor a target is in frame)
```

The one `NO-SUBJECT` is the new check catching a real defect the acceptance found by hand: the A5
pods frame does not contain the hive. `m_catapult_pad` is `lifted` — the lens was inside the
catapult's beam column and the retry lifted the mech out, which is the mechanism working.

The collapse, all three hives, 24 frames:

```
E2ECAMREPORT captures=24 clean=24 buried=0
E2ECAMREPORT distinct=24 duplicates=0 no_subject=0
E2EWEAPONS spires=3 bot_kills=0 debug_fallbacks=3 [hive_a2, hive_a5, hive_a6]
```

Contact sheets (8 frames, 0.25 s apart, for the trailer): `tmp/flow/r5/sheets/hive_a{2,5,6}_collapse_sheet.jpg`.
A6's eight frames read as: the intact spire on the Sky Garden deck with the mech small at its base →
the base blast and the acid ring → the fireball climbing the trunk → the crown blast → the topple →
the hand-back with the wreck on the ground. **Three faults had to be fixed to get that** (commit
`48758cb`): the duel-frame offset put the lens ~150 m out; the shot was built from the rig's stale
hard target; and `destroyed` was emitted *after* the collapse node started, so on the third spire the
boss gate's 300 m vista cinematic was requested last and won.

### 9 — a perf gate that can fail, and SPEC §8.1's title

* **The gate could not fail.** Both arms averaged `Performance.TIME_PROCESS` over 120 frames, and
  those monitors refresh about once a wall second, so both arms read the same stale number and the
  answer was always "flow costs 0.000 ms". It now measures **wall time over 2 s per arm** in three
  arms — flow on, flow held, and flow on with a 2 ms busy-loop inside its own physics tick
  (`FlowGameFlow.perf_busy_ms`, a test seam that is 0 in every other run). The busy arm is the proof:

```
PERF pair 1: flow 2.122 / held 2.109 / busy 4.304 ms per frame
PERF pair 2: flow 2.161 / held 2.272 / busy 4.207 ms per frame
PERF flow costs 0.013 ms per frame (2.122 with, 2.109 held); the busy arm reads 2.099 ms
PERF the busy arm moved the measurement by 2.099 ms, so the gate can fail
TEST 2 checks, 0 failed
```

  The arms differ, a 2 ms cost is visible as 2.099 ms, and flow's real cost is **0.013 ms** — the
  lead's ceiling is 1 ms. (The run's `EXIT=1` is the strict test host counting two engine errors from
  hero-v3's `hero3_glow` shader; flow's own two checks pass.)

* **The title shot.** SPEC §8.1: "Title (hero on a lit hangar platform, skyline behind)". The lens was
  110 m out and 30 m up at 62° with the mech parked at the landing in the dark — a dim container yard
  with a speck behind the logo. It now stands 45 m off the Insertion Pier at chest height, aims just
  past the mech's shoulder so the logo does not sit on it, and looks along world −Z, which from H0 is
  straight at the Spire and the skyline. Two unshadowed omni lights, a warm key on the camera side
  (energy 26, range 55, 13 m from the mech) and a cool rim from behind, both gone the moment the
  drop-in starts.

  `captures/r5_title_t4_0.jpg` / `_t9_0.jpg` (`tools/godot.sh drive
  --timeline=res://flow/tests/title_menu.json --shots=4,9 --nan-watch --out=r5_title`, `errors=0`):
  the mech spans roughly **half the frame height** (the gate is ≥ 10 %), its plates read individually,
  the rim separates it from the dusk and the pad has a warm pool on it. What it is **not** is bright:
  the title runs at night and the overall value is city-art's (the acceptance routed it to city-art
  r15), so a title key light is request 6 below.

## In progress / next — the r5 round

All nine r5 items and all three r5b items are implemented and evidenced above. What is left:

1. **`e2e_city` with `bot_kills=3 debug_fallbacks=0`.** The bot now kills hives with real taps
   (`assault_city` ends `spires=1 bot_kills=1 debug_fallbacks=0`, and in the `e2e_city` run A5 fell to
   the bot outright), but A2 and A6 still run out of window: A2 reached 1,870 of 7,000 HP in 50 s and
   A6 4,550 → frozen, both before the aim/muzzle fixes landed. The per-spire windows are now 130/140 s.
   r5b item 1 (`ccd8f19`) removes the two livelocks that were eating those windows — a firing stand
   5.5 m inside the floor it found, and a stand on another level of the city entirely. Whether that is
   enough is a windowed question: **capture 4** under "Captures needed". **If it still falls back, the
   honest statement is "two of three hives fall to the real kit in a scripted run", not a pass.**
2. **The checkpoint matrix's respawn frames** are captured (`captures/e2e_cp*.jpg`, 21 distinct) and
   the log table is in Evidence; two frames come back `lifted` (the lens was in a pocket and the retry
   lifted the mech), which is the mechanism working, not a defect.
3. **Re-run the S4 step gate** after city-build's rib-notch commit lands (r16 conflict E4): the
   catapult's outward leg runs along the S4 axis, which is where Crown rib j=2 is. Until then the arc
   is verified geometrically (`suite_catapult._arc_clears_the_deck`, 121 samples, 0 crossings) and by
   the matrix's real launch (`FLOWPROBE ... at=-3,301,-296` — the apex at r 175 from the Spire axis —
   then `state=boss` on the fighting floor at `0,249,-185`).
4. **Re-run the E2E** if city-layout moves a hive (r16 conflict E7). city-layout r6 already moved the
   three sites onto open ground and this round's runs are all on that layout. The r5b collapse gate
   reads the sites from the world's own `&"hive_site"` markers, so it follows the layout by itself.
5. `brood_titan.gd:282-283` still plays `kill_large` on the boss death. feel r5 owns the one-line
   switch to `boss_kill` when its row lands (lead r16 decision 6) — deliberately left alone.
6. **A2's hive site is enclosed** (new finding, r5b item 2). Only **42 of 1,344** sampled stands round
   it can see the spire, and they are all in a narrow slot on its south side, 80–110 m out. The
   collapse now finds them and films the beat cleanly, but this is also why the E2E bot struggles to
   find a firing position at A2 — see Request 8.


## Scope
`game/flow/**`, `game/flow/tests/**`, `game/flow/encounters/**` — GameFlow state machine,
EncounterDirector, Hive Spire objective, checkpoints/respawn, drop-in, victory, tutorial prompts, and
the scripted E2E harness that proves them.

## Done — `flow_debug_assault.gd` split (lead brief `reviews/flow-split-r1.md`)

`game/flow/flow_debug_assault.gd` was 624 lines, over the project's 600-line limit. It is now 182,
split along the responsibilities it already had, in one commit (`7a34e83`) with an explicit path list:

| file | lines | what it owns |
|---|---|---|
| `flow_debug_assault.gd` | 182 | the beat: what the bot is here to kill, when it looks up, when it lets go |
| `flow_assault_targets.gd` | 228 | the beat's lock points, line of sight, the ring of firing stands, blind spots |
| `flow_assault_aim.gd` | 215 | pointing the rig by hand, the aim cone/crosshair measures, trigger, reload, skills |
| `flow_assault_move.gd` | 100 | the three moves: orbit the trunk, stand off the titan, perch over a pack |
| `flow_assault_log.gd` | 48 | the `E2EBOT` heartbeat and the `E2EAIM` gain/lose line |

Callers are untouched — `flow_debug.gd` still uses `start_spire` / `start_arena` / `start_boss`,
`tick`, `tick_trigger`, `stop` and nothing else, and `flow_debug.gd` itself is not in the commit. The
only code change is the removal of `CHASE_RANGE`, which was declared and never read.

### Behaviour-identical: the evidence

* **`tools/godot.sh test res://flow/tests/test_flow.gd -- --sandbox --flow --spawn=0,1,60`**
  → **194 checks, 0 failed** before the split and **194 checks, 0 failed** after. Same number.
  `test_flow_idle.gd` → 8 checks, 0 failed.
* **`tools/godot.sh check --only=res://flow/`** → 39 files / 0 failed before, **43 files, 0 failed,
  0 engine errors, 0 warnings** after (the four new files). Whole project: **667 files, 0 failed,
  0 errors, 0 warnings**.
* **A scripted assault run, before and after** — the new fixture
  `game/flow/tests/assault_city.json` (its own commit, `5634a79`): a 150 s city run that fights the
  A1 arena with the real rifle and then assaults hive 2, so every part of the split file is on the
  path. Run three times — once on the old build, twice on the new one:

  ```
  tools/godot.sh drive --timeline=res://flow/tests/assault_city_drive.json --skip-menu --god \
    --nan-watch --spire-hp-scale=0.05 --flow-script=res://flow/tests/assault_city.json --out=flowsplit
  ```

  | | before | after #1 | after #2 |
  |---|---|---|---|
  | `FLOWDBG` command sequence | — | **byte-identical to before** | **byte-identical to before** |
  | `E2EBOT` / `E2EAIM` / `E2ESPOT` / `E2EPHASE` / `E2EWEAPONS` | 22 / 1 / 1 / 1 / 1 | 22 / 1 / 1 / 1 / 1 | 22 / 1 / 1 / 1 / 1 |
  | `E2EMOVE` / `E2ECHASE` | 63 / 20 | 62 / 19 | 59 / 16 |
  | `DRIVE done` | `t=150.0 errors=0 warnings=6` | same | same |

  The move counts are the run-to-run noise floor, not a change: the **two runs of the same new
  build differ by more (4 and 3) than the old build differs from either of them (1 and 1)**. That is
  expected — `tick_trigger` is documented as idle-frame driven, so the shot timing, the rippers'
  knockback and the bot's 1.2 s move cooldown all land differently on every run. Logs:
  `tmp/flow/split_{before,after,after2}_assault.log`.

## Done — r4 (lead items 1–5)

### 1. `park_boss_arena` is gone
`crown_gate.gd` is the trigger over the deck and the Ascension Catapult, nothing else:
`park_boss_arena()`, `release()`, `PARK_HZ` and `_parked` are deleted, `tick()` takes no delta, and
`game_flow.gd` no longer calls either. `BossArena.armed` (the boss unit's own gate) is what keeps the
Crown's return catapult out of the district. Covered by `suite_e2e._crown_gate`: a node in group
`&"boss_arena"` with physics on is still processing after two `crown.tick()` calls, and neither method
exists.

### 2. The bot destroys pods and cores with the REAL weapons — and where it still cannot
`FlowDebugAssault` had five separate faults, each found in a run's log and each now fixed:

* **It aimed with the hard lock.** `CameraLock.track` points the *pivot* at the target and then adds
  the CONTRACTS §5 large-target pitch offset (up to +12°) — right for framing a 60 m spire, wrong for
  a 6 m pod: the crosshair sat 1,400 m past the pod and the ray hit nothing. It now steers the rig by
  hand (`set_look` with absolute yaw/pitch in the rig's own convention), measures the angle between
  the aim ray and the target from `aim_origin()`, and fires inside 4°.
* **It measured the shot on the frame it asked for the turn.** The rig applies yaw/pitch in its own
  `_physics_process`, so the bot read the old view, concluded "blind", and teleported for ever.
  Measure-then-correct, four passes before it calls a position blind — and the counter is per
  *position*, not per target (two pods trading places used to reset it for ever).
* **It never reloaded.** The Pierce-Light has no auto-reload: a charged shot that empties the magazine
  leaves `ammo = 0` with `reloading` never set, so the bot fired exactly three rounds (2,100 damage)
  and then stood there. It now taps `reload` on a timer, held for 0.2 s so a physics tick sees it.
* **Its firing-position search tested the muzzle, not the lens.** The shot leaves the camera, 42 m
  behind: every log line said `t2_0 at 5 of 73 m`. `_lens_sees` now tests from the simulated lens,
  requires ground under the candidate (`standable`: an open pocket, nothing overlapping the chest),
  and falls back to a hover only if nothing on the ground works.
* **It held a target that had already died.** A burst pod keeps its lock point and its position and
  only leaves the `targetable` group, so the bot shot a corpse for the rest of the beat. `_keep_or_pick`
  now requires group membership — and keeps the same target while it is legal, because two pods 16°
  apart trading places every pass made the camera oscillate between them for ever.

Result in the city, with real damage through the real path (aim ray → muzzle → Hurtbox → pod burst):
**A2 20,000 → 13,000, A5 20,000 → 6,000, A6 20,000 → 6,000** (all four pods burst) in separate
50-second windows. **CORRECTED (r5 brief item 7):** those numbers are from BEFORE commit `86af948`,
which gave the spire its hull collision and buried three of its four pods inside it. They are not
reproducible on any commit after it, and they were quoted as if they were. The r5 numbers that are
reproducible are in "Done — r5 pass 2" below. What it does *not* do yet is finish a hive unaided inside the window: at A2 and A5
the site stands inside its arena's own structure, so most of the beat goes on finding a position with
a line, not on shooting (city-layout r6 moves them — request 2 below). `finish_spire` stays in the
E2E as the last resort, and now `push_warning`s, counts itself, and is listed by name in the report
(`E2EWEAPONS … debug_fallbacks=N [ids]`), so a run that leans on it can never be mistaken for a pass.

`--spire-hp-scale=` (new, flow's own constant, default 1.0) scales `POD_HP`/`CORE_HP` for scripted
runs; `--boss-hp-scale=` scales the titan's pool and its three cores. Both print what they did.

### 3. The E2E runs through the boss to VICTORY
`assault_boss` + `wait_won` + the victory beats. `res://flow/tests/boss_check.json` (gate → catapult →
Crown → fight → victory) is the fast proof:

```
FLOWDBG --boss-hp-scale=0.020 applied to the titan: 150000 -> 3000 HP, 3 cores
E2EMARK gate t=8.4   state=boss_gate
E2EMARK crown t=10.0 state=boss
FLOWDBG unblock won after 31.8 s
E2EMARK victory t=48.9 state=victory
E2EPHASE gate 1.6 s / crown 4.0 s / boss_fight 34.8 s / victory 0.9 s
E2ECAMREPORT captures=3 clean=3 buried=0 won=true
E2EWEAPONS spires=3 bot_kills=3 debug_fallbacks=0 []
```
**CORRECTED (r5 brief item 7):** that `E2EWEAPONS` line was wrong. `boss_check.json` removes all three
spires with `kill_spire`, and `flow_debug.gd` never counted `kill_spire` as a fallback, so
`bot_kills = spires_down − fallbacks` read 3 for three spires the script had collapsed. `kill_spire`
and `clear_arena` are both counted now (`5aea16b`), and the line reads
`spires=3 bot_kills=0 debug_fallbacks=3 […] scripted_clears=N`.
`captures/e2e_bosscheck_intro.jpg` (BROOD TITAN title card, boss bar PHASE 1, 3/3 HIVES),
`…_shooting.jpg` (the titan on the deck taking hits), `…_victory.jpg` (**任务完成 MISSION COMPLETE**
with TIME / MAX COMBO / KILLS / PARRIES / DODGES / EXECUTIONS and the FINISH row).
The bot's boss chase now stands off at the *titan's* height, not the core's — placing the mech 6 m
over a core 40 m up the beast's chest drops it off the Crown.

### 4. Every capture is checked against the world
`FlowDebugView.camera_state()` takes the camera's real position at the frame being saved, asks whether
a collider overlaps it (`intersect_point`, MASK_SIGHT) and how many of six axis probes reach 14 m. A
buried frame is retried up to three times (the mech is lifted, the rig follows) and then filed as
`buried`; either way the verdict, the position and the collider go into the log and into the report:

```
E2ECAMREPORT g_respawn  lifted at -424,90,0 open=0.67 in -
E2ECAMREPORT captures=16 clean=15 buried=1 won=true
```
The r3 frames that were dark walls are gone because the *stands* changed, not only the check:
`approach_spire` now scores 24 candidates (8 bearings × 3 ranges) on what the LENS would see — trunk,
pods, openness — rejects any with no floor or no line to the trunk, and warns
`no stand round hive_a2 (A2) can see the trunk — the site is enclosed` when the whole ring is blind.
Captures also wait for the rig's follow spring to arrive (a teleport of 300 m leaves the lens crossing
the map for most of a second, which is what put the r3 camera inside a wall).

### 5. Movies, re-recorded
Two recordings, because one run does not fit the tools' slots (see Known issues):

| file | what | size |
|---|---|---|
| `captures/e2e_city.mp4` | drop-in → tutorial → district → three hives → die/respawn → boss gate → catapult → Crown | 1600×900, 13,909 frames, 231.8 s, 151 MB |
| `captures/e2e_boss.mp4` | boss gate → catapult → Crown → the titan → the victory screen | 1600×900, 44.7 s, 24 MB |

Both recorded with `--nan-watch` and the scripts above. The district run's own log:
`E2ECAMREPORT captures=15 clean=12 buried=3` — the three "lifted" ones are the beats where the lens
passed through the Ascension Catapult's beam on the way up (its column has a collider), the retry
lifted the mech and the frame is clean; nothing was filmed inside a wall.

Frame times per phase, from the same run driven without the recorder (`--frametimes`, so these are
real frame times and not the recorder's fixed step):

| phase | game s | p50 ms | p95 ms | p99 ms |
|---|---|---|---|---|
| drop_in | 6.4 | 17.0 | 17.0 | 17.0 |
| tutorial (A1) | 29.6 | 34.0 | 71.0 | 72.0 |
| spire_0 (A2) | 51.9 | 67.0 | 71.0 | 73.0 |
| checkpoint (die + respawn) | 1.8 | 66.0 | 72.0 | 73.0 |
| spire_1 (A5) | 51.8 | 33.0 | 67.0 | 71.0 |
| spire_2 (A6) | 56.9 | 34.0 | 59.0 | 69.0 |
| boss_gate → catapult → crown | 2.7 | 28.0 | 48.0 | 71.0 |
| boss fight | 52.7 | 39.0 | 71.0 | 73.0 |
| whole run (257 s) | 256.7 | 35.0 | 70.0 | 72.0 |

That is the shared box with other units' captures and an ffmpeg encode running; flow's own share of
the frame is measured separately and is **0.000 ms of process and 0.000 ms of physics**
(`test_flow_perf.gd`, three interleaved A/B pairs, flow held and handed back through
`FlowGameFlow.set_frame_work(false)`).

## Done — look/flow.md item 1 (the four floating lime discs)

`reviews/look/flow.md` item 1, the only item routed to flow: four flat 9 m spheres floated in the air
beside the hive because `hive_visual` pushed every pod out to a guessed 13.2 m trunk radius, and the
spire collided with that same guess, so shots stopped on invisible air.

**Where the pods are now.** `game/flow/hive_surface.gd` (new, `FlowHiveSurface`) reads both of the
GLB's shells — the 60,000-face `Hive` the player sees and the 164-face `HiveCollision` — flattens them
into the visual's local space, and solves each weak point by casting a segment from 260 m out along
the socket's bearing back to the axis, taking the first face it crosses and stepping 1 m inside it.

The two shells are **not** the same shape, which is the thing the review's suggested fix gets wrong:
solving against the collision hull buries the pods. Measured on the shipped hive at the four pod
heights, skin vs hull radius along the same bearing:

| pod height | 54.5 m | 40.5 m | 24.0 m | 10.3 m |
|---|---|---|---|---|
| visible skin | 1.8 m | 3.8 m | 5.4 m | 7.0 m |
| collision hull | 4.4 m | 9.4 m | 17.8 m | 23.2 m |

The hive is a wide root mass under a thin spined crown, and the hull overshoots it by 2–16 m along
those bearings. So: **skin for placement, hull for collision.** A pod solved on the hull at 45°,
y = 54.3 landed at r = 4.5 m while the visible surface there is at r = 1.8 m — the cluster would have
been a lump inside the trunk. `test_flow.gd` measures the gap from each pod to the 60,000-face skin
and holds it under 5 m (measured: 3.5 / 1.9 / 0.9 / 0.7).

**The spire collides with the hull.** `FlowHiveSpire._build` uses `_visual.hull_shape()` — a
`ConcavePolygonShape3D` of those 164 triangles — instead of the 13.2 m cylinder. The stand-in
(no model) still gets a cylinder, sized from `hull_radius(y)`.

**The core moved too.** It sat on the axis at `(0, 31.2, 0)`, which is inside the hull, so with the
hull as collision no shot could ever reach it and the fight could not be finished. It is now on the
chest face (`chest` socket bearing) at the core socket's height.

**What the pods look like.** `game/flow/hive_pods.gd` + `game/flow/hive_pod.gdshader`, new. One pod is
a cluster of 3–5 sacs (seeded, so a spire looks the same every run), each a 32×16 sphere ~4 m across,
squashed along the trunk normal and sunk 28 % of its radius back into the shell — never a single
sphere. All the sacs of one cluster are merged into **one** ArrayMesh through `SurfaceTool`, so a
spire costs five weak-point draw calls and a burst is still one `visible = false`. The material is a
ShaderMaterial with a fresnel membrane, a dark chitin rim and an acid core at `core_energy = 1.45`
(the review's ceiling is 1.5); ALBEDO, EMISSION, ALPHA and ROUGHNESS are all driven off
`dot(NORMAL, VIEW)`, so the silhouette stays dark against the dusk instead of blooming into a lime
blob. The breathing moved from a 12 Hz `StandardMaterial3D` write per spire into the shader's `TIME`
with a per-cluster `phase` — `_process` and both pulse writes are gone.

**The burst.** `hive_spire._acid_burst` fires along the pod's surface normal: `spark_burst` +
`steam` + a green `FxBridge.flash` + a 12 m ring + a `scorch` decal stamped on the trunk at 2.4× and
tinted acid. `_visual.burst_pod` puts the cluster out, calls the model's per-pod glow off
(`set_pod_alive(index, alive)` — monster-assets landed exactly that signature) and rings the trunk:
`_physics_process` decays a 0.55 s wobble on the model node, and `restore_pod` puts both back on a
checkpoint respawn.

## Done — two harness faults the look work uncovered

**The stand scorer could not see any spire.** `approach_spire` reported "no stand round hive_a6 (A6)
can see the trunk — the site is enclosed" for **every** hive and fell back to holding the spawn, with
`0 of 40 candidates had no floor` — so the sites were not enclosed at all. The sight-line test aimed
at `spire.global_position + UP * height * 0.45`, the trunk's *axis*, which is inside the spire's own
collision: the ray always stopped on the trunk and every candidate scored zero. It now aims at
`_aim_point` — the same mid-height point pushed 22 m out along the bearing the candidate stands on.
The search also reaches in to 50 m, because A6 is a Sky Garden deck at +144 and at 90 m out every
bearing is a 144 m drop.

**The camera aimed from where it used to be.** `approach_spire` teleports the mech and then calls
`look_at`, but the rig follows on a spring — in that frame the lens is still hundreds of metres away,
so the pitch came out of a stale vector and the capture framed the sky above a hive 35 m below the
crosshair. `FlowDebugView.aim_from(from, want)` takes the lens position the caller knows it is going
to have; `look_at` is now a thin wrapper over it.

## Done — flow-look-r1 polish (the exposed core is a ruptured boil, not a sticker)

`reviews/flow-look-r1.md` PASSed look item 1 and left two polish items. Both are done.

### Polish 1 — the core reads as the hive's heart

**`game/flow/hive_core.gd` (new, `FlowHiveCore`)** replaces the one flat violet ellipse. The boil is
four pieces, all of them merged so a spire still costs a handful of draw calls:

* **Collar** — 24 torn flaps round the lip plus 14 loose plates just outside it, one `ArrayMesh` with
  vertex-coloured chitin (near-black at the root, a drier grey at the tip). Each flap is wide where it
  is still attached and tapers to a jagged point, and leans a random amount either way: some curl back
  over the cavity and throw it into shadow, some fold away from it. That mix is what makes the lip read
  as torn; a constant-width quad read as a paper card.
* **Cavity** — a dished fan, 22 segments, near-black with a violet ember at its centre and **no
  emission of its own**. A uniform violet emission across the dish is exactly the flat lilac sticker the
  review flagged; what light the cavity gets comes from the lamp in front of it, so it has real falloff
  into its corners.
* **Sacs** — the pod cluster (`FlowHivePods`), packed at 0.45 × the opening and pushed out of the shell,
  so four bulbs bulge through the wound instead of one sphere covering it. They carry the pod membrane
  shader with `mottle_scale` 16 (the pods' 6 cells across a sac is a flat wash at 70 m).
* **Glow** — an `OmniLight3D`, `radius * 3.0` range, **shadow off**, sitting *in front* of the sacs.
  A lamp buried inside a translucent sac lights it from within and the whole cluster blows out to
  white — that was the first thing the A/B caught.

**The heartbeat is real and measured.** `hive_pod.gdshader` grew `pulse_lo` / `pulse_hi` / `pulse_hz`;
a pod keeps the slow swell it always had (0.56 → 1.0 at 0.33 Hz, the defaults), the core asks for the
review's **0.6 → 1.4 at 1.2 Hz**. The core's `core_energy` is 0.9, so the *peak* emission is
0.9 × 1.4 = **1.26**, under the review's 1.5 ceiling — the first pass used the pods' 1.45 base and
peaked at 2.03. The lamp breathes on the same band. `_process` only runs while the shell is open, so a
sealed or destroyed spire costs nothing and leaves no violet lamp burning on the wreck.

**The whole boil sits in FRONT of the trunk.** The trunk's mesh is opaque, so a cavity modelled behind
the surface is simply invisible. `_shell_y(r)` is where the shell actually is `r` metres out along the
tangent plane (second order, `r²/2ρ`), `_floor_y(r)` dishes the cavity up from `CLEAR` at its centre to
`CLEAR + 0.30 R` at the lip, and every collar vertex is laid on that surface plus its own height.
`FlowHiveCore.clearance(v)` measures it and `suite_spires._core_look` asserts no collar or cavity vertex
is behind the shell.

**Three placement faults the A/B caught, each fixed at the cause:**

1. **The boil hung off the side of the trunk.** The core's outward direction was the *face normal* of
   the skin triangle the solve landed on — and along the chest bearing at the core's height that is a
   rib, whose face leaned 40° off the bearing (`n = -0.63, 0.26, 0.73`, printed by `--flow-verbose`).
   The core now takes the **bearing itself**, tilted by `FlowHiveSurface.slope()` (dr/dy, so a boil on a
   tapering trunk does not sink in on one side and float on the other). The pods still use the face
   normal — their sockets sit on smooth bulbs, where it is right.
2. **The collar floated metres off the shell.** `FlowHiveSurface.curvature()` measured across 0.26 rad
   lands inside one rib and answered 0.1 m on a 60 m hive; it is now measured across the **collar's own
   angular width** (`opening / trunk radius`, capped at 1.1 rad) so it averages the trunk instead, and
   floored at the opening itself.
3. **The loose plates hung in the air.** Their `lean` of 0.55 put their tips at 1.8 R — past the
   silhouette of a trunk only ~7 m across at that height. Ring pulled to 1.02 R, lean to 0.16.

**The A/B is one run from one stand.** `approach_spire` *searches* for a stand, so two runs frame the
hive from two different places; `FlowDebugView.core_stand` (new `core_stand` debug command) pins the
stand `distance` metres out along the core's own normal at the core's height. And `--core-legacy`
(`FlowHiveVisual.LEGACY_CORE_FLAG`) builds the pre-polish core — one flat cluster, no wound, no lamp —
so **before and after come out of the same build, the same stand and the same lighting**:

```
tools/godot.sh drive --timeline=res://flow/tests/core_ab_drive.json --skip-menu --god \
  --core-legacy --flow-script=res://flow/tests/core_ab.json --out=corelegacy
tools/godot.sh drive --timeline=res://flow/tests/core_ab_drive.json --skip-menu --god \
  --flow-script=res://flow/tests/core_ab.json --out=coreab
```

→ `captures/core_ab_near.jpg`, `captures/core_ab_open.jpg` (side-by-side sheets), and the raw pairs
`captures/core_before_*.jpg` / `core_after_*.jpg`. Both runs: `E2ECAMREPORT captures=3 clean=3
buried=0`, `DRIVE done errors=0`.

### Polish 2 — nothing assumes the old pod socket heights

The sockets moved (pod_0 10.3 → 18.8 m, pod_1 24.0 → 27.8 m). Nothing in flow hard-codes a pod height
and nothing needed changing: `_model_pod_sockets()` reads `pod_*` off the rig every build, the burst VFX
fire from the pod node's own `global_position` along `pod_normal(index)`, and the E2E's stand scorer
scores against `spire.pod_world_positions()` and `spire.height * 0.45` (the trunk's mid-height, not a
pod). Verified by grep and by the new test.

`suite_spires._pod_sockets` now **pins the contract instead of the numbers**: it reads the four
`pod_*` markers off the model's `weak_points()`, and asserts every pod sits at its own socket's height
(worst 0.00 m) and that the four are spread over more than 30 % of the trunk. Move a socket again and
the suite still passes; stop reading the sockets and it fails.

## In progress / next
- city-layout r6 moves the A2/A5 hive sites onto open ground; then the same E2E should destroy all
  three hives unaided and `debug_fallbacks` should read 0.
- The bot's rate of fire is the other half of it: one charged shot per ~1.1 s plus repositioning, so a
  20,000 HP hive is ~2.5 minutes of scripted time however good the sight lines are.
- Nothing else open from `reviews/flow-look-r1.md`: polish 1 and polish 2 are both done and evidenced
  above.


## How to verify (exact commands)

Every drive below passes `--stub=traversal` (r16 conflict E5: the traversal runtime is not in
`main.gd`'s PARTS yet, and the flag is a no-op until it is).

```
# the suites
tools/godot.sh check
tools/godot.sh test res://flow/tests/test_flow.gd       -- --sandbox --flow --spawn=0,1,60
tools/godot.sh test res://flow/tests/test_flow_idle.gd  -- --sandbox --spawn=0,1,60
tools/godot.sh test res://flow/tests/test_flow_perf.gd  -- \
  --skip-menu --no-enemies --stub=traversal --spawn=-514.5,112,105.1,-66.4 --timeout=600
tools/godot.sh test res://enemies/boss/tests/test_boss.gd
tools/godot.sh test res://enemies/boss/tests/test_boss_city.gd

# the real-path checkpoint matrix: nine checkpoints, lethal hits through PlayerMech.take_hit,
# RETRY as a real ui_accept on the page, no --god
tools/godot.sh drive --skip-menu --nan-watch --stub=traversal \
  --timeline=res://flow/tests/cp_matrix_drive.json \
  --flow-script=res://flow/tests/cp_matrix.json --out=cp_matrix --timeout=3600

# the bot on one hive with the real rifle and no fallback (~8 min of wall time)
tools/godot.sh drive --timeline=res://flow/tests/assault_city_drive.json --skip-menu --god \
  --stub=traversal --nan-watch --spire-hp-scale=0.05 \
  --flow-script=res://flow/tests/assault_city.json --out=r5_assault --timeout=2400

# the district E2E, log + captures (needs up to ~1950 s of script; --timeout= is the slot's)
tools/godot.sh drive --timeline=res://flow/tests/e2e_city_drive.json --skip-menu --god \
  --stub=traversal --nan-watch --spire-hp-scale=0.35 --boss-hp-scale=0.02 \
  --flow-script=res://flow/tests/e2e_city.json --out=e2e_city --timeout=3600

# the hive collapse on film, 8 frames 0.25 s apart at each of the three hives
tools/godot.sh drive --skip-menu --nan-watch --stub=traversal \
  --timeline=res://flow/tests/collapse_film_drive.json \
  --flow-script=res://flow/tests/collapse_film.json --out=collapse --timeout=2400

# SPEC §8.1's title shot
tools/godot.sh drive --timeline=res://flow/tests/title_menu.json --shots=4,9 --nan-watch \
  --stub=traversal --out=r5_title --timeout=900

# the boss → victory proof, about 3 minutes of wall time
tools/godot.sh drive --timeline=res://flow/tests/boss_check_drive.json --skip-menu --god \
  --stub=traversal --nan-watch --boss-hp-scale=0.02 \
  --flow-script=res://flow/tests/boss_check.json --out=bosscheck --timeout=2400

# the look evidence (unchanged from r4)
tools/godot.sh drive --timeline=res://flow/tests/look_check_drive.json --skip-menu --god \
  --nan-watch --flow-script=res://flow/tests/look_check.json --out=lookflow
```

## Evidence — r5

**The checkpoint matrix, one real-path run** (`cp_matrix.json`, no `--god`, every death a
`PlayerMech.take_hit`, every RETRY a real `ui_accept` on the page). `FLOWPROBE` prints state, HP/EN,
the lens distance from the hero, the menus page and `hud_state().alive`:

| # | beat | died | respawned |
|---|---|---|---|
| 1 | tutorial start (A1) | `game_over hp=0 page=5 alive=false at=-375,8,420` | `tutorial hp=10000/10000 cam=47m page=0 alive=true at=-560,8,600` |
| 2 | district start | `game_over hp=0 page=5 alive=false at=-560,8,600` | `district hp=10000/10000 cam=47m page=0 alive=true at=-560,8,600` |
| 3 | spire 0 (A2) | — | `district hp=10000/10000 cam=47m page=0 alive=true at=-482,88,143` |
| 4 | spire 1 (A5) | — | `district hp=10000/10000 cam=47m page=0 alive=true at=426,88,159` |
| 5 | spire 2 (A6) → boss gate | — | `boss_gate hp=10000/10000 cam=47m page=0 alive=true at=-38,152,393` |
| 6 | fall out of the world | `FLOW out of the world: feet at -208 m, 88 m below the -120 m floor — respawning at the last checkpoint` | `boss_gate hp=10000/10000 cam=47m page=0 alive=true at=-38,152,393` |
| 7 | S4 pad → the arc | — | `at=-3,301,-296` (the apex, r 175 from the Spire axis) then `boss hp=10000/10000 at=0,249,-185` (the fighting floor) |
| 8 | boss phase 1 | `game_over hp=0 page=5 alive=false at=0,249,-185` | `boss hp=10000/10000 cam=47m page=0 alive=true at=-0,249,-185` |
| 9 | boss phases 2 and 3 | `game_over hp=0 page=5 alive=false at=-6,249,-180` | `boss hp=10000/10000 cam=47m page=0 alive=true at=-0,249,-185` |

`E2ECAMREPORT captures=21 clean=19 buried=2` / `distinct=21 duplicates=0 no_subject=0`, **0 engine
errors in the whole run**. Frames: `captures/e2e_cp1_a_yard_fight.jpg` … `e2e_cp9_b_boss_p3_respawn.jpg`.
The three spire respawns land on the new `stand_off` probe (38 m out from the hive with a 45 m
walk-forward lane), not on the hero's live transform.

**`captures/e2e_cp3_b_spire0_respawn.jpg`** — the A2 respawn frame: HUD up (objective DESTROY THE
HIVE SPIRES with 1/3 diamonds, ARMOUR 10000/10000, radar, reticle, P1 PIERCE-LIGHT 9/9), the mech lit
and readable, the camera behind it.
**`captures/e2e_cp7_c_boss_p1_dead.jpg`** — the boss-phase-1 death frame: 机体损毁 MECH DESTROYED with
RETRY FROM CHECKPOINT selected and **every HUD widget hidden**, the dead mech on the deck.

**The bot with real weapons, no fallback** (`assault_city`):
`E2EWEAPONS spires=1 bot_kills=1 debug_fallbacks=0 [] scripted_clears=1 [&"A1"]`, and the log shows the
hive's pool falling under taps (`spire_hp=1000 → 475 → 0`) with `firing=true` and the magazine
cycling. `DRIVE done t=150.1 errors=2` — both are hero-v3's `hero3_glow` shader, not flow's.

**`e2e_city`**: `E2ECAMREPORT captures=17 clean=16 buried=1 won=true`,
`distinct=17 duplicates=0 no_subject=1` — **17 distinct md5s**, the brief's number — and the one
`NO-SUBJECT` is the new check catching the A5 pods frame that does not contain the hive.

**The collapse films**: `captures/e2e_hive_a{2,5,6}_collapse_0{0..7}.jpg`, 24 frames,
`clean=24 buried=0 distinct=24 duplicates=0 no_subject=0`, and the contact sheets
`tmp/flow/r5/sheets/hive_a{2,5,6}_collapse_sheet.jpg` (8 frames, 0.25 s apart, labelled, for the
trailer).

**The title**: `captures/r5_title_t4_0.jpg` and `_t9_0.jpg`, `DRIVE done t=34.0 errors=0`.

**Flow's own cost**: `PERF flow costs 0.013 ms per frame`, with the busy arm reading 2.099 ms of a
2 ms busy-loop — the gate can fail.

**The boss** (see `status/boss.md` for the full write-up): `DECKTRACK control 0.14 m / 20 summons
0.13 m / 8 s after a restore 0.81 m` per tick, the titan on the deck at y 16.0 with the deck at 16.0;
`BOSS TEST 135 checks, 0 failed`; `BOSS CITY TEST 20 checks, 0 failed`.

## Known issues

- **A2 and A6 still need `finish_spire` in a scripted run.** With the hull fixed and the bot firing
  real taps, A5 falls to the bot outright and A2 got 5,130 of 7,000 HP in a 50 s window before the
  aim/muzzle fixes landed. The windows are 130/140 s now and the last full run is in "In progress".
  The bot's rate is the other half of it: a tap is 230 damage and the repositioning between pods is
  what makes a hive a multi-minute fight in a script.
- **`--spire-hp-scale` is what makes a scripted hive killable at all.** At 1.0 a hive is 20,000 HP,
  which is six minutes of trigger time per spire at the city's frame rate. Every E2E number in this
  file is at 0.35 or 0.05 and says so.
- **The core's collar conforms to the trunk to second order only.** `FlowHiveSurface.curvature()`
  averages the shell across the collar's own angular width, which is right for the trunk and wrong for
  the individual ribs: two or three of the 14 loose plates still stand a little clear of a rib they
  should be lying on. They read as loose chitin rather than as an error at any distance the fight is
  played at, and closing it properly means sampling the 60,000-face skin on a grid (≈2 M triangle
  intersections a spire). Left as is deliberately.
- **The trunk's shot collision is 12,377 triangles a spire** (37 k for three). That is a deliberate
  trade: `GRID = 1.2` keeps the surface within half a cell of the skin, which is what lets a pod 1 m
  inside it poke through. A coarser grid is cheaper and buries the pods again.
- **`FlowDebugView.goto_place` and `film_collapse` place the mech by teleport.** They are debug
  commands; nothing in the shipped demo moves the hero that way.
- monster-assets is mid-refactor on the rigs: `monster_model.gd:293` errors 20×/run in the sandbox
  (their file). hero-v3's `hero3_glow` shader fails to compile in a headless run, which is the only
  reason two of flow's drives report `errors=2`.
- Frame times quoted anywhere in this file are from a shared box with other units' captures running;
  flow's own per-frame cost is measured separately by `test_flow_perf.gd` (0.013 ms).

## Requests (to the lead / other units)

**Closed since r4**

- ~~(lead) `drive --timeout=`~~ — it is in `tools/godot.sh` and every long run in this file uses it.
- ~~(city-layout) A2/A5 enclosed~~ — r6 moved the sites; the bot now kills A5 outright and takes A2 to
  27 % before the window ends.
- ~~(monster-assets) a shrink-wrapped `HiveCollision`~~ — **flow built its own** (`skin_shape()`, a
  decimated trimesh of the visible skin) because r5 could not wait. monster-assets can still land a
  proper hull; flow will use it when `collision_mesh()` stops being a convex hull.

**Open**

1. **(weapons) `ShotQuery.deliver` reports 0-damage hits.** `deliver` sets `receiver = collider` for
   any collider that answers `take_hit` and then emits `hit_landed` + `notify_mark` + `mark_hit`,
   whatever `final_amount` came back as. Flow's half is done — the trunk is a body with no `take_hit`,
   so a bare-shell hit is scenery and shows nothing — but any other 0-damage receiver still draws a
   marker and a number. `if hit.final_amount <= 0.0: return receiver` before the emits closes it.
2. **(weapons) `Rifle` has no auto-reload.** A charged shot that empties the magazine leaves
   `ammo = 0` with `reloading = false`, and only `_fire_normal` calls `reload()`. A player who empties
   the magazine on a stage-2 shot is stuck until they press R; the E2E bot works around it by tapping
   `reload` on a timer. `if ammo <= 0: reload()` after `_fire_charged` would fix it.
3. **(hud) the three menu items r5 depends on** (hud r6 has them): a PAUSE RETRY row that unpauses and
   then emits `retry_game`; GAME_OVER RETRY not closing its page before flow respawns; and the
   `abort_to_title` signal for PAUSE → ABORT. Until `abort_to_title` lands, flow answers `quit_game`
   itself and only when the page captured at the moment of the pause was PAUSE (see
   `_on_paused_changed`) — a stopgap that is deliberately as narrow as it can be.
4. **(combat / boss) `skill_system.gd:182` calls `is_alive()` on a `BossCore`,** which has no such
   method, so every core hit prints an error and the skill's on-hit hook is skipped. Pre-existing.
   `func is_alive() -> bool: return ratio() > 0.0` on `BossCore`, or a `has_method` guard at the call
   site.
5. **(city-build) the notch over the S4 pad.** flow's catapult arc routes outward past r 150 from the
   Spire axis before it rises (lead r16 decision 2), and that outward leg runs along the S4 axis —
   exactly where Crown rib j=2 is. city-build r11's notch is what makes it clear; flow re-runs its S4
   step gate after it (r16 conflict E4).
6. **(city-art) a title key light.** SPEC §8.1's title runs at night, so even with flow's two
   unshadowed omnis (a warm key at energy 26 and a cool rim) the mech reads as a dark, moody hero
   rather than a bright one. The staging is flow's and is done; the value is city-art's.
7. **(lead) `{"key": …}` timeline events for autoplay.** The acceptance fixtures use them
   (`title_menu.json` in `~/m/mc-accept`); `tools/autoplay.gd` only understands
   `press`/`release`/`tap`/`look`. Flow's own `title_menu.json` uses `press`, so this is a
   convenience, not a blocker.
8. **(city-layout) the A2 hive site is in a slot.** New finding, r5b item 2, measured not guessed: a
   sweep of **1,344 stands** round `hive_a2` (7 radii 80–320 m × 8 heights 20–280 m × 24 bearings)
   found **42** with a clear line to the spire's foot and top, and every one of them is at bearing
   255–285° (the south side) at r 80–110. For comparison A5 has 1,020 and A6 975. Nothing is broken —
   the collapse solver finds the slot and films the beat cleanly (the r5b gate passes at all four hero
   bearings) — but two things are worse for it than they need to be: the fight has almost no firing
   positions (this is the arena the E2E bot cannot finish inside its window), and the reward shot can
   only ever be a narrow south-side angle. Opening the slot, or moving the site 100 m, would fix both.
   The numbers are reproducible with the same sweep.
