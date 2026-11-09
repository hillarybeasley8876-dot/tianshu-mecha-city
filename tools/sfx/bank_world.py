"""Bank F: ambience beds per layer, emitters and destruction (dossier §3 row 70, §5.3).

Beds are long OGG loops (dossier §5.8); short one-shots stay WAV.
Layers follow SPEC §2: L0 canal trench -40 m, L1 street 0 m, L2/L3 sky decks +40/+90 m, crown +300 m.
"""

from __future__ import annotations

import numpy as np

import bank_common as C
import recorded as RD
import recipes as R
from dsp import SR, am, at, frames, lowpass, mix, noise_band, pink, white
from registry import sound

BED_SECONDS = 8.0
MACHINE_BED = r"^sfx100v2_loop_machine_"
TRAFFIC_BED = r"^sfx100v2_loop_highway"
ROOM_BED = r"^sfx100v2_loop_ambient_"


def _loopable(x: np.ndarray, fade_s: float = 0.35) -> np.ndarray:
    """Crossfade the tail into the head so a bed loops seamlessly, then trim it."""
    f = min(frames(fade_s), x.size // 3)
    out = x[: x.size - f].copy()
    out[:f] = x[:f] * np.linspace(0.0, 1.0, f) + x[x.size - f:] * np.linspace(1.0, 0.0, f)
    return out


# --- beds ------------------------------------------------------------------------------------------
def _bed(seed: int, rumble: float, wind: float, traffic: float, drips: float,
         machine: float, brightness: float, rec: str | None = None,
         rec_gain: float = 0.0) -> np.ndarray:
    """One ambience bed. `rec` names a *recorded* machine/traffic loop to lay under the synthetic
    wind and rumble — a real room tone is what stops a bed sounding like filtered noise."""
    n = frames(BED_SECONDS)
    r = R.rng(seed)
    out = lowpass(pink(n, r), 220.0) * rumble
    if rec is not None and rec_gain > 0.0:
        out = out + RD.ambience_loop(seed + 40, rec, BED_SECONDS,
                                     lp=min(6000.0 * brightness, 11000.0)) * rec_gain
    if wind > 0.0:
        gust = lowpass(pink(n, r), 2200.0 * brightness) * wind
        gust = am(gust, 0.11, 0.6) * am(gust, 0.043, 0.4)
        out = out + gust
    if traffic > 0.0:
        hum = noise_band(n, 90.0, 700.0, r) * traffic
        out = out + am(hum, 0.07, 0.3)
        for i in range(9):  # individual vehicles passing
            length = r.uniform(1.6, 3.2)
            pass_len = frames(length)
            centre = r.uniform(0.1, 0.9) * length
            sweep = noise_band(pass_len, 150.0, 1800.0 * brightness, r)
            sweep *= np.exp(-(((np.arange(pass_len) / SR - centre) / (length * 0.18)) ** 2))
            out += at(n, sweep * traffic * 0.5, r.uniform(0.0, BED_SECONDS - length))
    if drips > 0.0:
        for i in range(11):
            drop = R.metal_ting(float(r.uniform(900.0, 2600.0)), 0.25,
                                ratios=(1.0, 2.4), amps=(1.0, 0.3), taus=(0.08, 0.05),
                                seed=seed + i) * drips * 0.5
            out += at(n, drop, float(r.random()) * (BED_SECONDS - 0.4))
    if machine > 0.0:
        pump = R.hum_loop(BED_SECONDS, 41.0, 1.5, 27.0, 6) * machine
        out = out + pump
    return _loopable(out)


sound("amb_tunnel_hum",
      lambda s: _bed(s, 0.9, 0.05, 0.0, 1.0, 0.8, 0.4, MACHINE_BED, 0.55),
      layers="B", loop=True, ogg=True, peak_db=-18.0)
sound("amb_street",
      lambda s: _bed(s, 0.6, 0.25, 1.0, 0.0, 0.35, 1.0, TRAFFIC_BED, 0.6),
      layers="B", loop=True, ogg=True, peak_db=-16.0)
sound("amb_wind_high",
      lambda s: _bed(s, 0.25, 1.0, 0.12, 0.0, 0.0, 1.0, ROOM_BED, 0.18),
      layers="B", loop=True, ogg=True, peak_db=-16.0)
def _storm_crown(seed: int) -> np.ndarray:
    """Crown storm: high wind bed with a *recorded* thunder roll inside the loop."""
    base = _bed(seed, 0.55, 1.0, 0.0, 0.0, 0.0, 0.8)
    return _loopable(base + at(base.size, _thunder(seed), 2.4))


sound("amb_storm_crown", _storm_crown, layers="B/T", loop=True, ogg=True, peak_db=-14.0)
sound("distant_battle_bed",
      lambda s: _loopable(mix(R.explosion_far(BED_SECONDS * 0.5, s),
                              at(frames(BED_SECONDS), R.explosion_far(3.0, s + 1), 3.7)) * 0.8),
      layers="B", loop=True, ogg=True, peak_db=-20.0)


def _thunder(seed: int) -> np.ndarray:
    """Recorded rolling thunder, low-passed to 900 Hz — "distant thunder is a rumble, not a
    crack" (dossier §1.3), so the synthesised roll sits under it rather than replacing it."""
    n = frames(3.0)
    r = R.rng(seed)
    real = RD.thunder(seed, 3.0)
    real = real[:n] if real.size >= n else np.pad(real, (0, n - real.size))
    crack = at(n, noise_band(frames(0.4), 800.0, 6000.0, r) * 0.3, 0.0)
    roll = R.explosion_far(3.0, seed + 1)
    return real * 0.7 + crack + roll * 0.5


# --- emitters --------------------------------------------------------------------------------------
def _siren(seed: int) -> np.ndarray:
    """0.5 s 600/450 Hz sweep pair (dossier row 70)."""
    n = frames(1.0)
    x = np.arange(n) / SR
    sweep = 0.5 - 0.5 * np.cos(2 * np.pi * np.minimum(x / 0.5, 1.0))
    freq = 600.0 + (450.0 - 600.0) * sweep
    tone = np.sin(2 * np.pi * np.cumsum(freq) / SR) * np.linspace(1.0, 0.3, n)
    return at(n, tone, 0.0) + at(n, lowpass(white(n, R.rng(seed)), 3000.0) * 0.05, 0.0)


sound("siren_emitter", _siren, layers="B", variants=2, peak_db=-12.0)


def _maglev(seed: int) -> np.ndarray:
    """3 s pass-by: rising whine, doppler-shaped noise bed, rail clatter."""
    n = frames(3.0)
    r = R.rng(seed)
    x = np.arange(n) / SR
    approach = np.exp(-(((x - 1.5) / 0.6) ** 2))
    whine = R.sweep_sine(n, 300.0, 900.0, "exp2") * approach * 0.4
    bed = noise_band(n, 120.0, 3000.0, r) * approach
    clatter = np.zeros(n)
    for i in range(22):
        clatter += at(n, C.l_transient(seed + i, 1600.0, 0.006, 0.03), i * 0.13) * 0.25
    return whine + bed * 0.7 + clatter * approach


sound("maglev_pass", _maglev, layers="B/M", peak_db=-10.0)
sound("neon_buzz", lambda s: _loopable(R.hum_loop(2.0, 120.0, 0.7, 120.0, 12) * 0.6, 0.02),
      layers="B", loop=True, peak_db=-18.0)

# --- destruction ------------------------------------------------------------------------------------
sound("glass_shatter",
      lambda s: mix(C.l_transient(s, 5200.0, 0.006, 0.04),
                    at(frames(1.6), C.l_debris(s + 1, 1.2, 60.0, 3000.0, 12000.0), 0.01)),
      layers="T/D", variants=3, peak_db=-6.0)
sound("debris_concrete", lambda s: C.l_debris(s, 1.6, 22.0, 300.0, 4200.0), layers="D",
      variants=3, peak_db=-10.0)
sound("debris_metal", lambda s: C.l_debris(s, 1.8, 18.0, 800.0, 8000.0), layers="D", variants=3,
      peak_db=-10.0)
