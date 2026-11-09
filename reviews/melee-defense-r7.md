# melee-defense r7 — lead brief: the Mirror Guard must read as an energy shield, not a mint-green tile

## Why
The showcase reel the user asked for (`~/Desktop/天枢_实机演示_打怪技能机制.mp4`, segments m2_mantis and
g6_guard; sheet `captures/trailer/sheets/TIANSHU_showcase_segments.jpg`) shows the Mirror Guard (镜返盾)
as **a flat, opaque, mint-green hexagon about 12 m across with a hard edge**. It covers the hero and
the enemy it is blocking. It reads as a placeholder tile, not as the game's signature defence. The
catch field (hold ≥ 0.3 s) is a big green dome with the same flat look.

## House rules (the user's machine)
You are the ONLY worker. `tools/godot.sh shot|run|drive|movie|perf` refuse without the lead's
`MC_WINDOW_OK`. Do the work and its numeric checks headless, and list the exact capture commands under
**"Captures needed"** in your status. The lead runs them when the user OKs the screen. Never use git
stash; commit with explicit paths.

## Do
1. **The block shield** (`game/combat/defense/shield_visual.gd`, and a shader of yours if needed):
   - **Visibility:** mostly transparent in the centre, so the hero and the target stay visible behind
     it, with a bright fresnel rim and a subtle hex cell pattern. The hard silhouette edge becomes a
     soft glowing rim.
   - **Colour:** the hero's cyan accent (the cyan of `hero3_shell` seams), not mint green.
   - **Form:** sized to cover the hero's front, not 12 m of the screen; slightly curved, not a flat
     plane.
   - **Reactions:** a block ripples from the impact point (pass the hit position); a perfect parry
     flashes bright and shatters into a short burst of hex shards.
   - **Coming and going:** it fades in over about 0.08 s and out over about 0.15 s.
2. **The catch field** (`catch_field.gd`): the same language as a dome. It is translucent with a
   visible rim, and caught rounds orbit visibly inside it. Make it distinct from the block shield, for
   example with a slow rotation of the hex pattern.
3. **Headless checks**, in your tests:
   - the materials build without errors;
   - alpha at the centre is ≤ 0.25 and the rim reaches ≥ 0.8;
   - the ripple parameter animates from the hit point and decays to 0 within 0.5 s;
   - the parry burst spawns and frees its shards within 1 s;
   - no new SCRIPT or SHADER ERROR in `test_defense`.
4. **Captures needed:**
   - a still from 3/4 front and side while blocking a mantis strike;
   - a perfect parry, at 3 frames;
   - the catch field holding rounds;
   - each beside the current look. Give the exact commands (`tools/godot.sh shot`/`drive`, with flags).

## Gates
- `test_defense` and `test_melee` pass, plus your new checks; `check --only=res://combat/` is clean.
- `status/melee-defense.md` gets an r7 section with the numbers and the Captures needed list.
