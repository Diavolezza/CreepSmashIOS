"""Synthesizes the sound effects of the game (retro/chiptune style, like the music).

Everything is generated here, so the sounds are our own and free of third-party rights. The file names
are the ones the app uses (see SoundManager.swift); each sound is scaled to a fixed loudness, so the
volume balance between shots, explosions and signals stays as tuned in the app.

  shoot1, shoot2   Basic tower (level 1 / higher)        dead1 … dead5   creep shot down (small … big)
  laser1, laser2   Slow tower (level 1 / higher)         warn            creeps are coming
  shoot3, laser3   Splash tower (level 1 / higher)       dcloak          a creep got through (life lost)
  shoot4           Rocket tower                          holy            tower upgraded
  shoot5           Speed tower                           won             game won
  shoot6           Ultimate tower                        fin             game lost / player out

Usage (from the repository root): python3 tools/sounds/sfx.py   → CreepSmash/Sounds/*.wav
"""
import os
import wave
import numpy as np

RATE = 44_100
OUT = "CreepSmash/Sounds"
rng = np.random.default_rng(2008)


# --- building blocks -------------------------------------------------------------------------

def timeline(seconds):
    return np.arange(int(seconds * RATE)) / RATE


def phase(freqs):
    """Phase of an oscillator whose frequency changes over time (array of Hz per sample)."""
    return 2 * np.pi * np.cumsum(freqs) / RATE


def square(ph, duty=0.5):
    return np.where((ph / (2 * np.pi)) % 1 < duty, 1.0, -1.0)


def saw(ph):
    return 2 * ((ph / (2 * np.pi)) % 1) - 1


def triangle(ph):
    return 2 * np.abs(saw(ph)) - 1


def sweep(t, start, end, curve=1.0):
    """Frequency gliding from start to end over the length of t (exponential)."""
    x = (t / t[-1]) ** curve
    return start * (end / start) ** x


def decay(t, rate):
    return np.exp(-rate * t)


def adsr(t, attack=0.005, release=0.03):
    n, a, r = len(t), int(attack * RATE), int(release * RATE)
    env = np.ones(n)
    if a:
        env[:a] = np.linspace(0, 1, a)
    if r:
        env[-r:] *= np.linspace(1, 0, r)
    return env


def noise(t):
    return rng.uniform(-1, 1, len(t))


def lowpass(x, cutoff):
    """Simple one-pole low-pass; cutoff may be an array (Hz per sample)."""
    cutoff = np.broadcast_to(np.asarray(cutoff, dtype=float), x.shape)
    alpha = 1 - np.exp(-2 * np.pi * cutoff / RATE)
    y, acc = np.empty_like(x), 0.0
    for i in range(len(x)):
        acc += alpha[i] * (x[i] - acc)
        y[i] = acc
    return y


def crush(x, steps=16):
    """Fewer amplitude steps – the grainy 8-bit sound."""
    return np.round(x * steps) / steps


def note(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)


def tone(midi, seconds, wave_fn=square, duty=0.5, vibrato=0.0):
    t = timeline(seconds)
    f = note(midi) * (1 + vibrato * np.sin(2 * np.pi * 6 * t))
    ph = phase(f)
    return (wave_fn(ph, duty) if wave_fn is square else wave_fn(ph)) * adsr(t, 0.004, min(0.05, seconds / 3))


def sequence(parts, total=None):
    """Concatenates (start_seconds, samples) parts into one signal."""
    end = max(start + len(x) / RATE for start, x in parts)
    out = np.zeros(int((total or end) * RATE) + 1)
    for start, x in parts:
        i = int(start * RATE)
        out[i:i + len(x)] += x[: len(out) - i]
    return out


# --- the sounds ------------------------------------------------------------------------------

def shoot1():  # soft little "pew"
    t = timeline(0.07)
    return square(phase(sweep(t, 1400, 500)), 0.25) * decay(t, 45)


def shoot2():  # brighter, double "pew"
    t = timeline(0.09)
    a = square(phase(sweep(t, 2000, 600)), 0.25)
    b = square(phase(sweep(t, 2010, 610)), 0.5)
    return (0.6 * a + 0.4 * b) * decay(t, 35)


def laser1():  # cold buzzing ray (slow tower)
    t = timeline(0.12)
    f = 330 * (1 + 0.08 * np.sin(2 * np.pi * 40 * t))
    return crush(0.7 * saw(phase(f)) + 0.3 * triangle(phase(f * 2.01))) * adsr(t, 0.004, 0.03)


def laser2():
    t = timeline(0.16)
    f = sweep(t, 520, 380) * (1 + 0.1 * np.sin(2 * np.pi * 48 * t))
    return crush(0.6 * saw(phase(f)) + 0.4 * square(phase(f * 1.5), 0.3)) * adsr(t, 0.004, 0.04)


def shoot3():  # splash: crackling burst over a low tone
    t = timeline(0.12)
    body = triangle(phase(sweep(t, 360, 300)))
    crackle = lowpass(noise(t), 3000)
    return (0.6 * body + 0.8 * crackle) * adsr(t, 0.002, 0.02)


def laser3():
    t = timeline(0.12)
    f = sweep(t, 900, 700)
    return crush(0.6 * saw(phase(f)) + 0.5 * lowpass(noise(t), 4000)) * adsr(t, 0.002, 0.02)


