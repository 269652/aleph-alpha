extends GutTest

## MushroomFlush (see docs/concept/mushrooms.md's "Where and when a flush
## happens"). Same shape as EarthwormPatch.surface_drive -- a real moisture
## term, the identical rain trigger earthworm surfacing already reads --
## but SEASON-weighted rather than cold-gated, since real temperate fungal
## fruiting is overwhelmingly an autumn event, not merely "not frozen".

const MushroomFlush = preload("res://src/world/mushroom_flush.gd")


func test_autumn_gives_the_strongest_flush_at_the_same_moisture():
	var autumn := MushroomFlush.flush_drive(0.8, "autumn")
	var spring := MushroomFlush.flush_drive(0.8, "spring")
	var summer := MushroomFlush.flush_drive(0.8, "summer")
	assert_gt(autumn, spring, "autumn should flush harder than spring at equal rain")
	assert_gt(autumn, summer, "autumn should flush harder than summer at equal rain")


func test_winter_never_flushes_however_wet():
	assert_eq(MushroomFlush.flush_drive(1.0, "winter"), 0.0)


func test_off_season_still_gives_a_small_residual_flush():
	# Real off-season fruitings do happen -- this should not be a hard zero
	# the way winter is, just much weaker than autumn.
	assert_gt(MushroomFlush.flush_drive(1.0, "spring"), 0.0)
	assert_gt(MushroomFlush.flush_drive(1.0, "summer"), 0.0)


func test_drier_ground_flushes_less_at_the_same_season():
	var wet := MushroomFlush.flush_drive(1.0, "autumn")
	var dry := MushroomFlush.flush_drive(0.1, "autumn")
	assert_gt(wet, dry)


func test_zero_moisture_never_flushes():
	assert_eq(MushroomFlush.flush_drive(0.0, "autumn"), 0.0)


func test_drive_is_always_a_unit_fraction():
	for season in ["spring", "summer", "autumn", "winter"]:
		for i in 11:
			var moisture := float(i) / 10.0
			var drive: float = MushroomFlush.flush_drive(moisture, season)
			assert_true(drive >= 0.0 and drive <= 1.0, "%s at moisture %s" % [season, moisture])


func test_an_unknown_season_behaves_like_the_small_off_season_residual():
	# A defensive fallback, not a real calendar state -- should read like
	# spring/summer's own small trickle: never autumn's full flush, and
	# never winter's hard zero.
	var unknown := MushroomFlush.flush_drive(1.0, "nonsense")
	var autumn := MushroomFlush.flush_drive(1.0, "autumn")
	assert_gt(unknown, 0.0)
	assert_lt(unknown, autumn)
