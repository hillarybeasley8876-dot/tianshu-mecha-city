"""Record the Tripo Studio tab's XHR/fetch traffic (request + JSON response bodies) to a JSONL file.

  netlog.py OUT.jsonl [--filter SUBSTR]     runs until killed; one line per finished request
Used once to learn which web endpoints the workspace calls (upload, task create/poll, rig, animate,
export) so tools/tripo can drive the same flows without clicking through the UI.
"""
import asyncio
import json
import os
import sys
import time

import websockets

sys.path.insert(0, os.path.dirname(__file__))
from cdp import page_target  # noqa: E402

SKIP = (".js", ".css", ".png", ".jpg", ".webp", ".woff", ".svg", ".glb", ".fbx", ".mp4", "google", "sentry",
        "analytics", "clarity", "doubleclick", "facebook", "tiktok", "hotjar", "intercom")


async def main(out_path, filt):
    t = page_target()
    async with websockets.connect(t["webSocketDebuggerUrl"], max_size=256 * 1024 * 1024) as ws:
        msg_id = 0
        pending_bodies = {}

        async def send(method, **params):
            nonlocal msg_id
            msg_id += 1
            await ws.send(json.dumps({"id": msg_id, "method": method, "params": params}))
            return msg_id

        await send("Network.enable", maxPostDataSize=65536)
        reqs = {}
        with open(out_path, "a") as out:
            while True:
                msg = json.loads(await ws.recv())
                m, p = msg.get("method"), msg.get("params", {})
                if m == "Network.requestWillBeSent":
                    r = p["request"]
                    url = r["url"]
                    if p.get("type") in ("XHR", "Fetch") and not any(s in url for s in SKIP) and filt in url:
                        reqs[p["requestId"]] = {"t": time.strftime("%H:%M:%S"), "method": r["method"], "url": url,
                                                "post": r.get("postData", "")[:20000]}
                elif m == "Network.responseReceived" and p["requestId"] in reqs:
                    reqs[p["requestId"]]["status"] = p["response"]["status"]
                    reqs[p["requestId"]]["mime"] = p["response"].get("mimeType", "")
                elif m == "Network.loadingFinished" and p["requestId"] in reqs:
                    pending_bodies[await send("Network.getResponseBody", requestId=p["requestId"])] = p["requestId"]
                elif "id" in msg and msg["id"] in pending_bodies:
                    rid = pending_bodies.pop(msg["id"])
                    rec = reqs.pop(rid, None)
                    if rec is not None:
                        rec["body"] = (msg.get("result") or {}).get("body", "")[:20000]
                        out.write(json.dumps(rec, ensure_ascii=False) + "\n")
                        out.flush()


if __name__ == "__main__":
    args = sys.argv[1:]
    filt = args[args.index("--filter") + 1] if "--filter" in args else ""
    asyncio.run(main(args[0], filt))
