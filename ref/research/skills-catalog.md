# Mech Skills Catalog + Proposed Hero Kit

key: `skills-catalog` · for: Lead (Claude Opus) · implementers: MiniMax-M78 agents · engine: Godot 4.7 (Forward+) · date: 2026-11-01
Images: `ref/images/skills-catalog/` (12 frames + `sources.md` + `_sheet.jpg`)

## 0. TL;DR

- Build the kit on **three payoff loops** that the source games prove:
  1. **Mark → drones.** Rifle hits summon more remote drones (Gundam Evolution fin funnels).
  2. **Impact → stagger → execution.** AC6 ACS / direct hit, Titanfall terminations, Doom glory kills.
  3. **Prime → detonate.** Anthem combos.
- Defense is **offense-shaped**: tap-parry with a 167 ms window, hold to catch and return projectiles (Sekiro 12 f, DMC 6 f, Titanfall Vortex).
- The ultimate is a **12 s overdrive** that ends in a **0.8 s + 3.0 s mega beam** (Trans-Am, EXVS Awakening, Laser Core).
- Impact comes from **per-entity hitstop** (3–12 f, capped), shake, rumble and rare short global slow-mo, following Sakurai's rules.
- Every number is tunable `Resource` data. Times are given in seconds or 60 fps frames. Distances assume an **8 m hero** (estimate). The level-design dossier uses **16 m**, so §4.1 gives a ×2 conversion table; times stay the same.

## 1. Conventions

- **f** = frame at 60 fps. Implement all windows in seconds.
- **Tier** (catalog): damage per activation vs one unit of the same class.
  - T1 <5 %
  - T2 5–15 %
  - T3 15–35 %
  - T4 35–70 %
  - T5 >70 % or a kill
- **Cx** (complexity for an M78 agent):
  - 1: one script
  - 2: one system + simple VFX
  - 3: state machine, pooled projectiles/VFX, tuning
  - 4: cross-system integration (AI, animation, camera)
  - 5: new locomotion or rig paradigm
- **S/A/R** = startup / active / recovery.
- `[TAG]` → URL in §6. "(estimate)" marks my own design number. Fan-wiki values are patch-dependent reference ranges.

## 2. Catalog (63 entries)

### 2A Beams and charged shots

| # | Skill (source): mechanics | Input | Numbers | Tension | VFX / SFX | Why it feels good | Cx | Ref |
|---|---|---|---|---|---|---|---|---|
| A1 | Beam rifle, ν (Gundam Evolution). Hitscan; hits add marks that empower funnels. | fire / ADS | T2 per hit (150 vs 1,300 HP). 10 rds, 150 rpm, reload 1.5 s. Crit 1.5×. Zoom 1.25×. | Weak alone; payoff needs 2–4 hits in 5 s | Tracer + mark pips | Precise taps "load" the payoff | 1 | [GEVO-NU] |
| A2 | Charged mega beam (Twin Buster Rifle, Mega Bazooka Launcher). EXVS: each charge stage adds power and width, with an explosion at impact. Mega Launcher: long charge; other MS can feed it power. | hold | T4–T5 (estimate) | Long exposure | Muzzle rings → white core + arcs (img 04) | Anticipation → release | 3 | [EXVS-WZ] [GW-HS] [GW-WZ] |
| A3 | Laser Core, Ion (TF2). Chest beam. During the charge, movement and camera are slowed and only dash works; no dash while firing. | core | T5 ("destroys a Titan in seconds"). 1 s charge, 3.5 s beam (5 s with kit). | Telegraphed; open to flanks | 4 targeters converge from the screen corners | Guaranteed, screen-filling payoff | 2 | [TF-LC] |
| A4 | Plasma Railgun + Laser Shot (Titanfall). **Railgun:** charges while zoomed, can be held, pierces, 2× weakpoint. **Laser Shot:** costs ~55 % shared energy. | ADS hold / ordnance | Railgun: 0.5 s/stage, full 2.5 s; TF1 500 dmg uncharged, 600 m range. Laser Shot 1,200. T2–T4. | Scope tunnel vision; energy triage | Staged whine; bolt | Staged charge = skill expression | 2 | [TF-RG] [TF-LS] |
| A5 | Halberd / Vector Cannon (ZOE2). Button pressure sets beam radius and length; turning sweeps it; destroys buildings. Vector Cannon: long charge, must be grounded. | hold | T5 | Rooted, energy drain | Beam whipped across the arena | Cutting through geometry | 3 | [ZOE-HAL] [ZOE-VC] |
| A6 | Plasmacaster + chain sword (Pacific Rim). The arm becomes a cannon. Originally a long, arm-swing charge; later rapid shots. A wrist chain sword deploys. | context | T4 (estimate) | Transform = window | Arm reconfiguration | The transform is the windup | 3 | [PR-PC] [PR-GD] |
| A7 | Moving-shot bazooka, ν (Gundam Evolution). Dashes while firing; applies marks. | skill | T2: 300→100 splash. Dash 850 units. CD 8 s (4 s in ultimate). | 50 % self-damage | Dodge + boom | Offense and evasion in one | 2 | [GEVO-NU] |

### 2B Missiles and lock-on

| # | Skill | Input | Numbers | Tension | VFX / SFX | Why | Cx | Ref |
|---|---|---|---|---|---|---|---|---|
| B1 | Itano Circus (Macross). Dozens of missiles at once; the target loops through them. | anime | — | The dodge is the show | Curling trails (img 05) | Count + choreography | 3 | [MAC-IC] |
| B2 | Multi-Target Missile System (Titanfall). Hold and sweep to paint, release to fire; several locks per target. | hold-sweep-release | ≤12 missiles; T3 (estimate) | Aim held while exposed | Lock beeps | Player-sized volley | 3 | [TF-MTMS] |
| B3 | Salvo Core, Tone (TF2). Wire-guided missiles follow the crosshair around corners. | core | 60 missiles (90 upgraded); T5 | Shields soak; scatter if Tone dies | Rocket storm | Steering a swarm | 3 | [TF-SAL] |
| B4 | Tracker Rockets + Sonar Lock (TF2). 3 lock stacks (cannon hits or a sonar pulse through walls) → 5 rockets. | ordnance | ≈2,500 dmg; T3 | No corner pathing; Phase Dash wipes the locks | Orange pulse, pips | Build → payoff | 3 | [TF-TR] [TF-SL] [TF-40MM] |
| B5 | Lock-count variants. 8AAM (Ace Combat): ≤8 targets, several locks per target. ZOE2 Homing Missile: count follows button pressure. | hold | T3 (estimate) | — | Multiplying boxes | More input, more missiles | 2–3 | [AC7-8AAM] [ZOE-HM] |
| B6 | Hero-shooter volleys. **Valkyrie:** 12 missiles in a 4×3 grid, 25 dmg first + 3 each, 2 s slow, CD 30 s. **D.Va:** 18 missiles at 14/s, 50 m/s, 0.16 s startup, CD 7 s, usable while boosting. | tap | T2 | Impact markers warn the target | Small-blast ripple | Fire while moving | 2 | [APX-VAL] [OW-DVA] |

### 2C Remote weapons

| # | Skill | Input | Numbers | Tension | VFX / SFX | Why | Cx | Ref |
|---|---|---|---|---|---|---|---|---|
| C1 | Fin Funnels, ν (Gundam Evolution; anime). **Skill:** 0/1/2 marks → 2/4/6 funnels, each firing 4×55. **Ultimate:** a 5-funnel barrier plus 1 auto-attacker; resets all CDs; doesn't block melee or shots from inside. **Anime:** ≥4 funnels form a tetrahedral barrier. | skill / ult | Skill: 440/880/1,100 dmg, CD 9 s, marks last 5 s. Ult: barrier 4,000 HP, 12 s. T3. | Marks expire | Fanning funnels (img 01) | Precision summons drones | 3 | [GEVO-NU] [GW-NU] |
| C2 | DRAGOON full burst (Strike Freedom). Pods fire beams or project blades; Multi Lock-on hits several targets from many directions. | burst | 8 pods; T4 (estimate) | Needs space | Converging beams (img 02) | Omnidirectional crossfire | 4 | [GW-SF] |
| C3 | Wisp (ZOE2). Three bits latch onto a target and drag it back. | sub-weapon | T1 | — | Bits + tethers | Remote grab | 3 | [ZOE-W] |
| C4 | Mecha BREAK drones: decoy, camo, reflector, field shield, claw, boomerang, turret, repair. | skills | — | Shootable | — | Drones as a design space | 2–3 | [MB-LIST] |

