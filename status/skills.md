# skills status

## Scope
`game/combat/skills/**` — SkillSystem component + S1 Rift Step, S2 Skyhook Anchor, S4 Corona Fins +
Corona Ward, S6 Shockcore Burst, S7 Undertow Well (+COLLAPSE), S8 Plunge Breaker, Zenith Overdrive →
Zenith Lance. Own tuning resource, own tests, own capture range and capture drivers.

---

# r5 — the Overdrive ends inside our own death hook (and pays no aftermath)

Reviewed against `reviews/skills-r5.md` plus the lead's correction (a death ends the Overdrive
WITHOUT the 3 s aftermath). Tree at the time of these runs: `b1beb5a9` + `2b651f1c`.

## Done

| # | fix | files |
|---|-----|-------|
| 1 | **`on_player_died()` owns the whole skills teardown.** It now closes a running Overdrive through the same path as `end_overdrive()`: the meter drops to 0 (the mech's own `set_overdrive_active(false)`), exactly one `overdrive_changed(false)` leaves, the vignette closes and the model is told. It also stops a lance beam mid-fire (`zenith.reset()`), next to the anchor line and the ward it already dropped — a corpse keeping a 3 s city-splitting beam was the same class of bug as the corpse keeping its grapple. It touches no charge, no cooldown and no EN. The hook is idempotent: SkillInput fires it on the first dead tick AND mech-move's gate calls it directly, and the second call changes nothing. | `skill_system.gd`, `overdrive_state.gd` |
| 2 | **A death pays no aftermath** (lead correction). `end_overdrive()` — the Lance finishing, the window running out — still charges the 3 s of halved EN regen and no dash: that is the price of SPENDING an Overdrive. `end_on_death()` closes the window and clears `_aftermath` instead, so a revived mech inherits neither the drain nor the dash lock. `end()` itself refuses to arm an aftermath while `PlayerMech.is_alive()` is false, so a beam that outlives its pilot cannot hand the penalty to the next life through that path either. | `overdrive_state.gd` |
| 3 | **Test.** New `tests/suite_death.gd` (14 checks, run last by `test_skills.gd`): die 1.25 s into the window with `on_player_died()` as the ONLY call — no gate, no `end_overdrive()`, no `reset()`. The rig's `set_overdrive_active` now mirrors `MechEnergy` exactly (repeat call is a no-op, closing zeroes the meter and emits once), so the event count means something. | `tests/suite_death.gd`, `tests/harness.gd`, `tests/rig_player.gd` |
| 4 | **Split** (own commit `2b651f1c`): `skill_system.gd` 479 → 376. The Overdrive window / meter / aftermath / EN multiplier moved to `overdrive_state.gd` (180); every public name on the system still answers from there. The MechTuning+grounded lookup that the dash refund and the regen rate each had a copy of is now `SkillContext.mech_tuning()` / `grounded()`. | `overdrive_state.gd`, `skill_system.gd`, `skill_context.gd` |

## How to verify (exact commands)

```
tools/godot.sh check --only=res://combat/skills/   # 61 files, 0 failed, 0 errors, 0 warnings
tools/godot.sh check                                # 844 files, 0 failed, 0 errors, 0 warnings
tools/suites.sh --only=skills,mech_death
#   mech_death  0  PASS mech-move death: 108/108 checks passed   0  0  ok
#   skills      0  TEST 289 checks, 0 failed                     0  0  ok
tools/suites.sh --only=melee,defense,weapons,flow_die_once,mech_damage,mech_clocks,hud,aim
#   8 rows, 8 green, 0 known, 0 red
```

## Evidence

Headless only (the lead runs the windowed gates). Logs in `tmp/skills/`.

| run | what was reverted | result |
|-----|-------------------|--------|
| `r5_FAIL.log` | `on_player_died()` back to the r4 body (anchor + ward only) | **TEST 289 checks, 8 failed** — `death.overdrive_closed active=true od=100.0`, `death.meter_is_zero the meter reads 100.0 on the corpse`, `death.one_overdrive_changed_false 0 false / 0 true`, `death.model_told`, `death.hook_is_idempotent`, `death.v_while_dead_does_not_ignite`, `death.revive_carries_no_aftermath`, `death.mech_is_back` |
| `r5_FAIL_aftermath.log` | the death hook closes the window but arms the aftermath (the pre-correction behaviour) | **TEST 289 checks, 5 failed** — `death.no_aftermath the corpse carries a 3.00 s aftermath`, `death.revive_carries_no_aftermath aftermath=1.91, dashes_blocked=true`, `death.revive_drains_no_energy got 725.000 want 850.000` (125 EN drained in the 0.5 s after the revive), `death.hook_is_idempotent`, and — because that crude patch armed an aftermath on EVERY death — `input.dead_mech_spends_no_energy got 259.500`, i.e. a corpse's gauge draining is exactly what the r4 suite already forbade |
| `r5_PASS.log` | — | **TEST 289 checks, 0 failed, TEST ERRORS 0, exit 0** |

The r4 numbers still hold: 275 checks before this round, 289 now (14 new), 0 failed either way.

`mech_death` is the other half of the proof: mech-move's gate still calls `on_player_died()` and then
`end_overdrive()` only `if is_overdrive_active()` — which is now always false after the hook, so the
gate's own call is dead code (see Request 8) and the run still reports exactly one
`overdrive_changed(false)` and a 0 meter.

## Known issues
- Unchanged from r4 (the SKACC driver's sensitivity to a busy machine; the Lance reading best
  broadside; `fins.hero3_*` depending on hero-v3's tree compiling).
- `tests/skills_accept.gd` (the windowed driver) is ~630 lines — a capture driver, not shipped logic.

## Requests (to the lead / other units) — r5

8. **mech-move — the r5 handover.** `MechTeardown._skills()` (`player/mech/mech_teardown.gd:35`) can
   now be one line. `SkillSystem.on_player_died()` owns the whole skills teardown: the anchor line,
   the ward, a lance beam mid-fire AND the Overdrive window (meter 0, exactly one
   `overdrive_changed(false)`, the model told) — with no aftermath, which is the lead's ruling. So:
   - drop the `if sk.has_method(&"is_overdrive_active") … sk.call(&"end_overdrive")` block: it is
     dead code now (the hook already closed the window) and it is the only reason the gate still
     reaches into our state;
   - while you are in that file, `MechTeardown._weapons()`'s fallback branch writes
     `ctx.ads` / `ctx.strafe_aim` and `_cancel`s three private weapon nodes. weapons r7 landed
     `WeaponSystem.stop_volley()` (6c774d96), so the `if ws.has_method(&"stop_volley")` branch is
     the live one and the private-field writes below it never run — delete them.
   `test_death` 108/108 passes either way; nothing in skills depends on the gate's second call.
9. Everything from r4 stands (hero-v3 note, tooling suite row — now `skills` expects **289** checks —
   audio `timeline_reel.json`, trailer `tl_c_od.json`, flow tutorial prompt, monster-assets
   `'slash_1'`).

---

# r4 — every skill fires on the first press and reads on screen

Reviewed against `reviews/skills-r4.md`, `reviews/r16-lead-decisions.md` ("Shared", "Shared
(addition)", "skills r4" ×3) and `reviews/r16-conflicts.md` (C1, B3, B4, A1, A7).

**Tree at the time of these runs:** `93ccb69` (hero-v3 r8 items 1+2). hero-v3's
`player/model/hero3/**` was DIRTY (uncommitted `hero3_model.gd`, `hero3_rig.gd`, `hero3_gait.gd`,
`hero3_air.gd`, new `hero3_flight.gd`) during several runs below; every skills check that touches it
names that.

## Done — the six items

| # | fix | files |
|---|-----|-------|
| 1 | **Rift Step fires on the press edge.** `_rift()`'s 4-frame L3+R3 chord wait and its `lock_on` cancel are gone (that layout died in 37e66d6; Rift is C / RB+B and the chord lives in `core/pad_input.gd`). One shared 6 f real-clock buffer (SPEC §3) now serves rift, anchor, burst and well: the press fires immediately, and a press `can_act()` refuses waits in the buffer and fires on the first allowed tick. `od_chord` deleted from the tuning (its only reader). | `skill_input.gd`, `tuning/skill_tuning.gd` |
| 2 | **The Undertow Well honours the lock.** With a hard or soft lock the core lands on the locked actor's GROUND position (the reticle ray runs metres off a locked target — camera-aim's, not ours). With no lock it goes to the aim point, and a core that meets a body arms on the deck under that body instead of flying through it. `detonate()` spends primes with `StatusComponent.clear_prime()` so the HUD plate hears it, and emits `Events.prime_collapsed(center, n)` once per call when n > 0. | `undertow_well.gd` |
| 3 | **The Lance fires on a press, and the beam is a beam.** Input: during the Overdrive (or its ignition) a press edge fires the Lance — SPEC §3 gives it "V hold 0.25 s / V"; the hold only ignites, and audit #8 still holds (one 1 s hold ignites and never fires). A press during the 0.45 s ignition is LOCKED and fires when the ignition ends (lead decision). Look: **the prime suspect was confirmed** — `fx_beam.gd` hung its `CylinderMesh` under a quarter-turned pivot and then overwrote that pivot's `global_transform` every frame, wiping the quarter turn, so the tube's AXIS lay across the beam and every beam was a slab `width` tall and `length` deep. `SkillFx.tube_basis` puts the length on the cylinder's Y column; `fx_haze.gd` had the identical bug and got the same fix; the beam shader now flows on `local_pos.y`; both tubes are open-ended (`cap_top/bottom = false`) and carry a `reach` distance fade. | `skill_input.gd`, `fx/fx_beam.gd`, `fx/fx_haze.gd`, `fx/shaders/beam.gdshader`, `skill_fx.gd`, `zenith_lance.gd` |
| 4 | **A fin takes its own blade off the back.** `CoronaFins` drives the shipped `HeroModel.set_drones_docked(mask)` (hero-v3 r8, 742876f; bit i SET = `Drone_{i+1}` DEPLOYED/hidden, 0 shows all). Fins 0–5 map to `Drone_2..4` (wing_l) and `Drone_5..7` (wing_r); `Drone_1` never leaves. A fin launches from its own `drone_tip()`. The mask is absolute and pushed whenever it changes, so flying, returning, respawning and the Ward all keep the blade hidden and docking shows it. | `corona_fins.gd`, `corona_fin.gd`, `tests/rig_model.gd` |
| 5 | **The cable leaves `hand_l`, and is aimed from it.** `muzzle_l` is in neither CONTRACTS §5 nor `Hero3Sockets.TABLE`; every grapple tick logged `no socket named muzzle_l` (225 in one beat) and `ctx.socket()` fell back to the chest. The Skyhook now fires, reels and draws from `hand_l` — the CONTRACTS §5 socket the Undertow Well already throws from, on the same arm as `shield_l`, while the right arm carries the rifle muzzle and the saber. **Second bug found by the SKACC beat:** the cable was flown from `hand_l` but AIMED from the chest, 4 m lower on Hero3, so it overshot every low anchor by ~25 m and ran out of line at 120 m having touched nothing. `begin()` now aims, and measures the lock cone and range, from the cable socket. The stand-in publishes EXACTLY the §5 names and records any other. | `skyhook_anchor.gd`, `cable_visual.gd`, `tests/rig_model.gd` |
| 6 | **A dead mech's skill inputs do nothing.** `PlayerMech.is_alive()` (mech-move's single predicate) gates the whole router: while it is false nothing changes skill state, EN, a cooldown or an event, and the 6 f buffer DROPS presses made while dead rather than carrying them into the first live tick. Death also releases the anchor line and drops the ward (conflict map B4). | `skill_input.gd`, `skill_system.gd`, `corona_ward.gd` |

**Also in this round**
- `zenith_lance.gd` states its FEEL "0.15 continuous" shake with `Feel.shake_floor(0.15, …)` instead of
  re-deriving `camera_shake.gd`'s decay constant (lead note; the Request from r3 is closed).
- Splits, in their own commit `504bd4f`: `skyhook_anchor.gd` 443 → 319 with the three attached modes in
  `anchor_pull.gd` (202); `corona_fins.gd` 432 → 271 with one blade in `corona_fin.gd` (216).
- `SkillFx.beam_between` was dead code and is gone.

## How to verify (exact commands)

```
tools/godot.sh check --only=res://combat/skills/     # 59 files, 0 errors, 0 warnings
tools/godot.sh check                                  # 785 files, 0 failed, 0 errors, 0 warnings
tools/godot.sh test  res://combat/skills/tests/test_skills.gd --timeout=600
                                                     # TEST 275 checks, 0 failed, TEST ERRORS 0, exit 0
# SKACC (windowed, real main.tscn + real Hero3 + real input):
tools/godot.sh drive --scene=res://combat/skills/tests/skills_accept.tscn \
  --timeline=res://combat/skills/tests/timeline_accept.json \
  --sandbox --skip-menu --god --nan-watch [--skacc-beats=rift_taps,well,lance,fins,anchor]
# the r3 showcase reel is unchanged:
tools/godot.sh drive --sandbox --skip-menu --god --nan-watch \
  --timeline=res://combat/skills/tests/timeline_showcase.json --skills-showcase=all \
  --shots=/Users/minimax/m/mecha-city/captures --out=skills_all_r4
```

## Evidence

### Headless suite — FAIL on the pre-r4 code, PASS on this one
Every new check was run twice: once with the ONE source file its item fixes reverted to `b5d26d4`
(or, for item 5, with the cable asking for `muzzle_l` again — that is exactly what `b5d26d4` did), and
once on this tree. Logs in `tmp/skills/failpass/`.

| run | reverted | result |
|-----|----------|--------|
| `FAIL_input.log` | `skill_input.gd` + `tuning/skill_tuning.gd` → b5d26d4 | **TEST 270 checks, 35 failed** — every rift hold 1/2/3/4 t eaten (`lat=-1 moved=0.0m`), KEY_C, pad RB+B, `lock_on`-held and the buffered press all dead; the Lance never charged from a 1-tick press, a key tap or pad L3+R3; 5 activations while dead, 560 EN spent, a cooldown started, a corpse raised the Ward |
| `FAIL_well.log` | `undertow_well.gd` → b5d26d4 | **TEST 270 checks, 7 failed** — `well.lock_lands_on_target armed 68.4 m from the locked body`, `well.body_in_path_arms_on_it the core flew through the body and armed 34.6 m past it`, 0 `prime_collapsed` events |
| `FAIL_socket.log` | `CABLE_SOCKET = &"muzzle_l"` | **TEST 270 checks, 2 failed** — `input.cable_leaves_a_contract_socket the cable asks for muzzle_l`, `input.no_socket_outside_the_contract asked for muzzle_l × 225` |
| `FAIL_beam.log` | `fx/fx_beam.gd` → b5d26d4 | **TEST 270 checks, 2 failed** — `fins.beam_tube_lies_along_the_beam **the tube's axis is 90.0 deg off the beam**` (the lead's prime suspect, confirmed), `fins.beam_width_is_lateral got 31.261 want 0.066` |
| `FAIL_fins.log` | `corona_fins.gd` → the pre-r4 socket-mesh hide | **TEST 271 checks, 10 failed** — `7 of 7 blades hidden` for a 2-fin send (the old code stripped EVERY blade on any send), `Hero3 read back mask 0, the 2-fin send asked for 18` |
| `FAIL_anchor_aim.log` | `begin()` aims from `ctx.chest()` again | **TEST 275 checks, 1 failed** — `anchor.aimed_from_the_cable_socket the flown line passes 5.8 m from the aim point` (5.8 m in the rig, where the hand sits 3.9 m off the chest; ~25 m on Hero3, which is what the SKACC beat saw) |
| `PASS.log` | — | **TEST 275 checks, 0 failed, TEST ERRORS 0, exit 0** |

### SKACC (windowed) — the full reel, every beat `ok=1`
`tmp/skills/skacc_all.log`: `SKACC rift_taps ok=1 · well ok=1 · lance ok=1 · fins ok=1 · anchor ok=1`,
then `DRIVE done t=42.4 errors=0 warnings=6` — **0 engine/script errors, 0 `NANWATCH`, 0
`no socket named`**. Every beat was also run on its own (`tmp/skills/skacc_*.log`); the per-beat rows
below are from those runs and from the reel.

| beat | rows |
|------|------|
| `rift_taps` | holds 1/2/3/4/6/10/20 t, KEY_C 1 frame, pad RB+B 1 frame, the autoplay 3-frame tap — **every row `lat=1 moved=44.0m`** |
| `well` | hard lock 42 m: armed **8.8 m** from the body, primed. No lock, reticle on the body: armed **2.4 m**, primed. Then fire held 1.3 s (rifle stage 2): `well.collapsed_count +1`, **1 collapse hit for 900**, **1 `prime_collapsed` for 1 prime** |
| `lance` | 0.6 s hold ignites and does NOT fire; a V tap charges **2 ticks** after the press; camera at the gameplay arm (45.4 m); sweep **0.333 deg/tick = exactly the 40 deg/s cap** over 60 ticks |
| `fins` | Z tap at a spitter locked ~60 m: `skill_used(fins)=1`, **Hero3 mask 18** (bits 1 and 4 = `Drone_2` + `Drone_5`), `Drone_1` still docked, **mask 0** 0.3 s after the dock |
| `anchor` | `hand_l` exists and is 5.3 m off the chest pivot; a Y tap fires **1 tick** later; states `[FLYING, SURFACE]`; the cable's near end is **6.7 m off the body centreline**, the anchor point ~91 m out |

### The r3 showcase reel still runs clean
`tmp/skills/clip_all.log`: all 9 clips (rift → anchor → fins → ward → burst → well → plunge →
overdrive → lance), 15 stills written, `DRIVE done t=95.0 errors=0 warnings=13`, **0 `NANWATCH`**.
`captures/skills_lance_sweep.jpg` from that reel is the best read of the new beam: fully broadside
from the gameplay arm it is three concentric tubes — hot white core, warm gold band, soft red sleeve
— each with round soft edges and a visible fade at the far end. No flat sheet, no hard edge, no wedge.

### Stills — `captures/skills_r4_*.jpg`
`rift_taps_tap1` · `rift_taps_streak` · `well_locked_field` · `well_reticle_field` · `well_collapse` ·
`lance_overdrive` · `lance_beam_level` · `lance_beam_sweep` · `lance_beam_sky` ·
`lance_beam_first_person` · `fins_out` · `fins_volley` · `fins_docked` · `anchor_cable` · `anchor_reel`.

Judged from the images (I looked at every one):
- **well_locked_field** — the violet dome, its deck ring and the primed body's rim sit ON the
  juggernaut at 42 m. That is the whole of item 2.
- **lance_beam_sweep** — against `~/m/mc-accept/captures/acc_spec-coverage_34_lance_beam.jpg` (the
  lead's reference: a hard-edged flat pink sheet with sharp polygon corners that stops dead ~30 m out)
  the beam is now a soft round volume with a hot white core, no polygon edges, and a distance fade.
  `captures/skills_lance_sweep.jpg` (the showcase reel, fully broadside) is the clearest of the set.
- **lance_beam_first_person** — no whiteout: cockpit frame, HUD and city all readable.
- **anchor_cable** — the cable leaves the left arm, not the torso.
- **fins_out** — the back fan is thinner; the mask numbers above are the hard evidence.

## Known issues
- **The SKACC driver is sensitive to the shared machine.** Two of its waits were on `Feel.real_now()`
  and under-counted when every heavy slot was busy (a frame past 0.1 s); the rifle's stage-2 hold then
  delivered ~0.2 s of game time and the COLLAPSE never fired. Both waits are physics ticks now, and a
  beat first proves the mech still answers a teleport, so a mid-run edit by another unit reports
  `WORLD FROZEN` instead of twenty misleading rows. Run the beats selectively when the slots are busy.
- **The Lance still reads best broadside.** Seen almost straight down the barrel from the gameplay
  camera it is a bright muzzle with a soft halo. The geometry is provably a tube now
  (`fins.beam_tube_lies_along_the_beam` pins the axis to `to - from`), and the `reach` fade stops the
  far half filling the screen, but a 16 m × 800 m tube at 45 m is a big shape whatever it is made of.
- **Feel/impact of the sweep:** the 40 deg/s cap is exactly at the limit every tick
  (0.333 deg/tick measured, 0.333 allowed) — correct, but it means the beam is always at full speed
  when the player turns, which is the intended "rooted" statement.
- `fins.hero3_*` depends on hero-v3's tree compiling. It reads a clear `PENDING` line (never a silent
  pass) while their files are mid-refactor; at `93ccb69` it reads PASS.
- File sizes: `zenith_lance.gd` 316, `skill_input.gd` 224, `tests/skills_accept.gd` ~630 (a windowed
  capture driver, not runtime code — the 400-line rule is for shipped logic), `skyhook_anchor.gd` 319,
  `corona_fins.gd` 271. Nothing over 600 in the runtime path.

## Requests (to the lead / other units)

1. **hero-v3** — nothing owed: item 4 uses `set_drones_docked` / `drones_docked` / `drone_tip` exactly
   as shipped in 742876f, and `fins.hero3_drone_api` reads PASS at `93ccb69`. One note: while your
   `hero3_glow.gdshader` had a `return` inside `fragment()` (and later while `hero3_glow.gd:92` called
   a `_grille()` that had been moved out), EVERY suite that loads `hero3_model.tscn` went red on the
   stricter test host — `combat/skills/tests/test_skills.gd`, `combat/melee/tests/*` and your own
   `player/model/hero3/tests/*`. Worth a `check` before the next commit of that folder.
2. **tooling** — no allow-list row needed from skills: the stand-in's foreign-socket report is a
   `push_warning`, not a `push_error`, so `test_skills` exits 0 on its own. New suite row to add to
   `tools/suites.sh`: `res://combat/skills/tests/test_skills.gd`, no flags, expected green (273
   checks). `skills_accept.tscn` is a `drive` scene, not a suite.
3. **audio** — `timeline_reel.json` t=46 taps `rift_step`, which now blinks ~44 m on the press edge
   (it used to need a > 4-frame hold). Its overdrive taps at t=50 / 68.8 stay no-ops: ignition is a
   0.25 s HOLD.
4. **trailer** — the V tap at 3.4 s in `tl_c_od.json` now fires the Lance (it used to need a second
   hold). The beam's look changed with it: open-ended tubes with a distance fade, so re-time the cut
   to the new stills in `captures/skills_r4_lance_beam_*.jpg`.
5. **flow** — the tutorial's skills step (`tutorial_director.gd:31`) prompts `rift_step`, so a quick
   tap now counts.
6. **feel** — closed: `Feel.shake_floor(trauma, seconds)` is in and the Lance uses it (r3 Request 1).
7. **monster-assets** — still open from r3: `enemies/models/monster_model.gd:309` looks up `'slash_1'`
   in a Dictionary that does not have it on every enemy attack, and the same file is the only
   remaining `NANWATCH` line in a full reel.
