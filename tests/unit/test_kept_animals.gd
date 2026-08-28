extends GutTest

## Animals the player has a stake in -- tamed, tied to a tree, or part-way
## tamed -- persisted as INDIVIDUALS rather than as a number in a region's
## aggregate (see docs/concept/taming.md).
##
## The aggregate model is the right home for a herd: away from the player a
## population is a count that grows and migrates, and the specific animals it
## stands for are interchangeable. A horse the player spent an evening winning
## over is not interchangeable. It is a particular animal, in a particular
## place, with the trust it earned -- and it has to still be there tomorrow.

const KeptAnimals = preload("res://src/world/kept_animals.gd")
const Taming = preload("res://src/gameplay/taming.gd")


func _record(species: String, position: Vector2, trust: float) -> Dictionary:
	return {
		"species": species,
		"position": position,
		"trust": trust,
		"order": Taming.ORDER_STAY,
		"tied_to": Vector2.ZERO,
		"is_tied": false,
		"wander_seed": 0,
	}


# -- who is worth keeping ----------------------------------------------------

## A fully tamed animal is the player's, wherever it is.
func test_a_tamed_animal_is_kept():
	assert_true(KeptAnimals.is_worth_keeping(Taming.TAME_TRUST, false))


## So is one still being won over: losing a half-tamed horse to a chunk
## boundary would throw away the carrots already spent on it.
func test_an_animal_part_way_to_tame_is_kept():
	assert_true(KeptAnimals.is_worth_keeping(Taming.TRUST_PER_FEED, false))


## And one tied to a tree, even at zero trust -- the player put it there on
## purpose and expects to find it there.
func test_an_animal_tied_to_a_tree_is_kept():
	assert_true(KeptAnimals.is_worth_keeping(0.0, true))


## An ordinary wild animal is NOT: it belongs to the aggregate, and keeping
## every deer individually would be a save file that grows without bound.
func test_a_wild_animal_is_not_kept():
	assert_false(KeptAnimals.is_worth_keeping(0.0, false))


# -- the record round-trips --------------------------------------------------

func test_a_kept_animal_survives_being_written_and_read():
	var path := "user://test_kept.bin"
	var horse := _record("horse", Vector2(123.5, -64.25), 0.6)
	KeptAnimals.save_all([horse], path)
	var loaded := KeptAnimals.load_all(path)
	assert_eq(loaded.size(), 1)
	assert_eq(String(loaded[0]["species"]), "horse")
	assert_almost_eq(Vector2(loaded[0]["position"]).x, 123.5, 0.01)
	assert_almost_eq(Vector2(loaded[0]["position"]).y, -64.25, 0.01)
	assert_almost_eq(float(loaded[0]["trust"]), 0.6, 0.001)
	DirAccess.remove_absolute(path)


## A horse the player spent an evening winning over is a PARTICULAR animal
## (see this file's own doc comment) -- its individuality (AnimalFitness's
## strength/agility/coat_vibrancy phenotype, all deterministic from this one
## seed) has to survive a reload too, not just its trust/position/tied state.
func test_a_kept_animal_remembers_its_own_wander_seed():
	var path := "user://test_kept_wander_seed.bin"
	var horse := _record("horse", Vector2.ZERO, 1.0)
	horse["wander_seed"] = 918273
	KeptAnimals.save_all([horse], path)
	assert_eq(int(KeptAnimals.load_all(path)[0]["wander_seed"]), 918273)
	DirAccess.remove_absolute(path)


## The whole point of keeping a tied animal: where it was tied is where it
## still is.
func test_a_tied_animal_remembers_what_it_was_tied_to():
	var path := "user://test_kept_tied.bin"
	var horse := _record("horse", Vector2(10, 20), 0.4)
	horse["is_tied"] = true
	horse["tied_to"] = Vector2(48.0, 96.0)
	KeptAnimals.save_all([horse], path)
	var loaded := KeptAnimals.load_all(path)
	assert_true(bool(loaded[0]["is_tied"]))
	assert_almost_eq(Vector2(loaded[0]["tied_to"]).x, 48.0, 0.01)
	DirAccess.remove_absolute(path)


func test_a_tamed_animal_remembers_what_it_was_told_to_do():
	var path := "user://test_kept_order.bin"
	var horse := _record("horse", Vector2.ZERO, 1.0)
	horse["order"] = Taming.ORDER_FOLLOW
	KeptAnimals.save_all([horse], path)
	assert_eq(int(KeptAnimals.load_all(path)[0]["order"]), Taming.ORDER_FOLLOW)
	DirAccess.remove_absolute(path)


func test_several_kept_animals_all_survive():
	var path := "user://test_kept_many.bin"
	var animals := []
	for i in 5:
		animals.append(_record("horse", Vector2(float(i) * 10.0, 0.0), 1.0))
	KeptAnimals.save_all(animals, path)
	assert_eq(KeptAnimals.load_all(path).size(), 5)
	DirAccess.remove_absolute(path)


func test_reading_a_file_that_does_not_exist_yields_nothing():
	assert_eq(KeptAnimals.load_all("user://no_such_kept_file.bin").size(), 0)


## Saving nothing must CLEAR the record, not leave yesterday's horse behind --
## an animal that died, or was released, is gone.
func test_saving_an_empty_list_clears_the_record():
	var path := "user://test_kept_clear.bin"
	KeptAnimals.save_all([_record("horse", Vector2.ZERO, 1.0)], path)
	assert_eq(KeptAnimals.load_all(path).size(), 1)
	KeptAnimals.save_all([], path)
	assert_eq(KeptAnimals.load_all(path).size(), 0, "a released animal must not come back")
	DirAccess.remove_absolute(path)
