"""Bank A: hero locomotion, mech mechanisms, cockpit alerts (dossier §3 rows 1-16, 53, 67).

Layer codes: T transient, B body, S sub, M mechanical, Tl tail, D debris, UI.
"""

from __future__ import annotations

import numpy as np

import bank_common as C
import recipes as R
from dsp import at, exp_env, frames, mix, noise_band
from registry import sound

# --- footsteps ------------------------------------------------------------------------------------
def _footstep(seed: int, heavy: bool) -> np.ndarray:
    out = C.metal_impact(seed, size=1.35 if heavy else 1.0, debris=1.0 if heavy else 0.25,
                         air=0.6, taps=heavy)
    # servo pre-roll 80 ms *before* contact (dossier §1.2): negative offset via pre-pend
    pre = C.l_mech(seed + 7, 0.09, 380.0, 0.8, 0.55)
    n = out.size + frames(0.08)
    combined = at(n, pre, 0.0) + at(n, out, 0.08)
    if heavy:
        combined += at(n, C.l_sub(seed + 8, 0.5, 55.0, 26.0, 0.8), 0.09)
        combined += at(n, C.l_debris(seed + 9, 1.0, 30.0, 300.0, 5000.0), 0.12)
    return combined


sound("footstep_hero", lambda s: _footstep(s, False), layers="M/T/B/S/D", variants=4, peak_db=-3.0)
sound("footstep_hero_heavy", lambda s: _footstep(s, True), layers="M/T/B/S/D/Tl", variants=3,
      peak_db=-2.0)

# --- servos and hydraulics ------------------------------------------------------------------------
sound("servo_move_s", lambda s: C.servo_layer(s, 0.7, 0.26, 0.35), layers="M", variants=3,
      peak_db=-8.0)
sound("servo_move_m", lambda s: C.servo_layer(s, 1.0, 0.34, 0.5), layers="M", variants=3,
      peak_db=-7.0)
sound("servo_move_l", lambda s: C.servo_layer(s, 1.6, 0.42, 0.7), layers="M", variants=2,
      peak_db=-6.0)
sound("hydraulic_release",
      lambda s: mix(C.l_air(s, 0.22, 3000.0, 9000.0, 0.07),
                    at(frames(0.25), C.l_transient(s + 1, 2200.0, 0.008, 0.04), 0.0, 0.3)),
      layers="M", variants=2, peak_db=-9.0)

# --- jump / land ----------------------------------------------------------------------------------
sound("jump",
      lambda s: mix(C.l_transient(s, 5000.0, 0.006, 0.03)[: frames(0.05)] * 0.7,
                    at(frames(0.4), R.whoosh(0.3, 400.0, 1800.0, s) * 0.6, 0.02),
                    at(frames(0.4), C.l_mech(s + 2, 0.26, 620.0, 1.3, 0.6), 0.0)),
      layers="T/M", variants=2, peak_db=-5.0)
sound("land_light",
      lambda s: C.metal_impact(s, size=1.0, debris=0.3, air=1.0), layers="T/B/M", variants=3,
      peak_db=-4.0)
sound("land_heavy",
      lambda s: C.metal_impact(s, size=1.7, debris=1.2, air=0.8, taps=True), layers="T/B/S/D/Tl",
      variants=3, peak_db=-2.0)

# --- thrusters ------------------------------------------------------------------------------------
sound("hover_loop", lambda s: C.thruster_loop(s, 2.0, 0.75), layers="B/M", loop=True, peak_db=-9.0)
sound("flight_loop", lambda s: C.thruster_loop(s, 2.0, 1.25), layers="B/M", loop=True, peak_db=-7.0)
sound("boost_slide_loop", lambda s: C.thruster_loop(s, 2.0, 0.9, scrape=0.9), layers="B/M/D",
      loop=True, peak_db=-9.0)


def _boost_start(seed: int) -> np.ndarray:
    n = frames(1.1)
    ign = at(n, C.l_transient(seed, 6000.0, 0.005, 0.02) * 1.1, 0.0)
    chuff = at(n, noise_band(frames(0.12), 120.0, 1600.0, R.rng(seed + 1))
               * exp_env(frames(0.12), 0.035, 0.002), 0.004)
    roar = at(n, C.thruster_loop(seed + 2, 1.0, 1.0) * np.linspace(0.4, 1.0, frames(1.0)), 0.01, 0.9)
    sub = at(n, R.sub_thump(0.7, 48.0, 40.0, seed) * 0.8, 0.0)
    return ign + chuff + roar + sub


sound("boost_start", _boost_start, layers="T/B/S/M", peak_db=-3.0)


def _dash(seed: int) -> np.ndarray:
    n = frames(0.55)
    chuff = at(n, noise_band(frames(0.03), 800.0, 6000.0, R.rng(seed)) * exp_env(frames(0.03), 0.008), 0.0)
    return chuff + at(n, R.whoosh(0.32, 500.0, 3200.0, seed + 1), 0.0, 0.9) \
        + at(n, C.l_air(seed + 2, 0.12, 4000.0, 11000.0, 0.035) * 0.6, 0.18)


sound("dash", _dash, layers="T/B", variants=3, peak_db=-4.0)


