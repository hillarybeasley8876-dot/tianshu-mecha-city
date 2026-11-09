# traversal r1 — lead brief: the lifts, catapults and vents carry the mech, the three ways onto S4 first

## Why
The acceptance pass found that 17 of the city's 58 layout connectors are scenery: 11 lifts, the vcats W3_W4 and M3_M4,
the vents F7_F4 and A5_W5, the lcats F5_S4 and M4_S4. They wear the cyan "up" accent ART.md §2 reserves for this, yet
a mech standing on one goes nowhere: nothing in `world/`, `flow/` or `core/` moves the player except flow's S4→B1
Ascension Catapult, and `city_nav.gd:94-112` makes each row an AI-only NavigationLink3D. Worst is S4, where the boss
catapult is boarded: its three non-flight ways in (`level_graph.json`: S3n→S4 lift, F5→S4 lcat, M4→S4 lcat) are inert,
so the boss is reached only by free flight or a thruster climb between Crown ribs. You build the runtime; geometry stays
city-build's, endpoints city-layout's. Findings in `~/m/mc-lead/accept/findings_all.json` (the `check` block wins):
`map-up-connectors-inert` (major, reproduced) and `map-s4-catapult-pad-unreachable` (filed as a blocker, corrected to
major; its rib and pad halves go to city-build and flow r5). Both were made on the frozen copy at **b5d26d4**; `git
diff b5d26d4..HEAD` is empty on `game/world/city/`, `blender/city/`, `data/map/`, `game/flow/` at dcedb13. Re-check
each claim on HEAD before you build on it; if one is already fixed, say so in status with the run.

## You own, and read first
- **Own:** `game/world/traversal/**` (new: runtime, `traversal.tscn`, `tests/`), `status/traversal.md`,
  `captures/traversal_*`, scratch in `tmp/traversal/`. Global class_names start with `Trav`.
- **Read:** `ref/research/level-design-vertical.md` §3.4, §5.3 (edge times, arc formula), C12; `docs/MAP.md` §1 (capsule
  r 4 h 16, fall gravity 25.5 for C12 arcs only, the mech falls at 80 per SPEC §4, ceiling +260); CONTRACTS §5, §7;
  `flow/ascension_catapult.gd` (your pattern), `crown_gate.gd`; `blender/city/kit/connectors.py`, `spire.py:163-184`;
  `world/city.gd`, `city/city_nav.gd`, `city/tools/checks.gd:157-201` (C12). Evidence, read-only:
  `~/m/mc-accept/tmp/acc/verify-map-up-connectors-inert/` (`conn_r1.log`, `landing_r1.log`, `shaft_static.txt`, frames)
  and `…/verify-map-s4-catapult-pad-unreachable/`.

## 1. Baseline: standing on a connector does nothing — major [map-up-connectors-inert]
- **Repro:** copy `~/m/mc-accept/game/tmp_accept/spec-coverage/trav_probe.{gd,tscn}` and `end.json` into
  `game/world/traversal/tests/` (fix the `.tscn` script path and the TAG), then `tools/godot.sh drive
  --scene=res://world/traversal/tests/trav_probe.tscn --timeline=res://world/traversal/tests/end.json --skip-menu --god
  --no-enemies --stub=flow,boss --quality=low --acc-trav=con_S3n_S4_lift,con_F5_S4_lcat` → `pad_idle_3s: rise=0.0m
  moved=0.0m` on both, the lift's climb stops at `ascend_top_feet=142 blocked=true`. The verifier's
  `…/tmp_accept/verify-map-up-connectors-inert/conn_probe.gd` (copy it the same way, fix its `OUT`) adds 18/18
  `idle_rise=0.00m` and 9 of 14 up-shafts sealed overhead; its `conn_landing.gd` (same copy, `OUT` at `:15`) shows
  the 5 open columns ending in mid-air 100–233 m from `to` (`landing_r1.log`).
