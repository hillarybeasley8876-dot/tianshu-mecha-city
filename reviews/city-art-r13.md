# city-art r13 — lead brief: 60 fps at the A1 spawn, at the shipping default

## Where it stands (lead, 11-04 09:20, quiet machine, load 2)
At 1600 × 900 (a 3024 × 1898 backing store on this Retina Mac), `--quality=high`, with 0.67 MetalFX
temporal (lead 202c215):

| measure | result |
|---|---|
| A1 spawn | **45 fps**: 1 079 draws, 5.24 M prims, KitPlacer 92 draws |
| smoke run, 45 s | mean 42 fps, min 14 |
| street cameras, native | 23–24 fps (A1yard, T1fac). Sun shadows off gave **+5 fps**, SSAO + SSIL off **+6 fps** (lead probes, r11 evidence) |
| occlusion culling | **ON in `project.godot`, but the game has ZERO occluders**, so it buys nothing |

A mech action game wants 60. This round is the frame, and nothing else.

## Do
1. **Measure first.** Build a frame budget at the A1 spawn, A1yard, T1fac and A5deck, plus vistas V2
   and V5, at the shipping default.
   - Switch one lever at a time and measure: sun shadows, SSAO, SSIL, SSR, volumetric fog, glow, each
     post effect (lens / bloom / shafts / DOF; post-render is idle and you may tune its presets), the
     kit, the tiles, and the art environment.
   - Run the arms interleaved, at least 3 runs each, and print the machine load.
   - Name the top five costs, with ms.
   - `viewport_get_measured_render_time_gpu` returns 0 on this Metal build (lead checked), so toggling
     is the method.
2. **Occluders, at load, from data you already read.** Do not rebuild the tiles: city-kit r9 is
   rebuilding the city and owns `kit_placer.gd` this round.
   - Build `OccluderInstance3D`s (an `ArrayOccluder3D` per 200 m tile) from `design_layout.json`:
     - building cores, as each footprint shrunk 2 m and capped at the roof map's LOWEST flat
       height, so nothing visible is ever hidden;
     - deck slabs;
     - the ground crust.
   - **Gate:** a 6 s camera dolly through A1 → A3 at street height, occlusion on and off. No object
     pops (frame-diff the two runs: no pixel region appears in "on" later than in "off"). Report the
     draws and primitives saved at each camera.
3. **Tune `high` with your measurements.** Candidates:
   - shadow distance 500 → 300–350 m;
   - 4 → 3 splits;
   - shadow casting off for the far tier and for dressing smaller than about 2 m. That last one is
     your props, greebles and cargo: do it in your own placers, not in `kit_placer.gd`;
   - SSR and SSIL at a cheaper quality;
   - volumetric fog length or density.
   Every change gets a before/after of the 7 street cameras: **no visible regression is the bar.** If a
   lever costs the look, leave it and say so.
4. **Target.** At least 60 fps at the A1 spawn and at least 50 at the four street cameras, at the
   shipping default on this machine. If it cannot be reached without hurting the look, stop at the best
   honest number and list what is left.

## Coordination
- city-kit r9 is running at the same time: ring rows, a city rebuild, a settle re-bake. Do not edit
  `kit_placer.gd`, the kit glbs, or anything under `blender/city/`.
- Measure on a quiet machine, and write the load next to each number. city-kit's Blender runs will
  load it, so measure between them.

Commit per step with an explicit path list. Report in `status/city-art.md` (an r13 section).
