extends GutTest

## docs/concept/discovery.md: going somewhere has to be recorded, has to pay,
## and has to say so.
##
## Measured before this module existed: `mark_chunk_explored` had exactly ONE
## caller in the whole game -- `Player._cast_reveal`, the `reveal` spell atom
## -- so walking across a continent marked nothing and `/map` reported an
## empty world; distance from spawn appeared in no XP formula anywhere, so
## the far country was strictly more dangerous and strictly no more
## rewarding; and `JourneyRing.crossing_between` was written for a card that
## did not exist.
##
## This file pins the RULE. The wiring -- that World really walks it, really
## marks the manager's own ExploredTiles, and really pays the player -- is
## test_world_discovery.gd.

const Discovery = preload("res://src/gameplay/discovery.gd")
const JourneyRing = preload("res://src/gameplay/journey_ring.gd")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const EcologicalLiteracy = preload("res://src/gameplay/ecological_literacy.gd")
const Player = preload("res://scenes/player.gd")
const RegionDifficulty = preload("res://src/world/region_difficulty.gd")


func _outermost_ring() -> Dictionary:
	return JourneyRing.RINGS[JourneyRing.RINGS.size() - 1]


func _hearth() -> Dictionary:
	return JourneyRing.RINGS[0]


## A distance that lands inside ring `index`, one chunk past the previous
## ring's outer edge (the table's own inner bound).
func _distance_in_ring(index: int) -> int:
	return int(JourneyRing.RINGS[index]["inner_chunks"])


# -- the chunk is the unit of "somewhere else" ---------------------------

## Restated rather than preloading the streaming layer, so it is pinned the
## same way JourneyRing pins its own restated CHUNK_SIZE_TILES.
func test_the_restated_chunk_size_is_the_chunk_managers_own():
	assert_eq(Discovery.CHUNK_SIZE_TILES, EarthChunkManager.CHUNK_SIZE)


func test_every_tile_of_a_chunk_maps_to_that_chunk():
	var size := Discovery.CHUNK_SIZE_TILES
	for chunk in [Vector2i(0, 0), Vector2i(3, -2), Vector2i(-7, 11)]:
		for corner in [Vector2i(0, 0), Vector2i(size - 1, 0), Vector2i(0, size - 1), Vector2i(size - 1, size - 1)]:
			assert_eq(
				Discovery.chunk_of(chunk * size + corner), chunk,
				"tile %s belongs to chunk %s" % [chunk * size + corner, chunk]
			)


## Negative ground is west and north of spawn and is ordinary ground. Integer
## truncation would fold tile -1 into chunk 0 and make two different places
## the same place on the map.
func test_ground_west_and_north_of_the_origin_floors_rather_than_truncates():
	assert_eq(Discovery.chunk_of(Vector2i(-1, -1)), Vector2i(-1, -1))
	assert_eq(Discovery.chunk_of(Vector2i(-Discovery.CHUNK_SIZE_TILES, -1)), Vector2i(-1, -1))
	assert_eq(
		Discovery.chunk_of(Vector2i(-Discovery.CHUNK_SIZE_TILES - 1, 0)), Vector2i(-2, 0)
	)


# -- the payoff is derived, not picked -----------------------------------

## The one tuned number is FAR_COUNTRY_KILLS; XP_PER_DEMAND falls out of it,
## and the division must be EXACT for the real ring table or the payoff is
## quietly rounded away.
func test_the_per_demand_step_divides_the_anchor_exactly():
	assert_eq(
		Discovery.DISCOVERY_XP_BASE + Discovery.xp_per_demand() * Discovery.max_demand_count(),
		Discovery.XP_PER_KILL * Discovery.FAR_COUNTRY_KILLS,
		"the outermost ring's chunk must land exactly on the anchor, not near it"
	)


func test_the_restated_kill_xp_is_the_players_own():
	assert_eq(Discovery.XP_PER_KILL, Player.XP_PER_KILL)


## Read out: setting foot somewhere in the hearth is worth what an off-peak
## harvest is worth -- EcologicalLiteracy's own "engaging a real system at
## all" baseline, not a second opinion about it.
func test_a_new_chunk_of_the_hearth_is_worth_an_off_peak_harvest():
	assert_eq(
		Discovery.xp_for_distance(0),
		EcologicalLiteracy.new().harvest_xp(false),
		"the mildest ground pays the mildest existing reward"
	)


## And the hardest ground on the planet -- the only place bear, lion and
## venomous snake exist -- is worth exactly two level-1 kills.
func test_a_new_chunk_of_the_far_country_is_worth_the_pinned_number_of_kills():
	var far := _distance_in_ring(JourneyRing.RINGS.size() - 1)
	assert_eq(
		Discovery.xp_for_distance(far),
		Discovery.XP_PER_KILL * Discovery.FAR_COUNTRY_KILLS
	)


