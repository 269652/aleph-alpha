extends RefCounted

## Spawns collidable boulder nodes for a chunk's stone cells (see
## StonePlacement) -- the stone-entity equivalent of TreeRenderer, and
## deliberately the same shape: deterministic per-position placement, a
## seeded procedural sprite (see ProceduralStoneSprite), a slightly-forgiving
## collision box, no per-frame script. Mining them (MiningYield) is a later
## wiring step; for now they are terrain landmarks that block movement.

const StonePlacement = preload("res://src/world/stone_placement.gd")
const OrePlacement = preload("res://src/world/ore_placement.gd")
const Chunk = preload("res://src/world/chunk.gd")
const ProceduralStoneSprite = preload("res://src/rendering/procedural_stone_sprite.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")
const ProceduralOreSprite = preload("res://src/rendering/procedural_ore_sprite.gd")
const SmashableStone = preload("res://src/rendering/smashable_stone.gd")
const LiftableStone = preload("res://src/rendering/liftable_stone.gd")
const StoneSize = preload("res://src/world/stone_size.gd")
const MinableOre = preload("res://src/rendering/minable_ore.gd")
const IllustratedStoneSprite = preload("res://src/rendering/illustrated_stone_sprite.gd")
const PixelNoise = preload("res://src/rendering/pixel_noise.gd")
const BuildingPiece = preload("res://src/gameplay/building_piece.gd")

## The boulder's WORLD footprint -- derived from its art size, which is
## authored DETAIL_MULTIPLIER times oversized (see
## docs/concept/art_resolution.md). Collision sizes off this, so it stays
## matched to what the player actually sees.
const STONE_SIZE := Vector2(ProceduralStoneSprite.SIZE) * ArtResolution.SPRITE_SCALE
const COLLISION_SCALE := 0.6

## Cached PER (SEED, CLASS) rather than per bucket (was: 4 shared buckets,
## same reasoning as TreeRenderer.SPECIES_BUCKETS -- reported: "they all have
## the same shape", because every stone in the world really was drawing from
## one of only 4 textures). ProceduralStoneSprite.generate_image is cheap
## (SIZE.x*SIZE.y = 1024 pixel writes, no per-frame cost -- generated once
## at spawn and cached like every other seeded generator here), and the
## worst case is bounded: LOAD_RADIUS chunks * CHUNK_SIZE^2 tiles *
## StonePlacement.STONE_DENSITY is at most on the order of a few hundred
## live stone nodes at once (see EarthChunkManager.LOAD_RADIUS/CHUNK_SIZE),
## each caching one small 32x32 ImageTexture -- trivial memory next to a
## bucket-of-4 cache that made real per-seed shape variety (see
## ProceduralStoneSprite's silhouette irregularity) invisible in-game.
##
## CLASS is part of the key, not just seed: two independently-derived seeds
## (a solitary stone's vs. a pebble flock member's) CAN numerically collide,
## and once pebbles AND boulders both had real, visually distinct illustrated
## art, a seed-only cache meant a colliding boulder could silently inherit a
## cached PEBBLE texture (see _texture_for's own doc comment).

var _stone_placement := StonePlacement.new()
var _stone_sprite_generator := ProceduralStoneSprite.new()
var _ore_sprite_generator := ProceduralOreSprite.new()
var _ore_placement := OrePlacement.new()
var _texture_cache: Dictionary = {}  # "<seed_value>_<stone_class>" (String) -> ImageTexture
## Untyped on purpose (not `:=`) so a test can substitute a fake with the
## same has_variants/frame_for shape (see test_stone_renderer.gd's
## _FakeIllustratedStones) without needing real art on disk.
var _illustrated_stones = IllustratedStoneSprite.new()


