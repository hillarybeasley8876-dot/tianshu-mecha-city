"""Bank B: weapons (dossier §3 rows 17-31). Rates read from game/combat/weapons/tuning/*:
rifle 240 rpm (0.25 s), charge stages at 0.6/1.2 s, gatling 900 rpm (15 rps), missiles 12 over 0.5 s.
"""

from __future__ import annotations

import numpy as np

import bank_common as C
import recorded as RD
import recipes as R
from dsp import SR, at, exp_env, frames, high_shelf, highpass, mix, noise_band, lowpass
from registry import sound

GATLING_RPS = 15.0

# --- P1 Pierce-Light Rifle ------------------------------------------------------------------------
def _rifle_fire(seed: int) -> np.ndarray:
    """Beam layer (synth) over a recorded rifle report: the discharge mechanism is real hardware,
    the energy on top of it is not — that split is rule 11."""
    n = frames(0.75)
    out = at(n, R.beam(seed, 1.0, 1.0), 0.0, 1.0)
    # Recorded report, band-limited to 200 Hz-4 kHz so it reads as mechanism, not as a gunshot.
    crack = lowpass(highpass(RD.gunshot(seed + 9, "rifle", 0.35), 200.0), 4000.0)
    out += at(n, crack, 0.0, 0.45)
    cap = at(n, C.l_transient(seed + 4, 4200.0, 0.004, 0.02), 0.0, 0.5)   # capacitor click
    mech = at(n, C.l_mech(seed + 5, 0.12, 700.0, 1.2, 0.35), 0.0)
    return out + cap + mech


sound("rifle_fire", _rifle_fire, layers="T/B/M/Tl", variants=3, peak_db=-3.0)
sound("rifle_charge_1", lambda s: R.charge_riser(0.6, s, True, 220.0, 520.0), layers="B/UI",
      peak_db=-6.0)
sound("rifle_charge_2", lambda s: R.charge_riser(1.2, s, True, 300.0, 1100.0), layers="B/UI",
      peak_db=-5.0)


def _stage2_release(seed: int) -> np.ndarray:
    n = frames(1.1)
    out = at(n, R.beam(seed, 1.0, 0.8), 0.0, 1.1)
    out += at(n, R.sub_thump(0.5, 66.0, 30.0, seed), 0.0, 0.8)
    sizz = noise_band(frames(0.3), 3500.0, 9000.0, R.rng(seed + 3)) * exp_env(frames(0.3), 0.09)
    out += at(n, sizz * 0.5, 0.02)
    return out


sound("rifle_stage2_release", _stage2_release, layers="T/B/S/Tl", peak_db=-2.0)
sound("rifle_hit", lambda s: C.energy_hit(s, 0.7, 0.12), layers="T/B", variants=3, peak_db=-6.0)
sound("rifle_stage2_hit", lambda s: C.explosion(s, 0.75, False, 0.7), layers="T/B/S/Tl",
      variants=2, peak_db=-3.0)

# --- P2 Thunder Spindle Gatling -------------------------------------------------------------------
def _gatling_spin(seed: int, up: bool) -> np.ndarray:
    length = 0.35 if up else 0.6
    n = frames(length)
    f0, f1 = (200.0, 620.0) if up else (600.0, 180.0)
    x = np.linspace(0.0, 1.0, n)
    freq = f0 * (f1 / f0) ** x
    motor = np.tanh(2.5 * np.sin(2 * np.pi * np.cumsum(freq) / SR))
    belt = noise_band(n, 700.0, 3200.0, R.rng(seed + 1)) * 0.25
    env = np.minimum(x * 6.0, 1.0) * (1.0 if up else 1.0 - x * 0.7)
    return (motor + belt) * env


sound("gatling_spin_up", lambda s: _gatling_spin(s, True), layers="M", peak_db=-8.0)
sound("gatling_spin_down", lambda s: _gatling_spin(s, False), layers="M", peak_db=-9.0)


