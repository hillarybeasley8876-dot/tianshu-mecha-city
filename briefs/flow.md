# Brief: flow — the demo from title to victory: drop-in, tutorial, encounters, hive spires, checkpoints

## Goal
Turn the systems into a 20–25 minute demo with a tension curve (SPEC §8, MAP §2): title → carrier drop-in →
tutorial skirmish at the Container Yard → open district with three Hive Spires defended by escalating
waves, roaming packs and Harrier patrols → the Ascension Catapult opens → boss (boss unit) → victory and
stats. Pacing per level-design dossier rule 6 (Insomniac): 5–6 mini-combats per arena, the next wave
starting halfway through the current one, spawns near each sub-space.

## Read first
`docs/SPEC.md` §8, `docs/MAP.md` §2, `ref/research/level-design-vertical.md` §4.5 (arenas, spawn sockets,
palettes) and §0 rule 6, `ref/research/juice-impact.md` §11 (tension: telegraphs, alarms, intensity
director), `docs/CONTRACTS.md` (Events, Game flags, world markers §7), the enemies spawner API,
city-art's TimeOfDay API (`set_progress`), audio's `Audio.music_intensity` / `stinger`, HUD hud_state keys.

## You own
`game/flow/**` (`game_flow.tscn` instanced by main, encounter director, hive spire objective, checkpoint/
respawn, drop-in and victory sequences, tutorial triggers), `data/encounters/**`.

## Build
1. **GameFlow** state machine: `title` (camera at vista V1, HUD title screen; skipped with `--skip-menu`)
   → `drop_in` (hero falls from 400 m over the canal with thrusters, cinematic camera via
   `camera_rig.request_cinematic`, lands at H0 = `land_heavy`, AI voice line) → `tutorial` (A1: contextual
   prompts per verb, 2 small ripper waves + 1 mantis) → `district` (3 spires open, objective "摧毁蚀巢 0/3")
   → `boss_gate` (S4 catapult unlocked, objective "登上天枢之冠", vista of the crown) → `boss` (hands over to
   the boss unit; listens to its events) → `victory` (slow-mo, orbit camera, HUD victory stats) or
   `game_over` → respawn at the last checkpoint (start, then each destroyed spire) with full HP/EN.
2. **EncounterDirector**: data-driven waves `data/encounters/<arena>.json` (trigger on entering the
   arena Area3D; waves = type counts + spawn sockets + start condition: on enter / at 50 % of the previous
   wave killed / timer), enemy budget ≤ 40 alive, roaming packs between arenas (1–2 packs of 4–6 rippers
   + a Harrier pair patrol on the skyrail), escalation per destroyed spire, music intensity per state
   (explore 0.2 → contact 0.5 → spire fight 0.8), `Events.encounter_started/cleared`.
3. **Hive Spire** objective (`flow/hive_spire.tscn`, group `&"hive_spire"`, uses the monster-assets hive model
   when present): 4 glowing pods × 3,500 HP (weak points, Hurtbox + Targetable each) + a 6,000 HP core exposed
   when all pods burst (SPEC §7.1); spawns rippers from its base every 12 s while alive (cap 8); infection creep intensity around it
   (city-art hook); destruction: chain explosions (Feel `kill_large`), collapse to the destroyed state,
   AI voice 「蚀巢已摧毁 n/3」, Titan roar on the skyline (boss unit hook), TimeOfDay progress += 1/3,
   checkpoint saved.
4. **Tutorial prompts**: drive the HUD's prompt API for move, look, dash, boost, jump/hover, shoot, lock,
   melee, guard, missiles, skills — each once, when first relevant; never block play.
5. Works in the sandbox too (`--sandbox`: put 3 test spires on the deck, the plateau and the trench) so you
   can test before the city lands.

## Notes from the lead
- Clocks (CONTRACTS §3): timers that pace waves/encounters use plain delta (world clock); UI/cinematic timing
  uses `Feel.real_now()`.
- Checkpoints per SPEC §7.1 (start, each destroyed hive, each boss phase).

## Done when
- `tools/godot.sh check --only=res://flow/` → 0 errors; `tools/godot.sh test res://flow/tests/test_flow.gd`
  (state transitions incl. respawn, wave start conditions, enemy budget, spire pods → core → destroyed,
  checkpoint save/restore, objective/events order).
- A scripted run (`--skip-menu --sandbox --god`) destroying the 3 sandbox spires with a drive timeline (or
  debug commands) reaches `boss_gate` with 0 errors; captures `captures/flow_*.jpg` (drop-in, tutorial
  prompt, wave fight, spire pods glowing, spire collapse, objective HUD, boss gate vista) + a movie.