## Spawns a collidable stone node (as a child of `parent`) for every stone
## cell in the chunk. A minority of stone cells are ore-bearing (see
## OrePlacement.is_ore_at) and spawn a MinableOre node instead of a plain
## SmashableStone boulder. A pebble-class cell may instead spawn a FLOCK of
## several independently-seeded LiftableStone members (see
## StonePlacement.flock_size_at, docs/concept/stone.md) -- flat siblings, not
## one wrapping container (see _build_pebble_flock's own doc comment for
## why). Returns every spawned node -- one per ore cell, one per solitary
## stone, or `flock_size_at` many per flock cell -- so the caller can free
## them again when the chunk unloads.
func spawn_stones(
	parent: Node2D, chunk: Chunk, chunk_origin_tiles: Vector2i, tile_size: int
) -> Array[Node2D]:
	var spawned: Array[Node2D] = []
	for cell in _stone_placement.stones_in_chunk(
		chunk_origin_tiles, chunk.biome, chunk.width, chunk.height
	):
		var global_x := chunk_origin_tiles.x + cell.x
		var global_y := chunk_origin_tiles.y + cell.y
		if _piece_occupies(chunk, cell):
			continue
		var position := Vector2((global_x + 0.5) * tile_size, (global_y + 0.5) * tile_size)
		var biome_name: String = chunk.biome[cell.y * chunk.width + cell.x]

		if _ore_placement.is_ore_at(global_x, global_y, biome_name):
			var ore_node := _build_ore_node(global_x, global_y)
			ore_node.position = position
			parent.add_child(ore_node)
			spawned.append(ore_node)
			continue

		var flock_size := _stone_placement.flock_size_at(global_x, global_y)
		if flock_size > 1:
			for member in _build_pebble_flock(global_x, global_y, position, flock_size):
				parent.add_child(member)
				spawned.append(member)
			continue

		var node := _build_stone_node(_stone_placement.seed_at(global_x, global_y))
		node.position = position
		parent.add_child(node)
		spawned.append(node)
	return spawned


## Is `local_cell` already held by a real BUILDING PIECE, and therefore not
## open ground? (see docs/concept/building.md -- "a piece occupies its tile
## against vegetation", the same rule TreeRenderer.spawn_trees enforces for
## the forest, in the same place and for the same reason).
##
## EarthChunkManager._load_chunk loads `chunk.modifications` from disk BEFORE
## it spawns stones, and only stamps the village's houses afterwards -- so
## without this, boulders and ore respawn straight inside a persisted house
## on every revisit, including a player-built one the village generator never
## re-stamps. The complementary direction (a house stamped over a boulder
## that is ALREADY standing, on the first visit) cannot be closed here and
## lives in EarthChunkManager._clear_vegetation_on_cells.
##
## Deliberately narrow: only a REAL piece occupies, the same distinction
## EarthChunkManager._piece_grid_for draws. An earth path or a campfire is a
## chunk modification too, and neither clears a boulder (see
## test_a_non_piece_modification_does_not_stop_a_stone_spawning, which exists
## to go red if anyone widens this to `modifications.has`).
func _piece_occupies(chunk: Chunk, local_cell: Vector2i) -> bool:
	return BuildingPiece.has_piece(chunk.modifications.get(local_cell, ""))


## A loose stone at this position: a boulder to be broken, or a stone small
## enough to pick up (see docs/concept/stone.md). Which one is decided by the
## stone's SIZE, not by a flag -- if you can lift it, you take it.
func _build_stone_node(seed_value: int) -> Node2D:
	var diameter: float = StoneSize.diameter_for(seed_value)
	if StoneSize.is_liftable(diameter):
		return _build_liftable_node(seed_value, diameter)

	var body := SmashableStone.new()
	body.stone_seed = seed_value
	body.diameter_cm = diameter
	_attach_body_parts(body, _texture_for(seed_value, StoneSize.class_for(diameter)), diameter)
	return body


## Public wrapper around _build_liftable_node -- for callers outside this
## renderer that need to materialize a real, correctly-rendered liftable
## stone node directly (see Player._spawn_thrown_stone, the held-item
## throw's landing spot) rather than reaching into a private method across
## files.
func build_liftable_stone_node(seed_value: int, diameter_cm: float) -> Node2D:
	return _build_liftable_node(seed_value, diameter_cm)


