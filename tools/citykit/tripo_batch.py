"""Drive the city-kit Tripo wave: image -> model for every picked concept, 4 jobs at a time.

  tripo_batch.py [--picks art/concept/citykit/picks.json] [--jobs 4] [--only id,id] [--dry-run]

picks.json maps asset id -> candidate index (1 or 2) from art/concept/citykit/<id>-<c>-1.png.
Jobs are named kit_<id> and land in art/tripo/kit_<id>/. Existing registry entries are skipped, so a
transport failure never spends credits twice (brief: never retry a creating POST).
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from assets import ASSETS, BY_ID  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
STUDIO = os.path.join(ROOT, "tools", "tripo", "studio.sh")
CONCEPTS = os.path.join(ROOT, "art", "concept", "citykit")
REGISTRY = os.path.join(ROOT, "art", "tripo", "jobs.json")
LOG = os.path.join(ROOT, "status", "city-kit-tokens.md")

# Tripo mesh density before Blender decimation; credit cost is flat (~65) so detail is free.
FACES = {"tower": 800000, "megablock": 800000}
DEFAULT_FACES = 500000


def sh(args: list[str], timeout: int = 3600) -> subprocess.CompletedProcess:
    return subprocess.run([STUDIO] + args, capture_output=True, text=True, timeout=timeout)


def balance() -> int:
    r = sh(["balance"], timeout=300)
    try:
        return int(json.loads(r.stdout)["wallet"]["total_credit"])
    except Exception:
        return -1


def known() -> set[str]:
    try:
        return set(json.load(open(REGISTRY)))
    except Exception:
        return set()


def start(aid: str, cand: int, dry: bool) -> tuple[str, str]:
    img = os.path.join(CONCEPTS, "%s-%d-1.png" % (aid, cand))
    if not os.path.exists(img):
        return aid, "MISSING CONCEPT %s" % img
    faces = FACES.get(BY_ID[aid].band, DEFAULT_FACES)
    args = ["img2model", "kit_" + aid, img, "--faces", str(faces)]
    if dry:
        return aid, "dry-run faces=%d %s" % (faces, os.path.basename(img))
    r = sh(args, timeout=1800)
    out = (r.stdout.strip() or r.stderr.strip()).splitlines()
    return aid, (out[-1] if out else "no output")[:200]


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--picks", default=os.path.join(CONCEPTS, "picks.json"))
    p.add_argument("--jobs", type=int, default=4)
    p.add_argument("--only", default="")
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--wait-timeout", type=int, default=2400)
    args = p.parse_args()

    picks: dict[str, int] = json.load(open(args.picks))
    want = set(filter(None, args.only.split(",")))
    order = [a.id for a in ASSETS if a.id in picks and (not want or a.id in want)]
    done = known()
    todo = [i for i in order if "kit_" + i not in done]
    print("picked %d, already in registry %d, starting %d" % (len(order), len(order) - len(todo), len(todo)))
    if not todo:
        return 0
    before = balance()
    print("balance before: %d credits" % before, flush=True)

    for i in range(0, len(todo), args.jobs):
        batch = todo[i:i + args.jobs]
        t0 = time.time()
        with ThreadPoolExecutor(len(batch)) as pool:
            for aid, msg in pool.map(lambda x: start(x, picks[x], args.dry_run), batch):
                print("start %-4s %s" % (aid, msg), flush=True)
        if args.dry_run:
            continue
        r = sh(["wait"] + ["kit_" + a for a in batch] + ["--timeout", str(args.wait_timeout)])
        for line in (r.stdout.strip() or r.stderr.strip()).splitlines():
            print("  " + line[:220], flush=True)
        print("batch %d/%d took %.0f s, balance %d" %
              (i // args.jobs + 1, (len(todo) + args.jobs - 1) // args.jobs, time.time() - t0, balance()),
              flush=True)

    after = balance()
    print("balance after: %d (spent %d)" % (after, before - after if before > 0 and after > 0 else -1))
    if before > 0 and after > 0:
        with open(LOG, "a") as f:
            f.write("| %s | %d | %d | %d | tripo_batch %d assets |\n"
                    % (time.strftime("%Y-%m-%d %H:%M"), before, after, before - after, len(todo)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
