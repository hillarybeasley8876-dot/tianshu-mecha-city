"""Bank E: HUSK creature voices and steps (dossier §3 rows 60-66, §1.4).

Vocal bases are recorded, not synthesised: every archetype layers OGA — 80 CC0 Creature SFX through
`bank_common.creature_voice`, which blends the recording with a synthetic fundamental and pitches
it per role. Sizes follow SPEC §7: Ripper 6 m, Mantis 14 m, Spitter 12 m, Harrier 16 m,
Juggernaut 22 m, Brood Titan 90 m.
"""

from __future__ import annotations

import numpy as np

import bank_common as C
import recipes as R
from dsp import SR, at, frames, mix, noise_band
from registry import sound

# --- Ripper 裂爪 (swarmer) -------------------------------------------------------------------------
sound("ripper_chitter_loop",
      lambda s: C.creature_voice(s, "chitter", -5.0, 2.0, 55.0, clicks=1.0), layers="B",
      loop=True, peak_db=-12.0)
def _ripper_step(seed: int) -> np.ndarray:
    """Light skittering step: small metal tick plus a wet chitin scuff."""
    n = frames(1.4)
    return at(n, C.metal_impact(seed, 0.45, 0.5, 0.0), 0.0) \
        + at(n, C.creature_voice(seed + 1, "wet", -5.0, 0.18, 60.0, 0.4), 0.0, 0.7)


sound("ripper_step", _ripper_step, layers="T/D", variants=4, peak_db=-10.0)
sound("ripper_leap_tell",
      lambda s: C.creature_voice(s, "chitter", -5.0, 0.45, 60.0, clicks=0.5) * np.linspace(0.4, 1.0, frames(0.45)),
      layers="B", variants=2, peak_db=-6.0)
sound("ripper_bite",
      lambda s: mix(C.l_transient(s, 2200.0, 0.01, 0.05),
                    at(frames(0.6), C.creature_voice(s + 1, "wet", -5.0, 0.3, 48.0, 0.8), 0.0, 0.9)),
      layers="T/B", variants=3, peak_db=-7.0)
sound("ripper_death",
      lambda s: C.creature_voice(s, "wet", -7.0, 0.6, 40.0, clicks=1.2), layers="B/D", variants=3,
      peak_db=-8.0)

# --- Mantis 镰影 (duelist) -------------------------------------------------------------------------
def _glint(seed: int) -> np.ndarray:
    """2.5 kHz ping, 120 ms, priority 80: the parryable-hit telegraph (dossier §1.4)."""
    return R.metal_ting(2500.0, 0.12, ratios=(1.0, 2.76), amps=(1.0, 0.3), taus=(0.05, 0.03),
                        seed=seed)


sound("mantis_glint", _glint, layers="UI", variants=2, peak_db=-4.0)
sound("mantis_swing",
      lambda s: mix(R.whoosh(0.28, 600.0, 3200.0, s, center=0.1),
                    at(frames(0.6), noise_band(frames(0.2), 1800.0, 7000.0, R.rng(s + 1)) * 0.4, 0.16)),
      layers="B/T", variants=3, peak_db=-7.0)
sound("mantis_grab_tell",
      lambda s: C.creature_voice(s, "growl", -5.0, 0.6, 38.0, 0.0), layers="B", variants=2,
      peak_db=-6.0)
sound("mantis_death",
      lambda s: mix(C.creature_voice(s, "growl", -8.0, 0.9, 32.0, 0.0),
                    at(frames(2.0), C.metal_impact(s + 1, 1.0, 0.6, 0.2) * 0.6, 0.25)),
      layers="B/T/D", variants=2, peak_db=-7.0)

# --- Spitter 酸巢 (artillery) ----------------------------------------------------------------------
def _spitter_charge(seed: int) -> np.ndarray:
    """1.0 s pressure build before the lob (gameplay-critical telegraph)."""
    n = frames(1.0)
    gurgle = C.creature_voice(seed, "gurgle", -5.0, 1.0, 30.0, 0.0)
    rise = np.linspace(0.35, 1.0, n) ** 1.4
    return gurgle * rise


sound("spitter_charge", _spitter_charge, layers="B", variants=2, peak_db=-6.0)
sound("acid_lob",
      lambda s: mix(R.whoosh(0.35, 250.0, 1400.0, s, center=0.12),
                    at(frames(0.7), R.sub_thump(0.3, 90.0, 50.0, s + 1) * 0.5, 0.0)),
      layers="B", variants=3, peak_db=-7.0)
sound("acid_impact_loop",
      lambda s: _acid_loop(s), layers="B", loop=True, peak_db=-11.0)
sound("spitter_death",
      lambda s: mix(C.creature_voice(s, "gurgle", -9.0, 1.1, 26.0, 0.0),
                    at(frames(2.4), C.l_debris(s + 1, 1.0, 24.0, 600.0, 5000.0) * 0.6, 0.3)),
      layers="B/D", variants=2, peak_db=-7.0)

# --- Harrier 鸣翼 (flyer) --------------------------------------------------------------------------
sound("harrier_screech",
      lambda s: C.creature_voice(s, "screech", -2.0, 0.5, 70.0, 0.0), layers="B", variants=3,
      peak_db=-5.0)
sound("harrier_flyby", lambda s: R.whoosh(0.6, 500.0, 3600.0, s, center=0.2), layers="B",
      variants=3, peak_db=-7.0)
sound("harrier_wings",
      lambda s: _wing_beats(s, 1.0), layers="B", loop=True, peak_db=-10.0)
