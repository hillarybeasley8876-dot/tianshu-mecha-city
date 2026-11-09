# How the best mech action games create speed, weight and combat flow (with numbers)

Research key: `feel-mech-games`. Compiled 2026-11-01 for the lead designer (Claude Opus) and the MiniMax-M78 implementation briefs.
Reference images: `ref/images/feel-mech-games/` (17 images; per-image lessons in `sources.md`; contact sheet `_sheet.jpg`).

**Conventions**
- Frames assume 60 fps: 1 f = 16.7 ms.
- Titanfall 2 (TF2) engine units are converted at 1 u = 1 inch = 0.0254 m. Check: the titan hull is 235 u = 5.97 m, which matches the official "about twenty feet tall" [TF17].
- AC6 speed values are garage stats, recomputed with the data-mined ac6-advanced-garage formulas [AC2][AC5]. The community reads them as km/h [AC11], so their m/s equivalents are marked (estimate).
- Anything derived rather than read is marked **(estimate)**.
- Source keys like [TF2] resolve to URLs in §18.

---

## 0. The short version

1. **Heavy legs, instant thrusters.**
   - TF2 titans need 0.25–0.55 s to reach walk speed and 1.0 s to ramp into sprint. Their dash, by contrast, is a 0.10–0.30 s burst at 15–20 m/s [TF1–TF5].
   - An AC6 Quick Boost jet lasts 0.26–0.38 s on common boosters [AC3].
   - Weight is sold by legs, landings, camera damping and audio. Responsiveness is sold by thrusters. Never slow the thrusters to fake mass.
2. **Movement spends a resource that refills best on the ground.** This creates the launch → fight → land → relaunch tempo that players call "flow".
   - AC6 EN: 0.5–1.3 s recharge delay on most generators, or 1.2–3.2 s after redlining [AC2][AC3].
   - EXVS boost refills only on landing. Landing lag grows from 26 F to 42 F as the gauge empties [EX1].
   - Mecha BREAK regenerates EN about 6× faster on land than in the air (Alysnes: 5,470 vs 880) [MB1].
3. **The satisfying action must also be the winning action.** In AC6, impact fills the enemy's ACS bar. That causes "several seconds" of stagger, during which every follow-up is a high-multiplier "direct hit" [AC1]. FromSoftware built this explicitly as a "success moment inside the fight" [AC1]. Chinese players attacked Mecha BREAK because its "爽点和赢点分开了" (the fun moments and the winning moments are decoupled) [MB7].
4. **Lock-on must be explicit and sticky.**
   - Daemon X Machina had no hard lock, so 3D fights became "a constant balance of trying to keep targets lined up" [DX1].
   - Mecha BREAK players hate its lock delay, losing the lock when the target leaves the circle, and auto-switching to the wrong foe [MB2].
   - EXVS turns the reticle red when homing works and green when it does not [EX2].
   - ZOE2 turns lock-on strafing into an orbit on a sphere around the target [ZO1].
5. **In first person, never rotate the view without player input.**
   - Respawn's rule: "Any time we move the view without your input that can cause motion sickness" [TF15].
   - TF2's footstep jolt is a 10–15 cm vertical translation with no rotation [TF2–TF4].
   - Hawken slightly delays the cockpit mesh behind the mouse and rattles it when mechs pass [HW1].
   - MW5 players report that heavy cockpit sway makes fast mechs feel *less* responsive than slow ones [MW1][MW2].
6. **Express class weight through damping, not input lag.** TF2's view-punch springs:
   - Light chassis: bouncy (k 35, d 9, 0.61 Hz, half-life 0.15 s).
   - Medium chassis: k 65, d 15.
   - Heavy chassis: over-damped with no overshoot (k 95, d 30) [TF8].
   - Heavy single-shot weapons get a big kick with a slow, non-bouncing return; rapid-fire weapons get kicks of −0.05° to −0.2° [TF8][TF11].
7. **Landing is a gameplay beat, not just an animation.** EXVS punishes landings (26–42 F) [EX1]. Respawn found that a view spring scaled by fall height made landings "feel way more real, even though the movement code was identical" [TF15]. Gundam Evolution was criticised for lacking exactly this: "more of a penalty after landing" [GE1], "floaty… no sense of momentum" [GE2].

---

## 1. Armored Core VI: Fires of Rubicon (FromSoftware, 2023)

**Design intent (primary source)** [AC1]
- Miyazaki's guiding pillar for the initial direction: "人間にはできない、拡張されたアクション" (expanded actions humans cannot perform).
- The team focused on what only a machine can do: "evade and attack at the same time" and "use several weapons at once".
- Director Yamamura places average speed between the AC3 and ACV lines. Speed was deliberately lowered "to a level where attack and defence can be seen". Combat distance was set closer than in earlier games, so perceived speed stays high with sharper tempo swings.
- Leg types add verbs: tank drift-turn, tetrapod hover.
- Each weapon is given its own motion, recoil handling and bullet behaviour.

**Controls (PlayStation)** [AC7]
- ○ boost, × jump/ascend, □ Quick Boost, L3 Assault Boost, R3 Target Assist (hard lock).
- Four weapons sit on L1/L2/R1/R2 (shoulder and hand weapons).
- OS Tuning unlocks Boost Kick, Quick Turn and Manual Aiming [AC8].

### 1.1 Movement verbs

All values are garage stats computed with the data-mined formulas [AC2][AC3]. Columns are total AC weight. Booster sample: ALULA/21E, BST-G2/P04, BUERZEL/21D.

| Verb | Formula | 55 t (light) | 70 t (medium) | 90 t (heavy) |
|---|---|---|---|---|
| Boost speed | Thrust × 0.06 × weight curve (1.0 at ≤40 t → 0.65 at 120 t) | 342–380 | 317–352 | 268–298 |
| Quick Boost (QB) peak | QBThrust / 50 × curve | 337–404 | 314–377 | 280–336 |
| QB jet duration | booster stat | 0.26–0.38 s (range over all boosters: 0.26–0.54 s) | same | same |
| QB reload | base × curve over (weight − ideal weight) | 0.35–0.91 s | 0.42–0.91 s | 0.68–0.98 s |
| QB EN cost | 480–740 EN per QB (11–33% of the bar) | ≈3–9 QBs from a full bar (cap 2,240–4,420) | same | same |
| Assault Boost (AB) | ABThrust × 0.06 × curve | 479–525 | 464–508 | 398–435 |
| Upward (ascend) | UpwardThrust × 0.06 × curve | 284–312 | 264–291 | 236–259 |

**Overweight.** When load exceeds the leg limit, all speeds are multiplied by 0.95 at +5% load, 0.8 at +10% and 0.7 at +50% [AC2].

**Free horizontal boost.** The booster data has EN-cost fields only for upward thrust, QB, AB and melee thrust. There is no cost for standard horizontal boosting [AC3]. In other words, AC6 makes cruising free and charges EN for vertical moves, bursts and AB (inference from the data schema).

**Scale.** A community in-game measurement puts an AC at about 10 m tall (range 7.0–13.2 m) with speeds of 135–605 km/h [AC11]. Read as km/h:
- Boost = 75–105 m/s, about 7–10 body heights per second (estimate).
- One QB covers about 20–40 m, about 2–4 body heights (estimate: peak × jet time).
- Players call a boost stat of 330 or more "fast" [AC19].

**Assault Boost** [AC9]
- "Movement is largely locked into a straight line, turning while boosting is slow and heavily restricted."
- Most weapons can still fire during AB; weapons that need the AC to brace cannot.
- Yamamura describes AB as the high-speed approach for landing direct hits on an enemy staggered at range [AC1].

**Boost Kick (unlocked by OS Tuning)** [AC9][AC2]
- Turns AB momentum into a kick. Damage scales with total weight and AB thrust. Reverse-joint legs kick hardest [AC9].
- Data: base damage 350 (biped) or 420 (reverse-joint), times a weight curve from 1.0 (≤50 t) to 2.0 (130 t). The direct-hit kick is 2.8× that, i.e. 1,030–1,980 for 55–90 t builds [AC2].
- Kick impact / accumulative impact: biped 480/210, reverse-joint 700/320, tank 590/270, tetrapod 360/160 [AC2].

### 1.2 EN economy

