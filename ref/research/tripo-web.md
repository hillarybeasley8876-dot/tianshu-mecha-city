# Tripo Studio (web) for Game-Ready Assets — Dossier

key: `tripo-web` · for: Lead (Claude Opus) · implementers: the user (web clicks) and MiniMax-M78 agents (Blender and Godot steps) · engine: Godot 4.7.2 Forward+ · date: 2026-11-01
Images: `ref/images/tripo-web/` (8 Studio screenshots, `sources.md`, `_sheet.jpg`). In the text, "img NN" means file `NN-*.jpg`.

## 0. TL;DR

- **Two generation routes in the Studio, not two steps** [H-I2M][T-SCENE]:
  - **Best Quality = HD Model = H series (H3.1).** Dense mesh, up to 2,000,000 faces.
  - **Clean Topology = Smart Mesh = P series (P2.0, P1.0).** Native quad-dominant topology. Budget 500–25,000 quads or 500–50,000 triangles.
- **Use P2.0 with Quad topology for everything that will be rigged or edited** (mech parts, creatures).
  - One run costs 100 credits and can produce up to 4 variants at different face counts. Spread the budgets every time [T-SEP][T-P2].
- **Never generate the hero mech as one image.** Tripo's own help says a full mech puts too many parts into one image and one polycount budget, and the generator drops the least visible pieces [H-SMI].
  - Split the mech into about 12 parts, each from 4 matched views.
  - Assemble the parts in Blender. Our 2026-10-29 character job proved this approach [LOCAL].
- **Studio rigging:**
  - Humanoid uses the v3 algorithm: full body plus hand bones, and 5 engine skeleton presets.
  - "Other" uses the v2.5 algorithm and has no engine presets.
  - Rigging costs 20 credits. Limits: humanoids up to 100,000 triangle faces, posed in T or A [T-RIGBLOG][T-SEP].
- **Studio animation:**
  - The preset library is free: the 90+ biped clips, including box, kick, slash, shoot, cast and hit reacts.
  - Text-to-Motion makes clips of 1–10 s for 20 credits each.
  - Multi-stage Motion chains up to 5 segments.
  - Export the clips inside the rigged FBX or GLB [T-RIGBLOG][D-RET][img 06–07].
- **Do not ship Tripo's smooth skin weights on the mech.**
  - Use the auto-rig only to place a humanoid skeleton and to preview presets.
  - In Blender, bind each rigid part 100 % to one bone [CADA].
  - In Godot, attach weapons with BoneAttachment3D [GD-BA].
- **Pick the "Unity Humanoid Compatible" (or Mixamo) skeleton preset** so Godot's SkeletonProfileHumanoid auto-mapping finds the bones. Godot matches bone names by pattern [GD-RT][GD-SPH]. That Unity names fit best is my estimate.
- **Exports:**
  - FBX with the Blender preset goes to Blender. FBX keeps the quads and the skeleton; GLB and OBJ triangulate [H-SMI][img 07].
  - GLB, or the Godot DCC Bridge (Godot 4.6+), goes straight to Godot for static props [T-GBR].
- **Texturing:**
  - Leave "Remove Lighting" ON for everything lit by Godot [D-TEX][T-RL].
  - Keep 8K maps only as the authoring source: 8192² BaseColor plus 4096² Normal and ORM [T-8K]. Ship 2K or 4K by setting Godot's texture "Size Limit" [GD-IMG].
- **Budget:**
  - The hero mech is about 2,300 credits.
  - Each creature type is about 400.
  - Each prop is about 120–140.
  - The whole demo is about 8,000–10,000 credits, roughly $80–100 at $10 per 1,000 [T-PRICE]. All of these totals are my estimate.
- **The Studio cannot be scripted.** Cloudflare blocks headless browsers, so every web step is a manual click by the user [LOCAL]. Hand the user an upload kit per asset: 4 PNG views plus a settings card (§7).

## 1. Conventions

- **Tags** like `[T-P2]` map to URLs in §13. `[LOCAL]` means our own files or measurements under `~/m/tripo-char` or the memory notes.
- **"(estimate)"** marks my own number or judgement.
- **Snapshot dates:**
  - tripo3d.ai and studio.tripo3d.ai return 403 to fetchers. I read the tripo3d.ai pages through web.archive.org snapshots dated 2026-10-16 to 2026-10-19.
  - developers.tripo3d.ai was fetched live on 2026-11-01.
  - Tripo changes prices often. Two examples: P2 dropped its preview price of 65 for an official 100, and segmentation showed 35 in a May screenshot but is 40 in the October help table. Always trust the number on the Generate button over this file.
- **"Credits" means Studio (web) credits** unless marked API. API credits are a separate wallet and cannot be paid for with the subscription [H-API].
- **Triangles versus quads.** One quad renders as two triangles; the quad ceiling is half the triangle ceiling for the same reason [T-SCENE]. In Godot everything renders as triangles. Quads only matter for editing in Blender [T-PROP].

## 2. What the Studio is (Nov 2026)

### 2.1 Layout (from img 01, 02, 05, 06, 07)

| Area | Contents | Source |
|---|---|---|
| Top bar | **3D Workspace** dropdown (High Detail Model / Smart Topology Mesh / Generate Image), Home, Assets, Creator Hub, Resources. Right side: **DCC Bridge**, credit counter | [T-CHAR] img 06 |
| Left toolbar (in order) | **Image**, **Model**, **Segment** ▼ (Segment, Fill Parts), **Retopo**, **Smart UV**, **Texture** ▼, **Rig** ▼, **Animate** | img 06, [T-SEG] |
| Model panel | Tabs **HD Model \| Smart Mesh**. Input-mode icons (single image, multi-view, batch, sketch; the exact icon order is unverified). Upload accepts JPG/PNG/WEBP up to 20 MB. "Generate Image for 3D". **Generate Multi-Views**. General Settings (Topology or Geometry & Texture). **Members Only** (Number of Generation, Customize Poly Counts, Privacy, Generate in Parts, 8K Texture). **AI Model** dropdown. **Generate ⚡N** shows the price | img 01–02, [T-RL] |
| Right panel | **Assets / Property**. "Upload 3D Model" accepts OBJ, FBX, STL, GLB up to 150 MB. **Manage** does batch export and delete | [T-8K], [CGTW] |
| Bottom bar | Undo/redo, **Free Retry (×3)**, 3D Print, Share, **Export**. P2 models also get **Edit Mesh** | img 05, [T-CHAR] |
| Viewport HUD | Topology, Faces, Vertices; Hologram shader for checking inner faces | img 06, [H-SMI] |