## A pebble or cobble: a sprite you can walk over and pick up, with no
## collision body at all. Only boulders block.
func _build_liftable_node(seed_value: int, diameter: float) -> Node2D:
	var stone := LiftableStone.new()
	stone.stone_seed = seed_value
	stone.diameter_cm = diameter
	var sprite := Sprite2D.new()
	sprite.texture = _texture_for(seed_value, StoneSize.class_for(diameter))
	sprite.scale = Vector2.ONE * _sprite_scale_for(diameter)
	stone.add_child(sprite)
	return stone


# -- pebble flocks (see docs/concept/stone.md, StonePlacement.flock_size_at) -

## How far a flock member may sit from the cell's own centre, and how far
## apart consecutive members stay, in WORLD pixels -- not art pixels, since
## flock members are independent placed nodes, not regions of one canvas
## (contrast ProceduralFlowerSprite.BUSH_STEM_SPACING_PX, which IS in art
## pixels). Kept comfortably inside a half-tile (TILE_SIZE/2 == 8 at the
## standard 16px tile) so a flock reads as sitting on its own cell, and
## comfortably inside Player.PICKUP_RADIUS (34) so approaching a flock once
## collects every member in the same pickup_nearby sweep -- no special-cased
## "pick up the flock" action needed.
const FLOCK_MEMBER_SPACING_PX := 4.5

## How much a member's angle/radius may vary from an even ring, as a
## fraction of its slot -- same reasoning as
## ProceduralFlowerSprite.BUSH_SPREAD_JITTER: a perfectly even ring of
## pebbles reads as a diagram, not scree.
const FLOCK_SPREAD_JITTER := 0.3


## A cluster of several pebbles at one cell, standing in for the single
## pebble that would otherwise spawn there. Each member is a REAL
## independently-seeded LiftableStone -- its own diameter, its own shape/
## grain, its own yield -- rather than one entity with an invented "handful"
## yield: that keeps the economy exactly what it already is for every other
## seeded pickup in this game, and it is what makes a flock actually look
## like several different pebbles instead of one sprite stamped several
## times (see ProceduralStoneSprite's per-seed irregularity/grain, or
## IllustratedStoneSprite's per-seed variant pick once real art lands).
##
## Returned as flat SIBLING nodes, not one wrapping container. A container
## positioned at the cell centre would put each member's own `.position` in
## the container's LOCAL space rather than world space, which would break
## Player.pickup_nearby's distance check (it compares `.position` directly,
## not `global_position`) -- flat siblings keep every member's `.position`
## correct with no changes needed to the pickup sweep, or to
## EarthChunkManager's per-node bookkeeping, at all.
func _build_pebble_flock(
	global_x: int, global_y: int, cell_center: Vector2, member_count: int
) -> Array[Node2D]:
	var base_seed := _stone_placement.seed_at(global_x, global_y)
	var members: Array[Node2D] = []
	for index in member_count:
		var member_seed := _stone_placement.flock_member_seed(base_seed, index)
		var diameter := StoneSize.pebble_diameter_for(member_seed)
		var stone := _build_liftable_node(member_seed, diameter)
		stone.position = cell_center + _flock_member_offset(member_seed, index, member_count)
		members.append(stone)
	return members


## Where flock member `member_index` (of `member_count`) sits relative to the
## cell's own centre. Member 0 sits at the exact centre -- the same place a
## lone pebble sits today, so a flock's first member alone still satisfies
## every "a stone sits at its tile centre" assumption elsewhere in this
## codebase -- and the rest ring outward at even angular steps so members
## can never land on top of each other BY CONSTRUCTION, with a seeded wobble
## so the ring doesn't read as a perfectly-ruled diagram (see
## FLOCK_SPREAD_JITTER).
func _flock_member_offset(seed_value: int, member_index: int, member_count: int) -> Vector2:
	if member_index == 0:
		return Vector2.ZERO
	var slot := TAU / float(member_count)
	var wobble := PixelNoise.range_value(seed_value, 12, 1, -1.0, 1.0)
	var angle := slot * float(member_index) + wobble * slot * FLOCK_SPREAD_JITTER
	var radius := FLOCK_MEMBER_SPACING_PX * (1.0 + wobble * FLOCK_SPREAD_JITTER * 0.5)
	return Vector2(cos(angle), sin(angle)) * radius


