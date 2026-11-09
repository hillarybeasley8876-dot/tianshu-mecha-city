"""Bank D: skills S1-S8 + overdrive/lance + feedback UI (dossier §3 rows 44-59, 69)."""

from __future__ import annotations

import numpy as np

import bank_common as C
import recorded as RD
import recipes as R
from dsp import at, frames, mix, noise_band
from registry import sound

# --- S4 Skyhook Anchor ----------------------------------------------------------------------------
def _anchor_fire(seed: int) -> np.ndarray:
    n = frames(0.5)
    return at(n, C.l_transient(seed, 1800.0, 0.02, 0.09), 0.0, 1.0) \
        + at(n, R.whoosh(0.25, 1200.0, 2600.0, seed + 1), 0.01, 0.6)


sound("anchor_fire", _anchor_fire, layers="T/B", variants=2, peak_db=-6.0)
sound("anchor_latch",
      lambda s: mix(C.l_transient(s, 2400.0, 0.014, 0.07) * 1.1,
                    at(frames(0.5), C.l_body(s + 1, 0.2, 110.0, 600.0, 0.05), 0.002, 0.7)),
      layers="T/B", variants=2, peak_db=-4.0)
sound("anchor_reel_loop", lambda s: C.thruster_loop(s, 2.0, 0.55, scrape=0.3), layers="M",
      loop=True, peak_db=-10.0)

# --- S5 Corona Fins --------------------------------------------------------------------------------
sound("fins_launch", lambda s: C.chime_cascade(s), layers="UI", variants=2, peak_db=-6.0)
sound("fins_hit", lambda s: C.energy_hit(s, 0.5, 0.1), layers="T/B", variants=3, peak_db=-8.0)

# --- S6 Corona Ward --------------------------------------------------------------------------------
# The ring partials stay synthesised (rule 11); the recorded forcefield hum is the layer under them
# that makes the ward sound like a machine holding a field rather than a glass bowl.
sound("ward_up_loop",
      lambda s: mix(C.ring_loop(2.0, (1.0, 2.1, 3.4), (1.0, 0.4, 0.2), 0.5),
                    RD.forcefield(s, 2.0) * 0.5),
      layers="UI", loop=True, peak_db=-13.0)
sound("ward_hit", lambda s: R.metal_ting(2400.0, 0.5, seed=s), layers="UI", variants=3,
      peak_db=-8.0)


def _ward_break(seed: int) -> np.ndarray:
    n = frames(1.2)
    return at(n, R.metal_ting(1400.0, 0.9, seed=seed), 0.0, 1.0) \
        + at(n, C.l_debris(seed + 1, 0.9, 40.0, 2500.0, 11000.0), 0.01, 1.0) \
        + at(n, C.l_sub(seed + 2, 0.3, 64.0, 34.0, 0.5), 0.0)


sound("ward_break", _ward_break, layers="UI/D/S", peak_db=-4.0)

# --- S7 Shockcore / S8 Undertow Well / Plunge -------------------------------------------------------
def _shockcore(seed: int) -> np.ndarray:
    """Inhale 0.3 s (reversed riser) -> crack-boom."""
    n = frames(1.6)
    inhale = R.charge_riser(0.3, seed, False, 900.0, 200.0)[::-1].copy()
    out = at(n, inhale * 0.8, 0.0)
    out += at(n, C.explosion(seed + 1, 1.05, False, 0.5), 0.3)
    out += at(n, R.metal_ting(900.0, 0.8, seed=seed + 2) * 0.4, 0.3)
    return out


sound("shockcore", _shockcore, layers="T/B/S", peak_db=-2.0)
sound("undertow_loop", lambda s: R.hum_loop(2.0, 44.0, 1.5, 33.0, 6), layers="B", loop=True,
      peak_db=-11.0)


def _collapse(seed: int) -> np.ndarray:
    """Reverse cymbal (noise swell) then boom: the COLLAPSE detonation."""
    n = frames(2.0)
    swell = noise_band(frames(0.7), 1500.0, 9000.0, R.rng(seed)) * np.linspace(0.05, 1.0, frames(0.7))**2
    out = at(n, swell * 0.7, 0.0)
    out += at(n, C.explosion(seed + 1, 1.2, False, 0.8), 0.7)
    out += at(n, R.sub_thump(0.8, 58.0, 22.0, seed) * 0.9, 0.7)
    return out


sound("collapse", _collapse, layers="T/B/S", peak_db=-1.5)


