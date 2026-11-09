# Level design for a vertical, highly connected future-city combat map at mech scale

Key: `level-design-vertical` · Date: 2026-11-01 · For: lead designer (Opus) → MiniMax-M78 implementation briefs
Units are metres, seconds and degrees (frames at 60 fps where noted). Every factual claim carries a source tag `[Sn]` (URLs are listed in §8). Numbers I derived myself are marked **(estimate)**. Reference images are in `ref/images/level-design-vertical/` (20 files plus `sources.md` and `_sheet.jpg`).

---

## 0. TL;DR — the rules this dossier argues for

1. **Fix the movement metrics first, then derive geometry from them.** Mech H = 16 m and boost-jump apex J = 40 m give: free climb ≤ 32 m, hard step ≥ 48 m, and a **forbidden 33–47 m "ambiguity band"** (allowed only on ledges tagged and painted as skill shortcuts). A retuned jump silently breaks levels: Crysis 2's team saw "a challenging jump" become "super-easy" after suit changes [S19]. **(estimate for thresholds)**
2. **Use 5 datum layers on a 16 m module:** L0 Undercity −40, L1 Street 0, L2 Viaduct/Upper-City ground +32, L3 Skydeck +80, L4 Rooftops +128…+176, plus a Crown at +224 for the boss. L2 doubles as the plateau ground, which is the Chongqing trick of roads landing on rooftops (Kuixinglou's plaza is both the 1st and the 22nd floor [S47]).
3. **Size streets by the dodge, not by real roads.** Alley 24–32 m, street 40–56 m, combat avenue 80–96 m (≥ 2 × (35 m dodge + 4 m half-width) = 78 m), arena 160–320 m, boss arena 300–360 m **(estimate)**.
4. **Classify gaps by air range (150–250 m):** safe ≤ 100 m, committed 100–150 m, expert 150–220 m, impassable ≥ 260 m without a connector. Dropping 48 m adds about 100 m of reach, which is how one-way routes are made **(estimate)**.
5. **Arenas get ≥ 3 entrances on ≥ 2 layers, a cover piece every 40–60 m, and at most 5 % of sightlines longer than 350 m.** No pure circles: DOOM (2016) found circular arenas limited lateral movement and blurred the options for players and AI [S32].
6. **Pace encounters the Insomniac way:** 5–6 mini-combats per arena instead of one brawl, the next wave starting halfway through the current one, and spawns kept near each sub-space [S22].
7. **Build one global weenie and one local landmark per district.** The Spire with its tether into the sky should be visible from ≥ 80 % of navigable points, and the boss sits on top of it, as Mirror's Edge Catalyst ends on top of the Shard [S21][S39].
8. **Make loops, not dead ends.** The proposed graph has 37 independent cycles, a 2.8 km L2 ring and a 1.7 km L3 skyrail loop; its 7 dead ends all hold rewards (12 % of nodes).
9. **Every adjacent layer pair needs ≥ 4 up-links and ≥ 4 down-links map-wide, plus a way up and a way down inside every district that spans both layers**, all drawn from one fixed connector palette (edge jumps, ramps ≤ 20°, terraces, lifts, vertical and long catapults, updraft vents, skyrail).
10. **Give each layer its own light:** L1 under-deck warm and dark (the Hengsha model [S26]), L3/L4 sky-lit, and one reserved hue for "up" connectors. Lighting and colour are a 40 %-certainty wayfinding tool, so pair them with landmarks [S43].
11. **Separate parallel routes by ≥ 150 m or by a layer, then commit the player with one-way drops and exclusive rewards.** Paths that sit close together feel like the same path (Tost, GDC 2023) [S25].
12. **Validate automatically.** Blender exports a graph JSON; CI checks strong connectivity, bridges, layer links, jump physics and arena-to-arena time (≤ 45 s); Godot runs capsule sweeps over every non-walk link (§5).

---

## 1. Case studies

### 1.1 Armored Core VI (FromSoftware, 2023) — Grid 086, Watchpoint/Balteus, Old Spaceport
- **Intent.** The director describes the maps as "立体的で指向性のある" (three-dimensional *and directional*) and "複雑かつ立体的" (complex and three-dimensional), built so that 3D space is crossed with 3D movement [S2]. Most maps assume you use the whole space rather than creep forward, and some missions push you through a megastructure from start to goal [S1][S3]. Combat distance was deliberately pulled in, with game speed lowered one step so threats can be "seen and handled", because constantly changing distance and height difference also looks good [S1].
- **Engagement bands.** FCS assist bands: close < 130 m, medium 130–260 m, long > 260 m [S4]. Players report white lock at about 449 m and red lock at about 389 m regardless of parts [S9] (community test). In the Balteus fight the HUD reads about 258 m to the boss at the opening (IGN screenshot, image 11).
- **Grid 086.** A stacked industrial megastructure: you arrive in the lower levels by vertical catapult [S7], take an elevator to the upper level, boost up through **destroyed vent sections** as a route, and find a hidden mercenary by following a **molten-metal drain pipe down a hole** [S5]. The guide recommends hovering to fire down on dodging tetrapod MTs [S5]. Broken structure, drains and catapults are the connectors; open-edged lattice decks are the arena (images 08–09).
- **Old Spaceport.** The guide asks for "strong boosters so you can reach high locations" and notes a reverse-joint build "so a single hop can mostly get you high enough to mount a warship". Combat logs sit on "the middle level of the tall structure at the center" [S6]. The mid-height band is a deliberate traversal shelf.
- **Scale.** ACs are about 9–12 m tall by 1/72 kit measurements (community) [S8]; RX-78-2 is 18 m [S53]. A 16 m mech sits between them.
- → **Apply:** directional districts inside an open map; vertical catapults as layer links; broken vents and drains as secret routes; hover as a combat posture over decks; combat bands of 60–260 m.

### 1.2 Titanfall 1/2 (Respawn) — big unit and small unit in one map
- **Scale.** Titans are "about twenty feet" (≈ 6 m) [S15], roughly 3.5× a pilot. Our mech against human-scale props is about 9× (estimate), so we borrow the rule of two scales rather than the absolute numbers.
- **Level designer's own notes (Jason McCord) [S10].** *Airbase:* "Titan high ground (a rarity in the game)", open dueling spaces and tight chokepoints, with most high rooftops reachable by pilots. *Boneyard:* pilot interiors are "connected underground or up high", "a plethora of ziplines" cross large open areas, Titans "gravitate towards the edges when dueling", and **"spikey rocks … designed to allow for mid-map boundaries that Pilots wouldn't camp out on."** *War Games:* "sparse and clean" fields help Titans feel powerful because they don't lose sight of targets in visually dense props, and coloured lighting and panels landmark each side. *Backwater:* "no cover or buildings on the outskirts … to keep the action central and fast", with Titans contesting the hill that overlooks the map.
- **Movement-first SP.** In *Into the Abyss*, "the top two thirds of the screen could be a threat from any direction" (David Shaver) [S11]. Levels were stitched from rapid-prototype "action blocks" [S12][S11].
- **Effect and Cause.** Two complete maps are stacked one above the other (past above present) and the player is teleported by the exact offset. Misalignment dropped testers into "a room that didn't exist" (Jake Keating) [S13].
- **MP lane reading (secondary analysis).** Titanfall 2 lanes work as roads rather than firing lanes; they meet at intersections with a central feature, and lighting separates routes from fights [S14].
- → **Apply:** make big-unit high ground rare and contested; keep fields clean where large enemies fight; give small swarmers human-scale interiors and facades the mech cannot enter (danger from above); put spiky or sloped tops on mid-map blocks we don't want camped; when stacking layers, validate every vertical teleport or catapult landing automatically.

### 1.3 Halo — Valhalla, Warzone, Bungie metrics
- **Valhalla** is semi-symmetric with two bases, a river and two caves. **Man cannons replace teleporters**: the big one throws you "a third of the way out into the main battle area" and the small ones give a "quick getaway" to a cliff. They were added so infantry could cross a vehicle map, "with a risk-reward element of being helpless in the air" [S16].
- **Bungie HEK metrics (Halo CE)** [S17]: Chief ≈ 7 ft, FOV 70°, max walkable slope 45°, running jump height 80 units (≈ 1.14 × body height), running jump distance 312 units (≈ 4.5 × height), min standing ceiling 70 units (1.0 × height). Stairs make the player hitch, so Halo uses invisible ramps over stair visuals. Our mech's jump is 2.5 × H and its air range 9–16 × H, so spaces must be relatively much larger than Halo's.
- **Warzone** (12v12 PvPvE) mixes dynamic AI encounters and boss moments across a large map (level designer Adrian Bedoya) [S18], an open-world-ish template for staggered arena activation.
- → **Apply:** long catapults that commit you in the air, with collision-ramp stairs.

### 1.4 Crysis 2/3 — New York as an "urban jungle"
- EP Nathan Camarillo lists the layers: subterranean sewers and subway access, street level, vehicles to mount or slide under, 1–3 storey buildings with blown-open fronts used as interiors, **scaffolding** to reach higher places, and heavily destroyed zones with "giant sinkholes" from seismic activity. He also stresses hard versus soft cover [S19]. Crysis 3 deliberately mixed "broad horizontal sections and more narrow vertical sections" [S20].
- → **Apply:** use destruction states (sinkholes into L0, collapsed deck ramps) and construction scaffolds as diegetic connectors; mix wide horizontal arenas with narrow vertical canyons (our A4).

### 1.5 Mirror's Edge Catalyst — City of Glass
- Design director Erik Odeldahl wanted "If you can see it, you can get there". Each section is built from linear paths, "but … there are lots of them, and … they very often intersect". The team started from the network of roads, avenues and monorail paths. **Skybridges were locked early to connect large areas "while still maintaining a believable physical separation between them — usually a wide street or a body of water."** Districts began from "silhouettes, and peaks and valleys. What's the first thing the player sees when they enter a new space?" Landmarks guide travel (the Shard, a skyscraper under construction, a named tower) [S21].
- A "Financial" district of very tall towers was cut: "a lot of climbing … we wouldn't be able to make that fun. You'd spend too much time just looking into building façades." The designers set time trials against each other to tune routes, and the game ends on top of the Shard [S21].
- → **Apply:** keep vertical climbs short (no climb > 8 s staring at a wall **(estimate)**), separate districts with streets or water bridged by skybridges, playtest with time trials, and end on the highest landmark.

### 1.6 Marvel's Spider-Man (Insomniac) — traversal-first city and rooftop arenas
- "Our New York is not a one to one representation … more an approximation and distillation." Building heights barely changed, but Harlem's lower skyline was "smudged". Fire escapes and water towers were kept and given custom traversal animations, which produced point-launch moves on rooftops (art director Jacinda Chew) [S23]. A community measurement puts in-game Manhattan at about half its real width (≈ 1.9 km vs ≈ 3.2 km) [S24].
- Arena design (designer Shane McCloskey): "keep the player in the flow state … make sure [to] have spawns nearby each space and to kickoff a new wave half through the current one"; "providing them with 5-6 mini combats vs one big arena brawl"; shooters appear at wave start to pull the player across the space; rows of breakables enclose sub-spaces when structure isn't available [S22].
- → **Apply:** distil rather than replicate (Chongqing and Hong Kong as ingredients), turn signature props into traversal affordances, and use the arena pacing above.

### 1.7 Cyberpunk 2077 — non-linear lessons (Miles Tost, GDC 2023)
- The "generic path" was made too obvious, so most players took it. Fixes: "The closer paths are to each other, the less it feels like picking one makes a difference"; exclusivity; "Validation. Paths need to be treated as special". Spread path entrances apart, control what is visible, **commit players with one-way drops**, and reward each path exclusively [S25].
- → **Apply:** parallel routes to the same arena must differ by layer or by ≥ 150 m **(estimate)**, and each must hold something exclusive.

### 1.8 Deus Ex: Human Revolution — Hengsha, the two-tier city
- Hengsha grows upward because it has no land. Skyscrapers act as columns carrying an upper city: the poor lower level has no greenery, while the upper floors get sun and green space. The idea came from a Hong Kong mockumentary about building a second city floor on huge pillars [S26] (secondary article).
- → **Apply:** L2/L3 plates on mega-columns over L1; the dark underside (image 16) against sunlit decks gives each layer an identity you can read from colour alone.

### 1.9 Destiny 2 Lightfall — Neomuna
- "Go up. Go modern. Go fabricated instead of grown… The key idea was verticality, which led to traversal and actually entering these futuristic spaces." The Strand grapple anchors to thin air, and Bungie expected players to "grapple over mountains" [S27]. Players complained that many towers look explorable but aren't [S28].
- → **Apply:** if a tower looks climbable it must be climbable (the Mirror's Edge rule); decorative-only towers belong in the skyline ring outside the playable boundary; cap mobility with a no-fly ceiling.

### 1.10 inFAMOUS Second Son and Just Cause 3 — traversal toys shape the city
- Seattle was made into "a jungle gym playground… We're not trying to do this one-for-one, Google Maps version of Seattle. That wouldn't be fun" (art director Horia Dociu) [S29]. *Vent Dash*: dash into a vertical vent on a building's side and you are shot up to the roof [S30].
- Just Cause 3 slowed the parachute "to make it easier to fight from the air" and added the wingsuit "for joyful traversal" (director Roland Lesterlin) [S31].
- → **Apply:** reactor updraft vents (F7, W5) as one-way elevators; hover is a slow combat state while boost is the traversal state.

### 1.11 DOOM (2016/Eternal) and Ghostrunner — arena shape
- GDC 2018 "Embracing Push Forward Combat" (summary): 360° combat; half walls that block sight but can be jumped or mantled; "the right-sized arena with just enough space makes the player feel faster"; circles failed [S32]. Eternal arenas use swing bars, portals and jump pads [S33]. Ghostrunner 2's Dharma Tower is a single stepped megastructure that serves as the whole level (image 18).
- → **Apply:** mech-scale half walls (8–12 m), sized arenas, and traversal kit inside arenas.

### 1.12 Gundam Evolution / Gundam Breaker
- Gundam Evolution's battle director links map structure to mode rules and expects transformable suits to fly onto high ground to drag down snipers, with flight time limited [S34]. Every perch needs a flight counter.
- Gundam Breaker: I found no primary level-design source, so it is not used here.

### 1.13 Breath of the Wild (CEDEC 2017) — composition
- "Gravity" (引力): landmarks between towers with clear functions pull players off the road. The **triangle rule** uses three sizes: large triangles are landmarks, medium ones hide mid-distance landmarks, small ones set tempo. Triangles reveal gradually; rectangles (buildings, trees) hide things so they can appear suddenly. The team overlaid a Kyoto map to calibrate distance, and set density from real convenience-store and post-box distribution [S35]. Triangles offer a choice to "go straight over … or around" [S36].
- → **Apply:** stepped (triangular) tower crowns for the go-over-or-around choice; slab blocks for ambush reveals; density set against a real city.

### 1.14 Real-world connectivity — Chongqing "8D" and Hong Kong
| Place | Hard facts | Use in our map |
|---|---|---|
| **Huangjuewan interchange** | 5 levels, 15 or 20 ramps depending on the source, 8 directions; main line 60 km/h, ramps 40 km/h [S45]; top level ≈ 37 m [S45] | D2 Knot: 5 ramp levels (0/+16/+32/+56/+80), every ramp exits somewhere |
| **Liziba station** | Rail through floors 6–8 of a 19-storey block; 8F platform ≈ 26 m above street; 132 m inside the building; 3.6 m floor clear height; 6 rail columns ≈ 22 m long kept structurally separate from the building's ≈ 69 m columns [S44] | M5: skyrail tunnel through a megablock at L3 |
| **Kuixinglou** | Plaza is "both the 1st floor and the 22nd floor" [S47] | L2 = upper-city ground; viaduct lands on rooftops |
| **Hongyadong** | 11 floors on the cliff; top (11F) entrance on Cangbai Road, 1F on the riverside road [S48] | D3 terraces: each terrace is a "ground" |
| **Raffles City "Crystal"** | 250 m up, 300 m long, 32.5 m wide, 26.5 m tall, spanning four 250 m towers [S46] | F5 Crystal Bridge (36 × 28 m tube) |
| **Central–Mid-Levels escalator** | > 800 m long, > 135 m rise [S49] (≈ 17 % mean grade) | Sheltered funicular spines |
| **Kowloon Walled City** | ≈ 33,000 people, ≈ 300–350 buildings of 10–14 storeys on ≈ 2.6 ha [S50] | Megablock interiors at small-enemy scale |

---

## 2. Theory toolkit, translated to mech scale

**Lynch's five elements** [S37]: *paths* are "channels along which the observer … moves"; *edges* are "linear elements not used or considered as paths", where "those edges seem strongest which are not only visually prominent, but also continuous in form and impenetrable to cross movement"; *districts* are areas one "mentally enters 'inside of'"; *nodes* are "strategic spots … into which an observer can enter"; *landmarks* are point references "the observer does not enter". A highly "imageable" city is "a pattern of high continuity with many distinctive parts clearly interconnected" [S38]. Mapping for us: paths = Ring Viaduct, avenues, Skyrail, tunnels; edges = canal, escarpment (as a *seam* with lips, not a wall), map boundary; districts = D1–D7; nodes = Plaza, Knot, Forum, Root Station, Through-Block Station; landmarks = Spire (global), Pagoda, Knot, Crystal, Stacks, Block 9.

**Weenies.** Sklar's commandment #4: "Create a 'weenie.' Lead visitors from one area to another by creating visual magnets and giving visitors rewards for making the journey" [S39]. The Spire and tether are the master weenie; each district's local landmark should be visible from its arena entrances.

**Loops versus dead ends.** Use loopbacks, hubs and three-lane typologies [S41]. A dead end is acceptable only with a reward or a vista. Every arena should sit on a cycle, so it is never reachable through only one bridge edge (checked in §5).

**Critical path versus optional.** For the open demo, the critical path is START → any 4 of the 6 arenas (free order) → Spire Roof Ring → one-way catapult → boss. Optional content is caches, perches and the Undercity.

**Arena shapes** [S41][S42]. A *combat bowl* has central full cover for circling; an *arena/POI* has several circulation lanes plus cover; for foothold, use a **vista with a one-way entrance** for the boss. Our arena shapes are rounded rectangles and canyons, never pure circles [S32].

**Chokepoints and flanks.** Each arena gets ≥ 3 entries on ≥ 2 layers. Chokepoints are a squeeze tunnel (24 m clear), a skybridge (32–40 m wide) or a ramp neck; each has a flank via another layer.

**Three lanes** [S41]. Approaches to each arena run as a ground lane (L1), an elevated lane (L2/L3) and an underground or interior lane (L0).

**Vertical layering.** Layers must differ by *function and look* (Hengsha [S26]), not only height. Links between them use the §3.4 connector palette.

**Breadcrumbing and light.** Wayfinding certainty tiers (non-scientific) [S43]: subtle cues 1–20 %; lighting/colour 40 %; sightline composition 35 %; breadcrumb trails 80 %; dynamic UI 92 %. Respawn used coloured lighting and panels to mark map sides [S10]. Mirror's Edge used colour against white architecture to guide the eye [S21].

**Encounters in open worlds** [S42]. Footholds: "player ambushes enemies" (open-world outposts), "enemies ambush player", "vista with one-way entrance". Enemy palette: 2 types is "regular", 3 is "complex", 5+ is "slaughter". Use 2–3 enemy types per wave.

**Metrics-first** [S40]. Player metrics (facts) and building metrics (prescriptions) are separate things. Build a metrics zoo. "Don't follow real world scale." Use world-aligned grid textures and a jump-arc preview tool (Psychonauts 2).

---

## 3. Metrics for a 16 m mech (capability → geometry)

### 3.1 Capability baseline
| Parameter | Value | Basis |
|---|---|---|
| Height H / shoulder width | 16 m / 8–9 m | given / (estimate) |
| Collision capsule | r = 4.0 m, h = 16 m | (estimate) |
| Cockpit (FP) eye height | 12–13 m | (estimate) |
| TPS camera | boom 14–18 m, +4–6 m above head, FOV 70–80° | (estimate); Halo FOV 70° for reference [S17] |
| Walk / run (no boost) | ≈ 9 m/s / 15–18 m/s | Froude Fr = 1 caps walking at √(g·L) [S52] with L ≈ 8 m → 8.9 m/s; run (estimate) |
| Ground boost | 50 m/s | (estimate) |
| Assault boost | 100 m/s for ≤ 3 s | (estimate) |
| Quick-boost dodge | 35 m lateral in 0.25 s (15 frames) | (estimate) |
| Boost-jump apex J | 40 m | given |
| Air range on full EN, R | 150–250 m (design for R = 150) | given |
| Game gravity | 19.6 m/s² (2 g, for weight) | (estimate) |
| Engagement bands | close < 130, mid 130–260, long > 260 m | AC6 FCS bands [S4] |

### 3.2 Geometry table (all derived numbers are estimates unless sourced)
| Element | Value | Rule / why |
|---|---|---|
| **Step-over** (no jump) | ≤ 2 m | curbs and rubble; use collision ramps over stairs (Halo HEK [S17]) |
| **Hop** (no EN) | ≤ 8 m | low walls, cover tops |
| **Free climb** (one boost jump) | ≤ 32 m (0.8 J) | 8 m apex margin |
| **Ambiguity band** | 33–47 m | forbidden unless tagged as a painted "skill lip" |
| **Hard step** (needs connector) | ≥ 48 m (1.2 J) | cannot be cheesed |
| **Layer datums** | L0 −40, L1 0, L2 +32, L3 +80, L4 +128/+144/+160/+176, Crown +224 | 16 m module |
| **Deck slab** | 4 m (L2), 6 m (L3+) | under-L2 clear height = 28 m |
| **Min clear height (any navigable cover)** | 24 m (1.5 H) | camera boom and jump bonk |
| **Underground main / squeeze** | 32–36 m clear × 48–64 m wide / 24 m × 32 m | squeeze = no jumping (tension) |
| **Alley / street / avenue** | 24–32 / 40–56 / 80–96 m | dodge room: avenue ≥ 2 × (35 + 4) = 78 m; a street allows one dodge from the centre line |
| **Viaduct deck (L2)** | 48–64 m wide | 2 lanes of mech traffic plus dodge |
| **Skybridge** | 32–40 m wide, ≥ 28 m interior height | Raffles Crystal 32.5 × 26.5 m [S46] |
| **Skyrail beam walkway** | 24 m wide | (estimate) |
| **Parapet** | 4–6 m | readable edge you can still shoot over |
| **Gap, same height** | safe ≤ 100 / committed 100–150 / expert 150–220 / impassable ≥ 260 m | from R = 150–250 m |
| **Gap, downward** | + v_air·√(2Δh/g) ≈ +100 m per 48 m drop | v_air 45 m/s, g 19.6 m/s² |
| **Gap, upward** | Δh ≤ +32 m with horizontal ≤ 80 m | (estimate) |
| **Low cover / high cover** | 8–10 m tall × 16–24 m wide / ≥ 20 m × ≥ 24 m | hides legs / hides all |
| **Cover spacing** | 40–60 m (≈ 1 s of boost); every arena point within 60 m of full cover | (estimate) |
| **Soft (destructible) cover share** | 30–40 % of arena cover | hard versus soft cover [S19] |
| **Max clear LOS in arenas** | 350 m (≤ 5 % of sampled pairs above) | under the ≈ 389–449 m community lock limit [S9] |
| **Straight street segment** | ≤ 300 m before a bend, node or occluder | stops lane sniping |
| **L1 overhead cover** | ~50 % of L1 combat streets under decks/canopies | weakens L3 overwatch |
| **Arena: skirmish / major / boss** | 160–240 m, 2 tiers / 240–320 m, 3 tiers / 300–360 m | crossing 3–6 s at 50 m/s |
| **Ramps** | road 8–12 % (cosmetic traffic); mech service ramp ≤ 20°; walkable limit 40° | Godot `floor_max_angle` default is 45° [S60] |
| **Spiral ramp** | radius 60–90 m, ≈ +44 m per turn at 10 % | 2π·70·0.10 |
| **Building tiers** | A 16–32 m (hop blocks) · B 48–80 m (street walls) · C 128–176 m (L4 band) · D 240–400 m (landmarks) · E Spire 360 m + tether | massing |
| **Facade module** | 4 m floor-to-floor, so the mech reads as 4 storeys | CTBUH: office 3.9, residential 3.1, mixed 3.5 m [S51] |
| **Travel budgets** | arena→arena ≤ 45 s; any node→nearest arena ≤ 25 s; L1 point→up-connector ≤ 8 s | pacing (estimate) |

### 3.3 Formulas the agents should code (so metrics follow tuning)
- `free_climb = 0.8 * J`; `hard_step = 1.2 * J`; ambiguity band = (free_climb, hard_step).
- `safe_gap = 0.67 * R_min`; `committed_gap = R_min`; `impassable = 1.05 * R_max`.
- `drop_bonus(Δh) = v_air * sqrt(2*Δh/g)`.
- `avenue_min = 2 * (dodge + capsule_r)`; `min_ceiling = max(1.5*H, H + cam_height_above_head + 2)`.
- `arena_cross_time = width / v_boost` (target 3–6 s).

### 3.4 Connector palette (every vertical link uses one of these)
| Kind | Use | Metric | Note |
|---|---|---|---|
| `edgejump` | deck edge ↔ lower layer | Δz ≤ 32 m | both directions |
| `ramp` | road or service ramp | ≤ 20° (spiral 10 %) | AI-friendly |
| `stairs` | terraces, pylons, balconies | steps of 16–32 m | Hongyadong/terrace style |
| `lift` | freight lift, 40 × 40 m platform | 16 m/s + 3 s | doubles as enemy spawn (Spider-Man elevators [S22]) |
| `vcat` | vertical catapult | Δz 48–144 m in 2–4 s | AC6 Grid 086 [S7] |
| `lcat` | long catapult | 300–600 m in 4–6 s, cannot boost for the first 1.5 s | Valhalla risk-reward [S16] |
| `vent` | updraft shaft, one-way up | Δz up to 150 m | inFAMOUS Vent Dash [S30] |
| `rail` | skyrail beam walkway | 24 m wide | Liziba [S44] |
| `drop` | any one-way down | — | commitment (Tost [S25]) |

---

## 4. Proposed demo map — "Escarpment City around the Spire"

### 4.1 Parti and numbers
- **Playable square 1,400 × 1,400 m** (origin at centre; Blender X = east, Y = north, Z = up). A 200 m non-playable skyline ring sits outside it, and a no-fly ceiling at +260 m **(estimate)**. In Godot after glTF import a point is (X, Z, −Y). ±700 m stays far inside Godot's recommended single-precision range of 4096–8192 m for third-person games [S59].
- **Two Lynch edges.** (1) A **32 m escarpment** at Y ≈ +150 separates the Lower City (ground 0) from the Upper City plateau (ground +32 = L2). It is a *seam*: free-climbable only at lips, because buildings along its crest raise it to ≥ 48 m elsewhere. (2) A **canal** (60 m wide, water −16) closes the south.
- **Seven districts.** D1 Harbor (SW), D2 Interchange Knot (W), D3 Old Town Terraces (NW, upper), D4 Spire and Civic Core (centre, straddling the cliff), D5 Megablocks (NE, upper), D6 Foundry Works (E/SE), D7 Financial Skyline (S).
- **Layers.** L0 −40 · L1 0 · L2 +32 · L3 +80 · L4 +128…+176 · Crown +224.
- **Landmarks.** Global: **the Spire** (360 m, stepped crown, tether into the sky). Local: Stilt Pagoda (D3), the Knot itself (D2), Harbor cranes (D1), Crystal Bridge (D7), Reactor Stacks with plumes (D6), Block 9 with the rail hole and a giant hologram (D5).
- **Paths.** L2 Ring Viaduct (2.8 km loop; it lands on the plateau and becomes Ridge Avenue), L3 Skyrail loop (1.7 km), L1 avenues (West, Spire, Canal Road), L0 tunnel cross (W, E, N trunks plus the Old Line).

### 4.2 Plan (to scale: 1 char = 20 m E–W, 1 row = 40 m N–S; north up)
Legend: `~` water · `^` escarpment crest (32 m) · `=` L2 Ring Viaduct (+32) · `#` L3 skyrail (+80) · `.` L0 tunnels (−40) · `-` L1 avenues · `@` Spire footprint · `[A#]` arena · `(B)` boss · `*` landmark · `$` reward · `>` start.
Label → node: `H0>` start pier · `$h3` H3 crane cab · `$c6` O6 cliff cache · `*PAGODA$` O4/O5 · `$c7` M7 arcology cache · `$u6` U6 maglev depot · `*STACKS$` W5 reactor perch · `*CRYSTAL` F5 · `M6` M6b · `[A2]KNOT` K1–K5 · `S3` S3s collar; other labels are node ids from §4.7.
```
+-----------------------------------------------------------------------+
| D3 OLD TOWN (+32)        D4n FORUM (+32)         D5 MEGABLOCKS (+32)  |
|                                                                 $c7   |
| $c6                                                                   |
|                                                                       |
|                                                            M4         |
|                                                                       |
|                                                                       |
|       *PAGODA$                                         [A4]           |
|                                                        ##             |
|                                 ====S5=========M1    ###       M6     |
|    O7/U4              ==========               ===  ##                |
|       ..   O3=========            . U5            #M5                 |
|        ..   ==                @@@@@@S4@        ### #==                |
|          .   ==V7                 .        ####    ## ==V6            |
|^^^^^^^^^^^^^^==^^^^^^^^^^^^^S6@@@@@@@@@#####^^^^^^^^#^^==^^^^^^^^^^^^^|
|            ..O1          ####SPIRE.                  #   = D6 FOUNDRY |
| D2 INTERCHANGE     ######     @@@@@@@@@              W8  ==           |
|            == .#####              # S3             ---#    =          |
|            #####.             (B)+224             --   #   ==V5       |
|         [A2]KNOT-.-               .#             -     ##  =          |
|            ==...  ..--------------.#---$u6-------       #===  *STACKS$|
|              =  .....           [A3]     .    W1----     #            |
|              ==-   ....U1         .##     ..U3      ---=[A5]          |
| D1 HARBOR      =    ..   ..........S2.........       #####            |
|                ==-..     *CRYSTAL . #        ..##W7##= --             |
|                 H4     ==============#=====#####.. == --              |
|        $h3     --V2=====          -V3######  =====V4 -                |
|              ---          F3      -   F6        -  --                 |
|            [A1]                 ---F2-          - --                  |
|                ----        -[A6]     -----      --                    |
|~~~~~~~~~~~~        ----F7---              -----H6                     |
|~~~~~~~~~~~~         H5                                                |
|~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~|
|~~~~~~H0>~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~|
|~~~~~~~~~~~~         D7 FINANCIAL        CANAL edge (-16)              |
|~~~~~~~~~~~~                                                           |
+-----------------------------------------------------------------------+
```

### 4.3 Section S→N through the Spire axis (X ≈ 0; heights to scale, distances schematic)
```
 z (m)   S <- canal -- D7 FINANCIAL ---------- D4s PLAZA -------- SPIRE (straddles the 32 m cliff) -- D4n FORUM -> N
         y: -600    -450      -330    -300          -120          +40 .......................... +200        +330
  +224                                                       [============ B1 CROWN DECK ============]  boss
  +176                     [==F5 CRYSTAL==]                      ||                            ||
  +160                     |              |                      ||         [==S4 RING==]      ||
  +144           [=F4 SKY GARDEN=]        |                      ||                            ||
   +80           |         |  F6 ####### skyrail ########## [S3s COLLAR]######################[S3n]
   +32           |         |          [=V3 viaduct=]             ||                     cliff  ||___[S5 FORUM]___
     0  ~~~~ ____|_________|____________________[A3 PLAZA]_______||______________________|     ||      :
   -16  ~~~~ canal                                                                                     :  U5 lift
   -40                         ...........[S2 ROOT STN]......................... L0 north tunnel ........:[U5]
```

### 4.4 Districts
| ID | District | Footprint (X / Y, m) | Layers present | Role | Local landmark | Arena |
|---|---|---|---|---|---|---|
| D1 | Harbor | −700…−250 / −700…−260 | L0 portal, L1, docks −12, crane +48, L2 viaduct | start, tutorial fight, crane perch | gantry cranes | A1 Container Yard |
| D2 | Interchange Knot | −700…−250 / −260…+150 | L0–L3 (ramp levels 0/+16/+32/+56/+80) | west vertical gym; Ring Viaduct W | the Knot | A2 |
| D3 | Old Town Terraces | −700…−200 / +150…+700 | L0 (mine shaft), L1 foot, +16 terrace, L2 plateau, pagoda to +128 | exploration, caches, escarpment link | Stilt Pagoda | — (outposts only) |
| D4 | Spire & Civic Core | −250…+240 / −250…+700 | L0 Root Stn, L1 Plaza, L2 Forum, L3 Collar, L4 Roof Ring, Crown | hub and boss | Spire + tether | A3, Boss |
| D5 | Megablocks | +240…+700 / +150…+700 | L2 canyon floor, L3 skybridges and through-block rail, L4 roofline | vertical canyon fight | Block 9 (rail hole, hologram) | A4 |
| D6 | Foundry Works | +240…+700 / −560…+150 | L0 junction, L1 floor, L2 deck, L3 gantry, L4 stacks | stacked industrial decks | Reactor Stacks | A5 |
| D7 | Financial Skyline | −250…+240 / −560…−250 | L1 avenue, L2 viaduct, L3 skydeck, L4 garden +144, Crystal +176 | rooftop fight, sniper perch | Crystal Bridge | A6 |

### 4.5 Arenas (sizes, sockets and palettes are estimates)
| Arena | Nodes | Size | Tiers (z) | Entries | Defining features | Spawn sockets | Enemy palette |
|---|---|---|---|---|---|---|---|
| A1 Container Yard | A1 | 260 × 200 m | −12, 0, +16, +48 | 5 (L1, L2, crane) | mega-container stacks 12–16 m, crane gantries, dock trench | 4: ship hatches, warehouse doors, crane drop, trench | 2 types (tutorial) |
| A2 Interchange Knot | K1–K5 | 300 × 300 m | 0, +16, +32, +56, +80 | 7 (L0–L3) | spiral ramps, flyover gaps, viaduct through it | 5: tunnel mouth, 3 ramp ends, rail spur | 2–3 types: flyers + ramp chargers |
| A3 Spire Plaza | A3, S1b | 280 × 200 m | −20 court, 0, +16 terraces | 9 | sunken court to Root Station, canopies, terraces | 5: station escalators, lifts, avenue ends | 3 types |
| A4 Megablock Canyon | A4, M3, M4 | 90 × 400 m + roofs | +32, +80, +128 | 6 (L2–L4) | skybridges across the canyon, facade breaches, vcat | 6: breaches (swarmers), lift, bridge ends | 2 types + elite |
| A5 Foundry Decks | A5, W3, W4 | 300 × 240 m | 0, +32, +80 (+144 stack) | 7 (L1–L4) | open lattice decks, molten channel, vcat, updraft vent | 5: furnace doors, conveyor tunnels, gantry drop, rail | 3 types |
| A6 Sky Garden | F4 (+F5) | 240 × 200 m | +144, Crystal +176 | 3 (L1 vent, L3, L4) | park deck between towers; edges drop to L3/L1 | 4: tower lobbies, drop pods | 2 types: flyers + snipers |
| Boss Crown | B1 | 320 × 320 m deck, core Ø 80 m | +208 trench, +224 deck, +240 fins | 1 one-way (vcat S4→B1) + exit lift | central core (full cover), 4 fins 24 m tall, 2 broken edge gaps, fall → S4 ring (re-entry ≤ 12 s) | boss + 2 add sockets | boss 40–60 m tall |

Boss foothold uses the "vista with one-way entrance" pattern [S42]: from S4 you see the boss silhouette on the Crown before you commit to the catapult. Unlock rule for the open demo: clear any 4 of the 6 arenas → the Ascension Catapult at S4 powers up **(estimate)**.

### 4.6 Loops (lengths from the node coordinates)
| Loop | Layer | Nodes | Length | Lap @ 50 m/s |
|---|---|---|---|---|
| Ring Viaduct | L2 | K3–V2–V3–V4–V5–V6–M1–S5–O3–V7–K3 | 2,801 m | 56 s |
| Skyrail | L3 | S3s–F6–W4–M5–S3e–S3s | 1,697 m | 34 s |
| South loop | L1/L0 | A1–H5–F2–A3–S2–U1–H4–A1 | 1,442 m | 29 s |
| Canal–Foundry | L1 | F2–H6–A5–W1–A3–F2 | 1,445 m | 29 s |
| Spire Collar | L3 | S3s–S3e–S3n–S3w | 622 m | 12 s |

Long straight runs must be broken: Old Line tunnel U4–U1 (591 m) with two bends, so the longest straight sight is ≤ 250 m; West Avenue K1–A3 (474 m) with a mid-block arch at X ≈ −230; rail W4–M5 (471 m) passing through a signal gantry **(estimate)**.

### 4.7 Node list (Blender coordinates; Godot = (X, Z, −Y))
| id | name | district | layer | x | y | z | type | arena |
|---|---|---|---|---:|---:|---:|---|---|
| H0 | Insertion Pier | D1 | L1 | -560 | -600 | 0 | start |  |
| A1 | Container Yard | D1 | L1 | -430 | -420 | 0 | arena | A1 |
| H3 | Crane Cab | D1 | L2+ | -520 | -330 | 48 | reward |  |
| H4 | Harbor Portal | D1 | L1 | -330 | -290 | 0 | connector |  |
| H5 | Canal Road West | D1 | L1 | -240 | -520 | 0 | path |  |
| U1 | West Junction | D2 | L0 | -250 | -190 | -40 | hub |  |
| K1 | Knot Base | D2 | L1 | -470 | -60 | 0 | arena | A2 |
| K2 | Knot Ramp Ring | D2 | L1+ | -430 | -10 | 16 | arena | A2 |
| K3 | Knot Deck / Viaduct W | D2 | L2 | -470 | -40 | 32 | arena | A2 |
| K4 | Knot Flyover | D2 | L2+ | -560 | -120 | 56 | arena | A2 |
| K5 | Knot Crown / Rail Spur | D2 | L3 | -470 | -40 | 80 | arena | A2 |
| O1 | Terrace Foot | D3 | L1 | -420 | 110 | 0 | connector |  |
| O2 | Terrace Mid | D3 | L1+ | -430 | 150 | 16 | connector |  |
| O3 | Old Town Square | D3 | L2 | -440 | 240 | 32 | hub |  |
| O4 | Stilt Pagoda Base | D3 | L2 | -520 | 430 | 32 | landmark |  |
| O5 | Pagoda Crown | D3 | L4 | -520 | 430 | 128 | reward |  |
| O6 | Cliff Cache | D3 | L2 | -650 | 620 | 32 | reward |  |
| O7 | Mine Shaft Top | D3 | L2 | -580 | 300 | 32 | connector |  |
| U4 | Mine Shaft Bottom | D3 | L0 | -580 | 300 | -40 | connector |  |
| A3 | Spire Plaza | D4 | L1 | 0 | -120 | 0 | arena | A3 |
| S1b | Plaza Terraces | D4 | L1+ | 0 | -30 | 16 | arena | A3 |
| S2 | Spire Root Station | D4 | L0 | 0 | -240 | -40 | hub |  |
| S3s | Spire Collar S | D4 | L3 | 0 | 10 | 80 | hub |  |
| S3e | Spire Collar E | D4 | L3 | 110 | 120 | 80 | connector |  |
| S3n | Spire Collar N | D4 | L3 | 0 | 230 | 80 | connector |  |
| S3w | Spire Collar W | D4 | L3 | -110 | 120 | 80 | connector |  |
| S4 | Spire Roof Ring | D4 | L4 | 0 | 210 | 160 | hub |  |
| B1 | Crown Deck (boss) | D4 | L5 | 0 | 120 | 224 | boss | BOSS |
| S5 | Upper Civic Forum | D4 | L2 | 0 | 330 | 32 | hub |  |
| S6 | Spire Steps | D4 | L1+ | -150 | 150 | 16 | connector |  |
| U5 | Spire North Root | D4 | L0 | 0 | 260 | -40 | connector |  |
| F2 | Financial Avenue | D7 | L1 | 0 | -420 | 0 | hub |  |
| F3 | Tower Lift Lobby | D7 | L1 | -120 | -360 | 0 | connector |  |
| F4 | Sky Garden | D7 | L4 | -60 | -450 | 144 | arena | A6 |
| F5 | Crystal Bridge | D7 | L4 | -40 | -330 | 176 | landmark |  |
| F6 | Financial Skydeck | D7 | L3 | 60 | -360 | 80 | hub |  |
| F7 | Financial Updraft | D7 | L1 | -170 | -500 | 0 | connector |  |
| H6 | Canal Road East | D6 | L1 | 260 | -520 | 0 | path |  |
| V2 | Viaduct SW | D1 | L2 | -330 | -330 | 32 | path |  |
| V3 | Viaduct S | D7 | L2 | 0 | -300 | 32 | path |  |
| V4 | Viaduct SE | D6 | L2 | 330 | -330 | 32 | path |  |
| V5 | Viaduct E | D6 | L2 | 520 | -40 | 32 | path |  |
| V6 | Plateau Landing E | D5 | L2 | 420 | 170 | 32 | connector |  |
| V7 | Plateau Departure W | D3 | L2 | -400 | 170 | 32 | connector |  |
| W1 | Foundry Gate | D6 | L1 | 250 | -120 | 0 | path |  |
| A5 | Foundry Floor | D6 | L1 | 470 | -200 | 0 | arena | A5 |
| W3 | Foundry Deck | D6 | L2 | 470 | -220 | 32 | arena | A5 |
| W4 | Foundry Gantry / Rail Stn | D6 | L3 | 470 | -200 | 80 | arena | A5 |
| W5 | Reactor Stack Perch | D6 | L4 | 600 | -80 | 144 | reward |  |
| W7 | Foundry Portal | D6 | L1 | 300 | -300 | 0 | connector |  |
| W8 | Escarpment Ramp Foot | D6 | L1 | 380 | 40 | 0 | connector |  |
| U3 | East Junction | D4 | L0 | 200 | -220 | -40 | hub |  |
| U6 | Maglev Depot | D4 | L0 | 120 | -120 | -40 | reward |  |
| M1 | Ridge Avenue East | D5 | L2 | 260 | 330 | 32 | path |  |
| A4 | Canyon Floor | D5 | L2 | 460 | 420 | 32 | arena | A4 |
| M3 | Canyon Skybridge | D5 | L3 | 460 | 420 | 80 | arena | A4 |
| M4 | Canyon Roofline | D5 | L4 | 500 | 540 | 128 | arena | A4 |
| M5 | Through-Block Station | D5 | L3 | 330 | 250 | 80 | hub |  |
| M6b | Megablock Lift Base | D5 | L2 | 600 | 330 | 32 | connector |  |
| M7 | Arcology Roof Cache | D5 | L4 | 640 | 640 | 160 | reward |  |

### 4.8 Edge list (106 edges; horizontal distance, Δz and travel time computed from coordinates)
| from | dir | to | kind | horiz m | Δz m | t fwd s | t back s |
|---|:-:|---|---|---:|---:|---:|---:|
| H0 | ↔ | A1 | path | 222 | +0 | 4.4 | 4.4 |
| A1 | ↔ | H5 | path | 215 | +0 | 4.3 | 4.3 |
| A1 | ↔ | H4 | path | 164 | +0 | 3.3 | 3.3 |
| H4 | ↔ | U1 | ramp | 128 | -40 | 3.4 | 3.4 |
| A1 | → | H3 | stairs | 127 | +48 | 6.8 |  |
| H3 | → | A1 | drop | 127 | -48 | 5.3 |  |
| A1 | ↔ | V2 | edgejump | 135 | +32 | 5.0 | 5.1 |
| H5 | ↔ | F2 | path | 260 | +0 | 5.2 | 5.2 |
| H4 | ↔ | K1 | path | 269 | +0 | 5.4 | 5.4 |
| K1 | ↔ | U1 | ramp | 256 | -40 | 6.5 | 6.5 |
| K1 | ↔ | K2 | ramp | 64 | +16 | 1.6 | 1.6 |
| K2 | ↔ | K3 | ramp | 50 | +16 | 1.3 | 1.3 |
| K3 | ↔ | K4 | ramp | 120 | +24 | 3.1 | 3.1 |
| K4 | ↔ | K5 | ramp | 120 | +24 | 3.1 | 3.1 |
| K1 | ↔ | K3 | edgejump | 20 | +32 | 2.4 | 2.6 |
| K3 | ↔ | V2 | path | 322 | +0 | 6.4 | 6.4 |
| K3 | ↔ | V7 | path | 221 | +0 | 4.4 | 4.4 |
| K5 | ↔ | S3w | rail | 394 | +0 | 7.9 | 7.9 |
| K1 | ↔ | O1 | path | 177 | +0 | 3.5 | 3.5 |
| K1 | ↔ | A3 | path | 474 | +0 | 9.5 | 9.5 |
| O1 | ↔ | O2 | edgejump | 41 | +16 | 2.9 | 2.5 |
| O2 | ↔ | O3 | edgejump | 91 | +16 | 4.0 | 3.6 |
| V7 | ↔ | O1 | edgejump | 63 | -32 | 3.5 | 3.4 |
| O3 | ↔ | V7 | path | 81 | +0 | 1.6 | 1.6 |
| O3 | ↔ | O4 | path | 206 | +0 | 4.1 | 4.1 |
| O4 | → | O5 | stairs | 0 | +96 | 6.0 |  |
| O5 | → | O4 | drop | 0 | -96 | 3.4 |  |
| O4 | ↔ | O6 | path | 230 | +0 | 4.6 | 4.6 |
| O3 | ↔ | O7 | path | 152 | +0 | 3.0 | 3.0 |
| O7 | → | U4 | drop | 0 | -72 | 3.0 |  |
| U4 | → | O7 | lift | 0 | +72 | 7.5 |  |
| U4 | ↔ | U1 | tunnel | 591 | +0 | 11.8 | 11.8 |
| O3 | ↔ | S5 | path | 449 | +0 | 9.0 | 9.0 |
| A3 | ↔ | S1b | edgejump | 90 | +16 | 4.0 | 3.6 |
| A3 | ↔ | S2 | ramp | 120 | -40 | 3.2 | 3.2 |
| S1b | ↔ | S3s | lift | 40 | +64 | 7.8 | 7.8 |
| S3s | → | A3 | drop | 130 | -80 | 6.0 |  |
| S3s | ↔ | S3e | path | 156 | +0 | 3.1 | 3.1 |
| S3e | ↔ | S3n | path | 156 | +0 | 3.1 | 3.1 |
| S3n | ↔ | S3w | path | 156 | +0 | 3.1 | 3.1 |
| S3w | ↔ | S3s | path | 156 | +0 | 3.1 | 3.1 |
| S3n | ↔ | S4 | lift | 20 | +80 | 8.4 | 8.4 |
| S4 | → | B1 | vcat | 90 | +64 | 3.7 |  |
| B1 | → | S4 | drop | 90 | -64 | 4.9 |  |
| B1 | → | A3 | lift | 240 | -224 | 21.8 |  |
| S4 | → | S5 | drop | 120 | -128 | 6.6 |  |
| S5 | ↔ | S3n | lift | 100 | +48 | 8.0 | 8.0 |
| A3 | ↔ | S6 | edgejump | 309 | +16 | 8.9 | 8.4 |
| S6 | ↔ | S5 | edgejump | 234 | +16 | 7.2 | 6.8 |
| S2 | ↔ | U1 | tunnel | 255 | +0 | 5.1 | 5.1 |
| S2 | ↔ | U3 | tunnel | 201 | +0 | 4.0 | 4.0 |
| S2 | ↔ | U5 | tunnel | 500 | +0 | 10.0 | 10.0 |
| U5 | ↔ | S5 | lift | 70 | +72 | 8.9 | 8.9 |
| U3 | ↔ | U6 | tunnel | 128 | +0 | 2.6 | 2.6 |
| A3 | ↔ | F2 | path | 300 | +0 | 6.0 | 6.0 |
| A3 | ↔ | W1 | path | 250 | +0 | 5.0 | 5.0 |
| V3 | ↔ | F2 | edgejump | 120 | -32 | 4.8 | 4.7 |
| V3 | ↔ | A3 | ramp | 180 | -32 | 4.6 | 4.6 |
| F2 | ↔ | F3 | path | 134 | +0 | 2.7 | 2.7 |
| F3 | ↔ | F6 | lift | 180 | +80 | 11.6 | 11.6 |
| F6 | ↔ | S3s | rail | 375 | +0 | 7.5 | 7.5 |
| F6 | ↔ | W4 | rail | 440 | +0 | 8.8 | 8.8 |
| F6 | → | F4 | stairs | 150 | +64 | 7.3 |  |
| F4 | → | F6 | drop | 150 | -64 | 6.2 |  |
| F7 | → | F4 | vent | 121 | +144 | 7.3 |  |
| F4 | → | F2 | drop | 67 | -144 | 5.6 |  |
| F4 | ↔ | F5 | edgejump | 122 | +32 | 4.7 | 4.8 |
| F5 | → | S4 | lcat | 541 | -16 | 5.5 |  |
| H5 | ↔ | F7 | path | 73 | +0 | 1.5 | 1.5 |
| F2 | ↔ | H6 | path | 279 | +0 | 5.6 | 5.6 |
| V2 | ↔ | V3 | path | 331 | +0 | 6.6 | 6.6 |
| V3 | ↔ | V4 | path | 331 | +0 | 6.6 | 6.6 |
| V3 | ↔ | F6 | lift | 85 | +48 | 7.7 | 7.7 |
| V4 | ↔ | W3 | path | 178 | +0 | 3.6 | 3.6 |
| V4 | ↔ | V5 | path | 347 | +0 | 6.9 | 6.9 |
| V5 | ↔ | V6 | path | 233 | +0 | 4.7 | 4.7 |
| W1 | ↔ | A5 | path | 234 | +0 | 4.7 | 4.7 |
| A5 | ↔ | W3 | edgejump | 20 | +32 | 2.4 | 2.6 |
| W3 | → | W4 | vcat | 20 | +48 | 2.5 |  |
| W4 | → | W3 | drop | 20 | -48 | 3.0 |  |
| A5 | ↔ | W4 | lift | 0 | +80 | 8.0 | 8.0 |
| A5 | → | W5 | vent | 177 | +144 | 8.5 |  |
| W5 | → | A5 | drop | 177 | -144 | 8.1 |  |
| A5 | ↔ | H6 | path | 383 | +0 | 7.7 | 7.7 |
| H6 | ↔ | W7 | path | 224 | +0 | 4.5 | 4.5 |
| W7 | ↔ | U3 | ramp | 128 | -40 | 3.4 | 3.4 |
| W1 | ↔ | W8 | path | 206 | +0 | 4.1 | 4.1 |
| W8 | ↔ | V6 | ramp | 136 | +32 | 3.5 | 3.5 |
| V5 | ↔ | A5 | edgejump | 168 | -32 | 5.8 | 5.7 |
| W4 | ↔ | M5 | rail | 471 | +0 | 9.4 | 9.4 |
| V6 | ↔ | M1 | path | 226 | +0 | 4.5 | 4.5 |
| M1 | ↔ | S5 | path | 260 | +0 | 5.2 | 5.2 |
| M1 | ↔ | A4 | path | 219 | +0 | 4.4 | 4.4 |
| V6 | ↔ | A4 | path | 253 | +0 | 5.1 | 5.1 |
| A4 | → | M3 | stairs | 0 | +48 | 4.0 |  |
| M3 | → | A4 | drop | 0 | -48 | 2.5 |  |
| M3 | → | M4 | vcat | 126 | +48 | 3.9 |  |
| M4 | → | M3 | drop | 126 | -48 | 5.3 |  |
| M3 | ↔ | M5 | path | 214 | +0 | 4.3 | 4.3 |
| M5 | ↔ | S3e | rail | 256 | +0 | 5.1 | 5.1 |
| A4 | ↔ | M6b | path | 166 | +0 | 3.3 | 3.3 |
| M6b | ↔ | M4 | lift | 233 | +96 | 13.7 | 13.7 |
| M4 | → | M7 | edgejump | 172 | +32 | 5.8 |  |
| M7 | → | M4 | drop | 172 | -32 | 5.9 |  |
| M4 | → | S4 | lcat | 599 | +32 | 6.0 |  |
| M1 | ↔ | M5 | lift | 106 | +48 | 8.1 | 8.1 |

Edge kinds follow the §3.4 palette; times come from the model in §5.3; `↔` means traversable both ways, `→` means one-way.

### 4.9 Validation of this proposal (reference validator in §5.4, run on 2026-11-01)
`nodes 60 · directed edges 185 · independent loops 37 · dead ends 7 (all rewards or start, 12 %) · arena→arena worst 32.6 s (A1↔A4), median 16.9 s · any node→nearest arena ≤ 16.6 s · PASS`.
Arena → boss gate (via S4): A1 26.9 s, A2 23.1 s, A3 26.1 s, A4 9.7 s, A5 27.3 s, A6 13.9 s. Directed links per band (up/down): L0↔L1 6/6, L1↔L2 23/25, L2↔L3 12/15, L3↔L4 7/9, and every district has an internal way up and down for each band it spans. The only bridge edges lead to rewards or the start pier. Ramp grades range from 8.9° to 18.4° (all ≤ 20°).

---

## 5. Automated connectivity checklist (an agent can run this)

### 5.1 Data contract (Blender → JSON → Godot)
- In Blender, put one Empty per graph node in collection `GRAPH`, named `GN_<id>`, with custom properties `lg_id, lg_district, lg_layer, lg_type (start|arena|hub|path|connector|landmark|reward|boss), lg_arena`. Store edges in a `lg_edges` text block (one `from,to,kind,bidir,tags` per line). The Blender build script writes `level_graph.json` next to each district `.glb`:
```json
{"meta":{"units":"m","up":"Z","H":16,"J":40,"R_min":150,"R_max":250,"v_boost":50,"g":19.6},
 "nodes":[{"id":"K3","name":"Knot Deck","district":"D2","layer":"L2","pos":[-470,-40,32],"type":"arena","arena":"A2"}],
 "edges":[{"from":"K3","to":"K4","kind":"ramp","bidir":true,"tags":[]}]}
```
- Export with the glTF exporter's custom-properties option, so properties become glTF `extras`. Godot imports node extras as `metadata/extras` [S61]. A post-import script turns every non-walk edge into a `NavigationLink3D` (`start_position`, `end_position`, `bidirectional`) plus an `Area3D` trigger and gameplay script. Links only inform pathfinding: "game code needs to react … and provide means for the agent to move through the link" [S55].

### 5.2 Checks and thresholds (CI fails on any red)
| # | Check | Pass condition |
|---|---|---|
| C1 | Schema | unique ids; every edge endpoint exists; kind ∈ palette; on-datum node z within ±2 m of its layer datum unless tagged `offdatum` |
| C2 | Strong connectivity | directed graph has exactly 1 strongly connected component (every one-way edge has a way back) |
| C3 | Start coverage | all nodes reachable from START in ≤ 90 s **(estimate)** |
| C4 | Dead ends | every undirected degree-1 node has type reward/start/boss; dead ends ≤ 15 % of nodes |
| C5 | Loops | cyclomatic number ≥ 3 (target ≥ 10 for 60 nodes); no arena node sits on a bridge edge unless the other end is a reward |
| C6 | Redundancy | removing any one non-arena node never disconnects an arena from the start hub |
| C7 | Layer links | each band (L0↔L1, L1↔L2, L2↔L3, L3↔L4) has ≥ 4 up and ≥ 4 down links map-wide, and every district holding both layers of a band has a way up and a way down using only its own edges; Crown exempt (one gated entry, one exit) |
| C8 | Jump physics | `edgejump` Δz ≤ 0.8 J (32 m); 33–47 m only if tagged `skill` and painted; `stairs` steps ≤ 32 m; `drop` Δz < 0 |
| C9 | Arena entries | ≥ 3 entry edges from ≥ 2 layers (boss: exactly 1 entry, ≥ 1 exit) |
| C10 | Travel time | arena→arena max ≤ 45 s, median ≤ 30 s; arena→boss gate ≤ 30 s; any node→nearest arena ≤ 25 s |
| C11 | Route distinctness | for each arena pair, the two fastest edge-disjoint routes differ in layer mix or are ≥ 150 m apart at mid-route (from Tost [S25]) |
| C12 | Trajectory sweeps (Godot) | each `edgejump/drop/vcat/lcat/vent`: capsule r 4 / h 16 swept along the sampled arc at 0.1 s steps has no hit before landing; landing normal ≤ 40°; landing point on the target navmesh |
| C13 | Headroom/width | over sampled navmesh points, ceiling ray ≥ 24 m everywhere and ≥ 32 m in arenas; navmesh baked with agent_radius 4 stays continuous along every walk edge |
| C14 | Sightlines and cover | per arena, 500 random point pairs at +12 m: ≤ 5 % with clear LOS > 350 m; every sample within 60 m of a full-cover collider ≥ 20 m tall |
| C15 | Landmark visibility | ≥ 80 % of navigable samples on L1–L4 can ray-see ≥ 1 of 3 points on the Spire crown |
| C16 | Boundary | no navigable surface within 30 m of the playable edge without a soft wall; no catapult or vent arc leaves the square; no-fly ceiling at +260 m |
| C17 | Unknown reachability | 1,000 random max-boost jumps from navmesh samples must land on a known district navmesh; any other landing is reported as an "unmapped reachable surface" |

### 5.3 Edge-time model (seconds; v = 50 m/s; g = 19.6 m/s²) **(estimate)**
path/rail/tunnel h/50 · ramp L₃D/40 · edgejump or stairs up 2.0·⌈Δz/32⌉ + h/45 · drop h/45 + √(2|Δz|/g) + 0.3 · lift 3 + Δz/16 + h/50 · vcat 1.5 + Δz/60 + h/80 · lcat 1 + d/120 · vent 1 + Δz/40 + h/45.
Arc sampling for C12: with start S, end E and flight time T (Godot coordinates, gravity vector **g** = (0, −19.6, 0)): v₀ = (E − S − ½**g**T²)/T, p(t) = S + v₀t + ½**g**t². Take T from the edge time minus fixed overheads.

### 5.4 Reference validator (C1 endpoint check, C2, C4–C10; PASS on §4; on a negative test with a 40 m ledge and a removed pagoda link it reported C2, C4, C5, C7 and C8 as expected)
```python
"""lg_validate.py - level-graph checks C1-C10 (reference). Usage: uv run --with networkx python3 lg_validate.py level_graph.json"""
import json, math, sys, statistics, itertools
import networkx as nx

g = json.load(open(sys.argv[1])); M = g["meta"]
FREE, HARD = 0.8 * M["J"], 1.2 * M["J"]                       # 32 m / 48 m for J = 40
N = {n["id"]: n for n in g["nodes"]}
def t_edge(kind, h, dz, v=M["v_boost"], G=M["g"]):
    if kind in ("path", "rail", "tunnel"): return h / v
    if kind == "ramp": return math.hypot(h, dz) / 40
    if kind in ("edgejump", "stairs") and dz > 0: return 2.0 * math.ceil(dz / FREE) + h / 45
    if kind in ("drop", "edgejump", "stairs"): return h / 45 + math.sqrt(2 * abs(dz) / G) + 0.3
    if kind == "lift": return 3 + abs(dz) / 16 + h / v
    if kind == "vcat": return 1.5 + abs(dz) / 60 + h / 80
    if kind == "lcat": return 1 + math.hypot(h, dz) / 120
    if kind == "vent": return 1 + abs(dz) / 40 + h / 45
    raise ValueError(kind)

fail = []; D = nx.DiGraph()
for n in N: D.add_node(n)
for e in g["edges"]:                                            # C1 schema + C8 jump physics
    pairs = [(e["from"], e["to"])] + ([(e["to"], e["from"])] if e["bidir"] else [])
    for a, b in pairs:
        if a not in N or b not in N: fail.append(f"C1 unknown node {a}->{b}"); continue
        (xa, ya, za), (xb, yb, zb) = N[a]["pos"], N[b]["pos"]; h, dz = math.hypot(xb - xa, yb - ya), zb - za
        k = e["kind"]
        if k == "edgejump" and dz > FREE:                       # 33-47 m only as a tagged, painted skill lip
            if not (dz < HARD and "skill" in e.get("tags", [])): fail.append(f"C8 {a}->{b} jump dz {dz} > {FREE}")
        if k == "drop" and dz >= 0: fail.append(f"C8 {a}->{b} drop not downward")
        D.add_edge(a, b, t=t_edge(k, h, dz))
start = next(n for n in N if N[n]["type"] == "start")
if nx.number_strongly_connected_components(D) != 1: fail.append("C2 not strongly connected")   # C2
U = nx.Graph(D.to_undirected())
dead = [n for n in U if U.degree(n) == 1]                                                      # C4
fail += [f"C4 unrewarded dead end {n}" for n in dead if N[n]["type"] not in ("reward", "start", "boss")]
if len(dead) > 0.15 * len(N): fail.append("C4 too many dead ends")
cyc = U.number_of_edges() - U.number_of_nodes() + nx.number_connected_components(U)            # C5
if cyc < 3: fail.append(f"C5 only {cyc} loops")
arena = {}
for n, v in N.items():
    if v.get("arena"): arena.setdefault(v["arena"], set()).add(n)
for a, b in nx.bridges(U):
    for x, y in ((a, b), (b, a)):
        if N[x].get("arena") not in (None, "BOSS") and N[y]["type"] not in ("reward", "start"): fail.append(f"C5 arena {x} on bridge {a}-{b}")
G0 = U.copy(); G0.remove_node(start); root = next(iter(U[start]))                              # C6
for ap in nx.articulation_points(G0):
    G2 = G0.copy(); G2.remove_node(ap)
    for aid, mem in arena.items():
        if aid != "BOSS" and ap not in mem and ap != root and not any(nx.has_path(G2, root, m) for m in mem):
            fail.append(f"C6 removing {ap} isolates {aid}")
z = lambda n: N[n]["pos"][2]
for lo, hi in ((-40, 0), (0, 32), (32, 80), (80, 128)):                                         # C7
    up = sum(1 for a, b in D.edges if z(a) <= lo + 16 and z(b) >= hi - 16 and z(b) > z(a))
    dn = sum(1 for a, b in D.edges if z(b) <= lo + 16 and z(a) >= hi - 16 and z(b) < z(a))
    if up < 4 or dn < 4: fail.append(f"C7 band {lo}->{hi}: up {up} down {dn}")
    for d in sorted({v["district"] for v in N.values()}):        # inside each district: a way up and a way down
        mem = [n for n in N if N[n]["district"] == d]; sub = D.subgraph(mem)
        lows, highs = [n for n in mem if z(n) <= lo + 16], [n for n in mem if z(n) >= hi - 16]
        if not lows or not highs or {*lows} == {*highs}: continue
        if not any(z(b) > z(a) and nx.has_path(sub, a, b) for a in lows for b in highs) or \
           not any(z(b) > z(a) and nx.has_path(sub, b, a) for a in lows for b in highs):
            fail.append(f"C7 district {d} band {lo}->{hi} lacks a way up or down")
for aid, mem in arena.items():                                                                 # C9
    ins = [(a, b) for a, b in D.edges if b in mem and a not in mem]
    if aid != "BOSS" and (len(ins) < 3 or len({N[a]['layer'] for a, _ in ins}) < 2): fail.append(f"C9 {aid} entries")
dist = dict(nx.all_pairs_dijkstra_path_length(D, weight="t"))                                  # C10
ct = lambda A, B: min(dist[a].get(b, math.inf) for a in arena[A] for b in arena[B])
ids = [k for k in arena if k != "BOSS"]; tt = [ct(A, B) for A, B in itertools.permutations(ids, 2)]
near = max(min(min(dist[n].get(m, math.inf) for m in arena[k]) for k in ids) for n in N if N[n]["type"] != "boss")
if max(tt) > 45 or statistics.median(tt) > 30: fail.append(f"C10 arena travel max {max(tt):.1f}s median {statistics.median(tt):.1f}s")
if max(ct(A, "BOSS") for A in ids) > 30: fail.append("C10 boss gate too far")
if near > 25: fail.append(f"C10 node->arena {near:.1f}s")
print(f"nodes {len(N)} edges {D.number_of_edges()} loops {cyc} dead_ends {len(dead)} "
      f"arena_max {max(tt):.1f}s median {statistics.median(tt):.1f}s node->arena {near:.1f}s")
print("PASS" if not fail else "FAIL\n" + "\n".join(fail)); sys.exit(1 if fail else 0)
```

### 5.5 Godot trajectory and headroom probe (C12/C13 core; Y-up; run headless in Godot 4.7.2: a clear arc returns `ok`, an arc through a wall returns `blocked_at`)
```gdscript
extends Node3D
const H := 16.0
const R := 4.0
var capsule := CapsuleShape3D.new()

func _ready() -> void:
	capsule.radius = R
	capsule.height = H

# points: feet positions sampled every 0.1 s along the arc (last point = landing)
func sweep_arc(points: PackedVector3Array) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = capsule
	q.collision_mask = 1                                  # world geometry layer
	for i in range(points.size() - 2):
		q.transform = Transform3D(Basis(), points[i] + Vector3.UP * (H * 0.5))
		q.motion = points[i + 1] - points[i]
		var frac := space.cast_motion(q)                 # [safe, unsafe]; 1.0 = unobstructed
		if frac[0] < 1.0:
			return {"ok": false, "blocked_at": points[i]}
	var land := points[points.size() - 1]
	var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(land + Vector3.UP * 2.0, land + Vector3.DOWN * 6.0))
	if down.is_empty() or (down["normal"] as Vector3).angle_to(Vector3.UP) > deg_to_rad(40.0):
		return {"ok": false, "bad_landing": land}
	var up := space.intersect_ray(PhysicsRayQueryParameters3D.create(land + Vector3.UP * 0.5, land + Vector3.UP * 24.0))
	if not up.is_empty():
		return {"ok": false, "low_ceiling": land}
	return {"ok": true}
```

---

## 6. Godot 4.7 / Blender 5.2 implementation notes
- **Import suffixes** [S54]: put `-colonly` on simplified collision proxies for buildings and decks (StaticBody3D without the render mesh), `-convcolonly` on props, `-occonly` on occluder proxies (big facades, deck slabs), `-noimp` on helpers. Collision primitives beat trimesh for performance and reliability.
- **Navigation** [S56]: one `NavigationRegion3D` per district. Bake with `agent_radius 4.0, agent_height 16.0, agent_max_climb 2.0, agent_max_slope 40°, cell_size 1.0, cell_height 0.5` **(estimate)**, and keep the navigation map cell size equal to the mesh cell size. Use the baking bound with `border_size` for chunk seams. The docs warn that too small a `cell_size`/`cell_height` "can create so many voxels" that baking freezes or crashes. Add one `NavigationLink3D` per non-walk edge [S55].
- **Character**: `CharacterBody3D.floor_max_angle` defaults to 0.785 rad (45°) and `floor_snap_length` to 0.1 [S60]. Set 40° and roughly 2 m snap for a 16 m body **(estimate)**.
- **Rendering at city scale**: enable *Rendering → Occlusion Culling → Use Occlusion Culling*. Occluders are rasterised on the CPU, and larger occluders such as walls work much better than props [S57]. Use visibility ranges (HLOD) to swap block clusters into merged meshes at distance [S58]. Keep the map centred on the origin: ±700 m is far below the 4096–8192 m single-precision guidance for third-person games [S59].
- **Metrics zoo first**: build a 400 × 400 m test map with every metric from §3.2 (ledges at 24/32/40/48 m, gaps 80/100/150/220/260 m, alley/street/avenue widths, 24/32 m ceilings, cover heights) on a world-aligned grid material, plus a jump-arc preview gizmo like Psychonauts 2's [S40].

---

## 7. Risks
1. **Mobility outgrows geometry.** Hover plus a 250 m air range plus catapults can bypass arenas; Neomuna's grapple let players "grapple over mountains" [S27]. Mitigate with the no-fly ceiling, ambiguity-band discipline, C17 random-jump probes, and arena exits through gates or waves rather than walls.
2. **An over-permeable city loses tension.** If every edge is ≤ 32 m, layers stop mattering. Keep hard steps (≥ 48 m) between L2/L3/L4 and make high ground rare and contested, as McCord did with Titan high ground [S10].
3. **Climbing tedium and blank facades.** Mirror's Edge cut a tall-tower district because climbing it meant "too much time just looking into building façades" [S21]. Cap any single vertical ascent at about 8 s and give long climbs a view.
4. **3D disorientation.** Lynch's "?" junctions (image 19) multiply with layers. Mitigate with layer lighting identity, a minimap layer indicator, landmark visibility (C15), and 2–3 colour codes only.
5. **Performance on M1 Max (Forward+, Metal).** A dense 1.4 km city with stacked decks means high overdraw and many draw calls. Plan occluders, HLOD and per-district streaming from day one (§6) **(estimate)**.
6. **AI across layers.** Navigation links need custom traversal code [S55]; a 4 m agent radius erases narrow paths; small cells explode bake time [S56]. Big enemies should use region-limited navmeshes, flyers should use a 3D waypoint graph built from this node graph **(estimate)**.
7. **Camera clipping** in 24 m squeeze tunnels and under decks. Mitigate with a SpringArm3D margin and auto-zoom, and treat 24 m as an absolute minimum.
8. **Metrics drift.** If movement tuning changes J or R, the formulas in §3.3 regenerate thresholds; re-run §5 in CI on every tuning commit (Crysis 2 warning [S19]).
9. **Scale of generated enemies.** Tripo outputs arrive at arbitrary scale; enforce size classes (2–6 m, 10–20 m, 40–60 m) at import, or spawn sockets and cover heights stop working **(estimate)**.
10. **Source quality.** AC6 lock ranges and AC heights are community measurements [S8][S9]; the DOOM points come from a summary of the GDC talk [S32]; Hengsha and the Titanfall MP lane reading are secondary analyses [S14][S26]. Treat them as directional evidence.

---

## 8. Sources
- [S1] 4Gamer, AC6 interview (Yamamura/Ogura), 2023 — https://www.4gamer.net/games/674/G067420/20230726056/
- [S2] Famitsu, AC6 interview, 2023 — https://www.famitsu.com/news/202304/27300778.html
- [S3] PlayStation Blog JP, AC6 interview, 2023 — https://blog.ja.playstation.com/2023/08/22/20230822-acvi/
- [S4] PC Gamer, AC6 tips (FCS assist ranges) — https://www.pcgamer.com/armored-core-6-guide-tips-beginners/
- [S5] IGN wiki, AC6 "Infiltrate Grid 086" — https://www.ign.com/wikis/armored-core-6-fires-of-rubicon/Infiltrate_Grid_086
- [S6] IGN wiki, AC6 "Attack the Old Spaceport" — https://www.ign.com/wikis/armored-core-6-fires-of-rubicon/Attack_the_Old_Spaceport
- [S7] Armored Core Wiki, "Infiltrate Grid 086" (vertical catapult) — https://armoredcore.fandom.com/wiki/Infiltrate_Grid_086
- [S8] AC size estimates — https://armoredcore.fandom.com/wiki/Armored_Core_(mecha) ; https://www.reddit.com/r/armoredcore/comments/149w19f/estimated_height_for_ac6_mechs/
- [S9] Steam community lock-on tests (AC6) — https://steamcommunity.com/app/1888160/discussions/0/3820795505279006929/
- [S10] Jason McCord (Respawn level designer), Titanfall map breakdowns — https://www.monster-clip.com/titanfall.html
- [S11] IGN "Art of the Level", Into the Abyss (David Shaver) — https://www.ign.com/articles/how-titanfall-2-made-movement-the-star-of-the-show-art-of-the-level
- [S12] GDC Vault, "Designing Unforgettable Titanfall Single Player Levels with Action Blocks" — https://www.gdcvault.com/play/1025105/Designing-Unforgettable-Titanfall-Single-Player
- [S13] Vice, "Effect and Cause" behind the scenes (Jake Keating) — https://www.vice.com/en/article/a-behind-the-scenes-look-at-the-best-mission-in-titanfall-2/
- [S14] W. Wells, "How Titanfall 2's Multiplayer Level Design Gets You Moving" — https://www.linkedin.com/pulse/how-titanfall-2s-multiplayer-level-design-gets-you-moving-wells
- [S15] Titanfall 2 Wiki, Titans (~20 ft) — https://titanfall2.fandom.com/wiki/Titans
- [S16] Halopedia, Valhalla (layout, man cannons, production notes) — https://www.halopedia.org/Valhalla
- [S17] Bungie HEK tutorial, Halo player statistics — http://nikon.bungie.org/misc/hek_tutorial/references/general/halo_player_stats.html
- [S18] Adrian Bedoya, Halo 5 Warzone maps — https://www.adrianbedoya.com/halo-5-guardians
- [S19] Siliconera, Crysis 2 interview (Nathan Camarillo), 2011 — https://www.siliconera.com/how-crysis-2s-nanosuit-makes-you-feel-like-a-superhero/
- [S20] Polygon, Crysis 3 interview (Rasmus Hoejengaard), 2013 — https://www.polygon.com/features/2013/1/24/3754708/crysis-3-interview-posthuman-interest/
- [S21] K. Dimopoulos, "Designing The City of Glass" (Erik Odeldahl interview; Wireframe #62) — https://medium.com/@KonstantinosD/designing-the-city-of-glass-4ee2584835c7
- [S22] K. Majmudar, "Making combat spaces for SpidermanPS4" (incl. Shane McCloskey) — https://medium.com/@ketul1776/making-combat-spaces-for-spidermanps4-a72abf051792
- [S23] Mashable, Insomniac on NYC (Jacinda Chew) — https://mashable.com/article/marvel-spider-man-game-new-york-city-interview-art-director
- [S24] Reddit, in-game Manhattan width measurement — https://www.reddit.com/r/PS4/comments/brrk8j/spider_man_ps4_how_accurate_is_nyc_inside_the/
- [S25] IGN, Miles Tost GDC 2023 non-linear level design — https://www.ign.com/articles/cyberpunk-2077-level-design-gdc-2023
- [S26] Parametric Architecture, cities of Deus Ex (Hengsha) — https://parametric-architecture.com/a-journey-through-the-cyber-renaissance-cities-of-deus-ex-prague-hengsha-detroit/
- [S27] PC Gamer, Lightfall interview (Blackburn/McAuliffe) — https://www.pcgamer.com/bungies-joe-blackburn-talks-lightfall-strand-and-the-huge-systemic-changes-coming-to-destiny-2/
- [S28] Reddit, Neomuna buildings not explorable — https://www.reddit.com/r/DestinyTheGame/comments/11rthaa/i_like_neomuna_but_seeing_all_those_buildings_and/
- [S29] IGN, inFAMOUS Second Son Seattle (Horia Dociu) — https://www.ign.com/articles/2013/11/08/infamous-how-seattle-is-second-sons-seattle
- [S30] inFAMOUS Wiki, Vent Dash — https://infamous.fandom.com/wiki/Vent_Dash
- [S31] GamingBolt, Just Cause 3 interview (Roland Lesterlin) — https://gamingbolt.com/just-cause-3-interview-welcome-to-destruction-again
- [S32] "Embracing Push Forward Combat in DOOM", GDC 2018 (summary of the talk video) — https://videohighlight.com/v/2KQNpQD8Ayo ; listing https://gdcvault.com/browse/gdc-18/?categories=De
- [S33] Doom Eternal (Wikipedia: swing bars, portals, jump pads) — https://en.wikipedia.org/wiki/Doom_Eternal
- [S34] GAME Watch, GUNDAM EVOLUTION developer interview, 2021 — https://game.watch.impress.co.jp/docs/interview/1321966.html
- [S35] IGN Japan, CEDEC 2017 BotW field level design — https://jp.ign.com/cedec-2017/16928/botw
- [S36] Game Developer, "5 design lessons learned from BotW" — https://www.gamedeveloper.com/design/5-design-lessons-learned-from-i-the-legend-of-zelda-breath-of-the-wild-i-
- [S37] K. Lynch, *The Image of the City* (1960), pp. 47–48 — https://cus.ubt-uni.net/wp-content/uploads/2024/11/Kevin-Lynch-The-Image-of-the-City.pdf
- [S38] Bostonography, "Kevin Lynch & The Imageable Boston" — https://bostonography.com/2010/kevin-lynch-the-imageable-boston/
- [S39] M. Sklar, "Mickey's Ten Commandments" (weenie) — https://byrnesmedia.com/2016/02/28/mickeys-10-commandments/
- [S40] The Level Design Book, Metrics — https://book.leveldesignbook.com/process/blockout/metrics
- [S41] The Level Design Book, Typology — https://book.leveldesignbook.com/process/layout/typology
- [S42] The Level Design Book, Encounter — https://book.leveldesignbook.com/process/combat/encounter
- [S43] The Level Design Book, Wayfinding — https://book.leveldesignbook.com/process/blockout/wayfinding
- [S44] People's Daily / China News, Liziba station (Ye Tianyi), 2018 — http://travel.people.com.cn/n1/2018/0525/c41570-30013124.html
- [S45] Huangjuewan interchange — https://zh.wikipedia.org/zh-hans/%E9%BB%84%E6%A1%B7%E6%B9%BE%E7%AB%8B%E4%BA%A4 ; https://en.wikipedia.org/wiki/Huangjuewan_interchange ; http://paper.people.com.cn/rmrbhwb/html/2017-06/07/content_1780460.htm
- [S46] Raffles City Chongqing "Crystal" — https://baike.baidu.com/item/%E9%87%8D%E5%BA%86%E6%9D%A5%E7%A6%8F%E5%A3%AB%E6%B0%B4%E6%99%B6%E8%BF%9E%E5%BB%8A/50356849 ; https://3bur.cscec.com/xwzx11/gskx11/201712/2863130.html
- [S47] Kuixinglou (1st floor = 22nd floor) — https://www.unseenchina.com/zh-cn/attraction/kuixing-building
- [S48] Hongyadong (11 floors; Cangbai Rd at 11F) — https://epaper.cqrb.cn/kjb/2021-06/24/12/content_kj_275344.htm ; https://passagechina.com/zh-Hans/destinations/chongqing/attractions/hongya-cave
- [S49] Central–Mid-Levels escalator — https://en.wikipedia.org/wiki/Central%E2%80%93Mid-Levels_escalator ; https://www.landmark.hk/en/visit/around-central/central-mid-level-escalator
- [S50] Kowloon Walled City — https://en.wikipedia.org/wiki/Kowloon_Walled_City ; https://www.atlasobscura.com/articles/kowloon-walled-city
- [S51] CTBUH Tall Building Height Calculator assumptions — https://www.academia.edu/9675624/CTBUH_Tall_Building_Height_Calculator
- [S52] Froude number (walking limit Fr = 1) — https://en.wikipedia.org/wiki/Froude_number
- [S53] MAHQ, RX-78-2 (head height 18.0 m) — https://www.mahq.net/rx-78-2/
- [S54] Godot docs, node type customization (import suffixes) — https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/node_type_customization.html
- [S55] Godot docs, Using NavigationLinks — https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_using_navigationlinks.html
- [S56] Godot docs, Using navigation meshes — https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_using_navigationmeshes.html
- [S57] Godot docs, Occlusion culling — https://docs.godotengine.org/en/stable/tutorials/3d/occlusion_culling.html
- [S58] Godot docs, Visibility ranges (HLOD) — https://docs.godotengine.org/en/stable/tutorials/3d/visibility_ranges.html
- [S59] Godot docs, Large world coordinates — https://docs.godotengine.org/en/stable/tutorials/physics/large_world_coordinates.html
- [S60] Godot docs, CharacterBody3D — https://docs.godotengine.org/en/stable/classes/class_characterbody3d.html
- [S61] glTF extras → Godot metadata — https://forum.godotengine.org/t/gltf-import-how-does-one-get-metadata-extras/105711 ; https://docs.godotengine.org/en/latest/tutorials/assets_pipeline/importing_3d_scenes/import_configuration.html
