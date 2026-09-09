# Footstep/interaction SFX credits

All 3 files in this directory are sourced from [Wikimedia Commons](https://commons.wikimedia.org)
(direct `upload.wikimedia.org` links, downloaded 2026-09-09), the same
sourcing convention `assets/audio/soundscape/CREDITS.md` already
established. See `docs/concept/creature_and_footstep_audio.md` for what
each file is used for and the honest gaps (no dedicated grass/sand/rock/
underwater recording, no mushroom-crush recording) this list does not
fill.

| File | Source | Author | License |
|---|---|---|---|
| `default.ogg` | [ZapSibAudio-Steps.ogg](https://commons.wikimedia.org/wiki/File:ZapSibAudio-Steps.ogg) | MaksimPinigin | CC BY-SA 4.0 |
| `snow.mp3` | [Walking through snow.mp3](https://commons.wikimedia.org/wiki/File:Walking_through_snow.mp3) | Lukas Beck | CC BY 4.0 |
| `forest_twigs.ogg` | [Audio HörBild von Schritten nachts um 3 im Wald und Grillenzirpen.ogg](https://commons.wikimedia.org/wiki/File:Audio_H%C3%B6rBild_von_Schritten_nachts_um_3_im_Wald_und_Grillenzirpen.ogg) (Ogg Vorbis transcode, not the original Ogg FLAC upload -- see note below) | DrTrumpet | CC BY-SA 4.0 |

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
recordings (which is why the ambient soundscape sourced so cleanly), not
short interactive SFX clips. A real search effort did not turn up usable,
correctly-licensed candidates for grass/sand/rock/underwater specifically,
or for a mushroom crush/squish -- see `docs/concept/creature_and_footstep_
audio.md`'s own Status section for the honest gap this leaves, rather than
forcing a mismatched stand-in (a door-chime, a knife-chop) just to fill
every slot.
