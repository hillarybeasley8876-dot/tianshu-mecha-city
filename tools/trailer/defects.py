#!/usr/bin/env python3
"""The deliverable's defect gate: frame size, rate, codecs, loudness, black frames, frozen frames.

    tools/trailer/defects.py captures/trailer/TIANSHU_showcase.mp4
    tools/trailer/defects.py <file> --black 0.10 --freeze 0.002 --min-freeze 0.6

Black and frozen frames come from ffmpeg's own `blackdetect` / `freezedetect`; loudness from
`ebur128`. Exit 1 if anything fails, so it can be the last line of a render script.
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path


def probe(path: Path) -> dict[str, str]:
    """One dict per stream kind — a single `default=nw=1` dump flattens both streams into one map and
    the audio's keys silently overwrite the video's."""
    out: dict[str, str] = {}
    for sel, tag in (("v:0", "v"), ("a:0", "a")):
        txt = subprocess.run(
            ["ffprobe", "-v", "error", "-select_streams", sel, "-show_entries",
             "stream=codec_name,width,height,r_frame_rate,pix_fmt,sample_rate,channels:"
             "format=duration",
             "-of", "default=nw=1", str(path)], capture_output=True, text=True, check=True).stdout
        for line in txt.strip().splitlines():
            if "=" in line:
                k, v = line.split("=", 1)
                out[f"{tag}_{k}"] = v
                out.setdefault(k, v)
    return out


def detect(path: Path, vf: str, pattern: str) -> list[str]:
    err = subprocess.run(["ffmpeg", "-v", "info", "-i", str(path), "-vf", vf, "-an", "-f", "null", "-"],
                         capture_output=True, text=True).stderr
    return [m.group(0) for m in re.finditer(pattern, err)]


def loudness(path: Path) -> tuple[float, float]:
    err = subprocess.run(["ffmpeg", "-v", "info", "-i", str(path), "-af", "ebur128=peak=true",
                          "-f", "null", "-"], capture_output=True, text=True).stderr
    tail = err[err.rfind("Integrated loudness"):]
    i = re.search(r"I:\s*(-?[\d.]+) LUFS", tail)
    p = re.search(r"Peak:\s*(-?[\d.]+) dBFS", tail)
    return (float(i.group(1)) if i else 0.0, float(p.group(1)) if p else 0.0)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("src", type=Path)
    ap.add_argument("--lufs", type=float, default=-14.0)
    ap.add_argument("--tp", type=float, default=-1.0)
    ap.add_argument("--black", type=float, default=0.10, help="picture_black_th")
    ap.add_argument("--freeze", type=float, default=0.002, help="noise tolerance")
    ap.add_argument("--min-freeze", type=float, default=0.6, help="s a still must hold to count")
    args = ap.parse_args()

    st = probe(args.src)
    dur = float(st.get("duration", 0.0))
    blacks = detect(args.src, f"blackdetect=d=0.08:pix_th={args.black}", r"black_start:[^\n]*")
    frozen = detect(args.src, f"freezedetect=n={args.freeze}:d={args.min_freeze}",
                    r"freeze_start:[^\n]*")
    i, peak = loudness(args.src)

    print(f"defects: {args.src}")
    print(f"  duration {dur:.2f}s   size {st.get('v_width')}x{st.get('v_height')} "
          f"@ {st.get('v_r_frame_rate')}  {st.get('v_pix_fmt')}")
    print(f"  video {st.get('v_codec_name')}   audio {st.get('a_codec_name')} "
          f"{st.get('a_sample_rate')} Hz {st.get('a_channels')} ch")
    print(f"  integrated {i:.1f} LUFS (want {args.lufs})   true peak {peak:.1f} dBTP "
          f"(want <= {args.tp})")
    print(f"  black frames {len(blacks)}   frozen frames {len(frozen)}")
    for line in blacks[:5]:
        print(f"    BLACK {line}")
    for line in frozen[:5]:
        print(f"    FROZEN {line}")

    bad = []
    if st.get("v_width") != "1920" or st.get("v_height") != "1080":
        bad.append("frame size")
    if abs(i - args.lufs) > 0.5:
        bad.append("loudness")
    if peak > args.tp:
        bad.append("true peak")
    if blacks:
        bad.append(f"{len(blacks)} black")
    if frozen:
        bad.append(f"{len(frozen)} frozen")
    print("  " + ("FAIL " + ", ".join(bad) if bad else "PASS"))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
