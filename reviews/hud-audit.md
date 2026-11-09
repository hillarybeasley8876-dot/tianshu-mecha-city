# hud — numeric-robustness audit (lead, 2026-11-02) — 7 verified findings

A 36-agent audit read every non-test script twice (non-finite math; clocks + integrators) and a skeptic
tried to refute each finding; these survived. Fix them all (the proposed fixes were checked by the
skeptic — where it corrected one, the correction is what is written under *fix*). Add a regression check
for each high one in your suite, keep every suite green, run one scripted fight with `--nan-watch`, commit,
and report per finding: fixed (how) / not reproducible (evidence).

Clock contract reminder (CONTRACTS §3): Feel.real_delta/real_now for input, camera, UI/post and rate
limits; Feel.player_delta for player timers/anims; plain delta for world VFX; NEVER the wall clock
(movie capture renders a frame in ~70 ms of wall time). Feel now divides _process deltas by the
frame's own scale, so Feel.real_delta(delta) is correct in _process too.

## 1. [high] game/ui/hud_data.gd:196 (other)
**What**: HudData.project() returns Camera3D.unproject_position() in root-canvas pixels (1920x1080 under the project's canvas_items stretch), but enemy plates, the hard-lock diamond, telegraph icons, weak-point rings and damage numbers draw that value inside hud.gd's _root, which is scaled by k = 1.2 x hud_scale, so every world-anchored readout lands at k times its true screen position.

**Trigger**: Normal third-person play at the default hud_scale 1.0 (k = 1.2). In captures/huddbg_t3_3.jpg a Mantis at about window (340, 650) has its 'Mantis' plate drawn on top of the ARMOUR bar and its PARRY glint diamond below its feet instead of 74 px above it. Targets with canvas x > 1600/hud_scale or y > 900/hud_scale still pass project()'s canvas-space 'visible' test but are drawn off-screen. That same 'visible' flag suppresses the markers.gd off-screen threat arrow, so an unblockable windup in the right or bottom sixth of the view (the right 40% at hud_scale 1.4) gets no cue at all.

**Fix**: The proposed fix is correct: publish k from hud.gd::_apply_scale, return pos = p / k and keep 'visible' in canvas space. p / k also maps correctly into the canopy layout (1280/glass_k = 1920/k). Default the published scale to 1.0 so harness and test runs without hud.gd are unchanged.

**Skeptic's check**: Godot's Camera3D::unproject_position scales by get_viewport().get_visible_rect().size. With canvas_items stretch and a 1920x1080 base (game/project.godot:28-33) that size is 1920x1080, and hud_data.gd:196-200 returns the point unconverted. enemy_plates.gd:67, markers.gd:79, telegraphs.gd:96/107 and damage_numbers.gd:59 draw it inside _root, which is scaled by k = view.y/900*hud_scale (hud.gd:105,114), so every readout lands at k*p. captures/huddbg_t3_3.jpg matches this exactly: the Mantis feet are at window ~(335,735), and the plate sits at y~797-838 over the ARMOUR readout. Because markers.gd:111 drops the threat arrow whenever the canvas-space 'visible' flag is true, a target with canvas x > 1600/hud_scale gets an icon drawn off-screen and no arrow.

## 2. [medium] game/core/feel.gd:131 (clock)
**What**: Outside game/ui, found while checking the HUD fix: real_delta() and player_time_comp() divide by the CURRENT Engine.time_scale, but Feel writes the new scale in its own _process (priority -1000). So for every _process caller later in the same frame, the delta was scaled by the previous scale, and on hit-stop edges the result is wrong by up to 20x (50x at MIN_SCALE).

**Trigger**: First frame of every global hit-stop (Feel.hit_stop(s, 0.05) from kill_small, kill_large, hurt_heavy and boss_stagger): a _process caller gets 1/60 / 0.05 = 0.333 s (0.83 s at MIN_SCALE) instead of 0.0167 s, and 0.0008 s on the frame the hit-stop ends. Verified with a scratch probe on Godot 4.7.2 with --fixed-fps 60. On the transition frame it printed `delta=0.01667 time_scale_now=0.05 real_delta()=0.3333`, while Feel.real_now() differences stayed at 0.0167 s every frame. _physics_process callers stayed consistent, so camera_rig.gd:206 is unaffected. Witch-time player_delta in _process sees the same effect, e.g. 0.1 s when a hit-stop lands during witch time. Any UI timer written as 'use Feel.real_delta(delta)' inside _process gains about 0.32 s per hit-stop. An explicit spring in _process would take a 0.33 s Euler step, which is the camera_shake NaN bug class.

**Fix**: The proposed fix works. Simpler option: expose the clamped real_dt that Feel already computes at feel.gd:151 (e.g. Feel.frame_real_delta()) and switch the _process callers to it.

**Skeptic's check**: Godot 4.7.2 Main::iteration reads time_scale once (main.cpp:4936) and passes process_step*time_scale to every _process (main.cpp:5062). Feel writes Engine.time_scale inside its own _process (feel.gd:164). So any _process caller that runs after Feel takes a delta scaled by the old value and divides it by the new one (feel.gd:131): 0.333 s on the first frame of a global hit-stop and 0.0008 s on its last. Physics callers stay consistent. Current _process callers are only world art (time_of_day.gd:70, infection_field.gd:82, storm_crown.gd:86, prop_scatter.gd:114), which get bounded one-frame jumps. game/ui never calls real_delta, and this is core-owned code outside the hud area.

## 3. [medium] game/ui/widgets/hud_widget.gd:27 (clock)
**What**: HudWidget._process passes the time-scaled delta to every widget's update_hud. As a result, every HUD lifetime, pop, flash and blink freezes in global hit-stops and slows down in slow-mo and witch time, instead of running on the unscaled UI clock that Feel's contract requires.

**Trigger**: Every perfect dodge (witch slow-mo 0.3 for 0.35 s): the PERFECT callout pop (callouts.gd:44/73, POP_TIME 0.16) takes about 0.3 s, and the callout lives about 1.07 s instead of 0.9 s. Every execution window (JACKPOT slow-mo 0.2 for 0.5 s, execution_director.gd:396): the pop is about 2.8x slower and the callout lives about 1.2 s. A kill_large (0.1 s hit-stop plus 0.35 s slow-mo) holds the 0.25 s kill marker (hit_marker.gd:67-68) for about 0.45 s. Damage numbers (damage_numbers.gd:66) spawned in a slow-mo stay up about 1.3 to 2x longer while the real-time camera keeps moving, so these screen-fixed numbers slide off their targets. The same happens to the hp_bar flash/shake (hp_bar.gd:34), the low_hp heartbeat (low_hp.gd:25-31), the style_meter decay, 1.5 s combo reset and rank pop (style_meter.gd:85-90), the hotbar ready flash (hotbar.gd:69 -> hot_slot.gd:36), the od_ring/enemy_plates/reticle blinks and the tutorial LIFE.

**Fix**: The proposed fix is right: in the base class use the clamped Feel.real_now() difference (0..0.1 s), and let telegraphs/markers opt back into world delta. Its warning against Feel.real_delta(delta) in _process is also correct.

**Skeptic's check**: hud_widget.gd:27 passes the scaled _process delta to every update_hud, but feel.gd:17 puts UI timing on the unscaled clock. Example: perfect_dodge (fx/events/perfect_dodge.tres: 0.3x for 0.35 s, eased 0.05/0.2 through feel_director.gd:175) stretches the callouts.gd LIFE of 0.9 s to ~1.06 s real time and the 0.16 s pop to ~0.32 s. kill_large (GLOBAL 0.1 s at 0.05, then 0.35x for 0.35 s) holds hit_marker.gd's 0.25 s kill marker for ~0.45 s.

## 4. [medium] game/ui/widgets/weapon_panel.gd:63 (clock)
**What**: The reload/swap 'busy' sweep is driven by the wall clock (Time.get_ticks_msec) instead of the game clock.

**Trigger**: Reload or switch weapons while Movie Maker is recording, which takes about 70 ms of wall time per 1/60 s game frame. The sweep advances about 0.063 of its 1.1 s cycle per captured frame instead of 0.015, so it runs about 4x fast and strobes across the track. It also jumps after shader-compile hitches and makes the fixed-fps HUD shots non-deterministic.

**Fix**: The proposed fix is correct: fmod(Feel.real_now() * 0.9, 1.0) keeps the same 1.11 s period.

**Skeptic's check**: weapon_panel.gd:63 drives the RELOADING/SWITCHING sweep from Time.get_ticks_msec, i.e. a visual on the wall clock, which the contract forbids. tools/godot.sh movie records with --write-movie --fixed-fps 60. audio/tests/timeline_reel.json (captured as captures/audio_reel.avi with the HUD present) taps reload and weapon_next, so the sweep runs ~4x fast in an existing capture.

## 5. [low] game/ui/cockpit/glass_hud.gd:180 (clock)
**What**: The canopy parallax divides a real-time camera yaw step (the rig turns on Feel.real_delta) by the time-scaled _process delta. In hit-stop the turn rate is overestimated 50x (3.3x in witch time), so the quad pins to +/-PARALLAX_MAX, while the delta*8 settle lerp and the _up_t handover timer crawl at the scaled rate.

**Trigger**: First-person cockpit view, the player turns the camera during a hit-stop (time_scale 0.02) or witch time (0.3): rate = dyaw_real / (delta * time_scale). The maxf(delta, 0.0001) guard does not bite because 1/60 * 0.02 = 3.3e-4. The value stays bounded by the clamp, so the effect is visible lag and drift, not NaN.

**Fix**: Do not use Feel.real_delta(delta) here. Inside _process it returns 0.333 s on the first frame of every global hit-stop (finding 3), so the proposed settle weight 1-exp(-8*0.333) = 0.93 would snap the quad toward a rate underestimated 20x. Use a real frame delta instead: var now := Feel.real_now(); var dt := clampf(now - _last_real, 0.0, 0.1); _last_real = now. Re-seed _last_real (and _yaw_prev) in set_active. Then use _up_t += dt, rate = dyaw / maxf(dt, 0.0001), and settle weight 1.0 - exp(-8.0 * dt).

**Skeptic's check**: glass_hud.gd:180 divides the per-frame yaw step by the scaled _process delta, but the camera turns on real time (camera_rig.gd:210, Feel.real_delta). In a global hit-stop (HITSTOP_SCALE 0.05, feel_director.gd:23/138) the rate comes out 20x too high, and 3.3x in witch time. Meanwhile the delta*8 settle (line 183) and _up_t (line 177) advance on scaled time. The clamp at line 182 keeps the result bounded, so this is low-severity drift and lag, not NaN.

## 6. [low] game/ui/menus/menu_root.gd:311 (clock)
**What**: The run TIME on the victory page adds up the time-scaled delta, so every global hit-stop and slow-mo is under-counted.

**Trigger**: Normal combat. Each kill_small (0.04 s at 0.05), kill_large (0.1 s plus 0.35 s at 0.35), hurt_heavy, boss_stagger, perfect dodge (0.3), jackpot (0.2 for 0.5 s), finisher and 0.8 s Zenith Lance charge (0.3) removes (1 - scale) of its duration from stats.time. Over a full run, 用时 TIME is short by tens of seconds.

**Fix**: The proposed fix is correct: menu_root is PROCESS_MODE_ALWAYS, so track _last_real every frame and add minf(Feel.real_now() - _last_real, 0.1) only while page == NONE.

**Skeptic's check**: menu_root.gd:311 adds the scaled _process delta, so every global hit-stop (0.05) and slow-mo (perfect_dodge 0.3, kill_large 0.35, jackpot 0.2 for 0.5 s at execution_director.gd:396) removes (1-scale) of its real duration from the TIME shown on the victory page (_stat_text, line 342). Low severity.

## 7. [low] game/ui/menus/menu_screen.gd:154 (clock)
**What**: The title screen's PRESS ANY KEY pulse is driven by the wall clock (Time.get_ticks_msec).

**Trigger**: A Movie Maker capture of the title, at about 70 ms of wall time per 1/60 s game frame: the 2.1 s pulse runs about 4x fast. It also jumps after hitches.

**Fix**: The proposed fix is correct: sin(Feel.real_now() * 3.0). Feel is PROCESS_MODE_ALWAYS, so it advances on the title and pause pages.

**Skeptic's check**: menu_screen.gd:154 drives the PRESS ANY KEY pulse from Time.get_ticks_msec, a visual on the wall clock. A Movie Maker run without --skip-menu/--sandbox shows the title (menu_root.gd:98), and autoplay.gd cannot dismiss it (it injects only actions and mouse motion, not key events), so the 2.1 s pulse runs ~4x fast in a trailer-style capture. Cosmetic only, and current movie runs pass --sandbox/--skip-menu.
