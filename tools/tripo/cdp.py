"""Minimal Chrome DevTools Protocol client for the dedicated Tripo Studio Chrome (port 9222).

The browser is Google Chrome for Testing with the profile ~/m/tripo-chrome-profile, started by
tools/tripo/chrome.sh; the user logs in to studio.tripo3d.ai by hand in that window.
"""
import asyncio
import base64
import json
import os
import urllib.request

import websockets

PORT = 9222


def list_targets():
    with urllib.request.urlopen(f"http://127.0.0.1:{PORT}/json", timeout=10) as r:
        return json.load(r)


API_TAB_URL = "https://studio.tripo3d.ai/robots.txt?mc_api=1"


def ensure_api_tab():
    """A dedicated tab for scripted API calls, so clicking around the UI tab never aborts their fetches."""
    for t in list_targets():
        if t["type"] == "page" and "mc_api=1" in t["url"]:
            return t
    req = urllib.request.Request("http://127.0.0.1:%d/json/new?%s" % (PORT, API_TAB_URL), method="PUT")
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.load(r)


UI_TAB_FILE = os.path.expanduser("~/m/mecha-city/.lead/tripo-ui-tab")


def page_target(url_contains="tripo3d.ai"):
    """The API tab for url_contains="mc_api=1"; otherwise the pinned UI tab (id in UI_TAB_FILE), else the
    first Tripo tab that is not the API tab."""
    pages = [t for t in list_targets() if t["type"] == "page" and url_contains in t["url"]]
    if url_contains != "mc_api=1":
        pages = [t for t in pages if "mc_api=1" not in t["url"]]
        if os.path.exists(UI_TAB_FILE):
            pinned = open(UI_TAB_FILE).read().strip()
            pages = [t for t in pages if t["id"].startswith(pinned)] or pages
    for t in pages:
        return t
    raise SystemExit("no tab matching %r: %s" % (url_contains, [t["url"][:60] for t in list_targets()]))


class Page:
    def __init__(self, ws):
        self.ws, self._id, self.events = ws, 0, []

    @classmethod
    async def open(cls, url_contains="tripo3d.ai"):
        t = page_target(url_contains)
        return cls(await websockets.connect(t["webSocketDebuggerUrl"], max_size=256 * 1024 * 1024))

    async def call(self, method, timeout=60, **params):
        self._id += 1
        my_id = self._id
        await self.ws.send(json.dumps({"id": my_id, "method": method, "params": params}))
        while True:
            msg = json.loads(await asyncio.wait_for(self.ws.recv(), timeout))
            if msg.get("id") == my_id:
                if "error" in msg:
                    raise RuntimeError("%s: %s" % (method, msg["error"]))
                return msg["result"]
            if "method" in msg:
                self.events.append(msg)

    async def js(self, expression, timeout=60):
        r = await self.call("Runtime.evaluate", timeout=timeout, expression=expression,
                            returnByValue=True, awaitPromise=True)
        if "exceptionDetails" in r:
            d = r["exceptionDetails"]
            raise RuntimeError("js: %s %s" % (d.get("text", ""), str(d.get("exception", {}).get("description", ""))[:300]))
        return r["result"].get("value")

    async def screenshot(self, path):
        r = await self.call("Page.captureScreenshot", format="png")
        with open(path, "wb") as f:
            f.write(base64.b64decode(r["data"]))

    async def click_xy(self, x, y):
        for kind in ("mouseMoved", "mousePressed", "mouseReleased"):
            await self.call("Input.dispatchMouseEvent", type=kind, x=x, y=y, button="left", clickCount=1)
            await asyncio.sleep(0.05)

    async def close(self):
        await self.ws.close()
