"""Recorded CC0 layer builders (dossier rule 1: "sell mass with machinery", rule 11).

Each function returns one layer of the T/B/S/M/Tl/D schema built from a real recording, already
de-noised, band-shaped and enveloped so it drops into a `bank_common` composite. Synthesis still
supplies sub, servo, beam and UI layers — this module supplies the material: metal, mechanism,
gunfire, debris and creature.
"""

from __future__ import annotations

import numpy as np

import sources as S
from dsp import SR, exp_env, fade, frames, high_shelf, highpass, lowpass, noise_band

# Real metal, chosen by ear-independent criteria: the sfx100/v2 "metal", "metal_hit", "slam",
# "door_close" and "key_lock_door" sets are contact-recorded hardware, which is exactly the
# ironworks material the dossier's Armored Core VI note [A3] points at.
CLANK = r"^(metal_|sfx100v2_metal_hit_|impactmetal_|impactplate_)"
SLAM = r"^(slam_|door_close_|sfx100v2_door_0[123])"
MECHANISM = r"^(key_lock_door_|tools_|switch_|spring_|lock_open_)"
STONE = r"^(stones_|sfx100v2_stones_)"
GLASS = r"^(glass_|sfx100v2_glass_)"
WOOD = r"^(wooden_|wood_hit_|sfx100v2_wood_hit_)"
ZAP = r"^(zap|laser|phaser)"


def clank(seed: int, length: float = 0.18, size: float = 1.0, bright: float = 1.0) -> np.ndarray:
    """T/B: a real metal-on-metal hit, pitched down for a 16 m mech and trimmed to its transient."""
    pack = ("oga_sfx100v2", "oga_sfx100", "kenney_scifi")[seed % 3]
    buf = S.align(S.take(pack, CLANK, seed, length=length + 0.4))
    buf = S.shifted(buf, -7.0 * np.log2(max(size, 0.4)))
    buf = lowpass(buf, min(13000.0 * bright, 17000.0))
    buf = high_shelf(buf, 3500.0, 8.0)
    return S.norm(S.grain(S.envelope_out(buf, 0.03), max(length * 0.45, 0.02)))


def slam(seed: int, length: float = 0.35, size: float = 1.0) -> np.ndarray:
    """B: container/concrete slam — the mass under a footstep or a landing."""
    buf = S.align(S.take("oga_sfx100", SLAM, seed, length=length + 0.6))
    buf = S.shifted(buf, -9.0 * np.log2(max(size, 0.4)))
    buf = lowpass(high_shelf(buf, 2200.0, 4.0), 1100.0 / max(size, 0.5))
    return S.norm(S.grain(S.envelope_out(buf, 0.05), max(length * 0.6, 0.05)))


def mechanism(seed: int, length: float = 0.3) -> np.ndarray:
    """M: recorded latch/switch/tool clatter — the mechanical detail synthesis cannot fake."""
    buf = S.align(S.take("oga_moresounds", MECHANISM, seed, length=length + 0.3))
    buf = S.shifted(buf, -5.0)
    return S.norm(S.grain(S.envelope_out(highpass(buf, 220.0), 0.03), max(length * 0.5, 0.03)))


def debris(seed: int, length: float = 0.9, density: float = 26.0,
           kind: str = "mixed") -> np.ndarray:
    """D: scattered real fragments. `kind` picks the material group (mixed/stone/glass/metal)."""
    pattern = {"stone": STONE, "glass": GLASS, "metal": CLANK, "wood": WOOD}.get(kind)
    rng = np.random.default_rng(seed)
    out = np.zeros(frames(length))
    count = max(int(density * length), 4)
    mixed = (("oga_sfx100", CLANK), ("oga_sfx100v2", STONE), ("oga_sfx100v2", GLASS))
    for i in range(count):
        if pattern is None:
            pack, pat = mixed[(seed + i) % 3]
        else:
            pack = "oga_sfx100v2" if (seed + i) % 2 else "oga_sfx100"
            pat = pattern
        try:
            grain = S.align(S.take(pack, pat, seed * 7 + i, length=0.09))
        except FileNotFoundError:
            grain = noise_band(frames(0.05), 900.0, 6000.0, rng) * exp_env(frames(0.05), 0.01, 0.001)
        grain = S.shifted(grain, float(rng.uniform(-6.0, 6.0)))
        g = S.envelope_out(grain, 0.01) * float(rng.uniform(0.25, 1.0)) \
            * exp_env(grain.size, 0.02, 0.001)
        idx = frames(float(rng.random()) ** 1.7 * length)
        if idx + g.size <= out.size:
            out[idx:idx + g.size] += g
        else:
            out[idx:] += g[: out.size - idx]
    return S.norm(out * np.exp(-np.arange(out.size) / (length * 0.55 * SR)))


