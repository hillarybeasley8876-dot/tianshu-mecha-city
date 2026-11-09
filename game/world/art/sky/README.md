# Sky panoramas — `game/world/art/sky/`

Equirectangular Radiance (`.hdr`) plates the `mc_sky` shader blends in as its **cloud field**
(`pano`, `pano_blend`, `pano_yaw`). The dome's own ramp still supplies every colour, so `TimeOfDay`
keeps control of the time of day, the storm and the sun — the panorama only supplies the cloud
structure a value-noise dome cannot make. `sky/index.json` is the manifest: which plate is active,
where its sun is, and its median luminance (the shader's `pano_ref`).

## What ships (r16b)

`sky/index.json` ships **`"blend": 0.5`** — the plate is half the cloud field, the procedural deck is
the other half. r15's A/B put it at 0 (the hand-built dome won on `sky_dh` alone); r16b re-ran the A/B
after the golden-hour work and the plate wins on the number that round was about, because the
procedural deck's cloud BODY is violet-grey and the 0-9 deg band the whole frame is judged on is
mostly cloud:

| | dome alone | **plate at 0.5** |
|---|---|---|
| `skylo_hue` tod 0 | 55.0-68.0 (V3 64.9, V4 55.0 miss) | **66.5-73.8, every frame met** |
| `skylo_hue` tod 0.5 | 53.7-71.1 (V3 63.9, V4 53.7 miss) | **66.5-68.7, every frame met** |
| `skylo_chroma` | 17.2-34.4 | **29.7-32.0** |
| `sky_rel` | 0.131-0.265 | 0.154-0.209 |
| `clip` | 0.14-1.04 % | 0.17-1.27 % |

The plate is desaturated to a luminance field and re-tinted by the dome's own ramp, so it supplies
STRUCTURE and warm sunlit cloud edges and never a second time of day. `--pano=<id|none>` and
`--pano-blend=<0..1>` drive it; `--pano=none` is the dome-alone arm.

## Licence

Every plate here is **CC0** (public domain, no attribution required) from **Poly Haven**.

| file | Poly Haven id | source | licence |
|---|---|---|---|
| `kloppenheim_06_puresky_4k.hdr` | `kloppenheim_06_puresky` | https://polyhaven.com/a/kloppenheim_06_puresky — file `https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/4k/kloppenheim_06_puresky_4k.hdr` | CC0 |
| `belfast_sunset_puresky_4k.hdr` | `belfast_sunset_puresky` | https://polyhaven.com/a/belfast_sunset_puresky — file `https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/4k/belfast_sunset_puresky_4k.hdr` | CC0 |

CC0 does not require credit. The line the credits screen needs, if the lead wants one:

> Sky: "Kloppenheim 06 (Pure Sky)" and "Belfast Sunset (Pure Sky)" by Poly Haven — CC0.

## Why these two

Four sunset pure-skies with real cloud were downloaded and scored on structure, not on looks
(`tmp/city-art/r15/hdri_profile.py`, sheet `tmp/city-art/r15/hdri_sheet.jpg`):

| plate | sun az | log-luma std 0–8° / 8–20° / 20–40° | cloud-edge sharpness |
|---|---|---|---|
| **kloppenheim_06_puresky** | 29.2° | 2.57 / 6.00 / 6.66 | **0.133** |
| belfast_sunset_puresky | 35.6° | 58.4 / 9.99 / 8.50 | 0.048 |
| wasteland_clouds_puresky | 35.8° | 1.34 / 0.87 / 2.10 | 0.033 |
| qwantani_sunset_puresky | 36.1° | 1.39 / 1.19 / 2.32 | 0.015 |

`kloppenheim_06` wins on cloud edges by 3–9x and is the only plate with a cumulus deck in the 8–40°
band the city's cameras actually look at, over a blue zenith and a gold horizon — the same
blue-above / gold-below structure `sky_db` measures in the key art. `belfast_sunset` is kept as the
A/B arm: its cloud bodies are the violet-grey the key art has, at a lower structure.

## How the sun is aligned

The panorama's own sun sits at `sun_az_deg` (measured off the file by `tmp/city-art/r15/rgbe.py`).
`SkyPano` sets `pano_yaw = sun_az_deg − world_sun_azimuth`, so the plate's sun lands on the world's
`sun_dir` and the plate is rotated with the time of day rather than baked in.
