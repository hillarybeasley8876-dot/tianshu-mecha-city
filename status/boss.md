# boss status

## Scope
`game/enemies/boss/**` — Brood Titan (skyline walker + 3-phase crown fight), the Crown arena, the
boss director that owns intro/phase/death beats, arena hazards, tests.

## Done

### 2026-11-05 — flow r5 items 3 and 4 (flow's ownership exception, boss unit idle)

Flow was granted `game/enemies/boss/**` for this round for the death/respawn/restore/summon code.
Every change is in commit `5129b4c`; the flow side of item 4 is `FlowProgress.respawn`.

**Item 3 — the titan's own summon flings it 68–134 m in one tick (blocker).** Not the restore: the
`AddSpawner` was the titan's CHILD (`brood_titan.gd` `on_spawned`) and `EnemySpawner.spawn()` calls
`add_child()` on a new add *before* it sets that add's transform, so every new add was created at the
titan's feet, became its floor for one step, and Jolt then handed the titan the adds' ring-point
motion as platform velocity. Four changes:

| file | change |
|---|---|
| `brood_titan.gd` | `_attach_spawner()` puts the `AddSpawner` under the titan's PARENT, never under the titan |
| `brood_titan.gd` | `platform_floor_layers = WORLD \| PROPS` — it still collides with adds, it just cannot stand on one |
| `boss_combat.gd` | `_deck_point` → `_clear_of_the_titan`: the bearing steps round the deck until the spawn point is 45 m clear of the 18 m body. The rim fraction 0.88 is r 132, exactly where `_stay_on_the_deck` clamps the beast, so the old point was under its feet |
| `brood_titan.gd` | `_stay_on_the_deck` splits into `_clamp_radius` (unchanged) and `_clamp_height` (new): 20 m below / 40 m above the probed deck under it puts the beast back on `ring_point(0.25, 0.72)`. It is skipped while `_ai_enabled` is off, so the intro climb from under the rim still works. `clamp_moves` counts the corrections so a test's per-tick tracker can tell a deliberate teleport from a fling |

`restore_for_checkpoint` also places the titan on a deck ring point and no longer resets `hp_max` to
`BossTuning.HP_MAX`, so a scripted run's `--boss-hp-scale` survives a death.

**Item 4 — one respawn path (major).** `BossDirector` no longer connects `Events.player_died` at all.
It used to teleport the hero 127–179 m to `_respawn_at`, heal it to full, grant i-frames and
re-enable the fight under the MECH DESTROYED page, then RETRY moved it again. The restore is now
`BossDirector.restore_for_phase(phase)`, the duck-typed hook `FlowProgress.respawn` calls (lead r16
decision 4 — no new `Events` signal): the titan at `phase_start_hp(N)`, cores whole, **adds freed**
(`_spawner.clear()`), on a deck ring point, and the deck with the rim that phase runs on —
`arena.restore_segments()` then `arena.break_segments()` for N ≥ 2, so phases 2/3 no longer resume on
a phase-1 deck.

**Tests.** `tests/suite_boss_deck.gd` (new) is the per-tick tracker the gate asks for: a control
window, 20 forced `titan_summon`s with the adds cleared between them, and 8 s after a restore.
`tests/test_boss_city.gd`'s checkpoint block is rewritten around the two halves of item 4.

```
DECKTRACK control (no summon): worst single tick 0.14 m, 0 clamp corrections
DECKTRACK 20 summons: worst single tick 0.13 m, 0 clamp corrections, titan at y 16.0 (deck 16.0)
DECKTRACK 8 s after the restore: worst single tick 0.81 m, 0 clamp corrections, titan at y 16.0 (deck 8.0)
BOSS TEST 135 checks, 0 failed
```
On HEAD the same suite reads `control 87.94 m`, `20 summons 96.64 m`, the titan ending at `y 140.6`
with the deck at 8 — 5 checks fail. `test_boss_city.gd` fails 4 on HEAD (`death.no_move` 29.3 m,
`death.no_heal` 10000 HP, `death.no_restore`, `checkpoint.hook`) and is 20 checks 0 failed after.

