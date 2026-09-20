extends GutTest

## The three sentences a new character gets in their first ten seconds
## (see docs/concept/arrival.md): where you are, what is near you, one
## thing to do.
##
## Two rules carry this suite. First, every line is read off real state or
## is not printed at all -- so the sweep that matters is the one that
## feeds the briefing half-empty, id-shaped and outright broken facts and
## demands that nothing ever reaches a player as "null", "<null>" or a raw
## snake_case id. Second, the briefing must never be a second opinion:
## its bearing is Compass's reading, its distance is the map's own scale,
## and its errand is phrased the way ErrandDelivery phrases one at the
## villager's door -- each pinned against that module rather than
## restated here.

const ArrivalBriefing = preload("res://src/gameplay/arrival_briefing.gd")
const Compass = preload("res://src/gameplay/compass.gd")
const ErrandDelivery = preload("res://src/gameplay/errand_delivery.gd")
const JourneyRing = preload("res://src/gameplay/journey_ring.gd")
const Lithology = preload("res://src/world/lithology.gd")

## Far enough that a bearing is unambiguous and a rounding bug in the
## distance phrase cannot hide inside one tile.
const REACH := 100.0

## Just inside either side of a 22.5-degree boundary: close enough that a
## floor/ceil confusion in the snap fails, far enough that float noise in
## atan2 cannot decide the answer.
const BOUNDARY_NUDGE := 0.2

var here := Vector2(500.0, 500.0)


func _point_at(bearing_degrees: float, distance: float) -> Vector2:
	# Same convention as Compass: 0 = north = +Y, clockwise-positive.
	var radians := deg_to_rad(bearing_degrees)
	return here + Vector2(sin(radians), cos(radians)) * distance


func _full_facts() -> Dictionary:
	return {
		"river_name": "Loire",
		"season": "spring",
		"player_tile": here,
		"settlement_tile": here + Vector2(8.0, 8.0),
		"settlement_name": "Aubance",
		"errands": [{
			"settlement_id": "s_1",
			"household_id": "h_1",
			"occupation": "potter",
			"recipe_id": "clay_pot",
			"missing": [{"item_id": "clay", "need": 3}],
		}],
	}


# -- the bearing is Compass's, not a second opinion ------------------------


func test_the_eight_points_read_as_words():
	var expected := {
		0.0: "north",
		45.0: "northeast",
		90.0: "east",
		135.0: "southeast",
		180.0: "south",
		225.0: "southwest",
		270.0: "west",
		315.0: "northwest",
	}
	for degrees in expected:
		assert_eq(
			ArrivalBriefing.bearing_word(here, _point_at(degrees, REACH)),
			expected[degrees],
			"%.0f degrees should read as %s" % [degrees, expected[degrees]]
		)


func test_the_boundaries_fall_halfway_between_the_points():
	var names: Array = ArrivalBriefing.POINTS
	for index in names.size():
		var boundary := 45.0 * float(index) + 22.5
		var before := ArrivalBriefing.bearing_word(
			here, _point_at(boundary - BOUNDARY_NUDGE, REACH)
		)
		var after := ArrivalBriefing.bearing_word(
			here, _point_at(boundary + BOUNDARY_NUDGE, REACH)
		)
		assert_eq(before, names[index], "just before %.1f should still be %s" % [boundary, names[index]])
		assert_eq(
			after,
			names[(index + 1) % names.size()],
			"just after %.1f should be %s" % [boundary, names[(index + 1) % names.size()]]
		)


func test_every_degree_of_the_circle_agrees_with_the_compass_item():
	for degrees in 360:
		var word: String = ArrivalBriefing.word_for_degrees(float(degrees))
		var snapped := Compass.rough_reading(float(degrees))
		assert_eq(
			word,
			ArrivalBriefing.POINTS[int(snapped / Compass.ROUGH_STEP_DEGREES) % ArrivalBriefing.POINTS.size()],
			"%d degrees disagreed with Compass.rough_reading (%.1f)" % [degrees, snapped]
		)


func test_there_is_no_direction_to_where_you_already_stand():
	assert_eq(ArrivalBriefing.bearing_word(here, here), "")


# -- the distance is the map's own scale -----------------------------------


func test_the_tile_is_the_surface_maps_kilometre():
	assert_almost_eq(ArrivalBriefing.KM_PER_TILE, Lithology.KM_PER_TILE, 0.0000001)
	assert_almost_eq(ArrivalBriefing.KM_PER_TILE, JourneyRing.KM_PER_TILE, 0.0000001)
	assert_almost_eq(
		ArrivalBriefing.METRES_PER_TILE,
		ArrivalBriefing.KM_PER_TILE * JourneyRing.METRES_PER_KM,
		0.0000001
	)


