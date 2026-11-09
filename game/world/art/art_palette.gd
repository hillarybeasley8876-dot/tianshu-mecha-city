class_name ArtPalette
extends RefCounted
## ART.md §2 palette as code (city-art). Every colour in the unit comes from here so a single edit
## re-grades the city. Colours are written as sRGB hex literals and converted to linear on demand,
## because ART.md quotes sRGB but Godot material/light colours are linear.

## --- sky / atmosphere -------------------------------------------------------
## Review r2: the dome is GOLDEN dusk — gold in the sun's half of the horizon, peach away from it, and
## blue-violet only high up. A cool mid-sky (#6F86B0 in ART.md §2) turned every shadow in the city
## purple, which is the storm's colour, not dusk's.
## r15: #2b4c7e is linear 0.026/0.068/0.216 — a good blue, but the mid band above it was #a08d86 at
## linear 0.36, five to thirteen times brighter, so mixing the two (which the old wide ramp did at
## every elevation the cameras see) produced a warm NEUTRAL, not a blue top. The mid is now a dusty
## mauve at a third of that value and the zenith is lifted so the two are a ramp and not a step.
## The hue is #4a6f90 (Lab 261 deg, chroma 22) rather than a saturated blue because AgX rotates a
## rendered blue about +52 deg: #35578c (Lab 279) came out of the frame at 339 — magenta, not the
## violet-grey the key art's zenith is (v1 322 deg at chroma 5.5). 261 + 52 = 313, which is where v8's
## storm sky sits.
const SKY_ZENITH := Color("4a6f90")
const SKY_MID := Color("8a7a86")
## r16b §1: the golden hour went RED, not gold. `skylo_hue` measured 33-66 at tod 0 and 3-64 at 0.5
## against the key art's 65-85, and the horizon is the band the whole frame is judged on. Two causes:
## the ramp (see `TimeOfDay.dusk_for`) and the colour itself. Through AgX at the shipping gain
## (#ffd68f x the sky's 1.05 exposure x the post stack's 0.66) the authored colour lands about 8 deg
## BELOW where it reads on the frame, so the value is picked by where the tonemap probe
## (`tmp/city-art/r15/tonemap.py`) says it lands: #ffdc9a is hue 75.2 at chroma 39.0 there, and it
## measures `skylo_hue` 65-70 across the vistas. The value lift is what buys the hue — AgX rotates a
## *dark* saturated warm toward red exactly as it rotates a dark blue toward magenta.
const SKY_HORIZON := Color("ffdc9a")
## r16b: the ANTI-SUN horizon, same treatment one step paler so the two halves of the dome still
## separate (the key art's away-side sky is cooler and lighter than its sun side).
const SKY_HORIZON_AWAY := Color("ffd9a8")
const SUN_DISC := Color("fff0cf")
const CLOUD_WARM := Color("ffc08a")
const CLOUD_DUSK := Color("7a5c8c")   ## ART.md §2 "dusk clouds #E8956B / #7A5C8C"

## --- haze / fog -------------------------------------------------------------
const HAZE_WARM := Color("e9cba9")
const HAZE_COOL := Color("a8b6cc")
const HAZE_UNDER_DECK := Color("3a3440")
## Review r3 §3: the far band, past ~700 m. Godot's depth fog is one colour over one curve, so the
## warm near/mid scatter stays in the Environment and this cooler violet-blue is the shader half
## (mc_haze.gdshaderinc). The key art's distance goes violet-blue long before it goes orange.
const HAZE_FAR := Color("6e6a8e")
const HAZE_FAR_STORM := Color("5b4f86")

## --- the distant ring -------------------------------------------------------
## Review r3 §3: the ring past the map edge is silhouette, not architecture — a flat dark body with a
## warm rim on the sun side, dissolving upward into `SKYLINE_HAZE`.
const SKYLINE_BODY := Color("1d1a26")
const SKYLINE_HAZE := Color("7b7699")

