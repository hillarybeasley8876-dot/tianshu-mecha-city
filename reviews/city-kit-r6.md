# city-kit r6 — lead review: the near walls read as blank, faceted sheets

## First: what the lead changed in your tree while you were idle (commit 8f2bfd1)
Read the commit, and keep these.
- **Every kit glb drew sunk by half its height.**
  - `fit_native` ran `set_origin` and then `apply_transforms`. The second call baked straight back the
    offset the first one had moved. r5's "pivot fix" was the same no-op, and its commit message
    quoted a `0..150` that the shipped glb never had: every glb was centred.
  - `fit_native` now moves the mesh data itself, with an identity object transform.
  - `tools/citykit/rebase_glb.py` moved the 58 shipped families and is now the gate: `--check`.
  - After every `process_all`, `rebase_glb.py --check` must say PASS.
- **`kit_placer._basis` used `Basis.scaled()`.** That scales the WORLD axes after the turn, and
  `assign.py` also wrote odd-quarter-turn scales in the box's own order. Between them, 189 of 384
  buildings missed part of their footprint.
  - The scale is now per model axis (`scaled_local`).
  - `assign.py` writes `[sy, sx, sz]` on an odd `j`.
- **city-art fixed one of your rules.** Railings and pipe racks now stand on `d["z"]` (commit cec9b37).
  Keep it.
- **city-art r10 owns `kit_placer.gd` and `game/world/art/settle/`** (`near_batches`, `upload`, the
  settle pass). Do NOT edit them this round.
  - Any change to a glb, `kit.json` or `kit_assign.json` invalidates the settle bake. Re-bake it with
    `SETTLE_BAKE=1 tools/godot.sh run res://tools/float_audit.tscn 600`.
  - `test_settle_cache.gd` must pass, and `float_audit` must report 0 dressing floating.

## What the lead sees now
Shot after all of the above: `captures/lead_r6pre_st_*.jpg`. The sheet is `tmp/lead/r5/r6pre_sheet.jpg`.

### MUST-FIX 1 — a flat wall renders as a blank, faceted sheet (impact 9)
At T1fac (left third) and A4st, the near tower walls are large pale peach-to-white planes.
- **No storeys, no panels.** At play distance there is no structure at all.
- **The triangles show.** Neighbouring triangles of one flat wall are shaded visibly differently, as
  big light and dark wedges.

These are your r5 facade regions: the plane is flat now, but it reads as an untextured low-poly box,
which is the user's 搭积木 complaint again.

**Fix the normals.**
- On every planar region, every vertex's normal must BE the plane normal. Write it as a custom split
  normal from the region's fitted plane. The weighted-normal pass averages across the region boundary,
  and the collapse leaves slivers.
- Then a lit flat wall is one value, and the faceting is gone.

**Fix the albedo.**
- Bring the facade field into the city's value range: linear albedo 0.15–0.30, not near-white. The dusk
  sun is strong and the post grade lifts it further.
- Give it structure at WORLD scale:
  - storey bands every 4.0 m;
  - a panel or mullion grid;
  - slight per-storey value variation;
  - your pane mask's windows, lit by `mc_kit_body` as now.
- Reference: the key art's mid-rise facades (`art/concept/keyart/`).

**Gate.** Render t01, m01, o01 and one podium tower in Blender, with a grazing sun and the camera at
30 m:
- inside each planar region, the shading term (normal against sun) varies by less than 2 % of its
  mean;
- a 2× crop of the T1fac and A4st near third shows no triangle wedges and no blank planes.

### MUST-FIX 2 — black and white speckle on the machinery (impact 7)
- **Where:** A5deck (left, the transformer blocks), A6garden (the crate on the deck) and A3st.
- **What:** the near-tier kit pieces (k-series cover, s-series) show high-frequency black/white
  speckle, like a noise texture or an aliased specular term.
- **What to do:** find out which it is before fixing.
  - **Albedo:** the Tripo atlas islands at 1K.
  - **Roughness:** a gloss term that sparkles on micro-normals.
  - **Normal map:** too strong, or its mips are missing.
- Fix the one it is.
- **Gate:** in a 2× crop of A5deck's left half, no pixel-scale black/white alternation, and the blocks
  read as painted steel.

### MUST-FIX 3 — the camouflage blotches on mid-rise near walls are still there (impact 6)
- **Where:** T1fac right third: the r4 MUST-FIX 3 walls.
- **What:** MUST-FIX 1's facade field will cover the flattened walls.
- **Check:** whether the blotches survive on the walls that are NOT planar regions. If they do, the
  Tripo albedo on non-planar wall area needs the same world-scaled field blended over it.

### Request from city-art: the real roof
city-art r10 drops 1 099 rooftop units (20 % of the roof dressing), because both its greeble scatter
and city-build's `roof_machine` slots aim at the DESIGN box top, and a Tripo model reaches that only on
part of its footprint.
- **What to add:** a per-model roof map to `kit.json`, measured off the detail glb. On a 2 m grid over
  the footprint, in model space, store the top surface's height and whether it is flat (normal within
  15° of up).
- **Format:** keep it compact: 8-bit heights over the model's own height range, run-length or base64.
- **The gate is a test:**
  - a dressing point sampled from the map lands within 0.5 m of the real surface;
  - in the float audit, the map's "flat roof" cells agree with the settle pass.
- city-art consumes it next round, so say in your status exactly how to read it.

### Smaller
- **A4st's camera sits against a wall.** Re-pin it in `cams_street.json`. city-art re-pinned A1yard
  in r10.
- **Flatness ≥ 50 %: dropped.** Your argument about the triangle budget holds. MUST-FIX 1's gate is
  what matters to the player.

## Done means
- `process_all` through the fixed pipeline, and `rebase_glb.py --check` PASS.
- The normal and shading gate numbers per model.
- T1fac, A4st, A5deck and A6garden re-shot against `lead_r6pre_st_*`, with 2× crops of the near third.
- The settle cache re-baked, `test_settle_cache` and `float_audit` pass.
- Perf at the A1 spawn, with the kit draws inside 98.
- The roof map and its test.

Commit per item with an explicit path list. Report in `status/city-kit.md`.
