extends RefCounted

const BiomeClassifier = preload("res://src/world/biome_classifier.gd")
const Chunk = preload("res://src/world/chunk.gd")
const ProceduralTerrainSprite = preload("res://src/rendering/procedural_terrain_sprite.gd")
const ProceduralStructureSprite = preload("res://src/rendering/procedural_structure_sprite.gd")
const ProceduralShoreDistanceSprite = preload("res://src/rendering/procedural_shore_distance_sprite.gd")

const TILE_SIZE := 16

## Representative flat color per biome -- NOT used for actual tile art
## anymore (see ProceduralTerrainSprite for that); MinimapRenderer keeps
## using these as small, easily-distinguishable minimap swatches, where a
## textured close-up look would just be visual noise at that scale.
const BIOME_COLORS := {
	"ocean": Color(0.15, 0.35, 0.65),
	"mountain": Color(0.55, 0.55, 0.58),
	"tundra": Color(0.8, 0.85, 0.85),
	"forest": Color(0.13, 0.4, 0.18),
	"grassland": Color(0.45, 0.65, 0.25),
	"rainforest": Color(0.05, 0.3, 0.1),
	"desert": Color(0.85, 0.75, 0.45),
}

## How many distinct procedurally-generated variants each biome gets in the
## atlas -- picked per tile position (see variant_index_for_position) so the
## ground reads as naturally varied rather than one obviously-repeating
## texture, while staying deterministic (revisiting the same tile always
## looks the same). Six (up from four) so ground cover reads as natural
## variation, not a short texture loop -- pinned by
## test_variants_per_biome_is_at_least_six.
const VARIANTS_PER_BIOME := 6

## Base biome tiles animate in real time (scrolling water, swaying grass --
## see ProceduralTerrainSprite.generate_frame_image): each biome variant
## reserves FRAME_COUNT consecutive atlas cells, its frames laid out
## horizontally, registered via TileSetAtlasSource's tile animation so
## TileMapLayer plays them with zero per-frame script cost. ATLAS_COLUMNS
## must divide evenly by FRAME_COUNT so a frame row never wraps the atlas
## (pinned by test_atlas_columns_align_with_frame_blocks).
const FRAME_COUNT := ProceduralTerrainSprite.FRAME_COUNT

## Seconds each animation frame holds -- a slow, ambient shimmer/sway pace,
## not a strobing arcade loop. Pinned by
## test_biome_tiles_are_registered_as_animated_with_the_pinned_frame_count.
const FRAME_DURATION_SECONDS := 0.45

## Grassland ticks faster than the ambient default: the baked blade-sway
## cycle needs a livelier clock to read as wind at screen scale (pinned by
## test_biome_tiles_are_registered_as_animated_with_the_pinned_frame_count).
const GRASS_FRAME_DURATION_SECONDS := 0.28

## Phase 3's Terraria-style build/destroy tile: pressing E turns the faced
## tile into bare earth (Q reverts it). A single placeable structure type
## for now -- Chunk.modifications maps a local tile coord to this id when
## the player has built there.
const EARTH_TILE_ID := "earth"
const EARTH_COLOR := Color(0.35, 0.25, 0.15)

## Cardinal directions a blend can be oriented toward -- up/down/left/right,
## in this fixed order so mask/atlas indexing is stable.
const _DIRECTIONS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
const _DIRECTION_COUNT := 4

## A blend tile bakes in *which* cardinal edges lean toward the far biome, as a
## bitmask over _DIRECTIONS. Every non-empty subset of the 4 edges gets its own
## tile so a cell can dither toward a neighbor on any combination of sides (and
## their shared corners) -- that's (2^4 - 1) = 15 masks.
const DIRECTION_MASK_COUNT := (1 << _DIRECTION_COUNT) - 1

