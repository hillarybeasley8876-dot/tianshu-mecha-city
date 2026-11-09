# city-art — review r1 (lead) — FAIL on look (systems solid); r2 = art direction

Verified: `check` 0 errors, art/props tests PASS, perf 60 fps at every vista on high and low (143–978 draws) —
the systems work is excellent: the 12 role materials with triplanar PBR, the window shader on the 4 m module,
water foam, the hologram/storm shaders, 30 props inside budget, 1,819 instances, probes, SDFGI proven on Metal,
TimeOfDay hooks. The double-sRGB and winding finds were real.
But the look is not the key art yet, and you did not look at your own vista sheets — I did:
- **Infection creep** covers whole facades with a glowing lava-lamp pattern (`art_vista_p1.0_V6.jpg`,
  `art_probe_check_V6.jpg`). It reads as garish wallpaper, not an infection.
- **Light**: progress 0 is pink-purple and dark; the key art is GOLDEN dusk — a warm sun low in the NW, gold
  haze that turns distant towers into pale silhouettes, bright windows, bloom. Violet belongs to the storm
  (progress ≥ 0.66) only.
- Facades read as flat brown with a blotchy macro texture at close range (V7); the window cells — the
  strongest read at dusk — are not carrying the image.
- The vista cameras themselves are wrong (mine: most sit in walls); city-build is solving new ones
  (`data/vistas.proposed.json`) this round — judge on those plus your own cameras until then.

## Integration (CONTRACTS §7 "Art integration")
`world/city.tscn` will instance your `environment.tscn` and drop its blockout sky/sun (city-build, this round);
your environment root applies the materials to its parent's tiles on ready. Implement that side.

## r2 — art direction (look at every sheet you make; budget your image views for it)
1. **Creep**: only within ≤ 120 m of a hive site (`mc_hive*` radius) and scaled by `set_intensity`; thin
   branching veins (ridged/Voronoi-edge noise, 0.3–1 m wide at the source thinning outward), mostly on the
   lowest 30 m of facades and the ground, over a darkened chitin base; emission ≤ 2, slow pulse. Elsewhere at
   most a few streaks near arenas.
2. **Golden dusk at progress 0**: sun ~2,500 K from the NW at 16–20°, sky gold→peach at the horizon and
   blue-violet only at the zenith, clouds lit from below; height/volumetric haze with sun scattering
   (aerial perspective: towers past ~600 m go pale gold); bloom on the sun, windows and accents. Storm violet
   ramps in from 0.66 → 1.0.
3. **Facades**: windows lit on 35–60 % of cells at dusk (warm 2,700 K / cool 5,000 K mix), panel lines on the
   4 m module, macro variation subtle (±8 % value), glass reflecting the sky (SSR + the arena probes).
4. **Water**: the canal reflects the city (SSR) for the pier shot.
5. **Spire**: light strips up the shaft, glowing ring edges, the tether bright enough to read from V1.
6. Evidence: render-vs-key-art sheets for V1, V2/canyon, V3/old town, V6, V8 at progress 0 and 1 — your eyes
   on each, notes on what still differs.
