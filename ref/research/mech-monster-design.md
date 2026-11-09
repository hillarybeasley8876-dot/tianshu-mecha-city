# Mech + Monster Design, and the Tripo3D → Blender → Godot Pipeline

key: `mech-monster-design` · for: Lead (Claude Opus) · implementers: MiniMax-M78 (units `hero-asset`, `monster-assets`, `enemies`) · Godot 4.7.2 Forward+ · Blender 5.2.1 LTS · date: 2026-11-01
Images: `ref/images/mech-monster-design/`. 01–12 are mech references and 13–24 are monster references; see `sources.md` and `_sheet.jpg`.

**Conventions.**
- `[TAG]` → URL in §8.
- "(estimate)" = my own design number. "(calc)" = computed with the formula shown.
- "(observed)" = seen in the lead's Tripo Studio session on 2026-11-01 (`.lead/ws.jpg`, `retopo.jpg`, `rig.jpg`, `detail.json`) [LEAD-TRIPO] or in my scratch tests [INHOUSE-RIG].
- "img NN" = file NN in the image folder.
- Distances are in m. Times are in s; f = frame at 60 fps.
- All sizes follow SPEC §2/§7: hero 16 m to the crest, cockpit eye ≈ 12 m.

---

## 0. TL;DR

1. **What makes a mech look 帅 (in numbers):**
   - small head (7.8 heads);
   - hip at 53 % of height, shoulders 0.50 H wide, waist 0.21 H, feet 0.20 H long;
   - one unforgettable head feature and one unforgettable back feature;
   - inner frame visible at every joint, plus military markings;
   - value runs dark at the feet to highest contrast at the chest (Valve read hierarchy).
2. **Hero = 天枢 TIANSHU, unit YQ-X1.** Gundam spirit, no copied features. Four signatures:
   - a **pointer crest**: one forward-raked blade and two swept antennae, no V-fin;
   - **seven cyan "Big Dipper" chest lights**, which double as the overdrive meter;
   - a **corona-ring backpack** holding the six radial Corona Fins;
   - a **kite shield whose tip is the Skyhook anchor**.
3. **Palette.**
   - Paint: pearl `#E8EBEE`, midnight cobalt `#1E3F9E`, solar gold `#D9A23A`, vermilion markings `#E5482D`.
   - Frame: gunmetal `#3B4049`.
   - Hero glow: cyan `#4FE3FF`. Overdrive glow: white-gold `#FFE6A3`.
   - The hero never emits acid green, violet, red or flash-white. Those colours belong to enemies and telegraphs.
4. **Rig the hero with rigid segments, implemented as rigid skinning.**
   - Every vertex of a part is weighted 1.0 to one bone.
   - Parts are joined into one skinned mesh per material group.
   - Verified Blender 5.2.1 → GLB → Godot 4.7.2: one `Skeleton3D` (30 bones), two skinned `MeshInstance3D`, zero `BoneAttachment3D`, action imported [INHOUSE-RIG].
   - Do **not** parent objects to bones. Godot then builds a `BoneAttachment3D` per part, and there are open import bugs [GD-91132][GD-69601].
5. **Build the hero part by part**, each part from four views, fitted onto a grey-box skeleton that is built first (§5.3).
   - Model the hands, crest, antennae and fin edges in Blender.
   - Fused fingers and melted thin parts are Tripo's most common failures [TRIPO-TOPO][PRIOR-JOB].
6. **Husk faction language:**
   - dark chitin `#1B1E24`;
   - acid-green seams `#9BFF3A` along a shared dorsal keel;
   - three-slit eyes;
   - bone-white "this hurts" attack parts;
   - scavenged city steel as breakable armour;
   - round, ringed violet weak points `#B04CFF`, always paired with a HUD shape for colour-blind players [GAG-COLOUR].
7. **Roster** = SPEC §7, with one silhouette rule per type and the SPEC telegraph timings. Add a cheap **Ripper Alpha** elite on the same rig. Optional: **Mites** for swarm density.
8. **Tripo state (Nov 2026)** [ALI-GEN][ALI-RETOPO][SCN-TRIPO][TRIPO-P2][ALI-RIG][ALI-RETARGET]:
   - HD model `v3.1-20260211`.
   - Input: JPEG/PNG ≤ 6,000 px. Multiview takes 2–4 images in the fixed order front/left/back/right.
   - Retopo v3: 500–20,000 tris, with Smart UV and bake.
   - P2.0: native quads, ≤ 50k tris.
   - Auto-rig: 7 rig types. **Non-humanoid preset animations are walk-only**, so monster combat motion is keyed in Blender plus procedural in Godot.
9. **Procedural creature motion in Godot 4.6+** [GD-IK46]:
   - `TwoBoneIK3D` feet;
   - `SpringBoneSimulator3D` tails, antennae and fins;
   - `LookAtModifier3D` heads and aim;
   - `LimitAngularVelocityModifier3D` to smooth.
   - Key only attacks, hits, staggers and deaths.
10. **Budgets** (estimate):
    - hero ≈ 55k tris body + ≈ 23k weapons, ≤ 9 surfaces, one 4K armour set;
    - Ripper 6–8k tris / 1K texture; Mantis 18–22k / 2K; Juggernaut 30–40k / 4K;
    - Brood Titan 120–160k, with a 10k skyline LOD.
    - Skinned LODs are second meshes switched by visibility ranges.
11. **On-screen size at 1600×900, 70° vertical FOV** (calc):
    - hero at 26 m = **395 px** tall;
    - Spitter at 300 m = **26 px**;
    - Brood Titan at 1 km = **58 px**.
    - So weak points need glow plus a HUD marker, and the boss's emissive layer uses `render_mode fog_disabled` [GD-SPATIAL].
12. **QA every generated asset with:**
    - a numeric mesh audit;
    - lit close-ups of hands and thin parts;
    - a top-view limb check;
    - a UV-atlas view;
    - a black-silhouette test at 26 m and 150 m.

---

## 1. (A) The design language of a 帅 hero mech

### 1.1 What the references teach

| Source | What they did | Rule we take | Ref |
|---|---|---|---|
| Okawara, RX-78 | "Basically a samurai": a topknot, a face, and a *maedate* in the form of a V-fin. At 18 m "the face and a mouth was a little bit strange, so we put a mask over the mouth." | Start the head from a historical armour idea, then abstract it. Ours is an astronomer's pointer/armillary, not a kabuto. | [FORBES-OK], img 01 |
| Gundam conventions (official) | The "horn" plus the face is *the* symbol. The hero is white-based tricolour (white with red, blue, yellow). Rivals use dark tones. | One instantly recognisable head feature. A light hero against dark enemies. | [GOF-FACE] |
| RX-78 colours in fiction | Painted loud "because it is a prototype, for demonstrations". | YQ-X1 is a prototype demonstrator. That justifies the bright paint in fiction. | [JAWIKI-GUNDAM] |
| Katoki | An "industrial product" look made by inserting public signs (markings) to lower the sense of fiction. The **Katoki stance**: feet a little wider than the shoulders, toes turned out, elbows slightly bent, fists clenched, shoulders slightly raised, chest out, viewed slightly off-axis, eyes to camera. He made it to show ankle volume and ground contact. | Markings = realism. Our idle pose and key-art pose are Katoki stance. | [JAWIKI-KATOKI], img 02 |
| Ver.Ka (first kit: MG RX-78-2 Ver.Ka, 2002) | Proportions are "sharper, more detailed, and more mechanically plausible". Decals: "warning labels, maintenance markings, unit numbers, caution stripes… like real aircraft." | The decal vocabulary in §1.6. | [LASCA-VERKA], img 05 |
| Inner frame (PG Unleashed, Full Mechanics Barbatos) | Armour is a set of shells on a detailed frame. Pistons and tubing are picked out in gold or silver. | Expose the frame at the elbows, knees, ankles, waist and neck. Pistons are titanium. | [GP101-BARB], img 03, 04 |
| Kawamori (Armored Core, 1997) | "If the designs can't be distinguished from their silhouettes alone, it's no good." The idle pose looked stiff, so he asked for looseness and "more swing in their hips". | Black-silhouette test. Add 1–2° of hip sway to the idle. | [SHMUP-AC] |
| Kawamori (Macross) | Enemy designs differ "so that one can clearly distinguish foes and allies" (search snippet). | Hero = hard planar shapes. Husk = curved organic shapes with angular claws. | [FF-KAWAMORI] |
| Armored Core VI | Modular head, core, arms and legs. Leg classes: biped, reverse joint, tetrapod, tank. | Leg class as an enemy silhouette tool: Mantis is reverse-joint, Spitter is tetrapod. | [AC6-LEGS], img 10 |
| Titanfall (Joel Emslie) | A grounded look from kitbashed real parts, "an automatic grounding effect". Titans should control "like a natural extension of the player's body". Designs were changed so animators could move them. About 1,000 designs from an art team of under 20. | Use industrial cues: hydraulics, hatches, handles. Leave joint clearances before detailing. | [CGC-EMSLIE], img 11 |
| Pacific Rim jaegers | Gipsy Danger = Art-Deco skyscrapers plus John Wayne's gunslinger gait and hips. Cherno Alpha = T-series tank plus cooling tower. Crimson Typhoon = lacquered wood with gold edges. Striker Eureka = Land Rover with a jutting chest. | Give the hero **one metaphor plus one gait**. Ours: an observatory instrument (rings, pointers, star lights) plus the stillness-then-burst of iaidō. | [WIKI-PR], img 12 |
| Code Geass | The Landspinner is powered wheels on each heel. The Slash Harken is a rocket-launched wire spike. | Heel skates for the boost slide. A shield-tip anchor for Skyhook. | [GEASS-LS][GEASS-SH], img 09 |
| Aldnoah.Zero | Mech design by Kenji Teraoka (and I-IV). Martian Kataphrakts each have one unique, overpowered characteristic. | Elites and the boss get **one** power that you can read in the silhouette. | [WIKI-AZ][AZ-KATA] |
| Xenoblade X Skells | Designed by Takayuki Yanase (also a mech designer on several Armored Core games, per a fan-wiki snippet). Skells are used for traversal as well as combat. | Put thrusters where the motion comes from: sole, calf, back. | [XENO-YANASE][XB-FANDOM][XENO-SKELL] |
| Valve, TF2 read hierarchy | Team by colour, then class by silhouette, proportions and weapon. "Highest contrast at chest level, where weapon is held." "Gradient from dark feet to light chest." Rim highlights, and interior shapes that echo the silhouette. | The value plan in §1.4. Weak points are the brightest thing on an enemy. | [TF2-GDC08][TF2-NPAR07] |

