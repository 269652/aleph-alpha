extends GutTest

## Per-chunk earthworm population (see docs/concept/soil_fauna.md).
##
## Same per-chunk patch-sim contract as TallGrass/FlowerPatch/DesertScrub/
## TundraLichen -- deterministic PixelNoise-seeded placement, a hard cap,
## advance(delta), and a pure bool consumption method. What is different is
## that a worm is never created or destroyed by the weather: the BURROWS are
## permanent, and what changes is how close to the surface the worm in each
## one is.

const EarthwormPatch = preload("res://src/world/earthworm_patch.gd")
const TallGrass = preload("res://src/world/tall_grass.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")
const WeatherModel = preload("res://src/world/weather_model.gd")

const SIZE := 32


func _biome(name: String, size: int = SIZE) -> PackedStringArray:
	var out := PackedStringArray()
	for i in size * size:
		out.append(name)
	return out


func _patch(biome_name: String = "grassland", seed_value: int = 1234) -> EarthwormPatch:
	return EarthwormPatch.new(seed_value, SIZE, SIZE, _biome(biome_name))


## Brings every worm this patch is willing to surface all the way up.
func _settle(patch: EarthwormPatch, seconds: float = 10.0) -> void:
	var step := 0.1
	var elapsed := 0.0
	while elapsed < seconds:
		patch.advance(step)
		elapsed += step


func _surfaced_count(patch: EarthwormPatch) -> int:
	var count := 0
	for cell in patch.worm_cells():
		if patch.is_surfaced(cell):
			count += 1
	return count


# -- placement --------------------------------------------------------------

func test_seeds_burrows_in_soil_bearing_biomes():
	for biome_name in ["grassland", "forest", "rainforest"]:
		var patch := _patch(biome_name)
		assert_gt(patch.worm_cells().size(), 0, "%s has soil, so it has worms" % biome_name)


## Ocean has no soil, desert no moisture, tundra permafrost (the real boreal
## earthworm-free zone) -- mirrors AmbientFlyerRenderer.BIRD_BIOMES.
func test_seeds_no_burrows_in_soilless_biomes():
	for biome_name in ["ocean", "desert", "tundra", "mountain"]:
		var patch := _patch(biome_name)
		assert_eq(patch.worm_cells().size(), 0, "%s should have no earthworms" % biome_name)


func test_is_deterministic_for_the_same_seed():
	var a := _patch("grassland", 99)
	var b := _patch("grassland", 99)
	assert_eq(a.worm_cells(), b.worm_cells())


func test_different_seeds_give_different_layouts():
	var a := _patch("grassland", 1)
	var b := _patch("grassland", 2)
	assert_ne(a.worm_cells(), b.worm_cells())


func test_never_exceeds_the_per_chunk_cap():
	for seed_value in range(12):
		var patch := _patch("grassland", seed_value * 7717)
		assert_lte(patch.worm_cells().size(), EarthwormPatch.MAX_WORMS)


## Worms are sparser than tall grass: a chunk of lawn is not wall-to-wall
## worm casts. Pinned as an ordering rather than eyeballed in a comment.
func test_burrows_are_sparser_than_tall_grass_patches():
	assert_lt(EarthwormPatch.SEED_CHANCE, TallGrass.SEED_CHANCE)


func test_has_burrow_only_where_one_was_seeded():
	var patch := _patch()
	for cell in patch.worm_cells():
		assert_true(patch.has_burrow(cell))
	assert_false(patch.has_burrow(Vector2i(-1, -1)))


## The clustering bug this project has hit five times: Godot's string hash
## correlates neighbouring cells, so a seeded value can freeze into a single
## bucket. Every burrow's reluctance must actually spread across the unit
## range, not pile into one corner of it.
func test_per_burrow_reluctance_spreads_across_the_unit_range():
	var patch := _patch()
	var low := 0
	var high := 0
	for cell in patch.worm_cells():
		var reluctance := patch.reluctance_at(cell)
		assert_between(reluctance, 0.0, 1.0)
		if reluctance < 0.5:
			low += 1
		else:
			high += 1
	assert_gt(low, 0, "some worms should be eager to surface")
	assert_gt(high, 0, "some worms should be reluctant to surface")


