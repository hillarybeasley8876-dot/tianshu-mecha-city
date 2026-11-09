#!/usr/bin/env python3
"""Compare two probe_pose_dump dumps: every tick, every bone, every number."""
import sys

def load(path):
    rows = []
    with open(path) as fh:
        for line in fh:
            parts = line.split()
            tick = int(parts[0])
            first = next(i for i, p in enumerate(parts) if "," in p)
            clip = " ".join(parts[1:first - 5])
            head = [float(x) for x in parts[first - 5:first]]
            bones = [float(x) for p in parts[first:] for x in p.split(",")]
            rows.append((tick, clip, head, bones))
    return rows

a = load(sys.argv[1]); b = load(sys.argv[2])
if len(a) != len(b):
    print("FAIL row count %d != %d" % (len(a), len(b))); sys.exit(1)
worst = 0.0; worst_at = None; n = 0
for (t0, c0, h0, b0), (t1, c1, h1, b1) in zip(a, b):
    if (t0, c0) != (t1, c1):
        print("FAIL tick %d: %r/%d != %r/%d" % (t0, c0, t0, c1, t1)); sys.exit(1)
    if len(b0) != len(b1):
        print("FAIL tick %d: %d != %d bone numbers" % (t0, len(b0), len(b1))); sys.exit(1)
    for i, (x, y) in enumerate(zip(h0 + b0, h1 + b1)):
        n += 1
        d = abs(x - y)
        if d > worst:
            worst, worst_at = d, (t0, i)
print("POSE %d ticks, %d numbers, max |delta| = %.3e at %s" % (len(a), n, worst, worst_at))
print("PASS" if worst <= 1e-5 else "FAIL")
