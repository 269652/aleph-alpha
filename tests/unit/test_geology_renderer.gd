extends GutTest

## GeologyRenderer: spawns cave-entrance markers on the surface and reveals
## a real Strata-sourced diggable-rock chamber on entry (see
## docs/concept/geology.md "Reveal-on-entry, reused recursively"). Same
## deterministic-coordinate-finding style as test_ore_placement.gd's
## _find_stone_cell -- entrances are sparse, so tests locate a real one
## rather than hoping a small synthetic chunk happens to contain one.

const GeologyRenderer = preload("res://src/rendering/geology_renderer.gd")
const CaveEntrancePlacement = preload("res://src/world/cave_entrance_placement.gd")
const Strata = preload("res://src/world/strata.gd")
const GeologyChamber = preload("res://src/world/geology_chamber.gd")
const DiggableRock = preload("res://src/rendering/diggable_rock.gd")

const TILE_SIZE := 16

var renderer: GeologyRenderer
var parent: Node2D
var _placement := CaveEntrancePlacement.new()


func before_each():
	renderer = GeologyRenderer.new()
	parent = Node2D.new()


func after_each():
	parent.free()


## Deterministic scan for a real global tile the placement rule actually
## puts a cave entrance at, mirroring test_ore_placement.gd's
## _find_stone_cell.
func _find_mountain_entrance() -> Vector2i:
	for y in range(0, 600):
		for x in range(0, 600):
			if _placement.has_entrance_at(x, y, "mountain"):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _mountain_chunk_containing(entrance_global: Vector2i, size: int = 16) -> Dictionary:
	var origin := entrance_global - Vector2i(size / 2, size / 2)
	var biome: Array = []
	for i in size * size:
		biome.append("mountain")
	return {"origin": origin, "biome": biome, "local": entrance_global - origin}


func test_entrances_in_chunk_finds_a_known_entrance():
	var entrance := _find_mountain_entrance()
	assert_ne(entrance.x, -1, "need a real entrance to test against")
	var setup := _mountain_chunk_containing(entrance)
	var found := renderer.entrances_in_chunk(setup["origin"], setup["biome"], 16, 16)
	assert_true(found.has(setup["local"]))


func test_entrances_in_chunk_finds_none_in_a_non_mountain_biome():
	var entrance := _find_mountain_entrance()
	var setup := _mountain_chunk_containing(entrance)
	var grassland_biome: Array = []
	for i in 16 * 16:
		grassland_biome.append("grassland")
	var found := renderer.entrances_in_chunk(setup["origin"], grassland_biome, 16, 16)
	assert_eq(found.size(), 0)


func test_spawn_entrance_markers_spawns_one_node_per_entrance():
	var entrance := _find_mountain_entrance()
	var setup := _mountain_chunk_containing(entrance)
	var spawned := renderer.spawn_entrance_markers(parent, setup["origin"], setup["biome"], 16, 16, TILE_SIZE)
	assert_gt(spawned.size(), 0)
	for marker in spawned:
		assert_true(marker.get_parent() == parent)


func test_spawn_entrance_markers_positions_at_tile_center():
	var entrance := _find_mountain_entrance()
	var setup := _mountain_chunk_containing(entrance)
	var spawned := renderer.spawn_entrance_markers(parent, setup["origin"], setup["biome"], 16, 16, TILE_SIZE)
	var expected := Vector2((entrance.x + 0.5) * TILE_SIZE, (entrance.y + 0.5) * TILE_SIZE)
	var matched := false
	for marker in spawned:
		if marker.position.distance_to(expected) < 0.01:
			matched = true
	assert_true(matched, "expected a marker positioned at the known entrance tile's center")


# -- reveal_chamber: a real Strata-sourced diggable chamber ------------------

func test_reveal_chamber_spawns_real_diggable_rock_nodes():
	var strata := Strata.new(Strata.LAYER_TOPSOIL_REGOLITH, Vector2i.ZERO)
	var spawned := renderer.reveal_chamber(parent, strata, Vector2i(5, 5), Vector2i.ZERO, TILE_SIZE)
	assert_gt(spawned.size(), 0)
	for node in spawned:
		assert_true(node is DiggableRock)
		assert_true(node.strata == strata)


func test_reveal_chamber_matches_geology_chambers_cell_count():
	var strata := Strata.new(Strata.LAYER_TOPSOIL_REGOLITH, Vector2i.ZERO)
	var spawned := renderer.reveal_chamber(parent, strata, Vector2i(5, 5), Vector2i.ZERO, TILE_SIZE)
	assert_eq(spawned.size(), GeologyChamber.cells_for(Vector2i(5, 5)).size())


func test_reveal_chamber_skips_already_mined_cells():
	var strata := Strata.new(Strata.LAYER_TOPSOIL_REGOLITH, Vector2i.ZERO)
	var entrance := Vector2i(5, 5)
	strata.mine_at(entrance)
	var spawned := renderer.reveal_chamber(parent, strata, entrance, Vector2i.ZERO, TILE_SIZE)
	assert_eq(spawned.size(), GeologyChamber.cells_for(entrance).size() - 1)


func test_reveal_chamber_nodes_carry_their_own_local_cell_for_mining_writeback():
	var strata := Strata.new(Strata.LAYER_TOPSOIL_REGOLITH, Vector2i.ZERO)
	var entrance := Vector2i(5, 5)
	var spawned := renderer.reveal_chamber(parent, strata, entrance, Vector2i.ZERO, TILE_SIZE)
	var cells := GeologyChamber.cells_for(entrance)
	for node in spawned:
		assert_true(cells.has(node.local_cell))
