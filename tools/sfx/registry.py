"""Sound registry: one row per exported file, feeding game/audio/audio_manifest.csv.

Usage (bank modules):
    from registry import sound
    sound("rifle_fire", lambda s: beam(...), source="SYNTH", layers="T/B/S/M/Tl")
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Callable

import numpy as np

SOURCES = {
    "SYNTH": ("own synthesis (tools/sfx)", "https://github.com/", "ours", "mecha-city audio unit"),
    "MMX": ("minimax speech-2.8-hd (AI-generated voice)", "https://www.minimax.io/audio",
            "AI-generated, labelled in CREDITS_AUDIO.md", "minimax (AI)"),
}


@dataclass
class Row:
    sound_id: str
    render: Callable[[int], np.ndarray]
    source: str = "SYNTH"
    layers: str = "T"
    loop: bool = False
    ogg: bool = False
    peak_db: float = -1.0
    variants: int = 1
    modified: str = "Y"
    extra: dict = field(default_factory=dict)
    packs: set = field(default_factory=set)
    rendered: bool = False

    @property
    def files(self) -> list[str]:
        if self.variants == 1:
            return [f"{self.sound_id}.{'ogg' if self.ogg else 'wav'}"]
        ext = "ogg" if self.ogg else "wav"
        return [f"{self.sound_id}_{i + 1:02d}.{ext}" for i in range(self.variants)]

    def credits(self) -> tuple[str, str, str, str]:
        """(source, url, licence, author) for the manifest, covering *every* pack this id layers.

        A sound that mixes synthesis with recordings must name both, or the manifest lies about
        what is in the file.
        """
        labels = [SOURCES[self.source]]
        for key in sorted(self.packs):
            import sources as src
            labels.append(src.credit(key))
        source = " + ".join(dict.fromkeys(l[0] for l in labels))
        url = " + ".join(dict.fromkeys(l[1] for l in labels))
        licence = " + ".join(dict.fromkeys(l[2] for l in labels))
        author = " + ".join(dict.fromkeys(l[3] for l in labels))
        return source, url, licence, author


REGISTRY: dict[str, Row] = {}


def sound(sound_id: str, render: Callable[[int], np.ndarray], *, source: str = "SYNTH",
          layers: str = "T", loop: bool = False, ogg: bool = False, peak_db: float = -1.0,
          variants: int = 1, modified: str = "Y", **extra) -> None:
    """Register one sound id. `render(seed)` returns the buffer for variant `seed`."""
    if sound_id in REGISTRY:
        raise ValueError(f"duplicate sound id {sound_id}")
    REGISTRY[sound_id] = Row(sound_id, render, source, layers, loop, ogg, peak_db, variants,
                             modified, extra)
