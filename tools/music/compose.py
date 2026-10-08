"""Composes the background music: a calm retro (chiptune/synthwave) loop in A minor.

Everything is synthesized here, so the music is our own and free of third-party rights.
Layers: soft pad chords, triangle bass, a quiet square-wave arpeggio with echo, a simple lead in the
second half, and a soft kick and hi-hat. The loop is exactly 32 bars long and wraps around without a
gap (echo and release tails that run past the end are added to the beginning).

Usage (from the repository root):
  python3 tools/music/compose.py            → build/music.wav
  ffmpeg -y -i build/music.wav -c:a aac -b:a 96k CreepSmash/Sounds/music.m4a
"""
import os
import wave
import numpy as np

RATE = 24_000
BPM = 92
BEAT = 60 / BPM
BAR = 4 * BEAT
BARS = 32
LENGTH = int(round(BARS * BAR * RATE))
rng = np.random.default_rng(7)

# i – VI – III – VII in A minor, two bars each; the second half moves to iv for colour.
PROGRESSION_A = [("A", "m"), ("F", ""), ("C", ""), ("G", "")]
PROGRESSION_B = [("D", "m"), ("F", ""), ("C", ""), ("E", "m")]
NOTE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def freq(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)


def chord(root, quality, octave=4):
    base = 12 * (octave + 1) + NOTE[root]
    third = 3 if quality == "m" else 4
    return [base, base + third, base + 7]


def envelope(n, attack, release):
    env = np.ones(n)
    a = min(n, int(attack * RATE))
    r = min(n - a, int(release * RATE))
    if a:
        env[:a] = np.linspace(0, 1, a)
    if r:
        env[n - r:] = np.linspace(1, 0, r)
    return env


def osc(kind, f, n, duty=0.5):
    t = np.arange(n) / RATE
    phase = (t * f) % 1.0
    if kind == "sine":
        return np.sin(2 * np.pi * phase)
    if kind == "tri":
        return 4 * np.abs(phase - 0.5) - 1
    if kind == "square":
        return np.where(phase < duty, 1.0, -1.0)
    if kind == "saw":
        return 2 * phase - 1
    raise ValueError(kind)


def lowpass(x, cutoff):
    # One-pole low-pass, applied twice for a softer slope.
    a = np.exp(-2 * np.pi * cutoff / RATE)
    for _ in range(2):
        y = np.empty_like(x)
        acc = 0.0
        for i, v in enumerate(x):
            acc = (1 - a) * v + a * acc
            y[i] = acc
        x = y
    return x


def add(track, start_s, signal):
    """Adds a signal at a time; whatever runs past the end wraps to the beginning (seamless loop)."""
    start = int(round(start_s * RATE)) % LENGTH
    n = len(signal)
    end = start + n
    if end <= LENGTH:
        track[start:end] += signal
    else:
        first = LENGTH - start
        track[start:] += signal[:first]
        rest = signal[first:]
        while len(rest):
            k = min(len(rest), LENGTH)
            track[:k] += rest[:k]
            rest = rest[k:]