def _gatling_loop(seed: int) -> np.ndarray:
    """Shots baked at 15 rps with the spin motor under them: one voice, never one per round.

    The per-round transient is a *recorded* automatic-weapon report (OGA Free Firearm Library),
    windowed to 70 ms and band-limited to 1.2-4 kHz so 15 of them a second read as one roaring
    weapon rather than 15 gunshots. Every layer is periodic over the 2.0 s loop, so it loops clean.
    """
    dur = 2.0
    n = frames(dur)
    fade_len = frames(0.05)
    r = R.rng(seed)
    out = np.zeros(n)
    low = np.zeros(n)
    step = 1.0 / GATLING_RPS
    count = int(dur / step)
    # One recorded report reused every round: a real transient, resampled per round for grain.
    base = high_shelf(lowpass(highpass(RD.gunshot(seed, "auto", 0.35), 1000.0), 6500.0),
                      3000.0, 6.0)[: frames(0.07)]
    for i in range(count):
        when = i * step
        shot = base * r.uniform(0.85, 1.15)
        out += at(n, shot, when)
        # Body only every third round (dossier row 22): a 150-400 Hz layer on all 15 rounds a second
        # is one continuous rumble that buries the transients.
        if i % 3 == 0:
            low += at(n, noise_band(frames(0.06), 200.0, 1000.0, r)
                      * exp_env(frames(0.06), 0.016, 0.001), when) * 0.5
    motor = R.hum_loop(dur, 95.0, 1.5, 190.0, harmonics=6) * 0.22
    belt = C._seamless(noise_band(n + fade_len, 900.0, 4200.0, r), 0.05) * 0.12
    return out + motor + belt + highpass(low, 90.0)


sound("gatling_fire_loop", _gatling_loop, layers="T/B/M", loop=True, peak_db=-5.0)


def _gatling_accent(seed: int) -> np.ndarray:
    """Every third round's accent: a recorded report with the synth sub thump under it."""
    n = frames(0.3)
    # The report keeps its own band (measured flat to 18 dB of tilt); only 120 Hz is removed so the
    # synth sub has room. Before this the accent's 1-4 kHz band sat 27 dB under its 20-80 Hz band —
    # a thump with no crack.
    rec = highpass(RD.gunshot(seed, "auto", 0.25), 120.0)
    return at(n, rec, 0.0, 1.0) + at(n, R.sub_thump(0.2, 70.0, 52.0, seed) * 0.12, 0.0)


sound("gatling_fire_accent", _gatling_accent, layers="T/S", peak_db=-7.0)


def _gatling_tail(seed: int) -> np.ndarray:
    """The city tail after release: a *mid-distance* recorded report already carries its own
    outdoor reflection, so it only needs the street slapback on top plus recorded casing debris."""
    n = frames(1.3)
    rec = lowpass(RD.gunshot(seed, "auto_mid", 1.0), 2500.0)
    out = at(n, rec, 0.0, 0.55)
    out += at(n, C.l_tail(seed, 1.2, taps=((0.16, -8.0), (0.33, -12.0))), 0.0, 0.5)
    out += at(n, RD.debris(seed + 1, 0.5, 18.0, "metal") * 0.4, 0.05)
    return out


sound("gatling_tail", _gatling_tail, layers="Tl/D", peak_db=-6.0)
sound("gatling_hit",
      lambda s: mix(C.l_transient(s, 3600.0, 0.006, 0.03),
                    at(frames(0.12), R.ui_hit(3200.0, 5600.0, 0.04) * 0.4, 0.0)),
      layers="T", variants=4, peak_db=-8.0)
sound("gatling_vent", lambda s: C.l_air(s, 0.45, 1800.0, 8000.0, 0.16), layers="M", peak_db=-6.0)
sound("gatling_vent_perfect",
      lambda s: mix(C.l_air(s, 0.4, 1800.0, 8000.0, 0.14),
                    at(frames(0.9), R.metal_ting(2400.0, 0.7, seed=s) * 0.6, 0.12)),
      layers="M/UI", peak_db=-4.0)

def _gatling_jam(seed: int) -> np.ndarray:
    """The barrel seizes: latch slam, spin dying, two caution beeps."""
    n = frames(1.4)
    out = at(n, C.l_transient(seed, 1900.0, 0.02, 0.09), 0.0, 1.1)
    out += at(n, C.l_body(seed + 1, 0.2, 90.0, 500.0, 0.06), 0.002, 0.8)
    out += at(n, _gatling_spin(seed + 2, False), 0.06, 0.9)
    out += at(n, C.radio_beeps(seed + 3, 900.0, 2, 0.18, 0.09), 0.55)
    return out


