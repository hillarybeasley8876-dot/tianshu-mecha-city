# mech-move status

## Done

### Lead r9 — `MechTeardown` calls the owners' hooks only (`reviews/mech-move-r9.md`)

skills r5 (`b1beb5a`, `2b651f1`) gave `SkillSystem.on_player_died()` the whole skills teardown —
anchor line, ward, beam and the Overdrive window (`_od.end_on_death()`, no aftermath on a death) —
and weapons r7 (`ba5ada7`) shipped `WeaponSystem.stop_volley()` (rifle `cancel()`, gatling
`cancel()`, hailstorm `cancel()`, `ctx.ads = false`, `_apply_strafe(false)`). Both blocks the gate
had kept as a safety net were therefore dead:

- `_skills()`'s `if is_overdrive_active() … end_overdrive()` — `on_player_died()` already closed the
  window through `OverdriveState.end_on_death()`, which is the same `_close()` path plus the
  aftermath reset, so the second call could only ever be a no-op on an already-closed window.
- `_weapons()`'s fallback branch — the private `ctx.ads` / `ctx.strafe_aim` writes and `_unpaint()`'s
  `painting` / `_paint_time` / `_lock_timer` / `locks` writes. `stop_volley()` sets every one of the
  same fields (`_apply_strafe(false)` is what clears `ctx.strafe_aim`, and `Hailstorm.cancel()` is
  field-for-field what `_unpaint()` did), so the branch duplicated the owner.

`mech_teardown.gd` is now 27 lines and three branches: `on_player_died()`, `stop_volley()`, and
`reset()` for the components that ship no death hook (melee, defense). `_skills()`, `_weapons()`,
`_cancel()` and `_unpaint()` are gone — no dead code, and the gate writes no private field of another
unit any more (skills Request 8, the weapons Requests). The dispatch still keys off `has_method`
because that is how the gate tells the three kinds of component apart; there is no stand-in in my
tests without a hook (`MechTeardown.quiet()` has exactly one caller, `mech_death.gd:121`, over
`components()` — the real scenes).

One test comment updated with it: `death_phases.gd` `_phase_overdrive_death()` now says the gate only
calls `on_player_died()`.

### Lead r8 — the capsule outran the legs on a kerb (`reviews/mech-move-r8.md`)

**Item 1 — the step-up is a coast, and the model lags it.** Measured first, then fixed.

**The measurement.** `probe_float.gd --case=walk_kerb --debug=1` prints the hip and the plant every
tick. Between two consecutive physics frames the capsule moved **2.01 m up and 4.24 m forward**
(hip y 7.71 → 9.72, hip z 9.48 → 5.24) — `MechStepping.try_step` was doing
`global_position += up + forward` in one tick. The trailing foot's plant stayed at z 6.68 for the next
0.6 s while the hip ran on to z −0.28: **6.96 m of hip past a plant that is already 8.14 m below it**,
10.4 m from a hip whose leg reaches 8.5 m. The IK clamped, so the sole was drawn short of its plant:
`walk_kerb` **75 % near, worst +0.91 above / −1.11 below**.

**Why the displacement is what it is.** A 3.5 m-radius capsule meets a 2 m kerb on its bottom
hemisphere, where the contact normal is ~65° off vertical — a wall, not a floor. To get its bottom
POINT over the face (the only place a downward settle finds the kerb top) the body centre has to
travel from 3.9 m short of the face to 0.3 m past it. There is no smaller move, so the answer is not
to move less; it is to move at a rate the legs can follow.

**The fix, in `player/mech/mech_coast.gd` (new).**

1. **The coast.** `try_step` now hands the whole displacement to `MechLocomotion.begin_coast()` and
   the body walks it out over `run-up / speed` seconds — which is **exactly the speed the mech was
   already doing**, so it neither stalls nor surges. `move_and_slide` is skipped for the duration
   (`try_step` already proved the straight line clear with `test_move` up and then forward), so
   `is_on_floor()` keeps the last real move's answer and the mech never enters S.AIR half way up a
   kerb. The coast ends `LIFT_EXTRA` above the top face and the 0.6 m floor snap settles it from
   there, so the old `test_move`-down settle is gone.
2. **The model lag.** The model node hangs off the body, so the gait's ground plane
   (`Hero3Frame.ground()`) and every hip in the rig ride the capsule's climb. `step_lag` holds the
   node that many metres low, which keeps the plane on the surface the **trailing** foot is really
   standing on; `Hero3Ground` then plants each foot on the surface under IT, so the leading foot
   stands on the kerb top while the trailing one is still on the road — which is what a real climb
   looks like. The lag is given back per **metre travelled**, not per second (`step_ease_ratio` 0.26,
   i.e. the 2 m rise over 8 m of road, inside the 12 m sandbox kerb at every speed), with a time floor
   (`step_ease_speed` 1.2 m/s) so a mech that stops dead on a kerb still puts its feet back under it.
   The rest offset is read once, so `probe_float.gd --nofix` (which parks the node on the body origin
   on purpose) keeps its own value.

**The gate** (`walk_kerb`, `tools/godot.sh test res://player/model/hero3/tests/probe_float.gd`):

| | near | worst above | worst below | p50 | edge frames |
|---|---|---|---|---|---|
| HEAD (732d8d9) | **75 %** | **+0.91** | −1.11 | −0.00 | 21 |
| r8 | **100 %** | **+0.02** | −0.00 | +0.00 | 0 |

and the whole table is green — all **11** cases at 100 % near, `FLOAT PASS`.

**New suite** `player/mech/tests/test_step_coast.gd` (**36 checks**) is my own half of the gate, in
my own paths: a 2 m kerb and a 1 m kerb, each at a walk and at a run, plus the step down off the far
edge, the model lag, and the coast's cancellation. Every crossing owes six rows — no teleport, a
coast, no air, no speed lost, standing on the kerb, the model holding the lower surface.

**The split (`CLAUDE.md`: over 400 lines, split before you go on).** The coast took
`mech_locomotion.gd` to 469. Two files come out, both in the pattern the file already used
(`MechDash`, `MechBoost`, `MechAir`, `MechStepping` are all static helpers on `MechLocomotion`):

| new file | what moved | lines |
|---|---|---|
| `player/mech/mech_coast.gd` | the coast state, the clock and the model lag (`MechCoast`) | 92 |
| `player/mech/mech_ground.gd` | the grounded state, the coast label and the turn (`MechGround`) | 66 |

The ground split is its own commit (`b1f1579b`), verified in a tree with **nothing else from r8
applied** — `test_locomotion` 56/56, `test_stepping` 17/17, `test_flight_input` 16/16 — because
CLAUDE.md wants the split reviewable on its own. `mech_locomotion.gd` 396 → **341** there and
**378** with the coast on top. Nothing in the unit is over 400 lines any more
(`player_mech.gd` 396, `tests/death_phases.gd` 396, `mech_locomotion.gd` 378).

**Item 2 — monsters are not a moving floor** (committed `732d8d9` + `a02faeb`): unchanged by this
round and re-run green (`test_platform.gd` 5/5, the world-platform arm still carried 7.97 / flung
8.00, the monster arm 0.00 / 0.00).

**Item 3 — Requests 16 and 17 have NOT landed.** `SkillSystem.on_player_died()`
(`game/combat/skills/skill_system.gd:280`) still only detaches the anchor and drops the ward — it
does not end a running Overdrive window — and there is still no `stop_volley()` / `holster()` on
`WeaponSystem`. Both stay as Requests 16 and 17 below, unchanged, with my local adapters still doing
the work (`mech_teardown.gd` already prefers `stop_volley()` behind `has_method` the moment it
exists). I have not touched either unit's files.

### Lead r7b — the gate was right, but it refilled, left the Overdrive on and ate presses (`reviews/mech-move-r7b.md`)

**1. Overdrive (major 1).** `MechDeath.stop_components` called `SkillSystem.reset()`, which zeroes
`_od_active` without `end_overdrive()`: `MechEnergy.overdrive_active` stayed true, the meter stayed at
100, `overdrive_changed(false)` never fired and audio's Overdrive loop kept playing. The gate now ends
a running window through the skill's **own** path (`MechTeardown._skills` → `SkillSystem.end_overdrive()`),
which drops the meter to 0, emits `overdrive_changed(false)` once and tells the model. Gate:
`test_death.gd` `_phase_overdrive_death` — die 1.25 s into an Overdrive, revive the way
`_restore_player` does, then `overdrive_active` false, `overdrive_changed(false)` **exactly once**, the
meter 0, and a held V starts nothing.

**2. No refill (major 2).** `WeaponSystem.reset()` reloads the magazine and the belt, zeroes the heat
and the missile cooldown and selects the rifle **without** emitting `weapon_switched`;
`SkillSystem.reset()` restores every charge. Neither runs at a death any more. The new
`player/mech/mech_teardown.gd` stops only what was RUNNING, behind `has_method` so a component's own
hook wins when it has one:

| component | what the gate calls | what it leaves alone |
|---|---|---|
| skills | `on_player_died()` (skills r4 item 6: the anchor line and the ward) + `end_overdrive()` when a window is live | every charge, every cooldown, the buffs, EN |
| weapons | `rifle.cancel()`, `gatling.cancel()`, the launcher's `painting` / `locks` / paint timers, `ctx.ads` and `ctx.strafe_aim` | the cell's rounds, the belt, the heat, the jam and Superheated timers, the missile cooldown, `current` |
| melee | `reset()` — it refills nothing (the blade, the lunge, the execution, the charge state) | — |
| defense | `reset()` — it refills nothing (the guard, the catch field, the shield) | — |
| aim | nothing: a lock-on is carry-over | the lock |

Gate: `test_death.gd` `_phase_carry` spends three rifle rounds, a salvo, a burst charge and the
gatling's belt, swaps to the gatling, dies for a quarter of a second and reads the same line back.

