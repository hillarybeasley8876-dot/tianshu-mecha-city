# enemies — review r1 (lead) — FAIL (behaviour strong; integration + core hooks open)

Verified myself: check 44 files clean; test_status 83/0 PASS; test_ai + test_spawner rerun with a 280 s
timeout (the machine is at load 12–14 from 8 workers — the default test timeout is now 300 s in core).
Captures reviewed: telegraph language (white glint parryable, red unblockable, amber stagger), packs,
wrecks all read. Placeholders are fine — monster-assets will deliver the Tripo models with your API.
Core changes for you: `main.tscn` now instances `res://enemies/spawner.tscn` (part "enemies", stub-able);
`Events.enemy_telegraph(enemy, attack, kind)` exists (kind: parryable / unblockable / ranged).

## MUST-FIX
1. Emit `Events.enemy_telegraph` at every telegraph start (HUD threat arrows + audio cues depend on it);
   keep your local signal if useful internally.
2. **Real fight integration** in `main.tscn --sandbox` with the real PlayerMech + camera rig (both exist):
   `--enemies=ripper:8,mantis:2,spitter:2,harrier:2,juggernaut:1` and a drive timeline where the player
   runs, dashes through a ripper leap (must trigger perfect dodge), takes a mantis combo, jumps a
   juggernaut shockwave, and dies or survives. Verify through PlayerMech telemetry + Events that damage,
   perfect dodge, knockback and death all happen via the player's pipeline; 0 engine errors; 6 captures
   `captures/enemies_fight_*.jpg` + movie.
3. **Spawner in main**: `--enemies=` and `--no-enemies` must work from main.tscn (test it with
   `tools/godot.sh run res://main.tscn 20 --sandbox --enemies=ripper:6`), and spawns must avoid the
   player's 150 m bubble and appear on navmesh in the city later (use the world's `nav_map(class)` when
   `Game.world.has_method(&"nav_map")`, else the default map).
4. **Agent classes**: rippers/harriers small (r 1.5 m), mantis/spitter medium (r 4 m), juggernaut large
   (r 9 m) — use the class maps when the city provides them (CONTRACTS §7), fall back gracefully.
5. **Test runtime**: test_ai must finish < 150 s wall on a loaded machine (reduce simulated seconds or
   monsters, or assert progress milestones earlier); print the wall time.

## SHOULD
- Ripper placeholder legs: give them thickness (2 segments) so the pack reads until real models land.
- Weapons asked for the charged-weapon ids eligible for ×1.8: use `hit.weapon in [&"rifle_stage1",
  &"rifle_stage2", &"charge_slash", &"zenith_lance"]` + `hit.kind == MELEE`; agree names with weapons via
  status files.