# -- the surfacing drive ----------------------------------------------------
#
# A pure, tested function of two live world inputs (weather moisture and
# climate x season warmth), not a hand-tuned literal.

func test_wet_soil_drives_more_surfacing_than_dry_soil():
	assert_lt(
		EarthwormPatch.surface_drive(0.2, 1.0), EarthwormPatch.surface_drive(0.9, 1.0)
	)


## Frozen ground: worms move deep and go dormant regardless of how wet it is.
func test_frozen_ground_suppresses_surfacing_however_wet_it_is():
	assert_almost_eq(EarthwormPatch.surface_drive(1.0, 0.0), 0.0, 0.0001)


func test_warmth_raises_the_drive_up_to_mild_then_stops_mattering():
	var cold := EarthwormPatch.surface_drive(1.0, EarthwormPatch.COLD_CUTOFF)
	var middling := EarthwormPatch.surface_drive(
		1.0, (EarthwormPatch.COLD_CUTOFF + EarthwormPatch.MILD_WARMTH) * 0.5
	)
	var mild := EarthwormPatch.surface_drive(1.0, EarthwormPatch.MILD_WARMTH)
	var hot := EarthwormPatch.surface_drive(1.0, 1.0)
	assert_lt(cold, middling)
	assert_lt(middling, mild)
	assert_almost_eq(mild, hot, 0.0001, "past mild, temperature no longer limits")


func test_the_drive_stays_in_unit_range():
	for moisture in [0.0, 0.25, 0.5, 1.0]:
		for warmth in [0.0, 0.1, 0.5, 1.0]:
			assert_between(EarthwormPatch.surface_drive(moisture, warmth), 0.0, 1.0)


# -- surfacing over time ----------------------------------------------------

func test_worms_start_below_the_surface():
	var patch := _patch()
	assert_eq(_surfaced_count(patch), 0, "a freshly loaded chunk starts with worms underground")


func test_soaked_mild_ground_brings_worms_up():
	var patch := _patch()
	patch.set_conditions(1.0, 1.0)
	_settle(patch)
	assert_eq(
		_surfaced_count(patch), patch.worm_cells().size(),
		"a soaked, mild chunk should have every worm at the surface"
	)


## The graded response that makes drizzle different from a downpour: at a
## middling drive only the eager worms come up, because each burrow has its
## own reluctance.
func test_damp_ground_surfaces_some_worms_but_not_all():
	var patch := _patch()
	patch.set_conditions(0.5, 1.0)
	_settle(patch)
	var surfaced := _surfaced_count(patch)
	assert_gt(surfaced, 0, "damp ground should bring some worms up")
	assert_lt(surfaced, patch.worm_cells().size(), "damp is not a downpour")


func test_wetter_ground_surfaces_more_worms_than_drier_ground():
	var damp := _patch()
	damp.set_conditions(0.35, 1.0)
	_settle(damp)
	var soaked := _patch()
	soaked.set_conditions(1.0, 1.0)
	_settle(soaked)
	assert_lt(_surfaced_count(damp), _surfaced_count(soaked))


func test_worms_retreat_when_the_ground_freezes():
	var patch := _patch()
	patch.set_conditions(1.0, 1.0)
	_settle(patch)
	assert_gt(_surfaced_count(patch), 0)
	patch.set_conditions(1.0, 0.0)
	_settle(patch)
	assert_eq(_surfaced_count(patch), 0, "a frost should send every worm back down")


func test_surfacing_stays_in_unit_range():
	var patch := _patch()
	patch.set_conditions(1.0, 1.0)
	_settle(patch, 60.0)
	for cell in patch.worm_cells():
		assert_between(patch.surfacing_at(cell), 0.0, 1.0)


## Worms visibly emerge rather than popping into existence -- the sprite
## layer keys off is_surfaced, so an instant snap would flicker them in.
func test_a_worm_takes_time_to_reach_the_surface():
	var patch := _patch()
	patch.set_conditions(1.0, 1.0)
	patch.advance(0.05)
	assert_eq(_surfaced_count(patch), 0, "a worm should not surface within a single frame")


# -- predation --------------------------------------------------------------

