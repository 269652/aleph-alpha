extends RefCounted

const TreePlacement = preload("res://src/world/tree_placement.gd")
const PixelNoise = preload("res://src/rendering/pixel_noise.gd")
const Chunk = preload("res://src/world/chunk.gd")
const ChoppableTree = preload("res://src/rendering/choppable_tree.gd")
const ProceduralTreeSprite = preload("res://src/rendering/procedural_tree_sprite.gd")
const TreeGenome = preload("res://src/gameplay/tree_genome.gd")
const WindSway = preload("res://src/rendering/wind_sway.gd")
const DropShadow = preload("res://src/rendering/drop_shadow.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")
const TreeGrowth = preload("res://src/gameplay/tree_growth.gd")
const TreeSpecies = preload("res://src/world/tree_species.gd")
const BuildingPiece = preload("res://src/gameplay/building_piece.gd")

## A tree's WORLD footprint (see ProceduralTreeSprite.WORLD_SIZE) -- derived
## from the art size through ArtResolution rather than equal to it, since
## the art is authored DETAIL_MULTIPLIER times oversized and drawn scaled
## back down (see docs/concept/art_resolution.md). Shadow and collision size
## off this, so they stay matched to the tree's actual world presence.
const TREE_SIZE := Vector2(ProceduralTreeSprite.WORLD_SIZE)
## The trunk's solid box, in world units: a little wider than the drawn
## trunk so brushing past feels forgiving, and shallow so it blocks only
## the trunk's own tile rather than a column of them.
const TRUNK_COLLISION_WIDTH_SCALE := 1.15
## NOTE: was bumped to 10.0 to try to keep an approaching player's head
## clear of the canopy (see git history / test_tree_renderer.gd), but that
## made the collision box reach far enough south to start blocking the tile
## BELOW the trunk again -- the exact regression this box was shrunk to
## fix in the first place. Reverted to 5.0 pending a real fix: the root
## cause is that the player is center-anchored while the tree is
## foot-anchored, so no amount of trunk-depth tuning alone can satisfy both
## "don't block the tile below" and "keep the player's head clear of the
## canopy" at once. Reported as still broken, and affecting stones too, not
## just trees -- needs a proper architectural pass, not another number.
const TRUNK_COLLISION_DEPTH := 5.0

## Cached and bounded (see _texture_for) rather than one unique texture per
## tree -- thousands of trees can be loaded at once, so per-instance pixel
## generation would be wasteful. Textures are keyed by NAMED species (see
## TreeSpecies) -- exactly TreeSpecies.IDS.size() (3) distinct looks, not one
## per tree and not one per continuously-rounded species_bias value.

var _tree_placement := TreePlacement.new()
var _tree_sprite_generator := ProceduralTreeSprite.new()
var _texture_cache: Dictionary = {}  # species id (String) -> ImageTexture
var _wind_sway := WindSway.new()
var _drop_shadow := DropShadow.new()


## Forwards the live wind strength (see WeatherModel.wind_strength_for, via
## EarthChunkManager.set_wind_strength) to the one shared canopy-sway
## material every spawned tree's sprite already uses (see spawn_tree_at).
func set_wind_strength(strength: float) -> void:
	_wind_sway.set_wind_strength(strength)


## Spawns a collidable tree node (as a child of `parent`) for every forested
## cell in the chunk, positioned at its global tile coordinate. Returns the
## spawned nodes so the caller can free them again when the chunk unloads.
func spawn_trees(
	parent: Node2D, chunk: Chunk, chunk_origin_tiles: Vector2i, tile_size: int
) -> Array[Node2D]:
	# Trees must sort against each other and against whoever walks among
	# them (see _build_tree_node's anchor comment).
	parent.y_sort_enabled = true

	var spawned: Array[Node2D] = []
	for y in chunk.height:
		var global_y := chunk_origin_tiles.y + y
		for x in chunk.width:
			var global_x := chunk_origin_tiles.x + x
			var biome_name := chunk.biome[y * chunk.width + x]
			if not _tree_placement.has_tree_at(global_x, global_y, biome_name):
				continue
			# A cell a real building piece already stands on is not open
			# ground. chunk.modifications is loaded from disk BEFORE this runs
			# (see EarthChunkManager._load_chunk), so without this the
			# deterministic forest respawns straight into a persisted house on
			# every revisit -- a trunk rooted in the floor with its canopy over
			# the roof (reported). Only REAL pieces count, the same distinction
			# EarthChunkManager._piece_grid_for draws: an earth path or a
			# campfire is a modification too, and neither uproots a tree.
			if BuildingPiece.has_piece(chunk.modifications.get(Vector2i(x, y), "")):
				continue

			var position := _stand_position(global_x, global_y, tile_size)
			var tree := _build_tree_node(position)
			tree.position = position
			parent.add_child(tree)
			spawned.append(tree)

	return spawned


## Spawns a single collidable tree node at an explicit position -- for a
## seed-spread sapling (see TreeSpread/EarthChunkManager.step_tree_spread)
## planted outside the original map-generated forest.
## `age_seconds` is how long the tree has stood (see TreeGrowth). Defaults
## to INF -- fully grown -- for callers that mean "a tree that was always
## here"; a freshly spread sapling passes 0.0 and starts as a seedling.
func spawn_tree_at(parent: Node2D, position: Vector2, age_seconds: float = INF) -> ChoppableTree:
	parent.y_sort_enabled = true
	var tree := _build_tree_node(position, age_seconds)
	tree.position = position
	parent.add_child(tree)
	return tree


