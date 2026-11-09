"""city-kit asset table: the single source of truth for prompts, budgets and placement tags.

Every kit asset is listed once here; concepts, Tripo jobs, Blender processing and the Godot placer all
read this table so an id means the same thing everywhere. `Asset.prompt` is the *object* clause only —
`concept_prompt()` wraps it in the shared style + framing lines (brief: one look for the whole wave).
"""
from __future__ import annotations

from dataclasses import dataclass, field

STYLE = ("golden-dusk Chinese neo-futurist megacity architecture, white stone and pale concrete, "
         "dark glass, bronze accents, restrained cyan and red neon signs with fictional Chinese brands, "
         "Chongqing/Shanghai density, photoreal PBR game asset")

FRAME = ("the whole building isolated and centred on a plain flat light-grey background, three-quarter view "
         "from slightly above, full object visible with empty margin on every side, no ground plane, "
         "no base plate, no other buildings, no people, no cars, no text overlay, crisp clean silhouette edges, "
         "even soft studio lighting")

# r2: the cover kit is props, not architecture — same studio framing, object wording, and no
# "no other buildings" clause (a cover cluster IS a pile of separate objects).
PROP_FRAME = ("the whole object cluster isolated and centred on a plain flat light-grey background, "
              "three-quarter view from slightly above, the full cluster visible with empty margin on every "
              "side, no ground plane, no base plate, no pavement, no people, no text overlay, "
              "crisp clean silhouette edges, even soft studio lighting")

# Height band -> (tri budget LOD0, texture size). Brief §3.
BANDS: dict[str, tuple[int, int]] = {
    # r4: the tower and megablock albedo drops 2K -> 1K. The lead pre-approved it for the case where
    # VRAM was still over 1 GB after the planar and window-mask work, and it is: the kit was at
    # 1 146 MB in r3 and r4 ADDS a window mask per model (up to 2048 for a megablock, whose facade is
    # 38 000-54 000 m2). The trade is 1K albedo + a mask that resolves the panes, rather than a 2K
    # albedo and a pane grid 3 texels across.
    "tower": (40000, 1024),      # D7 supertalls, 128-240 m
    "megablock": (40000, 1024),  # D5 slabs, 128-200 m
    "midrise": (25000, 1024),    # 48-96 m
    "civic": (20000, 1024),      # D4 halls + podium towers
    "oldtown": (20000, 1024),    # D3, 16-56 m
    "industrial": (20000, 1024),  # D1 harbor + D6 foundry
    "street": (12000, 1024),     # L1 podiums, stalls, gates
    "tileable": (6000, 1024),    # straight repeatable segments
    # r2 item 1: arena cover. 1 070 of these stand in a fight, so the budget is the street one and
    # every cover model also ships a ~2 k LOD1 (the arenas are read from 400 m in the vistas).
    "cover": (12000, 1024),
}

# Bands that never skin a layout building: the assigner skips them as building candidates.
PROP_BANDS = frozenset(("street", "tileable", "cover"))


@dataclass(frozen=True)
class Asset:
    """One kit asset: what to generate and how the placer may use it."""
    id: str
    band: str
    districts: tuple[str, ...]          # layout districts it may skin ("" = any)
    archetypes: tuple[str, ...]        # layout archetypes it may skin
    object: str                         # the object clause of the image prompt
    proportions: str                    # explicit proportion clause (keeps Tripo distortion low)
    ar: str = "3:4"                     # concept aspect ratio; gpt4o ignores it, so the proportion
                                        # clause below is what actually controls the image's framing
    native_h: float = 0.0               # intended native height in metres (0 = derive from band)
    tileable: bool = False              # straight, repeatable along its long axis
    lod_tris: int = 0                   # second, cheaper glb for the pieces placed by the thousand
    front_axis: str = "-Y"              # which glTF axis faces the street after processing
    notes: str = ""
    extra_tags: tuple[str, ...] = field(default_factory=tuple)
    frame: str = FRAME                  # framing clause; the cover kit uses PROP_FRAME
    soft: bool = False                  # cover: a breakable piece reads flimsy, a hard one massive
    far: bool = True                    # ships a decimated <id>_far.glb for the 450-1600 m band

    @property
    def tris(self) -> int:
        return BANDS[self.band][0]

    @property
    def tex(self) -> int:
        return BANDS[self.band][1]


def concept_prompt(a: Asset) -> str:
    """Full image->model prompt: object, proportions, shared style, shared framing."""
    return "%s, %s, %s. %s." % (a.object, a.proportions, STYLE, a.frame)


