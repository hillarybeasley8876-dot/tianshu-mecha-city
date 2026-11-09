// mc_facade_style (city-art r12 §1) — the facade FAMILY a kit building wears, and the variant of it.
//
// r11 gave every kit building the same skin: one 3.4 x 4.0 m office cell with a 70 % x 55 % pane, on
// towers, megablocks, mid-rises, civic halls and old-town blocks alike. Five buildings in one frame
// were visibly the same building, which is the copy-paste read the user complained about.
//
// So the facade is a small family now, chosen deterministically and never at random:
//
//   family   the model's `kit.json` BAND picks it — `McKitSkin.facade_family_for()` reads the band out
//            of the albedo texture's path and sets the `facade_family` uniform. A tower is glass
//            dominant, a megablock is horizontal, an old-town block is wall dominant. That is
//            architecture, not taste, so it follows the model.
//   variant  the INSTANCE picks it, from the same per-building hash the window lighting uses
//            (`b_var`, a hash of the building's own world cell). Two towers of the same model can
//            therefore differ; two runs of the same build cannot.
//   phase    the instance also offsets the grid along the wall and up it, so two neighbours of the
//            same model do not line their mullions up across the street.
//
// | family | band | read |
// |---|---|---|
// | 0 curtain | tower | glass dominant: 1.5-2.0 m bays, 85-90 % panes, 0.08 m mullions, spandrel at the slab only, per-tower glass tint |
// | 1 ribbon  | megablock, midrise | horizontal: a continuous 1.6-2.0 m window band, a 2.0-2.4 m solid spandrel, a vertical joint every 6-9 m. Variant 1 carries a balcony / plant line. |
// | 2 punched | oldtown, civic | wall dominant: 35-45 % windows, a deep reveal, a cornice every 3-4 storeys, an arcade at the ground floor |

// The style of one (family, variant) pair. Everything the grid needs, in metres where it is a size.
struct FacadeStyle {
	float cell_w;      // the PANE subdivision along the wall — also the cell the lit windows use
	float cell_h;      // storey height
	float pane_w;      // pane, as a fraction of the cell
	float pane_h;
	float mull_m;      // the vertical line between panes; 0 = a continuous wall
	float mull_dark;
	float joint_m;     // a stronger vertical joint every N metres (a ribbon block's structural bay)
	float joint_dark;
	float slab_m;      // the horizontal band at the slab line (a spandrel on a ribbon block)
	float slab_dark;
	float reveal;      // how dark the recess around a pane is
	float cornice_m;   // the cornice band, metres; 0 = no cornice
	float cornice_dark;
	float cornice_n;   // cornice every N storeys
	float balc_m;      // the balcony / plant band, metres; 0 = none
	float balc_dark;
	float rail_m;      // the light rail line on top of it
	vec3 glass;        // the pane's own tint, per tower
};

