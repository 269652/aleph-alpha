extends GutTest

## Spawns/despawns MushroomMarker nodes to match a WildMushroomPatch sim's
## current fruiting cells -- WildCropRenderer's exact shape (individual
## Node2D per cell: mushrooms are sparse, and each needs its own real
## identity -- hover name/actions).

const MushroomRenderer = preload("res://src/rendering/mushroom_renderer.gd")
const WildMushroomPatch = preload("res://src/world/wild_mushroom_patch.gd")
const MushroomMarker = preload("res://src/rendering/mushroom_marker.gd")
const CrushMechanic = preload("res://src/world/crush_mechanic.gd")

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
	var markers := renderer.spawn_markers(parent, sim, CHUNK_ORIGIN, TILE_SIZE)
	assert_gt(markers.size(), 0, "precondition: this seed/biome produced at least one fruiting site")
	assert_eq(markers.size(), sim.get_fruiting_cells().size())
	assert_eq(parent.get_child_count(), markers.size())


func test_spawned_markers_are_positioned_at_their_tile_center():
	var sim := WildMushroomPatch.new(11, WIDTH, HEIGHT, _biome_all_forest())
	var markers := renderer.spawn_markers(parent, sim, CHUNK_ORIGIN, TILE_SIZE)
	for cell in markers:
		var marker: MushroomMarker = markers[cell]
		var expected := Vector2(
			(CHUNK_ORIGIN.x + cell.x + 0.5) * TILE_SIZE, (CHUNK_ORIGIN.y + cell.y + 0.5) * TILE_SIZE
		)
		assert_eq(marker.position, expected)


func test_spawned_markers_carry_the_real_species_and_the_sim_as_their_world():
	var sim := WildMushroomPatch.new(11, WIDTH, HEIGHT, _biome_all_forest())
	var markers := renderer.spawn_markers(parent, sim, CHUNK_ORIGIN, TILE_SIZE)
	for cell in markers:
		var marker: MushroomMarker = markers[cell]
		assert_eq(marker.species_id, sim.species_at(cell))
		assert_eq(marker.cell, cell)
		assert_eq(marker.mushroom_world, sim)


func _advance_until_a_new_cell_fruits(sim, max_ticks: int = 500) -> void:
	var before: int = sim.get_fruiting_cells().size()
	for i in max_ticks:
		sim.advance(1.0, 1.0)
		if sim.get_fruiting_cells().size() > before:
			return


func test_sync_markers_adds_a_marker_for_a_newly_fruiting_cell():
	var sim := WildMushroomPatch.new(11, WIDTH, HEIGHT, _biome_all_forest())
	var markers := renderer.spawn_markers(parent, sim, CHUNK_ORIGIN, TILE_SIZE)
	var before := markers.size()
	_advance_until_a_new_cell_fruits(sim)
	assert_gt(sim.get_fruiting_cells().size(), before, "precondition: a new site actually fruited")
	renderer.sync_markers(parent, sim, CHUNK_ORIGIN, TILE_SIZE, markers)
	assert_eq(markers.size(), sim.get_fruiting_cells().size())


func test_sync_markers_frees_and_removes_a_marker_whose_mushroom_was_picked():
	var sim := WildMushroomPatch.new(11, WIDTH, HEIGHT, _biome_all_forest())
	var markers := renderer.spawn_markers(parent, sim, CHUNK_ORIGIN, TILE_SIZE)
	var cell: Vector2i = markers.keys()[0]
	var marker: MushroomMarker = markers[cell]
	sim.pick(cell)
	renderer.sync_markers(parent, sim, CHUNK_ORIGIN, TILE_SIZE, markers)
	assert_false(markers.has(cell))
	assert_true(marker.is_queued_for_deletion())


# -- corpses linger instead of vanishing the instant they stop fruiting
# (see docs/concept/soil_fauna.md's "A corpse is new ground",
# WildMushroomPatch.is_corpse/corpse_kind) -- unlike a picked mushroom
# (test above), a crushed/bitten one must still show real crushed/bitten
# art rather than disappearing with the rest of the sync.

func test_sync_markers_keeps_a_marker_for_a_crushed_corpse_instead_of_freeing_it():
	var sim := WildMushroomPatch.new(11, WIDTH, HEIGHT, _biome_all_forest())
	var markers := renderer.spawn_markers(parent, sim, CHUNK_ORIGIN, TILE_SIZE)
	var cell: Vector2i = markers.keys()[0]
	var live_marker: MushroomMarker = markers[cell]
	sim.crush(cell, CrushMechanic.CRUSH_MOMENTUM_THRESHOLD_KG_M_S * 10.0)
	renderer.sync_markers(parent, sim, CHUNK_ORIGIN, TILE_SIZE, markers)
	assert_true(markers.has(cell), "a crushed corpse should still have a marker, not be freed like a pick")
	assert_true(live_marker.is_queued_for_deletion(), "the old LIVE marker is still freed -- a fresh corpse marker replaces it")
	var corpse_marker: MushroomMarker = markers[cell]
	assert_eq(corpse_marker.corpse_kind, "crushed")


func test_sync_markers_keeps_a_marker_for_a_bitten_corpse():
	var sim := WildMushroomPatch.new(11, WIDTH, HEIGHT, _biome_all_forest())
	var markers := renderer.spawn_markers(parent, sim, CHUNK_ORIGIN, TILE_SIZE)
	var cell: Vector2i = markers.keys()[0]
	sim.bite(cell)
	renderer.sync_markers(parent, sim, CHUNK_ORIGIN, TILE_SIZE, markers)
	assert_true(markers.has(cell), "a bitten corpse should still have a marker")
	var corpse_marker: MushroomMarker = markers[cell]
	assert_eq(corpse_marker.corpse_kind, "bitten")


func test_sync_markers_frees_the_corpse_once_recovery_expires():
	var sim := WildMushroomPatch.new(11, WIDTH, HEIGHT, _biome_all_forest())
	var markers := renderer.spawn_markers(parent, sim, CHUNK_ORIGIN, TILE_SIZE)
	var cell: Vector2i = markers.keys()[0]
	sim.crush(cell, CrushMechanic.CRUSH_MOMENTUM_THRESHOLD_KG_M_S * 10.0)
	renderer.sync_markers(parent, sim, CHUNK_ORIGIN, TILE_SIZE, markers)
	var corpse_marker: MushroomMarker = markers[cell]
	sim.advance(WildMushroomPatch.SPENT_SECONDS + 1.0, 0.0)
	renderer.sync_markers(parent, sim, CHUNK_ORIGIN, TILE_SIZE, markers)
	assert_false(markers.has(cell), "the corpse marker should be freed once the site can fruit fresh again")
	assert_true(corpse_marker.is_queued_for_deletion())
