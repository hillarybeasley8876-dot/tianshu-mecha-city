# trailer r6 — lead brief: re-record both reels on the golden-hour look (city-art r16b)

city-art r16b landed (00bd122 … b03fb3b):
- a real cloud sky (HDRI blend 0.5);
- a warm peach and gold horizon instead of the violet cast;
- no diagonal hatch;
- the tod 1.0 clip fixed.

hud r7 also landed: deaths play out. The user is still away and has OK'd the screen.

## Do
1. Re-run your `--tod` A/B per shot on the NEW sky (as in r1/r5) and update `shots.json` and
   `showcase.json` where a different time of day now reads better. Golden hour is the point.
2. Re-record and re-cut the showcase reel (`captures/trailer/TIANSHU_showcase.mp4`), then trailer v2
   (`captures/trailer/TIANSHU_trailer_v2.mp4`). Same gates as r5:
   - every take `errors=0`;
   - the framing report 0 failed;
   - −14 LUFS;
   - 0 black and 0 frozen frames;
   - the sheets.
3. While you are at it, fix the r5 "reads badly" items if your camera kit can:
   - the spitter's acid cloud covering a third of the frame;
   - the mech nearly out of frame in flight at 190 s;
   - the flat orange wall at 9–15 s of v2 (the drop and impact).

## Rules
- `MC_WINDOW_OK=1` on windowed commands, one window at a time.
- You are the only worker.
- Never use git stash.
- An r6 section in `status/trailer.md`.