### 1.2 Proportions: the hero sheet (16.0 m to the crest tip)

A practitioner rule [NOTE-PROP]:
- a typical MS is about **7 heads**; heroic is **7.5–8**; mass-produced is **6.5**;
- lengthen legs by raising the hip and the thigh, not by stretching the shin;
- shorten the chest-bottom-to-hip span;
- widen the shoulders relative to the head;
- back volume and ankle angle change the whole stance.

The grey-box rig in §5.2–5.3 uses exactly these joint heights.

| Landmark | Z (m) | % of 15.2 m | Note |
|---|---|---|---|
| Crest tip | 16.0 | 105 | crest is 0.8 m above the head |
| Head top | 15.2 | 100 | head is 1.95 m → **7.8 heads** |
| Chin / neck top | 13.25 | 87 | |
| Shoulder pivot | 12.0 | 79 | cockpit eye ≈ 12 m (SPEC), upper chest |
| Chest bottom | 9.6 | 63 | short abdomen, 0.7 m |
| Waist | 8.9 | 59 | waist width 3.2 m (0.21 H) |
| Hip pivot | 8.0 | **53** | legs are more than half the height |
| Knee | 4.6 | 30 | thigh 3.4 m, shin 3.6 m (shin ≥ thigh) |
| Ankle | 1.0 | 7 | |

Widths and lengths (estimate, inside [NOTE-PROP] ranges):
- Shoulder armour, outer: 7.6 m (0.50 H). Chest 5.2 m. Hips 3.6 m.
- Shoulder-to-waist ratio 2.4. Head width / shoulder width 0.20.
- Foot 3.0 × 1.6 m (0.20 H). Fist 0.9 m wide.
- Upper arm 3.0 m, forearm 2.6 m, hand 1.3 m. Fingertips at 5.1 m (mid-thigh).
- Backpack ring Ø 4.2 m, centred at 11.3 m, 1.8 m behind the chest. Six fins of 6.5 m each (0.41 H).

**Katoki idle** (estimate, after [JAWIKI-KATOKI]):
- feet centres 6.0–6.8 m apart, legs splayed 12–15°, toes out 15–20°;
- elbows bent 15–20°, fists closed;
- chest pitched up 3°, head pitched down 5° toward the camera;
- shoulders raised 2°;
- hip sway ±1.5° at 0.25 Hz [SHMUP-AC].

Key-art camera: 15–25° off-axis, eye at hip height. Low-angle *aori* makes 18 m feel huge (img 01).

**Joint limits** (estimate). Armour must clear these; the frame fills the gaps.

| Joint | Range |
|---|---|
| Neck | yaw ±70°, pitch −30/+40° |
| Waist | yaw ±45°, pitch ±20° |
| Shoulder | abduction 0–110°, flexion −40/+160° |
| Elbow | 0–145° (double-jointed frame) |
| Wrist | ±60° |
| Hip | flexion −30/+110°, abduction 0–60° |
| Knee | 0–150° (double-jointed) |
| Ankle | pitch ±35°, roll ±20° |
| Toe | 0–30° |

### 1.3 Silhouette toolkit: ours vs. too close to an existing design

| Feature | Do (ours) | Don't (too close) |
|---|---|---|
| Head crest | **Pointer crest**: one gold blade raked 20° forward from the forehead, plus two antennae swept back 35°. Reads as an upward arrowhead. | V-fin with a red forehead camera (RX-78). A horn that splits into a V (Unicorn). |
| Face | Narrow cyan visor band with two sharper eye-nodes inside. Faceplate with three vertical vents. Cheek guards form an inverted W. | The full combination of dual eyes, red chin and mouth slits. |
| Shoulders | Large, raised 2°. The hinged top plates hide the Hailstorm pods. | RX-78's flat boxes. |
| Chest | Cobalt block with a gold-framed seven-star light pattern. Side intake grilles. | Yellow chest vents plus a red waist block (RX-78 colour blocking). |
| Waist | V-buckle, two front skirts, side skirts (Undertow racks) and a rear skirt (rifle mount). Skirts follow the thighs. | — |
| Backpack | **Corona ring** Ø 4.2 m with six radial fins and two main nozzles. Fins fold in an X when idle and fan to 220° for the burst pose. | Hi-Nu's one-sided fin rack (img 07). Freedom's wing binders (img 08). Wing Zero's feathered wings. |
| Legs and feet | Long shins with calf thruster vents. Knee caps with a short spike. Ankle skirt. Heel-skate housing. Wedge toe, heel spur, sole thrusters. | — |

**Silhouette tests:**
- Fill the hero black at 400 px tall, the 3rd-person size from §1.5. The crest, ring and shield must still read.
- Repeat at 60 px. Crest and ring must still read.
- Repeat with the fins spread.

### 1.4 Colour, value and materials

| Role | Hex | Share of area | Godot material (estimate) |
|---|---|---|---|
| Pearl armour | `#E8EBEE` | ≈ 50 % | metallic 0, roughness 0.38, clearcoat 0.35 (clearcoat roughness 0.2) |
| Midnight cobalt | `#1E3F9E` | ≈ 20 % | as pearl, roughness 0.42 |
| Solar-gold trim (crest, star frame, fin spines) | `#D9A23A` | ≈ 4 % | metallic 0.9, roughness 0.3 |
| Vermilion markings / caution stripes | `#E5482D` | ≤ 2 % | decal atlas only |
| Frame gunmetal | `#3B4049` | ≈ 18 % | metallic 0.8, roughness 0.5 |
| Frame recess | `#23272E` | — | AO-darkened |
| Pistons (titanium) | `#9AA3AD` | ≈ 2 % | metallic 1.0, roughness 0.28 |
| Soft covers / carbon (elbow and knee covers, waist bellows) | `#15171B` | ≈ 2 % | roughness 0.7 |
| Visor glass | `#0B1A24` | < 1 % | roughness 0.05, glow behind |
| Glow, normal | `#4FE3FF` | < 2 % | emission energy: sensors 4, vents 2, fin edges 3 |
| Glow, overdrive | `#FFE6A3` | — | 0.4 s ramp to energy 8–12; frame seams lit (img 06 logic) |

**Value plan** (after the TF2 read hierarchy [TF2-GDC08]):
- Darkest: feet, shins and forearms, which carry the cobalt and the frame.
- Mid: pelvis.
- Highest contrast: chest (cobalt against pearl, gold and cyan stars).
- Head: pearl with the gold crest.

**Reserved colours** (SPEC / enemies brief). Never use these for the hero's emission:
- acid green `#9BFF3A` (Husk glow);
- violet `#B04CFF` (weak points);
- red (unblockable telegraph);
- flash-white (parry glint).

Check the hero glow against `docs/ART.md` once it exists. If the city's neon is mostly cyan, move the hero glow to ice-white `#DDF8FF` and keep cyan only on the visor.

**Implementation** (estimate unless cited):
- **Exact hexes, whatever Tripo paints.**
  - Quantise each part's baked Tripo albedo into palette IDs (k-means, k = 6–8; numpy in Blender).
  - Write an ID mask (or per-part vertex colours, which is trivial with rigid parts).
  - `hero_armor.gdshader` maps each ID to a palette uniform and multiplies by baked AO/cavity.
  - Normal and ORM maps come from the Tripo high→low bake.
  - This also gives cheap alternate liveries.
- **Markings.**
  - Use a 2K alpha decal atlas on UV2, through the StandardMaterial3D *Detail* layer (mask, Mix blend, UV2) [GD-STDMAT] or the same maths in the custom shader.
  - Don't use `Decal` nodes on the moving mech. They project world-space boxes that also hit neighbouring parts.
- **Edge wear.** Bake a curvature mask in Blender (Cycles bevel/pointiness → bake). Apply `wear = step(0.65, curvature × noise)`, which reveals titanium `#9AA3AD`. Keep it to ≤ 8 % of pearl edges.
- **Rim.** Godot's built-in Rim is light-dependent: no light means no rim [GD-STDMAT]. For enemies that must read in shadow, use a fresnel emissive rim in the shader instead.

### 1.5 Detail density at game distance (calc)

`px/m = H_px / (2·d·tan(FOV_v/2))`, with H_px = 900. Godot's `Camera3D.fov` is vertical by default (keep_aspect height) [GD-CAM].

