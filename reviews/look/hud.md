# Look diagnosis items for hud (lead-verified workflow wf_5e92d07a-bee, 2026-11-02)

Source: an independent critique of the user's screenshot `tmp/lead/user_shot_1.png` (A6 hive fight) against the key art.
Do them in this order (impact per hour). Each item: what is in the picture, the cause (file:line), the fix.

## Two bracket boxes for one target: the soft-lock bracket is drawn around the crosshair, not around the target  (impact 4, ~0.5 h)

**In the picture:** In the centre of the screen there are two cyan bracket boxes. One (680-735, 468-522) surrounds the lock diamond on the spire pod. The second (768-835, 480-548) surrounds the red crosshair 90 px to the right. It reads as two targets, or as a lock that is out of alignment.

**Cause:** /Users/minimax/m/mecha-city/game/ui/widgets/reticle.gd:97-98 calls `_draw_soft_lock(c)` whenever any soft target exists, even while a hard lock is up. reticle.gd:174-181 draws that bracket at `c`, the screen centre, instead of at the target. Meanwhile /Users/minimax/m/mecha-city/game/ui/widgets/markers.gd:87-89 draws the real hard-lock diamond and a 53 px bracket box (3.8x LOCK_ARM) on the target itself.

**Fix:** 1. reticle.gd:97: skip the soft-lock bracket when there is a hard target.
2. Otherwise project the soft target with data.project and draw the bracket there, not at screen centre.
3. markers.gd:88: shrink the hard-lock box to 2.6x LOCK_ARM (36 px) so the diamond and the box read as one mark.

Visual target: one lock mark per target, like AC6 (ref image 01, item 4).

## The most important signal in the frame, the Harrier's UNBLOCKABLE windup, cannot be read  (impact 7, ~1 h)

**In the picture:** Top left (125-290, 172-243). The red warning triangle sits on top of the objective counter's '◇◇◇' pips. Its red caption 'UNBLOCKABLE 不可格挡' is printed straight across the Harrier plate's name and HP bar. The cyan '0 / 3 HIVES 蚀巢' prints over both. That is three layers of text and none of it is legible (crop: /Users/minimax/m/mecha-city/tmp/lookcap/hud/tl_plate.png). Nothing near the reticle tells the player that an unblockable attack is coming.

**Cause:** Why the caption lands on the plate:
- /Users/minimax/m/mecha-city/game/ui/widgets/telegraphs.gd:106 anchors the tell at the enemy's root plus 2 m. :14 (LIFT 74) and :113 put the icon 74 px above that point.
- telegraphs.gd:126 puts the caption 33 px (ICON_R+18) below the icon, so about 41 px above the anchor.
- At 82 m, 2 m is about 16 px on screen, so the caption lands about 57 px above the root.
- /Users/minimax/m/mecha-city/game/ui/widgets/enemy_plates.gd:69-70 places the plate between 44 and 84 px above the root, so the caption always lands inside the plate. The comment 'clear of the plate' at telegraphs.gd:14 is false.

Why it is buried:
- /Users/minimax/m/mecha-city/game/ui/hud.gd:12 versus :16 draws the objective text on top of both.
- /Users/minimax/m/mecha-city/game/ui/widgets/markers.gd:117-118 draws a threat arrow only for attackers that are off screen. An on-screen attacker near the edge gets no cue near the centre.

**Fix:** 1. Anchor the telegraph icon to the plate: centre it 14 px above the plate's top edge, using one shared plate_rect(target) helper in enemy_plates.gd.
2. Remove the in-combat caption. Shape plus colour is the code, and the tutorial teaches it once.
3. In markers.gd, also draw unblockable and ranged tells as a 12 px red or amber triangle on a 72 px ring around the reticle, pointing at the attacker, whenever the attacker is outside the central 40% of the screen.

Visual target: AC6, where the warning arrives at the reticle, so you never have to look at a corner to learn that you must dodge.

