"""Synthesises the race's world sounds into godot/audio/*.wav (22 050 Hz, 16-bit mono).

The player's own engine is synthesised live by godot/scripts/ui/race_audio.gd. Everything else the race
makes a noise with is baked here once: the other cars' engines, kerbs, gravel and grass, wind, rain and
tyre spray, scraping a barrier, impacts, the pit crew's wheel guns and jack, and the crowd. WorldAudio
(godot/scripts/ui/world_audio.gd) plays them through Godot's mixer, pitched and faded by the race.

No recordings are used: every sound is filtered noise, impulse trains and decaying resonances, built with
numpy. Filtering is done in the frequency domain on the whole buffer, which makes it circular, so a loop
comes out seamless with no crossfade. Loops carry a 'smpl' chunk, which Godot's importer reads as forward
loop points. The random seeds are fixed: rebuilding gives the same files.

    python3 tools/build_sounds.py [--stats]
"""
import os
import struct
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'godot', 'audio')
RATE = 22050
LOOP_RMS = 0.126  # -18 dBFS: loops are levelled by loudness, WorldAudio sets their volumes
SHOT_PEAK = 0.89  # -1 dBFS: one-shots by their peak

ENGINE_RPM = 4500.0  # the bots' engine loop is recorded at this speed (WorldAudio pitches it from here)
KERB_RATE = 20.0  # bumps a second in the kerb loop
GUN_HAMMER = 32.0  # blows a second of a wheel gun's hammer


# ---------------- building blocks ----------------
def t_axis(n):
    return np.arange(n) / RATE


def filt(x, *gains):
    """Shapes x by the product of magnitude responses (functions of frequency in Hz), circularly."""
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / RATE)
    for g in gains:
        spec *= g(f)
    return np.fft.irfft(spec, len(x))


def filt_once(x, *gains, tail=1.0):
    """filt for a one-shot: padded with silence so nothing rings round from the end to the start."""
    pad = np.concatenate([x, np.zeros(int(tail * RATE))])
    return filt(pad, *gains)[:len(x)]


def lp(fc, order=2):
    return lambda f: 1.0 / np.sqrt(1.0 + (f / fc) ** (2 * order))


def hp(fc, order=2):
    return lambda f: 1.0 / np.sqrt(1.0 + (fc / np.maximum(f, 1e-3)) ** (2 * order))


def bp(fc, q):
    return lambda f: 1.0 / np.sqrt(1.0 + q * q * (np.maximum(f, 1e-3) / fc - fc / np.maximum(f, 1e-3)) ** 2)


def cconv(x, h):
    """Circular convolution of x with h (h shorter than x): for loops, what rings past the end wraps round."""
    hh = np.zeros(len(x))
    hh[:len(h)] = h[:len(x)]
    return np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(hh), len(x))


def conv(x, h):
    """Linear convolution, cut to x's length."""
    n = len(x) + len(h)
    return np.fft.irfft(np.fft.rfft(x, n) * np.fft.rfft(h, n), n)[:len(x)]


def modes(freqs, taus, amps, dur):
    """Impulse response of decaying resonances (a struck panel, a wheel nut)."""
    t = t_axis(int(dur * RATE))
    h = np.zeros(len(t))
    for f, tau, a in zip(freqs, taus, amps):
        h += a * np.exp(-t / tau) * np.sin(2.0 * np.pi * f * t)
    return h


def smooth(n, rng, hz):
    """Slowly wandering level, about -1..1, periodic over n (lowpassed noise)."""
    m = filt(rng.standard_normal(n), lp(hz, 3))
    m -= m.mean()  # no drift: a phase driven by it comes back to where it started
    return m / (np.abs(m).max() + 1e-9)


def poisson(n, rng, rate, amp_shape=1.0):
    """Impulses at random (rate a second) with random sizes: rain drops, stones, claps."""
    x = np.zeros(n)
    k = rng.poisson(rate * n / RATE)
    at = rng.integers(0, n, k)
    np.add.at(x, at, rng.exponential(amp_shape, k) * rng.choice([-1.0, 1.0], k))
    return x


def sweep_sine(t, f_of_t):
    return np.sin(2.0 * np.pi * np.cumsum(f_of_t) / RATE)


