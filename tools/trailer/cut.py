#!/usr/bin/env python3
"""Build the trailer edit from game/trailer/shots.json with ffmpeg.

    tools/trailer/cut.py                       # the whole cut -> captures/trailer/TIANSHU_trailer_v1.mp4
    tools/trailer/cut.py --only s03_drop       # one shot, for a quick look
    tools/trailer/cut.py --dry-run             # print the ffmpeg plan, render nothing

Pipeline: every shot is normalised (trim, retime, 1920x1080, 60 fps, yuv420p) into tmp/, then the
normalised clips are joined with the transition each shot declares, the game's own audio is laid under
a music bed (ducked), titles are composited from PIL-rendered PNGs and the whole thing is loudness
normalised to the deliverable's -14 LUFS / -1 dBTP.

This ffmpeg is built WITHOUT `drawtext` or libass, so every piece of text is rendered by PIL
(tools/trailer/titles.py) and overlaid as a PNG.
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from titles import Title, lower_third, render_card, render_titles  # noqa: E402

MUSIC_DIR = ROOT / "game/audio/music"
STINGER_DIR = MUSIC_DIR / "stingers"
## A step whose output has not grown for this long is hung, not slow. The 11-06 and 11-09 cuts both
## lost an hour to an ffmpeg that spun at ~175 % CPU while its output file stayed frozen, and the
## `subprocess.run` this used to be could not see it: the process was alive, so the cut waited.
STALL_S = 120.0
POLL_S = 2.0


def run(cmd: list[str], what: str, grows: Path | None = None) -> None:
    """Run one ffmpeg step, and fail loudly instead of hanging.

    `grows` is the file the step writes. When it is given, the step is watched: if the file has not
    grown for STALL_S seconds the process is killed and the cut dies with a readable message, rather
    than blocking forever on a filter graph that has deadlocked.
    """
    if grows is None:
        proc = subprocess.run(cmd, capture_output=True, text=True)
        if proc.returncode != 0:
            sys.stderr.write(proc.stderr[-4000:] + "\n")
            raise SystemExit(f"cut: {what} failed (ffmpeg exit {proc.returncode})")
        return
    proc = subprocess.Popen(cmd, stderr=subprocess.PIPE, stdout=subprocess.DEVNULL, text=True)
    last_size = -1
    last_change = time.monotonic()
    while proc.poll() is None:
        time.sleep(POLL_S)
        size = grows.stat().st_size if grows.exists() else -1
        now = time.monotonic()
        if size != last_size:
            last_size = size
            last_change = now
        elif now - last_change > STALL_S:
            proc.kill()
            proc.wait(timeout=30)
            raise SystemExit(
                f"cut: {what} STALLED — {grows.name} has not grown for {STALL_S:.0f} s "
                f"(stuck at {last_size} bytes). ffmpeg is spinning without writing; killed rather "
                f"than waiting. Command: {' '.join(cmd[:6])} …")
    err = proc.stderr.read() if proc.stderr else ""
    if proc.returncode != 0:
        sys.stderr.write((err or "")[-4000:] + "\n")
        raise SystemExit(f"cut: {what} failed (ffmpeg exit {proc.returncode})")


def probe_duration(path: Path) -> float:
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                          "-of", "csv=p=0", str(path)], capture_output=True, text=True, check=True)
    try:
        return float(out.stdout.strip())
    except ValueError:
        # A take that is still being written (or a container ffprobe cannot read) answers "N/A".
        return 0.0


def load_spec(path: Path) -> dict:
    spec = json.loads(path.read_text())
    for key in ("output", "shots"):
        if key not in spec:
            raise SystemExit(f"cut: {path} has no '{key}'")
    return spec


def card_clip(card: dict, bg: Path | None, work: Path, index: int, size: tuple[int, int],
              fps: int, dry: bool) -> tuple[dict, Path]:
    """A chapter card as a real clip: a blurred still from the chapter behind the title, held `dur`."""
    dur = float(card.get("dur", 1.5))
    png = render_card([(str(l[0]), str(l[1])) for l in card["lines"]], bg,
                      work / "cards" / f"card_{index:02d}.png",
                      blur=int(card.get("blur", 14)), darken=float(card.get("darken", 0.42)))
    dst = work / f"card_{index:02d}.mkv"
    w, h = size
    zoom = float(card.get("zoom", 0.06))
    frames = max(int(dur * fps), 1)
    cmd = ["ffmpeg", "-v", "error", "-y", "-loop", "1", "-t", f"{dur:.3f}", "-i", str(png),
           "-f", "lavfi", "-t", f"{dur:.3f}", "-i", "anullsrc=r=48000:cl=stereo",
           "-filter_complex",
           f"[0:v]scale={w * 2}:{h * 2},"
           f"zoompan=z='1+{zoom}*on/{frames}':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)'"
           f":d={frames}:s={w}x{h}:fps={fps},setsar=1,format=yuv420p[v]",
           "-map", "[v]", "-map", "1:a", "-c:v", "libx264", "-crf", "10", "-preset", "veryfast",
           "-c:a", "pcm_s16le", "-shortest", str(dst)]
    if not dry:
        run(cmd, f"card {index}", grows=dst)
    return {"id": f"card{index:02d}", "transition": "cut", "in": 0.0, "out": dur}, dst


def grab_frame(clip: Path, at: float, out: Path) -> Path:
    """One frame out of a normalised clip — the background a chapter card is built on."""
    out.parent.mkdir(parents=True, exist_ok=True)
    run(["ffmpeg", "-v", "error", "-y", "-ss", f"{max(at, 0.0):.3f}", "-i", str(clip),
         "-frames:v", "1", str(out)], f"card background from {clip.name}")
    return out


def build_items(shots: list[dict], clips: list[Path], spec: dict, work: Path,
                dry: bool) -> tuple[list[dict], list[Path]]:
    """Weave the chapter cards into the shot list, in the order the spec's `cards` declare.

    A card names the shot it opens (`before`), so the reel reads CHAPTER CARD -> that chapter's first
    segment without the caller having to know where the chapter boundary landed on the timeline.
    """
    cards = spec.get("cards", [])
    size = tuple(spec.get("size", [1920, 1080]))
    fps = int(spec.get("fps", 60))
    items: list[dict] = []
    out_clips: list[Path] = []
    made = 0
    for i, shot in enumerate(shots):
        for card in cards:
            if str(card.get("before", "")) != shot["id"]:
                continue
            bg = None
            if not dry:
                bg = grab_frame(clips[i], probe_duration(clips[i]) * float(card.get("bg_at", 0.5)),
                                work / "cards" / f"bg_{made:02d}.png")
            item, clip = card_clip(card, bg, work, made, size, fps, dry)
            items.append(item)
            out_clips.append(clip)
            made += 1
        items.append(shot)
        out_clips.append(clips[i])
    return items, out_clips


def source_of(shot: dict, spec: dict) -> Path:
    """The take a shot is cut from (`take`, defaulting to its own id), under the spec's `dir`.

    `--takes=<dir>` overrides it for one run, which is how the v2 re-cut reads the lead's r2b takes
    out of its own worktree without copying 3 GB of .avi into this tree.
    """
    src = shot.get("src") or f"{spec.get('dir', 'captures/trailer/shots')}/{shot.get('take', shot['id'])}.avi"
    p = Path(src)
    return p if p.is_absolute() else ROOT / p


def has_audio(path: Path) -> bool:
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "a", "-show_entries",
                          "stream=codec_type", "-of", "csv=p=0", str(path)],
                         capture_output=True, text=True)
    return "audio" in out.stdout


def normalise(shot: dict, src: Path, dst: Path, size: tuple[int, int], fps: int,
              grade: str, dry: bool) -> None:
    """Trim to in/out, retime, letterbox to the deliverable size, grade, force the frame rate."""
    a, b = float(shot.get("in", 0.0)), float(shot["out"])
    speed = float(shot.get("speed", 1.0))
    w, h = size
    v = (f"[0:v]trim=start={a}:end={b},setpts=PTS-STARTPTS"
         + (f",setpts=PTS/{speed}" if speed != 1.0 else "")
         + f",scale={w}:{h}:force_original_aspect_ratio=decrease"
         f",pad={w}:{h}:(ow-iw)/2:(oh-ih)/2:color=black"
         + (f",{grade}" if grade else "")
         + f",fps={fps},setsar=1,setrange=limited,format=yuv420p[v]")
    if has_audio(src):
        atrim = f"[0:a]atrim=start={a}:end={b},asetpts=PTS-STARTPTS"
    else:
        atrim = f"anullsrc=r=48000:cl=stereo:d={b - a},asetpts=PTS-STARTPTS"
    a_chain = atrim + (f",atempo={speed}" if speed != 1.0 else "") + \
        ",aresample=48000,aformat=sample_fmts=fltp:channel_layouts=stereo[a]"
    cmd = ["ffmpeg", "-v", "error", "-y", "-i", str(src), "-filter_complex", v + ";" + a_chain,
           "-map", "[v]", "-map", "[a]", "-c:v", "libx264", "-crf", "10", "-preset", "veryfast",
           "-c:a", "pcm_s16le", str(dst)]
    if dry:
        print("  " + " ".join(cmd))
        return
    run(cmd, f"normalise {shot['id']}", grows=dst)


def join_video(clips: list[Path], shots: list[dict], dry: bool) -> tuple[list[str], str, float]:
    """One filter chain: concat for a cut, xfade for a crossfade. Returns (parts, out label, length)."""
    parts: list[str] = []
    label = "[0:v]"
    lens = [(float(s["out"]) - float(s.get("in", 0.0))) / float(s.get("speed", 1.0)) for s in shots]
    if not dry:
        lens = [probe_duration(c) for c in clips]
    length = lens[0]
    for i in range(1, len(clips)):
        mode = str(shots[i - 1].get("transition", "cut"))
        nxt = f"[v{i}]"
        if mode == "xfade":
            d = float(shots[i - 1].get("xfade", 0.4))
            parts.append(f"{label}[{i}:v]xfade=transition=fade:duration={d}:offset={length - d:.4f}{nxt}")
            length += lens[i] - d
        else:
            parts.append(f"{label}[{i}:v]concat=n=2:v=1:a=0{nxt}")
            length += lens[i]
        label = nxt
    return parts, label, length


def extract_audio(clips: list[Path], work: Path) -> list[Path]:
    """Each clip's audio as its own WAV, one ffmpeg per clip.

    THE HANG THIS FIXES: the mix used to be ONE ffmpeg whose filter graph demuxed all 26 clips *and*
    the music at once, with `-vn` to drop the video. ffmpeg still opens and buffers every input's video
    stream to keep the graph fed, so a 26-input graph over 1080p60 h264 deadlocked: ~175 % CPU, output
    frozen, forever (the 11-06 and 11-09 cuts both lost an hour to it). Audio-only inputs have no video
    to interleave, so the mix is a graph over small WAVs instead of over the takes.
    """
    out: list[Path] = []
    adir = work / "audio"
    adir.mkdir(parents=True, exist_ok=True)
    for i, c in enumerate(clips):
        dst = adir / f"{i:03d}.wav"
        out.append(dst)
        if dst.exists() and dst.stat().st_size > 1024:
            continue
        run(["ffmpeg", "-v", "error", "-y", "-i", str(c), "-vn", "-c:a", "pcm_s16le",
             "-ar", "48000", "-ac", "2", str(dst)], f"audio extract {c.stem}", grows=dst)
    return out


def concat_audio(wavs: list[Path], work: Path) -> Path:
    """The game's own audio as ONE input, via the concat demuxer.

    With every transition a cut (which is what both reels use) the game audio is simply the clip
    audio laid end to end, so the mix does not need a 26-way concat filter at all -- it needs one
    file. A crossfade in the spec falls back to the per-clip filter graph instead.
    """
    lst = work / "sfx_list.txt"
    lst.write_text("".join(f"file '{w.resolve()}'\n" for w in wavs))
    dst = work / "sfx.wav"
    run(["ffmpeg", "-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", str(lst),
         "-c:a", "pcm_s16le", "-ar", "48000", "-ac", "2", str(dst)], "sfx concat", grows=dst)
    return dst


def join_audio(shots: list[dict]) -> tuple[list[str], str]:
    """The game's own audio, laid end to end with the same transitions as the picture."""
    parts: list[str] = []
    label = "[0:a]"
    for i in range(1, len(shots)):
        mode = str(shots[i - 1].get("transition", "cut"))
        nxt = f"[a{i}]"
        if mode == "xfade":
            parts.append(f"{label}[{i}:a]acrossfade=d={float(shots[i - 1].get('xfade', 0.4))}{nxt}")
        else:
            parts.append(f"{label}[{i}:a]concat=n=2:v=0:a=1{nxt}")
        label = nxt
    return parts, label