## The objective is thin white text on a white-hot sky (about 1.6:1 contrast), and it says 0/3 twice  (impact 6, ~1 h)

**In the picture:** Top left (56-410, 115-205):
- 'OBJECTIVE 目标' is a ghost: dim text on sky.
- The line '摧毁蚀巢 0/3  DESTROY THE HIVE SPIRES' is barely visible.
- The line below repeats the count as '0 / 3 HIVES 蚀巢 ◇◇◇'.

Measured: the background has a median luminance of 0.50 against white glyphs at about 0.84, which is roughly 1.6:1. WCAG asks for 4.5:1. AC6 and DXM objectives reach well above that because they use drop shadows.

**Cause:** /Users/minimax/m/mecha-city/game/ui/widgets/objective_bar.gd:22-29 draws no backing panel. The header (:25) and the objective line (:27-28) are drawn without shadow or outline. objective_bar.gd:33-40 adds a second counter. /Users/minimax/m/mecha-city/game/flow/flow_progress.gd:157 bakes '%d/%d' and both languages into the objective string. flow_progress.gd:163 appends the hint to the same line with '   ·   ', so hints run past the 470 px width.

**Fix:** 1. Drop the header.
2. Draw the objective as one 20 px medium-weight line with a 3 px INK outline, over a backing strip: INK at 0.45, 34 px tall, fading to 0 over its last 120 px.
3. Use one language per locale.
4. Show the count once, as the three diamonds after the line. Remove either the '%d/%d' at flow_progress.gd:157 or the label at objective_bar.gd:34 (a two-line change on the flow side).
5. Give the hint its own 16 px line that hides after 8 s. Emit it separately instead of joining it on at :163.

Visual target: DXM (ref image 17) 'Eliminate the enemy AIs. / Remaining Targets 33': bold white with a hard shadow, readable on any sky.

## Compass: doubled green labels, height shown as if it were distance, one label cut by the heading line and one spilling off the strip  (impact 6, ~1 h)

**In the picture:** Compass strip (490-1110, 98-148):
- '▼SPIRE -235m' is two labels printed on top of each other. At 12x zoom the glyphs are visibly doubled (/Users/minimax/m/mecha-city/tmp/lookcap/hud/c3.png, compass_lbl1.png).
- The cyan centre line slices through that label between the R and the E.
- '▼SPIRE -87 m' is pinned to the right edge, and its '-87 m' hangs past the end of the strip onto bare sky (x 1110-1150).
- Players will read '-235 m' as a distance, but it is a height difference.
- Green on the taupe strip looks muddy.

**Cause:** /Users/minimax/m/mecha-city/game/ui/widgets/compass.gd:
- :49-52: x_for clamps every off-strip marker to the strip edge, so they stack there.
- :80-85: every spire gets a label, with no collision pass, so spires at nearly the same bearing overprint.
- :94-97: the text is '%+d m' of dy, the height difference, not the distance.
- :61-63: the heading line is drawn after the markers, so it cuts through them.
- :83: labels use ACID, the same green as the Ripper blips (radar.gd:14) and the monsters' own glow.

**Fix:** 1. Label only the current objective (the nearest standing spire) as '蚀巢 312 m': horizontal distance, 16 px white/gold, outlined.
2. Add the ▲/▼ chevron and a small height suffix only when the height difference is more than 15 m.
3. Other spires get the 5 px diamond only, with no text.
4. Collapse markers pinned to an edge into one arrow with a count ('▶ 2'), and keep all text inside the strip.
5. Skip any label within 70 px of one already drawn.
6. Draw the heading line before the markers, or as a notch above the strip.

Visual target: the AC6 and Titanfall 2 compasses: a thin tape with one objective tag.

## A 200 px ring around the crosshair: the EN gauge plus a gatling HEAT gauge that is always empty, cutting through the lock  (impact 8, ~1.5 h)

