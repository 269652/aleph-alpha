extends GutTest

## VillageRenderer: chunk-based spawn/despawn of a settlement's houses + NPC
## markers, driven by SettlementGenerator -- same "one call per chunk load,
## deterministic, returns spawned nodes for the caller to free" shape as
## TreeRenderer/CreatureRenderer/FishRenderer.

const VillageRenderer = preload("res://src/rendering/village_renderer.gd")
const SettlementGenerator = preload("res://src/world/settlement_generator.gd")
const NpcMarker = preload("res://src/rendering/npc_marker.gd")
const BuildingPiece = preload("res://src/gameplay/building_piece.gd")

const TILE_SIZE := 16
const CHUNK_SIZE := 32

var renderer: VillageRenderer
var parent: Node2D
var _generator := SettlementGenerator.new()


## Duck-typed EarthChunkManager stand-in: records every stamp_structure_at_
## global call instead of actually touching a chunk, so these tests can
## verify VillageRenderer's houses are real stamped structures (walls,
## floor, one door, a roof) without paying a real EarthChunkManager's
## instantiation cost (its own atlas/chunk-generation setup takes several
## seconds -- fine for the dedicated EarthChunkManager test file, wasteful
## to pay once per test here for a question this stub answers just as well).
class StubWorld:
	var stamp_calls: Array = []
	var biome := "grassland"
	## Individual cells that report as ocean regardless of `biome` -- lets a
	## test carve a small pond/lake out of an otherwise-buildable chunk (see
	## the water-avoidance tests below), the same way a real chunk can have a
	## dominant biome with a water pocket cut through it.
	var water_cells: Dictionary = {}
	func stamp_structure_at_global(
		chunk_coord: Vector2i, origin_tile: Vector2i, ground_pieces: Dictionary, roof_pieces: Dictionary
	) -> void:
		stamp_calls.append({
			"chunk_coord": chunk_coord, "origin_tile": origin_tile,
			"ground_pieces": ground_pieces, "roof_pieces": roof_pieces,
		})
	func biome_at_global(x: int, y: int) -> String:
		if water_cells.has(Vector2i(x, y)):
			return "ocean"
		return biome

	## Records every settlement-founded call instead of touching a real event
	## store (see EarthChunkManager.record_settlement_founded_if_new).
	var founded_calls: Array = []
	func record_settlement_founded_if_new(chunk_coord: Vector2i, npcs: Array) -> void:
		founded_calls.append({"chunk_coord": chunk_coord, "npcs": npcs})


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


## A chunk whose fixed 5-villager roster happens to include at least one
## merchant -- occupation is seeded per villager, so not every settlement
## chunk has one; the water-avoidance/generic tests above don't care, but the
## personal-trading-stand tests below need a merchant to exist.
func _find_settlement_chunk_with_merchant(biome: String) -> Vector2i:
	for x in 400:
		var coord := Vector2i(x, 2)  # a row of its own, distinct from the other _find_* helpers'
		if not _generator.has_settlement_at(coord, biome):
			continue
		var settlement := _generator.generate_settlement(coord, coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE)
		for npc in settlement.npcs:
			if npc.occupation == "merchant":
				return coord
	fail_test("no settlement chunk with a merchant found within 400 chunks")
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


## Houses are real stamped structures now (see the stamp_structure_at_global
## tests below), not a decorative Sprite2D -- their walls/floor/door/roof
## ARE tiles, so they produce no Node2D of their own any more. Only the
## landmark props (well/stall/gate, plus one personal trading stand per
## merchant -- see the "merchants get their own personal trading stand"
## tests below) and the NPC markers remain spawned nodes.
func test_spawns_landmarks_and_npc_markers_on_a_settlement_chunk():
	var chunk_coord := _find_settlement_chunk("grassland")
	var settlement := SettlementGenerator.new().generate_settlement(
		chunk_coord, chunk_coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE
	)
	var merchant_count := 0
	for npc in settlement.npcs:
		if npc.occupation == "merchant":
			merchant_count += 1

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
	assert_eq(
		props, 3 + merchant_count,
		"expected the 3 shared landmarks plus one personal stand per merchant"
	)


# -- houses are real stamped structures (see docs/concept/building.md) ------
#
# A village house is not a decorative sprite with a painted-on door -- it is
# a real HouseBlueprint assembly of floor/wall/door/roof pieces, stamped
# into the world via EarthChunkManager.stamp_structure_at_global, exactly
# the same mechanism the player's own building pieces use. This is what
# "the player and the settlement generator build with one vocabulary" (see
# building.md) actually means in practice.

