extends GutTest

const StoneRenderer = preload("res://src/rendering/stone_renderer.gd")
const ProceduralStoneSprite = preload("res://src/rendering/procedural_stone_sprite.gd")
const StonePlacement = preload("res://src/world/stone_placement.gd")
const StoneSize = preload("res://src/world/stone_size.gd")
const OrePlacement = preload("res://src/world/ore_placement.gd")
const Chunk = preload("res://src/world/chunk.gd")
const LiftableStone = preload("res://src/rendering/liftable_stone.gd")

var renderer: StoneRenderer
var parent: Node2D
var stone_placement := StonePlacement.new()

const TILE_SIZE := 16
const CHUNK_ORIGIN := Vector2i(300, 500)


func before_each():
	renderer = StoneRenderer.new()
	parent = Node2D.new()


func after_each():
	parent.free()


func _make_grassland_chunk(size: int = 16) -> Chunk:
	var chunk := Chunk.new()
	chunk.width = size
	chunk.height = size
	chunk.elevation = PackedFloat32Array()
	chunk.elevation.resize(size * size)
	chunk.biome = PackedStringArray()
	for i in size * size:
		chunk.biome.append("grassland")
	return chunk


## Reported: "they all have the same shape" -- caused by _texture_for
## caching by `seed_value % 4` bucket, so every stone in the world drew from
## one of only 4 shared textures regardless of its own real seed. Two
## different seeds must now produce genuinely different textures, not the
## same shared bucket texture.
func test_different_seeds_get_their_own_texture_not_a_shared_bucket():
	var a := renderer._texture_for(11)
	var b := renderer._texture_for(23)  # 11 % 4 == 23 % 4 == 3 under the old bucket scheme
	assert_ne(a.get_image().get_data(), b.get_image().get_data())


## A flock cell spawns MORE than one node (see StonePlacement.flock_size_at),
## so "one node per cell" is no longer exactly true -- the real invariant is
## one node per FLOCK MEMBER (an ore cell, which never flocks, still spawns
## exactly one).
func test_spawns_one_node_per_stone_cell():
	var chunk := _make_grassland_chunk()
	var ore_placement := OrePlacement.new()
	var expected := 0
	for cell in stone_placement.stones_in_chunk(CHUNK_ORIGIN, chunk.biome, chunk.width, chunk.height):
		var global_x := CHUNK_ORIGIN.x + cell.x
		var global_y := CHUNK_ORIGIN.y + cell.y
		var biome_name: String = chunk.biome[cell.y * chunk.width + cell.x]
		if ore_placement.is_ore_at(global_x, global_y, biome_name):
			expected += 1
		else:
			expected += stone_placement.flock_size_at(global_x, global_y)
	var spawned := renderer.spawn_stones(parent, chunk, CHUNK_ORIGIN, TILE_SIZE)
	assert_eq(spawned.size(), expected)
	assert_eq(parent.get_child_count(), spawned.size())


func test_no_stones_spawn_on_an_ocean_chunk():
	var chunk := _make_grassland_chunk(8)
	for i in chunk.biome.size():
		chunk.biome[i] = "ocean"
	var spawned := renderer.spawn_stones(parent, chunk, CHUNK_ORIGIN, TILE_SIZE)
	assert_eq(spawned.size(), 0)


## Only BOULDERS block. A pebble is something you walk over, not around, so
## liftable stone is spawned with no collision body at all (see
## docs/concept/stone.md -- if you can lift it, you take it).
func test_spawned_stones_are_positioned_at_their_tile_center():
	var chunk := _make_grassland_chunk()
	var spawned := renderer.spawn_stones(parent, chunk, CHUNK_ORIGIN, TILE_SIZE)
	if spawned.is_empty():
		pass_test("no stone cells rolled in this chunk; covered by the count test")
		return
	var stone: Node2D = spawned[0]
	var cells := stone_placement.stones_in_chunk(CHUNK_ORIGIN, chunk.biome, chunk.width, chunk.height)
	var expected_position := Vector2(
		(CHUNK_ORIGIN.x + cells[0].x + 0.5) * TILE_SIZE,
		(CHUNK_ORIGIN.y + cells[0].y + 0.5) * TILE_SIZE
	)
	assert_eq(stone.position, expected_position)


