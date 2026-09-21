extends GutTest

## docs/concept/arena.md: staging a real fight on demand, so the spell and
## skill layers can be battletested without a three-minute walk.
##
## Asked directly, after the overhaul landed: *"we need a way to battletest
## the new spells and skills"*. Measured first, in test_battle_loop.gd: the
## machinery is sound end to end -- a woven spell really damages a real
## creature and really kills it, and a real predator really damages the
## player. What is missing is the ENCOUNTER, and three things stand between
## a player and one:
##
##   1. A new character owns **no motes**, so nothing can be woven at all.
##      Only three phenomena have call sites, and one of them (venom) lives
##      61+ chunks out.
##   2. Mana is entirely the class lens -- a warrior or artisan has
##      `max_mana` 0.0 and can never cast anything.
##   3. The hearth is deliberately safe, so the nearest fight worth having
##      is a walk away.
##
## This module is the pure half of the answer: where the opposition stands,
## what the tester is handed, and what the console says it did.

const Arena = preload("res://src/gameplay/arena.gd")
const SpeciesBite = preload("res://src/gameplay/species_bite.gd")
const SpellAtomCatalog = preload("res://src/gameplay/spell_atom_catalog.gd")
const CreatureMarker = preload("res://src/rendering/creature_marker.gd")


# -- where the opposition stands -----------------------------------------

## Derived from the species' OWN senses, never picked: close enough that it
## is certain to notice you, far enough that it is not already biting. A
## fight you have to walk into is not a battletest.
func test_the_ring_is_inside_the_species_own_sense_radius():
	for species in SpeciesBite.species_list():
		var profile := SpeciesBite.profile_for(species)
		var sense_px: float = float(profile["sense_radius_tiles"]) * Arena.TILE_SIZE_PX
		assert_lt(
			Arena.ring_radius_px_for(species), sense_px,
			"%s must notice you the moment it lands" % species
		)


func test_the_ring_is_outside_the_reach_of_its_teeth():
	for species in SpeciesBite.species_list():
		assert_gt(
			Arena.ring_radius_px_for(species), Arena.ATTACK_RANGE_PX,
			"%s must not land already inside your face" % species
		)


## The restated engine numbers are held to their real sources, the same rule
## every other restated constant in this codebase follows.
func test_the_restated_ranges_are_the_real_ones():
	assert_eq(Arena.ATTACK_RANGE_PX, CreatureMarker.ATTACK_RANGE)
	assert_eq(Arena.TILE_SIZE_PX, 16, "the play-scale tile")


## A species nobody profiled still gets a workable ring rather than a zero.
func test_an_unprofiled_species_still_gets_a_real_ring():
	assert_gt(Arena.ring_radius_px_for("not_a_species"), Arena.ATTACK_RANGE_PX)


# -- spread around you, not stacked on your head -------------------------

func test_the_offsets_are_evenly_spaced_around_a_circle():
	var offsets := Arena.ring_offsets(4, 100.0)
	assert_eq(offsets.size(), 4)
	for offset in offsets:
		assert_almost_eq(offset.length(), 100.0, 0.001, "every one stands on the ring")


func test_no_two_of_them_land_on_the_same_spot():
	var offsets := Arena.ring_offsets(6, 100.0)
	for i in offsets.size():
		for j in range(i + 1, offsets.size()):
			assert_gt(
				offsets[i].distance_to(offsets[j]), 1.0,
				"two creatures stacked on one pixel is one creature"
			)


func test_a_single_opponent_stands_in_front_of_you_rather_than_behind():
	var offsets := Arena.ring_offsets(1, 100.0)
	assert_eq(offsets.size(), 1)
	assert_gt(offsets[0].x, 0.0, "the first one is where the camera is looking")


func test_asking_for_nothing_places_nothing():
	assert_eq(Arena.ring_offsets(0, 100.0).size(), 0)
	assert_eq(Arena.ring_offsets(-3, 100.0).size(), 0)


func test_the_count_is_capped_so_a_typo_cannot_spawn_a_thousand():
	assert_eq(Arena.ring_offsets(9999, 100.0).size(), Arena.MAX_OPPONENTS)


# -- and what the tester is handed ---------------------------------------

## Point 1 of the three above: without motes there is nothing to weave, so
## an arena that did not hand them over could not test a single spell.
func test_the_loadout_carries_every_atom_the_catalogue_knows():
	var catalog := SpellAtomCatalog.new()
	var motes := Arena.loadout_motes()
	for atom_id in catalog.known_ids():
		assert_true(
			motes.has(atom_id), "%s cannot be woven without its mote" % atom_id
		)
	assert_eq(motes.size(), catalog.known_ids().size(), "and nothing it does not know")


func test_every_granted_mote_is_a_real_atom():
	var catalog := SpellAtomCatalog.new()
	for atom_id in Arena.loadout_motes():
		assert_true(catalog.has(String(atom_id)), "%s is not an atom" % atom_id)


## Point 2: a warrior has max_mana 0.0 and can never cast. A battletest
## command that respected that would be unable to test the thing it exists
## for, so it lends a pool -- and says so, rather than quietly rewriting the
## character's class.
func test_a_character_with_no_pool_is_lent_one():
	assert_gt(Arena.mana_pool_for(0.0), 0.0, "a warrior must still be able to test a spell")


func test_a_character_who_already_has_a_pool_keeps_their_own():
	assert_eq(Arena.mana_pool_for(50.0), 50.0, "a mage's own pool is not overwritten")
	assert_eq(Arena.mana_pool_for(500.0), 500.0)


## Enough to actually weave something and cast it more than once, or the
## lent pool is a formality.
func test_the_lent_pool_covers_a_real_weave_several_times_over():
	var lent := Arena.mana_pool_for(0.0)
	assert_gt(
		lent, SpellAtomCatalog.new().base_cost("summon_wisp") * 3.0,
		"a lent pool must outlast the most expensive atom three casts running"
	)


# -- and it says what it did ---------------------------------------------

func test_the_report_names_what_was_staged():
	var line := Arena.report_line("wolf", 3, true)
	assert_true(line.contains("3"), "how many")
	assert_true(line.contains("wolf"), "of what")


## The lent pool is called out rather than slipped in: a tester who does not
## know their mana was topped up will misread every result that follows.
func test_the_report_admits_when_it_lent_a_mana_pool():
	assert_true(Arena.report_line("wolf", 1, true).to_lower().contains("mana"))
	assert_false(
		Arena.report_line("wolf", 1, false).to_lower().contains("mana"),
		"and stays quiet when it changed nothing"
	)


func test_the_report_is_a_sentence_rather_than_a_dump():
	var line := Arena.report_line("wolf", 3, true)
	assert_true(line.ends_with("."), "the same rule every refusal in this game follows")
	assert_false(line.contains("_"), "nothing reaches the console as an id")
