# city-build r11 — lead brief: every designed route is drivable

## Why
The acceptance pass drove every connector with real inputs on a frozen copy at `b5d26d4`. The three dead-end tunnel
mouths are open: walk off the U5 lift pad and the mech falls below the world for good. 9 of 14 up-shafts are capped by
the level they serve and the other 5 end in mid-air; a Crown rib fills the S4 pad column; hive A2 cannot be entered,
and A6 only by a climb nobody designed. Pillar 4 is "loops, not dead ends", and no gate noticed. The new **traversal**
unit moves the player on lifts, vcats, vents and lcats; yours is the geometry a ride can use and the data it reads.

## Rules for this round
- **Evidence:** `~/m/mc-lead/accept/findings_all.json` (its `check` block wins; logs in
  `~/m/mc-accept/tmp/acc/verify-<id>/`): `map-u5-tunnel-open-end-fall`, `map-up-connectors-inert`,
  `map-hive-a6-a2-routes-dead`, and only part (1) of the refuted `map-s4-catapult-pad-unreachable` (flow r5 has (2)).
- **Re-check at HEAD:** `git diff b5d26d4 HEAD -- blender/city game/world/city tools/city tools/map data/map` is
  empty; run each probe on HEAD first (your "before") and report any number that does not reproduce.
- **Probes:** copy each with its `end.json` from `~/m/mc-accept/game/tmp_accept/<folder>/` to
  `game/world/city/tests/acc/`; fix the `.tscn` script paths and the hard-coded `/Users/minimax/m/mc-accept`
  (`u5_probe.gd:15-16`, `conn_probe.gd:21`, `conn_landing.gd:15`), write to `tmp/city-build/r11/` and
  `captures/city-build_r11_*`, and keep them passing `check`. Run them from this tree only: `tools/godot.sh drive
  --timeline=res://world/city/tests/acc/end.json --scene=res://world/city/tests/acc/<p>.tscn --skip-menu --god
  --no-enemies --stub=flow,boss --quality=low` plus the probe's `--s4v=`, `--vtest=` or `--acc-trav=`. `drive` stops
  at 600 s: split `trav_probe` (397 s) with `--acc-trav=`. Real inputs only; a teleport only places a trial's start.
- **Not yours:** `data/map/**`, `tools/map/**` (city-layout r8 runs; data asks go to Requests) and `game/flow/**`.
  Split `checks.gd` (546 lines) before it passes 600, as its own commit. Commit per item, explicit paths, no dead
  code. A new check FAILS on HEAD and PASSES after (both runs in status); nothing is fixed till the rerun shows it.
  Report in `status/city-build.md` (section "Round 9 (lead r11)"). **Order:** 1–5 now, 6–7 after layout r8.

## 1. The dead tunnel ends drop the mech out of the world — major
`kit/corridors.py:209-210` gives every tunnel end an open `_portal`, dead ends too, and `kit/connectors.py:92` centres
the 40 × 40 lift pad on the end: at U5 (Blender 0,260,−40) it spans y 241–279, half past the tunnel over nothing down
to −3,000. U4 (`tunnel_U4_U1`'s first end) and U6 (`tunnel_U3_U6`'s last end, the Maglev Depot reward) are the same,
and the uncut roof (`corridors.py:198-201`) catches the O7→U4 drop at −4 instead of the −37 pad. **Repro:**
`u5_probe`, `ray_probe` (`verify-map-u5-tunnel-open-end-fall`): W1 (forward + boost) leaves the U5 pad at 1.23 s and
ends at feet −512.6; ENDRAY finds no wall within 200 m; the drop's first hit is −4.0.
- **Done:** each dead end is walled round its pad or shaft (end wall, side walls to the ceiling), with the roof open
  over the shaft. Dead ends come from the data (an end no corridor or connector continues). A new city check asserts
  this for every corridor end and FAILS on HEAD at U4, U5 and U6.
