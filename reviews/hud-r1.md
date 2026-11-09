# hud — review r1 (lead) — FAIL (small polish round; very good base)

Verified myself: check 37 files clean; test_hud 115/0; in-game + menu captures reviewed at full size. The layout,
style, bilingual text, reticle cluster, hex skill arcs, plates, radar, compass, boss bar and canopy HUD all hit
the brief. Your requests: core now has `Events.prime_collapsed(center, count)`, `Events.execution_ready(enemy)`,
Settings `hud_scale` (0.8–1.4) next to `damage_numbers`; set `Game.hud = self` yourself in `_ready`; spires join
`&"hive_spire"`, the boss joins `&"boss"` with a documented `hud_state()` (CONTRACTS §6). The `hit.source_kind`
error is audio's bug (it will read `hit.kind`/`hit.weapon`).

## MUST-FIX
1. **Readability**: minimum label size 14 px at 1600×900 (scale with resolution and `hud_scale`); numbers 18–22 px;
   objective text 18 px; keep the thin style. Today most labels are ~10 px.
2. The accessibility/wayfinding items in `reviews/hud-lead.md` (shape-coded telegraph icons and hit markers,
   height on the compass, layer-shaded radar, blocked-shot cue, photosensitive + reduce-motion honour).
3. Style meter + damage numbers visible in one combat capture (they are not in the current set).
4. Re-capture the 7 in-game frames after camera-aim's new framing lands (hero ≈ 40 % of the height).