## The gradient the whole requirement rests on: further out is worth more,
## across every boundary in the table, because the ring's own packing list
## grows outward. This is what stops the danger gradient being a pure tax.
func test_every_ring_outward_pays_strictly_more_than_the_one_inside_it():
	for index in range(1, JourneyRing.RINGS.size()):
		var inner_edge := int(JourneyRing.RINGS[index - 1]["outer_chunks"])
		var outer_edge := _distance_in_ring(index)
		assert_gt(
			Discovery.xp_for_distance(outer_edge),
			Discovery.xp_for_distance(inner_edge),
			"%s must pay more than %s" % [
				JourneyRing.RINGS[index]["name"], JourneyRing.RINGS[index - 1]["name"]
			]
		)


## Never decreasing anywhere, swept well past the last bounded ring -- a dip
## would be a place it pays to turn back, which is the opposite of the point.
func test_the_payoff_never_decreases_with_distance():
	var previous := Discovery.xp_for_distance(0)
	for distance in range(1, RegionDifficulty.MEDIUM_RADIUS_CHUNKS * 2):
		var here := Discovery.xp_for_distance(distance)
		assert_true(here >= previous, "payoff dipped at %d chunks out" % distance)
		previous = here


func test_the_payoff_is_the_rings_own_demand_list_and_nothing_else():
	for index in JourneyRing.RINGS.size():
		var distance := _distance_in_ring(index)
		assert_eq(
			Discovery.xp_for_distance(distance),
			Discovery.DISCOVERY_XP_BASE
			+ Discovery.xp_per_demand() * int(JourneyRing.RINGS[index]["demands"].size()),
			"no second difficulty model -- the demands ARE the price"
		)


# -- the demands read as words -------------------------------------------

## Two-way, like Answerback's own drift test: every demand the real table
## declares has a readable phrase, and nothing reaches a player as an id.
func test_every_demand_in_the_real_table_reads_as_words():
	var seen := 0
	for ring in JourneyRing.RINGS:
		for demand in ring["demands"]:
			var phrase := Discovery.demand_phrase(String(demand))
			assert_false(phrase.is_empty(), "%s has no phrase" % demand)
			assert_false(phrase.contains("_"), "%s reached a player as an id" % demand)
			seen += 1
	assert_gt(seen, 0, "the sweep must really have seen demands")


func test_a_demand_nobody_declared_is_the_empty_string_rather_than_a_guess():
	assert_eq(Discovery.demand_phrase(""), "")


# -- the packing line ----------------------------------------------------

## The hearth demands nothing, so it gets no line at all rather than an
## empty "Carry: ." -- the same rule the briefing and every refusal follow.
func test_the_hearth_asks_for_nothing_and_says_so_by_saying_nothing():
	assert_eq(Discovery.packing_line(_hearth()), "")


func test_every_other_ring_lists_every_one_of_its_demands():
	for index in range(1, JourneyRing.RINGS.size()):
		var ring: Dictionary = JourneyRing.RINGS[index]
		var line := Discovery.packing_line(ring)
		assert_false(line.is_empty(), "%s demands things and must say so" % ring["name"])
		for demand in ring["demands"]:
			assert_true(
				line.contains(Discovery.demand_phrase(String(demand))),
				"%s left %s off the packing line" % [ring["name"], demand]
			)


# -- the crossing card ---------------------------------------------------

func test_crossing_outward_says_you_are_entering_and_names_what_is_lethal():
	var marches: Dictionary = JourneyRing.RINGS[2]
	var card := Discovery.crossing_card(marches, true)
	assert_true(card.contains("entering"), "outward is a warning")
	assert_true(card.contains(String(marches["description"])), "and says what changed")
	assert_true(card.contains(Discovery.packing_line(marches)))


func test_crossing_inward_says_you_are_back_rather_than_entering():
	var card := Discovery.crossing_card(_hearth(), false)
	assert_true(card.contains("back in"), "coming home reads as relief, not as a warning")
	assert_false(card.contains("entering"))


## "You are entering the Marches." -- never "entering The Marches", which is
## exactly the kind of line a first-time player notices.
func test_the_rings_article_is_lowercased_inside_the_sentence():
	for ring in JourneyRing.RINGS:
		var card := Discovery.crossing_card(ring, true)
		assert_false(
			card.contains("The %s" % String(ring["name"]).trim_prefix("The ")),
			"%s reads with a capitalised article mid-sentence" % ring["name"]
		)
		assert_true(
			card.contains("the %s" % String(ring["name"]).trim_prefix("The ")),
			"%s must still be named" % ring["name"]
		)


