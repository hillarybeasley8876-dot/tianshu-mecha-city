# monster-assets — review r4 (lead) — look round: PASS

## Verdict: PASS
Reproduced: `test_models.gd` → **TEST 722 checks, 0 failures / PASS**. Judged from
`captures/look_monster-assets_hive_ab.jpg` and `look_monster-assets_gallery_ab.jpg` (same world, same cameras):
- **The hive (item 1)** — at 25 m the trunk is no longer a lime blob with a halo: a dark ribbed spire, thin acid
  veins, small violet cores, and the ribs read for the first time. The 70 m shot no longer blooms over the deck.
  Masks measured and de-specked (hive acid 6.30 % → 3.95 %); per-pod glow via `set_pod_alive`, which flow
  already calls. Well done.
- **Brown at dusk (item 2)** — measured `albedo_gain` per type (not guessed), metallic cap, roughness floor, a
  distance-doubled rim. The ripper and the line-up are dark silhouettes with acid edges instead of brown smudges.
- **Seams (item 3)** — `merge_vertices=True` and a weld gate in every build: 0 open edges on six types, 1 on the
  hive (was 12,876 / 16,861 / 44,000).

## Notes (no action needed this round)
1. Known issue 10 (carapace pure black in the flat-lit gallery) — accepted: judged in game under the dusk key,
   where the A/B shows rib and form. If the user's next in-game screenshot shows monsters as black holes, the one
   number to move is `GRADE_TARGET`.
2. Requests #6 (the same weld fix in `blender/hero/hero_lib.py` and `blender/props/process_prop.py`) — the lead
   has it. The old hero is being replaced (hero-v3), so the hero half is moot. The prop half goes to city-art,
   which owns the prop pipeline. Requests #2 (juggernaut roar `set_locomotion(&"roar")` →
   `play_action(&"roar")`) goes to enemies with the next round. Requests #3 (`perfect_dodge` arity) was fixed by
   the lead in 7d79962 (`audio.gd` unbinds the signal's own arguments); the 9 errors you quote come from
   `tmp/monster-assets/fight.log` dated 00:29, which is before that fix.
