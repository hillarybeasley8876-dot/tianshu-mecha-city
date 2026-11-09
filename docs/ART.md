# ART BIBLE — 天枢 TIANSHU: 云阙城 YUNQUE at golden dusk (lead-owned)

Detail sources: `ref/research/city-art-direction.md` (looks, kit, textures, Godot recipe), `ref/images/*/_sheet.jpg`
(moodboards). The lead judges every visual unit against THIS file and the vista captures (§7).

## 1. The look in one paragraph
A vast, clean **Chinese neo-futurist megacity at golden dusk**: low warm sun raking across pale stone, glass
and bronze; long shadows down deep street canyons; warm haze that turns distant towers into layered
silhouettes; windows and neon just coming alive; the white **Spire** with its cyan-white light tether
rising out of everything. The monster infestation is a dark, glistening corruption (charcoal chitin with
acid-green veins) creeping over this beauty. Escalation: as spires fall the light ages toward dusk and a
violet storm gathers around the Spire crown where the boss waits. Readability first: the white hero and
the dark-green-glowing monsters must pop against warm mid-tones at every distance.

## 2. Palette (sRGB hex)
| Role | Colours |
|---|---|
| Sky | zenith #2B4C7E → mid #B8A49C (warm, measured against the key art) → horizon #F2B880; sun disc #FFE3B0, sun light #FFCB9C (sunlit facades R/B ≈ 1.40); dusk clouds #E8956B / #7A5C8C |
| Haze / fog | near-horizon warm #E8B98A, high-altitude cool #8FA7C4, under-deck shadow #3A3440 |
| Architecture | pale limestone #D9D4C7, warm concrete #A9A196, white panel #EDEFF2, dark glass #1C2633 (reflects sky), brushed steel #8C939B, bronze/copper accents #B07A4A, roof terracotta #8E4A36 (Old Town) |
| Lights | warm windows #FFCF8A (30–40 % lit), cool offices #BFE3FF (10 %), sodium street #FF9F45, LED rails #3EE6FF |
| Neon / holograms | cyan #3EE6FF, magenta #FF3EA5, amber #FFB13E, jade #3EFFB0 (limited: accents, never washes) |
| Nature | foliage #3E6B3A / #5E8C4A, blossoms #F2A7C3, water #2E5A6E with sky reflection |
| Hero | white #E9EDF2, cobalt #1F4FC8, amber #F2A33A, cyan glow #4FE6FF |
| Monsters | chitin #1B2430, acid glow #9BFF3A, weak points violet #B04CFF; infection creep = chitin + green veins |
| FX | hero beams #EFFFFF core / #36E2FF glow; explosions #FF8A2B → #FFD27A; enemy acid #9BFF3A; storm #8C5BFF |
Reserved: **cyan-white = "up" connectors** (lifts, catapults, vents, anchor nodes) everywhere in the city.

## 3. Lighting and atmosphere (Godot 4.7 Forward+)
- Sun: DirectionalLight3D, elevation 16–20°, azimuth from the NORTH-WEST (315°): most vistas look north or
  north-east, so they get side/back light, glowing rims and long shadows across the streets; colour #FFD3A0, energy 2.2; shadows 4 splits 0.05/0.15/0.40, max distance 500 m (godot-tech §4.3), blend splits off; building meshes chunked ≤ 60 m so they do not land in all splits.
- Sky: PhysicalSky or a dusk HDRI (Poly Haven) + a painted/procedural skyline ring; clouds band near the
  horizon. Ambient from sky, energy 0.6–0.8; reflected light from sky.
- Fog: depth fog for aerial perspective (start 120 m, warm), height fog under the decks (cooler, denser
  below +10 m), volumetric fog density 0.0015–0.003 with sun scattering for god rays through canyons (high), fog length
  120–160 m (keep it short for quality) with depth fog beyond; check for flicker in motion.
