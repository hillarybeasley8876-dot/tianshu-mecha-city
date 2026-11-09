# hero-v3 r8 — lead brief: close-up polish (the grille, the visor), the flight pose, the drone API

## Verdict on r7: ACCEPTED
The hero reads now. At the trailer's cameras the dark-pixel share fell 49.1 → 7.9 % (s01),
29.8 → 6.0 % (s03) and 31.1 → 5.3 % (s04), and hero/ring went 0.19 → 0.54. The trim is gold and the
plates are darker than the trim in 16/16 frames. The lead re-ran
`check --only=res://player/model/hero3/` (66 files, 0 errors) and `test_hero3_shade` (PASS), and looked
at `captures/hero3_read_before_after.jpg`, `hero3_look_vs_concept.jpg` and `hero3_glow_vs_concept.jpg`.
The vertical portcullis is right: the concept is vertical, and the lead's "horizontal" was wrong.

**Ruling on `GOLD_GLOW`:** keep the trim a metal that follows the environment. Do not raise
`GOLD_GLOW` to pass the 3 front-on, orange-lit frames: a self-lit trim reads as paint. Those 3/16
misses are accepted with that cause.

## 1. The grille interior is smeared
In `hero3_glow_vs_concept.jpg` (all four tods), the inside of the chest grille carries cream/white
blotches and a smeared bright patch between the bars. It reads as noise, where the concept shows clean
gold bars over an even amber glow that is brightest at the centre.
- Find the cause: the atlas showing through the additive panel, the panel's own feather texture, or
  the bars' albedo.
- Make the grille read as the concept: dark gaps, gold bars, an amber core glow, no white blotches.
- **Gate:** the 3× crop sheet again at 4 tods, beside the concept crop. Inside the grille mask, the
  share of pixels with saturation < 0.25 and value > 0.8 (white blotches) is ≤ 1 % (measure today's
  first).

## 2. The visor streak sticks out of the helmet
The amber slit extends past the helmet's silhouette on the right, like a glowing rod (visor crops, all
tods). Keep the slit inside the visor opening, with a thin hot core and a soft glow that bloom may
spread, but no geometry outside the helmet.
- **Gate:** the crop sheet; from the front, side and 3/4 views, no visor-panel pixel lies outside the
  helmet's screen mask.

## 3. The flight pose
mech-move r6 made flight work from every state (567027e). The hero still flies as a standing hover:
`captures/mech-move_flight_t*.jpg` and `tmp/camera-aim/flight_city_sheet.jpg`. Give flight a pose
language:
- a forward lean with speed, up to about 25° at the 50 m/s cruise and more under the 84 m/s flight
  boost;
- a bank into turns, from yaw rate;
- legs trailing back and together;
- the wing binders opening;
- thrusters (already lit) that point along the thrust.

Blend in and out with `is_flying()`, and keep the aimed rifle and the melee aerial combo working. Use
the existing clip/IK layers; no new rig.
- **Gate:**
  - film `res://player/mech/timelines/flight.json` (`--sandbox`) and a city flight;
  - a strip showing the climb, cruise, bank, boost and descend;
  - the lean and bank angles in the log, against speed and yaw rate;
  - `test_hero3_states` and the air-state suites still pass;
  - no interpenetration over 5 cm in the flight poses (your r4 gate).

## 4. The per-drone hide API (from skills r4)
skills r4 runs in parallel and will request an API to hide or show individual blade drones, so that
docked blades disappear while the Corona Fins are out. Hero3 has 7 drones: Drone_1–4 on `wing_l` and
5–7 on `wing_r`.
- Watch the Requests section of `status/skills.md` and implement the exact signature they ask for,
  beside `set_wings` in `hero3_rig.gd`.
- The modelled cyan tips in `hero3_glow.gd` must hide with their drones.
- **The lead's mapping decision:** `fins_max` stays 6, with 3 fins per side, and one `wing_l` blade
  always stays docked.
- **Gate:** a unit test for the API, plus stills with the fins out showing no docked copy of a deployed
  blade.

## 5. Re-run the palette and the read gates on city-art r16
city-art r16 is bringing the golden-hour warmth back and may change the sky plates. When
`status/city-art.md` reports r16 done, re-shoot `tmp/hero-v3/gates.sh look` and `read` and update the
tables. If r16 has not landed by the end of your round, say so and leave it to the lead.

## Optional (do it only if items 1–5 are done)
camera-aim r7 request 0f: in first person the pilot no longer sees the chassis (the hero is culled
from the FP camera). A lowered-weapon cockpit pose that keeps the arms out of the lens would let
camera-aim show the hands. Propose it in Requests; do not change camera files.

## Gates (all)
- `tools/godot.sh check --only=res://player/model/hero3/` is clean, every hero3 suite passes, and
  `test_damage` passes.
- The sheets: the grille and visor crops (4 tods, against the concept) and the flight strip (sandbox
  and city).
- The new API test fails before and passes after.
- `status/hero-v3.md` gets an r8 section.

## Coordination
- skills r4 (the fins; the request for item 4), city-art r16 (the light) and mech-move r7 (the death
  gate in `player_mech.gd`) run in parallel. Do not edit their files.
- Read `reviews/r16-lead-decisions.md`, section "Shared": never use git stash, and commit with explicit
  path lists.
