# Brief: weapons — WeaponSystem: Pierce-Light rifle, Thunder Spindle gatling, Hailstorm missiles

## Goal
Shooting feels precise and powerful at mech scale: crisp hitscan beams with a two-stage charge, a
spinning gatling with heat and a skill-based active vent, and a 12-lock missile swarm that blooms and
curves (Itano circus). Shots read clearly at 600 m and never cost frame rate.

## Read first
`docs/CONTRACTS.md` (all; §5 PlayerMech/AimSystem/HeroModel APIs, hud_state), `docs/SPEC.md` §3, §6,
`ref/research/skills-catalog.md` §4.2 (P1, P2), §4.4 S3 Hailstorm, §4.7–4.11 (synergies, feel, Godot
notes) — remember S = 2 for distances/speeds, `docs/FEEL.md` (rifle_*, gatling_*, missile_* rows),
`game/core/**`.

## You own
`game/combat/weapons/**` (`weapon_system.tscn` component + scripts + tuning resources + tests),
`game/combat/projectiles/**` (pooled projectile + missile managers, beam/tracer visuals).

## Build
1. **WeaponSystem** (component under PlayerMech): owns the two primaries and the Hailstorm launcher;
   swap with `weapon_next/prev` (0.35 s swap, `Events.weapon_switched`), reload (`reload` or empty);
   fires from the model's `muzzle_r` socket toward `aim().aim_dir_from(muzzle)`; calls
   `player.set_strafe_aim(true)` while firing/ADS (and false 0.6 s after); plays model actions
   (`fire_r`, `charge_r`, `gatling_spin`, `reload`, `missile_launch`).
2. **P1 Pierce-Light rifle**: numbers per skills-catalog P1 (ranges ×2: full 280 m, falloff to 60 % at
   440 m, cut-off 600 m), 9-round cell, charge stages at 0.6 s / 1.2 s (pierce 1 / pierce all + 8 m
   blast), auto-fire at 3 s; marks: each hit calls the enemy StatusComponent (`add_mark_hit()` — agree
   the method name with the enemies unit via status files; until then call `hit.receiver.call_deferred`
   only if it has the method). Beam visual: 0.06 s cylinder (core #EFFFFF, glow #36E2FF) + muzzle ring,
   pooled; impact via `VfxLibrary.spawn` (fx unit) if present, else your own minimal spark.
3. **P2 gatling**: spin-up 0.3 s, 15 rounds/s, projectiles 900 m/s with ray-stepped motion (pooled,
   MultiMesh tracers every 3rd round), spread + bloom, heat 0–100 (+0.85/shot, cool 30/s after 0.35 s),
   overheat → active vent needle (0.9 s sweep, perfect 6 f / good 12 f / miss 3.2 s jam;
   Superheated rounds +30 % dmg +50 % impact for 4 s), shell casings ejected (cheap MultiMesh).
4. **S3 Hailstorm**: hold `missiles` to paint (lock box 24°×16° around the crosshair via
   `aim().targets_in_view`, one lock per 0.10 s, max 12, max 4 per target, range 320 m, LOS), release to
   fire 12 in 0.5 s from `missile_l/missile_r`; bloom 0.2 s at 44 m/s random ±35° cone then ignite to
   120→200 m/s in 0.4 s, turn 300→600°/s, proximity fuse 5 m, 6 s life, 280 dmg / 140 impact / 6 m
   blast; no locks → 6 missiles at the aim point; hold `aim` after release = guided to the crosshair;
   spore-chaff (group `&"chaff"`) absorbs 4 missiles; CD 14 s; `Events.missiles_locked`. One
   MissileManager simulates all missiles (arrays) and renders bodies with MultiMesh + GPU trails.
5. **Shots**: build `HitInfo` (kinds BEAM/BALLISTIC/EXPLOSIVE, impact as stagger), query
   `Layers.MASK_PLAYER_ATTACK`, `Hurtbox.apply`, `Events.hit_landed`, `Feel.play` rows, world decals via
   the fx library; `Events.weapon_fired` for enemy hearing.
6. `hud_state()` keys: weapon, ammo, ammo_max, reloading, charge (0..1), charge_stage, heat, overheated,
   vent_needle (0..1), vent_mark (0..1), superheated, missile_cd, missile_locks, missile_locks_max.

## Done when
- `tools/godot.sh check --only=res://combat/weapons/,res://combat/projectiles/` → 0 errors.
- `tools/godot.sh test res://combat/weapons/tests/test_weapons.gd`: fire rates, damage + falloff at 100 /
  300 / 500 m, charge stage timings and costs (rounds + EN), pierce counts, heat/overheat/vent windows
  (perfect/good/miss), missile lock rate/max/per-target cap, guided mode, chaff absorption — against
  dummy hurtboxes in the sandbox; 600 live projectiles + 24 missiles cost < 4 ms physics per frame.
- Captures `captures/weapons_*.jpg` + a movie: rifle volley at 300 m targets, stage-2 charged shot,
  gatling stream with tracers and casings, overheat vent UI-less (show needle state in a debug label),
  missile bloom + curving trails onto 12 painted targets. Look at them: beams must read at distance.
