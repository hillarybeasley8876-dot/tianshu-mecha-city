"""Rebuild every HUSK monster model deterministically (monster-assets).

    tools/blender.sh run blender/monsters/build_all.py -- [--only=ripper,mantis] [--out=report.json]

Prints tri counts, bone counts and every clip (id + duration) per type, and writes the same numbers
to tmp/monster-assets/build_report.json. Each type is built in its own empty scene, so one failure
does not take the rest of the run with it.
"""
import argparse
import json
import os
import sys
import time
import traceback

import bpy

sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender"))
from lib import common  # noqa: E402

from monsters import mon_build, mon_hive, mon_lib, mon_types  # noqa: E402

ORDER = ["ripper", "mantis", "spitter", "harrier", "juggernaut", "titan", "hive"]
REPORT = os.path.join(mon_lib.TMP, "build_report.json")


def build_one(monster: str) -> dict:
    common.reset()
    source = mon_types.RIG_SOURCE[monster]
    if source == "tripo":
        return mon_build.build_tripo(monster)
    if source == "own":
        return mon_build.build_own(monster)
    return mon_hive.build_hive()


def _slide(report: dict, monster: str) -> float:
    """Residual foot slide as a fraction of the body speed, for the gait the model picks at the
    gameplay speed (the last rung of the fastest state's ladder)."""
    speed = mon_types.GAME_SPEED.get(monster, 0.0)
    ladders = [e for state, e in report.get("gait", {}).items() if state != "idle"]
    if speed <= 0.0 or not ladders:
        return 0.0
    ladder = max(ladders, key=len)
    top = ladder[-1]
    if top["stride"] <= 0.1:
        return 0.0
    played = top["stride"] * min(speed / top["stride"], report.get("speed_scale_max", 2.2))
    return max(0.0, speed - played) / speed


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:]
    p = argparse.ArgumentParser()
    p.add_argument("--only", default="")
    args = p.parse_args(argv)
    types = args.only.split(",") if args.only else ORDER
    results, failures = {}, []
    for monster in types:
        t0 = time.time()
        try:
            results[monster] = build_one(monster)
            results[monster]["seconds"] = round(time.time() - t0, 1)
        except Exception as exc:                      # one type must not abort the run
            failures.append(monster)
            results[monster] = {"error": "%s: %s" % (type(exc).__name__, exc)}
            print("BUILD FAIL %s\n%s" % (monster, traceback.format_exc()))
    os.makedirs(mon_lib.TMP, exist_ok=True)
    with open(REPORT, "w") as fh:
        json.dump(results, fh, indent=1, sort_keys=True)
    print("\n==== BUILD SUMMARY ====")
    for monster in types:
        r = results.get(monster, {})
        if "error" in r:
            print("%-11s FAILED  %s" % (monster, r["error"]))
            continue
        size = r.get("size", {})
        axis = str(size.get("axis", "height"))
        print("%-11s %6.1fs  lod0 %7d / lod1 %7d  verts %7d  bones %3d  clips %2d  %s %.2f/%.1f m"
              % (monster, r.get("seconds", 0.0), r.get("lod0_tris", 0), r.get("lod1_tris", 0),
                 r.get("verts", 0), r.get("bones", 0), len(r.get("clips", {})),
                 axis, size.get("value", 0.0), size.get("target", 0.0)))
        for clip_id in sorted(r.get("clips", {})):
            print("             clip %-14s %.2fs" % (clip_id, r["clips"][clip_id]))
        for state, ladder in sorted((r.get("gait") or {}).items()):
            print("             gait %-9s %s" % (state, "  ".join(
                "%s<=%.1f" % (e["clip"], e["clean_max"]) if e["clean_max"] < 1.0e8
                else "%s<=any" % e["clip"] for e in ladder)))
        if r.get("gait"):
            print("             slide at %.0f m/s: %.0f%% (ceiling %.2fx)" % (
                mon_types.GAME_SPEED.get(monster, 0.0), 100.0 * _slide(r, monster),
                r.get("speed_scale_max", 0.0)))
        if r.get("skyline"):
            print("             skyline %s tris %d x%.1f" % (
                r["skyline"]["path"].split("/")[-1], r["skyline"]["tris"], r["skyline"]["scale"]))
    print("REPORT %s" % REPORT)
    if failures:
        print("FAILURES: %s" % ", ".join(failures))
        sys.exit(1)


main()
