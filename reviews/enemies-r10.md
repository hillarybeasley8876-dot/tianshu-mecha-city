# enemies — round 10 (lead) — two small requests from monster-assets r4

1. **The juggernaut's roar never plays.** `game/enemies/juggernaut/juggernaut.gd:59` calls `set_locomotion(&"roar")`
   every windup tick; no locomotion table answers `roar`, so it resolves to idle. The clip exists (2.75 s, monster-assets
   status Requests 2). Call `play_action(&"roar")` ONCE on entering the windup (not every tick: a one-shot restarted
   each frame never advances), keep `decelerate` + `face_dir`, and make sure the charge's telegraph timing still
   matches the windup length (if the roar is longer than the windup, start it so its peak lands on the charge start,
   or trim the playback; do not retime the attack). Test: the juggernaut charge windup plays `roar` exactly once and
   the model state reports it.
2. **Dying monsters scaled to exactly zero** (melee-defense Requests 3): if anything in `game/enemies/**` scales a dying
   monster's model node to (0,0,0), `--nan-watch` reports a singular basis. Use an epsilon (0.001) or hide the node.
   If it is in `monster_model.gd` (monster-assets' file), tell them instead and do not edit it.
Evidence: the unit tests green, one `fight_probe` with `--nan-watch` showing 0 reports and the roar in the model trace.
Commit with an explicit path list; update status/enemies.md.