| View | d (m) | FOV_v | px/m | Consequence |
|---|---|---|---|---|
| 3rd person, hero | 26 | 70° | **24.7** | Hero = 395 px. An 8 cm panel groove ≈ 2 px. Marking letters ≥ 0.4 m ≈ 10 px. |
| 3rd person, ADS | 26 | 52° | 35.5 | — |
| 1st person, own forearm / rifle | 5 | 80° | **107** | Forearms, hands and weapons need ≥ 128 texels/m. |
| Ripper leap, close | 10 | 70° | 64 | Ripper texture needs ≥ 64 texels/m. |
| Mid range | 50 | 70° | 12.9 | Ripper (2.8 m tall) = 36 px. |
| Spitter band | 150 | 70° | 4.3 | Spitter = 51 px; acid sac (2.5 m) = 11 px. |
| Spitter band, far | 300 | 70° | 2.1 | Spitter = 26 px; sac = 5 px. **Glow plus HUD marker are mandatory.** |
| Lock range | 600 | 70° | 1.07 | Juggernaut = 24 px; Titan = 96 px. |
| Skyline | 1,000 | 70° | 0.64 | Titan = 58 px. |

**Detail tiers** (estimate):

| Tier | Size | Examples | Reads at |
|---|---|---|---|
| Primary | ≥ 2 m | armour blocks | 300 m |
| Secondary | 0.5–2 m | vents, hatches, nozzles, sensor ports | 50–150 m |
| Tertiary | 0.08–0.5 m | panel lines, rivets, markings | within ~60 m and in the cockpit |

- Leave ≥ 40 % of every big panel plain ("rest areas").
- Cluster tertiary detail at panel edges and joints, as in img 05.

**Texel budget** (calc):
- A 4K atlas at 70 % packing holds 11.7 M texels.
- At 128 texels/m (16,384 per m²) it covers 716 m², more than the hero's armour (≈ 500–650 m², estimate). **One 4K armour set is enough.**
- Weapons get a 2K set each. A rifle of ≈ 60 m² then gets ≈ 220 texels/m.

### 1.6 Marking vocabulary (Ver.Ka logic, original content)

- **Codes and emblems:**
  - unit code `YQ-X1` and `天枢` on the left shoulder and the shield;
  - a seven-star glyph as the emblem;
  - serial `YQ-X1-001`.
- **Caution stripes:** vermilion and black, 45°, 0.25 m wide. Place at thruster exhausts, hatch edges and the anchor port.
- **Stencils:** 0.35–0.6 m tall: `NO STEP`, `JET BLAST`, `LIFT POINT`, `EMERGENCY HATCH` (cockpit), plus maintenance arrows and a rescue triangle by the hatch.
- **Density:** one cluster per 2–3 m² of large flat panel; none on small or curved parts (estimate).
- **Never:** "Gundam", "Mobile Suit", E.F.S.F., Zeon, or any real brand or company logo.

---

## 2. Hero design brief: 天枢 TIANSHU (YQ-X1)

### 2.1 Name and concept

- **Name:** 天枢 TIANSHU is Dubhe, the first star of the Big Dipper, the "pivot of heaven". Dubhe and Merak point to Polaris, so the call-sign is **POINTER**.
- **Designation:** YQ-X1 (Yunque Defence, prototype 1).
- **Alternates:**
  - 北辰 BEICHEN (Pole Star);
  - 曦曜 XIYAO ("dawn radiance", matching the Dawn Edge saber);
  - 天衡 TIANHENG;
  - 破晓 POXIAO (Daybreak).
- **Sub-names:**
  - inner frame "Armillary Frame";
  - backpack "Corona Ring";
  - drones "Corona Fins".
- Run a name and trademark search before any public release.

**Concept in one line:** a prototype guardian built like an astronomical instrument (rings, pointers, star lights) worn as samurai-knight armour. It stands in perfect stillness, then explodes into motion like an iai draw.

### 2.2 Parts, front to back

These are the rigid segments and also the Tripo jobs. Triangle counts are LOD0 estimates.

| # | Part | Bone(s) | Design notes | Geometry source | Tris |
|---|---|---|---|---|---|
| 1 | Pointer crest and 2 antennae | head | gold; blade tip at 16.0 m; antennae 1.2 m | **Blender** (thin) | 300 |
| 2 | Helmet, visor, faceplate, cheek guards, rear sensor fin | head | small head, 1.95 m | Tripo "head" | 2.5k |
| 3 | Neck frame | neck | stacked rings and pistons | Blender | 400 |
| 4 | Upper chest | chest | cockpit block, collar armour, 7-star frame, side intakes, emergency hatch | Tripo "torso" | 6k |
| 5 | Abdomen | spine | segmented frame plus 3 plates | Tripo "torso" | 2k |
| 6 | Waist and skirts (front ×2, side ×2, rear) | hips, skirt_* | V-buckle; side skirts hold Undertow spheres; rear skirt holds the rifle | Tripo "torso" | 3k |
| 7 | Shoulder armour ×2 | shoulder.L/R | top plates hinge up to reveal 6 missile cells each | Tripo "arm" (mirror) | 2×2.5k |
| 8 | Upper arm ×2 | upperarm.L/R | frame visible at the inside | Tripo "arm" | 2×1.5k |
| 9 | Forearm ×2 | forearm.L/R | L: shield mount; R: saber-hilt bay | Tripo "arm" | 2×2.5k |
| 10 | Hands ×2 | hand + 8 finger bones each | thumb ×2, index ×3, 3-finger block ×3 | **Blender** parametric | 2×1.5k |
| 11 | Thigh ×2, knee cap ×2 | thigh, shin | knee cap slides on flexion | Tripo "leg" (mirror) | 2×2.5k |
| 12 | Shin and calf thrusters ×2 | shin | long shin, 2 calf nozzles each | Tripo "leg" | 2×3k |
| 13 | Ankle skirt, foot, toe, heel skate ×2 | foot, toe | wedge toe, heel spur, sole thrusters | Tripo "leg" | 2×2k |
| 14 | Backpack core, Corona Ring, 2 main nozzles | backpack | ring core glows; 6 fin sockets | Tripo "backpack" | 4k |
| 15 | Corona Fins ×6 | fin.1…6 | one Tripo fin instanced 6×; cyan edge strips | Tripo "fin" + Blender edges | 6×1k |
| W | Rifle, gatling, shield, saber hilt | sockets | see §2.4 | Tripo (rifle/shield exist) | 8k + 8k + 6k + 1k |

Totals:
- **Body ≈ 55k + weapons ≈ 23k** tris.
- About **65 bones**: 34 body (including 6 fins, 5 skirts and 2 toes), 16 fingers, and ~15 deform-flagged sockets with no weights.

Sockets:
- `socket_rifle_r`, `socket_shield_l`, `muzzle_rifle`, `muzzle_gatling`, `saber_emitter`, `anchor_tip`, `cam_cockpit`;
- `thr_back_l/r`, `thr_calf_l/r`, `thr_sole_l/r`;
- `core_chest`, `wing_l`, `wing_r` (SPEC).

### 2.3 Glow map and overdrive behaviour

**Cyan nodes:**
- visor and eye-nodes;
- the 7 chest stars;
- fin edge strips;
- ring core;
- calf vents and sole thrusters;
- rifle lens rings;
- shoulder pod interiors, only while open.

**Zenith Overdrive:**
- The stars light one by one as OD fills (1/7 each).
- On ignite, the frame seams, ring and fin edges ramp to white-gold `#FFE6A3` over 0.4 s.
- A whole-silhouette material change, not just particles (img 06).

### 2.4 Weapons and kit (matches SPEC §6 and the animation ids in SPEC §10)

| Kit | Mount / stow | Size (m) | Shape | Motion and VFX hooks | Anim ids |
|---|---|---|---|---|---|
| Pierce-Light Rifle 贯光步枪 | right hand; stows on the rear skirt | 9.0 long | long split barrel, 3 lens rings, top vent fins, foregrip, scope linked to the head sensor | charge stage 1: vent fins open in 0.2 s; stage 2: rings spin | fire_r, charge_r |
| Thunder Spindle Gatling 雷纺机炮 | swaps into the right hand; stows vertically on the ring's right side | 7.0 | 6 barrels inside an open coil cage | barrels heat from gunmetal to orange-white (diegetic HEAT) | gatling_spin, reload |
| Dawn Edge 曦刃 | hilt (1.4) pops from the right forearm bay | blade 11 | white core, cyan edge, gold forked emitter | weapon trail during active frames | melee_l1…l3, lunge, charge_slash, air_*, return_cut, execution |
| Mirror Guard 镜返盾 | left forearm | 7.5 × 3.4 kite | mirror lens in the centre; tip = anchor head | catch-field hold: 3 hard-light petals unfold into a 10 m disc | guard_up, parry, catch_hold, catch_release |
| Skyhook 天钩锚 | the shield tip on a cable | — | harpoon head with 3 hooks | cable plus spark trail | anchor_fire |
| Hailstorm 雹暴齐射 | 2 × 6 cells under the shoulder top plates | — | — | plates lift 0.15 s before launch (anticipation) | missile_launch |
| Corona Fins 日冕翼片 / Ward | 6 radial fins on the ring | 6.5 each | blade drones with 2 micro-thrusters each | send: fan out; Ward: hexagon of fins with panes between | fins_send, ward |
| Shockcore Burst 震核爆 | chest | — | chest plates slide 0.5 m apart | stars flare white, core burst | burst |
| Undertow Well 暗流引井 | side-skirt racks | Ø 1.2 sphere | sphere with 3 rings | ring spin, implosion | well_throw |
| Plunge Breaker 坠击破 | heel spurs, knee spikes | — | — | dive trail, landing ring | plunge_dive, plunge_land |
| Zenith Lance 天顶光枪 | fins form a 12 m ring 10 m in front of the chest; the rifle fires through it | beam 16 wide, 800 long (SPEC) | — | ring is the signature charge read | overdrive_ignite, lance_fire |

### 2.5 Concept-image prompts

