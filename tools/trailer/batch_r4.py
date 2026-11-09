#!/usr/bin/env python3
"""Run the r4 capture batch: every unit's "Captures needed" command, one window at a time.

    tools/trailer/batch_r4.py --list
    tools/trailer/batch_r4.py --only hud
    tools/trailer/batch_r4.py            # every unit, in the lead's order

Each command runs with MC_WINDOW_OK=1 from the repo root, exactly as the unit wrote it (only obvious
path typos are fixed in batch_r4.json). Its stdout+stderr go to tmp/trailer/r4/logs/<unit>_<id>.log,
and tmp/trailer/r4/results.json records exit code, wall time, the engine-error lines and every file
under captures/ the run touched. Nothing here fixes a unit's code: a failure is recorded and the
batch moves on (reviews/trailer-r4-captures.md, "Rules for this run").
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = Path(__file__).resolve().parent / "batch_r4.json"
OUT = ROOT / "tmp" / "trailer" / "r4"
CAPTURES = ROOT / "captures"
ERR_RE = re.compile(r"^(SCRIPT ERROR|USER ERROR|ERROR|CRASH)|ERROR:|\bFATAL\b")
DRIVE_RE = re.compile(r"errors=(\d+)")


def snapshot() -> dict[str, float]:
    return {str(p): p.stat().st_mtime for p in CAPTURES.rglob("*") if p.is_file()}


def load_spec() -> dict:
    return json.loads(SPEC.read_text())


def load_results() -> list[dict]:
    path = OUT / "results.json"
    return json.loads(path.read_text()) if path.exists() else []


def save_results(rows: list[dict]) -> None:
    """Merge with whatever is on disk: a second batch process must not drop another's rows."""
    OUT.mkdir(parents=True, exist_ok=True)
    mine = {(r["unit"], r["id"]): r for r in rows}
    merged = [r for r in load_results() if (r["unit"], r["id"]) not in mine]
    (OUT / "results.json").write_text(json.dumps(merged + list(mine.values()), indent=1))


def run_one(unit: str, cmd: dict) -> dict:
    cid = cmd["id"]
    log = OUT / "logs" / f"{unit}_{cid}.log"
    log.parent.mkdir(parents=True, exist_ok=True)
    before = snapshot()
    env = dict(os.environ, MC_WINDOW_OK="1")
    argv = ["bash", "-lc", cmd["raw"]] if "raw" in cmd else [os.path.expandvars(a) for a in cmd["argv"]]
    print(f"--- {unit} {cid}: {' '.join(argv)[:150]}", flush=True)
    t0 = time.time()
    proc = subprocess.run(argv, cwd=ROOT, env=env, capture_output=True, text=True)
    secs = time.time() - t0
    log.write_text(proc.stdout + ("\n=== stderr ===\n" + proc.stderr if proc.stderr else ""))
    text = proc.stdout + proc.stderr
    errs = [ln for ln in text.splitlines() if ERR_RE.search(ln)]
    drive = [int(m) for m in DRIVE_RE.findall(text)]
    after = snapshot()
    new = sorted(p for p, m in after.items() if p not in before or m > before[p] + 0.5)
    row = {
        "unit": unit, "id": cid, "note": cmd.get("note", ""),
        "cmd": cmd.get("raw") or " ".join(cmd["argv"]),
        "exit": proc.returncode, "secs": round(secs, 1),
        "errors": len(errs), "error_lines": errs[:12],
        "drive_errors": drive[-1] if drive else None,
        "log": str(log.relative_to(ROOT)), "outputs": [str(Path(p).relative_to(ROOT)) for p in new],
        "at": time.strftime("%H:%M:%S"),
    }
    print(f"    exit={proc.returncode} {secs:.0f}s errors={len(errs)} files={len(new)}", flush=True)
    return row


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default=None, help="one unit (comma separated)")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--force", action="store_true", help="re-run a command already in results.json")
    args = ap.parse_args()
    spec = load_spec()
    units = list(spec["units"])
    if args.only:
        wanted = args.only.split(",")
        units = [u for u in units if u in wanted]
    if args.list:
        for u in units:
            for c in spec["units"][u]:
                print(f"{u:16s} {c['id']:22s} {c.get('note','')}")
        return 0
    rows = load_results()
    done = {(r["unit"], r["id"]) for r in rows}
    for unit in units:
        for cmd in spec["units"][unit]:
            if (unit, cmd["id"]) in done and not args.force:
                print(f"--- {unit} {cmd['id']}: already run, skipping", flush=True)
                continue
            rows = [r for r in rows if (r["unit"], r["id"]) != (unit, cmd["id"])]
            rows.append(run_one(unit, cmd))
            save_results(rows)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
