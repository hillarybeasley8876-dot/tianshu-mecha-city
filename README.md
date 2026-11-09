# 天枢 TIANSHU — MECHA CITY

A playable demo of one vertical district of the future megacity 云阙 YUNQUE: a 16-metre mech drops into
the Plaza, tears down three Hive Spires while a 90-metre Brood Titan walks the skyline, and finishes the
colossus across the Spire Plaza at storm light. Built with Godot 4.7 on Metal.

---

## Requirements

- **macOS 11 or newer**, Apple Silicon or Intel — the app is a **universal** binary (`lipo -archs` reports
  `x86_64 arm64`).
- **Metal**. There is no Vulkan/OpenGL fallback; the renderer is Forward+ on Metal.
- About 600 MB of disk for the app.

## Running the app

1. Move `TIANSHU.app` anywhere you like (it is self-contained; keep `README.md` and
   `THIRD_PARTY_LICENSES.txt` beside it if you want them).
2. **The first launch needs one extra step.** The app is *ad-hoc signed*, not notarized, so Gatekeeper
   refuses it the first time. Either:
   - open **System Settings › Privacy & Security**, scroll to the line that says TIANSHU was blocked, and
     press **Open Anyway**; or
   - run this once in Terminal:

     ```sh
     xattr -dr com.apple.quarantine TIANSHU.app
     ```

   After that it opens normally, by double-click or `open TIANSHU.app`.
3. The title screen starts the demo. **Esc** pauses, **F11** toggles fullscreen.

## Controls

Both schemes are complete and independent — every verb is reachable from the keyboard and from a
gamepad. Verb names are the ones the game uses.

**On a gamepad, `RB` is a pure shift layer** — it has no verb of its own, so nothing ever lifts your left
thumb off the stick. Hold `RB` and the four face buttons become the four skills in the shifted column
below; a face button pressed while `RB` is down keeps its shifted verb until *that button* is released,
whatever `RB` does meanwhile.

| Verb | Keyboard + mouse | Gamepad | Tap / hold |
|---|---|---|---|
| Move | `W` `A` `S` `D` | `LS` | — |
| Look | `Mouse` | `RS` | — |
| Fire | `LMB` | `RT` | tap = shot; hold = charged shot. On the gatling, hold to fire and press again on the vent mark to vent |
| Aim / zoom (ADS) | `RMB` | `LT` | hold |
| Jump / hover / flight | `Space` | `A` | tap = jump; hold = ascend and hover; **double-tap in the air (within 0.30 s) = flight mode** |
| Descend (in flight) | `Ctrl` | `B` | hold while flying |
| Dash / boost | `Shift` | `B` | tap = dash (i-frames); hold = sustained boost skate / glide |
| Assault boost | `Left Alt` | `L3` | toggle; a dash or a skid brake exits it |
| Melee | `F` | `X` | tap = combo; hold = charged slash; in the air, hold = plunge breaker |
| Guard | `Q` | `LB` | tap = perfect parry; hold = block; **hold 0.3 s = catch field** (catches and returns projectiles) |
| Hailstorm missiles | `1` `Mouse 4` | `RB+RT` | hold to paint up to 12 locks, release to fire the salvo |
| Skyhook anchor | `E` | `Y` | press; a second press lets go of the line |
| Rift Step | `C` | `RB+B` | press |
| Corona Fins | `Z` | `RB+Y` | tap = send the six wing blades; **hold 0.35 s = Corona Ward** barrier |
| Shockcore Burst | `X` | `RB+X` | press |
| Undertow Well | `G` | `RB+A` | press |
| Swap primary | `Wheel ↓` `Wheel ↑` | `D-pad ↑` | tap (the gamepad fires it on release) |
| Reload | `R` | `D-pad ↑` | hold 0.25 s |
| Zenith Overdrive | `V` | `L3+R3` | hold 0.25 s to ignite (needs a full OD ring) |
| Zenith Lance | `V` | `L3+R3` | **press again while Overdrive is running** (or while it is igniting) for the Lance finale |
| Lock-on toggle | `Tab` `MMB` | `R3` | press |
| Lock switch | `Mouse` | `D-pad ←` `D-pad →` | flick the mouse, or tap the D-pad |
| Camera 1st / 3rd person | `B` | `D-pad ↓` `View` | press |
| Pause | `Esc` | `Menu` | press |
| Fullscreen | `F11` | — | press |
| Debug input quad | `F3` | — | press; shows a square that flips on the frame an input lands (latency measurement) |

Timings worth knowing: double-tap flight 0.30 s, reload hold 0.25 s, catch field 0.3 s, ward hold
0.35 s, Overdrive ignition hold 0.25 s, and the `L3`+`R3` chord must be pressed within 4 frames.

## Running from source

The project is a normal Godot 4.7 project; `game/` is the project root.

```sh
tools/godot.sh play          # launch it
tools/godot.sh check         # import + compile every script, scene and shader
tools/godot.sh test res://core/tests/test_core_input.gd
```

- **Godot 4.7.2** is expected at `/opt/homebrew/bin/godot`. Point `GODOT=` at another build to override
  it: `GODOT=/path/to/godot tools/godot.sh play`.
- Every run goes through `tools/godot.sh`, which serialises imports and windowed runs machine-wide. Each
  subcommand takes `--timeout=<s>` for long runs, e.g.
  `tools/godot.sh drive --timeline=res://core/tests/pad_atom.json --timeout=600`.
- Blender work uses `tools/blender.sh` (Blender 5.2 at `/Applications/Blender.app`, override with
  `BLENDER=`).

## Credits and licences

- **In-game:** the title screen's **CREDITS** page lists every sound, music and texture source with its
  licence, and the **开源许可 / LICENCES** page carries the full text of the licences the shipped assets
  are under.
- **Next to the app:** `THIRD_PARTY_LICENSES.txt` holds the same third-party licence texts in plain text.
- **In the repository:** `build/THIRD_PARTY_LICENSES.txt` is regenerated by the export step.

Audio is CC0 from Kenney, OpenGameArt and the artists credited in `art/audio_src/*/oga_sources.json`;
textures are CC0 from Poly Haven and ambientCG. The mech, the monsters and the city are original work
made for this demo. © 2026 erapi0neer.
