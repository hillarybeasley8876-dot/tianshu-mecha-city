// mc_facade (city-art r11, r12 §1) — the object-space facade that replaces the Tripo ATLAS on near walls.
//
// A Tripo albedo is an atlas of thousands of confetti islands, each carrying its own value and its own
// baked shading. On a 140 m wall at 50 m one texel is about nine screen pixels, so what the player
// sees is the ISLANDS: smooth light and dark wedges that run along the triangles, and no storeys or
// panels at all. city-kit tried twice to paint a facade into that atlas (r5, r6) and cannot — at
// 0.06-0.49 m per texel, cut into islands, it has nowhere to put a 4 m floor.
//
// So a wall stops reading the atlas. It takes its COLOUR from it at a coarse mip (one value per
// model, so a bronze tower stays bronze and a concrete slab stays grey) and its STRUCTURE from a grid
// built in METRES in the model's own object space. r12: which grid is `mc_facade_style.gdshaderinc`'s
// decision — a curtain wall, a ribbon block or a punched wall, chosen by the model's band and varied
// per instance, so five buildings in one frame are not five copies of one skin.
//
// Everything with a fixed width in metres fades out at the distance where it stops being two pixels
// wide (`mc_res`), which is what keeps a dolly past a tower from crawling. Roofs, soffits and curved
// parts never reach here — mc_kit_body gates on `vert` and on curvature.

uniform float facade_mix : hint_range(0.0, 1.0) = 1.0;
// The STRUCTURE on/off switch, separate from `facade_mix` (which is the whole facade on/off). At 0 the
// wall is the flat tint with no slab, mullion, reveal or pane — the reference the flatness gate needs,
// and the A/B knob for tuning the grid's weight without losing the model's colour.
uniform float facade_lines : hint_range(0.0, 1.0) = 1.0;
uniform float facade_mip : hint_range(0.0, 12.0) = 8.0;   // the mip that averages the islands away
uniform float facade_lo = 0.15;                            // r6's linear wall range
uniform float facade_hi = 0.30;
// r12 §1: how much one building's value may differ from its neighbour's. The lead asked for ±15 %
// inside the r6 clamp, so the per-building term is applied to the CLAMPED value and the result is
// clamped again to the widened band — a building is never allowed out of the wall range, only to sit
// at a different place in it.
uniform float facade_spread : hint_range(0.0, 0.5) = 0.15;
uniform float facade_rough : hint_range(0.03, 1.0) = 0.60; // r6's rough_after / metal_after
uniform float facade_metal : hint_range(0.0, 1.0) = 0.03;
uniform float facade_shop_m = 3.2;                         // podium glazing height, metres
uniform float facade_sign_m = 1.1;                         // the dark sign band over it
uniform float facade_sign_dark : hint_range(0.0, 1.0) = 0.55;
uniform float facade_shop_glow : hint_range(0.0, 2.0) = 0.22;
// r12 §1: which FAMILY this model's walls wear. `McKitSkin.facade_family_for()` sets it from the
// model's `kit.json` band: 0 curtain (tower), 1 ribbon (megablock, midrise), 2 punched (oldtown,
// civic). -1 means "no facade" and is never drawn.
uniform int facade_family : hint_range(-1, 3) = 0;

#include "mc_facade_style.gdshaderinc"

// 1 inside |d| < w, 0 outside, `aa` wide — all three in the same units.
float mc_band(float d, float w, float aa) {
	return 1.0 - smoothstep(w - aa, w + aa, abs(d));
}

// 1 between lo and hi, 0 outside, `aa` wide.
float mc_span(float x, float lo, float hi, float aa) {
	return smoothstep(lo - aa, lo + aa, x) * (1.0 - smoothstep(hi - aa, hi + aa, x));
}

// How much of a feature `w` metres wide survives at `px` metres per pixel: full while it is three
// pixels across, gone by the time it is one. This is the antialiasing that a fixed-size architectural
// line needs and `fwidth` alone does not give it.
float mc_res(float w, float px) {
	return 1.0 - smoothstep(w * 0.33, w * 1.1, px);
}

// The wall's own colour: the atlas at `facade_mip` is the model's identity without its islands, the
// luminance is clamped into the r6 wall range so no model arrives black or white, and a per-cell
// (±8 %) plus per-building offset keeps a facade from being one flat value.
vec3 facade_tint(vec2 uv, vec2 cid, float b_var) {
	vec3 t = base_color.rgb * textureLod(tex_albedo, uv, facade_mip).rgb;
	float lum = dot(t, vec3(0.2126, 0.7152, 0.0722));
	float v = clamp(lum, facade_lo, facade_hi);
	v *= mix(0.92, 1.08, hash21(cid * vec2(0.137, 0.211) + b_var * 57.0));
	v *= 1.0 + facade_spread * (b_var * 2.0 - 1.0);
	v = clamp(v, facade_lo * (1.0 - facade_spread), facade_hi * (1.0 + facade_spread));
	return t * (v / max(lum, 1e-4));
}