func test_spawn_village_stamps_a_real_house_for_every_villager():
	var chunk_coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	renderer.spawn_village(parent, chunk_coord, chunk_coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	assert_eq(world.stamp_calls.size(), SettlementGenerator.POPULATION)


func test_each_stamped_house_has_walls_a_floor_exactly_one_door_and_a_roof():
	var chunk_coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	renderer.spawn_village(parent, chunk_coord, chunk_coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)

	for call in world.stamp_calls:
		var categories := {}
		for cell in call.ground_pieces:
			var category := BuildingPiece.category_of(call.ground_pieces[cell])
			categories[category] = categories.get(category, 0) + 1
		assert_gt(categories.get(BuildingPiece.CATEGORY_WALL, 0), 0, "a house needs walls")
		assert_gt(categories.get(BuildingPiece.CATEGORY_FLOOR, 0), 0, "a house needs floor")
		assert_eq(categories.get(BuildingPiece.CATEGORY_DOOR, 0), 1, "a house needs exactly one door")
		assert_false(call.roof_pieces.is_empty(), "a house needs a roof")


## Each house lands at a different chunk cell -- a village of 5 identical
## overlapping houses would just be one house.
func test_stamped_houses_do_not_all_land_on_the_same_origin():
	var chunk_coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	renderer.spawn_village(parent, chunk_coord, chunk_coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)

	var origins := {}
	for call in world.stamp_calls:
		origins[call.origin_tile] = true
	assert_eq(origins.size(), world.stamp_calls.size(), "every house should stamp at its own origin")


## Walking an NPC to the raw ring-anchor position (the old decorative
## sprite's centre point) would walk it into the middle of a wall or floor
## cell at random -- home_position must be somewhere it can actually stand
## and enter from, so it resolves to the house's own door.
func test_npc_home_position_is_its_own_houses_door_not_the_raw_anchor():
	var chunk_coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	var spawned := renderer.spawn_village(
		parent, chunk_coord, chunk_coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world
	)
	var npc_index := 0
	for node in spawned:
		if not (node is NpcMarker):
			continue
		var call = world.stamp_calls[npc_index]
		var door_tile := Vector2i(
			floori(node.home_position.x / TILE_SIZE), floori(node.home_position.y / TILE_SIZE)
		)
		var local: Vector2i = door_tile - call.origin_tile
		assert_eq(
			BuildingPiece.category_of(call.ground_pieces.get(local, "")), BuildingPiece.CATEGORY_DOOR,
			"villager %d's home_position should be its own house's door cell" % npc_index
		)
		npc_index += 1


## A house whose ring-layout anchor happens to land on/over a water pocket
## (a chunk's dominant biome only gates the CHUNK, not every individual
## cell -- see BiomeClassifier.dominant_biome -- so a grassland-dominant
## chunk can still have a pond/river cutting through it) must not be stamped
## there; it should be nudged to nearby dry ground instead.
func test_a_house_is_never_stamped_partially_in_water():
	var chunk_coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	var settlement := SettlementGenerator.new().generate_settlement(
		chunk_coord, chunk_coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE
	)
	# Flood the exact footprint every house's raw (un-nudged) origin would
	# use, forcing every single one of them to need rescuing.
	for anchor in settlement.house_positions:
		var anchor_tile := Vector2i(floori(anchor.x / TILE_SIZE), floori(anchor.y / TILE_SIZE))
		var raw_origin := anchor_tile - VillageRenderer._HOUSE_FOOTPRINT / 2
		for x in VillageRenderer._HOUSE_FOOTPRINT.x:
			for y in VillageRenderer._HOUSE_FOOTPRINT.y:
				world.water_cells[raw_origin + Vector2i(x, y)] = true

	renderer.spawn_village(parent, chunk_coord, chunk_coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)

	assert_gt(world.stamp_calls.size(), 0, "precondition: at least one house should still get built on dry land nearby")
	for call in world.stamp_calls:
		for local_cell in call.ground_pieces:
			var global_cell: Vector2i = call.origin_tile + local_cell
			assert_ne(
				world.biome_at_global(global_cell.x, global_cell.y), "ocean",
				"house piece at %s was stamped on water" % global_cell
			)


## If there's genuinely no dry ground nearby, the house should be skipped
## entirely rather than forced into the water -- no house is better than a
## half-submerged one.
func test_a_house_with_no_dry_ground_anywhere_nearby_is_skipped_not_forced_into_water():
	var chunk_coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	world.biome = "ocean"  # the whole chunk is water -- nowhere dry to nudge to
	renderer.spawn_village(parent, chunk_coord, chunk_coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world)
	assert_eq(world.stamp_calls.size(), 0)


## -- merchants get their own personal trading stand (see docs/concept/
## npc.md's "Village trading stands") -- in addition to the one shared
## village-square stall, every merchant villager gets a second, personal
## stand near their own house door, since a whole village routing every
## merchant to the one central stall reads as one shop, not several
## villagers who each trade.

func test_merchant_villagers_get_a_personal_trading_stand_near_their_own_house():
	var chunk_coord := _find_settlement_chunk_with_merchant("grassland")
	var world := StubWorld.new()
	var settlement := SettlementGenerator.new().generate_settlement(
		chunk_coord, chunk_coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE
	)
	var merchant_count := 0
	for npc in settlement.npcs:
		if npc.occupation == "merchant":
			merchant_count += 1

	var spawned := renderer.spawn_village(
		parent, chunk_coord, chunk_coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world
	)

	# One shared plaza stall (well/gate are the other 2 shared landmarks) plus
	# one personal stand per merchant.
	var stall_like_positions: Array[Vector2] = []
	for node in spawned:
		if node is NpcMarker:
			continue
		if node.position == settlement.landmarks["well"] or node.position == settlement.landmarks["gate"]:
			continue
		stall_like_positions.append(node.position)
	assert_eq(stall_like_positions.size(), 1 + merchant_count, "expected the shared stall plus one stand per merchant")

	for node in spawned:
		if not (node is NpcMarker) or node.identity.occupation != "merchant":
			continue
		var nearest := INF
		for pos in stall_like_positions:
			nearest = minf(nearest, pos.distance_to(node.home_position))
		assert_lt(nearest, 4.0 * TILE_SIZE, "merchant should have a personal stand near their own house")


func test_non_merchant_villagers_do_not_get_a_personal_trading_stand():
	var chunk_coord := _find_settlement_chunk_with_merchant("grassland")
	var world := StubWorld.new()
	var settlement := SettlementGenerator.new().generate_settlement(
		chunk_coord, chunk_coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE
	)
	var non_merchant_count := 0
	for npc in settlement.npcs:
		if npc.occupation != "merchant":
			non_merchant_count += 1
	if non_merchant_count == 0:
		return  # nothing to assert -- this roster is all merchants

	var spawned := renderer.spawn_village(
		parent, chunk_coord, chunk_coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world
	)
	var npc_markers := 0
	for node in spawned:
		if node is NpcMarker:
			npc_markers += 1
	# props = 3 shared landmarks + 1 personal stand per merchant, never one
	# per non-merchant villager too.
	var merchant_count := npc_markers - non_merchant_count
	var props := spawned.size() - npc_markers
	assert_eq(props, 3 + merchant_count)


## Villagers must be water-aware (see NpcMarker._is_in_water/setup) the same
## way the player and wild creatures are, so a villager whose walk ever
## crosses water swims instead of "walking on water". This only works if
## VillageRenderer actually passes `world` through to NpcMarker.setup --
## spawn_village already receives it but nothing forwarded it, so every
## villager's movement_state was stuck non-swimming regardless of the tile.
func test_villagers_are_given_the_world_so_they_can_tell_when_theyre_in_water():
	var chunk_coord := _find_settlement_chunk("grassland")
	var world := StubWorld.new()
	world.biome = "ocean"
	var spawned := renderer.spawn_village(
		parent, chunk_coord, chunk_coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world
	)
	var npc: NpcMarker = _first_npc(spawned)
	assert_not_null(npc, "the fixture should spawn at least one villager")
	npc._process(0.1)
	var view := _character_view_of(npc)
	assert_eq(view.movement_state, CharacterView.MovementState.SWIMMING)


## No world (e.g. an isolated rendering test/tool that doesn't need real
## chunk mutation) must not crash -- same fail-open shape as _water_layer/
## _roof_layer elsewhere in this codebase.
func test_spawn_village_does_not_crash_without_a_world():
	var chunk_coord := _find_settlement_chunk("grassland")
	var settlement := SettlementGenerator.new().generate_settlement(
		chunk_coord, chunk_coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE
	)
	var merchant_count := 0
	for npc in settlement.npcs:
		if npc.occupation == "merchant":
			merchant_count += 1

	var spawned := renderer.spawn_village(
		parent, chunk_coord, chunk_coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland"
	)
	assert_eq(spawned.size(), SettlementGenerator.POPULATION + 3 + merchant_count)


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


## The NPC drop shadow was sized off CharacterView.BODY_SIZE directly,
## unscaled -- once CharacterView started shrinking itself down to 2/3 of a
## tree's height (see character_view.gd's SCALE), an unscaled shadow would
## be oversized relative to the now-smaller villager standing on it (the
## same class of bug already fixed once for creature shadows, see
## creature_renderer.gd's foot-offset-scaling history).
func test_npc_shadow_is_scaled_down_to_match_the_shrunk_character_view():
	const CharacterView = preload("res://scenes/character_view.gd")
	var chunk_coord := _find_settlement_chunk("grassland")
	var spawned := renderer.spawn_village(
		parent, chunk_coord, chunk_coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland"
	)
	var npc := _first_npc(spawned)
	var shadow: Sprite2D = npc.get_node("Shadow")
	var expected_width := int(CharacterView.BODY_SIZE.x * 0.9 * CharacterView.SCALE)
	assert_almost_eq(shadow.texture.get_width(), expected_width, 1)


# -- needs/local production economy (docs/concept/npc.md "Needs and the
# local production economy"): every villager of a settlement is wired up
# with a real NpcEconomy, and they all share the SAME VillageMarket -- a
# producer's real surplus must be visible to every consumer in that same
# village, not siloed per-NPC. ---------------------------------------------

func _all_npcs(spawned: Array) -> Array:
	var npcs: Array = []
	for node in spawned:
		if node is NpcMarker:
			npcs.append(node)
	return npcs


func test_every_spawned_villager_has_an_economy():
	var chunk_coord := _find_settlement_chunk("grassland")
	var spawned := renderer.spawn_village(
		parent, chunk_coord, chunk_coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland"
	)
	var npcs := _all_npcs(spawned)
	assert_gt(npcs.size(), 0, "the fixture should spawn at least one villager")
	for npc in npcs:
		assert_not_null(npc.economy, "every villager should carry a real NpcEconomy")


func test_every_villager_of_the_same_settlement_shares_one_village_market():
	var chunk_coord := _find_settlement_chunk("grassland")
	var spawned := renderer.spawn_village(
		parent, chunk_coord, chunk_coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland"
	)
	var npcs := _all_npcs(spawned)
	assert_gt(npcs.size(), 1, "precondition: need more than one villager to compare markets")
	var shared_market = npcs[0].economy.market
	for npc in npcs:
		assert_same(npc.economy.market, shared_market, "every villager of one settlement should share one market")


# -- founding is reported to the world, once ---------------------------------

## A newly-spawned settlement tells the world it was founded (see
## docs/emergence, EarthChunkManager.record_settlement_founded_if_new) --
## duck-typed exactly like stamp_structure_at_global, so a world that lacks
## the method (or is null, per the other tests in this file) is skipped
## rather than crashing.
func test_spawning_a_settlement_reports_it_founded():
	var world := StubWorld.new()
	var chunk_coord := _find_settlement_chunk("grassland")
	renderer.spawn_village(
		parent, chunk_coord, chunk_coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world
	)
	assert_eq(world.founded_calls.size(), 1)
	assert_eq(world.founded_calls[0].chunk_coord, chunk_coord)
	assert_eq(world.founded_calls[0].npcs.size(), SettlementGenerator.POPULATION)


## An empty chunk (no settlement here) reports nothing.
func test_a_chunk_with_no_settlement_reports_nothing():
	var world := StubWorld.new()
	var chunk_coord := Vector2i(0, 0)
	# Not every chunk hosts a settlement -- find one that provably doesn't
	# rather than assuming (0,0) never does.
	while _generator.has_settlement_at(chunk_coord, "grassland"):
		chunk_coord.x += 1
	renderer.spawn_village(
		parent, chunk_coord, chunk_coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland", world
	)
	assert_eq(world.founded_calls.size(), 0)


func test_a_world_with_no_such_method_does_not_crash():
	var chunk_coord := _find_settlement_chunk("grassland")
	renderer.spawn_village(
		parent, chunk_coord, chunk_coord * CHUNK_SIZE, CHUNK_SIZE, TILE_SIZE, "grassland"
	)
	pass_test("spawning with no world at all should not crash")
