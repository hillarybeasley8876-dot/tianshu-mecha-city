shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque, fog_disabled, diffuse_burley, specular_schlick_ggx;
// mc_cargo (city-art, look review 2026-11-02 item 3) — the skin that turns an arena cover box into
// a stack of shipping containers.
//
// city-build's cover is `kit.box(role)` + a pale cap: a plain 17-34 m rectangular solid, and there are
// 360 of them at the closest range in the whole game. A shader cannot add geometry, but a container
// stack is almost entirely a SURFACE: an ISO pitch grid of corrugated panels, corner castings, top and
// bottom rails, per-container paint, rust bleeding down from the stack, and hazard bands. All of that
// is pattern, and pattern is what this does — drawn on one unit cube per slot, so the layer is 360
// instances of 12 triangles.
//
// Everything is computed in OBJECT space in METRES (v_local = VERTEX * the instance's own size), so one
// MultiMesh can carry every differently-sized slot and the pitch stays 12.19 m on all of them. The
// containers all run along local X: the +-X faces are container ENDS (doors, locking bars) and the
// +-Z / +-Y faces are container SIDES (ribs, rails, stencils).
#include "mc_haze.gdshaderinc"

// Faded, not fresh: a container yard that has been in a salt wind for ten years. The first pass at
// full saturation read as toy blocks under the golden key.
uniform vec3 paint_a : source_color = vec3(0.40, 0.21, 0.16);   // faded oxide red
uniform vec3 paint_b : source_color = vec3(0.16, 0.28, 0.29);   // harbour teal
uniform vec3 paint_c : source_color = vec3(0.29, 0.30, 0.31);   // weathered grey
uniform vec3 paint_d : source_color = vec3(0.38, 0.32, 0.21);   // ochre
uniform vec3 hazard_a : source_color = vec3(0.86, 0.68, 0.10);
uniform vec3 hazard_b : source_color = vec3(0.09, 0.09, 0.10);
uniform float rib_pitch = 0.30;        // corrugation pitch, metres
uniform float rib_depth : hint_range(0.0, 3.0) = 1.15;
uniform float rust_amount : hint_range(0.0, 1.0) = 0.55;
uniform float grime_amount : hint_range(0.0, 1.0) = 0.45;
uniform float wet : hint_range(0.0, 1.0) = 0.0;   // driven by McMaterials.set_wetness

// ISO 668: 40 ft long, 8 ft wide, 8 ft 6 in high. Cells are this pitch ROUNDED to fit the box, so a
// stack always ends on a container edge and a perched single container gets exactly one cell.
const vec3 PITCH = vec3(12.19, 2.59, 2.44);

varying vec3 v_local;
varying vec3 v_size;
varying vec3 v_nrm_l;
varying vec3 v_world;
varying float v_seed;
varying float v_civic;
varying float v_exposed;   // COLOR.b: a single container standing on top of a stack, sun on all of it

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	return fract(p * (p + p));
}

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	v_size = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	v_local = VERTEX * v_size;
	v_nrm_l = NORMAL;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// The MultiMesh instance colour carries the district weight (r) and the slot's own seed (g), so two
	// identical footprints are not the same stack and one material serves every district.
	v_civic = COLOR.r;
	v_seed = COLOR.g;
	v_exposed = COLOR.b;
}

// One face's 2D frame in METRES, measured from the box's own corner so cells tile from an edge, plus
// the cell pitch rounded to fit and which container axis the face looks along (0 = end, 1 = side,
// 2 = top).
vec2 fit_pitch(vec2 size, vec2 want) {
	return size / max(vec2(1.0), floor(size / want + 0.5));
}

void face_frame(out vec2 f, out vec2 pitch, out float axis, out vec3 n_l) {
	n_l = normalize(v_nrm_l);
	vec3 an = abs(n_l);
	if (an.y > 0.7) {                       // top / bottom: length x width
		f = vec2(v_local.x, v_local.z) + vec2(v_size.x, v_size.z) * 0.5;
		pitch = fit_pitch(vec2(v_size.x, v_size.z), vec2(PITCH.x, PITCH.z));
		axis = 2.0;
	} else if (an.x > an.z) {               // container END: width x height
		f = vec2(v_local.z, v_local.y) + vec2(v_size.z, v_size.y) * 0.5;
		pitch = fit_pitch(vec2(v_size.z, v_size.y), vec2(PITCH.z, PITCH.y));
		axis = 0.0;
	} else {                                // container SIDE: length x height
		f = vec2(v_local.x, v_local.y) + vec2(v_size.x, v_size.y) * 0.5;
		pitch = fit_pitch(vec2(v_size.x, v_size.y), vec2(PITCH.x, PITCH.y));
		axis = 1.0;
	}
}