// 3 variants per family. `vi` is 0..2.
FacadeStyle facade_style(int fam, int vi) {
	FacadeStyle s;
	s.cornice_m = 0.0;
	s.cornice_dark = 0.0;
	s.cornice_n = 3.0;
	s.balc_m = 0.0;
	s.balc_dark = 0.0;
	s.rail_m = 0.0;
	s.joint_m = 0.0;
	s.joint_dark = 0.0;
	if (fam == 0) {
		// --- curtain wall: the glass IS the wall. Thin mullions, a spandrel only where the slab is.
		s.cell_w = vi == 0 ? 1.5 : (vi == 1 ? 1.8 : 2.0);
		s.cell_h = vi == 0 ? 3.9 : (vi == 1 ? 4.0 : 4.2);
		s.pane_w = vi == 0 ? 0.88 : (vi == 1 ? 0.86 : 0.90);
		s.pane_h = vi == 0 ? 0.86 : (vi == 1 ? 0.82 : 0.88);
		s.mull_m = vi == 1 ? 0.10 : 0.08;
		s.mull_dark = 0.22;
		s.slab_m = vi == 1 ? 0.45 : 0.32;
		s.slab_dark = vi == 2 ? 0.34 : 0.28;
		s.reveal = 0.16;
		// A tower's glass is the biggest colour decision it makes: cool blue-green, warm bronze, or a
		// near-black that only reads through its reflection.
		s.glass = vi == 0 ? vec3(0.078, 0.104, 0.140)
				: (vi == 1 ? vec3(0.115, 0.098, 0.078) : vec3(0.055, 0.062, 0.078));
	} else if (fam == 1) {
		// --- ribbon: a continuous band of glass with a solid spandrel under it, jointed every 6-9 m.
		// The band is ONE opening, but it is still divided by mullions — and, more importantly, the LIT
		// windows are per pane. Leaving the cell at the 7 m structural bay lit a 7 x 1.8 m slab of
		// window at a time, which is what made the first pass read as a wall of random blocks.
		s.cell_w = 1.8;
		s.joint_m = vi == 0 ? 7.0 : (vi == 1 ? 6.0 : 9.0);
		s.joint_dark = 0.40;
		s.cell_h = vi == 1 ? 3.8 : (vi == 2 ? 4.2 : 4.0);
		s.pane_w = 0.90;
		s.pane_h = (vi == 1 ? 1.6 : (vi == 2 ? 2.0 : 1.8)) / s.cell_h;
		s.mull_m = 0.12;
		s.mull_dark = 0.34;
		s.slab_m = s.cell_h - s.pane_h * s.cell_h;
		s.slab_dark = 0.26;
		s.reveal = 0.30;
		s.glass = vi == 1 ? vec3(0.090, 0.100, 0.118) : vec3(0.070, 0.090, 0.120);
		if (vi == 1) {
			// One megablock variant in three carries a balcony / plant line: a 0.6 m dark band with a
			// light rail on top, every storey. It is the cheapest way to break a 200 m horizontal.
			s.balc_m = 0.6;
			s.balc_dark = 0.45;
			s.rail_m = 0.10;
		}
	} else if (fam == 3) {
		// --- r11's single skin, kept as an A/B arm. `--facade-r11` forces every kit wall onto it, which
		// is how the "same frames, r11 -> r12" sheet is made from ONE build on ONE machine instead of
		// from two checkouts that also differ in everything else that landed between them.
		s.cell_w = 3.4;
		s.cell_h = 4.0;
		s.pane_w = 0.70;
		s.pane_h = 0.55;
		s.mull_m = 0.15;
		s.mull_dark = 0.30;
		s.slab_m = 0.5;
		s.slab_dark = 0.26;
		s.reveal = 0.40;
		s.glass = vec3(0.075, 0.098, 0.133);
	} else {
		// --- punched: the wall is the wall and the window is a hole in it.
		s.cell_w = vi == 0 ? 3.0 : (vi == 1 ? 2.6 : 3.6);
		s.cell_h = vi == 1 ? 3.4 : (vi == 2 ? 4.0 : 3.6);
		s.pane_w = vi == 0 ? 0.38 : (vi == 1 ? 0.42 : 0.35);
		s.pane_h = vi == 1 ? 0.40 : 0.45;
		s.mull_m = 0.0;
		s.mull_dark = 0.10;
		s.slab_m = 0.0;
		s.slab_dark = 0.0;
		s.reveal = 0.55;
		s.cornice_m = 0.45;
		s.cornice_dark = 0.34;
		s.cornice_n = vi == 1 ? 4.0 : 3.0;
		s.glass = vi == 2 ? vec3(0.100, 0.086, 0.070) : vec3(0.082, 0.086, 0.098);
	}
	return s;
}

// The variant, from the per-building hash. Three per family, and the hash is the same one the window
// lighting uses, so a building's facade and its lit windows agree about which building it is.
int facade_variant(float b_var, int fam) {
	if (fam == 3) {
		return 0;           // the r11 A/B arm has one variant, by definition
	}
	float h = fract(b_var * 37.13 + float(fam) * 0.317);
	return int(floor(h * 3.0));
}

// The grid's phase, so neighbours do not line up: a fraction of a bay along the wall and of a storey
// up it. The vertical part is small on purpose — a whole storey would put the slab line of one tower
// at the sill line of the next.
vec2 facade_phase(float b_var, FacadeStyle s) {
	return vec2(fract(b_var * 91.7) * s.cell_w, fract(b_var * 53.3) * s.cell_h * 0.5);
}

// r11 had no phase at all; the A/B arm must not have one either or it is not r11.
vec2 facade_phase_for(float b_var, int fam, FacadeStyle s) {
	return fam == 3 ? vec2(0.0) : facade_phase(b_var, s);
}