def chords_for(bar):
    progression = PROGRESSION_A if bar < 16 or bar >= 24 else PROGRESSION_B
    return progression[(bar // 2) % 4]


def pad():
    track = np.zeros(LENGTH)
    for bar in range(0, BARS, 2):
        root, quality = chords_for(bar)
        n = int(2 * BAR * RATE) + int(0.8 * RATE)
        sound = np.zeros(n)
        for midi in chord(root, quality, 4):
            for detune in (-0.12, 0.12):
                sound += osc("saw", freq(midi + detune), n) * 0.5
        sound = lowpass(sound, 900) * envelope(n, 0.6, 1.2)
        add(track, bar * BAR, sound * 0.05)
    return track


def bass():
    track = np.zeros(LENGTH)
    for bar in range(BARS):
        root, _ = chords_for(bar)
        midi = 12 * 3 + NOTE[root]  # octave 2
        for eighth in range(8):
            if eighth in (3, 7) and bar % 2 == 1:
                continue  # a little breathing room
            n = int(BEAT / 2 * RATE * 0.9)
            note = midi + (12 if eighth == 6 else 0)
            sound = osc("tri", freq(note), n) * envelope(n, 0.005, 0.08)
            add(track, bar * BAR + eighth * BEAT / 2, sound * 0.08)
    return track


def arpeggio():
    left, right = np.zeros(LENGTH), np.zeros(LENGTH)
    pattern = [0, 1, 2, 1, 0, 2, 1, 2]  # chord tones, 16th notes, two octaves
    for bar in range(BARS):
        if bar < 4:
            continue  # the arpeggio enters after the intro
        root, quality = chords_for(bar)
        tones = chord(root, quality, 5)
        for step in range(16):
            midi = tones[pattern[step % 8]] + (12 if step >= 8 and bar % 4 == 3 else 0)
            n = int(BEAT / 4 * RATE)
            sound = osc("square", freq(midi), n, duty=0.25) * envelope(n, 0.003, 0.12)
            sound = sound * (0.9 if step % 4 == 0 else 0.6)
            t = bar * BAR + step * BEAT / 4
            add(left, t, sound * 0.035)
            add(right, t, sound * 0.035)
            # Ping-pong echo, dotted eighth.
            add(right, t + 0.75 * BEAT, sound * 0.018)
            add(left, t + 1.5 * BEAT, sound * 0.010)
    return lowpass(left, 3200), lowpass(right, 3200)


# Lead: a calm pentatonic tune in the second half (bars 16–31), (beat offset, length in beats, midi).
LEAD = [
    (0, 1.5, 76), (1.5, 0.5, 74), (2, 2, 72), (4, 1, 74), (5, 1, 76), (6, 2, 79),
    (8, 3, 76), (11, 1, 74), (12, 4, 72),
    (16, 1.5, 74), (17.5, 0.5, 72), (18, 2, 69), (20, 1, 72), (21, 1, 74), (22, 2, 76),
    (24, 3, 74), (27, 1, 72), (28, 4, 71),
]


def lead():
    track = np.zeros(LENGTH)
    for section in (16, 24):
        for beat, length, midi in LEAD:
            n = int(length * BEAT * RATE)
            t = np.arange(n) / RATE
            vibrato = 1 + 0.004 * np.sin(2 * np.pi * 5 * t) * np.clip(t - 0.25, 0, None)
            f = freq(midi) * vibrato
            phase = np.cumsum(f) / RATE
            sound = (4 * np.abs(phase % 1.0 - 0.5) - 1) * 0.7 + np.sin(2 * np.pi * phase) * 0.3
            sound *= envelope(n, 0.03, min(0.25, length * BEAT * 0.4))
            add(track, section * BAR + beat * BEAT, sound * 0.075)
            add(track, section * BAR + beat * BEAT + 1.5 * BEAT, sound * 0.025)
    return lowpass(track, 2500)


def drums():
    track = np.zeros(LENGTH)
    kick_n = int(0.25 * RATE)
    t = np.arange(kick_n) / RATE
    kick = np.sin(2 * np.pi * (45 * t + 60 * (1 - np.exp(-t * 30)) / 30)) * np.exp(-t * 14)
    hat_n = int(0.05 * RATE)
    for bar in range(BARS):
        if bar < 8:
            continue  # drums enter late and stay soft
        for beat in (0, 2):
            add(track, bar * BAR + beat * BEAT, kick * 0.12)
        for eighth in range(1, 8, 2):
            noise = rng.standard_normal(hat_n) * np.exp(-np.arange(hat_n) / RATE * 80)
            noise = noise - lowpass(noise, 6000)  # keep only the hiss
            add(track, bar * BAR + eighth * BEAT / 2, noise * 0.012)
    return track


def main():
    mono = pad() + bass() + drums() + lead()
    arp_l, arp_r = arpeggio()
    left, right = mono + arp_l, mono + arp_r
    left, right = left - left.mean(), right - right.mean()
    peak = max(np.abs(left).max(), np.abs(right).max())
    gain = 0.8 / peak
    stereo = np.stack([left * gain, right * gain], axis=1)
    os.makedirs("build", exist_ok=True)
    with wave.open("build/music.wav", "wb") as f:
        f.setnchannels(2)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes((stereo * 32767).astype("<i2").tobytes())
    print(f"build/music.wav: {LENGTH / RATE:.1f} s, peak gain {gain:.2f}")


if __name__ == "__main__":
    main()
