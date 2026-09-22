extends GutTest

## What a kill is worth (docs/concept/items.md, ecosystem_dynamics.md).
##
## Measured before this: `LootTable._DROPS` had four keys -- herbivore,
## boar, predator, lynx -- and TWO of them are retired anonymous
## placeholders that no biome pool spawns any more. So killing a deer, a
## wolf, a bear, a lion, a jaguar, a horse or anything else in the live
## roster dropped literally nothing, and `_spawn_carcass_if_eligible`
## early-returns when `drops_for` is empty, so it did not even leave a body.
##
## A player learns within minutes that fighting is a pure cost with no
## upside, which is why predators read as obstacles to route around rather
## than as things to hunt.
##
## The counts are DERIVED from each animal's real mass rather than authored
## per species, so adding a creature to a pool cannot leave it worthless and
## nobody has to eyeball a number for eleven species.

const LootTable = preload("res://src/gameplay/loot_table.gd")
const CreatureRenderer = preload("res://src/rendering/creature_renderer.gd")
const CreatureMass = preload("res://src/world/creature_mass.gd")
const CreatureInfo = preload("res://src/world/creature_info.gd")
const Butchering = preload("res://src/gameplay/butchering.gd")


func _live_species() -> Array:
	var seen := {}
	for table in [
		CreatureRenderer.HERBIVORE_SPECIES_POOL_BY_BIOME,
		CreatureRenderer.PREDATOR_SPECIES_POOL_BY_BIOME,
	]:
		for biome in table:
			for species in table[biome]:
				seen[String(species)] = true
	return seen.keys()


func _total_of(species: String, item_id: String) -> int:
	var total := 0
	for stack in LootTable.new().drops_for(species):
		if stack.item.id == item_id:
			total += stack.count
	return total


# -- every species the world really spawns leaves a body -----------------

## The two-way drift test: a creature added to a biome pool cannot ship
## worthless, and a drop row for a species nothing spawns is dead weight.
func test_every_species_the_world_spawns_drops_something():
	var live := _live_species()
	assert_gt(live.size(), 10, "precondition: the roster is real")
	for species in live:
		assert_gt(
			LootTable.new().drops_for(species).size(), 0,
			"%s is spawned by a real biome pool and drops nothing" % species
		)


func test_a_species_nobody_spawns_drops_nothing():
	assert_eq(
		LootTable.new().drops_for("not_a_species").size(), 0,
		"an unknown species is not a silent handful of meat"
	)


# -- meat is the animal's own mass ---------------------------------------

## Derived, not authored: a bear is worth more meat than a squirrel because
## a bear IS more meat, through the same CreatureMass table every other
## real-world-grounded size in this codebase reads.
func test_a_heavier_animal_yields_more_meat():
	assert_gt(
		_total_of("bear", "meat"), _total_of("deer", "meat"),
		"three hundred kilos of bear is more meat than a deer"
	)
	assert_gt(_total_of("deer", "meat"), _total_of("squirrel", "meat"))


## The calibration is the row that already existed, so this change does not
## quietly rebalance the one species the game had tuned.
func test_the_boar_still_yields_what_it_always_did():
	assert_eq(_total_of("boar", "meat"), 2, "the existing boar row is the anchor")


func test_meat_never_rounds_away_to_nothing():
	for species in _live_species():
		assert_gt(
			_total_of(species, "meat"), 0,
			"%s must be worth at least one meal" % species
		)


func test_the_yield_is_monotone_in_mass():
	var live := _live_species()
	for a in live:
		for b in live:
			if CreatureMass.mass_kg_for(a) > CreatureMass.mass_kg_for(b):
				assert_true(
					_total_of(a, "meat") >= _total_of(b, "meat"),
					"%s outweighs %s and must not yield less meat" % [a, b]
				)


# -- a hide, and a fang --------------------------------------------------

## One animal, one skin -- a hide is not a function of mass, it is a fact
## about having been an animal. But you do not skin a mouse.
func test_an_animal_worth_skinning_yields_exactly_one_hide():
	assert_eq(_total_of("bear", "hide"), 1)
	assert_eq(_total_of("deer", "hide"), 1)


func test_nothing_too_small_to_skin_yields_a_hide():
	assert_eq(_total_of("mouse", "hide"), 0, "nobody skins a mouse")


## A fang comes off something that had fangs.
func test_predators_yield_a_fang_and_grazers_do_not():
	assert_gt(_total_of("wolf", "fang"), 0)
	assert_gt(_total_of("bear", "fang"), 0)
	assert_eq(_total_of("deer", "fang"), 0, "a deer has no fang to take")
	for species in _live_species():
		var has_fang := _total_of(species, "fang") > 0
		assert_eq(
			has_fang, bool(CreatureInfo.PREDATOR_SPECIES.get(species, false)),
			"%s's fang does not match whether it is a predator" % species
		)


# -- and the stacks are real ---------------------------------------------

func test_every_drop_is_a_real_stack_with_a_real_item():
	for species in _live_species():
		for stack in LootTable.new().drops_for(species):
			assert_not_null(stack.item, "%s dropped a null item" % species)
			assert_ne(String(stack.item.id), "", "%s dropped an id-less item" % species)
			assert_gt(stack.count, 0, "%s dropped an empty stack" % species)


func test_the_stacks_are_fresh_each_call():
	var first := LootTable.new().drops_for("bear")
	var second := LootTable.new().drops_for("bear")
	assert_ne(first[0], second[0], "a caller must be free to mutate what it was handed")


## One rule, in one place. This table decides whether there is a body at
## all; what the body is worth is `Butchering`'s arithmetic, and a second
## opinion about it here is exactly how two numbers drift apart.
func test_the_meat_count_is_butcherings_own():
	for species in ["mouse", "squirrel", "deer", "boar", "bear", "horse"]:
		assert_eq(LootTable.new().meat_for(species), Butchering.base_meat_for(species), species)
