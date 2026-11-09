"""Synthesis recipes R1-R11 from ref/research/audio-music.md §4, deterministic (fixed seeds).

Each function returns a mono float64 buffer. Callers layer them (dossier §1.2) and call dsp.finalize.
"""

from __future__ import annotations

import numpy as np

from dsp import (SR, am, at, drive, exp_env, frames, gauss_env, highpass, lowpass, mix, noise_band,
                 pink, saw, slapback, sweep_sine, t, white)

SPEED_OF_SOUND = 343.0


def rng(seed: int) -> np.random.Generator:
    return np.random.default_rng(seed)


# --- R1 sub thump ---------------------------------------------------------------------------------
def sub_thump(duration: float = 0.45, f0: float = 70.0, f1: float = 30.0, seed: int = 1) -> np.ndarray:
    """Sine glide with tanh drive (adds the harmonics laptops need) plus a 1.5 ms HP click."""
    n = frames(duration)
    body = sweep_sine(n, f0, f1) * exp_env(n, 0.12)
    click = noise_band(frames(0.0015), 1800.0, 9000.0, rng(seed)) * exp_env(frames(0.0015), 0.004)
    return drive(mix(body, at(n, click * 0.5, 0.0)), 1.6)


# --- R2 beam "tchew" ------------------------------------------------------------------------------
def beam(seed: int = 2, bright: float = 1.0, pitch: float = 1.0) -> np.ndarray:
    """Saw falling 2.4 k -> 280 Hz + HP noise transient + AM'd band sizzle + street slapback."""
    n = frames(0.58)
    r = rng(seed)
    core = saw(frames(0.14), 2400.0 * pitch, 280.0 * pitch) * exp_env(frames(0.14), 0.035, 0.001)
    tick = highpass(white(frames(0.004), r), 3000.0) * exp_env(frames(0.004), 0.0015, 0.0003)
    sizzle = noise_band(frames(0.18), 4000.0 * bright, 7000.0 * bright, r)
    sizzle = am(sizzle * exp_env(frames(0.18), 0.055), 43.0, 0.6) * 0.35
    zap = noise_band(frames(0.12), 200.0, 600.0, r) * exp_env(frames(0.12), 0.03) * 0.5
    body = mix(at(n, core * 0.9, 0.0), at(n, tick, 0.0), at(n, zap, 0.002), at(n, sizzle, 0.012))
    return slapback(body, [(0.09, -14.0), (0.16, -18.0)])


# --- R3 charge riser ------------------------------------------------------------------------------
def charge_riser(duration: float = 1.2, seed: int = 3, clicks: bool = True,
                 f0: float = 220.0, f1: float = 880.0) -> np.ndarray:
    """FM carrier sweep with rising tremolo; stage clicks at 0.6 / 1.19 s."""
    n = frames(duration)
    r = rng(seed)
    x = np.linspace(0.0, 1.0, n)
    carrier = f0 * (f1 / f0) ** x
    index = 2.0 + 3.0 * x
    mod = np.sin(2 * np.pi * (carrier * 0.5) * np.arange(n) / SR) * index
    tone = np.sin(2 * np.pi * np.cumsum(carrier) / SR + mod)
    env = (0.15 + 0.85 * x**1.6) * (1.0 - 0.25 * np.cos(2 * np.pi * (6.0 + 22.0 * x) * np.arange(n) / SR))
    out = tone * env
    air = noise_band(n, 1200.0, 6000.0, r) * (x**2) * 0.3
    out = out + air
    if clicks:
        for at_s in (duration * 0.5, duration - 0.01):
            cl = highpass(white(frames(0.02), r), 2500.0) * exp_env(frames(0.02), 0.005, 0.0005)
            out += at(n, cl * 0.8, at_s)
    return out