Use these with Tripo Studio's image tool (GPT Image 2.5) or ys-api. Tripo-ready rules are in §4.2.

**Master (front, A-pose, Tripo input):**
> Original heroic humanoid combat mech "TIANSHU YQ-X1", full body, strict front orthographic view, A-pose (arms 30° from body, legs shoulder-width), 7.8-heads proportions: small head, broad raised shoulders, narrow waist, long legs, large wedge feet. Pearl-white armour, midnight-cobalt chest block and shins, solar-gold trim, tiny vermilion caution markings and stencilled maintenance text. Dark gunmetal inner frame with titanium pistons visible at neck, elbows, waist, knees and ankles. Head: one forward-raked gold pointer blade crest with two short swept-back antennae, narrow cyan visor with two sharp eye nodes, faceplate with three vertical vents. Seven small cyan lights in a Big Dipper pattern across the chest, framed in gold. Backpack: a ring with six long blade-shaped fins folded in an X behind the shoulders. Crisp hard-surface panel lines. Plain light-grey background, even soft studio light, no cast shadows, no weapons, whole figure in frame, no logos, not Gundam.

**Turnaround (Tripo multiview).** Run once per view: "same mech, identical pose and scale, **left / back / right** orthographic view". Check that both arms hang identically in the side views (§4.3, swept-arms failure).

**Key art:** "same mech in Katoki stance, three-quarter low-angle view, holding a long rifle, kite shield on left forearm, fins fanned into a sunburst, dusk megacity behind".

**Per-part (Tripo, 4 views each)**, isolated on grey, as if mounted on an invisible armature:
- "TIANSHU head with pointer crest";
- "torso: chest, abdomen and waist skirts, no arms, no head, no legs";
- "left arm from shoulder armour to wrist, no hand";
- "left leg from hip joint to foot";
- "backpack ring with six fin sockets, two main thrusters";
- "single blade fin drone 6.5 m";
- "long beam rifle with three lens rings";
- "kite shield with mirror lens and harpoon tip";
- "six-barrel coil gatling".

**Tripo captions (short, concrete)** [SCN-TRIPO]:
- "white and cobalt armoured mech torso with gold trim and cyan lights";
- "white mech leg with calf thrusters".

---

## 3. (B) Biomechanical enemies: the 蚀骸 HUSK

### 3.1 What the references teach

| Source | Lesson | Use |
|---|---|---|
| Pacific Rim kaiju (Wayne Barlowe lead) | Families (reptilian, insect, crustacean) rendered with real animal anatomy. **Shared design elements show a common purpose.** A vaguely humanoid silhouette. No scars, because they are engineered. Signature reads: Knifehead (goblin-shark head), Leatherback ("brawler with a beer belly"), Onibaba (temple plus crustacean), Slattern (long neck, half-horn half-crown). About 100 kaiju designed, best picked by weekly vote [WIKI-PR]. | Shared Husk traits (§3.2). One animal-plus-object metaphor per type. Img 13 shows ~30 silhouettes with one glow language. |
| Edge of Tomorrow mimics | Bodies "made up of fast moving tentacles". Obsidian, "a glass that could cut". "Softer shapes toward the base and more angular toward the ends". Tentacles were procedural (spTentacle), with LOD by swapping geometry [FXG-EOT]. | Ripper legs: soft at the root, blade at the tip. Procedural secondary motion in Godot. One glowing core (img 15). |
| Dead Space necromorphs | "Strategic dismemberment" was core from the start. "The reason the slashers have long arms that extend above their head is to create dismemberment opportunities." Each enemy is a "brain teaser". Variants reuse the existing rig. The leaper was scaled down to fit the spaces [GR-DS]. | Mantis blades are breakable targets. Ripper Alpha reuses the Ripper rig. Size enemies to the navmesh classes (CONTRACTS §7). |
| Horizon machines | Scorpion-like machines failed because "the legs were so thin you barely had any surface to hit". Large surfaces allowed components "that could be shot off". Mix animals; never translate one literally. Watcher eye = instant-kill weak spot; the Scrapper has many weak points but no critical one [PS-HZD]. Early machines have one exposed weak point; armour is added later [GD-HZD]. | **Limbs ≥ 0.12 × body height thick** (estimate). Progression: Ripper (one obvious weak point) → Juggernaut (armour first). Img 20 shows a scan highlight in a reserved colour. |
| StarCraft II Zerg | "Strong silhouettes, exaggerated proportions, distinctive animations, and bold, saturated colors" (search snippet) [GS-SC2]. Team colour floods organic regions [PCG-SC2]. | One saturated faction colour on dark chitin (img 21). |
| Level Design Book | Unique silhouette so type reads at mid range (~10+ m). Details and animation must telegraph state and intent. Balance the roster as a role × speed × health × range × DPS matrix [LDB-ENEMY]. | The §3.5 table follows that matrix. |
| Starship Troopers, Halo Flood, EDF, Destiny Hive, God Eater, Attack on Titan (images) | Warrior bug: 4 walking legs plus 2 raised forelegs (img 16). Flood: one oversized tentacle arm (img 17). EDF: insects clinging to high-rises (img 19). Hive Ogre: huge shoulders, tiny head, eye-beam (img 22). Vajra: one coloured blade-mane as its whole identity (img 23). Colossal Titan: 60 m, "tall enough to peer over the top of the Walls" [AOT-COL] (img 24). | Ripper silhouette; Mantis asymmetry; vertical swarms; Juggernaut mass; one signature feature per type; Titan reveal by occlusion. |
| Accessibility | "Use colour as a back-up for another means of communicating the information, such as text or a symbol, pattern or shape" [GAG-COLOUR]. | Every colour code also has a shape and a sound. |

### 3.2 Husk faction design language (shared by every type)

1. **Dorsal keel.** A row of black chitin plates with an acid-green seam along the midline. It is the faction's silhouette signature: a spiky top line.
2. **Eyes.** Clusters of 3 slits, acid green, never violet.
3. **Attack parts are bone-white** (`#C9BFA6`: claws, mandibles, blades, horns). The lightest value on the body means "this hurts". Value contrast pre-reads every attack.
4. **Scavenged city steel.** Angular slabs fused into the carapace, carrying faded hazard stripes and signage glyphs. They are always breakable armour. This ties the Husk to the city: they "wear" what they corrode.
5. **Weak points are violet nerve cores.** Round or oval, ringed, recessed. They have a **closed** state (plates over) and an **open** state.
6. **Soft tissue** is desaturated maroon-brown `#3A2A2E`, never saturated red (red means unblockable).
7. **Posture separates the types:**
   - Ripper low and horizontal;
   - Mantis a tall vertical X;
   - Spitter a wide squat dome;
   - Harrier a flat triangle;
   - Juggernaut a wedge-boulder;
   - Brood Titan a walking cathedral.