The Studio remembers your last generation and export settings ("settings memory", April 2026) [T-APR].

### 2.2 Generation modes

| Mode | How in Studio | Notes | Source |
|---|---|---|---|
| Text → 3D | Prompt on the home page, or Generate Image first | Tripo turns the text into a reference image first. Tripo itself recommends making the image first for control | [CGCH][H-T2M] |
| Image → 3D | Upload in the Model panel, or hover a generated image → **Generate 3D** | Single view: the back and far sides are guessed | [T-CHAR][H-MV] |
| Multi-view → 3D | Upload 2–4 views, or press **Generate Multi-Views** | Views are front / left / right / back. Front is required. Even front + back helps | [T-P2][H-MV] |
| Batch → 3D | **Batch to 3D** | Up to 10 prepared images at once. Batch generation limit: Pro 10, Max/Team 30 | [T-SUN][T-PRICE] |
| Sketch → 3D | Sketch input (pencil icon) | Not needed for this project | [T-TUT25] |
| Upload own mesh | Assets → Upload 3D Model (≤150 MB) | Then use Retopo, Smart UV, Texture/Upscale, or Rig + Animate on it | [H-UPANIM][T-8K] |

### 2.3 Image tools (reference preparation inside the Studio)

- **Models:** GPT-Image-2.5 Sunburst (added Sept 2026), GPT Image 2, Nano Banana / Pro / 2, Midjourney [T-SEP][T-PRICE].
- **Templates** [T-SUN][CGCH]:
  - Character Extraction (splits a character into head, body and accessories)
  - Head Extraction
  - T Pose
  - Character Completion
  - Variants
  - 3D Enhance
  - 3D Print-Ready
  - Photo to Figure
  - Asset Extraction (pulls props out of a scene)
- **Tools:** Edit Image (text- or reference-guided) and Cutout.
- **Recommended editors for cleanup:** Nano Banana Pro or GPT Image 2.5 [T-CHAR].

## 3. Model versions

| Studio label | Series and version (wire id) | Topology and faces | Key options | Speed | Use here | Source |
|---|---|---|---|---|---|---|
| **HD Model / "v3.1 – Best Quality"** | H3.1 (`v3.1-20260211`), the default flagship | Triangle or quad. Polycount slider 500–2,000,000. The API allows 1.5M, or 2M with detailed geometry, or 150k with quad | Ultra Mesh Quality, AI Complete, Texture 2K/4K/8K, Remove Lighting, PBR, Generate in Parts, Smart Low Poly | API: about 40 s without texture, about 120 s with texture. Studio says "several minutes" | Detail source for normal bakes and renders; print. Not the game mesh | [D-H31] img 02 [H-SM] |
| **Smart Mesh → P2.0** | P2 (`P2-20260801`), official since Sept 2026 | **Quad 500–25,000 or triangle 500–50,000.** Default about 5,000 | 1/2/4 variants, multi-view, **Edit Mesh**, auto-separated parts, symmetry recognition, wireframe guidance | 10–40 s per run. One Bilibili tester saw 5–7 s | **Default for all game assets** | [T-P2][D-P2][H-SM][BILI][T-P2VM] |
| Smart Mesh → P1.0 | P1 (`P1-20260311`) | Triangle only, 500–20,000 | Launched as "clean low-poly in 2 seconds"; now powers Retopology | Seconds | Superseded by P2 | [T-P2][T-SEP][T-MAY] |
| Legacy | v3.0 (`v3.0-20250812`), v2.5 (`v2.5-20250123`) | — | — | — | Only to reproduce old assets | [CLI][D-H31] |

"v3" in older posts usually means Tripo 3.0 (Aug 2025, now legacy). It can also mean the **v3 API**, which replaced the v2 API that retires 2026-11-01 [LOCAL].

## 4. Feature and credit table (web credits)

| Operation | Credits | Free allowance / plan gate | Limits | Time | Source |
|---|---|---|---|---|---|
| HD generation, base | 25 | Free plan: "HD Model access" | — | min | [T-CRED][T-PRICE] |
| ↳ add-ons | Ultra +15, Generate in Parts +30, Texture +10, HD Texture +10, Quad +5, Smart Lowpoly +20 (PBR +5 per the texture row) | 8K, Parts and Privacy are member-only (img 02) | Parts come back untextured, then you texture them | — | [T-CRED] img 02 |
| ↳ observed totals | **55** for Best Quality defaults; **65** with 8K | — | — | — | [DEVTO] img 02 |
| **P2.0 generation** | **100 per run, 1–4 variants at the same price** | Every user gets 2 free single-image P2 runs. Multi-view and variants need Pro or higher | 500–25k quads / 500–50k triangles | 10–40 s | [T-SEP][T-P2][T-PIPE] |
| Mesh Edit (P2 only) | 50 per edit | **Pro: 3 free per model. Max/Team: unlimited** | Box-selected region | seconds | [T-P2][T-PIPE] |
| Segmentation v2 | 40 (a May UI screenshot showed 35) | First try free | Simple 3–6, Balanced 6–15, Detailed 15+ parts | < 1 min | [T-CRED][T-SEG] img 04 |
| Fill Parts | Quick Cap is free. AI Completion is "no credits on paid plans" [T-SEG], but the help table says +5 per part [T-CRED] and the UI showed "Part Completion 5" | — | — | instant | [T-SEG][T-CRED] |
| Retopology | 5 base, +5 quad, +30 Smart Low Poly. A 10k retopo was observed at 10: DEVTO used triangles; the T-SCENE screenshot shows Quad at 10,000 | Smart Low Poly v2 is member-only | 500–50,000 faces | seconds | [T-CRED][DEVTO][T-SCENE] |
| Smart UV | 20 per model; retry 10 | 2 free models for everyone. **Pro+: 3 free retries per model** | **≤80,000 triangles / 40,000 quads** | about 5 s | [T-UV] |
| Texture (one-click on a mesh) | 10 base, +5 PBR, +10 HD. The P2 pipeline table lists 20. **8K texture: 20** | 1 free 8K trial | 2K / 4K (the default) / 8K | 8K in under 2 min | [T-CRED][T-PIPE][T-BAT][T-8K] |
| Texture Edit / Magic Brush / Upscale | per action (amount not published) | Upscale needs 8K access | Edits project from the current view only | — | [T-CHAR][H-TEX] |
| **Auto Rig** | **20** | — | Humanoid ≤100,000 triangle faces; T or A pose | seconds to minutes | [T-RIGBLOG] |
| Preset animations | **0** | — | 90+ biped clips | instant | [T-RIGBLOG][D-RET] |
| **Text to Motion** | **20 per clip** | — | 1–10 s | — | [T-RIGBLOG] |
| Multi-stage Motion | 20 per generated motion (estimate: same price as Text to Motion) | — | ≤5 segments, with XY waypoints | — | [T-RIGBLOG][T-PIPE] |
| Generate Multi-Views | not published; the API equivalent (image-to-multiview) costs 10 | Member feature | 4 views | — | [LOCAL] (Studio price: estimate) |
| Image generation | Pro: "unlimited access", standard price. Max: 20 free per day, then 80 % off. Team: free | — | — | — | [T-PRICE] |
| Full P2 character pipeline | **≈180 (≈ $1.80)**: mesh 100 + UV 20 + texture 20 + rig 20 + motion 20 | — | — | under 10 min | [T-PIPE] |

