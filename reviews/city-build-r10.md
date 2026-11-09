# city-build r10 — lead brief: split `tools/map/build_layout.py` (605 lines) without changing its output

The project rule: a source file over 600 lines must be split the next time it is touched, and the split
is its own commit. r9 took `tools/map/build_layout.py` to 605 lines. It is mostly the stage order in
`main()` plus helpers that belong to other modules.

**Do:**
1. **Move the helpers to the modules they belong with.**
   - `_trench_mask`, `drop_over_cut`, `_mask` and `land_freed` go to `floors.py` / `lots.py`, or to a new
     `cuts.py`.
   - `_core`, `_avenues` and `_declare_through` go to `corridors.py` or `streets.py`.
   - `main()` stays the readable pipeline it is: the stage order and the prints.
2. **Size.** Every touched file stays under about 400 lines (`arenas.py` is 546: do not grow it).
3. **Output-identical.** Run `build_layout.py` before and after. `data/map/city_layout.json`,
   `overrides.json` and every other file it writes must be **byte-identical**. Show the sha256 of each,
   before and after.
4. **Validators.** `validate_layout` and `validate_graph` PASS.
5. **Nothing downstream.** Do not rebuild the city or re-bake anything. Nothing downstream changes,
   and city-art r12 and city-kit r8 are running.

One commit for the split, with an explicit path list. Report in `status/city-build.md` (a round 8
section) with the hashes.