def thud(dur, f_hi, f_lo, tau_f, tau, attack=0.001):
    """A low knock: a sine falling from f_hi to f_lo, dying away."""
    t = t_axis(int(dur * RATE))
    return sweep_sine(t, f_lo + (f_hi - f_lo) * np.exp(-t / tau_f)) * np.exp(-t / tau) * (1.0 - np.exp(-t / attack))


def level_loop(x):
    """To LOOP_RMS, rounding off the few peaks (sparks, drops) that would clip rather than turning it all down."""
    x = x - x.mean()
    for _ in range(4):
        x *= LOOP_RMS / (np.sqrt(np.mean(x * x)) + 1e-12)
        x = 0.97 * np.tanh(x / 0.97)
    return x


def level_shot(x):
    return x * (SHOT_PEAK / (np.abs(x).max() + 1e-12))


def fade_out(x, dur=0.02):
    k = min(len(x), int(dur * RATE))
    x[-k:] *= np.linspace(1.0, 0.0, k)
    return x


# ---------------- loops ----------------
def engine(rng):
    """Another car's 899 cc four at ENGINE_RPM: a firing pulse train through the exhaust's resonances."""
    n = RATE  # 1 s: 150 firing pulses of exactly 147 samples
    period = RATE / (ENGINE_RPM / 60.0 * 2.0)
    imp = np.zeros(n)
    cyl = [1.0, 0.82, 0.94, 0.78]  # no two cylinders fire quite alike
    k = 0
    while k * period < n:
        at = int(round(k * period + rng.normal(0.0, 0.4))) % n
        imp[at] += cyl[k % 4] * (1.0 + 0.07 * rng.standard_normal())
        k += 1
    t = t_axis(int(0.03 * RATE))
    pulse = (t / 0.0009) * np.exp(1.0 - t / 0.0009)  # the pressure bump of one firing
    pulse += 0.8 * np.exp(-t / 0.0028) * np.sin(2.0 * np.pi * 330.0 * t)  # exhaust pipe
    pulse += 0.3 * np.exp(-t / 0.0011) * np.sin(2.0 * np.pi * 1180.0 * t)  # silencer box
    x = cconv(imp, pulse)
    # valve train and intake: noise that comes and goes with the firing
    env = cconv(np.abs(imp), np.exp(-t / 0.0016))
    x += 0.5 * filt(rng.standard_normal(n), bp(2300.0, 1.1)) * (0.35 + env / env.max())
    return level_loop(filt(x, lp(4200.0, 2), hp(45.0, 2)))


def kerb(rng):
    """Tyres drumming over a kerb's ridges, KERB_RATE bumps a second."""
    n = RATE
    x = np.zeros(n)
    for k in range(int(KERB_RATE)):
        b = thud(0.09, 115.0, 58.0, 0.012, 0.02) * (1.0 + 0.12 * rng.standard_normal())
        t = t_axis(len(b))
        b += 0.35 * filt_once(rng.standard_normal(len(b)), lp(1500.0, 2)) * np.exp(-t / 0.003)
        at = int(k * n / KERB_RATE + rng.integers(-40, 41))
        idx = (at + np.arange(len(b))) % n
        np.add.at(x, idx, b)
    x += 0.12 * filt(rng.standard_normal(n), bp(320.0, 1.5))  # the rubber on the paint between ridges
    return level_loop(x)


def gravel(rng):
    """Stones rattling into the wheel arches over a low roar."""
    n = int(1.5 * RATE)
    x = filt(rng.standard_normal(n), lp(170.0, 2))
    x += 0.45 * filt(rng.standard_normal(n), bp(900.0, 0.9)) * (0.6 + 0.4 * smooth(n, rng, 8.0))
    stones = cconv(poisson(n, rng, 520.0), modes([2150.0, 3400.0], [0.0013, 0.0008], [1.0, 0.7], 0.02))
    stones += 0.6 * cconv(poisson(n, rng, 260.0), modes([1450.0, 4700.0], [0.002, 0.0007], [1.0, 0.6], 0.02))
    x += 0.5 * stones / (np.sqrt(np.mean(stones ** 2)) + 1e-9) * np.sqrt(np.mean(x ** 2))
    return level_loop(x)


