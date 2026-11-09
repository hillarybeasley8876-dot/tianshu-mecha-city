class_name MonsterBodyParts
extends RefCounted
## Placeholder silhouettes (enemies-owned), built from primitives so each archetype reads at a
## glance from 3/4 view before the Tripo models land. Row format:
##   [shape, position, size, material, rotation_degrees]
## shape: "box" | "cap" (capsule: size = diameter, length, diameter) | "sph" | "cyl".
## material index = MonsterPlaceholderModel.MAT_*.
## Sizes are metres; heights match EnemyTypes (ripper 6 m … juggernaut 22 m).

const PARTS: Dictionary = {
	&"ripper": [
		["cap", Vector3(0, 2.6, 0.4), Vector3(2.4, 5.2, 2.4), 0, Vector3(90, 0, 0)],
		["box", Vector3(0, 2.7, -3.0), Vector3(2.0, 1.4, 2.0), 0, Vector3(0, 0, 0)],
		["box", Vector3(-0.7, 2.5, -4.1), Vector3(0.3, 0.3, 1.6), 1, Vector3(0, -14, 0)],
		["box", Vector3(0.7, 2.5, -4.1), Vector3(0.3, 0.3, 1.6), 1, Vector3(0, 14, 0)],
		["box", Vector3(0, 3.9, -0.4), Vector3(0.5, 0.4, 3.6), 1, Vector3(0, 0, 0)],
		["sph", Vector3(0, 3.7, 1.6), Vector3(1.1, 1.1, 1.1), 2, Vector3(0, 0, 0)],
		# Six legs, two segments each (thigh → knee → shin): single struts read as flat sticks in a
		# pack, and the pack's silhouette is the whole point of the ripper.
		["cap", Vector3(-1.65, 2.55, -1.4), Vector3(0.55, 1.75, 0.55), 0, Vector3(0, 0, 59)],
		["sph", Vector3(-2.4, 3.0, -1.4), Vector3(0.5, 0.5, 0.5), 0, Vector3(0, 0, 0)],
		["cap", Vector3(-2.7, 1.55, -1.4), Vector3(0.42, 2.96, 0.42), 0, Vector3(0, 0, 11.7)],
		["cap", Vector3(1.65, 2.55, -1.4), Vector3(0.55, 1.75, 0.55), 0, Vector3(0, 0, -59)],
		["sph", Vector3(2.4, 3.0, -1.4), Vector3(0.5, 0.5, 0.5), 0, Vector3(0, 0, 0)],
		["cap", Vector3(2.7, 1.55, -1.4), Vector3(0.42, 2.96, 0.42), 0, Vector3(0, 0, -11.7)],
		["cap", Vector3(-1.65, 2.55, 0.6), Vector3(0.55, 1.75, 0.55), 0, Vector3(0, 0, 59)],
		["sph", Vector3(-2.4, 3.0, 0.6), Vector3(0.5, 0.5, 0.5), 0, Vector3(0, 0, 0)],
		["cap", Vector3(-2.7, 1.55, 0.6), Vector3(0.42, 2.96, 0.42), 0, Vector3(0, 0, 11.7)],
		["cap", Vector3(1.65, 2.55, 0.6), Vector3(0.55, 1.75, 0.55), 0, Vector3(0, 0, -59)],
		["sph", Vector3(2.4, 3.0, 0.6), Vector3(0.5, 0.5, 0.5), 0, Vector3(0, 0, 0)],
		["cap", Vector3(2.7, 1.55, 0.6), Vector3(0.42, 2.96, 0.42), 0, Vector3(0, 0, -11.7)],
		["cap", Vector3(-1.65, 2.55, 2.4), Vector3(0.55, 1.75, 0.55), 0, Vector3(0, 0, 59)],
		["sph", Vector3(-2.4, 3.0, 2.4), Vector3(0.5, 0.5, 0.5), 0, Vector3(0, 0, 0)],
		["cap", Vector3(-2.7, 1.55, 2.4), Vector3(0.42, 2.96, 0.42), 0, Vector3(0, 0, 11.7)],
		["cap", Vector3(1.65, 2.55, 2.4), Vector3(0.55, 1.75, 0.55), 0, Vector3(0, 0, -59)],
		["sph", Vector3(2.4, 3.0, 2.4), Vector3(0.5, 0.5, 0.5), 0, Vector3(0, 0, 0)],
		["cap", Vector3(2.7, 1.55, 2.4), Vector3(0.42, 2.96, 0.42), 0, Vector3(0, 0, -11.7)],
	],
	&"mantis": [
		["cap", Vector3(-1.3, 3.6, 0.2), Vector3(1.5, 7.0, 1.5), 0, Vector3(0, 0, 0)],
		["cap", Vector3(1.3, 3.6, 0.2), Vector3(1.5, 7.0, 1.5), 0, Vector3(0, 0, 0)],
		["box", Vector3(-1.4, 0.5, -0.9), Vector3(1.8, 1.0, 3.2), 0, Vector3(0, 0, 0)],
		["box", Vector3(1.4, 0.5, -0.9), Vector3(1.8, 1.0, 3.2), 0, Vector3(0, 0, 0)],
		["box", Vector3(0, 9.6, 0), Vector3(3.6, 5.2, 2.6), 0, Vector3(0, 0, 0)],
		["box", Vector3(0, 12.6, 0), Vector3(2.4, 1.0, 2.2), 1, Vector3(0, 0, 0)],
		["box", Vector3(0, 13.6, -0.3), Vector3(1.6, 1.3, 2.0), 0, Vector3(0, 0, 0)],
		["box", Vector3(0, 13.8, -1.35), Vector3(1.1, 0.4, 0.3), 1, Vector3(0, 0, 0)],
		["box", Vector3(-2.6, 10.2, -1.6), Vector3(0.5, 0.5, 7.0), 0, Vector3(-18, 0, 0)],
		["box", Vector3(2.6, 10.2, -1.6), Vector3(0.5, 0.5, 7.0), 0, Vector3(-18, 0, 0)],
		["box", Vector3(-2.6, 9.4, -4.6), Vector3(0.25, 1.1, 4.4), 1, Vector3(-18, 0, 0)],
		["box", Vector3(2.6, 9.4, -4.6), Vector3(0.25, 1.1, 4.4), 1, Vector3(-18, 0, 0)],
		["sph", Vector3(0, 11.4, 1.5), Vector3(1.6, 1.6, 1.6), 2, Vector3(0, 0, 0)],
	],
	&"spitter": [
		["cap", Vector3(-2.2, 3.0, -1.8), Vector3(1.3, 6.0, 1.3), 0, Vector3(0, 0, 12)],
		["cap", Vector3(2.2, 3.0, -1.8), Vector3(1.3, 6.0, 1.3), 0, Vector3(0, 0, -12)],
		["cap", Vector3(-2.4, 3.0, 2.4), Vector3(1.3, 6.0, 1.3), 0, Vector3(0, 0, 12)],
		["cap", Vector3(2.4, 3.0, 2.4), Vector3(1.3, 6.0, 1.3), 0, Vector3(0, 0, -12)],
		["sph", Vector3(0, 8.0, 0.4), Vector3(5.2, 4.6, 6.6), 0, Vector3(0, 0, 0)],
		["sph", Vector3(0, 10.4, 1.8), Vector3(3.4, 3.0, 3.4), 2, Vector3(0, 0, 0)],
		["box", Vector3(0, 8.6, -3.4), Vector3(1.8, 1.8, 2.2), 0, Vector3(0, 0, 0)],
		["cyl", Vector3(0, 10.4, -4.4), Vector3(1.5, 3.6, 1.5), 1, Vector3(-38, 0, 0)],
		["box", Vector3(0, 6.2, 0.4), Vector3(4.6, 0.4, 0.6), 1, Vector3(0, 0, 0)],
	],
	&"harrier": [
		["cap", Vector3(0, 0, 0), Vector3(2.6, 7.0, 2.6), 0, Vector3(90, 0, 0)],
		["box", Vector3(-4.8, 0.5, 0.2), Vector3(7.6, 0.5, 3.4), 0, Vector3(0, 0, -9)],
		["box", Vector3(4.8, 0.5, 0.2), Vector3(7.6, 0.5, 3.4), 0, Vector3(0, 0, 9)],
		["box", Vector3(-8.4, 1.1, 0.2), Vector3(0.4, 0.4, 3.2), 1, Vector3(0, 0, -9)],
		["box", Vector3(8.4, 1.1, 0.2), Vector3(0.4, 0.4, 3.2), 1, Vector3(0, 0, 9)],
		["box", Vector3(0, 0.2, 4.4), Vector3(1.2, 0.4, 3.6), 0, Vector3(0, 0, 0)],
		["box", Vector3(0, 0.1, -3.6), Vector3(1.6, 1.2, 2.2), 0, Vector3(0, 0, 0)],
		["box", Vector3(0, -0.2, -4.5), Vector3(1.2, 0.4, 0.5), 1, Vector3(0, 0, 0)],
		["sph", Vector3(0, 1.3, 1.2), Vector3(1.5, 1.5, 1.5), 2, Vector3(0, 0, 0)],
	],
	&"juggernaut": [
		["box", Vector3(-2.8, 5.0, 0), Vector3(4.2, 10.0, 4.2), 0, Vector3(0, 0, 0)],
		["box", Vector3(2.8, 5.0, 0), Vector3(4.2, 10.0, 4.2), 0, Vector3(0, 0, 0)],
		["box", Vector3(-2.8, 0.8, -0.6), Vector3(4.6, 1.6, 5.6), 0, Vector3(0, 0, 0)],
		["box", Vector3(2.8, 0.8, -0.6), Vector3(4.6, 1.6, 5.6), 0, Vector3(0, 0, 0)],
		["box", Vector3(0, 13.6, 0), Vector3(9.0, 8.0, 6.0), 0, Vector3(0, 0, 0)],
		["box", Vector3(-2.4, 14.4, -3.2), Vector3(3.2, 4.4, 1.2), 3, Vector3(0, 0, 8)],
		["box", Vector3(2.4, 14.4, -3.2), Vector3(3.2, 4.4, 1.2), 3, Vector3(0, 0, -8)],
		["box", Vector3(0, 11.4, -3.2), Vector3(5.0, 2.2, 1.2), 3, Vector3(0, 0, 0)],
		["box", Vector3(-5.6, 14.0, 0), Vector3(2.6, 7.0, 2.6), 0, Vector3(0, 0, 10)],
		["box", Vector3(5.6, 14.0, 0), Vector3(2.6, 7.0, 2.6), 0, Vector3(0, 0, -10)],
		["box", Vector3(0, 18.4, -0.4), Vector3(3.4, 2.4, 3.6), 0, Vector3(0, 0, 0)],
		["box", Vector3(0, 18.4, -2.2), Vector3(2.6, 0.6, 0.4), 1, Vector3(0, 0, 0)],
		["box", Vector3(0, 17.0, 0), Vector3(0.8, 0.8, 6.2), 1, Vector3(0, 0, 0)],
		["sph", Vector3(0, 14.0, 3.2), Vector3(3.2, 3.2, 3.2), 2, Vector3(0, 0, 0)],
	],
}