# --- R4 servo whine -------------------------------------------------------------------------------
def servo(duration: float = 0.42, f_mid: float = 490.0, rise: float = 1.14, seed: int = 4,
          jitter: float = 0.015) -> np.ndarray:
    """tanh(3*sin) glide 420->560->500 Hz with random-walk jitter, gear ripple and a 1.8 kHz blend."""
    n = frames(duration)
    r = rng(seed)
    x = np.linspace(0.0, 1.0, n)
    arc = 1.0 + (rise - 1.0) * np.sin(np.pi * x)
    base = f_mid * arc
    walk = np.cumsum(r.normal(scale=jitter, size=n) / np.sqrt(n))
    freq = base * (1.0 + walk)
    phase = np.cumsum(freq) / SR
    tone = drive(np.sin(2 * np.pi * phase), 3.0)
    ripple = np.sin(2 * np.pi * 90.0 * np.arange(n) / SR) * 0.18
    grind = noise_band(n, 1500.0, 2400.0, r) * 0.22
    env = exp_env(n, duration * 0.55, 0.02) * (0.6 + 0.4 * np.sin(np.pi * x))
    return (tone + ripple + grind) * env


# --- R5 saber hum loop ----------------------------------------------------------------------------
def hum_loop(duration: float = 2.0, f0: float = 87.0, detune: float = 2.5, buzz: float = 120.0,
             harmonics: int = 8) -> np.ndarray:
    """Two interlocked motor tones (Burtt's lightsaber) with integer cycle counts: seamless loop."""
    n = frames(duration)
    k0 = max(1, int(round(f0 * duration)))
    k1 = max(1, int(round((f0 + detune) * duration)))
    kb = max(1, int(round(buzz * duration)))
    x = np.arange(n) / n
    out = np.zeros(n)
    for h in range(1, harmonics + 1):
        out += (np.sin(2 * np.pi * h * k0 * x) + np.sin(2 * np.pi * h * k1 * x)) / (h**1.4)
    out /= 2.0
    out += 0.25 * np.tanh(3.0 * np.sin(2 * np.pi * kb * x))
    shimmer = np.sin(2 * np.pi * (k0 * 46) * x) * 0.05  # 4 kHz-ish air, also integer-period
    return out + shimmer


# --- R6 alarm -------------------------------------------------------------------------------------
def alarm(tone_a: float = 880.0, tone_b: float = 660.0, tone_s: float = 0.5, repeats: int = 3,
          gain: float = 0.1) -> np.ndarray:
    """Two-tone alert with 2.7 ms glide between pitches; rendered quiet (dossier §4 note)."""
    n = frames(tone_s)
    x = np.linspace(0.0, 1.0, n)
    freq = np.where(x < 0.5, tone_a, tone_b)
    glide = frames(0.0027)
    freq = np.convolve(freq, np.ones(glide) / glide, mode="same")
    env = np.ones(n) * (0.4 + 0.6 * (np.sin(np.pi * x) ** 0.3))
    one = drive(np.sin(2 * np.pi * np.cumsum(freq) / SR), 1.4) * env * gain
    out = np.zeros(frames(tone_s * 2 * repeats + 0.2))
    for i in range(repeats):
        out += at(out.size, one, i * tone_s * 2.0)
    return out


def unblockable_tell(seed: int = 31, duration: float = 0.85) -> np.ndarray:
    """Unblockable-attack tell: a metallic screech rising a twelfth over a low pulse.

    The lead's rule for this cue is that it must cut through a full combat mix, so the top end is a
    driven, high-passed sweep (never ducked: the event sits on the UI bus) and the pulse underneath is
    what carries it when the mix is already busy.
    """
    n = frames(duration)
    x = np.arange(n) / SR
    rise = 2.0 ** (x / duration * 0.583)          # a twelfth, exponential so the ear hears the climb
    phase = 2 * np.pi * np.cumsum(760.0 * rise) / SR
    screech = drive(np.sin(phase) + 0.5 * np.sin(phase * 2.76), 2.2)
    screech = highpass(screech * exp_env(n, duration * 0.45, 0.004, 0.6), 900.0)
    # Struck-metal edge: inharmonic partials riding the same rise, short decay.
    metal = np.sin(phase * 5.40) * exp_env(n, 0.09, 0.001) * 0.35
    # Air: a narrow noise band swept up with the screech so it reads as tearing metal, not a synth tone.
    air = _swept_band(white(n, rng(seed)), 2600.0 * rise, q=3.4) * exp_env(n, duration * 0.3, 0.01)
    pulse = mix(sweep_sine(frames(0.5), 96.0, 41.0) * exp_env(frames(0.5), 0.14, 0.002) * 0.9,
                at(frames(0.5), sweep_sine(frames(0.3), 62.0, 34.0)
                   * exp_env(frames(0.3), 0.1, 0.002), 0.22, 0.7))
    return mix(screech, metal, air * 0.5, at(n, pulse, 0.0))


