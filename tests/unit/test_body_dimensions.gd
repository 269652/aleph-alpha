extends GutTest

## Red-first spec for body_dimensions.gd -- docs/concept/capture_dsl.md's
## "Mesh physics": the three principal body extents (length, breadth, depth,
## in millimetres) of every species a net might meet, each a published
## figure, so what a mesh holds can be read off a body instead of a species
## list. The length is pinned equal to the one wingbeat_bounce.gd already
## flies on, so the two tables can never disagree about how long a monarch is.

const BodyDimensions = preload("res://src/gameplay/body_dimensions.gd")
const WingbeatBounce = preload("res://src/rendering/wingbeat_bounce.gd")
const AmbientFlyerRenderer = preload("res://src/rendering/ambient_flyer_renderer.gd")
const FishRenderer = preload("res://src/rendering/fish_renderer.gd")


# --- coverage: every species a net can meet is measured ------------------------

func test_every_ambient_flyer_species_is_measured():
	for species in AmbientFlyerRenderer.BUTTERFLY_SPECIES_POOL + AmbientFlyerRenderer.BIRD_SPECIES_POOL:
		assert_true(BodyDimensions.has(species), species)
	assert_true(BodyDimensions.has("fly"), "flies swarm as ambient flyers too")


func test_every_fish_species_is_measured():
	for species in FishRenderer.SPECIES_POOL:
		assert_true(BodyDimensions.has(species), species)


func test_an_unmeasured_species_has_no_extents():
	assert_false(BodyDimensions.has("dragon"))
	assert_eq(BodyDimensions.extents_mm("dragon"), [])
	assert_eq(BodyDimensions.largest_mm("dragon"), 0.0)
	assert_eq(BodyDimensions.middle_mm("dragon"), 0.0)


# --- the figures are real, and positive, and consistent with what flies -----

func test_every_extent_is_positive():
	for species in BodyDimensions.known_ids():
		for value in BodyDimensions.extents_mm(species):
			assert_gt(float(value), 0.0, species)


func test_the_length_is_the_length_the_wingbeat_model_already_flies_on():
	# One monarch, two tables, one number: WingbeatBounce.FLIGHT carries
	# body_length_m for every flyer; this table's length_mm must be that
	# figure in millimetres for every species both know.
	for species in WingbeatBounce.FLIGHT:
		if not BodyDimensions.has(species):
			continue
		assert_almost_eq(
			BodyDimensions.length_mm(species),
			float(WingbeatBounce.FLIGHT[species]["body_length_m"]) * 1000.0, 1e-6, species
		)


func test_extents_come_back_sorted_largest_first():
	for species in BodyDimensions.known_ids():
		var extents: Array = BodyDimensions.extents_mm(species)
		assert_eq(extents.size(), 3, species)
		assert_true(extents[0] >= extents[1] and extents[1] >= extents[2], "%s: %s" % [species, extents])
		assert_eq(BodyDimensions.largest_mm(species), extents[0], species)
		assert_eq(BodyDimensions.middle_mm(species), extents[1], species)


# --- the specific bodies the concept doc's verdict table rests on -------------

func test_a_honeybee_worker_is_a_thirteen_by_six_millimetre_body():
	assert_eq(BodyDimensions.extents_mm("bee"), [13.0, 6.0, 5.0])


func test_a_housefly_is_smaller_still():
	assert_eq(BodyDimensions.extents_mm("fly"), [7.0, 3.0, 3.0])


func test_a_monarch_stands_taller_folded_than_its_body_is_long():
	# Wings fold dorsally: the folded pair stands nearly half a ~95 mm span.
	assert_eq(BodyDimensions.length_mm("monarch"), 25.0)
	assert_eq(BodyDimensions.largest_mm("monarch"), 48.0)
	assert_eq(BodyDimensions.middle_mm("monarch"), 25.0)


func test_small_passerines_are_hand_sized():
	for bird in ["sparrow", "robin"]:
		assert_eq(BodyDimensions.largest_mm(bird), 140.0, bird)
		assert_eq(BodyDimensions.middle_mm(bird), 45.0, bird)


func test_the_fish_roster_spans_a_pond_goldfish_to_a_koi():
	assert_eq(BodyDimensions.largest_mm("goldfish"), 150.0)
	assert_eq(BodyDimensions.largest_mm("bluegill"), 190.0)
	assert_eq(BodyDimensions.largest_mm("trout"), 350.0)
	assert_eq(BodyDimensions.largest_mm("koi"), 550.0)


func test_the_extents_are_a_defensive_copy():
	var extents: Array = BodyDimensions.extents_mm("bee")
	extents[0] = 9999.0
	assert_eq(BodyDimensions.extents_mm("bee"), [13.0, 6.0, 5.0])
