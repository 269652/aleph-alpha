extends GutTest

## A wild juvenile's own age/growth -- NOT the player's stake in an animal
## (see KeptAnimals/test_kept_animals.gd for that, a different reason to
## persist an individual). See src/world/growing_juveniles.gd's own doc
## comment for why persisting this bounded set does not reopen
## KeptAnimals' "no unbounded per-animal saves" rule.

const GrowingJuveniles = preload("res://src/world/growing_juveniles.gd")


func _record(species: String, position: Vector2, age_seconds: float, wander_seed: int) -> Dictionary:
	return {
		"species": species,
		"position": position,
		"age_seconds": age_seconds,
		"wander_seed": wander_seed,
	}


# -- who is worth persisting --------------------------------------------------

## A newborn, well under its species' own mature_seconds_for, is still
## growing and worth persisting.
func test_a_newborn_is_worth_persisting():
	assert_true(GrowingJuveniles.is_worth_persisting(0.0, "horse"))


## A fully-grown individual is exactly as interchangeable as any other wild
## adult -- it belongs back in the aggregate, not this file.
func test_a_fully_grown_individual_is_not_worth_persisting():
	assert_false(GrowingJuveniles.is_worth_persisting(999999999.0, "horse"))


## Right at its own species' maturity threshold, an individual is (barely)
## grown -- mirrors MammalGrowth.is_mature's own inclusive boundary.
func test_an_individual_exactly_at_its_maturity_threshold_is_not_worth_persisting():
	const MammalGrowth = preload("res://src/gameplay/mammal_growth.gd")
	var mature_seconds := MammalGrowth.mature_seconds_for("horse")
	assert_false(GrowingJuveniles.is_worth_persisting(mature_seconds, "horse"))


# -- the record round-trips --------------------------------------------------

func test_a_growing_juvenile_survives_being_written_and_read():
	var path := "user://test_growing_juveniles.bin"
	var fawn := _record("deer", Vector2(88.0, -12.5), 4200.0, 55555)
	GrowingJuveniles.save_all([fawn], path)
	var loaded: Array = GrowingJuveniles.load_all(path)
	assert_eq(loaded.size(), 1)
	assert_eq(String(loaded[0]["species"]), "deer")
	assert_almost_eq(Vector2(loaded[0]["position"]).x, 88.0, 0.01)
	assert_almost_eq(Vector2(loaded[0]["position"]).y, -12.5, 0.01)
	assert_almost_eq(float(loaded[0]["age_seconds"]), 4200.0, 0.01)
	assert_eq(int(loaded[0]["wander_seed"]), 55555)
	DirAccess.remove_absolute(path)


## The same individuality point KeptAnimals makes for a tamed horse's
## phenotype applies here too: a juvenile that comes back with a re-rolled
## wander_seed would be a DIFFERENT individual with a different AnimalFitness
## phenotype, not the same fawn grown a little older.
func test_a_growing_juvenile_remembers_its_own_wander_seed():
	var path := "user://test_growing_juveniles_seed.bin"
	var fawn := _record("deer", Vector2.ZERO, 0.0, 918273)
	GrowingJuveniles.save_all([fawn], path)
	assert_eq(int(GrowingJuveniles.load_all(path)[0]["wander_seed"]), 918273)
	DirAccess.remove_absolute(path)


func test_several_growing_juveniles_all_survive():
	var path := "user://test_growing_juveniles_many.bin"
	var juveniles := []
	for i in 5:
		juveniles.append(_record("horse", Vector2(float(i) * 10.0, 0.0), float(i) * 100.0, i))
	GrowingJuveniles.save_all(juveniles, path)
	assert_eq(GrowingJuveniles.load_all(path).size(), 5)
	DirAccess.remove_absolute(path)


func test_reading_a_file_that_does_not_exist_yields_nothing():
	assert_eq(GrowingJuveniles.load_all("user://no_such_growing_juveniles_file.bin").size(), 0)


## Saving nothing must CLEAR the record, not leave yesterday's fawn behind --
## one that grew up (or died) since the last unload is gone from this file.
func test_saving_an_empty_list_clears_the_record():
	var path := "user://test_growing_juveniles_clear.bin"
	GrowingJuveniles.save_all([_record("deer", Vector2.ZERO, 0.0, 1)], path)
	assert_eq(GrowingJuveniles.load_all(path).size(), 1)
	GrowingJuveniles.save_all([], path)
	assert_eq(
		GrowingJuveniles.load_all(path).size(), 0,
		"a grown-up (or gone) juvenile must not come back"
	)
	DirAccess.remove_absolute(path)


## A file written by a different FORMAT_VERSION is dropped rather than read
## as garbage -- mirrors KeptAnimals' own convention (see
## growing_juveniles.gd's own doc comment on why this is an acceptable cost
## for a small, bounded set).
func test_a_file_from_a_different_format_version_is_dropped():
	var path := "user://test_growing_juveniles_bad_version.bin"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_32(GrowingJuveniles.FORMAT_VERSION + 1)
	file.store_32(1)
	file.close()
	assert_eq(GrowingJuveniles.load_all(path).size(), 0)
	DirAccess.remove_absolute(path)