def grass(rng):
    """The tyres swishing and thumping over grass and the ruts under it."""
    n = int(1.5 * RATE)
    x = filt(rng.standard_normal(n), lp(320.0, 2)) * (0.75 + 0.25 * smooth(n, rng, 3.0))
    x += 0.4 * filt(rng.standard_normal(n), bp(1350.0, 0.7)) * (0.5 + 0.5 * smooth(n, rng, 5.0)) ** 2
    thumps = cconv(poisson(n, rng, 7.0), thud(0.12, 90.0, 55.0, 0.02, 0.035))
    x += 0.8 * thumps / (np.abs(thumps).max() + 1e-9) * np.abs(x).max()
    return level_loop(x)


def wind(rng):
    """Air rushing past the car, in gusts."""
    n = 3 * RATE
    x = filt(rng.standard_normal(n), lp(480.0, 2), hp(60.0, 1))
    x += 0.35 * filt(rng.standard_normal(n), bp(950.0, 0.6))
    x *= 0.72 + 0.28 * smooth(n, rng, 1.2)
    return level_loop(x)


def rain(rng):
    """A steady downpour: hiss, a roar from further off and drops pattering close by."""
    n = 3 * RATE
    x = 0.55 * filt(rng.standard_normal(n), hp(1300.0, 2), lp(8500.0, 2))
    x += 0.35 * filt(rng.standard_normal(n), lp(520.0, 2))
    drops = cconv(poisson(n, rng, 1100.0), modes([4300.0, 1700.0], [0.0004, 0.0018], [1.0, 0.45], 0.012))
    x += 0.8 * drops / (np.sqrt(np.mean(drops ** 2)) + 1e-9) * np.sqrt(np.mean(x ** 2))
    return level_loop(x)


def spray(rng):
    """Water thrown up by the tyres on a wet road."""
    n = int(1.5 * RATE)
    x = filt(rng.standard_normal(n), bp(1900.0, 0.5)) * (0.78 + 0.22 * smooth(n, rng, 25.0))
    x += 0.3 * filt(rng.standard_normal(n), lp(420.0, 2))
    return level_loop(x)


def scrape(rng):
    """Steel grinding along a barrier: stick-slip noise ringing the panels, and sparks."""
    n = int(1.2 * RATE)
    grip = np.clip(0.4 + 0.8 * smooth(n, rng, 45.0), 0.0, None)  # stick-slip
    exc = rng.standard_normal(n) * grip
    ring = modes([1180.0, 1910.0, 2730.0, 3890.0, 5120.0], [0.05, 0.035, 0.03, 0.02, 0.012],
                 [1.0, 0.8, 0.7, 0.5, 0.35], 0.25)
    x = cconv(exc, ring)
    x /= np.sqrt(np.mean(x ** 2)) + 1e-9
    x += 0.5 * filt(rng.standard_normal(n), bp(2600.0, 0.8)) * grip
    sparks = filt(poisson(n, rng, 160.0), hp(4200.0, 2))
    x += 0.4 * sparks / (np.sqrt(np.mean(sparks ** 2)) + 1e-9)
    return level_loop(filt(x, hp(250.0, 2)))


def squeal(rng):
    """Tyres sliding: a howl that wavers in pitch and level."""
    n = int(1.5 * RATE)
    t = t_axis(n)
    wobble = smooth(n, rng, 6.0)
    # a whole number of cycles of the mean pitch round the loop, so its phase meets itself
    f0 = round(1250.0 * 1.5) / 1.5
    tone = np.sin(2.0 * np.pi * f0 * t + 9.0 * np.cumsum(wobble) / RATE * 2.0 * np.pi)
    x = 0.6 * tone * (0.7 + 0.3 * smooth(n, rng, 9.0))
    x += filt(rng.standard_normal(n), bp(1500.0, 3.0)) * (0.6 + 0.4 * smooth(n, rng, 12.0))
    return level_loop(x)


def crowd(rng):
    """A full grandstand chattering: syllable-paced bands of noise smeared by the space they fill."""
    n = 4 * RATE
    x = 0.5 * filt(rng.standard_normal(n), bp(600.0, 0.6))
    for fc in np.geomspace(260.0, 2600.0, 9):
        syll = np.clip(smooth(n, rng, rng.uniform(3.0, 6.0)), 0.0, None) ** 1.5
        x += filt(rng.standard_normal(n), bp(fc, 2.2)) * syll * (fc / 260.0) ** -0.3
    t = t_axis(int(0.35 * RATE))
    x = cconv(x, rng.standard_normal(len(t)) * np.exp(-t / 0.09))  # the stand's echo
    return level_loop(filt(x, hp(150.0, 2), lp(4000.0, 2)))


