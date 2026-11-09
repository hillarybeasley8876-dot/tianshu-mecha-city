"""Shared DSP helpers for the MECHA CITY sound bank (numpy/scipy only).

Every renderer in tools/sfx builds mono float64 buffers at SR and calls `finalize` to apply the
dossier's loudness target: -1 dBTP *true* peak (audio-music.md §4 "Process rules"), not sample peak.
"""

from __future__ import annotations

import subprocess
from pathlib import Path

import numpy as np
from scipy import signal as sg

SR = 44100  # matches the Godot mix rate (audio-music.md §5.8); no resample cost at import
SPEED_OF_SOUND = 343.0


def t(seconds: float) -> np.ndarray:
    """Time axis for `seconds` at SR."""
    return np.arange(int(round(seconds * SR)), dtype=np.float64) / SR


def frames(seconds: float) -> int:
    return int(round(seconds * SR))


def white(n: int, rng: np.random.Generator) -> np.ndarray:
    return rng.uniform(-1.0, 1.0, n)


def pink(n: int, rng: np.random.Generator) -> np.ndarray:
    """Pink noise via the Voss-McCartney-style 1/f spectral shaping (Farnell, ch. 8)."""
    spec = rng.normal(size=n // 2 + 1) + 1j * rng.normal(size=n // 2 + 1)
    freqs = np.arange(spec.size)
    freqs[0] = 1
    spec /= np.sqrt(freqs)
    out = np.fft.irfft(spec, n)
    return out / (np.max(np.abs(out)) + 1e-12)


# Sizzle and air layers are capped below 15 kHz: full-band bursts at 44.1 kHz swing sample to
# sample at Nyquist, which reads as harshness rather than air (dossier §1.1, Hawken note).
NOISE_BAND_MAX_HZ = 15000.0


def noise_band(n: int, lo: float, hi: float, rng: np.random.Generator, order: int = 4) -> np.ndarray:
    """Band-limited white noise (butter band-pass)."""
    lo = max(lo, 20.0)
    hi = min(hi, NOISE_BAND_MAX_HZ)
    if hi <= lo:
        hi = min(lo * 1.2, SR * 0.48)
    sos = sg.butter(order, [lo / (SR / 2), hi / (SR / 2)], btype="band", output="sos")
    out = sg.sosfilt(sos, white(n, rng))
    return out / (np.max(np.abs(out)) + 1e-12)


def lowpass(x: np.ndarray, cutoff: float | np.ndarray, order: int = 2) -> np.ndarray:
    """Zero-phase low-pass; `cutoff` may be a per-sample array (swept) for short buffers."""
    if np.isscalar(cutoff):
        return sg.sosfilt(sg.butter(order, _nyq(cutoff), btype="low", output="sos"), x)
    return _swept_lp(x, np.asarray(cutoff, dtype=np.float64), order)


def highpass(x: np.ndarray, cutoff: float, order: int = 2) -> np.ndarray:
    return sg.sosfilt(sg.butter(order, _nyq(cutoff), btype="high", output="sos"), x)


def high_shelf(x: np.ndarray, freq: float, gain_db: float, order: int = 2) -> np.ndarray:
    """Boost or cut everything above `freq`.

    The recorded CC0 impacts are dark: their 4-16 kHz band sits 10-20 dB under the mid, which reads
    as muffled rather than heavy. A shelf restores the bite without touching the mass below it.
    """
    if x.size < 16 or abs(gain_db) < 1e-3:
        return x
    return x + highpass(x, freq, order) * (10.0 ** (gain_db / 20.0) - 1.0)



def _nyq(cutoff: float) -> float:
    return float(np.clip(cutoff, 20.0, SR * 0.49)) / (SR / 2)


def _swept_lp(x: np.ndarray, cutoff: np.ndarray, order: int) -> np.ndarray:
    """Chunked time-varying one-pole cascade; stable and cheap, no phase jumps at chunk edges."""
    cutoff = np.clip(cutoff[: x.size], 20.0, SR * 0.45)
    a = np.exp(-2.0 * np.pi * cutoff / SR)
    out = x.copy()
    for _ in range(order):
        prev = 0.0
        acc = np.empty_like(out)
        for i in range(out.size):  # per-sample loop: only used on <= 3 s buffers
            prev = (1.0 - a[i]) * out[i] + a[i] * prev
            acc[i] = prev
        out = acc
    return out


def exp_env(n: int, tau: float, attack: float = 0.002, power: float = 1.0) -> np.ndarray:
    """Percussive envelope: short raised-cosine attack then exponential decay with time constant tau."""
    env = np.exp(-np.arange(n) / max(tau * SR, 1.0)) ** power
    atk = max(frames(attack), 1)
    ramp = 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, min(atk, n)))
    env[: ramp.size] *= ramp
    return env


