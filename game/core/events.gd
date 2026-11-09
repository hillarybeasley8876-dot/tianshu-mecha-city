extends Node
## Global signal bus (autoload "Events", core-owned). Gameplay units EMIT semantic events here; the
## feel, audio, HUD and encounter units LISTEN. Keep payloads typed; never rename a signal without the
## lead (CONTRACTS.md §Events). `hit` is always a HitInfo; actors are the damageable root nodes.

# --- combat ------------------------------------------------------------------------------------
signal hit_landed(hit: HitInfo, receiver: Node)          ## any successful hit (after armour/weak point)
signal player_damaged(hit: HitInfo)                       ## after the player's defences were applied
signal enemy_staggered(enemy: Node, hit: HitInfo)         ## poise broken: finisher window opens
signal enemy_killed(enemy: Node, hit: HitInfo)
signal attack_blocked(hit: HitInfo)                       ## shield block (damage reduced)
signal parry_success(hit: HitInfo, attacker: Node)        ## perfect parry: counter window opens
signal perfect_dodge(attacker: Node)                      ## dodge in the last moment: witch time
signal weapon_fired(weapon: StringName, muzzle: Vector3, direction: Vector3)
signal weapon_switched(weapon: StringName)
signal melee_swing(move: StringName, step: int)           ## saber move started (combo step 1..n)
signal skill_used(skill: StringName)
signal skill_ready(skill: StringName)
signal lock_changed(target: Node3D)                       ## hard-lock target (null = released)
signal missiles_locked(count: int)
signal overdrive_changed(active: bool)
signal ultimate_fired()
signal combo_changed(count: int, rank: StringName)        ## style meter (D..SSS); 0 = reset
signal enemy_telegraph(enemy: Node, attack: StringName, kind: StringName)  ## kind: parryable/unblockable/ranged
signal prime_collapsed(center: Vector3, count: int)         ## COLLAPSE detonation (skills)
signal execution_ready(enemy: Node)                       ## a staggered enemy is in Core Rend reach (melee)

# --- movement ----------------------------------------------------------------------------------
signal boost_started(kind: StringName)                    ## &"quick" (dodge burst) | &"slide" | &"assault"
signal boost_ended(kind: StringName)
signal jumped()
signal flight_changed(flying: bool)
signal landed(impact_speed: float)                        ## m/s downward at touchdown
signal footstep(position: Vector3, heavy: bool)
signal energy_depleted()                                  ## EN hit 0: overheat penalty starts
signal camera_mode_changed(first_person: bool)

# --- game flow ---------------------------------------------------------------------------------
signal world_ready()
signal player_spawned(player: Node3D)
signal player_died()
signal encounter_started(id: StringName)
signal encounter_cleared(id: StringName)
signal spire_destroyed(spire: Node3D, destroyed: int, total: int)  ## a Hive Spire fell (flow); the titan roars
signal boss_intro(title: String, subtitle: String)   ## boss title card (HUD) + stinger (audio)
signal boss_phase(phase: int)
signal objective_changed(text: String)
signal game_won()
signal paused_changed(paused: bool)
