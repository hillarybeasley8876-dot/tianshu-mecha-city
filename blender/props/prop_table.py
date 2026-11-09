"""Per-prop processing table (city-art). `budget` is the triangle ceiling from briefs/city-art.md
(vehicles <= 15k, street <= 5k, rooftop <= 8k, statues/landmarks <= 40k); `size_m` is the real-world
LONGEST dimension in metres, taken from the Tripo prompt in data/props_list.json, because Tripo
exports every prop at roughly unit scale.
"""
from typing import Dict, NamedTuple


class Prop(NamedTuple):
    budget: int          ## triangle ceiling
    size_m: float        ## target longest dimension, metres
    tex: int             ## base-colour texture size (normal is the same, ORM/emissive half)
    tier: str            ## placement class used by the prop placer


PROPS: Dict[str, Prop] = {
    # --- vehicles (budget 15k) ------------------------------------------------
    "hovercar_a": Prop(15000, 5.0, 1024, "vehicle"),
    "hovercar_b": Prop(15000, 6.0, 1024, "vehicle"),
    "truck": Prop(15000, 14.0, 1024, "vehicle"),
    "bus": Prop(15000, 18.0, 1024, "vehicle"),
    "maglev_car": Prop(15000, 25.0, 1024, "vehicle"),
    "wreck_car": Prop(15000, 5.0, 1024, "vehicle"),
    "wreck_mech": Prop(40000, 16.0, 2048, "statue"),
    # --- street furniture (budget 5k) ----------------------------------------
    "streetlamp": Prop(5000, 12.0, 512, "street"),
    "vending": Prop(5000, 2.4, 512, "street"),
    "bus_shelter": Prop(5000, 6.0, 512, "street"),
    "barrier": Prop(5000, 4.0, 512, "street"),
    # r10: 5k on a 262k-tri source is a 52x collapse and it tore three holes through the canopy the
    # player looks down on from a 16 m mech (lead acceptance `props-ac-cluster-food-stall-decimation`).
    "food_stall": Prop(10000, 4.0, 512, "street"),
    "anchor_node": Prop(5000, 3.0, 512, "street"),
    "holo_projector": Prop(5000, 2.5, 512, "street"),
    "lift_platform": Prop(5000, 12.0, 512, "street"),
    # --- rooftop / industrial (budget 8k) ------------------------------------
    # r10: ac_cluster is the most-placed roof machine in the city (187 instances, every district's
    # roof pool), and at the 8k rooftop tier the 264k-tri source collapsed 33x into crumpled foil:
    # kinked ducts, a twisted stack, magenta slivers on the fan grilles and a 1.09 m open boundary --
    # the largest of all 30 props. 16k is the smallest tier that keeps the ducts straight.
    "ac_cluster": Prop(16000, 6.0, 1024, "rooftop"),
    "antenna_array": Prop(8000, 8.0, 512, "rooftop"),
    "pipe_cluster": Prop(8000, 7.0, 512, "rooftop"),
    "solar_array": Prop(8000, 10.0, 512, "rooftop"),
    "storage_tank": Prop(8000, 9.0, 512, "rooftop"),
    "water_tank": Prop(8000, 7.0, 512, "rooftop"),
    "billboard_frame": Prop(8000, 14.0, 512, "rooftop"),
    "container_stack": Prop(8000, 12.0, 1024, "rooftop"),
    # r10: the harbour gantry crane is the biggest thing in the opening H0/A1 frames and it shipped as
    # gold shards -- at the 8k rooftop tier the 268,685-tri source collapsed into needle legs and a
    # crumpled cab (lead acceptance `props-crane-shredded`). It is a landmark, so it takes the statue
    # tier; 4 instances at 40k is 160k triangles, nothing against the 6 M budget.
    "crane": Prop(40000, 60.0, 1024, "statue"),
    # --- greenery: thin foliage decimates badly, so these sit at the rooftop budget -------------
    "planter_tree": Prop(8000, 9.0, 512, "street"),
    "blossom_tree": Prop(8000, 8.0, 512, "street"),
    # --- statues and landmarks (budget 40k) ----------------------------------
    "mech_statue": Prop(40000, 20.0, 2048, "statue"),
    "guardian_lion": Prop(40000, 4.0, 1024, "statue"),
    "pagoda_top": Prop(40000, 14.0, 2048, "statue"),
    "koi_dragon": Prop(40000, 60.0, 1024, "hologram"),
}

DEFAULT = Prop(8000, 6.0, 512, "rooftop")


def prop(name: str) -> Prop:
    return PROPS.get(name, DEFAULT)
