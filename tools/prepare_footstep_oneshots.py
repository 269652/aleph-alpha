#!/usr/bin/env python3
"""Build the per-surface footstep one-shot pools in assets/audio/footsteps/steps/.

Reported live: *"Can you find better sounds for the footsteps on every terrain?
They sound weak and not natural"*. Both halves of that turned out to be
measurable, and this tool is the measurement.

WHY THIS EXISTS AT ALL
    Every clip the game shipped before this was a recording of somebody
    WALKING, not a footstep -- forest_twigs.ogg is 41.67s, snow.mp3 13.72s,
    default.ogg 3.64s -- and the levels were 35dB apart end to end:

        grass.ogg          rms -12.59 dBFS   peak  -0.74 dBFS   (a real one-shot)
        snow.mp3           rms -38.42 dBFS   peak -10.34 dBFS
        forest_twigs.ogg   rms -41.26 dBFS   peak -15.93 dBFS
        default.ogg        rms -47.63 dBFS   peak -17.86 dBFS

    That is the whole complaint in numbers: grass was reported "way too loud"
    and got an eyeballed -12dB, which closed a third of a 35dB gap, and
    everything else stayed "weak". So the surfaces get real isolated footstep
    one-shots, several per surface, and ONE measured gain each.

WHAT IT DOES NOT DO
    It does not re-encode a clip it does not have to. Every pack one-shot is
    copied byte-for-byte; the level correction lives in code, as the measured
    per-surface gain this tool writes into steps/levels.json, which
    test_footstep_sound.gd pins FootstepSound._VOLUME_DB_BY_SURFACE against.
    Only two surfaces are genuinely re-encoded: `forest`, whose steps are cut
    out of the repo's OWN 41-second forest recording at its real footfalls
    (same file, same licence, same real forest -- just read one step at a
    time), and `snow`, whose source pack ships FLAC, which Godot's Ogg
    importer cannot read.

LEVELS
    Target: -24.59 dBFS RMS. Not a taste call -- it is the one footstep level
    the user has actually signed off on. grass.ogg measures -12.59 dBFS RMS
    and was accepted at volume_db -12.0, so -24.59 dBFS is what "right" has
    already been agreed to sound like. Each surface pool gets one gain so its
    MEAN lands there, which keeps a soft step softer than a hard one WITHIN a
    surface while making no surface louder than another. The gain is then
    pulled back if it would push that pool's loudest peak above
    PEAK_CEILING_DBFS.

RUNNING IT
    Needs a real ffmpeg and a 7z reader, neither of which is preinstalled
    here; both arrive as plain wheels, no system packages:

        pip install imageio-ffmpeg py7zr
        python3 tools/prepare_footstep_oneshots.py

    Downloads each pack once into --cache (default: .cache/footstep_sources,
    gitignored) and is idempotent -- re-running it rewrites identical files.
    Worth knowing: assets/audio/footsteps/CREDITS.md long recorded that "real
    audio-editing tooling to trim the FILE itself isn't available in this
    environment". With those two wheels, it is.
"""

import argparse
import array
import io
import json
import math
import os
import shutil
import subprocess
import sys
import urllib.request
import zipfile

RATE = 44100
HOP_SECONDS = 0.005

## The level the user already accepted: grass.ogg's own -12.59 dBFS RMS,
## played at the -12.0 dB it was reported as finally sounding right at.
TARGET_RMS_DBFS = -24.59

## Leaves real headroom under full scale for the pitch/volume the player
## applies per step on top of this (see FootstepSound.pitch_scale_for).
PEAK_CEILING_DBFS = -1.0