### 2D Melee, grabs and finishers

| # | Skill | Input | Numbers | Tension | VFX / SFX | Why | Cx | Ref |
|---|---|---|---|---|---|---|---|---|
| D1 | Blade lunges (AC6). **MOONLIGHT:** 615×2 (impact 495); charged 2,010→2,310 (impact 910); wave range 280; DHA 175. **Coral Oscillator WLT 101:** 1,350→1,460 (impact 960); DHA 210. | tap / hold | T3–T4; gated by cooling | Whiff = long recovery | Cyan crescent waves (img 09) | Lunge into one huge hit, ×1.75–2.1 on staggered | 3 | [AC-ML] [AC-CO] |
| D2 | Assault Boost → Boost Kick (AC6). Kick damage, knockback and ACS stress scale with weight and AB thrust. Director Yamamura: rush in while guns stagger, then land a direct pulse-blade hit. | AB, then AB key | T2–T3 | Straight-line commit | Boost flare | Momentum → damage | 2 | [AC-AB] |
| D3 | Shining / God Finger (G Gundam). A glowing liquid-metal hand grabs the head and crushes it; can also fire an energy wave. EXVS uses a Lv3 giant palm. | grab / charge | T5 (estimate) | Must close in | Green palm, shout, blast | Total control + operatic finish | 3 | [GW-SH] [EXVS-GOD] |
| D4 | Sword Core, Ronin (TF2). Dashes refilled and recharged faster; knockback −80 %. | core | 12 s. Melee 2,200 (≈3×, vs Titan HP 7,500 + 2,500). Block 70→85 %. ~1 s activation. | Swings can be pinned | Yellow glow | Time-boxed melee god mode | 2 | [TF-SC] |
| D5 | Termination (Titanfall). Melee on a doomed Titan plays a kill animation; both are invulnerable. | melee | ≤6.6675 m, ≤45° front | Positioning | Cinematic | Safe, spectacular finisher | 3 | [TF-TERM] |
| D6 | Glory Kill + Blood Punch (Doom Eternal). Staggered demons flash; glory kills are invulnerable and drop health; 2 GKs charge a shield-breaking Blood Punch. Loop: chainsaw → ammo, belch → armor. | melee | T5 / T3 | Must close in | Flash highlight | Aggression refuels | 3 | [DOOM-GK] [DOOM-BP] [DOOM-CS] |
| D7 | Deflect → Deathblow (Sekiro). The window shrinks with spam; a posture break enables the deathblow. | block tap | 12 f (0.2 s) | Mash penalty | Sparks, clang | Timing → instant kill | 3 | [SEK] |
| D8 | Blade Mode + Zandatsu (MGR). Grabbing the exposed core refills all HP and FC and is invincible; Ripper Mode = both sticks. | hold / L3+R3 | Time 43 % (manual); 4.3 % after finishers / parries | Needs FC | Blue screen, slice planes | Precise cut → full refill | 4 | [MGR-BM] [MGR-ZD] |
| D9 | "Jackpot!" (DMC). Charged shot as the killing blow. Exceed MAX-Act fills the whole gauge. | timed press | MAX-Act window 6 f (1/10 s) | Timing | Rev flame | Rhythm reward | 2 | [DMC-JP] [DMC-EX] |
| D10 | Meathook, Bonewidow (Warframe). Skewer and carry an enemy (5–20 %/s, 25–40 % lifesteal), then throw it as a projectile. | 2 presses | Throw AoE 10–17 m for 30–50 % of its HP; 25 energy | — | Skewer + throw | Enemies become ammo | 3 | [WF-MH] |
| D11 | Scissor anchor (Crossbone X-1). A chained claw grips a limb: reel the enemy in or swing it as a club. | anchor | T2 | — | Chain whip | Grab utility | 3 | [GW-XB] |

### 2E Mobility and traversal

| # | Skill | Input | Numbers | Tension | VFX / SFX | Why | Cx | Ref |
|---|---|---|---|---|---|---|---|---|
| E1 | Zero Shift (ZOE2). Locked-on warp toward the enemy, or back / up / down. Has a real travel speed and costs no energy. | lock + direction | Free | — | Warp streak | Appearing behind = dominance | 2 | [ZOE-ZS] [ZOE-FAQ] |
| E2 | Phase Dash, Ronin (TF2). Immune, passes through Titans, can't deal damage, clears locks. | tactical | CD 12 s (8 s with kit) | Exiting inside a Titan kills you | Shimmer | i-frame mobility | 2 | [TF-PD] |
| E3 | Boost family. **AC6 Quick Boost:** high-EN burst. **AC6 Assault Boost:** straight line, weapons usable. **D.Va Boosters:** 12 m/s, 0.4–2 s, CD 4 s, 17.5 m/s knockback. **Valkyrie VTOL:** 14.25 % fuel per activation, ~5.3 s, refuel after 8 s. | dash / hold | — | EN / fuel budget | Flame bursts | Speed on a budget | 1–2 | [AC-QB] [AC-AB] [OW-DVA] [APX-VAL] |
| E4 | Grapple, Pathfinder (Apex). Aim to the side to swing; detaches at 90° keeping momentum; hooking an enemy pulls both. | tactical | 21 m. CD scales with distance (≤5 s of travel). | — | Range ring | Momentum puzzle | 3 | [APX-PF] |
| E5 | Claw + Piledriver, Wrecking Ball (OW). **Claw:** fireball collisions deal 60 dmg + 30 m/s knockback. **Piledriver:** 0.75 s air-lock. | ability | Claw: 22.2 m, 20 m/s, CD 5 s. Piledriver: dive 98 m/s, radius 1.5–8 m, CD 8 s. | — | Swing arc, slam ring | Physics play | 3 | [OW-WB] |
| E6 | Meat Hook (Doom Eternal). Pulls you to the demon; small enemies are held; breaks on knockback, dash or jump; hook nodes for traversal. | alt fire | Upgrade −25 % recharge | Big enemies hit you mid-pull | Chain + impact | Gap-close to point blank | 2 | [DOOM-SSG] [DOOM-MH] |
| E7 | Slash Harken + Landspinner (Code Geass). Wire anchors: rappel, zipline, vault, whip, grind on wire. Heel wheels: skate, climb walls, catapult launch. | context | — | — | Wires, sparks | Urban mech parkour | 3 | [CG-SH] [CG-LS] |
| E8 | Charge, Reinhardt (OW). Wall pin = 300 dmg + stun. | ability | 0.592 s startup, 16.5 m/s, ≤50.2 m, CD 7 s. T3. | Can be baited off ledges | Shoulder rush | Wall-splat payoff | 2 | [OW-REIN] |
| E9 | Castle Wall, Newcastle (Apex). Leap and slam, raising an electrified wall. | ult | Leap ≤35 m; 9 segments × 750 HP | — | Hero landing | Arrival as an event | 3 | [APX-NC] |
| E10 | VF-1 transformation (Macross). Fighter ↔ GERWALK ↔ Battroid. | transform | — | — | Transformation | Two games in one | 5 | [MAC-VF1] |

### 2F Defense, parry and shields