def gunshot(seed: int, kind: str = "auto", length: float = 0.5) -> np.ndarray:
    """T+body: a real firearm report. `auto` = PPSh/M45 burst for the gatling, `rifle` = a single
    shot, `shell` = 12-gauge for the heaviest single transients, `tail` = a mid-distance report
    whose outdoor reflection is already in the recording."""
    table = {
        "auto": ("oga_firearm", r"^(ppsh|m45)_single_near"),
        "auto_mid": ("oga_firearm", r"^(ppsh|m45)_single_mid"),
        "rifle": ("oga_firearm", r"^(tikka3006|savage300|springfield3006)_single_near"),
        "rifle_mid": ("oga_firearm", r"^(tikka3006|savage300|springfield3006)_single_mid"),
        "shell": ("oga_firearm", r"^(winchester12g|nova12g|mossberg12g)_single_near"),
        "tail": ("oga_firearm", r"_single_mid"),
    }
    pack, pattern = table[kind]
    buf = S.align(S.take(pack, pattern, seed, length=length + 1.2))
    return S.norm(S.envelope_out(buf, 0.06))


def explosion_recording(seed: int, length: float = 1.6, size: float = 1.0) -> np.ndarray:
    """Crack + body for the explosion builder: real blast recording, pitched down by size."""
    pack, pattern = [("oga_sfx100", r"^explosion"),
                     ("kenney_scifi", r"^(lowfrequency_explosion|explosioncrunch)"),
                     ("oga_scifi50", r"^(explosion|retro_explosion)")][seed % 3]
    buf = S.align(S.take(pack, pattern, seed, length=length + 1.0))
    buf = S.shifted(buf, -10.0 * np.log2(max(size, 0.5)))
    return S.norm(fade(S.envelope_out(buf, 0.12), 0.0, 0.12))


def creature_base(seed: int, role: str, length: float) -> np.ndarray:
    """A recorded animal/monster vocal, chosen per HUSK role (dossier §1.4).

    Every role is served by OGA — 80 CC0 Creature SFX; the roles are the ones `creature_voice`
    asks for, so no other creature pack is layered.
    """
    table = {
        "chitter": ("oga_creature", r"^(bug|burble|spit)"),
        "screech": ("oga_creature", r"^(alien|scream|weird)"),
        "roar": ("oga_creature", r"^(roar|monster|troll)"),
        "grunt": ("oga_creature", r"^(grunt|hurt|burp)"),
        "breath": ("oga_creature", r"^(breath|howl|nose)"),
    }
    pack, pattern = table.get(role, table["roar"])
    buf = S.align(S.take(pack, pattern, seed, length=length + 1.5), threshold=0.04)
    if buf.size < frames(length):
        buf = np.pad(buf, (0, frames(length) - buf.size))
    return buf


def ambience_loop(seed: int, pattern: str, length: float, lp: float = 6000.0,
                  hp: float = 40.0) -> np.ndarray:
    """A recorded machine / traffic / weather bed, made seamless."""
    pack = "oga_sfx100v2"
    buf = S.take(pack, pattern, seed, length=length + 2.0)
    buf = lowpass(highpass(buf, hp), lp)
    return S.loopable(buf, length, 0.25)


def zap(seed: int, length: float = 0.4, semitones: float = 0.0) -> np.ndarray:
    """A real energy/laser zap. Rule 11 says beams synthesise well — they do, and the synthesis is
    still the body of the beam; this layer is the *discharge hardware* noise under it, the part a
    sine sweep cannot make."""
    buf = S.align(S.take("kenney_digital", ZAP, seed, length=length + 0.3))
    buf = S.shifted(buf, semitones)
    return S.norm(S.envelope_out(buf, 0.04))


def forcefield(seed: int, length: float = 1.0) -> np.ndarray:
    """A recorded energy-field hum for the ward / catch field loops."""
    buf = S.take("kenney_scifi", r"^forcefield_", seed, length=length + 1.0)
    return S.loopable(buf, length, 0.2)


def bell(seed: int, length: float = 1.6) -> np.ndarray:
    """A real struck bell or gong: the recorded half of the parry payoff."""
    buf = S.align(S.take("oga_sfx100", r"^(bell|gong)_", seed, length=length + 0.6),
                  threshold=0.05)
    buf = buf[: frames(length)] if buf.size >= frames(length) \
        else np.pad(buf, (0, frames(length) - buf.size))
    return S.norm(S.envelope_out(buf, 0.08))


def thunder(seed: int, length: float = 4.0) -> np.ndarray:
    """Distant rolling thunder for the crown storm layer."""
    buf = S.align(S.take("oga_sfx100v2", r"^sfx100v2_thunder_", 0, length=length + 3.0),
                  threshold=0.03)
    return lowpass(S.envelope_out(buf, 0.4), 900.0)


def swish(seed: int, length: float = 0.4) -> np.ndarray:
    """A recorded air swish: the air-movement half of a swing or a missile pass."""
    buf = S.align(S.take("oga_swishes", r"^swish_", seed, length=length + 0.4), threshold=0.05)
    return S.norm(S.envelope_out(buf, 0.05))