void fragment() {
	vec2 f;
	vec2 pitch;
	float axis;
	vec3 n_l;
	face_frame(f, pitch, axis, n_l);

	vec2 cid = floor(f / pitch);
	vec2 in_cell = fract(f / pitch) * pitch;          // metres inside this container's panel
	float px = max(fwidth(f.x), fwidth(f.y));         // metres per pixel — the AA for every pattern
	float detail = 1.0 - clamp(px / 0.09, 0.0, 1.0);  // gone once a rib is below a pixel
	float cell_fade = 1.0 - clamp((px - pitch.y * 0.12) / (pitch.y * 0.5), 0.0, 1.0);

	float h = hash21(cid + v_seed * 71.3 + axis * 131.7);
	float h2 = hash21(cid.yx + v_seed * 37.1 + 57.3);

	// --- paint -------------------------------------------------------------------------------
	vec3 civic = vec3(0.86, 0.85, 0.81);
	vec3 gold = vec3(0.66, 0.50, 0.18);
	vec3 paint = h < 0.34 ? paint_a : (h < 0.62 ? paint_b : (h < 0.85 ? paint_c : paint_d));
	paint = mix(paint, h2 < 0.22 ? gold : civic, v_civic * step(0.35, h2));
	// Every container is a slightly different batch: value drift first, hue drift second.
	paint *= 0.62 + 0.42 * h2;
	paint = mix(paint, paint.bgr, step(0.94, hash11(h * 91.0 + v_seed)) * 0.18);

	// --- corrugation -------------------------------------------------------------------------
	// Ribs always run along the panel's SHORT axis in the plane of the face: vertically on a side, and
	// across the width on an end or a roof. `rail` and `post` are the flat plate the ribs stop at —
	// a container's top and bottom rails and its corner castings are not corrugated.
	float rib_u = in_cell.x;   // the panel's first axis is the one the ribs vary along on every face
	float rail = smoothstep(0.10, 0.20, in_cell.y) * (1.0 - smoothstep(pitch.y - 0.20, pitch.y - 0.10, in_cell.y));
	float post = 1.0 - smoothstep(0.05, 0.12, min(in_cell.x, pitch.x - in_cell.x));
	// A container ROOF is a shallow pan inside a raised top rail, and it is seen from directly above on
	// every low cover piece: its border has to be wide enough to read as a separate box at 40 m.
	float roof_rail = (1.0 - smoothstep(0.16, 0.34, min(min(in_cell.x, pitch.x - in_cell.x),
		min(in_cell.y, pitch.y - in_cell.y)))) * step(1.5, axis);
	float flat_ = max(max(1.0 - rail, post), roof_rail);
	// A container ROOF is a shallow pan, not a corrugated wall: at full depth the ribs glitter under
	// the low sun and a stack top reads as sandpaper.
	float depth = axis > 1.5 ? rib_depth * 0.22 : rib_depth;
	float slope = cos(rib_u / rib_pitch * TAU) * depth * (1.0 - flat_) * detail;
	vec3 tang = axis < 0.5 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
	vec3 n_rib = normalize(n_l + tang * slope * 0.18);

	// --- panel separation, castings, stencil, hazard band ------------------------------------
	// A recessed shadow gap on every container edge: this is what makes the stack read as separate
	// boxes rather than one painted wall, and it survives to a long way out. The seam is a fraction of
	// the cell, not a fixed 7 cm: on a 10 x 2.5 m roof cell a 7 cm line is invisible from above, which
	// is exactly how the low cover pieces ended up reading as one red rug.
	vec2 edge = min(in_cell, pitch - in_cell);
	float gw = clamp(min(pitch.x, pitch.y) * 0.055, 0.05, 0.28);
	float gap = (1.0 - smoothstep(gw * 0.45, gw, min(edge.x, edge.y))) * mix(0.35, 1.0, cell_fade);
	paint *= 1.0 - gap * (axis > 1.5 ? 0.72 : 0.55);
	paint *= 1.0 - post * 0.30;
	// The roof rail catches the sky and the pan inside it does not: that one value step is most of what
	// separates a stack of boxes from a painted plane when the camera is above them.
	paint *= 1.0 + roof_rail * 0.22;
	paint *= 1.0 - (1.0 - roof_rail) * step(1.5, axis) * 0.10;

	// Every optional mark below is a masked mix, never a branch. This shader covers a large part of
	// the frame at the closest range in the game — 360 skins drawn over geometry that is already
	// there — so divergent branches and a third noise octave cost real milliseconds (r7 perf A/B).
	float is_end = 1.0 - step(0.5, axis);
	float is_wall = 1.0 - is_end - step(1.5, axis);   // side or end, i.e. not the roof

	// Doors on the container ENDS: a centre seam and four locking bars.
	float seam = (1.0 - smoothstep(0.015, 0.055, abs(in_cell.x - pitch.x * 0.5))) * cell_fade * is_end;
	float bar = 1.0 - smoothstep(0.03, 0.07,
		abs(fract(in_cell.x / (pitch.x * 0.25) + 0.5) - 0.5) * pitch.x * 0.25);
	bar *= step(0.28, in_cell.y / pitch.y) * rail * cell_fade * is_end;
	paint *= 1.0 - seam * 0.45;
	paint = mix(paint, paint * 1.18, bar);

	// A stencil block: the shipping marks that make a crate read as cargo. Procedural bars only.
	vec2 sp = (in_cell - vec2(pitch.x * 0.16, pitch.y * 0.52)) / vec2(1.5, 0.62);
	float in_block = step(0.0, sp.x) * step(sp.x, 1.0) * step(0.0, sp.y) * step(sp.y, 1.0)
		* step(0.72, h2) * step(0.5, axis);
	float glyph = step(0.42, fract(sp.x * 7.0 + floor(sp.y * 3.0) * 0.37));
	paint = mix(paint, vec3(0.86, 0.86, 0.83), in_block * glyph * 0.55 * cell_fade);

	// Hazard band on the bottom rail of about one container in five.
	float hz = step(0.80, h) * (1.0 - step(0.24, in_cell.y)) * is_wall * 0.75 * cell_fade;
	paint = mix(paint, mix(hazard_b, hazard_a, step(0.5, fract((f.x + f.y) * 1.1))), hz);

	// --- weathering --------------------------------------------------------------------------
	// Rust bleeds DOWN from every panel edge and pools at the base of a tall stack. `low` is deliberately
	// lazy (16 m): at 9 m an 8 m cover stack was rusty over its whole height and read as one red mass.
	// One noise field, sampled at three scales, rather than three fields.
	float n = vnoise(vec2(f.x * 1.7, f.y * 0.22 + v_seed));
	float bleed = smoothstep(0.55, 0.0, in_cell.y / pitch.y) * smoothstep(0.30, 0.75, n);
	// The pool is measured against the piece's OWN height, capped at 16 m. A fixed 16 m band made an
	// 8 m cover piece rusty over its whole face, which is what turned the low ones into red rugs.
	float lh = min(16.0, v_size.y * 0.6);
	float low = smoothstep(lh, 0.0, v_local.y + v_size.y * 0.5);   // the bottom of the stack
	float rust = clamp((bleed * 0.7 + low * 0.25 + step(0.86, h) * 0.35) * rust_amount, 0.0, 1.0);
	vec3 albedo = mix(paint, vec3(0.30, 0.15, 0.08), rust * 0.62 * (1.0 - v_exposed * 0.45));
	albedo *= 1.0 - grime_amount * 0.35 * smoothstep(0.35, 1.0, n);
	// A container standing clear of the stack has had the sun on every face for years: chalkier, and
	// the paint has gone further towards its own tint.
	albedo = mix(albedo, mix(albedo, vec3(dot(albedo, vec3(0.33))) * 1.12, 0.32), v_exposed);

	float rough = clamp(0.66 + rust * 0.28 - wet * 0.20 + gap * 0.15, 0.05, 1.0);
	float metal = clamp(0.55 - rust * 0.42, 0.0, 1.0);

	// The top of the stack catches the sky: it is the one face the low sun rakes across.
	float up = clamp(n_l.y, 0.0, 1.0);
	float pool = up * wet * smoothstep(0.45, 0.85, n);
	rough = mix(rough, 0.06, pool);
	metal = mix(metal, 0.0, pool);
	albedo *= 1.0 - pool * 0.45;

	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = mix(0.5, 0.85, pool);
	NORMAL = normalize((MODEL_NORMAL_MATRIX * n_rib).xyz);

	// The city opts out of Godot's fog and does its own two-band aerial perspective (mc_haze).
	vec3 alb = ALBEDO;
	vec3 emis = vec3(0.0);
	EMISSION = apply_haze(alb, emis, layered_haze(v_world, CAMERA_POSITION_WORLD));
	ALBEDO = alb;
}
