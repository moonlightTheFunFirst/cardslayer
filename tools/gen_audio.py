"""Generate CardSlayer's chiptune BGM and sound effects into res://assets/audio.

Run: python tools/gen_audio.py
Pure numpy synthesis (pulse / triangle / noise). BGM tails wrap around to the
start of the buffer so the tracks loop seamlessly.
"""
import os
import wave

import numpy as np

RATE = 22050
ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "audio")
NOTE_INDEX = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6, "Gb": 6, "G": 7, "G#": 8,
              "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11}
noise_rng = np.random.default_rng(1234)


def freq(note):
    name, octave = note[:-1], int(note[-1])
    midi = 12 * (octave + 1) + NOTE_INDEX[name]
    return 440.0 * 2 ** ((midi - 69) / 12)


def t_axis(duration):
    return np.arange(int(duration * RATE)) / RATE


def envelope(n, attack=0.005, decay=0.08, sustain=0.6, release=0.05):
    env = np.full(n, sustain)
    a = min(n, int(attack * RATE))
    d = min(n - a, int(decay * RATE))
    r = min(n, int(release * RATE))
    env[:a] = np.linspace(0, 1, a, endpoint=False)
    env[a:a + d] = np.linspace(1, sustain, d, endpoint=False)
    if r:
        env[n - r:] *= np.linspace(1, 0, r)
    return env


def pulse(f, duration, duty=0.5, **env):
    t = t_axis(duration)
    wave_ = np.where((t * f) % 1.0 < duty, 1.0, -1.0)
    return wave_ * envelope(len(t), **env)


def triangle(f, duration, **env):
    t = t_axis(duration)
    phase = (t * f) % 1.0
    wave_ = 4 * np.abs(phase - 0.5) - 1
    return wave_ * envelope(len(t), **env)


def noise(duration, decay=0.1, color=0):
    n = int(duration * RATE)
    data = noise_rng.uniform(-1, 1, n)
    if color:  # crude low-pass by repeated sample-and-hold
        data = np.repeat(data[::color], color)[:n]
    return data * np.exp(-np.arange(n) / RATE / decay)


def sweep(f0, f1, duration, shape="square", decay=None):
    t = t_axis(duration)
    f = np.geomspace(f0, f1, len(t))
    phase = np.cumsum(f) / RATE
    if shape == "square":
        wave_ = np.where(phase % 1 < 0.5, 1.0, -1.0)
    elif shape == "sine":
        wave_ = np.sin(2 * np.pi * phase)
    else:
        wave_ = 4 * np.abs(phase % 1 - 0.5) - 1
    env = np.exp(-t / decay) if decay else np.linspace(1, 0, len(t))
    return wave_ * env


def kick():
    return sweep(160, 40, 0.16, "sine", 0.06) * 1.2


def snare():
    return mix(noise(0.14, 0.05) * 0.7, triangle(190, 0.08, decay=0.04, sustain=0.0) * 0.4)


def hat():
    n = noise(0.04, 0.012)
    return np.diff(n, prepend=0) * 0.35


class Track:
    def __init__(self, bpm, bars, beats_per_bar=4):
        self.beat = 60.0 / bpm
        self.length = int(bars * beats_per_bar * self.beat * RATE)
        self.buffer = np.zeros(self.length)

    def add(self, sound, beat_pos, volume=1.0):
        start = int(beat_pos * self.beat * RATE) % self.length
        idx = (start + np.arange(len(sound))) % self.length  # wrap for seamless loop
        np.add.at(self.buffer, idx, sound * volume)

    def melody(self, notes, start_beat, instrument, volume, gap=0.9):
        pos = start_beat
        for note, beats in notes:
            if note != "R":
                self.add(instrument(freq(note), beats * self.beat * gap), pos, volume)
            pos += beats
        return pos


def bars_check(bars):
    for i, bar in enumerate(bars):
        total = sum(b for _, b in bar)
        assert abs(total - 4) < 1e-6, "bar %d has %s beats" % (i, total)
    return [n for bar in bars for n in bar]


def parse(text):
    bars = []
    for line in text.strip().splitlines():
        items = line.split()
        bars.append([(items[i], float(items[i + 1])) for i in range(0, len(items), 2)])
    return bars


CHORDS = {
    "Am": ["A", "C", "E"], "F": ["F", "A", "C"], "G": ["G", "B", "D"], "E": ["E", "G#", "B"], "Dm": ["D", "F", "A"],
    "C": ["C", "E", "G"], "Bb": ["Bb", "D", "F"], "A": ["A", "C#", "E"], "Gm": ["G", "Bb", "D"], "Em": ["E", "G", "B"],
}


