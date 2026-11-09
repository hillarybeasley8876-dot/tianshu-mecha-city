# Brief: melee-defense — Dawn Edge saber (曦刃) combos, lunge, charged slash, air combo, executions;
# Mirror Guard (镜返盾): perfect parry, block, catch field

## Goal
Close combat that feels like the best action games: snappy 3-hit saber string with cancels, a homing
lunge from 24–80 m, a charged overhead slash that throws a crescent wave, an aerial string, the Return Cut
riposte after a perfect parry, cinematic Core Rend executions on staggered enemies — and defence that is
offence-shaped: a 167 ms perfect parry, a held block, and a catch field that grabs projectiles and throws
them back. Every hit lands with local hit-stop, sparks, sound and a camera kick (FEEL.md).

## Read first
`docs/CONTRACTS.md` (§4–6, PlayerMech/AimSystem/HeroModel APIs, hud_state), `docs/SPEC.md` §3–§6,
`docs/FEEL.md` (melee_*, lunge_hit, charge_slash, finisher, parry_perfect, block, catch_release, jackpot),
`ref/research/skills-catalog.md` §4.3 (move table: startup/active/recovery frames, cancel windows, damage,
impact, reach — reach ×2 for our 16 m hero), §4.4 S5 Mirror Guard, §4.6 stagger + Core Rend + JACKPOT,
§4.7 synergies, `ref/research/juice-impact.md` §2 (local hit-stop rules), §5 (finishers), §7 (reactions).
Existing code: `game/player/**` (PlayerMech, camera rig, aim), `game/enemies/enemy_base.gd`
(`is_executable`, `execute_hit`, StatusComponent), `game/fx/**` (FeelDirector, VFX library).

## You own
`game/combat/melee/**` (`melee_system.tscn` component + scripts + tests), `game/combat/defense/**`
(`defense_system.tscn` component + scripts + tests).

## Build
1. **MeleeSystem**: input buffer 6 f; L1→L2→L3 per the §4.3 table (frames at 60 fps = ×2 physics ticks),
   cancel windows into dash/guard/skills; hit detection = ShapeCast3D boxes swept along the blade arc
   each active tick (reach 18–20 m, arcs per table), multi-hit prevention per swing; step-in 6 m on L1;
   lunge when hard-locked at 24–80 m (`player.lunge_to`, 110 m/s, homing 120°/s, 140 EN); charged slash
   (hold ≥ 30 f: 1,500 dmg + crescent wave 90 m long at 140 m/s, 24 m wide); air L1–L2 with 0.3 s
   hover-hang; Return Cut within 0.8 s after a perfect parry; Ram Kick during assault boost (mech-move
   exposes the state; you deal the hit); combo scaling handled by enemies' StatusComponent.
   Saber visual: blade from the model's `saber_r` socket (14 m long, white core #EFFFFF, cyan glow
   #4FE6FF, additive), swing trail ribbon mesh (fades in 0.12 s), sparks on contact via VFX library.
2. **Executions (Core Rend)**: melee on a staggered enemy within 14 m and ±60° (`enemy.is_executable`)
   → invulnerable cinematic: `camera_rig.request_cinematic` 2–3 shots (TPS), model `execution` action,
   enemy `execute_hit` (damage per §4.6, rupture blast 1,200 / 1,000 in 20 m), rewards (+300 EN, +8 % OD,
   +5 % HP), `Feel.play(&"finisher")`; durations 0.9 / 1.8 / 2.4 s by enemy class. JACKPOT rule per §4.6.
3. **DefenseSystem** (Mirror Guard): registers `player.add_damage_filter`. Tap guard = perfect window
   10 f (167 ms), shrinking to 5 f if re-pressed within 0.5 s of a release; minimum guard 18 f. Perfect vs
   melee (hit.parryable) → 0 dmg, attacker −600 stability + 0.6 s recoil, local hit-stop 8 f both,
   Return Cut window, +150 EN, +4 % OD, `Events.parry_success`; perfect vs projectile (meta reflectable) →
   reflect to source at 135 %. Held block: front 140°, −70 % dmg, 60 EN/s + 25 per 100 blocked, EN 0 →
   guard break 1.0 s stun. Hold ≥ 0.3 s = catch field: projectiles entering a 12 m frontal hemisphere
   freeze and orbit (≤ 24), max 3 s, 140 EN/s; release fires them back in a 20° cone at 135 %. Unblockable
   hits (hit.unblockable) ignore all of this. Visuals: shield hex panel (#4FE6FF), perfect ring
   white-gold, caught projectiles spinning in a disk.
4. `hud_state()` keys — melee: combo_step, charging (0..1), lunge_ready, execution_available, jackpot;
   defense: guarding, perfect_window, catch_count, guard_break.

## Done when
- `tools/godot.sh check --only=res://combat/melee/,res://combat/defense/` → 0 errors.
- `tools/godot.sh test res://combat/melee/tests/test_melee.gd`: frame timings of L1–L3 (startup/active/
  recovery at 120 Hz), cancel windows, reach/arc hits vs dummy hurtboxes, lunge range gate + EN, charged
  threshold + wave travel, execution trigger rules and invulnerability, combo buffer.
- `tools/godot.sh test res://combat/defense/tests/test_defense.gd`: perfect window 167 ms (and 83 ms when
  spammed), block reduction/angle, EN drain, guard break, reflect 135 %, catch ≤ 24 + release cone,
  unblockable bypass.
- Movie + captures `captures/melee_*.jpg`: full string on a Mantis (enemies unit) or a dummy, lunge from
  70 m, charged slash wave, aerial string, a perfect parry → Return Cut, a catch-and-release, an
  execution from the cinematic camera. Watch it: hits must read as heavy (hit-stop + sparks + kick).