Sources: [AC2][AC3][AC6].
- EN capacity: 2,240–4,420.
- Recharge delay after normal use: 1000 / ENRecharge × (2 − core supply adjustment). This gives **0.50–1.31 s** for most generators; the two Coral generators take about 4 s.
- After redlining (bar fully spent): delay is 1000 / SupplyRecovery = **1.2–3.2 s**. The bar then jumps instantly by a "post-recovery" refill of 280–3,100 EN.
- Supply rate depends on spare generator output: 1,500 EN/s at 0 surplus, 9,000 EN/s at 1,800 surplus, 16,500 EN/s at 3,500 surplus. A typical build refills fully about 0.3–0.7 s after the delay ends. Full cycle: about 0.8–1.8 s (estimate).
- Official tooltip for the delay stat: "Determines how long until your Energy replenishes upon being grounded" [AC6].
- AB drains about 320–435 EN/s, giving roughly 5–14 s of AB from a full bar (estimate).

**Read.** The bar is short (≈3–9 QBs) but refills in about a second. Redlining is punished with roughly double the delay; spending EN is never punished. The resulting rhythm: burst, breathe for 1 s, burst.

### 1.3 ACS, stagger and direct hits

- Every weapon has Attack Power and Impact. Impact fills the target's ACS bar. When it overloads, the target is "数秒間の動作不能" (unable to act for several seconds). Every follow-up during stagger counts as a **direct hit** [AC1][AC10].
- Purpose, in FromSoftware's words: "区切りとなる成功体験" (a punctuating success experience inside a battle) [AC1].
- Direct-hit multiplier (DirectHitAdjustment) per weapon class [AC3]:
  - Missiles: 125–175%.
  - Shotguns: 180–190%.
  - Charge-type weapons: 125–220% (linear rifles 220%).
  - Melee: up to 270%.
- Attitude Recovery (how fast impact decays) = 100 × a weight curve: 1.5 at 40 t, 1.2 at 60 t, 0.9 at 80 t, 0.6 at 110 t [AC2]. Light ACs shed impact faster.
- Shield "initial guard": the shield is stronger for about 1 s after it is raised [AC1].
- 3 repair kits per mission make HP a risk-management decision [AC1].
- Criticisms:
  - Some enemies break stagger in "maybe a third of a second" [AC20].
  - Heavy builds trivialise content, most fodder enemies stand still, and invisible walls fence every arena [AC18].

### 1.4 Lock and aim

- **Soft lock (FCS).** Engages automatically when an enemy is in sight and in range [AC15] and leads shots [AC13].
  - The FCS has separate assist values for close, medium and long range. The community tool plots these bands as ≤120 m / 140–250 m / ≥270 m [AC4].
  - Weapon ideal ranges [AC3]: shotguns 88–102 m, handguns 85–90 m, machine guns 114–130 m, rifles about 171 m (effective about 310 m), laser rifles 190–240 m, sniper 280 m.
- **Hard lock (R3).** The camera stays on the target and aim goes to centre of mass. Players say the game itself warns that hard lock reduces FCS performance [AC13][AC14]. A Chinese guide: with soft lock "you must turn the camera yourself to keep the enemy in view"; hard lock adds an outer ring to the HUD [AC16].
- **Missile lock.** 4/8/12-missile packs lock in 0.4/0.8/1.4 s, about 0.10–0.12 s per lock [AC3].
- **Community debate (NGA)** [AC17]:
  - Lock-on and turn speed used to be how AC balanced light against heavy mechs ("like TTK and aim assist in shooters").
  - Hard lock makes tracking trivial.
  - EXVS can rely on hard lock because it "was designed around hard lock from the start".

### 1.5 Camera and mass

- **FOV.** A FOV mod lists the default as "45 FoV" and its replacement values as "64 (96 horizontal)". That makes the default 45° vertical, about 73° horizontal at 16:9 [AC12] (estimate). The narrow, telephoto view makes ACs look big and compresses depth; speed reads through parallax, exhaust and sparks.
- **HUD.** Everything sits on the reticle ring: target AP and ACS arcs, missile lock arc, four weapon arcs and a distance readout (image 01). The player's own ACS bar is bottom-centre (image 03).
- **Weight perception.** Some players call AC mechs light "because it's a hallmark of the series", versus MechWarrior's clunkiness [AC21].

---

## 2. Titanfall 2 (Respawn, 2016)

All values come from the shipped multiplayer script files mirrored in the Syampuuh/Titanfall2 repository, a community dump of the game files [TF19].

### 2.1 Chassis tuning

| Chassis (titans) | Walk | Sprint | Accel / decel | Dash speed, time | Dash stop speed | Dashes, refill per dash | With Turbo Engine | View-punch spring | Step jolt | Sprint roll |
|---|---|---|---|---|---|---|---|---|---|---|
| Stryder (Ronin, Northstar) | 6.86 m/s | 10.16 m/s | 25.4 / 45.7 m/s² | 20.3 m/s, 0.10 s | 11.4 m/s | 2 dashes, 5.0 s each | 3 dashes, 5.0 s each | k 35, d 9 (0.61 Hz, half-life 0.15 s) | −15 cm | 4° |
| Atlas (Ion, Tone, Monarch) | 6.35 | 9.65 | 22.9 / 38.1 | 17.8 m/s, 0.20 s | 11.4 | 1 dash, 6.0 s | 2 dashes, 6.0 s each | k 65, d 15 (0.47 Hz, half-life 0.09 s) | −13 cm | 3° |
| Ogre (Scorch, Legion) | 5.33 | 7.87 | 9.7 / 30.5 | 15.2 m/s, 0.20 s | 8.9 | 1 dash, 10.0 s | 1 dash, 5.0 s | k 95, d 30 (over-damped, no bounce) | −10 cm | 2° |
| BT-7274 (campaign) | 7.11 | 10.67 | 22.9 / 38.1 | 17.4 m/s, 0.30 s | 8.9 | 2 dashes, 4.2 s each | — | as Atlas | −13 cm | 3° |

Sources: [TF2][TF3][TF4][TF5][TF6][TF8].

**How to read the dash columns**
- Dash count = 100 / dodgePowerDrain. Refill time per dash = drain / powerregenrate.
- The wiki describes Turbo Engine as "1 extra dash" for Ronin, Northstar, Ion, Tone and Monarch, and "reduced dash cooldown" for Legion and Scorch [TF18].
- Minimum interval between dashes: 0.2–0.35 s. Dash animation: 0.5 s. Regen restarts 0.2–0.3 s after a dash [TF2–TF4].
- Dash distance is about 4–6 m, i.e. 1–1.5 hull widths (estimate from speed × time plus deceleration).
- Spring maths comes from Respawn's own comment in springs.txt: frequency = √(4k − d²)/(4π), half-life = 1.386 / d [TF8].

**Shared titan settings** [TF1]
- Eye height 4.70 m in a 3.05 × 5.97 m hull.
- FOV 75 for titans vs 70 for pilots [TF1][TF7].
- Titans cannot jump, double-jump, wall-run or slide. They auto-step up 2.0 m (0.34 × hull height).
- Sprint ramps in over 1.0 s (sprint acceleration only 3.0–4.6 m/s²) and ramps out over 0.3 s.
- Footstep interval: 700 ms walking, 415 ms sprinting.
- Titans take 40% of damage impulse (knockback) on the ground and 10% in the air.
- Footsteps damage small entities: active above 50 u/s, applied every 100 u travelled.

**Read.** Top speeds differ by only about ±15% between classes. Mass is expressed through acceleration (the heavy chassis needs 0.55 s to reach walk speed vs 0.27 s for the light) and through view-punch damping (light bounces, heavy settles without overshoot).

### 2.2 Cores and abilities

| Core | Titan | Core build time | Wind-up | Active duration |
|---|---|---|---|---|
| Sword Core | Ronin | 120 s | 0.75 s | 12 s multiplayer / 20 s campaign; +1,400 melee damage |
| Flight Core | Northstar | 150 s | 0 | 6 s |
| Laser Core | Ion | 150 s | 1.1 s | 3.5 s multiplayer / 6.5 s campaign |
| Flame Core | Scorch | 150 s | 0.75–0.85 s | 0.5 s wave; 4,500 damage vs titan armour |
| Smart Core | Legion | 150 s | 0 | 12 s (18 s with mod) |
| Salvo Core | Tone | 150 s | 0.5 s | 2.0 s volley |
| Upgrade Core | Monarch | 100 s | 0 | instant (permanent upgrade) |

Sources: [TF9]. Other abilities: Phase Dash (Ronin) lasts 1.0 s with a 12.5 s recharge; Hover (Northstar) lasts 2.75 s with a 10 s recharge [TF12].

### 2.3 Weapon feel

Recoil spring values come from springs.txt [TF8]; everything else from the weapon files [TF11].

