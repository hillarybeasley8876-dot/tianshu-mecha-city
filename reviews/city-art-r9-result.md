# city-art — review r9 result (lead) — PASS

`captures/look_city-art_r9_far_V2|V5|V7.jpg`: the far ring and the HLOD layer now sit in the sky's own warm haze. The
lavender is gone, the checkerboard is gone, the masses darken at the base and dissolve at the crown, and V5's
horizon reads as a distant city instead of pasted cut-outs. The root cause (`sky_band` never registered, so
`_push_haze` never reached the skyline material, every round since r3) is a real find, and it is now pinned by
`test_art`. Putting sparkle and rim after the haze mix is right physically and visibly.
The prop weld A/B (`look_city-art_r9_prop_container.jpg`) shows the shredded container roof closed into clean
corrugation.

## Heads-up (no action yet)
City-kit's near tier is being regraded (glossy pale Tripo surfaces read as foil at dusk: roughness floor, palette
grade, weighted normals; `reviews/city-kit-r2.md`). If their regrade lands near but not on the palette, the
`McKitSkin` material is where a global grade would go. Wait for their A/B before touching it.
