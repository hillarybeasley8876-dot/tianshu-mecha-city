# hero-v3 r10 — lead brief: the thruster plumes are in the right place; now make them look like jets

## Why
r9 put the plumes on the measured nozzles (root within 0.043 m, in every state). In
`captures/hero3_r9_thruster_states.jpg` and the showcase reel's flight segment
(`~/Desktop/天枢_实机演示_打怪技能机制.mp4`, g4_flight), they read as **flat white slabs**: one uniform
white, a hard edge, no core and no colour. The user named the thrusters as a defect once already, so
this round makes them read as jet exhaust.

## House rules (the user's machine)
You are the ONLY worker. Headless only, one Godot process at a time. Visual proof goes under **Captures
needed**, with exact commands, and the lead runs them when the user OKs the screen. Never use git stash;
commit with explicit paths.

## Do (`hero3_thruster.gdshader`, `hero3_rig.gd` plume build; your files)
1. **The look:**
   - a hot, near-white core at the nozzle, falling off along the plume to the hero's accent colour (the
     cyan of the seams), then to transparent;
   - a soft radial falloff across the plume, so no hard silhouette edge (fresnel or a radial alpha);
   - a little flicker or shock-diamond banding along the axis, driven by time and thrust level.
   - It is additive and does not write depth, so it never hides the hero behind it.
2. **Scale with thrust:**
   - idle or walk: a faint nozzle glow only, or nothing;
   - boost or hover: a medium plume;
   - flight boost and assault: long and bright.
   Keep the r9 states and the r8 flight lean.
3. **Headless checks** in `test_hero3_thruster`:
   - the shader compiles in an error window, the way melee-defense's `mat.shader_compiles` does;
   - core alpha at the nozzle ≥ 0.8, and alpha at the tip ≤ 0.1;
   - the colour at mid-plume is the accent hue (±15°);
   - the plume length grows monotonically with the thrust level across the states;
   - the r9 root gate (0.3 m) still holds.

## Gates
- `test_hero3_thruster` (extended) and every hero3 suite pass.
- `tools/suites.sh --only=<hero3 rows>` is green.
- `status/hero-v3.md` gets an r10 section. The plume close-ups (behind and side; walk, boost, hover,
  flight boost) go under Captures needed.