## What to scale a stone's sprite by so it stands at its real size.
##
## The art is one canvas whatever the stone is, so the size lives here: a
## boulder is drawn near the full canvas and a pebble at a fraction of it.
## Derived from StoneSize.world_height_px rather than from a per-class factor,
## so the drawn size and the size the rules use can never drift apart.
func _sprite_scale_for(diameter_cm: float) -> float:
	return StoneSize.world_height_px(diameter_cm) / float(ProceduralStoneSprite.SIZE.y)


func _build_ore_node(global_x: int, global_y: int) -> StaticBody2D:
	var ore_type := _ore_placement.ore_type_at(global_x, global_y)
	var seed_value := _ore_placement.seed_at(global_x, global_y)
	var body := MinableOre.new()
	body.ore_type = ore_type
	body.ore_seed = seed_value
	# Ore art isn't cached by bucket -- there are far fewer ore nodes than
	# plain boulders, and the flecks should reflect the actual ore type/seed.
	_attach_body_parts(body, _ore_texture_for(ore_type, seed_value))
	return body


## An ore node is always drawn at boulder scale regardless of the underlying
## cell's rolled diameter (see _attach_body_parts' diameter_cm==0 branch), so
## it always asks illustrated art for CLASS_BOULDER specifically -- the same
## has_variants()-gated fallback _texture_for already uses for plain loose
## stone, just with the ore's own flecks composited onto that illustrated
## frame (ProceduralOreSprite.generate_texture_from_base) rather than reused
## as-is, so the ore type still reads at a glance. Falls back to the flat
## procedural boulder+flecks (generate_texture) when no illustrated boulder
## art is registered.
func _ore_texture_for(ore_type: String, seed_value: int) -> ImageTexture:
	if _illustrated_stones.has_variants(StoneSize.CLASS_BOULDER):
		var base: ImageTexture = _illustrated_stones.frame_for(StoneSize.CLASS_BOULDER, seed_value)
		if base != null:
			return _ore_sprite_generator.generate_texture_from_base(base.get_image(), ore_type, seed_value)
	return _ore_sprite_generator.generate_texture(ore_type, seed_value)


## `diameter_cm` of 0 keeps the node at the shared art scale, which is what
## ore veins want -- an ore boulder is one fixed size, and only loose stone
## varies (see docs/concept/stone.md).
func _attach_body_parts(body: StaticBody2D, texture: Texture2D, diameter_cm: float = 0.0) -> void:
	var sprite_scale := (
		ArtResolution.SPRITE_SCALE if diameter_cm <= 0.0 else _sprite_scale_for(diameter_cm)
	)
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.scale = Vector2.ONE * sprite_scale
	body.add_child(sprite)

	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	# The blocking shape follows the DRAWN size, so a small boulder does not
	# stop the player at arm's length from where it actually is.
	shape.size = Vector2(ProceduralStoneSprite.SIZE) * sprite_scale * COLLISION_SCALE
	collision.shape = shape
	body.add_child(collision)


## `stone_class` defaults to CLASS_BOULDER so the existing single-argument
## call (SmashableStone's own texture, and every pre-flock call site/test)
## keeps working unchanged.
##
## Illustrated art (see IllustratedStoneSprite) wins when this stone's CLASS
## has a real sheet registered; otherwise this is exactly the per-seed
## procedural cache it always was. Texture-source-agnostic by construction:
## every caller (solitary stone or flock member alike) asks for "a texture
## for this seed/class" through this one seam, with no separate code path
## for illustrated vs procedural art anywhere else in this file.
##
## Cached by (seed_value, stone_class) TOGETHER, not seed_value alone.
## Regression: a pebble flock member's seed (StonePlacement.flock_member_seed)
## and a solitary boulder's seed (StonePlacement.seed_at) are independently
## derived and CAN numerically collide at real-world stone counts -- when
## they did under a seed-only cache, whichever stone's texture was cached
## FIRST for that seed_value got silently reused for the second, WRONG-CLASS
## stone too (invisible while only pebbles had real art; a "wrong" texture
## for a boulder was just another indistinguishable procedural boulder --
## surfaced once boulders got real, visually distinct art of their own). See
## test_texture_for_does_not_collide_across_stone_classes_sharing_a_seed.
func _texture_for(seed_value: int, stone_class: String = StoneSize.CLASS_BOULDER) -> ImageTexture:
	var cache_key := "%d_%s" % [seed_value, stone_class]
	if not _texture_cache.has(cache_key):
		if _illustrated_stones.has_variants(stone_class):
			_texture_cache[cache_key] = _illustrated_stones.frame_for(stone_class, seed_value)
		else:
			_texture_cache[cache_key] = _stone_sprite_generator.generate_texture(seed_value)
	return _texture_cache[cache_key]


