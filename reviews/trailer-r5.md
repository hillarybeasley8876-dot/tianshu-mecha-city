# trailer r5 — lead brief: re-record the showcase reel and trailer v2 on today's build (the user OK'd the screen)

## Why
Since the 11-06 renders that sit on the user's Desktop, every demo-visible fix has landed headless and
been accepted. None of it is on video yet:
- hero-v3 r9: the hero's feet planted, no 7.4 m float, a real gait with lean and arm swing, the
  plumes on the nozzles;
- hero-v3 r10: the plumes read as jets;
- mech-move r8: no float on kerbs;
- monster-assets r5/r6: skins that do not tear, no sinking or floating, a flash that brightens;
- melee-defense r7: the Mirror Guard is a cyan energy shield;
- weapons r6: no orange slabs in first person;
- feel r5/r5b: skate sparks, afterimages, a victim-only freeze;
- flow r5b: the hive collapse films;
- enemies r11/r12, hud r6.

The user just said "现在全部跑，我离开电脑": they are away and the screen is ours.

## Rules
- Prefix every windowed command with `MC_WINDOW_OK=1`. ONE Godot window at a time, strictly
  sequential.
- You are the only worker. Render from the live tree at HEAD; nobody else is editing it. Write the HEAD
  hash in status.
- Never use git stash. Commit only under `game/trailer/**` and `tools/trailer/**` (yours), and
  `status/trailer.md`.

## Do (in this order)
1. **The showcase reel first.** It is what the user asked for: "打怪 技能展示 机制展示". Re-record every
   take of `game/trailer/showcase.json` with `--force`, re-cut it to
   `captures/trailer/TIANSHU_showcase.mp4`, and rebuild the segment sheet.
   - **The hive segment (m6):** flow r5b fixed the collapse camera, so the collapse should now film in
     the un-stubbed flow. Include it if it reads.
   - **Segments that were short (4–5 s):** lengthen to 6–8 s where the action allows.
   - **The jump and melee segments that sat under bridge trusses:** move the camera to clear sky if
     your kit can.
2. **Then trailer v2.** Re-record `game/trailer/shots.json` with `--force` and re-cut to
   `captures/trailer/TIANSHU_trailer_v2.mp4`.
3. **For each reel:**
   - the framing report;
   - ffprobe, loudness, 0 black and 0 frozen frames;
   - a 2 s sheet and a per-segment sheet;
   - in the r5 section of `status/trailer.md`, an honest list of what still reads badly, with
     timestamps. The lead routes those.

## Gates
Every take `errors=0`; the framing report 0 failed (relaxed for the movement segments as in r3); the
loudness targets; both mp4s; the sheets.
