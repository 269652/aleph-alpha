extends RefCounted

## The player-facing master volume control -- see docs/concept/soundscape.md's
## own named gap ("no player-facing way to turn this down"). Pure, standalone
## logic, same shape as RenderResolution.sanitize(): guards against a config
## file written by an older build (before this setting existed) or edited by
## hand, rather than leaving the game at an undefined or crashing volume.

const DEFAULT_VOLUME := 1.0

## Effectively inaudible, not literal -inf -- linear_to_db(0.0) IS -inf, and
## an AudioServer bus set to -inf is a real footgun (the same one
## NatureSoundscapePlayer.SILENT_VOLUME_DB already guards per-layer).
const SILENT_BUS_DB := -80.0


## Guards against a corrupted/hand-edited config value: out of [0, 1] range,
## or not a real number at all (NaN), falls back to something playable
## rather than an undefined or crashing volume.
static func sanitize_volume(value: float) -> float:
	if is_nan(value):
		return DEFAULT_VOLUME
	return clampf(value, 0.0, 1.0)


## The Master bus volume (dB) for a given player-facing volume [0, 1] --
## sanitizes its own input too, so a caller can pass a raw, possibly-
## corrupted config value straight through. Zero is a real finite floor,
## not linear_to_db(0.0)'s own -inf.
static func volume_to_bus_db(value: float) -> float:
	var sanitized := sanitize_volume(value)
	if sanitized <= 0.001:
		return SILENT_BUS_DB
	return linear_to_db(sanitized)