def music_inputs(spec: dict) -> tuple[list[Path], list[dict]]:
    """Every music bed segment and stinger, as (files, descriptors) in input order."""
    files: list[Path] = []
    descs: list[dict] = []
    for seg in spec.get("music", []):
        files.append(MUSIC_DIR / f"{seg['clip']}_mix.ogg")
        descs.append(seg)
    for st in spec.get("stingers", []):
        files.append(STINGER_DIR / f"{st['clip']}.ogg")
        descs.append(st)
    return files, descs


def music_chain(descs: list[dict], first: int, sfx_label: str, sfx_db: float) -> tuple[list[str], str]:
    """Music segments and stingers delayed onto the cut's timeline, mixed with the ducked game audio."""
    parts: list[str] = []
    labels: list[str] = []
    for j, d in enumerate(descs):
        delay = int(float(d["at"]) * 1000)
        src = f"[{first + j}:a]"
        filters: list[str] = []
        if "dur" in d:
            start = float(d.get("from", 0.0))
            filters += [f"atrim=start={start}:end={start + float(d['dur'])}", "asetpts=PTS-STARTPTS"]
        filters += ["aresample=48000", "aformat=sample_fmts=fltp:channel_layouts=stereo",
                    f"adelay={delay}|{delay}", f"volume={float(d.get('gain_db', 0.0))}dB"]
        parts.append(src + ",".join(filters) + f"[m{j}]")
        labels.append(f"[m{j}]")
    parts.append("".join(labels) + f"amix=inputs={len(labels)}:normalize=0:dropout_transition=0[bed]")
    parts.append(f"{sfx_label}volume={sfx_db}dB[sfx]")
    parts.append("[bed][sfx]amix=inputs=2:normalize=0:dropout_transition=0[mix]")
    return parts, "[mix]"