def gauss_env(n: int, center: float, width: float) -> np.ndarray:
    """Gaussian window centred at `center` seconds; used for whooshes and flybys."""
    x = np.arange(n) / SR
    return np.exp(-(((x - center) / max(width, 1e-4)) ** 2))


def fade(x: np.ndarray, in_s: float = 0.005, out_s: float = 0.02) -> np.ndarray:
    n = x.size
    a, b = min(frames(in_s), n // 2), min(frames(out_s), n // 2)
    if a > 0:
        x[:a] *= np.linspace(0.0, 1.0, a)
    if b > 0:
        x[-b:] *= np.linspace(1.0, 0.0, b)
    return x


def drive(x: np.ndarray, amount: float = 1.6) -> np.ndarray:
    """tanh saturation. Adds the 90-250 Hz harmonics small speakers need (dossier §0 rule 2)."""
    return np.tanh(amount * x) / np.tanh(amount)


def sweep_sine(n: int, f0: float, f1: float, curve: str = "exp") -> np.ndarray:
    """Phase-continuous sine sweep from f0 to f1 Hz."""
    x = np.linspace(0.0, 1.0, n)
    k = x**2 if curve == "exp2" else x
    f = f0 * (f1 / f0) ** k if curve != "lin" else f0 + (f1 - f0) * k
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def saw(n: int, f0: float, f1: float) -> np.ndarray:
    """Band-limited-ish saw (additive, 24 harmonics) with a swept fundamental."""
    x = np.linspace(0.0, 1.0, n)
    f = f0 * (f1 / f0) ** x
    phase = np.cumsum(f) / SR
    out = np.zeros(n)
    for h in range(1, 25):
        out += np.sin(2 * np.pi * h * phase) / h
    return out / (np.max(np.abs(out)) + 1e-12)


def am(x: np.ndarray, rate: float, depth: float, phase: float = 0.0) -> np.ndarray:
    mod = 1.0 - depth * 0.5 * (1.0 - np.cos(2 * np.pi * rate * np.arange(x.size) / SR + phase))
    return x * mod


def mix(*layers: np.ndarray) -> np.ndarray:
    """Sum layers of unequal length, padding to the longest."""
    n = max(layer.size for layer in layers)
    out = np.zeros(n)
    for layer in layers:
        out[: layer.size] += layer
    return out


def at(n: int, layer: np.ndarray, offset: float, gain: float = 1.0) -> np.ndarray:
    """Place `layer` into an n-sample buffer starting at `offset` seconds."""
    out = np.zeros(n)
    start = frames(offset)
    if start >= n:
        return out
    take = min(layer.size, n - start)
    out[start : start + take] += layer[:take] * gain
    return out


def slapback(x: np.ndarray, taps: list[tuple[float, float]], rng=None) -> np.ndarray:
    """Street-canyon reflections: list of (delay_seconds, gain_db)."""
    longest = max(d for d, _ in taps) if taps else 0.0
    out = np.zeros(x.size + frames(longest) + 1)
    out[: x.size] += x
    for delay, gain_db in taps:
        start = frames(delay)
        out[start : start + x.size] += x * (10.0 ** (gain_db / 20.0))
    return out


def true_peak_db(x: np.ndarray, oversample: int = 4) -> float:
    """Inter-sample peak in dBTP (audio-music.md §4: sample peak under-reports by ~1.6 dB)."""
    up = sg.resample_poly(x, oversample, 1)
    peak = float(np.max(np.abs(up))) if up.size else 0.0
    return 20.0 * np.log10(max(peak, 1e-9))


def finalize(x: np.ndarray, peak_db: float = -1.0, fade_out: float = 0.02) -> np.ndarray:
    """Normalise to a true-peak target and declick the tail."""
    x = np.nan_to_num(x, nan=0.0, posinf=0.0, neginf=0.0)
    x = dc_block(x)
    gain = 10.0 ** (peak_db / 20.0) / (10.0 ** (true_peak_db(x) / 20.0))
    return fade(x * gain, 0.001, fade_out)


def dc_block(x: np.ndarray, cutoff: float = 22.0, pad_s: float = 0.25) -> np.ndarray:
    """High-pass with a reflected pre-roll: a causal filter started on a sub-bass step rings."""
    pad = min(frames(pad_s), x.size)
    padded = np.concatenate([x[pad:0:-1], x])
    return highpass(padded, cutoff)[pad:]


def write_wav(path: Path, x: np.ndarray, loop: tuple[float, float] | None = None) -> Path:
    """16-bit mono WAV. `loop` = (begin_s, end_s) writes a forward loop chunk for Godot."""
    import soundfile as sf

    path.parent.mkdir(parents=True, exist_ok=True)
    data = np.clip(x, -1.0, 1.0).astype(np.float32)
    sf.write(str(path), data, SR, subtype="PCM_16")
    if loop is not None:
        _write_loop_chunk(path, loop)
    return path


def _write_loop_chunk(path: Path, loop: tuple[float, float]) -> None:
    """Append a 'smpl' chunk so Godot imports the loop points instead of guessing."""
    begin, end = frames(loop[0]), frames(loop[1])
    chunk = bytearray()
    chunk += b"smpl" + (36 + 24).to_bytes(4, "little")
    for value in (0, 0, int(1e9 / SR), 60, 0, 0, 0, 1):  # header: pitch 60, 1 loop
        chunk += int(value).to_bytes(4, "little", signed=True)
    chunk += int(begin).to_bytes(4, "little", signed=True)
    chunk += int(end).to_bytes(4, "little", signed=True)
    with open(path, "r+b") as handle:
        handle.seek(0, 2)
        size = handle.tell()
        handle.write(chunk)
        handle.seek(4)
        handle.write((size - 8 + len(chunk)).to_bytes(4, "little"))


def write_ogg(path: Path, x: np.ndarray, quality: float = 0.5) -> Path:
    """Stereo OGG Vorbis for music and long ambiences (dossier §5.8), via libsndfile.

    Written in 10 s blocks: a single `sf.write` of more than ~30 s of float32 stereo segfaults
    inside libsndfile's Vorbis encoder on this machine (verified by bisecting the buffer length).
    """
    import soundfile as sf

    path.parent.mkdir(parents=True, exist_ok=True)
    stereo = x if x.ndim == 2 else np.stack([x, x], axis=1)
    data = np.clip(stereo, -1.0, 1.0).astype(np.float32)
    block = 10 * SR
    with sf.SoundFile(str(path), "w", samplerate=SR, channels=data.shape[1],
                      format="OGG", subtype="VORBIS") as handle:
        for start in range(0, data.shape[0], block):
            handle.write(data[start:start + block])
    return path


def lufs_i(path: Path) -> float:
    """Integrated loudness via ffmpeg ebur128 (used by tools/sfx/measure.py)."""
    out = subprocess.run(
        ["ffmpeg", "-hide_banner", "-nostats", "-i", str(path),
         "-af", "ebur128=peak=true", "-f", "null", "-"],
        capture_output=True, text=True, check=True,
    ).stderr
    for line in out.splitlines():
        if "I:" in line and "LUFS" in line and "LRA" not in line:
            return float(line.split("I:")[1].split("LUFS")[0].strip())
    return float("nan")