# ITU-R BS.1770 K-weighting, at 48 kHz (the rate pcm() decodes to). Two
# biquads -- a high shelf standing in for the head's own response, then an
# RLB high-pass -- and then the standard's own mean square.
#
# Added 2026-09-19, reported live: *"pavement footsteps are way too loud"*.
# The pools WERE level-matched, to within 2.5 dB of a common RMS, and the
# complaint was still correct: RMS is not loudness for an impulsive sound.
# A footstep is a transient and a hard surface packs its energy into a much
# sharper one -- at equal RMS, rock's peaks sit 8.4 dB above grass's (crest
# 20.64 dB against 12.28 dB). Applying the shipped RMS-matched gains put
# grass at -33.65 LUFS and rock at -23.80: pavement ran 9.85 dB hot, sand
# 13.5. K-weighting is the standard answer to exactly this failure of RMS,
# and is what EBU R128 normalises broadcast audio by.
K_SHELF_B = (1.53512485958697, -2.69169618940638, 1.19839281085285)
K_SHELF_A = (1.0, -1.69065929318241, 0.73248077421585)
K_RLB_B = (1.0, -2.0, 1.0)
K_RLB_A = (1.0, -1.99004745483398, 0.99007225036621)

# The one footstep level a person has actually listened to and accepted:
# grass, at volume_db -12.0. Everything else is matched to it.
ANCHOR_SURFACE = "grass"
ANCHOR_GAIN_DB = -12.0

# The loudness every pool is matched to is DERIVED from that anchor, not
# written down: target = grass's own measured loudness + the gain grass was
# signed off at. Deriving it is what guarantees the anchor cannot drift --
# a hardcoded target rounded grass to -12.5 on the first run of this
# switch, moving the one level nobody was entitled to move.
TARGET_LUFS = None  # filled in by anchored_target() once grass is measured


def anchored_target(raw_lufs_by_surface: dict) -> float:
    return raw_lufs_by_surface[ANCHOR_SURFACE] + ANCHOR_GAIN_DB

## How long one cut step is allowed to be, and how much recording to keep
## AHEAD of the footfall so its own attack is not clipped off.
CUT_LENGTH_SECONDS = 0.40
CUT_PREROLL_SECONDS = 0.03
CUT_FADE_IN_SECONDS = 0.008
CUT_FADE_OUT_SECONDS = 0.08

## Anything quieter than this, relative to a clip's own peak, is the room
## rather than the step -- used to trim dead air off a transcoded clip.
SILENCE_FLOOR_BELOW_PEAK_DB = 45.0
TRANSCODE_MAX_SECONDS = 0.75

SOURCES = {
    "oga_footsteps": {
        "url": "https://opengameart.org/sites/default/files/footsteps_0.zip",
        "page": "https://opengameart.org/content/footsteps-on-different-surfaces",
        "kind": "zip",
    },
    "fantozzi": {
        "url": "https://opengameart.org/sites/default/files/Fantozzi-footsteps.7z",
        "page": "https://opengameart.org/content/fantozzis-footsteps-grasssand-stone",
        "kind": "7z",
    },
    "corsica_snow": {
        "url": "https://opengameart.org/sites/default/files/corsica_s-walking_in_snow.7z",
        "page": "https://opengameart.org/content/42-snow-and-gravel-footsteps",
        "kind": "7z",
    },
}

## Which real recording each surface's steps come from.
##
## `copy` ships the pack's own one-shot untouched -- no re-encode, no
## generation loss, and nothing to re-credit beyond the pack itself.
## `cut` reads individual footfalls out of a long walking recording.
## `transcode` exists only because Godot's Ogg importer cannot read FLAC.
##
## `rock` takes gravel rather than a polished stone slab because two of the
## three ways the game reaches this surface are bare ground (tundra and
## mountain biomes); the third is a laid stone street. If that street ever
## wants its own cobble sound, the same pack's `tile/` (9 clips) and
## Fantozzi's `Stone` (6) are both already sitting in the cache.
POOLS = {
    "grass": ("copy", "oga_footsteps", "footsteps/grass", ["%d.ogg" % i for i in range(9)]),
    "wood": ("copy", "oga_footsteps", "footsteps/wood", ["%d.ogg" % i for i in range(9)]),
    "rock": ("copy", "oga_footsteps", "footsteps/gravel", ["%d.ogg" % i for i in range(10)]),
    "underwater": ("copy", "oga_footsteps", "footsteps/water", ["%d.ogg" % i for i in range(5)]),
    "default": ("copy", "oga_footsteps", "footsteps/boots", ["%d.ogg" % i for i in range(9)]),
    "sand": (
        "copy", "fantozzi", "Fantozzi-footsteps/ogg",
        ["Fantozzi-Sand%s%d.ogg" % (s, n) for s in "LR" for n in (1, 2, 3)],
    ),
    # 8 of the pack's 42, spread across both of its surfaces (plain snow-
    # covered gravel and the icier variant) so a pool of 8 still holds the
    # real range of crunch the recording session captured.
    "snow": (
        "transcode", "corsica_snow", "Corsica_S-Walking_in_Snow",
        ["Corsica_S-Walking_on_snow_covered_gravel_%02d.flac" % n for n in (1, 5, 9, 14)]
        + ["Corsica_S-Walking_on_snow_covered_gravel_and_ice_%02d.flac" % n for n in (2, 8, 16, 22)],
    ),
    # The repo's own recording, read one footfall at a time. Its quiet floor
    # measures -51.6 dBFS against footfalls around -24 dBFS, so the crickets
    # in it stay 27dB under the step rather than riding along audibly.
    "forest": ("cut", "assets/audio/footsteps/forest_twigs.ogg", 8),
}