**3. The revive latch is per action (major 3).** The r7 latch kept **all five** components'
`_physics_process` off until **every** held action had been released, so holding RMB through RETRY
left fire, melee, guard, skills and lock-on dead. Now the components come back on the revive tick and
only the verbs that were held read as released: `PlayerMech.latch_revive` calls
`Input.action_release(a)` for each held component action, and `_tick_revive_latch` re-applies it every
tick **while the device is still down** (a key repeat would otherwise sneak the verb back in) and
drops it the moment nothing bound to the action is held. `_device_down` asks the physical device
through the InputMap (`is_physical_key_pressed` / `is_mouse_button_pressed` /
`is_joy_button_pressed`); an action with no InputMap event — the pad-only `lock_prev` / `lock_next`,
which `core/pad_input.gd` drives through `Input.action_press` — cannot be asked and cannot repeat
either, so the mute applied on the revive tick simply stands until the pad sends a new press. Gate:
`_revive_rmb_held` — RMB held across the revive, then a fresh **F**, **LMB** and **Q** each act, and
`ctx.ads` stays false.

**4. The tests hold their keys (major 4).** The suite is **108 checks**; the held-across set is fire
(LMB), guard (Q), Space on the ground, Space in the air, W, and a rifle charge released on the page. `death_test_base._kill()` called `_release_all()` two ticks
before the hit, so every "held" row released first, and in `_phase_revive` the guard was still up and
ate the "killing blow" (hp 10000 → 5500, no `player_died`). Now:
- `_kill_holding()` leaves every key down and lands an **unblockable** hit
  (`HitInfo.unblockable` short-circuits `defense_system.gd` `_damage_filter`), and `_kill()` is
  `_release_all()` + `_kill_holding()` for the rows that want a clean start;
- `_phase_revive` asserts the mech is really dead and that exactly one `player_died` fired, and that
  fire, guard and Space are still down at the revive;
- the DEAD loop ORs in the post-release state, as the LIVE loop does;
- `_reset_weapons()` is called per row that needs it, so no row inherits the 0.35 s swap lockout.

**5. Last stand (major 5).** `test_last_stand.gd` is folded into `test_damage.gd` (r16 B5) and
deleted. `reset_rate_limits()` is called before the pipeline half, before the director half and
**before the killing-blow row**, so the director's 60 s cooldown is never what makes a row pass.

**6–8.** A death in the flight assault jet (a toggle on S.FLIGHT, not the S.ASSAULT state) now emits
`boost_ended(&"assault")` at the latch, exactly once in both cases. `open_states` reads the state
machine off the floor contact the revive actually has, so a corpse `flow/hive_collapse.gd`
`_shove_hero` threw into the air no longer revives stuck in S.AIR where a jump press only buffers.
`player_died` fires once per death even when a driver writes hp itself: `MechDamage` listens to its
own signal and stays quiet when the announcement did not come from `_die()`.

**9. The missing rows** are all in: the pad's D-pad `lock_prev`/`lock_next` (a real
`InputEventJoypadButton` through `core/pad_input.gd`, with a second `Targetable` so the live baseline
can switch), dying with the Overdrive live and then V (the Lance), a salvo fired before the death that
keeps flying to its target, and — after the revive — no lit saber, no charge stance, no gatling spin,
no missile paint and no ADS (`_quiet_loadout()` reads all five off the components).

**10. Hygiene.** The cancel checks hold the trigger over real ticks, so the bus row can fail; the
`mech_test_base.gd` `_reset` comment no longer claims a bare hp write leaves the gate closed (it does
not, since `MechDamage.sync()` mirrors `is_alive()` on every tick); the slump is described in numbers.

### Lead r7 — a dead mech is dead (`reviews/mech-move-r7.md`, `reviews/r16-conflicts.md` B1–B10)

**Root cause.** `_dead` (`player_mech.gd:47` at 5aea16b) only played the held `death` clip. Nothing
else looked at it: `_physics_process` still ran `_loco.tick`, `MechInput.poll` still read the stick
every tick, every state acted on it, and each of the five components polled `Input` in its own
`_physics_process` with no alive check. `_dead` and `is_alive()` also disagreed whenever hp was
written without `heal()` — the test harness's `_reset` did exactly that.

**Fix — one gate, in PlayerMech.** `is_alive()` is the single "dead" predicate (r16 B3); `MechDamage.dead`
is only its cached mirror, synced at the top of every physics tick and at both places hp changes, so a
bare hp write can no longer leave the gate closed. `MechDeath` owns what the latch stops:

| what | how | why it is enough |
|---|---|---|
| movement | `PlayerMech._physics_process` takes a `MechDeath.tick` branch: `MechInput.poll` still runs (so the held-key edges stay current), gravity + `move_and_slide` keep running, no state acts | the wreck settles; nothing reads the stick for movement |
| horizontal speed | zeroed at the latch (`MechDeath.close_states`); the killing blow's knockback is applied **after** it (`MechDamage._knockback`, straight onto the body) | lead r7: "horizontal speed dies, though the killing blow's own knockback may still carry it". On the ground brake curve a 16 m/s corpse still coasted **1.3 m** |
| states | `close_states` leaves flight / slide / assault / dash / lunge / lock with their normal events (`flight_changed(false)`, `boost_ended`) | SPEC §3 |
| the five components | `set_physics_process(false)` + each one's public `reset()` | CONTRACTS §1: the loader is ours, so no guard line is added to another unit's file. `reset()` is the "drop everything" hook each component already ships and nobody called. Rounds and missiles in flight are children with their own clocks, so they keep flying |
| the model | one neutral `set_locomotion(&"idle", 0, 0)` then silence; thrusters, wings and the saber to 0 | `set_locomotion` is what drives the gait AND the upper-body clip map: without it the legs kept cycling the state the mech died in (and `Events.footstep` kept firing), and a `fly` / `slide` / `land_*` id swapped the held `death` clip out |
| the aim feed | `_feed_model` forces weight 0 while dead | the arm comes down and stays down |
| EN | `_en.tick` is not called at all | the corpse burns none and regenerates none |
| `can_cancel()` | `is_alive() and _loco.can_cancel(tag)` | false for every tag |
| the revive | `heal()` and the hp sync are the only release; `MechInput.swallow()` + `PlayerMech._clear_revive_latch` latch whatever was held | r16 B8 |

**r16 B8 (the revive latch) — this OVERRIDES the r7 review's "W held through RETRY walks normally".**
The conflict map's row wins, so every action held at the instant the gate re-opens reads as RELEASED
until it is really let go. `MechInput` does it for its own eight actions; the component-facing actions
(`fire`, `aim`, `reload`, `weapon_next/prev`, `missiles`, `melee`, `guard`, the five skills,
`overdrive`, `lock_on/prev/next`) hold their components' `_physics_process` off until every one of them
has been released, because the components poll `Input` themselves and cannot be edited from here.
`ui_accept` is `[Enter, Kp Enter, Space]` and `jump` is `[Space]` — the probe prints the InputMap, so
the collision is on the record.

**r16 B1 (the split).** `player_mech.gd` 493 → **366** lines, built off-tree in
`tmp/mech-move/split/` and swapped in whole: `MechBuild` (the scene graph, 116), `MechDamage` (the hit
pipeline + the latch, 169), `MechDeath` (the gate, 145). Commit `15657b0`, `check --only=res://player/mech/`
run straight after the swap: **25 files, 0 failed**. No file in the unit is over 400 lines
(`mech_locomotion.gd` 396 is the largest).