// One wall fragment. `u` is metres along the wall, `y` metres up from the model's own base, `px` the
// size of one pixel in metres, `dist_fade` the camera-distance dissolve. Writes the glass mask to
// `pane` (1 = glazing), the height inside that pane (0 sill, 1 head) to `pane_v`, the cell id the lit
// window logic has to use to `cid`, and the pane's own glass colour to `glass`; returns the albedo.
vec3 facade(vec2 uv, float u, float y, float px, float b_var, float dist_fade,
		inout float pane, inout float pane_v, inout vec2 cid, inout vec3 glass) {
	FacadeStyle s = facade_style(facade_family, facade_variant(b_var, facade_family));
	glass = s.glass;
	vec2 ph = facade_phase_for(b_var, facade_family, s);

	// --- the grid: a bay line, a slab line, a pane in the cell
	vec2 cell = vec2((u + ph.x) / s.cell_w, (y - win_podium_m + ph.y) / s.cell_h);
	cid = floor(cell);
	vec2 f = cell - cid;
	vec2 aa = vec2(px / s.cell_w, px / s.cell_h);
	float sw = s.slab_m * 0.5 / s.cell_h;
	float mw = s.mull_m * 0.5 / s.cell_w;

	float mull = mc_band(f.x, mw, aa.x) * mc_res(s.mull_m, px);
	float slab = mc_band(f.y, sw, aa.y) * mc_res(s.slab_m, px);
	float mull_p = 1.0 - mull;   // the same line, as a mask of everything that is NOT mullion

	// The structural joint: a ribbon block's band runs on past the pane grid, and every 6-9 m the
	// structure shows through it as a deeper, darker line. It is what makes a 200 m horizontal read as
	// a building rather than as a texture.
	float joint = 0.0;
	if (s.joint_m > 0.0) {
		float jf = fract((u + ph.x) / s.joint_m);
		joint = mc_band(jf - 0.5, 0.14 / s.joint_m, px / s.joint_m) * mc_res(0.28, px);
	}

	vec2 lo = vec2(0.5 - s.pane_w * 0.5, 0.5 - s.pane_h * 0.5);
	vec2 hi = vec2(0.5 + s.pane_w * 0.5, 0.5 + s.pane_h * 0.5);
	float pane_m = (1.0 - smoothstep(-aa.x, aa.x, max(lo.x - f.x, f.x - hi.x)))
		* (1.0 - smoothstep(-aa.y, aa.y, max(lo.y - f.y, f.y - hi.y)));
	// The reveal: the same rectangle grown by a hand's width, minus the pane — the shadow a recessed
	// window casts on its own surround. A punched wall's reveal is the deep one.
	float rv = 0.05;
	float outer = (1.0 - smoothstep(-aa.x, aa.x, max(lo.x - rv - f.x, f.x - hi.x - rv)))
		* (1.0 - smoothstep(-aa.y, aa.y, max(lo.y - rv - f.y, f.y - hi.y - rv)));
	float reveal = clamp(outer - pane_m, 0.0, 1.0);

	float pane_a = mc_res(s.cell_w * s.pane_w, px) * (1.0 - dist_fade) * facade_lines;
	vec3 wall = facade_tint(uv, cid, b_var);
	vec3 tower = wall;
	tower *= 1.0 - s.slab_dark * slab * facade_lines;
	tower *= 1.0 - s.mull_dark * mull * facade_lines;
	tower *= 1.0 - s.joint_dark * joint * facade_lines;
	tower *= 1.0 - s.reveal * reveal * pane_a;
	// As the pane dissolves into the wall (distance, sub-pixel), what is left is its AREA: a facade read
	// from 600 m is pane_w x pane_h glass, not a wall of glass. At 1.0 every far tower emitted at the
	// full lit fraction and the skyline ring bleached to white at dusk (lead A/B, 11-04).
	float pane_t = mix(s.pane_w * s.pane_h, pane_m, pane_a) * facade_lines;

	// --- the cornice: a band every few storeys. A punched wall without one is a stack of holes.
	if (s.cornice_m > 0.0) {
		float cy = fract(cell.y / s.cornice_n);
		float band = mc_band(cy - 0.5, s.cornice_m * 0.5 / (s.cornice_n * s.cell_h), aa.y)
				* mc_res(s.cornice_m, px);
		tower *= 1.0 - s.cornice_dark * band * facade_lines;
		// The lit top edge of the cornice — the line that reads as a shadow at 200 m.
		tower += wall * 0.22 * mc_band(cy - 0.5 - s.cornice_m * 0.5 / (s.cornice_n * s.cell_h),
				max(aa.y, 0.002), aa.y) * mc_res(s.cornice_m, px) * facade_lines;
	}

	// --- the balcony / plant line: a dark band with a light rail on it, every storey
	if (s.balc_m > 0.0) {
		float by = sw + s.balc_m * 0.5 / s.cell_h;
		float band = mc_span(f.y, sw, sw + s.balc_m / s.cell_h, aa.y) * mc_res(s.balc_m, px);
		tower *= 1.0 - s.balc_dark * band * facade_lines;
		float rail = mc_band(f.y - by - s.balc_m * 0.5 / s.cell_h + s.rail_m * 0.5 / s.cell_h,
				s.rail_m * 0.5 / s.cell_h, aa.y) * mc_res(s.rail_m, px);
		tower += wall * 0.55 * rail * facade_lines;
	}

	// --- the podium: taller shopfront glazing under one dark sign band, and no lit-window runs
	float glazing = mc_span(y, 0.5, facade_shop_m, px)
		* mix(1.0, mull_p, mc_res(max(s.mull_m, 0.15), px)) * facade_lines;
	float sign = mc_span(y, facade_shop_m, facade_shop_m + facade_sign_m, px);
	vec3 podium = wall * (1.0 - facade_sign_dark * sign * facade_lines);

	float above = smoothstep(win_podium_m - 0.12, win_podium_m + 0.12, y);
	pane = mix(glazing, pane_t, above);
	// Where in the pane this fragment sits: a lit room is brighter at the ceiling than at the sill, and
	// that gradient is most of what stops a lit window reading as a glowing sticker.
	pane_v = clamp((f.y - lo.y) / max(hi.y - lo.y, 1e-4), 0.0, 1.0);
	return mix(podium, tower, above);
}