| # | Skill | Input | Numbers | Tension | VFX / SFX | Why | Cx | Ref |
|---|---|---|---|---|---|---|---|---|
| F1 | Vortex Shield, Ion (TF2). Catches projectiles and throws them back; drains shared energy; returned damage scales with how many were caught. | hold / release | 35 per bullet vs Pilots; amplifier +35 % | Baited by single shots | Frozen bullet disk (img 12) | Their fire becomes yours | 3 | [TF-VS] |
| F2 | Thermal Shield, Scorch (TF2). Melts projectiles, burns contact. | hold | 0.3 s deploy, needs ≥20 % charge, 1 s CD | Partial hitbox cover | Fire wall | Defense that hurts | 2 | [TF-TS] |
| F3 | Sword Block / Particle Wall / Gun Shield (Titanfall). Block works in any direction but not vs melee; Particle Wall is one-way. | hold / deploy | Block 70 % (85 % in core). Particle Wall 2,000 HP. Gun Shield 2,500 HP. | Arc Wave deletes walls | Blue barriers | Readable safety | 1–2 | [TF-SB] [TF-PW] [TF-GS] |
| F4 | Pulse Armor family (AC6). Pulse Protection is stationary and doesn't stop melee. Terminal Armor triggers automatically at lethal damage. A broken boss Pulse Armor → stagger. | expansion | Pulse Armor 3,300 / 10 s. Pulse Protection 7,000 / 25 s. Terminal Armor 20,000 / 5 s. | P.A.-interference weapons | Dome (img 08) | Shield break → stagger window | 2 | [AC-PA] [AC-PP] [AC-TA] |
| F5 | Defense Matrix, D.Va (OW). Deletes projectiles in front; can't stop beams, melee or AoE. | hold | 10.3 m; 0.5–3 s; 33 %/s cost, 16 %/s regen | Beams, melee | Grid wall | Eat their big moment | 2 | [OW-DVA] |
| F6 | Shield Maiden, Bonewidow (Warframe). Absorbed damage becomes shield HP; reflects. | toggle | 3 s absorb, 160° block, ×1.25–2 reflect, 10 s CD if broken | — | Slab shield | Absorb, then return | 2 | [WF-SM] |
| F7 | Royalguard (DMC5). Normal block drains the gauge until guard break; Release counters. | tap / hold | Perfect block 6 f | 6 f is hard | Bell ring | Mastery spike | 3 | [DMC-RG] |
| F8 | A.T. Field (Evangelion). Invisible until struck, then concentric octagons. Only another field or massive energy breaks it; can be used offensively. | — | — | Neutralize with your own field | Octagons (img 11) | Invisible-until-hit readability | 3 | [EVA-AT] |
| F9 | Witch Time (Bayonetta). A last-moment dodge slows enemies. | dodge | 2–4 s (B1); 0.5–3 s base (B2) | Timing | Purple tint | The dodge becomes offense | 2 | [BAYO-WT] |
| F10 | Ward of Dawn (Destiny). Dome; passing through grants a weapon-damage buff. | super | +25 % for 10 s | Stationary | Dome | Defend → buff | 2 | [D-WOD] |
| F11 | Psycho-Field (Gundam UC). A Psycho-Frame overload emits an aurora; a sample deflected a mega-particle beam. | — | — | — | Green aurora | Emotional climax | 3 | [GW-PF] |

### 2G AoE and crowd control

| # | Skill | Input | Numbers | Tension | VFX / SFX | Why | Cx | Ref |
|---|---|---|---|---|---|---|---|---|
| G1 | Assault Armor (AC6). 360° pulse that deletes projectiles in the blast. | expansion | 1,500 dmg, 2,000 impact, radius 60, DHA 230; ≤3 charges per mission | Limited charges | Filament burst (img 07) | "Get off me" + wipe | 2 | [AC-AA] |
| G2 | Flame Core, Scorch (TF2). 3-segment ground wave; flows down, not up. | core | 4,500 dmg; T4 | Dash or hover avoids | Fire wave | Marching wall of fire | 2 | [TF-FC] |
| G3 | Electric Smoke (Titanfall). Blocks locks; AI ignores you inside. | tactical | TF1: 2 s smoke then 7 s live; 15 / 200 dmg per 0.1 s (infantry / Titans) | Leave the cloud | Electric fog | Denial + anti-lock | 2 | [TF-ES] |
| G4 | Arc Wave + Tether Trap (TF2). **Arc Wave** slows movement and dashes and deletes walls. **Tether Trap** pins a Titan; the trap can be shot. | ordnance | Arc Wave 1,000 (1,500 in core) | Shoot the trap | Ground lightning | A slow guarantees the follow-up | 2 | [TF-AW] [TF-TT] |
| G5 | Self-Destruct, D.Va (OW). Eject; the mech explodes after a fuse. | ult | 3 s fuse; 1,000→100 dmg over 6–21 m | 3 s to escape | Countdown beeps | Fear zoning | 2 | [OW-DVA] |
| G6 | Earthshatter, Reinhardt (OW). | ult | 0.448 s startup, 25 m, 3 s knockdown | Barriers block it | Fissure | Mass stun | 2 | [OW-REIN] |
| G7 | Geyser / Gauntlet (ZOE2). Geyser stuns and erupts; Gauntlet breaks guard, and slamming enemies into scenery adds damage. | sub-weapon | T1–T2 | — | Geysers | Environment as a weapon | 2 | [ZOE-G] [ZOE-GA] |
| G8 | Primer / detonator (Anthem). A detonator on a primed target triggers bonus damage plus an effect, with its own sound and "COMBO!". | any | + combo dmg | Prime expires | "COMBO!" floater | Two skills → a third effect | 2 | [ANT-CB] |
| G9 | Fist of Havoc / Thundercrash (Destiny). Leap-slam; Thundercrash hurls you like a missile. | super | T4 | Committal | Arc ring | You are the missile | 2 | [D-FOH] [D-TC] |

### 2H Overdrive and ultimates

| # | Skill | Input | Numbers | Tension | VFX / SFX | Why | Cx | Ref |
|---|---|---|---|---|---|---|---|---|
| H1 | Trans-Am (Gundam 00). Releases stored particles; very vulnerable once it ends. | toggle | ~3× output | Aftermath | Red body, afterimages (img 03) | Time-boxed transformation | 2 | [GW-TA] |
| H2 | Awakening (EXVS). Refills boost and ammo; attack / defense up; down value −10 %; motions ~10 % faster. | button | **Duration:** half 6.5 s (XB; +0.5 s since the Dec 2021 patch) / ~7 s (IB); full ≈16–17 s. **Boost refill:** half 30–50 %, full 100 %. **IB gauge:** +1.1 % per 1 % HP lost, +0.06 % per dmg dealt, +5 % per guard; no gain while active. | Dying while awakened | Cut-in, aura | Comeback catharsis | 2 | [EXVS-AWK] [EXVS-IB] |
| H3 | Titanfall cores. **Smart Core:** unlimited ammo, auto-lock, +20 % hidden dmg. **Damage Core (TF1):** after 2.5 s, 1.4× for 12.6 s. **Upgrade Core:** 2,500 shield refill + tier upgrade. | core | buff | — | — | Earned power spikes | 2–3 | [TF-SMC] [TF-DC] [TF-UC] |
| H4 | AR mode (Vanquish). Bullet time during dodges, building heat; a melee hit instantly overheats the suit. | trigger | Melee → 9 s ARS lockout | Heat | Slow-mo | Every melee is a gamble | 2 | [VQ-PG] [VQ-ARS] |
| H5 | Exalted weapons (Warframe Necramechs). Ironbride sword; Guard Mode immobile turret. | toggle | Ironbride 25 + 2.5/s. Guard Mode 50 + 5/s. | Drain | Weapon summon | Stance swap | 3 | [WF-EI] [WF-GM] |

## 3. Patterns to copy

1. **Telegraph → payoff**: Laser Core brackets, railgun stages, muzzle rings [TF-LC] [TF-RG] [EXVS-WZ].
2. **Build → payoff**: marks → funnels [GEVO-NU], 3 cannon locks → rockets [TF-40MM] [TF-TR], primer → detonator [ANT-CB].
3. **Stagger → finisher.**
   - AC6: impact overloads the ACS; hits on a staggered target deal direct-hit damage (DHA 175–230) [AC-STAB] [AC-ML] [AC-AA]. Assault Boost exists to cash the stagger in [AC-AB].
   - Titanfall terminations and Doom glory kills are invulnerable [TF-TERM] [DOOM-GK].
4. **Timing windows**: Sekiro 12 f [SEK], Royalguard 6 f [DMC-RG], Witch Time [BAYO-WT], Blade Mode 43 % / 4.3 % [MGR-BM].
5. **Aggression refuels; mistakes cost.**
   - Refuel: Doom's resource loop [DOOM-GK] [DOOM-CS]; Zandatsu [MGR-ZD].
   - Cost: Vanquish's 9 s melee overheat [VQ-PG].
   - Comeback: the EXVS gauge fills from damage taken [EXVS-IB].
6. **Their power becomes yours**: Vortex +35 % [TF-VS], Meathook throw [WF-MH], Shield Maiden [WF-SM].
7. **Time-boxed transformation**: Trans-Am [GW-TA], Sword Core [TF-SC], Awakening [EXVS-AWK].
8. **Hitstop rules (Sakurai) [SAK-HS]:**
   - Attacker and victim freeze for the same time; more damage → longer.
   - Projectiles get less; electric gets more; hard cap.
   - Shake the visuals, never the hurtboxes; vibrate horizontally on the ground, vertically in the air.
9. **Anti-degeneracy (EXVS) [EXVS-DMG]:**
   - Combo correction: beam rifle −30 %, first melee hit −20 %, floored at 10 %; resets after 2 s without being hit.
   - Cancel penalty −30 %; downed targets take −75 %.
   - Combo damage beyond 350 is cut by 75 %, but every hit still deals at least 1.

