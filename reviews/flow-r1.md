# flow — review r1 (lead) — FAIL (state machine, spires and encounters solid; export + world wiring open)

Verified: `check` 25 files 0 errors; `test_flow` 80/0 and `test_flow_idle` 8/0 (with their flags); the eight
captures and `flow_demo.mp4`. The whole loop works in the sandbox: drop-in → tutorial fight → spires with pods →
core → chained collapse → boss gate, checkpoints and respawn, the 40-enemy budget, roaming packs from behind.
The free-play rule landed with its own test. Good work.

## MUST-FIX
1. **Nothing outside `res://` at runtime.** `encounter_waves.gd`, `encounter_director.gd` and `flow_world.gd`
   open `../data/...` through `globalize_path`; an exported .app has no such files (ACCEPTANCE §5). Move the
   encounter tables to `game/flow/encounters/*.json` (you own them there; delete `data/encounters/`) and read
   them via `res://`. `FlowWorld` must read the WORLD, not the Blender source JSON: hive sites = group
   `&"hive_site"`, arenas = group `&"arena"` Area3Ds (`arena_id`, real shapes → fixes your AABB issue), spawn
   zones = `&"spawn_zone"`, start = `PlayerSpawn` (CONTRACTS §7; city-build is building exactly these now).
   Until the city lands the full flow runs only in `--sandbox --flow`. (FeelTable reading docs/ is test-only:
   fine.)
2. **`Events.spire_destroyed(spire, destroyed, total)`** now exists (core) — emit it; the boss's skyline walker
   roars on it.
3. **Tutorial prompts through the HUD API** (CONTRACTS §6 "Tutorial prompts", hud implements it next round):
   `Game.hud.prompt(id)` / `dismiss_prompt(id)` for every verb in brief §4, each once when first relevant;
   guard with `has_method` until the HUD lands it. Nothing on the objective line except objectives.
4. **Pods on the model's bulbs**: the pods sit at the trunk's base; place them on the hive model's glowing
   bulbs (its `weak_*` / pod sockets — ask monster-assets in your status if a socket is missing).
5. **Spire collapse beat**: in t51 the chained blasts engulf the camera. Make the fall a 1.5–2 s cinematic in the
   duel frame (hero → spire): a wide shot from ~90 m where the spire topples and the blasts chain up the trunk,
   then control returns; the hero gets a blast push outward if within 30 m. It should feel like the reward.

The `slash_1` error is routed to monster-assets. Boss hand-over: the boss unit is starting; keep the wiring.
