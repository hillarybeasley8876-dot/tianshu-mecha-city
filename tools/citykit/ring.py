"""The skyline ring: a kit far model on each of the 96 horizon boxes (lead r9 item 1).

The 96 boxes in `city_layout.json["skyline"]` are 740-1 229 m from the centre, 80-260 m tall and
55-109 m wide, and until r9 every one of them rendered as a plain pale box with a stepped cap — the
user's 搭积木 complaint at the scale of the whole city. city-build has read a `ring` row since its r8
(`blender/city/skin.py`): the row names an index into `skyline` and that box is dropped from
`skyline.glb`, so the kit model standing there is the only render.

What this module decides is which model, at which quarter turn, on each box:

* **Model.** A tall box gets a tower, a wide one a megablock or a mid-rise. The fit obeys the same
  anisotropy limits the buildings do (`tuning.ANISO_MAX` / `ANISO_SOFT`), so nothing on the horizon is
  stretched architecture. A model with a through-opening is refused: the box behind it is gone, so the
  hole would be a window onto the sky.
* **Yaw.** Every box is turned so the model's detailed face (-Y in Blender) looks at the city centre —
  the ring is read from inside, so the front is the only side that ever matters.
* **Spread.** The boxes are walked in angular order, and a model already used by either angular
  neighbour pays `NEIGHBOUR_PENALTY`, as does a repeat of the neighbour's CROWN class. Without the
  crown term the horizon is six kinds of tower in a row and reads as a texture; with it the skyline
  has spires, setbacks, flat tops and stepped crowns in an irregular rhythm.

The crown classes are read off `captures/kit/<id>.jpg` by eye — they are an art-direction label, not
a measurement, and they are only used to stop two neighbours looking alike.
"""
from __future__ import annotations

import math
from typing import Dict, List, Optional, Sequence, Tuple

import geom2d as g
from assets import PROP_BANDS
from tuning import ANISO_MAX, ANISO_SOFT, FRONT_BONUS, NEIGHBOUR_PENALTY, USAGE_PENALTY

# A skyline is towers, slabs and mid-rises. Civic halls, old-town houses and sheds are 16-80 m and
# belong inside the map, not on a 80-260 m horizon.
RING_BANDS = ("tower", "megablock", "midrise")

# The silhouette a model puts on the horizon, judged from its QA sheet (captures/kit/<id>.jpg).
CROWNS: Dict[str, str] = {
    "t01": "setback",    # stepped setbacks under a pagoda-roof crown
    "t02": "twisted",    # twisted shaft with vertical LED fins
    "t03": "spire",      # diagrid exoskeleton under a thin antenna spire
    "t04": "twin",       # two cores joined by skybridges
    "t05": "halo",       # cantilevered sky-gardens under a glowing halo ring
    "t06": "flat",       # slab with a rooftop helipad and an antenna cluster
    "m01": "slab",       # Kowloon wall of windows and neon, flat parapet
    "m02": "void",       # megablock around a central void, skybridges across it
    "m03": "stepped",    # terraced ziggurat with billboards on the upper walls
    "b01": "tank",       # apartment tower with a rooftop water tank
    "b02": "sign",       # hotel with a full-height vertical neon sign and a lit crown box
    "b03": "fins",       # office mid-rise, vertical stone fins, flat top
    "b04": "terrace",    # mixed-use block with planted terraces
    "b05": "pods",       # stacked capsule housing
    # The ring's own masses (assets.py r9): one per shape cluster of the 96 boxes.
    "r01": "setback",    # broad block tower under a stepped crown of plant rooms
    "r02": "mast",       # slender shaft under a bronze crown box and a thin mast
    "r03": "billboard",  # squat square block with giant billboards and a roof garden
    "r04": "antenna",    # tall thin slab with a bronze crown band and an antenna cluster
}

# The ring is horizon scenery and is drawn from the model's FAR glb, so a model without one cannot
# stand there at all.
MIN_FAR_TRI = 1

