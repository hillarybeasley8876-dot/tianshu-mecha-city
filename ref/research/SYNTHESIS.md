# SYNTHESIS — design proposal for SPEC v2 (天枢 TIANSHU · Mecha City demo)

Key `synthesis` · 2026-11-01 · for the lead (Claude Opus).

**Inputs**
- The 8 dossiers in `ref/research/` and the image contact sheets.
- The lead docs: SPEC, FEEL, MAP, ART, CONTRACTS, PLAN.
- `status/*.md`, `reviews/*-r1.md`, the Tripo outputs (`art/tripo/_hero_parts.jpg`, `_monsters.jpg`) and the key art (`art/concept/keyart/_sheet.jpg`).
- The `city-art-direction` dossier was never delivered (its image folder is empty). §8 rebuilds that ground from ART.md, the key art and new sources.
- **Snapshot:** written against the lead's 19:40 commit, which includes the new boss, flow, city, hud and audio briefs. Where a brief already decides something, this proposal follows it unless the research argues otherwise; those cases are flagged.

**Conventions**
- Dossier tags, with § numbers (each dossier carries the URLs): [MOVE] feel-mech-games · [JUICE] juice-impact · [KIT] skills-catalog · [LEVEL] level-design-vertical · [MON] mech-monster-design · [GODOT] godot-tech · [TRIPO] tripo-web · [AUDIO] audio-music.
- r1 = `reviews/<unit>-r1.md`. New sources [X1–X6] are in §13.
- **(estimate)** = my number · **(calc)** = computed here · **[L]** = run on this machine (`tmp/research/synthesis/`) · ▲ = change vs SPEC v1 · f = frame at 60 fps.

## 0. Conflict register