**r16 B5 (the last stand).** `Feel.play(&"last_stand", pos)` is wired in `MechDamage._last_stand`:
any hit that takes hp from ≥ `MechTuning.od_low_hp` (0.15) to below it **while the mech stays alive**.
Never on the killing blow, never in god mode, never for a hit that starts below the line. No second
timer: the 0.5×, the 1.5 s and the 60 s cooldown are the feel row's. It is a **standalone**
`test_last_stand.gd` (weapons' 25c0963 pattern) so `test_damage.gd` stays green for hero-v3 and
tooling until feel r5 lands `fx/events/last_stand.tres`.

**Fix — the harness.** `mech_test_base.gd` `_reset` wrote `_p.hp = _p.hp_max`; it now calls
`_p.heal(_p.hp_max)`, the one path every revive goes through.

### Lead r6 — 飞行 / the flight toggle
**Root cause, part 1: the reported repro does not reproduce.** `tl_s06_flight.json` run through the
exact command `tools/trailer/render_all.py` builds (`tools/trailer/record.sh` → `godot.sh movie
--movie-size=1920x1080`) **does** enter flight: `flying=true` from **t = 0.746 s**, 26 ms after the
second tap at 0.72 s, and it holds to t = 2.9 s. Telemetry: `tmp/mech-move/s06_rec.csv`. The take's
frames are the same in `drive` and in `movie`. So the trailer's "the hero never enters 飞行" is a
**camera** reading, not a state one — see Request 6: at the cut (in 1.2 / out 3.06) the mech is
flying but the rig has already whipped off it (`look_rate [0, -70]` at 2.0 s), so the shot shows
city and a ground boost at the tail.

**Root cause, part 2: the defect the report describes is real, and it is one line wide.**
`input.double_jump` was honoured in exactly **one** place — `MechAir.air()`. Every other state that
answers a jump press treated it as a plain hop and threw the flag away:

| state | file | before r6 |
|---|---|---|
| ground, inside the SPEC §4 knee-dip | `mech_locomotion.gd` `_ground` | `if _pending_jump: … return` ran **before** any double-tap test, so a tap-tap closer than 4 frames (67 ms) lost the second press entirely |
| boost slide | `mech_boost.gd` `slide` | `if jump_pressed: _launch()` |
| assault boost | `mech_boost.gd` `assault` | `if jump_pressed: _launch()` |
| dash (after the i-frames) | `mech_dash.gd` `dash` | `if jump_pressed …: _launch()` |
| landing recovery | `mech_air.gd` `land` | `if jump_pressed: GROUND; _launch()` |

The boost case is the one that bites a real take: `tl_s06_flight.json` presses `move_forward` +
`boost` at 1.3 s, and with boost held the mech is back in `S.SLIDE` one tick after the first tap's
hop — so the second tap is a slide jump and the toggle is unreachable. **Holding boost made flight
impossible to enter.** There was also no energy gate at all: a double tap on an empty gauge lit the
jet for a tick and dropped straight back out.

**Fix** — one shared entry point, `MechLocomotion.try_flight()`, asked first by every state that can
act on a jump press (`_ground` before the knee-dip, `MechAir.air`, `MechAir.land`, `MechBoost.slide`,
`MechBoost.assault`, `MechDash.dash` after the i-frames). It requires `jump_pressed and double_jump`,
refuses during an Outage (SPEC §4: no thrusters), and — SPEC §3 "from the ground the first tap's hop
is what puts the hero in the air" — launches first when the mech is still on the floor, so a pair
that lands inside the knee-dip still flies. `MechAir.flight`'s exit branch is unchanged.

**New suite** `player/mech/tests/test_flight_input.gd` (16 checks) drives the **real input path**:
`Input.parse_input_event` with `InputEventKey` physical keycodes (`core/input_setup.gd`'s bindings),
held for the same 3 rendered frames `tools/autoplay.gd`'s `tap` uses. Before the fix it scored
**8/14** (knee-dip, boost slide, dash, outage all FAIL); after, **16/16**.

- **PlayerMech root** (`player/player_mech.tscn` + `player/mech/player_mech.gd`): `CharacterBody3D`,
  group `&"player"`, layer `Layers.PLAYER`, mask `Layers.MASK_CHARACTER`, capsule r 3.5 / h 15,
  `floor_max_angle` 40°, `floor_snap` 0.6 m, spawns at `Game.spawn_transform(<world PlayerSpawn>)`,
  `Game.register_player(self)`, then instances the model (hero model if present, else the placeholder)
  and every component scene of CONTRACTS §5 in order (missing ones skipped). Two Hurtboxes (torso,
  legs) on `Layers.PLAYER_HURTBOX`. Debug follow camera created on the first **physics frame** only if
  `Game.camera_rig` is still null (main.gd spawns the player before the rig, so `_ready` is too early).
- **Tuning** (`mech_tuning.gd` / `mech_tuning.tres`): every number of the revised SPEC §4/§5 plus the
  r1 landing tiers and the stepping block, no magic numbers in the state code.
- **States** (`mech_locomotion.gd` 376 lines + `mech_boost.gd` + `mech_air.gd` + `mech_dash.gd` +
  `mech_contact.gd` + `mech_debug.gd`, one file per family, all < 400): ground (idle/walk/run/coast),
  dash, boost slide, assault boost, air, flight (with assault pitch), landing, locked, lunge.
- **Stepping** (`mech_stepping.gd`, SPEC §4): step-up ≤ 2.5 m on every grounded state (ground, slide,
  assault **and dash**) and the boost auto-hop over obstacles ≤ 7 m above the feet.
- **Landing tiers** (lead r1): soft < 25 m/s, hard ≥ 25 m/s, `land_heavy` feel only ≥ 32 m/s;
  `land_kind` (none/soft/hard/outage) exposed in `telemetry()`.
- **Assault pitch** (lead r1): in flight the assault boost carves its pitch toward the view at
  `assault_pitch_deg` (45°/s) instead of snapping to the crosshair.
- **Energy / OD** (`mech_energy.gd`), **damage pipeline** (`player_mech.gd`), full CONTRACTS §5 API
  incl. `telemetry()` (`land_kind`, `step_events`, `hop_events`, `assault`), `hud_state()`,
  `can_cancel()`, `drain_energy()`, `debug_teleport`.
- **Placeholder model**: 16 m blocky mech, full HeroModel API, procedural motion; rig pivot at
  12.37 m so the soles sit at y = 0, `cockpit` socket at 12.01 m above the feet.

### Lead r3
1. **Assault boost is its own input** (`assault` toggle from ground / boost / flight, sustained boost
   hold, skid brake 0.25 s exits). 2. **Clock split** (movement + input on `Feel.locomotion_delta`,
   timers/i-frames/EN on `Feel.player_delta`). 3. **Pad descend** (B without forward).

### Audit round (lead, `reviews/mech-move-audit.md`) — all 7 findings fixed
1. **[high] `face_toward` turned the body away from the stick** (`mech_locomotion.gd:184`). The yaw
   step is now `angle_difference(atan2(f.x, f.z), atan2(dir.x, dir.z))` (target − current), the
   convention `MechBoost._steer` already used. Verified by reverting the line and re-running the
   suite: the old expression gives **facing = −1.000** for right/left/back and labels a forward dash
   `dash_b`; the new one gives **1.000** and `dash_f`. Every caller (ground, air, boost, assault,
   flight, strafe, lunge, locked) is affected and now converges on `dir`.
2. **[high] + [5] a local hit-stop froze the state handlers while the body went on moving.** New
   `MechLocomotion.is_frozen()` = `_pause_t > 0` **and** state ∈ {LOCKED, LUNGE}: FEEL.md and juice
   §2.2 say a player-started boost/dash/landing never freezes. `PlayerMech._physics_process` keeps
   the move while frozen but at `FROZEN_CREEP` = **5 %** (FEEL.md "attacker at 5 % speed") and
   restores the velocity afterwards, so a lunge creeps 0.83 m instead of 16.5 m per 0.15 s stop.
   `post_move()` now runs the touchdown / leave-floor detection **above** the freeze return, so a
   floor touched inside a stop can never be dropped (that is what stranded a mech in `S.AIR`).
3. **[medium] inputs pressed during a stop were eaten.** `MechInput.latch_edges()` keeps the
   jump/boost/assault edges (and `double_jump`) while frozen and hides them from the states that are
   not running; `release_edges()` folds them back in on the first tick whose state can act, and a
   press older than the new `input_buffer` (0.30 s) is dropped. A combat lock keeps the press
   buffered, so a dash tapped inside a hit-stop fires when the lock ends.
4. **[medium] the boost hop was never flown.** `post_move` no longer demotes an airborne SLIDE /
   ASSAULT to `S.AIR` while `_hop_cd > 0`, so `MechBoost` flies the arc its own solver produced
   (fall gravity, constant boost speed) instead of the air states' 79 m/s² rise + 16 m/s brake.
   `MechContact.touchdown` uses `impact = maxf(-_pre_vy, 0.0)` (never `absf`: a vault touches down
   still rising) and treats a `_hop_cd > 0` SLIDE/ASSAULT touchdown as a **vault** — no LAND
   recovery, no `Events.landed`, the assault toggle survives.
5. **[medium] `hit_pause` never reached the model** (also lead note 2 / hero-asset r2).
   `PlayerMech.hit_pause` now forwards to `_model.hit_pause(seconds)` when the model has it.
6. **[low] EN drains ran on the real clock** while `MechEnergy.tick` ran on the player clock. Every
   per-second cost (`ascend`, `hover`, `flight`, `flight_boost`, `boost`, `assault`) is now charged
   on `l.pdelta`, so a global hit-stop no longer drains up to 18 EN while the regen behind it is
   frozen. Movement itself stays on the real clock.
7. **Lead note 1**: `PlayerMech.reset_dash_chain()` (+ `MechLocomotion.reset_dash_chain()`) for Rift
   Step, with a test.

Structure: `debug_reset()` moved out of the state machine into `mech_debug.gd` (tool-only code, keeps
`mech_locomotion.gd` at 376 lines); the damage + hit-stop checks moved into their own suite
`tests/test_damage.gd`, so no file in the unit is over 400 lines.

## In progress / next
- **Nothing outstanding from r8.** Items 1 and 2 are implemented, gated and mutation-tested (see
  Evidence → r8); item 3 is a check, and the answer is "not landed" — Requests 16 and 17 stand.
- **Nothing outstanding from r7b.** Every item in `reviews/mech-move-r7b.md` is implemented and
  mutation-tested (see Evidence → r7b); the two windowed gates are under **Captures needed**.
- **hud r6's GAME_OVER pause** has not landed. The gates were built so it cannot mask them (a headless
  suite with no HUD, a `--stub=hud` drive, and a windowed drive run before it lands). Re-run the probe
  once after it does.
- **`test_step_coast.gd` needs a row in `tools/suites.txt`** (lead-owned) — Request 21.

## How to verify (exact commands)
Every gate below is **headless** (the 11-05 dispatch note: `drive` refuses without the lead's
`MC_WINDOW_OK`). The two windowed runs are under **Captures needed**.
```
tools/godot.sh check --only=res://player/mech/
tools/godot.sh test res://player/mech/tests/test_step_coast.gd   --timeout=600   # r8, 36 checks
tools/godot.sh test res://player/mech/tests/test_stepping.gd     --timeout=600   # 17 checks
tools/godot.sh test res://player/mech/tests/test_platform.gd     --timeout=600   # r8 item 2, 5 checks
tools/godot.sh test res://player/mech/tests/test_death.gd        --timeout=1200  # r7b, 108 checks
tools/godot.sh test res://player/mech/tests/test_damage.gd       --timeout=900   # r7b, 33 checks
tools/godot.sh test res://player/mech/tests/test_flight_input.gd --timeout=900
tools/godot.sh test res://player/mech/tests/test_locomotion.gd   --timeout=600
tools/godot.sh test res://player/mech/tests/test_stepping.gd     --timeout=600
tools/godot.sh test res://player/mech/tests/test_clocks.gd       --timeout=600
tools/godot.sh test res://world/art/tests/test_no_abs_paths.gd   --timeout=600
# the lead's kerb gate (hero-v3's probe; `--case=walk_kerb` for the one row that was red):
tools/godot.sh test res://player/model/hero3/tests/probe_float.gd --timeout=1500
# the r8 mutation: `try_step` back to the one-tick teleport, tree restored after the run
python3 tmp/mech-move/r8_mutate.py
# the mutation matrix (one r7b fix reverted at a time, tree restored after every run):
python3 tmp/mech-move/mutate.py                    # all ten
python3 tmp/mech-move/mutate.py M8_last_stand_on_kill res://player/mech/tests/test_damage.gd
```
The older rounds' commands (the flight strip, the trailer take, the 45 s tour, the scripted fight)
are unchanged and still in the git history of this file.
# the flight film strip (r6): tap-tap, climb +56 m, bank, assault boost, descend, land
tools/godot.sh drive --sandbox --timeline=res://player/mech/timelines/flight.json \
  --out=mech-move_flight --shots=0.9,2.2,3.6,4.9,5.9,7.4,8.8,10.2,11.2
tools/godot.sh movie --movie=/Users/minimax/m/mecha-city/captures/mech-move_flight.avi \
  --sandbox --timeline=res://player/mech/timelines/flight.json --out=mech-move-flight-movie
# the trailer's own take, exactly as tools/trailer/render_all.py builds it:
tools/trailer/record.sh /tmp/s06.avi res://trailer/tl_s06_flight.json \
  --scene=res://trailer/shot.tscn --log=/Users/minimax/m/mecha-city/tmp/mech-move/s06_rec.csv \
  --skip-menu --god --tod=0.6 --stub=flow --spawn=-200,39.5,-260,180 --enemies=harrier:3
tools/godot.sh drive --sandbox --timeline=res://player/mech/timelines/tour.json --out=mech-move_r4 \
  --shots=1.5,4.7,6.5,8.0,16.5,19.6,24.5,29.6,37.6
tools/godot.sh movie --movie=/Users/minimax/m/mecha-city/captures/mech-move_tour.avi \
  --sandbox --timeline=res://player/mech/timelines/tour.json --out=mech-move-movie
# scripted fight (enemies unit's probe + timeline, driven read-only) with the NaN watcher:
tools/godot.sh drive --scene=res://enemies/tests/fight_probe.tscn \
  --timeline=res://enemies/tests/fight_timeline.json --out=mechmove_fight --shots=6,14.5,16,27 \
  --sandbox --enemies=ripper:6,mantis:2,juggernaut:1 --nan-watch
```
The tour timeline is calibrated for the **real rig** (mouse look 0.06°/px, `_yaw_deg -= px * 0.06`):
`look [1500, 0]` turns the view to +X (east), `look [-1500, 0]` back to -Z.

## Evidence

### r9 (`reviews/mech-move-r9.md`) — `MechTeardown` is three calls
- `tools/godot.sh check --only=res://player/`: **162 files, 0 failed, 0 engine errors, 0 warnings**.
- `tools/suites.sh --only=mech_locomotion,mech_damage,mech_stepping,mech_clocks,mech_flight_input,mech_death,mech_step_coast,mech_platform,skills,weapons,weapons_feel_rows`
  → **SUITES 11 rows, 11 green, 0 known, 0 red**, every row `script_err 0 / other_err 0`:

  ```
  mech_locomotion   0  PASS mech-move locomotion: 56/56 checks passed    ok
  mech_damage       0  PASS mech-move damage: 33/33 checks passed        ok
  mech_stepping     0  PASS mech-move stepping: 17/17 checks passed      ok
  mech_clocks       0  PASS mech-move clocks: 9/9 checks passed          ok
  mech_flight_input 0  PASS mech-move flight input: 16/16 checks passed  ok
  mech_death        0  PASS mech-move death: 108/108 checks passed       ok
  mech_step_coast   0  PASS mech-move step coast: 36/36 checks passed    ok
  mech_platform     0  PASS mech-move platforms: 5/5 checks passed       ok
  skills            0  TEST 289 checks, 0 failed                         ok
  weapons           0  TEST 189 checks, 0 failed                         ok
  weapons_feel_rows 0  TEST 13 checks, 0 failed                          ok
  ```

- `tmp/suites/mech_death.log` — the two rows the brief names are unchanged and still PASS:
  ```
  PASS CARRY a short death changes no ammo, charge or weapon  [rifle=6 gatling=226 burst=0 weapon=gatling | rifle=6 gatling=226 burst=0 weapon=gatling]
  PASS CARRY the missile cooldown is not zeroed by the death  [11.17 -> 11.12]
  PASS CARRY the gatling heat is not zeroed  [11.9 -> 11.9]
  PASS OD the V gesture opens the Overdrive  [mech=true sys=true meter=100]
  PASS OD the death closes the window with exactly one overdrive_changed(false)  [+1]
  PASS OD the meter reads 0 and the mech is out of Overdrive  [mech=false sys=false meter=0]
  PASS OD V while dead fires no Lance  [none]
  PASS OD V after the revive does not hand out a free Overdrive  [mech=false sys=false meter=0 none]
  ```
  The `+1` on the `overdrive_changed(false)` row is the proof the deleted block was dead: the gate now
  calls `on_player_died()` alone and the count is still exactly one (skills' `end_on_death()`), not two
  and not zero.
- No windowed capture is needed for r9 — nothing visible changed.

### r8 (`reviews/mech-move-r8.md`) — all gates headless, one Godot process at a time
- `tools/godot.sh check --only=res://player/mech/`: **35 files, 0 failed, 0 engine errors,
  0 warnings**. Nothing in the unit is over 400 lines (`player_mech.gd` 396,
  `tests/death_phases.gd` 396, `mech_locomotion.gd` **378**, `tests/death_test_base.gd` 369,
  `tests/test_locomotion.gd` 366, `tests/test_damage.gd` 344, `mech_coast.gd` 92, `mech_ground.gd` 66).
- **The lead's gate** — `tools/godot.sh test res://player/model/hero3/tests/probe_float.gd
  --timeout=1500`: **11 cases, 100 % near on every one, `FLOAT PASS: 0 case(s) outside the
  rendered-floor gate`**. `walk_kerb` **75 % → 100 %**, worst above **+0.91 → +0.02**, worst below
  **−1.11 → −0.00**, edge frames 21 → 0, planted frames 252 → 273. Rows:
  `idle_flat` +0.01/−0.05, `walk_flat` +0.02, `run_flat` +0.01, `strafe_flat` +0.02, `turn_flat` +0.01,
  `slide_flat` −0.00/−0.05, `hop_flat` −0.01/−0.05, `heavy_flat` −0.01/−0.05, `walk_ramp` +0.02,
  `walk_kerb` +0.02, `idle_kerb` +0.01.
- **My own gate** — `test_step_coast.gd`: **36/36**. The four crossings (2 m and 1 m, walk and run):

  | crossing | max single-tick move | coasting | airborne | min speed | climb | max model lag |
  |---|---|---|---|---|---|---|
  | 2 m at a walk | 0.075 m | 56 ticks | 0 | 9.00 m/s | 2.00 m | 1.99 m |
  | 2 m at a run | 0.133 m | 32 ticks | 0 | 16.00 m/s | 2.00 m | 1.99 m |
  | 1 m at a walk | 0.075 m | 56 ticks | 0 | 9.00 m/s | 1.00 m | 0.99 m |
  | 1 m at a run | 0.133 m | 32 ticks | 0 | 16.00 m/s | 1.00 m | 0.99 m |

  (0.075 m is 9 m/s / 120 Hz and 0.133 m is 16 m/s / 120 Hz — the frame's own motion, i.e. the coast
  moves the body at exactly its own speed.) Plus the step down off the far edge at both speeds
  (lands, `land_kind` none, no speed lost), the lag unwound (`lag 0.000` by z = −5.1, model node back
  at y = −7.500), and the cancellation (a jump during a coast ends it and the mech is airborne).
- **Regression, same tree:** `test_locomotion` **56/56**, `test_stepping` **17/17**, `test_clocks`
  **9/9**, `test_flight_input` **16/16**, `test_damage` **33/33**, `test_death` **108/108**,
  `test_platform` **5/5**, `test_no_abs_paths` **PASS**.
- **Mutation** (`python3 tmp/mech-move/r8_mutate.py`, one file: HEAD's `mech_stepping.gd`, tree
  restored from `tmp/mech-move/r8_pristine/` afterwards): `test_step_coast` **22/36** with **14 rows
  red** — the four `never teleported` rows (max tick move **4.238 / 4.278 m**), the four `is a coast`
  rows (0 ticks), the four `model holds the lower surface` rows (lag 0.00 m), `the model node lags
  the capsule` and `a run into the kerb reaches the coast` — and `probe_float walk_kerb` back to
  **75 % near, +0.91 / −1.11, edge 21, `FLOAT FAIL`**. The tree compiles clean after the restore
  (`check` 35 files, 0 failed).
- **`tools/suites.sh --only=mech_locomotion,mech_damage,mech_stepping,mech_clocks,mech_flight_input,mech_death`**:
  **`SUITES 6 rows, 6 green, 0 known, 0 red`**, every row `script_err 0, other_err 0`. The run also
  prints `UNLISTED game/player/mech/tests/test_step_coast.gd` and
  `UNLISTED game/player/mech/tests/test_platform.gd` — Request 21.
- **`--nofix` is intact** — `probe_float.gd -- --case=walk_kerb --nofix=1` still prints
  `BEFORE (--nofix) … sole trim L 0.000 R 0.000` and `near 0 % above +7.57 below +5.86`: the model lag
  captures the node's rest offset on the first physics frame, so a tool that parks the node on the
  body origin on purpose keeps its own value (Request 22).

### r7b (`reviews/mech-move-r7b.md`) — all gates headless, host `317d03c`
- `tools/godot.sh check --only=res://player/mech/`: **30 files, 0 failed, 0 engine errors,
  0 warnings**. No file in the unit is over 400 lines (`mech_locomotion.gd` 396, `player_mech.gd` 393,
  `death_phases.gd` 396, `death_test_base.gd` 369, `test_damage.gd` 344, `test_death.gd` 275,
  `mech_death.gd` 158, `death_dead_phase.gd` 129, `mech_teardown.gd` 75).
- `test_death.gd`: **108/108** (was 71). `test_damage.gd`: **33/33** (21 + the 12 last-stand rows).
  Regression, same host: `test_locomotion` **56/56**, `test_flight_input` **16/16**, `test_stepping`
  **17/17**, `test_clocks` **9/9**, `test_no_abs_paths` **2 492 files, 0 absolute home paths**.
- **Mutation score: 8 of 10 mutations flip the rows they should — 32 rows in total.**
  `tmp/mech-move/mutate.py` reverts one fix at a time, runs the suite and restores the tree from
  `tmp/mech-move/pristine/`; every number below is from a run of that script on this commit.

| mutation (what it reverts) | suite | rows that flip |
|---|---|---|
| **M1** `MUT_mech_death.diff` verbatim — the whole revive latch removed (the a4de047 behaviour of `player_mech.gd` + `mech_input.gd`) | `test_death` **102/108** | `a guard held across the revive does not come back up`; `Space held across the revive does not hop or take off` (`floor=false, hover`); `W held across the revive does not walk` (**16.0 m/s → 7.60 m**); `a fresh jump press hops again` (the RETRY press is still inside the double-tap window, so the fresh press toggles flight instead of hopping); `a held RMB does not put the mech back into ADS` (`ads=ON`); `Space held across an airborne revive does not ascend` (**y +4.6 m**, en 997 → 962) |
| **M2** the r7 all-or-nothing latch (components off until every held action is released) | `test_death` **97/108** | the lead's item 3 gate in full: `a fresh F press swings while RMB is still held`, `a fresh trigger press fires while RMB is still held`, `a fresh Q press guards while RMB is still held`, plus `the trigger works again after the dropped charge` and 7 rows the starved components take down with them |
| **M3** the r7 `reset()`-everything teardown | `test_death` **101/108** | `CARRY a short death changes no ammo, charge or weapon` (`rifle=6 gatling=226 burst=0 weapon=gatling` → `rifle=9 gatling=240 burst=1 weapon=beam_rifle`), `CARRY the missile cooldown is not zeroed` (11.17 → 0.00), `CARRY the gatling heat is not zeroed` (11.9 → 0.0), the three OD rows and `the gate stops the saber, the charge, the spin, the paint and ADS` |
| **M4** the r7 `open_states` (no floor read) | `test_death` **107/108** | `a shoved corpse revives on the ground and Space hops again` (`floor=false state=jump`, no `jumped`) |
| **M5** the r7 `close_states` (no assault emission) | `test_death` **107/108** | `the death ends the flight jet on the bus exactly once` (`+0`) |
| **M6** the r7 `_die` (always announce) | `test_death` **107/108** | `an external hp write and its own announcement still fire once` (`player_died +2`) |
| **M7a** the LIVE loop's post-release OR removed | `test_death` **107/108** | `LIVE fire (mouse) acts` — the rifle's shot lands on the RELEASE, so the OR is load-bearing in the LIVE phase |
| **M7b** the DEAD loop's post-release OR removed (review item 4) | `test_death` **108/108** | **none** — see Known issues: no verb can act on its release while the gate is closed, so the DEAD-side OR cannot be falsified by any row |
| **M8** `MUT_mech_damage.diff` — `last_stand` fires on the killing blow too | `test_damage` **31/33** | `the killing blow asks nothing` and `a killing blow from 20 % plays nothing on a fresh cooldown` (`played=1`) |
| **M9** no weapon teardown at all (the gate leaves the guns as the killing blow found them) | `test_death` **106/108** | `a trigger held across the revive does not act` (`weapon_fired 20->21` — the stale release edge in `WeaponSystem._fire_held` fires the charged shot on the first live tick) and `the gate stops the saber, the charge, the spin, the paint and ADS` (`spin=ON paint=ON` survive) |
- **The slump, in numbers** (`test_death.gd` `DEAD the corpse is a kneeling slump, not a standing mech`):
  the `cockpit` socket sits at **8.4 m** above the model origin 0.5 s after the blow and settles to
  **6.7 m**, against **13.1 m** standing — the same 6.4–7.1 m band the windowed probe's `POSE` lines
  print. It is a kneeling slump: torso pitched forward on its knees, not a mech lying flat and not a
  mech standing.
- `test_damage.gd` last stand: **12/12** with the director instanced, `reset_rate_limits()` before each
  half, and the killing-blow row on a fresh cooldown (the row M8 turns red).

### r7 (the death gate)
**Test host: `317d03c`** (tooling r1 item 3, the stricter host), named beside every pair below.
**Model under the POSE table: hero3 at `742876f`**, with these hero-v3 r8 files dirty in the tree at
the time of the run (r16 B6): `hero3_glow.gd`, `hero3_glow.gdshader`, `hero3_shell.gdshader`,
`tests/hero3_look.gd` modified; `hero3_surface.gd`, `tests/hero3_bonemask.gdshader`,
`tests/probe_panel.gd` untracked.

- `tools/godot.sh check` (whole project): **766 files, 0 failed, 0 engine errors, 0 warnings**;
  `check --only=res://player/mech/`: **28 files, 0 failed**. No file in the unit is over 400 lines
  (`mech_locomotion.gd` 396, `player_mech.gd` 366, `test_death.gd` 299).
- `test_death.gd`: **34/71 on `5aea16b` (pre-fix), 71/71 on `ffeb6bc`.** The FAIL run was made by
  copying my files aside and `git show 5aea16b:<path> > <path>` for `player_mech.gd`, `mech_input.gd`,
  `mech_locomotion.gd` and `tests/mech_test_base.gd`, with the three new modules moved out of `game/`
  (they would not compile against the pre-split `PlayerMech`). Log: `tmp/mech-move/test_death_HEAD.log`.
  The 37 that flip include `DEAD move_forward does nothing`, `DEAD jump/boost/melee/weapon_next/lock_on
  do nothing`, all five `can_cancel` rows, `every component stopped polling input`, `a trigger held
  then released fires nothing`, all six `death at weight 1` pose rows and the two revive-latch rows.
- **The live baseline is 16 verbs, every one of them proven to act first** (r16 Round 2): `move_forward`,
  `jump`, `boost`, `assault`, `fire` (LMB), `melee`, `guard`, `anchor`, `missiles` as **both `1` and
  MOUSE4**, `weapon_next`/`weapon_prev` (the **wheel**), `lock_on` as **both Tab and MMB**,
  `overdrive` (**V held 0.25 s**), and `melee` held while **falling from 160 m** (the plunge). A
  `Targetable` on a fake actor is in the test scene so `lock_changed` can fire while alive.
- **The death probe, windowed, on `main.tscn` at the district checkpoint — 0 checks failed**
  (`tmp/mech-move/death_fixed.log`, 44.5 s). HEAD numbers from the same probe on the same build
  (`tmp/mech-move/death_head.log`):

| probe line | HEAD (5aea16b) | fixed (c0ee30e) |
|---|---|---|
| `WHILE DEAD W 1.0 s` | moved **13.2 m**, states `["idle","run"]` | moved **0.0 m**, states `["idle"]`, **footsteps 0** |
| `WHILE DEAD LMB tap` | **1 shot** | **0 shots** |
| `WHILE DEAD F tap` | `melee_swing x1` | `melee_swing x0` |
| `WHILE DEAD Shift tap` | `boost_started x1`, moved **35.9 m** | `boost_started x0`, moved **0.0 m** |
| `HELD W THROUGH DEATH` | **19.2 m** in 1.2 s | **0.0 m** |
| `POSE dead_*` (7 lines) | `clip=death w=1.00` at death, then `fire_r`, `melee_l1`, `dash_f`, `land_light` with **cockpit_h 13.1** (standing) | **every line `clip=death weight=1.00`, cockpit_h 6.4–7.1** (13.1 standing) |
| `POSE hop_dead_landed` | `action=land_light clip= w=0.00 cockpit_h=13.1` — **it stood up on landing** | `clip=death weight=1.00 cockpit_h=7.0` |
| `POSE flight_dead_landed` | (cycle not reached: the session was cut) | `clip=death weight=1.00 cockpit_h=6.7` |
| `controls_after_retry` | PASS (19.0 m, 3 shots) | PASS (18.8 m, 3 shots) |

  The probe also prints the InputMap: `ui_accept = [Enter, Kp Enter, Space]`, `move_forward = [W …]`,
  `fire = [Left Mouse Button]` — so Space really is both RETRY and `jump`. `test_death.gd` holds
  **Space itself** across a death and a revive: no `jumped` fires while it is held, and a fresh press
  hops again, so the RETRY key is neither acted on nor eaten for good.
- **The same probe with `--stub=hud` — 0 checks failed** (`tmp/mech-move/death_stub.log`, 37.2 s,
  11 checks, `menus=false`). This is the r16 Round 2 arm that cannot be masked by hud r6's GAME_OVER
  pause; with no page the revive is the same three calls `flow_progress.gd` `_restore_player` makes.
- `test_last_stand.gd`: **9/12**. Green (ours): the threshold is `MechTuning.od_low_hp` 0.150; a
  crossing hit asks **once**; a hit that stays above 15 %, a hit that starts below it, the killing
  blow (`alive=false`) and god mode all ask **nothing**. **Red until feel r5** (expected, r16 B5):
  `fx/events/last_stand.tres is loaded`, `the director plays the row` (0 plays) and
  `time_scale is 0.5x from 0.1 s to 1.3 s` (`1.000..1.000`). `time_scale back to 1.0 by 1.6 s`, the
  60 s cooldown and `a killing blow from 20 % plays nothing` already pass.
- Regression, all under host `317d03c`: `test_locomotion` **56/56**, `test_damage` **21/21**,
  `test_stepping` **17/17**, `test_clocks` **9/9**, `test_flight_input` **16/16**.
- `test_no_abs_paths.gd`: **2 445 files scanned, 0 absolute home paths** (the probe takes its capture
  directory from `--outdir` and its prefix from `--out`, both passed by `tools/godot.sh`).
- **Capture sheet: `captures/mech-move_death_sheet.jpg`** (1 840×843, three rows). Row 1 is HEAD, rows
  2–3 are the fix, same probe, same camera:
  - HEAD `d3_fired_closeup` and `d6_hop_dead_closeup` show the mech **standing upright**;
  - every fixed close-up (`d1` dead, `d3` after LMB, `d4` after F + Shift, `d5` the held-W death,
    `d6` the hop landing, `d7` the flight landing) shows the **kneeling slump** — the `cockpit` socket
    at 6.4–7.1 m against 13.1 m standing, which is the number `test_death.gd` now measures headless;
  - `d8_standing_after_retry` shows it standing with the HUD back — the revive works;
  - `d2_walked_page` is the MECH DESTROYED page after 1.0 s of W: the world behind it has not panned,
    because the corpse moved 0.0 m.
  The individual frames are `captures/mech-move_death_*.jpg` (11) and the HEAD set is
  `captures/mech-move_death_head_*.jpg` (10).

### r6 (flight)
- `tools/godot.sh check` (whole project): **704 files, 0 failed, 0 engine errors, 0 warnings**;
  `check --only=res://player/`: **114 files, 0 failed**. No file in the unit is over 600 lines
  (largest: `player_mech.gd` 493, `mech_locomotion.gd` 396, `test_locomotion.gd` 366).
- `test_flight_input.gd`: **16/16** — every check through `Input.parse_input_event`. Ground tap-tap
  at the trailer's 0.22 s gap **2 ticks**; a 58 ms tap-tap inside the knee-dip **2 ticks**; falling
  **2**; hovering **2**; boost slide **2**; assault boost **2**; dash **2**; a double tap in flight
  exits in **2 ticks** into `glide`; a single tap jumps 4.1 m and does not fly; holding jump reads
  `hover` and does not fly; an Outage blocks the toggle; an empty gauge drops the mech into `glide`.
  Before the fix the same suite scored **8/14**.
- Regression: `test_locomotion` **56/56**, `test_damage` **21/21**, `test_stepping` **17/17**,
  `test_clocks` **9/9** (its slow-mo `_double_tap_flies(0.26)` case still passes).
- **The trailer's take, unmodified**: `tools/trailer/record.sh … tl_s06_flight.json` with the
  `shots.json` flags — `flying=true` from **t 0.746 s** (26 ms after the second tap) to t 2.9 s,
  `move_state=fly`, 50 m/s, EN 1000 → 858. Log: `tmp/mech-move/s06_rec.csv`. `drive` and `movie`
  agree frame for frame. Re-run after the fix (`tmp/mech-move/s06_fixed.csv`): still `fly` from
  0.75 s and now holds it to t 3.1 s, **0 errors**. (`tmp/` is scratch: the CSVs are on disk
  until the next clean-up, the numbers above are the record.)
- **Flight film strip** (`player/mech/timelines/flight.json`, sandbox, **11.5 s, 0 errors,
  0 warnings**): `idle` → tap-tap at 0.5/0.75 → `fly` from t 0.8 → climb (jump held) to **y 63.8 =
  +56 m** at 50 m/s → bank (`look [-900, 0]`) → `assault` toggle → **83.9 m/s** at 120 EN/s →
  toggle off → `descend` → −24 m/s → **soft landing** at t 9.0 (`land_kind=soft`), EN 293 left.
  Captures: `captures/mech-move_flight_t{0_9,2_2,3_6,4_9,5_9,7_4,8_8,10_2,11_2}.jpg`.
  Movie: `captures/mech-move_flight.avi` — **691 frames at 60 fps, 11.5 s, 1600×900, exit 0,
  0 ERROR lines** (`ffprobe -count_frames`).
- The HUD's EN gauge (the reticle arc, `ui/widgets/reticle.gd:57`) visibly drains across the strip —
  compare `t0_9` (full) with `t5_9` (about two thirds).

### earlier rounds
- `check --only=res://player/`: **62 files, 0 failed, 0 engine errors, 0 warnings**.
- `test_locomotion.gd`: **56/56** — adds the facing regression (right/left/back all `dot = 1.000`,
  forward dash labelled `dash_f`; the old expression scores −1.000 / `dash_b`) and
  `reset_dash_chain`. Run 16 m/s, dash 24 m / 110 EN / exactly 12 i-frame ticks, chain 1-2-3 then
  lockout, hop apex 8.16 m soft, ascend 100 EN/s at 18 m/s, hover 40 EN/s, dive 45 m/s, flight
  50 m/s at 80 EN/s, assault carve −39.7°/s at 84 m/s, 3 s of boost still a 42 m/s skate, assault
  toggle from boost and from standstill, skid brake exits, regen 500/s after 0.6 s, Outage 1.5 s
  then +250, 40 m deck drop = hard landing at 45.2 m/s, 19° ramp +20.5 m.
- `test_damage.gd`: **13/13** — a hit-stop never freezes a player-started boost (6.30 m covered
  during a 0.15 s stop), a lunge is frozen and creeps **0.83 m** instead of 16.5 m, a touchdown
  inside the stop is not dropped (`land_kind=hard`, on the floor), a tap buffered during the stop
  still fires when the lock ends, `hit_pause` reaches the model (spy), damage filter blocks, perfect
  dodge 0 damage + OD.
- `test_stepping.gd`: **17/17** — adds the assault vault: hops the 6 m block, clears it with **no
  landing recovery** and the jet survives (`assault/true`).
- `test_clocks.gd`: **9/9** — adds the EN clock: a 0.15 s global hit-stop during the 100 EN/s ascend
  costs **1.58 EN** instead of 15.
- `drive` tour (real rig): **45.0 s, 0 errors, 0 warnings** — run 16 → dash chain ×3 → 42 m/s skate
  → assault 84 m/s → dash back and skate north → teleport → hover 18 m/s west + dash-glide → soft
  touchdown on deck_west → turn east, hop off the deck, double tap → flight 50 m/s climbing to y 105
  → double tap out → 50 m/s terminal dive → hard landing at y 7.5 → dash out and run → teleport →
  boost skate into the 6 m `runway_wall`: `hop_events=1`, vaults it at z −354 and lands the far side.
- Captures: `captures/mech-move_r4_t{1_5,4_7,6_5,8_0,16_5,19_6,24_5,29_6,37_6}.jpg`.
- Movie: `captures/mech-move_tour.avi` — **2 702 frames at 60 fps, 45 s, 1600×900, 0 errors**
  (`ffprobe -count_frames`). Frame at t 12.8 s shows the mech turned to face the camera while it
  skates backwards — the turn the old sign got wrong.
- Scripted fight with `--nan-watch` (36 s, `ripper:6, mantis:2, juggernaut:1`): **0 NANWATCH
  lines**, 14 perfect dodges, 11 hits taken, 1 kill, player alive at hp 6 790. All 14 logged errors
  are the audio router's (see Request 2), none from the mech.

## Tuning choices beyond SPEC (all named fields in `mech_tuning.gd`)
| Field | Value | Why |
|---|---|---|
| `rise_gravity` / `jump_speed()` | 79.0 m/s² / 35.56 m/s | derived from SPEC's "hop to +8 m at 0.45 s"; falling uses the specified 25.5 |
| `dash_ease` | 1.0 | 150 → 42 over 0.25 s integrates to exactly 24 m only on a linear ramp |
| `dash_chain_window` | 0.50 s | chain lapses this long after a dash; `dash_reload` 0.38 s is measured from the dash start |
| `assault_brake` | 0.25 s | SPEC §4 skid brake: stick held against the jet this long drops the assault boost |
| `input_buffer` | 0.30 s | **new (audit [3])**: how long a press latched during a hit-stop stays buffered |
| `hover_reserve` | 60 EN | below this the mech hovers (40 EN/s) instead of ascending (100 EN/s) |
| `flight_boost_cost` | 120 EN/s | the flight assault boost costs the assault rate |
| `glide_fall_scale` / `glide_sink_cap` | 0.35 / 12 m/s | unpowered glide after EN runs out |
| `land_min_impact` | 5 m/s | below this a floor contact is a kerb, not a landing |
| `land_pose_time` | 0.18 s | how long the landing dip is drawn by the model |
| `strafe_turn_rate_deg` | 180 | aiming mode keeps the legs at walking turn speed |
| `lunge_arrive` / `lunge_turn_rate_deg` | 3 m / 240°/s | arrival radius; 120°/s only covers 84° in a 0.7 s lunge |
| `invuln_blink` | 0.12 s | mercy window after a heavy hit (≥ 600 dmg) only |
| `assault_accel_time` | 0.25 s | 42 → 84 spin-up |
| `safe_margin` | 0.01 | Godot's 0.001 default is too tight for a 3.5 m capsule |
| `step_probe` | 0.40 m | the step-up must fire *before* `move_and_slide` eats the velocity |
| `step_coast_min` | 0.05 s | **new (r8)**: the floor under the coast's duration, so a standstill crawl into a kerb still gets a coast rather than a teleport. The duration is otherwise `run-up / speed`, which is the mech's own speed — nothing to tune |
| `step_ease_ratio` | 0.26 | **new (r8)**: metres of model lag given back per metre travelled — the 2 m rise over 8 m of road, inside the 12 m sandbox kerb at every speed. Distance and not time, so a walk and a boost put the feet back under the hips after the same stretch of road |
| `step_ease_speed` | 1.2 m/s | **new (r8)**: the time floor under that ratio, so a mech that stops dead on a kerb still gives the lag back instead of holding it for the rest of the round |
| `hop_min_speed` | 12 m/s | under this the step-up alone carries the mech over |
| `hop_max_impulse` | 45 m/s | above this the mech is too close to clear it: it takes the wall |
| `hop_cooldown` | 0.60 s | one hop per obstacle, not one per frame; it also marks the vault window |

Clock-domain choices (all named in code):
- **real** (`Feel.locomotion_delta` / `Feel.real_delta`): every velocity integration, the dash jet,
  the vernier hang, the assault ignition, the hop cooldown, the lunge timer, jump buffer / coyote /
  knee-dip, the skid timer, the double-tap window, the input buffer, footsteps.
- **player** (`Feel.player_delta`): dash lockout / reload / chain window, landing recovery + cancel
  window + landing pose, combat `lock_movement`, the local hit-stop, `_invuln_t`, **EN/OD and every
  per-second EN cost (audit [7])**, dash i-frames.
- i-frames compare with half a tick of slack so the window is exactly 12 ticks at 120 Hz.
- A local hit-stop (`PlayerMech.FROZEN_CREEP` 0.05) is honoured only in LOCKED/LUNGE; `Feel.local_hit_stop`
  cannot tell attacker from victim, so the player always creeps at 5 % rather than standing still.

Stepping implementation note: the obstacle is measured with **rays**, not a capsule sweep. With a
3.5 m capsule the up → forward → down `test_move` recipe reports the kerb's top *edge* (normal ~60°
off vertical, never walkable), so the shim never fired; the rays give the face position and the top
height and `test_move` is still used to verify headroom and the forward move.

## Known issues
- **r7b**: the DEAD loop's post-release OR (review item 4) is a correctness fix the suite cannot
  falsify — mutation **M7b** reverts it and `test_death` stays **108/108**. No verb can act on its
  release while the gate is closed, so the DEAD rows are blind to it either way. The LIVE loop's OR is
  the load-bearing one: **M7a** reverts it and `LIVE fire (mouse) acts` goes red, because the rifle's
  shot lands on the release.
- **r7b**: `end_overdrive()` also opens the skill's 3 s **aftermath** window (`skills-catalog` §4.5:
  −50 % EN regen), so a death inside an Overdrive leaves that on the revive. It is carry-over, not a
  free Overdrive — the meter is 0 and V starts nothing — but it is skills' number, not mine;
  Request 16 asks skills to fold the window into `on_player_died()`.
