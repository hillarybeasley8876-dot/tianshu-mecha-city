# city-build r9 — lead brief: walkable floors with no rendered top face (the arena cover "floats")

## Why
The user's complaint is "地编物件浮空" (the scenery floats).
- **Fixed:** the lead and city-art fixed the dressing. Commits 8f2bfd1, dd8aa21 and 9c3c157 (city-art
  r10/r10b).
- **Left:** 30 arena cover boxes (45 kit pieces) still stand visibly in mid-air, up to 48 m over the
  nearest RENDERED surface.

city-art probed them (`status/city-art.md` r10b, Known issues and Requests):
> in every case I probed, a `_deck` mesh exists in the chunk with the right AABB but has **no up-facing
> face at the cover's z**: the cover stands on an invisible floor whose collider is there.

So the player can stand there and fight there, and sees nothing under their feet. The collider and
the cover are where the layout put them; what is missing is the floor's top face in YOUR render.

## The list (city-art's audit; gap = the cover's base minus the highest rendered surface under it)
| cover row | gap (m) | rendered surface under it (m) | arena tiers |
|---|---|---|---|
| A1#45 | nothing within 160 m | — | A1 [-12, 0, 16, 48] |
| A1#52, A1#55 | 4.0 | 36.0 | |
| A1#79 | 8.0 | 40.0 | |
| A2#54, A2#60 | 15.8 | 0.2 | A2 [0, 16, 32, 56, 80] |
| A2#115 | 35.1 | 20.9 | |
| A2#129 | 6.0 | 50.0 | |
| A3#36, #40, #44 | 20.0 | −40.0 | A3 [−20, 0, 16] |
| A3#41 | 10.1 | −30.1 | |
| A3#53 | 13.1 | 2.9 | |
| A3#55 | 15.7 | 0.3 | |
| A3#58 | 8.2 | 7.8 | |
| A3#76 | 38.7 | 1.3 | |
| A4#41, #42, #43, #48, #49 | 47.8 | 32.2 | A4 [32, 80, 128] |
| A4#44 | 16.0 | 64.0 | |
| A5#55 | 20.0 | 12.0 | A5 [0, 32, 80, 144] |
| A5#74 | 3.2 | 28.8 (a kit roof) | |
| A5#92 | 8.0 | 32.0 | |

Plus **D4_b034**: the building and its s01 podium stand 14 m over a sloped deck at y −31.5 (−34.6 under
its frontage).

The full list, re-runnable, is `float_audit`'s STRUCTURE section:
`tools/godot.sh run res://tools/float_audit.tscn 600`.

## Do
1. **Diagnose each case before you fix any of them.** It is one of these:
   - (a) a deck whose render lost its top face. The kit skin (`blender/city/skin.py`) mutes a deck's
     parapet for a railing row and the whole slab for a `deck_full` row; check that no top face goes
     with the parapet;
   - (b) a deck polygon that does not reach under the cover the layout put on it;
   - (c) a cover box on a tier that has no deck at that spot.

   `game/world/art/tests/probe_support.tscn` names every rendered surface and every mesh AABB under a
   point; use it. Write the per-case answer into your status.
2. **Fix by case.**
   - (a): the render keeps the top face.
   - (b) and (c): the layout is wrong. Move the box onto the floor that is there, or remove it, and
     collider and cover move TOGETHER. The data lives in `arenas[].cover`; city-layout is idle, so edit
     its tool (`tools/map/arenas.py`) rather than the generated file.
   - D4_b034: the terrain or the deck under it.
3. **Add a gate that catches this class of bug, not just these 30.** Every walkable collider top face,
   meaning every deck polygon and every arena tier floor, must have a rendered up-facing face within
   0.3 m of its z, or be covered by a kit `deck_full` piece. Sample a 4 m grid. It belongs in your
   city checks.
4. **Rebuild** (`build_city.py`), then:
   - `python3 tools/citykit/assign.py`, if the layout moved;
   - re-bake the settle cache: `SETTLE_BAKE=1 tools/godot.sh run res://tools/float_audit.tscn 600`;
   - run `test_settle_cache.gd` and `test_float.gd`;
   - run the nav checks.

   **city-kit is running r6 at the same time** and also re-bakes the cache. Re-bake once more at the end
   of your round and run the test, so the last bake reflects both.

## Done means
- `float_audit` STRUCTURE: 0 cover rows off their floor.
- The new top-face gate passes.
- Before/after shots of A4 tier 80 and A3 tier −20 from a player height. Use `--cams` with the cover
  positions above.
- Nav and the city checks still pass.

Commit per step with an explicit path list. Report in `status/city-build.md`.