## Border/blend tiles keep fewer variants than base ground: they're
## transitional fringe noise, not the surface the eye rests on, and every
## extra blend variant costs n*(n-1)*15 more generated atlas images at
## startup. Three here (vs. six base variants) keeps the atlas build FASTER
## than the original 4-variant scheme while the ground itself got richer.
## atlas_coords_for_directional_blend folds the caller's 0..VARIANTS_PER_BIOME
## variant into this range, so callers don't care about the difference.
const BLEND_VARIANTS := 3

## Every ordered (near, far) biome pair reserves this many atlas tiles: one per
## direction mask x BLEND_VARIANTS.
const _TILES_PER_PAIR := DIRECTION_MASK_COUNT * BLEND_VARIANTS

## The atlas is laid out as a grid this many tiles wide (rather than a single
## row) -- with every differing biome pair blended, the tile count runs into
## the thousands and a single row would exceed the max texture width.
const ATLAS_COLUMNS := 64

var _terrain_sprite_generator := ProceduralTerrainSprite.new()
var _structure_sprite_generator := ProceduralStructureSprite.new()
var _shore_distance_generator := ProceduralShoreDistanceSprite.new()


## Returns the atlas coordinate for one biome's variant -- the FIRST frame of
## its FRAME_COUNT-cell animation block. Biome variant blocks occupy the first
## region of the atlas, in BiomeClassifier.KNOWN_BIOMES order; the cells after
## each returned coordinate hold that tile's remaining animation frames (see
## build_tile_set) and are never tiles of their own.
func atlas_coords_for_biome(biome_name: String, variant_index: int = 0) -> Vector2i:
	var biome_index := BiomeClassifier.KNOWN_BIOMES.find(biome_name)
	return _grid_coords((biome_index * VARIANTS_PER_BIOME + variant_index) * FRAME_COUNT)


## Returns the atlas coordinate for a player-placed modification tile,
## positioned right after all biome variant tiles in the shared atlas. Known
## structure ids (see ProceduralStructureSprite.STRUCTURE_IDS -- campfire,
## furnace) each get their own dedicated slot; EARTH_TILE_ID and any
## unrecognized id fall back to the single plain-earth slot (fail-safe
## default, matching this codebase's `.get(x, default)` convention -- never
## crash on an unknown tile_id).
func atlas_coords_for_modification(tile_id: String) -> Vector2i:
	if ProceduralStructureSprite.STRUCTURE_IDS.has(tile_id):
		return _grid_coords(_structure_linear(tile_id))
	return _grid_coords(_earth_linear())


## Which of a biome's VARIANTS_PER_BIOME procedural tiles a given global tile
## position should use -- deterministic (the same tile always looks the same
## across sessions/reloads) but varies from position to position so the
## ground doesn't read as one repeating texture.
func variant_index_for_position(global_x: int, global_y: int) -> int:
	return absi(hash("%d_%d_terrain_variant" % [global_x, global_y])) % VARIANTS_PER_BIOME


## Returns the atlas coordinate for a directional blended border tile:
## near_biome is this tile's own biome, far_biome is the neighbor it's blending
## toward, and `directions` is every cardinal direction that neighbor lies in
## (see ProceduralTerrainSprite.generate_multi_directional_blend_image). Order
## within `directions` doesn't matter -- it's reduced to a set/mask.
func atlas_coords_for_directional_blend(
	near_biome: String, far_biome: String, directions: Array, variant_index: int = 0
) -> Vector2i:
	var mask := _direction_mask(directions)
	return _grid_coords(_blend_linear(near_biome, far_biome, mask, variant_index))


## Which biome fringes over which at a border: exactly ONE side of any border
## renders a transition tile -- the higher-priority biome dithers over its
## lower-priority neighbor while that neighbor stays a pure tile (both sides
## blending doubles the fringe into a mushy two-tile band). Land overlaps
## water, denser vegetation overlaps sparser ground.
const BLEND_PRIORITY := {
	"ocean": 0,
	"desert": 1,
	"tundra": 2,
	"grassland": 3,
	"rainforest": 4,
	"forest": 5,
	"mountain": 6,
}