**Still open for the boss unit:** `status/flow.md` request 5 — `skill_system.gd:182` calls `is_alive()`
on a `BossCore`, which has no such method, so every core hit prints an error.

### r2 (lead review) — what changed this session
1. **Free play stays free** (CONTRACTS §2): the director only spawns the `SkylineWalker` when the run
   is not a plain `--sandbox`, or `--flow` / `--boss-test` asked for it. `BossDirector.walker_wanted()`
   is the rule without the command line, so the suite checks it. One boot line
   (`BOSS skyline walker: on the ring / off (free play)`) answers it for every capture and smoke run.
2. **Death beat rebuilt** — `boss_collapse.gd` (new, 135 lines) owns it: six `kill_large` blasts walk
   UP the standing body over 1.5 s, the corpse turns outward, tips 88° about its feet, slides over the
   rim and drops; a dust ring + debris + a borrowed smoke column come out of the rim where it crossed.
   No dissolve. Three bugs the captures caught on the way:
   - the corpse stayed pure white for the whole victory beat — `EnemyBase` stops ticking `visuals`
     when an actor dies, so the killing blow's hit flash and the telegraph tint never decayed. The
     collapse ticks them now, and a checkpoint calls `visuals.reset()`.
   - `kill_large` is a 28 m fireball; six of them at scale 1.4 whited out the entire 60 m body. 0.8.
   - at 26 m/s + 70 m the body cleared the rim in under 2 s and the camera filmed an empty deck; now
     17 m/s + 34 m over the full 3 s.
3. **`framing_height()` = 60** on `BroodTitan` (CONTRACTS §5 large-target framing, camera-aim's side
   has landed and reads it).
4. **`Events.boss_intro(BossTuning.DISPLAY_NAME, BossTuning.INTRO_SUBTITLE)`** at the intro roar, and
   the director listens to `Events.spire_destroyed` itself so the pre-fight walker roars on its own.
5. **Crown rim through the group**: my twelve wedges join `&"crown_rim_segment"` with an `angle_deg`
   meta; when the world exports its own (the city now does — 16 of them) the arena adopts them
   instead of drawing a second ring, and breaking one finds its `CollisionShape3D` by type.
   `BossArena.world_has_crown()` is the rule.
6. **The arena finds the Crown on the real map**: no `&"boss_arena"` node ships with the city, so the
   director locates the deck from the `spire` landmark marker and attaches a geometry-less arena for
   the rim + catapult. Below `CROWN_SEARCH_Y` (150 m) it does not even look, so free play is silent.
