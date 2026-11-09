#!/usr/bin/env python3
"""Summarise the camera kit's per-frame framing logs (lead brief trailer-r2 §2 evidence).

    tools/trailer/framing_report.py                       # every log, windowed by shots.json
    tools/trailer/framing_report.py captures/trailer/logs/c_melee.csv
    tools/trailer/framing_report.py --whole               # judge the whole take, not just the cut

Each CSV is written by game/trailer/cam_rig.gd during the take: t, the hero's screen-space bbox as a
fraction of the frame height, whether scenery blocks the camera->chest ray, how many live enemies are
on screen and unblocked, and the camera position. The pass rules are the brief's:

    hero blocked for more than 0.2 s        -> FAIL
    hero shot: bbox < 0.25 for over 0.3 s   -> FAIL
    combat shot: no enemy for over 0.5 s    -> FAIL

By default each log is judged over the windows the EDIT actually uses (shots.json `in`/`out`), which
is what "does the shot pass" means: a take is recorded long and only a slice of it is cut.

"""
from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PASS_BLOCKED = 0.2
PASS_LOW = 0.3
PASS_NOFOE = 0.5
MIN_BBOX = 0.25


def header_of(path: Path) -> dict[str, str]:
    """The `# rig=… kind=… min_bbox=…` line cam_rig.gd writes above the CSV columns."""
    with path.open() as fh:
        first = fh.readline().strip()
    out: dict[str, str] = {}
    if first.startswith("#"):
        for tok in first.lstrip("#").split():
            if "=" in tok:
                k, v = tok.split("=", 1)
                out[k] = v
    return out


def longest_run(rows: list[dict], pred) -> float:
    """Longest continuous stretch where pred(row) holds, in seconds (frame deltas from `t`)."""
    best = run = 0.0
    prev_t = None
    for r in rows:
        t = float(r["t"])
        dt = 0.0 if prev_t is None else max(t - prev_t, 0.0)
        prev_t = t
        run = run + dt if pred(r) else 0.0
        best = max(best, run)
    return best


def windows_of(spec: Path) -> dict[str, list[tuple[float, float]]]:
    """take id -> the [in, out] slices of it the edit uses."""
    doc = json.loads(spec.read_text())
    out: dict[str, list[tuple[float, float]]] = {}
    for s in doc["shots"]:
        out.setdefault(s["take"], []).append((float(s["in"]), float(s["out"])))
    return out


def kinds_of(spec: Path) -> dict[str, str]:
    """take id -> the rig's `kind`, from the SPEC.

    The CSV header carries the kind the take was recorded with, which is stale the moment the shot
    list changes (a chapter-3 movement segment relaxed to `hero` after the fact would still be judged
    as combat). The spec is what the lead edits, so the spec wins; the header is the fallback for a
    log with no matching take.
    """
    doc = json.loads(spec.read_text())
    out: dict[str, str] = {}
    for t in doc.get("takes", []):
        rig = t.get("rig")
        if isinstance(rig, dict) and "kind" in rig:
            out[t["id"]] = str(rig["kind"])
    return out


def report(path: Path, windows: list[tuple[float, float]] | None = None,
           kind_override: str = "") -> tuple[bool, str]:
    head = header_of(path)
    with path.open() as fh:
        rows = list(csv.DictReader(l for l in fh if not l.startswith("#")))
    if windows:
        rows = [r for r in rows if any(a <= float(r["t"]) <= b for a, b in windows)]
    if not rows:
        return False, f"{path.stem:<12} EMPTY LOG"
    bbox = [float(r["bbox"]) for r in rows]
    foes = [int(r["foes"]) for r in rows]
    blocked = longest_run(rows, lambda r: r["blocked"] == "1")
    low = longest_run(rows, lambda r: float(r["bbox"]) < MIN_BBOX)
    nofoe = longest_run(rows, lambda r: int(r["foes"]) == 0)
    kind = kind_override or head.get("kind", "combat" if max(foes) > 0 else "hero")
    bad = []
    if blocked > PASS_BLOCKED:
        bad.append(f"blocked {blocked:.2f}s")
    if kind == "hero" and low > PASS_LOW:
        bad.append(f"small {low:.2f}s")
    if kind == "combat" and nofoe > PASS_NOFOE:
        bad.append(f"no enemy {nofoe:.2f}s")
    ok = not bad
    span = f"{float(rows[0]['t']):.1f}-{float(rows[-1]['t']):.1f}s" if rows else "-"
    return ok, (f"{path.stem:<12} {kind:<7} {head.get('rig', '?'):<12} {span:<12} frames={len(rows):<5} "
                f"bbox min/med={min(bbox):.2f}/{sorted(bbox)[len(bbox) // 2]:.2f}  "
                f"foes min/max={min(foes)}/{max(foes)}  "
                f"blocked={blocked:.2f}s low={low:.2f}s nofoe={nofoe:.2f}s  "
                f"{'PASS' if ok else 'FAIL ' + ', '.join(bad)}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("logs", nargs="*", type=Path)
    ap.add_argument("--spec", type=Path, default=ROOT / "game/trailer/shots.json")
    ap.add_argument("--whole", action="store_true", help="judge the whole take, not the cut windows")
    args = ap.parse_args()
    logs = args.logs or sorted((ROOT / "captures/trailer/logs").glob("*.csv"))
    if not logs:
        print("framing_report: no logs")
        return 2
    wins = {} if args.whole or not args.spec.exists() else windows_of(args.spec)
    kinds = {} if args.whole or not args.spec.exists() else kinds_of(args.spec)
    failed = 0
    for p in logs:
        ok, line = report(p, wins.get(p.stem), kinds.get(p.stem, ""))
        failed += 0 if ok else 1
        print(line)
    print(f"{len(logs)} takes, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