def _plunge(seed: int, dive: bool) -> np.ndarray:
    n = frames(1.6)
    if dive:
        whistle = R.charge_riser(0.6, seed, False, 1600.0, 300.0)
        return at(n, whistle * 0.7, 0.0) + at(n, R.whoosh(0.6, 200.0, 2400.0, seed + 1), 0.05, 0.8)
    out = at(n, C.explosion(seed + 2, 1.25, False, 1.2), 0.0)
    out += at(n, R.sub_thump(0.9, 62.0, 24.0, seed) * 1.0, 0.0)
    return out


sound("plunge_dive", lambda s: _plunge(s, True), layers="B", peak_db=-6.0)
sound("plunge_land", lambda s: _plunge(s, False), layers="T/B/S/D", variants=2, peak_db=-1.5)

# --- Zenith Overdrive / Lance ----------------------------------------------------------------------
def _overdrive_ignite(seed: int) -> np.ndarray:
    """Synth swell 1 s + a 5-beat servo-lock rhythm on the music grid (Aadahl, dossier §1.1)."""
    n = frames(2.0)
    out = at(n, R.charge_riser(1.0, seed, True, 110.0, 880.0), 0.0, 0.9)
    beat = 60.0 / 140.0
    for i in range(5):
        pitch = 1.0 + 0.12 * i
        lock = C.l_transient(seed + i, 2200.0 * pitch, 0.01, 0.05) * (0.6 + 0.1 * i)
        out += at(n, lock, 0.9 + i * beat * 0.5)
    out += at(n, C.thruster_loop(seed + 9, 1.0, 1.3), 0.95, 0.7)
    out += at(n, R.sub_thump(0.8, 55.0, 30.0, seed) * 0.7, 0.95)
    return out


sound("overdrive_ignite", _overdrive_ignite, layers="B/M/S", peak_db=-2.0)
sound("overdrive_loop", lambda s: R.hum_loop(2.0, 220.0, 6.0, 330.0, 12) * 0.5, layers="B",
      loop=True, peak_db=-13.0)


def _lance(seed: int, charge: bool) -> np.ndarray:
    n = frames(1.2)
    if charge:
        return at(n, R.charge_riser(0.8, seed, True, 260.0, 1600.0), 0.0, 1.0)
    out = at(n, C.explosion(seed + 1, 1.3, False, 0.4), 0.0)
    out += at(n, C.thruster_loop(seed + 2, 1.2, 1.8), 0.0, 0.9)
    out += at(n, R.sub_thump(1.0, 60.0, 26.0, seed) * 1.0, 0.0)
    return out


sound("lance_charge", lambda s: _lance(s, True), layers="B", peak_db=-4.0)
sound("lance_fire", lambda s: _lance(s, False), layers="T/B/S", peak_db=-1.0)

# --- feedback / UI ---------------------------------------------------------------------------------
sound("skill_ready", lambda s: R.metal_ting(1320.0, 0.5, seed=s), layers="UI", variants=3,
      peak_db=-10.0)
sound("hitmarker", lambda s: R.ui_hit(2200.0, 4100.0, 0.06), layers="UI", peak_db=-9.0)
sound("hitmarker_weak", lambda s: R.ui_hit(1500.0, 2600.0, 0.05), layers="UI", peak_db=-12.0)
sound("kill_confirm",
      lambda s: mix(R.ui_hit(2400.0, 4600.0, 0.09), R.sub_thump(0.14, 64.0, 46.0, s) * 0.6),
      layers="UI/S", peak_db=-6.0)
sound("kill_small",
      lambda s: mix(C.explosion(s, 0.7, False, 0.9),
                    at(frames(2.0), R.ui_hit(2400.0, 4600.0, 0.08) * 0.5, 0.02)),
      layers="B/D/UI", variants=3, peak_db=-4.0)
sound("kill_large", lambda s: C.explosion(s, 1.35, False, 1.3), layers="T/B/S/Tl/D", variants=2,
      peak_db=-1.5)
sound("kill_large_far", lambda s: R.explosion_far(3.0, s), layers="B/Tl", variants=2, peak_db=-6.0)


