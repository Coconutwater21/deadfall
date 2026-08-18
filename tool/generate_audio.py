#!/usr/bin/env python3
"""Regenerate Deadfall procedural music + SFX (MP3 via ffmpeg).

Music aims for dark industrial survival energy:
  menu   — tense cinematic drones
  combat — driving mid-tempo pulse with grit
  boss   — faster, dissonant, drop-heavy assault
"""

from __future__ import annotations

import math
import os
import random
import struct
import subprocess
import wave

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_M = os.path.join(ROOT, "assets", "audio", "music")
OUT_S = os.path.join(ROOT, "assets", "audio", "sfx")
SR = 44100
rng = random.Random(77)

# ---------------------------------------------------------------------------
# DSP helpers
# ---------------------------------------------------------------------------


def clamp(x: float, lo: float = -1.0, hi: float = 1.0) -> float:
    return lo if x < lo else hi if x > hi else x


def write_wav(path: str, samples: list[float], sr: int = SR) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        frames = bytearray()
        for s in samples:
            frames += struct.pack("<h", int(clamp(s) * 32767))
        w.writeframes(frames)


def to_mp3(wav_path: str, quality: int = 3) -> None:
    mp3_path = wav_path[:-4] + ".mp3"
    subprocess.check_call(
        [
            "ffmpeg",
            "-y",
            "-i",
            wav_path,
            "-codec:a",
            "libmp3lame",
            "-qscale:a",
            str(quality),
            mp3_path,
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    os.remove(wav_path)
    print(f"wrote {mp3_path}")


def noise() -> float:
    return rng.uniform(-1.0, 1.0)


def soft_clip(x: float, drive: float = 1.6) -> float:
    return math.tanh(x * drive)


def lowpass(samples: list[float], alpha: float = 0.2) -> list[float]:
    out: list[float] = []
    y = 0.0
    for x in samples:
        y += alpha * (x - y)
        out.append(y)
    return out


def highpass(samples: list[float], alpha: float = 0.96) -> list[float]:
    out: list[float] = []
    prev_x = 0.0
    prev_y = 0.0
    for x in samples:
        y = alpha * (prev_y + x - prev_x)
        out.append(y)
        prev_x, prev_y = x, y
    return out


def normalize(samples: list[float], peak: float = 0.92) -> list[float]:
    m = max((abs(x) for x in samples), default=1.0) or 1.0
    scale = peak / m
    return [x * scale for x in samples]


def fade_edges(samples: list[float], seconds: float = 0.05) -> list[float]:
    fade = max(1, int(SR * seconds))
    n = len(samples)
    out = list(samples)
    for i in range(fade):
        g = i / fade
        out[i] *= g
        out[n - 1 - i] *= g
    return out


def env_adsr(i: int, n: int, a: float = 0.01, d: float = 0.1, s: float = 0.7, r: float = 0.15) -> float:
    t = i / max(1, n)
    if t < a:
        return t / a if a > 0 else 1.0
    if t < a + d:
        return 1.0 - (1.0 - s) * ((t - a) / d if d > 0 else 0.0)
    if t < 1.0 - r:
        return s
    return s * (1.0 - (t - (1.0 - r)) / r) if r > 0 else 0.0


def midi(n: float) -> float:
    return 440.0 * (2.0 ** ((n - 69.0) / 12.0))


def phasor(freq: float, t: float) -> float:
    return (freq * t) % 1.0


def osc_sine(freq: float, t: float) -> float:
    return math.sin(2.0 * math.pi * freq * t)


def osc_tri(freq: float, t: float) -> float:
    p = phasor(freq, t)
    return 4.0 * abs(p - 0.5) - 1.0


def osc_saw(freq: float, t: float) -> float:
    return 2.0 * phasor(freq, t) - 1.0


def osc_square(freq: float, t: float, duty: float = 0.5) -> float:
    return 1.0 if phasor(freq, t) < duty else -1.0


def osc_supersaw(freq: float, t: float, voices: int = 5, detune: float = 0.012) -> float:
    s = 0.0
    half = (voices - 1) / 2.0
    for i in range(voices):
        ratio = 1.0 + (i - half) * detune
        s += osc_saw(freq * ratio, t)
    return s / voices


def osc_growl(freq: float, t: float) -> float:
    """Gritty bass: FM + folded saw."""
    mod = osc_sine(freq * 0.5, t) * 2.2
    carrier = osc_sine(freq + mod * freq * 0.35, t)
    saw = osc_saw(freq * 0.5, t)
    return soft_clip(carrier * 0.65 + saw * 0.55, 2.2)


# ---------------------------------------------------------------------------
# Percussion
# ---------------------------------------------------------------------------


def hit_kick(t: float) -> float:
    if t < 0 or t > 0.22:
        return 0.0
    env = math.exp(-t * 28)
    pitch = 78.0 * math.exp(-t * 22) + 38.0
    body = osc_sine(pitch, t) * env
    click = noise() * math.exp(-t * 120) * 0.35
    return soft_clip(body * 1.35 + click, 1.8)


def hit_snare(t: float) -> float:
    if t < 0 or t > 0.18:
        return 0.0
    tone = osc_sine(190.0, t) * math.exp(-t * 35) * 0.45
    snap = noise() * math.exp(-t * 28) * 0.85
    return soft_clip(tone + snap, 1.5)


def hit_hat(t: float, open_: bool = False) -> float:
    if t < 0 or t > (0.18 if open_ else 0.05):
        return 0.0
    decay = 18 if open_ else 70
    return noise() * math.exp(-t * decay) * (0.28 if open_ else 0.18)


def hit_clap(t: float) -> float:
    if t < 0 or t > 0.2:
        return 0.0
    s = 0.0
    for delay in (0.0, 0.012, 0.024):
        tt = t - delay
        if tt >= 0:
            s += noise() * math.exp(-tt * 40)
    return s * 0.35


def hit_tom(t: float, freq: float = 120.0) -> float:
    if t < 0 or t > 0.25:
        return 0.0
    return osc_sine(freq * math.exp(-t * 4), t) * math.exp(-t * 10) * 0.7


# ---------------------------------------------------------------------------
# Music builders
# ---------------------------------------------------------------------------


def render_drums(
    n: int,
    bpm: float,
    *,
    intensity: float = 1.0,
    double_hats: bool = False,
    industrial: bool = False,
) -> list[float]:
    beat = 60.0 / bpm
    out = [0.0] * n
    steps = int(round(n / (beat * 0.25 * SR)))  # 16th notes
    for step in range(steps + 1):
        start = int(step * beat * 0.25 * SR)
        if start >= n:
            break
        beat_in_bar = step % 16
        # Kick: 1 and 3, plus occasional offbeats when intense
        if beat_in_bar in (0, 8) or (industrial and beat_in_bar in (4, 12, 14)):
            for j in range(int(0.25 * SR)):
                if start + j >= n:
                    break
                out[start + j] += hit_kick(j / SR) * 1.15 * intensity
        if industrial and beat_in_bar == 6:
            for j in range(int(0.22 * SR)):
                if start + j >= n:
                    break
                out[start + j] += hit_kick(j / SR) * 0.55 * intensity

        # Snare / clap on 2 and 4
        if beat_in_bar in (4, 12):
            for j in range(int(0.2 * SR)):
                if start + j >= n:
                    break
                out[start + j] += hit_snare(j / SR) * 0.95 * intensity
                if industrial:
                    out[start + j] += hit_clap(j / SR) * 0.55 * intensity

        # Hats
        if double_hats or beat_in_bar % 2 == 0:
            open_ = industrial and beat_in_bar in (6, 14)
            for j in range(int(0.2 * SR)):
                if start + j >= n:
                    break
                out[start + j] += hit_hat(j / SR, open_) * intensity

        # Fills near loop end
        if step >= steps - 8 and beat_in_bar % 2 == 0:
            for j in range(int(0.2 * SR)):
                if start + j >= n:
                    break
                out[start + j] += hit_tom(j / SR, 140 - (beat_in_bar * 6)) * 0.45 * intensity

    return out


def sidechain_duck(carrier: list[float], kick_env: list[float], amount: float = 0.55) -> list[float]:
    """Approximate sidechain: duck pads when kick hits."""
    n = min(len(carrier), len(kick_env))
    # Smooth kick envelope
    env = [0.0] * n
    y = 0.0
    for i in range(n):
        target = abs(kick_env[i])
        y = y * 0.92 + target * 0.08
        env[i] = y
    peak = max(env) or 1.0
    out = [0.0] * n
    for i in range(n):
        duck = 1.0 - amount * (env[i] / peak)
        out[i] = carrier[i] * max(0.25, duck)
    return out


def violin_sample(freq: float, t: float, vibrato: float = 5.2) -> float:
    """Clean bowed violin tone — harmonic stack + gentle vibrato."""
    vib = 1.0 + 0.0035 * math.sin(2.0 * math.pi * vibrato * t)
    f = freq * vib
    # Mostly sine harmonics (musical), tiny saw for bow body
    s = (
        osc_sine(f, t) * 0.62
        + osc_sine(f * 2.0, t) * 0.26
        + osc_sine(f * 3.0, t) * 0.12
        + osc_sine(f * 4.0, t) * 0.06
        + osc_sine(f * 5.0, t) * 0.03
        + osc_tri(f, t) * 0.08
    )
    return s


def guitar_sample(freq: float, t: float) -> float:
    """Tighter electric guitar — less fizzy distortion."""
    s = osc_saw(freq, t) * 0.5 + osc_saw(freq * 1.5, t) * 0.22 + osc_sine(freq, t) * 0.25
    return soft_clip(s, 2.2)


def render_violin_melody(
    n: int,
    bpm: float,
    notes: list[tuple[float | None, float]],
    *,
    gain: float = 0.42,
    step_beats: float = 0.25,
) -> list[float]:
    """Main violin line. notes = [(midi_or_None, length_in_steps), ...]."""
    beat = 60.0 / bpm
    step = beat * step_beats
    out = [0.0] * n
    cursor = 0.0
    for note, steps in notes:
        dur = steps * step
        start = int(cursor * SR) % n
        length = int(dur * 0.92 * SR)
        cursor += dur
        if note is None or length <= 0:
            continue
        freq = midi(note)
        for j in range(length):
            idx = (start + j) % n
            t = j / SR
            e = env_adsr(j, length, 0.035, 0.12, 0.82, 0.18)
            # Soft bow onset, not noise scratch
            bow = osc_sine(freq * 2, t) * math.exp(-t * 40) * 0.08
            out[idx] += (violin_sample(freq, t) * e + bow) * gain
    return out


def render_violin_harmony(
    n: int,
    bpm: float,
    notes: list[tuple[float | None, float]],
    *,
    gain: float = 0.18,
    step_beats: float = 0.25,
    interval: float = 7.0,
) -> list[float]:
    """Second violin a fifth/third above the melody."""
    shifted = []
    for note, steps in notes:
        if note is None:
            shifted.append((None, steps))
        else:
            shifted.append((note + interval, steps))
    return render_violin_melody(n, bpm, shifted, gain=gain, step_beats=step_beats)


def render_violin_pads(
    n: int,
    bpm: float,
    chords: list[list[float]],
    *,
    beats_per_chord: float = 4.0,
    gain: float = 0.12,
) -> list[float]:
    beat = 60.0 / bpm
    chord_len = int(beats_per_chord * beat * SR)
    out = [0.0] * n
    for ci, chord in enumerate(chords):
        start = (ci * chord_len) % n
        for j in range(chord_len):
            idx = (start + j) % n
            t = j / SR
            e = env_adsr(j, chord_len, 0.25, 0.2, 0.88, 0.2)
            s = 0.0
            for note in chord:
                s += violin_sample(midi(note), t, vibrato=4.2 + (note % 3) * 0.2)
            out[idx] += s * e * gain / max(1.0, len(chord) * 0.6)
    return out


def render_guitar_rhythm(
    n: int,
    bpm: float,
    roots: list[float | None],
    *,
    step_beats: float = 0.5,
    gain: float = 0.16,
) -> list[float]:
    """Quiet supportive power chords under violin (boss tracks only)."""
    beat = 60.0 / bpm
    step_len = beat * step_beats
    out = [0.0] * n
    for si, note in enumerate(roots):
        if note is None:
            continue
        start = int(si * step_len * SR) % n
        length = int(step_len * 0.7 * SR)
        root = midi(note)
        for j in range(length):
            idx = (start + j) % n
            t = j / SR
            e = env_adsr(j, length, 0.008, 0.08, 0.45, 0.2)
            sample = (
                guitar_sample(root, t) * 0.5
                + guitar_sample(root * 1.498, t) * 0.32
                + osc_sine(root * 0.5, t) * 0.35
            )
            out[idx] += soft_clip(sample, 1.8) * e * gain
    return out


def render_bass(
    n: int,
    bpm: float,
    pattern: list[float | None],
    *,
    growl: bool = False,
    gain: float = 0.4,
) -> list[float]:
    beat = 60.0 / bpm
    step_len = beat * 0.5
    out = [0.0] * n
    for si, note in enumerate(pattern):
        if note is None:
            continue
        start = int(si * step_len * SR) % n
        length = int(step_len * 0.9 * SR)
        freq = midi(note)
        for j in range(length):
            idx = (start + j) % n
            t = j / SR
            e = env_adsr(j, length, 0.01, 0.08, 0.75, 0.12)
            # Cleaner bass — prefer sine/tri over growl unless asked
            if growl:
                sample = osc_sine(freq, t) * 0.7 + osc_saw(freq, t) * 0.2
                sample = soft_clip(sample, 1.4)
            else:
                sample = osc_sine(freq, t) * 0.85 + osc_tri(freq, t) * 0.2
            sample += osc_sine(freq * 0.5, t) * 0.4
            out[idx] += sample * e * gain
    return out


def mix_tracks(*tracks: list[float], gains: list[float] | None = None) -> list[float]:
    n = max(len(t) for t in tracks)
    gains = gains or [1.0] * len(tracks)
    out = [0.0] * n
    for track, g in zip(tracks, gains):
        for i, s in enumerate(track):
            out[i] += s * g
    return out


def add_in_place(dst: list[float], src: list[float], gain: float = 1.0) -> None:
    for i, s in enumerate(src):
        if i >= len(dst):
            break
        dst[i] += s * gain


def sidechain_duck(carrier: list[float], kick_env: list[float], amount: float = 0.35) -> list[float]:
    n = min(len(carrier), len(kick_env))
    env = [0.0] * n
    y = 0.0
    for i in range(n):
        y = y * 0.94 + abs(kick_env[i]) * 0.06
        env[i] = y
    peak = max(env) or 1.0
    out = [0.0] * n
    for i in range(n):
        duck = 1.0 - amount * (env[i] / peak)
        out[i] = carrier[i] * max(0.4, duck)
    return out


def _repeat_melody(phrase: list[tuple[float | None, float]], times: int) -> list[tuple[float | None, float]]:
    out: list[tuple[float | None, float]] = []
    for _ in range(times):
        out.extend(phrase)
    return out


def _bass_pattern(roots: list[float], bars: int) -> list[float | None]:
    pat: list[float | None] = []
    for bar in range(bars):
        root = roots[bar % len(roots)]
        # root _ root _  per bar of 8ths if 4 roots... simpler: 8 eighths
        pat += [root, None, root, None, root, None, roots[(bar + 1) % len(roots)], None]
    return pat


# ---------------------------------------------------------------------------
# Compositions — violin is the lead voice; drums/bass/guitar support quietly
# ---------------------------------------------------------------------------


def menu_music() -> list[float]:
    """Quiet drums + lyrical violin theme."""
    duration = 32.0
    bpm = 78.0
    n = int(SR * duration)
    beat = 60.0 / bpm
    bars = int(duration / (beat * 4))

    drums = render_drums(n, bpm, intensity=0.4, double_hats=False, industrial=False)
    for i in range(n):
        drums[i] *= 0.55

    # Melody in 8th-note steps (step_beats=0.5): long singing phrases
    theme = [
        (69, 2), (72, 2), (76, 3), (74, 1),
        (72, 2), (69, 2), (67, 2), (69, 2),
        (71, 2), (72, 2), (74, 3), (72, 1),
        (69, 4), (67, 2), (64, 2),
    ]
    melody = render_violin_melody(n, bpm, _repeat_melody(theme, max(1, bars // 2)), gain=0.48, step_beats=0.5)
    harmony = render_violin_harmony(
        n, bpm, _repeat_melody(theme, max(1, bars // 2)), gain=0.16, step_beats=0.5, interval=4,
    )

    chords = [[57, 60, 64], [53, 57, 60], [52, 55, 59], [55, 59, 62]] * ((bars + 3) // 4)
    pads = render_violin_pads(n, bpm, chords, beats_per_chord=4.0, gain=0.1)
    bass = render_bass(n, bpm, _bass_pattern([45, 41, 40, 43], bars), gain=0.28)

    mixed = mix_tracks(drums, bass, pads, harmony, melody)
    mixed = sidechain_duck(mixed, drums, amount=0.15)
    mixed = lowpass(mixed, 0.45)
    return fade_edges(normalize(mixed, 0.55), 0.08)


def combat_music() -> list[float]:
    """Drums + prominent violin lead (no guitar, no weird FX)."""
    duration = 32.0
    bpm = 124.0
    n = int(SR * duration)
    bars = 16

    drums = render_drums(n, bpm, intensity=0.85, double_hats=True, industrial=False)
    bass = render_bass(n, bpm, _bass_pattern([45, 45, 41, 40], bars), growl=False, gain=0.38)

    chords = [[57, 60, 64], [57, 60, 64], [53, 57, 60], [52, 55, 59]] * 8
    pads = render_violin_pads(n, bpm, chords, beats_per_chord=2.0, gain=0.1)

    # A section — urgent rising motif
    theme_a = [
        (69, 1), (69, 1), (72, 1), (76, 1), (74, 1), (72, 1), (69, 2),
        (67, 1), (69, 1), (72, 1), (74, 1), (76, 2), (72, 2),
        (69, 1), (72, 1), (76, 1), (79, 1), (76, 1), (74, 1), (72, 2),
        (74, 1), (72, 1), (69, 1), (67, 1), (69, 4),
    ]
    # B section — wider leaps
    theme_b = [
        (81, 2), (79, 1), (76, 1), (79, 2), (76, 2),
        (74, 1), (72, 1), (69, 2), (72, 2), (76, 2),
        (84, 2), (81, 1), (79, 1), (76, 2), (72, 2),
        (74, 2), (76, 2), (72, 2), (69, 2),
    ]
    phrase: list[tuple[float | None, float]] = []
    for bar_group in range(4):
        phrase.extend(theme_a if bar_group < 2 else theme_b)
    melody = render_violin_melody(n, bpm, phrase, gain=0.52, step_beats=0.5)
    harmony = render_violin_harmony(n, bpm, phrase, gain=0.18, step_beats=0.5, interval=7)

    # Soft answering violin in gaps (lower)
    answer = [
        (None, 8), (64, 2), (67, 2), (69, 4),
        (None, 8), (60, 2), (64, 2), (67, 4),
    ]
    counter = render_violin_melody(n, bpm, _repeat_melody(answer, 4), gain=0.22, step_beats=0.5)

    mixed = mix_tracks(drums, bass, pads, counter, harmony, melody)
    mixed = sidechain_duck(mixed, drums, amount=0.28)
    mixed = [soft_clip(x, 1.15) for x in mixed]
    return fade_edges(normalize(mixed, 0.58), 0.04)


def boss_music() -> list[float]:
    """Mini-boss — violin lead up front, light guitar underneath."""
    duration = 32.0
    bpm = 140.0
    n = int(SR * duration)
    bars = 16

    drums = render_drums(n, bpm, intensity=0.95, double_hats=True, industrial=False)
    bass = render_bass(n, bpm, _bass_pattern([45, 46, 45, 40], bars), growl=False, gain=0.4)

    chords = [[57, 60, 64], [58, 61, 64], [53, 57, 60], [52, 55, 59]] * 8
    pads = render_violin_pads(n, bpm, chords, beats_per_chord=2.0, gain=0.09)

    theme = [
        (76, 1), (79, 1), (81, 2), (79, 1), (76, 1), (74, 2),
        (72, 1), (74, 1), (76, 2), (72, 2), (69, 2),
        (81, 1), (84, 1), (81, 1), (79, 1), (76, 2), (79, 2),
        (81, 2), (76, 2), (72, 2), (69, 2),
    ]
    theme_b = [
        (84, 2), (81, 1), (79, 1), (81, 2), (76, 2),
        (79, 1), (81, 1), (84, 2), (88, 2), (84, 2),
        (81, 1), (79, 1), (76, 2), (74, 2), (72, 2),
        (69, 2), (72, 2), (76, 4),
    ]
    phrase = _repeat_melody(theme, 2) + _repeat_melody(theme_b, 2)
    melody = render_violin_melody(n, bpm, phrase, gain=0.55, step_beats=0.5)
    harmony = render_violin_harmony(n, bpm, phrase, gain=0.2, step_beats=0.5, interval=3)

    # Supportive guitar — quiet
    g_roots: list[float | None] = []
    for bar in range(bars):
        r = [45, 46, 41, 40][bar % 4]
        g_roots += [r, None, r, None]
    guitar = render_guitar_rhythm(n, bpm, g_roots, step_beats=0.5, gain=0.14)

    mixed = mix_tracks(drums, bass, pads, guitar, harmony, melody)
    mixed = sidechain_duck(mixed, drums, amount=0.3)
    mixed = [soft_clip(x, 1.2) for x in mixed]
    return fade_edges(normalize(mixed, 0.58), 0.035)


def boss_citadel_music() -> list[float]:
    """Wave 10 — noble violin theme over march drums + soft guitar."""
    duration = 36.0
    bpm = 112.0
    n = int(SR * duration)
    beat = 60.0 / bpm
    bars = int(duration / (beat * 4))

    drums = render_drums(n, bpm, intensity=0.9, double_hats=False, industrial=False)
    bass = render_bass(n, bpm, _bass_pattern([33, 33, 29, 28], bars), gain=0.42)

    chords = [[57, 64, 69], [57, 64, 69], [53, 60, 65], [52, 59, 64]] * ((bars + 3) // 4)
    pads = render_violin_pads(n, bpm, chords, beats_per_chord=2.0, gain=0.12)

    theme = [
        (69, 2), (None, 1), (69, 1), (72, 2), (76, 2),
        (74, 2), (72, 2), (69, 2), (67, 1), (69, 1),
        (76, 3), (79, 1), (76, 2), (72, 2),
        (74, 2), (69, 2), (67, 2), (64, 2),
    ]
    theme_b = [
        (81, 2), (79, 2), (76, 2), (72, 2),
        (74, 1), (76, 1), (79, 2), (81, 2), (76, 2),
        (84, 3), (81, 1), (79, 2), (76, 2),
        (74, 2), (72, 2), (69, 4),
    ]
    phrase = _repeat_melody(theme, 2) + _repeat_melody(theme_b, 2)
    melody = render_violin_melody(n, bpm, phrase, gain=0.56, step_beats=0.5)
    harmony = render_violin_harmony(n, bpm, phrase, gain=0.2, step_beats=0.5, interval=7)

    g_roots: list[float | None] = []
    for bar in range(bars):
        r = [45, 45, 41, 40][bar % 4]
        g_roots += [r, r, None, None]
    guitar = render_guitar_rhythm(n, bpm, g_roots, step_beats=0.5, gain=0.15)

    mixed = mix_tracks(drums, bass, pads, guitar, harmony, melody)
    mixed = sidechain_duck(mixed, drums, amount=0.28)
    mixed = [soft_clip(x, 1.18) for x in mixed]
    return fade_edges(normalize(mixed, 0.6), 0.04)


def boss_ronin_music() -> list[float]:
    """Wave 20 — virtuosic violin duel lead + restrained guitar."""
    duration = 36.0
    bpm = 152.0
    n = int(SR * duration)
    beat = 60.0 / bpm
    bars = int(duration / (beat * 4))

    drums = render_drums(n, bpm, intensity=1.0, double_hats=True, industrial=False)
    bass = render_bass(n, bpm, _bass_pattern([45, 46, 45, 40], bars), gain=0.4)

    chords = [[57, 60, 64], [58, 61, 65], [53, 57, 60], [52, 55, 59]] * ((bars + 3) // 4)
    pads = render_violin_pads(n, bpm, chords, beats_per_chord=2.0, gain=0.09)

    theme = [
        (81, 1), (84, 1), (88, 1), (84, 1), (81, 1), (79, 1), (76, 2),
        (79, 1), (81, 1), (84, 2), (81, 2), (76, 2),
        (88, 1), (91, 1), (88, 1), (84, 1), (81, 2), (84, 2),
        (79, 2), (76, 2), (72, 2), (69, 2),
    ]
    theme_b = [
        (93, 2), (91, 1), (88, 1), (84, 2), (88, 2),
        (91, 1), (93, 1), (96, 2), (93, 2), (88, 2),
        (84, 1), (81, 1), (79, 2), (76, 2), (81, 2),
        (84, 2), (76, 2), (72, 4),
    ]
    phrase = _repeat_melody(theme, 2) + _repeat_melody(theme_b, 2)
    melody = render_violin_melody(n, bpm, phrase, gain=0.58, step_beats=0.5)
    harmony = render_violin_harmony(n, bpm, phrase, gain=0.18, step_beats=0.5, interval=4)

    g_roots: list[float | None] = []
    for bar in range(bars):
        r = [45, 46, 47, 40][bar % 4]
        g_roots += [r, None, r, None]
    guitar = render_guitar_rhythm(n, bpm, g_roots, step_beats=0.5, gain=0.16)

    mixed = mix_tracks(drums, bass, pads, guitar, harmony, melody)
    mixed = sidechain_duck(mixed, drums, amount=0.32)
    mixed = [soft_clip(x, 1.22) for x in mixed]
    return fade_edges(normalize(mixed, 0.6), 0.03)


def boss_milestone_music(tier: int) -> list[float]:
    """Waves 30/40/50+ — violin stays lead; intensity via tempo/range, not noise."""
    tier = max(3, min(5, int(tier)))
    bpm = {3: 148.0, 4: 160.0, 5: 172.0}[tier]
    duration = {3: 34.0, 4: 36.0, 5: 38.0}[tier]
    n = int(SR * duration)
    beat = 60.0 / bpm
    bars = int(duration / (beat * 4))

    drums = render_drums(n, bpm, intensity=0.9 + tier * 0.05, double_hats=True, industrial=False)
    roots = {3: [45, 45, 41, 40], 4: [45, 46, 41, 40], 5: [45, 46, 47, 40]}[tier]
    bass = render_bass(n, bpm, _bass_pattern(roots, bars), gain=0.4)

    chord_sets = {
        3: [[57, 60, 64], [58, 61, 64], [53, 57, 60], [52, 55, 59]],
        4: [[57, 60, 64], [58, 61, 65], [56, 60, 63], [52, 55, 59]],
        5: [[57, 60, 64], [58, 61, 65], [59, 62, 66], [52, 55, 59]],
    }[tier]
    pads = render_violin_pads(n, bpm, chord_sets * ((bars + 3) // 4), beats_per_chord=2.0, gain=0.09)

    themes = {
        3: [
            (76, 1), (79, 1), (81, 2), (84, 2), (81, 2),
            (79, 1), (76, 1), (74, 2), (72, 2), (69, 2),
            (81, 1), (84, 1), (88, 2), (84, 2), (81, 2),
            (79, 2), (76, 2), (72, 4),
        ],
        4: [
            (81, 1), (84, 1), (88, 1), (91, 1), (88, 2), (84, 2),
            (81, 1), (79, 1), (76, 2), (79, 2), (81, 2),
            (93, 2), (91, 1), (88, 1), (84, 2), (88, 2),
            (81, 2), (76, 2), (72, 4),
        ],
        5: [
            (84, 1), (88, 1), (91, 1), (93, 1), (96, 2), (93, 2),
            (91, 1), (88, 1), (84, 2), (88, 2), (91, 2),
            (98, 2), (96, 1), (93, 1), (91, 2), (88, 2),
            (84, 2), (81, 2), (76, 4),
        ],
    }
    phrase = _repeat_melody(themes[tier], max(2, bars // 2))
    melody = render_violin_melody(n, bpm, phrase, gain=0.56 + tier * 0.01, step_beats=0.5)
    harmony = render_violin_harmony(n, bpm, phrase, gain=0.18, step_beats=0.5, interval=7 if tier < 5 else 3)

    g_roots: list[float | None] = []
    for bar in range(bars):
        r = roots[bar % len(roots)]
        g_roots += [r, None, r, None]
    guitar = render_guitar_rhythm(n, bpm, g_roots, step_beats=0.5, gain=0.13 + tier * 0.01)

    mixed = mix_tracks(drums, bass, pads, guitar, harmony, melody)
    mixed = sidechain_duck(mixed, drums, amount=0.3)
    mixed = [soft_clip(x, 1.18) for x in mixed]
    return fade_edges(normalize(mixed, 0.6), 0.03)


def boss_w30_music() -> list[float]:
    return boss_milestone_music(3)


def boss_w40_music() -> list[float]:
    return boss_milestone_music(4)


def boss_w50_music() -> list[float]:
    return boss_milestone_music(5)


# ---------------------------------------------------------------------------
# SFX (unchanged character, slight polish)
# ---------------------------------------------------------------------------


def sfx_shoot() -> list[float]:
    n = int(SR * 0.09)
    samples = []
    for i in range(n):
        t = i / SR
        body = math.sin(2 * math.pi * (220 - 800 * t) * t) * math.exp(-t * 55)
        click = noise() * math.exp(-t * 90) * 0.55
        samples.append(body * 0.55 + click)
    return samples


def sfx_hurt() -> list[float]:
    n = int(SR * 0.28)
    samples = []
    for i in range(n):
        t = i / SR
        tone_s = math.sin(2 * math.pi * (180 - 60 * t) * t)
        grit = noise() * 0.35
        samples.append((tone_s * 0.5 + grit) * math.exp(-t * 6))
    return lowpass(samples, 0.35)


def sfx_kill() -> list[float]:
    n = int(SR * 0.18)
    samples = []
    for i in range(n):
        t = i / SR
        thump = math.sin(2 * math.pi * (90 - 40 * t) * t) * math.exp(-t * 12)
        snap = noise() * math.exp(-t * 40) * 0.4
        samples.append(thump * 0.7 + snap)
    return samples


def sfx_reload() -> list[float]:
    n = int(SR * 0.35)
    samples = []
    for i in range(n):
        t = i / SR
        c1 = math.sin(2 * math.pi * 1800 * t) * math.exp(-((t - 0.05) ** 2) / 0.0003) * 0.5
        c2 = math.sin(2 * math.pi * 1200 * t) * math.exp(-((t - 0.18) ** 2) / 0.0004) * 0.45
        c3 = math.sin(2 * math.pi * 900 * t) * math.exp(-((t - 0.28) ** 2) / 0.0005) * 0.4
        samples.append(c1 + c2 + c3 + noise() * 0.02 * math.exp(-t * 3))
    return samples


def sfx_ability() -> list[float]:
    n = int(SR * 0.45)
    samples = []
    for i in range(n):
        t = i / SR
        sweep = math.sin(2 * math.pi * (220 + 680 * t) * t) * math.exp(-t * 3.2)
        shimmer = math.sin(2 * math.pi * (880 + 400 * t) * t) * 0.35 * math.exp(-t * 4)
        samples.append(sweep * 0.55 + shimmer)
    return samples


def sfx_explosion() -> list[float]:
    n = int(SR * 0.55)
    samples = []
    for i in range(n):
        t = i / SR
        boom = math.sin(2 * math.pi * (55 - 20 * t) * t) * math.exp(-t * 4)
        rumble = noise() * math.exp(-t * 5)
        samples.append(boom * 0.65 + rumble * 0.55)
    return lowpass(samples, 0.25)


def sfx_wave() -> list[float]:
    n = int(SR * 0.7)
    samples = []
    for i in range(n):
        t = i / SR
        a = math.sin(2 * math.pi * 110 * t) * env_adsr(i, n, 0.05, 0.15, 0.6, 0.3)
        b = math.sin(2 * math.pi * 165 * t) * env_adsr(i, n, 0.08, 0.2, 0.5, 0.3) * 0.6
        c = math.sin(2 * math.pi * 220 * t) * env_adsr(i, n, 0.1, 0.2, 0.4, 0.35) * 0.4
        samples.append((a + b + c) * 0.55)
    return samples


def sfx_boss() -> list[float]:
    n = int(SR * 1.1)
    samples = []
    for i in range(n):
        t = i / SR
        f = 220 * (0.55 ** t)
        tone_s = math.sin(2 * math.pi * f * t)
        fifth = math.sin(2 * math.pi * f * 1.5 * t) * 0.45
        sub = math.sin(2 * math.pi * f * 0.5 * t) * 0.7
        grit = noise() * 0.15 * math.exp(-t * 1.5)
        env = env_adsr(i, n, 0.02, 0.2, 0.7, 0.35)
        samples.append((tone_s + fifth + sub) * 0.35 * env + grit)
    return samples


def sfx_pickup() -> list[float]:
    n = int(SR * 0.22)
    samples = []
    notes = [523.25, 659.25, 783.99]
    for i in range(n):
        t = i / SR
        s = 0.0
        for j, f in enumerate(notes):
            delay = j * 0.045
            if t >= delay:
                tt = t - delay
                s += math.sin(2 * math.pi * f * tt) * math.exp(-tt * 14) * 0.4
        samples.append(s)
    return samples


def sfx_gameover() -> list[float]:
    n = int(SR * 1.4)
    samples = []
    for i in range(n):
        t = i / SR
        f = 220 * math.exp(-t * 0.7)
        tone_s = math.sin(2 * math.pi * f * t)
        low = math.sin(2 * math.pi * (f * 0.5) * t) * 0.6
        samples.append((tone_s + low) * 0.4 * math.exp(-t * 1.1))
    return samples


def sfx_ui() -> list[float]:
    n = int(SR * 0.06)
    samples = []
    for i in range(n):
        t = i / SR
        samples.append(math.sin(2 * math.pi * 880 * t) * math.exp(-t * 40) * 0.35)
    return samples


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main() -> None:
    import sys

    only = set(sys.argv[1:])  # e.g. python generate_audio.py citadel ronin
    print("Rendering music...")
    music = {
        "menu_v3.wav": menu_music,
        "combat_v3.wav": combat_music,
        "boss_v3.wav": boss_music,
        "boss_citadel_v3.wav": boss_citadel_music,
        "boss_ronin_v3.wav": boss_ronin_music,
        "boss_w30_v3.wav": boss_w30_music,
        "boss_w40_v3.wav": boss_w40_music,
        "boss_w50_v3.wav": boss_w50_music,
    }
    for name, factory in music.items():
        stem = name.replace(".wav", "")
        # Allow filters like: w30, combat, citadel, v3
        key = stem.replace("boss_", "").replace("_v3", "")
        stem_no_v = stem.replace("_v3", "")
        if only and key not in only and stem not in only and stem_no_v not in only:
            continue
        print(f"  {name}...")
        samples = factory()
        path = os.path.join(OUT_M, name)
        write_wav(path, samples)
        to_mp3(path, quality=2)

    if only:
        print("done (music subset)")
        return

    print("Rendering SFX...")
    sfx = {
        "shoot.wav": sfx_shoot(),
        "hurt.wav": sfx_hurt(),
        "kill.wav": sfx_kill(),
        "reload.wav": sfx_reload(),
        "ability.wav": sfx_ability(),
        "explosion.wav": sfx_explosion(),
        "wave.wav": sfx_wave(),
        "boss_alert.wav": sfx_boss(),
        "pickup.wav": sfx_pickup(),
        "game_over.wav": sfx_gameover(),
        "ui.wav": sfx_ui(),
    }
    for name, samples in sfx.items():
        path = os.path.join(OUT_S, name)
        write_wav(path, samples)
        to_mp3(path, quality=4)

    print("done")


if __name__ == "__main__":
    main()