#: How many distinct models the ring may use. Every ring model is a batch, and a MultiMeshInstance3D
#: is culled by its whole AABB, so the ring costs roughly two draws per model from anywhere in the
#: city: 12 models measured +26 draws at the A1 spawn, which put KitPlacer at 103 against the lead's
#: 98. Eight keeps eight distinct crown classes on the horizon — the variety the ring exists for — and
#: brings the placer back inside the gate. The palette is chosen by a first pass (`build`), so the
#: eight are the ones that actually FIT the 96 boxes rather than eight picked by hand.
RING_MODELS_MAX = 8
#: ... of which this many are reserved for a vertical crown. Ranking purely by how many boxes a model
#: wins gives a palette of chunky megablocks and mid-rises — the ring boxes are 50-109 m wide, so a
#: slender tower rarely wins one — and the horizon then has no spire, mast or halo on it at all, which
#: is the flatness the lead asked r9 to remove. Two reserved slots keep a vertical silhouette in the
#: palette without pretending the ring is a tower field.
RING_VERTICAL_SLOTS = 2
#: Crown classes that read as a vertical accent on a skyline.
VERTICAL_CROWNS = frozenset(("spire", "mast", "antenna", "halo", "twin"))


def _crown(model: dict) -> str:
    return CROWNS.get(model["id"], model["band"])


class Ring:
    """Fits one kit model to each skyline box. See the module docstring for the rules."""

    def __init__(self, a: "Assigner") -> None:
        self.a = a
        self.models = [m for m in a.models.values()
                       if m["band"] in RING_BANDS and m["band"] not in PROP_BANDS
                       and "hole" not in m.get("tags", [])
                       and int((m.get("far") or {}).get("tris", 0)) >= MIN_FAR_TRI]
        self.uses: Dict[str, int] = {}

    # ------------------------------------------------------------------ fit
    @staticmethod
    def fit(box: Sequence[float], model: dict, j: int) -> Tuple[float, List[float]]:
        """(anisotropy, per-model-axis scale) for model `m` at quarter turn `j` on this box.

        Same convention as `assign.Assigner.score`: on an odd turn the model's Y lies along the box's
        width, so the scale written in the model's own axis order swaps X and Y.
        """
        w, d, h = float(box[0]), float(box[1]), float(box[2])
        mx, my, mz = (float(v) for v in model["size"])
        fx, fy = (my, mx) if j % 2 else (mx, my)
        sx, sy, sz = w / max(fx, 1e-6), d / max(fy, 1e-6), h / max(mz, 1e-6)
        return g.anisotropy((sx, sy, sz)), ([sy, sx, sz] if j % 2 else [sx, sy, sz])

    def pick(self, box: Sequence[float], centre: g.Pt, prev: Sequence[dict],
             avoid: Sequence[str] = ()) -> Optional[dict]:
        """The best (model, turn) for one box, given the two angular neighbours already placed.

        `avoid` is a hard exclusion: the caller passes its neighbours' models, and if that leaves
        nothing the caller retries without it and marks the row `forced`. A soft penalty was not
        enough — 43 of the 96 boxes have a single model that fits inside the anisotropy cap, so a
        penalty only decides WHICH repeat happens, not whether one does.
        """
        face = g.yaw_towards(centre, (0.0, 0.0))
        recent = [r["model"] for r in prev]
        recent_crowns = [r["crown"] for r in prev]
        blocked = set(avoid)
        best: Optional[dict] = None
        for limit in (ANISO_MAX, ANISO_SOFT):
            for m in self.models:
                if m["id"] in blocked:
                    continue
                for j in range(4):
                    aniso, scale = self.fit(box, m, j)
                    if aniso > limit:
                        continue
                    yaw = 90.0 * j
                    off = abs(((yaw + 180.0 - face + 180.0) % 360.0) - 180.0)
                    score = math.log(aniso) + FRONT_BONUS * (off / 90.0)
                    score += NEIGHBOUR_PENALTY * recent.count(m["id"])
                    score += 0.5 * NEIGHBOUR_PENALTY * recent_crowns.count(_crown(m))
                    score += USAGE_PENALTY * self.uses.get(m["id"], 0)
                    if best is None or score < best["score"]:
                        best = {"model": m["id"], "yaw": yaw, "variant": j % 2,
                                "scale": [round(v, 4) for v in scale], "aniso": round(aniso, 3),
                                "score": round(score, 4), "crown": _crown(m),
                                "soft": limit > ANISO_MAX}
            if best is not None:
                return best
        return None

    # ---------------------------------------------------------------- build
    def _pass(self, order: Sequence[int], boxes: Sequence[dict]) -> Tuple[Dict[int, dict], List[dict]]:
        """One full walk of the ring in angular order, with the model palette currently in `self.models`."""
        rows: Dict[int, dict] = {}
        skipped: List[dict] = []
        self.uses = {}
        for k, i in enumerate(order):
            s = boxes[i]
            cx, cy = float(s["center"][0]), float(s["center"][1])
            box = [float(s["size"][0]), float(s["size"][1]), float(s["height"])]
            prev = [rows[order[k - n]] for n in (1, 2) if k - n >= 0 and order[k - n] in rows]
            got = self.pick(box, (cx, cy), prev, avoid=[r["model"] for r in prev])
            forced = got is None
            if forced:
                got = self.pick(box, (cx, cy), prev)
            if got is None:
                skipped.append({"index": i, "reason": "no ring model within anisotropy %.2f"
                                                      % ANISO_SOFT, "box": box})
                continue
            self.uses[got["model"]] = self.uses.get(got["model"], 0) + 1
            rows[i] = dict(got, kind="ring", index=i, forced=forced,
                           pos=[round(cx, 2), round(cy, 2), 0.0],
                           box=[round(v, 2) for v in box], height=round(box[2], 2),
                           radius=round(math.hypot(cx, cy), 1))
        return rows, skipped

    def build(self) -> Tuple[List[dict], List[dict]]:
        """Two passes: fit every box with the whole kit, then keep only the models that earned their
        place and fit again. See `RING_MODELS_MAX` for why the palette is capped."""
        boxes = self.a.lay["skyline"]
        order = sorted(range(len(boxes)), key=lambda i: math.atan2(boxes[i]["center"][1],
                                                                  boxes[i]["center"][0]))
        rows, skipped = self._pass(order, boxes)
        used = sorted(self.uses.items(), key=lambda kv: (-kv[1], kv[0]))
        palette = self._palette(used)
        if len(used) > len(palette):
            print("ring palette: %d models fit; keeping %d — the %d that won the most boxes plus the "
                  "vertical crowns (%s)" % (len(used), len(palette),
                                            len(palette) - RING_VERTICAL_SLOTS, ", ".join(palette)))
            keep = set(palette)
            self.models = [m for m in self.models if m["id"] in keep]
            rows, skipped = self._pass(order, boxes)
        out = [rows[i] for i in sorted(rows)]
        report(out, skipped, len(boxes))
        return out, skipped

    def _palette(self, used: Sequence[Tuple[str, int]]) -> List[str]:
        """The models the second pass is allowed to use: the busiest, plus the busiest vertical crowns."""
        crown_of = {m["id"]: _crown(m) for m in self.models}
        vertical = [mid for mid, _ in used if crown_of.get(mid) in VERTICAL_CROWNS]
        picked = [mid for mid, _ in used if mid not in vertical][:RING_MODELS_MAX - RING_VERTICAL_SLOTS]
        picked += vertical[:RING_VERTICAL_SLOTS]
        return picked[:RING_MODELS_MAX]


