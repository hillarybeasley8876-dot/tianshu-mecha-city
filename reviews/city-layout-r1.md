# city-layout — review r1 (lead) — FAIL (pipeline right; density + crown shape; decisions made)

Verified myself: validate_graph (only C11 A4→A5 fails), validate_layout PASS with your printed numbers; plan,
iso, section, street H0 and Sky Garden previews reviewed. Old Town now reads dense, the Ring Viaduct is one loop,
supports are declared, vistas are honest. Your diagnosis is right: the adopted corridors leave no land.
Lead decisions (MAP §4 "General" updated — read it): widths from our 24 m dodge (avenue 56–72, street 36–48,
alley 24–32); **podium-through** buildings over streets; revised coverage/frontage targets; circular crown;
C11 A4→A5 accepted.

## MUST-FIX
1. Apply the new widths (corridors.py) and re-run everything; print the land freed per district.
2. **Podium-through**: lots may straddle streets: podium footprint over the street with an arcade hole
   (`holes`: street width × ≥ 32 m clear, z 0), towers on top; emit them as buildings with `through` = street
   ids; L2 must accept them; city-build gets the arcade geometry from the hole data. Use it to build street
   walls in D4/D5/D7 (canyons along avenues and the Spire avenue).
3. Targets: D3 ≥ 60 %, D5 ≥ 55 %, D6 ≥ 40 %, D1/D2 ≥ 35 %, D4/D7 ≥ 40 %; avenue frontage ≥ 50 %; keep Spire
   visibility ≥ 80 % (if tall mass threatens it, cap heights inside the Spire's view cones instead of thinning).
4. **D5 Megablocks** must read as a wall of 128–200 m megablocks around the canyon with skybridges at +80/+128
   (today mostly empty); **D7 Financial**: towers 128–240 m on podiums between and over the converging streets
   so the Sky Garden (+144) and Crystal Bridge (+176) are surrounded by glass towers, as in key art.
5. **Crown deck B**: circle Ø 300 m at +224 with a stepped rim and 4 fins (24 m) at 45°, central core Ø 80 m;
   update the polygon + the section/iso previews.
6. Mark C11 A4→A5 as an accepted exception in validate_graph (allow-list with the reason) so the run is PASS.
7. Previews: render the street views with buildings shaded by height and decks with their supports drawn, plus
   two more street views (Spire Avenue at 20 m looking north; Megablock canyon floor V4).