**In the picture:** In the centre, a thick cyan arc (698-752, 425-600) and a thick dark arc with a white vent tick (848-900, 425-600) bracket the crosshair. The dark arc is the gatling's heat gauge, shown empty even though the rifle is equipped. The cyan arc runs straight through the HIVE SPIRE plate's HP bar, the lock diamond and its '6? m' distance (crop: /Users/minimax/m/mecha-city/tmp/lookcap/hud/lockzone.png). The 'EN' and 'HEAT' captions are drawn, but they are invisible on the sunlit sky (background luminance 0.95 and 0.86).

**Cause:** - /Users/minimax/m/mecha-city/game/ui/widgets/reticle.gd:7-9 sets radius 98, width 7 and a 120° sweep for each arc.
- reticle.gd:89-90 draws both arcs every frame.
- reticle.gd:127 hides HEAT only when the heat value is missing from the HUD data. But /Users/minimax/m/mecha-city/game/combat/weapons/weapon_system.gd:182-185 always copies the gatling's heat into it, even with the rifle out.
- /Users/minimax/m/mecha-city/game/ui/hud_palette.gd:138 draws every gauge track in TRACK colour at 0.8 alpha, so an empty gauge is a heavy dark band (measured minimum luminance 0.07 on a 0.86 sky).
- reticle.gd:121 and :137 draw the captions in TEXT_DIM.

**Fix:** 1. Radius 98→64 px, width 7→3 px, sweep 120→90°, track alpha 0.8→0.2.
2. reticle.gd:127: draw HEAT only when the gatling is equipped, heat is above 5%, or the gun is overheated.
3. Fade EN out once it has been full and unspent for 1.5 s; bring it back as soon as it drops below 100%.
4. Delete the 'EN' and 'HEAT' words.
5. When the hard target projects within 90 px of the centre, put its distance at the reticle's lower right, outside the ring.

Visual target: AC6 (ref image 01, item 3): a 3 px arc hugging the reticle, no labels, never crossing the lock box.

## Colours mean several things at once: green is both objective and enemy, red is both 'in range' and 'unblockable'  (impact 4, ~0.75 h)

**In the picture:** - The compass spire labels, the radar's spire diamonds and the radar's Ripper blips are all the same lime green.
- That green is also the glow of the hive trunk and the Harrier in the world, so HUD green disappears into the monsters.
- The crosshair is red because the target is in range, but red also marks every enemy HP bar and the UNBLOCKABLE warning.
- The radar colours its blips green, jade, amber and red by enemy class.

**Cause:** - /Users/minimax/m/mecha-city/game/ui/widgets/radar.gd:13-17: green Ripper/Mantis, jade Harrier, amber Spitter, red Juggernaut. radar.gd:120: spires in ACID green.
- /Users/minimax/m/mecha-city/game/ui/widgets/compass.gd:83: spires in ACID green.
- /Users/minimax/m/mecha-city/game/ui/widgets/reticle.gd:78-81: red (DANGER) means in range, JADE means out of range.
- /Users/minimax/m/mecha-city/game/ui/hud_palette.gd:14-15 defines ACID and JADE.
- /Users/minimax/m/mecha-city/game/ui/widgets/enemy_plates.gd:89: ACID marks a staggered HP bar.

**Fix:** Put one rule table in hud_palette.gd:
- Cyan: self and systems.
- White or gold #ffd36b: objective and navigation (compass tag, radar spire diamonds, and a spire plate that shows 4 pod pips instead of the stability bar).
- One red-orange family: hostile (blips, plate HP, unblockable).
- Amber: warnings only (empty, low, overheat).
- Violet: primed and boss.

Remove green from the HUD entirely. Show the out-of-range reticle in WHITE at 0.6 instead of JADE.

Visual target: AC6, where red means the enemy and white means you.

## The radar is a smear of hollow circles and chevrons, and its legend is invisible  (impact 5, ~1 h)