8. **Animation.** Engineered precision: stillness, then snaps (Pacific Rim's engineered "weapons" [WIKI-PR]). Add looseness and sway in the idle [SHMUP-AC].

### 3.3 Colour, emission and telegraph coding (estimate unless SPEC)

| Signal | Colour | Emission / timing | Shape back-up | Sound back-up |
|---|---|---|---|---|
| Faction glow seams | `#9BFF3A` (SPEC) | energy 2–3; pulse 0.5 Hz idle, 1.5 Hz alert | thin lines along plates | low breathing |
| Weak point, closed | `#B04CFF` (SPEC) | energy 2, steady | ring visible at a plate gap | — |
| Weak point, open | `#B04CFF` | energy 10; 2 Hz scale pulse 1.0→1.15 | ring, plus a HUD diamond on scan or lock | wet "thrum" loop |
| Parryable hit | white glint | sprite flash 0.12 s, 0.35 s before impact (SPEC, Mantis) | star-glint on the blade tip | metallic "ting" |
| Unblockable | red `#FF2A2A` | body fresnel rim plus a ground decal, from windup start | red glyph above the head [juice §11.1] | unique sting |
| Hit flash | white overlay | 2–3 f (feel unit) | — | — |
| Death | seams fade 0.5 s, then a dissolve | wreck stays 30 s (enemies brief) | — | — |

**Getting the masks out of Tripo textures.** Tripo GLBs carry one material with baseColor, metallicRoughness and normal textures and **no emissive map**. They are compressed with `EXT_meshopt_compression` and `KHR_mesh_quantization`. Observed in `art/tripo/hero_body_front/model.glb` (1,915,175 tris) and `hero_rifle/model.glb` (281,933 tris) [LEAD-TRIPO]. Always round-trip them through Blender before Godot.
- Paint the concept with **pure** `#9BFF3A` seams and `#B04CFF` cores on the dark carapace.
- `husk.gdshader` then chroma-keys them: `mask = 1 − smoothstep(0.10, 0.18, distance(albedo.rgb, key_rgb))`.
- It routes each mask to emission and to the open/closed uniforms (estimate; verify on the first generated Husk).
- The same shader exposes `hit_flash`, `dissolve`, `glow_energy` and `weak_open` for the monster model API (CONTRACTS §6).
- Generate with "Remove Lighting" (delight) on [LEAD-TRIPO][SCN-TRIPO] so baked shadows don't break the key.

### 3.4 Boss-specific readability

**Brood Titan on the skyline** (58 px at 1 km, calc):
- slow stride, 0.25 Hz;
- breathing glow on the brood chimneys;
- violet cores are hidden until phase 2;
- its emissive layer is a `next_pass` material with `render_mode fog_disabled` [GD-SPATIAL], so the city fog doesn't erase it.

**Reveal staging:** first seen through a gap between towers, head above the roofline, with steam occluding the body (img 24 logic).

### 3.5 Roster

Telegraphs in the table come from SPEC/brief. Shapes, sizes and budgets are estimates.

| Type (SPEC) | Size | Silhouette / metaphor | Movement | Telegraphs | Weak point | Rig | LOD0 / tex |
|---|---|---|---|---|---|---|---|
| **Ripper 裂爪** (swarmer/flanker) | 6 m long, 2.8 m tall | low arrowhead, "hound + mantis-shrimp": 4 thick blade-tipped walking legs, 2 raised sickle forelimbs, split mandibles, scavenged plate on the back (img 16) | sprint 32 m/s, climbs façades and ramps, leaps 25–40 m | **0.45 s crouch** + mandible flare + eye flash; leap-bite is parryable | throat sac under the jaw, shown in the crouch (×2.5); dies to 1–2 rifle shots anyway | hexapod: custom 26-bone rig; procedural tripod gait | 6–8k / 1K shared |
| **Ripper Alpha** (elite variant) | 1.4× scale | armoured crest, 2 extra dorsal plates, brighter seams | double leap; howl buffs the pack +15 % speed for 5 s | howl: 0.6 s rear-up | same sac, armoured until the crest breaks | same rig (Dead Space reuse [GR-DS]) | 9k / 1K + variant |
| **Mantis 镰影** (duelist) | 14 m biped | tall X: reverse-joint legs [AC6-LEGS], two 7 m scythe forearms raised above the head [GR-DS], hooded head | sidestep dash 20 m in 0.3 s; lunge | **white glint 0.35 s** before each of 3 hits; **red grab 0.6 s** (unblockable) | thorax core behind rib-plates that open during the grab and on stagger | Tripo humanoid (biped) + keyed combos | 18–22k / 2K |
| **Spitter 酸巢** (artillery) | 12 m tall quadruped | wide squat dome (siege-toad/beetle), dorsal acid sac, mortar chimney, spore pods on the flanks | 6–8 m/s; seeks high ground at 150–300 m; plants its legs before firing | sac swells 0.8 s + chimney glow + gurgle; lob arc is visible (catchable) | **back sac** (SPEC) ×2.5; spore pods pop | Tripo quadruped (walk preset) + keyed fire | 15–20k / 2K |
| **Harrier 鸣翼** (flyer) | 16 m span | flat manta-wasp triangle, bone finger-spars on opaque membranes, stinger tail, throat siren sacs | circles at 60–120 m; strafes at 40–60 m/s | **0.5 s screech** + wings fold into a dart (the silhouette change *is* the tell) | throat siren sac (seen from below) | avian rig (Tripo v2.5 has no avian preset) → procedural flap | 10–14k / 2K |
| **Juggernaut 裂山** (brute) | 22 m | wedge-boulder: rhino-ankylosaur knuckle-walker, 8 frontal scavenged-steel plates, tiny head (img 22) | plods 8 m/s; charges 45–60 m/s for 2 s | **0.7 s roar + ground glow** (SPEC); plates lock into a ram; slam: 1.0 s rear-up → shockwave ring | **back spine core** ×2.5 (SPEC) forces flanking | quadruped; plates are separate rigid meshes on bones | 30–40k + 8×1k / 4K or 2×2K |
| **Brood Titan 巢母** (boss) | 90 m | walking cathedral: 4 pillar legs, 2 scythe forelimbs, long neck, crown head with a beam maw, brood chimneys on the back birthing Rippers | stride 30 m at 0.25 Hz ≈ 7.5 m/s | beam sweep: 1.4 s head raise + maw glow + scorch-line preview; stomp: 1.0 s foot raise + shadow decal | cores on shoulders and back (SPEC, 8,000 HP each), hidden until phase 2 | **custom Blender rig**, keyed walk, IK foot planting | 120–160k; LOD1 40k; skyline 10k / 2×4K + tiling detail normal |
| *Mite* (optional fodder) | 3–4 m | Ripper hatchling, bulbous glowing abdomen | swarm rush, explodes on contact | 0.3 s abdomen swell | whole body | none (shader wobble) | 1.5k / 512² |

### 3.6 Per-type prompts

**Shared concept-image suffix** (Tripo-ready): *"…dark matte charcoal chitin (#1B1E24), thin glowing pure acid-green (#9BFF3A) seams along a dorsal keel of plates, three acid-green slit eyes, bone-white claws, violet (#B04CFF) ringed nerve core, fused slabs of scavenged steel with faded hazard stripes; neutral standing pose with all limbs separated and visible, mouth closed, tail straight; plain light-grey background, even soft light, no shadows, whole body in frame, game creature concept, clear readable silhouette."*

**Pose and view rule:**
- Bipeds: front A-pose.
- Quadrupeds, insects and flyers: **side view first**, then front/left/back/right multiview.
- Flyers: wings fully spread.

| Type | Tripo caption | Concept prompt core (+ suffix) |
|---|---|---|
| Ripper | "biomechanical six-legged hound, black chitin, green seams" | "Ripper: 6 m low wedge-bodied alien predator, four thick blade-tipped walking legs and two raised sickle forelimbs folded at the chest, split mandibles closed, violet throat sac under the jaw" |
| Mantis | "biomechanical mantis knight, scythe arms, black chitin" | "Mantis: 14 m reverse-jointed biped, narrow waist, two 7 m scythe forearms raised above the head, hooded insect head, rib-like chest plates over a violet core, A-pose with blades held out to the sides" |
| Spitter | "biomechanical artillery toad, acid sac on back" | "Spitter: 12 m squat four-legged siege beast, wide stance, huge translucent violet acid sac on the back, mortar-like chimney, spore pods along the flanks" |
| Harrier | "biomechanical manta wasp, membrane wings, stinger" | "Harrier: 16 m wingspan flat manta-wasp flyer, wings spread flat, bone finger spars, opaque dark membranes with green veins, long stinger tail, violet siren sacs under the throat" |
| Juggernaut | "armoured biomechanical rhino brute, steel front plates" | "Juggernaut: 22 m knuckle-walking armoured brute, eight huge scavenged-steel plates covering the front, tiny head low between massive shoulders, glowing violet core along the spine" |
| Brood Titan | "colossal biomechanical walker with chimneys" | "Brood Titan: 90 m colossus on four pillar legs, two folded scythe forelimbs, long neck with a crown-like head and glowing maw, cathedral-like brood chimneys on its back, violet cores on shoulders and back" |

---

## 4. (C) Tripo3D → game-ready characters

### 4.1 What Tripo offers today

| Step | Tool / option | Limits and facts | Cost | Ref |
|---|---|---|---|---|
| Concept image | Studio "Image" (GPT Image 2.5) | in-app | — | (observed) [LEAD-TRIPO] |
| One image → 4 views | "Generate Multi-Views" / image-to-multiview | order front, left, back, right | API 10 | [ALI-GEN][PRIOR-JOB] |
| Image / multiview → 3D | HD Model `v3.1-20260211` | Ultra mesh ≤ 2 M faces (standard ≤ 1.5 M); quad ≤ 150k (FBX); texture 2K/4K/8K; PBR; "Remove Lighting"; `texture_alignment`; `orientation=align_image`; `compress=geometry` (meshopt) | 65 web credits with Ultra + 8K (observed) | [LEAD-TRIPO][ALI-GEN] |
| Clean topology at birth | Smart Mesh **P2.0** (preview) | 500–50,000 tris or 500–25,000 quads; quad FBX; front + back is the safest multiview pair | API 100–130 | [TRIPO-P2][SCN-TRIPO][PRIOR-JOB] |
| Parts | "Generate in Parts" (members) / Segmentation v2 | generated parts are **untextured**. Segment v2: granularity Simple/Balanced/Detailed, split by connectivity, optional reference image, ≤ 150 MB | API seg 40 | [ALI-GEN][SCN-SEG] |
| Retopology | Retopo (Smart Mesh P1.0 toggle) / API v2–v3 | **500–20,000 tris** (≤ 10,000 quads); bakes textures; Smart UV in the same pass; v3 lands within ~1 % of target (max +8.6 %); quads up to +17 %; can target segmentation parts (`tripo_part_N`) | 35 (observed) | [LEAD-TRIPO][ALI-RETOPO][SCN-TRIPO] |
| Smart UV | Smart UV | keeps format, face count and skeleton (41/52 bones tested); **drops animation clips** | — | [SCN-TRIPO] |
| Rig check | API | `riggable` + recommended `rig_type` | free | [ALI-RIGCHECK] |
| Auto-rig | Rig: Humanoid / Other; presets UE5 Mannequin, Mixamo, VRM 1.0, Unity Humanoid, ActorCore; API types: biped, quadruped, hexapod, octopod, avian, serpentine, aquatic | biped `v1.0-20240301` (90+ presets); animals `v2.5-20260210`; spec `mixamo` cannot be retargeted by Tripo; refused the 1,915,175-face hero ("Polygon Limit Exceeded", observed); keep < 300k polys | 20 web (observed) | [SI-TRIPO][ALI-RIG][LEAD-TRIPO][SCN-TRIPO] |
| Animate | presets, Text-to-Motion (1–10 s), Multi-stage (≤ 5 segments) | **non-humanoid presets:** quadruped walk/catwalk, hexapod walk, octopod walk, serpentine march, aquatic march; **no avian**. Humanoid presets are everyday mocap (idle, walk, run, jump, fall, turn, slash, shoot, hurt, hit_to_*, front_kick, box, chop…). ≤ 5 clips per retarget; `animate_in_place` | 20 per generation | [SI-TRIPO][ALI-RETARGET] |
| Export | GLB / FBX | FBX recommended for rigs and animation | — | [SI-TRIPO] |

### 4.2 Input images that work

- **Background and light:** plain solid background (white or light grey), even diffused light, no harsh directional light [TRIPO-TIPS].
- **Format:** JPEG/PNG, 20–6,000 px (> 256 px recommended), ≤ 20 MB [ALI-GUIDE]. Use 1,536–2,048 px squares (estimate).
- **Subject:** one centred object, the whole object in frame, ~85 % of frame height (estimate). No props crossing the body, no motion blur, no perspective distortion. Orthographic views for multiview.
- **Pose:** T- or A-pose for anything to be rigged (observed UI hint; [SI-TRIPO]). Fingers spread. Mouth closed. Limbs clear of the torso by ≥ 0.3 × limb thickness (estimate).
- **Multiview:** the array is **fixed at 4 in the order front, left, back, right**. Front is required, 2–4 images valid, and lighting must be consistent [ALI-GEN]. In "left", the subject faces image-left [PRIOR-JOB]. Single views must invent the back; multiview "improves geometric accuracy and texture coverage" [ALI-GEN].
- **3/4 vs multiview:** a single 3/4 view gives the best one-shot volume for props. For anything rigged, use a front A-pose plus 3 more views. If you only have independently generated views, front + back is the safest P2 pair [SCN-TRIPO].
- **Colour keys:** paint emissive and weak-point regions in exact reserved hexes (§3.3), and turn Remove Lighting on.

### 4.3 Failure modes and fixes

| Failure | Evidence | Fix |
|---|---|---|
| Fused fingers or limbs, "mitten" hands | [TRIPO-TOPO]; both hands fused on the 10-29 job [PRIOR-JOB] | Hero hands: Blender parametric. Monsters: claws as separate parts, or design limbs clear of the body. |
| Thin parts melt, vanish or blob (crests, antennae, chains, wing spars) | the sword chain became a lumpy blob [PRIOR-JOB]; "paper-thin areas" (snippet) [BLYTH] | Model in Blender, or generate alone at full frame. Design-time minimum thickness ≥ 1.5 % of object height (estimate). |
| Asymmetry: arms swept back in a V (top view) | right arm 14.8°, left 7.5°, caused by inconsistent side views [PRIOR-JOB]; "symmetry is a high-level guideline, not a precise mirror" (snippet) [TRIPO-SYM] | Consistent ortho views. Check the top view numerically. Mirror the best half of hard-surface parts in Blender. |
| Hallucinated back side | single-view input | Multiview (4.2). |
| 1.5–2 M faces; auto-rig refuses or fails | observed 1,915,175 faces → refused; < 300k advised [SCN-TRIPO] | Retopo v3 (≤ 20k per part) or P2.0; Blender decimate plus bake for larger budgets. |
| Fragmented UV atlas (~1,200 islands) with leftover paint | [PRIOR-JOB] | Retopo with Smart UV plus bake, or re-unwrap and re-bake per part in Blender. |
| Floating fragments, holes, self-intersections, mirrored artefacts | [TRIPO-TOPO]; [BLYTH] snippet | Merge by distance 1 mm; delete loose; fill holes; check signed volume. **Never recalculate normals on open meshes**: it flipped whole shells [PRIOR-JOB]. |
| Baked lighting in the albedo | — | Remove Lighting / Delight on [SCN-TRIPO]. |
| Arbitrary scale and facing | the exporter's facing varies [PRIOR-JOB] | Normalise in Blender to the spec size; hero faces −Y (→ glTF +Z, Godot's model front). |
| Soft, rounded hard-surface edges | (estimate) | Hero armour: P2.0 per part for crisper planes, or weighted normals plus a normal bake from the Ultra mesh. |

