extends GutTest

## Blood marks on the ground: the world half of the trail (see
## docs/concept/olfaction.md, "Blood: the trail a wounded animal leaves").
##
## The marks are visible AND smellable -- they emit into the same
## `smells_near` field baits and carried food already use, so a predator's
## nose needs to be told nothing new about them.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const BloodTrail = preload("res://src/gameplay/blood_trail.gd")
const Olfaction = preload("res://src/gameplay/olfaction.gd")

var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var manager: EarthChunkManager
var _spawn: Vector2


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	var geo := GeoCoordinates.new()
	var tile := Vector2i(
		geo.tile_for_longitude(13.405, EarthChunkGenerator.WORLD_WIDTH_TILES),
		geo.tile_for_latitude(52.52, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	)
	manager.update(tile)
	_spawn = Vector2(tile) * 16.0


func after_each():
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


func _blood_smells_at(position: Vector2) -> Array:
	var found: Array = []
	for smell in manager.smells_near(position, 6.0):
		if float(smell["mixture"].get(Olfaction.BLOOD, 0.0)) > 0.0:
			found.append(smell)
	return found


func test_a_dropped_mark_can_be_smelled():
	manager.drop_blood_at(_spawn)
	assert_gt(_blood_smells_at(_spawn).size(), 0, "a fresh blood mark smells of nothing")


func test_nothing_smells_of_blood_before_anything_bleeds():
	assert_eq(_blood_smells_at(_spawn).size(), 0)


## The trail leads somewhere: marks laid along a path are each findable from
## where they fell, which is what makes following one possible at all.
func test_a_trail_of_marks_leads_along_the_path_it_was_laid_on():
	var walked: Array[Vector2] = []
	for step in 5:
		var at := _spawn + Vector2(float(step) * BloodTrail.SPACING_PX, 0.0)
		manager.drop_blood_at(at)
		walked.append(at)
	for at in walked:
		assert_gt(_blood_smells_at(at).size(), 0, "the trail has a hole in it at %s" % at)


## A trail is a window, not a permanent annotation.
func test_marks_stop_smelling_of_blood_once_they_are_stale():
	manager.drop_blood_at(_spawn)
	manager.step_blood_marks(BloodTrail.MARK_LIFETIME_SECONDS + 1.0)
	assert_eq(_blood_smells_at(_spawn).size(), 0, "a stale mark is still being tracked")


## ...and it goes over rather than simply going quiet: an old mark reads as
## carrion, which is a scavenger's signal rather than a hunter's.
func test_an_ageing_mark_turns_from_blood_to_carrion():
	manager.drop_blood_at(_spawn)
	manager.step_blood_marks(BloodTrail.MARK_LIFETIME_SECONDS * 0.85)
	var smells := manager.smells_near(_spawn, 6.0)
	var found := false
	for smell in smells:
		var mixture: Dictionary = smell["mixture"]
		if float(mixture.get(Olfaction.DECAY, 0.0)) > float(mixture.get(Olfaction.BLOOD, 0.0)):
			found = true
	assert_true(found, "an old mark never turns to carrion")


## Bounded like every other decoration: scenery that accumulates forever is a
## leak with a sprite (the same reasoning drop_guano_at's own cap gives).
func test_blood_marks_are_bounded():
	for step in EarthChunkManager.MAX_BLOOD_MARKS * 3:
		manager.drop_blood_at(_spawn + Vector2(float(step) * 4.0, 0.0))
	assert_lte(manager.blood_mark_count(), EarthChunkManager.MAX_BLOOD_MARKS)


## The oldest go first, so a fresh trail is never eaten by an old one.
func test_the_oldest_marks_are_the_ones_dropped():
	manager.drop_blood_at(_spawn)
	var newest := _spawn + Vector2(2000.0, 0.0)
	for step in EarthChunkManager.MAX_BLOOD_MARKS:
		manager.drop_blood_at(newest)
	assert_eq(_blood_smells_at(_spawn).size(), 0, "the oldest mark outlived the cap")
	assert_gt(_blood_smells_at(newest).size(), 0)
