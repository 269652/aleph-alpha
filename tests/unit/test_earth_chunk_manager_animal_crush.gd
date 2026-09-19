extends GutTest

## EarthChunkManager's ANIMAL-side crush detection (see docs/concept/
## soil_fauna.md "Generalized to ANY animal", CrushMechanic.crushes_
## underfoot).
##
## Reported in play: "Stepping on a frog doesn't kill it? Shouldn't this
## work out of the box for ANY animal when enough pressure is put on it? A
## boar walking over a frog should kill it as well". The physics was already
## general and both steppers were already real -- what was missing is that
## every victim wired up until now (worms, caterpillars, millipedes, ants,
## decomposers) is a small special-case invertebrate. A frog is a
## GrassFrogMarker; a mouse is a CreatureMarker; neither was crushable by
## anything.
##
## These two detection sides differ in exactly one way, and it is the reason
## they are two functions rather than one. A frog is chunk-keyed in this
## manager's own tracking dictionary, like a caterpillar, and every frog
## weighs the same, so its victim mass is a species constant. A creature is
## NOT tracked here at all -- it lives in the scene tree, and World already
## holds a cached group list of them -- and every creature weighs something
## different, so the victim term is read per marker from its own live mass.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const CrushMechanic = preload("res://src/world/crush_mechanic.gd")
const CreatureMass = preload("res://src/world/creature_mass.gd")
const CreatureMarker = preload("res://src/rendering/creature_marker.gd")
const CreatureInfo = preload("res://src/world/creature_info.gd")
const GrassFrogMarker = preload("res://src/rendering/grass_frog_marker.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

## Real stepper masses, read from the same table the live game reads -- never
## a test-only figure.
const PLAYER := CreatureMass.PLAYER_MASS_KG

var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)


func after_each():
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


func _pixel_for(cell: Vector2i) -> Vector2:
	return Vector2(float(cell.x) + 0.5, float(cell.y) + 0.5) * float(TerrainRenderer.TILE_SIZE)


func _chunk_coord_for_cell(cell: Vector2i) -> Vector2i:
	return Vector2i(
		floori(float(cell.x) / EarthChunkManager.CHUNK_SIZE),
		floori(float(cell.y) / EarthChunkManager.CHUNK_SIZE)
	)


func _frog_at(cell: Vector2i) -> GrassFrogMarker:
	var frog := GrassFrogMarker.new()
	frog.position = _pixel_for(cell)
	frog.home = frog.position
	add_child_autofree(frog)
	var chunk_coord := _chunk_coord_for_cell(cell)
	var frogs: Array = manager._grass_frog_markers.get(chunk_coord, [])
	frogs.append(frog)
	manager._grass_frog_markers[chunk_coord] = frogs
	return frog


func _creature_at(species: String, cell: Vector2i) -> CreatureMarker:
	var creature := CreatureMarker.new()
	creature.info = CreatureInfo.new(species)
	creature.position = _pixel_for(cell)
	creature.home = creature.position
	add_child_autofree(creature)
	return creature


# -- the frog the report is about -------------------------------------------


func test_a_person_stepping_on_a_frog_crushes_it():
	var cell := Vector2i(5, 5)
	var frog := _frog_at(cell)

	assert_true(manager.crush_grass_frogs_near(_pixel_for(cell), PLAYER))

	assert_true(frog._dying, "the frog should start dying immediately")
	assert_false(
		manager._grass_frog_markers[_chunk_coord_for_cell(cell)].has(frog),
		"and drop out of tracking at once, so a chunk unload never double-frees it"
	)


## The other half of the report, word for word: "A boar walking over a frog
## should kill it as well."
func test_a_boar_walking_over_a_frog_kills_it_as_well():
	var cell := Vector2i(6, 6)
	var frog := _frog_at(cell)

	assert_true(manager.crush_grass_frogs_near(_pixel_for(cell), CreatureMass.mass_kg_for("boar")))

	assert_true(frog._dying)


func test_a_mouse_running_over_a_frog_does_not():
	var cell := Vector2i(7, 7)
	var frog := _frog_at(cell)

	assert_false(manager.crush_grass_frogs_near(_pixel_for(cell), CreatureMass.mass_kg_for("mouse")))

	assert_false(frog._dying, "a mouse weighs too little to crush anything at all")


func test_a_frog_on_another_tile_is_not_stepped_on():
	var frog := _frog_at(Vector2i(5, 5))

	assert_false(manager.crush_grass_frogs_near(_pixel_for(Vector2i(20, 20)), PLAYER))

	assert_false(frog._dying)


func test_stepping_where_there_are_no_frogs_is_not_an_error():
	assert_false(manager.crush_grass_frogs_near(Vector2(-9000000, -9000000), PLAYER))