# --- the brood titan's death (FEEL `boss_kill`) -----------------------------------------------------
def _boss_kill(seed: int) -> np.ndarray:
    """The climax layer of the boss death. It LAYERS with kill_large, it does not replace it.

    kill_large already reaches this moment three ways (the row's own audio column, brood_titan.gd's
    direct call and the router's on_enemy_killed), so a fourth explosion crack here would only stack.
    What the death still lacks is everything AFTER the impact: the titan's own death cry, a sub that
    falls to 20 Hz under the 0.2x slow-mo, and the 90 m body coming down - a long collapse of metal
    and chitin with the city answering it.
    """
    # 4.2 s, not more: the longest layer (the settling debris at 2.3 s) ends at 3.9 s, and a
    # silent tail would hold a C4 world voice for nothing.
    n = frames(4.2)
    # the cry: the same roar voice the titan fights with, stretched and falling
    cry = C.creature_voice(seed, "roar", -19.0, 2.6, 26.0, 0.0)
    cry = cry * np.linspace(1.0, 0.35, cry.size)
    out = at(n, cry, 0.02, 1.0)
    # sub drop: 48 -> 20 Hz over 2 s, the floor of the whole moment
    out += at(n, R.sub_thump(2.4, 48.0, 20.0, seed + 1) * 1.0, 0.0)
    out += at(n, R.sub_thump(1.1, 30.0, 18.0, seed + 2) * 0.7, 0.55)
    # the body coming down: three impacts walking up the collapse, then the settling debris
    for i, (when, size) in enumerate(((0.30, 2.2), (0.85, 1.9), (1.70, 1.5))):
        out += at(n, C.metal_impact(seed + 10 + i, size, 1.0, 0.3, taps=True), when,
                  1.0 - 0.15 * i)
    out += at(n, C.l_debris(seed + 20, 2.4, 34.0, 300.0, 6500.0), 0.9, 0.9)
    out += at(n, C.l_debris(seed + 21, 1.6, 22.0, 900.0, 8000.0), 2.3, 0.6)
    # the city answers: a long slapback tail off the far explosion
    out += at(n, C.l_tail(seed + 30, 2.4, taps=((0.21, -8.0), (0.47, -12.0), (0.83, -16.0))), 0.35,
              0.8)
    # steam and structure letting go
    out += at(n, C.l_air(seed + 40, 1.6, 1200.0, 8000.0, 0.5), 0.45, 0.7)
    return out


# -3.0 dBTP, not the bank's loudest: this row ALWAYS layers with kill_large (-1.5), so the two
# transients land in the same millisecond and the Master limiter should not be doing the mixing.
sound("boss_kill", _boss_kill, layers="T/B/S/Tl/D", peak_db=-3.0)
sound("jackpot", lambda s: C.chime_cascade(s, notes=(880.0, 1174.7, 1760.0), step=0.09),
      layers="UI", peak_db=-5.0)

# --- stagger ---------------------------------------------------------------------------------------
def _stagger(seed: int, boss: bool) -> np.ndarray:
    """Metal groan 0.8 s (slowed ice/metal crunch); boss adds plates ejecting."""
    n = frames(1.8 if boss else 1.1)
    groan = C.creature_voice(seed, "growl", -3.0, 0.8, 28.0, 0.0)
    out = at(n, groan, 0.0, 0.8)
    out += at(n, C.metal_impact(seed + 1, 1.3 if boss else 1.0, 0.6, 0.4), 0.0, 0.8)
    if boss:
        out += at(n, C.l_debris(seed + 2, 1.4, 26.0, 400.0, 4000.0), 0.1)
        out += at(n, R.sub_thump(0.8, 58.0, 24.0, seed) * 0.9, 0.0)
        for i in range(4):
            out += at(n, C.l_transient(seed + 10 + i, 2000.0, 0.02, 0.08), 0.25 + i * 0.13, 0.7)
    return out


sound("stagger_enemy", lambda s: _stagger(s, False), layers="T/B/M", variants=2, peak_db=-4.0)
sound("boss_stagger", lambda s: _stagger(s, True), layers="T/B/S/D", peak_db=-2.0)

# --- combo rank ------------------------------------------------------------------------------------
def _rank_up(seed: int) -> np.ndarray:
    notes = (587.33, 880.0, 1174.66)
    n = frames(0.07 * len(notes) + 0.5)
    out = np.zeros(n)
    for i, note in enumerate(notes):
        out += at(n, R.metal_ting(note, 0.45, seed=seed + i) * (0.7 + 0.15 * i), i * 0.07)
    return out


sound("combo_rank_up", _rank_up, layers="UI", variants=2, peak_db=-8.0)

# --- menu / objective ------------------------------------------------------------------------------
sound("ui_move", lambda s: R.ui_hit(1600.0, 2400.0, 0.04) * 0.7, layers="UI", peak_db=-14.0)
sound("ui_confirm", lambda s: C.radio_beeps(s, 1400.0, 2, 0.05, 0.05), layers="UI", peak_db=-11.0)
sound("ui_back", lambda s: C.radio_beeps(s, 700.0, 2, 0.05, 0.05), layers="UI", peak_db=-13.0)
sound("ui_pause", lambda s: C.servo_layer(s, 0.8, 0.3, 0.6), layers="M/UI", peak_db=-9.0)
sound("objective_update",
      lambda s: mix(C.radio_beeps(s, 1200.0, 2, 0.09, 0.07),
                    at(frames(0.7), R.metal_ting(1760.0, 0.5, seed=s) * 0.6, 0.2)),
      layers="UI", peak_db=-9.0)
