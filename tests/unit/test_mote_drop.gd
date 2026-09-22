extends GutTest

## What a kill leaves for a spellwright (docs/concept/spell_weaving.md).
##
## The last unbuilt half of the Magicraft loop, and the sharpest one:
## `SpellMote.drop_tier_cap_for_ring` and `droppable_atoms_at_ring` say
## exactly what is eligible where, and had **zero callers**. The only two
## ways an atom ever reached a pouch were the seven one-time `witness`
## phenomena and the `/arena` dev command -- so a character had at most
## seven atoms for the whole game, and the four-socket Weave could never be
## full of anything they had chosen.
##
## A mote is a souvenir of something that nearly killed you, so the odds
## come from `SpeciesBite.threat_score` -- the same score the difficulty
## rings are ordered by -- and the eligible set comes from where you were
## standing when it died.

const MoteDrop = preload("res://src/gameplay/mote_drop.gd")
const SpellMote = preload("res://src/gameplay/spell_mote.gd")
const SpeciesBite = preload("res://src/gameplay/species_bite.gd")
const SpellDraft = preload("res://src/gameplay/spell_draft.gd")
const JourneyRing = preload("res://src/gameplay/journey_ring.gd")

const FAR_RING := 4


# -- who leaves one ------------------------------------------------------

## A mote is a souvenir of danger, so nothing that never threatened you
## leaves one. A deer is meat, not a lesson.
func test_a_grazer_leaves_no_mote():
	assert_almost_eq(MoteDrop.chance_for("deer"), 0.0, 0.0001)
	assert_almost_eq(MoteDrop.chance_for("squirrel"), 0.0, 0.0001)


## And the ordering is the roster's own threat ordering, not a second
## opinion about which animals are frightening.
func test_a_more_dangerous_animal_leaves_one_more_often():
	assert_gt(MoteDrop.chance_for("bear"), MoteDrop.chance_for("wolf"))
	assert_gt(MoteDrop.chance_for("wolf"), MoteDrop.chance_for("arctic_fox"))


func test_nothing_beats_the_most_dangerous_animal_in_the_world():
	for species in ["bear", "lion", "wolf", "jaguar", "boar", "venomous_snake"]:
		assert_lte(MoteDrop.chance_for(species), MoteDrop.MAX_DROP_CHANCE)


func test_something_really_reaches_the_ceiling():
	var best := 0.0
	for species in ["bear", "lion", "wolf", "jaguar", "boar", "venomous_snake", "lynx"]:
		best = maxf(best, MoteDrop.chance_for(species))
	assert_almost_eq(
		best, MoteDrop.MAX_DROP_CHANCE, 0.0001,
		"a ceiling nothing reaches is a ceiling nobody chose"
	)


func test_an_animal_the_world_does_not_know_leaves_nothing():
	assert_almost_eq(MoteDrop.chance_for("not_an_animal"), 0.0, 0.0001)


# -- how often, stated as a number a player would feel --------------------

## The one tuned value, pinned at both ends by what it means rather than by
## taste: filling a four-socket Weave from the world's most dangerous
## animal must be a hunting TRIP and not a grind, and not a vending
## machine either.
func test_filling_a_weave_is_a_trip_and_not_a_grind():
	var kills: float = float(SpellDraft.MAX_SOCKETS) / MoteDrop.MAX_DROP_CHANCE
	assert_gte(kills, 8.0, "a Weave you fill in a handful of kills is a vending machine")
	assert_lte(kills, 40.0, "and one that takes forty is a grind, not a trip")


func test_the_ceiling_is_neither_certain_nor_nothing():
	assert_gt(MoteDrop.MAX_DROP_CHANCE, 0.0, "a drop nobody gets is not a drop")
	assert_lt(
		MoteDrop.MAX_DROP_CHANCE, 0.5,
		"past a coin flip, motes are the reason to hunt rather than a souvenir of it"
	)


# -- and what it leaves --------------------------------------------------

## Only what this ground can teach: the eligible set is the ring's own, so
## a far-country atom cannot be farmed at the hearth.
func test_a_dropped_mote_is_one_this_ground_could_yield():
	for ring in range(JourneyRing.rings().size()):
		var atom: String = MoteDrop.atom_for(ring, 12345)
		if atom == "":
			continue
		assert_true(
			SpellMote.can_drop_at_ring(atom, ring),
			"ring %d yielded an atom it is not deep enough ground for" % ring
		)


