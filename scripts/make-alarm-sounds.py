#!/usr/bin/env python3
"""Generates the bundled alarm sounds for urgent tasks (see `AlarmSound`):

- overdo/subtle-chime.caf — Gentle: a soft, bell-like "ping" (a few decaying sine
  partials with a short fade-in to avoid clicks) followed by silence. AlarmKit loops
  the file while the alarm rings, so the file length sets how often the ping repeats.
- overdo/silent.caf — Silent: pure silence. AlarmKit needs some sound to play, so the
  silent option plays this.

Tweak the parameters below and run from anywhere (macOS, needs `afconvert`):

    python3 scripts/make-alarm-sounds.py
"""

import math
import os
import struct
import subprocess
import tempfile
import wave

RATE = 44100
LOOP_SECONDS = 8.0      # ping + silence; one ping per loop while the alarm rings
PEAK = 0.06             # linear peak amplitude, ~ -24 dBFS: barely there
ATTACK_SECONDS = 0.025  # soft onset, avoids a click
PARTIALS = [            # (frequency Hz, relative amplitude, decay time s)
    (659.25, 1.00, 0.65),  # E5 fundamental: low, warm, long fade
    (1318.5, 0.10, 0.20),  # faint octave, dies fast
]

APP_DIR = os.path.join(os.path.dirname(__file__), "..", "overdo")


def render_chime():
    samples = []
    for i in range(int(RATE * LOOP_SECONDS)):
        t = i / RATE
        fade_in = min(1.0, t / ATTACK_SECONDS)
        value = sum(a * math.exp(-t / d) * math.sin(2 * math.pi * f * t) for f, a, d in PARTIALS)
        samples.append(value * fade_in)
    scale = PEAK / max(abs(s) for s in samples)
    return [max(-1.0, min(1.0, s * scale)) for s in samples]


def render_silence():
    return [0.0] * int(RATE * LOOP_SECONDS)


def write_caf(name, samples):
    output = os.path.abspath(os.path.join(APP_DIR, name))
    with tempfile.TemporaryDirectory() as tmp:
        wav_path = os.path.join(tmp, "sound.wav")
        with wave.open(wav_path, "wb") as wav:
            wav.setnchannels(1)
            wav.setsampwidth(2)
            wav.setframerate(RATE)
            wav.writeframes(b"".join(struct.pack("<h", int(s * 32767)) for s in samples))
        # 16-bit linear PCM in a CAF container — a format alarms and notifications accept.
        subprocess.run(["afconvert", "-f", "caff", "-d", "LEI16@44100", wav_path, output], check=True)
    print(f"Wrote {output}")


def main():
    write_caf("subtle-chime.caf", render_chime())
    write_caf("silent.caf", render_silence())


if __name__ == "__main__":
    main()