**Plans** [T-PRICE] (prices are annual billing):

| Plan | Price | Credits / month | Concurrent tasks | Notes |
|---|---|---|---|---|
| Free | $0 | 200 | 1 | Public, non-commercial; 15 exports of H2.5 only |
| Pro | $20 / mo ($240 / yr) | 3,000 | 10 | Private models, commercial use, batch of 10, 7-day history |
| Max | $90 / mo | 25,000 | 100 | Unlimited 8K, unlimited free retries, batch of 30 |
| Team | $55 / seat | 90,000 | 200 | — |

**Credit rules:**
- Extra credits cost $10 per 1,000 [T-PRICE].
- Monthly credits expire at reset. Purchased credits never expire. Free credits are spent first, then subscription credits, then purchased ones [H-EXPIRE][H-ORDER].
- Credits are charged only on success. A failed task, or one stuck for more than 15 minutes, is refunded within 1 h [H-REFUND][H-FAIL].

## 5. Export and formats

| Item | Facts | Source |
|---|---|---|
| Formats | GLB, FBX, OBJ, STL, USD/USDZ, 3MF | [H-FMT][H-DCC] |
| FBX presets | **Blender / Mixamo / 3dsmax** | img 07 |
| Dialog options | File Name; Format; **Texture Resolution** (2K / 4K / 8K); **Export Skeleton**; **Number of Animations** with **Choose Animations** (multi-select, Select All); **Animation stay in Place**; **Send To** (DCC Bridge) or **Export** | img 07, [T-CHAR] |
| Pivot / scale / orientation | Export settings manage scale, orientation and pivot. A bottom-center pivot is recommended for characters | [80LV][CGTW] |
| Quads | Survive **only in FBX**. OBJ and GLB triangulate | [H-SMI][H-DCC] |
| Animations | GLB (recommended) or FBX carry several clips. Turn on "Include/Export Animations". In Blender each clip becomes its own Action | [H-MULTIANIM] |
| Axis | Tripo exports Y-up, the same as Godot and glTF | [H-DCC] |
| Raw scale | Our H3.1 GLBs came out with the longest side at 0.978–0.983 units, i.e. normalized to about 1 m. Always rescale | [LOCAL] |
| PBR maps | BaseColor + Normal + ORM. With 8K the BaseColor is 8192², Normal and ORM 4096². **No emissive map** (estimate, inferred from that list) | [T-8K] |
| Vertex colours | OBJ export option | [CGTW] |
| DCC Bridge | Blender 4.1+, Unity 2021.3+, UE 5.4+, **Godot 4.6+** (copy into `addons/`), Maya, 3ds Max, ZBrush, Cocos and others. Browsers: Chrome/Edge 116+ or Opera 102+. Editor mode only; connects to the first instance opened | [H-DCC][T-GBR] |
| Godot Bridge import defaults | Pivot center-bottom; texture resolution at the current maximum; materials created automatically; asset placed automatically. To send animations, select them in the Export panel | [T-GBR] |

## 6. Rigging and animation

### 6.1 Rig types

| Studio choice | Algorithm | What you get | Presets |
|---|---|---|---|
| **Humanoid** | Rebuilt humanoid rig (Sept 2026). Probably the API's rig v3.0 `v3.0-20260909`, which has the same 5 skeleton conventions (estimate) | Full body plus **hand bones (finger level)**; better binding at shoulders, elbows, knees and fingers | Skeleton preset: **UE5 Mannequin, Mixamo, VRM 1.0, Unity Humanoid (Compatible), ActorCore** [T-RIGBLOG][T-PIPE][img 05] |
| **Other** | v2.5 algorithm | Non-humanoid skeleton; no engine-specific presets | The API's v2.5 rig types are quadruped, hexapod, octopod, avian, serpentine, aquatic and others [D-RIG]. That "Other" auto-detects among them is my estimate [T-RIGBLOG] |

**Limits:**
- Humanoids up to **100,000 triangle faces**, in **T- or A-pose** [T-RIGBLOG]. Spatial Insider retopologized a dense scan to about 18,000 faces before rigging it [SPATIAL].
- The help center is stricter: auto-rig "currently supports **T-pose humanoid characters and standard standing quadruped animals only**". Non-standard poses and abstract shapes "may not rig correctly" [H-UPANIM].
- Users report "Auto-Rig is currently not supported for this model" errors and stray extra bones around the feet [RD-RIG].
- One user built the serpent bone chain by hand in Blender [RD-RIG].

### 6.2 Animation library

**Humanoid presets: free, about 90 clips.** The Studio grid (img 06) shows the API rig v1.0 biped list [D-RET]. Clips useful for this game:
- **Locomotion:** idle, walk, run, run_upstairs, turn, jump, jump_down, fall, climb, flip, look_around, wait, swagger, standing_relax.
- **Combat:** box_01–03, front_kick_01–02, slash, shoot, fire, cast_a_spell, hurt, hit_to_body_01–02, hit_to_head, hit_to_side, hit_to_stomach, flee_01–02.
- **Emotes / outros:** victory_celebration, defeat_02–03, angry_01–03, scared_01–02, afraid.

