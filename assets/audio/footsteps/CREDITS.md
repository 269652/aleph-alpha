# Footstep/interaction SFX credits

The first 3 files in this directory are sourced from [Wikimedia Commons](https://commons.wikimedia.org)
(direct `upload.wikimedia.org` links, downloaded 2026-09-09), the same
sourcing convention `assets/audio/soundscape/CREDITS.md` already
established. `mushroom_crush.mp3` (added 2026-09-09, same day) is sourced
from [Pixabay](https://pixabay.com) instead -- see its own row below and
"Why `mushroom_crush.mp3` breaks the Commons-only pattern" further down.
See `docs/concept/creature_and_footstep_audio.md` for what each file is
used for and the honest gaps (no dedicated grass/sand/rock recording)
this list does not fill.

| File | Source | Author | License |
|---|---|---|---|
| `default.ogg` | [ZapSibAudio-Steps.ogg](https://commons.wikimedia.org/wiki/File:ZapSibAudio-Steps.ogg) | MaksimPinigin | CC BY-SA 4.0 |
| `snow.mp3` | [Walking through snow.mp3](https://commons.wikimedia.org/wiki/File:Walking_through_snow.mp3) | Lukas Beck | CC BY 4.0 |
| `forest_twigs.ogg` | [Audio HörBild von Schritten nachts um 3 im Wald und Grillenzirpen.ogg](https://commons.wikimedia.org/wiki/File:Audio_H%C3%B6rBild_von_Schritten_nachts_um_3_im_Wald_und_Grillenzirpen.ogg) (Ogg Vorbis transcode, not the original Ogg FLAC upload -- see note below) | DrTrumpet | CC BY-SA 4.0 |
| `mushroom_crush.mp3` | ["Crinkling styrofoam; close"](https://pixabay.com/sound-effects/film-special-effects-crinkling-styrofoam-close-79974/) | TylerAM (via Freesound, rehosted on Pixabay) | Pixabay Content License |

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
candidates for grass/sand/rock specifically -- see
`docs/concept/creature_and_footstep_audio.md`'s own Status section for
the honest gap this still leaves, rather than forcing a mismatched
stand-in (a door-chime, a knife-chop) just to fill every slot. The
mushroom-crush gap this section used to also name is closed (see
`mushroom_crush.mp3`'s own row above) -- via Pixabay, once directly
asked for a specific Foley stand-in rather than left to a Commons search
alone to resolve.