- **r7b**: the latch mutes an action at the `Input` level, so a component that reads the RAW device
  (`Input.is_mouse_button_pressed`) instead of the action would not see it. Nothing in the five
  components does; `test_death.gd` asserts `ctx.ads` stays false with RMB held.
- **r7**: the revive latch (r16 B8) means a key held across the death page does not act until it is
  released. This is the conflict-map row winning over the r7 review's "W held through RETRY walks
  normally"; see Request 10 in case a flow case depends on the old reading. **r7b narrows it to the
  held action only** — every other verb acts on the first live tick.
- **r7**: a corpse's horizontal speed is zeroed at the latch rather than braked. On the ground brake
  curve a mech killed at 16 m/s still slid **1.3 m** (measured), which is over the review's 0.5 m
  gate; the knockback is applied after the zero, so the killing blow still carries the wreck.
- A jump press that is *itself* inside the double-tap window toggles flight — that is the SPEC §3
  behaviour, but it means a timeline that taps jump and then presses jump again within 0.30 s to
  climb will switch flight back off. `player/mech/timelines/flight.json` therefore waits 0.55 s
  between the second tap and the climb press; worth knowing when writing shot timelines.
- The rig's auto-framing puts the arm at 46 m standing (SPEC §5 says 28 m), so the hero reads small
  in the third-person captures (Request 1). Movement, yaw and look all behave.
