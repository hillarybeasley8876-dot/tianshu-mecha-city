# 天枢 TIANSHU — MECHA CITY demo: SPEC (lead-owned)

Detail sources (read the sections your brief names): `ref/research/skills-catalog.md` (kit, frame data),
`ref/research/juice-impact.md` (feel), `ref/research/feel-mech-games.md` (movement/camera),
`ref/research/level-design-vertical.md` (map), `ref/research/city-art-direction.md` (look).
**Scale rule:** the skills/juice dossiers assume an 8 m hero. Our hero is 16 m: multiply their skill REACH,
RADII and projectile SPEEDS by S = 2; keep TIMES, frame counts, damage, HP, EN costs and percentages.
Movement and weapon ranges are NOT scaled that way: use the explicit numbers in §4–§6 of this file.

## 1. Pillars
1. **Mech power fantasy with weight and speed** — a 16 m machine that skates, dashes and flies at
   highway speeds but lands like a building falling. Every input answers within 2 frames.
2. **A rich, readable kit** — shoot, charge, slash, parry, catch-and-return, blink, grapple, drones, barrier,
   missiles, slams, overdrive. Kit verbs chain into payoffs (mark→drones, impact→stagger→execution,
   prime→detonate). Nothing is filler.
3. **Impact you can feel** — local hit-stop, layered sound, shake, decals and wrecks that stay.
4. **A vertical city worth looking at** — 4–5 stacked layers, loops not dead ends, landmarks on every
   horizon, a lit and atmospheric future megacity (art bible: `docs/ART.md`).
5. **Tension** — a colossal monster walks the skyline from minute one; nests pulse; sirens; the music
   rises with the threat.

## 2. Scale and world
Hero 16 m (crest) / cockpit eye ≈ 12 m. Map: "Escarpment City around the Spire", one district of the
megacity 云阙 YUNQUE, playable 1.4 × 1.4 km (+200 m skyline ring), datum layers L0 −40 / L1 0 / L2 +32 /
L3 +80 / L4 +128…+176 / Crown +224, the Spire 360 m with a tether into the sky. Map contract: `docs/MAP.md`.
Physics 120 Hz.

## 3. Controls (actions in `core/input_setup.gd`; gamepad via `core/pad_input.gd`)
| Verb | KB+M | Pad |
|---|---|---|
| Move / look | WASD / mouse | LS / RS |
| Fire (hold = charge; gatling vent press) | LMB | RT |
| Aim / zoom (ADS) | RMB | LT |
| Jump / hold hover / double-tap = flight | Space | A |
| Descend (flight) | Ctrl | B held while flying |
| Dash (tap) / boost skate-glide (hold, sustained) | Shift | B |
| **Assault boost (toggle)** | Left Alt | L3 |
| Melee (combo, charged, lunge, plunge, execution) | F | X |
| Guard (tap parry, hold block, hold ≥0.3 s catch field) | Q | LB |
| Hailstorm missiles (hold paint, release) | 1 / Mouse4 | RB + RT |
| Skyhook anchor | E | Y |
| Rift Step | C | RB + B |
| Corona Fins (tap send, hold ward barrier) | Z | RB + Y |
| Shockcore Burst | X | RB + X |
| Undertow Well | G | RB + A |
| Swap primary / reload | wheel / R | D-pad ↑ tap / hold |
| Zenith Overdrive / Lance | V hold 0.25 s / V | L3 + R3 |
| Lock-on toggle / switch | MMB, Tab / mouse flick | R3 / RS flick, D-pad ← → |
| Camera 1st/3rd person | B | View, D-pad ↓ |
RB is a pure shift layer on the pad (no own action), so no verb lifts the left thumb off the stick.
Input buffer 6 f for combos/cancels, tap/hold threshold 0.25 s, chords within 4 f — all on the REAL clock.