| Weapon (titan) | Fire rate | Mag | ADS FOV / zoom time | Kick per shot | Recoil spring (k / d → behaviour) |
|---|---|---|---|---|---|
| Leadwall (Ronin) | 2.5/s | 4 | 55° / 0.2 s | −2.25° pitch, −0.95° yaw | 300 / 30 → 1.4 Hz, half-life 0.05 s (snappy) |
| Plasma Railgun (Northstar) | 0.9/s, 2.25 s charge | 6 | 50° (38° with mod) / 0.2 s | −3.5° × 2.8 view punch | 35 / 9 → 0.61 Hz, half-life 0.15 s (big, slow) |
| Splitter Rifle (Ion) | 9/s | 40 | 55° / 0.35 s | −0.05° | 55 / 8 |
| T-203 Thermite (Scorch) | 1.7/s | 1 | 50° / 0.1 s | −1.2° × 1.85 | 60 / 27 → over-damped, about 0.28 s (heavy thump) |
| Predator Cannon (Legion) | 15/s | 100 | 1.5 s in, 0.75 s out | 0 | 35 / 12 |
| 40mm Tracker (Tone) | 1.75/s | 12 | 50° / 0.1 s | −1.2° × 1.85 | 60 / 27 |
| XO-16 (Monarch) | 12/s | 40 | 50° / 0.2 s | −0.2° | 55 / 8 → 1 Hz, half-life 0.17 s |

**Melee** [TF10]
- Punch: range 6.6–7.6 m, 0.8 s swing, 1.0 s recovery, 500 damage.
- Sword: range 8.3 m, 0.9–1.2 s swing, 0.5 s lunge onto targets within 2.5 m / 45°, 625–800 damage.
- Both freeze aim input for 0.25 s on hit (`melee_freezelook_on_hit`).

### 2.4 The first-person cockpit

**View** [TF1][TF2–TF4][TF7]
- FOV 75 for titans vs 70 for pilots. Pilot slides scale FOV by 1.1 with 0.25 s lerps.
- Embarking plays a 2.05 s LCD start-up effect.
- Each footstep jolts the cockpit 10–15 cm downward, with no rotation. Sprint roll is capped at 2–4°.

**Sway** [TF7]
- Factors: turn angle −0.6, turn roll 0.2, turn origin −0.15, move angle −0.4, move roll −0.2, move origin −0.15, gain 5.0.
- The cockpit leans and lags opposite to the turn, then settles quickly.

**Damage feedback** [TF13]
- Jolt direction runs from the hit to the camera. Severity = clamp(damage / 2,000, 0, 1).
- Spark effects: 3 per 1,000 HP crossed, 20 on "doomed".
- EMP calls ClientCockpitShake(amplitude 0.25, frequency 3, duration 1.0 s). The developer comment says it "looks a bit artificial".

**Rumble envelopes** [TF14]
- Base graph "quickStrong" is 100% for 0.20 s, falling to 0 at 0.25 s.
- "longMedium" decays from 0.45 to 0 over 1.0 s.

| Event | Heavy motor | Light motor |
|---|---|---|
| Titan footstep | 0.25 power, 50 ms (off at 62 ms) | — |
| Soft landing | 1.0, 130 ms (off at 163 ms) | — |
| Hard landing | 2.0 scale (saturates), 190 ms | 0.4, 300 ms |
| Dash | 0.8, 100 ms, cut off | decaying from 0.9 over 1.0 s |
| Phase dash | 1.0, 100 ms | decaying from 1.35 over 1.0 s |
| Melee hit | 1.0 for 0.5 s, off at 0.75 s | 1.0 for 0.5 s → 0.5 at 0.75 s → off at 1.0 s |
| Sword hit | 0.8 for 0.5 s | tail to 2.0 s |
| Damage: small / medium / big | — / — / 0.5, 150 ms | 0.65 → 0 over 0.2 s / 1.0, 150 ms / 1.0, 150 ms |

**Design interview** [TF15]
- Halo: CE's second level was the benchmark.
- View bob with the crosshair fixed at screen centre made players feel they were "constantly looking left-right", which caused nausea. The team's rule: "Any time we move the view without your input that can cause motion sickness."
- The landing view spring's depth is proportional to fall height. It made landing "feel way more real".
- Wall-run tilt starts *before* contact, as anticipation.

**Audio** [TF16]
- Titans were built from self-recorded metal-on-metal layers.
- Servo sounds came from an Arduino-driven servo, pitched down. Contact-mic recordings of forklifts and factory machines add "chassis resonance".
- A procedural mix weighs sounds by speed, angle, distance and health. Occlusion = attenuation plus filtering.

### 2.5 Pilot/titan contrast

- Pilot sprint is 6.6 m/s [TF1]; titans sprint faster (7.9–10.7 m/s) but cannot jump or wall-run.
- Pilots get their speed from wall-runs and slides — "up to 30 mph, well over double a pilot's sprint speed" [TF15].
- So the contrast is **verticality and momentum tech** (pilot) versus **armour, dashes and cores** (titan), not raw speed.

---

## 3. Gundam Extreme VS. (Maxi Boost ON / EXVS2 line)

A 2v2 arcade game built entirely around boost economy, homing and landing punishes.

| Verb | Rule and numbers |
|---|---|
| Boost dash (double-tap boost) | Large up-front cost, then steady drain. Cancels almost any action. Dashes per full gauge by unit cost: 3000 → 8, 2500 → 7, 2000 and 1500 → 6 [EX1]. Holding a dash empties the gauge in about 4.3 s for every unit [EX1]. Dashing straight back has a penalty of roughly 10% [EX1][EX3]. Changing direction mid-dash bends the dash ("swerve") [EX3]. |
| Jump / ascend (hold boost) | Empties the gauge in about 2.5 s for every unit; rise speed differs per unit, drain time does not [EX1]. |
| Step (double-tap a direction) | Cuts homing only in its first instant. A ground step does not leave the ground, and the gauge refills completely when it ends. Steps can be cancelled into steps in another direction at extra cost [EX1]. Rainbow step = stepping out of a melee attack [EX3]. Fuwa-step = step + boost, giving an arcing jump [EX3]. |
| Landing | The gauge refills only on the ground. Landing lag depends on how much gauge is left: up to orange about 0.43 s (26 F), red about 0.46 s (28 F), overheat about 0.70 s (42 F) [EX1]. Overheat adds about 10 F [EX2]. |
| Airborne overheat | After 25 s airborne while overheated, all control is lost; the limit shrinks by 5 s each time [EX1]. |
| Air recovery / wake-up | Air recovery cuts homing and restores some boost. Getting up from the ground gives brief invulnerability [EX1]. |
| Vernier stall | Most special attacks stall you in mid-air while draining boost. Cancel them with a boost dash, or with a free-fall move that drops you immediately (amekyan) [EX3]. |
| Awakening (覚醒) | S and M awakening let you step-cancel standing shots [EX1]. |

**Lock model.**
- The reticle is red when homing ("guidance") works; "think of red lock range as effective range". It turns green when the target is too far, or too far above or below you [EX2].
- Guidance does most of the aiming, so the skill is in timing. Landing is "one of the most fundamental vulnerable periods", and punishing it is a core of the game [EX2].

---

## 4. Gundam Breaker 4 (2024) and SD Gundam Battle Alliance (2022)

**Gundam Breaker 4**
- Two attack buttons map to the left-arm and right-arm weapons. Almost every weapon type can be dual-wielded asymmetrically.
- One-handed weapons have a combo string, a hold-for-heavy attack, and a special move when you switch weapons mid-combo [GB1].
- **Hit gauge**: landing hits continuously fills it and grants buffs. **Break gauge**: breaking enemy parts fills it and raises the drop rate [GB1].
- EX and OP skills draw from one shared EX gauge instead of separate cooldowns, so they can be chained back-to-back [GB1][GB2].
- Hacking parts off enemies is the loot loop [GB2].
- Criticisms: closed wave arenas with teleports between them and no sense of spatial progress [GB1]; weak EX skills, especially melee [GB3].

**SD Gundam Battle Alliance**
- Monster-Hunter-style boss fights. The game "starts off almost deceptively easy, and then layers more and more" (melee, ranged, combos, stun-lock, dodge, dash). Bosses demand the whole toolkit [SD1].

---

## 5. Zone of the Enders: The 2nd Runner (2003; MARS remaster 2018)

**Lock-on movement is spherical** [ZO1]
- While locked on, left/right moves you along the surface of a sphere centred on the enemy, so distance stays constant. Forward/back changes the sphere's radius.
- Without a lock, movement is flat and camera-relative. Releasing the stick swings the camera back behind Jehuty.
- This is the cleanest model for 3D orbit-strafing.

**Burst modifier (R2)** [ZO1][ZO2]
- Gives burst slash (R2+□) and multi-target homing lasers. A "burst dash" (the modifier applied to a dash) is commonly described but was not verified in a primary source here.
- Homing lasers: hold R2+□ while moving to sweep-paint several targets; release to fire.

