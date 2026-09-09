extends GutTest

## Per-species vocalizations (see docs/concept/creature_and_footstep_audio.md).
## Reported live: "each animal should have an individual sound.. (horse,
## robin, boar, sparrow) etc." Pure species->clip lookup + an occasional
## chance-per-check gate, no AudioStreamPlayer/Node dependency -- the same
## "pure model, thin Node" split every other audio module in this codebase
## already uses. A species with no real recording sourced yet simply never
## calls (silent, not an error) -- graceful partial coverage, matching
## docs/concept/soundscape.md's own "ship what's actually sourced, flag the
## rest" convention, rather than every species blocking on 100% coverage.

const CreatureCallSound = preload("res://src/audio/creature_call_sound.gd")


func test_a_sourced_species_has_a_real_clip_path():
	for species in ["horse", "robin", "boar", "sparrow"]:
		assert_true(
			CreatureCallSound.has_call(species), "%s should have a sourced call" % species
		)
		assert_true(CreatureCallSound.clip_path_for(species).begins_with("res://"))


func test_an_unsourced_species_has_no_call_and_an_empty_path():
	assert_false(CreatureCallSound.has_call("dragon"))
	assert_eq(CreatureCallSound.clip_path_for("dragon"), "")


func test_check_call_never_fires_for_a_species_with_no_sourced_call():
	# Even a guaranteed-hit roll (0.0) must not fire for a species that
	# has nothing to play.
	assert_false(CreatureCallSound.check_call("dragon", 0.0))


func test_check_call_fires_when_the_roll_clears_the_threshold():
	assert_true(CreatureCallSound.check_call("robin", 0.0))


func test_check_call_does_not_fire_when_the_roll_misses_the_threshold():
	assert_false(CreatureCallSound.check_call("robin", 0.999))


func test_call_chance_per_check_is_low_not_constant():
	# A real bird calls occasionally, not on every single check -- pinned
	# so this can't silently drift back toward "basically always" or
	# "basically never" without a test noticing.
	assert_true(CreatureCallSound.CALL_CHANCE_PER_CHECK > 0.0)
	assert_true(CreatureCallSound.CALL_CHANCE_PER_CHECK < 0.05)