## 4. Proposed hero kit (original names)

### 4.1 Baseline and resources (estimate)

**Hero:** 10,000 HP (Titans: 7,500 + 2,500 doomed [TF-SC]).

**Enemies (Tripo biomech):**

| Archetype | HP | Stability |
|---|---|---|
| Swarmer | 300 | 150 |
| Stalker | 1,800 | 700 |
| Brute | 7,000 | 2,600 |
| Colossus (boss) | 60,000 | 9,000 |

Boss reference: AC6 Ibis SOL 644 has AP 42,020 and attitude stability 1,750 [AC-IBIS].

**Locomotion:**
- Walk 9 m/s; run 14 m/s.
- Jump v0 14 m/s; gravity 28 m/s².
- Hover 90 EN/s.

**Dash** (tap): 8 directions, 0.30 s.
- Peak 42 m/s easing to 18 m/s (≈9 m). Costs 110 EN.
- i-frames: first 6 f.
- **Perfect dodge**: a hit lands inside those i-frames → enemies slowed to 30 % for 0.35 s (Witch-Time-lite [BAYO-WT]) and +3 % OD.
- Up to 3 chained dashes, then a 0.45 s lockout.

**Assault Boost** (hold): 55 m/s, turning ≤70°/s, 170 EN/s, weapons usable.
- Melee during AB → **Ram Kick**: 850 dmg, 750 impact (AC6 boost kick [AC-AB]).

**Resources:**

| Resource | Rules (estimate) |
|---|---|
| **EN** (shared) | 1,000 max. Regen 320/s after 0.45 s without spending. **Outage** at 0: regen pauses 1.6 s, then 450/s up to 30 %. **Costs:** dash 110, hover 90/s, AB 170/s, lunge 140, charged shot 120 / 200, guard 60/s + 25 per 100 blocked, Catch Field 140/s. **Gains:** perfect guard +150, execution +300. |
| **HEAT** (gatling only) | 0–100. +0.85 per shot. Cools 30/s after 0.35 s. 100 → 2.6 s lock unless vented. |
| **OVERDRIVE (OD)** | 0–100 %. **Gains:** +1 % per 1 % own HP lost (EXVS uses 1.1 % [EXVS-IB]); +1 % per 450 dmg dealt; +4 % perfect guard; +3 % perfect dodge; +8 % execution; +2 % per Collapse. ×1.5 below 15 % HP. No gain while active [EXVS-IB]. Target fill time: 60–90 s of combat. |
| **MARKS** (enemy) | 2 / 4 rifle hits = 1 / 2 marks; expire 5 s after the last hit [GEVO-NU] |
| **STABILITY** (enemy) | Impact fills it; it decays after a delay (§4.6) |

Three meters stay readable:
- **EN** sits on the reticle.
- **HEAT** shows only while the gatling is equipped.
- **OD** is a slow ring.

**Scale reconciliation.** `level-design-vertical.md` builds the city for a **16 m** mech (16 m module, assault boost 100 m/s); `juice-impact.md` uses MECH_H ≈ 9 m. If the lead adopts 16 m, use the right-hand column. Rules:
- Frames, seconds, damage, EN and cooldowns do not change.
- Locomotion follows the movement/level metrics, not ×2: walking does not scale linearly.

| Value | 8 m (this doc) | 16 m (×2) |
|---|---|---|
| Dash peak / distance | 42 m/s / 9 m | 84 m/s / 18 m |
| Assault Boost | 55 m/s | 110 m/s (level doc: 100) |
| Saber reach / Lunge band, speed | 9–11 m / 12–40 m, 55 m/s | 18–22 m / 24–80 m, 110 m/s |
| Rift Step lock range / offset / free blink | 45 / 7 / 22 m | 90 / 14 / 44 m |
| Skyhook range / reel | 60 m / 30→46 m/s | 120 m / 60→92 m/s |
| Hailstorm range / missile speed / blast | 160 m / 100 m/s / 3 m | 320 m / 200 m/s / 6 m |
| Fins station radius / range | 9 m / 90 m | 18 m / 180 m |
| Shockcore radius | 16 m | 32 m |
| Undertow radius / throw | 12 m / 50 m | 24 m / 100 m |
| Plunge min height / dive / radius | 8 m / 95 m/s / 10 m | 16 m / 190 m/s / 20 m |
| Core Rend range | 7 m | 14 m |
| Zenith Lance width / length | 8 m / 400 m | 16 m / 600 m (clamped by sightlines) |

### 4.2 Primary weapons