func test_taking_a_worm_that_is_not_up_fails():
	var patch := _patch()
	var cell: Vector2i = patch.worm_cells()[0]
	assert_false(patch.take(cell), "nothing to take while the worm is underground")


func test_taking_an_empty_cell_fails():
	var patch := _patch()
	assert_false(patch.take(Vector2i(-5, -5)))


func test_taking_a_surfaced_worm_succeeds_and_removes_it():
	var patch := _patch()
	patch.set_conditions(1.0, 1.0)
	_settle(patch)
	var cell: Vector2i = patch.worm_cells()[0]
	assert_true(patch.is_surfaced(cell))
	assert_true(patch.take(cell), "a surfaced worm can be taken")
	assert_false(patch.is_surfaced(cell), "the worm is gone once eaten")


## Without a recovery interval a robin could stand on one burrow and eat the
## same worm forever. Another worm has to move in first.
func test_an_eaten_burrow_stays_empty_for_a_while_even_in_ideal_conditions():
	var patch := _patch()
	patch.set_conditions(1.0, 1.0)
	_settle(patch)
	var cell: Vector2i = patch.worm_cells()[0]
	patch.take(cell)
	_settle(patch, EarthwormPatch.RECOVERY_SECONDS * 0.5)
	assert_false(patch.is_surfaced(cell), "the burrow should still be recovering")
	assert_false(patch.take(cell))


func test_an_eaten_burrow_is_repopulated_eventually():
	var patch := _patch()
	patch.set_conditions(1.0, 1.0)
	_settle(patch)
	var cell: Vector2i = patch.worm_cells()[0]
	patch.take(cell)
	_settle(patch, EarthwormPatch.RECOVERY_SECONDS * 2.0)
	assert_true(patch.is_surfaced(cell), "a new worm should occupy the burrow eventually")


# -- crushed underfoot: weight-emergent worm mortality (see docs/concept/
# soil_fauna.md's own section by that name) --------------------------------

## The real, tested boundary this whole mechanic exists to draw: a mouse's
## own momentum (see CreatureMass/PebbleDispersion.FOOTSTEP_SPEED_MPS)
## must fall under the threshold, and a horse's/player's own must clear
## it -- computed here from the SAME real numbers the live game actually
## uses, not invented test-only figures.
func test_is_crushed_by_spares_a_mouses_own_real_momentum():
	const CreatureMass = preload("res://src/world/creature_mass.gd")
	const PebbleDispersion = preload("res://src/rendering/pebble_dispersion.gd")
	var mouse_momentum: float = CreatureMass.mass_kg_for("mouse") * PebbleDispersion.FOOTSTEP_SPEED_MPS
	assert_false(EarthwormPatch.is_crushed_by(mouse_momentum))


func test_is_crushed_by_kills_under_a_horses_own_real_momentum():
	const CreatureMass = preload("res://src/world/creature_mass.gd")
	const PebbleDispersion = preload("res://src/rendering/pebble_dispersion.gd")
	var horse_momentum: float = CreatureMass.mass_kg_for("horse") * PebbleDispersion.FOOTSTEP_SPEED_MPS
	assert_true(EarthwormPatch.is_crushed_by(horse_momentum))


## The calibration example given directly: a light creature's step spares
## a worm, a heavy one's kills it. No frog exists in this game (see the
## concept doc's own note) -- mouse/squirrel stand in for it here.
func test_is_crushed_by_spares_small_creatures_and_kills_under_large_ones():
	const CreatureMass = preload("res://src/world/creature_mass.gd")
	const PebbleDispersion = preload("res://src/rendering/pebble_dispersion.gd")
	for species in ["mouse", "squirrel"]:
		var momentum: float = CreatureMass.mass_kg_for(species) * PebbleDispersion.FOOTSTEP_SPEED_MPS
		assert_false(EarthwormPatch.is_crushed_by(momentum), "%s should spare a worm" % species)
	for species in ["horse", "boar", "deer", "bear"]:
		var momentum: float = CreatureMass.mass_kg_for(species) * PebbleDispersion.FOOTSTEP_SPEED_MPS
		assert_true(EarthwormPatch.is_crushed_by(momentum), "%s should crush a worm" % species)


func test_is_crushed_by_is_never_true_at_zero_momentum():
	assert_false(EarthwormPatch.is_crushed_by(0.0))


