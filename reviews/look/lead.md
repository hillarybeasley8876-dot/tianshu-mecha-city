# Look diagnosis items for lead (lead-verified workflow wf_5e92d07a-bee, 2026-11-02)

Source: an independent critique of the user's screenshot `tmp/lead/user_shot_1.png` (A6 hive fight) against the key art.
Do them in this order (impact per hour). Each item: what is in the picture, the cause (file:line), the fix.

## The window says DEBUG: an editor debug run in a 1600x900 window with the macOS title bar, and F11 does nothing  (impact 6, ~0.5 h)

**In the picture:** The top 64 px of the shot is a white macOS title bar reading '天枢 TIANSHU — Mecha City (DEBUG)'. The game runs as a 1600x900 window, not fullscreen. Before anyone looks at the art, the frame announces itself as a dev build. This is the first reason the user asks whether it is final.

**Cause:** /Users/minimax/m/mecha-city/tools/godot.sh:81-82 'play' launches the editor binary with only `--path`, and Godot appends '(DEBUG)' to every debug run. /Users/minimax/m/mecha-city/game/project.godot:30-31 forces a 1600x900 window size and sets no window/size/mode, so even a release build opens windowed. /Users/minimax/m/mecha-city/game/core/input_setup.gd:43 binds toggle_fullscreen to F11, but no code anywhere handles it (grep finds only that line). The release export /Users/minimax/m/mecha-city/build/TIANSHU.app (built at 11:15) exists, but it is not what the user ran.

**Fix:** 1. Only ever show people the release .app (built with `tools/godot.sh export`), never `tools/godot.sh play`.
2. Add `window/size/mode=3` (fullscreen) to project.godot. The capture and test commands already pass `--windowed --resolution 1600x900` (godot.sh:58-79), so captures keep working.
3. Add a 6-line F11 handler in core that toggles DisplayServer between WINDOWED and FULLSCREEN.
4. Let `play` accept `--fullscreen`.

Visual target: the first frame is game edge to edge, with no OS title bar and no DEBUG text, like any shipped AC6 or GB4 capture.
