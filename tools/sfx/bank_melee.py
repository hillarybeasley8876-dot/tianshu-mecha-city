"""Bank C: melee, defence, movement specials (dossier §3 rows 32-43)."""

from __future__ import annotations

import numpy as np

import bank_common as C
import recorded as RD
import recipes as R
from dsp import at, exp_env, frames, highpass, mix, noise_band
from registry import sound

# --- beam saber -----------------------------------------------------------------------------------
def _ignite(seed: int) -> np.ndarray:
    """Swell 0.4 s into the hum, then the hum fades in (R5 + short R3)."""
    n = frames(0.8)
    swell = R.charge_riser(0.4, seed, False, 160.0, 440.0) * 0.7
    hum = R.hum_loop(0.4) * np.linspace(0.0, 1.0, frames(0.4))
    return at(n, swell, 0.0) + at(n, hum, 0.38)


sound("saber_ignite", _ignite, layers="B/M", peak_db=-5.0)
sound("saber_hum_loop", lambda s: R.hum_loop(2.0, 87.0, 2.5, 120.0, 10), layers="B", loop=True,
      peak_db=-10.0)
sound("saber_sheathe", lambda s: R.charge_riser(0.35, s, False, 440.0, 120.0) * 0.6, layers="B",
      peak_db=-8.0)


def _swing(seed: int, step: int = 1) -> np.ndarray:
    """Whoosh 200-350 ms; +1 semitone per combo step (dossier row 33). A recorded air swish sits
    under the synthesised one — Burtt's "wave a mic past a speaker" [A6] — and the blade hum rides
    on top so the saber never sounds like plain air."""
    pitch = 2.0 ** ((step - 1) / 12.0)
    n = frames(0.45)
    out = at(n, R.whoosh(0.3, 400.0 * pitch, 3400.0 * pitch, seed, center=0.11), 0.0, 1.0)
    out += at(n, highpass(RD.swish(seed + 5, 0.3), 350.0 * pitch), 0.01, 0.55)
    out += at(n, R.hum_loop(0.3) * 0.5 * np.linspace(0.2, 1.0, frames(0.3)), 0.02)
    return out


sound("saber_swing", lambda s: _swing(s, 1), layers="B", variants=3, peak_db=-5.0)
sound("saber_swing_2", lambda s: _swing(s + 30, 2), layers="B", variants=2, peak_db=-5.0)
sound("saber_swing_3", lambda s: _swing(s + 60, 3), layers="B", variants=2, peak_db=-5.0)

# --- melee impacts --------------------------------------------------------------------------------
def _melee(seed: int, heavy: bool) -> np.ndarray:
    size = 1.6 if heavy else 1.05
    out = C.metal_impact(seed, size, debris=0.7 if heavy else 0.2, air=0.3, taps=heavy)
    n = out.size
    out += at(n, C.l_mech(seed + 11, 0.3, 400.0 / size, 1.25, 0.8), 0.0)
    sizz = noise_band(frames(0.2), 4000.0, 10000.0, R.rng(seed + 12)) * exp_env(frames(0.2), 0.05)
    out += at(n, sizz * 0.6, 0.01)
    if heavy:
        out += at(n, C.l_sub(seed + 13, 0.45, 58.0, 27.0, 0.9), 0.004)
    return out


sound("melee_light", lambda s: _melee(s, False), layers="T/B/M", variants=3, peak_db=-3.0)
sound("melee_heavy", lambda s: _melee(s, True), layers="T/B/S/M", variants=2, peak_db=-2.0)


def _lunge_hit(seed: int) -> np.ndarray:
    n = frames(0.9)
    return at(n, R.whoosh(0.28, 350.0, 2600.0, seed, center=0.09), 0.0, 0.7) \
        + at(n, C.metal_impact(seed + 1, 1.2, 0.4, 0.3), 0.16)


sound("lunge_hit", _lunge_hit, layers="B/T/B", variants=2, peak_db=-2.5)


def _charge_slash(seed: int) -> np.ndarray:
    """Crescent wave: riser -> T + B + S + tail (FEEL charge_slash, 90 m wave)."""
    n = frames(1.6)
    out = at(n, R.charge_riser(0.5, seed, False, 180.0, 700.0) * 0.7, 0.0)
    out += at(n, C.metal_impact(seed + 1, 1.5, 0.6, 0.3), 0.42)
    out += at(n, R.whoosh(0.6, 300.0, 3000.0, seed + 2, center=0.25), 0.42, 0.9)
    out += at(n, C.l_sub(seed + 3, 0.6, 60.0, 26.0, 1.0), 0.44)
    out += at(n, C.l_tail(seed + 4, 0.9), 0.5, 0.7)
    return out