- The hero model's `land_heavy` pose reads as a prone knockdown in the t29.6 capture. The mech side
  only sends `set_locomotion(&"land_heavy", …)`; the pose itself is the hero/animation unit's.
- Coasting out of a dash straight into a 6 m block does not auto-hop: the dash is a committed 24 m
  jet and the hop is a boost-slide move. By design.
- `mech_tuning.tres` carries no overrides (it exists so feel can be retuned without touching code);
  every number lives in `mech_tuning.gd`.
- A vault touchdown emits no `Events.landed` and no landing feel at all (it is a boost continuation,
  not a landing). If feel wants a scrape/whoosh there, it needs a new id.

## Requests (to the lead / other units)
1. **camera-aim / lead**: the rig's `camera_framing.gd` solves the arm to **46.0 m** standing against
   SPEC §5's 28 m arm / 32 boost / 36 assault, so the hero reads small in every third-person capture.
   Please confirm the intended framing (the mech side is unchanged: capsule 15 m, model 15.2 m).
2. **audio / lead**: `Events.perfect_dodge` (1 arg, `core/events.gd:13`) is bound through
   `AudioEventMap.SIMPLE_SIGNALS` to `event_router.on_simple(id)` (`game/audio/audio.gd:107`), which
   takes no further arguments — **every perfect dodge logs
   `Error calling from signal 'perfect_dodge' … expected 1 argument(s), but called with 2`** (14 of
   them in one 36 s fight). The signal emission is contract-correct; the binding needs a
   `func(_a: Node)` adapter. Other parameterised signals in `SIMPLE_SIGNALS` are probably affected.
