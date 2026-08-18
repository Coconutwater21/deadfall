#!/usr/bin/env python3
"""Generate a unique shoot SFX for every WeaponKind."""

from __future__ import annotations

import hashlib
import math
import os
import random
import struct
import subprocess
import wave

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "audio", "sfx", "weapons")
SR = 44100

# name -> (family, pitch_bias_hz, length_s, notes)
# Families drive the synth recipe; per-weapon hash + bias keeps them distinct.
WEAPONS: dict[str, tuple[str, float, float]] = {
    # Pistols
    "pistol": ("pistol", 0, 0.10),
    "revolver": ("revolver", -40, 0.14),
    "machinePistol": ("pistol", 55, 0.07),
    "dualPistols": ("pistol", 25, 0.09),
    "pepperbox": ("revolver", 30, 0.12),
    # SMG / rapid
    "smg": ("smg", 40, 0.06),
    "pdw": ("smg", 20, 0.065),
    "nailgun": ("nail", 80, 0.05),
    "shredder": ("nail", -10, 0.07),
    # Rifles
    "carbine": ("rifle", 10, 0.10),
    "assaultRifle": ("rifle", 0, 0.09),
    "burstCarbine": ("rifle", 25, 0.08),
    "battleRifle": ("rifle", -35, 0.12),
    "leverAction": ("rifle", -50, 0.13),
    "pulseRifle": ("pulse", 30, 0.09),
    # Shotguns
    "shotgun": ("shotgun", -20, 0.18),
    "combatShotgun": ("shotgun", 0, 0.16),
    "autoShotgun": ("shotgun", 25, 0.13),
    # Snipers / rails
    "sniper": ("sniper", -60, 0.28),
    "marksmanRifle": ("sniper", -20, 0.18),
    "railgun": ("rail", 40, 0.22),
    "gaussRifle": ("rail", 10, 0.20),
    "eternityRail": ("rail", -30, 0.30),
    # Bows / projectiles
    "crossbow": ("bow", -15, 0.16),
    "harpoonGun": ("bow", -45, 0.18),
    "phantomBow": ("bow", 35, 0.15),
    "blowdart": ("dart", 60, 0.10),
    # Spray / flame / ice
    "flamethrower": ("flame", 0, 0.22),
    "dragonBreath": ("flame", -40, 0.28),
    "toxinSprayer": ("spray", 20, 0.20),
    "cryoCannon": ("ice", -30, 0.24),
    "iceRifle": ("ice", 20, 0.12),
    # Launchers / explosives
    "grenadeLauncher": ("launcher", -25, 0.18),
    "rocketPod": ("rocket", 10, 0.20),
    "clusterLauncher": ("launcher", 15, 0.17),
    "rpg": ("rocket", -50, 0.26),
    "novaStorm": ("launcher", 40, 0.16),
    "thunderCannon": ("thunder", -40, 0.28),
    "stormCaller": ("thunder", 20, 0.22),
    # Heavy continuous
    "minigun": ("minigun", 30, 0.05),
    "arcCaster": ("arc", 50, 0.08),
    # Beams / lasers
    "laserLance": ("laser", 40, 0.14),
    "solarBeam": ("laser", -20, 0.20),
    "prismLance": ("laser", 70, 0.13),
    # Exotic / void
    "plasmaCannon": ("plasma", 0, 0.18),
    "voidCannon": ("void", -40, 0.24),
    "singularity": ("void", -70, 0.30),
    "oblivionCaster": ("void", 20, 0.22),
    "starSplitter": ("plasma", -30, 0.26),
    "apocalypseCannon": ("apocalypse", -50, 0.32),
    "worldEnder": ("apocalypse", -80, 0.36),
    "genesisBlaster": ("plasma", 45, 0.20),
}


def clamp(x: float, lo: float = -1.0, hi: float = 1.0) -> float:
    return lo if x < lo else hi if x > hi else x


def write_wav(path: str, samples: list[float]) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = bytearray()
        for s in samples:
            frames += struct.pack("<h", int(clamp(s) * 32767))
        w.writeframes(frames)