**Rig v2.5 / v3.0 presets** (API) [D-RET]:
- Biped: idle, walk, run, dive, climb, jump, slash, shoot, hurt, fall, turn.
- Quadruped: walk. Hexapod: walk. Octopod: walk.
- Serpentine: march. Aquatic: march.
- **Avian and others: none.** The CLI notes the same: a chain stops after the rig because there is no preset [CLI].

**AI motion:**
- **Text to Motion:** 1–10 s, 20 credits, prompted in "Create Your Own Animation" (pencil tab). The video tab is "Coming Soon" [T-RIGBLOG][img 06].
- **Multi-stage Motion:** Start → Point A → Add Keyframe, up to 5 segments; drag XY waypoints to set direction. It previews on a mannequin, then **Apply** puts it on your model [SPATIAL][T-PIPE].
- Every published Text to Motion and Multi-stage example uses a humanoid. Assume both are humanoid-only (estimate).

**Getting the clips out:** select every clip under **Choose Animations**. Turn **Animation stay in Place** ON for locomotion, so game code drives movement [img 07][CLI].

### 6.3 Godot implications

- glTF is Godot's recommended import format. FBX imports through ufbx [GD-FMT].
- **Retargeting:**
  - Path: Advanced Import Settings → Skeleton3D → Retarget → BoneMap + **SkeletonProfileHumanoid** (56 bones, named Hips / Spine / Chest / UpperChest / LeftUpperArm …).
  - Auto-mapping matches bone names by pattern, so use common English names. Magenta or red marks show bad mappings [GD-RT][GD-SPH].
  - My pick is "Unity Humanoid Compatible", then Mixamo. Tripo's exact bone names are unverified (estimate).
- **Pose:** the reference pose is a T-pose facing +Z. For A-pose models, enable **Fix Silhouette** [GD-RT].
- **Looping:** clips whose names start or end with `loop` or `cycle` import as looping [GD-LOOP].
- **LOD:** Godot builds mesh LODs automatically on import for glTF, FBX and .blend. Do not spend Tripo variants on LODs [GD-LOD].

## 7. Web workflow per asset (what to click, in order)

### 7.0 One-time setup (user, about 15 min)

1. Open **studio.tripo3d.ai** in Chrome 116+ (the bridges need it) [T-GBR]. Check the plan is **Pro or higher**: multi-view, variants, Private, commercial use [T-PRICE][T-P2].
2. Model panel → Members Only → **Privacy → Private** (not "Sharing Only" or public).
   - A public model grants Tripo a perpetual, worldwide licence to display your input and output [H-COMM].
   - Paid users' inputs and outputs are not used for training [H-TRAIN].
   - The setting is remembered [T-APR].
3. **DCC Bridge** (top right):
   - Install **Godot**: copy the plugin folder into `res://addons/`, then Project → Project Settings → Plugins → enable; the server starts automatically [T-GBR].
   - Install **Blender**: Preferences → Add-ons → Install from Disk; the bridge lists Blender 4.1+ [H-DCC]. Blender 5.2 compatibility is unverified; if it fails, use manual FBX export (§12).
4. Set defaults once (they are remembered) [T-APR]:
   - Smart Mesh: Topology **Quad**, AI Model **P2.0**.
   - HD Model: Ultra ON, Texture **4K**, **Remove Lighting ON**, PBR ON.
   - Export: **FBX + Blender preset**, **Export Skeleton ON**, Texture Resolution **4K** (2K for props).

### 7.1 Reference preparation (every asset)

1. **Image** (left toolbar) → model **GPT-Image-2.5 Sunburst** or **Nano Banana Pro** [T-CHAR][T-SUN] → template:
   - **T Pose** for bipeds.
   - **Character Extraction** for mech parts.
   - **Asset Extraction** for props.
   - **3D Enhance** if the concept is flat [T-SUN][H-SMI].
2. **Edit Image** until the image passes this checklist [H-BETTER][H-SMI][T-CHAR]:
   - Plain white or flat grey background.
   - Even, diffuse light.
   - Subject fills **70–90 %** of the frame, centred, with a margin on all four sides.
   - **≥1024 × 1024 px** (below 512 px the geometry turns to mush), saved as **PNG**.
   - No glass or chrome, and no motion blur.
3. **Generate Multi-Views** → check the 4 views:
   - Same pose, scale, light and design.
   - No top-down or bottom-up view.
   - If you only use two, a **front 3/4 + back 3/4** pair is the most reliable [H-MV].
4. Hover the approved image → **Generate 3D** → **Smart Topology Mesh** [T-CHAR].

### 7.2 Workflow A — hero mech (part-wise P2.0)

| Step | Click path / setting | Why | Source |
|---|---|---|---|
| A1 | Concept: front T-pose plus back view (from art direction) → **Character Extraction** → one image per part (§8a table). Mirror the left and right parts instead of generating both | Each part gets its own budget, texture and retries | [T-CHAR][T-SUN][H-SMI] |
| A2 | Per part: **Generate Multi-Views** → approve the 4 views → Model → **Smart Mesh** → AI Model **P2.0** → General Settings → Topology **Quad** → Members Only: **Number of Generation 4** → **Customize Poly Counts** → **Use Same Polygon Count OFF** → enter 4 budgets (§8a) → **Generate (100)** | 4 budgets for the price of one; keep the lowest one whose silhouette holds | [T-SCENE][T-SEP] img 01 |
| A3 | Inspect each variant: wireframe on; **Hologram** shader for inner faces; view from the top | P2 is quad-*dominant*; triangles stay on complex contours | [H-SMI][T-SCENE] |
| A4 | Local defect (hole, collapsed hand, broken V-fin) → bottom menu **Edit Mesh** → drag the yellow box faces to enclose only the bad region → **Retry Selection** → **Save** | Fixes one region and keeps the rest. 3 free per model on Pro | [T-CHAR][T-P2] img 08 |
| A5 | Same region fails twice → stop. Rebuild it in Blender | "Another identical generation will miss it again" | [H-SMI] |
| A6 | **Smart UV** → **Unwrap UV (20)** → read Utilization (the example shows 73.2 %) → up to 3 free **Retry** → **Save** | Large, structure-aligned islands for decals and paint-over. Utilization ≥70 % (estimate) | [T-UV][T-CHAR] |
| A7 | **Texture** → reference auto-loaded (if not, re-upload it) → **Remove Lighting ON** → 4K (8K only for head, chest and backpack) → Generate → **PBR** (normal, roughness, metalness) → **Texture Edit** for local fixes | Edits project from the current view only | [T-CHAR][T-RL][D-TEX] |
| A8 | **Export** → FBX → **Blender** preset → Texture 4K → Export (or **Send To** Blender) | Keeps the quads | img 07 [H-SMI] |
| A9 | *Motion prototype (optional):* in Blender, merge the T-posed mech to ≤100k triangles and export → Studio **Rig** → **Upload 3D Model** → **Humanoid** → Skeleton Preset **Unity Humanoid Compatible** → **Auto Rig (20)** → **Animate** → presets (idle, walk, run, jump, slash, shoot, hurt, fall, turn) → **Export** FBX + Export Skeleton + Select All + **stay in Place ON** for locomotion | A placed skeleton and placeholder motion, not final skinning | [T-CHAR][T-RIGBLOG][SPATIAL] |
| A10 | Blender (M78 brief) — see §8a "rig" row | Rigid mech skinning | [CADA][GD-BA] |

