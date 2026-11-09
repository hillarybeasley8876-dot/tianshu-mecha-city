# flow — lead notes (read at every session start)
- (22:40, lead movie repro `--sandbox --skip-menu`) The drop-in placed the hero at the CITY's H0 (Godot
  −560, 400, 600) inside the sandbox, so it fell for 30 s through empty space until FALL_TIMEOUT. In the
  sandbox (or whenever the world has no H0 marker) drop in over the world's `PlayerSpawn` instead.
- `Audio.play(&"assault")` warns "unknown or empty sound id 'assault'": the manifest id is `assault_boost`
  (better: let Feel.play(&"assault_boost") carry the sound — FEEL rows own juice).
- New tool: `--nan-watch` on drive/movie prints any Node3D whose transform goes non-finite (first offender
  first). Run your scripted runs with it once.
- (22:55) **Contract change (CONTRACTS §2 flags)**: `--sandbox` is FREE PLAY for every other unit's tests —
  GameFlow stays idle there (no drop-in, no tutorial prompts, no test spires, no waves) unless `--flow` is
  also passed. Your own runs use `--sandbox --flow`. Today every unit's `--sandbox --skip-menu` capture gets
  your 40 s drop-in cinematic (HUD r2 captured a collapsed arm because of it) and your spires' waves on top of
  their own `--enemies=` setups. Make this the first thing you fix; add a test for it.
- (audit, 2026-11-02) Robustness findings for your files: reviews/flow-audit.md — fix them in this round after your current items (regression checks for the high ones).
- (04:10, PRIORITY) **Flow costs ~50 ms per frame in the city.** `tools/godot.sh perf --skip-menu --no-enemies
  --warm=20 --spawn=-514.5,112,105.1,-66.4` (vista V2): 15–17 fps with flow, **60 fps with `--stub=flow`**
  (boss/hud/art stubs change nothing; low quality and `--blockout` are just as slow). Find the per-frame cost
  (group scans, arena polygon tests, physics queries, `FlowWorld` re-reads — profile with
  `Performance.TIME_PROCESS` / `Time.get_ticks_usec` around your `_process`/`_physics_process` bodies), fix it
  (cache the world reads at boot, tick directors at ≤ 10 Hz), and add a check that flow's per-frame cost in the
  city stays < 1 ms.
- (10:30) The boss arena's catapult now arms only when the fight starts (`BossArena.armed`, lead fix) — remove the
  `park_boss_arena` workaround from `crown_gate.gd`. HudData's prune error is fixed (lead).
- Hives A2/A5 stand inside their arenas' structures (no firing position on any pod): layout r6 moves them
  (noted there). Keep `finish_spire` only as a debug fallback, never in the E2E pass criteria.