def title_chain(plates: list[tuple[Title, Path]], first: int, label: str) -> tuple[list[str], str]:
    """Composite each still plate over the joined picture for its window, fading on the alpha."""
    parts: list[str] = []
    for j, (t, _png) in enumerate(plates):
        idx = first + j
        lab = f"[t{j}]"
        fade = min(t.fade, t.dur / 2.0)
        parts.append(f"[{idx}:v]format=rgba,fade=t=in:st=0:d={fade}:alpha=1,"
                     f"fade=t=out:st={t.dur - fade}:d={fade}:alpha=1,"
                     f"setpts=PTS-STARTPTS+{t.at}/TB{lab}")
        nxt = f"[vt{j}]"
        parts.append(f"{label}{lab}overlay=0:0:shortest=1"
                     f":enable='between(t,{t.at:.3f},{t.at + t.dur:.3f})'{nxt}")
        label = nxt
    return parts, label


def measure_loudness(bed: Path, lufs: float, tp: float) -> dict:
    """Pass 1 of loudnorm: the linear-mode measurement, so pass 2 does not pump."""
    proc = subprocess.run(
        ["ffmpeg", "-v", "info", "-i", str(bed), "-af",
         f"loudnorm=I={lufs}:TP={tp}:print_format=json", "-f", "null", "-"],
        capture_output=True, text=True)
    text = proc.stderr
    start = text.rfind("{")
    if start < 0:
        raise SystemExit("cut: loudnorm pass 1 produced no measurement")
    return json.loads(text[start:text.rfind("}") + 1])