## Given this cell's biome and a Dictionary of direction -> neighbor biome name
## (see _neighbor_biomes), returns {"partner": <biome>, "directions": Array of
## Vector2i toward it} for the differing LOWER-priority neighbor biome (see
## BLEND_PRIORITY -- only the higher-priority side of a border fringes) that
## covers the most edges (ties broken by BiomeClassifier.KNOWN_BIOMES order
## for determinism); or an empty Dictionary if no eligible neighbor exists.
func dominant_blend_for(biome_name: String, neighbor_biomes: Dictionary) -> Dictionary:
	var own_priority: int = BLEND_PRIORITY.get(biome_name, 0)
	var directions_by_biome := {}
	for direction in neighbor_biomes:
		var neighbor: String = neighbor_biomes[direction]
		if neighbor == biome_name:
			continue
		if BLEND_PRIORITY.get(neighbor, 0) >= own_priority:
			continue
		if not directions_by_biome.has(neighbor):
			directions_by_biome[neighbor] = []
		directions_by_biome[neighbor].append(direction)

	if directions_by_biome.is_empty():
		return {}

	var best_biome := ""
	var best_directions: Array = []
	for candidate in directions_by_biome:
		var candidate_directions: Array = directions_by_biome[candidate]
		if _is_more_dominant(candidate, candidate_directions, best_biome, best_directions):
			best_biome = candidate
			best_directions = candidate_directions
	return {"partner": best_biome, "directions": best_directions}


## True if (candidate, its directions) should beat the current best: more edges
## wins, and an equal edge count is broken toward the earlier KNOWN_BIOMES
## entry so the choice is deterministic regardless of neighbor iteration order.
func _is_more_dominant(candidate: String, candidate_directions: Array, best_biome: String, best_directions: Array) -> bool:
	if best_biome == "":
		return true
	if candidate_directions.size() != best_directions.size():
		return candidate_directions.size() > best_directions.size()
	return BiomeClassifier.KNOWN_BIOMES.find(candidate) < BiomeClassifier.KNOWN_BIOMES.find(best_biome)


func _biome_tile_count() -> int:
	return BiomeClassifier.KNOWN_BIOMES.size() * VARIANTS_PER_BIOME


## Linear atlas index of the single player-placeable "earth" tile: right after
## all biome variant animation blocks (each biome tile spans FRAME_COUNT cells).
func _earth_linear() -> int:
	return _biome_tile_count() * FRAME_COUNT


## Linear atlas index where the per-structure tiles begin (right after the
## earth tile) -- see ProceduralStructureSprite.STRUCTURE_IDS.
func _structure_base_linear() -> int:
	return _earth_linear() + 1


## Linear atlas index of one known structure's tile (campfire, furnace, ...),
## in ProceduralStructureSprite.STRUCTURE_IDS order. Callers must check
## STRUCTURE_IDS.has(tile_id) first -- unrecognized ids aren't this function's
## job to guard against (see atlas_coords_for_modification's fallback).
func _structure_linear(tile_id: String) -> int:
	return _structure_base_linear() + ProceduralStructureSprite.STRUCTURE_IDS.find(tile_id)


## Linear atlas index where the blend tiles begin (right after the earth and
## structure tiles).
func _blend_base_linear() -> int:
	return _structure_base_linear() + ProceduralStructureSprite.STRUCTURE_IDS.size()


