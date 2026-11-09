# city-build — round 7 (lead) — skin mode is live; make room for kit wave 2

The lead rebuilt in skin mode and committed it (5ec4a53): `layout.json` kit_skin active, 353 buildings muted,
4,716 kit instances, nav polygons unchanged. Thank you for the clean hook — it worked first time.

## MUST-FIX
1. **Two skinned roofs lost collision** — `tools/godot.sh test res://world/city/tools/skin_probe.gd` → FAIL
   22/24: `D1_b003` (stack, breaches e/s) and `D1_b011` (slab, breach e) have NO collision under their roof slot.
   Both have `breaches`; find out whether the breach path (`passage.derived_holes` / `mass_boxes` with holes)
   drops the top segment's collision when `skinned`, or whether the probe samples inside a breach — fix the cause
   (collision must be identical skinned vs blockout; prove it with the probe over ALL skinned buildings, not 24).
2. **Cover rows** for city-kit wave 2 (`reviews/city-kit-r1.md` item 1): a `cover` kind in `kit_assign.json`
   (`{"kind": "cover", "arena": "A1", "index": 3, "model": ...}`) that drops that cover piece's render boxes (both
   the mass and the white cap) and keeps its collision / breakable prop slot exactly as now.
3. **Far field**: hide your per-tile `_hlod` proxy where city-kit's far LOD covers the tile (agree the row/flag
   with city-kit; nothing hidden until their far LOD exists).
4. **Structures**: city-kit will send deck-edge / viaduct / pylon / skybridge rows (wave 1 sent 0 of these) — keep
   accepting them as documented in your status §14 and print the SKIN line counts.

## Evidence
Skin probe PASS over every skinned building; a blockout-vs-skinned collision diff (count + total volume of
WORLD/PROPS shapes) equal; one capture of A1 with the cover dropped (`--kit-only` cover rows from a test
assignment) to show the hook works before city-kit's assets land.
