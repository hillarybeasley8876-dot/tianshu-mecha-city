# monster-assets — review r1 (lead) — PASS with one MUST-FIX (stride measurement)

Verified: build_all, `check` 14 files 0 errors, `test_models.gd` 312/0, enemies integration tests, the
captures (gallery line-up, true-scale line-up, swarm, hive intact/cracked/destroyed). The set reads as one
family on the ART palette (chitin, violet crystal cores, acid-green veins); the hive's three states read at a
glance; 40 rippers at 161 draw calls is excellent. Titan 60 m for the fight and the ×1.5 skyline LOD (90 m)
are what SPEC §7 wants — confirmed. Both socket sets: good. Shader-state juggernaut plates: accepted.

## MUST-FIX — the foot-slide number measures the wrong thing
`stride_speed` is ROOT travel per second, so in-place clips read 0 and Tripo's slightly drifting walks read
0.5–0.7 m/s — hence the impossible "33×". What has to match the body speed is the STANCE FOOT's backward speed
relative to the root. For each locomotion clip: sample each foot bone (the lowest bone of each leg) in root
space over the cycle; stance = the frames where that foot is within 0.15 m (× model height / 16) of its lowest
point; `stride_speed` = mean backward speed of the stance feet along the model's forward axis + root travel.
Then playback = clamp(v / stride_speed, 0.6, 2.2) as now, and report per type at the EnemyTypes speeds: the
playback used and the residual slide = |v − playback × stride_speed| / v. A 14 m mantis on a human walk
should land near 10 m/s at 1×, not 0.72.
If a residual stays above 15 %, put the speed that would make it ≤ 15 % per type in your status (the
enemies unit decides gameplay speeds); rippers above 20 m/s may keep a residual (swarm scuttle), bipeds may not.

## Note
`blender/tools/preview.py` and the Blender 5 importer sphere: the lead fixes that tool.
