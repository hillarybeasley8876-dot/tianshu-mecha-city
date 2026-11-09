# audio — lead notes (read at every session start)
- Sound id `telegraph_unblockable` (enemies emit it via Audio.play at every unblockable wind-up): a sharp rising
  metallic screech + low pulse, must cut through combat (UI/Voice-priority bus, never ducked).
- Read `hit.kind` / `hit.weapon` — HitInfo has no `source_kind`.
- Rifle hit ids are `beam_rifle` (normal), `rifle_stage1`, `rifle_stage2` (lead fix in rifle.gd): map
  `rifle_stage1 → rifle_hit` (heavier variant if you have one) and `rifle_stage2 → rifle_stage2_hit`; the current
  `beam_rifle_stage2` key in event_router.gd never matches.
- (enemies r3) `event_router.gd on_simple` is bound to a signal that carries arguments → arity errors at
  runtime (~12 per fight). Give every bound handler the signal's exact signature (or bind through a lambda
  that drops the args); extend the "every signal wired" test to check argument counts.
- (boss r1) Bind `Events.boss_intro` (stinger) — the "every signal wired" test will fail until you do. Boss ids
  the boss unit needs: titan_stomp, titan_swipe, titan_beam_inhale, titan_beam_loop, titan_core_break,
  titan_summon, titan_tail, titan_death_fall, storm_lightning (recorded layers where they exist).