def _assault_boost(seed: int) -> np.ndarray:
    """Sonic boom + roar + whine x1.5 (dossier §1.2)."""
    n = frames(1.6)
    boom = R.explosion_near(1.4, 0.75, seed) * 0.8
    roar = C.thruster_loop(seed + 1, 1.4, 1.5)
    return at(n, boom, 0.0, 0.9) + at(n, roar, 0.02, 1.0) \
        + at(n, R.sub_thump(0.9, 55.0, 30.0, seed) * 0.7, 0.0)


sound("assault_boost", _assault_boost, layers="T/B/S/M", peak_db=-2.0)


def _boost_end(seed: int) -> np.ndarray:
    """Spool-down: falling servo + air release (0.6 s)."""
    n = frames(0.7)
    fall = C.l_mech(seed, 0.55, 520.0, 0.45, 1.0)
    hiss = C.l_air(seed + 1, 0.3, 2000.0, 8000.0, 0.1)
    return at(n, fall, 0.0) + at(n, hiss * 0.7, 0.05)


sound("boost_end", _boost_end, layers="M", variants=2, peak_db=-6.0)

# --- cockpit --------------------------------------------------------------------------------------
sound("energy_outage",
      lambda s: mix(R.charge_riser(0.8, s)[::-1].copy() * 0.8,
                    at(frames(1.3), C.radio_beeps(s, 1000.0, 2, 0.22, 0.09), 0.85)),
      layers="M/UI", peak_db=-6.0)
sound("camera_toggle",
      lambda s: mix(C.servo_layer(s, 0.85, 0.22, 0.0),
                    at(frames(0.35), C.l_air(s + 3, 0.2, 2500.0, 7000.0, 0.06), 0.14)),
      layers="M", variants=2, peak_db=-8.0)

# --- damage ---------------------------------------------------------------------------------------
def _hurt(seed: int, heavy: bool) -> np.ndarray:
    n = frames(1.0 if heavy else 0.5)
    out = C.metal_impact(seed, 1.5 if heavy else 0.9, 0.8 if heavy else 0.2, 0.4, heavy)
    out = out[:n] if out.size >= n else np.pad(out, (0, n - out.size))
    if heavy:
        out += at(n, C.l_sub(seed + 5, 0.55, 58.0, 26.0, 0.9), 0.0)
        out += at(n, C.radio_beeps(seed + 6, 660.0, 2, 0.16, 0.1), 0.35)
    return out


sound("hurt_light", lambda s: _hurt(s, False), layers="T/B", variants=3, peak_db=-4.0)
sound("hurt_heavy", lambda s: _hurt(s, True), layers="T/B/S/UI", variants=2, peak_db=-2.0)

# --- alarms (dossier §1.5) ------------------------------------------------------------------------
sound("alarm_warning", lambda s: R.alarm(880.0, 660.0, 0.5, 3, 0.5), layers="UI", peak_db=-8.0)
sound("alarm_caution", lambda s: C.radio_beeps(s, 1000.0, 2, 0.5, 0.09), layers="UI", peak_db=-10.0)


def _heartbeat(seed: int) -> np.ndarray:
    """70 BPM double-thump loop, 2 bars: rises in pitch when the mixer speeds it up."""
    period = frames(60.0 / 70.0)
    out = np.zeros(period)
    for offset, gain in ((0.0, 1.0), (0.22, 0.65)):
        thump = R.sub_thump(0.28, 78.0, 38.0, seed + int(offset * 100)) * gain
        out += at(period, thump, offset)
    return out


sound("heartbeat_loop", _heartbeat, layers="S", loop=True, peak_db=-8.0)


# --- last stand (FEEL `last_stand`, docs/FEEL.md: "alarm + low sub") --------------------------------
def _last_stand(seed: int) -> np.ndarray:
    """The hit that takes the mech below 15 % and leaves it alive: 0.5x for 1.5 s.

    A MASTER CAUTION pair a fifth below `alarm_warning` (440/330 Hz, slower, 2 repeats) so the moment
    reads as its own alert rather than a second copy of the damage alarm the row already layers, a
    55 -> 22 Hz sub drop that carries the weight, the steam vents and the thruster burst from the
    row's VFX column, and a metal groan underneath it all.
    """
    # 2.1 s: the alarm pair is the longest layer and ends at 1.93 s.
    n = frames(2.1)
    out = at(n, R.sub_thump(1.9, 55.0, 22.0, seed) * 1.0, 0.0)
    out += at(n, R.alarm(440.0, 330.0, 0.42, 2, 0.42), 0.05)
    # steam vents (both sides, the second a touch later so it reads as two ports)
    out += at(n, C.l_air(seed + 1, 1.0, 1500.0, 9000.0, 0.34), 0.10, 0.9)
    out += at(n, C.l_air(seed + 2, 0.8, 2000.0, 11000.0, 0.26), 0.22, 0.7)
    # thruster burst: the mech kicks itself away from the hit
    out += at(n, C.thruster_loop(seed + 3, 1.0, 0.85) * np.linspace(1.0, 0.25, frames(1.0)), 0.0, 0.5)
    out += at(n, C.l_transient(seed + 4, 2400.0, 0.012, 0.06), 0.0, 0.8)
    # armour groan, pitched down: this is the machine telling you it is nearly done
    out += at(n, C.creature_voice(seed + 5, "growl", -6.0, 1.4, 24.0, 0.0) * 0.45, 0.30)
    return out


sound("last_stand", _last_stand, layers="T/B/S/M/UI", peak_db=-2.0)
