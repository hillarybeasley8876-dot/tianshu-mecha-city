# audio — numeric-robustness audit (lead, 2026-11-02) — 5 verified findings

A 36-agent audit read every non-test script twice (non-finite math; clocks + integrators) and a skeptic
tried to refute each finding; these survived. Fix them all (the proposed fixes were checked by the
skeptic — where it corrected one, the correction is what is written under *fix*). Add a regression check
for each high one in your suite, keep every suite green, run one scripted fight with `--nan-watch`, commit,
and report per finding: fixed (how) / not reproducible (evidence).

Clock contract reminder (CONTRACTS §3): Feel.real_delta/real_now for input, camera, UI/post and rate
limits; Feel.player_delta for player timers/anims; plain delta for world VFX; NEVER the wall clock
(movie capture renders a frame in ~70 ms of wall time). Feel now divides _process deltas by the
frame's own scale, so Feel.real_delta(delta) is correct in _process too.

## 1. [high] game/audio/event_router.gd:210 (clock)
**What**: The gatling loop's lifetime is inferred from a 250 ms wall-clock gap since the last weapon_fired (`_gatling_last_shot_ms`, line 137). The gatling itself fires on Feel.player_delta, a different clock.

**Trigger**: Movie capture: at 15 rps a shot comes every 4 captured frames, about 280 ms of wall time, which is over 250 ms. So after every round the loop stops and spin_down + tail play, then spin_up and a loop restart follow on the next round 67 ms later. Live play: a kill_large (global 100 ms hit-stop + 0.35x slow-mo) stretches one shot gap to about 275 ms of real time, which releases the loop mid-burst.

**Fix**: Count the gap on the weapon's own clock in _physics_process: `_gatling_idle += Feel.player_delta(delta)`, reset it in on_weapon_fired, and release at GATLING_RELEASE_S. The router is PROCESS_MODE_ALWAYS, so a pause still releases the loop.

**Skeptic's check**: The router releases the loop after 250 ms of wall time with no weapon_fired (event_router.gd:137, 207-215), but the gatling fires every 8 physics ticks of Feel.player_delta (gatling.gd:142, weapon_system.gd:110). In a 60 fps capture the 4th frame's shot lands in physics before that frame's _process runs, so the release check sees 3 frames of wall time. Captures slower than about 20% of real time (83 ms per frame, as tmp/enemies/movie.log shows) therefore release and re-spin the loop between rounds. The live kill_large claim does not hold: with the director's 0.05/0.2 slow-mo eases (feel_director.gd:175), the longest gap is about 0.24 s.

## 2. [high] game/audio/voice_pool.gd:111 (clock)
**What**: Per-event min_interval_ms rate limits are measured on the wall clock: `_last_played_ms` and `started_ms` (lines 167-168, 184-185) and the steal-age `now` (241, 257).

**Trigger**: Movie capture (~70 ms of wall time per frame). Every interval of 70 ms or less disappears, and 200 ms becomes ~3 frames. gatling_fire_accent (meant for every 3rd round at 15 rps) can fire on every round. alarm_warning drops from 2.5 s to ~0.6 s and voice lines from 8 s to ~1.9 s. Steal ages are inflated about 4x. buses.gd's MASTER_TRIM_DB was calibrated by measuring a busy capture, so it may have been tuned on this too-dense mix.

**Fix**: As proposed.

**Skeptic's check**: budget_ok (voice_pool.gd:110-111), _last_played_ms (:168, :185) and the steal ages (:241, :257) all use Time.get_ticks_msec(). In --write-movie captures (18-83 ms of wall time per game frame, per tmp/*/movie*.log), gatling_fire_accent's 200 ms interval (table_weapons.gd:25-26) passes on every 66.7 ms round. Sub-frame intervals disappear, and the 8 s voice and 2.5 s alarm limits shrink 1.1-5×, so captures are denser than live play.

## 3. [high] game/audio/voice_queue.gd:52 (clock)
**What**: The cockpit AI queue's busy window (`_busy_until_ms`) and its 8 s repeat guard run on Time.get_ticks_msec(), the wall clock.

**Trigger**: tools/godot.sh movie (--write-movie --fixed-fps 60): each 1/60 s frame takes ~70 ms of wall time, and audio is recorded on game time. A 1.2 s line counts as finished after 1.32 s of wall time, which is about 19 captured frames (~0.31 s of audio), so the next queued line plays over it. REPEAT_GUARD_S (8 s) shrinks to ~1.9 s of footage. Fixed-fps tests that run faster than real time get the opposite effect.

**Fix**: As proposed: use Feel.real_now() in float seconds. Better still, end the busy window when the pool reports the polyphonic voice id stopped (is_stream_playing), which is right both live and in captures.

**Skeptic's check**: voice_queue.gd:27-56 runs the busy window and the 8 s repeat guard on Time.get_ticks_msec(), but Movie Maker records audio on game time. The project's own captures run at 20-92% of real-time speed (tmp/enemies/movie.log 20%, movie2 67%, mech-move_movie 80%), i.e. 18-83 ms of wall time per 1/60 s frame. So a 1.2 s line counts as finished after 0.3-1.1 s of footage, the next line overlaps it, and the repeat guard shrinks by the same factor.

## 4. [medium] game/audio/music_director.gd:198 (clock)
**What**: The 2 s global stinger rate limit uses Time.get_ticks_msec(). Stingers bypass the voice pool, so this is their only limit.

**Trigger**: Movie capture: the 2 s gap becomes ~0.48 s of footage, so stinger_stagger (sent on every stagger), stinger_kill_large and the boss-phase stingers stack on top of each other.

**Fix**: As proposed.

**Skeptic's check**: stinger() gates on Time.get_ticks_msec() (music_director.gd:197-205). Stingers bypass the voice pool: _play_stinger makes its own AudioStreamPlayer (:213-220), so the bank's 2000 ms row (table_world.gd:41) never applies. In captures, the 2 s gap shrinks to 0.4-1.8 s of footage, so stagger, kill_large and boss-phase stingers stack.

## 5. [low] game/audio/music_director.gd:193 (clock)
**What**: switch_to() restarts the metronome (the stinger beat clock) at the moment of the request. The interactive stream only changes clip at the next bar or beat (and plays a tension filler before boss), so after the first intensity change stingers are lined up to the wrong beat grid.

**Trigger**: The first explore->combat switch, when combat heat crosses 0.45. The metronome restarts mid-bar at the combat BPM while explore keeps playing until its next beat, and combat then enters at TRANSITION_TO_TIME_SAME_POSITION. Every later stinger() waits seconds_to_next_beat() on that unrelated grid and lands off-beat.

**Fix**: Polling get_current_clip_index() catches the real change (Godot updates playback_current when the destination starts mixing). But restarting the metronome at 0 is only right for TO_TIME_START transitions. For the SAME_POSITION ones, either start the metronome at the carried source position (tracked by the director, since the interactive playback reports position 0), or switch explore↔combat to TO_TIME_START.

**Skeptic's check**: switch_to restarts the metronome at request time (music_director.gd:184-193). Godot's interactive stream only queues the switch: the destination starts after the next beat or bar, and for SAME_POSITION transitions (explore↔combat, and the any→any default at :133-135) it seeks to the source position plus that wait. The music's beat grid therefore sits at an arbitrary phase relative to the metronome, and every quantised stinger after the first switch lands off-beat.
