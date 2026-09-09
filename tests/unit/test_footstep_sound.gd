extends GutTest

## Pure surface-classification + clip lookup for footstep/interaction SFX
## (see docs/concept/creature_and_footstep_audio.md). Reuses the SAME real
## biome/snow/underwater inputs EarthChunkManager.footstep_surface_for
## already computes for the VISUAL footprint sprite -- never re-derives
## them -- but keeps its own, WIDER surface classification: the footprint
## sprite only has art for 4 surfaces and silently draws nothing for the
## other 3 biomes (a correct visual scope cut), which would be a wrong cut
## for sound -- "we need footsteps" (reported live) means every biome
## should make SOME sound.

const FootstepSound = preload("res://src/audio/footstep_sound.gd")


func test_forest_biome_gets_the_forest_surface():
	assert_eq(FootstepSound.surface_for("forest", false, false), "forest")


func test_rainforest_shares_the_forest_surface_as_a_named_simplification():
	assert_eq(FootstepSound.surface_for("rainforest", false, false), "forest")


func test_grassland_biome_gets_the_grass_surface():
	assert_eq(FootstepSound.surface_for("grassland", false, false), "grass")


func test_desert_biome_gets_the_sand_surface():
	assert_eq(FootstepSound.surface_for("desert", false, false), "sand")


func test_tundra_and_mountain_biomes_get_the_rock_surface():
	assert_eq(FootstepSound.surface_for("tundra", false, false), "rock")
	assert_eq(FootstepSound.surface_for("mountain", false, false), "rock")


func test_an_unlisted_biome_falls_back_to_default_rather_than_silence():
	assert_eq(FootstepSound.surface_for("ocean", false, false), "default")


func test_snow_lying_wins_over_the_biome_surface():
	assert_eq(FootstepSound.surface_for("forest", true, false), "snow")


func test_underwater_wins_over_the_biome_surface_but_not_over_snow():
	assert_eq(FootstepSound.surface_for("grassland", false, true), "underwater")
	assert_eq(
		FootstepSound.surface_for("grassland", true, true), "snow",
		"mirrors EarthChunkManager.footstep_surface_for's own priority: snow checked first"
	)


func test_every_surface_key_resolves_to_a_real_non_empty_clip_path():
	for surface in ["grass", "forest", "snow", "underwater", "sand", "rock", "default"]:
		var path: String = FootstepSound.clip_path_for(surface)
		assert_true(path.begins_with("res://"), "%s should map to a real resource path" % surface)


func test_an_unknown_surface_falls_back_to_the_default_clip():
	assert_eq(FootstepSound.clip_path_for("lava"), FootstepSound.clip_path_for("default"))


## Reported live: "so river wading should be used for 'underwater walks'"
## -- a real, distinct water sound, not the same generic dry-land walking
## clip every other unsourced surface shares. Reuses river.ogg (the
## ambient river-proximity layer's own real flowing-water recording, see
## docs/concept/soundscape.md) rather than a second, separately-licensed
## file -- the same water, the same real reason to be heard, whether it's
## the continuous bed nearby or the one-shot underfoot when you're
## actually standing in it.
func test_underwater_gets_a_real_distinct_water_clip_not_the_default():
	var path := FootstepSound.clip_path_for("underwater")
	assert_ne(path, FootstepSound.clip_path_for("default"))
	assert_true(path.begins_with("res://"))


## No genuine mushroom-squish recording has been sourced yet (see
## MUSHROOM_CRUSH_CLIP_PATH's own doc comment for why forcing a mismatched
## stand-in would be worse than an honest gap) -- pinned as empty, not a
## nonexistent placeholder path, so a real future recording is a one-line
## change and callers can rely on the empty-string "not sourced yet"
## contract rather than a `load()` failure.
func test_mushroom_crush_is_honestly_empty_until_a_real_recording_is_sourced():
	assert_eq(FootstepSound.MUSHROOM_CRUSH_CLIP_PATH, "")
