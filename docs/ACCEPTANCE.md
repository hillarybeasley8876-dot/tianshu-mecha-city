# ACCEPTANCE — the demo is done when all of this holds (lead runs every gate itself)

## 1. Flow (E2E)
- `--skip-menu` run and a full title→drop-in→tutorial→3 spires→catapult→boss (3 phases)→victory run complete with
  0 engine errors and 0 script errors (scripted timeline + `--god` for the full run; a real play-through by the lead
  with keyboard+mouse AND a gamepad for the feel gates).
- Death and respawn at every checkpoint (start, each spire, each boss phase) work.

## 2. Feel (real time, never judged from movies alone)
- Every SPEC §3 verb reachable on KB+M and pad (PadInput tests + a pad-only 30 s combat atom: the left thumb never
  leaves the stick > 0.3 s).
- Perfect dodge → witch time: player at full speed, world at 0.3×, inputs unaffected.
- Every FEEL row fires (feel gallery) and reads at combat distance; swarm kills never freeze the world.
- Press-to-photon ≤ 50 ms on the 120 Hz panel (240 fps phone film, debug input quad).

## 3. Look
- Vistas V1–V8 sit next to the key art and read as the same world (lead sheet, honest notes).
- Hero, monsters, props: lit close-ups from 4 angles + top; no fused/broken geometry; textures right (asset QA lessons).
- First-person cockpit ≤ 18 % coverage, readable glass HUD.

## 4. Performance (M1 Max, 1600×900, high, real time with `--frametimes`, vsync on, max_fps 60)
- Busiest spire fight and the boss: p99 frame ≤ 18 ms, hitches > 25 ms ≤ 1 per minute, draw calls ≤ 3,500.
- Pacing: ≥ 99 % of frames within 16.67 ± 1.5 ms; no shader-compile hitches after the first 10 s.

## 5. Packaging
- `build/TIANSHU.app` (macOS universal, ad-hoc signed) boots to the title on a clean launch; README with
  controls; credits screen lists CC-BY audio and labels AI-generated content (Tripo models, MiniMax voice).
