"""ys-api image client (internal MiniMax platform, needs IOA VPN): generate concept images with one model.

  ys.py MODEL OUT_PREFIX "prompt" [--ref PATH_OR_URL ...] [--n N] [--ar 3:4]

MODEL: mj (Midjourney), kling (Kling v3 omni), gpt4o, nano (Nano Banana), seedream, qwen (edit, needs --ref).
Writes OUT_PREFIX-1.png, -2.png ... and prints the paths. Polls every 10 s, gives up after 15 min.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

BASE = os.environ.get("YS_API_BASE", "https://ys-api.internal/api").rstrip("/")
if "YS_API_BASE" not in os.environ:
    raise SystemExit("ys.py: set YS_API_BASE to the ys-api endpoint (internal MiniMax platform, "
                     "needs the IOA VPN); it is deliberately not in the repo")
POLL_EVERY, MAX_WAIT = 10, 900


def post(path, payload, timeout=180):
    out = subprocess.run(["curl", "-sS", "-m", str(timeout), "-X", "POST", BASE + path,
                          "-H", "Content-Type: application/json", "-d", json.dumps(payload)],
                         capture_output=True, text=True)
    if out.returncode:
        raise SystemExit("curl %s failed: %s" % (path, out.stderr.strip()))
    try:
        return json.loads(out.stdout)
    except ValueError:
        raise SystemExit("non-JSON reply from %s: %s" % (path, out.stdout[:300]))


def upload(path):
    out = subprocess.run(["curl", "-sS", "-m", "120", "-X", "POST", BASE + "/fileupload", "-F", "file=@" + path],
                         capture_output=True, text=True)
    reply = json.loads(out.stdout)
    if not reply.get("success"):
        raise SystemExit("upload failed: %s" % reply)
    return reply["data"]


def urls_in(obj):
    text = obj if isinstance(obj, str) else json.dumps(obj)
    return [u for u in re.findall(r"https?://[^\s\"'\\]+", text)
            if re.search(r"\.(png|jpe?g|webp)(\?|$)", u, re.I) or "image" in u.lower()]


def task_id_in(reply):
    data = reply.get("data")
    if isinstance(data, str):
        try:
            data = json.loads(data)
        except ValueError:
            return data if len(data) < 80 and "http" not in data else None
    if isinstance(data, dict):
        for k in ("task_id", "taskId", "id", "job_id"):
            if data.get(k):
                return str(data[k])
    return None


MODELS = {
    "mj": ("/midjourney", "/midjourney_query", lambda a, refs: {"prompt": a.prompt + (" --ar " + a.ar if a.ar else "")}),
    "kling": ("/kling_image_omni", "/kling_image_omni_query",
              lambda a, refs: dict({"model_name": "kling-v3", "prompt": a.prompt, "n": a.n, "resolution": "2k",
                                    "aspect_ratio": a.ar or "1:1"}, **({"image_url": refs[0]} if refs else {}))),
    "gpt4o": ("/gen_img_4o", "/gen_img_4o_query", lambda a, refs: {"prompt": a.prompt, "refer_imgs": refs}),
    "nano": ("/nano_banana_image", "/nano_banana_image_query", lambda a, refs: {"prompt": a.prompt, "image_urls": refs}),
    "seedream": ("/seeddream", None, lambda a, refs: dict({"prompt": a.prompt}, **({"image_urls": refs} if refs else {}))),
    "qwen": ("/qwen_image_edit", None, lambda a, refs: {"prompt": a.prompt, "image_url": refs[0] if refs else ""}),
}


def run(a):
    path, query, build = MODELS[a.model]
    refs = [r if r.startswith("http") else upload(r) for r in a.ref]
    reply = post(path, build(a, refs))
    if reply.get("success") is False:
        raise SystemExit("%s refused: %s" % (a.model, json.dumps(reply)[:400]))
    found = urls_in(reply.get("data") or "")
    tid = None if found else task_id_in(reply)
    deadline = time.time() + MAX_WAIT
    while not found:
        if not (query and tid):
            raise SystemExit("no image and no task id: %s" % json.dumps(reply)[:400])
        if time.time() > deadline:
            raise SystemExit("timeout waiting for task %s" % tid)
        time.sleep(POLL_EVERY)
        status = post(query, {"task_id": tid})
        if status.get("success") is False and "running" not in json.dumps(status).lower():
            raise SystemExit("task %s failed: %s" % (tid, json.dumps(status)[:400]))
        found = urls_in(status.get("data") or "")
    outs = []
    for i, url in enumerate(dict.fromkeys(found), 1):
        dest = Path("%s-%d.png" % (a.out, i))
        dest.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["curl", "-sS", "-L", "-m", "180", "-o", str(dest), url], check=True)
        outs.append(str(dest))
    print("\n".join(outs))


def main():
    p = argparse.ArgumentParser()
    p.add_argument("model", choices=sorted(MODELS))
    p.add_argument("out")
    p.add_argument("prompt")
    p.add_argument("--ref", action="append", default=[])
    p.add_argument("--n", type=int, default=1)
    p.add_argument("--ar", default="")
    run(p.parse_args())


if __name__ == "__main__":
    sys.exit(main())
