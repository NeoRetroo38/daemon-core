#!/usr/bin/env python3
"""Generador reproducible de los SFX de Daemon (solo biblioteca estándar).

Uso: python3 assets/sfx/generate_sfx.py  → escribe los .wav junto a este archivo.
Para refinarlos en Ableton Live: importa el .wav, procésalo y expórtalo con el
mismo nombre (44.1 kHz, 16 bit, mono). La app los carga por nombre.
"""
import math
import os
import random
import struct
import wave

RATE = 44100
HERE = os.path.dirname(os.path.abspath(__file__))


def env(i, n, attack, release):
    t = i / RATE
    total = n / RATE
    a = min(1.0, t / attack) if attack > 0 else 1.0
    r = min(1.0, (total - t) / release) if release > 0 else 1.0
    return max(0.0, min(a, r))


def tone(freq, dur, amp=0.5, attack=0.004, release=0.08, decay=0.0, fm=0.0, fm_ratio=2.0, detune=0.0):
    n = int(RATE * dur)
    out = []
    for i in range(n):
        t = i / RATE
        mod = math.sin(2 * math.pi * freq * fm_ratio * t) * fm
        s = math.sin(2 * math.pi * freq * t + mod)
        if detune:
            s = 0.5 * s + 0.5 * math.sin(2 * math.pi * freq * (1 + detune) * t + mod)
        d = math.exp(-decay * t) if decay else 1.0
        out.append(s * amp * d * env(i, n, attack, release))
    return out


def noise(dur, amp=0.3, attack=0.001, release=0.02, color=0.0, seed=7):
    rnd = random.Random(seed)
    n = int(RATE * dur)
    out, last = [], 0.0
    for i in range(n):
        w = rnd.uniform(-1, 1)
        last = color * last + (1 - color) * w  # paso bajo de un polo
        out.append(last * amp * env(i, n, attack, release))
    return out


def mix(*tracks, offsets=None):
    offsets = offsets or [0.0] * len(tracks)
    length = max(int(o * RATE) + len(t) for t, o in zip(tracks, offsets))
    out = [0.0] * length
    for track, offset in zip(tracks, offsets):
        start = int(offset * RATE)
        for i, v in enumerate(track):
            out[start + i] += v
    return out


def write(name, samples, peak=0.45):
    m = max(1e-9, max(abs(s) for s in samples))
    scale = peak / m
    with wave.open(os.path.join(HERE, name), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s * scale)) * 32767)) for s in samples))
    print("escrito", name, f"{len(samples) / RATE:.2f}s")


# Arranque: barrido grave que se abre en quinta y termina en un «ping» verde.
swell = [s * (i / (RATE * 1.1)) for i, s in enumerate(tone(55, 1.1, 0.6, attack=0.6, release=0.3, detune=0.004))]
fifth = tone(82.4, 1.0, 0.35, attack=0.5, release=0.35, detune=0.006)
air = noise(1.0, 0.18, attack=0.7, release=0.25, color=0.97, seed=3)
ping = mix(tone(1318.5, 0.6, 0.35, attack=0.002, release=0.5, decay=6), tone(1975.5, 0.5, 0.15, attack=0.002, release=0.4, decay=8))
write("boot.wav", mix(swell, fifth, air, ping, offsets=[0, 0.15, 0.1, 1.05]), peak=0.5)

# Medida: tick FM corto, casi un reloj de instrumento.
write("measure.wav", tone(2093, 0.07, 0.4, attack=0.001, release=0.05, decay=40, fm=1.2, fm_ratio=1.5), peak=0.22)

# Verificado: dos notas ascendentes (mi → si), limpias.
write("verified.wav", mix(tone(659.3, 0.18, 0.4, release=0.12, decay=10), tone(987.8, 0.26, 0.4, release=0.2, decay=8), offsets=[0, 0.07]), peak=0.3)

# Parcial: una nota neutra, sin resolver.
write("partial.wav", tone(740, 0.22, 0.4, release=0.18, decay=9, detune=0.01), peak=0.25)

# Alerta: dos pulsos graves desafinados.
pulse = [math.copysign(min(1, abs(v) * 3), v) for v in tone(110, 0.16, 0.5, attack=0.004, release=0.06, detune=0.03)]
write("alert.wav", mix(pulse, pulse, offsets=[0, 0.22]), peak=0.4)

# Envío: clic de tecla mecánica.
write("send.wav", mix(noise(0.03, 0.6, release=0.025, color=0.2, seed=11), tone(3500, 0.02, 0.2, release=0.015, decay=120)), peak=0.25)

# Clod: acorde aéreo lila (maj7) con ataque lento.
write("clod.wav", mix(*[tone(f, 0.55, 0.22, attack=0.06, release=0.35, decay=3, detune=0.003) for f in (523.3, 659.3, 784.0, 987.8)]), peak=0.28)