## Linear atlas index of one blend tile. Pairs are ordered (near, far) with the
## near==far slot skipped, so each of the N biomes has N-1 partners. The
## caller's variant (0..VARIANTS_PER_BIOME) folds into the smaller
## BLEND_VARIANTS range (see that constant's doc comment).
func _blend_linear(near_biome: String, far_biome: String, mask: int, variant_index: int) -> int:
	var near_index := BiomeClassifier.KNOWN_BIOMES.find(near_biome)
	var far_index := BiomeClassifier.KNOWN_BIOMES.find(far_biome)
	var far_ordinal := far_index if far_index < near_index else far_index - 1
	var pair_ordinal := near_index * (BiomeClassifier.KNOWN_BIOMES.size() - 1) + far_ordinal
	return (
		_blend_base_linear() + pair_ordinal * _TILES_PER_PAIR
		+ (mask - 1) * BLEND_VARIANTS + (variant_index % BLEND_VARIANTS)
	)


## Converts a set of cardinal directions into a bitmask over _DIRECTIONS.
func _direction_mask(directions: Array) -> int:
	var mask := 0
	for direction in directions:
		mask |= 1 << _DIRECTIONS.find(direction)
	return mask


## The cardinal directions set in a bitmask, in _DIRECTIONS order.
func _directions_from_mask(mask: int) -> Array:
	var directions := []
	for bit in _DIRECTION_COUNT:
		if mask & (1 << bit):
			directions.append(_DIRECTIONS[bit])
	return directions


## Maps a linear atlas index onto the ATLAS_COLUMNS-wide tile grid.
func _grid_coords(linear_index: int) -> Vector2i:
	return Vector2i(linear_index % ATLAS_COLUMNS, linear_index / ATLAS_COLUMNS)


## Blits a 16x16 tile image into the shared atlas image at the grid cell for
## `linear_index`.
func _blit_tile(atlas_image: Image, tile_image: Image, linear_index: int) -> void:
	var coords := _grid_coords(linear_index)
	atlas_image.blit_rect(
		tile_image, Rect2i(Vector2i.ZERO, Vector2i(TILE_SIZE, TILE_SIZE)), coords * TILE_SIZE
	)


## Builds a grid-laid-out TileSet: VARIANTS_PER_BIOME procedural tiles per known
## biome, one player-placeable "earth" tile, one dedicated tile per known
## placed structure (ProceduralStructureSprite.STRUCTURE_IDS -- campfire,
## furnace), then a directional blend tile for every ordered pair of distinct
## biomes x every non-empty cardinal-direction subset (DIRECTION_MASK_COUNT
## masks) x VARIANTS_PER_BIOME.
func build_tile_set() -> TileSet:
	var biome_count := BiomeClassifier.KNOWN_BIOMES.size()
	var total_cells := _blend_base_linear() + biome_count * (biome_count - 1) * _TILES_PER_PAIR
	var rows := int(ceil(float(total_cells) / ATLAS_COLUMNS))

	var image := Image.create(ATLAS_COLUMNS * TILE_SIZE, rows * TILE_SIZE, false, Image.FORMAT_RGBA8)

	# Base biome tiles: FRAME_COUNT animation frames each, blitted into
	# consecutive cells (the block never wraps a row -- see FRAME_COUNT's doc
	# comment on the ATLAS_COLUMNS alignment invariant).
	for i in biome_count:
		var biome_name: String = BiomeClassifier.KNOWN_BIOMES[i]
		for variant in VARIANTS_PER_BIOME:
			var block_start := (i * VARIANTS_PER_BIOME + variant) * FRAME_COUNT
			for frame in FRAME_COUNT:
				var frame_image := _terrain_sprite_generator.generate_frame_image(biome_name, variant, frame)
				_blit_tile(image, frame_image, block_start + frame)

	var earth_image := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	earth_image.fill(EARTH_COLOR)
	_blit_tile(image, earth_image, _earth_linear())

	for structure_id in ProceduralStructureSprite.STRUCTURE_IDS:
		var structure_image := _structure_sprite_generator.generate_image(structure_id)
		_blit_tile(image, structure_image, _structure_linear(structure_id))

	for near_index in biome_count:
		for far_index in biome_count:
			if far_index == near_index:
				continue
			var near_biome: String = BiomeClassifier.KNOWN_BIOMES[near_index]
			var far_biome: String = BiomeClassifier.KNOWN_BIOMES[far_index]
			for mask in range(1, DIRECTION_MASK_COUNT + 1):
				var directions := _directions_from_mask(mask)
				for variant in BLEND_VARIANTS:
					var blend_image := _terrain_sprite_generator.generate_multi_directional_blend_image(
						near_biome, far_biome, directions, variant
					)
					_blit_tile(image, blend_image, _blend_linear(near_biome, far_biome, mask, variant))

	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(image)
	source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)

	# Animated biome tiles: one created tile per block, at its first frame's
	# cell; the remaining cells of the block are claimed as animation frames
	# (never created as tiles of their own), and TileMapLayer plays them
	# automatically -- zero per-frame script cost.
	for i in biome_count:
		var duration := (
			GRASS_FRAME_DURATION_SECONDS
			if BiomeClassifier.KNOWN_BIOMES[i] == "grassland"
			else FRAME_DURATION_SECONDS
		)
		for variant in VARIANTS_PER_BIOME:
			var first := _grid_coords((i * VARIANTS_PER_BIOME + variant) * FRAME_COUNT)
			source.create_tile(first)
			source.set_tile_animation_frames_count(first, FRAME_COUNT)
			for frame in FRAME_COUNT:
				source.set_tile_animation_frame_duration(first, frame, duration)

	# Earth, structures, and blend tiles stay static single-cell tiles.
	source.create_tile(_grid_coords(_earth_linear()))
	for structure_id in ProceduralStructureSprite.STRUCTURE_IDS:
		source.create_tile(_grid_coords(_structure_linear(structure_id)))
	for linear_index in range(_blend_base_linear(), total_cells):
		source.create_tile(_grid_coords(linear_index))

	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	tile_set.add_source(source, 0)
	return tile_set