- **Gate** (U4, U5, U6, real inputs): boost 5 s out from the pad and from 60 m in, walk 6 s out: feet stay above −41.
  ENDRAY: a wall ≤ 5 m past the last floor. The O7→U4 drop lands at −37 ± 1. Captures: each end, before/after.

## 2. Nine shafts are capped by the level they serve — major
`kit/terrain.py:61-69` cuts the crust and plateau for every lift, vent and vcat pad; decks (`kit/decks.py:106` cuts
only declared `holes`), the tunnel roof and the Spire are not cut. Top feet / first ceiling in `conn_r1.log`: U4_O7,
U5_S5 −21/−6 (tunnel roof; U5 then S5_forum); A5_W4 lift, A5_W5 vent 13/28 (W3_foundry_l2, then W4); W3_W4 vcat,
V3_F6, S1b_S3s 59/74 (W4_foundry_l3, F6_skydeck, S3_collar); F7_F4 vent 18/33 (canopy_st_H5_F2_1, then the A6 garden,
underside 138); S3n_S4 is item 3. The lift's 46 × 46 × 6 m top cap (`connectors.py:99`) is render-only, over the top
stop. **Repro:** `conn_probe` (`verify-map-up-connectors-inert`): CONNUP `stop=stalled`.
- **Done:** every lift, vent and vcat column is open from its pad to its top stop + 16 m (a vent for its whole
  `rise`), the stop flush with the floor it serves and no parapet between (at S3n_S4 the S4 ring's slab and 6 m
  parapet cross the shaft's inner 14 m). Derive the openings from the connector rows at build time (like
  `ground_cuts`), never by hand or in `data/map`. Nothing render-only over a shaft; `markers.py::_floors` (:159)
  exports the openings, or C18 calls them missing floor. `con_S4_B1_vcat` is flow's (Coordination). In Requests, list
  each opening in an arena floor or on a node another connector uses (e.g. A5_W4 at (470,−200), where the W3_W4 vcat
  lands): the opening follows the data; the data decides.
- **Gate:** `conn_probe` shows no `stop=stalled` for the nine (running out of EN is not a geometry fail), C12 sweeps
  each column clear, and C18 PASSes. Captures: up-shaft stills at V3_F6, S1b_S3s, A5_W4, before/after.

## 3. A Crown rib stands on the S4 pad and caps the S3n→S4 shaft — major
`kit/spire.py:171` (`ang = j·τ/10 + π/10`) puts rib j = 2 on the north axis. By `spire.py`'s own formula it covers x
−10..10 of the whole S4 vcat pad (0,210,160) from z 162 to the soffit (218), and x −10.5..10.5 of the
`con_S3n_S4_lift` shaft (0,230) from z 144.5; its step-3 underside (156.75) stops the ascent at feet 141.7. Not a
blocker: climbs 18° either side reach the ring and fire the catapult. **Repro:** `s4v_probe --s4v=stub`
(`verify-map-s4-catapult-pad-unreachable`): `lift_shaft_S3n … top 141.7 stop=ceiling`.
- **Done:** no rib collision over the pad (44 × 44 m, z 162–218) or the shaft (40 × 40 m, z 80–176): notch rib j = 2
  (the lead confirms at dispatch). A half-pitch rotation clears both centres but stands the 72°/108° ribs on the pad's
  outer 10.5 m each side (x ±11.5..22) and on the shaft's corners. The notch reads as the catapult's well.
- **Gate:** from the S3n pad (θ 90°, r 110, feet 80) jump held reaches feet ≥ 176 (HEAD 141.7); a 3.5 × 15 m capsule
  fits at the pad centre; `S4VSURVEY th=90` opens to 218. Captures: V7 and the `r3S1–4` Spire frames, before/after.

