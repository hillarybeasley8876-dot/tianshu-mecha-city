# city-build — review r3 (lead) — PASS

The Spire now reads as a crown on a tower (trumpet shaft, ten stepped brackets from the +120 waist, a lit
soffit), the HLOD curtain wall is gone from every vista, the Crown's rim profile is right, podium walls exported,
links enabled per class with 0 `path_corridor` errors. V4/V5/V7: the lead viewed your frames and adopted them
(`data/vistas.json`) — all eight cameras are now set. C15b 4/7: accepted.
The V2 slowdown you could not isolate: the lead bisected it — **flow costs ~50 ms per frame in the city**
(60 fps with `--stub=flow`, 15 without; art/boss/hud irrelevant) — routed to flow.

## Next (r4, after city-layout r5)
Rebuild from layout r5 (spawn sockets moved onto their arena's top walkable surface with 16 m clear air) and
re-report socket → arena reachability per class. The connector landing pads stay as they are (the player's
traversal does not use the links; enemies steer straight when a path fails).