- **Then write your own `trav_probe`**, the round's main gate. Per connector, and per direction for `oneway: false`
  lifts: place the mech on the start floor ≥ 30 m from the pad (the only teleport), walk on with `move_*` (boost-skating
  allowed; log `board=walk|hop`), no input during the ride, then walk to `to`. One line each: `TRAV <id> dir=… ride_s=…
  model_s=… REACHED|FAILED|BLOCKED(<collider> y=…)`. REACHED = grounded, feet ±5 m of the probed `to` floor, ≤ 30 m from
  `to` in plan; no jump, ascend or flight input. An id filter keeps drives under 600 s (tooling r1 adds `--timeout=`).

## 2. The runtime: four kinds of ride — major [map-up-connectors-inert]
Read the rows from `Game.world` (`layout["nav_links"]`, `to_godot()`: `city.gd:73`, `:116`); skip `con_S4_B1_vcat`
(flow's catapult) and `con_B1_A3_lift` (Coordination). `layout.json` has no `params`: derive rise, range and pad from
`from`/`to`/`width`; a test asserts they match `data/map/city_layout.json` `connectors[].params`. Probe floors by ray,
never datum z (the Crown floor is 225.5, not 224: `status/city-build.md` Request 27). Lift and vent shafts stand at
`from` x,y between min and max z (`connectors.py:74-89`); vcat and lcat pads sit at `from`.
- **lift:** 40 × 40 m platform, ride 3 s + Δz/16 (dossier §5.3), both ways unless `oneway` (U4_O7); boarding either end
  rides with no call wait, feet end level with the far floor, a render-only platform visibly carries the mech.
- **vcat:** one-way arc, Δz 48–144 m in 2–4 s (model 1.5 + Δz/60 + h/80: W3_W4 2.6 s, M3_M4 3.9 s).
  **vent:** one-way updraft from the grille, Δz ≤ 150 m (both 144), model 1 + Δz/40 s.
- **lcat:** `range` 300–600 m in 4–6 s (model 1 + d/120: F5_S4 5.5 s, M4_S4 6.0 s); boost refused for the first
  `no_boost_s` = 1.5 s; untouched, it lands on the target floor every time; after 1.5 s a boost press ends the path and
  hands its velocity back (the dossier's risk-reward).
- **Pattern** (`ascension_catapult.gd`): Area3D on `Layers.TRIGGER`, mask `Layers.PLAYER` only (`:43-49`);
  `invulnerable_for` + `lock_movement` while carried (`:146-150`); position written each tick on `Feel.real_delta`, zero
  velocity (`:174-191`); control back with an exit velocity so the landing is a real `Events.landed` (`:196-207`).
  Traps: `lock_movement` only extends (`mech_locomotion.gd:370-372`, no early release), and that arc runs through deck
  tiles because nothing sweeps it (flow r5 item 2). Sweep every ride path with the C12 capsule (r 4, h 16) at ≤ 0.1 s
  steps on `Layers.WORLD`; a path that hits stays disarmed and `push_warning`s the collider and height once.
- **Not yours:** pads, columns, caps, decks (city-build), endpoints (city-layout); add no WORLD/PROPS collision (the
  navmeshes bake offline from WORLD). E.g. the 3 m lift pad (`connectors.py:96-98`) tops the 2.5 m `step_height`
  (`mech_tuning.gd:105`), so a walking mech cannot step on: a Request with the number, not a collider of yours.
- **Gate:** `tools/godot.sh test res://world/traversal/tests/test_traversal.gd` (rows and params, durations ±15 % of the
  model, item 5's rules, nothing on WORLD/PROPS); the probe: `ride_s` ±15 % of `model_s`, every line REACHED, or BLOCKED
  with its blocker in your Requests. The probe is the test that must fail on the old code: keep its pre-runtime run
  (every line FAILED, `rise=0.0`) beside the final one, both on the same city commit.

## 3. S4 first: S3n→S4 lift, F5→S4 lcat, M4→S4 lcat — major [map-s4-catapult-pad-unreachable, map-up-connectors-inert]
Build these three first, against geometry that is city-build's and partly changing this round:
- **Ribs** (`spire.py:163-184`): 10 at j·36° + 18°; at mech height each is a ~20 m wall across the ring (step 3: z
  156.75–169, r ≤ 110.8, half-width 10.1), so the S4 ring is 10 walled bays. Rib j=2 sits on θ 90°: the S4 node
  (Blender (0,210,160)) is inside it, and it caps the S3n lift shaft (Blender (0,230), r 110) at feet 141.7.
- **The lift's top:** ~13 m of the shaft overlaps the ring (r ≤ 104) and its parapet (top ≈ 166); the render-only
  46 × 46 × 6 m cap (`connectors.py:99`) fills z 160–166.
- **F5→S4:** the straight plan line from F5 (−40,−330,176) passes 6.6 m from the Spire axis (0,120), through the trunk
  (r ≈ 37–60 at z 160–218) under the soffit (218); the catapult's bay opens only to the north. M4→S4's line runs inside
  today's 54°–90° bay into rib j=2; after an 18° phase shift it would cross the 72° rib instead.
- **The catapult:** flow r5 puts its pad on the deck at Godot (0,160,−210) = S4; its trigger (r 16 m, y pad−4 … pad+20,
  `ascension_catapult.gd:59-66`) fires on `body_entered` in any state, and the S3n lift platform (20 m off) overlaps it.
- **Done:** each ride lands a grounded mech on the ring (feet 160 ± 2) in the catapult's bay, ≥ 20 m from its centre and
  never in its trigger, so boarding stays deliberate; if no swept F5→S4 path fits 4–6 s, show the sweep, propose a fix.
- **Gate:** flow live (no `--stub=flow`), a flow script (`flow_debug.gd:1-15`: `clear_arena A1`, `kill_spire 0..2`,
  `wait_state boss_gate`), then per route a start ≥ 30 m from its pad (S3 collar, F5, M4) and real inputs only: walk
  on, ride, walk onto the catapult → `launched`, state `boss`, `DRIVE done … errors=0`. Run it after flow r5's pad
  commit and city-build's rib commit; name both commits in status.

## 4. They read on screen — major (lead item)
- **Armed:** a render-only cyan-white accent of yours per pad (`McMaterials.accent_variant`, `material_library.gd:493`;
  `ArtPalette.NEON_CYAN`). The baked `mc_up_accent` strips pulse forever and cannot show state, so yours reads clearly
  brighter armed than riding, cooling or blocked; a connector that cannot ride shows no armed light.
- **The ride:** lift = the platform rising, servo sound; vent = an updraft column, thrusters lit (`set_thrusters`);
  vcat, lcat = launch ring, thruster burst, trail, as the catapult's `_launch`. Existing ids: Feel `boost_start`
  `assault_boost` `land_heavy` `overdrive_ignite`; FxBridge `thruster_burst` `shockwave_ring` `dust_ring` `steam`; Audio
  `hydraulic_release` `servo_move_l` `boost_start` `assault_boost` `amb_wind_high` `flight_loop`. An unknown sound id
  warns (`audio.gd:310-314`); new sounds or a FEEL row are Requests. The hero stays in frame through every ride (if
  the rig loses it: a short `request_cinematic` like the catapult's `_shoot`, or a Request to camera-aim).
- **Gate:** per kind a walk-on-to-arrival movie (`tools/godot.sh movie --movie=$PWD/captures/traversal_<kind>.avi …`)
  and its sheet (`uv run --with pillow python3 tools/trailer/sheet.py <avi> -o captures/traversal_<kind>_sheet.jpg
  --every 0.5`); an armed/idle pair of one pad at `--tod=0` and `--tod=1`. All in status.

## 5. What must not break — major (lead item)
- **AI:** a ride never moves an enemy; the NavigationLink3D set is unchanged (count, enabled per class).
- **Start** only on a deliberate entry: grounded on the pad (lift, vcat, lcat) or in the vent's mouth. Never from a
  teleport or respawn onto a pad (`debug_teleport`, flow checkpoints, the E2E bot's stands), a fly-over (`is_flying()`),
  a dead mech or a cinematic. **End:** `Events.player_died` (`events.gd:41`) or any other move of the player ends the
  ride that tick, no writes after. `--sandbox` has no layout: traversal does nothing there.
- **Gate:** test_traversal (an ENEMY body on a pad stays put, a teleport onto a pad does not launch, a death mid-ride
  stops the writes); `test_city`; `nav_report` against your pre-runtime run on the same city commit; flow's suite.

## Gates
```
tools/godot.sh check                                                   # 0 errors (also --only=res://world/traversal/)
tools/godot.sh test res://world/traversal/tests/test_traversal.gd     # 0 failures
tools/godot.sh drive --scene=res://world/traversal/tests/trav_probe.tscn \
  --timeline=res://world/traversal/tests/end.json --skip-menu --god --no-enemies --stub=flow,boss --quality=low \
  [--trav-ids=…]                                                       # each TRAV line REACHED or BLOCKED(named)
<item 3's S4 run, exact command in status>                             # 3 routes: launched, state boss, errors=0
tools/godot.sh test res://world/city/tests/test_city.gd               # 0 failures (NavigationLink3D count)
tools/city/nav_report.sh                                               # enabled links per class = pre-runtime run
tools/godot.sh test res://flow/tests/test_flow.gd -- --sandbox --flow --spawn=0,1,60
tools/godot.sh run res://main.tscn 20                                  # errors=0
tools/godot.sh perf --skip-menu --no-enemies --warm=90 --spawn=-583,14,640,-37.5   # draw calls ≤ pre-runtime + 60
```
- **Captures:** the four sheets, the armed/idle pair, and per S4 route the arrival, the walk onto the pad, the launch.
- **House rules:** files ≤ 400 lines (split before 600, in its own commit), no dead code, explicit path lists
  (`git commit -m "traversal: …" -- <paths>`), an r1 section in `status/traversal.md`, no "REACHED" without its rerun.

## Coordination
- **Wiring:** `main.gd` PARTS is the lead's; until it lists `traversal.tscn`, your probes add it themselves and log it.
- **In parallel:** city-build opens the sealed shafts and the S4 rib (read its status; re-run your probe after each of
  its commits and name it); city-layout fixes stairs data; flow r5 moves the catapult onto the deck and re-arms it;
  tooling r1 (wrappers, `drive --timeout=`); mech-move r7, camera-aim r8, hud r6, audio r6, feel r5. hero-v3 has
  uncommitted work: stage only your own paths.
- **No ownership exception.** Read-only: `game/flow/**` (the catapult is group `&"flow_catapult"`),
  `game/world/city/**`, `blender/**`, `data/**`, `game/player/**`, `game/core/**`.
- **Requests** (status Requests section), with your sweep's numbers. city-build: per connector the blocker (collider,
  y, plan point) and the opening needed; the 3 m lift lip; the render-only lift cap; the S4 parapet at the lift's top.
  city-layout: the five mid-air columns (S5_S3n 100 m, F3_F6 180, M6b_M4 233, M1_M5 106, A5_W5 177 from `to`) and the
  one pad `con_A5_W4_lift` and `con_A5_W5_vent` share (`from` (470,−200,0)). flow: only if a ride cannot keep out of
  the catapult trigger. audio, feel: ids and rows. lead: the PARTS row.
- **Not this round:** `con_B1_A3_lift`, the Crown exit lift (its shaft is buried in the Spire core: pad on the plinth,
  sealed at 16.8 m; it only matters after victory), and lifts as enemy spawns (dossier §3.4 note).

## Lead decisions (read first)
`reviews/r16-lead-decisions.md` holds the lead's dispatch decisions. Read its "Shared" section, and every section that names this unit, including those under "Round 2". Where a decision and this brief differ, the decision wins.
