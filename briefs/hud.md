# Brief: hud — HUD, cockpit glass HUD, combat feedback, menus

## Goal
A clean, gorgeous sci-fi HUD that makes a rich kit readable at a glance: reticle cluster with EN/heat arcs,
twin-arc skill hotbar, overdrive ring, weapon/ammo/charge, lock markers and missile paint, enemy plates
(HP, stability, marks, primed), boss bar, hit markers and damage numbers, style meter, objective + compass +
radar, contextual tutorial prompts — in third person (screen space) and first person (diegetic on the
canopy glass). Plus title, pause, settings, controls, game-over and victory screens.

## Read first
`docs/CONTRACTS.md` (hud_state contract §5), `docs/SPEC.md` §3, §5, §6, §8, §9, `docs/ART.md` (palette,
hero cyan #4FE6FF, amber #F2A33A, danger #FF4D5A, monster acid #9BFF3A), `ref/research/skills-catalog.md`
§4.9 (twin arcs, reticle cluster, OD ring, enemy plate), `ref/research/juice-impact.md` §8 (hit markers,
kill confirms, damage numbers, style meter), `ref/research/feel-mech-games.md` §2.4, §10, §15.4 (cockpit
HUD lessons), `ref/images/feel-mech-games/` (HUD references: AC6, Titanfall, EXVS, Mecha BREAK).
Read the existing `hud_state()` implementations in `game/player/**` and `game/combat/**`.

## You own
`game/ui/**` (`hud.tscn` instanced by main, menus, fonts, icons, shaders, tests).

## Build
1. **Data**: each frame read `Game.player.hud_state()` and every component's `hud_state()` (find them as
   PlayerMech children); listen to Events for hit/kill/parry/perfect_dodge/combo/lock/objective/boss
   events. Missing keys/components = hide that widget (units land at different times).
2. **Reticle cluster** (centre): dynamic reticle per weapon (rifle: thin cross + charge pips; gatling:
   circle with spread; red when the hard target is in effective range, green otherwise), EN arc (120°,
   left), heat arc (right, gatling only) with the vent needle + mark during overheat, hit markers
   (white normal / amber weak / red kill X with 0.25 s scale pop), soft-lock bracket.
3. **Targets**: hard-lock diamond with distance; missile paint box 24°×16° + lock diamonds + "n/12"; enemy
   plates above locked/nearby enemies (HP, thin stability bar flashing STAGGER, two mark pips, violet
   PRIMED rim); off-screen threat arrows for attackers (red when an unblockable is winding up).
4. **Bottom**: twin-arc hotbar (left: guard, rift step, well, fins; right: missiles, anchor, burst, charged
   melee) with radial cooldown wipes, charges pips, ready flash; OD ring bottom centre (pulses at 100 %,
   "V" prompt); HP bar (segmented, red flash on damage); weapon panel (name, ammo, reload bar).
5. **Top**: objective text + spire counter (0/3), compass strip with spire/boss markers and distance,
   circular radar (300 m, enemies as dots by class, layers shown by brightness), boss bar (name 巢母 BROOD
   TITAN, HP segments per core, phase pips).
6. **Combat feedback**: damage numbers (toggle in settings; white/amber crit/blue shield; stack and
   rise), style meter D→SSS (combo count + rank, decays) on the right, "PERFECT" / "PARRY" / "JACKPOT" /
   "COLLAPSE" callouts (brief, centred-low), low-HP warning (edge pulse + heartbeat via Audio event).
7. **First person**: the same information rendered to a SubViewport texture projected on the canopy glass
   (curved quad in the camera-aim cockpit) with slight parallax; screen-space widgets hidden.
8. **Tutorial prompts**: contextual key/button glyph prompts (KB+M or pad by last input device) shown once
   per verb when first relevant (SPEC §8 step 1).
9. **Menus**: title (game logo 天枢 TIANSHU, "Press any key", start/settings/quit; background = the city
   vista camera V1 if the world exists), pause (resume/settings/controls/quit), settings (all Settings keys
   with sliders/toggles, applied live), controls (both schemes from SPEC §3 drawn as a table), game over
   (retry from checkpoint), victory (time, max combo, parries, perfect dodges, executions, kills).
10. Style: thin lines, angular brackets, translucent dark panels (#0B1220 at 55 %), cyan primary, amber
   warnings, red danger; fonts: a clean sans for Latin + a Chinese-capable font (Noto Sans SC — check the
   SIL OFL licence file in the font folder; download with curl into `game/ui/fonts/`); never cover the
   centre 30 % of the screen except reticle elements.

## Done when
- `tools/godot.sh check --only=res://ui/` → 0 errors; `tools/godot.sh test res://ui/tests/test_hud.gd`
  (feeds fake hud_state dictionaries + events: every widget shows/hides correctly, cooldown wipes match
  values, hit markers/callouts time out, menus navigate with keyboard and pad).
- Captures `captures/hud_*.jpg` at 1600×900 in the sandbox with the real player: idle, combat with a
  locked target + missile paint, overheat vent, overdrive ready, low HP, boss bar (fake), first-person
  canopy HUD, title, pause, settings, victory. Look at each: readable, not cluttered, centre clear.