def normalise_all(shots: list[dict], spec: dict, work: Path, dry: bool) -> list[Path]:
    """Trim/retime/letterbox every shot into a uniform intermediate clip."""
    size = tuple(spec.get("size", [1920, 1080]))
    fps = int(spec.get("fps", 60))
    grade = str(spec.get("grade", ""))
    clips: list[Path] = []
    for shot in shots:
        src = source_of(shot, spec)
        if not src.exists() and not dry:
            raise SystemExit(f"cut: {shot['id']} has no source {src} — run tools/trailer/render_all.sh")
        take = probe_duration(src) if src.exists() else float(shot["out"])
        if float(shot["out"]) > take + 0.05:
            print(f"cut: WARNING {shot['id']} asks for {shot['out']:.2f}s but {src.name} is only "
                  f"{take:.2f}s — the shot will be short and the music will drift")
        dst = work / f"{shot['id']}.mkv"
        normalise(shot, src, dst, size, fps, grade, dry)
        clips.append(dst)
    return clips


def shot_starts(shots: list[dict], clips: list[Path], dry: bool) -> dict[str, float]:
    """Where each shot starts on the cut's own timeline (titles are anchored to this)."""
    lens = [(float(s["out"]) - float(s.get("in", 0.0))) / float(s.get("speed", 1.0)) for s in shots]
    if not dry:
        lens = [probe_duration(c) for c in clips]
    starts: dict[str, float] = {}
    t = 0.0
    for i, shot in enumerate(shots):
        starts[shot["id"]] = t
        t += lens[i]
        if i < len(shots) - 1 and str(shot.get("transition", "cut")) == "xfade":
            t -= float(shot.get("xfade", 0.4))
    return starts