def chord_notes(name, octave):
    return [n + str(octave) for n in CHORDS[name]]


def lead_square(duty):
    return lambda f, d: pulse(f, d, duty, attack=0.004, decay=0.1, sustain=0.55, release=0.04)


def bass_tri(f, d):
    return triangle(f, d, attack=0.002, decay=0.05, sustain=0.8, release=0.02)


def arp_pulse(f, d):
    return pulse(f, d, 0.125, attack=0.001, decay=0.05, sustain=0.3, release=0.01)


def battle_bgm():
    progression = ["Am", "F", "G", "E", "Am", "F", "Dm", "E", "C", "G", "Am", "F", "Dm", "Am", "E", "E"]
    lead = bars_check(parse("""
A4 1 C5 .5 E5 .5 D5 .5 C5 .5 B4 .5 C5 .5
A4 1.5 F4 .5 A4 .5 C5 .5 F5 1
G5 1 F5 .5 E5 .5 D5 1 B4 1
E5 1.5 D5 .5 C5 .5 B4 .5 G#4 1
A4 .5 A4 .5 C5 .5 E5 .5 A5 1 G5 1
F5 1 E5 .5 D5 .5 C5 1 A4 1
D5 1 F5 .5 E5 .5 D5 .5 C5 .5 A4 1
B4 1 G#4 1 E4 1 R 1
E5 .5 G5 .5 C6 1 B5 .5 G5 .5 E5 1
D5 1.5 B4 .5 D5 1 G5 1
C6 1 B5 .5 A5 .5 E5 1 C5 1
F5 1.5 G5 .5 A5 1 F5 1
D5 .5 E5 .5 F5 .5 A5 .5 D6 1 C6 1
C6 .5 B5 .5 A5 1 E5 1 C5 1
B4 1 D5 1 G#5 1 B5 1
E5 3 R 1
"""))
    track = Track(150, len(progression))
    track.melody(lead, 0, lead_square(0.25), 0.22)
    for bar, chord in enumerate(progression):
        root = chord_notes(chord, 2)[0]
        octave_up = chord_notes(chord, 3)[0]
        for i, note in enumerate([root, root, octave_up, root, root, octave_up, root, octave_up]):
            track.add(bass_tri(freq(note), track.beat * 0.45), bar * 4 + i * 0.5, 0.42)
        tones = chord_notes(chord, 4)
        for i in range(16):
            track.add(arp_pulse(freq(tones[i % 3]), track.beat * 0.22), bar * 4 + i * 0.25, 0.07)
        for beat in range(4):
            track.add(kick() if beat in (0, 2) else snare(), bar * 4 + beat, 0.5 if beat in (0, 2) else 0.32)
            track.add(hat(), bar * 4 + beat + 0.5, 0.35)
        track.add(kick(), bar * 4 + 2.5, 0.35)
    return track.buffer


def boss_bgm():
    progression = ["Dm", "Dm", "Bb", "A", "Dm", "Gm", "A", "A"] * 2
    lead = bars_check(parse("""
D5 .5 D5 .5 F5 .5 D5 .5 A5 1 G5 .5 F5 .5
E5 .5 F5 .5 E5 .5 D5 .5 C#5 1 A4 1
D5 1 F5 1 Bb5 1 A5 .5 G5 .5
A5 1.5 G5 .5 F5 .5 E5 .5 C#5 1
D6 1 A5 .5 F5 .5 D5 1 F5 .5 A5 .5
Bb5 1 A5 .5 G5 .5 D5 1 G5 1
C#6 1 A5 .5 E5 .5 G5 1 F5 .5 E5 .5
E5 .5 F5 .5 G5 .5 A5 .5 C#6 1 R 1
"""))
    track = Track(168, len(progression))
    end = track.melody(lead, 0, lead_square(0.5), 0.17)
    track.melody(lead, end, lead_square(0.5), 0.17)
    harmony = [(n if n == "R" else n[:-1] + str(int(n[-1]) - 1), b) for n, b in lead]
    track.melody(harmony, end, lead_square(0.25), 0.09)
    for bar, chord in enumerate(progression):
        root = chord_notes(chord, 2)[0]
        low = chord_notes(chord, 1)[0]
        for i in range(16):
            note = low if i % 4 == 0 else root
            track.add(bass_tri(freq(note), track.beat * 0.2), bar * 4 + i * 0.25, 0.45)
        for tone in chord_notes(chord, 3):
            track.add(pulse(freq(tone), track.beat * 3.8, 0.125, attack=0.05, decay=0.4, sustain=0.5, release=0.1), bar * 4, 0.035)
        for beat in range(4):
            track.add(kick(), bar * 4 + beat, 0.45)
            if beat in (1, 3):
                track.add(snare(), bar * 4 + beat, 0.38)
            track.add(hat(), bar * 4 + beat + 0.5, 0.3)
            track.add(hat(), bar * 4 + beat + 0.75, 0.18)
        if bar % 4 == 3:
            for i in range(4):
                track.add(snare(), bar * 4 + 3 + i * 0.25, 0.2 + i * 0.05)
    return track.buffer


