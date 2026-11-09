# city-art r10b — lead: settle the DRESSING, never the STRUCTURE (fix before anything else)

The settle pass is the right idea: the roof dressing numbers are good, and the bake and the shared
`ArtSurfaces` are good work. But it also moved and DROPPED kit pieces that are structure, or that are
registered with a city-build collider built from the same layout box. A visual that moves or vanishes
while its collider stays is worse than a float: it makes invisible walls, invisible floors and holes.

Measured from your own `settle_cache.json` (the lead mapped every kit cover piece back to its
`kit_assign.json` row):

| what | settled how | what the player gets |
|---|---|---|
| s06 = **deck_full**: the kit draws the WHOLE deck slab wherever city-build muted it | 33 of 53 dropped | holes in decks; the collider is still there, so the player walks on air |
| s05 = **pylons** under viaducts | 23 of 102 dropped | viaducts lose their pillars |
| arena **cover** k01–k12 | 173 of 1 265 dropped; 144 moved more than 0.5 m, up to ±2.94 m | invisible cover, and shots stopping at nothing |
| s07 railings | 95 dropped | — |

On the cover rows:
- **The dropped cover includes STACKED copies.** A1#68 pieces 3–5 at y 54.0, A1#65 pieces 2–3 at 49.7.
  The upper layers of a stack rest on the lower layers by construction (`tools/citykit/cover.py`).
  Since `piece` is no longer a support, the settle found nothing within ±3 m and removed them, while
  city-build's cover box (the collider) still stands at full height.
- **Moved cover:** A2#86 went up 2.94 m and A2#94 down 2.50 m. Its collider did not move.

## The rule
**Settle only DRESSING:** things with no collider and no structural role.
- greebles;
- the roof-machine props;
- kit s08 (roof machinery);
- the street props: lamps, barriers, planters, vehicles, stalls, trees, lions.

**Never move or drop STRUCTURE:**
- arena cover k01–k12, every copy of a stack;
- s06 deck_full, s05 pylons, s01/s02/s04 street skirts, s03 market;
- s07 railings, f03 pipe racks;
- u01/u02 fasciae.

Their placement comes from the same layout data as city-build's colliders and decks. If one of them is
off its surface, the bug is in the rule that placed it (`tools/citykit/pieces.py`, `cover.py`, or the
layout's arena z), not in its height at load. You already found one such rule (the railing z): that
is the right kind of fix.

## Do
1. **Restore** every STRUCTURE batch to the placer's own transforms, then re-bake.
2. **`float_audit` gets a third section, STRUCTURE.**
   - Judge the bottom of each stack only. Copies above the first layer sit on the copy under them, so
     use the `cover.py` stack index rather than guessing from heights.
   - List every structure instance off its surface by more than 0.5 m, with its `kit_assign` row id
     (cover `A1#68`, deck `D…`, pylon `…`), the gap, and what is under it.
   - It is REPORTED, not gated, this round.
   - Then fix the rules you can see in `pieces.py`, the way you fixed the railing z.
   - Put the cover boxes whose BOTTOM layer is off the floor into `## Requests` for city-layout, with
     their arena, index and gap. The cover's z comes from the layout, and the collider and the visual
     have to move together.
3. **Street-prop band.** 15 street props jumped exactly 2.9–3.0 m, onto the edge of the ±3 m band.
   Look at three of them. If they climbed onto a sill or a planter rim, narrow the street band to
   ±1.5 m.
4. Re-run the float gate (dressing: 0 floating), `test_settle_cache` and the timing, then re-shoot
   `look_city-art_r10_ab_2.jpg`: A5deck is where the deck slabs and the cover are.

Commit per step with an explicit path list. Append an r10b section to `status/city-art.md`.