**Grab** [ZO1]
- Works whenever "GRAB" is shown or the lock cursor turns orange, even at some distance. Jehuty moves in automatically.
- A grabbed object can be used as a shield, a melee weapon, thrown, or swung around. Jehuty is **invulnerable while swinging**.

**Other verbs**
- Opening the sub-weapon menu pauses time [ZO1].
- Zero Shift teleports to the locked target, in a controllable direction, and costs no sub-weapon energy [ZO3].

**Praise.** The blade cuts "like butter", enemies reel sharply on every hit, the boost sound sells speed, and blade clashes feel like "the universe's deadliest fencing match" [ZO4].

**Criticism (MARS).** The camera locks onto the enemy and keeps it near screen centre [ZO5]. Reviewers called the resulting camera changes "seizure inducing" [ZO7] and said it is "easy to be overwhelmed by the speed of the transitions between enemies" [ZO6].

---

## 6. Daemon X Machina (2019) and Titanic Scion (2025)

**Daemon X Machina (2019)**
- Large stamina pool for free boosting on land and in the air.
- Femto "Shift" modes: Wing Shift (speed), Guard Shift (sphere shield), Assault Shift (arm damage) [DX4]. Femto reserves buff damage or speed [DX2].
- **No hard lock**: "most encounters are a constant balance of trying to keep targets lined up". The reviewer deliberately dragged late-game enemies down to the ground [DX1].
- Highlight: Colossal Immortals, where you break armour off and wield the boss's own giant saber [DX1].

**Titanic Scion (2025)**
- Arsenals shrink to about 2.5 m, exosuit scale [DX3].
- Two independent acceleration systems: a stamina-limited short dash and a long-endurance Femto sprint/boost [DX3][DX4].
- Double-tap jump to fly; hovering costs nothing. A flight ceiling plus terrain partitions stop flight from reaching everything [DX3].
- The first melee hit includes a dash-in. Laser swords are overpowered ("lock on, close in, mash the three-hit combo") [DX3].
- A flinch gauge leads to a grab: throw the enemy or rip its armour off. Simultaneous melee hits trigger a blade clash [DX3].
- Fan verdict: "the brisk, high-speed 3D combat feel of Daemon X Machina is gone" [DX5].

---

## 7. Mecha BREAK (Amazing Seasun, 2025)

**Controls (PC)** [MB3]
- Space jumps (hold to fly). Shift is a short dash (hold to boost). Alt in the air is a fast descent.
- The mouse moves a central lock box. Enemies inside it are locked automatically and tagged "锁定". Some skills need a lock first.

**Stat model** [MB1]
- Max EN, with separate land and air regen. Example: Alysnes regenerates 5,470 on land vs 880 in the air (6.2×).
- EN overload disables dash, jump and flight. Recovery waits for a "fuse cooldown", then needs regen up to a "fuse threshold" %. Regen runs at 35% while overloaded.
- Fluid Armor (a regenerating shield) uses the same fuse model.
- Mobility stats exist per state: land dash speed and EN cost, land boost speed, EN per second and time-to-max, the air equivalents, ascend speed, and lock-on range.

**Reviews**
- "Everything in Mecha Break feels amazing… even the slowest ones come equipped with a solid dodge"; execution animations [MB4].
- You must land to recharge. Reviewers note "the heft of trying to get Stego into the air versus the sleekness of Falcon" and a HUD that is busy "yet clean and clear-cut". Melee hit registration is unreliable, and a low ceiling triggers out-of-bounds warnings [MB5].
- The sniper Aquila has a radar skill that raises lock-on range and reticle size and locks six enemies [MB6].

**Criticism**
- "Needs a true lock on system": lock delay, the lock dies when the target leaves the circle, and aim "suddenly changes to the wrong foe" [MB2].
- NGA: the fun moments and the winning moments are decoupled [MB7].
- TapTap: against agile mechs, "don't rely on assisted lock, aim manually" [MB8].

---

## 8. Synduality: Echo of Ada (2025)

- Cradlecoffins are "slower than something you'd find in Armored Core… but faster than the behemoths you'd see in MechWarrior". They are "reasonably fast but still heavy and limited in terms of… vertical mobility" — "Cradlecoffins got no ups" [SY1].
- The back is the weakest point, so players back away facing each other [SY1].
- Takeaway: a heavy, grounded mech can still feel good when the stakes are tense (image 23).

---

## 9. MechWarrior 5 (Mercenaries 2019, Clans 2024) and MechWarrior Online

**Torso twist** decouples aim from the legs.
- MechWarrior Online quirk threads cite 85° torso yaw for one chassis family [MW6]. A MW5 mod exposes twist rates and limits and allows 360° twist [MW8].
- One player argues torso speed "has to be at least double" in mech-control mode [MW5]. Another says decoupled aim "feels like driving a boat" [MW4].

**Cockpit**
- Praised for "bouncing cockpit viewports… sense of weight and velocity" [MW7].
- But heavy sway on Clan mechs makes "slower IS mechs feel more responsive than faster clan mechs" [MW1].
- Another player: mechs "don't feel as massive… because the cockpit sways side to side" [MW2].
- "Ridiculous cockpit bob" is fixed by disabling "Enable Synchronized Locomotion" [MW3].

**Heat.** Firing builds heat and overheating shuts the mech down; no numbers were retrieved.

---

## 10. Hawken (2012; Reborn 2023)

**Khang Le interview** [HW1]
- The cockpit covers about 30% of the screen, so it must be functional: UI lives on the cockpit screens.
- He studied footage of bulldozers and industrial machines: "how your head turns, your vehicle will get delayed behind. Things rattle."
- Turn speed is slower than a typical FPS because "we don't want a mech head to whip around like a human's".
- "We delay how the cockpit follows the mouse slightly." Passing mechs rattle your cockpit.
- Placed "between Halo and MechWarrior". He criticises Armored Core boosting as feeling "like on an airplane".
- Audio: two samples per weapon, swapped by distance; tunnels echo; footsteps heavy but kept "musical" to avoid ear fatigue.

**Mechanics** [HW2][HW3][HW4]
- You cannot fire while boosting forward (weapons lowered), and there is "a slight delay" before weapons come back up.
- Dodge cooldown by class: A 1.0 s, B 1.2 s, C 1.4 s.
- 180° thruster turn: no fuel cost, little delay between uses. Brief flight.
- One fuel bar is shared by boost, dodge and flight.
- Reticle parts spread away from centre when a weapon cannot fire. Hit-confirm triangles flash at the reticle corners. Arms droop during overheat or EMP.

---

## 11. Lost Planet (Vital Suits)

- Vital Suits are bipedal and 2–3× human height. They run on Thermal Energy, which drains constantly and faster when jumping or hovering. Below 100 T-Eng the suit shuts down [LP1].
- Weapons can be detached and carried by the pilot, who must stop to fire them; the suit fires and reloads on the move. Pilots can eject before the suit explodes [LP1].
- Takeaway: the mech as a power-up you are "inside", with a resource keeping it alive.

## 12. Override 2: Super Mech League (2020)

Limb-mapped controls: the shoulder buttons attack with the left and right arms, the triggers with the left and right legs. The reviewer felt "direct control" over the mech, but called it "little more than a gimmick" [OV1].

## 13. Mecharashi (钢岚)

A turn-based tactics game, relevant only as a presentation reference for per-part targeting and destruction ("unique part-destruction combat system") [ME1]. Players praise its diverse mech stats and playstyles [ME2].

## 14. Gundam Evolution (2022; shut down 2023)

- A first-person hero shooter with a thruster gauge and dash. Players found a G-dash technique (half a dash bar, then sprint) [GE4].
- Criticism: "mobile suit movement too fluid/quick" [GE3]; "lack of weight and impact… floaty and too rigid… no sense of momentum" [GE2]. Forbes: suits "need to be a bit heavier still but with more boost… more of a penalty after landing" [GE1].
- Lesson: first person with no cockpit frame and human-FPS movement reads as "people in costumes" (image 22 vs 06/14).

---

## 15. Cross-game synthesis

### 15.1 Movement verb archetypes (H = body height)

| Archetype | Games | Startup | Active time | Distance | Resource / limit | Recovery |
|---|---|---|---|---|---|---|
| Burst dodge | TF2 dash, AC6 QB, EXVS step, Hawken dodge | 0–1 f | 0.10–0.38 s | about 1–4 H | TF2: 1–3 charges at 4–10 s each. AC6: 11–33% EN. Hawken: 1.0–1.4 s cooldown | TF2 0.5 s animation; AC6 reload 0.35–0.98 s |
| Sustained boost | AC6 boost (free), EXVS boost dash, Mecha BREAK boost | ≤0.2 s | until released / gauge empty | AC6 7–10 H/s (estimate) | AC6: none; others: gauge | instant |
| Long boost | AC6 AB, DXM:TS Femto boost | ignition | until EN runs out (AC6 ≈5–14 s) | AC6 ≈1.4× boost | EN | restricted turning |
| Vertical | AC6 ascend, EXVS jump, Mecha BREAK flight | instant | EXVS empties gauge in 2.5 s | — | EN | landing lag |
| Teleport | ZOE2 Zero Shift | — | — | to the locked target | free | camera-whip risk |