func test_the_distance_phrase_speaks_in_human_units():
	assert_eq(ArrivalBriefing.distance_phrase(0.0), "")
	assert_eq(ArrivalBriefing.distance_phrase(0.2), "a few hundred metres")
	assert_eq(ArrivalBriefing.distance_phrase(0.6), "about a kilometre")
	assert_eq(ArrivalBriefing.distance_phrase(1.4), "about a kilometre")
	assert_eq(ArrivalBriefing.distance_phrase(1.6), "about 2 km")
	assert_eq(ArrivalBriefing.distance_phrase(9.4), "about 9 km")
	assert_eq(ArrivalBriefing.distance_phrase(12.0), "about 10 km")
	assert_eq(ArrivalBriefing.distance_phrase(43.0), "about 45 km")


func test_a_far_walk_is_never_claimed_to_the_kilometre():
	# Past the pinned threshold the phrase rounds to the nearest five, so
	# a briefing never pretends to know a long walk exactly.
	for tiles in range(11, 120):
		var phrase := ArrivalBriefing.distance_phrase(float(tiles))
		var number := int(phrase.replace("about ", "").replace(" km", ""))
		assert_eq(
			number % int(ArrivalBriefing.COARSE_STEP_KM),
			0,
			"%s is a false precision at %d tiles" % [phrase, tiles]
		)
		assert_true(
			absf(float(number) - float(tiles)) <= ArrivalBriefing.COARSE_STEP_KM / 2.0,
			"%s is not the nearest five to %d km" % [phrase, tiles]
		)


# -- the whole briefing ----------------------------------------------------


func test_the_three_facts_a_new_player_needs_are_all_there():
	var briefing: Dictionary = ArrivalBriefing.briefing_for(_full_facts())
	assert_string_contains(briefing["place_line"], "Loire")
	assert_string_contains(briefing["place_line"], "spring")
	assert_string_contains(briefing["bearing_line"], "Aubance")
	assert_string_contains(briefing["bearing_line"], "northeast")
	assert_string_contains(briefing["bearing_line"], "km")
	assert_string_contains(briefing["errand_line"], "potter")
	assert_string_contains(briefing["errand_line"], "3 clay")


func test_nothing_known_says_nothing_rather_than_null():
	var briefing: Dictionary = ArrivalBriefing.briefing_for({})
	assert_eq(briefing["place_line"], "")
	assert_eq(briefing["bearing_line"], "")
	assert_eq(briefing["errand_line"], "")


func test_no_village_nearby_means_no_bearing_line_and_nothing_else_lost():
	var facts := _full_facts()
	facts.erase("settlement_tile")
	facts.erase("settlement_name")
	var briefing: Dictionary = ArrivalBriefing.briefing_for(facts)
	assert_eq(briefing["bearing_line"], "")
	assert_gt(briefing["place_line"].length(), 0, "the place is still known")
	assert_gt(briefing["errand_line"].length(), 0, "the errand is still known")


func test_a_village_with_no_name_is_still_worth_a_direction():
	var facts := _full_facts()
	facts.erase("settlement_name")
	var briefing: Dictionary = ArrivalBriefing.briefing_for(facts)
	assert_string_contains(briefing["bearing_line"], "village")
	assert_string_contains(briefing["bearing_line"], "northeast")


func test_a_river_or_a_season_alone_still_reads_as_a_sentence():
	var river_only: Dictionary = ArrivalBriefing.briefing_for({"river_name": "Loire"})
	assert_string_contains(river_only["place_line"], "Loire")
	assert_false(river_only["place_line"].contains(","), "a half-known place needs no comma")
	var season_only: Dictionary = ArrivalBriefing.briefing_for({"season": "winter"})
	assert_string_contains(season_only["place_line"], "winter")