func test_crush_below_threshold_leaves_a_surfaced_worm_untouched():
	var patch := _patch()
	patch.set_conditions(1.0, 1.0)
	_settle(patch)
	var cell: Vector2i = patch.worm_cells()[0]
	assert_false(patch.crush(cell, 0.01), "momentum this small should not crush anything")
	assert_true(patch.is_surfaced(cell), "the worm should still be there")


func test_crush_above_threshold_kills_a_surfaced_worm():
	var patch := _patch()
	patch.set_conditions(1.0, 1.0)
	_settle(patch)
	var cell: Vector2i = patch.worm_cells()[0]
	assert_true(patch.crush(cell, EarthwormPatch.CRUSH_MOMENTUM_THRESHOLD_KG_M_S * 10.0))
	assert_false(patch.is_surfaced(cell), "the worm should be gone once crushed")


## A burrowed worm has no exposed body to step on -- crush honors the
## identical is_surfaced gate take() already does.
func test_crush_fails_on_a_worm_that_is_not_up_even_at_huge_momentum():
	var patch := _patch()
	var cell: Vector2i = patch.worm_cells()[0]
	assert_false(patch.crush(cell, 1000000.0))


## Crushing recovers on the identical clock as being eaten -- the burrow
## itself is not destroyed, only whatever worm was in it at the time.
func test_a_crushed_burrow_is_repopulated_on_the_same_clock_as_an_eaten_one():
	var patch := _patch()
	patch.set_conditions(1.0, 1.0)
	_settle(patch)
	var cell: Vector2i = patch.worm_cells()[0]
	patch.crush(cell, EarthwormPatch.CRUSH_MOMENTUM_THRESHOLD_KG_M_S * 10.0)
	_settle(patch, EarthwormPatch.RECOVERY_SECONDS * 2.0)
	assert_true(patch.is_surfaced(cell), "a new worm should occupy the burrow eventually")


## Eating one worm must not empty the whole lawn -- a robin's feeding
## territory is a renewable resource.
func test_taking_one_worm_leaves_the_rest_alone():
	var patch := _patch()
	patch.set_conditions(1.0, 1.0)
	_settle(patch)
	var before := _surfaced_count(patch)
	patch.take(patch.worm_cells()[0])
	assert_eq(_surfaced_count(patch), before - 1)


# -- soil temperature -------------------------------------------------------
#
# EarthChunkManager._warmth_at_pixel (climate x SeasonCycle.warmth_modifier)
# is the right figure for FRUITING, where a zero ripening rate in winter is
# exactly correct. As a SOIL temperature it is not: warmth_modifier troughs at
# exactly 0.0 mid-winter, which would freeze the rainforest and put the whole
# planet under COLD_CUTOFF for a quarter of every year -- and it is already
# under the cutoff at world start, since spring's modifier is only ~0.15.

func test_soil_warmth_tracks_the_underlying_climate():
	assert_lt(
		EarthwormPatch.soil_warmth(0.2, 1.0), EarthwormPatch.soil_warmth(0.9, 1.0)
	)


func test_winter_cools_the_soil_without_freezing_it():
	var summer := EarthwormPatch.soil_warmth(0.7, 1.0)
	var winter := EarthwormPatch.soil_warmth(0.7, 0.0)
	assert_lt(winter, summer, "winter soil is colder")
	assert_gt(winter, 0.0, "a warm climate does not freeze in winter")


## Regression on the exact number the live game starts at: spring's season
## warmth is only ~0.15, so a naive climate x season product would leave a
## temperate chunk below COLD_CUTOFF and the player would see no worms at all
## on a fresh world.
func test_a_temperate_chunk_in_spring_is_above_the_cold_cutoff():
	const SPRING_SEASON_WARMTH := 0.146
	const TEMPERATE_CLIMATE := 0.6
	assert_gt(
		EarthwormPatch.soil_warmth(TEMPERATE_CLIMATE, SPRING_SEASON_WARMTH),
		EarthwormPatch.COLD_CUTOFF,
		"a fresh temperate world must have worms, not frozen ground"
	)


