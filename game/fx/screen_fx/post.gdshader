shader_type canvas_item;
render_mode unshaded;

// Full-screen post stack for the feel unit (fx/screen_fx). One pass, every effect in docs/FEEL.md's
// "Flash / post" column: colour flash, chromatic aberration, radial blur, damage vignette, procedural
// speed lines, desaturation (witch time) and the 1-2 frame B/W impact frame.
//
// Rule (juice-impact §12, "high, not extreme"): every tint here is an EDGE effect. The centre of the
// screen stays readable - vignettes, witch tint, speed lines and radial blur all fade to nothing
// inside the inner 55 % of the frame. Only the 1-2 frame B/W impact frame touches the whole screen.
// Masks use `rn` (rectangular radius: 0 at the centre, 1 at any screen edge) so the bands cover all
// four edges evenly instead of leaving the short sides bare.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

group_uniforms flash;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 0.0);

group_uniforms distortion;
// Chromatic aberration in 1080p pixels, scaled to the real viewport height.
uniform float chromatic_px = 0.0;
// Radial (zoom) blur strength in UV at the screen edges; masked to 0 at the centre. Max 0.04.
uniform float radial = 0.0;
uniform vec2 radial_center = vec2(0.5, 0.5);

group_uniforms tint;
uniform float vignette = 0.0;
uniform vec4 vignette_color : source_color = vec4(0.85, 0.06, 0.05, 1.0);
uniform float desaturate = 0.0;
// Cyan edge tint of witch time (perfect dodge), 0..1.
uniform float witch = 0.0;
uniform vec4 witch_color : source_color = vec4(0.31, 0.9, 1.0, 1.0);
// Kanada impact frame: 1 = hard black/white threshold.
uniform float impact_bw = 0.0;

group_uniforms speed_lines;
uniform float speed_lines = 0.0;
uniform float time_offset = 0.0;

const int TAPS = 8;
// Rectangular mask bands: everything starts at 0.55 of the half-screen and reaches full at the edge.
const float EDGE_IN = 0.55;
const float WITCH_IN = 0.55;
const float VIGNETTE_IN = 0.62;
// Speed lines: angular slots around the screen and the thinnest line we draw, in pixels.
const float SLOTS = 150.0;
const float LINE_PX = 1.0;

float streak_hash(float n) {
	return fract(sin(n * 91.3458) * 47453.5453);
}

void fragment() {
	vec2 texel = SCREEN_PIXEL_SIZE;
	vec2 vp = 1.0 / texel;
	float aspect = vp.x / max(vp.y, 1.0);
	vec2 d = SCREEN_UV - radial_center;
	vec2 nd = d * 2.0;                       // -1..1 across the frame
	vec2 an = abs(nd);
	float rn = max(an.x, an.y);              // 0 centre, 1 at any edge (rectangular mask)
	vec2 da = vec2(d.x * aspect, d.y);       // aspect-correct, for radial directions

	// Radial blur: TAPS samples towards the centre, masked to the outer band (0 at the centre).
	float blur = radial * smoothstep(EDGE_IN, 1.0, rn);
	vec3 col;
	if (blur > 0.0005) {
		vec3 acc = vec3(0.0);
		for (int i = 0; i < TAPS; i++) {
			float k = float(i) / float(TAPS - 1);
			acc += texture(screen_tex, radial_center + d * (1.0 - blur * k)).rgb;
		}
		col = acc / float(TAPS);
	} else {
		col = texture(screen_tex, SCREEN_UV).rgb;
	}

	// Chromatic aberration: red pushed out, blue pulled in, along the screen radius.
	if (chromatic_px > 0.01) {
		float len = length(da);
		vec2 dir = (len > 1e-4 ? da / len : vec2(0.0)) * chromatic_px * texel.y;
		dir.x /= aspect;
		col.r = texture(screen_tex, SCREEN_UV + dir).r;
		col.b = texture(screen_tex, SCREEN_UV - dir).b;
	}

	// Procedural speed lines: thin radial streaks in the outer band only, alpha <= 0.3.
	if (speed_lines > 0.001) {
		vec2 p = d * vp;                     // pixels from the centre
		float rp = max(length(p), 1.0);      // pixels per radian at this radius
		float s = atan(p.y, p.x) * SLOTS / TAU;
		float h = streak_hash(floor(s));
		float off = (fract(s) - 0.5) * (TAU / SLOTS) * rp;   // pixels from the slot centre
		float half_w = LINE_PX * (0.55 + 0.45 * h);
		float line = step(0.45, h) * (1.0 - smoothstep(half_w * 0.35, half_w, abs(off)));
		float flick = 0.65 + 0.35 * sin(time_offset * 24.0 + h * 30.0);
		col += vec3(0.78, 0.87, 1.0) * line * smoothstep(EDGE_IN, 1.0, rn) * flick * speed_lines * 0.3;
	}

	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	// Witch time desaturates the world 60 %; the cyan only reaches the edges.
	float dsat = max(desaturate, witch * 0.6);
	if (dsat > 0.001) {
		col = mix(col, vec3(lum), clamp(dsat, 0.0, 1.0));
	}
	if (witch > 0.001) {
		float e = smoothstep(WITCH_IN, 1.0, rn) * 0.35;
		col = mix(col, witch_color.rgb * (0.3 + lum * 0.9), witch * e);
		col = mix(col, col * vec3(0.93, 0.99, 1.07), witch);   // slight cool shift everywhere
	}
	if (vignette > 0.001) {
		// Squared falloff: the inner half of the frame stays completely clean.
		float e = smoothstep(VIGNETTE_IN, 1.0, rn);
		col = mix(col, vignette_color.rgb, vignette * e * e);
	}
	if (impact_bw > 0.001) {
		// Photosensitive mode dims impact_bw instead of inverting; strength is passed in.
		vec3 bw = mix(vec3(lum), vec3(step(0.45, lum)), step(0.5, impact_bw));
		col = mix(col, bw, min(impact_bw, 1.0));
	}

	col = mix(col, flash_color.rgb, clamp(flash_color.a, 0.0, 1.0));
	COLOR = vec4(col, 1.0);
}