def plates_of(spec: dict, starts: dict[str, float]) -> list[Title]:
    """Titles are anchored to a shot (`"shot": id`, `at` relative to its first frame) or absolute.

    A shot may instead carry `"lower": {"label", "key", "detail"}` — the showcase reel's per-segment
    label — which is turned into the lower third here so the spec stays readable.
    """
    out: list[Title] = []
    for shot in spec.get("shots", []):
        low = shot.get("lower")
        if not low or shot["id"] not in starts:
            continue
        start = starts[shot["id"]]
        span = float(shot["out"]) - float(shot.get("in", 0.0))
        t = lower_third(str(low["label"]), str(low.get("key", "")), str(low.get("detail", "")))
        t.at = start + float(low.get("at", 0.35))
        t.dur = min(float(low.get("dur", span - 0.7)), start + span - t.at - 0.2)
        if t.dur > 0.2:
            out.append(t)
    for t in spec.get("titles", []):
        at = float(t["at"])
        if "shot" in t:
            if t["shot"] not in starts:
                continue
            at += starts[t["shot"]]
        out.append(Title(at=at, dur=float(t["dur"]),
                         lines=[(str(l[0]), str(l[1])) for l in t["lines"]],
                         fade=float(t.get("fade", 0.5)), y=int(t.get("y", -1)),
                         align=str(t.get("align", "center")), x=int(t.get("x", 960))))
    return out