7. **The deck under it is probed, not assumed**: the city's Crown is not the `B1_crown` step table
   (probe at the titan's bearing: 226 / 234 / 241 / 248 m at radius 0.92 / 0.72 / 0.55 / 0.80), so
   `ring_point` / `floor_y_at` ray onto the real floor whenever the world owns the deck.
8. **The titan cannot walk off its own arena** — `_stay_on_the_deck()` clamps it inside
   `DECK_RADIUS - RADIUS`. The city test caught it 300 m out and 120 m below the deck.
9. **Legibility pass**: the showcase kites the hero at `KITE_TURN` (0.16 turns ≈ 100 m — inside every
   attack's `range_max`, off the Ø80 core's shadow), re-aims the rig at the titan each tick, waits out
   the intro before the first attack, and instances the feel director (without it the movie had no
   VFX at all). Three real bugs fell out of it:
   - cinematic shot `t` is a START time, not a length: the phase shot (`t = 2.6`) and the first death
     shot (`t = 1.6`) were never shown at all. All shots now start at 0.0.
   - the rig captures its hard target when a cinematic is requested; the boss had not locked the
     camera yet, so the duel frame collapsed to 10 m in front of the hero and the intro filmed an
     empty deck. The director locks it, and the intro shots are built from the live gap.
   - the intro put its camera on the deck, where the climbing titan is behind the rim. Both shots that
     matter are now outside the rim looking back at the Spire.

### Files (all under `game/enemies/boss/`)
| file | lines | what |
|---|---|---|
| `boss_tuning.gd` (`BossTuning`) | 277 | every number: pools, phases, core table, attack rows, arena, crown centre, the death beat. Nothing else invents a value. |
| `boss_body.gd` (`BossBody`) | 71 | capsule + body/head/legs hurtboxes + lock point + the three cores. |
| `boss_core.gd` (`BossCore`) | 160 | one weak core: own 8,000 pool, Hurtbox + violet Targetable + pulsing glow; ×2.5 to its pool, ×1.0 forwarded to the titan. |
| `boss_ring.gd` (`TitanRing`) | 122 | the stomp ring 0→80 m at 45 m/s. |
| `boss_beam.gd` (`TitanBeam`) | 159 | the 4 s sweeping beam: rotating volume, 0.25 s damage ticks, core-shadow blind spot. |
| `boss_lightning.gd` (`TitanLightning`) | 139 | phase-3 telegraphed circles → column strikes, through `&"time_of_day".lightning_at`. |
| `boss_combat.gd` (`BossCombat`) | 218 | per-phase attack table, telegraph/active/recover hooks, stomp spawn, rear-arc tail sweep, summon adds, storm. |
| `boss_brain.gd` (`BossBrain`) | 163 | `EnemyBrain` subclass: no attack tokens, no pack separation, direct steering, its own chain/rest rhythm. |
| `brood_titan.gd` (`BroodTitan`) | 395 | the actor: 150k pool, phases, armour, `framing_height()`, checkpoint restore. |
| `boss_collapse.gd` (`BossCollapse`) | 135 | the death beat: blast chain up the body, topple over the rim, dust + smoke out of the edge. |
| `boss_plate.gd` (`BossPlate`) | 47 | the CONTRACTS §6 `hud_state()` plate and its push. |
| `boss_arena.gd` (`BossArena`) | 341 | the Crown: ziggurat (own deck) or the city's, rim segment group, catapult, floor probe. |
| `skyline_walker.gd` (`SkylineWalker`) | 125 | the 90 m `titan_skyline` on the 820 m skyline ring, roars on demand, despawns for the fight. |
| `boss_director.gd` (`BossDirector`) | 359 | walker + arena + intro climb + phase cinematics + death beat + checkpoints + `--boss-test`. |
| `tests/` | 1160 | `test_boss.gd` (124 checks), `test_boss_city.gd` (13 checks on the real map), harness, three suites, showcase scene/script/cams/timeline, the `--flow` script. |

### Numbers (SPEC §7.1 + brief)
HP 150,000; phases at 65 %/30 % → 52.5k/52.5k/45k → 105/105/90 s at 50 % uptime of 1,000 DPS.
Stability 9,000, decay 8 %/s after 2.0 s, stagger 3.4 s, immunity 6 s. 3 cores × 8,000 (×1.0 main,
×2.5 core); break → stagger + attack removed (L→swipe, R→summon, chest→beam). Legs ×0.5, head ×0.6.
Core Rend = 12 % max HP, never lethal. Unblockables ≥ 0.85 s in every phase, parryables ≥ 0.50 s.

### Tuning choices (docs silent — PLAN.md requires listing them)
- Tail sweep is in all three phases (brief §3 lists it; §4's phase lists omit it — a positional punish
  that must always be live, or standing behind the titan is free).
- Attack damage vs PlayerMech's 10,000 pool: stomp 2,200 / swipe 1,800 / beam 900 per 0.25 s /
  tail 2,000 / lightning 1,600 — a fifth of the bar, every one telegraphed ≥ 0.8 s and dodgeable.
- Knockback 10–26 m/s: the arena is a 300 m disc with a 224 m drop.
- Summon adds 6 rippers + 2 harriers, cap 10 alive, cooldown 25 s.
- Skyline walker: 90 m model, 820 m ring, 14 m/s, 6 s roar stop.
- Death: 6 blasts over 1.5 s at scale 0.8, 88° topple, 17 m/s slide, 34 m drop, 14 s of edge smoke.

## In progress / next
Nothing outstanding. The city now ships its Crown, so `test_boss_city.gd` and the `--flow` run below
are the live integration checks; both pass.

## How to verify (exact commands)
```
tools/godot.sh check --only=res://enemies/boss/                    # 24 files, 0 errors, 0 warnings
tools/godot.sh test res://enemies/boss/tests/test_boss.gd          # 124 checks, 0 failed, PASS
tools/godot.sh test res://enemies/boss/tests/test_boss_city.gd     # 13 checks on the real city, PASS
tools/godot.sh movie --movie=$HOME/m/mecha-city/captures/boss_fight.avi \
    --scene=res://enemies/boss/tests/boss_showcase.tscn \
    --timeline=res://enemies/boss/tests/boss_showcase_timeline.json \
    --god --boss-world=sandbox --boss-at=0,140,0
tools/godot.sh drive --timeline=res://enemies/boss/tests/boss_city_timeline.json --skip-menu \
    --spawn=0,20,-40,180 --flow-script=res://enemies/boss/tests/boss_city_flow.json --god \
    --shots=20,30,38 --out=boss_flow
```
`--boss-world=sandbox|city` forces the stage; `--boss-at=x,y,z` moves the Crown; `--boss-beats=` runs
one beat. Note `tools/godot.sh run` does NOT forward extra flags — use `shot`/`drive`/`movie`.

## Evidence
- `captures/boss_fight.avi` — 62.6 s, 1600×900 @ 60 fps, 3,757 frames, 0 errors. Every beat logs
  `SHOWCASE beat <id> (titan <range> m away)` and `SHOWCASE attack <id> (<kind>)`: stomp, swipe,
  summon, tail, beam, lightning, both phases, two core breaks and the death collapse.
- `captures/boss_intro_roar.jpg` (the titan on the deck after the climb), `boss_stomp_telegraph.jpg`
  (red unblockable tell), `boss_stomp_ring.jpg` (hero + titan + the expanding ring — the scale shot),
  `boss_core_break.jpg` (the orange blast on the shoulder core), `boss_beam_sweep.jpg` (the violet
  beam from the mouth across the frame), `boss_phase3_storm.jpg` (phase-3 red + an add on the deck),
  `boss_death_collapse.jpg` (fire and debris as the body goes over the rim),
  `boss_arena_wide.jpg` (the Crown from outside).
- `captures/boss_flow_t20_0.jpg`, `_t30_0.jpg`, `_t38_0.jpg` — the full demo on the real city:
  the flow reaches `boss`, the HUD boss bar reads 巢母 BROOD TITAN / PHASE 1 with three phase
  segments, the objective line and the 3/3 HIVES counter are live, the radar shows the TITAN marker,
  and the hero is standing on the city's Crown inside the storm shell.
- City test log: `CITYTEST crown at 0,224,-120 (0 m from the layout centre), build_geometry=false`,
  deck probes at six bearings (233–234 m), and 20/20 checks including the two halves of the phase
  checkpoint: the death moves the hero 0.0 m and leaves it at hp 0, and `restore_for_phase(2)` brings
  the boss back at `phase_start_hp(2)` on a broken rim with 0 adds.
- 2026-11-05 (flow r5): `DECKTRACK` lines and the 135-check `BOSS TEST` above, plus
  `BOSS CITY TEST 20 checks, 0 failed`.
- Balance report printed by the test: `phase 1 52500 → 105 s / phase 2 52500 → 105 s /
  phase 3 45000 → 90 s`.

## Known issues
1. **The sandbox stage, not the city, is the capture stage.** `--boss-world=city` works (the flow run
   above is on it) but the fight there sits inside city-art's dusk fog and the Spire's tether column
   runs straight through the middle of the arena, so the stills are worse. The brief's §7 asks for the
   sandbox until the city crown exists; it now does, so the next pass should re-shoot on the city.
2. **The city's Crown profile is not `B1_crown`'s.** The step table in the layout does not match the
   built deck (probe: 226 / 234 / 241 / 248 m at radius 0.92 / 0.72 / 0.55 / 0.80 — the rise is not
   monotonic). I probe the real floor rather than guess, but the fight's geometry (cover, the beam's
   blind spot, the catapult landing) is only as good as that deck.
