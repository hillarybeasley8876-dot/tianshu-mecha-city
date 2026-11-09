#!/usr/bin/env python3
"""Turn mipmaps on for the kit's window-mask PNGs.

    python3 tools/citykit/win_import.py           # report
    python3 tools/citykit/win_import.py --apply   # rewrite the .import params

Godot imports a 2D PNG with `mipmaps/generate=false` and lossless compression. That is right for UI
and wrong for a mask sampled across a 200 m facade: without mipmaps a 1024 px mask minified onto a
300 px building aliases, and — worse for this use — the thin panes drop in and out as the camera
moves, which is exactly the flickering the window layer must not have.

Godot reads the `[params]` block of an existing `.import` file as the defaults for the next import, so
rewriting the two lines is enough; the file is then re-imported by `tools/godot.sh check`. The `.ctex`
itself is not touched here — this only changes what the NEXT import does.
"""
from __future__ import annotations

import hashlib
import os
import re
import sys
from pathlib import Path

PROJ = Path(__file__).resolve().parents[2] / "game"
ROOT = PROJ / "world" / "kit"
WANT = {"mipmaps/generate": "true", "detect_3d/compress_to": "0"}


def drop_artifacts(png: Path) -> int:
    """Delete this PNG's imported artefacts so Godot re-imports it with the new params.

    `godot --import` re-imports a file when its SOURCE md5 changes, not when the `.import` params do
    — and `tools/godot_import.sh` deliberately ignores `*.import` when deciding whether anything
    changed at all. So editing the params alone is a no-op. Removing the `.ctex`/`.md5` pair is the
    same targeted reset `tools/import_doctor.py` does for an invalid asset, scoped to these files.
    """
    digest = hashlib.md5(("res://" + png.relative_to(PROJ).as_posix()).encode("utf-8")).hexdigest()
    n = 0
    for art in (PROJ / ".godot" / "imported").glob("%s-%s.*" % (png.name, digest)):
        art.unlink()
        n += 1
    return n


def main() -> int:
    apply = "--apply" in sys.argv
    force = "--force" in sys.argv      # re-import even where the params were already right
    changed, missing, ok, dropped = [], [], 0, 0
    for d in sorted(os.listdir(ROOT)):
        png = ROOT / d / ("%s_win.png" % d)
        imp = Path(str(png) + ".import")
        if not png.exists():
            continue
        if not imp.exists():
            missing.append(d)
            continue
        text = imp.read_text()
        out = text
        for key, val in WANT.items():
            out = re.sub(r"^%s=.*$" % re.escape(key), "%s=%s" % (key, val), out, flags=re.M)
        if out == text and not force:
            ok += 1
            continue
        changed.append(d)
        if apply:
            imp.write_text(out)
            dropped += drop_artifacts(png)
    print("window masks: %d already correct, %d %s, %d without a .import yet"
          % (ok, len(changed), "rewritten" if apply else "need rewriting", len(missing)))
    if changed:
        print("  %s" % ", ".join(changed))
    if apply and dropped:
        # tools/godot_import.sh skips the import when no non-.import project file is newer than its
        # stamp, so touch the kit index to make the request visible. It is this unit's own file.
        (ROOT / "kit.json").touch()
        print("  %d stale import artefacts removed — run tools/godot.sh import to rebuild them"
              % dropped)
    if missing:
        print("  no .import yet (run tools/godot.sh check first): %s" % ", ".join(missing))
    return 0


if __name__ == "__main__":
    sys.exit(main())