sound("charge_slash", _charge_slash, layers="T/B/S/Tl", variants=2, peak_db=-2.0)


def _finisher(seed: int) -> np.ndarray:
    """Swell 0.5 s -> T + B + S + Tl. 2D, world ducked -9 dB by the mixer (FEEL finisher)."""
    n = frames(2.2)
    out = at(n, R.charge_riser(0.5, seed, True, 140.0, 900.0) * 0.8, 0.0)
    out += at(n, C.explosion(seed + 1, 1.15, False, 1.0), 0.5)
    out += at(n, R.sub_thump(0.9, 62.0, 24.0, seed) * 0.9, 0.5)
    out += at(n, C.l_tail(seed + 2, 1.4), 0.55, 0.8)
    return out


sound("finisher", _finisher, layers="T/B/S/Tl", peak_db=-1.5)

# --- defence --------------------------------------------------------------------------------------
def _parry(seed: int) -> np.ndarray:
    """Payoff sound: a *recorded* struck bell under the synthesised inharmonic partials, plus the
    60 Hz thump. UI bus, never ducked."""
    n = frames(1.6)
    return at(n, R.metal_ting(1850.0, 1.4, seed=seed), 0.0, 1.0) \
        + at(n, RD.bell(seed, 1.6), 0.0, 0.55) \
        + at(n, R.sub_thump(0.3, 62.0, 40.0, seed + 1) * 0.8, 0.0)


sound("parry_perfect", _parry, layers="UI/S", variants=2, peak_db=-3.0)


def _block(seed: int) -> np.ndarray:
    """Muffled clank: recorded plate hit low-passed, no ring (contrast with the parry), plus the
    recorded shield servo seating."""
    n = frames(0.4)
    out = at(n, C.l_transient(seed, 1500.0, 0.02, 0.08), 0.0, 1.0)
    out += at(n, C.l_body(seed + 1, 0.18, 90.0, 400.0, 0.05), 0.002, 0.8)
    out += at(n, C.l_mech(seed + 2, 0.18, 320.0, 0.9, 0.4), 0.0)
    out += at(n, RD.mechanism(seed + 5, 0.08), 0.0, 0.35)
    return out


sound("block", _block, layers="T/B/M", variants=3, peak_db=-5.0)
sound("catch_field_loop",
      lambda s: mix(R.hum_loop(2.0, 130.0, 4.0, 210.0, 6), RD.forcefield(s + 3, 2.0) * 0.45),
      layers="B", loop=True, peak_db=-12.0)


def _catch_release(seed: int) -> np.ndarray:
    n = frames(0.7)
    return at(n, R.whoosh(0.3, 900.0, 200.0, seed), 0.0, 0.9) \
        + at(n, R.sub_thump(0.4, 70.0, 34.0, seed + 1), 0.05, 0.9)


sound("catch_release", _catch_release, layers="B/S", peak_db=-4.0)


def _perfect_dodge(seed: int) -> np.ndarray:
    """Reversed whoosh + a single heartbeat: witch time entry."""
    n = frames(0.9)
    return at(n, R.whoosh(0.35, 2800.0, 300.0, seed, reverse=True), 0.0, 1.0) \
        + at(n, R.sub_thump(0.3, 74.0, 36.0, seed + 1) * 0.7, 0.3)


sound("perfect_dodge", _perfect_dodge, layers="B/S", peak_db=-5.0)

# --- rift step ------------------------------------------------------------------------------------
def _rift(seed: int, out: bool) -> np.ndarray:
    n = frames(0.8)
    rev = R.whoosh(0.3, 3000.0, 400.0, seed, reverse=out)
    thump = R.sub_thump(0.35, 58.0 if out else 40.0, 30.0 if out else 58.0, seed + 1)
    return at(n, rev, 0.0) + at(n, thump * 0.8, 0.12 if out else 0.02)


sound("rift_out", lambda s: _rift(s, True), layers="B/S", peak_db=-6.0)
sound("rift_in", lambda s: _rift(s, False), layers="B/S", peak_db=-5.0)

# --- near miss ------------------------------------------------------------------------------------
sound("near_miss", lambda s: R.whoosh(0.4, 700.0, 4000.0, s, center=0.12), layers="B",
      variants=3, peak_db=-6.0)