**P1 Pierce-Light Rifle (贯光步枪)**: semi-auto hitscan (estimates; compare Gundam Evolution's 10 rds / 150 rpm / 1.5 s [GEVO-NU]).
- **Fire:** ≤240 rpm. 9-round cell; reload 1.6 s (1.2 s with ≥1 round left).
- **Damage:** 230 body / 345 weakpoint (1.5× [GEVO-NU]); impact 70.
- **Range:** full damage to 140 m; falls to 60 % at 220 m; cut-off 300 m.
- **Charged shot** (hold fire; railgun-style staging [TF-RG], auto-fire at 3 s like Laser Shot's hold [TF-LS]):

  | Stage | Hold | Damage / impact | Effect | Cost |
  |---|---|---|---|---|
  | 1 | 0.6 s | 700 / 350 | Pierces 1 | 3 rds + 120 EN |
  | 2 | 1.2 s | 1,400 / 800 | Pierces all, 4 m blast, detonates primes | 5 rds + 200 EN |

- **ADS:** TPS FOV 70→52°; FPS 75→60° (≈1.25× [GEVO-NU]); 0.18 s transition.
- **Feel:**
  - VFX: 0.06 s beam (core #EFFFFF, glow #36E2FF), one muzzle ring per stage (img 04).
  - SFX: crisp "tchew"; charge whine rising a fourth per stage.
- **Godot:** `intersect_ray` / RayCast3D [GD-RC]. Cx 1 (charge 2).

**P2 Thunder Spindle Gatling (雷纺机炮)** (estimates):
- **Fire:** 0.3 s audible spin-up; 900 rpm (15/s); projectiles at 450 m/s.
- **Damage:** 52 per bullet (weakpoint 1.25×); impact 22 per bullet.
- **Range:** full to 80 m; 50 % at 120 m.
- **Spread:** hip 2.6°, ADS 1.1°, +1.2° max bloom.
- **Heat:** overheats after ~118 shots (≈7.9 s).
- **Active Vent:** on overheat, a needle sweeps a 0.9 s arc; press fire or reload as it crosses the marker.

  | Result | Window | Outcome |
  |---|---|---|
  | Perfect | 6 f (DMC MAX-Act [DMC-EX]) | Heat 0 + 4 s Superheated (+30 % dmg, +50 % impact) |
  | Good | 12 f | Heat 0 after 0.8 s |
  | Miss | — | 3.2 s jam |

- **Balance check:** sustained DPS ≈620 (≈745 with perfect vents) vs rifle ≈515 plus marks and crits.
- **Godot:** pooled projectiles; MultiMesh tracers [GD-MM]. Cx 2.

### 4.3 Melee: Dawn Edge plasma saber (曦刃)

| Move | Input | S / A / R (f) | Cancel into | Dmg | Impact | Reach | Hitstop | Notes |
|---|---|---|---|---|---|---|---|---|
| L1 | tap | 9 / 4 / 16 | f14–24: L2, dash, guard, skills | 380 | 180 | 9 m, 120° | 5 f | 3 m step-in |
| L2 | tap | 8 / 4 / 16 | f13–24 | 380 | 180 | 9 m, 120° | 5 f | |
| L3 | tap | 14 / 6 / 28 | f22–34: dash, guard | 820 | 480 | 10 m, 200° | 9 f | Knockback 14 m/s |
| Lunge | tap while locked at 12–40 m | 6 f windup, then ≤0.7 s at 55 m/s | → L2 | 950 | 520 | Homing 120°/s | 7 f | 140 EN [AC-ML] |
| Charged slash | hold ≥30 f | 10 / 8 / 30 | — | 1,500 + wave 600 | 900 + 300 | 11 m, 210°; wave 45 m at 70 m/s | 10 f | MOONLIGHT-style wave [AC-ML] |
| Air L1–L2 | tap in air | 8 / 4 / 14 | — | 340 | 160 | 8 m | 4 f | 0.3 s hang |
| Return Cut | melee ≤0.8 s after a perfect guard | 6 / 6 / 20 | — | 1,400 | 900 | 9 m | 10 f | Staggers non-bosses |

- **Combo scaling:** hits 1–6 deal 100 %, then −6 % per hit (floor 55 %); resets after 1.5 s without a hit; suspended on staggered targets (EXVS idea, PvE numbers [EXVS-DMG]).
- **Godot:** ShapeCast3D box swept on each active frame [GD-SC]. Cx 3.

### 4.4 Active skills (8)

**S1 Rift Step (裂隙步): blink.** L3 + LS direction / `C`. CD 8 s (Phase Dash: 12 s, 8 s with kit [TF-PD]).

| Field | Spec (estimate unless tagged) |
|---|---|
| Destinations (locked target ≤45 m) | Stick neutral or forward: 7 m behind the target, facing it. Left / right: 7 m to that flank. Back: 25 m away. |
| Without lock | 22 m in the stick direction |
| Transit | 9 f, invulnerable, drawn as a visible streak (Zero Shift travels, it doesn't pop [ZOE-ZS]) |
| Arrival | 6 f recovery, then a 0.45 s **Ambush** window: next melee or charged shot +50 % dmg, +100 % impact. Resets the dash chain. |
| Tension | Leaves a 0.6 s decoy shell that draws Swarmers [ZOE-DEC]. After 2 consecutive rear warps, bosses pre-swing at their rear (35 %). |
| Feel | Ghost shell + refraction ripple at the origin; imploding ring and +8° FOV punch on arrival; reversed whoosh + 50–80 Hz thump |
| Godot | ShapeCast3D free-space check at the destination [GD-SC], fallback ring of 8 points; collision off during transit. Cx 2. |

**S2 Skyhook Anchor (天钩锚): grapple and traversal.** Y / `E`. 2 charges, 5 s recharge each.

| Field | Spec (estimate unless tagged) |
|---|---|
| Shot | 180 m/s, 60 m (mech-scaled from Pathfinder's 21 m and Wrecking Ball's 22.2 m [APX-PF] [OW-WB]). Snaps to a locked target within 15°. |
| On a surface | Reel 30 → 46 m/s over 0.6 s. Aim >25° off the cable → swing, auto-detaching at 90° with momentum kept [APX-PF]. Jump releases with +6 m/s up. Dash, guard or attack cancels. |
| On an enemy | **Light:** yanked to 9 m in front of you in 0.35 s + 0.6 s stun (Wisp [ZOE-W]). **Heavy:** you are pulled in [DOOM-SSG]; melee during the reel = Hook Kick (900 / 700). **Staggered:** instant Core Rend (Doom hook → Blood Punch on a stunned boss [DOOM-MH]). |
| Tension | A miss costs a charge. Heavies hit you mid-reel and knockback detaches you [DOOM-SSG]. The cable has 600 HP. |
| Level hooks | Glowing anchor nodes on roofs and skybridge undersides every 40–60 m (hook nodes [DOOM-MH]; harken rappel / zip / vault [CG-SH]) |
| Feel | Emissive cable with a 0.1 s twang; latch sparks + Decal; speed lines above 35 m/s; whine pitch follows reel speed |
| Godot | Ray step per tick [GD-RC]; CharacterBody3D velocity with a rope constraint. Cx 3. |

**S3 Hailstorm Volley (雹暴齐射): multi-lock missiles.** RB / `1` or Mouse4: hold to paint, release to fire. CD 14 s (Valkyrie 30 s, D.Va 7 s [APX-VAL] [OW-DVA]).

| Field | Spec (estimate unless tagged) |
|---|---|
| Painting | Box 24°×16° on the reticle. 1 lock per 0.10 s. Max 12 locks [TF-MTMS], ≤4 per target [AC7-8AAM]. Range 160 m; LOS needed when locking. Auto-fires after 3 s. |
| Launch | 12 missiles in 0.5 s. **Bloom:** 0.2 s eject at 22 m/s in a random ±35° cone (img 05). Then 60 → 100 m/s; turn rate 300 → 600°/s after 0.6 s. Fuse 2.5 m; life 3 s. |
| Damage | 280 each, 140 impact, 3 m blast. All 12 on a Brute = 3,360 (T4). No locks → 6 missiles to the reticle point. |
| Upgrade | Hold ADS after release to steer the swarm (Salvo Core [TF-SAL]) |
| Tension | Aim held while exposed. Unguided missiles can't turn corners [TF-TR]. Spore chaff eats 4 missiles per cloud. |
| Feel | GPUParticles3D ribbon trails (`trail_enabled`, `trail_lifetime` 0.8 s) [GD-GPUP] [GD-TRAIL]; "n/12" counter; lock tick +1 semitone per lock; impacts staggered 30–60 ms |
| Godot | One MissileManager with position/velocity arrays, drawn by MultiMeshInstance3D [GD-MM]. Cx 3. |

**S4 Corona Fins (日冕翼片): remote drones.** D-pad ↓ / `Z`. Six fins.

| Field | Spec (estimate unless tagged) |
|---|---|
| Tap | Launches 2 + 2 × Marks fins (2/4/6) [GEVO-NU] at 75 m/s. They hold stations on a 9 m sphere around the target and each fires 4 beams 0.22 s apart for 110 / 45 impact (totals 880 / 1,760 / 2,640). Return after 2.4 s. Range 90 m. CD 10 s (Gundam Evolution: 9 s [GEVO-NU]). |
| Hold 0.35 s: Corona Ward | 4 fins form a tetrahedron [GW-NU] that absorbs 3,000 projectile damage over 6 s. Doesn't stop melee, shockwaves or shots from inside (Gundam Evolution barrier: 4,000 / 12 s [GEVO-NU]). The other 2 fins auto-fire 60 dmg every 0.5 s. CD 20 s. |
| Tension | Marks expire after 5 s, so two rifle taps then send. Fins have 400 HP, respawn after 6 s. Jammers cap you at 2 fins. |
| Feel | Cyan ribbons, 4 f pre-flash per beam, converging angles (img 01, 02); each fin's shot is one tone of a chord; Ward rings like glass |
| Godot | Seek + arrive steering; RayCast3D beams [GD-RC]; Ward = shader sphere + Area3D. Cx 3. |

**S5 Mirror Guard (镜返盾): parry and defense.** LB / `Q`. EN-gated.

| Field | Spec (estimate unless tagged) |
|---|---|
| Perfect window | First 10 f (167 ms), between Sekiro's 12 f [SEK] and DMC's 6 f [DMC-RG]. Minimum guard 18 f. Re-press within 0.5 s → window 5 f (anti-mash [SEK]). |
| Perfect vs melee | 0 dmg. Attacker −600 stability and 0.6 s recoil; 8 f mutual hitstop; 0.8 s Return Cut window. |
| Perfect vs projectiles | Reflected at 135 % (Vortex amplifier [TF-VS]) |
| Held guard | Front 140°, −70 % [TF-SB]. EN −60/s and −25 per 100 blocked. EN 0 → 1.0 s guard break. |
| Hold ≥0.3 s: Catch Field | Projectiles in a 6 m frontal hemisphere freeze, up to 24 [TF-VS]; max 3 s; EN −140/s. Release = 20° cone back at 135 %. Beams, melee and AoE can't be caught [OW-DVA]. |
| Rewards / risk | Perfect: +150 EN, +4 % OD. Whiff: 18 f open. Red-glow attacks are unblockable. |
| Feel | Perfect: white-gold ring, 40 sparks, 4 f chromatic punch, bell "ting" + thump. Catch: spinning projectile disk (img 12). |
| Godot | The damage pipeline checks a GuardComponent timestamp; projectiles carry `reflectable` / `owner`. Cx 3. |

**S6 Shockcore Burst (震核爆): 360° AoE.** D-pad → (alt: LB+RB) / `X`. CD 20 s (Assault Armor is charge-limited [AC-AA]).

| Field | Spec (estimate unless tagged) |
|---|---|
| Frames | 18 / 6 / 20, super armor during startup |
| Damage | Radius 16 m: 1,800 within 6 m → 600 at the edge. Impact 1,400. Knockback 20 m/s (Swarmer/Stalker), 6 m/s (Brute), 0 (boss). |
| Special | Deletes enemy projectiles in the radius on the active frame [AC-AA]. Detonates primes. Walls block it (LOS). |
| Feel | Fresnel shell 0→16 m in 0.18 s; scorch Decal [GD-DEC]; 6 f radial blur; inhale → crack-boom + glass shatter (img 07) |
| Godot | `intersect_shape` sphere query + projectile cull. Cx 2. |

**S7 Undertow Well (暗流引井): crowd control + primer.** D-pad ← / `G`. CD 16 s.

| Field | Spec (estimate unless tagged) |
|---|---|
| Throw | 45 m/s arc, ≤50 m; arms on impact or after 1.2 s |
| Field | 3.5 s, radius 12 m. Pulls Swarmers/Stalkers at ≤9 m/s; slows Brutes 40 %, bosses 15 %. Everything inside is Primed for 5 s. |
| Detonators | Shockcore, Hailstorm, Plunge, the charged-slash wave, rifle Stage 2 → **COLLAPSE**: 900 dmg + 700 impact in 10 m [ANT-CB] |
| Tension | Pulls ranged enemies toward you. Bosses can't be pulled. Ledge kills give +2 % OD (scenery-slam bonus [ZOE-GA]). |
| Feel | Violet lensing sphere, spiral inflow, violet rim on primed enemies; COLLAPSE implosion + "COLLAPSE!" floater [ANT-CB] |
| Godot | Area3D + pull vector applied in the enemy's physics step; StatusComponent. Cx 2. |

**S8 Plunge Breaker (坠击破): aerial slam.** Hold melee ≥0.25 s while airborne and ≥8 m up (KB alt: `Ctrl`). CD 12 s.

| Field | Spec (estimate unless tagged) |
|---|---|
| Dive | 10 f startup, then 95 m/s (Piledriver: 98 m/s [OW-WB]); within 30° of vertical; homes on a locked target ≤60 m away horizontally |
| Impact | Radius 10 m: 1,600 → 500, +10 % per 10 m fallen (cap +50 %). Impact 1,100. Non-bosses launched into a 0.75 s air-lock [OW-WB] for an air juggle. |
| Recovery | 24 f; dash-cancel from f12 |
| Tension | Full commitment; trades away height advantage; blocked under low ceilings |
| Feel | Plasma sheath during the dive [D-TC]; crater Decal [GD-DEC] + debris [GD-GPUP]; shake 0.4 for 0.35 s; window-crack flash within 20 m |
| Godot | ShapeCast3D ground probe [GD-SC]; damage on `is_on_floor()`. Cx 2. |

### 4.5 Ultimate: Zenith Overdrive (天顶超驱) → Zenith Lance (天顶光枪)

| Field | Spec (estimate unless tagged) |
|---|---|
| Input | `V` held 0.25 s / L3+R3 within 4 f (MGR uses both sticks for Ripper Mode [MGR-BM]); requires OD = 100 % |
| Ignition | 0.45 s, super armor. `Engine.time_scale` 0.3 for 0.25 s [GD-ENG]. Body shifts crimson → gold (img 03) [GW-TA]. |
| Duration | 12 s, between EXVS's half and full awakening [EXVS-AWK] [EXVS-IB] |
| On activation | All CDs reset [GEVO-NU]; EN full [EXVS-AWK]; heat 0 |
| While active | CDs tick 2.5× faster; EN regen ×3; dashes free. Damage +25 %, damage taken −30 %, impact +30 %. Animation speed +10 % [EXVS-AWK]. |
| Afterimages | A ghost every 3 f, each lasting 0.25 s [GW-TA]. Every 5th saber hit adds a clone slash for 600 (AC6 Ibis clones [AC-IBIS]). |
| Zenith Lance | Press again, or auto at 1.0 s left. **Charge** 0.8 s with 4 converging brackets [TF-LC]. **Beam** 3.0 s [TF-LC]: 8 m wide, 400 m long, 10 ticks/s × 450 dmg, 150 impact per tick. Pierces and breaks props. **Rooted;** turn rate ≤40°/s so it sweeps [ZOE-HAL]. |
| Aftermath | 3 s: EN regen −50 %, no dash (Trans-Am vulnerability [GW-TA]) |
| Tension | Boss barriers need 1.0 s of beam contact to break; the 0.8 s telegraph lets bosses dodge |
| Feel | Ghosts = 4 pooled mesh copies with a fading unlit shader. Beam layers: white 1.2 m / gold 4 m / red 8 m. Riser → sustained roar; hiss at the end. |
| Cx | 3 + 3 |

### 4.6 Stagger and execution (estimate)

| Archetype | Stability | Decay | Stagger | Immunity after |
|---|---|---|---|---|
| Swarmer | 150 | 30 %/s after 0.8 s | 0.8 s | — |
| Stalker | 700 | 15 %/s after 1.2 s | 1.4 s | 1.5 s |
| Brute | 2,600 | 12 %/s after 1.5 s | 2.6 s | 3 s |
| Colossus | 9,000 | 8 %/s after 2.0 s | 3.4 s | 6 s |

**Damage vs staggered targets:** ×1.8 for melee, charged shots and the Lance; ×1.35 for everything else (AC6 DHA 175–230 [AC-ML] [AC-AA]).

**Core Rend:**
- **Trigger:** melee on a staggered enemy within 7 m and ±60° in front (Titanfall: 6.67 m / 45° [TF-TERM]), or Skyhook on a staggered enemy.
- **Duration:** 0.9 s (light), 1.8 s (Brute), 2.4 s (Colossus — deals 12 % max HP, not lethal). Invulnerable throughout [TF-TERM] [DOOM-GK].
- **Reward:** +300 EN, +8 % OD, +5 % HP. The core ruptures for 1,200 / 1,000 in 10 m (living bomb, after the Meathook throw [WF-MH]).

**JACKPOT:** killing a Brute or boss with a rifle Stage 2 shot or the Lance → 0.5 s at time scale 0.2 plus a callout [DMC-JP].

### 4.7 Synergy map

| Chain | Rule | Payoff | Precedent |
|---|---|---|---|
| Rifle → Fins | 2 / 4 hits within 5 s | 2 → 6 fins (880 → 2,640) | [GEVO-NU] |
| Impact → Stagger → Core Rend | Stability full | ×1.8 window + invulnerable execution + EN / OD / HP | [AC-AA] [TF-TERM] [DOOM-GK] |
| Perfect guard → Return Cut | 0.8 s | 1,400 + stagger | [SEK] [DMC-RG] |
| Catch Field → release | ≤24 projectiles | 135 % back | [TF-VS] |
| Undertow → detonator | Primed 5 s | COLLAPSE 900 / 700 | [ANT-CB] |
| Skyhook → melee | During the reel | Hook Kick; staggered target → Core Rend | [DOOM-MH] |
| Rift Step → Ambush | 0.45 s | +50 % dmg, +100 % impact | [ZOE-ZS] |
| Plunge → air juggle | 0.75 s air-lock | Free air L1–L2 | [OW-WB] |
| Overdrive | CD reset + 2.5× tick | Two rotations in 12 s | [GEVO-NU] [EXVS-AWK] |

### 4.8 Input mapping

| Action | KB+M | Gamepad (Xbox [PS]) |
|---|---|---|
| Move / look | WASD / mouse | LS / RS |
| Fire (hold = charge; overheated = vent) | LMB | RT [R2] |
| Aim | RMB | LT [L2] |
| Jump / hover | Space | A [×] |
| Dash tap / Assault Boost hold | Shift | B [○] |
| Melee: tap, hold = charged slash, air-hold = Plunge; context Lunge / Core Rend | F | X [□] |
| Mirror Guard (tap parry, hold catch) | Q | LB [L1] |
| Hailstorm Volley (hold paint, release) | 1 / Mouse4 | RB [R1] (RS stays free to sweep) |
| Skyhook Anchor | E | Y [△] |
| Rift Step | C | L3 |
| Lock-on / switch target | MMB / flick >15° | R3 / RS flick |
| Corona Fins (tap / hold) | Z | D-pad ↓ |
| Shockcore Burst | X | D-pad → (alt preset: LB+RB) |
| Undertow Well | G | D-pad ← |
| Swap primary / hold = reload | Wheel / R | D-pad ↑ |
| Zenith Overdrive / Lance | V hold 0.25 s | L3+R3 (4 f chord; Rift Step waits 4 f before committing) |
| 1st / 3rd person toggle | B | View |
| Loadout wheel | Tab hold | D-pad ↑ hold 0.4 s (out of combat) |

**Input rules:**
- Tap/hold threshold 0.25 s.
- Input buffer 6 f.
- Chords resolve within 4 f.
- Fully remappable; ship two presets.

### 4.9 HUD: twin-arc hotbar + loadout wheel

- **Twin arcs under the reticle, mirroring the hands.**
  - Left arc: Guard, Rift, Undertow, Fins.
  - Right arc: Hailstorm, Skyhook, Shockcore, charged-melee state.
  - 48 px hex icons; cooldown = clockwise radial wipe; charge pips.
  - Ready = 120 ms flash + chime. EN Outage = desaturated icons with a red rim.
- **Reticle cluster.**
  - EN arc (left) and HEAT arc (right, gatling only).
  - Paint box with an "n/12" counter; the vent needle appears inside the reticle.
- **OD ring** bottom center. Titanfall puts its core ring bottom-left (img 12); centered suits a symmetric cockpit.
- **Enemy plate:** HP, a yellow STABILITY bar that flashes "STAGGER", 2 mark pips, violet PRIMED rim.
- **FPS cockpit:** the arcs are printed on the lower canopy glass. VFX opacity −40 %, camera shake −50 %; cockpit strut shake replaces it.
- **Loadout wheel:** 8 slots for swapping alternate skills into the D-pad / key slots.
  - Time scale 0.25 while open (Doom Eternal's weapon wheel slows the game [DOOM-SSG]).
  - 3 s lockout after closing in combat.

### 4.10 Feel tuning (estimate; rules [SAK-HS], APIs [GD-IN] [GD-ENG])

| Event | Hitstop | Shake (amp, dur) | Rumble weak / strong, ms | Global time |
|---|---|---|---|---|
| Rifle hit | 0 f | 0.02, 0.06 s | 0.15 / 0, 30 | — |
| Rifle Stage 2 | 3 f | 0.12, 0.15 s | 0.3 / 0.5, 90 | — |
| Saber L1 / L2 | 5 f | 0.05, 0.08 s | 0.35 / 0, 60 | — |
| Saber L3 / Lunge | 9 f / 7 f | 0.15, 0.15 s | 0.5 / 0.4, 100 | — |
| Perfect guard | 8 f | 0.10, 0.10 s | 0.8 / 0.2, 80 | — |
| Shockcore | 4 f (victims) | 0.30, 0.25 s | 0.4 / 1.0, 220 | — |
| Plunge Breaker | 6 f | 0.40, 0.35 s | 0.6 / 1.0, 260 | — |
| Overdrive ignition | — | 0.20, 0.30 s | 0.3 / 0.7, 300 | 0.3 for 0.25 s |
| Zenith Lance | — | 0.15 continuous | 0.3 / 0.6, every 250 ms | — |
| JACKPOT kill | — | 0.25, 0.30 s | 1.0 / 1.0, 200 | 0.2 for 0.5 s |

**Hitstop formula:** melee frames = clamp(2 + dmg/150, 3, 12); projectiles get half; electric/beam +2 f.

### 4.11 Godot 4.7 notes and build order

**Hitstop**
- Use a per-entity `local_time_scale`: freeze velocity integration and animation speed for N ticks.
- Never use `Engine.time_scale` for hitstop; it would also freeze missiles, fins and timers.
- `time_scale` does not adjust the physics tick rate [GD-ENG]; keep global changes to ≤0.5 s beats.

**Fast movers**
- Turn on physics interpolation for 42 m/s dashes and 100 m/s missiles [GD-PI].

**Systems**
- Hitscan: RayCast3D [GD-RC]. Saber: ShapeCast3D [GD-SC].
- Missiles: MultiMeshInstance3D [GD-MM]. Trails: GPUParticles3D trails [GD-GPUP] [GD-TRAIL].
- Craters: Decal [GD-DEC]. FOV punch: Camera3D `fov` [GD-CAM].
- Rumble: `Input.start_joy_vibration(device, weak, strong, duration)` [GD-IN].
- Each skill is a `.tres` Resource with the numbers above.

**Build order:**

| Sprint | Contents (Cx) |
|---|---|
| A, core feel | Rifle (1), Dash/AB (2), Saber + Lunge (3), hitstop/rumble service (2), Stagger → Core Rend (3), Mirror Guard (3) |
| B, signature | Hailstorm (3), Skyhook (3), Shockcore (2), Zenith Overdrive (3) |
| C, depth | Fins + Marks (3), Undertow (2), Plunge (2), Gatling + vent (2), Rift Step (2), Zenith Lance (3), hotbar (2), loadout wheel (2) |

### 4.12 Acceptance tests (for the M78 agents)

**Mirror Guard**
- A swing landing 0–166 ms after the press → `PerfectGuard`.
- At 170 ms → normal guard (−70 %).
- After a re-press within 0.5 s → 83 ms window.

**Hailstorm Volley**
- Painting 3 dummies for 1.2 s → 12 locks, ≤4 each.
- All 12 hit dummies 60 m away within 2.0 s.

**Stagger and execution**
- 2,600 impact on a Brute within 1.5 s → `Staggered` for 2.6 s ± 1 f.
- The Core Rend prompt appears only within 7 m and ±60°.

**Hitstop**
- An L3 hit freezes the attacker and victim for 9 f.
- Missiles in flight keep moving.

**Overdrive**
- CDs reset on activation; the state lasts 12.0 s ± 1 f.
- The Lance auto-fires at 1.0 s left; the aftermath blocks dashing for 3 s.

**Gatling vent**
- A press at the marker ±50 ms → heat 0 + Superheated for 4 s.

## 5. Risks and mitigations

1. **IP.** Never reuse "Funnel / DRAGOON / Trans-Am / Zero Shift / AT Field / Vortex / Assault Armor" names or silhouettes. Use hex-petal fins and a crimson-to-gold overdrive.
2. **Scope.** Sprints A + B are the demo floor; C is the stretch goal.
3. **Global time scale** freezes VFX and missiles. Use per-entity hitstop [GD-ENG].
4. **First-person whiteout** from Pulse, Lance and Overdrive. FPS presets get −40 % opacity and bloom clamps.
5. **Dense multi-level city.**
   - Lunges, reels and dives clip or overshoot ledges: ShapeCast path checks, ledge-stop, SpringArm camera.
   - Anchor nodes must be authored in Blender.
6. **Cognitive load** (EN, Heat, OD, Marks, Stability, Primes). Teach them in that order; keep the color code: cyan player, violet prime, yellow stability, crimson-gold OD.
7. **Frame-rate dependence.** Doom's meat-hook speed bug came from frame-based acceleration [DOOM-SSG]. Use seconds × delta everywhere.
8. **Chord misfires** (L3+R3, LB+RB). Use 4 f windows with buffered single presses.
9. **Tripo meshes** need hand-placed hurtbox / weakpoint bones for marks, crits and Core Rend alignment.
10. **Patch volatility.** OW, AC6 and Gundam Evolution values are starting points, not targets.
11. **Scale mismatch between dossiers** (8 / 9 / 16 m). The lead must fix MECH_H once. Skill ranges here scale ×H/8 (table in §4.1); locomotion comes from the level / movement metrics.

## 6. References

**Titanfall wiki:**
- [TF-LC] https://titanfall.fandom.com/wiki/Laser_Core
- [TF-VS] https://titanfall.fandom.com/wiki/Vortex_Shield
- [TF-FC] https://titanfall.fandom.com/wiki/Flame_Core
- [TF-SC] https://titanfall.fandom.com/wiki/Sword_Core
- [TF-PD] https://titanfall.fandom.com/wiki/Phase_Dash
- [TF-SMC] https://titanfall.fandom.com/wiki/Smart_Core
- [TF-SAL] https://titanfall.fandom.com/wiki/Salvo_Core
- [TF-TS] https://titanfall.fandom.com/wiki/Thermal_Shield
- [TF-ES] https://titanfall.fandom.com/wiki/Electric_Smoke
- [TF-AW] https://titanfall.fandom.com/wiki/Arc_Wave
- [TF-SB] https://titanfall.fandom.com/wiki/Sword_Block
- [TF-PW] https://titanfall.fandom.com/wiki/Particle_Wall
- [TF-GS] https://titanfall.fandom.com/wiki/Gun_Shield
- [TF-TT] https://titanfall.fandom.com/wiki/Tether_Trap
- [TF-TR] https://titanfall.fandom.com/wiki/Tracker_Rockets
- [TF-SL] https://titanfall.fandom.com/wiki/Sonar_Lock
- [TF-40MM] https://titanfall.fandom.com/wiki/40mm_Tracker_Cannon (3 locks from 3 hits → rocket salvo)
- [TF-MTMS] https://titanfall.fandom.com/wiki/Multi-Target_Missile_System
- [TF-LS] https://titanfall.fandom.com/wiki/Laser_Shot
- [TF-RG] https://titanfall.fandom.com/wiki/Plasma_Railgun
- [TF-TERM] https://titanfall.fandom.com/wiki/Termination
- [TF-DC] https://titanfall.fandom.com/wiki/Damage_Core
- [TF-UC] https://titanfall.fandom.com/wiki/Upgrade_Core

**Armored Core wiki:**
- [AC-AA] https://armoredcore.fandom.com/wiki/ARMORED_CORE_VI_FIRES_OF_RUBICON/Assault_Armor
- [AC-PA] https://armoredcore.fandom.com/wiki/Pulse_Armor
- [AC-PP] https://armoredcore.fandom.com/wiki/Pulse_Protection
- [AC-TA] https://armoredcore.fandom.com/wiki/Terminal_Armor
- [AC-STAB] https://armoredcore.fandom.com/wiki/Stability
- [AC-AB] https://armoredcore.fandom.com/wiki/Assault_Boost (includes the Yamamura / Famitsu quote and boost kick)
- [AC-ML] https://armoredcore.fandom.com/wiki/IA-C01W2:_MOONLIGHT
- [AC-CO] https://armoredcore.fandom.com/wiki/IB-C03W2:_WLT_101
- [AC-IBIS] https://armoredcore.fandom.com/wiki/IB-07:_SOL_644
- [AC-QB] https://armoredcore.fandom.com/wiki/Quick_Boost

**Gundam:**
- [GEVO-NU] https://gunevo.swiki.jp/index.php?%CE%BD%E3%82%AC%E3%83%B3%E3%83%80%E3%83%A0
- [EXVS-DMG] https://www.dragonicfighter.net/entry/2021/03/17/045916
- [EXVS-AWK] https://www.dragonicfighter.net/entry/2021/03/22/044714
- [EXVS-IB] https://gundam-exvs.online/exvs2ib-kakusei-guide/
- [EXVS-WZ] https://w.atwiki.jp/exvs2ob/pages/159.html (search-result snippet; the page is Cloudflare-blocked)
- [EXVS-GOD] https://w.atwiki.jp/exvs2ob/pages/238.html (search-result snippet)
- [GW-TA] https://gundam.fandom.com/wiki/Trans-Am_System
- [GW-NU] https://gundam.fandom.com/wiki/RX-93_%CE%BD_Gundam
- [GW-SF] https://gundam.fandom.com/wiki/ZGMF-X20A_Strike_Freedom_Gundam
- [GW-WZ] https://gundam.fandom.com/wiki/Wing_Gundam_Zero
- [GW-SH] https://gundam.fandom.com/wiki/GF13-017NJ_Shining_Gundam
- [GW-HS] https://gundam.fandom.com/wiki/MSN-00100_Hyaku_Shiki
- [GW-PF] https://gundam.fandom.com/wiki/Psycho-Frame
- [GW-XB] https://gundam.fandom.com/wiki/XM-X1_Crossbone_Gundam_X-1

**Other anime:**
- [MAC-IC] https://macross.fandom.com/wiki/Itano_Circus
- [MAC-VF1] https://macross.fandom.com/wiki/VF-1_Valkyrie
- [CG-SH] https://codegeass.fandom.com/wiki/Slash_Harken
- [CG-LS] https://codegeass.fandom.com/wiki/Landspinner_Propulsion_System
- [EVA-AT] https://wiki.evageeks.org/A.T._Field
- [PR-PC] https://pacificrim.fandom.com/wiki/I-19_Plasmacaster
- [PR-GD] https://pacificrim.fandom.com/wiki/Gipsy_Danger_(Jaeger)

**Zone of the Enders:**
- [ZOE-ZS] https://zoneoftheenders.fandom.com/wiki/Zero_Shift
- [ZOE-HM] https://zoneoftheenders.fandom.com/wiki/Homing_Missile
- [ZOE-HAL] https://zoneoftheenders.fandom.com/wiki/Halberd
- [ZOE-VC] https://zoneoftheenders.fandom.com/wiki/Vector_Cannon
- [ZOE-W] https://zoneoftheenders.fandom.com/wiki/Wisp
- [ZOE-G] https://zoneoftheenders.fandom.com/wiki/Geyser
- [ZOE-GA] https://zoneoftheenders.fandom.com/wiki/Gauntlet
- [ZOE-DEC] https://zoneoftheenders.fandom.com/wiki/Decoy
- [ZOE-FAQ] https://gamefaqs.gamespot.com/ps2/561586-zone-of-the-enders-the-2nd-runner/faqs/22267 (search-result snippet)

**Hero shooters, Warframe, Destiny, Mecha BREAK, Ace Combat:**
- [OW-DVA] https://overwatch.fandom.com/wiki/D.Va
- [OW-WB] https://overwatch.fandom.com/wiki/Wrecking_Ball
- [OW-REIN] https://overwatch.fandom.com/wiki/Reinhardt
- [APX-VAL] https://apexlegends.fandom.com/wiki/Valkyrie
- [APX-PF] https://apexlegends.fandom.com/wiki/Pathfinder
- [APX-NC] https://apexlegends.fandom.com/wiki/Newcastle
- [WF-MH] https://warframe.fandom.com/wiki/Meathook
- [WF-SM] https://warframe.fandom.com/wiki/Shield_Maiden
- [WF-EI] https://warframe.fandom.com/wiki/Exalted_Ironbride
- [WF-GM] https://warframe.fandom.com/wiki/Guard_Mode
- [D-FOH] https://destiny.fandom.com/wiki/Fist_of_Havoc
- [D-WOD] https://destiny.fandom.com/wiki/Ward_of_Dawn
- [D-TC] https://plarium.com/en/blog/destiny-2-class-guide/ (Thundercrash description)
- [MB-LIST] https://www.turtlebeach.com/blog/all-mecha-break-strikers-and-their-abilities
- [AC7-8AAM] https://acecombat.fandom.com/wiki/8_Target_Air-to-Air_Missile (search-result snippet)

**Action games:**
- [DOOM-SSG] https://doomwiki.org/wiki/Super_shotgun_(Doom_Eternal)
- [DOOM-MH] https://doom.fandom.com/wiki/Meat_Hook
- [DOOM-BP] https://doomwiki.org/wiki/Blood_punch
- [DOOM-GK] https://doomwiki.org/wiki/Glory_kill
- [DOOM-CS] https://doomwiki.org/wiki/Chainsaw_(Doom_Eternal)
- Doom push-forward combat, GDC 2018: https://www.gdcvault.com/play/1024940/Embracing-Push-Forward-
- [SEK] https://sekiroshadowsdietwice.wiki.fextralife.com/Deflection (search-result snippet: 12 f / 0.2 s, shrinks with spam)
- [DMC-RG] https://devilmaycry.fandom.com/wiki/Royalguard_Style
- [DMC-EX] https://devilmaycry.fandom.com/wiki/Exceed
- [DMC-JP] https://devilmaycry.fandom.com/wiki/Jackpot
- [BAYO-WT] https://bayonetta.fandom.com/wiki/Witch_Time
- [MGR-BM] https://metalgear.fandom.com/wiki/Blade_Mode
- [MGR-ZD] https://metalgear.fandom.com/wiki/Zandatsu
- [VQ-PG] https://www.platinumgames.com/official-blog/article/9334
- [VQ-ARS] https://vanquish.fandom.com/wiki/Augmented_Reaction_Suit
- [ANT-CB] https://anthem.fandom.com/wiki/Combo
- [SAK-HS] https://sourcegaming.info/2015/11/11/thoughts-on-hitstop-sakurais-famitsu-column-vol-490-1/
- Sakurai video "Stop for Big Moments!": https://www.youtube.com/watch?v=OdVkEOzdCPw

**Godot docs (stable = 4.7):**
- [GD-ENG] https://docs.godotengine.org/en/stable/classes/class_engine.html
- [GD-GPUP] https://docs.godotengine.org/en/stable/classes/class_gpuparticles3d.html
- [GD-TRAIL] https://docs.godotengine.org/en/stable/tutorials/3d/particles/trails.html
- [GD-SC] https://docs.godotengine.org/en/stable/classes/class_shapecast3d.html
- [GD-RC] https://docs.godotengine.org/en/stable/classes/class_raycast3d.html
- [GD-MM] https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html
- [GD-IN] https://docs.godotengine.org/en/stable/classes/class_input.html
- [GD-PI] https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/physics_interpolation_introduction.html
- [GD-DEC] https://docs.godotengine.org/en/stable/classes/class_decal.html
- [GD-CAM] https://docs.godotengine.org/en/stable/classes/class_camera3d.html