func test_no_line_ever_shows_a_raw_id_or_a_null():
	var broken_facts: Array = [
		{},
		{"river_name": "", "season": "", "errands": []},
		{"errands": [{}]},
		{"errands": [{"missing": []}]},
		{"errands": [{"occupation": "", "missing": [{"item_id": "plant_fibre", "need": 2}]}]},
		{"player_tile": here, "settlement_tile": here, "settlement_name": "Aubance"},
		{
			"river_name": "Loire",
			"season": "spring",
			"player_tile": here,
			"settlement_tile": here + Vector2(3.0, 0.0),
			"settlement_name": "",
			"errands": [{
				"settlement_id": "s_1",
				"household_id": "h_1",
				"occupation": "innkeeper",
				"missing": [{"item_id": "plant_fibre", "need": 2}, {"item_id": "oak_log", "need": 1}],
			}],
		},
	]
	for facts in broken_facts:
		var briefing: Dictionary = ArrivalBriefing.briefing_for(facts)
		for key in ["place_line", "bearing_line", "errand_line"]:
			var line: String = briefing[key]
			assert_false(line.contains("null"), "%s leaked a null: '%s'" % [key, line])
			assert_false(line.contains("_"), "%s leaked a raw id: '%s'" % [key, line])
			assert_false(line.begins_with(" "), "%s starts with a gap: '%s'" % [key, line])
			if line != "":
				assert_true(line.ends_with("."), "%s is not a sentence: '%s'" % [key, line])


func test_a_vowel_occupation_gets_the_right_article():
	var facts := _full_facts()
	facts["errands"] = [{
		"settlement_id": "s_1",
		"household_id": "h_1",
		"occupation": "innkeeper",
		"missing": [{"item_id": "clay", "need": 1}],
	}]
	assert_string_contains(ArrivalBriefing.briefing_for(facts)["errand_line"], "an innkeeper")


func test_several_missing_inputs_are_joined_the_way_a_villager_says_them():
	var facts := _full_facts()
	facts["errands"] = [{
		"settlement_id": "s_1",
		"household_id": "h_1",
		"occupation": "potter",
		"missing": [
			{"item_id": "clay", "need": 3},
			{"item_id": "rock", "need": 1},
			{"item_id": "stick", "need": 2},
		],
	}]
	assert_string_contains(
		ArrivalBriefing.briefing_for(facts)["errand_line"], "3 clay, 1 rock and 2 stick"
	)


func test_the_errand_is_worded_exactly_as_the_give_verb_words_it():
	# ErrandDelivery is the module the player meets at the villager's door.
	# If the briefing said "plant_fibre" and the door said "plant fibre",
	# the game would be talking about two different things.
	var missing: Array = [{"item_id": "plant_fibre", "need": 3}]
	var offer: Dictionary = ErrandDelivery.offer_from_frame({
		"shortfall_missing": missing,
		"player_carrying": {"plant_fibre": 3},
		"npc_name": "Mara",
		"household_id": "h_1",
		"settlement_id": "s_1",
	})
	var door_phrase: String = String(offer["label"]).replace("Give ", "")
	var facts := _full_facts()
	facts["errands"] = [{
		"settlement_id": "s_1", "household_id": "h_1", "occupation": "potter", "missing": missing
	}]
	assert_string_contains(ArrivalBriefing.briefing_for(facts)["errand_line"], door_phrase)


# -- which errand, and why -------------------------------------------------


func test_the_first_errand_is_the_one_a_newcomer_can_actually_finish():
	var errands: Array = [
		{
			"settlement_id": "s_1",
			"household_id": "h_big",
			"occupation": "blacksmith",
			"missing": [{"item_id": "rock", "need": 9}, {"item_id": "stick", "need": 4}],
		},
		{
			"settlement_id": "s_1",
			"household_id": "h_small",
			"occupation": "potter",
			"missing": [{"item_id": "clay", "need": 2}],
		},
	]
	assert_eq(ArrivalBriefing.salient_errand(errands)["household_id"], "h_small")


func test_the_same_world_always_gives_the_same_first_errand():
	var a := {
		"settlement_id": "s_2",
		"household_id": "h_a",
		"occupation": "potter",
		"missing": [{"item_id": "clay", "need": 2}],
	}
	var b := {
		"settlement_id": "s_1",
		"household_id": "h_b",
		"occupation": "fisher",
		"missing": [{"item_id": "stick", "need": 2}],
	}
	# Same total need: the tie must break on something stable, not on the
	# order a Dictionary happened to iterate its households in.
	var forwards: Dictionary = ArrivalBriefing.salient_errand([a, b])
	var backwards: Dictionary = ArrivalBriefing.salient_errand([b, a])
	assert_eq(forwards["household_id"], backwards["household_id"])


func test_an_errand_nobody_is_short_of_is_not_an_errand():
	assert_eq(ArrivalBriefing.salient_errand([]), {})
	assert_eq(ArrivalBriefing.salient_errand([{"missing": []}]), {})
	assert_eq(
		ArrivalBriefing.salient_errand([{"missing": [{"item_id": "clay", "need": 0}]}]), {}
	)