func test_a_frozen_climate_stays_below_the_cold_cutoff_all_year():
	for season_warmth in [0.0, 0.5, 1.0]:
		assert_lt(EarthwormPatch.soil_warmth(0.05, season_warmth), EarthwormPatch.COLD_CUTOFF)


func test_soil_warmth_stays_in_unit_range():
	for climate in [0.0, 0.3, 1.0]:
		for season_warmth in [0.0, 0.5, 1.0]:
			assert_between(EarthwormPatch.soil_warmth(climate, season_warmth), 0.0, 1.0)


# -- calibration against the REAL world the player starts in ----------------
#
# The gate constants were tuned against an assumed warmth scale that the
# actual soil_warmth output never reaches at temperate latitudes. Measured at
# the game's own spawn point (Berlin, climate temperature 0.413) in the
# season the world STARTS in (spring): the surfacing drive topped out at 0.48
# in a storm and 0.41 in rain, against SURFACED_THRESHOLD of 0.6. So a worm
# could never surface there in ANY weather -- reported as "I can't see any
# worms or birds eating worms", and it was never observable, because the
# whole mechanic was gated off for the entire early game.
#
# These pin the intended behaviour instead of the numbers: worms come up when
# it RAINS, from spring onward, and stay down in dry weather and in winter.

## The spawn point's real climate temperature, measured from
## EarthChunkGenerator rather than assumed -- if worldgen shifts, this test
## should be re-measured rather than quietly drifting.
const BERLIN_CLIMATE := 0.413


func _drive_at(climate: float, season_warmth: float, moisture: float) -> float:
	return EarthwormPatch.surface_drive(
		moisture, EarthwormPatch.soil_warmth(climate, season_warmth)
	)


## SPRING, the season the world starts in, is the case that was completely
## dead.
func test_rain_surfaces_worms_in_spring_at_the_spawn_climate():
	var spring := SeasonCycle.new().warmth_modifier(0.0)
	assert_gt(
		_drive_at(BERLIN_CLIMATE, spring, WeatherModel.new().soil_moisture("rain")),
		EarthwormPatch.SURFACED_THRESHOLD,
		"spring rain is the classic worms-on-the-surface case; it must actually work"
	)


func test_dry_weather_keeps_worms_down_in_spring():
	var spring := SeasonCycle.new().warmth_modifier(0.0)
	var wm := WeatherModel.new()
	for dry in ["clear", "cloudy"]:
		assert_lt(
			_drive_at(BERLIN_CLIMATE, spring, wm.soil_moisture(dry)),
			EarthwormPatch.SURFACED_THRESHOLD,
			"%s ground should stay quiet -- worms surface for rain, not for daylight" % dry
		)


func test_rain_still_surfaces_worms_in_summer():
	var summer := SeasonCycle.new().warmth_modifier(SeasonCycle.SECONDS_PER_YEAR * 0.375)
	assert_gt(
		_drive_at(BERLIN_CLIMATE, summer, WeatherModel.new().soil_moisture("rain")),
		EarthwormPatch.SURFACED_THRESHOLD
	)


## ...but cold ground still suppresses them, which is the whole point of the
## cold gate: winter rain falls on ground too cold to be worth coming up for.
func test_winter_rain_does_not_surface_worms():
	var winter := SeasonCycle.new().warmth_modifier(SeasonCycle.SECONDS_PER_YEAR * 0.875)
	assert_lt(
		_drive_at(BERLIN_CLIMATE, winter, WeatherModel.new().soil_moisture("rain")),
		EarthwormPatch.SURFACED_THRESHOLD,
		"cold ground keeps them down even when it is wet"
	)


# -- crawl: a surfaced worm inches along ------------------------------------
#
# A worm at the surface is not a decal: it crawls, slowly. Kept as a sub-tile
# offset rather than a change of cell, because the cell IS the worm's
# identity everywhere else (worm_cells/is_surfaced/take, and the bird's own
# targeting) -- a worm that changed cells mid-approach would have a robin
# pecking where it used to be.

func test_crawl_offset_stays_within_its_own_tile():
	for seed_value in [1, 77, 4242]:
		for step in 60:
			var offset := EarthwormPatch.crawl_offset(seed_value, float(step) * 0.7)
			assert_lte(
				offset.length(), EarthwormPatch.CRAWL_RADIUS_PX + 0.001,
				"a crawling worm must not wander off its own cell"
			)