### 15.2 Selling mass without sluggishness

| Technique | Evidence | Number to copy |
|---|---|---|
| Slow legs, instant thrusters | TF2 accel/decel and 1.0 s sprint ramp vs 0.1–0.2 s dash [TF2–TF4] | Legs: 0.25–0.55 s to walk speed. Thrusters: ≤0.2 s to full |
| Camera damping by class | TF2 view-punch springs [TF8] | Light k 35/d 9 → medium k 65/d 15 → heavy k 95/d 30 |
| Footstep jolt that only translates | TF2 step jolt and nausea rule [TF2][TF15] | ≤10–15 cm per titan step, no rotation |
| Footstep cadence and rumble | TF2 [TF1][TF14] | 700 ms walk / 415 ms sprint; rumble 0.25 for 50 ms |
| Landing spring scaled by fall | TF2 [TF15] | Proportional to fall height |
| Landing as a punishable window | EXVS [EX1] | 26 / 28 / 42 F |
| Cockpit lag and rattle; slower head turn | Hawken [HW1]; TF2 sway gain 5 [TF7] | Cockpit mesh lags the view slightly |
| Heavy weapon recoil, slow over-damped return | TF2 40mm / Thermite springs [TF8][TF11] | k 60 / d 27, half-life ≈0.28 s |
| Hit freeze | TF2 freeze-look [TF10] | 0.25 s |
| Servo and metal audio, distance-swapped samples | TF2 [TF16], Hawken [HW1] | — |
| Crushing small things underfoot | TF2 footstep damage [TF1] | — |
| Avoid: big cockpit sway | MW5 [MW1][MW2] | — |
| Avoid: floaty, momentum-free bodies | Gundam Evolution [GE1][GE2] | — |

### 15.3 Lock-on models

| Game | Soft assist | Hard lock | Range feedback | Main player complaint |
|---|---|---|---|---|
| AC6 | FCS auto lock with lead; 3 range bands | R3: camera tracks, aims at centre of mass, less FCS help | Distance readout, ideal ranges | Hard lock trivialises tracking [AC17] |
| EXVS | — | The lock drives guidance (homing) [EX2] | Red / green reticle [EX2] | — |
| ZOE2 | — | Lock = spherical orbit; orange cursor = grabbable | Cursor colour | Camera whip [ZO7] |
| Mecha BREAK | Auto-locks anything inside the box | None | Box with name + distance | Lock delay, wrong-target switches [MB2] |
| DXM | Automatic lock-on [DX6] | None | — | Can't keep targets lined up in 3D [DX1] |

### 15.4 What makes a cockpit work

1. The **view stays steady**; the cockpit **mesh** carries the motion [TF15][HW1].
2. A **wider FOV than the on-foot view** (TF2: 75 vs 70) [TF1][TF7].
3. **Directional, damage-scaled jolts plus sparks** that tell you where the hit came from [TF13].
4. A **frame that covers ≤ about 20%** of the screen. Hawken's 30% is a deliberate, costly choice [HW1].
5. **HUD on the glass and the cockpit screens** (images 06, 14, 16).
6. **Audio that is heavy but musical** [HW1][TF16].

---

## 16. Recommended tuning for our hero mech

### 16.1 Assumptions

**The mech**
- Height H = 16.5 m. Hip height about 8.6 m.
- Chest core cockpit with the eye at 11.5 m (0.7 H). Shoulder span about 7 m.

**The district (estimate)**
- 20–40 m streets and 80–150 m blocks.
- Skybridges, elevated highways and rooftops for verticality.

**Physical scaling**
- Froude number Fr = v² / (g·L), with L = hip height. Walk-to-run transition happens at Fr ≈ 0.5; the theoretical walking maximum is Fr 1.0 [PH1].
- At L = 8.6 m that gives walk ≈6.5 m/s (Fr 0.5) and run ≈11 m/s (Fr 1.5) for a big body.

**Speed choices**
- AC6-level boost (7–10 H/s) would cross a 30 m street in 0.2 s, which is unreadable. So cruise is set to about 2 H/s and Assault Boost to about 4.4 H/s (estimate).

### 16.2 Main table

Every value in the middle column is a design recommendation (estimate), derived from the sourced anchors in the right column.