3. **hero / animation**: the `land_heavy` locomotion id plays a prone pose (capture
   `mech-move_r4_t29_6.jpg`); SPEC §10 reads as a heavy crouch. Flagging, not blocking.
4. **docs**: SPEC §10's locomotion id list has no `coast`; it is emitted while the mech is still moving
   with no stick. `telemetry()` gained `land_kind`, `step_events`, `hop_events`, `assault` — worth a
   line in CONTRACTS §5. CONTRACTS §5 now also lists `reset_dash_chain()` (implemented here).
5. **lead**: `Feel.local_hit_stop(actors, seconds)` cannot distinguish attacker from victim, so
   FEEL.md's "victim frozen, attacker at 5 %" cannot be expressed per role. The mech creeps at 5 %
   in both roles; a role flag (or `hit_pause(seconds, creep)`) would fix it at the core level.
6. **camera-aim / trailer — the rig loses a flying mech.** In `tl_s06_flight.json` the hero is in
   `fly` from t 0.75 to t 2.9 (telemetry `tmp/mech-move/s06_rec.csv`), but the shot's cut (in 1.2 /
   out 3.06) shows city with no mech in frame from about t 1.6 — `captures/trailer/shots/s06_flight.avi`
   at 1.8 s. The `look_rate [0, -70]` at 2.0 s pitches the view off the hero and the arm never re-acquires it. A flying mech leaves
   the ground plane fast (50 m/s, +20 m/s climb), so the follow probably needs a vertical dead-zone or a
   speed-scaled arm; the mech side offers `is_flying()` and `telemetry()["flying"]`.
