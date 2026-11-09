#!/usr/bin/env python3
"""The spec reader every trailer tool shares: a take in a shot list -> the godot.sh arguments.

A take is one RECORDED run (a `tools/godot.sh movie`), a shot is one CUT out of a take. `shots.json`
and `showcase.json` both hold `takes` and `shots`; `render_all.py` records the takes, `cut.py` cuts the
shots, and the time-of-day A/B drives the same take again with `--tod` swapped for stills — so the
argument building lives here once instead of in each tool.

    from takes import load_spec, take_args, take_by_id
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def load_spec(path: Path) -> dict:
    return json.loads(Path(path).read_text())


def spec_value(value) -> str:
    """A rig / assist / flow script is either a `res://…json` path or the JSON itself (inline rigs)."""
    return value if isinstance(value, str) else json.dumps(value, separators=(",", ":"))


def take_by_id(spec: dict, take_id: str) -> dict:
    for t in spec["takes"]:
        if t["id"] == take_id:
            return t
    raise SystemExit(f"takes: no take {take_id!r} in the spec")


def take_args(take: dict, *, tod: str | None = None, log: Path | None = None) -> list[str]:
    """The godot.sh arguments for one take, in the order autoplay reads them.

    `tod` overrides the take's own `--tod=` flag (the time-of-day A/B); `log` is the framing CSV, which
    only makes sense for a take that carries a camera rig.
    """
    args = [f"--timeline={take['timeline']}",
            f"--scene={take.get('scene', 'res://trailer/shot.tscn')}"]
    if take.get("cam"):
        args.append(f"--trailer-cam={take['cam']}")
    for key, flag in (("rig", "--trailer-rig="), ("rig2", "--trailer-rig2="),
                      ("assist", "--trailer-assist="), ("flow_script", "--flow-script=")):
        if take.get(key):
            args.append(flag + spec_value(take[key]))
    if log is not None and (take.get("rig") or take.get("rig2")):
        args.append(f"--trailer-log={log}")
    for f in take.get("flags", []):
        if tod is not None and f.startswith("--tod="):
            continue
        args.append(f)
    if tod is not None:
        args.append(f"--tod={tod}")
    return args


def shot_times(spec: dict, take_id: str, limit: int = 3) -> list[float]:
    """Sample times inside the CUT windows that use this take — what the edit actually shows."""
    mids: list[float] = []
    for s in spec["shots"]:
        if s.get("take") != take_id:
            continue
        mid = (float(s["in"]) + float(s["out"])) / 2.0
        if all(abs(mid - m) > 0.4 for m in mids):
            mids.append(mid)
    return [round(m, 1) for m in sorted(mids)[:limit]]


if __name__ == "__main__":
    import sys
    spec = load_spec(Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "game/trailer/shots.json")
    for t in spec["takes"]:
        print(t["id"], " ".join(take_args(t)))
