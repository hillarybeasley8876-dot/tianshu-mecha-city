#!/usr/bin/env python3
"""Machine-wide slot pool: run a command while holding one of N flock slots.

  slots.py <pool> <n> [--timeout SECS] [--stall SECS] [--name LABEL] -- <command...>
--timeout kills the command's process group after SECS (exit 124, prints "[slots] TIMEOUT").
--stall kills it after SECS of making no CPU progress (exit 124, prints "[slots] STALLED ... naming the
  run and freeing the slot). Default: 120 s for the heavy pool, off elsewhere. A windowed Godot run at
  60 fps burns about one core, so 90 s under 0.5 s of CPU is definitively stuck, not working.
Waits (printing a notice to stderr) until a slot is free; the slot is released when the command exits.
"""
import fcntl
import os
import signal
import subprocess
import sys
import time

DEFAULT_TIMEOUT = {"light": 300, "import": 900, "heavy": 600}
DEFAULT_STALL = {"heavy": 120}
STALL_CPU = 0.5      # seconds of CPU a run must make inside the stall window to count as alive
POLL = 5.0
SLOT_DIR = os.path.expanduser("~/m/mecha-city/jobs/.slots")

MAX_WAIT = 540  # give up before a caller's 10-min tool timeout, instead of piling up stale waiters


def acquire(pool, n):
    os.makedirs(SLOT_DIR, exist_ok=True)
    noted = False
    deadline = time.time() + MAX_WAIT
    while True:
        if time.time() > deadline:
            sys.stderr.write("[slots] gave up after %d s waiting for a free '%s' slot (machine busy) - retry later\n"
                             % (MAX_WAIT, pool))
            sys.exit(75)
        for i in range(n):
            fd = os.open(os.path.join(SLOT_DIR, "%s_%d.lock" % (pool, i)), os.O_CREAT | os.O_RDWR)
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                return fd
            except OSError:
                os.close(fd)
        if not noted:
            sys.stderr.write("[slots] waiting for a free '%s' slot (%d in use)...\n" % (pool, n))
            noted = True
        time.sleep(3)


def cpu_seconds(pid):
    """Total CPU seconds the process has used, from ps (macOS has no /proc)."""
    try:
        out = subprocess.run(["ps", "-o", "time=", "-p", str(pid)], capture_output=True, text=True,
                             timeout=10).stdout.strip()
    except (subprocess.SubprocessError, OSError):
        return None
    if not out:
        return None
    parts = [float(p) for p in out.split(":")]
    while len(parts) < 3:
        parts.insert(0, 0.0)
    return parts[0] * 3600.0 + parts[1] * 60.0 + parts[2]


def run(cmd, timeout, stall, label):
    proc = subprocess.Popen(cmd, start_new_session=True)
    started = time.time()
    last_cpu, last_progress = None, time.time()
    while True:
        try:
            code = proc.wait(timeout=POLL)
            return code
        except subprocess.TimeoutExpired:
            pass
        if timeout and time.time() - started > timeout:
            sys.stderr.write("[slots] TIMEOUT after %d s, killing: %s\n" % (timeout, " ".join(cmd)[:200]))
            break
        if stall:
            cpu = cpu_seconds(proc.pid)
            if cpu is None:
                continue          # gone: the wait() above will collect it
            if last_cpu is None or cpu - last_cpu >= STALL_CPU:
                last_cpu, last_progress = cpu, time.time()
            elif time.time() - last_progress > stall:
                sys.stderr.write("[slots] STALLED %s after %d s with no CPU progress (%.1f s CPU total) - "
                                 "the window is probably hidden or covered; freeing the slot\n"
                                 % (label, stall, cpu))
                break
    os.killpg(proc.pid, signal.SIGTERM)
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
    return 124


def main():
    args = sys.argv[1:]
    if "--" not in args or len(args) < 4:
        sys.exit(__doc__)
    sep = args.index("--")
    pool, n, opts, cmd = args[0], int(args[1]), args[2:sep], args[sep + 1:]
    timeout = DEFAULT_TIMEOUT.get(pool, 600)
    if "--timeout" in opts:
        timeout = int(opts[opts.index("--timeout") + 1])
    stall = DEFAULT_STALL.get(pool, 0)
    if "--stall" in opts:
        stall = int(opts[opts.index("--stall") + 1])
    label = opts[opts.index("--name") + 1] if "--name" in opts else cmd[0].split("/")[-1]
    fd = acquire(pool, n)
    try:
        sys.exit(run(cmd, timeout, stall, label))
    finally:
        os.close(fd)


if __name__ == "__main__":
    main()