### 4.4 Budgets (estimate; M1 Max target 60 fps per SPEC §12)

| Asset | Max on screen | LOD0 tris | LOD1 / LOD2 | Bones | Materials | Textures |
|---|---|---|---|---|---|---|
| Hero body + fins | 1 | 55k | none (always near) | ~65 | armour, frame, glow/glass, fins | 4K armour set (albedo-ID, ORM, normal) + 2K frame + 2K decal atlas |
| Hero weapons | 2 | 8k + 8k + 6k + 1k | — | sockets | 1 | 2K atlas |
| Ripper | 16 | 6–8k | 2.5k (> 60 m) / 0.8k (> 150 m) | 26 | 1 | 1K shared |
| Mantis | 2 | 18–22k | 7k / 2k | ~50 | 1–2 | 2K |
| Spitter | 3 | 15–20k | 6k / 2k | ~35 | 1 | 2K |
| Harrier | 4 | 10–14k | 4k / 1.2k | ~30 | 1 (opaque membrane) | 2K |
| Juggernaut | 1 | 30–40k + plates | 12k / 4k | ~45 | 2 | 4K or 2×2K |
| Brood Titan | 1 | 120–160k | 40k / 10k | ~80 | 2–3 | 2×4K + tiling detail normal |

Worst-case skinned load ≈ 0.25 M tris without the boss, ≈ 0.4 M with it (calc from the table).

**Skinned LODs:** Godot's automatic import LOD "may occasionally introduce rendering issues (especially in skinned meshes)" [GD-LOD]. So:
- export LOD0 and LOD1 as **two skinned meshes on the same skeleton**;
- switch them with `visibility_range_begin/end` (fade mode Self);
- keep auto-LOD only if the visual check passes.

### 4.5 Step by step

**Hero (unit `hero-asset`, lead supplies the Tripo outputs):**
1. Lock the proportion sheet (§1.2). Build the grey-box rig with the §5.3 script and render a Katoki-stance check.
2. Images:
   - master front A-pose → Tripo multiview (10) → fix the side views until both arms hang identically;
   - then isolate each part into its own 4 views (image edit "keep only X").
3. Per part:
   - multiview → HD model (Ultra, PBR, Remove Lighting, texture 4K);
   - optionally P2.0 for armour shells;
   - then Retopo v3 to the §2.2 tris with Smart UV and bake on.
   - Cost ≈ 10 + 65 + 35 ≈ 110 credits per part, ≈ 1,000 for 9 parts (estimate). Keep the Ultra mesh for the bakes.
4. Blender:
   - import; scale (crest tip 16.0 m); face −Y;
   - clean (§4.3); mirror L/R parts; fit each part to its bone with snapping to the grey box;
   - top-view and joint-clearance check at the §1.2 limits.
5. Bake Ultra → low normal, AO and curvature. Write the palette ID map (§1.4). Markings go on UV2.
6. Rigid-skin, join and export (§5.3). Godot import and smoke test.
7. Animate SPEC §10 ids as Blender actions at 30 fps.
   - Loop clips use the `-loop` suffix, or the loop flag is set in `hero_model.gd` [GD-HINTS].
   - Aim, feet and fin idle are procedural (§4.7).

**Monsters (unit `monster-assets`):**
1. Concept (§3.6 prompts) → multiview → HD model.
2. Split breakables before rigging: Juggernaut plates, Spitter sac, Titan cores. Use Segmentation v2 "Detailed", then hand-pick [SCN-SEG].
3. Retopo v3 + Smart UV + bake. Rippers, Harriers and the Mantis hit their LOD0 inside 20k. For the Juggernaut and Titan, retopo per segment and combine, or use Blender decimate plus bake.
4. Second retopo at the LOD1 count (35 credits).
5. Rig:
   - run the free rig check;
   - Mantis: Tripo biped with spec `tripo` (so Tripo can retarget) or Mixamo (for Mixamo clips);
   - Spitter and Juggernaut: Tripo quadruped (walk preset);
   - Ripper, Harrier and Titan: custom Blender rigs (Tripo has no hexapod or avian combat clips).
6. Animate: key attacks, hits, stagger and death in Blender; locomotion is procedural (§4.7).
7. Godot: `husk.gdshader` (§3.3), LOD meshes on visibility ranges, model API wrapper.

Per-monster cost ≈ 10 + 65 + 35 + 35 + 20 ≈ 165 credits (estimate).

### 4.6 Hero rig decision: rigid segments vs smooth skin

| Criterion | **Rigid skin (recommended)** | Objects parented to bones | Smooth skin (auto-weights / Tripo rig) |
|---|---|---|---|
| Deformation | none; true mechanical joints | none | candy-wrapping and bending armour at elbows and knees |
| Godot import | 1 `Skeleton3D` + 1–3 skinned meshes (**verified**) | one `BoneAttachment3D` + mesh per part [GD-91132]; position bugs reported [GD-69601] | 1 skeleton + skinned mesh |
| Draw calls | one per surface (≈ 6–9) | parts × materials (≈ 25–60) | one per material |
| Hide or detach one part | bone scale → 0 (estimate) or a separate mesh | toggle the node | hard |
| Authoring | scripted mapping of parts to bones (§5.3) | trivial | weight painting, clean-up |
| First-person split | per-mesh `cast_shadow = SHADOWS_ONLY` | per node | per mesh |

**Recommendation:**
- Rigid skin for all armour and frame.
- Two-bone smooth weights only on cables, waist bellows and skirt hinges.
- Meshes grouped by first-person visibility, each with up to 3 surfaces (armour, frame, glow/glass), so ≤ 9 draw calls:
  - `HeroUpper` (head, neck, chest, shoulders): set to `SHADOWS_ONLY` in first person, so the cockpit camera at 12 m sees arms and weapons but keeps the body's shadow;
  - `HeroLower` (everything else);
  - `HeroFins` (6 fins, emissive edges).
- Hide a docked fin when its drone launches: `skeleton.set_bone_pose_scale(fin_idx, Vector3.ZERO)` (estimate; verify).

### 4.7 Procedural layers in Godot 4.7 (SkeletonModifier3D stack)

