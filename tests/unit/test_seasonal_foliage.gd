extends GutTest

## SeasonalFoliage: what the season does to LIVING GREEN -- the ground cover,
## the tall grass, a root crop's tops. IllustratedTree already gives a TREE
## its season (four canopy frames, mapped by meaning); everything underneath
## it wore high summer all year, so forcing winter produced bare trees
## standing on a bright green lawn. Same clock, read by the flat green
## instead of by the crown.
##
## Every assertion here is about the colour a GRASSLAND TILE ends up wearing,
## not about the raw multiplier -- the multiplier is derived (target / summer
## base), so asserting on it would be asserting on arithmetic rather than on
## what a player actually sees.

const SeasonalFoliage = preload("res://src/rendering/seasonal_foliage.gd")
const SeasonTransition = preload("res://src/world/season_transition.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")
const ProceduralTerrainSprite = preload("res://src/rendering/procedural_terrain_sprite.gd")

## Biomes whose base colour is chlorophyll -- the ones a season must reach.
const GREEN_BIOMES := ["grassland", "forest", "rainforest"]
## Biomes a season must never touch: water, sand, rock, snow. One material
## covers the WHOLE terrain layer, so an ungated multiply would brown the sea.
const NON_GREEN_BIOMES := ["ocean", "desert", "mountain", "tundra"]

## The exact middle of each season's quarter. Settled, well clear of
## SeasonTransition's turn window (the last TURN_FRACTION of a season), and
## deliberately the true midpoints: mid-spring and mid-autumn are the two
## points SeasonCycle.warmth_modifier's cosine gives IDENTICAL warmth, which
## is the premise the spring-vs-autumn test rests on.
const MID_SPRING := 0.125
const MID_SUMMER := 0.375
const MID_AUTUMN := 0.625
const MID_WINTER := 0.875


## The colour a grassland tile actually renders at, at this point in the year.
func _grass_at(year_fraction: float) -> Color:
	var base: Color = ProceduralTerrainSprite.BASE_COLORS["grassland"]
	var tint := SeasonalFoliage.tint_at(year_fraction)
	return Color(base.r * tint.r, base.g * tint.g, base.b * tint.b)


func test_summer_is_the_identity_tint_so_todays_picture_is_unchanged():
	# The tint can only ever move the world AWAY from the picture that ships
	# today: high summer must stay pixel-for-pixel what it already was.
	var summer := SeasonalFoliage.tint_at(MID_SUMMER)
	assert_almost_eq(summer.r, 1.0, 0.0001)
	assert_almost_eq(summer.g, 1.0, 0.0001)
	assert_almost_eq(summer.b, 1.0, 0.0001)


func test_winter_grass_is_dead_thatch_not_a_dimmer_lawn():
	# Chlorophyll is gone, not merely darker: the drained colour must stop
	# being green-dominant and must lose most of its saturation.
	var summer := _grass_at(MID_SUMMER)
	var winter := _grass_at(MID_WINTER)
	assert_gte(winter.r, winter.g, "dead thatch is not green-dominant")
	assert_lt(winter.g, summer.g, "the green channel must actually drop")
	assert_gt(summer.s, 0.6, "the premise: summer turf is a saturated green")
	assert_lt(winter.s, 0.4, "winter must read washed-out, not just dim")


func test_autumn_grass_turns_gold_rather_than_simply_fading():
	# Chlorophyll breaks down first and the carotenoids underneath show
	# through, so a senescing meadow shifts toward yellow before it greys.
	var summer := _grass_at(MID_SUMMER)
	var autumn := _grass_at(MID_AUTUMN)
	assert_lt(autumn.h, summer.h, "the hue must swing toward yellow, not blue")
	assert_gt(autumn.r, summer.r, "gold needs the red carotenoids to come up")
	assert_gt(autumn.g, autumn.b, "gold, not olive-grey")
	assert_gt(autumn.s, 0.3, "autumn is a colour, not a wash-out -- that is winter")


func test_spring_and_autumn_differ_even_though_their_warmth_is_the_same():
	# SeasonCycle.warmth_modifier is a cosine: mid-spring and mid-autumn sit
	# at the same warmth by construction, which is exactly why this reads
	# SeasonTransition's season NAMES instead of the warmth curve. Warmth
	# alone cannot tell a greening year from a dying one.
	var cycle := SeasonCycle.new()
	var spring_warmth := cycle.warmth_modifier(MID_SPRING * SeasonCycle.SECONDS_PER_YEAR)
	var autumn_warmth := cycle.warmth_modifier(MID_AUTUMN * SeasonCycle.SECONDS_PER_YEAR)
	assert_almost_eq(spring_warmth, autumn_warmth, 0.05, "the premise: same warmth")

	var spring := _grass_at(MID_SPRING)
	var autumn := _grass_at(MID_AUTUMN)
	assert_gt(spring.g - autumn.g, 0.15, "spring is new growth, autumn is dying back")
	assert_lt(autumn.h, spring.h, "autumn sits yellower round the wheel than spring")


