# Look diagnosis items for flow (lead-verified workflow wf_5e92d07a-bee, 2026-11-02)

Source: an independent critique of the user's screenshot `tmp/lead/user_shot_1.png` (A6 hive fight) against the key art.
Do them in this order (impact per hour). Each item: what is in the picture, the cause (file:line), the fix.

## Flow draws four 9 m flat lime spheres floating beside the hive (the 'discs')  (impact 9, ~2 h)

**In the picture:** Three pale lime discs around the hive: at about (590,670), at (700,490) behind the cyan aim arc, and at (840,840) under the OD gauge. Each is about 90-100 px across, filled with one flat colour and no shading, with its 12-sided outline visible. They hang in the air beside the trunk instead of growing out of it. The model's own green pods are painted on the trunk underneath, so the spire shows two sets of weak points, and the floating set looks like debug gizmos.

**Cause:** game/flow/hive_visual.gd:218 creates one SphereMesh per pod with radius height*POD_RADIUS = 60*0.075 = 4.5 m (:22). It has only 12 radial segments and 6 rings (:236-237). Its material (:241-248) is a StandardMaterial3D with albedo = emission = POD_COLOR at energy 2.6 (:52), pulsing 1.4-3.0 (:123). It has no texture, normal map or fresnel, so it renders as a flat disc. _on_trunk (:77-81) then pushes every pod out to height*TRUNK_RADIUS = 13.2 m from the axis (:28). The rig's pod sockets (hive_rig.json pod_0..3) sit 0.3-7 m from the axis, and the trunk is far thinner than 13 m, so the spheres float in the air. hive_spire.gd:76 also sizes the spire's collision cylinder to that 13.2 m radius, so shots stop on invisible air around a thin trunk.

**Fix:** Delete the pod and core spheres (:217-219) and the pulse writes (:123-125).

Place each pod Hurtbox (hive_spire.gd:87-88) at the model's own pod socket projected onto the surface: raycast outward along the socket's bearing against the HiveCollision hull (hive_model.collision_mesh()) and step 1 m back in from the hit. Use that hull as the spire's collision instead of the 13.2 m cylinder (:76).

When a pod bursts:
- call the model's per-pod glow off (see the hive emission issue)
- spawn an acid-burst VFX and a scar decal at the hit point
- shake the trunk

Until the per-pod uniform exists, the interim visual at each projected point is a cluster of 3-5 translucent sacs, 3-4 m across, half-sunk into the surface. Never a single sphere. Spec: at least 32x16 segments, a ShaderMaterial with a fresnel membrane, a dark chitin rim and an acid core at energy 1.5 or less.

Visual target: captures/monsters_hive_intact.jpg, four grape-cluster pods that grow out of the spire.