## Boulders block movement the way trees do; liftable stone does not.
func test_only_boulders_block_movement():
	var chunk := _make_grassland_chunk()
	var spawned := renderer.spawn_stones(parent, chunk, CHUNK_ORIGIN, TILE_SIZE)
	if spawned.is_empty():
		pass_test("no stone cells rolled in this chunk; covered by the count test")
		return
	for stone in spawned:
		if stone.has_method("smash") or stone.has_method("mine"):
			assert_true(stone is StaticBody2D, "a boulder should block movement like a tree")
		else:
			assert_false(stone is StaticBody2D, "a pebble should be something you walk over")


## Every stone the renderer spawns can be taken one way or the other -- there
## is no third kind that is neither pickable nor breakable.
func test_every_spawned_stone_can_be_taken():
	var chunk := _make_grassland_chunk()
	var spawned := renderer.spawn_stones(parent, chunk, CHUNK_ORIGIN, TILE_SIZE)
	if spawned.is_empty():
		pass_test("no stone cells rolled in this chunk; covered by the count test")
		return
	for stone in spawned:
		assert_true(
			stone.has_method("smash") or stone.has_method("pick_up") or stone.has_method("mine"),
			"a stone that can neither be smashed, picked up nor mined is scenery"
		)


## A boulder is drawn bigger than a pebble. The drawn size comes from the same
## StoneSize the rules use, so the two cannot drift apart.
func test_a_stones_drawn_size_follows_its_real_size():
	var StoneSize := load("res://src/world/stone_size.gd")
	var chunk := _make_grassland_chunk()
	var spawned := renderer.spawn_stones(parent, chunk, CHUNK_ORIGIN, TILE_SIZE)
	for stone in spawned:
		var sprite: Sprite2D = null
		for child in stone.get_children():
			if child is Sprite2D:
				sprite = child
		if sprite == null or not ("diameter_cm" in stone):
			continue
		var expected: float = (
			StoneSize.world_height_px(stone.diameter_cm)
			/ float(ProceduralStoneSprite.SIZE.y)
		)
		assert_almost_eq(sprite.scale.x, expected, 0.001, "drawn size drifted from real size")


# -- pebble flocks (see docs/concept/stone.md, StonePlacement.flock_size_at) -

## _build_pebble_flock's members are plain constructed nodes, not attached to
## `parent` the way spawn_stones' own output is -- these tests call it
## directly (same established precedent as
## test_different_seeds_get_their_own_texture_not_a_shared_bucket calling
## _texture_for directly), so they must free what they construct themselves.
func _autofreed_flock(global_x: int, global_y: int, cell_center: Vector2, member_count: int) -> Array:
	var members := renderer._build_pebble_flock(global_x, global_y, cell_center, member_count)
	for member in members:
		add_child_autofree(member)
	return members


func test_build_pebble_flock_returns_that_many_liftable_members():
	var members := _autofreed_flock(100, 200, Vector2(50, 50), 4)
	assert_eq(members.size(), 4)
	for member in members:
		assert_true(member.has_method("pick_up"), "a flock member should be pickable like any other pebble")
		assert_false(member is StaticBody2D, "a flock member should be something you walk over, not around")


func test_flock_members_have_independent_seeds():
	var members := _autofreed_flock(100, 200, Vector2(50, 50), 5)
	var seeds := {}
	for member in members:
		seeds[member.stone_seed] = true
	assert_eq(seeds.size(), 5, "every member should be independently seeded")


## A flock is a cluster of PEBBLES: no member may roll a cobble/boulder
## diameter, which would break the lift/smash pillar for that member (a
## flock member is always built as a LiftableStone, with no boulder
## fallback).
func test_flock_members_are_always_pebble_sized():
	for trial in 20:
		var members := _autofreed_flock(
			trial * 31, trial * 53, Vector2.ZERO, StonePlacement.FLOCK_MAX_MEMBERS
		)
		for member in members:
			assert_lte(member.diameter_cm, StoneSize.PEBBLE_MAX_CM)


## Member 0 sits at the exact cell centre -- the same place a lone pebble
## sits today. test_spawned_stones_are_positioned_at_their_tile_center relies
## on this holding even when cells[0] happens to be a flock.
func test_flock_member_zero_sits_at_the_cell_center():
	var members := _autofreed_flock(100, 200, Vector2(50, 50), 3)
	assert_eq(members[0].position, Vector2(50, 50))