## Paints every cell of a chunk's biome grid onto a TileMapLayer, offset by
## origin (in tile coordinates) -- used to place a chunk at its global
## position when streaming multiple chunks onto one shared TileMapLayer. A
## cell with a player-made modification (see Chunk.modifications) paints that
## instead of its generated biome tile; otherwise, if any cardinal neighbor
## *within this same chunk* is a different biome, a corner-aware directional
## blend tile is used -- the cell dithers toward the dominant differing neighbor
## biome (see dominant_blend_for) on every edge that neighbor occupies, so
## borders read as soft transitions rather than hard square cuts. Neighbors
## falling outside the chunk are resolved through `global_biome_lookup`
## (a Callable(global_x, global_y) -> String biome name, or "" for unknown)
## when one is provided -- so chunk seams blend just like interior borders;
## without a lookup, out-of-chunk neighbors are simply ignored as before.
## The tile's global position picks a deterministic procedural variant either
## way (see variant_index_for_position).
func paint(
	tile_map_layer: TileMapLayer,
	chunk: Chunk,
	origin: Vector2i = Vector2i.ZERO,
	global_biome_lookup: Callable = Callable()
) -> void:
	for y in chunk.height:
		for x in chunk.width:
			var local := Vector2i(x, y)
			var global := origin + local
			var atlas_coords: Vector2i
			if chunk.modifications.has(local):
				atlas_coords = atlas_coords_for_modification(chunk.modifications[local])
			else:
				var biome_name: String = chunk.biome[y * chunk.width + x]
				var variant := variant_index_for_position(global.x, global.y)
				var neighbors := _neighbor_biomes(chunk, x, y, origin, global_biome_lookup)
				# Water never fringes over land (lowest BLEND_PRIORITY), so
				# ocean cells always fall through to the plain animated tile
				# here -- shore blending and rain now live entirely on the
				# GPU WaterFx overlay (see build_water_overlay_tile_set,
				# EarthChunkManager.set_water_layer, water_shader.gd), which
				# reads land-proximity as continuous per-pixel data instead
				# of swapping discrete baked tiles at the 16px tile grid
				# (the old approach's jagged shore-staircase look).
				var blend := dominant_blend_for(biome_name, neighbors)
				if blend.is_empty():
					atlas_coords = atlas_coords_for_biome(biome_name, variant)
				else:
					atlas_coords = atlas_coords_for_directional_blend(
						biome_name, blend.partner, blend.directions, variant
					)
			tile_map_layer.set_cell(global, 0, atlas_coords)


