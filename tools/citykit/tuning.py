"""Tuning constants for the kit fitting (brief step 5). Named here so both `assign.py` and
`pieces.py` can read them without importing each other.
"""

ANISO_MAX = 1.30       # brief step 5: the architecture must not read stretched
ANISO_SOFT = 1.90      # accepted only when nothing better exists, and reported per row as `soft`
# The height window is wide because the anisotropy cap already bounds the stretch; a narrow window
# only starves the search (measured: 0.50-2.00 covers 85.2 % of the city, 0.35-2.80 covers 90.3 %,
# with the median anisotropy unchanged at 1.24).
HR_LO, HR_HI = 0.35, 2.80
NEIGHBOUR_R = 60.0     # no two neighbours within this radius share a model
NEIGHBOUR_PENALTY = 4.50   # a twin next door loses to any clean pick, even one from a looser tier ...
TIER_PENALTY = 0.80        # ... but a clean pick from the strict tier still wins (0.8 * 3 = 2.4 < 4.5)
FRONT_BONUS = 0.30     # cost of turning the model's detailed face away from its street
TILE_PENALTY = 0.50    # r2 item 3: three copies end to end is worse than two, all else equal
TILE_MAX = 4           # r9: copies per axis. 4 x 1 covers a 5 x 49 m wall; 2 x 2 covers a 130 m square
TILE_MAX_COPIES = 6    # ... but never more than six models standing in for one layout building
MIN_COPY_M = 8.0       # a divided axis must leave a copy at least this wide; a whole axis is exempt
PODIUM_H = 12.0        # shopfront podium height, metres
PODIUM_NEAR = 150.0    # "near an arena or the Spire plaza"
GATE_NEAR = 90.0       # paifang reach from an arena outline
PODIUM_DEPTH = 10.0    # shopfront podium depth, metres
USAGE_PENALTY = 0.06    # spread the variants: without it the four D7 towers never win a box and the
                       # most striking models in the kit (t02 twisted, t03 diagrid, t05 halo) stay unused
MARKET_NEAR = 120.0     # market stalls: a tight ring around the arenas, not the whole city
MARKET_MAX = 12         # stalls per street — a row, not a continuous market
RAIL_SEG = 28.0        # railing segment length: the model is 6.4 m and uniform along its run, so a
                       # 3.7x stretch is invisible and cuts the instance count by 3.7
RAIL_NEAR = 300.0      # railings only where they are READ: the arenas, the Spire plaza and every
                       # viaduct. 26 km of deck edge at 1 570 tris a segment was 3.4 M triangles of
                       # fence that, past 400 m, renders as the dotted noise the lead flagged in V6 —
                       # so a deck further than this from the fight gets the u01 fascia and no rail.
FASCIA_SEG = 24.0      # u01 deck-edge beam: a 24 m run of a uniform section reads the same as a 16 m
                       # one and 26 km of elevated deck edge is 1 100 segments instead of 1 650
PARAPET_SEG = 20.0     # u02 viaduct parapet, same reasoning over 5.2 km of viaduct

# --- r2: arena cover -----------------------------------------------------------------------
COVER_FILL_MIN = 0.72  # the cluster has to cover its collision box; below this it reads as a toy
                       # standing inside an invisible crate the player is shooting at
COVER_MAX_COPIES = 3   # copies per axis for a box that is not a slot; slots get one more
COVER_TRIS_PER_BOX = 30000  # LOD triangles one cover box may spend. This is the lever that decides
                            # whether a cover model is usable at all: a 24 x 25 x 20 m box needs
                            # SEVEN 3.4 m barrier lines across it to stop reading as a box, so a
                            # 1 400-tri line may be tiled 21x and a 2 200-tri crate pile only 13x.
COVER_STRETCH = 1.0    # every cover copy is scaled UNIFORMLY (brief: stack/tile, never stretch)

# Candidate tiers, strictest first: (district, archetype, height band must all match).
TIERS = ((True, True, True), (True, False, True), (True, True, False), (False, False, True))

# Models whose top is a usable deck rather than a crown, spire or mast (judged from captures/kit/*.jpg).
# A roof-walkable layout building keeps its collision box, so the player stands on an invisible slab:
# the model on it has to reach that height with a roof, not with a pagoda finial.
FLAT_TOP = frozenset("t06 m01 m02 m03 m04 c01 c02 c03 c04 b01 b03 b04 b05 "
                     "o01 o02 o03 o04 o05 o06 h01 h03 f01 f02 s01".split())
