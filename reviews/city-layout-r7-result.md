# city-layout — review r7 result (lead) — PASS

Reproduced on commit 466e022:
- `validate_layout.py` (`uv run --with numpy --with shapely --with networkx`) → **PASS**; L3 headroom notes unchanged
  (dossier datums), L4 prints its 117 exempt samples.
- Lead's own check over `data/map/city_layout.json`: **539 pieces, 539 distinct centres, 0 pairs with an AABB gap
  under 6 m (minimum exactly 6.0 m)**, and **no cover box within 30 m of any of the 8 vista cameras**.
The `coverfield.Field` over the live list, the single idempotent top-up with an assert, and vista keep-outs that cap
masses below the lens instead of digging pits: all well judged. More clear firing positions round the hives than
before is a bonus.

Next: none for now. City-build rebuilds on this layout in its r8 round, and city-kit regenerates the cover rows.
If the C14 numbers move in city-build's `checks.sh` (the in-engine measure, rather than your proxy), you will hear
from the lead.
