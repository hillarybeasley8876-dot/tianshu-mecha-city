# Juice, Impact (打击感 / 冲击力 / 顿帧 / 震屏) and Tension: Research Dossier v1

Project: mecha-city demo (Godot 4.7.2, Forward+, Metal, M1 Max). Research key: `juice-impact`. Date: 2026-11-01.
Audience: the lead designer (Claude Opus), who turns this into briefs for MiniMax-M78 implementers.

Conventions
- 1 f = 1 frame at 60 fps = 16.7 ms. "f" always means 60 fps frames unless stated.
- `[Sx]` = source; full URLs are listed in section 14. **(estimate)** marks my own recommendation or derivation. It is not a sourced fact.
- *Local hitstop* = only the attacker and the victim freeze. *Global hitstop* = the whole simulation slows (`Engine.time_scale`).
- *Trauma* ∈ [0,1]. *Shake* = trauma² (Eiserloh).
- Mech scale is a parameter. Numbers that depend on it are given relative to `MECH_H` (player mech height). The examples assume MECH_H ≈ 9 m (estimate; align with the movement dossier).
- Reference images: `/Users/minimax/m/mecha-city/ref/images/juice-impact/` (4 slides from Eiserloh GDC 2016).

---

## 0. The twelve rules (read this if nothing else)

1. **One data table drives all feel.** Every gameplay event calls `Feel.play(&"event_id", ctx)`. Durations, trauma, FOV, flashes, VFX, SFX and rumble live in `FeelEvent` resources. Tuning happens only there (estimate). The table in section 13 is v0 of that data.
2. **Hitstop is local by default.** Smash freezes only the objects involved in the hit, and particle effects keep running [S4]. Capcom gives projectiles no hitstop for the attacker [S7]. Dynasty Warriors-style crowd games use little hitstop because constant stops would freeze the game [S5]. Gunfire gets **no hitstop**. Melee gets local hitstop. Only kills, boss staggers, heavy hits taken and the ultimate get short *global* micro-freezes, and those are rate-limited (estimate).
3. **Hitstop is not a dead freeze.** Sakurai's eight Smash specs [S6]: the victim vibrates hard and the attacker vibrates slightly. The vibration is visual only, so hurtboxes stay still. Grounded targets vibrate horizontally; airborne ones vibrate on all axes. Amplitude decays across the stop. A per-attack coefficient scales strength. The hurt pose blends in over about 4 f. The attacker keeps creeping forward at sub-frame speed. Amplitude scales with camera distance.
4. **VFX and audio keep running during hitstop.** Smash particles are not frozen [S4]. Zenless Zone Zero keeps hit VFX at full speed while actors slow [S11]. In Godot, `Engine.time_scale` does not affect audio [S41].
5. **3D camera shake is rotational only.** Use Perlin/noise, not random values. Shake = trauma², and trauma decays linearly [S1]. Add a separate spring "kick" channel for recoil and directional hits, in the spirit of Vlambeer's camera kick [S2] and Juicy Breakout's spring shaker [S3].
6. **Escalation must be perceptible.** Because of the square, the same +0.2 trauma reads very differently at low and high stress [S1]. Reserve full trauma for boss staggers and the ultimate.
7. **Telegraph windup ≥ reaction time + dodge trigger time + buffer** [S32]. Use 250 ms as the reaction baseline (Human Benchmark median: 273 ms [S33]).
8. **Finishers are short.** Doom cut glory kills from about 3 s in the animatic down to 30–60 frames, and it hands control back before the victim's death animation ends [S14].
9. **Layer every impact sound:** transient, body, sub/LFE, mechanical, tail [S25]. Duck the world, not the kill-confirm. Players notice when the hitmarker changes [S27].
10. **Rumble is two motors, not a speaker.** Strong = low frequency, weak = high frequency [S39, S47]. Mix envelopes in your own autoload. Always ship a slider [S48].
11. **Permanence sells violence.** Leave wrecks, scorch marks and shells behind [S2], within decal and light budgets (Godot clusters cap at 512 elements per view [S51]).
12. **Aim for "high" juice, not "extreme".** In Kao's study, *none* and *extreme* both lowered play time and player experience [S35]. Ship per-effect sliders as Halo Infinite, Cyberpunk and Minecraft do [S36, S38]. Keep full-screen flashes ≤ 3 per second per WCAG [S37].

---

## 1. Architecture: the FeelDirector in Godot 4.7 (estimate)

```
Autoload "Feel" (Node, process_mode = PROCESS_MODE_ALWAYS)
 ├─ TimeFX        global micro-freeze + slow-mo curves (Engine.time_scale)
 ├─ CameraFX      trauma shake, kick spring, FOV punch (talks to CameraRig)
 ├─ ScreenFX      one CanvasLayer(layer 50) > ColorRect full-rect post shader
 ├─ VFXPool       pre-instanced GPUParticles3D one-shots + Decal ring buffer + flash OmniLight3D pool
 ├─ AudioFX       bus routing, ducking, AudioStreamRandomizer players, intensity → music
 ├─ Haptics       envelope mixer → Input.start_joy_vibration
 └─ HUDFX         hit markers, kill confirms, damage numbers, style meter
Data: res://feel/events/*.tres (class FeelEvent extends Resource)
Settings multipliers: shake, kick, fov_fx, radial_blur, speed_lines, chroma, flash,
                      hitstop (0.5–1.0), slowmo (on/off), rumble, photosensitive_mode
```

- `PROCESS_MODE_ALWAYS` keeps Feel running even when the SceneTree is paused [S68]. It reads real time from `Time.get_ticks_usec()`, so it never depends on scaled `delta`.
- Timers that must run in real time: `get_tree().create_timer(t, true, false, true)`. The last argument is `ignore_time_scale` [S43]. Tweens use `create_tween().set_ignore_time_scale(true)` [S44]. Timer nodes use `ignore_time_scale = true` [S42].
- Godot docs say to keep `Engine.time_scale` above 0.0 [S41]. Use 0.02–0.05 for "freezes".
- Rate limiters (estimate):
  - Global hitstop: at most 1 per 150 ms and 3 per second. A new request extends the current stop to the longer of the two; it never adds.
  - Full-screen flash: at most 2 per second (WCAG ceiling is 3 [S37]).
  - FOV punch: clamp the total delta to ±15°.
  - Rumble: take the max of active envelopes, never the sum.

---

## 2. Hit-stop / hit-lag (顿帧, 卡肉, ヒットストップ)

### 2.1 Reference data

| Source | What they do | Numbers |
|---|---|---|
| Capcom SFV design column [S7] | Hitstop follows a fixed per-game system, not per-move tuning | Example L/M/H = **8 / 12 / 16 f** (133/200/267 ms). Multi-hit moves get shortened stops. Projectiles give the attacker **0** hitstop. |
| Guilty Gear Strive [S8] | Hitstop by attack level | Lv0–Lv4 = **11, 12, 13, 14, 15 f** |
| GGST counter hits [S8] | "Cinematic" counter hits | Mid: **21 f** hitstop + **25 f** slowdown. Large: **31 f** + **35 f** slowdown. |
| GGST Roman Cancel [S8] | Super freeze + slowdown | Super freeze **12–25 F**; slowdown 9–59 F |
| Smash Ultimate [S4] | Damage-based formula | `floor((d·0.65 + 6) · h · e · s)` … A 15% hit = **15 f**. Electric ×1.5. Cap **30 f** (Melee: 20 f). |
| Sakurai, Famitsu 490 [S5] | Design notes | Both sides freeze for the same time. Projectiles get less hitstop. A cap exists. Hurt pose blends in over **4 f**. Attacker creeps during the stop. |
| Vlambeer, *Art of Screenshake* [S2] | "sleep" on enemy hit | **~20 ms** ("your brain won't notice") |
| Juicy Breakout source [S3] | Freezer with eased in/out | Slider ranges: duration 0–**320 ms**, speed multiplier 0–1, fade-in 0–**160 ms**, fade-out 0–160 ms |
| Practitioner article, gcores (CN) [S11] | Typical action-game stops | Usually **50–80 ms**. **>100–120 ms** only for huge hits. ZZZ slows actors but keeps hit VFX at full speed. |
| Monster Hunter (4G/XX era) [S9] | Hitstop driven by sharpness × hitzone | ≤25 bounce · 25–45 none · 45–100 **small** · >100 **large**. Hitstop lowers DPS because attacks take longer. |
| Monster Hunter Wilds [S10] | Tuning history | World players said hitstop "interfered". The Wilds beta lowered it for seamless play, then raised it again after feedback, adding extra hit SFX. |

