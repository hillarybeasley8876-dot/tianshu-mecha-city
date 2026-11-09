# city-layout — review r2 (lead) — PASS for city-build; r3 = focused additions (runs in parallel)

Verified myself: `validate_graph` PASS (C11 A4→A5 accepted NOTE), `validate_layout` PASS (L1–L9), your coverage /
frontage / visibility numbers reproduce; plan, iso SW/NE, section and the four street views reviewed. The
Megablock Canyon now reads as a wall with skybridges, podium-through works, the circular Crown is right, the
vistas are honest. **city-build starts now on v2** — so r3 must keep the file backward-compatible (additive
fields only; existing ids keep their meaning).

## Answers to your requests (MAP §3/§4 updated — read them)
1. **D7**: neither move the Ring Viaduct nor accept a low district. New rule **viaduct/rail-through**: in
   D4/D5/D7 a tower may straddle the Ring Viaduct (+32) or the Skyrail (+80); the corridor runs through a hole =
   corridor width + 2 × 4 m, clear ≥ 40 m above the viaduct deck / ≥ 32 m above the rail (Chongqing Liziba —
   the train through the building is exactly the image we want). Declare it as `holes` + `through` on the
   building and `through` on the corridor; L2 accepts it.
2. **Coverage**: yes, measure against buildable land (your definition), print both. Targets on buildable land:
   D3 ≥ 65 %, D5 ≥ 75 %, D7 ≥ 60 %, D2/D4/D6 ≥ 50 %, D1 ≥ 40 %.
3. city-build gets the v2 fields from MAP §3 and its brief.
4. V6 framed by the canyon walls: accepted — keep it.

## MUST-FIX (r3)
1. **D4 north plateau is a void**: x −150…250, y 450…700 (≈ 10 ha) is empty behind the Forum — it is what you
   see from the Crown during the whole boss fight and from every view facing north. Build the **Civic
   Quarter** there (MAP §4 D4 row): a street grid on +32 continuing the D3/D5 corridors and tied to S5 / the O-
   and M-nodes, civic archetypes (setback halls, podium towers, a colonnaded archive block), heights 48–144 m
   rising toward the north edge so the Spire stands in front of a backdrop from the south (keep the Spire view
   cone cap). Counts in D4 coverage.
2. **D7 skyline** via rule 1: the Sky Garden (+144) and the Crystal Bridge (+176) ringed by ≥ 8 towers 128–240 m
   within 260 m, ≥ 3 of them ≥ 200 m; the A6 arena stays open to the sky above its deck (towers around, never
   over). Keep Spire visibility ≥ 80 % and the vistas.
3. **Overhead cover** (MAP §4 revised): 60 % of ALL L1 street length under slabs reads as floating plates, kills
   the dusk light shafts and costs shadow draws. Inside arenas and within 100 m of their outline 40–60 %;
   elsewhere ≤ 25 %, and only by structures that read as architecture (podium decks spanning between
   buildings, skybridges, viaducts, rails). Remove free-standing canopies outside arenas; every remaining deck
   has `columns` at ≤ 48 m or a `span` between two buildings. Print both percentages.
4. **Sky graph** (missed from the r1 lead notes): `sky_waypoints` + `sky_edges` per MAP §3 — +60…+250 m, nodes
   ≥ 12 m and edges ≥ 8 m clear of every building/deck/rail box, one connected graph, ≥ 24 nodes per district,
   ≥ 6 within 150 m of each arena centre, ≥ 8 ringing the Crown at +232…+250 (the boss's summoned Harriers).
   New check L10 (connected + clearances); draw it in the plan as thin violet lines.
5. **D3 Old Town ≥ 65 % of buildable**: merge lots along each terrace row into contiguous stepped terrace masses
   (heights per lot 16–56 m on the 4 m module) and keep stair-alleys ≥ 24 m every 60–90 m as the walkable lanes.
   Seen against the NW sun it must read as one dense hillside town, not rows of separate boxes.
6. Previews: add a view from the Crown deck (+230) looking north (judge the Civic Quarter) and a D7 street view
   looking up at the Sky Garden; rerun every check and report the numbers like this round.

Keep: graph, arenas, Knot, escarpment, canal, hives, Megablocks, podium-through, Crown, vistas.
