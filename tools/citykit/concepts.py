"""Generate city-kit concept images (2 candidates per asset) with ys-api gpt4o.

  concepts.py [--only id,id,...] [--jobs 6] [--cands 2]

Writes art/concept/citykit/<id>-<c>.png. Existing files are kept (rerun-safe). Candidate 1 and 2 differ
only in the camera clause, so both obey the brief's framing rules but give a real choice.
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from assets import ASSETS, Asset, concept_prompt  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "art", "concept", "citykit")
YS = os.path.join(ROOT, "tools", "concept", "ys.py")

# Camera clause per candidate index; both keep "three-quarter from slightly above" (brief).
CAMS = ("viewed from a slightly elevated three-quarter angle so the front and one side are both visible",
        "viewed from a low three-quarter angle, camera almost level with the middle of the building, "
        "so vertical edges stay parallel")


def prompt(a: Asset, cand: int) -> str:
    base = concept_prompt(a).replace(
        "three-quarter view from slightly above,", CAMS[cand % len(CAMS)] + ",")
    return base


def one(a: Asset, cand: int, model: str) -> tuple[str, str]:
    dest = os.path.join(OUT, "%s-%d" % (a.id, cand + 1))
    if os.path.exists(dest + "-1.png"):  # ys.py appends its own -1 index
        return a.id, "c%d exists" % (cand + 1)
    r = subprocess.run([sys.executable, YS, model, dest, prompt(a, cand), "--ar", a.ar],
                       capture_output=True, text=True)
    msg = (r.stdout.strip() or r.stderr.strip()).splitlines()
    return a.id, "c%d %s" % (cand + 1, (msg[-1] if msg else "?")[-90:])


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--only", default="")
    p.add_argument("--jobs", type=int, default=6)
    p.add_argument("--cands", type=int, default=2)
    p.add_argument("--model", default="gpt4o")
    args = p.parse_args()
    want = set(filter(None, args.only.split(",")))
    todo = [(a, c) for a in ASSETS if not want or a.id in want for c in range(args.cands)]
    os.makedirs(OUT, exist_ok=True)
    bad = 0
    with ThreadPoolExecutor(args.jobs) as pool:
        for aid, msg in pool.map(lambda t: one(t[0], t[1], args.model), todo):
            if "fail" in msg.lower() or "error" in msg.lower() or "?" == msg[-1:]:
                bad += 1
            print(aid, msg, flush=True)
    print("done: %d jobs, %d suspicious" % (len(todo), bad))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