func test_a_worm_actually_moves_over_time():
	var early := EarthwormPatch.crawl_offset(9, 0.0)
	var later := EarthwormPatch.crawl_offset(9, 6.0)
	assert_gt(early.distance_to(later), 0.5, "it should visibly have inched along")


## Slowly: a worm covers its whole crawl range over seconds, not in a frame.
## Pinned as a rate so "slowly" is a tested property rather than a comment.
func test_a_worm_crawls_slowly():
	var moved := EarthwormPatch.crawl_offset(3, 0.0).distance_to(
		EarthwormPatch.crawl_offset(3, 1.0 / 60.0)
	)
	assert_lt(moved, 0.35, "a single frame of crawl should be a creep, not a dart")


## Deterministic, like everything else in this sim: the same worm at the same
## moment is in the same place, so a reloaded chunk looks identical.
func test_crawl_is_deterministic():
	assert_eq(EarthwormPatch.crawl_offset(5, 2.5), EarthwormPatch.crawl_offset(5, 2.5))


## Two worms side by side must not crawl in lockstep, which would read as a
## grid of clones rather than as animals.
func test_different_worms_crawl_differently():
	assert_ne(EarthwormPatch.crawl_offset(1, 3.0), EarthwormPatch.crawl_offset(2, 3.0))


# -- crawling out, and back down ---------------------------------------------

## A worm crawls out of the earth rather than appearing on top of it.
##
## The sprite was created at full size the moment the worm counted as surfaced
## and freed the moment it stopped, so worms blinked in and out of existence.
## The model already tracked how far up a worm was; only the drawing ignored
## it.
func test_a_worm_emerges_gradually_rather_than_all_at_once():
	var seen := {}
	var surfacing := EarthwormPatch.SURFACED_THRESHOLD
	while surfacing <= 1.0:
		seen[snappedf(EarthwormPatch.emergence_for(surfacing), 0.05)] = true
		surfacing += 0.02
	assert_gt(seen.size(), 3, "a worm should appear in stages, not in one step")


## Fully up when fully surfaced, and nothing showing at the threshold -- so a
## worm's first frame is its nose, not its whole body.
func test_a_worm_is_all_the_way_out_only_when_fully_surfaced():
	assert_almost_eq(EarthwormPatch.emergence_for(1.0), 1.0, 0.001)
	assert_lt(
		EarthwormPatch.emergence_for(EarthwormPatch.SURFACED_THRESHOLD), 0.2,
		"a worm should start as barely a nose above the soil"
	)


## Emergence never runs backwards as a worm rises, and never exceeds itself.
func test_emergence_rises_with_surfacing():
	var previous := -1.0
	var surfacing := 0.0
	while surfacing <= 1.0:
		var emerged := EarthwormPatch.emergence_for(surfacing)
		assert_gte(emerged, previous, "emergence went backwards at %.2f" % surfacing)
		assert_between(emerged, 0.0, 1.0, "emergence out of range at %.2f" % surfacing)
		previous = emerged
		surfacing += 0.05


## Below the surfacing threshold a worm is still underground and shows
## nothing -- the same line the gameplay uses, so a bird can never see a worm
## it cannot take.
func test_a_worm_below_the_threshold_shows_nothing():
	assert_eq(EarthwormPatch.emergence_for(0.0), 0.0)
	assert_eq(EarthwormPatch.emergence_for(EarthwormPatch.SURFACED_THRESHOLD - 0.01), 0.0)


# -- illustrated worm sprite: corpse state (see docs/concept/soil_fauna.md's
# "Illustrated worm sprite: crawl, emerge, retreat, die" -> "A corpse is
# new ground") ---------------------------------------------------------

## A crushed worm becomes a corpse -- distinct from simply having been
## eaten, so the sprite layer can tell "play the die animation and hold
## it" apart from "just disappear", which take() still does.
func test_crushing_a_worm_makes_it_a_corpse():
	var patch := _patch()
	patch.set_conditions(1.0, 1.0)
	_settle(patch)
	var cell: Vector2i = patch.worm_cells()[0]
	assert_false(patch.is_corpse(cell), "nothing has died yet")
	patch.crush(cell, EarthwormPatch.CRUSH_MOMENTUM_THRESHOLD_KG_M_S * 10.0)
	assert_true(patch.is_corpse(cell), "a crushed worm should leave a corpse")


