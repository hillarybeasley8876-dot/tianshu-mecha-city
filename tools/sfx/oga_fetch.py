#!/usr/bin/env python3
"""Fetch OpenGameArt node metadata and files, recording licence + author.

Every download this project uses must have its licence captured at fetch time, so the
manifest and CREDITS_AUDIO.md can never drift from what is actually on disk.
Writes a JSON sidecar next to the downloaded files.
"""
from __future__ import annotations

import argparse
import datetime as dt
import html
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

BASE = "https://opengameart.org"
UA = "mecha-city-audio/1.0 (CC0 asset fetch; contact: repo owner)"
FILE_RE = re.compile(r'href="(https://opengameart\.org/sites/default/files/[^"]+\.(?:ogg|mp3|wav|zip|7z))"')
LICENCE_RE = re.compile(r"<div class='license-name'>([^<]+)</div>")
TITLE_RE = re.compile(r"<title>(.*?)</title>", re.S)
# The author field's own text, not the first /users/ link inside it: on a page whose author is
# plain text (The Free Firearm Sound Library) that link belongs to "Submitted by", and taking it
# credited four recordists' work to the person who uploaded it.
AUTHOR_BLOCK_RE = re.compile(r"field-name-author-submitter(.{0,800}?)field-name-post-date", re.S)
USERNAME_RE = re.compile(r"<span class='username'>(.*?)</span>", re.S)
SUBMITTED_RE = re.compile(r"\(Submitted by.{0,200}?/users/([A-Za-z0-9_.-]+)\"", re.S)
# "Attribution Instructions" — the page's own statement of who created the work.
ATTRIBUTION_RE = re.compile(
    r"field-name-field-art-attribution.*?<div class=\"field-item [^\"]*\">(.*?)</div>", re.S)
# Licence names this project may ship. The trailing space matters: "CC-BY-SA 3.0" also starts with
# "CC-BY", and a share-alike licence is not one of these.
ALLOWED = ("CC0", "CC-BY ")


def text(fragment: str) -> str:
    """Tags out, entities decoded, whitespace collapsed."""
    return " ".join(html.unescape(re.sub(r"<[^>]+>", " ", fragment)).split())


def get(url: str, attempts: int = 3) -> bytes:
    """Fetch a URL, retrying: an OGA node that times out once usually answers on the next try."""
    last: Exception | None = None
    for attempt in range(attempts):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=60) as resp:
                return resp.read()
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            last = exc
            if attempt + 1 < attempts:
                time.sleep(2.0 * (attempt + 1))
    raise RuntimeError(f"{url}: {attempts} attempts failed ({last})")


def node_meta(slug: str) -> dict[str, object]:
    page = get(f"{BASE}/content/{slug}").decode("utf-8", "replace")
    block = AUTHOR_BLOCK_RE.search(page)
    block_html = block.group(1) if block else ""
    username = USERNAME_RE.search(block_html)
    submitted = SUBMITTED_RE.search(block_html)
    attribution = ATTRIBUTION_RE.search(page)
    title = TITLE_RE.search(page)
    files = sorted({u for u in FILE_RE.findall(page)
                    if "/styles/" not in u and "/audio_preview/" not in u})
    return {
        "slug": slug,
        "title": " ".join(title.group(1).split()) if title else slug,
        "author": text(username.group(1)) if username else "unknown",
        "submitted_by": submitted.group(1) if submitted else "",
        "attribution": text(attribution.group(1)) if attribution else "",
        "licences": sorted(set(LICENCE_RE.findall(page))),
        "page": f"{BASE}/content/{slug}",
        "recorded": dt.date.today().isoformat(),
        "files": files,
    }


def download(url: str, dest: Path) -> Path:
    name = urllib.parse.unquote(Path(urllib.parse.urlparse(url).path).name)
    out = dest / re.sub(r"[^A-Za-z0-9._-]+", "_", name)
    out.write_bytes(get(url))
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("slug", nargs="+")
    ap.add_argument("--dest", type=Path, default=Path("art/audio_src/oga_music"))
    ap.add_argument("--get", action="store_true", help="download the node's source files")
    args = ap.parse_args()
    args.dest.mkdir(parents=True, exist_ok=True)
    records = []
    for slug in args.slug:
        meta = node_meta(slug)
        print(f"{slug}: {meta['licences']} by {meta['author']} — {len(meta['files'])} files")
        outside = [lic for lic in meta["licences"] if not lic.startswith(ALLOWED)]
        if outside or not meta["licences"]:
            # Refuse rather than record: a pack this project may not ship must never reach the
            # manifest, so the tool exits non-zero and writes nothing for the node.
            print(f"  !! {slug}: licence {outside or 'none found'} is outside {ALLOWED} — "
                  f"refusing to record or download it", file=sys.stderr)
            return 2
        if args.get:
            for url in meta["files"]:
                try:
                    out = download(url, args.dest)
                except (urllib.error.HTTPError, RuntimeError) as exc:
                    print(f"  !! {exc} {url}", file=sys.stderr)
                    continue
                print(f"  -> {out.name} ({out.stat().st_size} B)")
        records.append(meta)
    sidecar = args.dest / "oga_sources.json"
    old = json.loads(sidecar.read_text()) if sidecar.is_file() else []
    merged = {r["slug"]: r for r in old}
    merged.update({r["slug"]: r for r in records})
    sidecar.write_text(json.dumps(sorted(merged.values(), key=lambda r: r["slug"]), indent=2))
    print(f"[oga_fetch] {len(merged)} sources recorded in {sidecar}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