| # | Topic | Sources | Proposal |
|---|---|---|---|
| K1 | Hero height | 8 m [KIT], ≈ 9 m [JUICE], 16 m [LEVEL][MON][SPEC], 16.5 m [MOVE] | 16.0 m to the crest. KIT/JUICE reach, radii and projectile speeds ×2; times, damage and EN as-is (SPEC scale rule) |
| K2 | Eye / pivot | 11.5 m [MOVE], ≈ 12 m [MON], 12–13 m [LEVEL]; placeholder socket at 9.9 m | eye 12.0 m; 3P pivot 12.5 m (camera r1) |
| K3 | Speeds | walk/run · boost/assault · dash: 6.5/11 · 34/72 · 16 m [MOVE]; 9/15–18 · 50/100 · 35 m [LEVEL]; 44/110 [GODOT][AUDIO] (stale) | keep SPEC 9/16 · 42/84 m/s · 24 m (all tested). Avenues stay 80–96 m as assault lanes; dodge room alone needs 56 m (calc) |
| K4 | Gravity | 19.6 [LEVEL], 25.5 [MOVE], 56 [GODOT, stale] | fall 25.5 m/s²; hop rise 79 (derived); all arc checks use 25.5 |
| K5 | Landing | hard ≥ 15 m/s [MOVE][SPEC] made every hop hard | soft < 25 m/s, hard ≥ 25, `land_heavy` ≥ 32 (mech-move r1) |
| K6 | 3P framing | FOV/arm 55°/28 m [MOVE]; 62°/1.3 H [JUICE]; 70–80°/14–18 m [LEVEL]; 70°/26 m [MON]; r1 asks for "arm 22 m" and "hero 38 % of screen height" | the screen fraction is the spec; the arm is the solver's output (§2.2). At 55°, 38 % needs ≈ 40 m; 22 m gives ≈ 70 % (calc) |
| K7 | Dash FOV punch | +3° [MOVE][SPEC §5] vs +10° [JUICE][FEEL] | +6° in 60 ms, back in 250 ms; chained punches clamp at +10° |
| K8 | Stagger | 2.5 s elites / 4 s bosses [MOVE]; 3/4/5–6 s [JUICE]; 0.8/1.4/2.6/3.4 s [KIT] | KIT (boss brief: Titan 3.4 s), except ▲ Mantis 2.0 s. An elite's ×1.8 window should last "several seconds" (AC6); AC6 players called ⅓ s staggers a cheat [MOVE §1.3, §16.2] |
| K9 | Global time scale | never [KIT §4.11] vs kills/boss [JUICE §2] | local hit-stop by default; global only on FEEL rows marked G (≤ 1 per 150 ms, ≤ 3/s) |
| K10 | Titan | 90 m [MON][SPEC §7] vs 60 m [MAP][boss brief] vs 40–60 m [LEVEL] | 60 m (fits the 320 m deck [LEVEL §4.5]); ▲ fix SPEC §7. Condition: the skyline walk crosses only sectors ≤ 40 m tall, because 48–80 m street walls would hide it. At 1 km it is ≈ 52 px tall at 55° (calc) |
| K11 | Boss place | Spire Plaza [SPEC §8] vs Crown deck [MAP] | Crown (boss brief). SPEC §8's Plaza break-in becomes optional: the boss-gate vista shows the Titan climbing the Spire |
| K12 | Objective | 4 of 6 arenas [LEVEL] vs 3 hives [SPEC][MAP] | 3 hives (A2, A5, A6); escalation by count |
| K13 | Map / Spire | 1.6 km, 600 m [AUDIO][GODOT, stale] vs 1.4 km, 360 m [MAP] | 1.4 km + 200 m ring; Spire 360 m. ▲ Other buildings capped at 240 m ([LEVEL]'s tier D ran to 400 m) |
| K14 | Air range R | 150–250 m [LEVEL][MAP §1], but SPEC's 6 m/s glide sink gives ≈ 280 m from a 40 m apex, and flight ≈ 625 m (calc) | ▲ glide sink 10 m/s → ≈ 170 m from 40 m (calc), restoring R; flight is the EN-paid exception |
| K15 | Hero build | part-wise P2.0 [TRIPO §7.2][MON §4.5] vs whole-body H3.1 + rigged proxy (hero-asset brief) | keep whole-body for v1. Rebuild hands, crest, antennae and blade edges in Blender; P2.0 part-wise only for what fails QA |
| K16 | Backpack | corona ring [MON §2] vs two 3-blade binders (g1 design) | binders, deployed as a halo ring, not a wing spread (§8.4) |
| K17 | Low-HP muffle | LPF 6 / 1.2 kHz [JUICE §11.3] vs 8 / 2.5 kHz [AUDIO §5.3] | 8 / 2.5 kHz; 1.2 kHz only for the 400 ms `hurt_heavy` dip |
| K18 | Settled in code | interpolation on [MOVE §16.4] vs off [GODOT §2.6]; missile life 3 vs 6 s; MON vs ART hexes | off + `max_fps` 60; 6 s; ART palette |

## 1. Pillars and the demo at three time scales

**Pillars**
1. **Heavy legs, instant thrusters.** Mass comes from legs, landings, camera damping and sound. Thrusters answer within 2 f; never add input lag [MOVE §0, §15.2].
2. **Every hit pays off.** Impact → stagger → execution, mark → drones, prime → detonate. The fun action is also the winning action; Mecha BREAK's "爽点和赢点分开了" is the anti-goal [MOVE §0][KIT §3].
3. **The city is the arena.** Five stacked layers, loops not dead ends, a landmark on every horizon. Climbs spend EN that only the ground refills: launch → fight → land → relaunch [LEVEL §0][MOVE §0].
4. **A city under a colossus.** The Titan walks the skyline from second 0. Telegraphs are honest; an intensity director builds and relaxes; the light ages toward storm [JUICE §11][ART §1].

**30 s: the combat atom.** Halo built on "30 seconds of fun… over and over" [X1]. Ours:
- **0–3 s:** from a skybridge (L3), the 7° soft lock finds a Ripper pack on L1 with a Mantis behind it. Rifle taps mark the Mantis.
- **3–6 s:** boost off the edge, then a hard landing with a crater (cancellable from f14). A leap-bite lands inside the dash i-frames → perfect dodge (world 0.3× for 0.35 s). Shockcore pops six Rippers.
- **6–18 s:** Corona Fins strike the marked Mantis. It glints → perfect parry → Return Cut → stagger → Core Rend (+300 EN, +8 % OD, +5 % HP).
- **18–30 s:** boost-slide out, Skyhook to a roof anchor, paint 12 locks on Harriers, missile bloom. Land; the ground refills EN in ≈ 2.6 s.
- **Rhythm:** bursts of ≤ 1.5 s, then ≈ 1 s breaths on the ground, AC6's cadence [MOVE §1.2].

**5 min: a hive assault.**
1. Pick a lane: L1, L2/L3 deck, L0 tunnel, or flight.
2. Five mini-combats, each starting when the previous is half cleared [LEVEL §1.6].
3. The hive's four pods burst, then its core is exposed (flow brief).
4. Collapse: kill_large ×3, stinger, the Titan roars, the sun steps down.
5. 30–45 s of relaxed traversal [JUICE §11.2].

**20 min: the arc.**

| Time | Beat |
|---|---|
| 0:00 | Carrier drop onto the Insertion Pier; the Titan's silhouette crosses the bay ≈ 600 m away |
| 0:30–3:00 | A1 tutorial: Rippers, then one Mantis; contextual prompts |
| 3:00–15:00 | Three hives, any order; roaming packs and Harrier patrols between; OD fills every 60–90 s of combat [KIT §4.1] |
| 15:00–16:30 | Third hive falls → the Titan leaves the skyline and climbs the Spire (seen from the boss-gate vista); the S4 Ascension Catapult lights |
| 16:30–23:00 | Boss: 3 phases on the Crown (+224) in storm light |
| 23:00 | Victory: slow-mo, orbit cam, stats |

Death → respawn at the last cleared hive with full HP (SPEC §8).

## 2. Scale and metrics

### 2.1 Hero and engagement
- **Hero:** 16.0 m; head 1.95 m (7.8 heads); hip 8.0 m (53 %); shoulders 7.6 m; foot 3.0 × 1.6 m [MON §1.2]. Eye 12.0 m.
- **Collision:** capsule r 3.5 h 15 in code; level sweeps use r 4 h 16.
- **Speed in body heights per second (calc):** walk 0.56 · run 1.0 · boost 2.6 · assault 5.25 · dash peak 9.4. AC6's 7–10 H/s is unreadable in 30 m streets [MOVE §16.1].
- **Bands:** close ≤ 80 m · mid 80–180 m · long 180–300 m [MOVE §16.2].
- **Locks:** soft 300 m · hard 450 m · paint 300 m.
- **Rifle:** full damage ≤ 200 m, 60 % at 350 m, cut-off 500 m.
- **Sightlines:** ≤ 350 m on ≥ 95 % of arena samples [LEVEL §3.2].

### 2.2 Cameras
Hero screen fraction: f = H / (2·d·tan(FOV_v/2)). Godot's `fov` is vertical [MOVE §16.4].

| Setting | Value |
|---|---|
| 3P FOV (vertical) | 55° (≈ 85° horizontal); boost 60°, assault 66°, ADS 38°; in 0.25 s expo, out 0.40 s (SPEC §5) |
| 3P framing (r1) | f 0.38–0.42 at rest; hero centre at 0.33–0.36 of the width; crosshair clear by ≥ 0.06 of the width |
| Arm (solver output) | ≈ 38–40 m at 55° (calc). Boost ×1.16 and assault ×1.32 (`camera_framing.gd`) give f ≈ 0.30 / 0.23 (calc): speed reads as space. If the solver returns ≈ 22 m, check `camera.fov` at runtime |
| Rig | pitch −6°; SpringArm sphere r 1.5 m, margin 0.5; instant pull-in, push-out 10 m/s after 0.25 s; occluding buildings dither to 30 %. Camera at rest ≈ 16.7 m high (calc), under the 24 m deck clearance [MOVE §16.2] |
| First person | eye 12.0 m; FOV 62° (≈ 94° horizontal), ADS 45°; frame ≤ 18 % of the screen; 0.35 s blend that keeps the aim point; footsteps translate −0.12 m and never rotate [MOVE §2.4] |

### 2.3 City [LEVEL §3.2][MAP]
| Metric | Value |
|---|---|
| Layers | L0 −40 tunnels · L1 0 streets · L2 +32 viaduct and plateau · L3 +80 skydecks and skyrail · L4 +128…+176 roofs · Crown +224 · soft ceiling +260 |
| Widths (m) | alley 24–32 · street 40–56 · avenue 80–96 · viaduct 56 · skybridge 32–40 (≥ 28 m inside) · skyrail 24 · tunnel 48–64 × 32–36 clear · squeeze 24 × 32 |
| Decks | slab 4 m (L2) / 6 m (L3+); under-deck clearance 28 m (min 24); parapet 4–6 m |
| Vertical thresholds | step ≤ 2 m (step-up 2.5) · hop ≤ 8 · free climb ≤ 32 · ambiguity 33–47 (tagged `skill` only) · hard step ≥ 48 |
| Gaps without flight (needs K14) | safe ≤ 100 m · committed 100–150 · expert 150–220 · ≥ 260 needs a connector or flight |
| Cover | low 8–10 m, full ≥ 20 m; every 40–60 m; 30–40 % soft |
| Buildings | A 16–32 · B 48–80 · C 128–176 · ▲ D 180–240 · Spire 360 m; 4 m floor module |
| Arenas / map | skirmish 160–240, major 240–320, boss deck 320 × 320 m; map 1.4 × 1.4 km, skyline ring to ±900 m |
| Travel [L] (validator, v 42, g 25.5) | arena → arena worst 36.9 s, median 18.9; arena → boss gate ≤ 29.9 s (budgets 45 / 30 / 30). One fail: C11 A4 → A5 routes only 51 m apart |

## 3. Movement kit

| Verb | KB / pad | Numbers | EN | Notes |
|---|---|---|---|---|
| Walk / run | WASD / LS | 9 / 16 m/s. Walk top speed 0.35 s, stop 0.25 s. Run blends in over 0.8 s, out over 0.3 s. Steps every 0.90 / 0.62 s. Legs turn 180 / 120°/s. Torso follows aim with a 0.10 s lag, twists ±100° before the legs pivot | 0 | [MOVE §16.2] |
| Step-up | — | ≤ 2.5 m via `test_move` (up → forward → down). While boosting, auto-hop obstacles ≤ 7 m, clearing them by 1 m | 0 | r1; no built-in step [GODOT §2.3] |
| Dash | Shift / B tap | 8 camera-relative directions; 24 m in 0.25 s (150 → 42 m/s). Reload 0.38 s; ≤ 3 chained, then 0.45 s lockout. I-frames f1–6; breaks homing on f1. Air dash: 130 EN + 0.15 s hang | 110 | Perfect dodge: 0.3× for 0.35 s, +3 % OD |
| Boost | Shift / B hold | 42 m/s, reached in 0.18 s, turn 160°/s. Free on the ground (EN regen continues). Air cruise free but ▲ sinks 10 m/s | 0 | speed lines from 40 m/s |
| Assault boost | hold 1.2 s | 0.30 s ignition (FOV +11°), then 84 m/s. Yaw 80°/s (turn radius ≈ 60 m, calc). ▲ Pitch 45°/s in flight. Light weapons fire. Melee = Ram Kick 850 / 750 (×2.5 on staggered) | 120/s | exit by dash or 0.25 s skid |
| Jump / ascend | Space / A | 4 f knee-dip, hop to +8 m at 0.45 s; ascend 18 m/s; hover below a 60 EN reserve; apex J = 40 m | 100/s · hover 40/s | J drives the level metrics [LEVEL §3.3] |
| Fall | — / Ctrl dive | 25.5 m/s², terminal 50 m/s; dive 45 m/s | 0 | — |
| Flight | double-tap jump | 50 m/s; boost = assault; soft ceiling +260; at 0 EN → glide (sink 12 m/s). ▲ Pad: heading follows camera pitch, so B stays dash. ▲ Airborne players draw Harrier and Spitter fire first (estimate) | 80/s, no regen | 12.5 s of flight from full (calc) |
| Landing (SPEC 19:40) | — | Soft < 25 m/s: 0.20 s, cancellable from f6. Hard ≥ 25: 0.38 s, cancellable from f14. `land_heavy` ≥ 32. Empty EN: 0.70 s, no cancel | — | EXVS lag 26–42 F [MOVE §3] |
| EN | — | 1,000. Ground regen 500/s after 0.6 s; air 120/s after 0.9 s. Outage: 1.5 s lockout, then +250; big moves need ≥ 300 | — | [MOVE §1.2, §7] |
| Hard lock | MMB / R3 | Strafing orbits the target at constant radius; yaw spring 9 rad/s; never auto-switches; flick to switch | — | ZOE2 sphere [MOVE §5] |

**Mass cues** [MOVE §15.2]: 1P footsteps translate on a k 65 / d 15 spring; landing dip 0.25–0.6 m by fall speed; cockpit mesh lags turns by 80 ms; servo layers; leg IK on slopes.

**EN from full (calc):** 9 dashes, 8.3 s of assault, 12.5 s of flight or 10 s of ascent. A full ground refill takes 2.6 s.

## 4. Weapons and skills (12 + ultimate)

16 m scale (KIT ×2 for reach and speed; SPEC wins). Pad labels are Xbox.

| # | Kit | KB / pad | Numbers | Cost · CD | Signature | Feeds |
|---|---|---|---|---|---|---|
| 1 | **Pierce-Light Rifle 贯光步枪** | LMB / RT; hold = charge | Hitscan, ≤ 240 rpm, 9 rounds, reload 1.6 s. 230 dmg / 345 weak, impact 70. Charge 0.6 s → 700/350, pierce 1. Charge 1.2 s → 1,400/800, pierce all, 8 m blast | 3 rds + 120 EN / 5 rds + 200 EN | beam core 0.5 / 1.0 / 2.2 m by stage (weapons r1); "tchew"; whine rises a fourth per stage | 2 / 4 hits → 1 / 2 marks; stage 2 detonates primes |
| 2 | **Thunder Spindle Gatling 雷纺机炮** | wheel / D-pad ↑ to swap | 15 rds/s at 900 m/s after a 0.3 s spin-up; 52 dmg, impact 22; cut-off 350 m. Overheats at 118 rounds. 0.9 s vent needle: perfect 6 f = Superheated 4 s (+30 % dmg); miss = 3.2 s jam | HEAT | barrels glow orange-white; loop + accent | swarm shredder, ≈ 620 DPS [KIT §4.2] |
| 3 | **Dawn Edge saber 曦刃** | F / X | L1, L2: 380/180, 18 m, 120°. L3: 820/480, 200°. **Lunge** 24–80 m at 110 m/s: 950. **Charged** (hold 30 f): 1,500 + a 90 m wave. **Air** L1–L2. **Return Cut**: 1,400. Combo scaling −6 %/hit after hit 6 (floor 55 %) | lunge 140 EN | 14 m white/cyan blade; hum bent by blade speed; hit-stop 5/5/9/7/10 f | impact → stagger; the wave detonates |
| 4 | **Core Rend 核裂处决** | F / X on a staggered enemy ≤ 14 m, ±60° | 0.9 s small, 1.8 s Brute, 2.4 s Titan (12 % HP, never lethal). Invulnerable. Core rupture: 1,200 dmg / 1,000 impact in 20 m | +300 EN, +8 % OD, +5 % HP | 3P execution cam even from 1P; B/W impact frame | closes the loop |
| 5 | **Rift Step 裂隙步** | C / L3 | With a lock ≤ 90 m: 14 m behind or to a flank, or 50 m back. No lock: 44 m. 9 f intangible transit, then **Ambush** for 0.45 s (+50 % dmg, +100 % impact). Leaves a decoy | CD 8 s | ghost shell; imploding ring; FOV +8° | Juggernaut back core |
| 6 | **Skyhook Anchor 天钩锚** | E / Y | 120 m cable. **Surface:** reel 60 → 92 m/s, swing, jump-release +12 m/s. **Light enemy:** yanked to 18 m + 0.6 s stun. **Heavy:** you are pulled in; Hook Kick 900. **Staggered:** Core Rend | 2 charges × 5 s | cable twang; latch sparks | anchors every 40–60 m, ≥ 8 per arena |
| 7 | **Hailstorm Volley 雹暴齐射** | hold 1 / RB, release | 24° × 16° paint box; 1 lock per 0.10 s, 12 max (≤ 4 per target), 300 m. 12 missiles: 0.2 s bloom, then 120 → 200 m/s, 6 s life. 280/140 each + 6 m blast. Steerable while ADS is held | CD 14 s | Itano-circus flares, ribbons, lingering smoke (r1); lock tick +1 semitone | anti-air; detonator |
| 8 | **Corona Fins 日冕翼片 / Ward** | Z / D-pad ↓; hold 0.35 s = Ward | **Tap:** 2 + 2 × marks fins at 150 m/s to an 18 m sphere round the target; 4 beams × 110 each (880 / 1,760 / 2,640 total). **Ward:** a tetrahedral barrier absorbing 3,000 projectile damage over 6 s | CD 10 s / Ward 20 s | the six wing blades launch; each fin's shot is one note of a chord | marks → more fins |
| 9 | **Mirror Guard 镜返盾** | Q / LB | **Tap:** perfect parry in the first 10 f (5 f if re-pressed within 0.5 s); 0 dmg, attacker −600 stability, 8 f mutual stop, reflect 135 %. **Hold:** block 140°, −70 %. **Hold ≥ 0.3 s:** Catch Field takes ≤ 24 projectiles (12 m), released at 135 %. Red attacks can't be blocked | 60 EN/s + 25 per 100 blocked; catch 140 EN/s; perfect +150 EN, +4 % OD | white-gold ring; bell "ting" on the UI bus | Mantis counter → Return Cut |
| 10 | **Shockcore Burst 震核爆** | X / D-pad → | 18/6/20 f with super armour. Radius 32 m: 1,800 → 600; impact 1,400. Deletes projectiles in range; walls block it | CD 20 s | shell 0 → 32 m in 0.18 s; crack-boom | get-off-me; detonator |
| 11 | **Undertow Well 暗流引井** | G / D-pad ← | Thrown ≤ 100 m. 3.5 s field, radius 24 m: pulls ≤ 18 m/s; slows Brutes 40 %, bosses 15 %; primes for 5 s | CD 16 s | violet lensing; spiral inflow | any detonator → **COLLAPSE** 900/700 in 20 m |
| 12 | **Plunge Breaker 坠击破** | hold F / X in air ≥ 16 m up | 190 m/s dive, homes ≤ 120 m. Radius 20 m: 1,600 → 500, +10 % per 20 m fallen (cap +50 %). 0.75 s air-lock on non-bosses | CD 12 s | plasma sheath; 8 m crater; whistle → boom | air juggle; detonator |

**Ultimate: Zenith Overdrive 天顶超驱 → Zenith Lance 天顶光枪** (V hold 0.25 s / L3+R3 within 4 f; needs OD 100 %) [KIT §4.5]
- **Ignition:** 0.45 s with super armour; global 0.3× for 0.25 s.
- **Overdrive, 12 s:** cooldowns reset, then tick 2.5×; EN regen ×3; free dashes; damage +25 %, damage taken −30 %; afterimages; every 5th saber hit adds a 600-damage clone slash.
- **Lance** (second press, or automatic at 1 s left): 0.8 s charge (enemies at 0.3×), then a 3.0 s beam, 16 × 800 m: 10 ticks/s × 450, pierces and breaks props. Rooted, turn ≤ 40°/s. Breaks a boss barrier after 1 s of contact.
- **Aftermath, 3 s:** no dash, EN regen −50 %.
- **Signature:** seven chest stars light one per OD seventh; on ignition the seams turn white-gold #FFE6A3 over 0.4 s; the six blades form a 12 m ring in front of the chest that the beam fires through [MON §2.3]; the music drops out, then slams back.

**Resources**
- **EN:** §3. **HEAT:** gatling only.
- **OD gains:** +1 % per 1 % of own HP lost · +1 % per 450 dmg dealt · +4 % perfect guard · +3 % perfect dodge · +8 % execution · +2 % per COLLAPSE · ▲ +15 % per hive (estimate). ×1.5 below 15 % HP; nothing while active.
- **HP 10,000.** Heals: Core Rend +5 %; ▲ hive destroyed +30 % (estimate).
- **Enemy states:** marks (5 s), stability, primed (5 s).
- **Style meter D → SSS:** variety over the last 4 skills; damage taken costs 2 ranks; ▲ rank S and above gives +25 % OD gain (estimate) [JUICE §8].

**Synergies** [KIT §4.7]: marks → Fins · impact → stagger → Core Rend · perfect guard → Return Cut · catch → release · Undertow → detonator → COLLAPSE · Skyhook → Hook Kick or Core Rend · Rift Step → Ambush · Plunge → juggle · Overdrive → two rotations in 12 s.

**Inputs:** tap/hold threshold 0.25 s; buffer 6 f; chords resolve within 4 f (L3 waits 4 f before Rift Step); mouse wheel swaps weapons, flicks switch locks.

**Cut order** [KIT §4.11]
- **Floor:** rifle, saber + lunge, Core Rend, dash/assault, Mirror Guard, Hailstorm, Skyhook, Shockcore, Overdrive + Lance.
- **Cut first, in order:** Undertow → Rift Step → vent mini-game → Ward → Plunge.

## 5. Feel spec

**Global rules**
- **One data table:** FEEL.md → `fx/events/*.tres`.
- **Hit-stop:** gunfire never freezes. Melee is local: victim 0, attacker 0.05; the victim's visual root vibrates ±0.04 H; 4 f blend into the hurt pose. Global stop only on rows marked G. Never freeze locomotion the player started. Buffer inputs during stops [JUICE §2].
- **Shake:** rotational Perlin, shake = trauma², linear decay 1.2/s. At trauma 1: yaw/pitch 2.5°, roll 1.2°. Kick spring ω 22 rad/s. Aim rays come from the un-shaken pivot [JUICE §3].
- **Post is edge-only** (feel r1):
  - centre alpha ≤ 0.05;
  - full-screen flashes ≤ 0.25 alpha and ≤ 2/s (except 1–2 f B/W frames);
  - speed lines only in the outer 35 %, alpha ≤ 0.3;
  - FOV deltas clamp at ±15°;
  - first person: shake ×0.6, FOV ×0.75, VFX alpha −40 %.
- **Explosion radii:** missile 8 m · kill_small 12 m · kill_large 28 m · boss or hive 60 m.
- **Rumble:** each motor takes the max of its envelopes, re-sent every 50 ms. Sliders plus a photosensitive mode [JUICE §12].

**Table** (rows not listed keep FEEL.md v1).

| Event | Hit-stop | Shake | Flash / post | FOV | Slow-mo | VFX | Sound | Rumble w/s/ms |
|---|---|---|---|---|---|---|---|---|
| footstep (run) | — | 1P −0.12 m; 3P 0.03 | — | — | — | dust | servo pre-roll → clank + slam + sub 45 → 30 Hz | 0.05/0.15/50 |
| dash ▲ | — | 0.06 + 0.6° kick | CA 2 px; edge radial 0.04 | +6° (60 ms in, 250 ms out) | — | plume + 3 afterimages | chuff + whoosh | 0.5/0.3/90 |
| perfect_dodge | — | — | desaturate 60 % + cyan edge | +6° | 0.3× 0.35 s | afterimages | reverse whoosh + heartbeat | 0.3/0.1/80 |
| land_heavy | — | 0.35, dip 0.5 m | — | −2° | — | 8 m crater | T + B + S 60 → 28 Hz + debris | 0.3/0.9/220 |
| missile_hit | local 50 ms (first of salvo) | 0.25, falloff 160 m | flash 4 f + light 3 f | — | — | 8 m fireball; ring to 20 m in 0.18 s | T + B + S + tail + debris | 0.35/0.6/180 |
| parry_perfect | local 8 f (both) | 0.10 | white-gold ring; CA 4 f | — | — | 40 sparks | ting + 60 Hz (UI) | 0.8/0.2/80 |
| execution | local 10 f | 0.55 | B/W 1–2 f + flash 6 f | −10° push, +6° release | 0.3× 0.3 s | 20 m rupture | swell → T + B + S + tail; World −9 dB | 0.8/1.0/250 |
| kill_large | G 100 ms | 0.45 | white 0.25 2 f | −3° | 0.35× 0.35 s | 28 m ×3 chained; burning wreck | full layers; World −6 dB | 0.5/0.9/350 |
| boss_stagger | G 150 ms | 0.60 | B/W 1 f + white 0.4 | −6° | 0.5× 0.4 s | plates eject, arcs | groan + sub + stinger | 0.6/1.0/400 |
| hive_pod_break ▲ | G 60 ms | 0.35 | violet edge flash | −3° | — | 20 m burst, spores | crunch + sub + stinger | 0.4/0.8/250 |
| hive_destroyed ▲ | G 150 ms | 0.60 | B/W 1 f + white 0.25 | −6° (120 / 400 ms) | 0.5× 0.6 s | 60 m blast, debris rain 4 s, smoke column 60 s | XL builder + Titan roar (delayed d/343 s) + stinger | 0.6/1.0/500 |
| titan_step ▲ | — | 0.06 within 300 m | — | — | — | dust falls from façades | sub 25–35 Hz + delayed rumble | 0/0.3/150 |
| titan_roar | — | 0.15; 0.4 within 300 m | — | −4° | — | glass-shatter decals | roar; World −8 dB; input lock ≤ 0.3 s | 0.3/0.6/600 |
| telegraph_unblockable ▲ | — | — | red fresnel + ground decal; HUD arrow if off-screen | — | — | — | unique sting (priority 80) | — |
| hurt_heavy | G 83 ms | 0.50 + 1.5° kick away | red edge 0.6 / 350 ms; CA 3 px | −3° | last stand < 15 % HP: 0.5× 1.5 s (60 s CD) | armour chunk, smoke | alarm; World LPF 1.2 kHz 400 ms | 0.6/0.8/300 |
| lance_fire | — | 0.15 sustained; +0.8 on release | B/W 2 f on release | −12° charge, +14° release | enemies 0.3× during the charge | beam 2.4 / 8 / 16 m + heat haze | riser → roar + sub | 0.3/0.6 every 250 ms |
| low HP ▲ | — | — | < 30 %: LPF 8 kHz, heartbeat 70 bpm. < 15 %: LPF 2.5 kHz, 110 bpm, saturation 0.55, pulsing edge | — | — | — | cockpit alarm 2 Hz | — |

## 6. Enemies and encounters

### 6.1 Roster
**Rules**
- Windup ≥ 250 ms reaction + time for the counter + a buffer. Off-screen attackers add +200 ms and a HUD arrow [JUICE §11.1].
- Tokens: ≤ 3 melee and ≤ 2 ranged on the player; ≤ 1 boss-class telegraph at a time.
- Caps: ≤ 40 active AI; ≤ 24 per arena (estimate).

| Type | Size · LOD0 | HP / stability / stagger | Behaviour | Telegraphs | Weak point | Counters |
|---|---|---|---|---|---|---|
| **Ripper 裂爪** | 6 m long · 6–8k; ≤ 16 on screen | 300 / 150 / 0.8 s | packs of 6–16; 32 m/s; climbs façades; flanks | leap-bite 25–40 m after a 0.45 s crouch + mandible flare (parryable) | throat sac ×2.5 | gatling, Shockcore, COLLAPSE, perfect dodge |
| **Ripper Alpha** | 1.4× · 9k | 1,200 / 500 / 1.2 s (estimate) | leads packs of ≥ 8 | howl after a 0.6 s rear-up: pack +15 % speed for 5 s | crest (600 HP), then the sac | rifle on the crest; Core Rend |
| **Mantis 镰影** | 14 m · 18–22k | 1,800 / 700 / ▲ 2.0 s | pairs; 20 m sidestep in 0.3 s when aimed at | 3-hit combo, white glint 0.35 s before each hit (parryable); red grab after 0.6 s (dodge it) | thorax core, open on grab and stagger | parry → Return Cut |
| **Spitter 酸巢** | 12 m · 15–20k | 2,400 / 900 / 1.6 s (estimate) | holds 150–300 m on high ground; plants to fire | lob after a 1.0 s sac swell + gurgle; visible arc (catchable); chaff eats 4 missiles | back sac ×2.5 | Skyhook/assault to close; Catch Field |
| **Harrier 鸣翼** | 16 m span · 10–14k | 900 / 300 / ▲ falls 1.5 s, then grounded and executable for 1 s (estimate) | circles 60–120 m up; strafes at 40–60 m/s; hunts flyers | dive bomb (unblockable) after a 0.5 s screech as the wings fold | throat sac | Hailstorm, Skyhook yank, Fins |
| **Juggernaut 裂山** | 22 m · 30–40k | 7,000 / 2,600 / 2.6 s | 8 m/s; ≤ 1 per arena | charge at 45–60 m/s (0.7 s roar + ground glow); slam with a 1.0 s rear-up → 4 m ring (jump it) | back core ×2.5; 8 front plates (600 each) | Rift Step behind; Plunge on the back |
| **Brood Titan 巢母** (boss brief) | 60 m · 120–160k (skyline LOD 10k) | 60,000 / 9,000 / 3.4 s (6 s immunity); legs armoured ×0.5 | skyline walk outside ±700 m; enters the fight by climbing over the deck edge | stomp: 0.9 s lift → ring to 80 m (jump/dash it) · claw swipe: 1.1 s, parryable on a 167 ms glint · beam breath: 1.4 s inhale → 4 s sweep (unblockable) · summon: 6 Rippers + 2 Harriers · tail sweep (rear only) · P3 lightning: 1.0 s circles | 3 cores (shoulders L/R + chest), 8,000 each, ×2.5; breaking one staggers it and removes an attack | flight to the cores; anchors on the deck fins; Lance; Core Rend 12 % |
| **Hive Spire 蚀巢** (flow brief) | 60 m, static | 20,000 HP over 4 pods (weak points) + a core | births Rippers every 12 s (cap 8); pulses at 0.8 Hz | — | the pods, then the core | everything |

### 6.2 Encounter plan
| Place | When | Waves | Escalation |
|---|---|---|---|
| A1 Container Yard | 0:30–3:00 | W1: 6 Rippers (shoot, dash) · W2: 8 Rippers + 1 Alpha (melee, Shockcore, Core Rend) · W3: 1 Mantis (parry prompt) | fixed |
| Roaming L1 packs | between hives | 1–2 packs of 4–6 Rippers on L1 junctions (K1, H4, F2, W1, A3, U1); a cleared junction respawns after ≥ 90 s, never in view (flow brief + estimate) | +2 per hive destroyed (estimate) |
| Sky / perches | after hive 1 | a Harrier pair on the skyrail (flow brief) and over the A4 canyon; Spitter pairs on L3/L4 above A3 and A4 | trios after hive 2 |
| **Hive assault** (A2, A5, A6; any order) | 4–6 min | **M1** 6 Rippers · **M2** 8 Rippers from breaches + Alpha · **M3** 2 Spitters on the upper tier + 6 Rippers · **M4** elite · **M5** pods and core under fire while the hive births every 12 s (cap 8). Each starts at half-clear of the previous [LEVEL §1.6] | elite by hive count: #1 = 1 Mantis; #2 = 2 Mantis + 2 Harriers; #3 = Juggernaut + Mantis + 2 Alphas |
| Boss gate | 15:00 | vista of the Titan climbing the Spire; the last roaming pack | — |
| **Crown boss** (boss brief) | 16:30–23:00 | **P1** 100–65 %: stomp, swipe, summon · **P2** 65–30 %: + beam; deck edge segments break (a fall lands on the S4 ring; back in ≤ 12 s) · **P3** < 30 %: storm lightning, enraged combos. 2–3 s invulnerable roar cinematics between phases | — |

**Hive rewards ▲ (estimate):** +30 % HP, full EN, +15 % OD. The sun steps 20° → 14° → 9° → 6° and lit windows rise 40 → 75 % [ART §3].

### 6.3 Tension
- **Intensity I** rises with damage taken, nearby kills (inverse distance) and being airborne below 30 % EN (estimate). It decays only while no enemy is engaging.
- **Phases:** build → peak 3–5 s → fade → relax 30–45 s [JUICE §11.2, Booth's L4D director].
- **Music:** explore 0.2 → contact 0.5 → hive 0.8 → boss 1.0 (SPEC §8).
```
I 1.0 |                                                     .:########:.
  0.8 |           .:##:.          .:###:.           .:####:.:##########
  0.5 |  .:#:.   :      :.  .:. .:       :.  .:.  .:       :
  0.2 |::     :.:        :.:   :           :.:   :.          relax 30-45 s
      +----+----+----+----+----+----+----+----+----+----+----+----+---> min
      0    2    4    6    8    10   12   14   16   18   20   22   24
      drop A1   hive#1    hive#2      hive#3    Titan   boss P1-P3  win
```

## 7. Map: "Escarpment City around the Spire" ([LEVEL §4] as adopted by MAP; ▲ = delta)

### 7.1 Districts and arenas
| District | Layers present | Landmark | Arena (size; tiers; entries) | Role |
|---|---|---|---|---|
| D1 Harbor (SW) | L0–L2; docks −12; cranes +48 | gantry cranes | A1 Container Yard (260 × 200; −12…+48; 5) | start, tutorial |
| D2 Interchange Knot (W) | ramps 0…+80 | the Knot | A2 (300 × 300; 0…+80; 7) | **Hive H1** |
| D3 Old Town (NW plateau) | L0 shaft; terraces +16/+32/+48; pagoda +128 | Stilt Pagoda | outposts only | caches, escarpment links |
| D4 Spire / Civic Core | L0–L4 + Crown | the Spire and its tether | A3 Plaza (280 × 200; 9); **B1 Crown** (320 × 320; +208…+240; one-way vcat in, lift out) | hub, boss gate (S4), boss |
| D5 Megablocks (NE) | L2 canyon; L3 bridges + rail | Block 9 + koi hologram | A4 Canyon (90 × 400 + roofs; +32…+128; 6) | Harrier nest, perches |
| D6 Foundry (E) | L1–L3; stacks +144 | Reactor Stacks | A5 (300 × 240; 0…+144; 7) | **Hive H2** |
| D7 Financial (S) | L1, L3; garden +144; Crystal +176 | Crystal Bridge | A6 Sky Garden (240 × 200; +144/+176; 3) | **Hive H3** |

- **Hives:** each stands at its arena's centre of mass, 60 m tall, on the highest tier with ≥ 3 approach routes (MAP §2).
- **Light per layer** (ART §3): L0 cool fluorescent · L1 warm, dark sodium under the decks · L2 golden · L3/L4 sky-lit with rim · Crown storm.
- **Weenie:** the Spire, visible from ≥ 80 % of the map (check C15).

### 7.2 Loops and links
- **Loops** [LEVEL §4.6], times at 42 m/s (calc): Ring Viaduct L2 2.80 km / 67 s · Skyrail L3 1.70 km / 40 s · South L1/L0 1.44 km / 34 s · Canal–Foundry 1.45 km / 34 s · Spire Collar 0.62 km / 15 s.
- **Connectors** [LEVEL §3.4]:
  - `edgejump` ≤ 32 m · `ramp` ≤ 20° · `stairs` · `lift` 16 m/s + 3 s · `drop`
  - `vcat` 48–144 m in 2–4 s · `lcat` 300–600 m in 4–6 s · `vent` up ≤ 150 m · `rail`
- **Up/down links per band, measured [L]:** L0↔L1 6/6 · L1↔L2 23/25 · L2↔L3 12/15 · L3↔L4 7/9 (target ≥ 4 each).

### 7.3 Boss arena and Titan routing ▲
- **Crown deck B1:** central core Ø 80 m as full cover; four 24 m fins; edge segments that break in P2 [LEVEL §4.5][boss brief].
- **The Titan (60 m) stands on the deck.** It enters by climbing over the deck edge.
  - Its cores (≈ +38…+50 m above the deck, calc) are reached by hover, flight, or Skyhook anchors on the crown fins (▲ add ≥ 8).
- **Skyline walk** (▲ condition for K10):
  - a closed ring at r ≈ 750–850 m crossing only sectors ≤ 40 m tall (south bay, warehouse belt, west Old Town terraces); never behind D5 or D7 towers;
  - head above the roofline, body veiled in steam [MON §3.4];
  - after ≥ 20 s unseen it may relocate to the ring segment most visible from the player's district (estimate).

### 7.4 Plan
1 column = 25 m E–W, 1 row = 50 m N–S. Generated from `level_graph.json` by `tmp/research/synthesis/scripts/ascii_plan2.py` [L].

Legend: `+` playable edge · `^` escarpment (+32) · `=` L2 viaduct · `#` L3 skyrail · `.` L0 tunnel · `@` Spire · `~` water · `T` Titan walk · H1–H3 hives.
```
     T  +++++++++++++++++++++++++++++++++++++++++++++++++++++++++
     T  D3 OLD TOWN (L2 +32)              D5 MEGABLOCKS (L2 +32)+
    T   +                                                       +
   T    +      *PAGODA                                          +
   T    +                                             [A4]      +
   T    +                          =S5=========                 +
   T    +    .            ==========           ==               +
   T    +     ..  O3======          .           #*BLK9          +
   T    +      ..  ==           @@@@S4@@@   ####  #===          +
   T    +^^^^^^^^^^^V7^^^^^^^^^^@@@@@@@@@^^^^^^^^^^^^V6^^^^^^^^^+
   T    +         .=        ####@@@@(BOSS+224)     #  ==        +
   T    D2 KNOT   ==.  ######   @@@@@@@@@          ##  =        +
   T    +        ==#####        @@@@@@@@@ D4        ##  =       +
   T    +        [A2]H1.            ##               #  =V5     +
   T    +         ==   ..           [A3] .           ##==*STACKS+
  T     +          ==   ...         .#   ..          ===        +
  T     +           ==    U1......  .#    ..U3      ==#[A5]H2   +
  T     +            ==          ...S2#....    ####==   D6      +
   T    +             == ======================= ===            +
   T    +              V2=        *CRYSTAL#    ==V4             +
   T    +          [A1]                   D7 FINANCIAL          +
   T    D1 HARBOR                 [A6]H3                        +
   T    +~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~+
   T    +~~~~~>START~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~+
   T    +++++++++++++++++++++++++++++++++++++++++++++++++++++++++
          TT TT T TT TT T TT TT T TT TT T TT TT T TT  T TT T T TT
```

### 7.5 Node and edge list
- **Full list:** [LEVEL §4.7] (60 nodes) and §4.8 (106 edges) = `data/map/level_graph.json`.
  - Validator with SPEC constants [L]: 185 directed edges, 37 loops, 7 dead ends (all rewards or the start).
- **Macro graph:** fastest travel between arenas in seconds [L].

| from \ to | A1 | A2 | A3 | A4 | A5 | A6 | boss gate S4 |
|---|---|---|---|---|---|---|---|
| A1 | — | 10.3 | 16.5 | 36.9 | 25.0 | 14.1 | 28.0 |
| A2 | 10.3 | — | 11.3 | 28.0 | 22.8 | 24.4 | 21.6 (K5-S3w-S3n-S4) |
| A3 | 16.5 | 11.3 | — | 20.4 | 11.5 | 19.9 | 27.5 |
| A4 | 36.9 | 27.6 | 20.4 | — | 16.3 | 31.1 | 9.7 |
| A5 | 24.9 | 22.8 | 11.5 | 16.3 | — | 17.8 | 26.2 (W4-M5-M3-M4-S4) |
| A6 | 16.5 | 23.6 | 12.3 | 27.8 | 16.4 | — | 10.2 (F4-F5-S4) |

Start → A1 5.3 s · A2 15.6 · A6 19.4 · A5 30.3.

**Deltas ▲**
1. Fix C11 by giving A4 → A5 a second route on another layer: the L3 rail M5–W4, or L0 via U3.
2. Cap buildings at 240 m.
3. Add ≥ 8 anchors on the Crown fins and deck edges.
4. Keep the skyline-ring sectors on the Titan's path ≤ 40 m tall.

## 8. Art direction

### 8.1 One look: golden-dusk Chinese neo-futurism (keep ART.md, refined)
**Rejected**
- **Rain-night neon cyberpunk:** it needs hundreds of lights; Godot clusters 512 elements per view, and area lights cost every object [GODOT §0]. Its neon greens and violets collide with the Husk glow [MON §6]. The white hero drowns in saturation.
- **Overcast "city of glass":** flat light kills armour volume and monster glow, and it cannot age as a tension curve.

**Why dusk wins**
1. **Readability:** the light hero, warm mid-tones and dark chitin cut by acid glow follow Valve's read hierarchy (dark feet to a high-contrast chest; team by colour) [MON §1.1].
2. **Scale:** a low sun gives long shadows and backlit layers [X3]. Haze lowers contrast and saturation with distance [X2], which sells 1.4 km and a 60 m Titan.
3. **Wayfinding:** per-layer light, as in Hengsha's dark underside against sunlit decks [LEVEL §1.8].
4. **Cost:** one sun plus emissive window shaders [GODOT §4.3].
5. **Tension:** the light ages 20° → 6° and storms at the Crown.
6. **Continuity:** it matches the key art and the Chongqing / Hong Kong references [LEVEL §1.14].

### 8.2 Colour language ▲ (ART §2 palette stands)
| Meaning | Colours | Rule |
|---|---|---|
| Player and affordances | glow #4FE6FF, beams #EFFFFF / #36E2FF, cyan-white "up" connectors | ▲ no cyan city neon (hue 175–200°) within 60 m of play spaces; the Knot's cyan barriers become amber #FFB13E |
| City neon | magenta #FF3EA5, amber #FFB13E, jade #3EFFB0 | accents only |
| Monsters | chitin #1B2430, seams #9BFF3A, ▲ bone-white attack parts #C9BFA6 [MON §3.2] | soft tissue maroon #3A2A2E |
| Weak points | violet #B04CFF, emission 10, 2 Hz pulse + HUD diamond | every code also has a shape and a sound [MON §3.3] |
| Danger | red #FF2A2A, unblockables only | Old Town red signage never pulses |
| Storm ▲ | indigo #3B3F73 / slate #2E3550; violet only in lightning | keeps weak points unique on the Crown |

### 8.3 Lighting, fog and post
Godot 4.7.2 names and defaults verified [L]; values are estimates unless cited.

| System | Setting |
|---|---|
| Sun | Elevation 20° → 14° → 9° → 6° per hive; from the SW (Spire backlit from the pier). Colour #FFD3A0 → #FFB27A; energy 2.2 → 1.6. `light_angular_distance` 0.5°. Shadows: 500 m max (default 100), splits 0.05 / 0.15 / 0.40, blend off; buildings in ≤ 60 m chunks [GODOT §4.3] |
| Sky | PhysicalSkyMaterial: `turbidity` 10 → 14, `mie_coefficient` 0.005 → 0.012, `mie_eccentricity` 0.85, `sun_disk_scale` 1.5. Or a CC0 dusk HDRI |
| Fog | `fog_mode` DEPTH (1); begin 120 m, end 1,800 m, curve 1.6; `fog_density` 0.85 (the maximum in depth mode [X4]); colour #E8B98A; `fog_sun_scatter` 0.25; `fog_aerial_perspective` 0.7 (blends fog into the sky colour [X4]); `fog_height` +10 m, `fog_height_density` 0.02 (thickens below [X4]) |
| Volumetric fog (high) | density 0.002, albedo #E8B98A, anisotropy 0.6, length 300 m (default 64); short-lived lights at fog energy 0 [GODOT §4.3] |
| GI / AO / SSR | SDFGI medium/high: 6 cascades, min cell 0.6 m [GODOT §4.3]. SSAO radius 4 m (default 1 m is human scale). SSIL high, 10 m. Probe per arena; SSR on high |
| Glow / tonemap | glow SCREEN (1), intensity 0.45 (default 0.3), HDR threshold 1.2. AgX (4) with defaults (white 16.29, contrast 1.25). Saturation 1.05; low HP 0.55 |
| Windows | emissive cells 40 % lit → 75 % by hive 3; #FFCF8A warm, #BFE3FF cool |

### 8.4 Hero brief: 天枢 TIANSHU YQ-X1 (call-sign POINTER)
**Concept:** an astronomical instrument worn as samurai-knight armour: stillness, then an iai-draw burst [MON §2.1].

**Keep from the g1 body:** white / cobalt / amber with cyan glow; the narrow visor; the inner frame visible at every joint.

**Changes ▲**
1. **Crest:** a gold pointer blade raked 20° forward, plus antennae swept *back* 35°. g1's rising V reads as RX-78 [MON §1.3].
2. **Chest:** seven Big-Dipper lights that double as the OD meter.
3. **Binders:** fold along the back; deploy as a halo ring for Ward and Lance, never a Strike Freedom-style spread.
4. **Markings:** Ver.Ka vocabulary (`YQ-X1`, `天枢`, caution stripes, stencils); no franchise words [MON §1.6].
5. **Idle:** Katoki stance, hip sway ±1.5° at 0.25 Hz.

**Build:**
- Hands, crest, antennae and blade edges are built in Blender (fused fingers and melted thin parts are Tripo's top failures [TRIPO §10]).
- Rigid skin; LOD0 150k / LOD1 70k (hero-asset brief).
- Silhouette tests at 400 px and 60 px [MON §1.3].

### 8.5 Monster look and audit of the current Tripo set
**Husk traits** [MON §3.2]: an acid-seamed dorsal keel; three-slit eyes; bone-white attack parts; scavenged steel as breakable armour; recessed violet cores; one animal-plus-object metaphor per type.

| Model | Issue | Fix |
|---|---|---|
| **Titan** ▲ | A 60 m biped with a long tail and violet dorsal crystal rows reads as Godzilla. Japan's IP High Court upheld Toho's 3D shape trademark for Shin Godzilla on 30 Oct 2024, citing its shared characteristics with the original figure [X5]; Toho has sued lookalikes before [X6] | Keep the biped (rig and presets work). Break the read: replace the dorsal rows with 3–5 brood chimneys (which also justify the summons), give it a crown or hammer head and scythe forelimbs, and shorten or segment the tail. Budget ≈ 400 credits per creature type, re-rolls included [TRIPO §11] (D1) |
| Mantis | Limbs ≈ 0.04 H thick; Horizon found thin legs leave nothing to hit [MON §3.1] | Hurtboxes ≥ 1.7 m (0.12 H); thicker forearms |
| Harrier | Membrane wings are a thin-part risk | Opaque membranes on thick spars; procedural flap (no avian preset [TRIPO §6.2]) |
| Spitter / all | The sac is green; no bone-white parts or scavenged steel | Violet core in the sac; add both in the texture pass; chroma-key emission masks [MON §3.3] |

## 9. Tech architecture and the Blender city pipeline
```
main.tscn
├ World: city tiles/*.glb · NavigationRegion3D ×3 (r 1.5 / 4 / 9) · markers · WorldEnvironment · Sun
├ PlayerMech (CharacterBody3D) → HeroModel, AimSystem, WeaponSystem, MeleeSystem, DefenseSystem, SkillSystem
├ CameraRig (top_level) → SpringArm3D → ShakePivot → Camera3D (+ AudioListener3D at the chest, CockpitFrame)
├ EnemySpawner · EncounterDirector · Titan
├ ProjectileManager / MissileManager (packed arrays + MultiMesh) · VfxLibrary · DecalPool
├ FeelDirector · ScreenFx (CanvasLayer 50) · HUD (CanvasLayer 60; cockpit HUD in a SubViewport)
└ autoloads: Events, Game, Feel (sole owner of Engine.time_scale), Settings, Audio
```

**Rules** [GODOT §0–3]
- **Timing:** Jolt at 120 Hz; `max_fps` 60; no interpolation.
- **Bodies:** CharacterBody3D for every mech and monster (FLOATING for flyers); RigidBody3D only for debris.
- **Projectiles:** data, not nodes.
- **Local hit-stop:** AnimationTree in MANUAL mode, `advance(dt × scale)`.
- **Navigation:** navmeshes baked offline from colliders with WATERSHED (LAYERS took 175 s). One NavigationLink3D per non-walk edge, driven by scripted traversal on `link_reached`. Flyers use AStar3D over sky markers. ≤ 6 path queries per tick.
- **Shaders:** warm up every VFX scene at load.

**Budgets** (1600 × 900 high, 60 fps in the boss fight):
- **Rendering:** ≤ 3,500 draws (aim < 2,000) · ≤ 150 unique materials in view · ≤ 20 M primitives · ≤ 400 of 512 clustered elements · ≤ 16 shadowed lights · 0 area lights · ≤ 60k particles · ≤ 150 visible decals.
- **Simulation:** ≤ 40 AI (AI scripts measured at 0.52 ms) · ≤ 600 bullets + 48 missiles (1.75 ms measured) · 0 pipeline compiles mid-game · VRAM < 6 GB [GODOT §4.2].
- **Per 100 m tile:** ≤ 25 draws, ≤ 60k tris, ≤ 6 materials (estimate).
- **Measuring:** Metal reports GPU time as 0 in 4.7, so measure frame time with vsync off or `MTL_HUD_ENABLED=1` [GODOT §1.2].

**City pipeline**
1. **Layout:** `tools/map/build_layout.py` (seeded) → `city_layout.json`. Validators: C1–C11 on the graph, L1–L7 on the layout.
2. **Geometry:** `blender/city/build_city.py`, headless in Blender 5.2, builds 100 m tiles from the JSON only: 10 building archetypes on the 4 m module, decks, viaducts, rails, tunnels and terrain. Materials: 6–10 trim sheets plus triplanar. Window parameters go in UV2. Meshes are chunked ≤ 60 m.
3. **Helpers by name suffix:** `-colonly` (boxes where possible), `-convcolonly`, `-occonly` (façades, decks), `-noimp`. Empties `GN_<id>`, anchors, sockets, hives and vistas carry glTF extras and become Marker3D on import [GODOT §0].
4. **LOD:** merged HLOD per tile from 300 m.
5. **Godot side:** post-import script → headless navmesh bake per class → C12–C17 probes (▲ including flight arcs) → perf at 8 vistas.

## 10. Audio plan (after [AUDIO])
1. **Buses** (sidechain keys sit to the right) [AUDIO §5.1]:
   - Master (limiter −1 dB) · Music · Stinger · UI (never ducked) · World · Bed · Enemies · Player · Weapons · Impacts (key) · Voice (key) · Cockpit.
   - Godot's compressor gives ≈ 2× the textbook reduction, so aim for Music −7 dB under voice and Bed −8 dB under impacts.
2. **Layers:** transient / body / sub / mechanical / tail / debris, with 90–250 Hz harmonics on sub layers for laptops.
3. **Space:**
   - 8 distance classes using Godot's formula; listener at the chest with the camera's orientation;
   - far layers delayed by (d − 120)/343 s; street slapback 117 / 233 ms; listener doppler off (at 84 m/s statics would bend +4.9/−3.8 st, calc).
4. **Voices:** 40 world + 12 near-field + 24 2D. Per-event caps; lowest priority stolen; the gatling is one loop plus accents.
5. **Music:**
   - one AudioStreamInteractive of synchronized stems at 140 BPM, D minor;
   - clips: explore / combat / boss / boss_p3 / tension / spire_cleared / victory / defeat;
   - stems by intensity; stingers on the beat (≤ 1 per 2 s);
   - 2 bars of silence before the roar [AUDIO §6].
6. **Signatures:** hero = turbine + bell metal + servo · Husk = wet chitin + clicks + pitched animals · Titan = 25–35 Hz footfalls map-wide · ▲ hives pulse at 0.8 Hz.
7. **Sourcing:**
   - CC0 first (Kenney, OGA, Freesound), then credited CC-BY. Sonniss and Pixabay only inside composites (raw files git-ignored).
   - 11 numpy recipes cover ≈ 35 % of ids.
   - Cockpit AI on MiniMax `speech-2.8-hd` "robotic", 24 lines EN/ZH. AI music only as an upgrade.
   - Loudness −23 LUFS ±2, ≤ −1 dBTP [AUDIO §5.9].

## 11. Implementation units (14)

PLAN at 19:40 lists 16 units, including the new boss unit. Proposal: 14, by merging two pairs. Where a brief already exists, it becomes a milestone of the merged unit.
- **view** = camera-aim + hud: the HUD reads the aim state and lives in the cockpit.
- **city** = city-layout + city-build: one owner for the data and its geometry.

| # | Unit (state) | Owns | Depends on | Done when (executable) |
|---|---|---|---|---|
| 1 | mech-move (PASS r2; ▲ follow-up) | `game/player/mech/**`, `player_mech.tscn`, `model/placeholder/**` | core | Add to `test_locomotion.gd`: glide 170 ± 10 m from a 40 m apex at sink 10 m/s; pad flight heading follows camera pitch while B still dashes; `telemetry()` exposes `airborne_low_en` for the director. Keep the r2 tour green in `main.tscn` with the real rig (0 errors) |
| 2 | **view** | `game/player/camera/**`, `aim/**`, `game/ui/**` | mech-move, all `hud_state()` | Projection test: f 0.38–0.42, centre x 0.33–0.36, crosshair clearance ≥ 0.06, at rest and in 6 poses. Cockpit mask ≤ 18 %. `test_hud`: every `hud_state` key bound. Shots: 3P, 1P, HUD in combat, boss bar |
| 3 | feel (r1) | `game/fx/**` | core | `test_feel` PASS. Centre-circle (r 0.25 H) alpha ≤ 0.05 for every post effect. ≤ 2 flashes/s at 10 kills/s. Explosion AABBs 8 / 12 / 28 / 60 m. Gallery with the 16 m mech under glow + AgX |
| 4 | weapons (r1) | `game/combat/weapons/**`, `projectiles/**` | mech-move, view | `test_weapons` ≥ 70. `main.tscn --sandbox` timeline with the real mech: rifle at 120/300 m, stage 2, gatling, 12-missile salvo. ≤ 2 ms/frame |
| 5 | melee-defense | `game/combat/melee/**`, `defense/**` | mech-move, view, enemies | `test_defense`: a swing at 0–166 ms → PerfectGuard; at 170 ms → block; re-press → 83 ms window. `test_melee`: frame data, cancels, scaling. Core Rend gate 14 m / ±60°. Movie: parry → Return Cut → Core Rend |
| 6 | skills | `game/combat/skills/**` | mech-move, view, enemies | `test_skills`: Lance 30 × 450; Overdrive 12.0 s ± 1 f; Fins 2/4/6 from marks; COLLAPSE from all 5 detonators. Movie of all skills |
| 7 | enemies | `game/enemies/**` except `models/`, `boss/` | core | `test_status`, `test_ai`. Every attack preceded by its telegraph event (≥ 350 ms; +200 ms off-screen); tokens ≤ 3/2; Mantis stagger 2.0 s; 40 AI ≤ 6 ms physics on a quiet machine |
| 8 | boss | `game/enemies/boss/**` | enemies, monster-assets, city | `test_boss` (brief): phases at 65/30 %; a core break staggers and removes an attack; unblockable telegraphs ≥ 0.6 s; summon cap; `game_won` once. Scripted `--god` fight ≤ 5 min. ▲ Ray test: the skyline walker is visible from ≥ 6 of 8 vistas |
| 9 | **city** | `tools/map/**`, `tools/city/**`, `data/map/**`, `blender/city/**`, `game/world/city/**` | MAP, ART | `validate_graph.py` PASS (incl. C11) and `validate_layout.py` PASS. `tools/blender.sh run blender/city/build_city.py` deterministic (same hashes twice). Import 0 errors; 3 navmeshes; C12–C17 PASS. ≤ 3,500 draws and ≤ 20 M primitives at all 8 vistas |
| 10 | city-art | `game/world/art/**`, `props/**`, `blender/props/**` | city | 8 vista captures reviewed against ART; ≤ 150 materials in view; 4 time-of-day states; frame time within 10 % of the untextured city |
| 11 | hero-asset | `blender/hero/**`, `game/player/model/hero/**` | lead's Tripo assets | Reproducible build. QA [MON §4.9]: mesh audit; lit close-ups of hands and crest; top-view L/R ≤ 2°; silhouettes at 400/60 px; joint sweep. One Skeleton3D; SPEC §10 clip ids; 16.0 ± 0.05 m; all sockets |
| 12 | monster-assets | `blender/monsters/**`, `game/enemies/models/**` | lead's Tripo monsters, D1 | 5 models + the Titan with the monster API; LOD1 on visibility ranges; emission chroma-key test; hurtboxes ≥ 0.12 H; hero QA gates |
| 13 | audio | `game/audio/**` | Events, FEEL | Every FEEL row and Events signal maps to a sound id or "silent". Bus-order test. Music switches on the bar (±20 ms). A 5-min capture measures −23 ± 2 LUFS (ffmpeg `ebur128`). Manifest audit: no raw licensed files in `game/` |
| 14 | flow | `game/flow/**`, `data/encounters/**` | enemies, city, view | `test_flow` (brief). `--god` autoplay from title to victory in ≤ 25 sim-minutes. Director trace shows ≥ 3 relaxes of ≥ 30 s. Escalation by hive count. Respawn and objectives work |

## 12. Open decisions and risks

**Decisions (my recommendation first)**
1. **D1 Titan:** keep the 60 m biped, but break the Godzilla read (chimneys instead of dorsal rows, a crown head, a short tail) before monster-assets rigs it.
2. **D2 Flight:** keep it, bounded: 80 EN/s, no regen, aggro priority, 10 m/s glide sink.
3. **D3 Framing:** 55° plus the solver's arm (≈ 40 m). If alleys feel cramped, try 60° (≈ 35 m).
4. **D4 Staggers:** KIT values, but Mantis 2.0 s.
5. **D5 Boss:** Crown fight (boss brief); update SPEC §7 (60 m) and §8 (no Plaza break-in).
6. **D6 Hero IP:** swept-back antennae; halo deployment.
7. **D7 Cut order:** fix it now (§4).
8. **D8 Storm:** indigo with violet only in the lightning, since the boss and city-art briefs pair a violet storm with violet cores. Cyan stays the player's colour.
9. **D9 Hive rewards:** +30 % HP, full EN and +15 % OD on top of the flow brief's checkpoint.
10. **D10 Missing art dossier:** §8 plus ART.md may be enough.

**Risks**
| # | Risk | Mitigation |
|---|---|---|
| R1 | Scope: 14 units, a 12-entry kit, a 60 m boss | D7; boss unit; Floor / Stretch tiers |
| R2 | Whole-body Tripo hero (fused hands, melted crest, swept arms) [TRIPO §10] | QA gates; Blender thin parts; P2.0 fallback |
| R3 | Perf: a dense city at 84 m/s, no Metal GPU timing, and numbers skewed by machine load (one scene measured 2.9–253 ms) | tile budgets; 8-vista perf every round on a quiet machine, with the load average logged |
| R4 | Flight trivialises the vertical city [LEVEL §7] | D2; C17 with flight; overhead decks in hive arenas |
| R5 | Camera crowding in 24–32 m alleys | solver arm, pull-in, building dither |
| R6 | Over-juice and photosensitivity [JUICE §4, §12] | edge-only post, rate limits, photosensitive mode |
| R7 | IP: V crest, Freedom wings, Godzilla silhouette [MON §6][X5] | D1, D6; name and trademark search |
| R8 | Animation load (≈ 45 hero clips; monster presets are walk-only) [TRIPO §6] | IK, spring bones, tripod gait; key only attacks, hits, staggers, deaths |
| R9 | AI across layers | per-class navmeshes; scripted links [GODOT §3] |
| R10 | Audio licence leaks in a public repo | git-ignored raw sources; manifest audit |
| R11 | Stale dossier numbers (110 m/s, 1.6 km, 600 m Spire) leak into briefs | briefs cite SPEC v2 and the K-register only |

## 13. New sources
- [X1] Engadget, "Half-Minute Halo: An Interview with Jaime Griesemer": https://www.engadget.com/2011-07-14-half-minute-halo-an-interview-with-jaime-griesemer.html
- [X2] Wikipedia, Aerial perspective: https://en.wikipedia.org/wiki/Aerial_perspective
- [X3] Wikipedia, Golden hour (photography): https://en.wikipedia.org/wiki/Golden_hour_(photography)
- [X4] Godot, Environment class reference: https://docs.godotengine.org/en/stable/classes/class_environment.html · issue #97803 (`fog_aerial_perspective`): https://github.com/godotengine/godot/issues/97803
- [X5] AIPPI, "Shin Godzilla finally calms down: IP High Court approves 3D Trademark" (2024-12-12): https://www.aippi.org/news/shin-godzilla-finally-calms-down-ip-high-court-approves-3d-trademark/
- [X6] The Hollywood Reporter, "Clash of the Godzilla Monsters in Trademark Case": https://www.hollywoodreporter.com/business/business-news/clash-godzilla-monsters-trademark-case-62216/
- [L] Local runs on 2026-11-01: `tmp/research/synthesis/proj/probe*.gd` (Godot 4.7.2 Environment, sky, light and camera defaults and enums), `scripts/macro_graph.py` (travel matrix), `scripts/ascii_plan2.py` (§7.4 plan), and a read-only run of `tools/map/validate_graph.py` (C1–C11).