3. **The showcase teleports the hero** (`_face_the_titan` every 0.25 s) — there is no player at the
   pad. The titan itself is never faked: real brain, real telegraphs, real hazards; only the hero's
   damage and position are scripted, and every scripted hit goes through `take_hit`.
4. **The Ø80 core eats the gameplay camera** if the hero stands within ~90 m of it (the showcase keeps
   clear of that ring; a real player will not).
5. `EnemyBase.begin_telegraph` asks for `enemy_telegraph` / `telegraph_unblockable`, which the audio
   bank does not have; the warning is pre-existing (enemies + audio units).
6. The intro's three shots read, but the titan sits small in shots 1 and 3 — the duel frame's origin is
   the midpoint of a 240 m gap during the climb, so the framing is bounded by that.

## Requests (to the lead / other units)
1. **city-build / lead — the Crown deck profile.** The built deck at the Spire does not follow
   `B1_crown.rim_steps` (r150/r126/r104 rising 0/8/16): the probe finds 226 m at r=138, 248 m at
   r=120, 234 m at r=108 and 241 m at r=82. Either the layout or the geometry should move; until one
   does, every fight-space number I own (cover radius, the beam's core-shadow, the catapult landing)
   is fitted to a deck that is not the documented one.
2. **city-art** — the Spire's light tether rises through the middle of the Crown arena. It splits the
   frame in every gameplay shot from the centre of the deck.
3. **camera-aim** — the large-target framing works (the r2 captures are framed on it). One gap: the
   lock drops while the boss is climbing over the rim during the intro, and the rig then keeps the
   player's own pitch; the director works around it with `_lock_the_camera()` + a per-tick `set_look`
   in the capture driver only.
4. **hud** — `Events.boss_intro(title, subtitle)` is emitted at the intro roar with
   `"巢母 BROOD TITAN"` / `"CROWN DECK +224 — SPIRE OF THE HIVE"`. The boss bar itself is live (see the
   flow captures), so only the title card is outstanding.
5. **audio** — the boss uses existing ids (`titan_roar`, `titan_breath_beam`, `titan_step_far`,
   `boss_stagger`, `spire_destroyed`, `kill_large`, `kill_large_far`, `shockcore`, `anchor_latch`,
   `land_heavy`). Dedicated `boss_stomp`, `boss_core_break`, `boss_lightning`, `boss_death` and
   `boss_deck_break` ids would let those moments read as their own events.
6. **flow** — the boss director starts the fight on its own as soon as the player is on the Crown
   (height + radius, no trigger). During `boss_gate` that can pre-empt the gate cinematic; a
   `FlowGameFlow` signal for "the boss may start" would make the hand-off explicit.
7. **(2026-11-05, flow r5) city-build — the notch over the S4 pad.** flow's Ascension Catapult now
   routes its arc OUT past r 150 from the Spire axis before it rises (lead r16 decision 2), because
   the pad at S4 sits under the Crown deck. The outward leg runs along the S4 axis, which is exactly
   where Crown rib j=2 is; city-build r11's notch is what makes that leg clear. Until it lands, the
   arc's outward leg passes through the rib.