func test_a_card_for_no_crossing_is_nothing_at_all():
	assert_eq(Discovery.crossing_card({}, true), "")


# -- the whole step ------------------------------------------------------

func test_new_ground_pays_and_old_ground_does_not():
	var walked: Dictionary = Discovery.report_for(0, 0, true)
	assert_eq(int(walked["xp"]), Discovery.xp_for_distance(0))
	var revisited: Dictionary = Discovery.report_for(0, 0, false)
	assert_eq(int(revisited["xp"]), 0, "ground you have already walked pays once, and it already has")


## Pillar 4: an ordinary new chunk gets the receipt and nothing else. A chunk
## edge arrives every ~13 s of walking and a banner at that rate teaches a
## player to stop reading banners.
func test_an_ordinary_new_chunk_answers_with_a_receipt_and_no_card():
	var report: Dictionary = Discovery.report_for(0, 1, true)
	assert_eq(String(report["message"]), "", "no card inside a ring")
	assert_true(String(report["float_text"]).contains(str(int(report["xp"]))), "the receipt names the number")
	assert_false(String(report["float_text"]).is_empty())


func test_a_receipt_names_the_ground_rather_than_a_bare_number():
	var report: Dictionary = Discovery.report_for(0, 1, true)
	assert_true(
		String(report["float_text"]).to_lower().contains("ground"),
		"a bare '+2 XP' does not tell a player what they were paid for"
	)


func test_old_ground_inside_a_ring_answers_with_nothing_at_all():
	var report: Dictionary = Discovery.report_for(1, 2, false)
	assert_eq(String(report["float_text"]), "")
	assert_eq(String(report["message"]), "")


func test_crossing_a_boundary_raises_the_card_for_the_ring_landed_in():
	var from := int(JourneyRing.RINGS[0]["outer_chunks"])
	var to := _distance_in_ring(1)
	var report: Dictionary = Discovery.report_for(from, to, true)
	assert_false(report["crossing"].is_empty(), "a boundary really was crossed")
	assert_eq(String(report["crossing"]["id"]), String(JourneyRing.RINGS[1]["id"]))
	assert_true(bool(report["outward"]))
	assert_eq(String(report["message"]), Discovery.crossing_card(JourneyRing.RINGS[1], true))


func test_coming_home_is_news_too_and_is_not_reported_as_outward():
	var report: Dictionary = Discovery.report_for(_distance_in_ring(1), 0, false)
	assert_false(report["crossing"].is_empty(), "coming home is also a crossing")
	assert_false(bool(report["outward"]))
	assert_true(String(report["message"]).contains("back in"))


## A teleport, a load, or a `/spawn` reports the ring actually landed in
## rather than every ring passed over -- that is the one the player now has
## to survive.
func test_a_jump_across_several_rings_reports_the_one_landed_in():
	var report: Dictionary = Discovery.report_for(0, _distance_in_ring(JourneyRing.RINGS.size() - 1), true)
	assert_eq(String(report["crossing"]["id"]), String(_outermost_ring()["id"]))


## A character who has not moved yet has nothing to have crossed. The arrival
## briefing owns that moment (docs/concept/arrival.md), not a crossing card
## fired on the first frame of every session.
func test_a_character_who_has_not_moved_yet_crosses_nothing():
	for distance in [0, 1, 40, 400]:
		var report: Dictionary = Discovery.report_for(Discovery.NO_PREVIOUS_DISTANCE, distance, true)
		assert_true(
			report["crossing"].is_empty(),
			"no previous position is not a crossing at %d chunks out" % distance
		)
		assert_eq(String(report["message"]), "")
		assert_gt(int(report["xp"]), 0, "but the ground under them is still new")


func test_wandering_inside_one_ring_never_raises_a_card():
	var inner := _distance_in_ring(3)
	var outer := int(JourneyRing.RINGS[3]["outer_chunks"])
	for distance in range(inner, outer + 1):
		var report: Dictionary = Discovery.report_for(inner, distance, true)
		assert_eq(
			String(report["message"]), "",
			"%d chunks out is still the same ring as %d" % [distance, inner]
		)


# -- and it still cannot refuse entry ------------------------------------