func test_the_hearth_yields_shallower_atoms_than_the_far_country():
	assert_lte(
		SpellMote.droppable_atoms_at_ring(0).size(),
		SpellMote.droppable_atoms_at_ring(FAR_RING).size(),
		"precondition: the rings really differ"
	)


## Deterministic from where it died, like every other one-time world roll
## in this project: the same kill always leaves the same thing.
func test_the_same_kill_always_leaves_the_same_mote():
	assert_eq(MoteDrop.atom_for(FAR_RING, 99), MoteDrop.atom_for(FAR_RING, 99))


func test_different_kills_do_not_all_leave_the_same_thing():
	var seen := {}
	for seed_value in range(60):
		seen[MoteDrop.atom_for(FAR_RING, seed_value)] = true
	assert_gt(seen.size(), 1, "a drop table with one row is not a drop table")


# -- the whole roll ------------------------------------------------------

func test_a_grazer_never_yields_whatever_the_roll():
	for seed_value in range(50):
		assert_eq(MoteDrop.drops(  "deer", FAR_RING, seed_value), "")


func test_a_dangerous_animal_yields_sometimes_and_not_always():
	var yields := 0
	for seed_value in range(200):
		if MoteDrop.drops("bear", FAR_RING, seed_value) != "":
			yields += 1
	assert_gt(yields, 0, "the most dangerous animal in the world must teach something")
	assert_lt(yields, 200, "and not every time, or it is a vending machine")


# -- and a real kill really hands one over ---------------------------------

const PlayerScene = preload("res://scenes/player.tscn")


## The wiring, which is the whole point: two pure functions that say
## exactly what is eligible where had zero callers for as long as they have
## existed.
##
## Asked of `_credit_kill` rather than of the swing. The body used to live
## inside `_perform_attack`, which is exactly why the swing was the only
## verb in the game that paid -- so this test now follows the chain instead
## of pinning the address, and the test below pins that EVERY verb which
## deals damage walks it (docs/concept/spell_runtime.md, "A spell is a
## blow").
func test_a_kill_is_where_a_mote_comes_from():
	var body := _function_body("_credit_kill")
	assert_false(body.is_empty(), "precondition: the shared credit was found")
	assert_true(body.contains("MoteDrop.drops("), "a kill must roll for one")
	assert_true(
		body.contains("find_mote("),
		"and hand it over through the one path that also announces it"
	)


## And every way the player deals damage walks that chain. This is the
## assertion that would have caught the original defect: the roll existed,
## the grant existed, and only one of the three verbs ever reached them, so
## a mage could not fill the Weave their own class is built around.
func test_every_verb_that_kills_pays_through_the_same_credit():
	for verb in ["_perform_attack", "_apply_cast_step_to", "_resolve_thrown_stone_impact"]:
		var body := _function_body(verb)
		assert_false(body.is_empty(), "precondition: %s was found" % verb)
		assert_true(
			body.contains("_credit_kill("),
			"%s kills things, so %s must pay for them" % [verb, verb]
		)


## The body of one function in scenes/player.gd, up to the next one. Reading
## a fixed window of characters instead trips over the doc comment of
## whatever follows -- a trap this repo has fallen into twice.
func _function_body(name: String) -> String:
	var source := FileAccess.get_file_as_string("res://scenes/player.gd")
	var start := source.find("func %s(" % name)
	if start < 0:
		return ""
	var rest := source.substr(start)
	var next := rest.find("\nfunc ")
	return rest if next < 0 else rest.substr(0, next)


## The grant is the same one the witness layer uses, so a found atom and a
## learned one land in one place and are announced by one row.
func test_a_granted_mote_reaches_the_pouch_and_says_so():
	var player = PlayerScene.instantiate()
	add_child(player)
	var seen: Array = []
	player.answered.connect(func(feedback): seen.append(feedback))
	player.find_mote("frost_damage")
	assert_gt(int(player.motes().get("frost_damage", 0)), 0, "it really reached the pouch")
	assert_eq(seen.size(), 1, "and a silent grant is how an atom goes unnoticed")
	player.queue_free()


func test_finding_nothing_grants_nothing_and_says_nothing():
	var player = PlayerScene.instantiate()
	add_child(player)
	var seen: Array = []
	player.answered.connect(func(feedback): seen.append(feedback))
	player.find_mote("")
	assert_eq(player.motes().size(), 0)
	assert_eq(seen.size(), 0)
	player.queue_free()