# ---------------- one-shots ----------------
def impact(rng):
    """A hard hit: a deep thump, crumpling metal and plastic, the shell ringing, bits falling off."""
    n = int(1.0 * RATE)
    t = t_axis(n)
    x = thud(1.0, rng.uniform(100.0, 130.0), rng.uniform(36.0, 46.0), 0.04, rng.uniform(0.07, 0.11))
    noise = rng.standard_normal(n)
    x += 0.8 * filt_once(noise * np.exp(-t / rng.uniform(0.025, 0.045)), bp(rng.uniform(1100.0, 1500.0), 0.7))
    x += 0.35 * filt_once(rng.standard_normal(n) * np.exp(-t / 0.008), hp(2500.0, 2))
    burst = rng.standard_normal(int(0.006 * RATE))
    ring = modes(rng.uniform(450.0, 2800.0, 4), rng.uniform(0.1, 0.3, 4), rng.uniform(0.4, 1.0, 4), 0.9)
    x += 0.07 * conv(np.concatenate([burst, np.zeros(n - len(burst))]), ring)
    for _ in range(rng.integers(4, 8)):  # debris landing
        at = int(rng.uniform(0.06, 0.6) * RATE)
        tink = modes(rng.uniform(2500.0, 7000.0, 2), [0.02, 0.012], [1.0, 0.6], 0.08) * rng.uniform(0.05, 0.12)
        end = min(n, at + len(tink))
        x[at:end] += tink[:end - at]
    return level_shot(fade_out(x))


def bump(rng):
    """Two cars touching: a hollow plastic knock."""
    n = int(0.5 * RATE)
    t = t_axis(n)
    x = thud(0.5, 160.0, 70.0, 0.025, 0.045)
    x += 0.5 * filt_once(rng.standard_normal(n) * np.exp(-t / 0.012), bp(650.0, 1.5))
    x += 0.15 * conv(np.eye(1, n)[0], modes([900.0, 1700.0], [0.04, 0.025], [1.0, 0.6], 0.3))
    return level_shot(fade_out(x))


def gun(rng):
    """A pit crew's pneumatic wheel gun: a motor spinning up and the hammer rattling the wheel nut."""
    n = int(0.55 * RATE)
    t = t_axis(n)
    run = 0.42
    env = np.clip(t / 0.015, 0.0, 1.0) * np.clip((run - t) / 0.04, 0.0, 1.0)
    hammer = np.zeros(n)
    k = 0.0
    while k < run * RATE:
        hammer[int(k)] = 1.0 + 0.15 * rng.standard_normal()
        k += RATE / GUN_HAMMER * (1.0 + 0.05 * rng.standard_normal())
    x = conv(hammer, modes([2400.0, 3900.0, 5600.0], [0.004, 0.003, 0.002], [1.0, 0.7, 0.5], 0.03)) * env
    motor_f = 210.0 + 60.0 * (1.0 - np.exp(-t / 0.06))
    saw = 2.0 * ((np.cumsum(motor_f) / RATE) % 1.0) - 1.0
    x += 0.35 * filt_once(saw, bp(1100.0, 1.0)) * env
    x += 0.3 * filt_once(rng.standard_normal(n), hp(3000.0, 2)) * env
    # the air let out as the trigger goes
    x += 0.25 * filt_once(rng.standard_normal(n), hp(2000.0, 2)) * np.exp(-np.maximum(t - run, 0.0) / 0.05) * (t >= run)
    return level_shot(fade_out(x))


def jack(rng):
    """The air jack dropping the car: a metal clunk."""
    n = int(0.45 * RATE)
    x = thud(0.45, 120.0, 70.0, 0.02, 0.05)
    click = np.zeros(n)
    click[0] = 1.0
    x += 0.4 * conv(click, modes([380.0, 1020.0, 2240.0], [0.15, 0.1, 0.08], [1.0, 0.7, 0.5], 0.45))
    return level_shot(fade_out(x))


