# city-art r12 — lead brief: facade variety, the real roofs, and a build that runs on another Mac

## r11 verdict: accepted
The foil is gone, the gates are honest (including your note that the std metric cannot separate the
two cases and the eye gate does), the cost is measured on matched arms, and the probe is adopted with
the restore bug fixed. T1fac is the best near-city frame the game has had.

## 1. Every building wears the same facade (impact 8)
The same 3.4 m × 4.0 m office cell with a 70 % × 55 % pane is on every tower, megablock, mid-rise,
civic hall and old-town block. At T1fac five buildings in one frame are visibly the same skin, and
the user will read that as copy-paste.

Make the facade a small FAMILY, chosen deterministically:
- the model's `kit.json` band and archetype pick the family;
- the instance (`b_var` or a hash of the instance position) picks a variant inside it;
- the instance also offsets the phase, so neighbours do not line up.

| family | read | rule of thumb |
|---|---|---|
| curtain wall (towers) | glass dominant | bays 1.5–2.0 m, panes 85–90 % of the cell, thin 0.08 m mullions, spandrel only at the slab; per-tower glass tint (cool or warm); a few lit floors in runs |
| ribbon (megablock / midrise) | horizontal | continuous window bands 1.6–2.0 m tall, a solid spandrel 2.0–2.4 m, vertical joints every 6–9 m |
| punched (old town / civic) | wall dominant | smaller windows (35–45 % of the cell), deeper reveals (a darker frame), a cornice line every 3–4 storeys, ground floor arcades |
| industrial (stays atlas or `facade_mix` 0) | — | unchanged |

Also:
- **A balcony or a plant line** on one megablock variant in three: a 0.6 m dark band with a light rail
  line every storey.
- **Per-building colour:** keep `textureLod(..., facade_mip)` as the identity, and add ±15 % value
  between buildings (within the 0.15–0.30 clamp). Two neighbours must not read as one block.

**Gates:**
- **Variety.** On the T1fac frame and two high vistas (V2, V5), the near buildings are told apart by
  their facade. Show a sheet: the same frames r11 → r12.
- **Count.** Over the kit buildings in the city, print the number of distinct (family, variant)
  pairs, and the share that the most common pair holds (below 25 %).
- **Unchanged.** Night lit-window density, shimmer (re-run the dolly) and cost (the matched-arm
  method you used in r11).

## 2. Use city-kit's roof map: put the 1 099 dropped rooftop units back (impact 7)
city-kit r6 wrote a per-model roof map into `world/kit/kit.json` (`models[].roof`; the format and the
read recipe are in `status/city-kit.md`, r6 roof map section). `test_roofmap.py` puts its worst p95 at
0.376 m.

Your ROOF rule drops 1 099 greebles and roof props because they were aimed at the DESIGN box top.
Aim them at the map instead:
- for each unit, take its model-space (x, y) under the building's instance transform;
- read `h` and `flat`;
- place it at `z0 + h/255 · z_span` if `flat > 127`;
- otherwise try the nearest flat cell within 6 m, and drop the unit only when there is none.

Keep the settle pass as the safety net, but it should now move almost nothing.

**Gates:**
- `float_audit` still reports 0 floating.
- The dropped count per category is printed: ROOF drops fall from 1 099 to under 150.
- A high roof camera over D5/D7 (r10's cameras), r11 → r12.
- Re-bake the settle cache. You own that bake this round; city-kit r8 is also running, so coordinate
  through `status/` and re-bake LAST.

## 3. A build that runs on another Mac (impact 6; the game repo may go public)
Runtime scripts read files by absolute paths under `/Users/minimax/...`:
- `world/art/city_art.gd:14` (`DESIGN_LAYOUT`);
- `world/art/detail/cargo_blocks.gd:27` (`KIT_ASSIGN`);
- `world/art/settle/kit_rows.gd:18`;
- `world/art/settle/cache.gd:24`.

The exported app reads them from this Mac's disk, so on any other machine the roof dressing and the
cargo blocks silently vanish.

Fix:
1. Read what you need from `res://` copies: `world/kit/kit_assign.json` already exists. For the design
   layout, either read the fields you need from `world/city/layout.json`, or have the tool that writes
   the game copies also write a `res://` copy of the fields you use.
2. Do not hand-copy. The copy must be part of the existing export step that writes the game files, so
   it cannot go stale.
3. Test, tool and probe scripts must not hard-code `/Users/...` either. Derive the repo root from
   `ProjectSettings.globalize_path("res://").get_base_dir()`, or take a flag.
   - Your files: `vistas.gd`, `probe_*.gd`, `test_art.gd`, `test_props.gd`, `probe_kit_layers.gd`.
   - Not yours: `world/post/tests/lookdev.gd` and the three `combat/melee/tests/*` files. Post and
     melee are idle, so fix those too, with the same helper.
4. Add a check that fails on any `"/Users/` literal under `game/` outside `.godot/`.
5. Verify. **Do NOT rename or move `data/`**: city-kit r8 is running and reads it.
   - Export with `tools/godot.sh export`.
   - Search the pack inside `build/TIANSHU.app` for the bytes `/Users/`; there must be 0 hits.
   - Run the app for 30 s: the greebles and cargo blocks must still be there, and the log must show
     0 errors.

Commit per step with an explicit path list. Report in `status/city-art.md` (an r12 section).