func test_spring_growth_is_brighter_and_greener_than_mature_summer_turf():
	var summer := _grass_at(MID_SUMMER)
	var spring := _grass_at(MID_SPRING)
	assert_gt(spring.v, summer.v, "new growth is lighter than mature turf")
	assert_gt(spring.g, summer.g)


func test_the_tint_blends_across_a_season_turn_on_the_same_transition_the_canopies_use():
	# Inside summer's own turn window: the lawn and the crown above it must
	# never disagree about what month it is, so this rides SeasonTransition
	# rather than inventing a second blend.
	var turning := 0.45
	var state := SeasonTransition.state_at(turning)
	assert_eq(state.from, "summer", "the premise: this year_fraction is mid-turn")
	assert_eq(state.to, "autumn")
	assert_gt(state.progress, 0.0)
	assert_lt(state.progress, 1.0)

	var blended := SeasonalFoliage.tint_at(turning)
	var summer := SeasonalFoliage.tint_at(MID_SUMMER)
	var autumn := SeasonalFoliage.tint_at(MID_AUTUMN)
	assert_gt(blended.r, summer.r, "already past pure summer")
	assert_lt(blended.r, autumn.r, "not yet fully autumn")

	var expected: Color = summer.lerp(autumn, state.progress)
	assert_almost_eq(blended.r, expected.r, 0.0001)
	assert_almost_eq(blended.g, expected.g, 0.0001)
	assert_almost_eq(blended.b, expected.b, 0.0001)


func test_greenness_gain_covers_every_green_biome_and_no_other():
	# Measured against the real palette rather than eyeballed (CLAUDE.md):
	# GREENNESS_GAIN is set by the LEAST green of the green biomes
	# (rainforest), and every non-green biome must score exactly zero.
	for biome in GREEN_BIOMES:
		var color: Color = ProceduralTerrainSprite.BASE_COLORS[biome]
		assert_gte(
			SeasonalFoliage.greenness_of(color), 0.85,
			"%s must take nearly the whole season tint" % biome
		)
	for biome in NON_GREEN_BIOMES:
		var color: Color = ProceduralTerrainSprite.BASE_COLORS[biome]
		assert_eq(
			SeasonalFoliage.greenness_of(color), 0.0,
			"%s is not chlorophyll and must never take the season" % biome
		)


func test_greenness_is_clamped_to_a_usable_zero_to_one_mix_weight():
	assert_eq(SeasonalFoliage.greenness_of(Color(0.0, 1.0, 0.0)), 1.0)
	assert_eq(SeasonalFoliage.greenness_of(Color(1.0, 0.0, 1.0)), 0.0)
	assert_eq(SeasonalFoliage.greenness_of(Color(0.5, 0.5, 0.5)), 0.0)


func test_an_unknown_season_falls_back_to_summer_rather_than_crashing():
	# Same reason IllustratedTree falls back to summer: unexpectedly green is
	# a lawn, unexpectedly brown reads as dead ground.
	assert_eq(SeasonalFoliage.tint_for_season("harvest"), Color(1.0, 1.0, 1.0))
	assert_eq(SeasonalFoliage.tint_for_season(""), Color(1.0, 1.0, 1.0))


func test_the_world_clock_convenience_agrees_with_the_year_fraction_one():
	# Callers hold raw elapsed seconds (EarthChunkManager.world_age_seconds),
	# not a year fraction -- the two entry points must never diverge.
	var elapsed := MID_WINTER * SeasonCycle.SECONDS_PER_YEAR
	var from_clock := SeasonalFoliage.tint_for_world_age(elapsed)
	var from_fraction := SeasonalFoliage.tint_at(MID_WINTER)
	assert_almost_eq(from_clock.r, from_fraction.r, 0.0001)
	assert_almost_eq(from_clock.g, from_fraction.g, 0.0001)
	assert_almost_eq(from_clock.b, from_fraction.b, 0.0001)


func test_every_season_the_cycle_can_report_has_a_grass_colour_of_its_own():
	for season in SeasonCycle.SEASONS:
		assert_true(
			SeasonalFoliage.GRASSLAND_BY_SEASON.has(season),
			"%s has no grass colour, so it would silently render as summer" % season
		)


func test_the_summer_reference_is_the_shipped_grassland_colour_itself():
	# This is WHY summer is the identity tint rather than a tuned 1.0: the
	# multiplier is target/summer, and summer's target is the palette entry.
	assert_eq(
		SeasonalFoliage.GRASSLAND_BY_SEASON["summer"],
		ProceduralTerrainSprite.BASE_COLORS["grassland"]
	)
