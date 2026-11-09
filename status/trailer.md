# trailer status

Job: `reviews/trailer-r1.md` (v1, delivered) → `reviews/trailer-r2.md` (part A delivered, part B
re-recorded by the lead in `~/m/trailer-r2b`) → `reviews/trailer-r3.md` (the showcase reel) →
`reviews/trailer-r5.md` (both reels re-recorded on today's build, delivered) →
**`reviews/trailer-r6.md` — both reels re-recorded on the golden-hour sky. DELIVERED; read the r6
section first.** Then `reviews/trailer-r4-captures.md` (the captures batch, delivered).
The r5/r3/r2/r1 sections below it are history.

## r6 — both reels on the city-art r16b golden hour (reviews/trailer-r6.md) — DELIVERED

Rendered from the live tree at **`5424809d`** ("lead: trailer r6 brief") plus this unit's own
trailer-only commits, which touch nothing outside `game/trailer/**`, `tools/trailer/**` and
`status/trailer.md`. The city-art r16b sky (real clouds at HDRI blend 0.5, a warm peach and gold
horizon, no diagonal hatch, the tod 1.0 clip fixed) and hud r7 are therefore in every take below.

### 1. The three r5 "reads badly" items — fixed, each on a rendered sweep

The r5 list was: the spitter's acid cloud over a third of the frame, the mech nearly out of frame in
flight, and the flat orange wall behind the drop. All three are "the lens is on the wrong side / too
far" problems, so all three were fixed the same way — by rendering the alternatives and looking at
them, with a new tool for each kind of sweep.

| tool | what it does |
|---|---|
| `tools/trailer/takes.py` | the spec reader every trailer tool shares: a take -> the `godot.sh` arguments (factored out of `render_all.py`, which now uses it) |
| `tools/trailer/stills.py` | drive a take and keep its stills as 16:9 — a `drive --shots` frame is the window's **backing store** (3024x1898, 16:10 on this Retina Mac), so every still is centre-cropped and downscaled before it is compared |
| `tools/trailer/rig_sweep.py` | sweep a rig's **bearing** (rotating `pos_hero`, keeping the spawn wedge opposite), a **rig patch** (`--configs`), or a **keyframed `cam`** about a pivot (`--cam-bearings`) — one `drive` per arm, one labelled sheet per take |
| `tools/trailer/vfx_cover.py` | how much of a frame a coloured VFX covers, as a percentage — the acid-cloud gate |
| `tools/trailer/tod_ab.py` | the `--tod` A/B per take (r1/r5's `tod_ab.sh`, now spec-driven and re-runnable) |
| `tools/trailer/set_tod.py` | put the A/B's per-shot decision into a shot list without hand-editing forty flag lists |

**(a) The spitter's acid cloud — `m3_spitter`.** The cloud is not one billboard, it is up to three
overlapping ones: the take spawned `spitter:3`. The fix is the **spitter count**, measured with
`vfx_cover.py` (hue 95 ±40, saturation ≥ 0.22) on real recorded frames:

| | acid cloud covers |
|---|---|
| r5 as delivered (reel t=25 s / 29 s) | **9.9 % / 12.6 %** of the frame |
| r6, measured on the re-recorded take at t=2/4/6/8/10 s | **0.76 / 1.27 / 1.02 / 0.97 / 1.08 %** |

The lens stays on the r5 bearing 225. A bearing sweep said 180 read clean, but the recorded take at 180
left the camera→chest ray **blocked for 9.48 s of 11.5** (`RIG m3_wide FAIL`) — a still sweep cannot see
that — and 225 with one spitter measures the *lowest* coverage of the four bearings swept anyway
(0.74 % / 0.91 %). Re-recorded on 225 with `spitter:1`: `blocked_max=0.00 foes_min=1` **PASS**.

**(b) The flight segment — `g4_flight`.** The chase rig sat 38 m back with `lag` 0.35, so through the
climb and the bank the mech fell to bbox 0.25–0.31 and the lower third of the frame was empty deck.
Five configurations were rendered (`tmp/trailer/r6/sweep_g4_flight.jpg`, sheet rows `now`/`tight`/
`high`/`side`/`lowhero`): **`tight` — offset (6, 11, 27), lag 0.18, fov 50 — is the arm where the mech
reads two to three times bigger against the towers with its jets lit at every sample time.** `side`
puts a tower across the lens at 4 s and 6.5 s; `lowhero` loses the mech behind a bridge at 6.5 s.

**(c) The drop's orange wall — `s03_drop` / `s03_impact`.** The camera sat north-west of the landing
point, where a flat orange megablock facade fills two thirds of the frame for the whole fall and the
impact. `rig_sweep.py --cam-bearings 0,60,120,180,240,300 --pivot=-560,7.5,600` rotates all three
camera keys about the landing point; **240° is the arm where the city, the Spire beam and the clouds
sit behind the mech at both the fall (t=0.9) and the landing (t=1.9)**
(`tmp/trailer/r6/sweep_s03_drop.jpg`). `cam_s03_impact.json` was deleted: nothing referenced it.

### 2. The time-of-day A/B, re-run on the r16b sky

`tools/trailer/tod_ab.py` drives a take's own timeline, camera and flags once per time of day with
`--tod` swapped and screenshots **the midpoint of every cut window that uses the take** — so the arms
are the frames the edit actually shows. Evidence: `tmp/trailer/r6/tod_<take>.jpg` (one row per time of
day) and `tmp/trailer/r6/tod/<take>_tod<X>_t<T>.jpg`.

**What the new sky changed.** On the r15 sky the A/B was a choice between a violet cast and a slightly
less violet one; on r16b every arm below 0.85 is golden hour, and the choice became *how much light*:

| | reads as |
|---|---|
| **tod 0.0** | the deepest blue-to-gold gradient, the longest shadows, the strongest silhouette. Best when the mech is against sky, or the shot is a wide of the city. |
| **tod 0.35** | the warmest bounce light on surfaces — the deck, the mech's armour and the enemies all pick up gold. Best when the subject has to read against the deck. |
| **tod 0.6** | the flattest and the palest: the sky loses its gradient and the frame loses contrast. It won no shot in the A/B. |
| tod 0.85+ | the storm — violet. The Brood Titan stays at 0.9 on purpose. |

`tools/trailer/sky_stats.py` measures the same frames (sky-band hue/chroma/value plus whole-frame
value). Its `brightest` column is the numeric form of the table: over the twelve takes measured in r6
the brightest arm is 0.35 or 0.6 in 9 of 12. Its `warmest` column is **not** usable on low-angle shots
— there the top of the frame is the blue zenith, so it reads 213-271 deg at every time of day. The
pick is made on the frames.

**The decision** (`shots.json` and `showcase.json`, applied with `tools/trailer/set_tod.py`). Every take
of both reels was A/B'd at 0.0 / 0.35 / 0.6; the rule that came out of the frames is *"0.0 where the
mech is against sky or the frame is a wide of the city, 0.35 where the subject has to read against the
deck"*, and 0.6 won no shot:

| time of day | trailer v2 takes | showcase takes |
|---|---|---|
| **0.0** | `s01_cold` `s03_drop` `s07_hive` `s09_end` `c_gatling` `c_flight` | `m4_harrier` `g3_jump` `g4_flight` |
| **0.35** | `s02_city` `c_melee` `c_missiles` `c_well` `c_fins` `c_parry` `c_dodge` `c_dash` `c_ram` `c_od` `c_fp` | the other 20 |
| **0.9** | `s08_boss` (the storm, unchanged) | `m7_titan` |

Two picks worth naming: `c_flight`/`g4_flight` are chases that spend the shot with the mech against the
sky, so 0.0's gradient and its silhouette are worth more than 0.35's bounce light; `c_fp`/`g10_fp` go
the other way — the r5 note was "a dark cockpit", and 0.35 is the arm where the muzzle flash reads
brightest (mean frame value 0.379 / 0.431 / 0.408 at 0.0 / 0.35 / 0.6).

### 3. Both reels re-recorded and re-cut — the gates

Everything below was recorded on the live tree at `5424809d` + this unit's trailer-only commits.

| | showcase reel | trailer v2 |
|---|---|---|
| takes | **26 recorded, 26 `DRIVE done … errors=0`** | **19 recorded, 19 `errors=0`** |
| framing | **22 takes, 0 failed** | **12 takes, 0 failed** |
| duration | **248.71 s (4:09)** | **64.48 s** |
| frame | **1920×1080, 60/1, yuv420p** | **1920×1080, 60/1, yuv420p** |
| video / audio | **h264 / AAC 301 kb/s** | **h264 / AAC 306 kb/s** |
| loudness | **−14.0 LUFS, −2.1 dBTP** | **−14.0 LUFS, −2.2 dBTP** |
| defects | **0 black, 0 frozen — PASS** | **0 black, 0 frozen — PASS** |
| sheets | `_segments.jpg`, `_2s.jpg` | `_shots.jpg`, `_2s.jpg` |

26 takes, not 24: `m3_spitter` and `m7_titan` were recorded twice (below). 19 for v2, not 18: `c_parry`
was recorded twice.

**Three takes had to be re-recorded, each for a reason the gate or the still sweep had missed.**

1. **`m3_spitter`** — the bearing-180 arm read clean in the still sweep but the recorded take left the
   camera→chest ray blocked 9.48 s of 11.5. Reverted to the r5 bearing with `spitter:1`: PASS.
2. **`m7_titan`** — `blocked 0.23 s` inside the cut windows against a 0.20 s gate, a Crown fin wiping
   the lens during the beam beat. The rig's `repair_rate` 12 → **24**: `blocked 0.00 s`.
3. **`c_parry`** — the framing gate passed and the frame was still wrong: a mantis filled **30.7 %** of
   the frame at reel t=35.3 s. `MASK_SIGHT` excludes enemies by design, so no framing metric can see
   this. `--trailer-pack-arc=332,140` keeps the pack on the far side of the hero for the whole cut:
   **30.7 % → 8.8 %** measured on the delivered mp4 (`vfx_cover.py`), 4.7 % on the take itself.

### 4. What still reads badly (reel timestamps, from the finished mp4s)

1. **`c_parry`, v2 t=34.2–36.1 s.** The mantis no longer fills a third of the frame (30.7 % → 8.8 %)
   but it is still the largest thing in it at t=35.3 s. A tighter spawn wedge or a lens that starts
   further round the orbit would finish the job; I ran out of round.
2. **`s3_fins`, showcase t≈91–101 s.** The Corona Fins VFX is a pale cyan disc across the centre and
   the drones do not read as drones. Unchanged from r5 — not in the r6 list.
3. **`m4_harrier`, showcase.** The mech is a small silhouette against a bright tower and the harriers
   are specks. The gate passes (bbox 0.42–0.48); it is the *look* that is too wide, not the framing.
4. **`c_fp` / `g10_fp`.** The cockpit is still dark. 0.35 is the brightest arm of the three and it is
   what ships, but the segment still says "a dark cockpit" more than "first person". This is exposure
   in the cockpit scene, not geometry — a `ui`/camera-aim change, not a trailer one.
5. **`c_missiles`, v2.** `low 1.83 s` — the hero's bbox sits under the 0.25 floor for nearly two
   seconds of a 1.9 s cut. It passes the gate (the gate allows 0.3 s for a `hero` shot and this is a
   `combat` shot, judged on enemies) but the mech is small for most of the cut.

## r4 — the captures batch (reviews/trailer-r4-captures.md, dispatched 11-09 03:20) — DELIVERED

The user OK'd the screen; I ran every unit's **"Captures needed"** command exactly as written, one
Godot window at a time, in the lead's order. Nothing of another unit's code was touched.

**44 commands, 10 units, 42 × exit 0 and 2 × exit 124** (both flow's collapse runs, killed by the
machine slot — see §6). Every sheet is in `captures/batch_r4/<unit>_sheet.jpg`; every log is in
`tmp/trailer/r4/logs/<unit>_<id>.log`; the machine table is `tmp/trailer/r4/results.json`.

**Tooling (new, mine):** `tools/trailer/batch_r4.json` (the command table), `tools/trailer/batch_r4.py`
(runs them with `MC_WINDOW_OK=1`, logs stdout+stderr per command to `tmp/trailer/r4/logs/`, records
exit code / wall time / engine errors / every file the run touched in `tmp/trailer/r4/results.json`),
`tools/trailer/batch_sheet.py` (the labelled contact sheets), `tools/trailer/batch_table.py` (the
table below), `tools/trailer/batch_death_sheet.py` (mech-move's item 10 heredoc, as a file).

Re-run any of it with:

```
MC_WINDOW_OK=1 tools/trailer/batch_r4.py --only <unit>[,<unit>…]   # skips what is already recorded
MC_WINDOW_OK=1 tools/trailer/batch_r4.py --only <unit> --force      # re-run
tools/trailer/batch_sheet.py <unit> --cols 5 --cell 440             # rebuild a sheet
tools/trailer/batch_table.py <unit>                                 # the machine table
```

**Two deviations, both recorded in the table below.** (1) monster-assets' three hive states all used
`--out=monsters_r6_hive`, which would have left only the last one on disk; I gave each its own `--out`.
(2) weapons asked for a *before/after* against commits `557410e~1` / `fb2e41a`; checking an old
commit out of this shared tree is forbidden by the run rules, so only the post-r6 half was filmed.

### 1. hud — sheet `captures/batch_r4/hud_sheet.jpg`

| id | command | exit | s | engine errors | outputs |
|---|---|---|---|---|---|
| 1_combat | `shot --scene=res://ui/tests/hud_shots.tscn --out=hud_r6_combat --hud=combat --sandbox --skip-menu --god --enemies=mantis:3,ripper:3,spitter:1 --times=1.7,…,13.7` | 0 | 21 | `DRIVE … errors=0`; the exit-time `3 resources still in use` line | `hud_r6_combat_t1_7 … t13_7.jpg` (9) |
| 2_menus | `shot … --out=hud_r6_menus --hud=menus --sandbox --skip-menu --god --no-enemies --times=1.7,…,18.2` | 0 | 26 | none | `hud_r6_menus_t1_7 … t18_2.jpg` (12) |
| 3_title | `shot … --out=hud_r6_title --hud=title --god --times=3,9,14,…,31` | 0 | 49 | the exit-time line | `hud_r6_title_t3_0 … t31_0.jpg` (14) |
| 4_flight | `drive --sandbox --timeline=res://player/mech/timelines/flight.json --out=hud_r6_flight --shots=0.9,…,11.2 --log=…/tmp/hud/r6_flight.csv` | 0 | 18 | none | `hud_r6_flight_t0_9 … t11_2.jpg` (9) + `tmp/hud/r6_flight.csv` |

**What the sheet shows.** The harness printed `HUDSTEP 0…8 at t=0.07, 2.51, 4.01 … 13.01`, so
`_t10_7` really is HUDSTEP 6 `_flight`, `_t12_2` HUDSTEP 7 `_first_person` and `_t13_7` HUDSTEP 8
`_flight_canopy`, as the unit said: **matches** — and the last two frames do show the canopy struts,
i.e. the cue-on-the-glass state. Menu pages, both credits ends and both LICENCES ends are all on the
sheet. The `W 移动 MOVE` / `MOUSE 环视 LOOK` tutorial boxes are visible in `_t16_0`…`_t20_5` and
`_t23_5`…`_t29_5` of the title run, which is what the title path is supposed to do.

**One thing I could not settle, and it is item 1.** The flight take's own CSV says `flying=true` for
t = 0.9–8.8 s and `flying=false` for t = 10.2 and 11.2 s, so the unit's rule ("the cue in every
flying=true frame and in none where it says false") is testable on these nine frames. Measuring the
cyan pixel count in the cue's own box (centre + `OFFSET (-118, 0)`, `RULE_H 42`,
`ui/widgets/flight_cue.gd:20-21`) gives 373 / 390 / 385 / 211 / 191 / 129 / 104 for the seven flying
frames and **17 / 176** for the two non-flying ones — and zoomed in, a **cyan arc is drawn left of the
crosshair in all nine frames**, including both `flying=false` ones. So either that arc is a different
widget (it is curved; the cue is a rule plus a number) or the cue is not hiding. **Not confirmed —
hud should look at `captures/hud_r6_flight_t10_2.jpg` / `_t11_2.jpg` full size.**

### 2. melee-defense — sheet `captures/batch_r4/melee-defense_sheet.jpg`

| id | command | exit | s | engine errors | outputs |
|---|---|---|---|---|---|
| A_front34 | `drive --timeout=600 --scene=res://combat/melee/tests/melee_range.tscn --nocam --cam=22,14,-20,-2,11,-5,45 --timeline=…/timeline_guard_r7.json --shots=1.82,6.35,8.88 --autoshot --out=melee_r7_front34` | 0 | 20 | none | `melee_r7_front34_t1_8/t6_4/t8_9.jpg`, `melee_ev_parry_0/1.jpg` |
| B_side | the same, `--cam=28,13,-4,-3,11,-4,45 --out=melee_r7_side` | 0 | 15 | the exit-time line | `melee_r7_side_t1_8/t6_4/t8_9.jpg` |
| C_close | the same, `--cam=12,12,-14,-3,11,-5,38 --out=melee_r7_close` | 0 | 15 | none | `melee_r7_close_t1_8/t6_4/t8_9.jpg` |
| D_mantis | `drive --timeout=900 --scene=res://combat/melee/tests/integration.tscn --sandbox --enemies=mantis:2,ripper:6 --timeline=…/timeline_integration.json --nan-watch --out=melee_r7_int` | 0 | 61 | the exit-time line | `melee_int_01…06` (6 of 9 beats) |
| E_movie | `movie --timeout=900 --movie=…/melee_r7_guard.avi … --timeline=…/timeline_guard_r7.json` | 0 | 16 | the exit-time line | `melee_r7_guard.avi` (11 s) |

**What the sheet shows.** The guard surface reads as a **translucent pale-cyan dome with a visible
rim**, the mech and the deck visible through it and a faint facet pattern on the lower half — the
flat mint hexagon I reported in r5 is gone: **matches** the r7 claim. The parry stills show a white
burst at the mech's left arm with the caught green acid round beside it: **matches**.
Framing is the weak part: in **every** A/B/C frame one of the range's own untextured arena blocks
(`melee_range.gd::_arena`) covers the lower-right third.
**D_mantis re-shot only 6 of the 9 beats** — `INT FAIL lunge — start=36m move=melee_l1 end=49m
en=1000->1000 lock=false`, and `timeline_integration.json` is a single `{"t": 55.0, "end": true}`, so
the catch / parry_return / core_rend beats never ran. `melee_int_05_catch_hold.jpg` and
`_07_parry_return.jpg` are therefore still the **11-05 r6 files**; they are on the sheet, labelled
"r6 FILE not re-shot this round": **DOES NOT match** (the unit expected those two overwritten).

### 3. weapons — sheet `captures/batch_r4/weapons_sheet.jpg`

| id | command | exit | s | engine errors | outputs |
|---|---|---|---|---|---|
| 1_fp_gatling | `drive --scene=res://trailer/shot.tscn --timeline=res://trailer/tl_c_fp.json --skip-menu --god --tod=0.6 --stub=flow --spawn=-540,10,570,45 --trailer-pack=30,ripper:4,mantis:1 --trailer-hud=1 --out=weapons_r6_fp --shots=3.4,…,5.6` | 0 | 21 | the exit-time line | `weapons_r6_fp_t3_4 … t5_6.jpg` (5) |
| 2_tp_gatling | the same with `--timeline=res://trailer/tl_c_gatling.json --out=weapons_r6_tp --shots=2.2,…,3.4` | 0 | 20 | the exit-time line | `weapons_r6_tp_t2_2 … t3_4.jpg` (4) |
| 3_fp_kit | the same with `--timeline=res://combat/weapons/tests/timeline_fp_kit.json --out=weapons_r6_kit --shots=2.7,4.75,6.2,8.75,9.1` | 0 | 25 | the exit-time line | `weapons_r6_kit_t2_7 … t9_1.jpg` (5) |
| 4_movie | `movie --movie=…/weapons_r6_fp.avi … --timeline=…/timeline_fp_kit.json` | 0 | 82 | the exit-time line | `weapons_r6_fp.avi` (11 s) |

**What the sheet shows.** No flat orange polygon anywhere on the right of the frame, and the ejected
casings read as **small tumbling orange rectangles leaving down-and-right**: **matches** the r6 claim
(checked full size on `weapons_r6_fp_t4_4.jpg`). Third person is unchanged — the mech fires from the
hip with a warm flash at the muzzle: **matches** "nothing may have changed". The Hailstorm frames at
8.75 s and 9.1 s are a normal dark blue dusk, **not** whited out, and the salvo reads as a fan of
white streaks: **matches**. Still wrong, and not part of the r6 claim: the gatling **muzzle flash is
a flat opaque cream disc with a hard edge** parked on the target's chest (my long-standing Request 2).

### 4. hero-v3 — sheet `captures/batch_r4/hero-v3_sheet.jpg`

| id | command | exit | s | engine errors | outputs |
|---|---|---|---|---|---|
| plume_behind | `drive --scene=res://player/model/hero3/tests/hero3_city_shot.tscn --timeline=…/timeline_plume.json --shots=3.0,6.4,10.6,15.0 --out=hero3_r10_plume_behind --shots-dir=…/captures --side=0 --dist=15 --height=6 --look=5.5 --stub=camera,flow,hud --sandbox --skip-menu --no-enemies --god --nan-watch` | 0 | 22 | none | `hero3_r10_plume_behind_t3_0/6_4/10_6/15_0.jpg` |
| plume_side | the same with `--side=90 --out=hero3_r10_plume_side` | 0 | 22 | none | `hero3_r10_plume_side_t3_0/6_4/10_6/15_0.jpg` |

**What the sheet shows.** The plume **is** there — a soft pale-cyan cone leaving the backpack nozzle,
roughly 6–8 m long and about half the torso's width, clearest in the boost cell (t=6.4 s) from both
cameras, fainter in the hover cell; the framing is right (the backpack fills the frame at 15 m):
**matches**, with the note that the plume is small and pale rather than a thrust.
**The fourth cell does not happen.** `timeline_plume.json` taps `assault` at t=13.0 and 13.8, but the
take goes `fall → land_heavy (t=14.0) → idle` and never enters assault, so `t=15.0` is an idle mech
with `throttle=0.00` — the unit's "one 17 s run that does all four in order (walk, boost dash, hover,
assault)" is **3 of 4: DOES NOT match**. Throttle windows measured from the run's own `PLUME` lines:
walk 0.5–4.0 (throttle 0), boost/slide 4.5–7.5 (0.55–0.80), jump/hover 8.0–12.5 (0.25–0.45), nothing
after 14.0.

### 5. mech-move — sheet `captures/batch_r4/mech-move_sheet.jpg`

| id | command | exit | s | engine errors | outputs |
|---|---|---|---|---|---|
| 0_kerb | `drive --timeout=900 --sandbox --timeline=res://player/mech/timelines/kerb.json --out=mech-move_kerb --shots=2.2,…,4.4` | 0 | 13 | none | `mech-move_kerb_t2_2 … t4_4.jpg` (8) |
| 1_death | `drive --timeout=1500 --scene=res://player/mech/tests/death_probe.tscn --timeline=…/death_probe_end.json --skip-menu --out=mech-move_death` | 0 | 78 | none | `mech-move_death_d1…d8` (11) |
| 2_death_stub | the same with `--stub=hud --out=mech-move_death_stub` | 0 | 53 | the exit-time line | `mech-move_death_stub_d1…d8` (11) |
| 3_sheet | `python3 tools/trailer/batch_death_sheet.py` (the unit's item-10 heredoc, verbatim) | 0 | 0 | none | `mech-move_death_sheet.jpg` |

**What the sheet shows — three findings, one of them a real bug.**

1. **0_kerb: the kerb is not in the scene this capture runs.** The eight frames show the mech walking
   across a flat tiled plaza at a constant height, and the run's own telemetry says `y=7.51` for every
   sample from t=2.0 to t=4.5 (it crosses the kerb lane, z = +6.8 → −1.5, between t=3.0 and t=3.5) with
   `step_events=0` for the whole take. The reason is in the code: the 2 m kerb is added by
   `player/mech/tests/mech_test_base.gd::OBSTACLES` — by the **headless test harness**, not by the
   core sandbox — so `tools/godot.sh drive --sandbox` films an empty lane. **DOES NOT match**, and no
   re-timing of the shot list can fix it; the capture needs the harness's obstacle range (or a kerb in
   the sandbox) to exist first.
2. **1_death (menus live): the death slump does not play.** Every `POSE dead_*` line reads
   `clip=death weight=0.00 cockpit_h=13.1` (13.1 = standing) and the run ends
   **`VDEAD t=63.54 SUMMARY: 2 checks failed`** — `hop_death_still_posed`,
   `flight_death_still_posed`. The close-ups agree: the mech stands upright under the MECH DESTROYED
   page. The unit expected "0 checks failed": **DOES NOT match**.
3. **2_death_stub (`--stub=hud`): everything the unit claims.** `clip=death weight=1.00`,
   `cockpit_h` 7.1 → 6.7 (inside the 6.4–8.5 m band), **`SUMMARY: 0 checks failed`**, and the
   close-ups show the mech collapsed on the deck: **matches**. So the pose works with the menus
   stubbed out and not in the full build — that difference is the finding for the lead.

### 6. flow — sheet `captures/batch_r4/flow_sheet.jpg`

| id | command | exit | s | engine errors | outputs |
|---|---|---|---|---|---|
| 1_collapse | `drive --timeline=res://flow/tests/collapse_film_drive.json --skip-menu --god --nan-watch --flow-script=res://flow/tests/collapse_film.json --out=flow_r5b_collapse` | **124** (slot) | 602 | `FlowDebug: the world has no zone or marker 'A2'` and `'A6'` | `e2e_hive_{a2,a5,a6}_collapse_00…07.jpg` (24) |
| 2_collapse_movie | `movie --movie=…/flow_r5b_collapse.avi` + the same timeline | **124** (slot) | 1805 | the same two | the same 24 stills + `flow_r5b_collapse.avi` (2.3 GB) |
| 3_city | `drive --timeout=1500 --timeline=res://flow/tests/e2e_city_drive.json --skip-menu --god --nan-watch --spire-hp-scale=0.05 --flow-script=res://flow/tests/e2e_city.json --out=flow_r5b_city` | 0 | 969 | none (`errors=0`, 2 warnings) | `e2e_a_dropin`, `_b_landing_prompt`, `_c_a1_fight`, `_c2_a1_clear`, `_d_spire0_pods`, `_e_spire0_collapse` (**6 of 17**) |
| 4_assault | `drive --timeout=900 --timeline=res://flow/tests/assault_city_drive.json … --flow-script=res://flow/tests/assault_city.json --out=flow_r5b_assault` | 0 | 293 | the exit-time line | none — this script takes no stills; the evidence is its log |

**What the sheet shows.**

- **The three hive collapses film, and they read.** All 24 frames are there (8 per hive, 0.25 s apart):
  the green spire, the burst, a bright yellow-green **shockwave ring** sweeping the frame, then the
  fireball and the debris — hive_a2 and hive_a5 are exactly what the unit claims: **matches**. Only
  `hive_a6_collapse_06/07` lose the subject (the lens is on a bridge truss with a green glow at the
  bottom, no spire) — the collapse-camera issue I routed to flow in r3, still there for that hive.
- **Both runs of the collapse timeline are killed by the machine slot, not by the game.** The drive
  reaches only game t=246.5 s in its 600 s slot (the sim runs at ≈0.41× real time under this scene),
  and the movie fills its whole 1800 s slot and 2.3 GB. Both still write every frame the unit asked
  for before the kill, and `ffmpeg` can still decode the .avi (frame 600 extracts cleanly), but the
  exit code is 124 and there is **no clean end**: the timeline's own `end` at t=420 is never reached.
- **The whole-city run stalls at the death beat — 6 of the 17 captures.**
  `FLOWDBG t=77.8 die []` → `FLOWDBG t=77.8 wait_state ["game_over", 10.0]`, and then
  `WARNING: FlowDebug: beat wait timed out (25 s)`. Nothing after that: no `game_over`, no respawn,
  no checkpoint capture, no boss gate, no catapult, no victory, and **no `E2ECAMREPORT` tally** in the
  log. The drive itself is healthy (`DRIVE done t=900.0 errors=0`). **DOES NOT match.**
  This is the same wall mech-move hit in the full build: with the menus live the death path does not
  complete (see §5 item 2). Worth the lead's attention as one bug, not two.
- **The real-kit assault answers the unit's question: yes.** `FLOWDBG t=50.0 assault_spire [2.0]` →
  `unblock down after 7.5 s` → `FLOWDBG state=district … down=1 hp=10000 en=850` — the bot took hive_a6
  down unaided in 7.5 s with the shipped kit: **matches**. It writes no stills, so nothing of it is on
  the sheet; the line above is the evidence.

### 7. enemies — sheet `captures/batch_r4/enemies_sheet.jpg`

| id | command | exit | s | engine errors | outputs |
|---|---|---|---|---|---|
| r12_1_search | `drive --scene=res://enemies/tests/fight_probe.tscn --timeline=res://enemies/tests/fight_timeline.json --out=enemies_r12_search --shots=6,14,22,30 --sandbox --stub=hud --nan-watch --probe-cam=follow --enemies=ripper:6,mantis:2,spitter:2,harrier:2,juggernaut:1` | 0 | 45 | the exit-time line | `enemies_r12_search_t6_0/14_0/22_0/30_0.jpg` |
| r12_2_movie | the same as a `movie` to `…/enemies_r12_search.avi` | 0 | 199 | the exit-time line | `enemies_r12_search.avi` (≈60 s) |
| 1_spawn | `drive --scene=res://enemies/tests/spawn_probe.tscn --timeline=res://enemies/tests/spawn_probe.json --sandbox --god --quality=low` | 0 | 22 | the exit-time line | none (log only) |
| 2_fight | `drive … --out=enemies_r11 --shots=14,24,34 --sandbox --stub=hud --nan-watch --enemies=ripper:8,mantis:2,spitter:2,harrier:2,juggernaut:1` | 0 | 46 | the exit-time line | `enemies_r11_t14/24/34` + the probe's own `fight_big_hit`, `fight_pack`, `fight_perfect_dodge`, `fight_shockwave`, `fight_telegraph_glint`, `fight_telegraph_rod` (9) |
| 3_near_miss | `movie --movie=…/enemies_r11_near_miss.avi … --enemies=harrier:2,spitter:2` | 0 | 177 | the exit-time line | `enemies_r11_near_miss.avi` (≈40 s) |

**What the sheet shows.**

- **The spawn probe is clean**: `SPAWN PROBE done trials=10 flung=0 worst_speed=0.000 m/s
  worst_moved=0.000 m (limits 1.0 / 0.1)` — every trial at 0.000, against the r15 baseline's
  15979 m/s / 7846 m: **matches**, and then some.
- **The near-miss rule holds**: `FIGHT 2.97s near_miss harrier_strafe 1.8 m`,
  `9.10s … 2.9 m`, `23.79s … 0.7 m`, and `FIGHT SUMMARY near_miss=3 played_by_director=3` — every
  distance ≤ 6 m and the director's own count agrees: **matches**.
- **The r12 search reads as a fight that spreads out, not as a statue.** In the four stills the pack
  goes from clustered at t=6 s to scattered across the plaza at t=22–30 s, with the spitter's acid
  cloud hanging at the right; in the movie frames the monsters are walking and repositioning rather
  than frozen. What the stills cannot show is the *horizon sweep* itself — that needs the movie, and
  the movie is on the sheet at 2 s intervals.
- **The old hit-flash ghost is still there** (my r2/r5 Request 1 to monster-assets): at
  `enemies_r12_search.avi` t=16 s and t=18 s a mantis reads as a **flat pale cut-out**, white against
  the plaza, with its silhouette intact but every material detail gone.

### 8. feel — sheet `captures/batch_r4/feel_sheet.jpg` (121 tiles)

| id | command | exit | s | engine errors | outputs |
|---|---|---|---|---|---|
| 1_gallery_movie | `movie --movie=…/feel_gallery.avi --movie-size=1600x900 --scene=res://fx/tests/feel_gallery.tscn --timeline=res://fx/tests/gallery_timeline.json` | 0 | 343 | the exit-time line | `feel_gallery.avi` (49 rows × 1.5 s) |
| 2_gallery_stills | `drive --scene=res://fx/tests/feel_gallery.tscn --timeline=res://fx/tests/gallery_timeline.json --fx-stills=1` | 0 | 99 | none | **98 stills**, `01_rifle_fire_f1.jpg` … `49_*_f4.jpg` |
| 3_swarm_movie | `movie --movie=…/feel_r5_swarm.avi --movie-size=1600x900 --scene=res://fx/tests/swarm_feel.tscn --timeline=res://fx/tests/swarm_timeline.json --sandbox --skip-menu --no-enemies --god` | 0 | 90 | the exit-time line | `feel_r5_swarm.avi` |
| 4_skate | `TRAILER_SIZE=1600x900 tools/trailer/record.sh …/feel_r5b_skate.avi res://trailer/tl_c_gatling.json --scene=res://trailer/shot.tscn --trailer-rig=res://trailer/rig_c_low.json --skip-menu --god --tod=0.6 --stub=flow` | 0 | 47 | the exit-time line | `feel_r5b_skate.avi` (6.0 s) |

**What the sheet shows.**

- **The gallery films, and most rows read.** Of the first 24 rows at frame 1, the rifle fire/hit and
  charge, the missile hit (a bright orange burst), melee light (a smoke puff), melee heavy, the lunge
  hit, the charge slash (a white ring), the finisher (an orange burst), the perfect parry (smoke plus
  a white flash), the perfect dodge (a cyan glow on the mech) and the dash streak are all clearly
  visible: **matches**.
- **But a block of rows is nearly empty at both sampled frames.** At f1 *and* f4 the six gatling rows
  (`gatling_fire`, `_hit`, `_vent_perfect`, `_vent_good`, `_overheat`, `_jam`) plus `block`,
  `catch_release` and `boost_start` show only a faint wisp, a faint ring outline or nothing at all.
  The gallery camera may simply be far from those effects — the same `block` shield reads as a big
  translucent dome in melee-defense's own takes — so this is a note for the lead's eye on
  `feel_sheet.jpg`, not a verdict on the VFX.
- **Item 4 does not film what it asks for.** `feel_r5b_skate.avi` is 6.0 s of the mech **standing
  still and firing the gatling** (muzzle flash from t=2.0 s, orange casings tumbling left); there is
  no skate, no dash slide and no spark/dust trail at the feet in any of the twelve 0.5 s frames. The
  cause is in the command: the timeline it names, `game/trailer/tl_c_gatling.json`, is
  `lock_on → weapon_next → fire (1.6–5.0 s) → end` — **it contains no boost, dash or movement at
  all**, so the skate trail cannot appear. **DOES NOT match**; the take needs a timeline that actually
  boosts.

### 9. monster-assets — sheet `captures/batch_r4/monster-assets_sheet.jpg`

All ten commands exit 0. Rather than eyeball the tiles I measured where the monster actually is in
each frame (green-pixel bounding box, `PIL` + numpy):

| id | command | exit | s | outputs | green px | bbox (x, y) |
|---|---|---|---|---|---|---|
| 1_charge | `shot --scene=res://enemies/models/tests/model_gallery.tscn --out=monsters_r6_charge --cams="charge:40,13,-40:40,10,0:42" --warm=120 --gallery-gait=juggernaut:20` | 0 | 6 | `monsters_r6_charge_charge.jpg` | **0** | — |
| 1b_charge_side | the same with `--cams="charge_side:0,11,-46:0,9,0:42" --out=monsters_r6_charge_side` | 0 | 6 | `…_charge_side.jpg` | 182 915 | x[788,1695] **y[0,1436]** of 3024×1898 |
| 2_idle | `--cams="idle:…;idle_side:…" --gallery-clip=idle` | 0 | 9 | `…_idle.jpg`, `…_idle_side.jpg` | 56 171 / 36 450 | y[15,756] / **y[0,700]** of 1600×900 |
| 3_lineup | `--cams="lineup:40,45,-150:40,30,0:60"` | 0 | 7 | `…_lineup.jpg` | 28 997 | y[308,645] — fully in frame |
| 4_slam | `--times=0.2,…,1.7 --gallery-attack=juggernaut:ground_slam` | 0 | 7 | 6 frames | — | the whole line-up is in every frame |
| 5a/5b/5c hive | `--gallery-state=intact / cracked / destroyed` (three runs; I gave each its own `--out`) | 0 | 7 each | 3 frames | — | — |
| 5d_ingame | `shot --scene=res://main.tscn --sandbox --skip-menu --out=monsters_r6_ingame --cams="juggernaut:34,12,-34:34,8,0:45" --warm=180 --enemies=juggernaut:1 --env-only` | 0 | 12 | `monsters_r6_ingame_juggernaut.jpg` | — | — |
| 6_cycles_movie | `movie --movie=…/monsters_r6_cycles.avi --scene=…/model_gallery.tscn --timeline=…/gallery_timeline.json` | 0 | 29 | `monsters_r6_cycles.avi` | — | — |

**What the sheet shows.**

- **The round's headline capture is an empty frame.** `monsters_r6_charge_charge.jpg` has **zero**
  green pixels in 1600×900: the plaza, the blocks and nothing else. The juggernaut's `charge_run` —
  "the clip this round fixed", the one the unit says must keep its knuckle claws clear of the deck —
  **is not in the picture at all**: **DOES NOT match**.
- The side camera does film it, but **cropped**: the animal's bounding box starts at y=0 and runs to
  y=1436 of 1898, i.e. its head/shoulders are cut by the top of the frame (and that shot came out at
  the window's 3024×1898 while the others are 1600×900).
- The `idle` shots are in frame (`idle_side` also touches the top edge), and the pose reads as planted
  rather than up on its knuckles — but with the front charge frame empty I cannot confirm the unit's
  "the feet must now read as planted" claim from the front.
- **The hive's three states read clearly**: intact = a tall spire with green pods, cracked = the same
  spire with the glow broken up, destroyed = a collapsed green mass on the deck: **matches**.
- The line-up (with the blue 16 m hero placeholder for scale) and the cycles movie both show every
  archetype, and `monsters_r6_ingame_juggernaut.jpg` shows a juggernaut in the sandbox with the hero
  beside it.

### 10. audio — sheet `captures/batch_r4/audio_sheet.jpg`

| id | command | exit | s | engine errors | outputs |
|---|---|---|---|---|---|
| 1_boss_movie | `movie --movie=…/audio_r7_boss.avi --timeline=res://audio/tests/timeline_reel.json --scene=res://main.tscn --sandbox --skip-menu` | 0 | 432 | the exit-time line | `audio_r7_boss.avi` — **88.0 s, mjpeg + pcm_s16le** |
| 2_fight_trace | `drive --timeline=res://audio/tests/timeline_fight_r5.json --scene=res://main.tscn --sandbox --skip-menu --enemies=juggernaut:1,mantis:2,ripper:5,spitter:1,harrier:1 --audio-trace --nan-watch` | 0 | 37 | the exit-time line | none (log only) |

**What this shows** (audio is judged from the stream and the trace, not from pixels):

- The boss reel **carries the real mix**: `ffmpeg ebur128` over the movie's own audio gives
  **I = −21.6 LUFS, LRA 9.1 LU, true peak −5.9 dBFS** over 88 s — audible, dynamic, nothing clipping
  and nothing silent.
- The fight trace fires **48 sound ids** with per-id counts (`heartbeat_loop=113`, `hurt_light=56`,
  `hurt_heavy=50`, `footstep_hero=38`, `melee_light=35`, `hitmarker=30`, `alarm_warning=20`,
  `missile_hit=21`, `missile_launch=18`, `rifle_fire=11`, `near_miss=2`, `last_stand=1`,
  `jugg_roar=5`, …), and there is **no `unknown or empty sound id` line anywhere in the log** — the
  unit's own gate. The r7 sounds (`last_stand`, `near_miss`, `jugg_slam`) all fire in a real fight:
  **matches**.

### r4 — the six things that do not match, in one place

| unit | item | what the capture shows | where |
|---|---|---|---|
| **mech-move** | 0_kerb | the mech walks a flat plaza at a constant `y=7.51`, `step_events=0`: the 2 m kerb is built by the **headless test harness** (`mech_test_base.gd::OBSTACLES`), not by the sandbox this command runs | §5.1 |
| **mech-move** | 1_death | the death clip never plays with the menus live (`weight=0.00`, `cockpit_h=13.1`), **2 checks failed**; the same probe with `--stub=hud` is `weight=1.00`, `cockpit_h=6.7`, **0 failed** | §5.2–3 |
| **flow** | 3_city | the E2E bot stalls at `wait_state ["game_over"]` after the death beat: **6 of 17 captures**, no respawn/boss/catapult/victory, no `E2ECAMREPORT` | §6 |
| **monster-assets** | 1_charge | **zero green pixels** in the frame — the juggernaut's `charge_run` is not in the picture; the side camera has it but cropped at the top edge | §9 |
| **feel** | 4_skate | 6 s of the mech standing still and firing the gatling: `tl_c_gatling.json` has no boost or dash in it, so no skate trail can appear | §8 |
| **hero-v3** | plume t=15.0 | the `assault` taps at t=13.0/13.8 never take: the take ends `fall → land_heavy → idle`, so the fourth cell is an idle mech at `throttle=0.00` | §4 |

Plus two smaller ones: melee-defense's `D_mantis` re-shot only 6 of 9 beats (its timeline is a single
`{"t": 55.0, "end": true}`), and hud's flight-cue item is **unresolved** — a cyan arc sits left of the
crosshair in all nine flight frames including the two whose CSV row says `flying=false`.

### r4 — Requests (routed, nothing of another unit's code touched here)

1. **mech-move + flow + the lead — one bug, seen twice.** With the menus live, the death path does not
   complete: mech-move's probe ends `SUMMARY: 2 checks failed` with `clip=death weight=0.00` and the
   mech standing at `cockpit_h=13.1`, and flow's E2E bot waits forever for `game_over`
   (`FlowDebug: beat wait timed out (25 s)`) and never reaches respawn. Both pass with `--stub=hud`.
   Frames: `captures/mech-move_death_d1_dead_closeup.jpg` (standing) vs
   `captures/mech-move_death_stub_d1_dead_closeup.jpg` (collapsed).
2. **mech-move — the kerb capture needs the harness's obstacle range.** `player/mech/timelines/kerb.json`
   is run with `--sandbox`, but the 2 m kerb only exists inside `mech_test_base.gd::OBSTACLES`. Either
   the timeline runs in a scene that builds the range, or the kerb has to exist in the sandbox.
3. **monster-assets — `monsters_r6_charge` is an empty frame** (0 green pixels); the side camera has the
   animal but its bounding box touches y=0. The `--cams` values need a look-at that follows the gait.
4. **feel — `4_skate` needs a timeline that boosts.** `tl_c_gatling.json` is lock_on → weapon_next →
   fire; nothing in it moves the mech, so the skate trail cannot be filmed with it.
5. **hero-v3 — the plume run's `assault` taps do not take** (t=13.0 / 13.8, while the mech is falling),
   so the fourth cell of the 4-cell grid is an idle mech.
6. **melee-defense — `timeline_integration.json` is 55 s** and the lunge beat's retry eats the budget,
   so the catch / parry_return / core_rend beats never run in a capture.
7. **hud — the flight cue could not be confirmed hidden** on the two `flying=false` frames
   (`captures/hud_r6_flight_t10_2.jpg`, `_t11_2.jpg`).

### r4 — Evidence

- `captures/batch_r4/` — the ten contact sheets: `hud`, `melee-defense`, `weapons`, `hero-v3`,
  `mech-move`, `flow`, `enemies`, `feel`, `monster-assets`, `audio` (`*_sheet.jpg`), every tile
  labelled with the command id, the file name and the wall-clock time.
- `tmp/trailer/r4/results.json` — 44 rows: command, exit code, wall time, engine errors, outputs.
- `tmp/trailer/r4/logs/<unit>_<id>.log` — the full stdout+stderr of every command.
- `captures/` — the frames and movies themselves, left in place (git-ignored): 24 hive-collapse
  frames, 98 gallery stills, the two death-probe sets, the monster gallery, `melee_r7_guard.avi`,
  `weapons_r6_fp.avi`, `flow_r5b_collapse.avi` (2.3 GB), `enemies_r12_search.avi`,
  `enemies_r11_near_miss.avi`, `feel_gallery.avi`, `feel_r5_swarm.avi`, `feel_r5b_skate.avi`,
  `monsters_r6_cycles.avi`, `audio_r7_boss.avi`.
- `tmp/trailer/r4/verdicts.md` — my raw notes while looking at each sheet.


## r5 — the showcase reel and trailer v2 re-recorded on today's build — IN PROGRESS

Rendered from the live tree at **`13f787fb`** ("lead: trailer r5 brief") plus this unit's own
trailer-only commits (`b5af5535`, `6b324f39`), which touch nothing outside `game/trailer/**` and
`tools/trailer/**`. Every demo-visible fix the brief lists — hero-v3 r9/r10, mech-move r8,
monster-assets r5/r6, melee-defense r7, weapons r6, feel r5/r5b, flow r5b, enemies r11/r12, hud r6 —
is therefore in these takes.

### What changed before the re-record

**The skybridge is now measured, not guessed.** Three segments (`g2_assault`, `g3_jump`, `g7_melee`)
filmed *under* a skybridge while every framing gate was green, because the gate cannot see it: a thin
truss overhead never blocks the chest ray and barely moves `open`. Two tools came out of that:

| tool | what it does |
|---|---|
| `game/trailer/probe_clear.gd` | headless screen: rasterises the triangles of every near mesh onto a 32×18 frame grid and reports the fraction within N metres of the lens. `--csv=<a.csv,…>` replays the camera path a **finished take actually flew**. |
| `tools/trailer/bearings.py` | the authoritative method: prints the `--cams=` argument for a rendered sweep of one arena (`tools/godot.sh shot`), 24 bearings in one windowed run. |

**The probe under-reports and is not a placement tool.** On the A6 deck it scored bearing 105 at 0.06
and bearing 195 at 0.00 while `tools/godot.sh shot` showed both lenses buried in a wall; I could not
close that gap inside this round's budget. It is kept because it does catch gross failures — it found
`g3_jump`'s truss at 5 m for 2.87 s, and its ranking of the bridge sector matched the render — and its
header says so. **Every bearing in the reel is placed from the rendered sweep**
(`tmp/trailer/bear/a6bear_*.jpg`, sheet `tmp/trailer/look/bearings.jpg`):

| bearing | what the render shows |
|---|---|
| 030–060, 120–135 | the skybridge truss banded across the frame |
| 090, 075 | clear, but the truss sits directly **behind** the mech and costs it contrast |
| 105, 195 | the lens is inside a wall |
| 150, 165 | a slab fills the frame |
| **000, 015, 180, 210–345** | open deck, sky, the lit megablock behind |

So five rigs were re-aimed: `g3_jump` 200→**000** (and its whole take moved off the bridge spawn onto
the main deck), `g5_dodge` 165→**015**, `m5_juggernaut` 195→**180**, `g7_melee` 150→**330**,
`s7_msl` 180→**345**.

**The other three changes:** `g6_guard` loses its three spitters (their acid cloud covered half the
frame for the whole segment — the verb is the shield), and the three shortest cuts are lengthened
(`g2_assault` 7.1→9.2 s with a third boost-ram, `g3_jump` 7.2→10.4 s with a second jump and hover,
`g5_dodge` 7.3→7.9 s). **No segment in the reel was 4–5 s** — the shortest cut in the r3 edit was
7.1 s — so "lengthen the short ones" was applied to the three shortest rather than to a 4–5 s band.

### The showcase reel — `captures/trailer/TIANSHU_showcase.mp4`, DELIVERED

24 takes re-recorded on the r5 build, **24/24 `DRIVE done … errors=0`**, then re-cut.

| | required | measured |
|---|---|---|
| framing | 0 failed over the cut windows | **22 takes, 0 failed** |
| takes | `errors=0` | **24/24, `render_all` exit 0** |
| frame | 1920×1080, 60 fps, 16:9 | **1920×1080, 60/1, yuv420p** |
| video / audio | H.264 / AAC | **h264 / AAC 300 kb/s** |
| loudness | −14 LUFS, TP ≤ −1 dBTP | **−14.0 LUFS, −2.1 dBTP** |
| defects | none | **0 black frames, 0 frozen frames** (`defects.py` → PASS) |
| length | 4–7 min | **4:09 (248.71 s)**, 26 cuts + 3 chapter cards |

**The cut pipeline had a real bug and it is fixed** (`2d0f497a`). The audio mix was ONE ffmpeg whose
filter graph demuxed all 26 clips *and* the music at once with `-vn`; ffmpeg still opens and buffers
every input's video to keep the graph fed, so a 26-input graph over 1080p60 h264 **deadlocked** — 175 %
CPU with `mix.wav` frozen at 12.5 MB, for 55 minutes, and `subprocess.run` could not see it because the
process was alive. The 11-06 cut lost an hour to the same thing. Now each clip's audio is extracted to
its own WAV (one ffmpeg per clip) and the game-audio bed is built with the **concat demuxer**, so the
mix is a graph over ONE input plus the music beds. **The step that hung for 55 minutes now finishes in
seconds.** `run()` also grew a watchdog: a step that is given the file it writes is killed and the cut
fails loudly if that file has not grown for 120 s.

### The hive collapse now films (flow r5b) — `m6` is two cuts

The real `FlowHiveCollapse` holds the burning spire from **19.0 s to 20.9 s** of the m6 take and hands
the view back to the player at 21.0 s — which is why the old 11–21 s cut ended on an empty deck under a
bridge. `m6_spire` is now 11.0–18.8 (pods + core) and `m6b_collapse` is 18.9–20.9 at **half speed**:
the burning spire, the shockwave ring, the fireball. This closes r3 Known issue 1 and r3 Request 1.

### What still reads badly (reel timestamps, from the finished mp4)

Frames: `tmp/trailer/look/reel_weak_s.jpg`. The framing gate passes all of these — it measures the
hero's bbox and whether scenery blocks the lens, and it cannot see a VFX billboard.

1. **`m3_spitter`, reel t=23–33 s — the worst one.** The spitter's acid cloud is a flat translucent
   green blob over the **upper-left third of the frame for the whole ten seconds** (t=25 s and t=29 s
   both show it). The fight happens behind it; the lower two thirds read fine.
2. **`s3_fins`, reel t=105.7–115.3 s.** At 108 s the frame is mostly empty deck and the lit megablock;
   at 112 s the Corona Fins VFX is a **pale cyan disc filling the centre** and the drones do not read
   as drones.
3. **`g4_flight`, reel t=184.6–192.4 s.** At 187 s the mech is small and the lower third is empty
   deck; at 190 s it is nearly out of frame — only the lock reticle and a sliver of the mech.
4. **`m4_harrier`, reel t=33–41.8 s.** The mech is a small silhouette against a bright tower and the
   harriers are specks. The crane aims 24 m above the hero (`look: [0,24,0]`), so the frame is mostly
   sky. Re-rigged once this round (pack 34→20 m, lens 50→40 m, shorter rise) which fixed the gate —
   bbox 0.17→0.42, no-enemy 4.33 s→0.35 s — but the *look* is still too high.
5. **`g10_fp`, reel t=240.7–248.7 s.** The cockpit is very dark: the gatling fire is a small orange
   blob at the lower left and the enemies barely read. It says "a dark cockpit" more than "first
   person". (The orange slabs weapons r6 removed are gone; this is exposure, not geometry.)

### Trailer v2 — `captures/trailer/TIANSHU_trailer_v2.mp4`, DELIVERED

18 takes re-recorded on the same build, **18/18 `errors=0`**, cut with the fixed pipeline.

| | required | measured |
|---|---|---|
| framing | 0 failed over the cut windows | **12 takes, 0 failed** |
| takes | `errors=0` | **18/18, `render_all` exit 0** |
| duration | 60–90 s | **64.48 s** |
| frame | 1920×1080, 60 fps, 16:9 | **1920×1080, 60/1, yuv420p** |
| video / audio | H.264 / AAC | **h264 / AAC 309 kb/s** |
| loudness | −14 LUFS, TP ≤ −1 dBTP | **−14.0 LUFS, −2.2 dBTP** |
| defects | none | **0 black frames, 0 frozen frames** (`defects.py` → PASS) |

**One rig change was needed.** The v2 boss take came out blocked 1.95 s over its cut windows: the
Brood Titan **charges**, and a Crown fin crosses the lens in under a second — the rig's swing-clear
repair at the default 3/s arrives after the fin already has. `repair_rate` is now a per-rig field
(`game/trailer/cam_rig.gd`, default unchanged) and the boss rig uses 12: **blocked 1.95 s → 0.17 s**,
and the report went to 12 takes, 0 failed.

**What still reads badly in v2** (`captures/trailer/sheets/TIANSHU_trailer_v2_shots.jpg`):

1. **`s03_drop` / `s03_impact`, reel t=9.1–14.7 s.** The 40 m fall and the landing happen in front of
   a **large flat orange wall** that fills most of the frame; the mech reads but the city does not.
   The drop take's spawn puts the lens against that facade.
2. **`c_fp`, reel t=27.7–29.6 s.** Same as the showcase's `g10_fp`: the cockpit is dark and the
   gatling flash is a small glow at the lower left.

Everything else in v2 reads: the cold open, the Spire beam, the hive, all eleven combat cuts (the
Mirror Guard is a cyan dome in `c_parry`, the perfect dodge shows PERFECT in `c_dodge`), the four boss
cuts and the end card.

### How to re-render either reel (one command each)

```
MC_WINDOW_OK=1 tools/trailer/showcase.sh --force   # showcase: record every take, cut, sheets, gates
MC_WINDOW_OK=1 tools/trailer/v2.sh --force         # trailer v2: the same, from game/trailer/shots.json
tools/trailer/showcase.sh --cut-only               # just the edit + the evidence (no screen needed)
tools/trailer/v2.sh --cut-only
```


## r3 — the gameplay showcase reel (打怪 / 技能展示 / 机制展示) — IN PROGRESS

The user asked for fighting monsters, a skill showcase and a mechanics showcase, each long enough to
understand. `captures/trailer/TIANSHU_showcase.mp4`: 25 segments in three chapters, every segment
6–13 s, a lower-third label with the verb's in-game name and its key, a 1.5 s chapter card per
chapter, the combat HUD on throughout.

### The pipeline (new this round)

| file | what it adds |
|---|---|
| `game/trailer/showcase.json` | the spec: 24 takes, 25 shots, 3 cards, 4 music beds, 4 stingers. Camera rigs are **inline objects** — `TrailerShot` now takes a rig as JSON *or* as a `res://` path, so a rig is one object in the shot list instead of a file nobody opens. |
| `game/trailer/showcase/tl_*.json` | 23 autoplay timelines (one per segment). |
| `game/trailer/showcase/flow_m6_spire.json` | the hive-spire flow script (un-stubbed flow). |
| `game/trailer/assist/*.json` | six assist specs (below). |
| `game/trailer/assist.gd` (`TrailerAssist`) | **new.** Scripted *reactions* for the three verbs a timeline cannot time: a perfect parry is a 167 ms window that only opens when a monster decides to swing, a Core Rend needs its victim staggered, and the gatling's perfect vent is a needle crossing a mark. It presses the REAL actions at the REAL moment — the player's reaction, scripted — so the camera films the game's own parry / execution / vent. Four rule kinds: `t` (a press on the clock), `telegraph` (react to `Events.enemy_telegraph`), `poise` (real `take_hit` carrying **only** stagger, until the bar breaks), `stagger` (press the moment a staggered monster is executable), `vent` (tap fire as the needle crosses). Every rule prints `ASSIST …`. |
| `tools/trailer/titles.py` | `lower_third()` (accent rule + name + key + what it does) and `render_card()` (a full-frame chapter card over a blurred, darkened still). |
| `tools/trailer/cut.py` | chapter cards woven into the shot list (`cards[].before`), and a shot's `lower` block turned into its lower third. `--spec` / `--out` already existed. |
| `tools/trailer/render_all.py` | `--spec` gains `dir` / `logdir` (the showcase renders into its own folders) and inline rig / assist / `flow_script` pass-through. |
| `tools/trailer/sheet.py` | the segments sheet prints each shot's label under its frame (CJK from Hiragino). |

### The segment list

Chapter 1 打怪 (8 cuts, 90.5 s) — one per enemy: Ripper swarm, Mantis (block → perfect parry),
Spitter (dodge the lob → charged shot), Harrier (lock → salvo), Juggernaut (stagger → execution),
Hive Spire (pods → core → collapse), Brood Titan ×2 (reveal/beam, core/stagger/finisher).
Chapter 2 技能展示 (7 cuts, 66.2 s) — every skill in SPEC §3: Skyhook Anchor [E], Rift Step [C],
Corona Fins [Z] + the ward, Shockcore Burst [X], Undertow Well [G], Zenith Overdrive [V] → Lance,
Hailstorm Volley [1].
Chapter 3 机制展示 (10 cuts, 92.3 s) — dash/slide, assault boost + ram, jump/hover/landing, flight,
perfect dodge → witch time, Mirror Guard (block/parry/catch field), Dawn Edge (L1–L3, charged,
lunge, air, execution), rifle + gatling + vent + swap, lock-on + switch, first person.

Total ≈ 253 s (4:13) + 3 cards.

### What the first takes taught (all measured, all in this file's Evidence)

1. **On A6 the lens must sit at or below the mech's chest.** The first pilot take used a 40 m orbit
   13 m *above* the hero's origin (i.e. above its head): the lens aimed down at the dark deck, the
   mech read as a silhouette and `foes` was 0 for 5.42 s. The lead's accepted `c_gatling` is a `low`
   rig.
2. **A 16 m mech under a pack of 14 m mantises is batted 100 m across the district in twelve
   seconds.** `m2_mantis`'s framing log has the camera going from (−88, 440) to (+24, 542) — the hero
   was launched by mantis hits, the camera followed it into a building, and the take failed
   `blocked 1.65 s / no enemy 5.57 s`. Fixed with `--trailer-mark=x,y,z[,radius[,drop]]`: a
   capture-side arena wall that projects the hero back onto a disc and removes the outward velocity,
   plus a fall recovery. Travel segments (dash / assault / jump / flight / blink) get a radius wide
   enough for the move and a drop deep enough that a deliberate fall is not "recovered".
3. **The pack has to outlast the segment.** `m1_ripper` killed all 7 of its monsters before the
   gatling beat at t=6.4 s, so the second verb fired at nothing. Every pack now carries 8–13 bodies.
4. **The gatling/ram locked-off cameras were pinned against a hero that floated 7.4 m.** hero-v3 r9
   fixed the float; the lenses then looked *over* the parapet instead of along the deck. Same class
   of bug as the lead's r3 note 3.

### Placing the cameras: a measurement, not a taste (this took four passes)

`game/trailer/stages_a6.json` sweeps the A6 mark over **24 bearings × 4 camera kinds** in one
headless run (`tools/godot.sh test res://trailer/probe_stage.gd`, 97 cameras, `tmp/trailer/a6_sweep.log`).
The answer is a **geometry**, not a bearing:

| camera kind | d | h | result over 24 bearings |
|---|---|---|---|
| `low` | 44 m | +3 m | clear at 23 of 24 (135° is walled by `t3_1_props`) |
| `mid` | 46 m | +14 m | clear at 23 of 24 (45° only) |
| `crane` | 50 m | +3→+32 m | clear at all 24 |
| `wide` | 60 m | +10 m | **blocked across the whole 225–315° sector** (`t3_1_props`, `t2_1_props`, `t2_1`) |

Four things that measurement then forced, each of which cost a render to learn:

- **Everything past ~50 m is blocked.** Pass 2 used 51–85 m locked-off cameras and every one of them
  framed a wall. Every lens is now 44–50 m from the hero.
- **The lens must not be *low*.** Pass 3 put the cameras at −6…+5 m and 32–46 m and the A6 garden's
  own canopy props swallowed half the frame (`m1_ripper`: a brown mass over the right half from
  t=3.6 s, `blocked 9.88 s`). The sweep's clear configurations are +3 m and above — chest height for
  a 16 m mech is *above* the planting.
- **A 50° lens at 44 m sees a 41 × 23 m window**, which is narrower than a 20–30 m spawn ring: most
  of the pack is outside the frame by construction. Every combat lens is fov 52–58 and every pack
  ring is 14–26 m. (`m1_ripper` pass 2: `no enemy 8 s`.)
- **A monster that closes from the camera's own side walks into the lens.** `m1_ripper` pass 4 passed
  every metric and still had a mantis filling the frame from t=8 s — `MASK_SIGHT` excludes enemies by
  design, so the framing metric *cannot* see this. `--trailer-pack-arc=<centre>,<width>` now spawns
  the pack in a wedge on the far side of the hero (centre = lens bearing + 180).

`m1_ripper` with the sweep's own `low` geometry (bearing 225, d 44, h +3, fov 55):
`blocked_max=0.00 low_max=0.00 nofoe_max=0.00 foes_min=1` — **PASS**.

## r6 — how to verify (exact commands)

```
# the whole round, one command each (recording needs the screen: MC_WINDOW_OK=1)
MC_WINDOW_OK=1 tools/trailer/render_all.py --spec game/trailer/showcase.json --force   # 24 takes
MC_WINDOW_OK=1 tools/trailer/render_all.py --spec game/trailer/shots.json --force      # 18 takes
tools/trailer/showcase.sh --cut-only     # the showcase edit + its sheets + framing + defects
tools/trailer/v2.sh --cut-only           # trailer v2, the same

# the time-of-day A/B on the current sky (one drive per arm, ~20 s each)
MC_WINDOW_OK=1 tools/trailer/tod_ab.py --spec game/trailer/shots.json --take s02_city --tods 0.0,0.35,0.6
MC_WINDOW_OK=1 tools/trailer/tod_ab.py --spec game/trailer/shots.json --take all --reuse   # rebuild sheets only
uv run --with numpy --with pillow python tools/trailer/sky_stats.py tmp/trailer/r6/tod/*_16x9.jpg

# the camera sweeps the three r5 fixes were picked on
MC_WINDOW_OK=1 tools/trailer/rig_sweep.py --spec game/trailer/showcase.json --take m3_spitter \
    --bearings 135,180,225,270 --at 3.0,7.5 --tod 0.35 --pack "60,spitter:1,ripper:6"
MC_WINDOW_OK=1 tools/trailer/rig_sweep.py --spec game/trailer/showcase.json --take g4_flight \
    --configs tmp/trailer/r6/g4.json --at 1.2,4.0,6.5 --tod 0.35
MC_WINDOW_OK=1 tools/trailer/rig_sweep.py --spec game/trailer/shots.json --take s03_drop \
    --cam-bearings 0,60,120,180,240,300 --pivot=-560,7.5,600 --at 0.9,1.9 --tod 0.35
uv run --with numpy --with pillow python tools/trailer/vfx_cover.py tmp/trailer/r6/sweep/m3_spitter_b*_t*_16x9.jpg

# the gates
python3 tools/trailer/framing_report.py --spec game/trailer/showcase.json captures/trailer/logs_showcase/*.csv
python3 tools/trailer/framing_report.py --spec game/trailer/shots.json captures/trailer/logs/*.csv
tools/trailer/defects.py captures/trailer/TIANSHU_showcase.mp4     # loudness + 0 black + 0 frozen
tools/trailer/defects.py captures/trailer/TIANSHU_trailer_v2.mp4
tools/trailer/stack_sheets.py -o tmp/trailer/r6/reels.jpg --width 1500 \
    captures/trailer/sheets/TIANSHU_showcase_segments.jpg captures/trailer/sheets/TIANSHU_trailer_v2_shots.jpg
```

## How to verify (exact commands)

```
# the whole reel, one command (recording needs the screen: MC_WINDOW_OK=1)
MC_WINDOW_OK=1 tools/trailer/showcase.sh            # record what is missing, cut, sheets, gates
MC_WINDOW_OK=1 tools/trailer/showcase.sh --force    # re-record every take first
tools/trailer/showcase.sh --cut-only                # just the edit + the evidence

# the pieces
MC_WINDOW_OK=1 tools/trailer/render_all.py --spec game/trailer/showcase.json [--force] [--only m1_ripper]
tools/trailer/cut.py --spec game/trailer/showcase.json --out captures/trailer/TIANSHU_showcase.mp4
tools/trailer/framing_report.py --spec game/trailer/showcase.json captures/trailer/logs_showcase/*.csv
tools/trailer/sheet.py --spec game/trailer/showcase.json \
    -o captures/trailer/sheets/TIANSHU_showcase_segments.jpg --cols 4 --cell 640
tools/trailer/sheet.py captures/trailer/TIANSHU_showcase.mp4 \
    -o captures/trailer/sheets/TIANSHU_showcase_2s.jpg --every 2.0 --cols 6
tools/trailer/defects.py captures/trailer/TIANSHU_showcase.mp4

# the camera placement the rigs come from (headless, ~90 s, 97 cameras)
tools/godot.sh test res://trailer/probe_stage.gd -- --stage=res://trailer/stages_a6.json \
    --skip-menu --stub=flow --timeout=900 | grep -E "^STAGE|^  CAM"

# the v2 re-cut with the lead's r3 fixes
MC_WINDOW_OK=1 tools/trailer/recut_v2.sh

tools/godot.sh check --only=res://trailer/
```

## Known issues

- **The hive-spire collapse does not film.** The un-stubbed flow runs the real path (`hurt_spire` on
  each of `hive_a6`'s four pods, then the core, then the spire's own death), the four pods burst and
  the core opens cleanly, and `FLOWDBG state=… down=1` confirms the spire fell — but about **one second
  after the core dies the collapse cinematic parks the lens inside geometry** and the rest of the
  collapse is a dark interior with the burning spire visible through a gap. Frames: the 56 s take,
  t=32–41 s clean, t=42 s buried, t=44–54 s looking at an unrelated bridge.
  `captures/trailer/sheets/` (the m6 segment). The segment therefore shows the pods and the core and
  the label says so; routed below.
- **The Mirror Guard shield reads as a flat mint-green hexagon** about 12 m across, opaque, with a
  hard edge (`m2_mantis` t=1.6–4.0 s, `g6_guard`). It is the melee-defense unit's `shield_visual`,
  not a capture artefact — it is the same in every take that holds guard.
- **The gatling muzzle flash is a ~10 m sprite** (already routed in r2, weapons' file). It is why the
  first-person segment is kept to the cockpit and a short burst.
- `g4_flight` (the fliers) is the one segment the framing gate still fails on first render: harriers
  circle at 60–120 m and leave a 50 m lens. Re-rigged (pack at 34 m, a crane that rises with them,
  fov 62) — see Evidence.
- **The reel is 8.4 s shorter than the shot list.** FIXED — see the commit "fix the reel losing
  8.4 s in the final encode": the 25 title plates are infinite `-loop 1` image inputs and `-shortest`
  treated them as the limiting stream. Each overlay now carries `shortest=1` and the mux takes an
  explicit `-t <length>`.
- **Six segments read badly** (confirmed on the finished reel, `TIANSHU_showcase_2s.jpg`) (`captures/trailer/sheets/TIANSHU_showcase_segments.jpg`,
  one frame at the midpoint of each cut). The framing gate passes all of them — it measures the
  hero's bbox and whether scenery blocks the lens, and it cannot see a VFX billboard:
  - `m3_spitter` — **the worst one**: the spitter's acid/spore cloud sits across a third of the frame
    as a flat translucent green blob for about **ten seconds** (reel t=22–32 s). The fight is behind it.
  - `s3_fins` — the Corona Fins/ward VFX fills the frame as a pale cyan disc; the drones do not read
    as drones.
  - `s5_well` — the frame is mostly empty deck with the word COLLAPSE on it; the well itself is not
    in the sampled frame.
  - `g2_assault`, `g3_jump` — the mech is small or out of the sampled frame (both are long fast
    traversals; the gate passes them on bbox over the whole window).
  - `g6_guard` — the Mirror Guard shield (the flat mint hexagon, routed below) covers the left third.
  These are listed so the lead can judge them from the sheets; each is a re-record away from fixed and
  none of them is a fake — they film the real verb. **If the lead wants one thing re-shot first, make
  it `m3_spitter`.**

## Requests (to the lead / other units)

1. **flow — the hive collapse cinematic parks the camera inside geometry.** `hive_collapse.gd` runs
   the topple, the chained blasts and the smoke column, and `FlowDebug.film_collapse` can photograph
   it, but in a *gameplay* take the lens ends up inside a wall about a second after the core dies. A
   shot of the spire actually falling is the one thing the showcase cannot get from the real path.
2. **melee-defense — the Mirror Guard shield is an opaque 12 m hexagon.** In a guard segment it is
   the largest object in the frame and it reads as a flat cut-out rather than a shield.
3. (carried from r2, still open) **monster-assets — the hit flash whitens a Mantis into a paper
   cut-out**, and **weapons — the gatling muzzle flash does not work in first person**.

### The gate

| | required | measured |
|---|---|---|
| framing | 0 failed over the cut windows | **22 takes, 0 failed** (`tools/trailer/framing_report.py --spec game/trailer/showcase.json`) |
| takes | `DRIVE done … errors=0` | **24/24 recorded, `record.sh exit 0`** |
| frame | 1920×1080, 60 fps, 16:9 | **1920×1080, 60/1, yuv420p** |
| video / audio | H.264 / AAC | **h264 / AAC 304 kb/s** |
| loudness | −14 LUFS, TP ≤ −1 dBTP | **−14.0 LUFS, −2.0 dBTP** |
| defects | none | **0 black frames, 0 frozen frames** (`tools/trailer/defects.py`) |
| length | 4–7 min | **4:03 (242.90 s)** |
| segments | 6–12 s each, 3 chapters | **25 cuts, 7.3–12.5 s, 3 chapter cards** |

**Where the enemy-visible rule is relaxed** (brief: "relax the enemy-visible rule for chapter 3
movement segments, and say which"): the four segments whose verb IS travel — `g1_move` (dash),
`g2_assault` (assault boost + ram), `g3_jump` (jump/hover/landing) and `g4_flight` (flight) — plus
`s2_rift` (Rift Step blinks) and `s6_od` (the Overdrive chase). Their rigs carry `kind: "hero"`, which
is what `framing_report.py` reads (from the spec, not the stale CSV header). Everything else is
judged as combat.

## Evidence

- `captures/trailer/TIANSHU_showcase.mp4` — the reel, **242.90 s**, every gate green.
- `captures/trailer/TIANSHU_trailer_v2.mp4` — the v2 re-cut with the lead's r3 notes 1–3 fixed,
  **64.52 s**, every gate green (`tools/trailer/defects.py` → PASS).
- `captures/trailer/sheets/TIANSHU_trailer_v2_shots.jpg` — one frame per v2 shot: c_melee now has
  5–9 enemies in frame, c_dash/c_ram are unblocked, and all four boss cuts frame the titan with no
  blown-out floor disc.
- `captures/trailer/sheets/TIANSHU_showcase_segments.jpg` — one frame per segment with its label.
- `captures/trailer/sheets/TIANSHU_showcase_2s.jpg` — one frame every 2 s.
- `captures/trailer/shots_showcase/<id>.avi` — the 24 takes (git-ignored).
- `captures/trailer/logs_showcase/<id>.csv` — the per-frame framing logs; `framing_report.py` turns
  them into the pass/fail table (22 takes, 0 failed — the two takes with no rig, `m6_spire` and
  `g10_fp`, have no log by construction: the spire is filmed by the flow's own aimed camera and the
  first-person segment IS the game camera).
- `tmp/trailer/a6_sweep.log` — the 97-camera A6 sweep every rig is placed from.
- `tmp/trailer/render_showcase_raw.log`, `render_pass2.log`, `render_v3.log` — the take logs.

## Done

**v1 (r1)** — `captures/trailer/TIANSHU_trailer_v1.mp4`, 60.62 s, accepted as a pipeline.

**r2 part A — delivered: `captures/trailer/TIANSHU_trailer_v2a.mp4`**

| | required | measured |
|---|---|---|
| duration | 60–90 s | **60.40 s** |
| frame | 1920×1080, 60 fps, 16:9 | **1920×1080, 60/1, yuv420p** |
| video | H.264 | **h264, faststart** |
| audio | AAC, −14 LUFS, TP ≤ −1 dBTP | **AAC 305 kb/s, −14.1 LUFS, −2.3 dBTP** |
| defects | none | **0 black frames, 0 frozen frames** |
| takes | 0 engine errors | **11/11 takes `DRIVE done … errors=0`, `record.sh exit 0`** |
| framing | every shot passes §2 | **11 takes, 0 failed** (`tools/trailer/framing_report.py`) |

1. **`--movie-size=WxH` on `tools/godot.sh movie`** (approved Request 1) — writes the Movie Maker size
   override for that run only, removes it on exit; `tools/trailer/record.sh` is now a thin wrapper.
2. **`game/trailer/framing.gd` (`TrailerFraming`)** — the numbers a trailer shot is judged on: the
   subject's screen-space bbox as a fraction of frame height, whether a `MASK_SIGHT` ray to its chest
   is blocked, how many live enemies are on screen *and* unblocked, and the fraction of the frame that
   is sky / far city / a landmark rather than a near wall. Pure maths + physics queries, so it runs
   headless (the scout) and in a take (the rigs) with identical numbers.
3. **`game/trailer/probe_stage.gd` + `stages.json`** — a headless scout: one 30 s run teleports the
   hero into eleven candidate arenas, spawns a pack on the navmesh, lets the fight start and scores
   five cameras per stage at two bearings. 83 cameras scored in one run.
4. **`game/trailer/cam_rig.gd` (`TrailerCamRig`)** — the camera kit: **orbit**, **crane**, **chase**,
   **low**, **locked-off wide**. Each takes the view from the game camera for its window and hands it
   back; each looks at its subject through a framing offset and holds a **frame-height floor** (when
   the subject would read under `min_bbox` the camera closes the distance); each writes a per-frame
   CSV and prints a verdict. `subject` picks what is framed *and* measured — the boss take names
   `BroodTitan`.
5. **`--trailer-pack=<r>,<type>:<n>,…`** — the fight pack spawns on a ring of `r` metres around the
   hero at world-ready, each monster snapped onto its navmesh by the spawner's public `spawn()`.
   `--enemies` puts them 150–250 m out, which is why no enemy read in v1.
6. **`PlayerMech.debug_perfect_dodge()`** (mech-move, idle) — the witch-time beat through the real
   `_perfect_dodge()`. All five mech-move suites still pass (9/21/56/17/14 checks).
7. **`game/trailer/boss_shot.tscn`** — wraps the boss showcase untouched and puts a rig in front of it.
8. **First person and flight** (part B verbs, unblocked by camera-aim r7 / mech-move r6):
   `tl_c_fp` films the cockpit with the gatling firing; `tl_c_flight` films the double-tap lift-off
   on a lagged chase.

## The stage pick (lead brief §1)

`bbox` = the 16 m mech as a fraction of frame height at 44–48 m, `open` = the fraction of the frame
that is not a near wall, `foes` = enemies visible and unblocked.

| stage | best camera | bbox | open | foes | blocked | verdict |
|---|---|---|---|---|---|---|
| **A6 Sky Garden** `(-60,155,450)` | 225/315 low + mid | 0.34–0.39 | **0.71–0.87** | 2–3 | never | **main stage** |
| **H0 Insertion Pier** `(-540,8,570)` | 225 low + mid | 0.34–0.39 | **0.82–0.89** | 3–5 | never | **alternate** (the first-person take) |
| A3 Spire Plaza | 225_mid, 315_low | 0.34–0.39 | 0.60–0.76 | 1–2 | 2 of 8 | spare |
| W5 stack perch | 225_mid | 0.34 | 1.00 | **0** | never | nothing can reach it |
| S5 Forum | 225_low | 0.39 | 0.82 | 0 | 2 of 8 | the hero gets knocked off |
| A5 Foundry L2/L3 | — | 0.39 | 0.16–0.71 | 1–3 | **every camera** (`t5_2`) | rejected |
| A1 Container Yard | 315_low | 0.39 | 0.56 | 0 | every camera (`t1_1`) | rejected |
| A4 Megablock Canyon | 315_low | 0.39 | 0.69 | 0 | 2 of 8 | no enemy reads |
| K5 Knot crown | 225_low | 0.39 | 0.73 | 0 | 3 of 4 | no enemy reads |
| **B1 Crown deck** | — | 0.39 | **0.00** | 0 | 7 of 8 | **rejected: the boss arena is roofed** |

Sheet: `captures/trailer/scout/sheet_stages.jpg`; the scored run: `captures/trailer/scout/scout_scores.log`.

## The shot list (lead brief §3)

Eleven combat cuts on **eight distinct camera setups**, each ≤ 2.79 s (a half-bar of `combat_mix` at
129.2 BPM), no setup twice in a row, every cut point on the beat from t = 9.10.

| shot | setup | what |
|---|---|---|
| c_melee | orbit_close | melee L1→L3 on a close orbit |
| c_dash | lock_dash | the boost dash across a locked-off frame |
| c_flight | chase_flight | the double tap lifts the mech over the roof line |
| c_gatling | low | gatling spin-up from deck level, looking up |
| c_fp | game camera | first person: gatling from the cockpit |
| c_missiles | wide | the Hailstorm salvo on a wide |
| c_well | orbit_wide | skill 1/3 — Undertow Well, the gravity slam |
| c_parry | orbit_parry | guard into the parry beat |
| c_fins | crane | skill 2/3 — Corona Fins, the camera cranes up with the drones |
| c_ram | lock_ram | the assault-boost ram kick, straight at the lens |
| c_dodge | orbit_parry | perfect dodge into witch time, the world at 0.3× |
| c_kill | orbit_close | the charged slash and a kill, death FX in frame |
| c_od | chase | skill 3/3 — Overdrive into the Zenith Lance |

## r3 — IN PROGRESS / NEXT

- **`m3_spitter` is the one segment worth re-shooting first** (the acid cloud covers the fight for
  ~10 s). Everything else on the list above is a smaller blemish.
- `tools/trailer/cut.py --encode-only` exists because the final encode is the fragile stage: it
  reuses `tmp/trailer/cut` (picture.mkv + mix.wav + the 28 clips + the title plates) and redoes only
  the last pass, which is ~10 min instead of ~25. The first attempt at the fixed encode produced a
  **truncated file** (invalid NAL units throughout) with ffmpeg reporting success; the retry from the
  same intermediates was clean. If it recurs, composite the titles in two passes to halve the filter
  graph's memory.

## In progress / next

- **HOLDING the part-B re-records** on the lead's instruction (r2 part A review, note 1): city-art r15
  and hero-v3 r7 are still mid-round in the shared tree. Five takes were re-recorded before the hold
  landed; they are parked as **test takes** in `captures/trailer/shots_r15_test/` and are NOT in any
  cut. The authoritative set for `TIANSHU_trailer_v2a.mp4` is the one in `captures/trailer/shots/`.
  When the lead sends "re-record": `tools/trailer/render_all.py --force`, then `tools/trailer/cut.py`.
- `shots.json` already carries the part-B list (two extra takes, 64.95 s); `c_fp.avi` and
  `c_flight.avi` have been probed with `drive` (both film correctly) but not yet recorded as movies,
  so `cut.py` will not run to completion until the re-record.
- Still to probe when the hold lifts: the **spire collapse** (`flow/hive_collapse.gd`) now that
  camera-aim r7 has fixed the post-cinematic camera park.

## How to verify (exact commands)

```
# the stage scout (headless, ~30 s, no rendering)
tools/godot.sh test res://trailer/probe_stage.gd -- --stage=res://trailer/stages.json \
    --skip-menu --stub=flow --timeout=900 | grep -E "^STAGE|^  CAM|^RANK"
tools/trailer/scout_cams.py captures/trailer/scout/scout_scores.log --stages A6_garden,H0_pier,A3_plaza
tools/trailer/scout_shots.sh

# every take (resumable; --force re-records), then the edit
tools/trailer/render_all.py
tools/trailer/cut.py
tools/trailer/framing_report.py            # the per-shot framing evidence (--whole for the full take)
tools/trailer/sheet.py --spec game/trailer/shots.json \
    -o captures/trailer/sheets/TIANSHU_trailer_v2_shots.jpg --cols 4
tools/godot.sh check --only=res://trailer/
```

## Evidence

- `captures/trailer/TIANSHU_trailer_v2a.mp4` — the part-A rough cut.
- `captures/trailer/sheets/TIANSHU_trailer_v2a_shots.jpg` — one frame per shot.
- `captures/trailer/sheets/TIANSHU_trailer_v2a.jpg` — one frame every 1.5 s.
- `captures/trailer/logs/<take>.csv` — the per-frame framing logs; `tools/trailer/framing_report.py`
  turns them into the pass/fail table (11 takes, 0 failed).
- `captures/trailer/scout/` — 53 candidate stills + `sheet_stages.jpg`.
- `captures/trailer/scout/scout_scores.log` — 83 cameras scored over 11 arenas.
- `captures/trailer/sheets/ghost_mantis_hitflash.jpg`, `ghost_archetype_ab.jpg` — the ghost-enemy
  diagnosis (Requests #1).
- `captures/trailer/sheets/look_r14_vs_r15.jpg` — the same cold-open frame on city-art r14 and on
  r15 + hero-v3 r7, for the lead's "one hue" and "the hero is a silhouette" items. Not my work; kept
  because it shows why the final re-record is worth waiting for.

## Known issues

- **v2a is a camera-work rough cut, not a look reference** — the lead accepted it as such. Its takes
  were recorded across the window in which city-art r15 and hero-v3 r7 landed, so the film mixes two
  looks; that is why the final re-record is held.
- **The gatling muzzle flash is a ~10 m sprite.** In first person the eye is ~10 m from the muzzle and
  the flash covers a quarter of the frame as a flat yellow disc
  (`captures/trailer_fp2_t5_6.jpg`). Routed below.
- **A hit-flashed Mantis reads as a flat pale ghost** in four combat cuts. Diagnosed in Requests #1;
  it is the enemies unit's `flash_energy`, not a trailer artefact.
- `c_dodge`'s orbit passes behind a Sky Garden pillar after 3.0 s; the cut stops at 2.91 s.
- `c_missiles` is a deliberate wide: bbox 0.24, below the 0.25 hero floor, which is why it is a combat
  shot (the rule that applies there is "an enemy must read", and 2–4 do).

## Requests (to the lead / other units)

1. **monster-assets — the pale "ghost" is the MANTIS, and it is the hit flash, not the material.**
   (Lead note r2 part A, item 2. No enemy file was edited.)

   **Which archetype:** Mantis (14 m, `game/enemies/models/mantis/`). Proven by isolation, not by eye:
   two runs of the same take with a single-archetype pack —
   `--trailer-pack=24,mantis:3` produces the ghost, `--trailer-pack=24,ripper:6` never does, at the
   same timestamp and the same camera. Frames: `captures/trailer/sheets/ghost_archetype_ab.jpg`
   (top row mantis-only → ghost at frame left; bottom row ripper-only → no ghost).
   In the mantis-only run **one mantis is pale while another is green in the same frame**, so it is a
   per-instance state and cannot be the shared ShaderMaterial.

   **Hit flash or material:** hit flash. The same mantis across six frames of `c_missiles` —
   normal at 3.4 s, flat pale beige at 3.6–3.8 s, back to acid green at 4.0 s, while the lock-on
   distance readout climbs 40 → 57 m and the missile counter reads 8/12, i.e. the salvo is landing on it
   the whole time. Frames: `captures/trailer/sheets/ghost_mantis_hitflash.jpg`.

   **What makes it read as a ghost rather than a flash** (all in enemies-owned files, quoted not changed):
   - `game/enemies/enemy_base.gd:146` — `take_hit()` calls `set_hit_flash(0.6)`.
   - `game/enemies/visuals.gd:74-83` — `_flash = maxf(_flash, v)`, decayed at **6.0/s**, so one hit is
     ~0.1 s; a 12-missile salvo re-arms it every impact, which is why the pale state holds ~0.4 s.
   - `game/enemies/models/monster_body.gdshader:78` —
     `EMISSION = glow + rim * rim_color * rim_gain + vec3(hit_flash * flash_energy)`, with
     `flash_energy` defaulting to **4.0** (line 23). So a hit adds **0.6 × 4.0 = 2.4** of pure white
     emission — three to four times the monster's own `emission_energy` (2.0) and far over the bloom
     threshold. The albedo, the normal map and the acid veins are all still there; they are simply
     swamped, so the body flattens into an unlit paper cut-out.
   - **No `<type>_rig.json` "look" block sets `flash_energy`** — I checked all seven
     (`ripper`, `mantis`, `spitter`, `harrier`, `juggernaut`, `hive`, `titan`): each has
     `emission_energy`, `rim_gain` and `albedo_gain`, none has `flash_energy`. Every archetype is on
     the 4.0 default, so this is not a mantis-specific tuning slip; the mantis just reads worst because
     it is the tallest thin-limbed body in the pack and the flash covers all of it at once.

   Suggested routing (monster-assets' call, not mine): `flash_energy` is the one number that decides
   whether a hit reads as light or as a white cut-out — the shader's own header comment says the flash
   is "added, never multiplied into ALBEDO … a hit has to read as light", which is the right intent and
   is what 4.0 defeats at dusk. A per-type `flash_energy` in the look block, or clamping the additive
   term so the rim and the veins survive it, would fix every archetype at once.

2. **weapons — the gatling muzzle flash does not work in first person.** The flash sprite is ~10 m
   across; the cockpit eye sits ~10 m behind the muzzle, so it fills a quarter of the frame as a flat
   yellow disc with a hard edge. Frames: `captures/trailer_fp2_t4_4.jpg`, `captures/trailer_fp2_t5_6.jpg`.
   A distance-scaled (or view-facing-card) flash would fix it; this is the only thing that makes the
   first-person shot unusable as a hero frame.
3. **lead — the boss arena is roofed.** From the Crown deck (+224) every sight ray hits scenery within
   15 m in all eight bearings tested (`open` = 0.00, colliders `t3_3` / `t3_4`). MAP §4 describes B1 as
   "CIRCULAR (Ø 300 m, stepped rim, 4 fins 24 m tall)" — open sky. Whatever encloses it, the boss fight
   films as an interior: the deck reads as a red dome in every wide.
4. **lead — `game/override.cfg` is not in `.gitignore`.** `--movie-size` creates it for the run and
   removes it on exit, but a crashed capture leaves an untracked file in a lead-owned directory.
5. **flow — the spire collapse still needs a camera.** `flow/hive_collapse.gd` has the topple, the
   chained blasts and the smoke column; every gameplay take here stubs the flow, so the collapse is
   the one part-B verb still missing from the cut.

## r6 — note for the lead (11-09 12:05)

The lead accepted r6 at 11:55 and copied both reels to the Desktop. **The v2 copy there was the 11:48
cut, before the `c_parry` re-record**: at 12:01 I re-cut v2 with the parry take that keeps the mantis
off the lens (30.7 % -> 8.8 % of the frame at reel t=35.3 s), and at 12:04 I refreshed
`~/Desktop/天枢_预告片_v2.mp4` with it. Same length (64.48 s), same gates (-14.0 LUFS, -2.2 dBTP, 0
black, 0 frozen, framing 12 takes 0 failed). The showcase copy on the Desktop is unchanged and current.

## r6 — evidence

| what | where |
|---|---|
| the showcase reel | `captures/trailer/TIANSHU_showcase.mp4` (248.71 s, 621 MB) |
| trailer v2 | `captures/trailer/TIANSHU_trailer_v2.mp4` (64.48 s, 178 MB) |
| the per-shot sheets | `captures/trailer/sheets/TIANSHU_{showcase_segments,showcase_2s,trailer_v2_shots,trailer_v2_2s}.jpg` |
| the time-of-day A/B | `tmp/trailer/r6/tod_<take>.jpg`, `tmp/trailer/r6/tod/*.jpg`, `tmp/trailer/r6/ab_*.log` |
| the camera sweeps | `tmp/trailer/r6/sweep_{m3_spitter,g4_flight,s03_drop}.jpg`, `tmp/trailer/r6/g4.json` |
| the record logs | `tmp/trailer/r6/rec_{showcase,spitter,v2,titan,parry}.log` |
| the cut logs | `tmp/trailer/r6/cut_{showcase,v2,v2b}.log` |
| the framing CSVs | `captures/trailer/logs_showcase/*.csv`, `captures/trailer/logs/*.csv` |
| the r5 reels, backed up before the overwrite | `tmp/trailer/r6/r5_backup/` (754 MB — delete when the lead is happy) |