OUT_DIR = "assets/audio/footsteps/steps"
MANIFEST = OUT_DIR + "/levels.json"


def ffmpeg() -> str:
    try:
        import imageio_ffmpeg
        return imageio_ffmpeg.get_ffmpeg_exe()
    except ImportError:
        found = shutil.which("ffmpeg")
        if found:
            return found
        sys.exit("no ffmpeg: pip install imageio-ffmpeg")


FFMPEG = None


def pcm(path_or_bytes) -> array.array:
    """Decode anything ffmpeg reads to mono 16-bit samples at RATE."""
    if isinstance(path_or_bytes, bytes):
        proc = subprocess.run(
            [FFMPEG, "-v", "error", "-i", "pipe:0", "-ac", "1", "-ar", str(RATE),
             "-f", "s16le", "-"], input=path_or_bytes, capture_output=True)
    else:
        proc = subprocess.run(
            [FFMPEG, "-v", "error", "-i", path_or_bytes, "-ac", "1", "-ar", str(RATE),
             "-f", "s16le", "-"], capture_output=True)
    proc.check_returncode()
    samples = array.array("h")
    samples.frombytes(proc.stdout)
    return samples


def encode_ogg(samples: array.array, out_path: str) -> None:
    proc = subprocess.run(
        [FFMPEG, "-v", "error", "-y", "-f", "s16le", "-ar", str(RATE), "-ac", "1",
         "-i", "pipe:0", "-c:a", "libvorbis", "-q:a", "4", out_path],
        input=samples.tobytes(), capture_output=True)
    proc.check_returncode()


def dbfs(level: float) -> float:
    return 20.0 * math.log10(level / 32768.0) if level > 0.0 else -120.0


def rms_dbfs(samples: array.array) -> float:
    if not len(samples):
        return -120.0
    total = 0
    for value in samples:
        total += value * value
    return dbfs(math.sqrt(total / len(samples)))


def _biquad(samples, b, a) -> list:
    out = [0.0] * len(samples)
    x1 = x2 = y1 = y2 = 0.0
    for i, x in enumerate(samples):
        y = b[0] * x + b[1] * x1 + b[2] * x2 - a[1] * y1 - a[2] * y2
        out[i] = y
        x2, x1 = x1, x
        y2, y1 = y1, y
    return out


def lufs(samples: array.array) -> float:
    """K-weighted loudness of one clip, in LUFS (see K_SHELF_B above).

    pcm() hands back signed 16-bit integers, so samples are scaled to the
    +/-1.0 full scale the standard is defined against first -- exactly the
    /32768.0 dbfs() already applies. Skipping it reads every clip about
    90 dB hot, which is how it was caught.
    """
    if not len(samples):
        return -120.0
    scaled = [v / 32768.0 for v in samples]
    weighted = _biquad(_biquad(scaled, K_SHELF_B, K_SHELF_A), K_RLB_B, K_RLB_A)
    mean_square = sum(v * v for v in weighted) / len(weighted)
    return -0.691 + 10.0 * math.log10(mean_square) if mean_square > 0 else -120.0