### 7.3 Workflow B — creature enemy with rig and animations

| Step | Click path / setting | Source |
|---|---|---|
| B1 | Design for a rig type Tripo supports. **Biped** (Humanoid) is best: full preset library plus Text to Motion. **Standing quadruped** (Other) is second. Avoid wing-led or serpentine silhouettes unless you will animate them in Blender | [H-UPANIM][D-RET] |
| B2 | Concept pose. Bipeds: **T Pose template** (arms clear of the body). Quadrupeds: neutral four-leg stand. Either way: no crouch, tail clear of the legs, mouth closed (estimate) | [SPATIAL][T-CHAR] |
| B3 | Generate Multi-Views (2–4 views). Optional **edge-flow guide**: Nano Banana Pro or GPT Image 2.5 prompt "grey clay render, crisp black quad wireframe, clean edge flow, A-pose, three-quarter view". Start the budget near the wireframe's visible density | [H-SMI] |
| B4 | Smart Mesh → P2.0 → **Quad** → 4 variants. Grunt: **4k / 6k / 8k / 10k quads**. Boss: **10k / 15k / 20k / 25k** (estimate) | [D-P2] |
| B5 | Edit Mesh for local failures → Smart UV → Texture (Remove Lighting ON) → PBR | [T-PIPE] |
| B6 | **Rig** → Rigging Type **Humanoid** → Skeleton **Unity Humanoid Compatible** (or Mixamo) → **Auto Rig (20)**. For non-humanoids choose **Other** | img 05 [T-RIGBLOG] |
| B7 | **Animate** → Preset tab: pick 8–15 free clips (idle, walk, run, box_01–03, front_kick_01, slash, shoot, cast_a_spell, hurt, hit_to_*, fall, flee_01, defeat_02). **Text to Motion** (20 each): monster signatures with an explicit duration, e.g. "lunges two steps, slams both claws into the ground, recoils" at 2 s. **Multi-stage Motion** for windup → strike → recover | [D-RET][T-RIGBLOG][SPATIAL] |
| B8 | **Export** FBX (or GLB) → Export Skeleton ON → **Choose Animations → Select All** → **stay in Place ON** (locomotion). Or **Send To** Godot | img 07 [H-MULTIANIM][T-GBR] |
| B9 | API fallback for hexapod, octopod or serpentine walk/march clips: `tripo anim rig --rig-type hexapod` + `retarget preset:hexapod:walk`. Costs API credits (rig 25), not web credits | [D-RIG][D-RET][CLI][H-API] |

### 7.4 Workflow C — props

| Step | Click path / setting | Source |
|---|---|---|
| C1 | Prop sheet or scene concept → **Asset Extraction** → **Cutout** → select up to 10 images → **Batch to 3D** | [T-SUN][CGCH] |
| C2 | Smart Mesh → P2.0 → **Triangle** for static props (quads only help editing) → budgets in §8c. Use 4 variants only on hero props | [T-PROP][T-SCENE] |
| C3 | Texture → Remove Lighting ON → **2K** (4K only on hero props) → PBR | [T-RL][T-8K] |
| C4 | **Smart UV** only if the prop needs tiling, decals or material variants (one UV layout can carry three colourways) | [T-PROP][T-UV] |
| C5 | **Send To → Godot** (bridge: center-bottom pivot, automatic materials) or Export GLB. In Godot set the texture import **Process > Size Limit = 2048** | [T-GBR][GD-IMG] |
| C6 | Glass, visors and neon: Tripo makes glass solid and has no emissive map. Assign glass and emission materials in Blender or Godot | [H-SMI][T-8K] |

### 7.5 QA gates before an asset leaves Tripo or Blender

1. Silhouette from front, side, back **and top**. A top view caught the 7.5°/14.8° V-swept arms on our last job [LOCAL].
2. Hologram view: no inner body or layer faces [H-SMI].
3. Blender: count non-manifold edges and holes.
   - Weld with **Merge by Distance** at a tight threshold (0.1 mm at 1-unit scale, estimate) [H-SMI].
   - Never recalc normals on open meshes; check signed volume instead [LOCAL].
4. Lit close-ups of hands, joints and thrusters; look for fused fingers (seen before [LOCAL]).
5. Triangle count within the §8 budget. UV: no 1,000-island atlases (our H3.1 body had about 1,200 fragments [LOCAL]).
6. Godot: the BoneMap shows no red or magenta; clips loop where named; texture size within the limit [GD-RT][GD-LOOP][GD-IMG].

## 8. Recommendations

### 8a. Hero mech (original "heroic tricolor" humanoid, about 16 m in-world)

**Route:** P2.0 Quad, part by part (Workflow A). Optionally, generate one **H3.1 Ultra + Generate in Parts** full-body detail source (about 70 credits untextured, 25 + 15 + 30 [T-CRED]). Use it only to bake normal maps onto the P2 parts and for key art. The in-game mesh stays P2.

