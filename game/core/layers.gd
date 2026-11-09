class_name Layers
extends RefCounted
## Physics layer bits (core-owned; names in project.godot [layer_names]). Use these constants, never
## raw numbers. Bodies: WORLD/PROPS static or dynamic scenery, PLAYER/ENEMY character bodies.
## Hurtboxes are Area3D (class Hurtbox) on PLAYER_HURTBOX / ENEMY_HURTBOX; shots raycast against them.

const WORLD := 1 << 0
const PROPS := 1 << 1
const PLAYER := 1 << 2
const ENEMY := 1 << 3
const PLAYER_HURTBOX := 1 << 4
const ENEMY_HURTBOX := 1 << 5
const PLAYER_SHOT := 1 << 6
const ENEMY_SHOT := 1 << 7
const TRIGGER := 1 << 8
const BARRIER := 1 << 9
const DEBRIS := 1 << 10

## What the player's shots/beams/melee query (hurtboxes + anything that stops a shot).
const MASK_PLAYER_ATTACK := WORLD | PROPS | ENEMY_HURTBOX
## What enemy attacks query (the player's barrier absorbs them before the hurtbox).
const MASK_ENEMY_ATTACK := WORLD | PROPS | PLAYER_HURTBOX | BARRIER
## Character movement collides with scenery and other characters.
const MASK_CHARACTER := WORLD | PROPS | PLAYER | ENEMY
## Line of sight / camera collision: scenery only.
const MASK_SIGHT := WORLD | PROPS