def beep(freq: float = 1000.0, duration: float = 0.08, gain: float = 0.12,
         shape: str = "sine") -> np.ndarray:
    """Single cockpit beep (caution tier, lock ticks, UI)."""
    n = frames(duration)
    x = np.arange(n) / SR
    wave = np.sin(2 * np.pi * freq * x)
    if shape == "square":
        wave = np.sign(wave) * 0.7
    return wave * exp_env(n, duration * 0.4, 0.003) * gain


# --- R7 whoosh / flyby ---------------------------------------------------------------------------
def whoosh(duration: float = 1.0, f_lo: float = 300.0, f_hi: float = 2500.0, seed: int = 7,
           center: float | None = None, reverse: bool = False) -> np.ndarray:
    """Pink noise through a band-pass swept lo -> hi -> lo under a Gaussian envelope."""
    n = frames(duration)
    r = rng(seed)
    src = pink(n, r)
    x = np.linspace(0.0, 1.0, n)
    centre = 0.5 if center is None else center / duration
    cutoff = f_lo + (f_hi - f_lo) * np.exp(-(((x - centre) / 0.28) ** 2))
    band = _swept_band(src, cutoff)
    env = gauss_env(n, (0.5 if center is None else center / 1.0) * duration, duration * 0.22)
    out = band * env
    return out[::-1].copy() if reverse else out


def _swept_band(x: np.ndarray, centre: np.ndarray, q: float = 2.2) -> np.ndarray:
    """Time-varying band-pass built from a swept low-pass minus a swept low-pass an octave down."""
    hi = lowpass(x, np.clip(centre * 1.6, 60.0, 18000.0))
    lo = lowpass(x, np.clip(centre / q, 40.0, 9000.0))
    return hi - lo


# --- R8 explosions --------------------------------------------------------------------------------
def explosion_near(duration: float = 2.9, size: float = 1.0, seed: int = 8,
                   taps: bool = True) -> np.ndarray:
    """crack + LP-swept body + R1 sub + slapback taps at 180/420/700 ms (dossier §4 R8a)."""
    n = frames(duration)
    r = rng(seed)
    crack = highpass(white(frames(0.01), r), 2500.0) * exp_env(frames(0.01), 0.004, 0.0004)
    body_n = frames(0.9)
    body_x = np.linspace(0.0, 1.0, body_n)
    body = lowpass(white(body_n, r), 6000.0 * (300.0 / 6000.0) ** body_x)
    body *= exp_env(body_n, 0.35)
    sub = sub_thump(0.9, 60.0, 32.0, seed)
    out = np.zeros(n)
    out += at(n, crack * 0.9, 0.0)
    out += at(n, body * 0.8, 0.0)
    out += at(n, sub * 0.7, 0.005)
    if size != 1.0:  # bigger = slower and darker
        out = _resample(out, 1.0 / size)[:n]
    if taps:
        out = slapback(out, [(0.18, -8.0), (0.42, -12.0), (0.70, -16.0)])
    return out[:n] if out.size >= n else np.pad(out, (0, n - out.size))


def explosion_far(duration: float = 3.0, seed: int = 9) -> np.ndarray:
    """Double LP 800 Hz noise, tau 1 s, 3-7 Hz roll AM: the rolling-thunder far variant (R8b)."""
    n = frames(duration)
    r = rng(seed)
    roll = lowpass(lowpass(white(n, r), 800.0), 800.0)
    rate = r.uniform(3.0, 7.0)
    env = exp_env(n, 1.0, 0.05) * (0.6 + 0.4 * np.sin(2 * np.pi * rate * np.arange(n) / SR))
    sub = sweep_sine(n, 55.0, 28.0) * exp_env(n, 0.6) * 0.4
    return roll * env + sub


