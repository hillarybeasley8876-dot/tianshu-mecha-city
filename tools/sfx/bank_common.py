"""Layered sound builders shared by the bank modules (dossier §1.2 layer anatomy).

Every builder returns a mono buffer assembled from T/B/S/M/Tl/D layers so a single id can be
tuned by editing one call. All randomness is seeded -> the bank is byte-reproducible.
"""

from __future__ import annotations

import numpy as np

import recorded as RD
import recipes as R
from dsp import (SR, am, at, drive, exp_env, fade, frames, high_shelf, highpass, lowpass,
                 mix, noise_band, pink, slapback, sweep_sine, white)

SPEED_OF_SOUND = 343.0


def _r(seed: int) -> np.random.Generator:
    return np.random.default_rng(seed)


# --- individual layers ----------------------------------------------------------------------------
# Rule 11 split: T, B, D and the creature bases are *recorded* (`recorded.py`); S, M, beams, UI and
# whooshes stay synthesised, where numpy does the job better than any CC0 recording would.
def l_transient(seed: int, freq: float = 3200.0, tau: float = 0.012, length: float = 0.05) -> np.ndarray:
    """T: a real metal-on-metal hit, with a synthesised inharmonic ring on top for the mech scale."""
    n = frames(length)
    r = _r(seed)
    size = 3400.0 / max(freq, 200.0)
    real = RD.clank(seed, length * 2.2, size, bright=min(1.4, freq / 3200.0))[:n]
    ring = R.metal_ting(freq * 0.45, length, ratios=(1.0, 2.41, 4.07), amps=(1.0, 0.45, 0.2),
                        taus=(tau * 2, tau, tau * 0.6), seed=seed)
    tick = highpass(white(n, r), freq) * exp_env(n, tau, 0.0008)
    return mix(real[:n] * 0.9, ring * 0.4, tick * 0.55)


def l_body(seed: int, length: float = 0.28, f_lo: float = 80.0, f_hi: float = 900.0,
           tau: float = 0.14) -> np.ndarray:
    """B: the container/concrete slam body — a recorded door/container slam, band-limited."""
    n = frames(length)
    size = max(1.0, 200.0 / max(f_lo, 40.0))
    real = RD.slam(seed, length * 1.6, size)[:n]
    real = lowpass(highpass(real, f_lo * 0.7), min(f_hi * 2.2, 6000.0))
    real = real * exp_env(n, tau, 0.004)
    thump = noise_band(n, f_lo, f_hi, _r(seed)) * exp_env(n, tau, 0.004)
    return mix(real * 1.0, thump * 0.35)


def l_sub(seed: int, length: float = 0.3, f0: float = 60.0, f1: float = 32.0,
          gain: float = 1.0) -> np.ndarray:
    """S: the mass layer, always with tanh harmonics."""
    return R.sub_thump(length, f0, f1, seed) * gain


def l_mech(seed: int, length: float = 0.3, f_mid: float = 490.0, rise: float = 1.14,
           gain: float = 0.7) -> np.ndarray:
    """M: pitched-down servo / hydraulic, the 'this is a machine' layer."""
    return R.servo(length, f_mid, rise, seed) * gain


def l_air(seed: int, length: float = 0.18, lo: float = 2500.0, hi: float = 8000.0,
          tau: float = 0.06) -> np.ndarray:
    """M-tail: pneumatic release hiss."""
    n = frames(length)
    return noise_band(n, lo, hi, _r(seed)) * exp_env(n, tau, 0.006)


def l_debris(seed: int, length: float = 0.8, density: float = 26.0, lo: float = 900.0,
             hi: float = 7000.0) -> np.ndarray:
    """D: scattered real fragments (stone/glass/metal), band-shaped to the composite's material."""
    kind = "stone" if hi < 5000.0 else ("glass" if lo > 1200.0 else "mixed")
    return RD.debris(seed, length, density, kind)


def l_tail(seed: int, length: float = 1.2, taps=((0.18, -9.0), (0.42, -13.0), (0.7, -17.0))) -> np.ndarray:
    """Tl: city slapback built from the source itself."""
    n = frames(length)
    src = R.explosion_far(min(length, 3.0), seed)[:n]
    src = np.pad(src, (0, max(0, n - src.size)))[:n]
    return slapback(src, list(taps))[:n]


