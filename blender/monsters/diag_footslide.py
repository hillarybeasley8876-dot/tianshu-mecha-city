"""Foot slide per locomotion state at the gameplay speeds (monster-assets).

    tools/blender.sh run blender/monsters/diag_footslide.py

A locomotion clip is authored for one ground speed — how fast its legs cycle, measured against the
pelvis (`mon_stride`). Played while the actor moves at another speed, the planted foot slides at the
difference, so every type carries a *ladder* of gaits (lead r3) and the model picks the rung whose
authored stride is nearest the speed the body is really moving. This prints, per type and state:

  * the ladder, each rung's stride and the speed it stays clean up to,
  * which rung the model picks at the enemies unit's move speed (`enemies/types.gd`) and at the
    0.35x patrol speed `brain.gd` uses for `walk`,
  * the playback `monster_model.gd` picks (v / stride, clamped to MIN/MAX and the rig's own ceiling)
    and the residual slide that leaves: |v - playback x stride| / v,
  * whether that clears the bar (15 %, or 25 % for the swarmer).
"""
import json
import math
import os
import sys

sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender"))

from monsters import mon_types  # noqa: E402

MODELS = os.path.join(os.path.expanduser("~/m/mecha-city"), "game", "enemies", "models")
#: brain.gd PATROL_SPEED — the speed the `walk` state is driven at while patrolling.
PATROL_FRACTION = 0.35
#: monster_model.gd's hard bounds on a rig's own speed_scale_min / speed_scale_max
SCALE_LIMIT = 4.0


def pick(rungs: list, speed: float) -> tuple:
    """The rung `monster_model.gd` picks at `speed`, and the playback scale it then uses.

    Mirrors `MonsterModel._current_locomotion_clip` / `_update_speed_scale`: of the rungs that stay
    clean at this speed, the one whose authored stride is nearest it."""
    best, best_score = None, math.inf
    for rung in rungs:
        if speed > float(rung["clean_max"]):
            continue
        stride = float(rung["stride"])
        score = 0.0 if stride <= 0.1 else (stride if speed <= 0.5
                                           else abs(math.log(speed / stride)))
        if score < best_score:
            best, best_score = rung, score
    return best or rungs[-1], best_score


def main() -> None:
    print("FOOTSLIDE  bars: %s; playback clamped by each rig's own speed_scale_min/max"
          % ", ".join(["%s %.0f%%" % (k, v * 100)
                       for k, v in sorted(mon_types.SLIDE_TOLERANCE.items())]
                      + ["everyone else %.0f%%" % (mon_types.SLIDE_DEFAULT * 100)]))
    print("  %-11s %-5s %-11s %7s %8s %7s %6s %6s %8s" % (
        "type", "state", "picked", "stride", "speed", "playback", "slide", "patrol", "clean to"))
    over = []
    for monster in ["ripper", "mantis", "spitter", "harrier", "juggernaut", "titan"]:
        path = os.path.join(MODELS, monster, "%s_rig.json" % monster)
        if not os.path.exists(path):
            continue
        with open(path) as fh:
            rig = json.load(fh)
        speed = mon_types.GAME_SPEED.get(monster, 0.0)
        bar = mon_types.SLIDE_TOLERANCE.get(monster, mon_types.SLIDE_DEFAULT)
        ceiling = float(rig.get("speed_scale_max", 2.2))
        floor = float(rig.get("speed_scale_min", 0.6))
        for state, rungs in sorted((rig.get("gait") or {}).items()):
            if state == "idle" or not rungs:
                continue
            rung, _ = pick(rungs, speed)
            stride = float(rung["stride"])
            patrol_rung, _ = pick(rungs, speed * PATROL_FRACTION)
            if stride <= 0.01:
                print("  %-11s %-5s %-11s %7s %8.1f %7s %6s %6s %8s"
                      % (monster, state, rung["clip"], "air", speed, "1.00", "0%", "0%", "any"))
                continue
            used = min(max(speed / stride, floor), min(ceiling, SCALE_LIMIT))
            slide = abs(speed - stride * used) / max(speed, 1e-6)
            patrol_speed = speed * PATROL_FRACTION
            patrol_used = min(max(patrol_speed / float(patrol_rung["stride"]), floor),
                              min(ceiling, SCALE_LIMIT))
            patrol = abs(patrol_speed - float(patrol_rung["stride"]) * patrol_used) \
                / max(patrol_speed, 1e-6)
            flag = ""
            if slide > bar:
                flag = "  <-- over the bar"
                over.append((monster, state, rung["clip"], speed, stride))
            print("  %-11s %-5s %-11s %7.2f %8.1f %7.2f %5.0f%% %5.0f%% %8.1f%s"
                  % (monster, state, rung["clip"], stride, speed, used, slide * 100.0,
                     patrol * 100.0, float(rung["clean_max"]), flag))
    if over:
        print("\n  Over the bar:")
        for monster, state, clip, speed, stride in over:
            print("    %-11s %-5s %-11s now %5.1f m/s against a %.2f m/s stride"
                  % (monster, state, clip, speed, stride))
    else:
        print("\n  Every state clears its bar at the types.gd speed, patrol included.")
    print("\nFOOTSLIDE NOTE: Tripo's walks are marches in place, so their stride comes from the leg")
    print("  cycle, not from root travel (mon_stride). The ripper, spitter and juggernaut carry an")
    print("  authored fast gait above their Tripo walk (lead r3); the ladder picks it by speed.")


main()