## 4. Movement (hero; reconciled by the lead from feel-mech-games §16, level-design §3, skills §4.1)
Principle: **heavy legs, instant thrusters** — mass is sold by legs, landings, camera damping and audio;
responsiveness by thrusters; never add input lag. Tune in `mech_tuning.tres`, start from these.
| Verb | Numbers |
|---|---|
| Walk / run | 9 / 16 m/s (run = legs + thruster assist); walk top speed in 0.35 s, stop 0.25 s; walk→run blend 0.8 s in / 0.3 s out; steps every 0.90 s walk / 0.62 s run; legs turn 180°/s walk, 120°/s run; torso + arms follow aim with a 0.10 s critically damped lag, torso twist ±100° then legs pivot |
| Boost (hold Shift after the dash) | ground skate / air cruise 42 m/s, 0→42 in 0.18 s, turn 160°/s, **sustained for as long as it is held** (never turns into assault by itself); **free on the ground** (EN keeps regenerating); in the air no EN cost but sinks 6 m/s (glide) |
| Dash / quick boost (tap Shift) | 8 directions (camera-relative), 24 m over a 0.25 s jet: peak ≈150 m/s with exponential decay, exits at boost speed; 110 EN; ground reload 0.38 s, ≤3 chained then 0.45 s lockout; **i-frames first 6 f (12 ticks)**; breaks enemy homing on frame 1. Air dash same distance, 130 EN, then a 0.15 s vernier hang. **Perfect dodge**: an enemy hit lands inside the i-frames → `Feel.slow_mo(0.3, 0.35, witch=true)`, +3 % OD, Events.perfect_dodge |
| Assault boost | own toggle (`assault`: Left Alt / pad L3), from the ground, a boost or flight: 0.30 s ignition (FOV +11°), then 84 m/s, yaw 80°/s, pitch 45°/s, 120 EN/s; light weapons fire, melee = **Ram Kick** (850 dmg / 750 impact, ×2.5 vs staggered); cancel with dash or a 0.25 s skid brake |
| Jump | 4 f knee-dip (input still accepted), thruster hop to +8 m apex at 0.45 s |
| Ascend / hover (hold jump) | ascend 18 m/s at 100 EN/s; hover 40 EN/s. Boost-jump apex J = 40 m (hop + ascend) — the level metrics depend on it |
| Gravity / fall | rising per the hop curve (79 m/s²); falling 80 m/s² — as hard as it rises (lead 11-03: 25.5 read as a balloon) — terminal 80 m/s; `descend` held in the air = dive 95 m/s |
| Flight mode (飞行) | double-tap jump in the air: free 3D flight 50 m/s (boost in flight 84 m/s = assault), climb/descend 20 m/s, **80 EN/s and no EN regen while flying**, ceiling +260 m (storm shield: soft push down above it); exits at EN 0 into a glide. All weapons/skills usable; melee = aerial combo |
| Landing | under 8 m/s it is a kerb; soft (< 46 m/s down, e.g. any plain hop at 36): 0.20 s, dash/boost-cancel from 6 f; hard (≥ 46 m/s ≈ 13 m fall): 0.38 s, cancel from 14 f; `land_heavy` feel only ≥ 52 m/s (≈ 17 m fall); landing with EN empty: 0.70 s, no cancel |
| EN | 1,000. Ground regen 500/s after 0.6 s; air regen 120/s after 0.9 s; regen continues during ground boost. Empty (**Outage**): 1.5 s lockout, then instant +250; dash/ascend need ≥ 300 to restart |
| Stepping | floor_snap 0.6 m, step-up 2.5 m, auto-hop obstacles ≤ 7 m while boosting; floor_max_angle 40° |
| Mass cues | footstep camera translate (no rotation in 1st person), landing dip scaled by fall speed, servo/hydraulic layers, leg IK on slopes |

## 5. Camera and aim (feel-mech-games §16.2/16.4; Godot fov is VERTICAL)
Third person (lead decision after camera r2): framing wins — at rest the hero spans ≈ 40 % of the screen
height, body centred at ≈ 32 % of the width, crosshair clear by ≥ 6 % (arm 42 m; boost 46, assault 52;
ADS arm 34 m with FOV 38° ≈ 60 % height; arm pulls in on collision as specified). Pivot at the chest (12.5 m), default
pitch −6°, sphere r 1.5 m margin 0.5 against large static geometry, pull in instantly, push out 10 m/s after
0.25 s, occluding buildings dither to 30 %. Vertical FOV 55° (boost 60°, assault 66°, ADS 38°; in 0.25 s
expo, out 0.40 s; dash punch +3°). Follow spring 10 rad/s walk, 7 boost, 14 sideways during a dash; mouse
rotation unsmoothed; gamepad yaw ≤ 300°/s, pitch 180°/s, response exponent 2.0.
First person: cockpit eye at 11.5–13.5 m (model `cockpit` socket), vertical FOV 62° (ADS 45°), frame ≤ 18 %
of the screen, HUD on the glass, footstep −0.12 m translate spring (k 65 d 15), landing dip −0.35…−1.2 m,
cockpit mesh lags turns 80 ms, damage rotates the cockpit mesh ≤ 1.5° (never the view). 1st↔3rd blend
0.35 s keeping the aim point. Toggle with B at any time.
Aim: soft lock auto-acquire within 7° (mouse) / 10° (pad) of the reticle ≤ 300 m with LOS, lead prediction;
pad aim slowdown 0.55× inside the cone. Hard lock toggle ≤ 450 m, camera yaw tracks the target (critically
damped 9 rad/s), strafing orbits the target, **never auto-switches**; switch by stick flick / mouse wheel
(nearest in that direction); kept while inside 1.5× the cone or hidden ≤ 0.5 s. Reticle red = target in
the weapon's effective range, green otherwise. Missile paint box 24°×16°.
Engagement bands: close ≤ 80 m, mid 80–180 m, long 180–300 m; city sightlines ≤ 350 m.