def report(rows: Sequence[dict], skipped: Sequence[dict], total: int) -> None:
    aniso = sorted(r["aniso"] for r in rows)
    by_model: Dict[str, int] = {}
    by_crown: Dict[str, int] = {}
    for r in rows:
        by_model[r["model"]] = by_model.get(r["model"], 0) + 1
        by_crown[r["crown"]] = by_crown.get(r["crown"], 0) + 1
    print("ring: %d of %d skyline boxes covered, %d skipped"
          % (len(rows), total, len(skipped)))
    if aniso:
        print("ring anisotropy: p50 %.2f  p90 %.2f  max %.2f  |  <= %.2f: %d  soft: %d"
              % (aniso[len(aniso) // 2], aniso[int(len(aniso) * 0.9)], aniso[-1], ANISO_MAX,
                 sum(1 for v in aniso if v <= ANISO_MAX), sum(1 for r in rows if r.get("soft"))))
    print("ring models: %d  %s" % (len(by_model),
                                  ", ".join("%s:%d" % kv for kv in sorted(by_model.items()))))
    print("ring crowns: %s" % ", ".join("%s:%d" % kv for kv in sorted(by_crown.items())))
    forced = sum(1 for r in rows if r.get("forced"))
    if forced:
        print("ring forced repeats (no other model fits inside the cap): %d" % forced)


def build(a: "Assigner") -> Tuple[List[dict], List[dict]]:
    return Ring(a).build()
