"""Cockpit AI voice lines: minimax speech through the internal ys-api, then radio processing.

    tools/sfx/run.sh voice.py [--limit N] [--reprocess]

Raw MP3 downloads land in art/audio_src/voice/ (git-ignored); only the processed OGGs in
game/audio/voice/ are committed. Lines are Chinese with a short English tag, per the brief.
The output is AI-generated audio and is labelled as such in game/audio/CREDITS_AUDIO.md.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

import numpy as np
import soundfile as sf

import dsp

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "art" / "audio_src" / "voice"
OUT = ROOT / "game" / "audio" / "voice"
API = "https://ys-api.xaminim.com/api/minimax_tts"
VOICE_ID = "female-shaonv"
VOICE_SETTING = {"voice_id": VOICE_ID, "speed": 1.05, "vol": 1.0, "pitch": -1, "emotion": "calm"}
VOICE_MODIFY = {"sound_effects": "robotic"}

# id -> (chinese line, english tag, priority). Priority feeds Audio.voice() at the call site.
LINES: dict[str, tuple[str, str]] = {
    "ai_boot": ("天枢系统启动", "TIANSHU online"),
    "ai_systems_online": ("全部系统正常", "Systems online"),
    "ai_target_locked": ("锁定目标", "Target locked"),
    "ai_target_lost": ("目标丢失", "Target lost"),
    "ai_energy_low": ("能量不足", "Energy low"),
    "ai_energy_restored": ("能量恢复", "Energy restored"),
    "ai_armor_75": ("装甲受损", "Armour damaged"),
    "ai_armor_50": ("装甲剩余一半", "Armour fifty percent"),
    "ai_armor_25": ("装甲严重受损", "Armour critical"),
    "ai_armor_critical": ("警告：装甲临界", "Warning: armour critical"),
    "ai_missile_alert": ("导弹来袭", "Missile alert"),
    "ai_incoming_unblockable": ("警告：无法格挡", "Warning: unblockable"),
    "ai_overdrive_ready": ("超载就绪", "Overdrive ready"),
    "ai_overdrive_engaged": ("超载启动", "Overdrive engaged"),
    "ai_skill_ready": ("技能就绪", "Skill ready"),
    "ai_parry_perfect": ("完美格挡", "Perfect parry"),
    "ai_combo_rank": ("连击提升", "Combo up"),
    "ai_target_staggered": ("目标失衡", "Target staggered"),
    "ai_execution_ready": ("可处决", "Execution ready"),
    "ai_kill_confirm": ("目标已摧毁", "Target destroyed"),
    "ai_multi_kill": ("多重击杀", "Multi kill"),
    "ai_gatling_heat": ("机炮过热", "Gatling heat"),
    "ai_vent_now": ("立即排热", "Vent now"),
    "ai_reload": ("更换弹药", "Reloading"),
    "ai_ammo_low": ("弹药不足", "Ammo low"),
    "ai_spire_down_1": ("蚀巢已摧毁 一", "Spire down, one of three"),
    "ai_spire_down_2": ("蚀巢已摧毁 二", "Spire down, two of three"),
    "ai_spire_down_3": ("蚀巢全部摧毁", "All spires down"),
    "ai_district_clear": ("区域安全", "District clear"),
    "ai_titan_approach": ("警告：巨型生命体接近", "Warning: titan approaching"),
    "ai_titan_roar": ("巢母咆哮", "Titan roar"),
    "ai_boss_phase_2": ("巢母进入第二阶段", "Boss phase two"),
    "ai_boss_phase_3": ("巢母进入最终阶段", "Boss final phase"),
    "ai_boss_staggered": ("巢母失衡", "Boss staggered"),
    "ai_boss_core_exposed": ("核心暴露", "Core exposed"),
    "ai_ultimate_ready": ("光枪就绪", "Lance ready"),
    "ai_lance_fired": ("光枪发射", "Lance fired"),
    "ai_objective_new": ("新任务", "New objective"),
    "ai_objective_done": ("任务完成", "Objective complete"),
    "ai_enemies_remaining": ("侦测到敌群", "Hostiles detected"),
    "ai_rift_unstable": ("裂隙不稳定", "Rift unstable"),
    "ai_barrier_down": ("屏障失效", "Barrier down"),
    "ai_drone_link": ("无人机连接", "Drones linked"),
    "ai_anchor_locked": ("锚点锁定", "Anchor locked"),
    "ai_well_charged": ("引井充能完成", "Well charged"),
    "ai_victory": ("任务成功", "Mission complete"),
    "ai_failure": ("机体损毁", "Unit destroyed"),
}


def synthesize(line: str, out_path: Path) -> bool:
    """One API call; the platform answers with a CDN URL to an MP3."""
    payload = json.dumps({"text": line, "voice_setting": VOICE_SETTING,
                          "voice_modify": VOICE_MODIFY}).encode()
    request = urllib.request.Request(API, data=payload,
                                     headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=90) as response:
        body = json.loads(response.read().decode())
    if not body.get("success") or not body.get("data"):
        print(f"  ! api error for {out_path.name}: {str(body)[:160]}")
        return False
    with urllib.request.urlopen(body["data"], timeout=120) as audio:
        out_path.write_bytes(audio.read())
    return True


def decode(path: Path) -> tuple[np.ndarray, int]:
    """MP3 -> mono float64 at the bank sample rate."""
    wav = path.with_suffix(".wav")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(path), "-ac", "1",
                    "-ar", str(dsp.SR), str(wav)], check=True)
    data, rate = sf.read(str(wav), always_2d=False)
    wav.unlink()
    return data.astype(np.float64), rate


def trim_silence(x: np.ndarray, head_s: float = 0.04, tail_s: float = 0.22) -> np.ndarray:
    """The API pads each clip with silence; a callout that starts 0.8 s late reads as lag, not calm."""
    envelope = np.abs(x)
    loud = np.nonzero(envelope > 0.02 * envelope.max())[0]
    if loud.size == 0:
        return x
    start = max(int(loud[0]) - dsp.frames(head_s), 0)
    end = min(int(loud[-1]) + dsp.frames(tail_s), x.size)
    return x[start:end]


def radio_process(x: np.ndarray) -> np.ndarray:
    """Cockpit radio chain: band limit, 55 Hz ring mod, tanh drive, hiss floor, -3 dBTP.

    The ring modulation is the 'machine-in-flesh' trick from the dossier's creature chain (§1.4)
    reused here at low depth: it is what makes the voice read as synthetic rather than human.
    """
    x = trim_silence(x)
    n = x.size
    t = np.arange(n) / dsp.SR
    x = dsp.highpass(x, 190.0, 2)
    x = dsp.lowpass(x, 5200.0, 2)
    ring = 1.0 - 0.22 * (1.0 - np.cos(2 * np.pi * 55.0 * t))
    x = x * ring
    x = np.tanh(1.8 * x) / np.tanh(1.8)
    hiss = dsp.noise_band(n, 600.0, 4000.0, np.random.default_rng(7)) * 0.004
    tail = dsp.frames(0.12)
    squelch = np.zeros(n)
    squelch[:tail] = hiss[:tail]
    squelch[-tail:] = hiss[-tail:]
    x = x + squelch
    x = np.concatenate([np.zeros(dsp.frames(0.03)), x, np.zeros(dsp.frames(0.12))])
    return dsp.finalize(x, -3.0, fade_out=0.05)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--reprocess", action="store_true")
    args = parser.parse_args()
    RAW.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    ids = list(LINES)
    if args.limit:
        ids = ids[: args.limit]
    written = 0
    for line_id in ids:
        text, tag = LINES[line_id]
        raw = RAW / f"{line_id}.mp3"
        if not raw.exists() and not args.reprocess:
            if not synthesize(text, raw):
                continue
            time.sleep(1.2)   # be polite to the shared internal endpoint
        if not raw.exists():
            print(f"  ! no raw audio for {line_id}")
            continue
        audio, _ = decode(raw)
        processed = radio_process(audio)
        dsp.write_ogg(OUT / f"{line_id}.ogg", processed)
        written += 1
        print(f"  {line_id:22s} {processed.size / dsp.SR:4.2f}s  {text}  ({tag})")
    print(f"{written}/{len(ids)} voice lines -> {OUT.relative_to(ROOT)}")
    return 0 if written else 1


if __name__ == "__main__":
    sys.exit(main())