## Members must not land on top of each other -- positioned with real
## separation by construction, not just probabilistically-unlikely-to-
## collide jitter (see _flock_member_offset's own doc comment).
func test_flock_members_do_not_overlap():
	var members := _autofreed_flock(100, 200, Vector2(50, 50), 5)
	for i in members.size():
		for j in range(i + 1, members.size()):
			assert_gt(
				members[i].position.distance_to(members[j].position), 1.0,
				"flock members %d and %d landed on top of each other" % [i, j]
			)


## Kept tight: a flock should read as sitting on its own cell, not sprawled
## across neighbours.
func test_flock_members_stay_close_to_the_cell_center():
	var members := _autofreed_flock(100, 200, Vector2(50, 50), 5)
	for member in members:
		assert_lt(
			member.position.distance_to(Vector2(50, 50)), float(TILE_SIZE) / 2.0 + 4.0,
			"a flock member drifted too far from its own cell"
		)


## A flock's whole spread must stay well inside Player.PICKUP_RADIUS (34) so
## walking up to a flock once collects every member in the same
## pickup_nearby sweep -- no special-cased "pick up the flock" action needed.
func test_flock_spread_stays_inside_the_pickup_radius():
	var members := _autofreed_flock(100, 200, Vector2(50, 50), StonePlacement.FLOCK_MAX_MEMBERS)
	for member in members:
		assert_lt(member.position.distance_to(Vector2(50, 50)), 34.0)


## A real cell found via the real placement, not a synthetic one -- confirms
## spawn_stones actually produces flock_size_at's own count of nodes for a
## cell that genuinely rolls a flock, not just that _build_pebble_flock does
## the right thing in isolation.
func test_spawn_stones_produces_a_real_flock_for_a_cell_that_rolls_one():
	var ore_placement := OrePlacement.new()
	var flock_x := -1
	var flock_y := -1
	var expected_size := 1
	for i in 20000:
		var x := i * 3
		var y := i * 5
		if not stone_placement.has_stone_at(x, y, "grassland"):
			continue
		# Ore takes precedence over flocking in spawn_stones' own control
		# flow (checked first, same as it always was) -- an ore-bearing cell
		# always spawns exactly one MinableOre node regardless of what
		# flock_size_at says, so it must be excluded here too.
		if ore_placement.is_ore_at(x, y, "grassland"):
			continue
		var size := stone_placement.flock_size_at(x, y)
		if size > 1:
			flock_x = x
			flock_y = y
			expected_size = size
			break
	assert_gt(expected_size, 1, "no flocking cell turned up in the sample -- widen the search")

	var chunk := Chunk.new()
	chunk.width = 1
	chunk.height = 1
	chunk.elevation = PackedFloat32Array([0.0])
	chunk.biome = PackedStringArray(["grassland"])
	var spawned := renderer.spawn_stones(parent, chunk, Vector2i(flock_x, flock_y), TILE_SIZE)
	assert_eq(spawned.size(), expected_size)


# -- illustrated art plumbing (see IllustratedStoneSprite) -------------------
#
# No real sheet exists yet, so this pins the WIRING with a fake stand-in
# rather than real art: when the illustrated source reports a class as
# covered, its frame wins; when it doesn't, the procedural generator still
# runs exactly as it does today. The same has_X()-gated fallback every other
# optional illustrated-art seam in this codebase uses.

class _FakeIllustratedStones:
	var registered_class := ""
	var canned_texture: ImageTexture

	func has_variants(stone_class: String) -> bool:
		return stone_class == registered_class

	func frame_for(_stone_class: String, _seed_value: int) -> ImageTexture:
		return canned_texture


func test_texture_for_uses_illustrated_art_when_the_class_has_a_sheet():
	var fake := _FakeIllustratedStones.new()
	fake.registered_class = StoneSize.CLASS_PEBBLE
	fake.canned_texture = ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))
	renderer._illustrated_stones = fake
	assert_eq(renderer._texture_for(999, StoneSize.CLASS_PEBBLE), fake.canned_texture)


func test_texture_for_falls_back_to_procedural_when_the_class_has_no_sheet():
	var fake := _FakeIllustratedStones.new()
	fake.registered_class = StoneSize.CLASS_PEBBLE  # boulder is NOT registered
	renderer._illustrated_stones = fake
	var texture := renderer._texture_for(999, StoneSize.CLASS_BOULDER)
	assert_not_null(texture)
	assert_ne(texture, fake.canned_texture)