## 6. Combat kit — implement per `skills-catalog.md` §4.1–4.7 (scale rule above; explicit numbers here win)
| Kit element | Dossier § | Unit | Notes / deviations |
|---|---|---|---|
| EN / HEAT / OD / Marks / Stability / Primed | 4.1, 4.6 | mech-move (EN, OD), enemies (marks, stability, primed) | OD target fill 60–90 s |
| P1 Pierce-Light Rifle (贯光步枪) + 2-stage charge | 4.2 | weapons | hitscan; full damage ≤ 200 m, 60 % at 350 m, cut-off 500 m |
| P2 Thunder Spindle Gatling (雷纺机炮) + active vent | 4.2 | weapons | projectile speed 900 m/s |
| Dawn Edge saber (曦刃): L1–L3, lunge, charged slash + wave, air L1–L2, Return Cut | 4.3 | melee-defense | reach/arcs ×2 |
| Core Rend execution + JACKPOT | 4.6 | melee-defense (+camera for the mini-cinematic) | |
| S1 Rift Step (裂隙步) | 4.4 | skills | |
| S2 Skyhook Anchor (天钩锚) + anchor nodes in the city | 4.4 | skills (+city-blockout places `&"anchor_node"` markers) | |
| S3 Hailstorm Volley (雹暴齐射) | 4.4 | weapons | 12 locks at 0.10 s, range 300 m, missiles 120→200 m/s |
| S4 Corona Fins (日冕翼片) + Corona Ward barrier (防护罩) | 4.4 | skills | the fins ARE the hero's six wing blades (hero model sockets `wing_l/r`) |
| S5 Mirror Guard (镜返盾): perfect parry, block, catch field | 4.4 | melee-defense | shield on the left forearm |
| S6 Shockcore Burst (震核爆) | 4.4 | skills | |
| S7 Undertow Well (暗流引井) + COLLAPSE detonation | 4.4 | skills | |
| S8 Plunge Breaker (坠击破) | 4.4 | skills | |
| Zenith Overdrive (天顶超驱) → Zenith Lance (天顶光枪) | 4.5 | skills | beam 800 m long, 16 m wide |
Hit-stop / shake / rumble per `docs/FEEL.md`; every listed move gets its FEEL row.

## 7. Enemies (biomechanical 蚀骸 HUSK swarm; models from Tripo)
| Type | Size | HP / Stability | Behaviour, telegraphs, counters |
|---|---|---|---|
| Ripper 裂爪 (swarmer) | 6 m long, insectoid | 300 / 150 | packs of 6–16; flank, leap-bite (parryable, 0.45 s crouch telegraph); climb ramps; die in 1–2 rifle shots |
| Mantis 镰影 (stalker/duelist) | 14 m biped, blade arms | 1,800 / 700 | 3-hit parryable combos (white glint 0.35 s before each), unblockable red grab (0.6 s), sidesteps shots, pairs |
| Spitter 酸巢 (artillery) | 12 m tall quadruped | 2,400 / 900 | keeps 150–300 m away on high ground; lobs acid arcs (catchable/reflectable), spore-chaff cloud eats 4 missiles; weak sac on back |
| Harrier 鸣翼 (flyer) | 16 m wingspan | 900 / 300 | strafing runs, dive bombs (unblockable, 0.5 s screech), circle at 60–120 m; grapple-able |
| Juggernaut 裂山 (brute) | 22 m, armoured front | 7,000 / 2,600 | charge (unblockable, 0.7 s roar + ground glow), ground-slam shockwave ring (jump it), armour plates break; glowing weak point on the back (×2.5) |
| Brood Titan 巢母 (boss) | 90 m colossus | 60,000 / 9,000 | 3 phases: stomps + swarm births; beam breath sweep (dodge vertically); exposed cores on shoulders/back (each 8,000); seen walking the skyline from the start |
Per-type numbers and AI in the enemies brief; archetype attack HitInfo sets parryable/unblockable truthfully.