func test_the_smallest_errand_wins_from_any_order_the_projection_listed_them_in():
	# Quest.production_shortfall_quests_for walks a Dictionary of
	# households, whose iteration order is not a contract. Every
	# permutation of the same shortfalls must name the same first errand.
	var errands: Array = [
		{"settlement_id": "s_1", "household_id": "h_1", "occupation": "blacksmith",
			"missing": [{"item_id": "rock", "need": 9}]},
		{"settlement_id": "s_1", "household_id": "h_2", "occupation": "farmer",
			"missing": [{"item_id": "plant_fibre", "need": 4}, {"item_id": "stick", "need": 2}]},
		{"settlement_id": "s_1", "household_id": "h_3", "occupation": "potter",
			"missing": [{"item_id": "clay", "need": 2}]},
		{"settlement_id": "s_1", "household_id": "h_4", "occupation": "fisher",
			"missing": [{"item_id": "stick", "need": 5}]},
		{"settlement_id": "s_1", "household_id": "h_5", "occupation": "guard",
			"missing": []},
	]
	for rotation in errands.size():
		var rotated: Array = errands.slice(rotation) + errands.slice(0, rotation)
		rotated.reverse()
		assert_eq(
			ArrivalBriefing.salient_errand(rotated)["household_id"],
			"h_3",
			"rotation %d named a different errand" % rotation
		)


func test_a_village_on_the_doorstep_still_reads_as_a_sentence():
	var facts := _full_facts()
	facts["settlement_tile"] = here + Vector2(0.0, 0.3)
	var line: String = ArrivalBriefing.briefing_for(facts)["bearing_line"]
	assert_eq(line, "Aubance lies a few hundred metres north.")


func test_an_errand_that_knows_its_own_village_names_that_one():
	# The nearest settlement and the settlement the errand is in are not
	# always the same place; the errand's own name wins where it has one.
	var facts := _full_facts()
	facts["errands"] = [{
		"settlement_id": "s_2",
		"household_id": "h_1",
		"occupation": "potter",
		"settlement_name": "Brissac",
		"missing": [{"item_id": "clay", "need": 3}],
	}]
	var line: String = ArrivalBriefing.briefing_for(facts)["errand_line"]
	assert_string_contains(line, "Brissac")
	assert_false(line.contains("Aubance"), "the errand is not in the nearest village")


# -- the card the three lines become ------------------------------------
#
# The briefing hands back three separately-optional lines, and every caller
# would otherwise invent its own way of joining them. `card_text` is that
# join, once, so "a missing fact is a line the caller does not draw" stays
# one rule rather than one rule per caller.

func test_the_card_is_the_three_lines_in_order():
	var card := ArrivalBriefing.card_text({
		"place_line": "You are on the Loire, in spring.",
		"bearing_line": "A village lies about 12 km northeast.",
		"errand_line": "A potter needs 3 clay.",
	})
	assert_eq(
		card,
		"You are on the Loire, in spring.\nA village lies about 12 km northeast.\nA potter needs 3 clay."
	)


## The case the whole "read real state, invent nothing" rule exists for: no
## village anywhere near, so there is no bearing to give. The card closes up
## rather than showing a blank line where a fact should have been.
func test_a_missing_line_leaves_no_gap():
	var card := ArrivalBriefing.card_text({
		"place_line": "You are on the Loire, in spring.",
		"bearing_line": "",
		"errand_line": "A potter needs 3 clay.",
	})
	assert_eq(card, "You are on the Loire, in spring.\nA potter needs 3 clay.")
	assert_false(card.contains("\n\n"), "no blank line where a fact would have been")


func test_a_briefing_that_knows_nothing_is_no_card_at_all():
	assert_eq(ArrivalBriefing.card_text({"place_line": "", "bearing_line": "", "errand_line": ""}), "")
	assert_eq(ArrivalBriefing.card_text({}), "")


## Straight from the real entry point, so the two cannot drift: whatever
## briefing_for produces is what card_text is given.
func test_the_card_is_built_from_the_real_briefing():
	var facts := {
		"river_name": "Loire",
		"season": "spring",
		"player_tile": Vector2i(0, 0),
		"settlement_tile": Vector2i(11, 0),
		"errands": [],
	}
	var briefing: Dictionary = ArrivalBriefing.briefing_for(facts)
	var card := ArrivalBriefing.card_text(briefing)
	assert_true(card.contains(String(briefing["place_line"])))
	assert_true(card.contains(String(briefing["bearing_line"])))