def hub_bgm():
    progression = ["C", "Am", "F", "G", "C", "Em", "F", "G"] * 2
    lead = bars_check(parse("""
E5 1 G5 1 C6 1.5 B5 .5
A5 2 E5 1 C5 1
F5 1 A5 1 C6 1 A5 1
G5 3 R 1
E5 1 D5 .5 C5 .5 D5 1 E5 1
G5 1.5 E5 .5 B4 2
A4 1 C5 1 F5 1 E5 .5 D5 .5
D5 2 G4 1 R 1
"""))
    track = Track(92, len(progression))
    soft = lambda f, d: triangle(f, d, attack=0.02, decay=0.2, sustain=0.6, release=0.15)
    end = track.melody(lead, 0, soft, 0.34, gap=0.95)
    track.melody(lead, end, lambda f, d: pulse(f, d, 0.25, attack=0.02, decay=0.2, sustain=0.4, release=0.15), 0.1, gap=0.95)
    track.melody([(n[:-1] + str(int(n[-1]) - 1) if n != "R" else n, b) for n, b in lead], end, soft, 0.2, gap=0.95)
    for bar, chord in enumerate(progression):
        root = chord_notes(chord, 2)[0]
        track.add(bass_tri(freq(root), track.beat * 1.8), bar * 4, 0.35)
        track.add(bass_tri(freq(chord_notes(chord, 2)[2]), track.beat * 1.8), bar * 4 + 2, 0.3)
        tones = chord_notes(chord, 4)
        for i, idx in enumerate([0, 1, 2, 1, 0, 1, 2, 1]):
            track.add(arp_pulse(freq(tones[idx]), track.beat * 0.4), bar * 4 + i * 0.5, 0.06)
        track.add(hat(), bar * 4 + 1, 0.12)
        track.add(hat(), bar * 4 + 3, 0.12)
    return track.buffer


# ---------------------------------------------------------------- sound effects

def concat(*parts):
    return np.concatenate(parts)


def mix(*parts):
    out = np.zeros(max(len(p) for p in parts))
    for p in parts:
        out[:len(p)] += p
    return out


def arpeggio(notes, step, shape=pulse, **kw):
    return concat(*[shape(freq(n), step, **kw) for n in notes])


