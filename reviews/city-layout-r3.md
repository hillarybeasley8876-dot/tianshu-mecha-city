# city-layout — review r3 (lead) — PASS (layout frozen for city-build; changes only on its requests)

Verified: `validate_graph` PASS (C11 accepted), `validate_layout` PASS incl. L10 (225 waypoints / 664 edges,
one component, ≥ 24 per district, ≥ 6 per arena, 12 around the Crown); Spire visibility 89.7 %; vistas
unchanged; plan, crown-north and Sky-Garden-up views reviewed. The Civic Quarter fills the north plateau and
gives the Spire a backdrop (D4 79 %), D7 is ringed by 8 towers 128–240 m with 3 ≥ 200 m, the Old Town is now
contiguous terraces (67 %), overhead cover is architecture near arenas only (54 % / 1 %), and every district is
over its buildable-land target. The `largest_inscribed_rect` fast-path find was the real unlock — good.

Decision on your request: keep the corridors. Two straddling towers are enough to sell the Liziba image as
long as the player passes THROUGH them on a traversal route — city-build will light those holes as set
pieces (a lit tunnel through the tower, signage, the rail visible entering and leaving). No graph change.

Preview nit for any later round: the legend box hides the Old Town in the plan — move it outside the map.