7. **hud — no flight cue.** `hud_state()` already carries `state` (`&"fly"` while flying) and
   `ui/hud_data.gd` merges it, but **no widget reads it** (`grep -rn '"fly"' game/ui` finds only
   `hero3_air.gd` and the placeholder model). The EN drain does read on screen — the reticle arc
   (`ui/widgets/reticle.gd:57`) shrinks visibly across `captures/mech-move_flight_t0_9.jpg` →
   `t5_9.jpg` — so only the state itself is missing. A "FLIGHT" tell (reticle ring, a chevron on the
   compass, or the existing `callouts` widget) would make the mode legible in a trailer cut. Frame:
   `captures/mech-move_flight_t3_6.jpg`.
8. **trailer — how to film flight.** `tl_s06_flight.json` with its `shots.json` flags
   (`--skip-menu --god --tod=0.6 --stub=flow --spawn=-200,39.5,-260,180 --enemies=harrier:3`) does
   enter flight; re-record it as is. If you want the flight to *read*, the beats that work in
   `player/mech/timelines/flight.json` are: tap jump, tap jump again **0.20–0.28 s later**, then
   **wait at least 0.35 s** before pressing jump again to climb (a third press inside the 0.30 s
   window toggles flight back OFF), hold it to climb at 20 m/s, `tap assault` for the 84 m/s jet,
   hold `descend` to come down. Do not hold `boost` across the taps — with boost held the pair is
   read as a slide, and while that now flies too (r6) the mech keeps the ground-skate pose for a
   beat. Cut the shot between the second tap and the landing, and keep `look_rate` at 0 while the
   mech is airborne.

### r7 (numbered from 9, as the brief asks)
9. **feel — `fx/events/last_stand.tres` and the FEEL.md row** (lead decision, r16 B5): `slow_scale`
   0.5, `slow_seconds` 1.5, `cooldown` 60, `slow_witch` **false** (true would light the
   perfect-dodge tint, `screen_fx.gd:72`). Until it lands, `test_last_stand.gd` is **9/12** — the
   three red rows are `fx/events/last_stand.tres is loaded`, `the director plays the row on a
   crossing hit` and `time_scale is 0.5x from 0.1 s to 1.3 s real`. The `Feel.play(&"last_stand")`
   call is already wired on the mech side; nothing else is waiting on me. When it lands, fold the
   director checks into `test_damage.gd` and the suite goes 12/12 unchanged.