# --- R9 inharmonic metal partials -----------------------------------------------------------------
def metal_ting(f0: float = 1850.0, duration: float = 1.4, ratios=(1.0, 2.76, 5.40, 8.93),
               amps=(1.0, 0.5, 0.25, 0.12), taus=(0.9, 0.5, 0.3, 0.2), seed: int = 10) -> np.ndarray:
    """Free-bar partials: parry ting, ward ring, fins chimes."""
    n = frames(duration)
    x = np.arange(n) / SR
    out = np.zeros(n)
    for ratio, amp, tau in zip(ratios, amps, taus):
        out += amp * np.sin(2 * np.pi * f0 * ratio * x + rng(seed).uniform(0, 6.28)) * np.exp(-x / tau)
    strike = highpass(white(frames(0.003), rng(seed)), 3000.0) * exp_env(frames(0.003), 0.001, 0.0004)
    return mix(out, at(n, strike * 0.4, 0.0))


# --- R10 UI hit -----------------------------------------------------------------------------------
def ui_hit(f1: float = 2200.0, f2: float = 4100.0, duration: float = 0.06) -> np.ndarray:
    """Hitmarker click: two fast partials, identical every time, never ducked (juice §8)."""
    n = frames(duration)
    x = np.arange(n) / SR
    return (np.sin(2 * np.pi * f1 * x) * np.exp(-x / 0.012)
            + 0.6 * np.sin(2 * np.pi * f2 * x) * np.exp(-x / 0.005))


# --- R11 creature chain ---------------------------------------------------------------------------
def creature(base: np.ndarray, semitones: float = -5.0, ring_hz: float = 45.0, stretch: float = 1.0,
             seed: int = 11) -> np.ndarray:
    """Offline HUSK chain: pitch shift, ring modulation, granular stretch, plate-ish smear (§1.4)."""
    out = pitch_shift(base, semitones)
    if stretch != 1.0:
        out = _granular_stretch(out, stretch, rng(seed))
    x = np.arange(out.size) / SR
    ring = 1.0 - 0.55 * (1.0 - np.cos(2 * np.pi * ring_hz * x))
    out = out * ring
    plate = noise_band(out.size, 900.0, 4200.0, rng(seed + 1)) * exp_env(out.size, 0.12) * 0.12
    return mix(out, plate)


def pitch_shift(x: np.ndarray, semitones: float) -> np.ndarray:
    """Resampling pitch shift with a 60 ms crossfaded tail so formants drift only slightly."""
    factor = 2.0 ** (semitones / 12.0)
    if abs(factor - 1.0) < 1e-3:
        return x
    n_out = int(x.size / factor)
    idx = np.linspace(0.0, x.size - 1.0, n_out)
    return np.interp(idx, np.arange(x.size), x)


def _granular_stretch(x: np.ndarray, factor: float, r: np.random.Generator,
                      grain_s: float = 0.08) -> np.ndarray:
    """Overlap-add grains with jittered read heads: the 'wet flesh' texture of §1.4 step 3."""
    grain = frames(grain_s)
    hop_out = grain // 2
    n_out = int(x.size * factor)
    out = np.zeros(n_out + grain)
    window = np.hanning(grain)
    read = 0.0
    write = 0
    while write < n_out:
        start = int(np.clip(read + r.normal(scale=grain * 0.15), 0, max(x.size - grain, 0)))
        take = min(grain, x.size - start)
        out[write : write + take] += x[start : start + take] * window[:take]
        read += grain / factor
        write += hop_out
    return out[:n_out]


def _resample(x: np.ndarray, factor: float) -> np.ndarray:
    n_out = max(int(x.size * factor), 2)
    return np.interp(np.linspace(0.0, x.size - 1.0, n_out), np.arange(x.size), x)