## 4. The checks that should have caught this — major
C17 skips a jump that never lands (`checks.gd:518`) and divides by `landed` (:529), so a void counts as nothing; C16
samples only within 30 m of the ±700 edge (:473), and U5 is 440 m in. C12's stairs arc has 3 points (:207-208), so
`range(1, pts.size() − 2)` (:182) sweeps nothing (and `nav_links` carry no `path`, `markers.py:60-63`); its vertical
kinds are a straight `from`→`to` line (:200-206), not the column built at `from` (`connectors.py:76`).
- **Done:** C17 reports each never-landing arc as a VOID with its start, a hard gate at 0 kept apart from the
  informational off-navmesh share; it FAILS on HEAD at U4, U5 and U6 (sample there) and PASSES after item 1. C12
  sweeps stairs along their flights and each mover as built from the item-5 rows (up the column, onto the exit).

## 5. Export the movers for traversal — major (traversal is blocked on it)
Nothing moves the player on 17 connectors (11 lifts; vcats W3_W4, M3_M4; vents F7_F4, A5_W5; lcats F5_S4, M4_S4).
Traversal writes that runtime from what you export; today's `layout.json["nav_links"]` has no pad, stops or `params`,
and its `from`/`to` are graph nodes, not where you built the pad.
- **Done:** `layout.json["movers"]`, one row per lift, vcat, vent and lcat (18, flow's `con_S4_B1_vcat` included), in
  Blender metres, written through one helper shared with `kit/connectors.py` so it cannot drift: `{id, kind, edge,
  oneway, pad: {center: [x,y,z], size: [w,d]}, stops: [z_from, z_to], exit: [x,y,z], params: {rise | range,
  no_boost_s}, usable, why}`, where `pad.center.z` is the boarding floor's top, `stops` the floors a lift or vent is
  flush with (none for vcat/lcat), and `exit` a standable point where the ride lets go. `city_markers.gd` adds one
  `Area3D` `Mover_<id>` per row in group `&"mover"` (`Layers.TRIGGER`, `monitoring = false` for traversal to turn on,
  box = pad × 24 m) with Godot-space metas `mover_id`, `kind`, `pad_top`, `pad_size`, `stop_top`, `exit`, `params`,
  `usable`. Publish the format in Requests on day one; later changes go through the lead, who writes CONTRACTS §7.
- **Gate:** a movers block in `test_city.gd` (FAILS on HEAD): a row and a node per mover, metas equal to the row,
  `pad_top` within 0.5 m of a floor hit, every `usable` exit standable (floor ≤ 1 m below, capsule free).

## 6. After layout r8: every usable ride ends on its `to` floor
`conn_landing`: S5_S3n, F3_F6, M6b_M4, M1_M5 and A5_W5 end in mid-air 100–233 m from their `to` node (only the 3 m
corner posts on top); U5_S5, V3_F6, S1b_S3s and S3n_S4 open 20–85 m off theirs. Alignment is data: report a lift or
vent that r8 leaves out of plumb (build log, C12); never move it yourself.
- **Done:** rebuild on r8 (`build_city.py`, `assign.py` if the layout moved, the nav and settle bakes). Every `usable`
  mover ends grounded within ±5 m of its `to` floor and ≤ 30 m of the node in plan (C12 as built, `conn_landing`). One
  that cannot work (e.g. `con_B1_A3_lift`, built inside the Spire's core) gets `usable: false` and the reason, its nav
  link stays off, and a Request goes to city-layout (L1 wants every edge realised); never delete a prop on your own.
- **Gate:** C12 shows 0 blocked for lift, vcat, vent, lcat and stairs.

## 7. After layout r8: hives A2 and A6 each get three designed ways in
A2's K3 tier (+32) has no way in: both Ring Viaduct W ends meet K3's 5 m parapet (`decks.py:125` walls the whole
polygon) under the K4 flyover at 52.0, leaving 14.8–15.1 m for a 15 m capsule; the mech wedges at feet 37 and `vprobe
rimscan` finds 0 of 369 bearings crossable. A6's stairs run under the garden slab and its vent is item 2.
- **Done (yours):** a deck's parapet opens wherever a corridor, viaduct or connector meets it, derived from the data,
  and its `edges` row (`markers.py:218`, read by city-kit's railings) opens with it.
- **Gate** (r8's data, real inputs): ≥ 3 designed inbound routes per hive end grounded within 5 m of its tier (today
  A2 from both viaduct ends and K1, A6 by the F6 stairs and the F7 vent; r8 owns A6's third). On a mover route your
  part is the column sweep and climb. Run `vprobe
  --vtest=stairs,vent,via_v2,via_v7,rimscan,parapet_v2,parapet_v7,helix` and `trav_probe
  --acc-trav=con_F6_F4_stairs,con_F7_F4_vent,con_K1_K3_ramps`. Captures: the K3 entry and the A6 stairs' top.

## Gates
- `tools/godot.sh check` is clean, no file is over 600 lines, and `tools/godot.sh test
  res://world/city/tests/test_city.gd` PASSES.
- `tools/city/checks.sh`: the dead-end check, C16 and C18 PASS; C17 VOID = 0; C12 0 blocked for movers and stairs
  after item 6 (after items 1–5, list the off-plumb columns still failing). Paste the C12–C18 lines, before and after.
- After every rebuild: `tools/city/bake_nav.sh`; `SETTLE_BAKE=1 tools/godot.sh run res://tools/float_audit.tscn 600`
  (STRUCTURE stays 0); `tools/godot.sh test res://world/art/tests/test_settle_cache.gd` and `test_float.gd`;
  `tools/city/nav_report.sh`; `tools/godot.sh run res://main.tscn 20` (errors=0).
- The probes on HEAD and on your final commit, logs in `tmp/city-build/r11/`: `u5_probe`, `ray_probe`, `conn_probe`,
  `conn_landing`, `s4v_probe --s4v=stub`, `vprobe`, `trav_probe`. Captures in `captures/city-build_r11_*`, listed in
  your status. The lead re-runs the probes and `checks.sh` on a fresh copy of your final commit.

## Coordination
- **city-layout r8** owns `data/map/**` and `tools/map/**` (the zero-run stairs, the hive approach data). Rebuild when
  it reports done; send it data problems via Requests (off-plumb lifts, the shared A5 pad, dead edges).
- **traversal** (new) writes the rides and reads only `movers` and the `&"mover"` nodes; you write no runtime.
- **flow r5** owns the fall-out respawn, PAUSE → ABORT and the catapult on the deck. Its respawn gate is a teleport,
  so your caps do not break it; say when they land. It compensates for the +20 m in `_zone` (`city_markers.gd:145`):
  do not move the zone origin. A Crown opening over S4, if flow asks, is the lead's to route (Crown `holes` are layout
  data; the rim discs in `decks.py::_crown` :150-156 ignore holes). Land item 3 early: flow's launch gate needs it.
- **city-kit:** railings follow the new `edges` gaps. **city-art r16** re-bakes the settle cache too: bake once more
  at the very end, and tell it about the notch (the Spire is in every vista). **trailer:** its A6 stage gets the vent.
- No ownership exceptions this round. Requests go in your status's Requests section.

## Lead decisions (read first)
`reviews/r16-lead-decisions.md` holds the lead's dispatch decisions. Read its "Shared" section, and every section that names this unit, including those under "Round 2". Where a decision and this brief differ, the decision wins.

## Dispatch note from the lead (11-05 10:45)
city-layout r8 is committed (437e0b9, md5 615d1f71…) but does not pass yet: 18/40 connectors pass
a–d. city-layout r8b runs in parallel to finish it. Work in this order:
1. Do the items that do not depend on the layout first: the tunnel dead ends, the Crown rib notch,
   the movers export (publish the format on day one, for traversal) and C17.
2. Then build on r8 for the layout-dependent items.
3. Rebuild once more when city-layout posts its r8b commit.
Re-bake the settle cache after each rebuild (`reviews/r16-conflicts.md`, F1). Lower the 3 m lift pad
lips, and move the H3 crane cab collider (Round 2 decisions).
