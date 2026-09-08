extends GutTest

## AudioSettings: the player-facing master volume control (docs/concept/
## soundscape.md's own named gap -- "no player-facing way to turn this
## down"). Mirrors RenderResolution.sanitize()'s exact precedent: a pure,
## standalone guard against a config file written by an older build, or
## edited by hand, rather than leaving the game at an undefined volume.

const AudioSettings = preload("res://src/audio/audio_settings.gd")


func test_default_volume_is_full():
	assert_eq(AudioSettings.DEFAULT_VOLUME, 1.0)


func test_sanitize_passes_through_a_valid_value_unchanged():
	assert_eq(AudioSettings.sanitize_volume(0.5), 0.5)
	assert_eq(AudioSettings.sanitize_volume(0.0), 0.0)
	assert_eq(AudioSettings.sanitize_volume(1.0), 1.0)


func test_sanitize_clamps_a_value_above_full():
	assert_eq(AudioSettings.sanitize_volume(1.5), 1.0)


func test_sanitize_clamps_a_negative_value():
	assert_eq(AudioSettings.sanitize_volume(-0.3), 0.0)


## A config file written by an older build (before this setting existed)
## has no value at all -- ConfigFile.get_value's own fallback covers a
## MISSING key, but a value that made it into the file corrupted/non-
## numeric (hand-edited) still has to fall back to something playable
## rather than crashing linear_to_db on a garbage float.
func test_sanitize_falls_back_to_default_for_nan():
	assert_eq(AudioSettings.sanitize_volume(NAN), AudioSettings.DEFAULT_VOLUME)


func test_volume_to_bus_db_matches_linear_to_db_for_a_sanitized_value():
	assert_eq(AudioSettings.volume_to_bus_db(1.0), linear_to_db(1.0))
	assert_eq(AudioSettings.volume_to_bus_db(0.5), linear_to_db(0.5))


## Zero volume must be REAL silence, not linear_to_db(0.0)'s own -inf --
## same footgun NatureSoundscapePlayer.SILENT_VOLUME_DB already guards
## against, for the same reason.
func test_volume_to_bus_db_at_zero_is_a_real_finite_floor_not_negative_infinity():
	var db := AudioSettings.volume_to_bus_db(0.0)
	assert_true(is_finite(db), "zero volume must not be -inf")
	assert_lt(db, -60.0, "and it must still be effectively silent")


func test_volume_to_bus_db_sanitizes_its_input_too():
	assert_eq(AudioSettings.volume_to_bus_db(1.5), AudioSettings.volume_to_bus_db(1.0))