| Parameter | Value for our mech | Anchor |
|---|---|---|
| Walk | 6.5 m/s. Reaches top speed in 0.35 s, stops in 0.25 s. One step every 0.90 s | Fr 0.5 [PH1]; TF2 Atlas 0.28 s to walk / 0.17 s to stop [TF2] |
| Run (legs + thruster assist) | 11 m/s. Walk→run blend 0.8 s in, 0.3 s out. One step every 0.62 s | TF2 sprint ramps 1.0 / 0.3 s; footsteps 700 → 415 ms [TF1] |
| Boost (hold): ground skate / air cruise | 34 m/s (122 km/h, ≈2 H/s). 0 → 34 m/s in 0.18 s. Turn rate 160°/s. **No EN cost** on the ground; in the air, no cost but a 3 m/s glide-down (estimate) | AC6 standard boost costs no EN [AC3]; AC6 speeds scaled down for city streets (estimate) |
| Quick Boost (tap, 8 directions relative to camera) | 16 m (≈1 H) over a 0.24 s jet. Peak ≈115 m/s with exponential decay (time constant ≈0.19 s): ≈65% of the distance is done by 0.12 s, and the dash exits at ≈34 m/s, i.e. boost speed. 0.10 s blend back to the previous velocity. Costs 14% EN. Reload 0.38 s (0.30 s light / 0.60 s heavy loadout). Breaks enemy homing on frame 1 | AC6 jet 0.26–0.38 s, reload 0.35–0.98 s, 11–33% EN per QB [AC2][AC3]; EXVS step cuts homing at the start [EX1] |
| Air Quick Boost | 16 m for 16% EN, then a 0.15 s "vernier" hang unless cancelled by firing or another QB | EXVS vernier [EX3] |
| Assault Boost (toggle) | 0.30 s ignition (exhaust flare, FOV +11°), then 72 m/s (≈4.4 H/s). Yaw 80°/s (≈52 m turn radius), pitch 45°/s. Drains 9% EN/s (≈11 s). Light weapons can fire; heavy weapons need bracing. Cancel by QB or a 0.25 s skid brake | AC6 AB ≈1.4× boost, turning "heavily restricted", bracing weapons excluded [AC9][AC2] |
| AB Kick (melee input during AB) | 0.20 s lunge. Damage scales with speed. ×2.5 against a staggered target. Fills 60% of a stagger bar. 6 f hit-stop | AC6 kick ×2.8 direct, impact 480–700 [AC2] |
| Jump | 4 f knee-dip that still accepts input, then a thruster hop to +8 m apex at 0.45 s | (estimate) |
| Ascend / hover | Ascend at 18 m/s for 10% EN/s. Hover for 4% EN/s | EXVS empties the gauge in 2.5 s when ascending [EX1]; AC6 charges EN for upward thrust [AC3] |
| Gravity | Rising 1.0×. Falling 2.6 g (25.5 m/s²). Terminal 50 m/s. Dive (fast descent) 45 m/s | Mecha BREAK fast descent [MB3]; Gundam Evolution "floaty" complaints [GE1][GE2] (estimate) |
| Landing | Soft (vertical speed < 15 m/s): 12 f (0.20 s), cancellable by QB or boost from frame 6. Hard (≥ 15 m/s): 23 f (0.38 s), cancellable from frame 14. Landing with EN empty: 42 f (0.70 s), no cancel | EXVS 26 / 28 / 42 F [EX1], shortened for PvE |
| EN | 100 units. Ground regen 50%/s after 0.6 s. Air regen 12%/s after 0.9 s. Regen continues during horizontal boost. **Empty bar**: 1.5 s lockout, then an instant +25% refill; boost / QB work again at ≥30% | AC6 delays 0.5–1.3 s normal / 1.2–3.2 s empty, post-empty refill [AC2][AC3]; Mecha BREAK land 6.2× air (Alysnes), fuse threshold [MB1] |
| Turning | Legs turn at 180°/s walking, 120°/s running. Torso and arms follow the aim with a 0.10 s critically damped lag. Torso twists up to ±100°, then the legs pivot. Quick Turn: 180° in 0.35 s, 6% EN, 0.5 s cooldown | AC6 Quick Turn [AC8]; Hawken 180° turn [HW2]; MWO 85° torso yaw [MW6] (estimate) |
| Stepping | CharacterBody3D floor_snap_length 0.6 m (default 0.1). Step-up 2.5 m. While boosting, auto hop over obstacles ≤7 m | TF2 titan steps up 2.0 m = 0.34 H [TF1]; [GD4] (estimate) |
| Soft lock | Auto-acquire within 7° (mouse) or 10° (gamepad) of the reticle, ≤300 m, line of sight required. Lead prediction on. Gamepad: 0.55× aim slowdown inside the cone; magnetism removes 25% of the aim error per second | AC6 FCS auto-lock with lead [AC13][AC15]; Mecha BREAK auto adhesion [MB3] (estimate for angles) |
| Hard lock | Toggle (R3 / middle mouse), up to 450 m. Camera yaw tracks the target with a critically damped spring at 9 rad/s; pitch limited to −35°/+50°. **Strafing orbits the target at constant radius.** Aims at centre of mass unless the FCS lead upgrade is fitted. Lock stays while the target is within 1.5× the cone, or hidden for ≤0.5 s. **Never auto-switches.** Switch with a right-stick flick (≥0.7 within 0.15 s) or the mouse wheel, picking the nearest target in that direction | ZOE2 sphere [ZO1]; Mecha BREAK complaints [MB2]; AC6 hard lock [AC13][AC14] |
| Range colour | Reticle red when the target is inside the weapon's effective range and the vertical angle is ≤55°; green otherwise. Homing weapons home only on red | EXVS red / green lock [EX2] |
| Multi-lock missiles | 0.12 s per lock, up to 8. Hold to sweep-paint | AC6 0.10–0.12 s per lock [AC3]; ZOE2 [ZO1]; Mecha BREAK Aquila (6) [MB6] |
| Engagement bands | Close ≤80 m, mid 80–180 m, long 180–300 m | AC6 bands ≤120 / 140–250 / ≥270 m, scaled down for city sight lines [AC4] (estimate) |
| 3P FOV (vertical) | 55° (≈85° horizontal at 16:9). Boost 60°, AB 66°, aiming 38°. Lerp in over 0.25 s (expo ease-out), out over 0.40 s. QB punch +3° in 0.06 s, back in 0.30 s | AC6 45° vertical [AC12]; Godot's fov is vertical (KEEP_HEIGHT) [GD1]; titan FOV wider than pilot [TF1][TF7]; slide FOV ×1.1 over 0.25 s [TF1] |
| 3P camera rig | Pivot at the chest (11.5 m) + 3.5 m right. SpringArm3D length 28 m (1.7 H) normal, 32 m boost, 36 m AB. Default pitch −8°. Sphere radius 1.5 m, margin 0.5 m, colliding only with large static world geometry. Pulls in instantly, pushes back out at 10 m/s after 0.25 s. Buildings between camera and mech dither to 30% opacity | TF2 chase cam 1.36 H back, 0.47 H right [TF1]; [GD2] (estimate) |
| 3P follow | Position uses a critically damped spring: 10 rad/s walking, 7 rad/s boost/AB (2–4 m of visible lag), 14 rad/s sideways during QB. Mouse rotation unsmoothed. Gamepad: yaw up to 300°/s, pitch 180°/s, response exponent 2.0 | (estimate) |
| 1P cockpit | Eye at 11.5 m. Vertical FOV 62° (≈94° horizontal at 16:9). Frame covers ≤18% of the screen. HUD on the glass. 1P↔3P switch blends over 0.35 s and keeps the aim point | Hawken's 30% is heavy [HW1]; TF2 titan FOV 75 [TF1] (estimate) |
| 1P motion | Footstep: cockpit and camera translate −0.12 m on a k 65 / d 15 spring (half-life 0.09 s), no rotation. Run roll ≤2°. Cockpit mesh lags turns by 80 ms (sway gain 5). Landing dips −0.25 m (soft) to −0.6 m (hard), scaled by fall speed. Damage rotates the **cockpit mesh** ≤1.5° with severity clamp(damage / (0.2 × max HP)); 3 sparks per 10% HP lost | TF2 [TF2][TF7][TF13][TF15]; Hawken [HW1] |
| 1P gamepad turning | Yaw up to 220°/s, pitch 140°/s (+15% while boosting) | Hawken's slower-than-FPS turn [HW1] (estimate) |
| Stagger (enemy ACS) | An impact gauge per enemy. It starts decaying 1.5 s after the last hit, at 20%/s. Stagger lasts 2.5 s (elites) or 4 s (bosses) — never under 1 s. Direct-hit multiplier: 1.5× machine guns, 2.0× rifles and missiles, 2.5× melee and kick | AC6 "several seconds", 1.15–2.7× [AC1][AC3]; complaints about ⅓ s staggers [AC20] |

### 16.3 Feedback timings

| Event | Gamepad rumble (strong / weak motor) | Camera | Other |
|---|---|---|---|
| Footstep, walking (0.90 s cadence) | strong 0.25 for 50 ms | 3P 0.15° shake; 1P −0.12 m translate | Dust puff; sub-bass layer at 40–60 Hz (estimate) |
| QB / air dash | strong 0.8 for 100 ms + weak decaying 0.9 → 0 over 1.0 s | FOV +3°; lateral follow at 14 rad/s | 2 f thruster flash; 0.2 s afterimage trail |
| AB ignition | strong 1.0 for 0.3 s ramp, then weak 0.3 continuous | FOV +11°, spring arm +8 m over 0.3 s | Speed lines above 30 m/s; radial blur via CompositorEffect |
| Soft landing | strong 1.0 for 130 ms, off at 163 ms | 0.6° pitch kick | — |
| Hard landing | strong 1.0 for 190 ms + weak 0.4 for 300 ms | 1.5° kick; 1P −0.6 m | Crack decal and 20 m dust ring |
| Melee hit, light / heavy | strong 1.0 for 0.5 s; weak tail to 1.0 s | Hit-stop 3 f / 6 f at time scale 0.05; aim freeze 0.15–0.25 s | — |
| Taking damage, small / big | weak 0.65 → 0 over 0.2 s / strong 0.5 + weak 1.0 for 150 ms | Directional jolt | Cockpit sparks |

Sources: rumble shapes, the freeze-look time and the damage jolt rule come from TF2 [TF10][TF13][TF14]. Everything else (AB rumble, hit-stop frame counts, shake angles, dust, audio) is (estimate).

### 16.4 Godot 4.7 implementation notes

**Physics**
- Set `physics/common/physics_ticks_per_second` = 120 and enable `physics/common/physics_interpolation` [GD6].
- Update the camera rig in `_process` from interpolated transforms.
- Hero body: CharacterBody3D with `floor_snap_length` 0.6 (default 0.1) and `floor_max_angle` 40° (default 45°) [GD4].
- For QB and AB, run a ShapeCast3D sweep along each step's motion. Stop at walls and spawn a scrape effect [GD5].

**Camera rig**
- Scene tree: `Node3D` pivot (top_level, chest + shoulder offset) → `SpringArm3D` (SphereShape3D r 1.5 m, margin 0.5, collision_mask = large-static layer only) → `Camera3D` (keep_aspect KEEP_HEIGHT, fov 55) [GD1][GD2].
- Put the shoulder offset on the pivot, not on `h_offset`, so collision is tested from the shoulder.
- Drive FOV and spring length with critically damped springs, or with Tween (TRANS_EXPO, EASE_OUT).

**Rumble**
- `Input.start_joy_vibration(device, weak, strong, duration)` [GD3]. TF2's heavy motor maps to `strong` and the light motor to `weak`.
- Approximate decaying envelopes by re-issuing the call every 50 ms.

**Hit-stop**
- Set `Engine.time_scale` = 0.05 [GD7].
- Restore it with `get_tree().create_timer(t, true, false, true)`; the last argument (`ignore_time_scale`) must be true.

**Post-processing**
- Speed lines and radial blur via the Compositor / CompositorEffect (Forward+) [GD8].

### 16.5 Level-design consequences

- **AB lanes.** Turn radius is about 52 m at 72 m/s, so AB needs straight runs at least 40 m wide and 300+ m long: elevated highways, rail cuts, canal corridors, rooftop runways.
- **QB space.** One QB is 16 m, so a 30 m street fits one side-to-side QB with margin. Narrower alleys mean ground fighting with walk and boost.
- **Vertical thresholds.** Step-up handles 2.5 m. Boost hops clear 3–7 m. Anything 8 m or higher needs jump or ascend. Make skybridge and rooftop links 8–25 m apart vertically, so climbing spends EN and landing creates the rhythm.

