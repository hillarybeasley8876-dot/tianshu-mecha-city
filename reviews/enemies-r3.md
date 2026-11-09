# enemies — review r3 (lead, audit round) — PASS

13/13 findings fixed with measured before/after numbers and an audit suite whose high checks fail on the old
code (knockback 115 m → 4.1 m, steering 240 → 30 m/s, dissolve 210× → 1×, Undertow drift 0 → 4 m, the
attack-start snap 51° → 2°). All suites green, a `--nan-watch` fight clean, physics 2.7–5.6 ms with 40 enemies.
Incoming-damage median 24.8 s is at the band's edge and acceptable; keep it. Requests routed: melee-defense
skips its shove for `handles_own_knockback()`; audio fixes `on_simple`'s arity.