| Part (mirror the L/R pairs) | Views | 4-variant quad spread | Expected pick | ≈ Triangles | Texture |
|---|---|---|---|---|---|
| Head + V-fin + sensor visor | 4 | 2,000 / 3,000 / 4,500 / 6,000 | 3,000 | 6,000 | 4K (8K source) |
| Chest core + cockpit hatch + exposed frame | 4 | 5,000 / 8,000 / 11,000 / 14,000 | 9,000 | 18,000 | 4K |
| Waist + skirt armor | 4 | 2,000 / 3,500 / 5,000 / 7,000 | 3,500 | 7,000 | 2K |
| Backpack + thrusters + binders (seen most in third person) | 4 | 4,000 / 6,000 / 9,000 / 12,000 | 7,000 | 14,000 | 4K |
| Shoulder armor ×2 | 4 | 1,500 / 2,500 / 3,500 / 5,000 | 2,500 | 10,000 | 2K |
| Arm ×2 (inner frame visible) | 4 | 3,000 / 4,500 / 6,000 / 8,000 | 4,500 | 18,000 | 2K |
| Hand, open + grip poses (2 runs) ×2 | 2–4 | 1,000 / 1,500 / 2,000 / 3,000 | 1,500 | 6,000 | 2K |
| Leg ×2 (with ankle thrusters) | 4 | 3,500 / 5,000 / 7,000 / 10,000 | 5,500 | 22,000 | 2K–4K |
| Beam rifle | 4 | 1,500 / 2,500 / 3,500 / 5,000 | 2,500 | 5,000 | 2K |
| Shield | 2–4 | 800 / 1,200 / 1,800 / 2,500 | 1,200 | 2,400 | 2K |
| Saber hilt (the blade is a VFX mesh) | 2 | 500 / 700 / 900 / 1,200 (500 is the P2 minimum) | 600 | 1,200 | 1K |
| **Total** | | | | **≈110k triangles LOD0 (estimate)** | |

All spreads, picks and triangle counts in this table are my estimate. P2's 500–25k quad range is from [T-P2].

**Mech-specific rules:**
- **Prompts:** describe the parts, never franchise names. You are responsible for the source material being free of copyright disputes [H-COMM].
  - A Taiwanese tutorial's mech prompt literally names "Gundam" [CGTW]. Do not copy it.
  - Do copy its useful wording: "wings completely separate from the main torso geometry", "highly defined boundaries between armor parts".
- **Thin parts** are generated as their own parts or modelled in Blender: V-fin, antennas, cables, beam blades. Strands thinner than a few pixels disconnect at low budgets and turn into "cards" at high budgets [H-SMI].
- **Visor and canopy glass** come back solid; assign the material later [H-SMI].
- **P2 builds parts separately and does not weld them** [H-SMI]. For a mech that is a feature: armor plates are already separate rigid pieces.
- **Rig (Blender, M78):**
  - Keep the Tripo humanoid bone placement from A9.
  - Weight every armor and frame piece **100 % to one bone** so plates do not bend like cloth [CADA][RD-HS].
  - Add extra bones for thruster flaps, shoulder pods, V-fin and backpack binders.
  - Export glTF. In Godot, mount the rifle, shield and saber with **BoneAttachment3D** [GD-BA].
- **Credits (estimate):**
  - 12 P2 runs × 100 = 1,200.
  - Smart UV and texture: about 480.
  - Rig 20, Text to Motion about 200, multi-view about 120.
  - That is about 2,000; with 50 % re-rolls about 3,000.

### 8b. Creature enemies (biomechanical, rigged and animated)

**Roster shape** (estimate, driven by what Tripo can rig) [H-UPANIM][D-RET]:

| Archetype | Tripo rig | Animation source | Budget (triangles) |
|---|---|---|---|
| Biped brute or soldier (2–3 types) | Humanoid, Unity preset | Preset library (combat set) + 3–5 Text to Motion signature attacks | 8–20k (estimate) |
| Quadruped stalker or hound (1–2 types) | Other (quadruped) | Preset quadruped walk + Blender or procedural attacks | 8–16k (estimate) |
| Hexapod or swarm drone (1 type) | Other, or API hexapod | Preset hexapod walk (API) + procedural | 2–6k (estimate) |
| Boss (biped, 2–3× scale) | Humanoid | Presets + Multi-stage combos | 30–50k (estimate) |

**Design rules for rig-ability:**
- Limbs clearly separated.
- Body masses symmetric.
- No more than 4 limbs, except the hexapod.
- Biomech "cables" kept as surface relief, not free strands [H-SMI].

**Preset-to-gameplay mapping** (estimate):

| Gameplay state | Preset clip |
|---|---|
| idle | idle / standing_relax |
| patrol | walk |
| charge | run |
| light attack | box_01 / box_02 |
| heavy attack | front_kick_01 / slash |
| ranged attack | shoot / fire / cast_a_spell |
| hit react (by direction) | hit_to_body_01 / hit_to_head / hit_to_side |
| stagger | hurt |
| death | fall / defeat_02 |

**Godot:** every clip comes in one file per enemy. Rename the locomotion clips with the `_loop` token [GD-LOOP]. Use in-place clips; CharacterBody3D moves the enemy [CLI].

**Credits per type (estimate):** P2 100, UV 20, texture 20, rig 20, 5 Text to Motion = 100. That is about 260, or about 400 with re-rolls.

### 8c. Props (city dressing, vehicles, debris)

| Class | Topology | Faces | Texture | Variants | Example |
|---|---|---|---|---|---|
| Small clutter | Triangle | 500–1,500 | 1K–2K | 1 | Cans, signs, cones |
| Medium | Triangle | 2,000–6,000 | 2K | 1–2 | Vending machine, barricade, crate |
| Large / hero | Quad if it will be edited or animated | 6,000–15,000 | 4K | 4 | Hover-car, mech hangar crane, a destructible tank |

All numbers in this table are my estimate. The P2 minimum is 500 faces [T-P2].

- Use **Batch to 3D** (up to 10 images per batch) [T-SUN].
- Use the Godot bridge for direct placement [T-GBR].
- Leave building-scale geometry to procedural Blender; Tripo is for objects, not levels (estimate, matching project scope).
- **Credits (estimate):** P2 100 + texture 20 (+ UV 20) = 120–140 per prop.

## 9. Input-art guide for mechs and monsters

| Rule | Mech | Creature | Source |
|---|---|---|---|
| Framing | Part fills 70–90 % of the frame, centred, with a margin | Same | [H-SMI][T-CHAR] |
| Resolution | ≥1024², PNG | ≥1024², PNG | [H-SMI][H-BETTER] |
| Light | Even, no hard highlights (they bake into texture or read as geometry) | Same; wet or glossy skin causes trouble | [H-BETTER][T-RL] |
| Pose | T-pose for the full-body concept; neutral pose for single parts | Biped T or A; quadruped neutral stand | [T-RIGBLOG][SPATIAL] |
| Views | 4 matched views (front / left / back / right); for complex parts, never fewer than front + side | 2–4 views; front 3/4 + back 3/4 if only two | [H-MV] |
| Consistency | Identical pose, scale, light and design in every view, or the mesh leans or drifts | Same | [H-MV][H-SMI] |
| Symmetry | Neutral, centred front view; off-centre crops make lopsided meshes | Same | [H-SMI] |
| Split | One part per image; multiple subjects merge into one mesh | Separate body from armor or weapons if they will swap | [H-BETTER][H-SMI] |
| Avoid | Glass, chrome, steep top-down views | Hair, fur, thin tendrils | [H-SMI][H-BETTER] |
| Templates | Character Extraction, 3D Enhance | T Pose, Character Completion | [T-SUN] |
| Prompt order | subject → materials and key details → style; decide the pose before generating; change one thing per iteration | Same | [T-CHAR] |