---

## 17. Risks and open questions

1. **Data provenance.**
   - TF2 numbers come from a community mirror of shipped script files [TF19]; values may differ between patches.
   - AC6 numbers come from a data-mined fan tool [AC5].
   - AC6 speed units are inferred to be km/h, not confirmed [AC11].
2. **Speed vs city density.** At 34 m/s boost and 72 m/s AB, the camera spring will collide constantly. Godot will also need streaming or LOD budgets for the higher traversal speed. Occluder dithering and AB lanes are mandatory.
3. **First-person nausea.** FOV kicks, landing dips and jolts must translate, never rotate the aim [TF15]. Offer a "reduce camera motion" setting.
4. **Lock-on edge cases.** Tall buildings break line of sight constantly. The 0.5 s occlusion grace and no-auto-switch rules are essential, or we inherit Mecha BREAK's complaints [MB2].
5. **Camera whip.** Teleports or fast target switches (ZOE2's problem [ZO7]) need a camera turn-rate cap of about 540°/s with ease.
6. **Hard lock can trivialise aiming** [AC17]. Keep FCS lead on soft lock only, and limit hard lock with a pitch clamp and range bands.
7. **Stagger tuning.** Staggers that are too short feel cheated [AC20]; if they are too long, bosses become pinatas. Prototype 2.5 s / 4 s first.
8. **Fodder enemies that stand still** were AC6's weakest point [AC18]. Our Tripo monsters need movement and dodge behaviour, or the speed toolkit has nothing to bite on.
9. **IP distance.** The "Gundam spirit" hero must not reuse protected silhouettes. This is a design-review gate, not a feel issue.
10. **Godot specifics.** CharacterBody3D tunnelling at 72 m/s is solved by 120 Hz physics plus ShapeCast3D sweeps. Physics interpolation must be enabled so the camera does not jitter [GD6].

---

## 18. Sources

**Armored Core VI**
- [AC1] Famitsu, Yamamura & Ogura long interview (2023-04-27): https://www.famitsu.com/news/202304/27300778.html
- [AC2] matteosal/ac6-advanced-garage, ACStats.jsx (stat formulas): https://github.com/matteosal/ac6-advanced-garage/blob/master/src/Components/ACStats.jsx
- [AC3] matteosal/ac6-advanced-garage, PartsData.json (part data): https://github.com/matteosal/ac6-advanced-garage/blob/master/src/Assets/PartsData.json
- [AC4] matteosal/ac6-advanced-garage, StatRows.jsx (FCS range plot): https://github.com/matteosal/ac6-advanced-garage/blob/master/src/Components/StatRows.jsx
- [AC5] ac6-advanced-garage README ("data mining of the game files and/or reverse engineering"): https://github.com/matteosal/ac6-advanced-garage
- [AC6] Fextralife AC6 wiki, Stats: https://armoredcore6.wiki.fextralife.com/Stats
- [AC7] Fextralife AC6 wiki, Controls: https://armoredcore6.wiki.fextralife.com/Controls
- [AC8] Fextralife AC6 wiki, Boost Kick (OS Tuning list incl. Quick Turn, Manual Aiming): https://armoredcore6.wiki.fextralife.com/Boost_Kick
- [AC9] Armored Core Wiki, Assault Boost: https://armoredcore.fandom.com/wiki/Assault_Boost
- [AC10] Armored Core Wiki, Stability/ACS: https://armoredcore.fandom.com/wiki/Stability
- [AC11] SpaceBattles, AC capability thread (≈10 m, 135–605 kph): https://forums.spacebattles.com/threads/armored-core-franchise-capability-thread.1118995/
- [AC12] Nexus Mods, "More FoV at Armored Core VI" (default 45): https://www.nexusmods.com/armoredcore6firesofrubicon/mods/302
- [AC13] GameFAQs, soft lock leads shots / hard lock centre of mass: https://gamefaqs.gamespot.com/boards/389515-armored-core-vi-fires-of-rubicon/80550172
- [AC14] Steam, Hard Lock vs Soft Lock: https://steamcommunity.com/app/1888160/discussions/0/3883848063139960829/
- [AC15] Game8, soft/hard lock: https://game8.co/games/armored-core-6/archives/425274
- [AC16] 3DMGame, 硬锁和软锁区别: https://www.3dmgame.com/gl/3901867.html
- [AC17] NGA, 装甲核心6的锁定为什么争议那么大: https://bbs.nga.cn/read.php?tid=37194841&page=4 and https://ngabbs.com/read.php?tid=37194841&page=2
- [AC18] The Gemsbok, mechanical critique of AC6: https://thegemsbok.com/art-reviews-and-articles/armored-core-vi-6-fromsoftware-critique-mechanics-analysis/
- [AC19] Reddit, what is considered fast in AC6: https://www.reddit.com/r/armoredcore/comments/16923s7/what_is_considered_fast_in_ac6/
- [AC20] Steam, enemies break stagger fast: https://steamcommunity.com/app/1888160/discussions/0/4757578099468669530/
- [AC21] Steam, "Mech feels weightless": https://steamcommunity.com/app/1888160/discussions/0/3820795131607503449/

**Titanfall 2**
- [TF1] titan_base.set: https://github.com/Syampuuh/Titanfall2/blob/master/scripts/players/mp/titan_base.set (also pilot_base.set and pilot_mp.set in the same folder)
- [TF2] titan_atlas.set: https://github.com/Syampuuh/Titanfall2/blob/master/scripts/players/mp/titan_atlas.set
- [TF3] titan_stryder.set: https://github.com/Syampuuh/Titanfall2/blob/master/scripts/players/mp/titan_stryder.set
- [TF4] titan_ogre.set: https://github.com/Syampuuh/Titanfall2/blob/master/scripts/players/mp/titan_ogre.set
- [TF5] titan_buddy.set (BT): https://github.com/Syampuuh/Titanfall2/blob/master/scripts/players/mp/titan_buddy.set
- [TF6] Variant sets (titan_stryder_leadwall/sniper, titan_atlas_stickybomb/tracker/vanguard, titan_ogre_meteor/minigun): https://github.com/Syampuuh/Titanfall2/tree/master/scripts/players/mp
- [TF7] pilot_titan_cockpit.set (cockpit sway): https://github.com/Syampuuh/Titanfall2/blob/master/scripts/players/mp/pilot_titan_cockpit.set
- [TF8] springs.txt (weapon and view-punch springs): https://github.com/Syampuuh/Titanfall2/blob/master/scripts/weapons/springs.txt
- [TF9] Core weapon files mp_titancore_*.txt: https://github.com/Syampuuh/Titanfall2/tree/master/scripts/weapons
- [TF10] melee_titan_sword.txt / melee_titan_punch.txt: https://github.com/Syampuuh/Titanfall2/blob/master/scripts/weapons/melee_titan_sword.txt
- [TF11] Titan weapon files mp_titanweapon_*.txt: https://github.com/Syampuuh/Titanfall2/tree/master/scripts/weapons
- [TF12] mp_titanability_phase_dash.txt / mp_titanability_hover.txt: https://github.com/Syampuuh/Titanfall2/blob/master/scripts/weapons/mp_titanability_hover.txt
- [TF13] cl_titan_cockpit.nut: https://github.com/Syampuuh/Titanfall2/blob/master/scripts/vscripts/client/cl_titan_cockpit.nut
- [TF14] cl_rumble.gnut: https://github.com/Syampuuh/Titanfall2/blob/master/scripts/vscripts/client/cl_rumble.gnut
- [TF15] Game Developer, "Designer Interview: Getting Titanfall's controls just right": https://www.gamedeveloper.com/design/designer-interview-getting-i-titanfall-i-s-controls-just-right
- [TF16] A Sound Effect, "Creating Titanfall 2's Terrific Sci-Fi Sound": https://www.asoundeffect.com/titanfall-2-sound/
- [TF17] Titanfall 2 wiki, Titans ("about twenty feet tall"): https://titanfall2.fandom.com/wiki/Titans
- [TF18] Titanfall 2 wiki, Titanfall 2 Titans (Turbo Engine): https://titanfall2.fandom.com/wiki/Titanfall_2_Titans
- [TF19] Syampuuh/Titanfall2 repository ("Titanfall 2 client tracking"): https://github.com/Syampuuh/Titanfall2

**Gundam Extreme VS**
- [EX1] Dragonic Fighter, EXVS2 movement basics (Japanese): https://www.dragonicfighter.net/entry/2019/10/02/083306
- [EX2] MBON Guide, System and Controls: https://sites.google.com/view/mbon-guide/system-and-controls
- [EX3] MBON Guide, Movement: https://sites.google.com/view/mbon-guide/movement

**Gundam Breaker 4 / SD Gundam Battle Alliance**
- [GB1] RPG Site, Gundam Breaker 4 review: https://www.rpgsite.net/review/16218-gundam-breaker-4-review
- [GB2] Gaming Boulevard, Gundam Breaker 4 review: https://gamingboulevard.com/2024/09/review-gundam-breaker-4/
- [GB3] Reddit r/GundamBreaker, biggest critique: https://www.reddit.com/r/GundamBreaker/comments/1fchy7l/what_is_your_biggest_critique_about_this_game/
- [SD1] GamingBolt, SD Gundam Battle Alliance review: https://gamingbolt.com/sd-gundam-battle-alliance-review-mecha-hunter

**Zone of the Enders**
- [ZO1] からすや ANUBIS skill guide (Japanese): https://karasuya.fool.jp/anubis/anubis0skill.html
- [ZO2] Konami ANUBIS site (R2 = burst attack): https://www.konami.com/games/zoe2/japanese/log_neta_2.html
- [ZO3] ZOE wiki, Zero Shift: https://zoneoftheenders.fandom.com/wiki/Zero_Shift
- [ZO4] Cane and Rinse, ZoE2 game feel: https://caneandrinse.com/zone-of-the-enders-the-2nd-runner-and-its-delicious-game-feel/
- [ZO5] Hardcore Gamer, MARS review: https://hardcoregamer.com/reviews/review-zone-of-the-enders-the-2nd-runner-mars/311800/
- [ZO6] TheSixthAxis, MARS review: https://www.thesixthaxis.com/2018/09/11/zone-of-the-enders-the-2nd-runner-mars-review/
- [ZO7] Forbes, MARS review: https://www.forbes.com/sites/games/2018/09/23/zone-of-the-enders-the-2nd-runner-mars-review-a-decent-game-with-an-unnecessary-vr-mode/

**Daemon X Machina**
- [DX1] Nintendo World Report, DXM review: http://www.nintendoworldreport.com/review/51678/daemon-x-machina-switch-review
- [DX2] PCMag, DXM review: https://www.pcmag.com/reviews/daemon-x-machina-for-pc
- [DX3] IGN China, 机甲战魔 神话之裔 review: https://www.ign.com.cn/daemon-x-machina-titanic-scion/55922/review/ji-jia-zhan-mo-shen-hua-zhi-yi-ping-ce-7-fen-ign-zhong-guo
- [DX4] Source Gaming, Titanic Scion review: https://sourcegaming.info/2025/09/26/daemon-x-machina-titanic-scion-review/
- [DX5] Reddit r/DaemonXMachina, Titanic Scion impressions: https://www.reddit.com/r/DaemonXMachina/comments/1ncipsz/titanic_scion_clear_impressionscontains_spoilers/
- [DX6] NintyBuzz, DXM review ("automatic lock-on function"): https://www.nintybuzz.com/2019/09/11/review-daemon-x-machina/

**Mecha BREAK**
- [MB1] Steam, MOD list and stat explanations: https://steamcommunity.com/app/2452280/discussions/0/595141926473208919/
- [MB2] Steam, "This game needs a true lock on system": https://steamcommunity.com/app/2452280/discussions/0/604149632150280585/
- [MB3] GamerSky, 解限机 controls guide: https://www.gamersky.com/handbook/202408/1798190.shtml
- [MB4] IGN, Mecha Break review: https://www.ign.com/articles/mecha-break-review
- [MB5] GamingBolt, Mecha Break review: https://gamingbolt.com/mecha-break-review-metal-madness
- [MB6] Mecha BREAK wiki, AQUILA: https://mechabreak.wiki.gg/wiki/AQUILA
- [MB7] NGA 解限机 board (thread "这游戏不好玩是不是因为爽点和赢点分开了"): https://bbs.nga.cn/thread.php?stid=38632827
- [MB8] TapTap, 解限机 mech analysis: https://www.taptap.cn/moment/689489439382048262

**Synduality**
- [SY1] IGN, Synduality Echo of Ada review: https://www.ign.com/articles/synduality-echo-of-ada-review

**MechWarrior**
- [MW1] Steam, cockpit sway on Clan mechs: https://steamcommunity.com/app/784080/discussions/0/839502025821621125/
- [MW2] Reddit, cockpit sways too much: https://www.reddit.com/r/Mechwarrior5/comments/1g647ow/cockpit_sways_side_to_side_too_much_opinion/
- [MW3] Reddit, ridiculous cockpit bob: https://www.reddit.com/r/Mechwarrior5/comments/1ogav6u/ridiculous_cockpit_bob/
- [MW4] Reddit, torso twist / anchor turn: https://www.reddit.com/r/Mechwarrior5/comments/11c5v8k/how_do_torso_twist_and_anchor_turn_interact_with/
- [MW5] Steam, first-person torso twist: https://steamcommunity.com/app/784080/discussions/0/662737213850739029/
- [MW6] Reddit r/OutreachHPG, mech quirks (85° torso yaw): https://www.reddit.com/r/OutreachHPG/comments/2lru4f/official_mech_quirks_need_feedback_from_you_on/
- [MW7] VICE, MW5 review: https://www.vice.com/en/article/mechwarrior-5-mercenaries-review/
- [MW8] Nexus Mods, Adjustable Twist Rates: https://www.nexusmods.com/mechwarrior5mercenaries/mods/1254

**Hawken**
- [HW1] Game Developer, "Inside the striking art and design of Hawken": https://www.gamedeveloper.com/business/inside-the-striking-art-and-design-of-i-hawken-i-
- [HW2] Hawken wiki, Thrusters/Boost: https://hawken.fandom.com/wiki/Boost
- [HW3] Hawken wiki, Cockpit: https://hawken.fandom.com/wiki/Cockpit
- [HW4] Hawken wiki, Fuel: https://hawken.fandom.com/wiki/Fuel

**Other games**
- [LP1] Lost Planet wiki, Vital Suit: https://lostplanet.fandom.com/wiki/Vital_Suit
- [OV1] Nintendo World Report, Override 2 review: http://www.nintendoworldreport.com/review/56456/override-2-super-mech-league-switch-review
- [ME1] Mecharashi on Google Play: https://play.google.com/store/apps/details/Mecharashi?id=com.tentree.gp.un.mecharashi&hl=en_IE
- [ME2] Reddit r/frontmission, Mecharashi impressions: https://www.reddit.com/r/frontmission/comments/1isxfk3/i_played_chinese_japanese_and_taiwanese/
- [GE1] Forbes, Gundam Evolution impressions: https://www.forbes.com/sites/olliebarder/2022/04/11/gundam-evolution-impressions-not-entirely-terrible-but-needs-more-work/
- [GE2] Reddit, why Gundam Evolution failed: https://www.reddit.com/r/Gundam/comments/1030e5m/why_do_you_think_gundam_evolution_failed_to/
- [GE3] Reddit, Gundam Evolution first impressions: https://www.reddit.com/r/Gundam/comments/tz4bu9/whats_your_initial_impressions_of_gundam/
- [GE4] Reddit, G-Dash tech: https://www.reddit.com/r/GundamEvolution/comments/yro47i/gallant_dash_gdash_movement_tech/

**Physics and Godot**
- [PH1] Wikipedia, Froude number (walking Froude number; walk–run transition Fr ≈ 0.5): https://en.wikipedia.org/wiki/Froude_number
- [GD1] Godot Camera3D (fov is vertical by default; KEEP_HEIGHT; 75° = 107.5° horizontal at 16:9): https://docs.godotengine.org/en/stable/classes/class_camera3d.html
- [GD2] Godot SpringArm3D: https://docs.godotengine.org/en/stable/classes/class_springarm3d.html
- [GD3] Godot Input.start_joy_vibration: https://docs.godotengine.org/en/stable/classes/class_input.html
- [GD4] Godot CharacterBody3D (floor_snap_length 0.1, floor_max_angle 45° defaults): https://docs.godotengine.org/en/stable/classes/class_characterbody3d.html
- [GD5] Godot ShapeCast3D: https://docs.godotengine.org/en/stable/classes/class_shapecast3d.html
- [GD6] Godot physics interpolation: https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/physics_interpolation_introduction.html
- [GD7] Godot Engine.time_scale and SceneTree.create_timer(ignore_time_scale): https://docs.godotengine.org/en/stable/classes/class_engine.html and https://docs.godotengine.org/en/stable/classes/class_scenetree.html
- [GD8] Godot Compositor: https://docs.godotengine.org/en/stable/tutorials/rendering/compositor.html
