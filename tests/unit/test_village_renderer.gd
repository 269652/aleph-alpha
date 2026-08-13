extends GutTest

## VillageRenderer: chunk-based spawn/despawn of a settlement's houses + NPC
## markers, driven by SettlementGenerator -- same "one call per chunk load,
## deterministic, returns spawned nodes for the caller to free" shape as
## TreeRenderer/CreatureRenderer/FishRenderer.

const VillageRenderer = preload("res://src/rendering/village_renderer.gd")
const SettlementGenerator = preload("res://src/world/settlement_generator.gd")
const NpcMarker = preload("res://src/rendering/npc_marker.gd")

const TILE_SIZE := 16
const CHUNK_SIZE := 32

var renderer: VillageRenderer
var parent: Node2D
var _generator := SettlementGenerator.new()


func before_each():
	renderer = VillageRenderer.new()
	parent = Node2D.new()


func after_each():
	parent.free()


func _find_settlement_chunk(biome: String) -> Vector2i:
	for x in 400:
		var coord := Vector2i(x, 0)
		if _generator.has_settlement_at(coord, biome):
			return coord
	fail_test("no settlement chunk found within 400 chunks")
	return Vector2i.ZERO


func _find_non_settlement_chunk(biome: String) -> Vector2i:
	for x in 400:
		var coord := Vector2i(x, 1)
		if not _generator.has_settlement_at(coord, biome):
			return coord
	fail_test("no non-settlement chunk found within 400 chunks")
	return Vector2i.ZERO


func test_spawns_nothing_on_a_chunk_without_a_settlement():
	var chunk_coord := _find_non_settlement_chunk("grassland")
	var spawned := renderer.spawn_village(
		parent, chunk_coord, chunk_coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland"
	)
	assert_eq(spawned.size(), 0)


func test_spawns_nothing_on_an_uninhabitable_biome_even_if_the_chunk_would_otherwise_qualify():
	var chunk_coord := _find_settlement_chunk("grassland")
	var spawned := renderer.spawn_village(
		parent, chunk_coord, chunk_coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "ocean"
	)
	assert_eq(spawned.size(), 0)


func test_spawns_houses_landmarks_and_npc_markers_on_a_settlement_chunk():
	var chunk_coord := _find_settlement_chunk("grassland")
	var spawned := renderer.spawn_village(
		parent, chunk_coord, chunk_coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland"
	)
	assert_eq(spawned.size(), parent.get_child_count())

	var npc_markers := 0
	var props := 0
	for node in spawned:
		if node is NpcMarker:
			npc_markers += 1
		else:
			props += 1
	assert_eq(npc_markers, SettlementGenerator.POPULATION)
	# One house per villager plus the 3 shared landmarks (well/stall/gate).
	assert_eq(props, SettlementGenerator.POPULATION + 3)


## The well/stall/gate must be real visible sprites at the settlement's
## landmark positions -- not just invisible walk targets.
func test_landmarks_are_rendered_as_sprites_at_their_positions():
	var chunk_coord := _find_settlement_chunk("grassland")
	var settlement := SettlementGenerator.new().generate_settlement(
		chunk_coord, chunk_coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE
	)
	var spawned := renderer.spawn_village(
		parent, chunk_coord, chunk_coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland"
	)
	for landmark_id in ["well", "stall", "gate"]:
		var found := false
		for node in spawned:
			if node is NpcMarker:
				continue
			if node.position == settlement.landmarks[landmark_id] and node.texture != null:
				found = true
		assert_true(found, "no rendered sprite at the %s's position" % landmark_id)


func test_spawned_npc_markers_have_an_identity_and_a_schedule_source():
	var chunk_coord := _find_settlement_chunk("grassland")
	var spawned := renderer.spawn_village(
		parent, chunk_coord, chunk_coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland"
	)
	for node in spawned:
		if node is NpcMarker:
			assert_not_null(node.identity)
			assert_ne(node.home_position, Vector2.ZERO)


func test_spawned_npc_markers_know_the_settlements_shared_landmarks():
	var chunk_coord := _find_settlement_chunk("grassland")
	var spawned := renderer.spawn_village(
		parent, chunk_coord, chunk_coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland"
	)
	for node in spawned:
		if node is NpcMarker:
			for landmark in ["well", "stall", "gate"]:
				assert_true(node.landmarks.has(landmark))


func test_positions_are_deterministic_for_the_same_chunk():
	var chunk_coord := _find_settlement_chunk("grassland")
	var origin := chunk_coord * CHUNK_SIZE
	var first := renderer.spawn_village(parent, chunk_coord, origin, CHUNK_SIZE, TILE_SIZE, "grassland")
	var first_positions: Array[Vector2] = []
	for node in first:
		first_positions.append(node.position)

	var other_parent := Node2D.new()
	var second := renderer.spawn_village(other_parent, chunk_coord, origin, CHUNK_SIZE, TILE_SIZE, "grassland")
	var second_positions: Array[Vector2] = []
	for node in second:
		second_positions.append(node.position)
	other_parent.free()

	assert_eq(first_positions, second_positions)


# -- NPCs are whole people, not a torso and a head -------------------------
#
# Villagers were assembled from just a tunic sprite plus a head sprite, with
# their own stale size constants (10x14 / 8x8, left behind when CharacterView
# grew) and no limbs at all -- reported as "npcs have no legs". They now use
# the same CharacterView the player does, so body proportions, art
# resolution and animation come from one place.

const CharacterView = preload("res://scenes/character_view.gd")


func _first_npc(spawned: Array) -> Node2D:
	for node in spawned:
		if node is NpcMarker:
			return node
	return null


func _character_view_of(npc: Node2D) -> Node2D:
	for child in npc.get_children():
		if child is CharacterView:
			return child
	return null


func test_villagers_are_built_from_the_same_character_view_as_the_player():
	var chunk_coord := _find_settlement_chunk("grassland")
	var spawned := renderer.spawn_village(
		parent, chunk_coord, chunk_coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland"
	)
	var npc := _first_npc(spawned)
	assert_not_null(npc, "the fixture should spawn at least one villager")
	assert_not_null(_character_view_of(npc), "a villager should own a CharacterView")


func test_villagers_have_legs_and_arms():
	var chunk_coord := _find_settlement_chunk("grassland")
	var spawned := renderer.spawn_village(
		parent, chunk_coord, chunk_coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland"
	)
	var view := _character_view_of(_first_npc(spawned))
	for part_name in ["LegLeft", "LegRight", "ArmLeft", "ArmRight", "Body", "Head"]:
		assert_not_null(view.get_node_or_null(part_name), "villager should have a %s" % part_name)
