"""Load and normalise `data/map/city_layout.json` (city-build). Read-only: the city is built
from the JSON and nothing else, so a layout revision costs one rebuild."""
import json
import math
import os

ROOT = os.path.expanduser("~/m/mecha-city")
LAYOUT = os.path.join(ROOT, "data", "map", "city_layout.json")
LEVEL_GRAPH = os.path.join(ROOT, "data", "map", "level_graph.json")
VISTAS = os.path.join(ROOT, "data", "vistas.json")

# MAP.md 1 tuning constants the geometry has to agree with.
H = 16.0            ## mech height
CAPSULE_R = 4.0
FLOOR = 4.0         ## facade module (ART.md 4)
PARAPET = (4.0, 6.0)
GROUND_CRUST = 6.0  ## thickness of the walkable ground slab
BOUNDS_HALF = 700.0


class Layout:
    """Typed-ish access to the layout file plus the small helpers every builder needs."""

    def __init__(self, path: str = LAYOUT):
        with open(path) as fh:
            self.data = json.load(fh)
        # Kept so a writer can stamp the file its rows came from (city-art r12 §3 `markers.py`).
        self.path = path
        self.meta = self.data["meta"]
        self.bounds = self.data["bounds"]
        self.terrain = self.data["terrain"]
        self.streets = self.data["streets"]
        self.viaducts = self.data["viaducts"]
        self.rails = self.data["rails"]
        self.tunnels = self.data["tunnels"]
        self.decks = self.data["decks"]
        self.buildings = self.data["buildings"]
        self.connectors = self.data["connectors"]
        self.arenas = self.data["arenas"]
        self.landmarks = self.data["landmarks"]
        self.hives = self.data["hives"]
        self.anchors = self.data["anchors"]
        self.skyline = self.data["skyline"]
        self.player_start = self.data["player_start"]
        self.sky_waypoints = self.data.get("sky_waypoints", [])
        self.sky_edges = self.data.get("sky_edges", [])
        self.nodes = {n["id"]: n for n in json.load(open(LEVEL_GRAPH))["nodes"]}
        self.districts = sorted({b["district"] for b in self.buildings})

    # ------------------------------------------------------------------ queries
    def by_district(self, district):
        """Every structure whose home district is `district` (None = all)."""
        if district is None:
            return self
        want = district.upper()
        keep = lambda rows: [r for r in rows if str(r.get("district", "")).upper() == want]
        out = Layout.__new__(Layout)
        out.__dict__.update(self.__dict__)
        out.buildings = keep(self.buildings)
        out.decks = keep(self.decks)
        out.streets = keep(self.streets)
        out.viaducts = keep(self.viaducts)
        out.rails = keep(self.rails)
        out.tunnels = keep(self.tunnels)
        out.connectors = keep(self.connectors)
        out.landmarks = keep(self.landmarks)
        out.arenas = keep(self.arenas)
        out.anchors = [a for a in self.anchors if str(a.get("arena", "")).upper() == want
                       or _near_any(a["pos"], [ar["polygon"] for ar in out.arenas])]
        return out

    def landmark(self, kind):
        for lm in self.landmarks:
            if lm["kind"] == kind:
                return lm
        return None


def _near_any(pos, polys, limit=400.0):
    for poly in polys:
        for p in poly:
            if math.hypot(pos[0] - p[0], pos[1] - p[1]) < limit:
                return True
    return False


def poly_center(poly):
    return (sum(p[0] for p in poly) / len(poly), sum(p[1] for p in poly) / len(poly))


def poly_bounds(poly):
    xs = [p[0] for p in poly]
    ys = [p[1] for p in poly]
    return min(xs), min(ys), max(xs), max(ys)


def path3(points, z):
    """A 2D corridor polyline lifted to a constant height."""
    return [(p[0], p[1], z) for p in points]


def path_len(points):
    return sum(math.dist(a, b) for a, b in zip(points, points[1:]))


def segment_quad(a, b, width):
    """Plan quad covering a segment of a corridor `width` wide (used for ground cuts)."""
    dx, dy = b[0] - a[0], b[1] - a[1]
    length = math.hypot(dx, dy)
    if length < 1e-6:
        return []
    nx, ny = -dy / length * width * 0.5, dx / length * width * 0.5
    return [(a[0] + nx, a[1] + ny), (b[0] + nx, b[1] + ny),
            (b[0] - nx, b[1] - ny), (a[0] - nx, a[1] - ny)]


def densify(points, step):
    """Insert points so no segment is longer than `step` (keeps sweeps and cuts stable)."""
    out = [tuple(points[0])]
    for a, b in zip(points, points[1:]):
        d = math.dist(a[:2], b[:2])
        n = max(1, int(math.ceil(d / step)))
        for k in range(1, n + 1):
            t = k / n
            out.append(tuple(a[i] + (b[i] - a[i]) * t for i in range(len(a))))
    return out


def load_vistas():
    with open(VISTAS) as fh:
        return json.load(fh)["vistas"]