def se_all():
    s = {}
    s["card_draw"] = mix(np.diff(noise(0.09, 0.03), prepend=0) * 0.6, sweep(900, 1500, 0.06, "square", 0.02) * 0.08)
    s["card_hover"] = pulse(1400, 0.025, 0.25, attack=0.001, decay=0.02, sustain=0.0) * 0.2
    s["card_select"] = arpeggio(["E6", "B6"], 0.035, pulse, duty=0.25, decay=0.03, sustain=0.2) * 0.25
    s["card_play"] = mix(noise(0.14, 0.05, 2) * 0.5, sweep(400, 1200, 0.12, "square", 0.05) * 0.18)
    s["slash"] = mix(np.diff(noise(0.18, 0.06), prepend=0) * 0.9, sweep(1800, 300, 0.12, "square", 0.04) * 0.15)
    s["heavy"] = mix(sweep(120, 35, 0.3, "sine", 0.12) * 1.1, noise(0.3, 0.09, 3) * 0.7)
    s["sweep"] = concat(s["slash"][:1800] * 0.7, s["slash"])
    s["magic"] = mix(sweep(200, 1400, 0.3, "triangle") * 0.5, noise(0.35, 0.15, 4) * 0.45, sweep(90, 50, 0.35, "sine", 0.2) * 0.5)
    s["block"] = mix(pulse(620, 0.18, 0.5, decay=0.12, sustain=0.0) * 0.3, pulse(930, 0.14, 0.5, decay=0.1, sustain=0.0) * 0.2, noise(0.05, 0.015) * 0.4)
    s["block_hit"] = mix(pulse(1200, 0.08, 0.5, decay=0.05, sustain=0.0) * 0.3, noise(0.06, 0.02) * 0.5)
    s["hurt"] = mix(sweep(300, 80, 0.22, "square", 0.08) * 0.35, noise(0.2, 0.06, 2) * 0.6)
    s["enemy_attack"] = mix(noise(0.2, 0.08, 3) * 0.5, sweep(220, 90, 0.18, "square", 0.08) * 0.2)
    s["poison"] = concat(*[mix(sweep(300 + i * 80, 500 + i * 80, 0.07, "triangle", 0.04) * 0.4) for i in range(4)])
    s["heal"] = arpeggio(["C5", "E5", "G5", "C6", "E6"], 0.06, triangle, decay=0.05, sustain=0.5) * 0.45
    s["mp"] = arpeggio(["G5", "D6", "G6"], 0.06, pulse, duty=0.125, decay=0.05, sustain=0.4) * 0.3
    s["buff"] = arpeggio(["C4", "G4", "C5", "G5", "C6"], 0.05, pulse, duty=0.25, decay=0.04, sustain=0.5) * 0.3
    s["draw_card"] = s["card_draw"]
    s["enemy_die"] = mix(sweep(600, 60, 0.6, "square", 0.25) * 0.25, noise(0.6, 0.25, 4) * 0.5)
    s["turn_end"] = mix(sweep(700, 300, 0.12, "square", 0.05) * 0.2, noise(0.1, 0.03, 2) * 0.3)
    s["turn_start"] = arpeggio(["A5", "E6"], 0.07, pulse, duty=0.5, decay=0.05, sustain=0.4) * 0.22
    s["click"] = pulse(900, 0.04, 0.5, attack=0.001, decay=0.03, sustain=0.0) * 0.25
    s["denied"] = concat(pulse(160, 0.08, 0.5, decay=0.05, sustain=0.6), pulse(120, 0.12, 0.5, decay=0.05, sustain=0.6)) * 0.22
    v_notes = [("C5", 0.12), ("E5", 0.12), ("G5", 0.12), ("C6", 0.36), ("G5", 0.12), ("C6", 0.9)]
    s["victory"] = mix(concat(*[pulse(freq(n), d, 0.25, decay=0.1, sustain=0.6, release=0.05) for n, d in v_notes]) * 0.3,
                       concat(*[triangle(freq(n[:-1] + "3"), d, sustain=0.8) for n, d in v_notes]) * 0.35)
    d_notes = [("E5", 0.3), ("D#5", 0.3), ("D5", 0.3), ("C#5", 1.2)]
    s["defeat"] = mix(concat(*[pulse(freq(n), d, 0.5, decay=0.2, sustain=0.5, release=0.1) for n, d in d_notes]) * 0.22,
                      concat(*[triangle(freq(n[:-1] + "3"), d, sustain=0.8) for n, d in d_notes]) * 0.35)
    # Added later: keep at the end so earlier sounds keep their noise samples.
    s["item_use"] = concat(sweep(300, 900, 0.05, "square", 0.03) * 0.2, noise(0.08, 0.03, 2) * 0.3, arpeggio(["C5", "G5"], 0.05, triangle, decay=0.04, sustain=0.4) * 0.3)
    s["cure"] = mix(arpeggio(["E5", "G#5", "B5", "E6", "G#6"], 0.05, pulse, duty=0.125, decay=0.04, sustain=0.5) * 0.28, noise(0.3, 0.12, 6) * 0.1)
    return s


def write(name, data, peak=None):
    """peak normalizes (BGM); without it the authored SE levels are kept."""
    os.makedirs(ROOT, exist_ok=True)
    data = np.tanh(data * 1.2)
    if peak:
        data = data / (np.max(np.abs(data)) or 1) * peak
    pcm = (data * 32767).astype("<i2")
    with wave.open(os.path.join(ROOT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())


if __name__ == "__main__":
    write("bgm_battle", battle_bgm(), 0.7)
    write("bgm_boss", boss_bgm(), 0.7)
    write("bgm_hub", hub_bgm(), 0.6)
    for key, value in se_all().items():
        if key != "draw_card":
            write("se_" + key, value * 1.6)
    print("audio generated in", ROOT)
