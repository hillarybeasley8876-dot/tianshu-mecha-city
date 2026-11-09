# hud — lead notes (read at every session start)
- Accessibility (critic #12): never colour-only — parryable = white glint DIAMOND icon, unblockable = red TRIANGLE
  with "!" + sound cue, weak point = violet RING; hit markers differ by shape (normal ×, weak ◇, kill ✕ bold).
  Honour Settings `damage_numbers`, `photosensitive`, `hold_to_toggle`; add a reduce-motion note in settings.
- Vertical wayfinding: the compass shows objective height (▲ +128 m / ▼ −40 m) and the radar shades enemies by layer.
- Blocked-shot cue: when the aim ray hits world geometry < 30 m from the muzzle, dim the reticle + show a small
  barrier icon.
- New pad layout (SPEC §3): RB is a shift layer; glyph prompts and the controls screen must show "RB + X" etc.
- (r2 PASS 22:58) Polish queue: re-capture in free-play sandbox after flow's fix; compass marker label outline.
- (audio r2) Credits screen: read `game/audio/audio_manifest.csv` + CREDITS_AUDIO.md, show every pack/track and
  the AI-content labels (Tripo models, MiniMax voice) — ACCEPTANCE §5.
- (flow r1) **Tutorial prompt API** (CONTRACTS §6): `prompt(id, action = &"", line = "")` +
  `dismiss_prompt(id)`; the built-in tutorial must not run on its own any more — show only what the flow asks
  for (free-play sandbox shows nothing). Extend the table with look, boost, jump, hover, missiles, skills.
- (flow r2) `HudData.enemies` is not pruned between its 0.1 s scans → `radar.gd:36` / `enemy_plates.gd:35`
  error on a monster freed inside the window (~8 per run): skip `is_instance_valid() == false` entries at use
  and prune on scan. `menu_root` accumulates its own scaled run time → read the flow's unscaled `stats["time"]`.
- (boss r1) Boss bar from the boss's `hud_state()` (group `&"boss"`: name, hp, hp_max, phase, cores[]); title
  card on `Events.boss_intro(title, subtitle)` (big centred bilingual card, 2.5 s, photosensitive-safe).