# -- mountain ore veins: slope-gated placement (see docs/concept/terrain_relief.md) -
#
# A separate spawn path from spawn_stones above -- mountain isn't in
# StonePlacement.STONE_BIOMES at all, and even where it overlapped, vein
# placement is gated by real LOCAL SLOPE (MountainOrePlacement), not the
# flat per-tile density roll grassland/forest ore uses.

const MountainOrePlacement = preload("res://src/world/mountain_ore_placement.gd")

var _mountain_ore_placement := MountainOrePlacement.new()


## Spawns a collidable ore-vein node for every mountain cell whose real
## local slope rolls a vein (see MountainOrePlacement). `slope_lookup` is
## anything with a `slope_at_global(global_x, global_y)` method -- real
## EarthChunkManager, or a test fake (see test_stone_renderer.gd's
## _FakeSlopeLookup, the same fake-injection shape _illustrated_stones
## already uses) -- left untyped/duck-typed so this file doesn't need to
## import EarthChunkManager's type. Returns every spawned node, same
## contract as spawn_stones, so the caller can free them on unload.
func spawn_mountain_veins(
	parent: Node2D, chunk: Chunk, chunk_origin_tiles: Vector2i, tile_size: int, slope_lookup
) -> Array[Node2D]:
	var spawned: Array[Node2D] = []
	for y in chunk.height:
		for x in chunk.width:
			var biome_name: String = chunk.biome[y * chunk.width + x]
			if biome_name != "mountain":
				continue
			# Same occupancy rule as spawn_stones -- a vein is placed by a
			# different rule but arrives at the same point in _load_chunk and
			# lands in the same _loaded_stones list, so a player-built
			# mountain shelter must not sprout ore through its floor.
			if _piece_occupies(chunk, Vector2i(x, y)):
				continue
			var global_x := chunk_origin_tiles.x + x
			var global_y := chunk_origin_tiles.y + y
			var slope: float = slope_lookup.slope_at_global(global_x, global_y)
			if not _mountain_ore_placement.has_vein_at(global_x, global_y, slope):
				continue
			var node := _build_mountain_vein_node(global_x, global_y)
			node.position = Vector2((global_x + 0.5) * tile_size, (global_y + 0.5) * tile_size)
			parent.add_child(node)
			spawned.append(node)
	return spawned


## Same shape as _build_ore_node, drawing from the exact same
## illustrated-boulder-composited texture path (_ore_texture_for) -- a
## mountain vein is visually and mechanically an ore node, just placed by a
## different rule. MountainOrePlacement.ore_type_at/seed_at reuse
## OrePlacement's own derivation exactly (see that class's own doc
## comment), so this composes with the existing ore-texture cache/
## compositing with no changes needed there.
func _build_mountain_vein_node(global_x: int, global_y: int) -> StaticBody2D:
	var ore_type := _mountain_ore_placement.ore_type_at(global_x, global_y)
	var seed_value := _mountain_ore_placement.seed_at(global_x, global_y)
	var body := MinableOre.new()
	body.ore_type = ore_type
	body.ore_seed = seed_value
	_attach_body_parts(body, _ore_texture_for(ore_type, seed_value))
	return body