# --- composite builders --------------------------------------------------------------------------
def metal_impact(seed: int, size: float = 1.0, debris: float = 0.6, air: float = 0.4,
                 taps: bool = False) -> np.ndarray:
    """Footsteps, melee clangs, landings: T + B + S + M + optional D/Tl, scaled by `size`."""
    dur = 0.22 + 0.35 * size
    n = frames(dur + 0.9)
    t_f = 3400.0 / size
    out = np.zeros(n)
    out += at(n, l_transient(seed, t_f, 0.010 * size, 0.06 * size), 0.0, 0.9)
    out += at(n, l_body(seed + 1, dur, 70.0 / size, 700.0, 0.11 * size), 0.004, 1.0)
    out += at(n, l_sub(seed + 2, 0.24 + 0.2 * size, 62.0, 30.0, 0.55 * size), 0.006)
    out += at(n, l_mech(seed + 3, 0.22 * size, 430.0 / size, 1.1, 0.5), 0.0)
    if debris > 0.0:
        out += at(n, l_debris(seed + 4, 0.7 * size, 22.0 * debris) * debris, 0.05)
    if air > 0.0:
        out += at(n, l_air(seed + 5, 0.2, 2600.0, 7000.0, 0.05) * air, 0.02)
    if taps:
        out = slapback(out, [(0.117, -13.0), (0.233, -17.0)])
    return out


def servo_layer(seed: int, size: float = 1.0, length: float = 0.34, air: float = 0.5) -> np.ndarray:
    """Pure M layer for turn/aim/limb movement, three sizes (s/m/l)."""
    n = frames(length + 0.25)
    out = at(n, l_mech(seed, length, 520.0 / size, 1.16, 1.0), 0.0)
    out += at(n, l_transient(seed + 1, 2600.0, 0.006, 0.03), 0.0, 0.25)
    if air > 0.0:
        out += at(n, l_air(seed + 2, 0.14, 3000.0, 9000.0, 0.04) * air, length * 0.75)
    return out


def thruster_loop(seed: int, duration: float = 2.0, bright: float = 1.0, scrape: float = 0.0) -> np.ndarray:
    """Boost/flight loop: roar + turbine whine + optional ground scrape, seamless (integer periods).

    Noise beds are generated `duration + fade` long and crossfaded by `_seamless`, so the returned
    buffer is exactly `duration` and loops without a click.
    """
    n = frames(duration)
    fade_len = frames(0.05)
    r = _r(seed + 3)
    base = R.hum_loop(duration, 62.0, 3.0, 47.0, harmonics=10) * 0.9
    roar = lowpass(pink(n + fade_len, r), 1800.0 * bright)
    roar = _seamless(am(roar, 7.0, 0.35), 0.05)
    k = int(round(2400.0 * bright * duration))
    x = np.arange(n) / n
    whine = (np.sin(2 * np.pi * k * x) + 0.4 * np.sin(2 * np.pi * k * 2 * x)) * 0.12
    out = base * 0.6 + roar * 0.8 + whine
    if scrape > 0.0:
        grit = _seamless(noise_band(n + fade_len, 1200.0, 6500.0, r), 0.05)
        out = out + am(grit, 11.0, 0.6) * 0.5 * scrape
    return out


def ring_loop(duration: float = 2.0, partials=(880.0, 2.1, 3.4), amps=(1.0, 0.4, 0.2),
              lfo_hz: float = 0.5) -> np.ndarray:
    """Seamless glass-ring loop: partials rounded to integer cycle counts (no loop-point click)."""
    n = frames(duration)
    x = np.arange(n) / n
    out = np.zeros(n)
    for ratio, amp in zip(partials, amps):
        k = max(1, int(round(880.0 * ratio * duration)))
        out += amp * np.sin(2 * np.pi * k * x)
    k_lfo = max(1, int(round(lfo_hz * duration)))
    out *= 0.75 + 0.25 * np.cos(2 * np.pi * k_lfo * x)
    return out / (np.max(np.abs(out)) + 1e-12)


