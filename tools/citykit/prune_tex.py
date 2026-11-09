"""Delete the texture files Godot extracted from a kit glb that the glb no longer references.

  python3 tools/citykit/prune_tex.py            # report only
  python3 tools/citykit/prune_tex.py --apply

Godot's glTF importer writes every embedded image out next to the .glb as `<glb-stem>_<image name>.<ext>`
and tracks them, so a rebuild that changes an image's NAME (the r3 grade writes `t01_albedo.jpg` where
the old pipeline shipped `t01_Color_<uuid>.jpg`) leaves the previous file behind: dead weight in the
repo, and a `.import` for a texture nothing loads. This reads each glb's own image list — the only
authority on what is still referenced — and removes the rest, with the `.import` beside it.

Only files matching the `<stem>_*` pattern inside `game/world/kit/<id>/` are ever considered, so a
stray capture or a hand-made texture is never touched.
"""
from __future__ import annotations

import glob
import json
import os
import struct
import sys
from typing import List, Set

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
KIT = os.path.join(ROOT, "game", "world", "kit")
IMAGE_EXT = (".jpg", ".jpeg", ".png", ".webp")


def glb_images(path: str) -> Set[str]:
    """The `<name>.<ext>` Godot will extract for this glb, from the glb's own image list."""
    with open(path, "rb") as fh:
        data = fh.read()
    off, js = 12, None
    while off < len(data) - 8:
        ln, ty = struct.unpack_from("<II", data, off)
        if ty == 0x4E4F534A:
            js = json.loads(data[off + 8:off + 8 + ln])
            break
        off += 8 + ln
    if js is None:
        raise ValueError("%s has no JSON chunk" % path)
    out: Set[str] = set()
    for im in js.get("images", []):
        name = im.get("name") or ""
        mime = im.get("mimeType", "")
        ext = {"image/jpeg": ".jpg", "image/png": ".png", "image/webp": ".webp"}.get(mime, ".png")
        if not name:
            continue
        out.add(name + ext)
    return out


def stale(aid: str) -> List[str]:
    folder = os.path.join(KIT, aid)
    keep: Set[str] = set()
    stems: Set[str] = set()
    for glb in sorted(glob.glob(os.path.join(folder, "*.glb"))):
        stem = os.path.splitext(os.path.basename(glb))[0]
        stems.add(stem)
        keep |= {stem + "_" + n for n in glb_images(glb)}
    # The window mask is written next to the glb by blender/citykit/panes.py but is NOT inside it —
    # Godot loads it by path, through `kit_placer.gd`. Its name starts with the glb stem, so without
    # this line the sweep below would delete every mask in the kit.
    keep.add("%s_win.png" % aid)
    dead = []
    for path in sorted(glob.glob(os.path.join(folder, "*"))):
        base = os.path.basename(path)
        if base.endswith(".import"):
            continue                       # the sidecar goes with its image, never on its own
        if not base.lower().endswith(IMAGE_EXT):
            continue
        if not any(base.startswith(s + "_") for s in stems):
            continue                       # not extracted from one of our glbs
        if base not in keep:
            dead.append(path)
    return dead


def main() -> None:
    apply = "--apply" in sys.argv
    total = freed = 0
    for folder in sorted(glob.glob(os.path.join(KIT, "*/"))):
        aid = os.path.basename(folder.rstrip("/"))
        dead = stale(aid)
        for path in dead:
            freed += os.path.getsize(path)
            if apply:
                os.remove(path)
                side = path + ".import"
                if os.path.exists(side):
                    os.remove(side)
        if dead:
            total += len(dead)
            print("%-4s %d stale: %s" % (aid, len(dead),
                                         ", ".join(os.path.basename(p) for p in dead[:4])))
    print("%s %d stale textures (%.0f MB)"
          % ("removed" if apply else "would remove", total, freed / 1e6))


if __name__ == "__main__":
    main()