TOWERS = ("slab", "setback", "podium_tower", "twisted")
MIDS = ("slab", "setback", "terrace", "podium_tower")

ASSETS: list[Asset] = [
    # --- D7 / D4 towers -----------------------------------------------------
    Asset("t01", "tower", ("D7",), TOWERS,
          "a glass supertall skyscraper with stepped setbacks, open sky-garden terraces every 40 metres, "
          "and a crown shaped like a stylised pagoda roof",
          "height 6 times its width, square footprint, perfectly straight vertical walls, "
          "no perspective distortion, vertical edges parallel",
          native_h=200.0),
    Asset("t02", "tower", ("D7",), TOWERS,
          "a twisted glass tower whose floor plates rotate slightly as it rises, wrapped in vertical LED fins, "
          "standing on a bronze-clad base podium",
          "height 5 times its width, square footprint, straight vertical silhouette with a gentle twist, "
          "vertical edges nearly parallel",
          native_h=190.0),
    Asset("t03", "tower", ("D7",), TOWERS,
          "a slender tower wrapped in a white steel diagrid exoskeleton with gold accents and a thin antenna "
          "spire on top",
          "height 7 times its width, square footprint, straight vertical walls, diagrid members evenly spaced",
          native_h=210.0),
    Asset("t04", "tower", ("D7",), TOWERS,
          "two identical slender glass tower cores joined near the top by two horizontal glass skybridges",
          "two towers side by side, total width 2.5 times a single core, height 5 times the total width, "
          "straight vertical walls",
          native_h=185.0),
    Asset("t05", "tower", ("D7",), TOWERS,
          "a tower with cantilevered glass sky-garden boxes jutting out at several levels and a glowing halo "
          "ring at the crown",
          "height 5 times its width, square footprint, straight vertical walls, cantilevered boxes symmetric",
          native_h=195.0),
    Asset("t06", "tower", ("D7", "D4"), ("slab", "setback"),
          "a slab-shaped office tower with strong vertical facade fins, a rooftop helipad and a cluster of "
          "antennas",
          "rectangular slab footprint twice as deep as it is wide, height 4 times its width, "
          "straight vertical walls",
          native_h=150.0),
    # --- D5 megablocks ------------------------------------------------------
    Asset("m01", "megablock", ("D5",), ("megablock", "slab"),
          "a massive Kowloon-futurist residential megablock: thousands of small windows, stacked balconies, "
          "air-conditioning units, hanging laundry and tall vertical neon signs down the facade",
          "a huge rectangular slab, height 3 times its width, flat straight facade walls, "
          "regular grid of identical windows",
          native_h=170.0),
    Asset("m02", "megablock", ("D5",), ("megablock",),
          "a residential megablock built around a tall central void, with glass skybridges crossing the void "
          "and green planted terraces inside it",
          "a thick rectangular ring of building seen from outside, height 3 times its width, "
          "straight vertical outer walls",
          native_h=160.0),
    Asset("m03", "megablock", ("D5",), ("megablock", "setback"),
          "a stepped terraced megablock rising in three big steps, each terrace planted, with giant "
          "illuminated billboards on the upper walls",
          "a stepped ziggurat slab, height 2.5 times its base width, straight vertical walls, "
          "clean horizontal step edges",
          native_h=150.0),
    Asset("m04", "megablock", ("D5",), ("megablock",),
          "a brutalist megablock slab with a large rectangular tunnel opening punched clean through its "
          "middle at one third of the height, an elevated railway passing through the opening",
          "a wide rectangular slab, height 2.5 times its width, straight vertical walls, "
          "one clean rectangular through-hole in the centre",
          native_h=140.0, extra_tags=("hole",)),
    # Block 9 is a 130 x 130 x 200 m square tower with the rail punched through it — m04's 2.9:1 slab
    # would need a 3x stretch on one axis, so the square pierced tower is its own asset.
    Asset("m05", "megablock", ("D5", "D4", "D7"), ("megablock", "slab", "podium_tower"),
          "a monumental square brutalist megablock tower with a huge rectangular tunnel opening "
          "punched clean through its base, an elevated railway passing through the opening, deep "
          "recessed window bands and a stepped crown",
          "a square tower, height 1.5 times its width, identical square footprint on every side, "
          "straight vertical walls, one clean rectangular through-hole at the base",
          ar="1:1", native_h=200.0, extra_tags=("hole",)),
    # r9 item 2: the pierced buildings that stayed bare boxes. m05 has the right shape for Block 9 but
    # a stepped crown, and Block 9's roof is walkable — the player would stand on an invisible slab.
    # m06 is the same square pierced tower with a FLAT roof deck, so the landmark can be skinned.
    Asset("m06", "megablock", ("D5", "D4"), ("megablock", "slab", "podium_tower"),
          "a monumental square brutalist megablock tower with a huge rectangular tunnel opening "
          "punched clean through its base at street level, an elevated railway passing through the "
          "opening, deep recessed window bands, and a completely flat rooftop deck with a parapet, "
          "rooftop plant rooms and a helipad marking",
          "a square tower, height 1.5 times its width, identical square footprint on every side, "
          "perfectly straight vertical walls, one clean rectangular through-hole at the base, "
          "a dead-flat horizontal roof",
          ar="1:1", native_h=200.0, extra_tags=("hole",)),
    # D4_p001 and D5_p009 are 56 m wide slabs with a street punched through the FULL width of their
    # base — a gate building, not a tunnel slab. m04's opening leaves piers at the sides, which would
    # stand in the middle of the street.
    Asset("m07", "megablock", ("D4", "D5"), ("podium_tower", "megablock", "slab"),
          "a long neo-futurist gate building: a tall slab whose whole ground floor is one huge "
          "rectangular opening spanning the full width of the building, a city street passing clean "
          "through it under a deep coffered soffit, bronze-clad piers at the two ends only, "
          "recessed window bands above and a flat parapet roof with rooftop plant",
          "a rectangular slab, length 2.3 times its width and height 2.3 times its width, "
          "perfectly straight vertical walls, one clean full-width rectangular opening at the base, "
          "a dead-flat horizontal roof",
          ar="3:4", native_h=132.0, extra_tags=("hole",)),
    # D7_s001 carries a viaduct at 32 m AND a rail at 80 m: two stacked openings, which no single
    # asset in the kit has.
    Asset("m08", "megablock", ("D7", "D4"), ("podium_tower", "slab", "megablock"),
          "a wide brutalist transit building pierced by two stacked rectangular openings: a tall "
          "opening at its base with an elevated highway viaduct passing through it, and a second, "
          "smaller opening higher up with a monorail passing through that, deep recessed window "
          "bands between them and a flat parapet roof",
          "a wide rectangular block, width 1.3 times its depth and height 1.5 times its width, "
          "perfectly straight vertical walls, two clean rectangular through-holes stacked one above "
          "the other, a dead-flat horizontal roof",
          ar="4:3", native_h=136.0, extra_tags=("hole",)),
    # The four thinnest layout boxes (4.2-6.0 m deep, 41-59 m long, 24-36 m tall) are single-file
    # rows built against the plateau edge. Nothing in the kit is under 9 m deep, so they need their
    # own assets rather than a row of squashed towers.
    Asset("w01", "midrise", ("D2", "D4", "D5"), ("podium_tower", "setback", "terrace"),
          "a single-file row of narrow slot houses sharing one continuous street facade: six shallow "
          "units side by side, stacked stepped balconies with plants and hanging laundry, "
          "air-conditioning units, small windows, shop awnings at the base, vertical neon signs and "
          "a tiled parapet roof",
          "an extremely narrow slab: its depth is one ninth of its length and its height is three "
          "quarters of its length, one perfectly flat long facade, dead-straight parallel walls, "
          "a flat parapet roof, flat end walls",
          ar="16:9", native_h=34.0),
    Asset("w02", "midrise", ("D2", "D4", "D5"), ("podium_tower", "setback", "terrace"),
          "a long thin hillside gallery block built against a retaining wall: an open colonnade of "
          "square columns along the ground floor, a continuous balcony walkway with a steel railing "
          "above it, three floors of shuttered windows, hanging laundry, planters and a flat roof "
          "garden with a parapet",
          "an extremely narrow slab: its depth is one twelfth of its length and its height is half "
          "its length, one perfectly flat long facade, dead-straight parallel walls, a flat parapet "
          "roof, flat end walls",
          ar="16:9", native_h=28.0),
    # --- r9 item 1: the skyline-ring masses -----------------------------------------------
    # The 96 horizon boxes are 50-109 m wide and 80-260 m tall — far chunkier than anything else in
    # the kit, whose towers are 28-48 m in plan. Fitting them from the in-city models left 43 of 96
    # boxes with a single candidate and 13 with none inside the anisotropy cap, which is why the first
    # r9 pass put three models on 55 of the 96. These four are the ring's own masses, one per shape
    # cluster measured off `city_layout.json["skyline"]` (tools/citykit/ring.py). `ring_only` keeps
    # them out of the city: they are silhouettes for 700 m and up, not architecture anyone walks past.
    Asset("r01", "megablock", ("",), (),
          "a broad neo-futurist city block tower: a heavy rectangular mass with deep horizontal "
          "recessed window bands, a colonnaded base, corner buttresses and a stepped crown of "
          "setback plant rooms, bronze trim and two tall neon signs",
          "a rectangular tower, its plan 1.2 times longer than it is wide and its height 1.6 times "
          "its length, dead-straight vertical walls, a stepped crown, a flat parapet roof",
          ar="3:4", native_h=160.0, extra_tags=("ring_only",)),
    Asset("r02", "tower", ("",), (),
          "a tall city skyline tower: a slender rectangular shaft with vertical stone piers and dark "
          "glass between them, a bronze crown box and a thin mast with a red aircraft light",
          "a tall rectangular tower, its plan roughly square and its height 2.6 times its width, "
          "dead-straight vertical walls, a stepped crown with a mast",
          ar="3:4", native_h=216.0, extra_tags=("ring_only",)),
    Asset("r03", "megablock", ("",), (),
          "a wide squat city block: a big square mass with a continuous two-storey glazed podium, "
          "deep recessed window bands above, giant illuminated billboards on two faces and a flat "
          "roof garden with a parapet and rooftop plant",
          "a square block, its plan almost square and its height equal to its width, dead-straight "
          "vertical walls, a dead-flat parapet roof",
          ar="1:1", native_h=100.0, extra_tags=("ring_only",)),
    Asset("r04", "tower", ("",), (),
          "a tall thin skyline slab: a long narrow slab tower with strong vertical fins, service "
          "balconies up one flank, a bronze crown band and a cluster of rooftop antennas",
          "a narrow slab, its plan 1.5 times longer than it is wide and its height 2.4 times its "
          "length, dead-straight vertical walls, a flat parapet roof with antennas",
          ar="2:3", native_h=224.0, extra_tags=("ring_only",)),
    # --- D4 civic -----------------------------------------------------------
    Asset("c01", "civic", ("D4",), ("colonnade", "setback"),
          "a neo-Chinese civic hall in white stone with a sweeping curved bronze-edged roof and a long "
          "colonnade of square columns along the front",
          "a low wide building, width 3 times its height, straight vertical colonnade columns, "
          "symmetric front elevation",
          ar="4:3", native_h=60.0),
    Asset("c02", "civic", ("D4",), ("colonnade", "slab"),
          "a monumental archive block whose whole facade is screened by a deep bronze lattice, with a "
          "recessed glass wall behind it",
          "a solid rectangular block, width 2 times its height, straight vertical walls, flat roof",
          ar="4:3", native_h=52.0),
    Asset("c03", "civic", ("D4",), ("podium_tower",),
          "a white stone tower rising from a broad podium whose entrance is a giant bronze gate motif, "
          "the tower stepping back twice as it rises",
          "a wide podium one third of the total height with a slender tower above it, "
          "total height 3 times the podium width, straight vertical walls",
          native_h=120.0),
    Asset("c04", "civic", ("D4",), ("setback", "terrace"),
          "a terraced museum hall in white stone, three broad planted roof gardens stepping back, "
          "deep bronze window reveals",
          "a low stepped building, width 2.5 times its height, straight walls, clean horizontal terraces",
          ar="4:3", native_h=48.0),
    # --- mid-rise (D2 / D4 / D7) -------------------------------------------
    Asset("b01", "midrise", ("D2", "D4", "D7"), MIDS,
          "a plain apartment tower with stacked balconies, a rooftop water tank and one vertical neon sign",
          "height 3 times its width, rectangular footprint, straight vertical walls, "
          "regular identical floors",
          native_h=72.0),
    Asset("b02", "midrise", ("D2", "D4", "D7"), MIDS,
          "a slim hotel tower with a tall vertical neon sign running its full height and a lit crown box "
          "on the roof",
          "height 4 times its width, narrow rectangular footprint, straight vertical walls",
          native_h=80.0),
    Asset("b03", "midrise", ("D2", "D4", "D7"), MIDS,
          "an office mid-rise with strong vertical stone fins and one fully glazed corner running the "
          "full height",
          "height 2.5 times its width, square footprint, straight vertical walls, evenly spaced fins",
          native_h=64.0),
    Asset("b04", "midrise", ("D2", "D4", "D7"), ("podium_tower", "terrace", "setback"),
          "a mixed-use block: a two-storey shop podium with awnings, stepped planted terraces above it",
          "height 2 times its width, wide rectangular footprint, straight vertical walls, "
          "clean horizontal terrace edges",
          ar="4:3", native_h=56.0),
    Asset("b05", "midrise", ("D2", "D4", "D7"), ("slab", "setback"),
          "a stacked capsule-housing tower: rows of identical prefabricated concrete pods with round "
          "windows bolted onto a concrete core",
          "height 3 times its width, narrow rectangular footprint, straight vertical core walls, "
          "pods in a regular grid",
          native_h=60.0),
    # --- D3 old town --------------------------------------------------------
    Asset("o01", "oldtown", ("D3",), ("terrace", "pagoda", "slab"),
          "a Chongqing stilt house (diaojiaolou) of dark timber standing on tall thin stilts against a "
          "slope, with grey tiled roofs, wooden balconies and red lanterns",
          "a tall narrow house raised on stilts, height 2 times its width, straight vertical stilts, "
          "steep tiled roofs",
          native_h=32.0, extra_tags=("slope",)),
    Asset("o02", "oldtown", ("D3",), ("terrace", "slab"),
          "a terrace of old-town shop-houses: three narrow houses side by side, wooden balconies, "
          "grey tiled roofs, red lanterns and hanging shop banners",
          "a row of three narrow houses, total width 2 times the height, straight vertical walls, "
          "even roof ridge",
          ar="4:3", native_h=24.0, extra_tags=("row",)),
    Asset("o03", "oldtown", ("D3",), ("slab", "terrace"),
          "a narrow six-storey grey-plaster tenement with a tiled roof, laundry lines strung across the "
          "front, air-conditioning units and barred windows",
          "a very narrow tall building, height 3 times its width, straight vertical walls, "
          "flat facade with regular windows",
          native_h=30.0),
    Asset("o04", "oldtown", ("D3",), ("pagoda", "terrace"),
          "a two-storey wooden teahouse with upturned eaves, red columns, a wrap-around balcony walkway "
          "and paper lanterns",
          "a wide low pavilion, width 1.6 times its height, symmetric front, straight columns, "
          "curved eave roof",
          ar="4:3", native_h=20.0),
    Asset("o05", "oldtown", ("D3",), ("terrace",),
          "a cluster of stacked hillside homes climbing over each other in steps, with outside staircases, "
          "grey tiled roofs and laundry lines",
          "an irregular stepped cluster, total width 2 times its height, all walls vertical, "
          "stairs on the outside",
          ar="4:3", native_h=40.0, extra_tags=("slope",)),
    Asset("o06", "oldtown", ("D3",), ("slab", "warehouse"),
          "an old-town market hall with a big grey tiled hip roof, an open colonnade of red columns and "
          "neon signs along the eaves",
          "a wide low hall, width 2.5 times its height, straight vertical columns, one big roof",
          ar="4:3", native_h=22.0),
    # --- D1 harbor ----------------------------------------------------------
    Asset("h01", "industrial", ("D1",), ("warehouse",),
          "a weathered port warehouse of corrugated steel with roller shutter doors and a gantry crane "
          "rail running along its roof",
          "a long low box, length 3 times its height, straight vertical walls, flat roof, "
          "evenly spaced roller doors",
          ar="4:3", native_h=14.0, extra_tags=("long",)),
    Asset("h02", "industrial", ("D1",), ("slab", "setback"),
          "a port office tower with a cantilevered glazed control room on top and a red-and-white "
          "antenna mast",
          "height 3 times its width, square footprint, straight vertical walls, control room overhanging",
          native_h=56.0),
    Asset("h03", "industrial", ("D1",), ("warehouse", "industrial"),
          "a long customs hall with a sawtooth north-light roof of glass and steel, stone end walls "
          "and a bronze crest over the entrance",
          "a long low building, length 3 times its height, straight vertical walls, "
          "regular sawtooth roof profile",
          ar="4:3", native_h=18.0, extra_tags=("long",)),
    # --- D6 foundry ---------------------------------------------------------
    Asset("f01", "industrial", ("D6",), ("industrial", "warehouse"),
          "a dark industrial hall with a sawtooth roof, external pipe racks, steel stairs and hazard "
          "stripes along its base",
          "a long box, length 2.5 times its height, straight vertical walls, regular sawtooth roof",
          ar="4:3", native_h=26.0, extra_tags=("long",)),
    Asset("f02", "industrial", ("D6",), ("industrial", "stack"),
          "a heavy reactor building with two concrete domes, ventilation stacks, external catwalks and "
          "faint orange glow from its vents",
          "a compact block, width 1.5 times its height, straight vertical walls, two domes on top",
          ar="4:3", native_h=44.0),
    Asset("f03", "industrial", ("D6",), ("industrial",),
          "a long straight industrial pipe-rack bridge: a steel truss frame carrying six parallel pipes "
          "on top, with a walkway and handrail",
          "a long straight horizontal structure, length 8 times its height, perfectly straight and "
          "uniform along its length, flat ends",
          ar="4:3", native_h=8.0, tileable=True, lod_tris=2500, extra_tags=("pipe_rack",)),
    Asset("f04", "industrial", ("D6",), ("stack",),
          "a cluster of one large concrete cooling tower and three tall brick chimneys bound together by "
          "steel walkways",
          "total height 2.5 times the total width, all chimneys perfectly vertical, cooling tower a "
          "clean hyperboloid",
          native_h=96.0),
    # --- L1 street pieces ---------------------------------------------------
    Asset("s01", "street", ("",), ("podium_tower", "slab", "megablock", "terrace", "setback"),
          "a street-level shopfront podium block of three floors: a deep arcade of square columns at the "
          "ground floor, striped awnings, glass shop windows and small neon shop signs above",
          "a long low block, length 3 times its height, straight vertical columns, flat roof with a "
          "parapet, shop bays evenly spaced",
          ar="4:3", native_h=12.0, lod_tris=6000, extra_tags=("podium", "frontage")),
    Asset("s02", "street", ("",), (),
          "a metro station entrance: a glass and steel canopy on slender columns over a stair opening, "
          "with a lit cyan sign band and bollards",
          "a small low structure, width 2 times its height, straight columns, one flat glass roof",
          ar="4:3", native_h=6.0, extra_tags=("entrance",)),
    Asset("s03", "street", ("",), (),
          "a row of street-market stalls under bright fabric umbrellas, with steel frames, crates and "
          "small hanging signs",
          "a long low row, length 4 times its height, umbrellas in an even line, straight stall frames",
          ar="4:3", native_h=4.0, lod_tris=800, extra_tags=("market",)),
    Asset("s04", "street", ("",), (),
          "a neo-futurist Chinese paifang memorial arch gate: four stone pillars carrying three stacked "
          "bronze-edged roof beams, with cyan light strips along the beams",
          "a wide gate, width 1.5 times its height, perfectly symmetric front elevation, "
          "pillars vertical and evenly spaced",
          ar="4:3", native_h=14.0, extra_tags=("gate",)),
    Asset("s05", "street", ("",), (),
          "an elevated-highway pylon: a tapered concrete pier with a wide pier cap, cable trays and "
          "service lights climbing its side",
          "a single vertical pier, height 3 times its width, straight vertical shaft, "
          "symmetric front elevation",
          native_h=28.0, extra_tags=("pylon",)),
    Asset("s06", "tileable", ("",), (),
          "a straight glass skybridge tube segment: a steel space-frame tube fully glazed, with a flat "
          "floor deck inside and identical square ends",
          "a straight horizontal tube, length 4 times its diameter, perfectly straight and uniform "
          "along its length, both ends cut flat and identical",
          ar="4:3", native_h=6.0, tileable=True, lod_tris=2500, extra_tags=("skybridge",)),
    Asset("s07", "tileable", ("",), (),
          "a straight futuristic guardrail segment: a steel post-and-panel railing with a continuous "
          "cyan light strip along the top rail and a kick plate at the bottom",
          "a straight horizontal railing, length 10 times its height, perfectly straight and uniform "
          "along its length, both ends identical, no end posts",
          ar="4:3", native_h=1.4, tileable=True, lod_tris=350, extra_tags=("railing",)),
    Asset("s08", "street", ("",), (),
          "a rooftop machinery cluster: three boxy air-conditioning units, two cylindrical water tanks, "
          "a lattice antenna mast and connecting pipework on a small concrete pad",
          "a low wide cluster, width 2 times its height, all units sitting flat on one level base, "
          "antenna mast vertical",
          ar="4:3", native_h=8.0, lod_tris=2000, extra_tags=("roof",)),
    # --- r2 item 3: long slabs for the extreme-aspect boxes wave 1 could not fit -------------
    # The 33 skipped boxes are 3:1 to 6:1 in plan (40 x 152 m slabs, 28 x 11 m slots). A single
    # tower model on those needs a 3x stretch on one axis, so they get their own long archetypes.
    Asset("l01", "megablock", ("D5", "D2"), ("megablock", "slab"),
          "a very long Kowloon-futurist residential slab block: one continuous facade of thousands of "
          "small windows, stacked balconies, air-conditioning units and vertical neon signs, with two "
          "stair towers breaking the length",
          "an extremely long rectangular slab, length 5 times its height and 12 times its depth, "
          "perfectly straight parallel facade walls, flat roof line, one flat end wall at each end",
          ar="16:9", native_h=64.0, extra_tags=("long",)),
    Asset("l02", "industrial", ("D1", "D2"), ("warehouse", "industrial", "slab"),
          "a very long low port shed row: a continuous run of corrugated-steel warehouses with a "
          "sawtooth roof, roller shutter doors in an even rhythm and a bronze fascia band",
          "an extremely long low building, length 6 times its height and 14 times its depth, "
          "perfectly straight parallel walls, one flat end wall at each end, even roof rhythm",
          ar="16:9", native_h=22.0, extra_tags=("long",)),
    Asset("l03", "midrise", ("D2", "D4", "D5"), ("slab", "terrace", "megablock"),
          "a long mixed-use terrace block: a continuous arcade of shops with awnings at street level "
          "and five identical floors of flats with balconies and laundry above",
          "a long rectangular block, length 4 times its height and 10 times its depth, perfectly "
          "straight parallel walls, flat parapet roof, one flat end wall at each end",
          ar="16:9", native_h=40.0, extra_tags=("long",)),
    # --- r2 item 4: the structures that are still bare slabs ---------------------------------
    Asset("u01", "tileable", ("",), (),
          "a straight elevated-deck edge section seen from below and outside: a deep concrete edge "
          "fascia beam with a bronze drip rail, a run of cyan light strips under the lip, and a ribbed "
          "concrete soffit with service conduits on the underside",
          "a straight horizontal beam section, length 8 times its depth, perfectly straight and uniform "
          "along its length, both ends cut flat and identical, one flat top face",
          ar="16:9", native_h=6.0, tileable=True, lod_tris=2500, extra_tags=("fascia",)),
    Asset("u02", "tileable", ("",), (),
          "a straight elevated-highway parapet section: a heavy concrete crash barrier with a steel "
          "top rail, translucent noise-barrier panels above it and hazard chevrons on the face",
          "a straight horizontal parapet, length 8 times its height, perfectly straight and uniform "
          "along its length, both ends cut flat and identical",
          ar="16:9", native_h=4.5, tileable=True, lod_tris=1800, extra_tags=("parapet",)),
    # --- r2 item 1: the arena cover kit -----------------------------------------------------
    # Every arena cover box in the layout is 16-33 m in plan and 8-28 m tall, so each model is a
    # CLUSTER of one kind of object at roughly that size; the assigner fits, tiles or stacks it.
    #
    # Lead note (city-art 5c08f44): every cover piece ALREADY wears a procedural container-door
    # skin, so a Tripo model only earns its 65 credits where it changes the SILHOUETTE — the wide
    # shot captures/look_city-art_cover_after_wide.jpg is a canyon of identical flat walls. Plain
    # container stacks were dropped from this list for that reason; what is here is round, tilted,
    # broken or skeletal.
    Asset("k01", "cover", ("",), (),
          "a downed bipedal combat mech used as battlefield cover: a heavy humanoid war machine "
          "collapsed onto one knee and one shattered arm, torn bronze and white armour plates, an "
          "exposed hydraulic spine, a broken cannon barrel resting on the ground",
          "an irregular angular wreck, total height 1.2 times its width, one thick leg vertical, "
          "the torso leaning at a clear diagonal, no straight box shapes anywhere",
          ar="1:1", native_h=22.0, frame=PROP_FRAME, lod_tris=2200,
          extra_tags=("hard", "wreck")),
    Asset("k02", "cover", ("",), (),
          "a cluster of three enormous cylindrical fuel tanks lying on a steel cradle frame, one "
          "ruptured and tilted off the frame, wrapped in pipework with a catwalk over the top",
          "a blocky arrangement of big cylinders, total height 0.9 times its width, every tank a "
          "perfect straight cylinder, the cradle a rectangular steel frame",
          ar="4:3", native_h=14.0, frame=PROP_FRAME, lod_tris=2200,
          extra_tags=("hard", "round")),
    Asset("k03", "cover", ("",), (),
          "a cluster of large cargo crates lashed to steel pallets, banded with strapping, stencilled "
          "with shipping marks, stacked two high with one crate tilted off the pile",
          "a blocky pile, width 1.3 times its height, crates rectangular with straight edges, "
          "stack roughly rectangular overall",
          ar="4:3", native_h=12.0, frame=PROP_FRAME, lod_tris=2200, soft=True,
          extra_tags=("soft",)),
    Asset("k04", "cover", ("",), (),
          "a zigzag line of heavy precast concrete jersey barriers with scuffed paint, hazard chevrons "
          "and a steel fence panel bolted along the top of part of the line",
          "a long low line of barriers, length 3 times its height, every barrier straight and upright, "
          "even spacing along the line",
          ar="16:9", native_h=5.0, frame=PROP_FRAME, lod_tris=1400,
          extra_tags=("hard", "line")),
    Asset("k05", "cover", ("",), (),
          "a flimsy barricade of stacked sandbags and bolted steel plates on a light scaffold frame, "
          "bending under its own weight, with a torn warning banner",
          "a long low barricade, length 2.5 times its height, thin bent panels, visibly lightweight "
          "and improvised",
          ar="16:9", native_h=6.0, frame=PROP_FRAME, lod_tris=1400, soft=True,
          extra_tags=("soft", "line")),
    Asset("k06", "cover", ("",), (),
          "a wrecked hover-truck: a heavy cab crushed at the front, hovering skirts deflated, still "
          "coupled to a container trailer that has jack-knifed sideways",
          "a long low vehicle, length 3 times its height, wheels and skirts level, one flat container "
          "box on the trailer",
          ar="16:9", native_h=8.0, frame=PROP_FRAME, lod_tris=2200,
          extra_tags=("hard", "long")),
    Asset("k07", "cover", ("",), (),
          "a heavy industrial transformer unit: a riveted steel tank with vertical radiator fins, "
          "ceramic bushings and cable trays on top, hazard stripes along its concrete plinth",
          "a compact upright machine, height 1.3 times its width, a single straight rectangular tank, "
          "vertical fins evenly spaced",
          ar="1:1", native_h=16.0, frame=PROP_FRAME, lod_tris=2200,
          extra_tags=("hard", "tall")),
    Asset("k08", "cover", ("",), (),
          "a stack of enormous wooden cable drums with thick coiled power cable, three drums standing "
          "and two lying on their sides against them",
          "a blocky pile, width 1.5 times its height, drums perfect circles with straight flat sides, "
          "stack roughly rectangular overall",
          ar="4:3", native_h=12.0, frame=PROP_FRAME, lod_tris=2200, soft=True,
          extra_tags=("soft",)),
    Asset("k09", "cover", ("",), (),
          "a collapsed advertising billboard: a buckled steel lattice mast folded over, its huge torn "
          "LED screen panel lying face-up across broken concrete rubble",
          "a wide low pile, width 2 times its height, one large flat rectangular screen panel, "
          "straight lattice members",
          ar="4:3", native_h=12.0, frame=PROP_FRAME, lod_tris=2200, soft=True,
          extra_tags=("soft",)),
    Asset("k10", "cover", ("",), (),
          "a construction-site hoarding: a long run of thin painted steel fence panels on light feet, "
          "with pasted posters, a mesh gate and a few scaffold poles leaning against it",
          "a long thin fence, length 4 times its height, panels perfectly flat and vertical, "
          "evenly spaced along the run",
          ar="16:9", native_h=7.0, frame=PROP_FRAME, lod_tris=1200, soft=True,
          extra_tags=("soft", "line")),
    Asset("k11", "cover", ("",), (),
          "a heavy pile of demolition rubble: broken reinforced-concrete slabs leaning against each "
          "other with bent rebar, a snapped column and drifted dust",
          "a broad low mound, width 1.8 times its height, large flat slab faces, angular chunks, "
          "a roughly triangular silhouette",
          ar="4:3", native_h=12.0, frame=PROP_FRAME, lod_tris=2200,
          extra_tags=("hard",)),
    Asset("k12", "cover", ("",), (),
          "a stack of large precast concrete pipe sections and culvert rings piled in a pyramid, with "
          "a tall steel cement silo standing behind them",
          "an upright pile, total height 1.2 times its width, pipe sections perfect rings, "
          "the silo a straight vertical cylinder",
          ar="1:1", native_h=18.0, frame=PROP_FRAME, lod_tris=2200,
          extra_tags=("hard", "tall")),
]

BY_ID: dict[str, Asset] = {a.id: a for a in ASSETS}


def pick(ids: list[str]) -> list[Asset]:
    return [BY_ID[i] for i in ids]