def shoot4():  # rocket: thump and a fading whoosh
    t = timeline(0.25)
    thump = np.sin(phase(sweep(t, 160, 50, 0.4))) * decay(t, 30)
    whoosh = lowpass(noise(t), sweep(t, 6000, 600)) * decay(t, 14)
    return 0.9 * thump + 1.2 * whoosh


def shoot5():  # speed: hard zap with a quick drop
    t = timeline(0.25)
    f = sweep(t, 1800, 120, 0.35)
    return square(phase(f), 0.4) * decay(t, 18)


def shoot6():  # ultimate: bright chord zap with a ringing tail
    t = timeline(0.37)
    zap = square(phase(sweep(t, 2400, 900, 0.3)), 0.3) * decay(t, 25)
    ring = sum(triangle(phase(np.full_like(t, note(m)))) for m in (83, 87, 90)) / 3 * decay(t, 6)
    return 0.7 * zap + 0.6 * ring * adsr(t, 0.01, 0.05)


def dead(size):
    """Creep shot down: pop and a short falling blip; bigger creeps sound lower and longer."""
    seconds = 0.28 + 0.07 * (size - 1)
    t = timeline(seconds)
    pop = lowpass(noise(t), 9000 - 1300 * size) * decay(t, 22 - 2.5 * size)
    blip = square(phase(sweep(t, 1500 - 180 * size, 180 - 20 * size, 0.6)), 0.5) * decay(t, 16 - 1.5 * size)
    return crush(0.8 * pop + 0.5 * blip, 24)


def warn():  # creeps are coming: two-tone alarm, twice
    parts, beat = [], 0.12
    for i, m in enumerate((88, 83, 88, 83)):
        parts.append((i * beat, tone(m, beat * 0.9, square, 0.5)))
    return sequence(parts, 0.54)


def dcloak():  # a creep got through: short falling "bwomp" that ends hard
    t = timeline(0.13)
    f = sweep(t, 700, 140, 0.7)
    return (0.7 * square(phase(f), 0.5) + 0.3 * lowpass(noise(t), 2000)) * np.linspace(0.3, 1, len(t)) * adsr(t, 0.002, 0.01)


def holy():  # tower upgraded: rising sparkle arpeggio
    parts = []
    for i, m in enumerate((72, 76, 79, 84, 88)):
        parts.append((i * 0.07, tone(m, 0.35, triangle) * decay(timeline(0.35), 6)))
        parts.append((i * 0.07 + 0.02, 0.3 * tone(m + 12, 0.2, square, 0.125) * decay(timeline(0.2), 12)))
    return sequence(parts, 0.9)


def won():  # fanfare: short pickup and a held major chord
    parts = [(0.00, tone(67, 0.11)), (0.12, tone(72, 0.11)), (0.24, tone(76, 0.11))]
    held = sum(tone(m, 0.85, square, 0.25, vibrato=0.004) for m in (72, 76, 79)) / 3
    parts.append((0.36, held * decay(timeline(0.85), 2.2)))
    parts.append((0.36, 0.8 * tone(48, 0.8, triangle) * decay(timeline(0.8), 2)))
    return sequence(parts, 1.16)


def fin():  # game lost: slow falling minor line
    parts = []
    for i, m in enumerate((76, 72, 69, 64)):
        length = 0.3 if i < 3 else 0.6
        parts.append((i * 0.3, tone(m, length, square, 0.5, vibrato=0.006) * decay(timeline(length), 2.5)))
        parts.append((i * 0.3, 0.7 * tone(m - 24, length, triangle) * decay(timeline(length), 2)))
    return sequence(parts, 1.49)


# Target loudness (RMS) per sound – the levels the app's gain settings were tuned with.
SOUNDS = {
    "shoot1": (shoot1, 0.025), "shoot2": (shoot2, 0.10), "laser1": (laser1, 0.25),
    "laser2": (laser2, 0.22), "shoot3": (shoot3, 0.30), "laser3": (laser3, 0.23),
    "shoot4": (shoot4, 0.15), "shoot5": (shoot5, 0.18), "shoot6": (shoot6, 0.14),
    "dead1": (lambda: dead(1), 0.11), "dead2": (lambda: dead(2), 0.10), "dead3": (lambda: dead(3), 0.10),
    "dead4": (lambda: dead(4), 0.24), "dead5": (lambda: dead(5), 0.20),
    "warn": (warn, 0.13), "dcloak": (dcloak, 0.10), "holy": (holy, 0.12),
    "won": (won, 0.20), "fin": (fin, 0.10),
}


def write(name, x, target_rms):
    x = x - x.mean()
    x *= target_rms / max(1e-9, np.sqrt((x ** 2).mean()))
    peak = np.abs(x).max()
    if peak > 0.98:  # never clip
        x *= 0.98 / peak
    fade = min(len(x), int(0.004 * RATE))  # no click at the end
    x[-fade:] *= np.linspace(1, 0, fade)
    with wave.open(f"{OUT}/{name}.wav", "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes((x * 32767).astype(np.int16).tobytes())


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, (make, rms) in SOUNDS.items():
        write(name, make(), rms)
        print("✓", name)


if __name__ == "__main__":
    main()