sound("harrier_death",
      lambda s: mix(C.creature_voice(s, "screech", -5.0, 0.7, 70.0, 0.0)
                    * np.linspace(1.0, 0.3, frames(0.7)),
                    at(frames(1.8), C.creature_voice(s + 1, "wet", -4.0, 0.5, 55.0, clicks=1.0) * 0.7,
                       0.3),
                    at(frames(1.8), C.metal_impact(s + 2, 0.9, 0.6, 0.3) * 0.5, 0.55)),
      layers="B/T/D", variants=2, peak_db=-7.0)

# --- Juggernaut 裂山 (brute) ----------------------------------------------------------------------
sound("jugg_roar",
      lambda s: C.creature_voice(s, "roar", -12.0, 0.7, 34.0, 0.0), layers="B/S", variants=2,
      peak_db=-4.0)
sound("jugg_step", lambda s: C.metal_impact(s, 2.2, 1.0, 0.5, taps=True), layers="T/B/S/Tl",
      variants=3, peak_db=-3.0)
sound("jugg_slam", lambda s: C.explosion(s, 1.4, False, 1.2), layers="T/B/S/D", variants=2,
      peak_db=-2.0)
sound("jugg_plate_break",
      lambda s: mix(C.creature_voice(s, "wet", -6.0, 0.5, 24.0, clicks=1.5),
                    at(frames(1.6), C.metal_impact(s + 1, 1.4, 1.0, 0.4), 0.0, 0.8),
                    at(frames(1.6), C.l_transient(s + 2, 1800.0, 0.02, 0.09), 0.32, 1.0)),
      layers="T/B/D", variants=2, peak_db=-4.0)

# --- Brood Titan 巢母 (boss, 90 m) ------------------------------------------------------------------
sound("titan_step_far",
      lambda s: mix(R.sub_thump(1.2, 34.0, 22.0, s), at(frames(3.0), R.explosion_far(2.5, s + 1) * 0.6, 0.05)),
      layers="S/B", variants=2, peak_db=-6.0)
sound("titan_roar",
      lambda s: C.creature_voice(s, "roar", -19.0, 2.0, 30.0, 0.0), layers="B/S", peak_db=-3.0)
sound("boss_roar",
      lambda s: C.creature_voice(s + 5, "roar", -19.0, 1.6, 30.0, 0.0), layers="B/S", peak_db=-3.0)


def _breath_beam(seed: int) -> np.ndarray:
    """1.5 s charge then a 1.2 s beam breath sweep."""
    n = frames(2.8)
    charge = C.creature_voice(seed, "roar", -14.0, 1.5, 28.0, 0.0) * np.linspace(0.5, 1.0, frames(1.5))
    beam = R.charge_riser(1.2, seed + 1, False, 900.0, 2200.0)
    return at(n, charge, 0.0, 0.9) + at(n, beam, 1.5, 1.0) \
        + at(n, C.thruster_loop(seed + 2, 1.2, 1.9), 1.5, 0.8)


sound("titan_breath_beam", _breath_beam, layers="B/M", peak_db=-3.0)

# --- hive spires ------------------------------------------------------------------------------------
sound("spire_pulse_loop",
      lambda s: _pulse_loop(s), layers="S/B", loop=True, peak_db=-13.0)
sound("spire_destroyed",
      lambda s: mix(C.explosion(s, 1.35, False, 1.3),
                    at(frames(4.0), C.creature_voice(s + 1, "roar", -12.0, 1.4, 26.0, 0.0), 0.15, 0.8)),
      layers="T/B/S/D", peak_db=-1.5)


# The unblockable tell every enemy plays directly (enemy_base.gd): rising metallic screech over a low
# pulse, on the never-ducked UI bus.
sound("telegraph_unblockable", lambda s: R.unblockable_tell(s), layers="T/B/S/UI", peak_db=-6.0)


def _acid_loop(seed: int) -> np.ndarray:
    """2 s bubbling/sizzle loop for acid pools, seamless (tail crossfaded into the head)."""
    n = frames(2.0)
    r = R.rng(seed)
    hiss = noise_band(n, 2500.0, 9000.0, r) * 0.4
    bubbles = np.zeros(n)
    for i in range(26):
        when = float(r.random()) * 1.9
        blen = frames(r.uniform(0.03, 0.09))
        bubble = R.sweep_sine(blen, r.uniform(300.0, 900.0), r.uniform(90.0, 200.0))
        bubbles += at(n, bubble * np.exp(-np.arange(blen) / (0.02 * SR)) * 0.5, when)
    out = hiss + bubbles
    fade_len = frames(0.05)
    head = out[:fade_len].copy()
    out[:fade_len] = head * np.linspace(0.0, 1.0, fade_len) + out[-fade_len:] * np.linspace(1.0, 0.0, fade_len)
    return out[: n - fade_len]


def _wing_beats(seed: int, seconds: float) -> np.ndarray:
    """2 Hz wing thumps with a chitin flutter layer, seamless over `seconds`."""
    n = frames(seconds)
    out = np.zeros(n)
    period = 0.5
    i = 0
    while i * period < seconds:
        beat = mix(noise_band(frames(0.12), 90.0, 900.0, R.rng(seed + i))
                   * np.exp(-np.arange(frames(0.12)) / (0.035 * SR)) * 0.8,
                   noise_band(frames(0.16), 900.0, 4200.0, R.rng(seed + 100 + i)) * 0.35)
        out += at(n, beat, i * period)
        i += 1
    return out


def _pulse_loop(seed: int) -> np.ndarray:
    """0.8 Hz organic pulse for the hive spires (dossier row 66)."""
    period = frames(1.25)
    beat = R.sub_thump(0.9, 46.0, 30.0, seed) * 1.0
    breath = C.creature_voice(seed + 1, "gurgle", -12.0, 1.0, 22.0, 0.0) * 0.35
    return at(period, beat, 0.0) + at(period, breath, 0.15)