def _seamless(x: np.ndarray, fade_s: float = 0.05) -> np.ndarray:
    """Crossfade the tail into the head and drop it: the returned buffer loops without a click."""
    n = x.size
    f = min(frames(fade_s), n // 4)
    out = x[: n - f].copy()
    out[:f] = x[:f] * np.linspace(0.0, 1.0, f) + x[n - f:] * np.linspace(1.0, 0.0, f)
    return out


def energy_hit(seed: int, size: float = 1.0, tail: float = 0.25) -> np.ndarray:
    """Beam/energy impact: recorded discharge zap + synthesised beam body + sub bump + sizzle tail."""
    n = frames(0.2 + 0.5 * size + tail)
    out = np.zeros(n)
    out += at(n, R.beam(seed, bright=1.0, pitch=1.0 / size)[: frames(0.3)], 0.0, 0.8)
    out += at(n, RD.zap(seed + 7, 0.2, -3.0 * size), 0.0, 0.4)
    out += at(n, l_body(seed + 1, 0.12 * size, 120.0, 900.0, 0.03), 0.002, 0.5)
    out += at(n, l_sub(seed + 2, 0.2 * size, 70.0, 36.0, 0.4 * size), 0.0)
    sizz = noise_band(frames(tail), 4000.0, 9000.0, _r(seed + 4)) * exp_env(frames(tail), tail * 0.4)
    out += at(n, sizz * 0.35, 0.03)
    return out


def explosion(seed: int, size: float = 1.0, far: bool = False, debris: float = 1.0) -> np.ndarray:
    """Runtime explosion builder baked to one file (dossier §1.3): recorded crack + body from a
    real blast, synthesised sub, city slapback, and recorded material debris."""
    if far:
        n = frames(3.0)
        roll = R.explosion_far(3.0, seed) * 0.55
        thunder = RD.thunder(seed, 3.0)
        thunder = thunder[:n] if thunder.size >= n else np.pad(thunder, (0, n - thunder.size))
        return roll + lowpass(thunder, 700.0) * 0.5
    n = frames(2.4 * min(size, 1.4))
    rec = RD.explosion_recording(seed, 2.4, size)
    rec = rec[:n] if rec.size >= n else np.pad(rec, (0, n - rec.size))
    crack = RD.gunshot(seed + 1, "shell" if size > 1.1 else "rifle", 0.6) * 0.5
    core = R.explosion_near(2.4, size, seed) * 0.5
    core = core[:n] if core.size >= n else np.pad(core, (0, n - core.size))
    out = rec * 0.9 + core + at(n, crack, 0.0, 0.45)
    out = slapback(out, [(0.18, -12.0), (0.42, -16.0), (0.7, -20.0)])
    out = out[:n] if out.size >= n else np.pad(out, (0, n - out.size))
    out += at(n, RD.debris(seed + 6, 1.1 * size, 30.0 * debris) * debris, 0.12)
    return out


def creature_voice(seed: int, base_kind: str, semitones: float, length: float,
                   ring_hz: float = 45.0, clicks: float = 0.0) -> np.ndarray:
    """HUSK vocal: a *recorded* animal/monster base through the R11 chain (dossier §1.4).

    Rule 11 and the Collings note [A12] both say the same thing — layer real animal recordings
    chosen for an emotion, pitch them for scale, then blend. `_creature_base` is kept as the
    fallback sub-layer so a vocal still has a synthetic fundamental under the recording.
    """
    n = frames(length)
    role = {"chitter": "chitter", "growl": "grunt", "roar": "roar", "screech": "screech",
            "gurgle": "breath", "wet": "chitter"}[base_kind]
    real = RD.creature_base(seed, role, length * 1.4)
    real = real[:n] if real.size >= n else np.pad(real, (0, n - real.size))
    synth = _creature_base(base_kind, n, seed) * 0.4
    out = R.creature(mix(real, synth), semitones, ring_hz, 1.2, seed)
    # The creature packs are recorded close and dark; without a shelf a Titan roar has no bite
    # (measured 33 dB of band tilt, 4-16 kHz 26 dB under the mid).
    out = high_shelf(out, 2500.0, 7.0)
    out = out[:n] if out.size >= n else np.pad(out, (0, n - out.size))
    if clicks > 0.0:
        wet = RD.debris(seed + 9, length, 40.0 * clicks, "mixed") * clicks * 0.4
        out += at(n, highpass(wet, 1800.0), 0.0)
    return fade(out, 0.01, 0.06)


def _creature_base(kind: str, n: int, seed: int) -> np.ndarray:
    """Synthesised animal base: glottal pulse train + noise, shaped per creature role."""
    r = _r(seed)
    x = np.arange(n) / SR
    spec = {
        "chitter": (150.0, 26.0, 0.55, 2600.0),
        "growl": (72.0, 5.0, 0.35, 700.0),
        "roar": (58.0, 3.0, 0.5, 1200.0),
        "screech": (620.0, 7.0, 0.45, 4200.0),
        "gurgle": (48.0, 9.0, 0.7, 480.0),
        "wet": (95.0, 14.0, 0.75, 1500.0),
    }[kind]
    f0, wobble, noise_mix, formant = spec
    vib = 1.0 + 0.25 * np.sin(2 * np.pi * wobble * x)
    phase = np.cumsum(f0 * vib) / SR
    pulse = drive(np.sin(2 * np.pi * phase) + 0.5 * np.sin(4 * np.pi * phase), 2.2)
    breath = noise_band(n, formant * 0.5, formant * 2.0, r)
    env = np.sin(np.pi * np.clip(x / max(x[-1], 1e-6), 0, 1)) ** 0.6
    return (pulse * (1.0 - noise_mix) + breath * noise_mix) * env


def chime_cascade(seed: int, notes=(587.33, 698.46, 880.0, 1046.5, 1318.5, 1760.0),
                  step: float = 0.06) -> np.ndarray:
    """Fins launch: 6-note D-minor cascade of metal_ting partials."""
    total = frames(step * len(notes) + 0.8)
    out = np.zeros(total)
    for i, note in enumerate(notes):
        out += at(total, R.metal_ting(note, 0.6, seed=seed + i) * (0.9 - 0.07 * i), i * step)
    return out


def radio_beeps(seed: int, freq: float = 1800.0, count: int = 3, step: float = 0.06,
                length: float = 0.05) -> np.ndarray:
    """Lock ticks, caution beeps, UI confirms."""
    total = frames(step * count + 0.1)
    out = np.zeros(total)
    for i in range(count):
        out += at(total, R.beep(freq, length, 0.5), i * step)
    return out