## --- architecture -----------------------------------------------------------
## city-art r14: the architecture albedos were the other half of the bleaching. #ded9cd is 0.73 in
## LINEAR reflectance — brighter than fresh snow — and a 2.3-energy key on it put the Spire's crown and
## every sunlit slab over 248/255. These are the values a real stone and a real concrete have.
const STONE := Color("b9b3a6")
const CONCRETE := Color("94908a")
const PANEL_WHITE := Color("c6c9cf")   ## r14: #edeff2 is a 0.85 linear albedo — the Spire's crown cladding clipped to white
const GLASS := Color("1c2633")
const STEEL := Color("767c84")
const BRONZE := Color("8f6339")
const TERRACOTTA := Color("763e2d")
const ROAD := Color("2e2f30")
const DECK := Color("7d7970")

## --- lights -----------------------------------------------------------------
const WINDOW_WARM := Color("ffcf8a")
const WINDOW_COOL := Color("bfe3ff")
const STREET_SODIUM := Color("ff9f45")
const LED_RAIL := Color("3ee6ff")
## Aviation obstruction light on every mast above the roofline. The one saturated red in the city.
const AVIATION_RED := Color("ff3b30")

## --- neon / holograms -------------------------------------------------------
const NEON_CYAN := Color("3ee6ff")
const NEON_MAGENTA := Color("ff3ea5")
const NEON_AMBER := Color("ffb13e")
const NEON_JADE := Color("3effb0")

## --- nature / water ---------------------------------------------------------
const FOLIAGE := Color("3e6b3a")
const FOLIAGE_LIGHT := Color("5e8c4a")
const BLOSSOM := Color("f2a7c3")
const WATER := Color("2e5a6e")

## --- monsters / infection ---------------------------------------------------
const CHITIN := Color("1b2430")
const ACID := Color("9bff3a")
const WEAK_VIOLET := Color("b04cff")
const STORM := Color("8c5bff")

## --- sun --------------------------------------------------------------------
## Review r2: a warm key from the north-west, dropping to a deep ember at the boss. Measured against
## art/concept/keyart/v1_pier-1.png: the reference's sunlit facades sit at R/B 1.40, which needs a
## ~3,200 K key once the grade and the gold haze are counted — a literal 2,500 K lamp turned every
## grey facade orange and read as sepia, not golden hour.
## r15: #ffcb9c reads as hue 60-69 at chroma 22-40 through the display chain and the sunlit facades
## measured 30-50 against a key-art 46-66; #ffcf8a reads as 67-76 at chroma 27-46.
## r16b §1: the sunlit faces still measured `lit_hue` 34-56 at tod 0 and 16-46 at 0.5 against the key
## art's 45-75, because the key itself was already half-way to the ember at 0.5 and because the ramp's
## own red survives the display chain. Hue and chroma trade against each other here — a redder light is
## MORE chromatic in Lab — and both are gated, so the colour is picked off the tonemap probe's
## hue/chroma pair at the shipping gain: #ffcc80 is hue 67.9 at chroma 49.7, against #ffcf8a's 68.5 /
## 46.8 (r15) and #ffe0a8's 75.7 / 33.4 (the first r16b attempt, which bought its hue by going pale and
## cost `lit_chroma` two frames).
const SUN_COLOR := Color("ffcc80")
const SUN_COLOR_DUSK := Color("ff9d66")   ## r6: #ff8f52 clipped the red channel on every sunlit face


## sRGB -> linear, for material albedo / emission / light colour.
static func linear(c: Color) -> Color:
	return c.srgb_to_linear()


## sRGB -> linear with an exposure multiplier (energy-like gain on lights).
static func lit(c: Color, gain: float) -> Color:
	var l := c.srgb_to_linear()
	return Color(l.r * gain, l.g * gain, l.b * gain, 1.0)


## Blend two sRGB colours then linearise — for Godot properties that take LINEAR colour
## (light_color, Environment.fog_light_color).
static func mix_linear(a: Color, b: Color, t: float) -> Color:
	return a.lerp(b, clampf(t, 0.0, 1.0)).srgb_to_linear()


## Blend two sRGB colours and keep them sRGB — for shader uniforms declared `: source_color`,
## which the engine converts to linear itself. Passing linear values there darkens and over-saturates.
static func srgb_mix(a: Color, b: Color, t: float) -> Color:
	return a.lerp(b, clampf(t, 0.0, 1.0))