## 10. Failure modes → fixes

| Symptom | Cause | Fix in Tripo | Fix in Blender | Source |
|---|---|---|---|---|
| Flat, soft, missing detail | Small subject, blur, below 512 px, compressed JPEG | Re-frame, use PNG ≥1024, run the **3D Enhance** template | — | [H-SMI] |
| Lumpy, noisy surface | Busy background, noise | Plain background; **AI Complete** toggle (HD) | — | [H-SMI] img 02 |
| Back or side invented (one ponytail became two) | Single view | Multi-view, 2–4 views | — | [H-SMI][H-MV] |
| Symmetric subject comes out lopsided | Off-centre or 3/4 crop, mismatched views | Centred front view, matched scale | Mirror half | [H-SMI] |
| Component misplaced (wing) | Ambiguous view | Matched multi-view | Move or rebuild | [H-SMI] |
| **Complex assembly loses pieces (mech upper leg missing)** | Too many parts for one budget | **Split into components**, or raise the polycount | — | [H-SMI] |
| Thin parts break or become cards | Below pixel scale | Lower the budget or remove them from the reference | Model them separately | [H-SMI] |
| Glass comes out solid | No readable surface | Opaque stand-in | Assign the material | [H-SMI] |
| Polycount too low or too high | Wrong budget | 4-variant spread, then a tighter round | — | [H-SMI] |
| Local hole, collapsed hand, extra part | Local failure | **Edit Mesh** | Delete and rebuild | [H-SMI][T-CHAR] |
| Loops ignore joints or panels | No topology hint | Wireframe guide image matched to the budget | Re-route loops at elbow, knee, shoulder, neck | [H-SMI] |
| Holes, non-manifold edges, inner faces | Generator artefacts | Hologram check; lower the budget | Select Non Manifold, delete, fill | [H-SMI] |
| Parts look joined but are not welded | P2 part-aware output | — | Merge by Distance (tight) | [H-SMI] |
| Quads gone after export | GLB or OBJ triangulate | Export FBX | — | [H-SMI] |
| Arms swept back in a V | Side views drew swept arms | Fix the side views | Measure axes in top view; shear | [LOCAL] |
| Fused "mitten" fingers | Full-body generation | Generate hands separately | Rebuild the fingers | [LOCAL] |
| Fragmented atlas (~1,200 islands) | H3.1 auto-unwrap | **Smart UV** (≤80k triangles) or P2 | Re-unwrap and bake | [LOCAL][T-UV] |
| "Auto-Rig not supported" | Pose, shape or face count | T or A pose, ≤100k faces, Retopo first | Rig manually | [RD-RIG][T-RIGBLOG] |
| Extra foot bones or odd joints | Auto-skeleton guess | Re-rig | Delete or merge bones | [RD-RIG] |
| Rubbery armor when posed | Smooth skin weights | — | Rigid 100 % weights | [CADA] |
| Task stuck | Server load | After 15 min it is refunded within 1 h; clear the cache or switch browser | — | [H-FAIL][H-SMI] |

## 11. Credit plan for the demo (estimate)

| Block | Count | Each | Total |
|---|---|---|---|
| Hero mech (incl. re-rolls) | 1 | ~3,000 | 3,000 |
| Enemy types | 6 | ~400 | 2,400 |
| Boss | 1 | ~800 | 800 |
| Props | 25 | ~130 | 3,250 |
| Contingency | — | — | 500 |
| **Total** | | | **≈10,000 credits ≈ $100** |

Every figure in this table is my estimate; the dollar figure uses the $10 per 1,000 rate [T-PRICE].

Pro's 3,000 credits a month do not cover this. Max's 25,000 do. Bought credits never expire [T-PRICE][H-EXPIRE].

## 12. Risks and unknowns

1. **Manual bottleneck.** Cloudflare blocks headless Studio access, so every web step is user clicks [LOCAL]. Batch the work: prepare kits of 10 assets for **Batch to 3D** [T-SUN].
2. **Price drift.**
   - P2 was 65 in preview and is 100 now.
   - Segmentation showed 35 and is listed at 40.
   - Part Completion is both "free" and "+5" depending on the page.
   - Text-to-Motion and multi-view prices are unpublished for some steps [T-P2][T-BAT][T-SEG][T-CRED].
3. **Rig coverage.**
   - Non-humanoids get only walk or march presets.
   - Avian and "others" types get none [D-RET].
   - Text to Motion probably works on humanoids only (estimate).
   - The help center only promises T-pose humanoids and standing quadrupeds [H-UPANIM].
4. **Mech skinning.** Tripo advertises smooth, natural deformation at shoulders, elbows, knees and fingers [T-PIPE]. Rigid armor needs rigid weights instead [CADA], so re-weighting in Blender is mandatory (estimate of effort: about 1 h per mech for an M78 agent).
5. **Bridge versions.**
   - The Blender bridge is documented for 4.1+, and our Blender 5.2 is untested [H-DCC].
   - The Godot bridge imports at the "current maximum" texture resolution, so set Size Limit [T-GBR][GD-IMG].
6. **Godot retarget naming.** Matching the Unity preset's names to SkeletonProfileHumanoid is unverified. Fallback: map the bones by hand in BoneMap [GD-RT] (estimate).
7. **IP and privacy.** Use Private models [H-COMM]. No franchise names in prompts.
8. **Source freshness.**
   - The Tripo pages were read from Wayback snapshots of 2026-10-16 to 19.
   - YouTube and Reddit bodies were unreadable (login or 403). Their claims come from search snippets only [RD-RIG].
   - The Studio UI may have moved since those snapshots.
9. **P2 quirks.**
   - Parts are not welded.
   - Detected symmetry is per part, not a vertex mirror.
   - Budgets below about 150 faces for simple shapes or 250 for complex ones are not recommended [H-SMI][D-P2].