Godot 4.4–4.6 added 19 modifiers [GD-IK46]:
- 4.4: `LookAtModifier3D`, `RetargetModifier3D`;
- 4.5: `SpringBoneSimulator3D`, plus `BoneConstraint3D` with `AimModifier3D`, `CopyTransformModifier3D`, `ConvertTransformModifier3D`;
- 4.6: `IKModifier3D` with `TwoBoneIK3D`, `ChainIK3D`, `SplineIK3D`, `IterateIK3D`, `FABRIK3D`, `CCDIK3D`, `JacobianIK3D`, plus `BoneTwistDisperser3D` and `LimitAngularVelocityModifier3D`.
- `TwoBoneIK3D` and `SplineIK3D` are always deterministic.

**Hero:**
- chest/upper-arm `LookAtModifier3D` (or `AimModifier3D`) driven by `set_aim(point)`, waist ±45°;
- foot `TwoBoneIK3D` on slopes;
- fins: sine idle ±3° at 0.4 Hz;
- skirts: `CopyTransformModifier3D` from the thighs at 0.5 weight;
- `LimitAngularVelocityModifier3D` caps aim snaps at 720°/s (estimate).

**Ripper (hexapod) tripod gait** (estimate):
- leg sets {L1, R2, L3} / {R1, L2, R3};
- a leg steps when its foot target is more than 0.35 × leg length from rest;
- step 0.18 s at sprint, 0.30 s at walk, arc height 0.25 × leg length;
- body height = mean of the feet + 1.4 m;
- body tilt from the plane fitted to the foot contacts;
- targets come from `PhysicsDirectSpaceState3D` raycasts, so Rippers walk up façades.

**Quadrupeds:**
- keep the Tripo walk clip;
- add `TwoBoneIK3D` foot planting;
- `LookAtModifier3D` head on the player (±70°).

**Harrier:**
- wing flap = shoulder rotation ±35° at 1.5 Hz cruise, 0 Hz glide;
- banking = −0.6 × yaw rate;
- `SpringBoneSimulator3D` on the tail.

**Brood Titan:**
- keyed walk;
- `TwoBoneIK3D` foot planting on rooftops;
- `SpringBoneSimulator3D` on the chimneys;
- shake on footfall (feel unit).

**Shared clips across a family:** a custom `SkeletonProfile` exported from one Ripper skeleton plus a `BoneMap` lets Ripper and Ripper Alpha share every clip [GD-RETARGET]. For humanoids, use `SkeletonProfileHumanoid` auto-mapping [GD-RETARGET].

### 4.8 Godot import settings and runtime notes

- **Format:** GLB.
  - Mesh tangents on.
  - `animation/fps` = 30.
  - `skins/use_named_skins` on.
  - Generate LODs **off** for skinned characters (see §4.4); on for weapons and props.
- **Loops:** loop clips use the `-loop` / `-cycle` suffix, which the glTF importer honours [GD-HINTS], or a loop flag set in the model wrapper.
- **Sockets:**
  - sockets are deform-flagged bones with no weights, so they survive `export_def_bones`;
  - at runtime, create `BoneAttachment3D` nodes for weapons and VFX in the model scene, not in the import;
  - `socket(name)` returns them (CONTRACTS §6).
- **Monster API:**
  - `set_hit_flash(v)` → shader uniform;
  - `hit_pause(s)` → `AnimationMixer` speed 0 plus model vibration (feel unit);
  - `play_action(id)` returns the clip length.

### 4.9 QA checklist (from [PRIOR-JOB] lessons, numeric where possible)

Per asset, before handing it to Godot:
1. **Mesh integrity.** Report counts for each:
   - holes, with size and location;
   - non-manifold edges;
   - loose parts;
   - flipped winding, by signed volume.
2. **Lit renders.**
   - Close-ups at 3 angles of hands/claws, crest/antennae, joints and seams.
   - Never crop through a limb.
   - Use unlit renders only for colour comparison.
3. **Top-view check.** Limb axis per lateral slice; L/R difference ≤ 2°.
4. **UV atlas view.** Island count and leftover paint.
5. **Silhouette.** Black fill at 395 px and at 51 px (hero 26 m; Spitter 150 m).
6. **Joint sweep.** Every joint to its §1.2 limit: no armour interpenetration and no visible holes into the frame.
7. **Godot.**
   - `print_tree` shows 1 `Skeleton3D`, the expected meshes, 0 `BoneAttachment3D`, and the clip list.
   - A screenshot is taken next to a 16 m pillar.

---

## 5. Decisions and implementation notes for the lead

### 5.1 Ten decisions to lock now
1. The hero proportion sheet (§1.2) and the grey-box skeleton come before any more Tripo spending. All parts are fitted to it.
2. The hero signature set (§2.1–2.4) and the "don't" list (§1.3).
3. The palette and reserved colours (§1.4, §3.3). Verify them against ART.md when it lands.
4. Rigid skin for the hero (§4.6), with the 3 mesh groups.
5. Hands, crest, antennae and fin edge strips are built in Blender, not Tripo.
6. Husk shared traits (§3.2) in every concept prompt (§3.6 suffix).
7. Glow and weak-point masks via chroma key from Tripo albedo (§3.3). Test on the first Ripper.
8. Custom rigs for the Ripper, Harrier and Titan. Tripo auto-rig for the Mantis (biped), Spitter and Juggernaut (quadruped).
9. Skinned LODs as separate meshes on visibility ranges.
10. QA checklist (§4.9) in the `hero-asset` and `monster-assets` briefs' "Done when".

### 5.2 Verified rigid-skin pipeline (Blender 5.2.1 → Godot 4.7.2)

Scratch proof:
- `tmp/research/mech-monster-design/scripts/rigid_rig_test.py` builds a 30-bone, 29-part grey box with the §1.2 heights.
- `scripts/verify_glb.py` parses the GLB.
- `stage/godot_test/` holds the Godot import [INHOUSE-RIG].

Results:
- **GLB:** 1 skin with 30 joints; 2 meshes (`HeroBody`, `HeroWings`); 552 + 144 vertices, **100 % with a single weight of 1.0**; 23 + 6 distinct joints used; animation `idle` with 90 channels.
- **Godot:** `hero_blockout → HeroRig → Skeleton3D (30 bones) → HeroBody, HeroWings (skin=true)`, plus `AnimationPlayer ["idle"]`, and `BoneAttachment3D` count **0**.
- **The §5.3 code block itself** was extracted and run: `nearest_bone` mapped 29 of 29 grey-box parts to the right bone, and the joined mesh exported with all 696 vertices rigid (`scripts/dossier_core_test.py`).

The exporter parameter names were read from Blender 5.2.1 itself [BL-GLTF]:
- `export_animation_mode` ∈ {ACTIONS, ACTIVE_ACTIONS, BROADCAST, NLA_TRACKS, SCENE};
- `export_def_bones` default False;
- `export_influence_nb` default 4;
- `export_rest_position_armature` default True;
- `export_leaf_bone` default False.

### 5.3 Blender 5.2 Python: the reusable core (hero-asset unit)

```python
# Run: Blender -b scene.blend --python hero_rig.py -- out_dir   (hero faces -Y; metres)
import bpy
from mathutils import Vector

def build_armature(bones: dict) -> bpy.types.Object:
    """bones = {name: (head_xyz, tail_xyz, parent_or_None)}; all deform (sockets too, they get no weights)."""
    arm = bpy.data.armatures.new("HeroRig"); rig = bpy.data.objects.new("HeroRig", arm)
    bpy.context.scene.collection.objects.link(rig); bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    for n, (h, t, _) in bones.items():
        eb = arm.edit_bones.new(n); eb.head, eb.tail, eb.use_deform = h, t, True
    for n, (_, _, p) in bones.items():
        if p: arm.edit_bones[n].parent = arm.edit_bones[p]
    bpy.ops.object.mode_set(mode="OBJECT")
    return rig

def nearest_bone(rig, obj) -> str:
    """Auto-map a part (e.g. Tripo segment tripo_part_N) to the bone whose segment is closest to its centroid."""
    c = obj.matrix_world @ (sum((Vector(b) for b in obj.bound_box), Vector()) / 8)
    best, dist = None, 1e9
    for b in rig.data.bones:
        h, t = rig.matrix_world @ b.head_local, rig.matrix_world @ b.tail_local
        d = (c - (h + (t - h) * max(0.0, min(1.0, (c - h).dot(t - h) / max((t - h).length_squared, 1e-9))))).length
        if d < dist: best, dist = b.name, d
    return best   # print a part->bone table; apply manual overrides from a JSON file

def rigid_skin(obj, bone: str) -> None:
    obj.vertex_groups.clear()
    vg = obj.vertex_groups.new(name=bone)
    vg.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")    # 100 % to one bone

def join(objs, name):
    a = objs[0]
    with bpy.context.temp_override(active_object=a, object=a, selected_objects=objs, selected_editable_objects=objs):
        bpy.ops.object.join()
    a.name = a.data.name = name
    return a

def bind(obj, rig):
    obj.parent = rig
    obj.modifiers.new("Armature", "ARMATURE").object = rig

def export_glb(path):
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_skins=True, export_animations=True,
        export_animation_mode="ACTIONS", export_def_bones=True, export_influence_nb=4, export_yup=True,
        export_apply=False, export_rest_position_armature=True, export_leaf_bone=False)
```

Workflow:
- for each part: `rigid_skin(part, mapping[part.name])`;
- `join()` per mesh group (`HeroUpper`, `HeroLower`, `HeroFins`; each keeps up to 3 surfaces: armour, frame, glow/glass);
- `bind()` each group;
- keyframe actions (`pose_bone.keyframe_insert("rotation_euler", frame=f)`; set `action.use_fake_user=True`);
- `export_glb()`.

