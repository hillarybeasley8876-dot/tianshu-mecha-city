# trailer r2 — lead review of v1, and the r2 brief: a combat stage, a camera kit, a shot list with variety

## Verdict on v1
**The pipeline: accepted.** One command re-renders every take, the cut is bar-aligned, every take
ran with 0 engine errors, the loudness is right, and the Requests list is precise. Keep all of it.

**The film: not accepted. It does not go to the user as "炫酷实机" yet.** The lead's frames are in
`tmp/lead/r15/`:
- `combat.jpg`: 13.5 / 17 / 27.5 / 34 s;
- `grid.jpg`: 2–42 s;
- `hero_vs.jpg`: the concept beside the A1 spawn.

Four things are wrong:
1. **The combat is unreadable, and it is 40 % of the film.** Shots 5–12 (≈ 25 s) are one game camera
   on one fight in the Civic Quarter.
   - The hero is a black blob at the left edge of the frame.
   - No enemy reads anywhere.
   - In `s04_melee` from 5.4 to 7.2 s the camera points at the city and the hero is out of frame.
   - The frame is a wall of dark boxes with lit-window grids. Nothing in it says "fight".

   You diagnosed this yourself in Known issues: the fix is a different stage, not another camera at
   the same spot.
2. **The whole film is one hue.** At `--tod=0.6` the city is orange-brown everywhere and the shadows
   crush to black. *Not yours:* city-art r15 is fixing the sky and the colour of the light now.
3. **The hero is a silhouette in every shot**, even against the boss's bright pink sky. *Not yours:*
   hero-v3 r7 is giving the armour emissive accents and a gold that reads.
4. **Missing verbs.** First person, flight and a spire falling are not in the cut. *Not yours:*
   - first person goes to camera-aim r7;
   - flight goes to mech-move r6;
   - the spire fall already exists (`flow/hive_collapse.gd`: the topple, the chained blasts, debris
     and the smoke column). It was only unfilmable because the camera parks after the flow's
     cinematic, and that is also camera-aim r7.

## Do — part A, now, on the current look
Part B (below) re-records everything after the look rounds land. Part A builds what B needs.

1. **Find the combat stage.** It must be an open, well-lit place with long sightlines.
   - Candidates to scout: the A5 deck, the A1 container yard, the A3 Spire plaza, the Crown deck
     before the boss, the river or escarpment edge. Use `data/vistas.json` and `docs/MAP.md`.
   - For each candidate, shoot a top-down plus four candidate cameras.
   - Requirements:
     - a 16 m hero fills ≥ 1/3 of the frame height at a 40–60 m camera distance, with no occluder in
       between;
     - ≥ 50 % of the frame behind the hero is sky, far city or a lit landmark, not a near wall;
     - enemies spawn there on the navmesh and fight (`--enemies=type:count`, `--spawn=`).
   - Pick one main stage and one alternate. Put a sheet of the candidates in your status file.
2. **A trailer camera kit** in `game/trailer/`: script-driven Camera3D rigs that take the view from the
   game camera for a shot and hand it back afterwards.
   - **orbit:** around the hero; radius, height, rate and start angle.
   - **crane:** rises or descends with a look-at.
   - **chase:** a lagged follow from behind or the side, at a fixed offset.
   - **low hero:** at ground level, looking up at the hero.
   - **locked-off wide:** a fixed camera framing the hero and the enemies together.
   - Every rig keeps the hero framed: a look-at with a framing offset, and a frame-height floor.
   - Every rig logs per frame:
     - the hero's screen-space bbox height as a fraction of the frame;
     - whether a ray from the camera to the hero's chest is blocked;
     - the number of live enemies on screen whose ray is unblocked.
   - A shot fails its take if:
     - the hero is blocked for more than 0.2 s;
     - in a hero shot, the bbox is under 0.25 of the frame for more than 0.3 s;
     - in a combat shot, no enemy is visible for more than 0.5 s.
3. **Shot list v2.** At least 8 distinct camera setups in the combat section, each combat shot ≤ 3 s.
   It must contain all of these:
   - a dash or slide past the camera;
   - the melee combo L1→L3 on a close orbit;
   - a perfect parry into witch time (the world at 0.3×);
   - a gatling spin-up from a low angle;
   - a missile salvo on a wide;
   - **three different skills**, picked from barrier / feather drones / gravity slam / grapple /
     overdrive / ultimate;
   - an assault-boost ram kick;
   - an enemy kill with its death FX in frame.

   Enemies must read in every combat shot. If an archetype still reads as a black shape once the stage
   is lit, name it in Requests with a frame; the lead routes it to monster-assets.
4. **The boss take's black first 7 s.** The intro camera sits under the Crown deck. Either start the
   take later or move that camera with your kit. Do not edit the boss's own files; if the fix belongs
   there, put it in Requests.
5. **Request 1 is approved: `--movie-size=WxH` on `tools/godot.sh movie`.** Implement it yourself:
   - it writes the Movie Maker size override for that run only;
   - `record.sh` then drops its override.cfg workaround;
   - nothing else in `tools/godot.sh` changes.
6. **Deliver part A** with:
   - a rough cut `TIANSHU_trailer_v2a.mp4` on the current look, so the lead can judge the camera work
     separately from the colour;
   - one frame per shot (`_shots.jpg`);
   - the per-shot framing logs.

## Part B (after the lead's "re-record" feedback)
The lead sends this when city-art r15, hero-v3 r7, camera-aim r7 and mech-move r6 have landed.
Then:
- re-record every take;
- redo the `--tod` A/B per shot on the new sky;
- add the first-person, flight and spire-collapse shots. The spire collapse is a real kill in the
  un-stubbed flow;
- recut as `TIANSHU_trailer_v2.mp4`.

## Gates (part A)
- Every take renders with 0 engine errors.
- Every shot passes the framing rules in §2. The logs are the evidence; the lead re-runs one take.
- Combat montage: ≥ 8 setups, no setup used twice in a row, every shot ≤ 3 s.
- `tools/godot.sh check --only=res://trailer/` is clean, and no file is over 600 lines.
