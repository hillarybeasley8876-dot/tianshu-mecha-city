"""Batch concept images: batch.py LIST.json OUT_DIR [--model gpt4o] [--jobs 4]
LIST.json = [{"name": ..., "prompt": ..., "ref": optional path}]; skips names whose OUT_DIR/<name>-1.png exists.
"""
import json
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

YS = os.path.join(os.path.dirname(__file__), "ys.py")


def run(item, out_dir, model):
    dest = os.path.join(out_dir, item["name"])
    if os.path.exists(dest + "-1.png"):
        return item["name"], "exists"
    cmd = [sys.executable, YS, model, dest, item["prompt"]]
    if item.get("ref"):
        cmd += ["--ref", os.path.expanduser(item["ref"])]
    r = subprocess.run(cmd, capture_output=True, text=True)
    return item["name"], (r.stdout.strip() or r.stderr.strip())[-160:]


def main():
    args = sys.argv[1:]
    model = args[args.index("--model") + 1] if "--model" in args else "gpt4o"
    jobs = int(args[args.index("--jobs") + 1]) if "--jobs" in args else 4
    items = json.load(open(args[0]))
    os.makedirs(args[1], exist_ok=True)
    with ThreadPoolExecutor(jobs) as pool:
        for name, msg in pool.map(lambda it: run(it, args[1], model), items):
            print(name, "->", msg, flush=True)


if __name__ == "__main__":
    main()
