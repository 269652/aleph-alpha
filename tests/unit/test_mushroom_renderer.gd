extends GutTest

## Spawns/despawns MushroomMarker nodes to match a WildMushroomPatch sim's
## current fruiting cells -- WildCropRenderer's exact shape (individual
## Node2D per cell: mushrooms are sparse, and each needs its own real
## identity -- hover name/actions, an independent identification state).

const MushroomRenderer = preload("res://src/rendering/mushroom_renderer.gd")
const WildMushroomPatch = preload("res://src/world/wild_mushroom_patch.gd")
const MushroomMarker = preload("res://src/rendering/mushroom_marker.gd")

const TILE_SIZE := 16.0
const CHUNK_ORIGIN := Vector2i(100, 200)
const WIDTH := 40
const HEIGHT := 40

var renderer: MushroomRenderer
var parent: Node2D


func before_each():
	renderer = MushroomRenderer.new()
	parent = Node2D.new()
	add_child_autofree(parent)


func _biome_all_forest() -> PackedStringArray:
	var biome := PackedStringArray()
	biome.resize(WIDTH * HEIGHT)
	biome.fill("forest")
	return biome


func test_spawn_markers_makes_one_marker_per_fruiting_cell():
	var sim := WildMushroomPatch.new(11, WIDTH, HEIGHT, _biome_all_forest())
	var markers := renderer.spawn_markers(parent, sim, CHUNK_ORIGIN, TILE_SIZE, false)
	assert_gt(markers.size(), 0, "precondition: this seed/biome produced at least one fruiting site")
	assert_eq(markers.size(), sim.get_fruiting_cells().size())
	assert_eq(parent.get_child_count(), markers.size())


func test_spawned_markers_are_positioned_at_their_tile_center():
	var sim := WildMushroomPatch.new(11, WIDTH, HEIGHT, _biome_all_forest())
	var markers := renderer.spawn_markers(parent, sim, CHUNK_ORIGIN, TILE_SIZE, false)
	for cell in markers:
		var marker: MushroomMarker = markers[cell]
		var expected := Vector2(
			(CHUNK_ORIGIN.x + cell.x + 0.5) * TILE_SIZE, (CHUNK_ORIGIN.y + cell.y + 0.5) * TILE_SIZE
		)
		assert_eq(marker.position, expected)


func test_spawned_markers_carry_the_real_species_and_the_sim_as_their_world():
	var sim := WildMushroomPatch.new(11, WIDTH, HEIGHT, _biome_all_forest())
	var markers := renderer.spawn_markers(parent, sim, CHUNK_ORIGIN, TILE_SIZE, false)
	for cell in markers:
		var marker: MushroomMarker = markers[cell]
		assert_eq(marker.species_id, sim.species_at(cell))
		assert_eq(marker.cell, cell)
		assert_eq(marker.mushroom_world, sim)


func test_spawned_markers_carry_the_current_identification_state():
	var sim := WildMushroomPatch.new(11, WIDTH, HEIGHT, _biome_all_forest())
	var markers := renderer.spawn_markers(parent, sim, CHUNK_ORIGIN, TILE_SIZE, true)
	assert_gt(markers.size(), 0, "precondition: something got spawned")
	for cell in markers:
		assert_true(markers[cell].identified)


func _advance_until_a_new_cell_fruits(sim, max_ticks: int = 500) -> void:
	var before: int = sim.get_fruiting_cells().size()
	for i in max_ticks:
		sim.advance(1.0, 1.0)
		if sim.get_fruiting_cells().size() > before:
			return


func test_sync_markers_adds_a_marker_for_a_newly_fruiting_cell():
	var sim := WildMushroomPatch.new(11, WIDTH, HEIGHT, _biome_all_forest())
	var markers := renderer.spawn_markers(parent, sim, CHUNK_ORIGIN, TILE_SIZE, false)
	var before := markers.size()
	_advance_until_a_new_cell_fruits(sim)
	assert_gt(sim.get_fruiting_cells().size(), before, "precondition: a new site actually fruited")
	renderer.sync_markers(parent, sim, CHUNK_ORIGIN, TILE_SIZE, false, markers)
	assert_eq(markers.size(), sim.get_fruiting_cells().size())


func test_sync_markers_frees_and_removes_a_marker_whose_mushroom_was_picked():
	var sim := WildMushroomPatch.new(11, WIDTH, HEIGHT, _biome_all_forest())
	var markers := renderer.spawn_markers(parent, sim, CHUNK_ORIGIN, TILE_SIZE, false)
	var cell: Vector2i = markers.keys()[0]
	var marker: MushroomMarker = markers[cell]
	sim.pick(cell)
	renderer.sync_markers(parent, sim, CHUNK_ORIGIN, TILE_SIZE, false, markers)
	assert_false(markers.has(cell))
	assert_true(marker.is_queued_for_deletion())


# -- identification reaches the markers this renderer owns, live -----------
#
# Player.knows_mushrooms() can flip false -> true mid-play; a marker
# spawned before that moment has to show it the next sync, not wait for a
# respawn (see MushroomMarker's own identified setter).

func test_syncing_pushes_newly_learned_identification_onto_every_live_marker():
	var sim := WildMushroomPatch.new(11, WIDTH, HEIGHT, _biome_all_forest())
	var markers := renderer.spawn_markers(parent, sim, CHUNK_ORIGIN, TILE_SIZE, false)
	assert_gt(markers.size(), 0, "precondition: something got spawned")
	renderer.sync_markers(parent, sim, CHUNK_ORIGIN, TILE_SIZE, true, markers)
	for cell in markers:
		assert_true(markers[cell].identified)


func test_a_caller_that_never_learns_identification_keeps_markers_unidentified():
	var sim := WildMushroomPatch.new(11, WIDTH, HEIGHT, _biome_all_forest())
	var markers := renderer.spawn_markers(parent, sim, CHUNK_ORIGIN, TILE_SIZE, false)
	renderer.sync_markers(parent, sim, CHUNK_ORIGIN, TILE_SIZE, false, markers)
	for cell in markers:
		assert_false(markers[cell].identified)
