"""Build zones: the ground a district's rules actually apply to.

Most districts are one zone - their whole footprint sits on one datum. D4 Spire & Civic
Core straddles the escarpment: its lower ground is the plaza district and its plateau
ground north of the Forum is the **Civic Quarter** (MAP §4 D4 row, lead r2 point 1). The
quarter gets its own footprint, street grid and building rules, but every record it emits
still carries `district: "D4"`, so the layout schema and city-build are unaffected; the
quarter is tagged with `quarter: "civic"` instead.
"""
from __future__ import annotations


def _merge(base: dict, over: dict) -> dict:
    """Shallow merge, one level deep, so a quarter may override only `streets.angle_deg`."""
    out = dict(base)
    for key, value in over.items():
        if isinstance(value, dict) and isinstance(base.get(key), dict):
            out[key] = dict(base[key], **value)
        else:
            out[key] = value
    return out


def zones(rules: dict) -> list[dict]:
    """Every zone as {id, tag, district, quarter, footprint, ground_z, streets, buildings}.

    `id` is unique per zone and is what the free-land dictionaries are keyed by; `district`
    is the D1..D7 tag that goes into the layout file.
    """
    out: list[dict] = []
    for did, rule in rules["districts"].items():
        out.append({"id": did, "tag": did.lower(), "district": did, "quarter": None,
                    "footprint": rule["footprint"], "ground_z": float(rule["ground_z"]),
                    "streets": rule["streets"], "buildings": rule["buildings"],
                    "name": rule["name"]})
        for quarter in rule.get("quarters", []):
            merged = _merge(rule, quarter)
            out.append({"id": quarter["tag"].upper(), "tag": quarter["tag"],
                        "district": did, "quarter": quarter["tag"],
                        "footprint": merged["footprint"],
                        "ground_z": float(merged["ground_z"]),
                        "streets": merged["streets"], "buildings": merged["buildings"],
                        "name": merged["name"]})
    return out


def rule_of(rules: dict, zone_id: str) -> dict:
    """The merged district rule a zone builds from (its own overrides already applied)."""
    for zone in zones(rules):
        if zone["id"] == zone_id:
            base = rules["districts"][zone["district"]]
            if zone["quarter"] is None:
                return base
            for quarter in base.get("quarters", []):
                if quarter["tag"] == zone["quarter"]:
                    return _merge(base, quarter)
    raise KeyError(f"unknown build zone {zone_id}")


def district_zones(rules: dict) -> dict[str, list[dict]]:
    """Zones grouped by the district tag they emit into."""
    out: dict[str, list[dict]] = {}
    for zone in zones(rules):
        out.setdefault(zone["district"], []).append(zone)
    return out


def tag_quarters(rules: dict, buildings: list[dict]) -> int:
    """Tag every building that stands in a district's second zone with its quarter name.

    `fill.generate` tags what it places; the kerb walls and the podium portals are built by
    other stages and would otherwise be indistinguishable from the district's main fabric.
    """
    tagged = 0
    for zone in zones(rules):
        if not zone["quarter"]:
            continue
        fp = zone["footprint"]
        for b in buildings:
            if b["district"] != zone["district"] or abs(b["base_z"] - zone["ground_z"]) > 1.0:
                continue
            if fp[0] <= b["center"][0] <= fp[2] and fp[1] <= b["center"][1] <= fp[3]:
                b["quarter"] = zone["quarter"]
                tagged += 1
    return tagged