## The cardinal neighbor biomes of a local chunk cell, keyed by direction
## (see _DIRECTIONS). Neighbors inside the chunk read straight off its biome
## grid; neighbors outside it are resolved via `global_biome_lookup` when
## provided (asked with the neighbor's *global* tile coordinate), and omitted
## when the lookup is invalid or answers "" (unknown).
func _neighbor_biomes(
	chunk: Chunk, x: int, y: int, origin: Vector2i, global_biome_lookup: Callable
) -> Dictionary:
	var neighbors := {}
	for direction in _DIRECTIONS:
		var nx: int = x + direction.x
		var ny: int = y + direction.y
		if nx >= 0 and nx < chunk.width and ny >= 0 and ny < chunk.height:
			neighbors[direction] = chunk.biome[ny * chunk.width + nx]
		elif global_biome_lookup.is_valid():
			var neighbor_biome: String = global_biome_lookup.call(origin.x + nx, origin.y + ny)
			if neighbor_biome != "":
				neighbors[direction] = neighbor_biome
	return neighbors


## Clears a chunk_size x chunk_size region starting at origin, undoing a
## previous paint() call -- used when a chunk streams out of range.
func erase(tile_map_layer: TileMapLayer, chunk_size: int, origin: Vector2i = Vector2i.ZERO) -> void:
	for y in chunk_size:
		for x in chunk_size:
			tile_map_layer.erase_cell(origin + Vector2i(x, y))


## The atlas coordinate of the WaterFx overlay tile for an ocean cell whose
## land neighbors lie in `land_directions` (empty == open water, no land
## neighbor). Order-independent (reduced to a mask, matching
## atlas_coords_for_directional_blend's convention) -- callers can pass the
## direction list in any order.
func atlas_coords_for_water_overlay(land_directions: Array) -> Vector2i:
	if land_directions.is_empty():
		return Vector2i(0, 0)
	return Vector2i(_direction_mask(land_directions), 0)


## A small, separate TileSet for the GPU water overlay layer (see
## EarthChunkManager.set_water_layer): one flat "deep water" tile plus one
## per cardinal land-direction mask (DIRECTION_MASK_COUNT = 15), each holding
## real shore-distance DATA (see ProceduralShoreDistanceSprite) rather than
## art -- water_shader.gd samples it as a texture channel to blend and
## animate everything continuously on the GPU. No animation-frame bookkeeping
## needed here at all: unlike the old baked shore/rain tiles, every bit of
## motion (waves, shore reflection, raindrop ripples) is computed in the
## shader from TIME and world position, not by swapping tile frames.
func build_water_overlay_tile_set() -> TileSet:
	var total := 1 + DIRECTION_MASK_COUNT
	var image := Image.create(total * TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	image.blit_rect(
		_shore_distance_generator.generate_deep_water_image(),
		Rect2i(Vector2i.ZERO, Vector2i(TILE_SIZE, TILE_SIZE)), Vector2i.ZERO
	)
	for mask in range(1, DIRECTION_MASK_COUNT + 1):
		var land_directions := _directions_from_mask(mask)
		var distance_image := _shore_distance_generator.generate_image(land_directions)
		image.blit_rect(
			distance_image, Rect2i(Vector2i.ZERO, Vector2i(TILE_SIZE, TILE_SIZE)), Vector2i(mask * TILE_SIZE, 0)
		)

	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(image)
	source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	for i in total:
		source.create_tile(Vector2i(i, 0))

	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	tile_set.add_source(source, 0)
	return tile_set
