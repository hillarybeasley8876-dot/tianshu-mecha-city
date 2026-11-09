# city-art — review r2 (lead) — real progress; r3 = facades, signage, depth

Verified: `check` 45 files 0 errors, art/props tests PASS, perf 60 fps at every vista on high/low, the look-dev
set (`look_p0_*`, `look_p1_*`) and sheets. The golden dome, the cool ambient against the warm key, the storm
violet from 0.66, the restrained creep and the Spire strips/tether now give the city a mood — the aerial
(`look_p0_high`) and pier shots read as dusk. The three bugs you found by looking (unshaded → ALBEDO, the tether
never spawned, MultiMesh culling) are exactly why we look. I grepped every other unit's unshaded shaders: none
write EMISSION only. ART.md now carries your measured SKY_MID / sun light. `movie` takes `--scene=` and
main.tscn now includes your environment through city.tscn — record the flythrough with
`tools/godot.sh movie --movie=<abs> --timeline=res://world/city/tests/flight.json --skip-menu --no-enemies --stub=flow`.

## r3 — what still separates us from the key art
1. **Facades**: towers read as flat orange blocks. C/D towers need glass curtain walls (dark, sky-reflecting,
   mullions on the 4 m module), A/B blocks concrete with lit window grids; ≥ 40 % of window cells lit at p0,
   warm/cool mix; rooftop parapet light lines on C/D towers.
2. **Signage — the Chinese neo-futurist read**: vertical neon blade signs (procedural CJK-like glyph strips —
   fictional brands, no real ones) on podiums and towers, 6–10 large holo billboards, shopfront glow at L1
   podiums; restrained (key art), concentrated where the player is (arenas, canyon, Spire plaza).
3. **Depth**: layered aerial perspective — warm haze in the near/mid band, cooler violet-blue beyond ~800 m,
   god rays through canyons (volumetric fog high preset); the skyline ring must read as distant silhouettes, not
   a flat orange band (use its own darker, hazed material).
4. **The street level** (`look_p0_street` is a blank slab): judge two street cameras inside the canyon (A4) and
   the Spire plaza (A3) with props, decals and lights.
5. The vistas: city-build's solved cameras (`data/vistas.proposed.json`) land this round — the lead adopts them;
   then render-vs-key-art sheets V1–V8 at p0 and p1, looked at, honest notes.