## Named sockets (the model API). Monster assets will provide the same names on the rigged model.
const SOCKETS: Dictionary = {
	&"ripper": {&"mouth": Vector3(0, 2.6, -4.4), &"chest": Vector3(0, 2.8, -1.0),
		&"back": Vector3(0, 3.8, 1.6), &"muzzle": Vector3(0, 2.6, -4.6)},
	&"mantis": {&"mouth": Vector3(0, 13.8, -1.6), &"chest": Vector3(0, 10.4, -1.4),
		&"back": Vector3(0, 11.4, 1.6), &"hand_l": Vector3(-2.6, 9.2, -5.2),
		&"hand_r": Vector3(2.6, 9.2, -5.2), &"muzzle": Vector3(0, 13.6, -1.8)},
	&"spitter": {&"mouth": Vector3(0, 8.6, -4.6), &"chest": Vector3(0, 8.0, -3.2),
		&"back": Vector3(0, 10.4, 1.8), &"muzzle": Vector3(0, 11.4, -5.4)},
	&"harrier": {&"mouth": Vector3(0, 0.1, -4.8), &"chest": Vector3(0, 0, -2.0),
		&"back": Vector3(0, 1.3, 1.2), &"muzzle": Vector3(0, -0.4, -4.8)},
	&"juggernaut": {&"mouth": Vector3(0, 18.4, -2.6), &"chest": Vector3(0, 14.0, -3.4),
		&"back": Vector3(0, 14.0, 3.4), &"hand_l": Vector3(-6.6, 11.0, 0),
		&"hand_r": Vector3(6.6, 11.0, 0), &"muzzle": Vector3(0, 18.4, -2.8)},
}