### 2.2 Rules for a heavy mech (estimate unless cited)

- **Gunfire**: no stop on either side, following Capcom [S7] and Sakurai [S5]. Feedback comes from enemy hit flash, sparks, a hitmarker and a ticking UI sound.
- **Melee**: local hitstop on the attacker and the victim. Light 4 f, heavy 7 f, finisher 10 f, plus a slow-mo tail. These sit inside the 50–80 ms practitioner band [S11] and well under fighting-game values (8–16 f [S7]), because the open world keeps running around the fight.
- **Weak-point coefficient (MH / Marth-tipper idea)** [S6, S9]:

  `hitstop_ms = base_ms · coeff`, with coeff = 1.25 for weak points, 1.0 normal, 0.6 armor glance.

  Make it audible too: armor glance plays a "bounce" ping; a weak point plays a wet crunch with sub.
- **Multi-hit**: hits 2..n within 100 ms of the previous hit get 50% of the stop [S7].
- **Kill stop**: a global micro-freeze of **40 ms** at `time_scale = 0.05` for small kills (close to Vlambeer's 20 ms [S2], doubled for mech mass) and **100 ms** for large ones.
- **"Boss stop"** (Sakurai): freeze **plus** flash when a boss is beaten or staggered. Sakurai traces it back to *Kirby's Adventure*. *Fantasy Zone* freezes when the player is hit [S6b]. → Boss stagger = 150 ms global stop plus a white impact frame. Heavy damage taken = 83 ms global stop.
- **Never freeze player locomotion** that the player started (boost, quick boost, landing). Freezing it reads as input lag. GoW lengthened the axe-recall "wiggle" and players said their inputs felt delayed; 0.1 s was the maximum that worked [S23].
- **Buffer inputs** pressed during a stop and execute them when it ends. GGST mid/large counters clear the input register, which shows that buffering during stops is a deliberate tuning knob [S8].
- **Caps**: local ≤ 250 ms. Global ≤ 200 ms, except the ultimate's super freeze at 400 ms. Smash caps at 500 ms for a 1v1 fighter [S4].

### 2.3 Godot 4.7 implementation

- **Local hitstop (per actor)**:
  - Insert an `AnimationNodeTimeScale` node, named `TimeScale`, at the root of every actor's AnimationTree. A value of 0 pauses it [S55].
  - Set `anim_tree.set("parameters/TimeScale/scale", s)`. Actors driven only by AnimationPlayer use `speed_scale` instead [S69].
  - Multiply the actor's own movement `delta` by `local_time`. The actor stays in the tree; do **not** toggle `process_mode` (that would also stop the countdown).
  - Attacker `local_time` = 0.05 (Sakurai "creep" [S6]). Victim = 0.0.
- **Victim vibration** (Sakurai [S5, S6]):
  - Offset only the `VisualRoot` Node3D that holds the meshes. Never move the collision shapes.
  - Offset = ±A, alternating sign each frame. A(t) = A0·(1 − t/T).
  - A0 = 0.04·MECH_H at 10 m from the camera, scaled linearly by camera distance / 10 m (estimate).
  - Grounded: local X axis only. Airborne: X and Y.
  - Blend to the hurt pose over 4 f using a OneShot fade-in of 0.067 s.
- **Global micro-freeze**:
  - `Engine.time_scale = 0.05`. Store the end time from `Time.get_ticks_usec()` and restore in `_process`, or use `create_timer(..., ignore_time_scale = true)` [S43].
  - Restore to the *current slow-mo baseline*, not to 1.0.
  - Audio keeps playing at normal speed [S41]. That is desirable: the impact sound "rings" through the stop.
- **VFX during stops**:
  - GPUParticles3D follow the scaled clock. With the default `fixed_fps = 30` [S49] they become choppy under a low `time_scale` (Godot issue #81429, translation-only interpolation [S50]).
  - Impact emitters: `fixed_fps = 0`, `interpolate = false`. During a *global* stop, set `speed_scale = 1/time_scale` on hit-spark emitters that must stay live, as in the ZZZ/Smash precedent (estimate; verify on 4.7.2).
- Sketch:

```gdscript
# Feel/TimeFX.gd  (child of autoload, PROCESS_MODE_ALWAYS)
var _stop_end_us := 0
var baseline := 1.0          # slow-mo layer writes here
func micro_freeze(ms: float, scale := 0.05) -> void:
    _stop_end_us = maxi(_stop_end_us, Time.get_ticks_usec() + int(ms * 1000.0 * Settings.hitstop))
    Engine.time_scale = scale
func _process(_d: float) -> void:
    if _stop_end_us != 0 and Time.get_ticks_usec() >= _stop_end_us:
        _stop_end_us = 0
        Engine.time_scale = baseline
```

---

## 3. Camera: trauma shake, kick/recoil, FOV punch, framing

### 3.1 Sources

- **Eiserloh, GDC 2016** [S1] (slides saved to the image dir):
  - Trauma in [0,1]. Damage adds +0.2 or +0.5. Trauma decays linearly. Shake = trauma² or trauma³. With trauma³, trauma 0.3/0.6/0.9 → 3%/22%/73% shake.
  - 3D: **rotational only**; translational is "VERY BAD".
  - Each axis uses its own Perlin seed: `yaw = maxYaw·shake·Perlin(seed, t)`, `pitch` with seed+1, and so on. Noise "automagically works with pause and slow-motion" and is reproducible.
  - Smoothing: asymptotic averaging weight per frame at 60 fps. 0.01 is slow, 0.1 fast, 0.5 very fast. Multiply by timeScale.
- **KidsCanCode Godot 4 recipe** [S12] (2D defaults): `decay = 0.8/s`, `max_offset = (100, 75) px`, `max_roll = 0.1 rad`, `trauma_power = 2` (use 2–3). Noise period 4, 2 octaves.
- **Vlambeer** [S2]:
  - Camera kick: shove the camera *opposite* to the firing direction, not only random shake.
  - Gun kickback.
  - Camera leads toward where you aim.
  - Warning: shake is addictive. You stop noticing it "and then everybody else throws up".
- **Juicy Breakout Shaker** [S3]: a spring-damper with `drag = 0.1`, `elasticity = 0.1` per timestep. Impulse = −ball velocity × 0.5. This gives a *directional* kick, not noise.
- **Practitioner (CN)** [S11]: 3D games mostly shake pitch and yaw and avoid roll because it causes dizziness. Shake only on strong hits so the rhythm doesn't feel like a metronome.
- **Sakurai on framing** [S6b]: don't glue the look-at point to the character. In *Armored Core*, the AC drifts slightly off-center when moving so dodged bullets stay visible.
- **CS:GO recoil decay defaults** (public config) [S13]: `weapon_recoil_decay2_exp 8`, `weapon_recoil_decay2_lin 18`, `weapon_recoil_view_punch_extra 0.055`, `weapon_recoil_scale 2.0`, `weapon_recoil_cooldown 0.55`. Reading the names, that is an exponential plus linear return of view punch (interpretation, estimate).

### 3.2 Recommended camera numbers (all estimate)

| Parameter | Third person (TP) | First person cockpit (FP) |
|---|---|---|
| Base vertical FOV | 62° (≈ 95° H at 16:9; Godot 75° V ≈ 107.5° H [S46]) | 70° |
| Shake axes at trauma 1 | yaw 2.5°, pitch 2.5°, roll 1.2° | 0.6× view; cockpit interior mesh shakes 1.0× |
| Shake law / decay | shake = trauma², linear decay 1.5/s, noise ≈ 14 Hz, real time | same |
| Micro jitter | `Camera3D.h_offset/v_offset` ≤ 0.03 m, only on beam contact | 0 |
| Kick spring | critically damped, ω = 22 rad/s (settles ≈ 200 ms) | ω = 26 rad/s |
| Recoil per shot | MG pitch +0.25° (± yaw 0.1°); cannon +1.5°; railgun +3°. Returns via spring with no residual climb (arcade). | 1.2× (the cockpit "feels" closer) |
| Follow smoothing | Asymmetric asymptotic averaging: 0.12/frame horizontal, 0.06 upward, 0.2 downward on landing, × time scale [S1] | n/a |
| Aim lead | Shift the look-at point 1.5–3 m toward aim when boosting (AC style [S6b], Vlambeer lead [S2]) | n/a |

### 3.3 FOV punch (estimate)

| Trigger | Delta | In / hold / out |
|---|---|---|
| Boost start | +6° | 120 ms ease-out, hold while boosting, 300 ms back |
| Quick boost / dash | +10° | 60 ms in, 250 ms exponential return |
| Melee lunge | +4° | 80 ms in, 200 ms out |
| Finisher push-in | −10° | 150 ms in during slow-mo; on release +6° overshoot, 300 ms settle |
| Heavy hit taken | −3° | 40 ms in, 200 ms out |
| Boss stagger | −6° | 120 ms in, 400 ms out |
| Ultimate | −12° during the freeze, then +14° punch | 300 ms in, 80 ms punch, 500 ms recover |

- Clamp the sum to ±15° and multiply by the "FOV effects" slider.
- Minecraft ships exactly this slider ("FOV Effects") next to "Damage Tilt" (hurt shake) and "Distortion Effects" [S38].

### 3.4 Godot rig

```
CameraRig (Node3D, top_level=true, follows mech with asymmetric smoothing)
 └ Yaw (Node3D) └ Pitch (Node3D) └ SpringArm3D (TP length 10–13 m; collision mask = world)
    └ ShakePivot (Node3D)   ← noise rotation + kick spring rotation (local Euler, radians)
       └ Camera3D           ← fov tween; h_offset/v_offset micro-jitter [S46]
FP: Camera3D re-parented under BoneAttachment3D("cockpit"); CockpitInterior mesh gets shake.
```

- Noise: `FastNoiseLite` with `noise_type = TYPE_PERLIN` and 3 seeds; sample `get_noise_1d(t·14)` [S66].
- Advance `t` and the decay with **unscaled** time, so the camera still shakes during hitstop. Infil describes hitstop as the game "putting the characters on hold while someone shakes the camera a bit" [S67].
- **Aim input stays in real time during slow-mo.** Divide by `Engine.time_scale` or use raw mouse deltas. This is what makes slow-mo an aiming power, as in Vanquish AR mode [S19].
- Apply kick and noise to `ShakePivot` only. Gameplay aim raycasts come from the un-shaken Pitch node, so shake never steals accuracy (estimate).

---

## 4. Screen-space FX: radial blur, speed lines, chromatic aberration, flash and impact frames

- **Who does this:** Halo Infinite exposes sliders (0–100%) for radial blur, screen shake, full-screen effects and speed lines. XAG 117 cites it as the model [S36].
- **Impact frames come from giant-robot anime.** Yoshinori Kanada turned impact frames into black/white frames that *support* the impact ("the shock is so great it can no longer be represented"). His first was in *Getter Robo G* #39 [S24]. → They fit a Gundam-spirit game. Use them **only** on finishers, boss staggers and the ultimate.
- **Photosensitivity:** WCAG 2.3.1 [S37] allows no more than 3 general or red flashes in any 1 s, unless the flashing area is ≤ 25% of a 10° field (341×256 px on a 1024×768 reference). A "general flash" is an opposing relative-luminance change ≥ 10% where the darker state is < 0.80. Full-screen flashes always exceed the area limit, so cap their **rate**. Minecraft also offers "Hide Sky Flashes" [S38].
- **Godot 4.7 HDR caveat:** 4.7 adds HDR output on macOS [S63]. A "white" flash can hit the display's peak nits. Clamp the flash luminance in HDR mode (estimate; verify).

Recommended values (estimate)

| Effect | Value | Duration / curve |
|---|---|---|
| Radial blur (boost) | strength 0.025 UV, 8 taps, clear center radius 0.25 | Ramps with speed above boost threshold; 0.04 on quick boost for 120 ms |
| Speed lines | Screen-space streaks beyond 0.45 radius, opacity 0.35 | Only above 70% of max boost speed |
| Chromatic aberration pulse | 3 px at 1080p on heavy damage; 2 px on quick boost | 120 ms attack, 200 ms decay |
| Red damage vignette | Light: alpha 0.25; heavy: 0.6 | 150 ms / 350 ms |
| White flash (kill large) | Alpha 0.25 | 2 f |
| Impact frame (B/W, Kanada) | Full-screen threshold to black/white, alpha 0.6–0.85 | 1–2 f. Photosensitive mode: dim to 0.2 alpha, no inversion |
| Low-HP desaturation | `Environment.adjustment_saturation` → 0.55 below 15% HP [S62] | 500 ms ease |

**Godot implementation.** Use one `CanvasLayer` (layer 50, under the HUD) > `ColorRect` (Full Rect) with a `canvas_item` shader that samples `hint_screen_texture`. This is the official "custom post-processing" path [S57]. Hide the node (`visible = false`) when every strength is 0. Use `CompositorEffect` [S56] only if you need depth or motion vectors, or a pre-tonemap pass. Note that the compositor's compute template reads and writes the same `color_image`, so blurs need a copy pass (estimate). Sketch:

```glsl
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float radial = 0.0;    // 0..0.06
uniform float ca_px = 0.0;     // 0..4
uniform vec4 flash = vec4(1.0, 1.0, 1.0, 0.0);
uniform float vignette = 0.0;  // 0..1, tinted by vignette_col
uniform vec4 vignette_col : source_color = vec4(0.8, 0.0, 0.0, 1.0);
uniform float impact_bw = 0.0; // 0/1 impact frame
void fragment() {
    vec2 d = SCREEN_UV - vec2(0.5);
    vec2 ca = normalize(d + 1e-5) * ca_px * SCREEN_PIXEL_SIZE.x;
    vec3 acc = vec3(0.0);
    for (int i = 0; i < 8; i++) {
        vec2 uv = vec2(0.5) + d * (1.0 - radial * float(i) / 7.0);
        acc += vec3(texture(screen_tex, uv + ca).r, texture(screen_tex, uv).g, texture(screen_tex, uv - ca).b);
    }
    vec3 c = acc / 8.0;
    c = mix(c, vignette_col.rgb, vignette * smoothstep(0.35, 0.75, length(d)));
    float l = dot(c, vec3(0.299, 0.587, 0.114));
    c = mix(c, vec3(step(0.45, l)), impact_bw);
    COLOR = vec4(mix(c, flash.rgb, flash.a), 1.0);
}
```

---

## 5. Slow motion, finishers and kill cams

| Reference | Mechanic | Numbers |
|---|---|---|
| Doom 2016 glory kill [S14, S16] | Stagger → melee finisher | Staggered enemies glow blue, then orange once in range. Animatic kills ran about 3 s and felt bad; shipped kills are **30–60 frames (1–1.5 s)**. The player regains control while the death animation plays on. The camera exits looking where the player looked, to avoid nausea. The player is invulnerable (fully in Eternal). |
| Doom GDC 2018 [S15] | Control-state ladder | Twitch → Falter → Stagger. A monster released from stagger gets a "second wind". |
| Titanfall [S17] | Titan termination | Doomed titan within **6.6675 m** and a 45° front cone. TF2 plays it in **third person**, with both titans invulnerable. TF1 cores: **200 s** base charge, cut by dealing damage, and a **2 s** priming on activation. |
| Bayonetta [S18] | Witch Time (last-moment dodge) | B1: dodge grants **2–4 s**, counter **3–6 s**, 1.5× combo points. B2: base **0.5–3 s** per attack; hits extend it (4 → 12 s). B3: about 1 s base ×4 on a perfect dodge. |
| Vanquish [S19] | AR mode | Auto-triggers when taking too much damage. Manual: aim while boosting, dodging or vaulting. Shares heat with boosters; overheat = cooldown with reduced mobility. Melee overheats instantly. |
| GGST [S8] | Counter-hit slowdown | Mid 25 f, Large 35 f slowdown after the hitstop |

Recommendations (estimate)
- **Finisher ("Overdrive Execution")**:
  - Trigger: an enemy in *Stagger* within 0.7·MECH_H of the player and inside a 45° cone (Titanfall-style gate [S17]).
  - Timeline:
    - 0–150 ms: lunge with FOV −10°.
    - Hit: 10 f local hitstop plus a 1–2 f impact frame.
    - 0.3× slow-mo for 300 ms real time, then ease back over 200 ms.
    - Total player lock ≤ 1.2 s; the enemy's death animation runs on for another 1–2 s [S14].
  - The player is invulnerable for the whole lock (Doom Eternal precedent [S16]).
  - In FP the camera cuts to a fixed TP "execution cam" for the lock (TF2 precedent [S17]), then returns to the pre-kill aim direction [S14].
- **Large kill**: 100 ms micro-freeze, then 0.35× for 350 ms. No input lock.
- **"Last stand" (Vanquish-inspired)**: when HP first crosses 15%, apply 0.5× world slow-mo for 1.5 s. The player's aim and movement stay at 1.0×. Cooldown 60 s.
- **Ultimate activation**: a 400 ms super freeze (GGST-style 12–25 F [S8], extended for spectacle) with a camera push-in. Then 0.6 s of player-only wind-up while enemies run at 0.3×.
- **Godot**:
  - Tween `Engine.time_scale` with `create_tween().set_ignore_time_scale(true)` [S44]. Without it, the tween slows itself down.
  - Player-relative time: scale player movement by `1/Engine.time_scale` while a "player-exempt" flag is set.
  - Sync kills: one AnimationLibrary per (attacker, victim-class, direction) with matching root offsets. Snap the victim to `attacker.global_transform * offset` for the lock.
  - Audio: `AudioServer.playback_speed_scale` slows **all** audio [S45]. Prefer routing SFX through a bus with `AudioEffectPitchShift` (pitch_scale 0.8) plus a low-pass (cutoff 3–5 kHz) during slow-mo. Leave music untouched.

---

## 6. VFX: sparks, debris, decals, shockwaves, permanence

- **Sources:**
  - Vlambeer's list [S2]: bigger bullets, muzzle flash (first frame of the bullet), faster bullets, impact effects, enemy knockback, permanence (bodies and shells stay), bigger explosions, smoke that lingers.
  - Juicy Breakout [S3]: shatter particles, block push/rotate/darken, ball trails, a "Finish him" color glitch.
  - Practitioner tips [S11]: hit VFX about 1.2× the attack VFX's visual size, but shorter-lived. Wuthering Waves offsets hit VFX about 0.5 m upward so they don't overlap the slash VFX. Rotate hit VFX to match the slash direction.
- **Godot nodes**:
  - `GPUParticles3D` with `one_shot = true`, `explosiveness = 1.0` (all particles at once [S49]), and `emitting = true`/`restart()` from a pool.
  - Spark streaks: `transform_align = TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY` [S49].
  - Trails: `trail_enabled` with RibbonTrailMesh, which needs `use_particle_trails` on the material [S49].
  - 4.7 adds new particle scale and rotation controls [S63].
  - Single impacts: `emit_particle()` exists (Forward+/Mobile) [S49].
- **Decals**:
  - `Decal` with `texture_albedo/normal/emission`, `upper_fade`/`lower_fade` (0.3 default), `distance_fade_enabled` + `distance_fade_begin` [S51].
  - Decals are clustered, not post-process [S51]. Lights, decals and reflection probes share **512 clustered elements per view** [S51].
  - Ring buffer: 128 decals plus 16 pooled flash `OmniLight3D` (2–3 f life) (estimate).
- **Hit flash on enemies**: `instance uniform float hit_flash;` in the monster shader, set via `set_instance_shader_parameter` with no material duplication [S58]. Max about 16 instance uniforms per shader. With multiple materials, the first material's parameters "win" unless the name, index and type match [S58]. That matters for Tripo meshes with several materials.

Particle presets (estimate; speeds in m/s, lifetimes in s)

| Preset | Contents |
|---|---|
| `spark_bullet` | 12 streaks, v 18–40, life 0.12–0.25, gravity 20; 2 f flash quad; world decal 0.35 m |
| `beam_contact` | Continuous 80/s sparks, 0.8 m molten decal every 0.12 s, 0.03 m h/v-offset camera jitter |
| `missile_blast` | Fireball flipbook ×1, 32 sparks, 12 debris (collide), 6 smoke puffs (1.5–3 s), shockwave ring 0 → 10 m in 180 ms (distortion shader on a quad), scorch decal 3.5 m, OmniLight3D energy 8 / range 12 m for 3 f |
| `melee_light` | 16 sparks + slash arc (rotated to the swing) |
| `melee_heavy` | 32 sparks + 6 armor shards + ring 0 → 4 m |
| `finisher` | 64 sparks, 12 shards, coolant burst, ring 0 → 8 m, impact frame |
| `kill_small` | Medium blast, 24 debris, 2 s smoke, scorch 2.5 m |
| `kill_large` | 3 chained blasts at +0/0.15/0.35 s, ring 0 → 18 m, burning wreck for 30 s (permanence) |
| `land_heavy` | Crater decal 4 m, dust ring 0 → 10 m, 12 rubble chunks |

---

## 7. Enemy hit reactions: flinch, stagger, knockback, dismemberment

- **Doom ladder** [S15]: *Twitch* plays a reaction that doesn't impede combat. *Falter* stops the current attack and restarts its combat behaviour. *Stagger* takes the AI out of the fight and enables the glory kill. "Second wind" applies if stagger is ignored. Doom's stagger is RE4-inspired and fires at a health percentage [S14]. Doom's prototype used location reactions: a shoulder shot spins the enemy, a leg shot can blow the leg off [S14].
- **Armored Core VI ACS** [S21]: any hit can overload the ACS, leaving the target staggered and vulnerable for a short time. Attacks on a staggered target add "Direct Hit" bonus damage. OS tuning raises it by up to **15%**.
- **Sekiro posture** [S22]: posture recovers more slowly at low vitality. Deflects deal more posture damage than hits. Perilous attacks are flagged by a red kanji.
- **Monster Hunter**: parts have flinch values (怯み値). Hitstop depends on hitzone softness [S9].
- **Sakurai**: about 4 f blend into the hurt pose. Hurtboxes don't vibrate [S5, S6].

Recommended ladder (estimate)

| State | Trigger | Animation | Duration |
|---|---|---|---|
| Twitch | Any hit | Additive directional flinch (Add3 in AnimationTree), 0.25 weight | 150–250 ms, never interrupts |
| Falter | ≥ 8% max HP in 0.5 s, or a heavy melee | Interrupt the current attack; knock back 0.15·MECH_H | 0.6–0.9 s |
| Stagger | Posture/ACS meter full (meter = impact damage; decays 15%/s when not hit) | Kneel/sway loop; enemy flashes cyan (out of range) or amber (in finisher range), Doom-style [S16] | Fodder 3 s, elite 4 s, boss 5–6 s; damage ×1.3 (Direct-Hit style) |
| Second wind | Stagger expires | +25% attack speed for 6 s | n/a |
| Death | HP 0 | Ragdoll blend or scripted collapse + debris | Wreck persists 30 s |

- **Godot**:
  - Hit reactions: `AnimationNodeOneShot` (fade 0.067 s ≈ 4 f) and `AnimationNodeAdd3` for direction.
  - Partial ragdoll: `PhysicalBoneSimulator3D.physical_bones_start_simulation(["arm_l", …])` [S61] with `influence` ramped 0.3 → 0 over 200 ms (SkeletonModifier3D influence [S61]).
  - Knockback: apply velocity to the CharacterBody3D. 4–6 m/s for fodder, 0 for bosses (estimate).
- **Dismemberment with Tripo models**: Tripo outputs fused single meshes. Dismemberment needs the limb meshes split along bone weights in Blender, with cap geometry and a `BoneAttachment3D` per detachable part. Budget 2–4 detachable parts per monster (estimate). This is a pipeline task, not a runtime trick.

---

## 8. HUD feedback: hit markers, kill confirms, damage numbers, style meter

- **Hitmarker sound (CoD)** [S27]: it "has to cut through the guns, the explosions" and give "the same exact feeling" every game. When Treyarch's audio director swapped it, complaints arrived within 3 hours. → Route it on a dedicated `UI` bus that is never ducked. Keep it identical across weapons.
- **Hit marks matter more when the camera is far.** Sakurai, *Hit Marks [Effects]* [S65]. Our TP camera at 10–13 m qualifies.
- **Damage numbers (KidsCanCode recipe)** [S64]: travel (0, −80) px, duration 2 s, random spread π/2. Crits pop at 2× scale → 1× over 0.4 s with TRANS_BACK. Pool the labels instead of freeing them.
- **Godot**:
  - `Label3D` with billboard, `no_depth_test = true` and `fixed_size = true` (same on-screen size at any distance) [S59].
  - 4.7 Control nodes gain `offset_transform_*` for pops inside containers [S63].
- **Recommended for this game (estimate)**:
  - Numbers live 0.7 s and merge per target within 150 ms (one rolling number per enemy).
  - Weak point: amber, 1.6× pop over 120 ms. Armor glance: grey, 0.8×.
  - Hitmarker: white X, 80 ms. Kill: red X plus a 250 ms ring, with a distinct kill sound (sub thump + high click).
- **Style meter (DMC)** [S20]:
  - Ranks D → SSS. DMC5 names them Dismal, Crazy, Badass, Apocalyptic!, Savage!, Sick Skills!!, Smokin' Sexy Style!!.
  - Repeating a move gives diminishing returns, and the gauge drains faster at higher ranks.
  - Taking damage drops 2 ranks in DMC4/5. DMC1 lost the rank after 1.5 s of inactivity.
  - Witch Time multiplies combo points ×1.5 [S18].
  - → Mech version (estimate): 7 ranks. Variety is measured over the last 4 skill IDs; a repeat earns 35%. Higher ranks feed ultimate charge (Titanfall cores charge faster from damage dealt [S17]). Damage taken drops 2 ranks. Decay: 3 s per rank at D, 1.2 s per rank at SSS.

---

## 9. Audio for impact

- **Five layers** [S25] (Mark Kilborn, CoD): **Body, Transient, Sub/LFE, Mechanical, Tail.** Each is routed separately before rendering.
- **"More bass"**: Vlambeer cites a gun that became popular after nothing more than added bass [S2].
- **Duration by weight** [S11]: light 0.1–0.3 s, medium 0.3–0.5 s, heavy 0.5–0.8 s. Loudness priority: block > hit > attack > voice.
- **HDR mixing (Wwise)** [S26]: an HDR window is positioned by the loudest sound at any moment, and quieter sounds are pushed down. Godot has no HDR bus, so emulate it with sidechain compression.
- **Low health** [S28, S29]: a low-pass on the World bus driven by HP, plus a heartbeat loop. A full muffle sits at a cutoff of about 150–300 Hz.
- **Godot buses (estimate)**:

  `Master ← {Music, World, Impacts, Player, UI, Voice}`

  - `Music` and `World` carry an `AudioEffectCompressor` with `sidechain = &"Impacts"`, threshold −20 dB, ratio 4, attack 500 µs, release 250 ms. Ranges: attack 20–2000 µs, release 20–2000 ms [S52].
  - `UI` (hitmarkers, kill confirms) is never ducked.
  - `World` also carries an `AudioEffectLowPassFilter` (`cutoff_hz` range 1–20500 [S70]) tied to HP and concussion.
- **Variation**: `AudioStreamRandomizer` with `random_pitch = 1.06` (range is 1/x … x [S53]) and `random_volume_offset_db = 1.5`. Raise `AudioStreamPlayer3D.max_polyphony` (default 1 cuts the oldest sound [S60]) to 4–6 for automatic weapons. `panning_strength` multiplies the project's 0.5 base [S60].
- **Slow-mo**: see section 5. Global hitstop leaves audio running [S41].
- **Kill confirm and explosions**: duck World by −6 dB for 300 ms after a large kill. Leave room for the tail (city reverb 1.5–2.5 s) (estimate).

---

## 10. Controller rumble (haptics)

- **Motor semantics** [S39]: the left motor is low-frequency and the right is high-frequency (XInput). Godot exposes `Input.start_joy_vibration(device, weak_magnitude, strong_magnitude, duration)` with values 0–1. A duration of 0 means "as long as possible" (about 65 s) [S47].
- **macOS** [S47]: requires macOS 11+. Over **USB**, only major brands work, and **Xbox One/Series pads are excluded**. Test Xbox pads over Bluetooth, plus DualSense. Godot uses SDL3 for controllers on macOS [S63].
- **Godot docs** [S48]: "provide an in-game slider to disable vibration or reduce its intensity."
- **God of War axe recall** [S23]: three separate rumbles (trigger, flight, catch). The sound is attached to the axe and its pitch follows the axe's spin rate. → Use multi-phase patterns for signature moves.
- **Short pulses**: Android guidance puts a crisp click at 10–20 ms and says actuators ring 20–50 ms afterward [S40]. Gamepad ERM motors spin up more slowly, so use ≥ 60 ms pulses for anything that must be felt (estimate).
- **Mixer (estimate)**:
  - Keep a list of envelopes (weak, strong, attack, hold, release, curve).
  - Every 50 ms, send the per-motor **max** with `duration = 0.1`. Assume each call replaces the previous effect (verify on 4.7.2).
  - Scale everything by the rumble slider.
  - Sustained boost rumble sits under the transients at 0.1–0.15.

---

## 11. Tension: telegraphs, roars, alarms, intensity director, low HP, near misses, crowd pressure

### 11.1 Telegraph timing

- **GDKeys** [S32]: anticipation = player reaction (0.25 s ≈ 15 f at 60 fps) + time for the expected player action to take effect + a difficulty buffer.
  - Every anticipation animation must be unique and hint at its follow-up.
  - The attack itself is near-instant and "constant".
  - Recovery length *is* the window of opportunity.
  - Use weapon-trail VFX during the attack phase (Nioh precedent).
  - Example: Hollow Knight's Hornet dash has a **15 f at 30 fps (0.5 s)** anticipation.
- **Human Benchmark median reaction**: **273 ms** [S33].
- **Sekiro** [S22]: one red kanji flags every unblockable "perilous" attack; the counter depends on reading body language.

Windups for mech enemies (estimate). Assumes quick boost becomes effective 67 ms after the press.

| Attack class | Windup (anticipation) | Signals | Recovery (WoO) |
|---|---|---|---|
| Fodder melee | 450–600 ms | Pose + 0.2 s eye/vent glow | 500–800 ms |
| Fodder ranged burst | 600 ms charge | Muzzle glow + rising whine (3D audio) | 400 ms |
| Elite lunge | 400–500 ms | Unique silhouette + trail VFX during the attack | 600 ms |
| Sniper / railgun | 1.2–2.0 s laser lock; final "ping" at −300 ms | Laser line, HUD edge arrow if off-screen | n/a |
| Boss heavy | 700–1,200 ms | Roar or vent flare, ground decal of the AoE | 1.2–2.0 s |
| Boss perilous (unblockable) | 900–1,400 ms | Red glyph above the boss + unique sting (Sekiro-style) | 1.5 s |
| Off-screen attacker | +200 ms on top of the above | Directional audio + HUD arrow | n/a |

### 11.2 Roars, alarms, music, intensity

- **Boss roar (estimate)**: 1.2–2.0 s. At most 0.3 s input lock; no long stun.
  - World ducks −8 dB. Strong rumble 0.6 for the roar's length. Sustained trauma 0.25 at about 8 Hz noise. FOV −4°.
  - Glass-shatter decals and dust on nearby façades (permanence).
- **City alarm (estimate)**: two-tone siren alternating every 0.5 s on 3D emitters on buildings, plus slow rotating amber/red SpotLights. Budget at most 6 alarm lights in view (cluster budget [S51]).
- **Intensity director (L4D)** [S31]:
  - Intensity rises with damage taken (proportional), being incapacitated, or being pushed off a ledge.
  - Nearby kills add intensity inversely proportional to distance.
  - It decays over time but **not while enemies are actively engaging**.
  - Phases: Build-up → **Sustain peak 3–5 s** → Peak fade → **Relax 30–45 s** with minimal threats.
  - Mobs of 20–30 spawn every 90–180 s; **75% come from behind**; special enemies spawn out of sight.
- **Doom music** [S30]: tracks are cut into small sections, and code picks the section that fits the action.
- **Godot music**:
  - `AudioStreamInteractive` for horizontal re-sequencing: clips plus a transition table with from/to time rules and fade beats [S54].
  - `AudioStreamSynchronized` for vertical layers, up to 32 synced streams, with `set_sync_stream_volume` per layer [S54].
  - Map intensity I ∈ [0,1] (estimate): layer 2 at I > 0.3, layer 3 at I > 0.6, layer 4 at I > 0.85. Use 1.5 s fades. Switch clips Explore → Tension → Combat → Boss on bar boundaries.

### 11.3 Low HP, near misses, crowd pressure

- **Low HP (estimate)**:

  | HP | Heartbeat | World LPF | Saturation | Red vignette |
  |---|---|---|---|---|
  | < 35% | 80 bpm | 6 kHz | n/a | n/a |
  | < 15% | 120 bpm | 1.2 kHz | 0.55 | Pulses with the heartbeat |

  - Cockpit alarm beep at 2 Hz.
  - "Last stand" slow-mo once per 60 s (Vanquish [S19]).
  - Never rely on color alone; pair it with sound and HUD text.
- **Near miss** [S34]: BF3 puts a 1.5 m suppression sphere around a soldier's head (≈ 0.83× a 1.8 m body). Suppression penalties start above a 40% threshold.
  - → Mech (estimate): sphere radius = 0.8·MECH_H (≈ 7 m) around the cockpit.
  - On a non-hit pass: play a doppler whoosh at the closest-approach point (supersonic crack for railgun), add trauma 0.04, and nudge yaw 0.4° toward that side.
  - A suppression meter above 40% drives a subtle edge blur and vignette.
  - Rate limit: 4 per second.
- **Crowd pressure** [S15]:
  - Doom limits the number of *active* attackers and keeps the player's tools able to interrupt.
  - Arena fights last about 5 minutes. Minions are capped at 10 (20 in big encounters). A "last heavy standing" rule ends a fight.
  - Health drops are rubber-banded.
  - → Mech (estimate): attack tokens allow at most 2 melee and 3 ranged attackers on the player at once, and 1 boss-class telegraph at a time. A freed token is re-granted after 0.6–1.0 s. The HUD threat ring shows the count off-screen.

---

## 12. Avoiding over-juicing: readability, sickness, accessibility

- **Evidence**:
  - Kao's action-RPG study found *None* and *Extreme* juiciness both reduced play time and player experience; Medium and High did best [S35] (n = 3,018 per Kao 2024's summary [S35b]).
  - Vlambeer warns that designers habituate to shake [S2].
  - MH World players found hitstop intrusive; Wilds tuned it down for seamless play, then partly back up, adding hit SFX [S10].
  - Sakurai keeps hitstop short in free-for-alls because a frozen pair invites a third player [S5].
  - Doom shortened glory kills and fixed the camera exit direction for motion-sick players [S14].
  - God of War: a longer pre-motion felt like input lag [S23].
- **Readability**: hit VFX ≈ 1.2× the slash, shorter-lived, and offset [S11]. Enemy hit flash ≤ 6 f. Never cover the reticle with sparks: kill the screen-space alpha of particles within 4° of the reticle (estimate).
- **Settings menu**: every item from XAG 117 [S36], with defaults (estimate):

  | Setting | Default | Range / note |
  |---|---|---|
  | Screen shake | 100% | 0–100 |
  | Camera kick | 100% | n/a |
  | FOV effects | 100% | n/a |
  | Radial blur | 100% | n/a |
  | Speed lines | 100% | n/a |
  | Chromatic aberration | On | n/a |
  | Flash intensity | 100% | n/a |
  | Photosensitivity mode | Off | When on: flashes ≤ 30% alpha, ≤ 2 per second, impact frames replaced by a dim |
  | Hitstop | 100% | 50–100 |
  | Slow-motion effects | On | n/a |
  | Rumble | 100% | n/a |
  | Heartbeat / low-HP muffle | On | n/a |
  | Damage numbers | On | n/a |
  | Base FOV | n/a | Adjustable, per XAG 117 |
  | Cockpit shake moves interior, not view | On | n/a |

---

## 13. Feel spec v0

Global stops use `Engine.time_scale = 0.05`. Local stops use AnimationTree TimeScale (victim 0, attacker 0.05). Trauma values are *added* (clamp 1). Rumble is weak(HF)/strong(LF)/ms. Everything is **(estimate)** and calibrated against the sourced ranges above. Sound layers: **T** transient, **B** body, **S** sub/LFE, **M** mechanical, **Tl** tail, **D** debris, **UI** = UI bus (never ducked).

| Event | Hitstop | Shake (trauma) | Flash | FOV | Slow-mo | Particles | Sound layers | Rumble w/s/ms |
|---|---|---|---|---|---|---|---|---|
| Bullet hit (player MG/rifle on enemy) | none | 0 (firing uses kick 0.25°/shot) | Enemy `hit_flash` 0.6 for 2 f | 0 | none | `spark_bullet` (12 streaks), decal on world only | T metal tick + small B; UI tick | 0.15 / 0 / 60 (rate-limit 10 per second) |
| Beam hit (continuous) | none; 33 ms local on first contact, then every 0.5 s | +0.6 per second, capped at 0.25 sustained; 0.03 m h/v jitter | Flicker 0.35 at 10 Hz | 0 | none | `beam_contact` 80/s + molten decals | Sizzle loop B + contact T + 50 Hz S hum | 0.3 / 0.15 sustained, 120 ms release |
| Missile hit | Victim local 50 ms (first of a salvo only, then 0 for 150 ms) | 0.25·(1 − d/80 m) | Enemy flash 4 f; OmniLight 3 f | 0 | none | `missile_blast`, shockwave 0 → 10 m in 180 ms | T crack + B blast + S 35–55 Hz 300 ms + Tl 1.5–2.5 s + D | 0.35 / 0.6 / 180 |
| Melee light | Local 67 ms (4 f) | +0.15 | Enemy flash 3 f full | +4° lunge | none | `melee_light` | T clang + B 150 ms + M servo | 0.4 / 0.2 / 80 |
| Melee heavy | Local 117 ms (7 f); weak point ×1.25 | +0.30 + kick 1° along swing | Enemy flash 5 f | +4° lunge, −2° on hit | none | `melee_heavy`, ring 0 → 4 m | T + B 300 ms + S 200 ms + M | 0.6 / 0.6 / 150 |
| Melee finisher | Local 167 ms (10 f) | +0.55 | 1–2 f B/W impact frame + enemy flash 6 f | −10° push, +6° release | 0.3× for 300 ms, 200 ms ease-out | `finisher` | Reverse-swell 300 ms → T + B + S + Tl; World −9 dB for 0.5 s | 0.8 / 1.0 / 250 |
| Enemy kill (small) | Global 40 ms | +0.12 (distance falloff) | White 0.15 alpha 1 f (if < 40 m) | 0 | none | `kill_small` + wreck | B blast + D; UI kill confirm | 0.3 / 0.3 / 100 |
| Enemy kill (large) | Global 100 ms | +0.45 | White 0.25 alpha 2 f | −3°, then back over 400 ms | 0.35× for 350 ms | `kill_large` (3 chained) + 30 s burning wreck | T + B + S + Tl + D; World −6 dB 300 ms; UI kill | 0.5 / 0.9 / 350 |
| Boss stagger | Global 150 ms | +0.60 | B/W impact frame 1 f + white 0.4 alpha 2 f; boss flashes amber when in finisher range | −6° 120 ms, out 400 ms | 0.5× for 400 ms | Armor plates eject (3–5 rigid bodies), arcs 1.5 s, steam | Metal groan B + S + music sting; boss alarm loop | 0.6 / 1.0 / 400 (two pulses 150 + 250) |
| Boost start | none | +0.08 | none | +6° in 120 ms, hold | none | Thruster burst + ground dust ring if altitude < 5 m | Ignition T + roar loop B (attached 3D) + S 40 Hz 150 ms | 0.2 / 0.4 / 200, then 0.1 / 0.15 sustained |
| Quick boost | none (never freeze) | +0.06 + kick 0.6° opposite to the dash | CA 2 px for 120 ms | +10° in 60 ms, 250 ms return | none | Plume + 3 afterimages for 120 ms; radial blur 0.04 for 120 ms | T "chuff" + whoosh B 250 ms | 0.5 / 0.3 / 90 |
| Landing (light) | none | +0.08 + camera dip 0.1 m | none | 0 | none | 8-particle dust puff | B thud 120 ms + M hydraulics | 0.1 / 0.3 / 80 |
| Landing (heavy) | none (player); world props bounce | +0.35 + dip 0.25 m | none | −2° for 60 ms | none | `land_heavy` (crater decal 4 m) | T + B + S + D rubble | 0.3 / 0.9 / 220 |
| Taking damage (light) | none | +0.18 | Red vignette 0.25 for 150 ms | 0 | none | Sparks on own armor | Armor ping T + B; no UI | 0.3 / 0.2 / 100 |
| Taking damage (heavy) | Global 83 ms (5 f) | +0.50 + kick 1.5° away from the source | Red vignette 0.6 for 350 ms + CA 3 px for 120 ms | −3° in 40 ms, out 200 ms | none (last stand at < 15% HP: 0.5× for 1.5 s, cooldown 60 s) | Armor chunk + 2 s smoke on own mech | T + B + S + cockpit alarm; World LPF 1.5 kHz for 400 ms | 0.6 / 0.8 / 300 |
| Near miss | none | +0.04 + yaw nudge 0.4° toward the side | Subtle edge blur if suppression > 40% | 0 | none | Tracer only | Doppler flyby (3D) at closest approach; supersonic crack for rails | 0.25 / 0 / 60 |
| Ultimate activation | Global super-freeze 400 ms (enemies), then enemies at 0.3× for 600 ms while the player winds up | +0.25 at activation, +0.80 at release | B/W impact frame 2 f at release (photosensitive mode: dim) | −12° push in 300 ms, +14° punch in 80 ms at release, 500 ms recover | Enemies 0.3× for 0.6 s (player 1.0×) | Converging energy 0.4 s → release burst + ring 0 → 25 m | Riser 0.4 s (pitch up) → T + B + S + Tl; music drop-out then slam back in | Ramp 0.3/0.6 over 400 ms, then 1.0/1.0 for 300 ms |

Implementation note for the table: store each row as a `FeelEvent` `.tres`. Distance falloff = `clamp(1 − d / falloff_m, 0, 1)` with `falloff_m` per event (kills 60 m, missiles 80 m). FP view applies shake ×0.6 and FOV ×0.75. HUD markers are identical in FP and TP (estimate).

---

## 14. Sources

- S1 Eiserloh, *Math for Game Programmers: Juicing Your Cameras With Math*, GDC 2016. Slides: https://gdcvault.com/play/mediaProxy.php?sid=1023146 · session page: https://gdcvault.com/play/1023146/Math-for-Game-Programmers-Juicing
- S2 Jan Willem Nijman, *The Art of Screenshake*, INDIGO 2013. Video: https://www.youtube.com/watch?v=AJdEqssNZ-U · transcript: https://lilys.ai/ko/notes/783970
- S3 Jonasson & Purho, *Juice it or lose it*. Talk: https://www.youtube.com/watch?v=Fy0aCDmgnxg · source: https://github.com/grapefrukt/juicy-breakout (Settings.as, Freezer.as, Shaker.as)
- S4 SmashWiki, Hitlag: https://www.ssbwiki.com/Hitlag
- S5 Sakurai, "Thinking About Hitstop", Famitsu Vol. 490 (translation): https://sourcegaming.info/2015/11/11/thoughts-on-hitstop-sakurais-famitsu-column-vol-490-1/
- S6 Sakurai, *8つのヒットストップ仕様* / *Eight Hit Stop Techniques*: https://www.youtube.com/watch?v=CiQzmwz_Olg · https://www.youtube.com/watch?v=tycbMSjDDLg · JP summary: https://note.com/rr_r612/n/n7773b6ebf77e
- S6b Sakurai "仕様" category summary (boss stop, Fantasy Zone, look-at point / Armored Core): https://senkohome.com/sakurai-game-dev-specification/
- S7 Capcom SFV column "Hour 11: The Basics of Attacking: Damage Part II" (archived): https://web.archive.org/web/2023/https://game.capcom.com/cfn/sfv/column/131545
- S8 Dustloop GGST Frame Data: https://www.dustloop.com/w/GGST/Frame_Data · Mechanics: https://www.dustloop.com/w/GGST/Mechanics
- S9 モンハン攻略 (hitstop/bounce thresholds): https://bassy-mh.info/mhzyotatu-hitstop.html
- S10 GamingBolt / MP1st, MH Wilds hitstop interview: https://gamingbolt.com/monster-hunter-wilds-weapon-hitstops-will-be-closer-to-what-people-are-looking-forward-to
- S11 机核 gcores, 浅谈游戏战斗设计——战斗表现 (2025): https://www.gcores.com/articles/202329
- S12 KidsCanCode, Godot 4 Recipes: Screen Shake: https://kidscancode.org/godot_recipes/4.x/2d/screen_shake/index.html
- S13 CS:GO recoil cvars (public config): https://github.com/Aox2120/CSGO-Config/blob/master/recoil.cfg
- S14 Rock Paper Shotgun, *How Doom's Glory Kills Maintain Momentum* (2016): https://www.rockpapershotgun.com/doom-glory-kills-mechanic
- S15 Loudy & Campbell, *Embracing Push Forward Combat in DOOM*, GDC 2018: https://www.youtube.com/watch?v=2KQNpQD8Ayo · summary: https://videohighlight.com/v/2KQNpQD8Ayo
- S16 DoomWiki, Glory kill: https://doomwiki.org/wiki/Glory_kill · Doom Fandom: https://doom.fandom.com/wiki/Glory_Kill
- S17 Titanfall Wiki: https://titanfall.fandom.com/wiki/Termination · https://titanfall.fandom.com/wiki/Core_Abilities
- S18 Bayonetta Wiki, Witch Time: https://bayonetta.fandom.com/wiki/Witch_Time
- S19 Wikipedia, Vanquish: https://en.wikipedia.org/wiki/Vanquish_(video_game)
- S20 DMC Wiki, Stylish Rank: https://devilmaycry.fandom.com/wiki/Stylish_Rank
- S21 Armored Core Wiki, Stability (ACS): https://armoredcore.fandom.com/wiki/Stability
- S22 Eurogamer, Sekiro combat system explained: https://www.eurogamer.net/sekiro-combat-system-explained-posture-perilous-attacks-how-to-deflect-dodge-counter-frame-data-6009
- S23 Vince Napoli, *Recalling the Leviathan Axe* (2018): https://www.gamedeveloper.com/design/recalling-the-leviathan-axe
- S24 Animétudes, *The Kanada style in context*: https://animetudes.com/2021/03/06/the-kanada-style-in-context/
- S25 Mark Kilborn gunshot layers (Pro Sound Effects): https://blog.prosoundeffects.com/how-to-sound-design-first-person-shooter-gunshot-sound-effects-with-mark-kilborn
- S26 Audiokinetic, Setting the dynamics of HDR: https://www.audiokinetic.com/library/2025.1.12_9287/?source=Help&id=setting_dynamics_of_hdr
- S27 PC Gamer, *The origin of Call of Duty's most-heard sound*: https://www.pcgamer.com/the-origin-of-call-of-dutys-most-heard-sound/
- S28 Splice, *How to design a dynamic game audio mix*: https://splice.com/blog/dynamic-game-audio-mix/
- S29 GameDevBeginner, low-health audio filter: https://gamedevbeginner.com/create-a-low-health-audio-filter-in-unity-using-the-audio-mixer-transition-to-snapshots/
- S30 Everything Is Noise, *Sound Test: DOOM (2016)*: https://everythingisnoise.net/features/sound-test-doom-2016/
- S31 Michael Booth, *The AI Systems of Left 4 Dead* (2009): https://steamcdn-a.akamaihd.net/apps/valve/2009/ai_systems_of_l4d_mike_booth.pdf
- S32 GDKeys, *Keys to Combat Design: Anatomy of an Attack*: https://gdkeys.com/keys-to-combat-design-1-anatomy-of-an-attack/
- S33 Human Benchmark, reaction-time statistics: https://humanbenchmark.com/tests/reactiontime/statistics
- S34 Symthic, BF3 weapon mechanics (suppression): https://sym.gg/legacy/index.html?game=bf3&page=weapon-mechanics (content: https://sym.gg/legacy/pages/bf3/bf3_dataWeapon.html)
- S35 Kao, *The effects of juiciness in an action RPG* (2020): https://www.sciencedirect.com/science/article/pii/S1875952118300879 · S35b Kao 2024 summary: https://people.csail.mit.edu/dkao/pdf/3613904.3642656.pdf
- S36 Xbox Accessibility Guideline 117: https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/117
- S37 WCAG 2.2 Understanding SC 2.3.1: https://www.w3.org/WAI/WCAG22/Understanding/three-flashes-or-below-threshold.html
- S38 Minecraft Wiki, Options: https://minecraft.wiki/w/Options
- S39 Microsoft, XINPUT_VIBRATION: https://learn.microsoft.com/en-us/windows/win32/api/xinput/ns-xinput-xinput_vibration
- S40 Android, Haptics design principles: https://developer.android.com/develop/ui/views/haptics/haptics-principles
- S41 Godot Engine.time_scale: https://docs.godotengine.org/en/stable/classes/class_engine.html
- S42 Godot Timer.ignore_time_scale: https://docs.godotengine.org/en/stable/classes/class_timer.html
- S43 Godot SceneTree.create_timer: https://docs.godotengine.org/en/stable/classes/class_scenetree.html
- S44 Godot Tween.set_ignore_time_scale: https://docs.godotengine.org/en/stable/classes/class_tween.html
- S45 Godot AudioServer.playback_speed_scale: https://docs.godotengine.org/en/stable/classes/class_audioserver.html
- S46 Godot Camera3D (fov, h_offset, v_offset): https://docs.godotengine.org/en/stable/classes/class_camera3d.html
- S47 Godot Input.start_joy_vibration: https://docs.godotengine.org/en/stable/classes/class_input.html
- S48 Godot, Controllers, gamepads and joysticks: https://docs.godotengine.org/en/stable/tutorials/inputs/controllers_gamepads_joysticks.html
- S49 Godot GPUParticles3D: https://docs.godotengine.org/en/stable/classes/class_gpuparticles3d.html
- S50 Godot issue #81429: https://github.com/godotengine/godot/issues/81429
- S51 Godot Decal: https://docs.godotengine.org/en/stable/classes/class_decal.html · ProjectSettings `rendering/limits/cluster_builder/max_clustered_elements`: https://docs.godotengine.org/en/stable/classes/class_projectsettings.html
- S52 Godot AudioEffectCompressor: https://docs.godotengine.org/en/stable/classes/class_audioeffectcompressor.html
- S53 Godot AudioStreamRandomizer: https://docs.godotengine.org/en/stable/classes/class_audiostreamrandomizer.html
- S54 Godot AudioStreamSynchronized: https://docs.godotengine.org/en/stable/classes/class_audiostreamsynchronized.html · AudioStreamInteractive: https://docs.godotengine.org/en/stable/classes/class_audiostreaminteractive.html
- S55 Godot AnimationNodeTimeScale: https://docs.godotengine.org/en/stable/classes/class_animationnodetimescale.html
- S56 Godot, The Compositor: https://docs.godotengine.org/en/stable/tutorials/rendering/compositor.html
- S57 Godot, Custom post-processing: https://docs.godotengine.org/en/stable/tutorials/shaders/custom_postprocessing.html · Advanced post-processing: https://docs.godotengine.org/en/stable/tutorials/shaders/advanced_postprocessing.html
- S58 Godot per-instance uniforms: https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/shading_language.html · GeometryInstance3D: https://docs.godotengine.org/en/stable/classes/class_geometryinstance3d.html
- S59 Godot Label3D: https://docs.godotengine.org/en/stable/classes/class_label3d.html
- S60 Godot AudioStreamPlayer3D: https://docs.godotengine.org/en/stable/classes/class_audiostreamplayer3d.html
- S61 Godot PhysicalBoneSimulator3D: https://docs.godotengine.org/en/stable/classes/class_physicalbonesimulator3d.html · SkeletonModifier3D: https://docs.godotengine.org/en/stable/classes/class_skeletonmodifier3d.html
- S62 Godot Environment.adjustment_saturation: https://docs.godotengine.org/en/stable/classes/class_environment.html
- S63 Godot 4.7 release notes: https://godotengine.org/releases/4.7/
- S64 KidsCanCode, Floating combat text: https://kidscancode.org/godot_recipes/4.x/ui/floating_text/index.html
- S65 Sakurai, *Hit Marks [Effects]*: https://www.youtube.com/watch?v=8_muiV-JGuc
- S66 Godot FastNoiseLite: https://docs.godotengine.org/en/stable/classes/class_fastnoiselite.html
- S67 Infil, Fighting Game Glossary: Hitstop: https://glossary.infil.net/?t=Hitstop
- S68 Godot Node.process_mode: https://docs.godotengine.org/en/stable/classes/class_node.html
- S69 Godot AnimationPlayer.speed_scale: https://docs.godotengine.org/en/stable/classes/class_animationplayer.html
- S70 Godot AudioEffectFilter.cutoff_hz: https://docs.godotengine.org/en/stable/classes/class_audioeffectfilter.html