def _gatling_overheat(seed: int) -> np.ndarray:
    """Heat hits 100: a long steam dump with the caution pair over it."""
    n = frames(1.8)
    out = at(n, C.l_air(seed, 1.2, 1500.0, 9000.0, 0.45), 0.0, 1.0)
    out += at(n, C.l_transient(seed + 1, 2600.0, 0.01, 0.05), 0.0, 0.6)
    out += at(n, C.radio_beeps(seed + 2, 1000.0, 2, 0.5, 0.09), 0.35)
    out += at(n, R.sub_thump(0.4, 84.0, 48.0, seed) * 0.4, 0.0)
    return out


sound("gatling_jam", _gatling_jam, layers="T/B/M/UI", peak_db=-4.0)
sound("gatling_overheat", _gatling_overheat, layers="M/UI/S", peak_db=-4.0)

# --- weapon handling ------------------------------------------------------------------------------
def _switch(seed: int) -> np.ndarray:
    n = frames(0.4)
    return at(n, C.servo_layer(seed, 1.0, 0.2, 0.4), 0.0) \
        + at(n, C.l_transient(seed + 4, 2800.0, 0.01, 0.05), 0.16, 0.8)


sound("weapon_switch", _switch, layers="M/T", variants=2, peak_db=-6.0)


def _reload(seed: int) -> np.ndarray:
    """Magazine out / seat / bolt: three *recorded* latch actions under the servo layer. The
    Free Firearm Library's bolt actions and the moresounds key/lock set are real mechanisms, which
    is exactly what the dossier's shotgun-cock note [A5] asks for."""
    n = frames(1.7)
    out = at(n, C.servo_layer(seed, 1.1, 0.25, 0.3), 0.0, 0.8)
    out += at(n, RD.mechanism(seed + 4, 0.1), 0.55, 0.9)   # mag out
    out += at(n, RD.mechanism(seed + 5, 0.08), 1.15, 0.7)  # mag seat
    out += at(n, RD.mechanism(seed + 6, 0.14), 1.45, 1.0)  # bolt
    out += at(n, C.l_transient(seed + 6, 2200.0, 0.014, 0.07), 1.45, 0.6)
    out += at(n, C.l_body(seed + 7, 0.12, 120.0, 700.0, 0.03), 1.45, 0.5)
    return out


sound("reload", _reload, layers="M/T/B", peak_db=-5.0)

# --- S3 Hailstorm Volley --------------------------------------------------------------------------
def _lock_tick(seed: int, count: int, step: float) -> np.ndarray:
    return C.radio_beeps(seed, 1800.0, count, step, 0.05)


sound("missile_lock_tick", lambda s: R.beep(1800.0, 0.06, 0.6), layers="UI", peak_db=-12.0)
sound("missile_lock_full", lambda s: _lock_tick(s, 3, 0.09), layers="UI", peak_db=-9.0)


def _missile_launch(seed: int) -> np.ndarray:
    """One tube: recorded air swish for the 'fwip' + hatch thump + latch; the salvo is 12 of these
    42 ms apart (salvo_time 0.5 s)."""
    n = frames(0.5)
    fwip = at(n, highpass(RD.swish(seed, 0.12), 700.0), 0.0, 0.8)
    fwip += at(n, R.whoosh(0.09, 1000.0, 3400.0, seed, center=0.03), 0.0, 0.6)
    thump = at(n, C.l_body(seed + 1, 0.12, 100.0, 300.0, 0.03), 0.0, 0.7)
    latch = at(n, RD.mechanism(seed + 2, 0.06), 0.0, 0.35)
    return fwip + thump + latch


sound("missile_launch", _missile_launch, layers="T/B/M", variants=3, peak_db=-6.0)
sound("missile_flight", lambda s: C.thruster_loop(s, 2.0, 1.6), layers="B", loop=True, peak_db=-12.0)
sound("missile_hit", lambda s: C.explosion(s, 1.0, False, 1.0), layers="T/B/S/Tl/D", variants=3,
      peak_db=-2.0)

# --- lock tones -----------------------------------------------------------------------------------
sound("lock_on", lambda s: C.radio_beeps(s, 1400.0, 2, 0.07, 0.05), layers="UI", peak_db=-10.0)
sound("lock_off", lambda s: C.radio_beeps(s, 900.0, 2, 0.07, 0.05), layers="UI", peak_db=-12.0)
