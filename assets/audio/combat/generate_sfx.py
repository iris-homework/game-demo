"""Original procedural combat Foley; Python standard library, fixed seeds.

Run this file to rebuild the three 48 kHz / 16-bit mono WAV assets.
No recordings, external samples, runtime synthesis or gameplay RNG are used.
"""
from pathlib import Path
import json
import math
import random
import struct
import wave

RATE = 48000
ROOT = Path(__file__).resolve().parent


def noise(count, seed):
    rng = random.Random(seed)
    return [rng.uniform(-1, 1) for _ in range(count)]


def lowpass(values, frequency):
    a = 1 - math.exp(-2 * math.pi * frequency / RATE)
    previous = 0.0
    result = []
    for value in values:
        previous += a * (value - previous)
        result.append(previous)
    return result


def band(values, low, high):
    bottom = lowpass(values, low)
    return lowpass([x - y for x, y in zip(values, bottom)], high)


def export(name, values, peak):
    # Remove DC and fade endpoints; leave generous mixing headroom.
    dc = sum(values) / len(values)
    values = [x - dc for x in values]
    fade = int(RATE * 0.012)
    for i in range(fade):
        values[-1 - i] *= i / fade
    for i in range(24):
        values[i] *= i / 24
    scale = peak / max(abs(x) for x in values)
    values = [x * scale for x in values]
    with wave.open(str(ROOT / name), 'wb') as output:
        output.setparams((1, 2, RATE, 0, 'NONE', 'not compressed'))
        output.writeframes(b''.join(struct.pack('<h', round(x * 32767)) for x in values))
    return {'file': name, 'duration_seconds': len(values) / RATE,
            'peak_dbfs': round(20 * math.log10(peak), 2),
            'rms_dbfs': round(20 * math.log10(math.sqrt(sum(x*x for x in values)/len(values))), 2)}


def slash():
    n = int(RATE * 0.29)
    raw = noise(n, 711)
    air = band(raw, 900, 10500)
    body = band(raw, 180, 1800)
    result = []
    for i in range(n):
        t = i / RATE
        # Air peaks just before the existing 35 ms contact point.
        envelope = (1 - math.exp(-t / 0.007)) * math.exp(-t / 0.043)
        edge = max(0, t - 0.027)
        ring = 0.0 if t < 0.027 else math.exp(-edge / 0.039) * (
            math.sin(2*math.pi*2830*edge) + 0.3*math.sin(2*math.pi*4760*edge))
        result.append((air[i]*1.9 + body[i]*0.55)*envelope + ring*0.055)
    return result


def shotgun():
    n = int(RATE * 0.48)
    raw = noise(n, 194)
    crack = band(raw, 1200, 11500)
    blast = band(raw, 90, 1900)
    result = []
    for i in range(n):
        t = i / RATE
        # Sharp ignition, broad powder blast, short low-frequency punch.
        transient = crack[i]*1.7*math.exp(-t/0.011)
        pressure = blast[i]*2.3*math.exp(-t/0.061)
        body = math.sin(2*math.pi*(73*t + 58*0.022*(1-math.exp(-t/0.022))))
        body *= 0.43*(1-math.exp(-t/0.001))*math.exp(-t/0.047)
        result.append(math.tanh(1.4*(transient+pressure+body)))
    # Very quiet early reflections, no long reverb or distracting shell sounds.
    dry = result[:]
    for seconds, gain in [(0.037, 0.10), (0.071, 0.055)]:
        delay = int(seconds*RATE)
        for i in range(delay, n):
            result[i] += dry[i-delay]*gain
    return result


def snap():
    n = int(RATE * 0.18)
    raw = noise(n, 420)
    skin = band(raw, 1600, 12000)
    palm = band(raw, 500, 3600)
    result = []
    for i in range(n):
        t = i / RATE
        # Finger-on-palm pop with skin crack; deliberately dry and non-metallic.
        pop = math.sin(2*math.pi*1060*t)*math.exp(-t/0.008)*0.50
        cavity = math.sin(2*math.pi*1780*t)*math.exp(-t/0.005)*0.15
        result.append(skin[i]*math.exp(-t/0.0026)*1.7 +
                      palm[i]*math.exp(-t/0.013)*0.85 + pop + cavity)
    return result


if __name__ == '__main__':
    results = [export('slash.wav', slash(), 0.78),
               export('shotgun.wav', shotgun(), 0.82),
               export('finger_snap.wav', snap(), 0.78)]
    (ROOT/'sources.json').write_text(json.dumps({
        'source': 'Original procedural synthesis for MidnightDemo; no third-party samples',
        'generator': 'generate_sfx.py (Python standard library; fixed local seeds)',
        'format': 'PCM signed 16-bit mono, 48000 Hz', 'clips': results,
    }, ensure_ascii=False, indent=2)+'\n')
    print(json.dumps(results, indent=2))