**In the picture:** Top-right disc (1372-1544, 110-282). About a dozen hollow green rings with ▲/▼ chevrons pile up around the player arrow (1415-1500, 165-230). Three rings plus cross lines add more noise. The '300 m / ▲上层 ▼下层' legend below it (1420-1500, 290-320) cannot be seen against the sky: dim text at 0.55 alpha on a background of luminance 0.67.

**Cause:** - /Users/minimax/m/mecha-city/game/ui/widgets/radar.gd:6 and :8 set radius 86 px and range 300 m. That is 0.29 px per metre, so a fight within 40 m collapses into 12 px.
- radar.gd:29 and :35-49 plot every enemy within 300 m.
- radar.gd:64-72 draw a disc at 0.45 alpha, three rings, cross lines and an outer ring.
- radar.gd:94-105 turn any blip more than 12 m above or below the player into a hollow ring plus a chevron. In a stacked city that is most of them.
- radar.gd:81-88 draw a permanent legend in TEXT_DIM.

**Fix:** 1. Radius 70 px and range 150 m. Show enemies beyond 150 m as ticks on the rim.
2. One mid ring plus the rim, no cross lines, disc alpha 0.3.
3. Delete the legend.
4. Chevrons only beyond 25 m of height difference.
5. Merge blips within 4 px of each other into one dot with a count.
6. One hostile colour, with size encoding class. Elites as filled triangles.

Visual target: GB4 (ref image 19): dark disc, two rings, a handful of clean marks, nothing written underneath.

## The type cannot survive a bright city: one regular weight, 14 px dim captions, outlines off by default  (impact 7, ~1.5 h)