## 13. Sources

Tripo site pages were read via web.archive.org snapshots (2026-10-16 to 19) because the live site returns 403.

| Tag | URL |
|---|---|
| T-CRED | https://www.tripo3d.ai/help/credit/how-do-credits-work |
| T-PRICE | https://www.tripo3d.ai/pricing |
| T-RIGBLOG | https://www.tripo3d.ai/blog/rigging-animation |
| T-PIPE | https://www.tripo3d.ai/blog/3d-game-pipeline |
| T-SEP | https://www.tripo3d.ai/blog/tripo-september-update |
| T-P2 | https://www.tripo3d.ai/blog/tripo-p2-0-preview |
| T-P2VM | https://www.tripo3d.ai/blog/tripo-p2-vs-meshy-t2 |
| T-UV | https://www.tripo3d.ai/blog/smart-uv |
| T-CHAR | https://www.tripo3d.ai/blog/mesh-game-character-p-2 |
| T-PROP | https://www.tripo3d.ai/blog/game-ready-prop-p-2 |
| T-SCENE | https://www.tripo3d.ai/blog/workflow-game-scene |
| T-GBR | https://www.tripo3d.ai/blog/tripo-dcc-bridge-for-godot |
| T-RL | https://www.tripo3d.ai/blog/tripo-texture-remove-lighting |
| T-8K | https://www.tripo3d.ai/blog/tripo-8k-texture |
| T-SEG | https://www.tripo3d.ai/blog/tripo-segmentation-v2 |
| T-SUN | https://www.tripo3d.ai/blog/gpt-image-2-5-sunburst-tripo |
| T-BAT | https://www.tripo3d.ai/blog/tripo-gpt-astra-bat-workflow |
| T-TUT25 | https://www.tripo3d.ai/blog/tripo-studio-tutorial-english |
| T-APR / T-MAY | https://www.tripo3d.ai/blog/tripo-april-update · https://www.tripo3d.ai/blog/may-update-on-tripo |
| H-I2M / H-T2M | https://www.tripo3d.ai/help/features/how-to-use-the-image-to-3d-feature · …/how-to-use-the-text-to-3d-feature |
| H-BETTER | https://www.tripo3d.ai/help/features/how-to-get-better-image-to-3d-results |
| H-MV | https://www.tripo3d.ai/help/features/how-to-use-multi-view-input-effectively |
| H-SMI | https://www.tripo3d.ai/help/features/how-to-handle-common-issues---smart-mesh |
| H-SM | https://www.tripo3d.ai/help/features/what-is-smart-mesh |
| H-DCC | https://www.tripo3d.ai/help/features/how-to-export-and-import-to-dcc-tools |
| H-MULTIANIM | https://www.tripo3d.ai/help/features/how-do-i-export-multiple-animations-into-a-single-file-for-blender |
| H-UPANIM | https://www.tripo3d.ai/help/features/is-it-possible-to-upload-my-existing-model-for-animation |
| H-TEX | https://www.tripo3d.ai/help/features/can-tripo-generate-high-quality-textures-for-3d-models |
| H-FAIL / H-REFUND | https://www.tripo3d.ai/help/features/why-did-my-generation-fail-or-get-stuck · https://www.tripo3d.ai/help/credit/if-one-generation-fails-will-my-credits-still-be-deducted |
| H-EXPIRE / H-ORDER | https://www.tripo3d.ai/help/credit/do-my-credits-expire · https://www.tripo3d.ai/help/credit/what-type-of-credits-are-consumed-first |
| H-FMT | https://www.tripo3d.ai/help/getting-started/what-3d-file-formats-do-you-support |
| H-API | https://www.tripo3d.ai/help/api-plugins/tripo-studiotripo-api |
| H-COMM / H-TRAIN | https://www.tripo3d.ai/help/privacy-policy/can-i-use-models-commercially · …/will-paid-users-inputs-and-outputs-be-used-for-ai-training |
| D-H31 / D-P2 / D-TEX | https://developers.tripo3d.ai/en/models/v3-1 · …/models/p2 · …/models/texture |
| D-RIG / D-RET | https://developers.tripo3d.ai/en/docs/animations-rig · https://developers.tripo3d.ai/en/docs/animations-retarget |
| CLI | tripo-cli 0.8.1 bundled docs (`skill/commands/process.md`, `generate.md`); https://github.com/vast-enterprise/Tripo-API-CLI |
| DEVTO | https://dev.to/rohanmori/tripo-ai-review-2026-i-tested-the-free-3d-model-generator-end-to-end-2ok7 |
| SPATIAL | https://spatialinsiders.com/stories/tripo-rigging-animation-text-to-motion |
| CGCH | https://www.cgchannel.com/2026/10/tripo-integrates-gpt-image-2-5-sunburst-into-its-image-to-3d-workflow/ (sponsored) |
| 80LV | https://80.lv/articles/how-tripo-p2-0-astra-work-together-in-blender-and-unity |
| CGTW | https://www.cg.com.tw/TripoAI/ |
| BILI | https://www.bilibili.com/video/BV1GS8u6dEAw/ |
| RD-RIG | Search snippets only: https://www.reddit.com/r/Tripo_ai/comments/1tkjb6x/ · …/1urldiy/ · …/1sto0d8/ · https://www.reddit.com/r/Tripo_ai/ |
| RD-HS | https://www.reddit.com/r/blenderhelp/comments/138eo4m/ (snippet) |
| CADA | https://cada-edu.com/guides/rigging-in-blender-how-to-rig-a-character-for-games |
| GD-RT | https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/retargeting_3d_skeletons.html |
| GD-SPH | https://docs.godotengine.org/en/stable/classes/class_skeletonprofilehumanoid.html |
| GD-FMT | https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html |
| GD-LOOP | https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/node_type_customization.html |
| GD-BA | https://docs.godotengine.org/en/stable/classes/class_boneattachment3d.html |
| GD-LOD | https://docs.godotengine.org/en/stable/tutorials/3d/mesh_lod.html |
| GD-IMG | https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_images.html |
| LOCAL | `~/m/tripo-char/out/{h31-ultra,head,weapon}/tripo-out/*/model.glb` and `task.json` (2026-10-29: 1.66–1.89M triangles, longest side 0.98 units, 60–70 API credits); memory notes `awaken-char-3d-job.md`, `tripo-v3-api-pipeline.md` |