## Real end-to-end integration, no fake: a fresh renderer's OWN
## IllustratedStoneSprite instance now has real pebble AND boulder art
## registered (see assets/sprites/pebbles.png / boulders.png, both real 4x5
## variant grids), so a real stone of either class should draw from its own
## illustrated sheet rather than the procedural fallback. Only cobbles (no
## sheet at all, by design) still fall all the way through to procedural.
func test_a_real_pebble_draws_from_the_registered_illustrated_sheet():
	var pebble_texture := renderer._texture_for(555, StoneSize.CLASS_PEBBLE)
	var expected: ImageTexture = renderer._illustrated_stones.frame_for(StoneSize.CLASS_PEBBLE, 555)
	assert_not_null(expected, "the real pebble sheet should have produced a frame")
	assert_eq(pebble_texture, expected)


## Boulders now ALSO draw from a real illustrated sheet (assets/sprites/
## boulders.png) instead of falling back to the procedural generator -- the
## fallback this test used to pin no longer applies now that boulder art
## exists (see test_a_real_cobble_still_falls_back_to_procedural below for
## the class that still does).
func test_a_real_boulder_draws_from_the_registered_illustrated_sheet():
	var boulder_texture := renderer._texture_for(555, StoneSize.CLASS_BOULDER)
	var expected: ImageTexture = renderer._illustrated_stones.frame_for(StoneSize.CLASS_BOULDER, 555)
	assert_not_null(expected, "the real boulder sheet should have produced a frame")
	assert_eq(boulder_texture, expected)


## Cobbles have no sheet at all, by design (see IllustratedStoneSprite's own
## class doc comment) -- the one class that still genuinely falls all the way
## through to the procedural generator.
func test_a_real_cobble_still_falls_back_to_procedural():
	var cobble_texture := renderer._texture_for(555, StoneSize.CLASS_COBBLE)
	assert_not_null(cobble_texture)
	assert_null(renderer._illustrated_stones.frame_for(StoneSize.CLASS_COBBLE, 555))


## Public wrapper around the existing _build_liftable_node, for callers
## outside StoneRenderer that need to materialize a real, correctly-rendered
## liftable stone node directly (see Player._spawn_thrown_stone, the
## held-item throw's landing spot) rather than reaching into a private
## method across files.
func test_build_liftable_stone_node_returns_a_real_rendered_liftable_node():
	var node := renderer.build_liftable_stone_node(42, 4.0)
	assert_true(node is LiftableStone)
	assert_eq(node.stone_seed, 42)
	assert_almost_eq(node.diameter_cm, 4.0, 0.001)
	assert_eq(node.get_child_count(), 1, "should carry a real rendered sprite child")
	node.free()


## Regression: _texture_cache used to be keyed by seed_value ALONE. A pebble
## flock member's seed (StonePlacement.flock_member_seed, constrained only to
## the pebble diameter range) and a solitary boulder's seed
## (StonePlacement.seed_at) are independently derived and CAN numerically
## collide at real-world stone counts -- when they did, whichever stone's
## texture got cached first for that seed_value was silently reused for the
## second, WRONG-CLASS stone too. Invisible before (a "wrong" texture for a
## boulder was just another indistinguishable procedural boulder) and only
## surfaced once both pebbles and boulders had real, visually distinct
## illustrated art. Forces the collision directly rather than waiting on a
## real one to turn up.
func test_texture_for_does_not_collide_across_stone_classes_sharing_a_seed():
	var shared_seed := 555
	var pebble_texture := renderer._texture_for(shared_seed, StoneSize.CLASS_PEBBLE)
	var boulder_texture := renderer._texture_for(shared_seed, StoneSize.CLASS_BOULDER)
	assert_ne(
		boulder_texture, pebble_texture,
		"a boulder must not inherit a pebble's cached texture just because they share a seed"
	)
	assert_eq(boulder_texture, renderer._illustrated_stones.frame_for(StoneSize.CLASS_BOULDER, shared_seed))
	assert_eq(pebble_texture, renderer._illustrated_stones.frame_for(StoneSize.CLASS_PEBBLE, shared_seed))
