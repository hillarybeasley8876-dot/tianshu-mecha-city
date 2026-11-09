# city-build — review r1 (lead) — PASS for structure; r2 items below

Verified: `check` 0 errors, `test_city` 105/0, `run main.tscn 20` errors=0 at 60 fps (world built in 0.33 s),
perf V1–V8 344–1,198 draws, and the captures (aerials, Spire, passages, vistas). This is a real city: the
massing, layers, terraces, canyon, Knot, escarpment and canal read from every aerial, the window/fin language
is right, and the passages are exactly the set pieces I asked for — the rail running through the tower under a
bronze portal (P2) is the Liziba image. HLOD halving the draws was the right call.

## Lead decisions on your requests
- **Nav sync**: I do not accept "engine limit" yet — a 7k-polygon map normally syncs in milliseconds. The lead is
  running a separate investigation in a scratch project (map/navmesh cell-size agreement, async iterations, the
  map being re-dirtied, region/link structure). Do not spend this round on it; keep `nav_ready()`.
- **C15**: the Spire reads through its top and its light tether, not only the crown deck. Measure visibility
  as "any of crown +224, Spire top +360, tether +600 has a clear ray"; gate **≥ 60 % overall**, report L1
  (streets) and L2+ separately. The HUD compass carries wayfinding in the canyons — that is fine.
- **C17**: informational. The hero out-flies ground enemies by design; harriers and spitters own the roofs.
- **C12 / C13 / C14 / Block 9 / rails into Block 9**: layout data — city-layout r4 gets them (connector
  keep-clear 12 m, arena decks ≥ 32 m under-clear, tall cover in A1, Block 9 `holes`, rails ending at a
  platform). Rebuild when it lands.
- **Vistas**: mine to fix, your tooling. Write a solver (Godot headless, your checks harness): for each
  `data/vistas.json` entry keep the subject, the height band (±20 m) and the general direction; search within
  80 m of the position for a camera that is outside all geometry, has a clear ray to the subject, and whose
  16×9 ray grid hits geometry closer than 60 m in ≤ 30 % of rays. Write `data/vistas.proposed.json` (same
  schema) + `captures/city_Vn_proposed.jpg`; the lead reviews and adopts.

## r2
1. The vista solver above.
2. C15 re-measured as above.
3. **Spire silhouette**: today it reads as a mushroom — a plain cylinder under a solid inverted cone holding the
   Crown disc (S2). Make it the landmark of the key art (`art/concept/keyart/v8_crown-1.png`, `v1_pier-1.png`):
   a massive tapered shaft (≈ Ø 80 → 56 m) with vertical fins, the collar (+80) and roof (+160) rings as
   cantilevered stepped rings, and the Crown carried by 8–12 radiating ribs/brackets (dougong-like stepped
   corbels) instead of a solid cone, lit edges on every ring. Same data contract (decks, heights, B1).
4. Keep everything else; rebuild after layout r4 and rerun C12–C17 + perf.
