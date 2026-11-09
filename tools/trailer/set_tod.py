#!/usr/bin/env python3
"""Set the `--tod` a take records at, in a shot list, without hand-editing forty flag lists.

    tools/trailer/set_tod.py --spec game/trailer/shots.json --tod 0.35 --keep s08_boss=0.9
    tools/trailer/set_tod.py --spec game/trailer/showcase.json --tod 0.35 --dry-run

`--tod` is the new value for every take; `--keep id=value` leaves a take alone (the boss is filmed at
the storm time on purpose) and `--only id=value` sets one take. The specs round-trip byte-for-byte
through `json.dumps(indent=2)`, so this rewrites the file in place without reformatting it.

r6: the time of day is now picked per shot from the A/B on the city-art r16b sky
(`tools/trailer/tod_ab.py`), and this is how that decision gets into the spec.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def set_tod(take: dict, value: str) -> bool:
    flags = take.setdefault("flags", [])
    for i, f in enumerate(flags):
        if f.startswith("--tod="):
            if f == f"--tod={value}":
                return False
            flags[i] = f"--tod={value}"
            return True
    flags.append(f"--tod={value}")
    return True


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--spec", type=Path, default=ROOT / "game/trailer/shots.json")
    ap.add_argument("--tod", default="", help="the new --tod for every take")
    ap.add_argument("--keep", action="append", default=[], metavar="ID=VALUE",
                    help="a take to leave alone (repeatable)")
    ap.add_argument("--only", action="append", default=[], metavar="ID=VALUE",
                    help="set one take only (repeatable)")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    doc = json.loads(args.spec.read_text())
    keep = {k.split("=")[0] for k in args.keep}
    only = {k.split("=")[0]: k.split("=")[1] for k in args.only}
    if not args.tod and not only:
        raise SystemExit("set_tod: pass --tod and/or --only id=value")

    changed: list[str] = []
    for take in doc["takes"]:
        if take["id"] in only:
            value = only[take["id"]]
        elif args.tod and take["id"] not in keep:
            value = args.tod
        else:
            continue
        if set_tod(take, value):
            changed.append(f"{take['id']}={value}")
    if changed:
        print(f"set_tod: {len(changed)} takes -> " + " ".join(changed))
    else:
        print("set_tod: nothing to change")
    if not args.dry_run and changed:
        args.spec.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