## Not a second rule of its own: whether a frog is crushed is exactly
## CrushMechanic's own answer for a frog's own tabulated mass, for every
## stepper the game has.
func test_a_frogs_crushing_is_exactly_the_shared_rule_at_a_frogs_own_mass():
	var frog_mass: float = CreatureMass.mass_kg_for(GrassFrogMarker.SPECIES)
	var cell := Vector2i(9, 9)
	for stepper in ["mouse", "squirrel", "arctic_fox", "jackal", "wolf", "deer", "boar", "horse"]:
		var frog := _frog_at(cell)
		var stepper_mass: float = CreatureMass.mass_kg_for(stepper)
		assert_eq(
			manager.crush_grass_frogs_near(_pixel_for(cell), stepper_mass),
			CrushMechanic.crushes_underfoot(stepper_mass, frog_mass),
			"%s stepping on a frog" % stepper
		)
		manager._grass_frog_markers.clear()
		frog.queue_free()


# -- and any real animal ----------------------------------------------------


func test_a_horse_crushes_a_mouse_underfoot():
	var cell := Vector2i(5, 5)
	var mouse := _creature_at("mouse", cell)
	var horse: float = CreatureMass.mass_kg_for("horse")

	assert_true(manager.crush_creatures_near([mouse], _pixel_for(cell), horse))

	assert_true(mouse.info.health <= 0.0, "a mouse under a horse's foot is dead")


## The case momentum alone gets wrong, and the whole reason the victim term
## exists: a horse crushes worms all day and still does not flatten a wolf.
func test_a_horse_does_not_crush_a_wolf_it_stands_on():
	var cell := Vector2i(5, 5)
	var wolf := _creature_at("wolf", cell)

	assert_false(manager.crush_creatures_near([wolf], _pixel_for(cell), CreatureMass.mass_kg_for("horse")))

	assert_gt(wolf.info.health, 0.0)


func test_an_animal_on_another_tile_is_not_stepped_on():
	var mouse := _creature_at("mouse", Vector2i(5, 5))

	assert_false(manager.crush_creatures_near([mouse], _pixel_for(Vector2i(20, 20)), CreatureMass.mass_kg_for("horse")))

	assert_gt(mouse.info.health, 0.0)


## Nothing crushes itself -- a stepper is always far heavier than its own
## foot, so the rule alone rules this out even before the caller excludes it.
func test_a_creature_standing_on_its_own_tile_never_crushes_itself():
	var cell := Vector2i(5, 5)
	var mouse := _creature_at("mouse", cell)

	assert_false(manager.crush_creatures_near([mouse], _pixel_for(cell), mouse.current_mass_kg(), mouse))
	assert_false(manager.crush_creatures_near([mouse], _pixel_for(cell), mouse.current_mass_kg()))

	assert_gt(mouse.info.health, 0.0)


## A heavy creature that happens to be standing on the same tile as the
## stepper is still excluded explicitly -- the caller's own identity guard,
## independent of the mass rule that already covers it.
func test_the_stepper_is_excluded_from_its_own_scan():
	var cell := Vector2i(5, 5)
	var mouse := _creature_at("mouse", cell)

	assert_false(
		manager.crush_creatures_near([mouse], _pixel_for(cell), CreatureMass.mass_kg_for("horse"), mouse),
		"a horse-heavy stepper still cannot crush the creature that IS the stepper"
	)
	assert_gt(mouse.info.health, 0.0)


## Each victim is weighed on its own, not as a group: a herd of mixed sizes
## standing on one tile loses only the ones that fit under the foot.
func test_only_the_animals_light_enough_to_go_under_the_foot_die():
	var cell := Vector2i(5, 5)
	var mouse := _creature_at("mouse", cell)
	var squirrel := _creature_at("squirrel", cell)
	var jackal := _creature_at("jackal", cell)

	assert_true(manager.crush_creatures_near([mouse, squirrel, jackal], _pixel_for(cell), CreatureMass.PLAYER_MASS_KG))

	assert_true(mouse.info.health <= 0.0, "a mouse goes under a boot")
	assert_true(squirrel.info.health <= 0.0, "so does a squirrel, at half a kilo")
	assert_gt(jackal.info.health, 0.0, "a ten-kilo jackal does not")


func test_stepping_among_no_animals_at_all_is_not_an_error():
	assert_false(manager.crush_creatures_near([], _pixel_for(Vector2i(5, 5)), CreatureMass.mass_kg_for("horse")))


## A creature already freed elsewhere this frame must not crash the scan --
## the same defensive contract _crush_markers_near already documents for a
## stale marker reference.
func test_a_stale_marker_in_the_list_is_skipped_rather_than_crashing():
	var cell := Vector2i(5, 5)
	var mouse := _creature_at("mouse", cell)
	mouse.queue_free()

	assert_false(manager.crush_creatures_near([mouse], _pixel_for(cell), CreatureMass.mass_kg_for("horse")))
