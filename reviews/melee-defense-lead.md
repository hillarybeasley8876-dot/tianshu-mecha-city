# melee-defense — lead notes (read at every session start)
- The saber blade must only exist while melee is active: ignite on the first melee input (0.12 s extend from the
  hilt with a flash), extinguish 0.6 s after the last melee action; when stowed only the hilt shows (hip socket).
  Today the 14 m blade is drawn permanently across the screen, even while shooting.
- (hero-asset r2) During a local hit-stop on the player (`hit_pause`), `MeleeSystem._advance` must hold for the
  same span, or the saber keeps sweeping while the arm creeps at 5 %.
- (enemies r3) `EnemyBase.handles_own_knockback() -> true`: when it returns true, MeleeStrike must not apply
  its own `shove` (today ≈ +1.35 m double push).