## JourneyRing deliberately exposes no can_enter, and neither does this. The
## world's order is enforced by what lives out there and by the cold, never
## by an invisible fence (docs/concept/discovery.md, pillar 5).
func test_nothing_here_can_refuse_entry():
	var forbidden: Array = [
		"can_enter", "is_blocked", "may_pass", "is_allowed", "can_pass",
		"blocks_entry", "is_locked", "requires_level", "gate_at",
	]
	var declared: Array = []
	for method in Discovery.new().get_script().get_script_method_list():
		declared.append(method["name"])
	assert_true(
		declared.has("report_for"),
		"reflection returned no known method -- the guard below would be vacuous"
	)
	for forbidden_name in forbidden:
		assert_false(declared.has(forbidden_name), "%s must not exist here" % forbidden_name)


# -- how long the card stays up -----------------------------------------
#
# The rule itself is Answerback's (seconds_to_read, and the ceiling it is
# held to); what is pinned here is that the real ring table produces cards
# the rule can actually show.

const Answerback = preload("res://src/gameplay/answerback.gd")


## The property that matters on screen: every card the real ring table can
## produce is up long enough to read and gone before it is furniture.
func test_every_real_crossing_card_is_readable_and_none_becomes_furniture():
	for ring in JourneyRing.RINGS:
		for outward in [true, false]:
			var seconds := Answerback.seconds_to_read(Discovery.crossing_card(ring, outward))
			assert_gt(seconds, 2.0, "%s is gone before it can be read" % ring["name"])
			assert_true(
				seconds < Answerback.MAX_CARD_SECONDS,
				"%s has become a HUD element rather than a message" % ring["name"]
			)


# -- the one reading that does not vanish --------------------------------
#
# Measured by instrumenting a --solo launch, after the report "no card or XP
# visible": the wiring was fine -- frame 1 paid 2 XP and produced the float
# -- but EVERYTHING built here was transient. The receipt lasts
# DELIBERATE_INTERVAL_SECONDS (~1.0 s) and only re-fires after a whole chunk
# of walking (512 px, ~13 s in a straight line at BASE_SPEED); the crossing
# card needs six chunks, over a minute of walking one way. A player who
# wanders inside their spawn chunk sees the journey layer exactly once, for
# one second, during the loading fade.
#
# So the journey needs a reading that is simply always on screen. This is
# the "HUD place chip naming the ring" that docs/concept/journey_rings.md
# has listed as unbuilt since the rings shipped.

func test_the_place_chip_names_the_ring_you_are_standing_in():
	for index in JourneyRing.RINGS.size():
		var ring: Dictionary = JourneyRing.RINGS[index]
		var chip := Discovery.place_chip(_distance_in_ring(index), 1)
		assert_true(
			chip.contains(String(ring["name"])),
			"%s must say where you are" % ring["name"]
		)


## In metres a player can compare with something they know -- the same play
## scale SprintCost measures a burst in, so "410 m from home" and "one burst
## carries 80 m" are numbers about the same world.
func test_the_distance_is_the_walking_scale_not_the_map_scale():
	var distance := 9
	var walking := JourneyRing.walking_metres_from_spawn(distance)
	assert_true(
		Discovery.place_chip(distance, 1).contains("%d m" % int(roundf(walking))),
		"the chip reports %d m" % int(roundf(walking))
	)
	assert_false(
		Discovery.place_chip(distance, 1).contains(
			"%d m" % int(roundf(JourneyRing.metres_from_spawn(distance)))
		),
		"never the planet's own kilometres -- that is the map's scale, not the legs'"
	)


## Standing at home there is no distance to report, and "0 m from home" is
## the kind of line ArrivalBriefing.distance_phrase already refuses to print.
func test_standing_at_home_says_home_rather_than_zero_metres():
	var chip := Discovery.place_chip(0, 1)
	assert_false(chip.contains("0 m"), "no zero distances")
	assert_true(chip.contains(String(JourneyRing.RINGS[0]["name"])))


## The visible proof that walking records ground: a number that ticks up
## every chunk, which is the evidence a player was missing entirely.
func test_the_chip_reports_how_much_ground_is_known():
	assert_true(Discovery.place_chip(9, 14).contains("14"))
	assert_ne(Discovery.place_chip(9, 14), Discovery.place_chip(9, 15))


func test_the_chip_is_never_empty_at_any_distance():
	for distance in [0, 1, 5, 6, 15, 16, 30, 31, 60, 61, 400]:
		assert_false(
			Discovery.place_chip(distance, 0).is_empty(),
			"a permanent readout must always have something to read at %d" % distance
		)


## It is a chip, not a paragraph: it sits in the HUD's bottom-left column
## beside the condition chips, and a line that wraps there is a line that
## covers the world.
func test_the_chip_stays_short_enough_to_be_a_chip():
	for distance in [0, 6, 16, 31, 61, 400]:
		assert_lt(
			Discovery.place_chip(distance, 9999).length(), 60,
			"the chip is one short line at %d chunks out" % distance
		)