def encode_only(shots: list[dict], spec: dict, work: Path, out: Path, keep: bool) -> int:
    """Redo the final encode from the intermediates a previous run left in tmp/trailer/cut."""
    video, wav = work / "picture.mkv", work / "mix.wav"
    for f in (video, wav):
        if not f.exists():
            raise SystemExit(f"cut: --encode-only needs {f} — run the full cut once with --keep")
    items: list[dict] = []
    clips: list[Path] = []
    made = 0
    for shot in shots:
        for card in spec.get("cards", []):
            if str(card.get("before", "")) != shot["id"]:
                continue
            dur = float(card.get("dur", 1.5))
            items.append({"id": f"card{made:02d}", "transition": "cut", "in": 0.0, "out": dur})
            clips.append(work / f"card_{made:02d}.mkv")
            made += 1
        items.append(shot)
        clips.append(work / f"{shot['id']}.mkv")
    missing = [c.name for c in clips if not c.exists()]
    if missing:
        raise SystemExit(f"cut: --encode-only is missing {len(missing)} clips: {missing[:4]}")
    length = sum(probe_duration(c) for c in clips)
    plates = render_titles(plates_of(spec, shot_starts(items, clips, False)), work / "titles")
    print(f"cut: encode-only over {len(clips)} clips, {length:.2f}s, {len(plates)} plates")
    return encode(video, wav, plates, out, spec, work, keep, length)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--spec", type=Path, default=ROOT / "game/trailer/shots.json")
    ap.add_argument("--out", type=Path, default=None)
    ap.add_argument("--takes", default="", help="override the spec's take directory for this run")
    ap.add_argument("--only", default="", help="comma-separated shot ids (a partial cut)")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--keep", action="store_true", help="keep the normalised clips in tmp/")
    ap.add_argument("--encode-only", action="store_true",
                    help="reuse tmp/trailer/cut (picture.mkv + mix.wav + clips) and redo only the "
                         "final encode — the join stages are the expensive half and they survive a "
                         "crash in the last one")
    args = ap.parse_args()

    spec = load_spec(args.spec)
    if args.takes:
        spec["dir"] = args.takes
    shots = spec["shots"]
    if args.only:
        wanted = args.only.split(",")
        shots = [s for s in shots if s["id"] in wanted]
        if not shots:
            raise SystemExit(f"cut: no shot matches --only={args.only}")
    out = args.out or (ROOT / spec["output"])
    work = ROOT / "tmp/trailer/cut"
    work.mkdir(parents=True, exist_ok=True)

    if args.encode_only:
        return encode_only(shots, spec, work, out, args.keep)
    clips = normalise_all(shots, spec, work, args.dry_run)
    items, clips = build_items(shots, clips, spec, work, args.dry_run)
    vparts, vlabel, length = join_video(clips, items, args.dry_run)

    music_files, music_descs = music_inputs(spec)

    # The game audio becomes ONE input when every transition is a cut (which is what both reels use):
    # a 26-input graph over the takes is what deadlocked. A crossfade anywhere falls back to the
    # per-clip concat filter, now over audio-only WAVs rather than over the video.
    crossfade = any(str(s.get("transition", "cut")) == "xfade" for s in items)
    aparts: list[str] = []
    if not args.dry_run:
        wavs = extract_audio(clips, work)
    else:
        wavs = clips
    if crossfade:
        aparts, alabel = join_audio(items)
        sfx_inputs: list[str] = []
        for w in wavs:
            sfx_inputs += ["-i", str(w)]
        sfx_first = len(wavs)
    else:
        alabel = "[0:a]"
        if args.dry_run:
            sfx_inputs = ["-i", "<sfx.wav>"]
        else:
            sfx_inputs = ["-i", str(concat_audio(wavs, work))]
        sfx_first = 1
    mparts, mlabel = music_chain(music_descs, sfx_first, alabel,
                                 float(spec.get("sfx_db", -6.0)))

    plates = render_titles(plates_of(spec, shot_starts(items, clips, args.dry_run)),
                           work / "titles")

    agraph = ";".join(aparts + mparts) + f";{mlabel}atrim=end={length:.3f},asetpts=PTS-STARTPTS[mixlen]"
    clip_inputs: list[str] = []
    for c in clips:
        clip_inputs += ["-i", str(c)]
    music_inputs_args: list[str] = []
    for m in music_files:
        music_inputs_args += ["-stream_loop", "-1", "-i", str(m)]

    if args.dry_run:
        print("ffmpeg " + " ".join(clip_inputs) + " -filter_complex " + ";".join(vparts))
        print("ffmpeg " + " ".join(sfx_inputs + music_inputs_args) + " -filter_complex " + agraph)
        return 0
    # Small passes instead of one graph over 26 takes: join the picture, mix the audio over WAVs, and
    # mux. Every one of them is watched for a stalled output file (see run()).
    video = work / "picture.mkv"
    run(["ffmpeg", "-v", "error", "-y"] + clip_inputs +
        ["-filter_complex", ";".join(vparts), "-map", vlabel, "-an",
         "-c:v", "libx264", "-crf", "10", "-preset", "veryfast", str(video)],
        "picture join", grows=video)
    wav = work / "mix.wav"
    run(["ffmpeg", "-v", "error", "-y"] + sfx_inputs + music_inputs_args +
        ["-filter_complex", agraph, "-map", "[mixlen]",
         "-c:a", "pcm_s16le", "-ar", "48000", str(wav)], "audio mix", grows=wav)
    return encode(video, wav, plates, out, spec, work, args.keep, length)


