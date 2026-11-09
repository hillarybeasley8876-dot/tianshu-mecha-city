"""Tripo Studio web helper (CDP). Usage:
  web.py text [N]                 visible page text (first N chars)
  web.py shot OUT.png             screenshot
  web.py goto URL                 navigate the Tripo tab
  web.py clickables [FILTER]      list visible clickable elements: index, text, box
  web.py click TEXT [--nth K]     click the K-th visible clickable whose text contains TEXT (real mouse events)
  web.py clickxy X Y              click at CSS pixel coordinates
  web.py inputs                   list <input>/<textarea> elements (type, accept, placeholder, box)
  web.py upload CSS FILE...       set files on the matching <input type=file>
  web.py type CSS TEXT            focus the element and insert text
"""
import asyncio
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from cdp import Page  # noqa: E402

CLICKABLES_JS = r"""
(() => {
  const sel = 'button, a, [role=button], [role=tab], [role=menuitem], [role=option], label, li, [class*=btn], [class*=Button], [class*=tab], [class*=card], div[tabindex], span[tabindex]';
  const out = [];
  for (const el of document.querySelectorAll(sel)) {
    const r = el.getBoundingClientRect();
    if (r.width < 4 || r.height < 4 || r.bottom < 0 || r.top > innerHeight || r.right < 0 || r.left > innerWidth) continue;
    const st = getComputedStyle(el);
    if (st.visibility === 'hidden' || st.display === 'none' || +st.opacity === 0) continue;
    const t = (el.innerText || el.getAttribute('aria-label') || el.title || '').trim().replace(/\s+/g, ' ');
    out.push({t: t.slice(0, 80), x: Math.round(r.left + r.width / 2), y: Math.round(r.top + r.height / 2),
              w: Math.round(r.width), h: Math.round(r.height), tag: el.tagName.toLowerCase()});
  }
  return out;
})()
"""

INPUTS_JS = r"""
(() => [...document.querySelectorAll('input, textarea, [contenteditable=true]')].map((el, i) => {
  const r = el.getBoundingClientRect();
  return {i, tag: el.tagName.toLowerCase(), type: el.type || '', accept: el.accept || '', multiple: !!el.multiple,
          ph: el.placeholder || '', id: el.id, cls: (el.className || '').toString().slice(0, 60),
          x: Math.round(r.left + r.width / 2), y: Math.round(r.top + r.height / 2), w: Math.round(r.width), h: Math.round(r.height)};
}))()
"""


async def main(argv):
    cmd, rest = argv[0], argv[1:]
    page = await Page.open()
    try:
        if cmd == "text":
            n = int(rest[0]) if rest else 3000
            print((await page.js("document.body.innerText"))[:n])
        elif cmd == "shot":
            await page.screenshot(rest[0])
            print("saved", rest[0])
        elif cmd == "goto":
            await page.call("Page.enable")
            await page.call("Page.navigate", url=rest[0])
            await asyncio.sleep(6)
            print(await page.js("location.href"))
        elif cmd == "clickables":
            items = await page.js(CLICKABLES_JS)
            filt = rest[0].lower() if rest else ""
            for i, it in enumerate(items):
                if filt in it["t"].lower():
                    print(i, json.dumps(it, ensure_ascii=False))
        elif cmd == "click":
            text, nth = rest[0], 0
            if "--nth" in rest:
                nth = int(rest[rest.index("--nth") + 1])
            items = [it for it in await page.js(CLICKABLES_JS) if text.lower() in it["t"].lower()]
            items.sort(key=lambda it: it["w"] * it["h"])  # innermost (smallest) match first
            if len(items) <= nth:
                raise SystemExit("no clickable containing %r" % text)
            it = items[nth]
            await page.click_xy(it["x"], it["y"])
            print("clicked", json.dumps(it, ensure_ascii=False))
        elif cmd == "clickxy":
            await page.click_xy(float(rest[0]), float(rest[1]))
            print("clicked", rest[0], rest[1])
        elif cmd == "inputs":
            for it in await page.js(INPUTS_JS):
                print(json.dumps(it, ensure_ascii=False))
        elif cmd == "upload":
            css, files = rest[0], [os.path.abspath(f) for f in rest[1:]]
            doc = await page.call("DOM.getDocument", depth=-1, pierce=True)
            node = await page.call("DOM.querySelector", nodeId=doc["root"]["nodeId"], selector=css)
            if not node.get("nodeId"):
                raise SystemExit("no element for " + css)
            await page.call("DOM.setFileInputFiles", nodeId=node["nodeId"], files=files)
            print("uploaded", files)
        elif cmd == "type":
            css, text = rest[0], rest[1]
            await page.js("document.querySelector(%s).focus()" % json.dumps(css))
            await page.call("Input.insertText", text=text)
            print("typed")
        else:
            print(__doc__)
    finally:
        await page.close()


if __name__ == "__main__":
    asyncio.run(main(sys.argv[1:] or ["help"]))
