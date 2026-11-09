# city-art r16b — lead dispatch: finish r16 (items 1–4, 7, 8) — golden hour, the hatch, the HDRI, tod 1.0

Your r16 brief (`reviews/city-art-r16.md`) stands. Items 5 and 6 landed in r16 (1f2dd83, 6d905c6,
9435912), and item 9 plus the static index landed in r16a. Do the rest now: **1** (golden hour must
stay golden), **2** (the diagonal hatch), **3** (the HDRI plates at blend 0: use them or remove them),
**4** (the `--tod=1.0` emissive budget), **7** (fold the post rows back, so `test_post` checks what
ships) and **8** (`test_occlusion`'s stale premise and the infinitely tall core).

## Why now
The user is away and has OK'd the screen: "现在全部跑，我离开电脑". Your colour work needs rendered
measurements, so this is the window.

The user's own reels on the Desktop (`天枢_预告片_v2.mp4`, `天枢_实机演示_打怪技能机制.mp4`, re-recorded on
11-09) show the frame as a violet-mauve dusk at the combat todays. The key art
(`art/concept/keyart/v1_pier`, `v2_canyon`, `v3_oldtown`) is golden: warm sunlit faces and a gold
horizon.

## Rules for this round
- Prefix every windowed command with `MC_WINDOW_OK=1`. ONE Godot window at a time.
- You are the only worker.
- Never use git stash. Commit with explicit paths.
- Re-bake the settle cache only if a settle input changes; it should not.

## Gates
Unchanged from the r16 brief, plus:
- the r15 clip gate and colour table on every frame at tod 0, 0.5, 0.6 and 1.0, with the misses
  stated with causes, and V1–V3 not missing;
- side-by-sides r15 | r16b | key art for V1, V2, V3 and V8, and for the trailer's s02 and s04 cameras;
- `tools/suites.sh --only=<world/art rows>,post` is green, with `art_occlusion` green (no longer
  KNOWN) after item 8;
- the frame budget at `cams_budget5`: ≤ +1.0 ms.