### 7.1 Balance model (critic P0 #4; the gate is `enemies/tests/test_ai.gd`, which prints DPS per attack, TTK per archetype and incoming-damage time-to-death every run)
- Player sustained single-target DPS ≈ 1,000 mixed (rifle 540–575, gatling 555–700, missiles 240, fins 88–264);
  OD fills in 60–90 s of fighting.
- Time-to-kill targets: Ripper ≤ 0.5 s, Harrier 2–4 s, Spitter 4–6 s, Mantis 6–10 s, Juggernaut 20–30 s.
- Incoming damage: a player who never defends under full attack tokens (3 melee + 2 ranged; "full" = the pool at
  capacity: every slot held or in its re-grant delay while another monster of that kind is asking) dies in 25–35 s;
  a median run finishes a hive at 30–60 % HP. Enemy attack damage is tuned to this, not invented.
- Brood Titan: **150,000 HP** main pool (phase uptime targets P1 90 s, P2 120 s, P3 90 s at ~50 % uptime);
  3 cores × 8,000 (core hits count ×1.0 to the main pool and ×2.5 to the core pool); core → attack removed:
  L shoulder → swipe, R shoulder → summon, chest → beam breath; Core Rend on the Titan = 12 % max HP, not lethal.
- Telegraphs: parryable glint onset ≥ 400 ms before contact (273 ms reaction + input/display + buffer), the
  perfect window is the last 167 ms; unblockables ≥ 600 ms (boss ≥ 800 ms) with a distinct sound + shape cue
  (never colour alone — accessibility).
- Hive Spire: 4 pods × 3,500 + core 6,000 = 20,000 HP.
- Checkpoints: start, each destroyed hive, and each boss phase (respawn at 100 % HP, boss restored to the
  phase threshold).

## 8. Demo flow and tension curve (~20–25 min)
1. **Title** (hero on a lit hangar platform, skyline behind) → **drop-in**: the hero falls from a carrier
   into the Plaza district (0:00), tutorial prompts appear contextually (move, dash, shoot, melee, guard).
2. **First contact** (Ripper pack at the plaza, then a Mantis pair).
3. **Open district**: destroy 3 **Hive Spires** (蚀巢) in any order (Harbor, Old Town stacks, Sky Garden),
   each guarded by escalating mixes (Rippers + Spitters → + Harriers → + Juggernaut). Roaming packs and
   flyer patrols between. The Brood Titan walks the skyline the whole time; each destroyed spire makes it
   roar and change course toward the player.
4. **Boss**: after the third spire the Titan breaks into the central Spire Plaza; fight across ground, decks
   and sky bridges; phase 3 on the rooftops at sunset/storm light.
5. **Victory**: slow-mo kill, orbit camera, stats (time, max combo, parries, executions), credits.
Music intensity: explore 0.2 → contact 0.5 → spire fight 0.8 → boss 1.0; stingers on stagger/kill/phase.
Death → respawn at the last cleared spire with full HP (no lives).

## 9. HUD (per skills-catalog §4.9 + juice §8)
Reticle cluster (EN arc left, HEAT arc right when gatling), twin-arc skill hotbar, OD ring bottom centre,
weapon + ammo/charge, lock markers + missile lock count n/12, enemy plates (HP, stability, marks, primed),
boss bar, hit markers (normal/weak/kill), damage numbers (toggle), style meter (D→SSS), objective + compass
with spire markers, mini radar (300 m). 1st person: diegetic canopy version. Menus: title, pause (resume,
settings, controls, quit), settings (sensitivity, invert, FOV, shake, aim assist, volumes, quality),
game over, victory.

## 10. Hero animation ids (HeroModel.play_action / set_locomotion)
Locomotion states: `idle walk run coast slide assault hover fly fall land_light land_heavy` (`coast` = decelerating run). Actions: `dash_f dash_b
dash_l dash_r jump fire_r charge_r gatling_spin reload melee_l1 melee_l2 melee_l3 lunge charge_slash
air_l1 air_l2 return_cut execution guard_up parry catch_hold catch_release missile_launch anchor_fire
rift_out rift_in fins_send ward burst well_throw plunge_dive plunge_land overdrive_ignite lance_fire
hit_light hit_heavy stagger death`. Aim layer: upper body follows `set_aim(point)`.

## 11. Audio
Bus layout and sourcing per `ref/research/audio-music.md`. Every Events signal and every FEEL row has a
sound; layered impacts (transient/body/sub/mech/tail). Music: adaptive stems (explore/combat/boss) with
intensity control and stingers.

## 12. Quality and performance
Presets low/medium/high. Target 60 fps @1600×900 high on M1 Max in the boss fight. Budgets in CONTRACTS §2.
