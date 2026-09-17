# Footstep/interaction SFX credits

Two kinds of file live here. `steps/` holds the per-surface pools of real,
isolated footstep one-shots the game actually plays -- 5 to 10 per surface,
see the table below. The loose files beside it are what is left of the
one-recording-per-surface era: `default.ogg`, still the fallback for a
surface nobody has recorded, `forest_twigs.ogg`, which the forest pool is
cut out of, and `mushroom_crush.mp3`.

`docs/concept/creature_and_footstep_audio.md`'s "A recording of walking is
not a footstep" has the full reasoning; the short version is that every clip
the game played was a recording of somebody WALKING (up to 41.67s of it) and
their levels were 35 dB apart, which is why footsteps were reported as
"weak and not natural" and grass as "way too loud" before that.

`steps/levels.json`, beside the clips, records what
`tools/prepare_footstep_oneshots.py` measured off every one of them: length,
RMS, peak, and the one gain applied per surface.

## The step pools

| surface | clips | source | author | licence |
|---|---|---|---|---|
| `grass` | 9 | [Footsteps on different surfaces](https://opengameart.org/content/footsteps-on-different-surfaces) (`footsteps/grass/0-8.ogg`) | swuing (original: [`footstep-grass.wav`](https://freesound.org/people/swuing/sounds/38874/)), repackaged by congusbongus | CC BY 3.0 |
| `wood` | 9 | same pack (`footsteps/wood/`) | swuing (original: [`footstep-wood.wav`](https://freesound.org/people/swuing/sounds/38876/)) | CC BY 3.0 |
| `rock` | 10 | same pack (`footsteps/gravel/`) | Ali_6868 ([Gravel Footsteps pack](https://freesound.org/people/Ali_6868/packs/21608/)) | CC0 |
| `underwater` | 5 | same pack (`footsteps/water/`) | EminYILDIRIM ([Water Footsteps](https://freesound.org/people/EminYILDIRIM/sounds/608663/)) and swuing | CC BY 3.0 |
| `default` | 9 | same pack (`footsteps/boots/`) | swuing (original: [`footstep-concrete.wav`](https://freesound.org/people/swuing/sounds/38873/)) | CC BY 3.0 |
| `sand` | 6 | [Fantozzi's Footsteps (Grass/Sand & Stone)](https://opengameart.org/content/fantozzis-footsteps-grasssand-stone) (`ogg/Fantozzi-Sand{L,R}{1,2,3}.ogg`) | Fantozzi (submitted by qubodup) | CC0 |
| `snow` | 8 | [42 snow and gravel footsteps](https://opengameart.org/content/42-snow-and-gravel-footsteps) (8 of the 42, transcoded from FLAC) | Corsica_S (extracted by Iwan Gabovitch) | CC0 |
| `forest` | 8 | cut from `forest_twigs.ogg` below, at its own real footfalls | DrTrumpet | CC BY-SA 4.0 |

Every one of those pack clips ships **byte-for-byte** as downloaded -- the
level correction is a measured per-surface gain in
`FootstepSound._VOLUME_DB_BY_SURFACE`, not a re-encode, so nothing has
generation loss and nothing needs re-crediting as modified. The two
exceptions are honest derivatives of files already credited here: `snow`,
whose pack ships FLAC that Godot's Ogg importer cannot read, and `forest`,
cut out of this repository's own recording (same file, same licence, same
real forest -- see the concept doc for why its crickets do not ride along).

Each pack's own per-folder `license.txt` is the authority for the rows
above, read directly rather than trusting the pack page's summary -- the
`gravel/` folder is CC0 while its siblings are CC BY 3.0, which the page
does not say.

## The loose files

The first 2 files below are sourced from [Wikimedia Commons](https://commons.wikimedia.org)
(direct `upload.wikimedia.org` links, downloaded 2026-09-09), the same
sourcing convention `assets/audio/soundscape/CREDITS.md` already
established. `mushroom_crush.mp3` (added 2026-09-09) is sourced from
Pixabay -- see its own row below and "Why `mushroom_crush.mp3` breaks the
Commons-only pattern" further down.

| File | Source | Author | License |
|---|---|---|---|
| `default.ogg` | [ZapSibAudio-Steps.ogg](https://commons.wikimedia.org/wiki/File:ZapSibAudio-Steps.ogg) | MaksimPinigin | CC BY-SA 4.0 |
| `forest_twigs.ogg` | [Audio HörBild von Schritten nachts um 3 im Wald und Grillenzirpen.ogg](https://commons.wikimedia.org/wiki/File:Audio_H%C3%B6rBild_von_Schritten_nachts_um_3_im_Wald_und_Grillenzirpen.ogg) (Ogg Vorbis transcode, not the original Ogg FLAC upload -- see note below) | DrTrumpet | CC BY-SA 4.0 |
| `mushroom_crush.mp3` | ["Crinkling styrofoam; close"](https://pixabay.com/sound-effects/film-special-effects-crinkling-styrofoam-close-79974/) | TylerAM (via Freesound, rehosted on Pixabay) | Pixabay Content License |

`snow.mp3` ([Walking through snow.mp3](https://commons.wikimedia.org/wiki/File:Walking_through_snow.mp3),
Lukas Beck, CC BY 4.0) and `grass.ogg` were both removed on 2026-09-17,
superseded by the `snow` and `grass` pools above. `grass.ogg` was
byte-identical to what now ships as `steps/grass_00.ogg`, so git records
that one as the rename it is.

## Why the grass recording breaks the Commons-only pattern

Reported live: "also please fix the grass footstep sound" / "it sounds
like a drum, not like walking on grass" -- grass was silently sharing
`default.ogg`. A genuine, isolated grass-footstep recording was never
found on Wikimedia Commons despite a real search effort (several fresh
angles: English, German, category browsing -- corroborating this file's
own prior documented failure, not just repeating it unchecked). Freesound.org
had two real candidates (a CC0 one that turned out to be recorded on
*artificial* turf -- a genuine content mismatch, not just a gating
problem -- and a genuinely natural-sounding CC BY 4.0 one) but both sit
behind Freesound's login-gated download, which this project does not
bypass by creating an account. A Pixabay candidate ("Walking on grass" by
gabytoledosci) looked promising next, but its actual download is gated
behind a Cloudflare Turnstile bot-check that never completed in an
automated browser -- also not something this project bypasses.
OpenGameArt.org, by contrast, hosts plain, ungated static file downloads
(no login, no CAPTCHA) -- it had already done the "download the real
Freesound recording and rehost it" step itself, for a pack used in a real
shipped open-source game (C-Dogs SDL). Worth flagging: OpenGameArt is a
new source for this project, one step removed from Wikimedia Commons'
usual very-clean provenance, but the file is fully traceable back to its
original Freesound author and license and was verified directly (real
`OggS` header, real ~5.2KB size, genuinely decodes) before being trusted --
not just assumed from the pack's page description, which itself turned out
to be unreliable once (a *different*, CC0-licensed pack on the same site,
"Fantozzi's Footsteps," titled itself "Grass/Sand & Stone" but its actual
archive contained zero grass files, only sand and stone -- caught by
checking the real extracted file list rather than trusting the title, and
not used for that reason). The pack's own `footsteps/grass/` folder holds
9 numbered variations (`0.ogg`-`8.ogg`); `0.ogg` was picked as the one
wired in that day since this codebase's per-surface clip lookup was a single
path per surface, not a variation pool -- the other 8 were left in the pack,
"available (same license/attribution) if per-step variation is ever added
later". **It was** (2026-09-17): all nine ship, and so do that same pack's
gravel, wood, water and boots folders, which nobody had looked inside. The
lesson worth keeping is that the pack was re-read rather than re-searched
for.

## Why `mushroom_crush.mp3` breaks the Commons-only pattern

Requested directly: "find a styrofoam crushing sound and use it for the
mushroom crushing sound." A genuine mushroom squish/splat recording was
never found on Commons despite a real search effort (see "Why Wikimedia
Commons was the wrong shelf for this" below) -- crushed styrofoam is a real, established
Foley stand-in for a crunchy/organic crush (the same technique Foley
artists use it for in film), requested here by name rather than invented
as an unasked-for mismatch. Checked Commons again specifically for this
first; still nothing. Sourced from Pixabay instead: free to embed in a
commercial project, modify, and redistribute (not resell standalone,
unmodified) under the [Pixabay Content License](https://pixabay.com/service/license-summary/),
no attribution legally required -- credited here anyway, matching this
directory's own convention of citing every file's real source regardless
of what the license strictly requires. The original recording is
Freesound-hosted; Pixabay is the actual download source used.

## `underwater` no longer borrows `river.ogg` (2026-09-17)

Reported live: "river wading should be used for 'underwater walks'." That
was answered on 2026-09-09 by pointing `underwater` at
`assets/audio/soundscape/river.ogg` (public domain, Stephan -- see that
directory's own CREDITS.md), reused rather than duplicated, because it was
the only water in the project.

`underwater` now has five real recordings of feet going INTO water (see the
step pools above), which is what wading is, where `river.ogg` is a river
heard from the bank. `river.ogg` keeps its ambient river-proximity job
untouched. Flagged here because it is a deliberate change to something
asked for by name, not a silent one -- the earlier mapping is one line away
if the river is preferred underfoot.

## Note on `forest_twigs.ogg`

The original upload is Ogg **FLAC**, which Godot's `ResourceImporterOggVorbis`
does not decode (confirmed empirically: it silently fails to import). Saved
here is Wikimedia's own auto-generated Ogg **Vorbis** transcode of the same
recording instead (`.../transcoded/.../<filename>.ogg.ogg`, 109kbps) --
same real recording, same license/author, just a codec Godot can actually
play. Worth knowing if this file is ever re-fetched: grab the Vorbis
transcode link from the file's own "Transcode status" table, not the
"Original file" download link.

## Why Wikimedia Commons was the wrong shelf for this

Wikimedia Commons turned out to have very little isolated Foley-style
"footstep on X" material -- it excels at longer-form nature/wildlife field
recordings (which is why the ambient soundscape sourced so cleanly), not
short interactive SFX clips. That is exactly what the footstep pools needed,
and it is why every clip the game played for its first week was a
minutes-long recording of somebody walking.

This section used to name sand and rock as gaps a real search effort had
failed to fill. Both are closed now (2026-09-17), and neither needed a new
search: OpenGameArt -- already the source of the grass clip, already known
to host ungated static downloads -- had a gravel folder in the very pack
grass came from, and Fantozzi's Footsteps, a pack an earlier session had
already downloaded and correctly rejected for grass, has six real sand
steps in it. What was missing was not a source but a second look.

## Real audio tooling IS available here

Several decisions recorded in this file and in `docs/concept/
creature_and_footstep_audio.md` were shaped by the belief that "real
audio-editing tooling to trim the FILE itself isn't available in this
environment" -- which is why `forest_twigs.ogg` needed a transcode swap
rather than a re-encode, why the mushroom crush is capped in PLAYBACK
rather than trimmed, and why grass's level was corrected with a playback
dB rather than by normalizing the file.

It is not true. `pip install imageio-ffmpeg py7zr` brings a real ffmpeg 7
and a 7z reader as plain wheels -- no system packages, no apt. That is what
`tools/prepare_footstep_oneshots.py` runs on: it decodes every clip to raw
PCM, measures RMS and peak, finds real footfalls in a walking recording,
cuts and fades them, and transcodes FLAC. Anything in this file that reads
as "we cannot edit audio here" should be treated as out of date.