def pool_lufs(clip_levels: list) -> float:
    """A pool's loudness: the ENERGY mean of its clips, not the dB mean.

    Averaging decibels would let one quiet clip drag a pool's figure down
    without making the pool any quieter to walk on.
    """
    return 10.0 * math.log10(
        sum(10.0 ** (level / 10.0) for level in clip_levels) / len(clip_levels)
    )


def peak_dbfs(samples: array.array) -> float:
    return dbfs(max((abs(v) for v in samples), default=0))


def envelope(samples: array.array) -> list:
    hop = int(RATE * HOP_SECONDS)
    out = []
    for start in range(0, len(samples) - hop, hop):
        total = 0
        for value in samples[start:start + hop]:
            total += value * value
        out.append(math.sqrt(total / hop))
    return out


def footfalls(samples: array.array, rise_db=9.0, min_gap_seconds=0.18) -> list:
    """Sample indices where a real footfall lands in a walking recording.

    A footfall is a sharp rise over what the recording was doing just before
    it -- measured against the lower quartile of the preceding 0.4s, which in
    a recording of walking IS the gap between steps, so the threshold follows
    the room's own floor instead of a fixed number.
    """
    env = envelope(samples)
    floor_frames = int(0.40 / HOP_SECONDS)
    min_gap_frames = int(min_gap_seconds / HOP_SECONDS)
    picks = []
    for i in range(1, len(env)):
        back = env[max(0, i - floor_frames):i]
        if not back:
            continue
        floor = sorted(back)[len(back) // 4]
        if dbfs(env[i]) - dbfs(floor) < rise_db:
            continue
        if picks and i - picks[-1] < min_gap_frames:
            if env[i] > env[picks[-1]]:
                picks[-1] = i
            continue
        picks.append(i)
    hop = int(RATE * HOP_SECONDS)
    return [(p * hop, env[p]) for p in picks]


def cut_steps(source_path: str, count: int) -> list:
    """The `count` strongest, well-spread footfalls in a walking recording."""
    samples = pcm(source_path)
    found = footfalls(samples)
    if len(found) < count:
        sys.exit("%s: only %d footfalls found, wanted %d" % (source_path, len(found), count))
    # Strongest first, but never two from the same stride: a step and its own
    # decay would otherwise ship twice as two "different" variants.
    chosen = []
    for index, _level in sorted(found, key=lambda f: -f[1]):
        if all(abs(index - taken) > int(RATE * 0.5) for taken in chosen):
            chosen.append(index)
        if len(chosen) == count:
            break
    chosen.sort()

    length = int(RATE * CUT_LENGTH_SECONDS)
    preroll = int(RATE * CUT_PREROLL_SECONDS)
    fade_in = int(RATE * CUT_FADE_IN_SECONDS)
    fade_out = int(RATE * CUT_FADE_OUT_SECONDS)
    cuts = []
    for index in chosen:
        start = max(0, index - preroll)
        window = array.array("h", samples[start:start + length])
        if len(window) < length // 2:
            continue
        # Faded at both ends: a cut that starts or stops mid-waveform clicks,
        # and a click is the least natural sound there is.
        for i in range(min(fade_in, len(window))):
            window[i] = int(window[i] * i / fade_in)
        for i in range(min(fade_out, len(window))):
            at = len(window) - 1 - i
            window[at] = int(window[at] * i / fade_out)
        cuts.append(window)
    return cuts


def trim_to_the_step(samples: array.array) -> array.array:
    """Drop the dead air around a one-shot and cap it at one step's length."""
    if not len(samples):
        return samples
    gate = max((abs(v) for v in samples), default=0) / (10 ** (SILENCE_FLOOR_BELOW_PEAK_DB / 20.0))
    first = 0
    while first < len(samples) and abs(samples[first]) < gate:
        first += 1
    last = len(samples) - 1
    while last > first and abs(samples[last]) < gate:
        last -= 1
    start = max(0, first - int(RATE * CUT_PREROLL_SECONDS))
    end = min(len(samples), last + int(RATE * CUT_FADE_OUT_SECONDS), start + int(RATE * TRANSCODE_MAX_SECONDS))
    out = array.array("h", samples[start:end])
    fade_out = int(RATE * CUT_FADE_OUT_SECONDS)
    for i in range(min(fade_out, len(out))):
        at = len(out) - 1 - i
        out[at] = int(out[at] * i / fade_out)
    return out


def fetch(name: str, cache_dir: str) -> str:
    source = SOURCES[name]
    os.makedirs(cache_dir, exist_ok=True)
    extracted = os.path.join(cache_dir, name)
    if os.path.isdir(extracted):
        return extracted
    archive = os.path.join(cache_dir, name + "." + source["kind"])
    if not os.path.exists(archive):
        print("  fetching %s" % source["url"])
        with urllib.request.urlopen(source["url"], timeout=180) as response:
            data = response.read()
        with open(archive, "wb") as handle:
            handle.write(data)
    os.makedirs(extracted, exist_ok=True)
    if source["kind"] == "zip":
        zipfile.ZipFile(archive).extractall(extracted)
    else:
        import py7zr
        with py7zr.SevenZipFile(archive) as seven:
            seven.extractall(extracted)
    return extracted


def remeasure(repo_root: str) -> dict:
    """Re-derive every gain from the clips ALREADY in the repo.

    The full build downloads several source packs and re-encodes two
    surfaces; re-deriving a level from the shipped one-shots needs none of
    that, and must not touch a single audio byte. Added when the matching
    metric changed from RMS to K-weighted loudness (see K_SHELF_B): the
    clips were right, only the gains computed from them were wrong.
    """
    global TARGET_LUFS
    out_dir = os.path.join(repo_root, OUT_DIR)
    measured = {}
    for surface in sorted(POOLS):
        names = sorted(
            n for n in os.listdir(out_dir)
            if n.startswith(surface + "_") and n.endswith(".ogg")
        )
        if not names:
            raise SystemExit("no shipped clips for %s in %s" % (surface, out_dir))
        measured[surface] = _measure([os.path.join(out_dir, n) for n in names])
    # Measure everything first, THEN derive the target from the anchor --
    # the gain cannot be computed until grass has told us what it is.
    TARGET_LUFS = anchored_target({s: m["pool_lufs"] for s, m in measured.items()})
    print("  anchored on %s at %+.1f dB -> target %.2f LUFS"
          % (ANCHOR_SURFACE, ANCHOR_GAIN_DB, TARGET_LUFS))
    return {surface: _gained(surface, m) for surface, m in sorted(measured.items())}


def _measure(paths: list) -> dict:
    """One pool's clip measurements, before any target is known."""
    clips = []
    for path in paths:
        samples = pcm(path)
        clips.append({
            "file": os.path.basename(path),
            "seconds": round(len(samples) / RATE, 3),
            "rms_dbfs": round(rms_dbfs(samples), 2),
            "peak_dbfs": round(peak_dbfs(samples), 2),
            "lufs": round(lufs(samples), 2),
        })
    return {
        "clips": clips,
        "mean_rms": sum(c["rms_dbfs"] for c in clips) / len(clips),
        "loudest_peak": max(c["peak_dbfs"] for c in clips),
        "pool_lufs": pool_lufs([c["lufs"] for c in clips]),
    }


def _gained(surface: str, measured: dict) -> dict:
    """That pool's single matched gain, against the anchored target."""
    clips = measured["clips"]
    mean_rms = measured["mean_rms"]
    loudest_peak = measured["loudest_peak"]
    pool_loudness = measured["pool_lufs"]
    gain = TARGET_LUFS - pool_loudness
    headroom = PEAK_CEILING_DBFS - loudest_peak
    capped = gain > headroom
    gain = round(min(gain, headroom), 1)
    if loudest_peak + gain > PEAK_CEILING_DBFS:
        gain = math.floor(headroom * 10.0) / 10.0
    print("  %-11s %2d clips, %7.2f LUFS -> gain %+6.1f dB -> %7.2f LUFS%s" % (
        surface, len(clips), pool_loudness, gain, pool_loudness + gain,
        "  (capped at the peak ceiling)" if capped else ""))
    return {
        "achieved_lufs": round(pool_loudness + gain, 2),
        "raw_lufs": round(pool_loudness, 2),
        "achieved_peak_dbfs": round(loudest_peak + gain, 2),
        "achieved_rms_dbfs": round(mean_rms + gain, 2),
        "clips": clips,
        "gain_db": gain,
        "peak_capped": capped,
    }


# One-shot event sounds that are NOT footsteps but are played through the
# same voices, at the same target, and were never measured into it.
#
# Reported live: "can you make the mushroom crush sound louder". The crush
# is 7.54s of styrofoam crushed about twenty separate times, and it was
# being played by picking a UNIFORM random offset anywhere in the file.
# Most of a recording of repeated crushes is the gap between them, so most
# rolls played the gap: across 101 evenly spaced rolls the 0.30s window that
# actually reaches the speaker measured a median of -45.34 LUFS against a
# footstep target of -33.13, with 58 of them more than 10 dB under it.
#
# Measuring it is the fix, in both directions at once: the onset detector
# already here finds where the crushes actually are, and the same per-pool
# gain rule the surfaces use then lands that pool on the same target.
ONE_SHOTS = {
    "mushroom_crush": "assets/audio/footsteps/mushroom_crush.mp3",
}

# How much of a one-shot actually reaches the speaker. Must match
# InteractionSfxPlayer.MUSHROOM_CRUSH_MAX_DURATION_SECONDS, which caps
# playback -- measuring a second of a clip that is cut after 0.3 would
# measure a level nobody hears. Pinned across the two by
# test_the_measured_crush_window_is_the_one_playback_really_allows.
ONE_SHOT_WINDOW_SECONDS = 0.30

# A little of the recording BEFORE the onset, so the transient's own attack
# is not clipped off by starting exactly on it. 20ms: shorter than the
# ~30ms a human needs to localise an attack at all, so it cannot read as a
# delay, and long enough to carry the rise itself.
ONE_SHOT_PRE_ROLL_SECONDS = 0.02


def one_shot_windows(samples: array.array, keep_within_db: float) -> list:
    """Where the real events are in a recording of many, as playable windows.

    Every onset the footstep detector finds, measured as the window playback
    would actually give it, and then the quiet ones dropped -- a recording of
    repeated crushes has soft ones and near-misses in it, and a pool takes
    ONE gain, so a window 20 dB under its neighbours stays 20 dB under them
    and is simply inaudible.

    `keep_within_db` is not a number chosen here: main() passes the widest
    spread any SHIPPED footstep pool already runs, so what survives is
    exactly as varied as a pool this project already accepted.
    """
    window = int(ONE_SHOT_WINDOW_SECONDS * RATE)
    pre_roll = int(ONE_SHOT_PRE_ROLL_SECONDS * RATE)
    found = []
    for index, _strength in footfalls(samples):
        start = max(0, index - pre_roll)
        cut = samples[start:start + window]
        if len(cut) < window:
            continue
        found.append({
            "offset_seconds": round(start / RATE, 3),
            "lufs": round(lufs(cut), 2),
            "peak_dbfs": round(peak_dbfs(cut), 2),
        })
    if not found:
        return []
    loudest = max(f["lufs"] for f in found)
    return [f for f in found if f["lufs"] >= loudest - keep_within_db]


def measure_one_shots(repo_root: str, keep_within_db: float) -> dict:
    """Each one-shot's playable windows and the single gain its pool takes."""
    out = {}
    for name, relative in sorted(ONE_SHOTS.items()):
        samples = pcm(os.path.join(repo_root, relative))
        windows = one_shot_windows(samples, keep_within_db)
        if not windows:
            raise SystemExit("no events found in %s" % relative)
        pool_loudness = pool_lufs([w["lufs"] for w in windows])
        loudest_peak = max(w["peak_dbfs"] for w in windows)
        gain = TARGET_LUFS - pool_loudness
        headroom = PEAK_CEILING_DBFS - loudest_peak
        capped = gain > headroom
        gain = round(min(gain, headroom), 1)
        if loudest_peak + gain > PEAK_CEILING_DBFS:
            gain = math.floor(headroom * 10.0) / 10.0
        print("  %-15s %2d events kept of %2d, %7.2f LUFS -> gain %+6.1f dB -> %7.2f LUFS%s" % (
            name, len(windows), len(footfalls(samples)), pool_loudness, gain,
            pool_loudness + gain,
            "  (capped at the peak ceiling)" if capped else ""))
        out[name] = {
            "source": relative,
            "window_seconds": ONE_SHOT_WINDOW_SECONDS,
            "pre_roll_seconds": ONE_SHOT_PRE_ROLL_SECONDS,
            "kept_within_db": round(keep_within_db, 2),
            "offsets_seconds": [w["offset_seconds"] for w in windows],
            "raw_lufs": round(pool_loudness, 2),
            "gain_db": gain,
            "achieved_lufs": round(pool_loudness + gain, 2),
            "achieved_peak_dbfs": round(loudest_peak + gain, 2),
            "peak_capped": capped,
            "windows": windows,
        }
    return out


def widest_pool_spread(surfaces: dict) -> float:
    """The widest within-pool loudness spread any shipped surface runs.

    The one-shot pools are held to the same variety a footstep pool already
    has rather than to a threshold anybody picked: measured, the shipped
    pools run 0.45 dB (grass) to 8.34 dB (snow) end to end.
    """
    return max(
        max(c["lufs"] for c in s["clips"]) - min(c["lufs"] for c in s["clips"])
        for s in surfaces.values()
    )


def build(cache_dir: str, repo_root: str) -> dict:
    out_dir = os.path.join(repo_root, OUT_DIR)
    os.makedirs(out_dir, exist_ok=True)
    for stale in os.listdir(out_dir):
        if stale.endswith(".ogg") or stale.endswith(".ogg.import"):
            os.remove(os.path.join(out_dir, stale))

    surfaces = {}
    for surface in sorted(POOLS):
        spec = POOLS[surface]
        print("%s:" % surface)
        written = []
        if spec[0] == "copy":
            _, source_name, folder, files = spec
            root = fetch(source_name, cache_dir)
            for i, name in enumerate(files):
                src = os.path.join(root, folder, name)
                dst = os.path.join(out_dir, "%s_%02d.ogg" % (surface, i))
                shutil.copyfile(src, dst)
                written.append(dst)
        elif spec[0] == "transcode":
            _, source_name, folder, files = spec
            root = fetch(source_name, cache_dir)
            for i, name in enumerate(files):
                src = os.path.join(root, folder, name)
                dst = os.path.join(out_dir, "%s_%02d.ogg" % (surface, i))
                encode_ogg(trim_to_the_step(pcm(src)), dst)
                written.append(dst)
        elif spec[0] == "cut":
            _, relative_source, count = spec
            for i, window in enumerate(cut_steps(os.path.join(repo_root, relative_source), count)):
                dst = os.path.join(out_dir, "%s_%02d.ogg" % (surface, i))
                encode_ogg(window, dst)
                written.append(dst)

        clips = []
        for path in written:
            samples = pcm(path)
            clips.append({
                "file": os.path.basename(path),
                "seconds": round(len(samples) / RATE, 3),
                "rms_dbfs": round(rms_dbfs(samples), 2),
                "peak_dbfs": round(peak_dbfs(samples), 2),
                "lufs": round(lufs(samples), 2),
            })
        mean_rms = sum(c["rms_dbfs"] for c in clips) / len(clips)
        loudest_peak = max(c["peak_dbfs"] for c in clips)
        pool_loudness = pool_lufs([c["lufs"] for c in clips])
        # Matched on LOUDNESS, not RMS -- see K_SHELF_B's own note for why
        # the RMS match left pavement 9.85 dB hot while measuring level.
        gain = TARGET_LUFS - pool_loudness
        headroom = PEAK_CEILING_DBFS - loudest_peak
        capped = gain > headroom
        # The gain ships as a one-decimal constant in GDScript, so it is
        # rounded here rather than where it is read. A capped gain is
        # rounded DOWN specifically: rounding it to nearest can put that
        # pool's loudest peak back over the ceiling the cap exists to
        # respect, and a tenth of a dB of level is not worth that.
        gain = round(min(gain, headroom), 1)
        if loudest_peak + gain > PEAK_CEILING_DBFS:
            gain = math.floor(headroom * 10.0) / 10.0
        surfaces[surface] = {
            "achieved_lufs": round(pool_loudness + gain, 2),
            "raw_lufs": round(pool_loudness, 2),
            "gain_db": gain,
            "achieved_rms_dbfs": round(mean_rms + gain, 2),
            "achieved_peak_dbfs": round(loudest_peak + gain, 2),
            "peak_capped": capped,
            "clips": clips,
        }
        print("    %d clips, mean rms %.2f -> gain %+.1f dB -> %.2f dBFS%s" % (
            len(clips), mean_rms, gain, surfaces[surface]["achieved_rms_dbfs"],
            " (pulled back for peak headroom)" if capped else ""))
    return surfaces


def main() -> None:
    global FFMPEG
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", default=".cache/footstep_sources")
    parser.add_argument(
        "--remeasure", action="store_true",
        help="re-derive the gains from the clips already in the repo, "
             "downloading nothing and rewriting no audio",
    )
    args = parser.parse_args()
    FFMPEG = ffmpeg()
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    if args.remeasure:
        print("re-measuring the shipped clips (no downloads, no re-encoding):")
        surfaces = remeasure(repo_root)
    else:
        surfaces = build(os.path.join(repo_root, args.cache), repo_root)
    print("measuring the one-shots that are played through the same voices:")
    spread = widest_pool_spread(surfaces)
    print("  keeping events within %.2f dB of the loudest"
          " (the widest spread a shipped footstep pool runs)" % spread)
    one_shots = measure_one_shots(repo_root, spread)
    manifest = {
        "generated_by": "tools/prepare_footstep_oneshots.py",
        "one_shots": one_shots,
        "target_lufs": TARGET_LUFS,
        "target_rms_dbfs": TARGET_RMS_DBFS,
        "peak_ceiling_dbfs": PEAK_CEILING_DBFS,
        "why_this_target": (
            "grass.ogg measures -12.59 dBFS RMS and was accepted at volume_db "
            "-12.0, so this is the one footstep level already signed off on. "
            "Pools are matched by K-weighted loudness (ITU-R BS.1770) rather "
            "than RMS: reported live as 'pavement footsteps are way too loud' "
            "while every pool sat within 2.5 dB of a common RMS, because RMS "
            "under-reads a transient and a hard surface is all transient."
        ),
        "surfaces": surfaces,
    }
    with open(os.path.join(repo_root, MANIFEST), "w") as handle:
        json.dump(manifest, handle, indent=2, sort_keys=True)
        handle.write("\n")
    spread = [s["achieved_lufs"] for s in surfaces.values()]
    rms_spread = [s["achieved_rms_dbfs"] for s in surfaces.values()]
    print("\nwrote %s\n  %d surfaces, achieved loudness spread %.2f dB (rms %.2f dB)" % (
        MANIFEST, len(surfaces), max(spread) - min(spread),
        max(rms_spread) - min(rms_spread)))
    # Said out loud because this repository has been bitten by it before:
    # the .import sidecars went with the clips, so until Godot re-imports,
    # every path in the manifest loads as null.
    print("\nnow re-import, or none of these clips will load:\n  godot --headless --import")
    print("then copy the gains into FootstepSound._VOLUME_DB_BY_SURFACE"
          " (test_every_surfaces_volume_is_the_gain_the_pipeline_measured checks them):")
    for surface in sorted(surfaces):
        print('\t"%s": %.1f,' % (surface, surfaces[surface]["gain_db"]))
    for name, measured in sorted(one_shots.items()):
        print("\nand the one-shot %s into FootstepSound"
              " (test_the_crush_volume_is_the_gain_the_pipeline_measured checks it):" % name)
        print("\tconst MUSHROOM_CRUSH_VOLUME_DB := %.1f" % measured["gain_db"])
        print("\tconst MUSHROOM_CRUSH_OFFSET_SECONDS: Array[float] = [")
        for i in range(0, len(measured["offsets_seconds"]), 5):
            print("\t\t" + " ".join(
                "%.3f," % o for o in measured["offsets_seconds"][i:i + 5]))
        print("\t]")


if __name__ == "__main__":
    main()
