# 天枢 TIANSHU — MECHA CITY

A playable demo of one vertical district of the future megacity 云阙 YUNQUE: a 16-metre mech drops into
the Plaza, tears down three Hive Spires while a 90-metre Brood Titan walks the skyline, and finishes the
colossus across the Spire Plaza at storm light. Built with Godot 4.7 on Metal.

> 中文说明见下方 [中文版说明](#中文版说明)。

## Download / 下载

| | |
|---|---|
| **macOS build** | [Releases → v0.1 (TIANSHU.app)](https://github.com/hillarybeasley8876-dot/tianshu-mecha-city/releases) — universal binary, ad-hoc signed |
| **Source** | this repository, `game/` is the Godot project root |
| **Trailer** | 预告片 v2 (1080p) |

The demo needs **macOS 11+** and **Metal**; there is no Vulkan/OpenGL fallback because the renderer is
Forward+ on Metal. The app is ad-hoc signed, so the first launch needs one extra step — see
[Running the app](#running-the-app).

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

---

## 中文版说明

**天枢 TIANSHU — 云阙 MECHA CITY**：未来巨型都市「云阙 YUNQUE」一个纵向街区的可玩 Demo。16 米机甲空降
广场，在 90 米「育巢泰坦」巡视天际线的同时拆掉三座巢塔，最终在风暴光里终结巨兽。Godot 4.7 + Metal，
Forward+ 渲染。

### 系统要求

- **macOS 11 及以上**，Apple Silicon 或 Intel 均可（通用二进制，`lipo -archs` 显示 `x86_64 arm64`）。
- 必须支持 **Metal**：渲染器是 Metal 上的 Forward+，没有 Vulkan / OpenGL 回退。
- 约 600 MB 磁盘空间。

### 运行

1. 把 `TIANSHU.app` 拖到任意位置即可（自包含；`README.md` 与 `THIRD_PARTY_LICENSES.txt` 可放在旁边）。
2. **首次启动需要一步操作**：应用是 ad-hoc 签名、未公证，Gatekeeper 首次会拦截。二选一：
   - 打开 **系统设置 › 隐私与安全性**，找到被拦截的 TIANSHU，点 **仍要打开**；
   - 或在终端执行一次：

     ```sh
     xattr -dr com.apple.quarantine TIANSHU.app
     ```

3. 标题页开始演示。**Esc** 暂停，**F11** 全屏。

### 操作（键鼠 / 手柄）

| 动作 | 键鼠 | 手柄 |
|---|---|---|
| 移动 | `W` `A` `S` `D` | `LS` |
| 视角 | 鼠标 | `RS` |
| 射击 | 鼠标左键 | `RT`（点击=射击，按住=蓄力） |
| 瞄准（ADS） | 鼠标右键 | `LT`（按住） |
| 跳跃 / 悬停 / 飞行 | `Space` | `A`（点击=跳，按住=上升悬停，空中 0.30 s 内双击=飞行） |
| 下降（飞行中） | `Ctrl` | `B`（按住） |
| 冲刺 / 加速 | `Shift` | `B`（点击=冲刺有无敌帧，按住=持续加速滑行） |
| 近战 | `F` | `X`（点击=连段，按住=蓄力斩，空中按住=下劈） |
| 防御 | `Q` | `LB`（点击=完美弹反，按住=格挡，按住 0.3 s=接球力场） |
| 暴雨导弹 | `1` `鼠标侧键4` | `RB+RT`（按住锁定最多 12 个目标，松开齐射） |
| 天钩锚点 | `E` | `Y`（再按一次松手） |
| 裂步 / 冕羽 / 震核 / 暗涌 | `C` / `Z` / `X` / `G` | `RB+B` / `RB+Y` / `RB+X` / `RB+A` |
| 换主武器 | 滚轮 ↓ / ↑ | `D-pad ↑` |
| 换弹 | `R` | `D-pad ↑`（按住 0.25 s） |
| 天顶超载 / 天顶之矛 | `V` | `L3+R3`（超载中再按=天顶之矛） |
| 锁定切换 | `Tab` `鼠标中键` | `R3` |
| 一 / 三人称视角 | `B` | `D-pad ↓` / `View` |

### 从源码运行

`game/` 是 Godot 工程根目录：

```sh
tools/godot.sh play          # 运行
tools/godot.sh check         # 导入并编译全部脚本、场景与着色器
tools/godot.sh test res://core/tests/test_core_input.gd
```

需要 **Godot 4.7.2**（默认路径 `/opt/homebrew/bin/godot`，可用 `GODOT=` 覆盖）。Blender 相关工作走
`tools/blender.sh`（Blender 5.2）。

### 素材许可

音频为 CC0（Kenney / OpenGameArt 等，来源见 `art/audio_src/*/oga_sources.json`），贴图为 CC0
（Poly Haven / ambientCG）。机甲、怪物与城市均为本 Demo 原创。第三方许可全文见仓库根目录的
`THIRD_PARTY_LICENSES.txt`，游戏内「开源许可 / LICENCES」页亦有完整文本。