## A collidable, choppable tree (see ChoppableTree), textured from this
## position's TreeGenome (see _texture_for). Trees deliberately run NO
## per-frame script: there are thousands loaded at once, so forage dropping is
## handled centrally and throttled by EarthChunkManager (see ForageScheduler)
## instead; take_damage() only runs on demand when an axe hits one.
## How far a tree may stand from the middle of its own tile, as a fraction of
## the tile.
##
## Trees stood at exact tile centres, so an original forest read as a lattice
## -- every trunk on a perfect grid, which no wood has ever looked like. Kept
## under half a tile so a tree never leaves the tile that has it: the tile with
## a tree still has that tree, it simply is not standing in the middle of it.
const STAND_OFFSET_FRACTION := 0.34


## Where the tree on this tile actually stands.
##
## Deterministic from the tile, like everything else about it, so a wood does
## not rearrange itself every time a chunk reloads.
func _stand_position(global_x: int, global_y: int, tile_size: int) -> Vector2:
	var span := float(tile_size) * STAND_OFFSET_FRACTION
	var across := float(PixelNoise.range_index(global_x * 7919 + global_y, 211, 0, 1001)) / 500.0 - 1.0
	var down := float(PixelNoise.range_index(global_x * 104729 + global_y, 223, 0, 1001)) / 500.0 - 1.0
	return Vector2(
		(float(global_x) + 0.5) * float(tile_size) + across * span,
		(float(global_y) + 0.5) * float(tile_size) + down * span
	)


func _build_tree_node(position: Vector2, age_seconds: float = INF) -> ChoppableTree:
	var body := ChoppableTree.new()

	var genome := TreeGenome.new(hash("%d_%d" % [int(position.x), int(position.y)]))
	body.species_bias = genome.species_bias
	body.sprite_seed = hash("%d_%d" % [int(position.x), int(position.y)])

	# Contact shadow at the trunk's base, added first so it draws under the
	# canopy sprite (sibling order == draw order). The body's origin IS the
	# trunk's foot (see the sprite anchor comment below), NOT the sprite's
	# center -- so unlike village_renderer's center-anchored shadows, this
	# one belongs almost AT the origin, not half the tree's height south of
	# it. Getting this wrong once stranded the shadow ~11 units into the
	# tile below, nowhere near the visible trunk (reported: "trees float").
	body.add_child(
		_drop_shadow.make_shadow(int(TREE_SIZE.x * 0.85), TRUNK_COLLISION_DEPTH * 0.5)
	)

	var sprite := Sprite2D.new()
	sprite.texture = _texture_for(position)
	# Growth stage: a tree spread in mid-session starts as a seedling and
	# thickens over time (see TreeGrowth), so a forest shows an age
	# structure instead of every trunk arriving full-grown. Original forest
	# trees are already mature -- they predate the session.
	body.growth_scale = TreeGrowth.new().scale_at(age_seconds)
	# The canopy art is authored DETAIL_MULTIPLIER times oversized for pixel
	# detail; scaling it back down is what keeps the tree's world footprint
	# unchanged (see docs/concept/art_resolution.md).
	sprite.scale = Vector2.ONE * ArtResolution.SPRITE_SCALE
	# Anchor the tree at the FOOT of its trunk rather than its middle, by
	# drawing the canopy above the node's origin. Y-sorting compares node
	# origins, so a centre-anchored tree sorts as though it stood where its
	# crown is -- and a player walking behind it would draw in front.
	sprite.offset.y = -float(ProceduralTreeSprite.SIZE.y) * 0.5
	# Canopy sways in the wind (GPU-only, preserving this function's no-per-
	# frame-script constraint) -- one shared material across all trees.
	sprite.material = _wind_sway.shared_material()
	body.add_child(sprite)
	body.bind_canopy(sprite)

	# Only the TRUNK is solid, and it sits at the node's origin -- which the
	# Y-sort anchor put at the foot of the trunk. Sizing this to the whole
	# canopy (as it was) blocked the tile below the tree while leaving the
	# trunk itself walkable, because the box stayed centred on an origin
	# that had moved. You should be able to walk under a canopy; you should
	# not be able to walk through a trunk.
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(
		ProceduralTreeSprite.trunk_world_width() * TRUNK_COLLISION_WIDTH_SCALE,
		TRUNK_COLLISION_DEPTH
	)
	collision.shape = shape
	collision.position = Vector2.ZERO
	body.add_child(collision)

	return body


## The season new trees are drawn in. Set by the caller (EarthChunkManager)
## before spawning, so a chunk loading in winter loads bare trees rather than
## summer ones that correct themselves a moment later.
var season := ""

## The season new trees are turning INTO, and how far along, so a tree that
## loads mid-turn arrives part-turned like its neighbours rather than snapping
## to whichever season it was built in.
var turning_into := ""
var turn_progress := 0.0


## The genome-tinted tree texture for a tree at `position` -- the same genome
## a tree at this position drops forage under (see ForageScheduler.genome_for),
## so a visibly fruit-leaning canopy actually drops more fruit.
##
## Cached per NAMED SPECIES AND SEASON (see TreeSpecies, IllustratedTree), not
## per tree, so the generated texture count stays bounded at species x seasons
## however many trees are loaded. The season belongs in the key: without it a
## forest would keep wearing whatever season it first loaded in.
func _texture_for(position: Vector2) -> ImageTexture:
	var genome := TreeGenome.new(hash("%d_%d" % [int(position.x), int(position.y)]))
	var species_id := TreeSpecies.species_for_bias(genome.species_bias)
	var key := "%s_%s_%s_%.2f" % [species_id, season, turning_into, turn_progress]
	if not _texture_cache.has(key):
		_texture_cache[key] = _tree_sprite_generator.generate_texture_with_fruit(
			genome.species_bias, hash(species_id), 0, season, turning_into, turn_progress
		)
	return _texture_cache[key]
