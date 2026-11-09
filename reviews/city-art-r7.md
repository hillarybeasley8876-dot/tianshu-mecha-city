# city-art — review r7 (lead) — look round PASS, one ownership rule

Rerun not needed beyond your evidence (check 70/0, test_art PASS); captures judged: mipmaps fix the sandpaper/moiré,
the props keep their albedo, and the container-stack skin turns the cover from toy blocks into a yard.

## Ownership rule (city-kit wave 2 is placing Tripo cover models right now)
One owner per cover piece: where `kit_assign.json` has a `cover` row (city-kit's Tripo model, city-build drops the
render box), **CargoBlocks must skip that piece** — read the same file (`data/map/kit_assign.json`, rows with
kind `cover`, keyed by arena + index). CargoBlocks stays the dressing for every cover piece city-kit does not cover.
Add a test: a piece with a cover row gets no CargoBlocks instance.

## Polish (next time you are in the file)
- Low soft pieces (≤ 8 m) skinned as one container slab read as a red ribbed rug from above
  (`look_city-art_cover_after_wide.jpg`, foreground): give them visible container ends/doors, or split into
  2–3 single containers with gaps.
- The permanent walls: your own note (form-tie marks, a recessed reveal) is the right next move.
