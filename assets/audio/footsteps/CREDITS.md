# Footstep/interaction SFX credits

The first 3 files in this directory are sourced from [Wikimedia Commons](https://commons.wikimedia.org)
(direct `upload.wikimedia.org` links, downloaded 2026-09-09), the same
sourcing convention `assets/audio/soundscape/CREDITS.md` already
established. `mushroom_crush.mp3` and `grass.ogg` (both added 2026-09-09,
same day) are sourced from Pixabay and OpenGameArt.org respectively -- see
their own rows below and "Why `mushroom_crush.mp3` breaks the Commons-only
pattern" / "Why `grass.ogg` breaks the Commons-only pattern" further down.
See `docs/concept/creature_and_footstep_audio.md` for what each file is
used for and the honest gaps (no dedicated sand/rock recording) this list
does not fill.

| File | Source | Author | License |
|---|---|---|---|
| `default.ogg` | [ZapSibAudio-Steps.ogg](https://commons.wikimedia.org/wiki/File:ZapSibAudio-Steps.ogg) | MaksimPinigin | CC BY-SA 4.0 |
| `snow.mp3` | [Walking through snow.mp3](https://commons.wikimedia.org/wiki/File:Walking_through_snow.mp3) | Lukas Beck | CC BY 4.0 |
| `forest_twigs.ogg` | [Audio HörBild von Schritten nachts um 3 im Wald und Grillenzirpen.ogg](https://commons.wikimedia.org/wiki/File:Audio_H%C3%B6rBild_von_Schritten_nachts_um_3_im_Wald_und_Grillenzirpen.ogg) (Ogg Vorbis transcode, not the original Ogg FLAC upload -- see note below) | DrTrumpet | CC BY-SA 4.0 |
| `mushroom_crush.mp3` | ["Crinkling styrofoam; close"](https://pixabay.com/sound-effects/film-special-effects-crinkling-styrofoam-close-79974/) | TylerAM (via Freesound, rehosted on Pixabay) | Pixabay Content License |
| `grass.ogg` | [Footsteps on different surfaces](https://opengameart.org/content/footsteps-on-different-surfaces) (`footsteps/grass/0.ogg` from the pack's zip; the pack's own `license.txt` for that folder names the original as `footstep-grass.wav` by [swuing on Freesound](https://freesound.org/people/swuing/sounds/38874/)) | swuing (original recording), repackaged by congusbongus (OpenGameArt) | CC BY 3.0 |

## Why `grass.ogg` breaks the Commons-only pattern

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
wired in today since this codebase's per-surface clip lookup is a single
path per surface, not a variation pool -- the other 8 are not copied in,
but remain available in the same pack (same license/attribution) if
per-step variation is ever added later.

## Why `mushroom_crush.mp3` breaks the Commons-only pattern

Requested directly: "find a styrofoam crushing sound and use it for the
mushroom crushing sound." A genuine mushroom squish/splat recording was
never found on Commons despite a real search effort (see "Why not one
recording per surface" below) -- crushed styrofoam is a real, established
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

## `underwater` reuses `river.ogg`, not a file in this directory

Reported live: "river wading should be used for 'underwater walks'."
`FootstepSound.clip_path_for("underwater")` points at
`assets/audio/soundscape/river.ogg` -- see that directory's own CREDITS.md
for its attribution (public domain, Stephan). Deliberately not copied into
this directory as a second file: it's the same real flowing-water
recording backing the ambient river-proximity bed, reused rather than
duplicated on disk/in the license record for the same water.

## Note on `forest_twigs.ogg`

The original upload is Ogg **FLAC**, which Godot's `ResourceImporterOggVorbis`
does not decode (confirmed empirically: it silently fails to import). Saved
here is Wikimedia's own auto-generated Ogg **Vorbis** transcode of the same
recording instead (`.../transcoded/.../<filename>.ogg.ogg`, 109kbps) --
same real recording, same license/author, just a codec Godot can actually
play. Worth knowing if this file is ever re-fetched: grab the Vorbis
transcode link from the file's own "Transcode status" table, not the
"Original file" download link.

## Why not one recording per surface

Wikimedia Commons turned out to have very little isolated Foley-style
"footstep on X" material -- it excels at longer-form nature/wildlife field
recordings (which is why the ambient soundscape, and `underwater`'s own
`river.ogg` reuse above, sourced so cleanly), not short interactive SFX
clips. A real search effort did not turn up usable, correctly-licensed
candidates for sand/rock specifically -- see `docs/concept/
creature_and_footstep_audio.md`'s own Status section for the honest gap
this still leaves, rather than forcing a mismatched stand-in (a
door-chime, a knife-chop) just to fill every slot. The mushroom-crush and
grass gaps this section used to also name are both closed now (see their
own rows above) -- via Pixabay and OpenGameArt respectively, once each
was directly asked for or chased down past a Commons-only search.