- GI (critic P0 #6): Godot warns SDFGI degrades with fast cameras (ours: 42–190 m/s) and an open Metal bug
  makes SDFGI ignore lights on some Apple GPUs. city-art first runs the Metal check (two boxes + sun: the
  upper box's underside must receive bounce), then A/Bs on a 20 s assault-boost run + V1–V8 stills:
  (a) SDFGI 4 cascades 0.6 m min cell, (b) GI off + SSIL + sky ambient 0.7 + one ReflectionProbe per arena —
  keep the cheapest within 10 % of the look of (a). If SDFGI stays: fade it out above 60 m/s camera speed over
  0.5 s; GI mode Disabled on every moving/destructible prop. SSAO on; SSR on high for glass and wet plazas.
- Glow: on (HDR threshold ~1.2) so neon, windows, beams and the tether bloom; no full-screen bloom wash.
- Tonemap AgX, exposure 1.0; colour grade: warm highlights, teal-violet shadows, slight vignette.
- Layers have their own light (wayfinding): L0 tunnels cool fluorescent + cyan rails; L1 under-deck warm,
  dark, sodium; L2 open golden; L3/L4 sky-lit with rim light; Crown storm-violet with lightning.
- Time progression (flow unit drives it): spires 0 → 3 = sun elevation 20° → 6°, haze warmer → redder,
  more windows lit (40 % → 75 %), storm cloud cover around the Spire 0 → 100 %.

## 4. Architecture language (Chinese neo-futurism)
- Massing: stepped crowns, cantilevered sky gardens, twisting towers, megablocks with deep balconies,
  podium + tower, terraces on the escarpment (Chongqing), stilt structures, bridges between towers,
  maglev rails piercing buildings (Liziba), roof gardens, curved roof eaves reinterpreted in metal.
- Facade module 4 m floor-to-floor (a 16 m mech reads as 4 storeys); window bands, fins, louvres, panel
  seams, balconies; triplanar/box-mapped PBR + an emissive-window shader (interior mapping or randomised
  lit cells) so towers glow at dusk.
- Detail layers on every district: rooftop machinery (AC units, tanks, antennas, pads), signage and
  holograms (fictional Chinese/English brands — never real ones), cables and pipes, street furniture,
  vehicles (hover cars, trucks, maglev cars, parked and wrecked), vegetation, decals (stains, cracks,
  road markings), infection creep near hive spires, debris after fights.
- District identities: D1 Harbor rust + faded containers + crane yellow + sodium light; D2 Knot curving
  concrete + cyan LED barriers + traffic holograms; D3 Old Town warm lanterns, red-gold signage, banners,
  terracotta roofs, foliage, the Stilt Pagoda; D4 white stone + gold, reflecting pools, monumental; D5
  brutalist megablocks + thousands of windows + the giant koi-dragon hologram (magenta/cyan); D6 dark
  industrial, molten orange channels, smoke plumes from 4 reactor stacks, hazard stripes; D7 glass +
  steel, gold reflections, sky garden with cherry blossoms, prismatic Crystal Bridge.

## 5. Asset sources
Procedural Blender kit for all structure (buildings, decks, viaducts, rails, tunnels, terrain) with CC0 PBR
textures (Poly Haven / ambientCG via `tools/textures/fetch.py`). Tripo (lead-generated, `art/tripo/`) for
hero props and landmarks: vehicles, cranes, containers, rooftop machinery, holo-projectors, statues, the
pagoda top, hive spires, wrecks. Decals for grime and markings.

## 6. Performance rules for art
Merge static geometry per city tile/material; MultiMesh for repeated props; LODs (auto mesh LOD on
import + VisibilityRange HLOD for distant blocks); ≤ 3,500 draw calls; textures 2K default, 4K only for
hero/landmarks; emissive windows in shader, not lights; ≤ 16 shadowed lights in view.

## 7. Key art targets (the bar for every vista)
`art/concept/keyart/v1_pier-1.png` (V1), `v2_canyon-1.png` (multi-level street canyon with infection creep,
the 16 m mech small), `v3_oldtown-1.png` (V3 terraces + pagoda), `v8_crown-1.png` (V8 boss crown at storm).
Match their lighting logic (low warm sun, haze layers, lit windows, restrained neon, bloom on lights only),
not their exact buildings.

## 8. Vista cameras (every city/art review captures these; transforms in `data/vistas.json`, lead-owned)
V1 Insertion Pier → NE across the canal at the backlit Spire · V2 top of the Knot (+80) → east to the Spire
· V3 Old Town terraces (+48) → down over the Lower City · V4 Megablock canyon floor → up at Block 9 and
the hologram · V5 Foundry deck (+32) → reactor stacks and plumes · V6 Sky Garden (+144) → the Spire across
the Financial towers · V7 Spire Plaza (0) → straight up the Spire · V8 Crown deck (+224) panorama at storm.
Each vista must look like key art: clear focal point, layered depth (near/mid/far), haze, lights.