## Eating a worm must NOT leave a corpse -- only crushing does. take() and
## crush() reduce the model to the identical surfacing/recovery state;
## this is the one bit that actually distinguishes them afterward.
func test_eating_a_worm_leaves_no_corpse():
	var patch := _patch()
	patch.set_conditions(1.0, 1.0)
	_settle(patch)
	var cell: Vector2i = patch.worm_cells()[0]
	patch.take(cell)
	assert_false(patch.is_corpse(cell), "an eaten worm is not a corpse")


## A corpse rides the identical RECOVERY_SECONDS clock as ordinary
## recovery -- it clears the instant a new worm could occupy the burrow
## again, not on a second, independent timer.
func test_a_corpse_clears_when_its_burrow_recovers():
	var patch := _patch()
	patch.set_conditions(1.0, 1.0)
	_settle(patch)
	var cell: Vector2i = patch.worm_cells()[0]
	patch.crush(cell, EarthwormPatch.CRUSH_MOMENTUM_THRESHOLD_KG_M_S * 10.0)
	_settle(patch, EarthwormPatch.RECOVERY_SECONDS * 2.0)
	assert_false(patch.is_corpse(cell), "the corpse should be long gone by the time a new worm surfaces")


## corpse_age_seconds starts at zero right when a worm is crushed, and
## rises as time passes -- the signal the sprite layer indexes the die
## row's 8 frames by.
func test_corpse_age_rises_from_zero():
	var patch := _patch()
	patch.set_conditions(1.0, 1.0)
	_settle(patch)
	var cell: Vector2i = patch.worm_cells()[0]
	patch.crush(cell, EarthwormPatch.CRUSH_MOMENTUM_THRESHOLD_KG_M_S * 10.0)
	assert_almost_eq(patch.corpse_age_seconds(cell), 0.0, 0.01)
	patch.advance(5.0)
	assert_almost_eq(patch.corpse_age_seconds(cell), 5.0, 0.01)


## corpse_age_seconds is meaningless for a cell that never died -- zero
## rather than a stale/undefined value, the same "harmless default" shape
## surfacing_at/reluctance_at already use for a cell nobody has asked
## about yet.
func test_corpse_age_is_zero_for_a_cell_that_never_died():
	var patch := _patch()
	var cell: Vector2i = patch.worm_cells()[0]
	assert_eq(patch.corpse_age_seconds(cell), 0.0)


# -- illustrated worm sprite: direction (see docs/concept/soil_fauna.md's
# "Direction, not just amount") ------------------------------------------

## Before anything has ever advanced, a fresh burrow defaults to "not
## rising" -- a harmless default, the same shape every other per-cell
## query in this file already uses for a cell nobody has asked about yet.
func test_is_rising_defaults_to_false_before_any_advance():
	var patch := _patch()
	var cell: Vector2i = patch.worm_cells()[0]
	assert_false(patch.is_rising(cell))


## While the environment is actively pushing a worm up, is_rising is true.
func test_is_rising_while_surfacing_climbs():
	var patch := _patch()
	patch.set_conditions(1.0, 1.0)
	var cell: Vector2i = patch.worm_cells()[0]
	patch.advance(0.1)
	assert_true(patch.is_rising(cell), "full drive should be pulling this worm up")


## The same worm, once conditions reverse, is falling instead -- advance()
## already computes exactly this comparison internally (target vs level)
## to decide which way to move surfacing; this is that same decision,
## recorded rather than thrown away.
func test_is_rising_turns_false_once_conditions_reverse():
	var patch := _patch()
	patch.set_conditions(1.0, 1.0)
	var cell: Vector2i = patch.worm_cells()[0]
	patch.advance(0.1)
	assert_true(patch.is_rising(cell), "climbing toward full drive")
	patch.set_conditions(0.0, 1.0)
	patch.advance(0.1)
	assert_false(patch.is_rising(cell), "dry conditions should now be pulling it back down")