10. **flow — the revive latch changes one behaviour you may be testing.** r16 B8 (which overrides the
   r7 review's "W held through RETRY walks normally"): **every action held at the instant the death
   gate re-opens is ignored until it is released.** A key the player never let go of across the death
   page therefore does not act on the first live tick — including W. If any flow E2E case holds a key
   across a respawn and expects it to keep working, it must release and re-press. `set(hp)` + `heal()`
   is still a full revive (r16 B2) and my test mirrors your **commit `5129b4c`** verbatim, not your
   working copy. Please post each further change to `_restore_player`.
11. **skills — the anchor line and the ward on death** (r16 B4). My gate reaches SkillSystem through
   `set_physics_process(false)` + `SkillSystem.reset()`, which clears `_od_active`, the buffs and
   every skill's own `reset()` — so `skill_used`, `overdrive_changed` and `ultimate_fired` are all 0
   while dead and the anchor/ward state machines stop. What I cannot verify from here is that the
   **anchor line VFX** and the **ward dome** are actually torn down by `SkyhookAnchor.reset()` and
   `CoronaWard.reset()`; that is skills r4 item 6's "release the anchor line and the ward on death".
   `test_death.gd` therefore has no row for those two and I have marked it in the file. Also r16 B3:
   the buffered skill press is covered — `test_death.gd` presses `anchor` **while dead** and after the
   revive it produces nothing.
12. **hud — the GAME_OVER pause.** All three r16 Round 2 arms are in place: the headless
   `test_death.gd` (no HUD at all), the `--stub=hud` drive (0 checks failed) and a windowed drive run
   **before** your pause lands (0 checks failed). Please ping when `menu_root.gd:96` pauses the tree
   and I will re-run the windowed probe. One thing you will want to know: with the tree paused,
   `_physics_process` does not run, so the mech's poll history is stale at the revive — that is
   exactly what the r16 B8 latch is for, and it is already in.
13. **lead / core — `InputMap action "debug_toggle" doesn't exist`** is logged as an engine ERROR by
   `tools/godot.sh check` on the **whole project** (`core/input_quad.gd:55` reads it;
   `core/input_setup.gd:44` registers it, so the quad is asking before `register_actions` has run).
   It is not mine (`check --only=res://player/mech/` is 0 engine errors) and it predates r7 — flagging
   it because the stricter host (`317d03c`) will fail any suite that boots it.
14. **tooling — two new suites** (r16 A3, `tools/suites.sh`):
    `res://player/mech/tests/test_death.gd` (flags `-- --timeout=900`, expected **green**) and
    `res://player/mech/tests/test_last_stand.gd` (flags `-- --timeout=600`, expected **RED at 9/12**
    until feel r5 lands `fx/events/last_stand.tres` — please allow-list it the way weapons'
    `test_feel_rows.gd` is handled). Neither logs a deliberate `push_error`. Both are new files as of
    commit `c0ee30e`.
15. **weapons / melee-defense — no hook Request is needed.** The pipeline reaches all five components
    through `set_physics_process(false)` plus the `reset()` each of you already ships
    (`weapon_system.gd:202`, `melee_system.gd:427`, `defense_system.gd:431`, `skill_system.gd:421`).
    `test_death.gd` proves it end to end: 0 `weapon_fired`, 0 `melee_swing`, 0 `skill_used`,
    0 `missiles_locked`, 0 `weapon_switched`, 0 `lock_changed`, 0 `overdrive_changed`, the guard down
    and the gatling/rifle/launcher all reset. **One caveat for weapons r5:** `WeaponSystem.reset()`
    does not clear `ctx.ads` or `ctx.strafe_aim`; both self-correct on the first live tick
    (`_strafe()` recomputes `want` and `ctx.ads` is assigned every tick), so I did not need a change —
    but if you refactor `_strafe`, that is the assumption my gate rests on.


### r8 (numbered from 21, as the brief asks)
21. **tooling / lead — two rows for `tools/suites.txt`.** `res://player/mech/tests/test_step_coast.gd`
    is new (r8 item 1, **36 checks**, green, `--timeout=600` is plenty — the run takes ~25 s):
    `mech_step_coast|res://player/mech/tests/test_step_coast.gd|--timeout=600`.
    `res://player/mech/tests/test_platform.gd` is new too (r8 item 2, **5 checks**, green, ~10 s) and
    is **UNLISTED** as well: `mech_platform|res://player/mech/tests/test_platform.gd|--timeout=600`.
    `test_death.gd` is still unlisted (Request 20). `mech_coast.gd` and `mech_ground.gd` are not
    suites, so the `test_*.gd` scanner will not pick them up.
22. **hero-v3 — `probe_float.gd --nofix` still works; no change needed.** The r8 model lag writes
    `PlayerMech/Model.position.y` while a kerb climb is unwinding, so it could have stomped your
    `_nofix` line. It does not: the lag captures the node's rest offset on the **first physics frame**,
    and `_nofix` sets `model.position.y = 0.0` in `_ready` (before that frame), so 0.0 is what it
    offsets from. Verified — `tools/godot.sh test res://player/model/hero3/tests/probe_float.gd --
    --case=walk_kerb --nofix=1` still prints `FLOAT setup: world=sandbox BEFORE (--nofix) … sole trim
    L 0.000 R 0.000` and the BEFORE row `near 0 % above +7.57 below +5.86`, i.e. the whole model back
    on the body origin. Nothing for you to change; it is on the record so the BEFORE column is not a
    surprise when you re-run the table.
23. **lead — SPEC §4 "Stepping" describes the step-up as instantaneous; it is now a coast.** The
    observable change is that a kerb is climbed over `run-up / speed` seconds (0.47 s at a walk,
    0.27 s at a run) instead of in one tick, at **exactly the mech's own speed**, so no number in
    SPEC §4 changes: no stall, no lost speed, no landing, no state change, `step_height` still 2.5 m
    and the auto-hop still 7 m. What is new is `MechLocomotion.step_lag` (a model-only offset, in
    `telemetry()`-adjacent state but not in `telemetry()` itself) and the tuning fields in the table
    above. Worth a line in SPEC §4 if you want the coast written down.

### r7b (numbered from 16)
16. **skills — fold the Overdrive teardown into `on_player_died()`.** Your r4 hook is exactly right and
    I call it at the latch (`MechTeardown._skills`), but it releases the anchor line and the ward and
    nothing else, so a death inside an Overdrive needed `end_overdrive()` from my side as well. That
    works (the meter drops to 0, `overdrive_changed(false)` fires once, the model is told, V starts
    nothing after the revive — `test_death.gd` `_phase_overdrive_death`), but it leaves the 3 s
    **aftermath** window running on the revive, which is your number. If `on_player_died()` ended the
    window itself (and skipped the aftermath), my adapter would only have to call the one hook. I do
    NOT call `SkillSystem.reset()` at a death any more: it restores every charge, and the lead ruled
    carry-over in and refilling out.
17. **weapons — a `stop_volley()` (or `holster()`) hook on `WeaponSystem`, please.** The death gate
    must stop what is running without refilling, and `WeaponSystem.reset()` does both: it reloads the
    magazine and the belt, zeroes the heat and the missile cooldown and sets `current = RIFLE`
    without emitting `weapon_switched` (`weapon_system.gd:202`). I ship a local adapter
    (`player/mech/mech_teardown.gd`) that calls `rifle.cancel()`, `gatling.cancel()`, clears
    `hailstorm.painting` / `locks` / `_paint_time` / `_lock_timer` and sets `ctx.ads` and
    `ctx.strafe_aim` false — `HailstormLauncher` has no public cancel, so the gate writes those four
    fields itself. If you add `func stop_volley() -> void` that does exactly that (and nothing else),
    `MechTeardown` calls it in preference and the private-field writes go away. The CARRY gate in
    `test_death.gd` is what will tell you if it refills: it spends three rifle rounds, a salvo, a
    burst charge and the gatling's belt, swaps to the gatling, dies for 0.25 s and reads
    `rifle=6 gatling=226 burst=0 weapon=gatling` back unchanged.
18. **flow — your debug `die` command announces the death twice.** `flow_progress.gd` (and
    `test_boss_city`) write hp to 0 and emit `Events.player_died` themselves, and `MechDamage.sync()`
    announced it again on the next tick, so every listener ran twice. I have made the mech side emit
    **once per death** either way (`MechDamage._died_seen`, `test_death.gd` `_phase_died_once`), so
    nothing is broken — but the cleanest fix is on your side: write hp and let the pipeline announce
    it, or call `player.damage()` / `take_hit()` instead of emitting. Please post any change to the
    `die` command; my gate asserts exactly one `player_died` for an external hp write **and** that the
    next real death is announced again.
19. **lead — external drivers must go through `damage()` or `is_alive()`.** The r7 split moved `_dead`
    and `_invuln_t` out of `PlayerMech` into `MechDamage`, so a driver that reads or writes
    `player._dead` / `player._invuln_t` now silently touches nothing. The public surface is
    `PlayerMech.is_alive()` (the single predicate, r16 B3), `PlayerMech.take_hit(hit)`,
    `PlayerMech.heal(n)`, `PlayerMech.invulnerable_for(s)` and `PlayerMech.is_invulnerable()`. Your
    acceptance driver is the one I know of that pokes at the privates
    (`_dead_of(p)` in the probe base reads `damage().dead` behind a `has_method`, which is fine).
20. **tooling — the suite table (PARTLY LANDED, r8).** `test_death.gd` now **has** its row
    (`tools/suites.txt:18`, `mech_death|…|--timeout=1200`) — Request 14 is closed, and
    `tools/suites.sh --only=…mech_death` runs it green. `test_damage.gd` is listed and has **33
    checks** (21 + the 12 last-stand rows), green. `test_last_stand.gd` is gone (folded into
    `test_damage.gd`, r16 B5). What is still missing is Request 21 below: the two r8 suites.
    The three death files are not suites (`death_phases.gd`, `death_dead_phase.gd`,
    `mech_teardown.gd`), so the `test_*.gd` scanner will not pick them up.

## Captures needed (windowed — `MC_WINDOW_OK=1`, the lead runs these)
Everything in the Gates list of `reviews/mech-move-r7b.md` is headless and green above. These two are
the windowed arms the 11-05 dispatch note moved out of my reach, plus the sheet rebuild (item 10).
Both write only under `captures/` and `tmp/mech-move/`.

**r8 — one more, and it is the one worth looking at.** The kerb fix is a *visual* fix: the numbers say
the sole is on the floor, but only pixels say the climb reads as a 16 m mech stepping up rather than
sliding up. The sandbox kerb is at x −120, z ±6 (the same one every stepping gate uses); the tour
timeline already walks the mech over that lane.

```
# 0. r8: the kerb climb, windowed — walk onto the 2 m kerb, then off the far edge
tools/godot.sh drive --timeout=900 --sandbox \
  --timeline=res://player/mech/timelines/kerb.json --out=mech-move_kerb \
  --shots=2.2,2.5,2.8,3.1,3.4,3.7,4.0,4.4
```

`player/mech/timelines/kerb.json` is new and deliberately dull: teleport to (−120, 7.6, 40) — the
sandbox kerb lane every stepping gate uses — hold `move_forward` from 0.6 s to 6.0 s. At the 16 m/s
run the capsule meets the kerb face at about **t 2.7 s** and walks off the far edge at about
**t 3.5 s**, so the eight shots bracket the climb and the step down. **The shot times are calculated,
not measured** — I cannot open a window, so if the climb lands outside the strip, move the whole set
rather than the timeline; the beats are ~0.8 s apart and the coast itself is 0.27 s at this speed.

```
# 1. the death probe, windowed, at the district checkpoint — expect "0 checks failed"
tools/godot.sh drive --timeout=1500 --scene=res://player/mech/tests/death_probe.tscn \
  --timeline=res://player/mech/tests/death_probe_end.json --skip-menu --out=mech-move_death \
  | tee tmp/mech-move/death_fixed.log

# 2. the same probe with the menus out of the way (r16 Round 2) — expect "0 checks failed"
tools/godot.sh drive --timeout=1500 --scene=res://player/mech/tests/death_probe.tscn \
  --timeline=res://player/mech/tests/death_probe_end.json --skip-menu --stub=hud \
  --out=mech-move_death_stub | tee tmp/mech-move/death_stub.log

# 3. the capture sheet (item 10): d1_dead_page | d2_walked_page side by side, plus d2_walked_closeup
python3 - <<'SHEET'
from PIL import Image
root = "/Users/minimax/m/mecha-city/captures"
def load(n):
    return Image.open(f"{root}/mech-move_death_{n}.jpg")
pages = [load("d1_dead_page"), load("d2_walked_page")]
close = load("d2_walked_closeup")
w = max(i.width for i in pages)
h = max(i.height for i in pages)
pad = 8
wide = w * 2 + pad
close = close.resize((wide, round(close.height * wide / close.width)))
sheet = Image.new("RGB", (wide + pad * 2, h + close.height + pad * 3), (10, 10, 12))
for n, i in enumerate(pages):
    sheet.paste(i, (pad + n * (w + pad), pad))
sheet.paste(close, (pad, h + pad * 2))
sheet.save(f"{root}/mech-move_death_sheet.jpg", quality=88)
print("wrote", f"{root}/mech-move_death_sheet.jpg", sheet.size)
SHEET
```
What to look for, in order:
- **`VDEAD CHECK` lines**: every one `PASS` in both logs (`fails` is printed at the end of the run).
- **`POSE dead_*` lines**: `clip=death weight=1.00` with `cockpit_h` in the **6.4–8.5 m** band
  (13.1 standing). `test_death.gd` measures the same socket headless: 8.4 m at 0.5 s, 6.7 m settled.
- **`AFTER RETRY`**: `alive=true dead=false`, then `controls_after_retry` PASS (W 1.5 s > 3 m and
  LMB x3 > 0 shots). With the per-action latch the probe's ENTER tap is not a mech action, so nothing
  is muted and the controls come back on the first live tick.
- **The new behaviour to eyeball**: `d2_walked_page` (1.0 s of W under the MECH DESTROYED page) — the
  world behind the page must not pan; `d2_walked_closeup` — the kneeling slump, cockpit well below the
  standing 13.1 m.
- If `mc_window_ok` is not set the wrapper exits 3 without running anything, so a missing log is not a
  failure of the probe.