def encode(video: Path, wav: Path, plates: list[tuple[Title, Path]], out: Path, spec: dict,
           work: Path, keep: bool, length: float = 0.0) -> int:
    """Mux the joined picture and the mixed audio, composite the titles, normalise the loudness."""
    loud = spec.get("loudness", {})
    lufs, tp = float(loud.get("lufs", -14.0)), float(loud.get("tp", -1.0))
    fps = int(spec.get("fps", 60))
    m = measure_loudness(wav, lufs, tp)
    print(f"cut: mix measured I={m['input_i']} LUFS  TP={m['input_tp']} dBTP  "
          f"LRA={m['input_lra']}  thresh={m['input_thresh']}")
    norm = (f"loudnorm=I={lufs}:TP={tp}:measured_I={m['input_i']}:measured_TP={m['input_tp']}"
            f":measured_LRA={m['input_lra']}:measured_thresh={m['input_thresh']}:linear=true")
    # inputs: 0 = the joined picture, 1 = the mixed audio, 2.. = the title plates
    tparts, tlabel = title_chain(plates, 2, "[0:v]")
    graph = ";".join(tparts + [f"{tlabel}format=yuv420p[vout]"]) if plates else "[0:v]format=yuv420p[vout]"
    inputs: list[str] = ["-i", str(video), "-i", str(wav)]
    for _t, png in plates:
        inputs += ["-loop", "1", "-framerate", str(fps), "-i", str(png)]
    out.parent.mkdir(parents=True, exist_ok=True)
    run(["ffmpeg", "-v", "error", "-y"] + inputs +
        ["-filter_complex", graph + f";[1:a]{norm},aresample=48000[aout]",
         "-map", "[vout]", "-map", "[aout]"]
        + (["-t", f"{length:.3f}"] if length > 0 else []) + [
         "-c:v", "libx264", "-crf", str(int(spec.get("crf", 16))), "-preset", "medium",
         "-pix_fmt", "yuv420p", "-profile:v", "high", "-level", "4.2", "-r", str(fps),
         "-c:a", "aac", "-b:a", "320k", "-ar", "48000", "-movflags", "+faststart", str(out)],
        "final encode", grows=out)
    trim_loudness(out, lufs)
    if not keep:
        shutil.rmtree(work, ignore_errors=True)
    return report(out)


def measured_lufs(path: Path) -> tuple[float, float]:
    """(integrated LUFS, true peak dBTP) of a finished file, from ffmpeg's ebur128."""
    err = subprocess.run(["ffmpeg", "-v", "info", "-i", str(path), "-af", "ebur128=peak=true",
                          "-f", "null", "-"], capture_output=True, text=True).stderr
    tail = err[err.rfind("Integrated loudness"):]
    i = re.search(r"I:\s*(-?[\d.]+) LUFS", tail)
    p = re.search(r"Peak:\s*(-?[\d.]+) dBFS", tail)
    return (float(i.group(1)) if i else 0.0, float(p.group(1)) if p else 0.0)


def trim_loudness(out: Path, lufs: float) -> None:
    """AAC and the ebur128/loudnorm meters disagree by a few tenths; land the file on the target."""
    for _ in range(3):
        i, _peak = measured_lufs(out)
        delta = lufs - i
        if abs(delta) < 0.2:
            return
        tmp = out.with_suffix(".loud.mp4")
        run(["ffmpeg", "-v", "error", "-y", "-i", str(out), "-c:v", "copy",
             "-af", f"volume={delta:.2f}dB", "-c:a", "aac", "-b:a", "320k", "-ar", "48000",
             "-movflags", "+faststart", str(tmp)], "loudness trim", grows=tmp)
        tmp.replace(out)
        print(f"cut: loudness trim {delta:+.2f} dB -> {lufs:.1f} LUFS")


def report(out: Path) -> int:
    dur = probe_duration(out)
    size = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                           "stream=width,height,r_frame_rate,codec_name,pix_fmt",
                           "-of", "csv=p=0", str(out)], capture_output=True, text=True).stdout.strip()
    i, peak = measured_lufs(out)
    audio = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries",
                            "stream=codec_name,sample_rate,channels,bit_rate",
                            "-of", "csv=p=0", str(out)], capture_output=True, text=True).stdout.strip()
    print(f"cut: {out}  {dur:.2f}s")
    print(f"cut: video {size}   audio {audio}")
    print(f"cut: integrated {i:.1f} LUFS   true peak {peak:.1f} dBTP")
    return 0


if __name__ == "__main__":
    sys.exit(main())