def to_mp3(wav_path: str) -> None:
    mp3_path = wav_path[:-4] + ".mp3"
    subprocess.check_call(
        ["ffmpeg", "-y", "-i", wav_path, "-codec:a", "libmp3lame", "-qscale:a", "5", mp3_path],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    os.remove(wav_path)


def seed_for(name: str) -> int:
    return int(hashlib.md5(name.encode()).hexdigest()[:8], 16)


def noise(rng: random.Random) -> float:
    return rng.uniform(-1.0, 1.0)


def soft(x: float, d: float = 1.6) -> float:
    return math.tanh(x * d)


def env(t: float, attack: float, decay: float) -> float:
    if t < 0:
        return 0.0
    if t < attack:
        return t / attack if attack > 0 else 1.0
    return math.exp(-(t - attack) * decay)


def synth(name: str, family: str, pitch_bias: float, length: float) -> list[float]:
    rng = random.Random(seed_for(name))
    n = max(1, int(SR * length))
    # Unique per-weapon micro-variation
    pitch = pitch_bias + rng.uniform(-18, 18)
    grit = 0.85 + rng.uniform(0, 0.35)
    click_amt = 0.3 + rng.uniform(0, 0.4)
    out = [0.0] * n

    for i in range(n):
        t = i / SR
        s = 0.0

        if family == "pistol":
            f = (340 + pitch) * math.exp(-t * 28)
            s = math.sin(2 * math.pi * f * t) * env(t, 0.001, 42)
            s += noise(rng) * env(t, 0.0, 90) * click_amt
            s += math.sin(2 * math.pi * (180 + pitch * 0.3) * t) * env(t, 0.002, 25) * 0.35

        elif family == "revolver":
            f = (220 + pitch) * math.exp(-t * 18)
            s = math.sin(2 * math.pi * f * t) * env(t, 0.002, 22) * 0.9
            s += math.sin(2 * math.pi * (90 + pitch * 0.2) * t) * env(t, 0.0, 14) * 0.55
            s += noise(rng) * env(t, 0.0, 55) * 0.45
            # Cylinder tick
            if 0.02 < t < 0.05:
                s += math.sin(2 * math.pi * 2200 * t) * 0.2

        elif family == "smg":
            f = (480 + pitch) * math.exp(-t * 55)
            s = math.sin(2 * math.pi * f * t) * env(t, 0.0005, 70) * 0.7
            s += noise(rng) * env(t, 0.0, 110) * 0.55
            s += math.sin(2 * math.pi * (900 + pitch) * t) * env(t, 0.0, 100) * 0.15

        elif family == "nail":
            f = (700 + pitch) * math.exp(-t * 60)
            s = math.sin(2 * math.pi * f * t) * env(t, 0.0, 80) * 0.55
            s += noise(rng) * env(t, 0.0, 140) * 0.7
            # Metallic ping
            s += math.sin(2 * math.pi * (2400 + pitch * 2) * t) * env(t, 0.0, 90) * 0.25

        elif family == "rifle":
            f = (280 + pitch) * math.exp(-t * 24)
            s = math.sin(2 * math.pi * f * t) * env(t, 0.001, 30) * 0.85
            s += math.sin(2 * math.pi * (140 + pitch * 0.4) * t) * env(t, 0.0, 18) * 0.45
            s += noise(rng) * env(t, 0.0, 70) * 0.4
            s += math.sin(2 * math.pi * (1600 + pitch) * t) * env(t, 0.0, 85) * 0.12

        elif family == "pulse":
            f = (320 + pitch) * math.exp(-t * 20)
            s = soft(math.sin(2 * math.pi * f * t) + 0.4 * math.sin(2 * math.pi * f * 2 * t), 2.0)
            s *= env(t, 0.002, 28)
            s += noise(rng) * env(t, 0.0, 60) * 0.2
            s += math.sin(2 * math.pi * (650 + pitch) * t) * env(t, 0.01, 20) * 0.25

        elif family == "shotgun":
            f = (140 + pitch) * math.exp(-t * 12)
            s = math.sin(2 * math.pi * f * t) * env(t, 0.001, 14) * 0.85
            s += noise(rng) * env(t, 0.0, 18) * 0.85 * grit
            # Pellet scatter shimmer
            s += noise(rng) * env(t, 0.02, 25) * 0.35
            s += math.sin(2 * math.pi * (70 + pitch * 0.2) * t) * env(t, 0.0, 10) * 0.4

        elif family == "sniper":
            f = (200 + pitch) * math.exp(-t * 10)
            s = math.sin(2 * math.pi * f * t) * env(t, 0.001, 12) * 1.0
            s += math.sin(2 * math.pi * (100 + pitch * 0.3) * t) * env(t, 0.0, 8) * 0.6
            s += noise(rng) * env(t, 0.0, 40) * 0.5
            # Echo crack tail
            s += math.sin(2 * math.pi * (900 + pitch) * t) * env(t, 0.04, 12) * 0.2
            s += noise(rng) * env(t, 0.06, 10) * 0.15

        elif family == "rail":
            # Charge chirp then crack
            charge = math.sin(2 * math.pi * (400 + pitch + 1200 * min(1, t * 25)) * t)
            s = charge * env(t, 0.0, 8) * 0.35 * (1 if t < 0.05 else 0.15)
            f = (260 + pitch) * math.exp(-max(0, t - 0.03) * 16)
            s += math.sin(2 * math.pi * f * t) * env(max(0, t - 0.03), 0.001, 18) * 0.8
            s += noise(rng) * env(max(0, t - 0.03), 0.0, 35) * 0.45
            s += math.sin(2 * math.pi * (1800 + pitch) * t) * env(t, 0.0, 40) * 0.2

        elif family == "bow":
            # String thwip + body
            s = noise(rng) * env(t, 0.0, 80) * 0.35
            s += math.sin(2 * math.pi * (220 + pitch) * t) * env(t, 0.005, 20) * 0.4
            s += math.sin(2 * math.pi * (880 + pitch * 2) * t) * env(t, 0.0, 45) * 0.35
            if t < 0.03:
                s += math.sin(2 * math.pi * (1400 + pitch * 3) * t) * 0.3

        elif family == "dart":
            s = math.sin(2 * math.pi * (900 + pitch) * t) * env(t, 0.0, 55) * 0.45
            s += noise(rng) * env(t, 0.0, 100) * 0.25
            s += math.sin(2 * math.pi * (1600 + pitch) * t) * env(t, 0.0, 70) * 0.2

        elif family == "flame":
            s = noise(rng) * env(t, 0.01, 8) * 0.7
            s += noise(rng) * abs(math.sin(2 * math.pi * (18 + pitch * 0.05) * t)) * env(t, 0.0, 6) * 0.45
            s += math.sin(2 * math.pi * (90 + pitch * 0.2) * t) * env(t, 0.02, 10) * 0.2

        elif family == "spray":
            s = noise(rng) * env(t, 0.005, 10) * 0.65
            s += math.sin(2 * math.pi * (160 + pitch) * t) * env(t, 0.0, 14) * 0.2
            # Wet hiss
            s += noise(rng) * env(t, 0.0, 20) * 0.3 * abs(math.sin(t * 40))

        elif family == "ice":
            s = math.sin(2 * math.pi * (520 + pitch) * t) * env(t, 0.002, 22) * 0.4
            s += math.sin(2 * math.pi * (1040 + pitch * 2) * t) * env(t, 0.0, 30) * 0.3
            s += noise(rng) * env(t, 0.0, 40) * 0.35
            # Crystal shatter bits
            s += math.sin(2 * math.pi * (2100 + pitch * 3) * t) * env(t, 0.02, 35) * 0.2

        elif family == "launcher":
            f = (120 + pitch) * math.exp(-t * 10)
            s = math.sin(2 * math.pi * f * t) * env(t, 0.002, 12) * 0.7
            s += noise(rng) * env(t, 0.0, 25) * 0.4
            # Tube thump
            s += math.sin(2 * math.pi * (55 + pitch * 0.15) * t) * env(t, 0.0, 9) * 0.5

        elif family == "rocket":
            f = (100 + pitch) * math.exp(-t * 8)
            s = math.sin(2 * math.pi * f * t) * env(t, 0.003, 10) * 0.75
            s += noise(rng) * env(t, 0.01, 9) * 0.55  # whoosh
            s += math.sin(2 * math.pi * (48 + pitch * 0.1) * t) * env(t, 0.0, 7) * 0.55

        elif family == "thunder":
            f = (80 + pitch) * math.exp(-t * 7)
            s = math.sin(2 * math.pi * f * t) * env(t, 0.002, 8) * 0.9
            s += noise(rng) * env(t, 0.0, 12) * 0.7
            s += math.sin(2 * math.pi * (40 + pitch * 0.1) * t) * env(t, 0.0, 6) * 0.6
            # Electric snap
            s += math.sin(2 * math.pi * (1800 + pitch * 2) * t) * env(t, 0.0, 50) * 0.25

        elif family == "minigun":
            f = (360 + pitch) * math.exp(-t * 70)
            s = math.sin(2 * math.pi * f * t) * env(t, 0.0, 90) * 0.65
            s += noise(rng) * env(t, 0.0, 130) * 0.5
            s += math.sin(2 * math.pi * (120 + pitch * 0.3) * t) * env(t, 0.0, 50) * 0.25

        elif family == "arc":
            s = noise(rng) * env(t, 0.0, 70) * 0.55
            s += math.sin(2 * math.pi * (600 + pitch + 400 * math.sin(t * 90)) * t) * env(t, 0.0, 35) * 0.45
            s += math.sin(2 * math.pi * (200 + pitch) * t) * env(t, 0.0, 25) * 0.3

        elif family == "laser":
            f = 700 + pitch + 200 * math.sin(t * 30)
            s = math.sin(2 * math.pi * f * t) * env(t, 0.005, 16) * 0.55
            s += math.sin(2 * math.pi * (f * 1.5) * t) * env(t, 0.0, 20) * 0.3
            s += noise(rng) * env(t, 0.0, 50) * 0.15

        elif family == "plasma":
            f = 280 + pitch
            s = soft(math.sin(2 * math.pi * f * t) + 0.5 * math.sin(2 * math.pi * f * 1.33 * t), 2.2)
            s *= env(t, 0.003, 14)
            s += noise(rng) * env(t, 0.0, 30) * 0.3
            s += math.sin(2 * math.pi * (150 + pitch * 0.4) * t) * env(t, 0.0, 12) * 0.35

        elif family == "void":
            f = 90 + pitch * 0.5 + 40 * math.sin(t * 12)
            s = math.sin(2 * math.pi * f * t) * env(t, 0.01, 9) * 0.7
            s += math.sin(2 * math.pi * (f * 1.618) * t) * env(t, 0.0, 11) * 0.4
            s += noise(rng) * env(t, 0.0, 16) * 0.35
            # Reverse-ish swell
            s += math.sin(2 * math.pi * (60 + abs(pitch)) * t) * (t / max(length, 0.01)) * math.exp(-t * 4) * 0.35

        else:  # apocalypse
            f = (70 + pitch) * math.exp(-t * 5)
            s = math.sin(2 * math.pi * f * t) * env(t, 0.004, 6) * 0.95
            s += noise(rng) * env(t, 0.0, 8) * 0.75
            s += math.sin(2 * math.pi * (35 + pitch * 0.1) * t) * env(t, 0.0, 5) * 0.7
            s += math.sin(2 * math.pi * (500 + pitch) * t) * env(t, 0.0, 20) * 0.2
            s += noise(rng) * env(t, 0.08, 8) * 0.3

        out[i] = soft(s * grit, 1.5)

    # Normalize
    peak = max((abs(x) for x in out), default=1.0) or 1.0
    out = [x * 0.9 / peak for x in out]
    return out


def main() -> None:
    print(f"Generating {len(WEAPONS)} weapon shoot sounds...")
    os.makedirs(OUT, exist_ok=True)
    for name, (family, pitch, length) in WEAPONS.items():
        samples = synth(name, family, pitch, length)
        wav = os.path.join(OUT, f"{name}.wav")
        write_wav(wav, samples)
        to_mp3(wav)
        print(f"  {name} ({family})")
    print("done")


if __name__ == "__main__":
    main()