Do apply transforms on the parts first (scale = 1). Do not run recalculate-normals on open Tripo meshes [PRIOR-JOB].

---

## 6. Risks

1. **IP proximity.** The combination of V-fin, dual-eye face and RX-78 colour blocking, or Hi-Nu or Freedom backpacks, would read as a copy. Enforce §1.3, and keep the words Gundam, funnel, dragoon, psycho-frame and beam saber out of the UI.
2. **Tripo hard-surface fidelity.** Melted edges, asymmetry, fused hands and broken thin parts. Plan Blender time for hands, crests and fin edges, plus symmetry fixes.
3. **Animation workload.** Tripo gives monsters walk only, and the hero needs ~40 clips (SPEC §10). Lean on procedural layers. Key only signature actions. Budget M78 time for scripted keyframes.
4. **Colour collisions with the city.** Cyan neon against the hero glow, green signage against the Husk glow, violet neon against weak points. Needs ART.md cross-check and a colour-blind simulation pass.
5. **Skinned LOD artefacts and CPU cost.** 16 Rippers with IK modifiers, at 120 Hz physics. Throttle IK updates for far enemies and switch them to baked walk clips beyond 80 m (estimate).
6. **Rigid-joint gaps.** At extreme poses holes open into the frame. Design overlapping armour and double-jointed frames, and clamp at the §1.2 limits.
7. **Untested assumptions.**
   - Chroma-key masks (hue drift after texturing and Delight).
   - Bone-scale-to-zero hiding.
   - P2.0 edge crispness.
   - Verify each on the first asset.
8. **Tripo Studio is behind Cloudflare** (403 for scripted access): uploads and downloads are manual [PRIOR-JOB]. Studio and API credits are separate pools [PRIOR-JOB].
9. **Scale and orientation drift** between parts. Always normalise to the spec heights and −Y facing before fitting.
10. **Name and trademark collision** for TIANSHU and the alternates. Not checked.

---

## 7. Image index

The 24 reference images, each with its source page and the lesson to take from it, are listed one per line in `ref/images/mech-monster-design/sources.md`. 01–12 are mech references and 13–24 are monster references; `_sheet.jpg` is the numbered contact sheet.

---

## 8. Sources

**Mech design**
- [FORBES-OK] https://www.forbes.com/sites/olliebarder/2016/07/29/kunio-okawara-the-man-who-designed-gundam-and-created-the-profession-of-mechanical-design/ (read via web.archive.org)
- [GOF-FACE] https://gundam-official.com/news/i/special-series/gundam-today/special-series_gundam-today_20120418_738p
- [JAWIKI-GUNDAM] https://ja.wikipedia.org/wiki/ガンダム_(架空の兵器) — RX-78-2: head height 18.0 m, 43.4 t; prototype-colour rationale
- [JAWIKI-KATOKI] https://ja.wikipedia.org/wiki/カトキハジメ — Katoki stance, Ver.Ka, markings as public signs
- [NOTE-PROP] https://note.com/ririwo/n/n6fc011a877f7 — MS head counts 7 / 7.5–8 / 6.5; hip, waist and shoulder adjustments
- [LASCA-VERKA] https://lascalemodel.com/blogs/gunpla-101/gunpla-ver-ka-everything-you-need-to-know-about-this-iconic-line-of-kits
- [GP101-BARB] https://www.gunpla101.com/review-1-100-full-mechanics-gundam-barbatos-lupus-rex/
- [SHMUP-AC] https://shmuplations.com/armoredcore/ — Kawamori, 1997
- [FF-KAWAMORI] https://fullfrontal.moe/kawamori-40-interview/ (search snippet)
- [AC6-LEGS] https://armoredcore6.wiki.fextralife.com/Legs
- [CGC-EMSLIE] https://www.cgchannel.com/2014/04/qa-titanfall-lead-artist-joel-emslie/
- [TF-ATLAS] https://titanfall.fandom.com/wiki/Atlas — Atlas estimated at 20–25 ft
- [WIKI-PR] https://en.wikipedia.org/wiki/Pacific_Rim_(film) — jaeger and kaiju design notes
- [PR-GIPSY] https://pacificrim.fandom.com/wiki/Gipsy_Danger_(Jaeger) — 260 ft (79.25 m), 1,980 t
- [GEASS-LS] https://codegeass.fandom.com/wiki/Landspinner_Propulsion_System
- [GEASS-SH] https://geass.miraheze.org/wiki/Sheffield_Eye — Slash Harken
- [WIKI-AZ] https://en.wikipedia.org/wiki/Aldnoah.Zero
- [AZ-KATA] https://aldnoahzero.fandom.com/wiki/Kataphrakt
- [XENO-YANASE] https://xenoserieswiki.org/wiki/Takayuki_Yanase
- [XENO-SKELL] https://www.xenoserieswiki.org/wiki/Skell
- [XB-FANDOM] https://xenoblade.fandom.com/f/p/2915740562751963749 (search snippet: Yanase also designed for several Armored Core games)
- [TF2-GDC08] https://cdn.fastly.steamstatic.com/apps/valve/2008/GDC2008_StylizationWithAPurpose_TF2.pdf
- [TF2-NPAR07] https://steamcdn-a.akamaihd.net/apps/valve/2007/NPAR07_IllustrativeRenderingInTeamFortress2.pdf

**Monster design**
- [PS-HZD] https://blog.playstation.com/archive/2017/02/24/the-making-of-horizon-zero-dawns-machines-as-told-by-guerrilla-games
- [GD-HZD] https://www.gamedeveloper.com/design/horizon-zero-dawn-design-analysis
- [GR-DS] https://www.gamerevolution.com/originals/443251-dead-space-creative-director-necromorph-design
- [FXG-EOT] https://www.fxguide.com/fxfeatured/live-die-repeat-the-effects/
- [GS-SC2] https://www.gamespot.com/articles/blizzard-talks-starcraft-ii-art-design/1100-6171176/ (search snippet)
- [PCG-SC2] https://www.pcgamer.com/sc2-week-brand-new-zerg-art-style-revealed/ (search snippet)
- [LDB-ENEMY] https://book.leveldesignbook.com/process/combat/enemy
- [AOT-COL] https://attackontitan.fandom.com/wiki/Colossal_Titan_(Anime)
- [GAG-COLOUR] https://gameaccessibilityguidelines.com/ensure-no-essential-information-is-conveyed-by-a-fixed-colour-alone/

**Tripo**
- [ALI-GEN] https://help.aliyun.com/en/model-studio/tripo-3d-generation-api-reference
- [ALI-GUIDE] https://help.aliyun.com/en/model-studio/tripo-3d-generation-guide
- [ALI-RETOPO] https://help.aliyun.com/en/model-studio/tripo-retopology-api-reference
- [ALI-RIG] https://help.aliyun.com/en/model-studio/tripo-auto-rig-api-reference
- [ALI-RIGCHECK] https://help.aliyun.com/en/model-studio/tripo-rig-check-api-reference
- [ALI-RETARGET] https://help.aliyun.com/en/model-studio/tripo-animation-retarget-api-reference
- [SCN-TRIPO] https://help.scenario.com/articles/4692888910-tripo-family-the-complete-guide
- [SCN-SEG] https://help.scenario.com/articles/9861107995-tripo-segmentation-the-essentials
- [SI-TRIPO] https://spatialinsiders.com/stories/tripo-rigging-animation-text-to-motion (2026-10-02)
- [TRIPO-TIPS] https://www.tripo3d.ai/help/features/how-to-get-better-image-to-3d-results (search snippet; the site returns 403)
- [TRIPO-TOPO] https://www.tripo3d.ai/blog/why-ai-3d-models-have-bad-topology (search snippet)
- [TRIPO-SYM] https://www.tripo3d.ai/blog/explore/ai-3d-model-generator-and-symmetry-toggle-edge-cases (search snippet)
- [TRIPO-P2] https://www.tripo3d.ai/blog/tripo-p2-0-preview and https://www.tripo3d.ai/features/smart-mesh (search snippets)
- [BLYTH] https://blyth.ai/blog/best-ai-3d-model-generators-2026 (search snippet)

**Godot and Blender**
- [GD-IK46] https://godotengine.org/article/inverse-kinematics-returns-to-godot-4-6/
- [GD-91132] https://github.com/godotengine/godot/issues/91132
- [GD-69601] https://github.com/godotengine/godot/issues/69601
- [GD-LOD] https://docs.godotengine.org/en/stable/tutorials/3d/mesh_lod.html
- [GD-RETARGET] https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/retargeting_3d_skeletons.html
- [GD-HINTS] https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/node_type_customization.html
- [GD-STDMAT] https://docs.godotengine.org/en/stable/tutorials/3d/standard_material_3d.html
- [GD-SPATIAL] https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html
- [GD-CAM] https://docs.godotengine.org/en/stable/classes/class_camera3d.html
- [BL-GLTF] https://docs.blender.org/manual/en/latest/addons/scene_gltf2.html — parameter names introspected from Blender 5.2.1 (`bpy.ops.export_scene.gltf`)

**Internal evidence**
- [LEAD-TRIPO] `/Users/minimax/m/mecha-city/.lead/{ws,retopo,rig}.jpg`, `detail.json` — the lead's Tripo Studio session, 2026-11-01
- [INHOUSE-RIG] `/Users/minimax/m/mecha-city/tmp/research/mech-monster-design/{scripts/rigid_rig_test.py, scripts/verify_glb.py, stage/rigtest/, stage/godot_test/}`
- [PRIOR-JOB] the 2026-10-29 Tripo character job in `~/m/tripo-char`: hands, swept arms, UV fragmentation, chain blob, normals flip, API prices