def cheer(rng):
    """The crowd roaring as the lights go out or the winner crosses the line, with whistles and applause."""
    n = int(3.5 * RATE)
    t = t_axis(n)
    env = np.clip(t / 0.35, 0.0, 1.0) ** 2 * np.where(t < 1.6, 1.0, np.exp(-(t - 1.6) / 0.7))
    x = filt(rng.standard_normal(n), bp(1100.0, 0.5)) * 0.6
    for fc in np.geomspace(400.0, 3000.0, 7):
        x += filt(rng.standard_normal(n), bp(fc, 2.0)) * np.clip(smooth(n, rng, 9.0), 0.0, None)
    x += 0.8 * filt(poisson(n, rng, 90.0), bp(1500.0, 1.2))  # clapping
    x *= env
    for _ in range(3):  # whistles
        start = rng.uniform(0.25, 1.4)
        dur = rng.uniform(0.35, 0.8)
        f0 = rng.uniform(2000.0, 3100.0)
        mask = (t >= start) & (t < start + dur)
        u = (t[mask] - start) / dur
        f = f0 * (1.0 + 0.12 * np.sin(np.pi * u)) + 35.0 * np.sin(2.0 * np.pi * 6.0 * (t[mask] - start))
        x[mask] += 0.18 * np.sin(2.0 * np.pi * np.cumsum(f) / RATE) * np.sin(np.pi * u) ** 0.5
    tail = t_axis(int(0.4 * RATE))
    x = conv(x, rng.standard_normal(len(tail)) * np.exp(-tail / 0.1))
    return level_shot(fade_out(filt_once(x, hp(180.0, 2), lp(5000.0, 2))))


LOOPS = {'engine': engine, 'kerb': kerb, 'gravel': gravel, 'grass': grass, 'wind': wind, 'rain': rain,
         'spray': spray, 'scrape': scrape, 'squeal': squeal, 'crowd': crowd}
SHOTS = {'impact_0': impact, 'impact_1': impact, 'impact_2': impact, 'bump': bump, 'gun': gun,
         'jack': jack, 'cheer': cheer}


# ---------------- files ----------------
def write_wav(path, x, loop):
    pcm = np.clip(np.round(x * 32767.0), -32768, 32767).astype('<i2').tobytes()
    fmt = struct.pack('<HHIIHH', 1, 1, RATE, RATE * 2, 2, 16)
    chunks = b'fmt ' + struct.pack('<I', len(fmt)) + fmt
    if loop:
        # one forward loop over the whole sound. The format means the end to be the last sample played, but
        # Godot's importer takes it as the first one not played, so it is one past the last
        smpl = struct.pack('<9I', 0, 0, round(1e9 / RATE), 60, 0, 0, 0, 1, 0)
        smpl += struct.pack('<6I', 0, 0, 0, len(x), 0, 0)
        chunks += b'smpl' + struct.pack('<I', len(smpl)) + smpl
    chunks += b'data' + struct.pack('<I', len(pcm)) + pcm
    with open(path, 'wb') as f:
        f.write(b'RIFF' + struct.pack('<I', 4 + len(chunks)) + b'WAVE' + chunks)


def main():
    os.makedirs(OUT, exist_ok=True)
    stats = '--stats' in sys.argv
    for i, (name, fn) in enumerate(list(LOOPS.items()) + list(SHOTS.items())):
        rng = np.random.default_rng(1000 + i)
        x = fn(rng)
        loop = name in LOOPS
        write_wav(os.path.join(OUT, name + '.wav'), x, loop)
        if stats:
            spec = np.abs(np.fft.rfft(x)) ** 2
            f = np.fft.rfftfreq(len(x), 1.0 / RATE)
            centroid = (spec * f).sum() / spec.sum()
            # how the step from the last sample back to the first ranks among all the steps (a click: ~100)
            seam = 100.0 * np.mean(np.abs(np.diff(x)) < abs(x[0] - x[-1])) if loop else 0.0
            print('%-9s %5.2f s  rms %6.1f dB  peak %6.1f dB  centroid %5.0f Hz%s' % (
                name, len(x) / RATE, 20 * np.log10(np.sqrt(np.mean(x * x))), 20 * np.log10(np.abs(x).max()),
                centroid, '  seam step at the %.0fth percentile' % seam if loop else ''))
    print('wrote %d sounds to %s' % (len(LOOPS) + len(SHOTS), os.path.normpath(OUT)))


if __name__ == '__main__':
    main()
