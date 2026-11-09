# Brief: skills — SkillSystem: Rift Step, Skyhook Anchor, Corona Fins + Ward (防护罩), Shockcore Burst,
# Undertow Well, Plunge Breaker, Zenith Overdrive → Zenith Lance

## Goal
Eight active abilities and the ultimate that make the kit rich and chain into payoffs: blink behind
targets, grapple/swing through the vertical city or yank enemies, six wing-blade drones that strike marked
targets or form a tetrahedral barrier, a 360° burst that deletes projectiles, a gravity well that primes
enemies for COLLAPSE detonations, an aerial slam, and a 12 s overdrive that ends in a city-splitting beam.

## Read first
`docs/CONTRACTS.md` (all), `docs/SPEC.md` §3, §6, `docs/FEEL.md` (rift_step, anchor_latch, fins_launch,
ward_hit, shockcore, collapse, plunge_land, overdrive_ignite, lance_fire), `ref/research/skills-catalog.md`
§4.4 S1, S2, S4, S6, S7, S8, §4.5, §4.6–4.7 (×2 for reach/radii/projectile speeds; times unchanged).
Existing code: `game/player/**`, `game/combat/**`, `game/enemies/**` (StatusComponent: marks, primed,
pull/slow hooks), `game/fx/**`. Anchor nodes: group `&"anchor_node"` (city places them; in the sandbox
spawn your own test anchors on the towers and the sky bridge).

## You own
`game/combat/skills/**` (`skill_system.tscn` component + one script per skill + tuning resources + tests).

## Build (numbers per §4.4/4.5, reach ×2)
1. **SkillSystem** component: input per action (rift_step, anchor, fins tap/hold, burst, well, melee-hold
   in air for plunge via the melee unit's hook or your own air check, overdrive hold 0.25 s / pad L3+R3),
   cooldowns/charges, EN costs, `Events.skill_used/skill_ready`, `hud_state()` keys per skill:
   `<id>_cd`, `<id>_cd_max`, `<id>_charges`, `<id>_ready`, `od` (0..100), `overdrive_active`,
   `overdrive_left`, `lance_ready`.
2. **Rift Step**: destinations per table (behind / flank / back-off 50 m; no lock 44 m along stick), 9 f
   intangible transit (collision off, visible streak), 6 f recovery, 0.45 s Ambush buff, decoy shell that
   attracts Rippers, free-space check (ShapeCast + 8-point fallback).
3. **Skyhook Anchor**: cable shot 360 m/s, range 120 m, 2 charges / 5 s; on surface: reel 60→92 m/s,
   swing if > 25° off-cable, jump = release + 12 m/s up; on light enemy: yank to 18 m + 0.6 s stun; on
   heavy: pull the player in, melee while reeling = Hook Kick; on staggered: straight into execution (call
   the melee unit's execution entry if present); cable can be cut (600 HP). Visual cable + latch sparks.
4. **Corona Fins**: the six wing blades (model sockets `wing_l`, `wing_r`; detach meshes or spawn copies
   while hiding the docked blades): tap sends 2 + 2×marks fins (marks from StatusComponent) at 150 m/s,
   station on an 18 m sphere around the target, 4 beams each 0.22 s apart (110 dmg), return after 2.4 s;
   hold 0.35 s = **Corona Ward**: 4 fins form a tetrahedral barrier around the hero absorbing 3,000
   projectile damage over 6 s (Layers.BARRIER, ripples on hit), other 2 auto-fire; separate CD 20 s.
5. **Shockcore Burst**: 18 f startup with super armour, 6 f active: radius 32 m (1,800 → 600 dmg),
   impact 1,400, knockback by class, deletes enemy projectiles in radius, detonates primes, LOS-gated.
6. **Undertow Well**: thrown arc 90 m/s, ≤ 100 m, arms on impact or 1.2 s: 3.5 s field radius 24 m,
   pull (via enemy hooks) / slow, primes for 5 s; detonators (burst, missiles, plunge, charged wave, rifle
   stage 2) trigger COLLAPSE (900 dmg / 700 impact in 20 m) — expose `detonate_primes(center, radius)`.
7. **Plunge Breaker**: in air ≥ 16 m above ground, hold melee 0.25 s: 10 f hang then 190 m/s dive,
   homes on a locked target below within 120 m; impact radius 20 m 1,600 → 500 (+10 % per 20 m fallen,
   cap +50 %), launches non-bosses into a 0.75 s air-lock; crater decal; CD 12 s.
8. **Zenith Overdrive → Lance**: needs OD 100 (PlayerMech OD); ignition 0.45 s super armour +
   `Feel.slow_mo(0.3, 0.25)`; 12 s buffs per §4.5 (CDs reset + tick 2.5×, EN regen ×3, dashes free, dmg
   +25 %, taken −30 %), afterimages (VFX library helper), model `set_overdrive(true)`; press again or at
   1 s left → **Lance**: 0.8 s charge (4 converging brackets via `Feel.post`) then a 3 s beam 16 m wide,
   800 m long, 10 ticks/s × 450 dmg, pierces and breaks props, rooted, turn ≤ 40°/s; 3 s aftermath.

## Done when
- `tools/godot.sh check --only=res://combat/skills/` → 0 errors.
- `tools/godot.sh test res://combat/skills/tests/test_skills.gd`: each skill's CD/charges/costs, Rift Step
  destinations + intangibility, anchor reel speeds/swing/release, fins count from marks + beam count +
  ward absorption cap, burst radius falloff + projectile deletion, well pull + prime + COLLAPSE, plunge
  height gate + damage bonus, overdrive gating at OD 100 + buff values + lance duration/ticks.
- Movie + captures `captures/skills_*.jpg` for every skill in the sandbox with enemies (or dummies):
  readable silhouettes of each effect at 100–300 m, the ward around the hero, the lance sweeping across
  the runway. Watch it and judge 爽感 honestly in your report.