**In the picture:** Every caption drawn straight on the scene disappears: 'OBJECTIVE 目标', 'EN', 'HEAT', the radar legend, 'ARMOUR 装甲' (58, 866, on the mech's arm), 'OD 0%', and the hotbar key letters Q/G/Z/E/X/F under each hex. The armour bar's cyan segments sit on the hero's own cyan-lit armour. Mixing Chinese and English on every label (贯光步枪 PIERCE-LIGHT, 装甲 ARMOUR, 蚀巢 HIVE SPIRE) doubles the amount of text.

**Cause:** - /Users/minimax/m/mecha-city/game/ui/hud_palette.gd:7 loads a single font, NotoSansSC-Regular.
- hud_palette.gd:21 sets TEXT_DIM to 0.55 alpha; :28 sets SIZE_TINY to 14.
- hud_palette.gd:150-161: draw_text defaults to no shadow and no outline.
- Most widgets never turn the outline on: objective_bar.gd:25/27/35, reticle.gd:121/137, radar.gd:83/86/88, hp_bar.gd:79/81, od_ring.gd:71.
- hot_slot.gd:114-119 skips draw_text altogether and calls draw_string directly in TEXT_DIM.
- The brief only required captures in the dark sandbox (/Users/minimax/m/mecha-city/briefs/hud.md:58-60), and none were judged in the dusk city.

**Fix:** 1. Make draw_text outline by default (3 px INK at 0.9). Turn it off only for text inside opaque panels.
2. TEXT_DIM alpha 0.55→0.8.
3. Add NotoSansSC-Medium for labels, and a condensed Latin face with fixed-width digits for numbers such as ammo, distances and armour: Barlow Condensed SemiBold or Rajdhani SemiBold (both OFL).
4. One language per label, chosen by a Settings locale. Keep bilingual text only in menus and the tutorial.
5. Route the hot_slot key letters through draw_text.
6. Put a 4 px INK backing strip at 0.5 behind the armour segments.

Visual target: AC6 and DXM condensed semibold numerals with a dark edge, legible over sun and sky.

## Nothing ever fades back: every widget is at 100% all the time, so nothing reads as urgent  (impact 7, ~2 h)

**In the picture:** All at full strength in one frame:
- eight bright skill hexes, all saying 'ready'
- an OD ring at 0%
- a full EN arc and an empty HEAT arc
- a full armour bar reading '10000 / 10000'
- the radar, the compass and the objective

The eye has nowhere to land. The truly urgent items, the unblockable tell and the empty gun, are just two more elements in the noise.

**Cause:** /Users/minimax/m/mecha-city/game/ui/hud.gd has no layer that decides what matters most, and no per-widget alpha. Each widget only sets `visible = data.alive() and data.has(key)`: /Users/minimax/m/mecha-city/game/ui/widgets/hotbar.gd:64, hp_bar.gd:35, weapon_panel.gd:25, od_ring.gd:22, radar.gd:29, compass.gd:24, objective_bar.gd:19.

**Fix:** 1. Give each widget a rest alpha in hud.gd and drive its `modulate.a` with a 0.25 s tween.
2. A widget whose value has not changed for 3 s, and is not urgent, drops to its rest alpha: hotbar 0.45, OD 0.3, radar 0.55, armour 0.6 while above 60%, compass 0.7, style meter hidden at rank D.
3. Any change (cooldown ready, hit taken, ammo spent) or urgency (low, empty, overheat, energy outage) pops the widget back to 1.0 for 2 s.

Visual target: Titanfall 2 (ref image 06): only the target plate and the reticle are bright; the abilities at bottom left are small and muted until needed.

## Enemy plates: five on screen, overlapping each other and the chrome, shown through walls, anchored at the feet  (impact 9, ~3 h)

**In the picture:** Five plates:
- Harrier (125-290, 205-243), under the objective text.
- HIVE SPIRE (622-790, 410-450), cut by the EN arc.
- Two 'Ripper' plates (1100-1367, 733-783) overlapping; the second covers the first one's '78 m'.
- A third Ripper (720-885, 872-912), inside the OD ring, with 'OD 0%' printed over its name.

The plates for the street-level Rippers float near the creatures' feet on the lower street, not above the creatures.

**Cause:** - /Users/minimax/m/mecha-city/game/ui/widgets/enemy_plates.gd:11 allows up to 6 plates (MAX_PLATES).
- enemy_plates.gd:26-37 fills them with the nearest enemies, whatever their relevance.
- enemy_plates.gd:42-59 (`_push`) does no overlap, line-of-sight or safe-zone test.
- enemy_plates.gd:69 anchors unlocked enemies at their root, 44 px up. :75 fills each box at 0.62.
- /Users/minimax/m/mecha-city/game/ui/hud_data.gd:183-193 (`_scan_world`) collects every enemy within 300 m with no line-of-sight check.
- /Users/minimax/m/mecha-city/game/ui/hud.gd:11 versus :16-28: plates are drawn under all the chrome, so chrome text prints over them.
- /Users/minimax/m/mecha-city/status/hud.md:134-136 already lists the overlap and edge clipping as known issues.

**Fix:** 1. A full plate (150x30: name, HP, stability, pips) only for the hard target, the soft target and elites (juggernaut, boss, spire). Maximum 3.
2. Other enemies in view get a 6 px hostile chevron plus a 60x3 px HP sliver, shown only for 3 s after they take damage.
3. Unlocked plates require line of sight, via has_line_of_sight in /Users/minimax/m/mecha-city/game/player/aim/target_query.gd:45.
4. Add screen exclusion rects: compass strip_rect, the objective block, the radar disc, the hp bar_rect, the weapon panel_rect, the hotbar/OD block, and a 70 px disc around the reticle. A plate that hits one flips below its target or is dropped.
5. When two plates overlap, drop the lower-priority one.
6. Keep plates inside a safe rect inset 5% from the screen edges.
7. Distance fade: scale 1.0→0.75 and alpha 1.0→0.6 between 60 m and 250 m.
8. Anchor plates at the top of the enemy's bounding box or at its lock point, not at the root.
9. Add a test in ui/tests that places 6 enemies on chrome positions and asserts that no plate overlaps the chrome or another plate.
10. Add city frames (captures/e2e_c_a1_fight, e2e_d_spire0_pods) to the HUD acceptance set.

Visual target: Titanfall 2 (ref image 06): one name plus a bar over the locked enemy, and nothing else floating.

## Chrome that looks like programmer art: navy translucent boxes turn to taupe mud on the warm sky, and corner brackets sit on everything  (impact 6, ~2 h)

**In the picture:** The compass strip (490-1110, 98-148) is a flat grey-brown band (measured luminance 0.21 against a sky of 0.54). The plates and the weapon panel are the same muddy rectangles, each with four cyan corner ticks. Against the orange dusk the HUD reads as debug overlays, not designed chrome. Its only shape language is 'rectangle plus brackets'.

**Cause:** - /Users/minimax/m/mecha-city/game/ui/hud_palette.gd:18-19: the cool navy INK #0b1220 at 0.55 alpha turns grey-brown over a warm sky.
- hud_palette.gd:85-96: brackets are used as the frame for everything.
- /Users/minimax/m/mecha-city/game/ui/widgets/compass.gd:57: panel at 0.4.
- /Users/minimax/m/mecha-city/game/ui/widgets/enemy_plates.gd:75-76: box at 0.62 plus brackets.
- /Users/minimax/m/mecha-city/game/ui/widgets/weapon_panel.gd:55-56: panel plus brackets.

**Fix:** 1. Compass: no fill; only a 1 px rule, ticks and outlined labels.
2. Plates: no box; a 2 px top rule in the target's colour, an outlined name and the bars.
3. Weapon and armour: one panel shape with a 6 px 45° cut on the outer corner and a horizontal gradient from INK 0.6 to 0. No brackets.
4. Keep brackets only on the lock box, so a bracket always means 'locked'.

Visual target: AC6 (ref image 01), where nothing is a filled box and everything is 1-3 px lines and outlined numerals. Or GB4's corner chrome, where panels are deliberate framed shapes.

## The twin-arc hotbar and the OD ring wall off the bottom centre, right where the enemies are  (impact 7, ~2.5 h)

**In the picture:** Eight 48 px cyan hexes in two arcs (540-1060, 745-905) and a dark, empty OD ring (755-845, 837-927) sit on the street in front of the mech, where the Rippers are walking. One Ripper's plate is trapped inside the ring. All eight hexes say 'ready' in full cyan, and the key letters under them cannot be read.

**Cause:** - /Users/minimax/m/mecha-city/game/ui/widgets/hotbar.gd:7-10 places the slots on a 330 px arc centred 130 px below the screen, at angles 224-316°. The slot centres span x 563-1037, y 705-801 in layout coordinates. Placement code at :47-53.
- /Users/minimax/m/mecha-city/game/ui/widgets/hot_slot.gd:7 sets R 24. :51-58 draws a ready slot with a full CYAN frame. :66-67 fills the hex at 0.5 and draws the icon at alpha 1.0.
- /Users/minimax/m/mecha-city/game/ui/widgets/od_ring.gd:6-9 puts a 45 px ring 82 px above the bottom edge. :46 draws a dark track at 0.8 alpha when the ring is at 0%.
- od_ring.gd:64-65 also has a duplicated `return` (dead code).
- The layout follows /Users/minimax/m/mecha-city/ref/research/skills-catalog.md §4.9, so the lead must sign off on changing it.

**Fix:** 1. Move the slots into two corner clusters: the left four as a 2x2 hex cluster just above the armour bar (x 56-190, y 730-830 in layout coordinates), the right four above the weapon panel.
2. Hexes 36 px.
3. A ready slot is an outline at 0.55 alpha. Bright fill only for 1.2 s after it becomes ready, and while the skill is active.
4. Key letter 14 px medium weight, outlined, inside the bottom of the hex.
5. OD becomes a 30 px ring at the left end of the weapon panel, at 0.3 alpha below 100%, pulsing only when full.
6. Delete the dead `return` at od_ring.gd:65.

Visual target: GB4 (ref image 19), with skill hexes tucked into the bottom corners, and Titanfall 2 (ref image 06), with three small ability icons at bottom left. The bottom centre stays clear for the world.
