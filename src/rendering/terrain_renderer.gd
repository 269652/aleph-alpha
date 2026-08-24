extends RefCounted

const BiomeClassifier = preload("res://src/world/biome_classifier.gd")
const Chunk = preload("res://src/world/chunk.gd")
const ProceduralTerrainSprite = preload("res://src/rendering/procedural_terrain_sprite.gd")
const ProceduralStructureSprite = preload("res://src/rendering/procedural_structure_sprite.gd")
const ProceduralBuildingPieceSprite = preload("res://src/rendering/procedural_building_piece_sprite.gd")
const BuildingPiece = preload("res://src/gameplay/building_piece.gd")
const ProceduralShoreDistanceSprite = preload("res://src/rendering/procedural_shore_distance_sprite.gd")
const TerrainAtlasCache = preload("res://src/rendering/terrain_atlas_cache.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")
const PixelNoise = preload("res://src/rendering/pixel_noise.gd")
const IllustratedTerrainSprite = preload("res://src/rendering/illustrated_terrain_sprite.gd")

## How many WORLD UNITS one tile occupies. Every gameplay system is built on
## this -- player movement/collision, spawn placement, chunk streaming,
## creature/fish positioning, structure proximity -- and the player's own
## 12-unit body is proportioned against it. It is NOT an art resolution and
## must not change when art detail changes (see ART_TILE_SIZE): the
## art-resolution pass's first attempt bumped this to 64, which made every
## tile cover 4x the world area and was reported as "water squares are
## gigantic compared to the player".
const TILE_SIZE := 16

## How many PIXELS OF ART are painted per tile -- TILE_SIZE times the
## shared 4x detail factor, so a tile carries 16x the pixel detail of the
## original 1px-per-world-unit art (see docs/concept/art_resolution.md).
## Every generator's own SIZE constant is matched to this, and every atlas
## image/blit/region below is sized in these art pixels. Derived from
## ArtResolution rather than restated, so terrain and entity sprites can
## never drift to different detail densities.
const ART_TILE_SIZE := TILE_SIZE * ArtResolution.DETAIL_MULTIPLIER

## What a tile LAYER (the TileMapLayer nodes drawing these tiles -- see
## EarthChunkManager) must be scaled by so ART_TILE_SIZE pixels of art span
## exactly TILE_SIZE world units. This is the whole mechanism that keeps art
## resolution and world footprint independent: raise ART_TILE_SIZE for more
## detail, LAYER_SCALE shrinks to compensate, and the world is unchanged.
const LAYER_SCALE := float(TILE_SIZE) / float(ART_TILE_SIZE)

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
## Doubled from 6: base biome tiles cost only biomes x variants x frames,
## a small fraction of the blend-tile count that dominates atlas build
## time, so more ground variety is nearly free. With variant SELECTION
## also decorrelated (see variant_index_for_position) this is what stops
## the ground reading as a short repeating texture.
##
## Raised 12 -> 25, then settled at 9: the terrain art pipeline originally
## targeted a full 5x5/25-variant illustrated sheet per biome, but real
## generation only reliably held a square-cell grid at 3x3 (a 5x5 attempt
## came back as uneven tall strips -- see IllustratedTerrainSprite's own doc
## comment). Every LAND biome now has a real 3x3/9-variant sheet registered,
## so 9 lets every baked atlas slot map to a genuinely distinct illustrated
## tile with none wasted on duplicates a higher cap would have produced.
## Ocean (the one biome still procedural) still gets real per-position
## variety from 9 -- comfortably above the original test_variants_per_biome
## floor of 6. Still cheap for the same reason as the earlier bumps -- base
## tiles are a small fraction of atlas build cost next to the blend/corner
## tile families, which this constant does not affect (see BLEND_VARIANTS).
const VARIANTS_PER_BIOME := 9

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

## Bump whenever build_tile_set's pixel-generation logic changes (a new
## detail pass, a resolution change, a new biome...) -- TerrainAtlasCache
## keys its cached image to this string, so a stale cache from an older
## build is never silently reused (see docs/concept/
## art_resolution.md#boot-performance). Manual, not content-hashed: matches
## this codebase's existing "bump a version const" conventions elsewhere
## rather than adding hash-computation machinery for a one-developer project.
## Arbitrary fixed salt so variant selection is stable across runs while
## still being decorrelated between neighbouring tiles.
const _VARIANT_SALT := 90210

const ATLAS_VERSION := "art_resolution_v20_land_land_diagonal_corners"

## Overridable so tests never touch the real user:// cache (see
## TerrainAtlasCache) -- production code (EarthChunkManager) never sets
## these, so it always gets the real cache.
var atlas_cache_path := TerrainAtlasCache.CACHE_PATH
var atlas_version_path := TerrainAtlasCache.VERSION_PATH

var _terrain_sprite_generator := ProceduralTerrainSprite.new()
var _structure_sprite_generator := ProceduralStructureSprite.new()
var _building_piece_sprite_generator := ProceduralBuildingPieceSprite.new()
var _shore_distance_generator := ProceduralShoreDistanceSprite.new()
var _atlas_cache := TerrainAtlasCache.new()
var _illustrated_terrain = IllustratedTerrainSprite.new()


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
## furnace) and known building piece ids (see BuildingPiece.PIECE_IDS --
## floor/wall/door/window/roof x wood/stone) each get their own dedicated
## slot; EARTH_TILE_ID and any unrecognized id fall back to the single plain-
## earth slot (fail-safe default, matching this codebase's `.get(x, default)`
## convention -- never crash on an unknown tile_id).
func atlas_coords_for_modification(tile_id: String) -> Vector2i:
	if ProceduralStructureSprite.STRUCTURE_IDS.has(tile_id):
		return _grid_coords(_structure_linear(tile_id))
	if BuildingPiece.has_piece(tile_id):
		return _grid_coords(_building_piece_linear(tile_id))
	return _grid_coords(_earth_linear())


## Which of a biome's VARIANTS_PER_BIOME procedural tiles a given global tile
## position should use -- deterministic (the same tile always looks the same
## across sessions/reloads) but varies from position to position so the
## ground doesn't read as one repeating texture.
func variant_index_for_position(global_x: int, global_y: int) -> int:
	# PixelNoise, not Godot's string hash. Hashing adjacent coordinates
	# correlates, so neighbouring tiles kept drawing the SAME variant and the
	# ground broke into patches of repeated tile -- exactly the "tiled
	# repeating pattern" look, despite there being several variants
	# available. This is the sixth site of that clustering bug in this
	# project, after village house sizes, tree leaf angles, grass tuft
	# blades, the GPU blade field and the baked terrain blades.
	return PixelNoise.range_index(_VARIANT_SALT, global_x, global_y, VARIANTS_PER_BIOME)


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
		# Water is a special case, not just "lowest priority": land never
		# blends toward ocean at all, on EITHER side. The shoreline
		# transition belongs entirely to the GPU WaterFx overlay now (see
		# water_shader.gd) -- a land-side dithered fringe here would fight
		# the overlay's own shore-distance blending on the water side (the
		# reported "shoreline renders backwards" bug: two independent
		# transition treatments on opposite sides of the same border).
		if neighbor == "ocean" and biome_name != "ocean":
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


## Which of `biome_name`'s geometric tile CORNERS (see
## ProceduralTerrainSprite.CORNER_DIRECTIONS) should be carved toward a
## different biome -- {"partner": <biome>, "directions": Array of diagonal
## Vector2i toward it}, or an empty Dictionary if this cell has no corner
## case at all.
##
## Three corner shapes, each checked per diagonal direction (see
## docs/concept/terrain_biome_borders.md):
##   - CONVEX (this cell is ocean, land pokes into it on two perpendicular
##     cardinal sides -- a peninsula tip narrowing the water).
##   - CONCAVE (this cell is land, water pokes into it on two perpendicular
##     cardinal sides -- a bay/inlet tip narrowing the land).
##   - DIAGONAL-ONLY (this cell's own biome fills BOTH cardinal flanks --
##     no shared cardinal edge with anything -- but its actual DIAGONAL
##     neighbor, read from `diagonal_neighbor_biomes`, is a different LAND
##     biome: two land biomes meeting only at a shared tile corner, the
##     outer corner of a staircase-shaped biome boundary. Reported: a
##     grassland/forest corner rendering as a hard, unblended square.
##     Deliberately scoped to LAND/LAND only -- ocean stays out of this new
##     branch, kept separate from the already-much-revised water-corner
##     logic above.)
## A cell can qualify on MORE THAN ONE of its four corners at once -- a
## single-tile-wide spit/peninsula (land with water on three sides) has TWO
## simultaneous qualifying corners, and a lone one-tile pond/island has all
## FOUR. Measured directly against real generated chunks: of 3355 real cells
## with at least one qualifying corner, 859 qualified on more than one
## simultaneously (4522 total qualifying corner-instances). An earlier
## version of this function returned only the FIRST direction found and
## silently dropped the rest, which is exactly why some corners on a real
## coastline carved while others on the very same tile stayed hard right
## angles (reported: "still not giving every corner a border radius"). Now
## every qualifying direction is collected and grouped by partner biome, the
## same "most edges wins, ties broken by KNOWN_BIOMES order" dominance
## picked as dominant_blend_for already uses -- so a lone pond's four
## corners (nearly always the same partner) all round together, and a mixed
## spit only drops a direction if it genuinely disagrees on which biome it's
## carving toward.
## The two flanking neighbors no longer need to be the SAME biome, either:
## an ocean corner flanked by two DIFFERENT land biomes (e.g. grassland
## north, desert east -- routine on a real coastline where land-biome edges
## rarely line up with shore corners) now still carves, toward whichever
## neighbor wins BLEND_PRIORITY (deterministic tie-break, same convention as
## dominant_blend_for).
## The diagonal-only branch stays ONE-SIDED like dominant_blend_for's own
## cardinal fringe ("exactly ONE side of any border renders a transition
## tile"): it only carves toward a diagonal neighbor with a STRICTLY HIGHER
## BLEND_PRIORITY, so the higher-priority side's own corner (looking back at
## the same point from its own cell) never also carves -- the same point
## never gets carved from both sides at once. `diagonal_neighbor_biomes`
## defaults to an empty Dictionary so every existing caller that only passes
## cardinal neighbors keeps working unchanged. A water/land diagonal-only
## touch (e.g. the corner-diagonal land cells around an isolated one-tile
## pond) has this same underlying gap but is deliberately left unaddressed
## here too -- see docs/concept/terrain_biome_borders.md.
func corner_direction_for(
	biome_name: String, neighbor_biomes: Dictionary, diagonal_neighbor_biomes: Dictionary = {}
) -> Dictionary:
	var directions_by_partner := {}
	for direction in ProceduralTerrainSprite.CORNER_DIRECTIONS:
		var horizontal: String = neighbor_biomes.get(Vector2i(direction.x, 0), "")
		var vertical: String = neighbor_biomes.get(Vector2i(0, direction.y), "")
		var partner := ""
		if horizontal != "" and vertical != "" and horizontal != biome_name and vertical != biome_name:
			if horizontal == vertical:
				partner = horizontal
			elif biome_name == "ocean" and horizontal != "ocean" and vertical != "ocean":
				# Mixed land biomes flanking an ocean corner: still a real
				# corner, just carved toward whichever neighbor dominates.
				partner = _dominant_corner_partner(horizontal, vertical)
		elif horizontal == biome_name and vertical == biome_name and biome_name != "ocean":
			# No shared cardinal edge with anything -- only a genuine
			# diagonal-only touch (see this function's own doc comment)
			# can still qualify this corner.
			var diagonal: String = diagonal_neighbor_biomes.get(direction, "")
			if (
				diagonal != "" and diagonal != biome_name and diagonal != "ocean"
				and BLEND_PRIORITY.get(diagonal, 0) > BLEND_PRIORITY.get(biome_name, 0)
			):
				partner = diagonal
		if partner == "":
			continue
		if not directions_by_partner.has(partner):
			directions_by_partner[partner] = []
		directions_by_partner[partner].append(direction)

	if directions_by_partner.is_empty():
		return {}

	var best_partner := ""
	var best_directions: Array = []
	for candidate in directions_by_partner:
		var candidate_directions: Array = directions_by_partner[candidate]
		if _is_more_dominant(candidate, candidate_directions, best_partner, best_directions):
			best_partner = candidate
			best_directions = candidate_directions
	return {"partner": best_partner, "directions": best_directions}


## Deterministic tie-break for a mixed-biome ocean corner (see
## corner_direction_for): higher BLEND_PRIORITY wins, ties broken toward the
## earlier KNOWN_BIOMES entry -- the same convention _is_more_dominant uses
## for land/land blending.
func _dominant_corner_partner(a: String, b: String) -> String:
	var priority_a: int = BLEND_PRIORITY.get(a, 0)
	var priority_b: int = BLEND_PRIORITY.get(b, 0)
	if priority_a != priority_b:
		return a if priority_a > priority_b else b
	return a if BiomeClassifier.KNOWN_BIOMES.find(a) < BiomeClassifier.KNOWN_BIOMES.find(b) else b


## Returns the atlas coordinate for one corner-carve tile (see
## corner_direction_for/ProceduralTerrainSprite.generate_corner_image):
## `own_biome` is the cell's own biome (whichever tile is being carved --
## ocean for a convex corner, a land biome for a concave one), `other_biome`
## is what gets carved into its corner geometry, `corner_directions` is every
## diagonal corner being carved at once (a cell can qualify on more than one
## simultaneously -- see corner_direction_for), and `variant` folds into
## BLEND_VARIANTS the same way atlas_coords_for_directional_blend does.
## Order within `corner_directions` doesn't matter -- reduced to a bitmask,
## same convention as atlas_coords_for_directional_blend's `directions`.
func atlas_coords_for_corner(own_biome: String, other_biome: String, corner_directions: Array, variant: int = 0) -> Vector2i:
	return _grid_coords(_corner_linear(own_biome, other_biome, corner_directions, variant))


## Converts a set of diagonal corner directions into a bitmask over
## ProceduralTerrainSprite.CORNER_DIRECTIONS -- the corner-carve equivalent
## of _direction_mask.
func _corner_direction_mask(directions: Array) -> int:
	var mask := 0
	for direction in directions:
		mask |= 1 << ProceduralTerrainSprite.CORNER_DIRECTIONS.find(direction)
	return mask


## The diagonal corner directions set in a bitmask, in CORNER_DIRECTIONS
## order -- the corner-carve equivalent of _directions_from_mask.
func _corner_directions_from_mask(mask: int) -> Array:
	var directions := []
	for bit in ProceduralTerrainSprite.CORNER_DIRECTIONS.size():
		if mask & (1 << bit):
			directions.append(ProceduralTerrainSprite.CORNER_DIRECTIONS[bit])
	return directions


## Every non-empty subset of a tile's 4 diagonal corners gets its own carved
## tile, mirroring DIRECTION_MASK_COUNT's role for the blend system -- a cell
## can qualify on more than one corner at once (see corner_direction_for),
## so a single fixed direction slot per tile isn't enough.
const CORNER_MASK_COUNT := (1 << 4) - 1


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


## Linear atlas index where the building-piece tiles begin (right after
## earth and structures).
func _building_piece_base_linear() -> int:
	return _structure_base_linear() + ProceduralStructureSprite.STRUCTURE_IDS.size()


## Linear atlas index of one known building piece's tile (see
## BuildingPiece.PIECE_IDS), in PIECE_IDS order. Callers must check
## BuildingPiece.has_piece(tile_id) first, mirroring _structure_linear.
func _building_piece_linear(piece_id: String) -> int:
	return _building_piece_base_linear() + BuildingPiece.PIECE_IDS.find(piece_id)


## Linear atlas index where the blend tiles begin (right after earth,
## structure, and building-piece tiles).
func _blend_base_linear() -> int:
	return _building_piece_base_linear() + BuildingPiece.PIECE_IDS.size()


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


## How many atlas cells one "corner family" (every land-biome ordinal slot,
## including ocean's own never-referenced one, x every non-empty subset of
## the 4 diagonal corners (CORNER_MASK_COUNT) x BLEND_VARIANTS) reserves.
## Two such families are sized by this function (see _corner_linear):
## ocean-owning (convex corners) and land-owning (concave corners) -- both
## always pair a land biome with ocean specifically. A THIRD, differently-
## sized family (land/land, pair-indexed rather than single-biome-indexed --
## see _land_land_corner_family_size) covers every corner between two
## DIFFERENT land biomes instead. A cell can qualify on more than one corner
## simultaneously (see corner_direction_for), so every mask -- not just a
## single direction slot -- needs its own tile, mirroring _TILES_PER_PAIR's
## role for the blend system.
func _corner_family_size() -> int:
	var biome_count := BiomeClassifier.KNOWN_BIOMES.size()
	return biome_count * CORNER_MASK_COUNT * BLEND_VARIANTS


## Linear atlas index where corner-carve tiles begin (right after all blend
## tiles) -- the ocean-owning family (convex corners: an ocean cell carved
## toward a land neighbor) starts here.
func _corner_base_linear() -> int:
	var biome_count := BiomeClassifier.KNOWN_BIOMES.size()
	return _blend_base_linear() + biome_count * (biome_count - 1) * _TILES_PER_PAIR


## Linear atlas index where the land-owning corner family begins (concave
## corners: a land cell carved toward ocean) -- right after the whole
## ocean-owning family.
func _land_corner_base_linear() -> int:
	return _corner_base_linear() + _corner_family_size()


## How many of the 6 land biomes exist (KNOWN_BIOMES minus ocean, which is
## always index 0) -- the land/land corner family's own pair space is scoped
## to these, since land/ocean corners keep their existing, unchanged
## addressing above.
func _land_biome_count() -> int:
	return BiomeClassifier.KNOWN_BIOMES.size() - 1


## Linear atlas index where the land/land corner family begins -- right
## after the whole land-owning-toward-ocean family. The THIRD and last
## corner-carve family (see _corner_linear): unlike the other two, which
## always pair a land biome with ocean, this one carves toward another LAND
## biome entirely -- the corner shape a staircase-shaped biome boundary
## makes where two land biomes touch only at a shared tile corner (no shared
## cardinal edge -- see corner_direction_for's own doc comment), or a real
## right-angle corner between two land biomes.
func _land_land_corner_base_linear() -> int:
	return _land_corner_base_linear() + _corner_family_size()


## Every ordered (own,other) land pair -- own != other, own's own ordinal
## slot against itself skipped, same "n * (n-1)" shape _TILES_PER_PAIR's own
## family uses for the blend system -- x CORNER_MASK_COUNT x BLEND_VARIANTS.
## Some slots go permanently unused: corner_direction_for's own diagonal-only
## branch is one-sided (only the lower-BLEND_PRIORITY side ever carves), so
## the "wrong direction" of every pair is never actually requested through
## paint(). Reserving the full pair space anyway -- rather than a fragile,
## priority-restricted half-sized scheme -- mirrors this function's own
## ocean-corner siblings, which already accept ocean's own unused ordinal
## slot as cheap, deliberate waste; corner_direction_for's existing
## right-angle branch (unlike the new diagonal-only one) has no priority
## gate at all and is unit-tested with hand-built dictionaries that bypass
## paint()'s call-order gating, so a half-sized scheme would leave undefined/
## colliding behavior for a synthetic call in the "wrong" priority direction.
func _land_land_corner_family_size() -> int:
	var land_count := _land_biome_count()
	return land_count * (land_count - 1) * CORNER_MASK_COUNT * BLEND_VARIANTS


## Linear atlas index of one land/land corner-carve tile. Ordered pair
## (own_biome, other_biome), both real land biomes -- mirrors _blend_linear's
## own near/far pair-ordinal formula exactly, scoped to the 6 land biomes
## (skip ocean's own KNOWN_BIOMES index 0 by subtracting 1 from each
## ordinal).
func _land_land_corner_linear(own_biome: String, other_biome: String, mask: int, variant: int) -> int:
	var land_count := _land_biome_count()
	var own_ordinal := BiomeClassifier.KNOWN_BIOMES.find(own_biome) - 1
	var other_ordinal := BiomeClassifier.KNOWN_BIOMES.find(other_biome) - 1
	var other_slot := other_ordinal if other_ordinal < own_ordinal else other_ordinal - 1
	var pair_ordinal := own_ordinal * (land_count - 1) + other_slot
	return (
		_land_land_corner_base_linear()
		+ pair_ordinal * CORNER_MASK_COUNT * BLEND_VARIANTS
		+ (mask - 1) * BLEND_VARIANTS + (variant % BLEND_VARIANTS)
	)


## Linear atlas index of one corner-carve tile. Routes to whichever of the
## THREE corner families actually owns the tile (see corner_direction_for):
## ocean-owning (own_biome == "ocean", indexed by other_biome's ordinal),
## land-owning-toward-ocean (own_biome != "ocean" and other_biome == "ocean",
## indexed by own_biome's ordinal), or land/land (neither side is "ocean",
## indexed by the ordered (own_biome,other_biome) pair -- see
## _land_land_corner_linear). Ocean's own ordinal slot in the first two
## families is never referenced (corner_direction_for never returns a
## same-biome partner) -- a small, cheap amount of unused atlas space rather
## than a fragile re-indexing scheme.
func _corner_linear(own_biome: String, other_biome: String, corner_directions: Array, variant: int) -> int:
	var mask := _corner_direction_mask(corner_directions)
	if own_biome != "ocean" and other_biome != "ocean":
		return _land_land_corner_linear(own_biome, other_biome, mask, variant)
	var base := _corner_base_linear()
	var biome_index := BiomeClassifier.KNOWN_BIOMES.find(other_biome)
	if own_biome != "ocean":
		base = _land_corner_base_linear()
		biome_index = BiomeClassifier.KNOWN_BIOMES.find(own_biome)
	return (
		base
		+ biome_index * CORNER_MASK_COUNT * BLEND_VARIANTS
		+ (mask - 1) * BLEND_VARIANTS + (variant % BLEND_VARIANTS)
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


## Blits one generated tile image into the shared atlas image at the grid
## cell for `linear_index`, scaling it down first if the generator authored
## it larger than ART_TILE_SIZE.
##
## That rescale is load-bearing, not a nicety. This used to blit a
## Rect2i(0, 0, ART_TILE_SIZE, ART_TILE_SIZE) SOURCE region, which silently
## CROPPED every oversized tile to its top-left quadrant instead of scaling
## it: ProceduralTerrainSprite authors at its own SIZE (64), while
## ART_TILE_SIZE is TILE_SIZE * ArtResolution.DETAIL_MULTIPLIER and so
## follows whatever that shared multiplier currently is (32 at a 2x factor).
## Three of any corner-carved tile's four rounded corners were thrown away
## before ever reaching the atlas -- which is exactly why an isolated
## one-tile pond still rendered as a hard square in game no matter how
## correct the carve logic was (reported: isolated ponds "rendering as
## perfect hard squares"), and it quietly degraded every other terrain tile
## too (blend gradients, grass blades, moss all showing only their top-left
## quarter). Nearest-neighbour, never bilinear -- this is pixel art.
## Pinned by test_baked_tiles_represent_the_whole_generated_tile_not_a_
## cropped_corner.
func _blit_tile(atlas_image: Image, tile_image: Image, linear_index: int) -> void:
	var coords := _grid_coords(linear_index)
	var source := tile_image
	if source.get_width() != ART_TILE_SIZE or source.get_height() != ART_TILE_SIZE:
		source = Image.create_from_data(
			tile_image.get_width(), tile_image.get_height(), false,
			tile_image.get_format(), tile_image.get_data()
		)
		source.resize(ART_TILE_SIZE, ART_TILE_SIZE, Image.INTERPOLATE_NEAREST)
	atlas_image.blit_rect(
		source, Rect2i(Vector2i.ZERO, Vector2i(ART_TILE_SIZE, ART_TILE_SIZE)), coords * ART_TILE_SIZE
	)


## The expensive part of build_tile_set: paints every biome/structure/blend
## tile's real pixels into one shared atlas Image. Fully deterministic (same
## inputs always produce the same pixels), so it's the part cached to disk
## (see ATLAS_VERSION/atlas_cache_path and build_tile_set's cache check) --
## ~13.5s measured at the 4x resolution (docs/concept/
## art_resolution.md#boot-performance) for thousands of tiles at TILE_SIZE^2
## pixels each, far too slow to pay on every boot.
## One base biome tile's pixels for (biome_name, variant, frame). Illustrated
## art (see IllustratedTerrainSprite) wins when this biome has a real sheet
## registered; otherwise this is exactly the per-(biome, variant, frame)
## procedural image it always was. The same has_X()-gated fallback seam
## StoneRenderer._texture_for uses for illustrated stone art.
##
## An illustrated tile has no real animation of its own (a single hand/AI-
## illustrated frame, not FRAME_COUNT seamlessly looping ones) -- `frame` is
## ignored and the SAME illustrated image is reused for every one of a
## biome/variant's animation cells, matching generate_frame_image's own
## "static biomes return identical frames" convention rather than needing a
## separate no-animation code path.
func _biome_frame_image(biome_name: String, variant: int, frame: int) -> Image:
	if _illustrated_terrain.has_variants(biome_name):
		return _illustrated_terrain.frame_for(biome_name, variant)
	return _terrain_sprite_generator.generate_frame_image(biome_name, variant, frame)


## A directional-blend border between near_biome/far_biome, dithering their
## REAL images together (illustrated where registered, procedural
## otherwise -- see _biome_frame_image) via ProceduralTerrainSprite's dither
## mask, instead of a flat-color-plus-speckle blend synthesized from a bare
## biome name (reported: illustrated ground next to a flat/procedural-
## looking border read as visibly inconsistent). Every land biome is
## illustrated today, so a land-land blend composites two same-size (32px)
## illustrated images directly; only ocean (still procedural, 64px) would
## ever mismatch, and directional blends never involve it (land never
## blends toward/from ocean -- see dominant_blend_for's own doc comment) --
## the size-normalizing seam exists for _corner_image below, which does.
func _blend_image(near_biome: String, far_biome: String, directions: Array, variant: int) -> Image:
	var near_image := _normalized_for_compositing(_biome_frame_image(near_biome, variant, 0))
	var far_image := _normalized_for_compositing(_biome_frame_image(far_biome, variant, 0))
	return _terrain_sprite_generator.generate_multi_directional_blend_image_from(near_image, far_image, directions)


## Corner-carve counterpart of _blend_image -- see its own doc comment.
## Generic over any biome pair (land/ocean OR land/land -- see
## corner_direction_for): _normalized_for_compositing is what keeps a size
## mismatch (illustrated land at 32px vs still-procedural ocean at
## ProceduralTerrainSprite.SIZE, 64px) from crashing or silently cropping;
## for a land/land pair both sides are already the same illustrated size, so
## it's a no-op there.
func _corner_image(own_biome: String, other_biome: String, corner_directions: Array, variant: int) -> Image:
	var own_image := _normalized_for_compositing(_biome_frame_image(own_biome, variant, 0))
	var other_image := _normalized_for_compositing(_biome_frame_image(other_biome, variant, 0))
	return _terrain_sprite_generator.generate_corner_image_from(own_image, other_image, corner_directions)


## Resizes `image` to ART_TILE_SIZE if it isn't already that size --
## nearest-neighbour when upscaling (keeps pixel art crisp, matches
## _blit_tile's own convention for a generator smaller than the atlas
## slot), Lanczos when downscaling. Nearest-neighbour aliases fine
## per-pixel detail into visible noise when shrinking -- the exact bug
## IllustratedTerrainSprite.CANVAS_SIZE's own doc comment describes fixing
## for base tiles; compositing at the real final size here (rather than
## leaving _blit_tile to rescale the COMPOSITE afterward) means that lesson
## carries over to blend/corner tiles instead of quietly regressing on them.
func _normalized_for_compositing(image: Image) -> Image:
	if image.get_width() == ART_TILE_SIZE and image.get_height() == ART_TILE_SIZE:
		return image
	var resized := Image.create_from_data(
		image.get_width(), image.get_height(), false, image.get_format(), image.get_data()
	)
	var interpolation := (
		Image.INTERPOLATE_LANCZOS
		if image.get_width() > ART_TILE_SIZE or image.get_height() > ART_TILE_SIZE
		else Image.INTERPOLATE_NEAREST
	)
	resized.resize(ART_TILE_SIZE, ART_TILE_SIZE, interpolation)
	return resized


func _build_atlas_pixels(biome_count: int, rows: int) -> Image:
	var image := Image.create(ATLAS_COLUMNS * ART_TILE_SIZE, rows * ART_TILE_SIZE, false, Image.FORMAT_RGBA8)

	# Base biome tiles: FRAME_COUNT animation frames each, blitted into
	# consecutive cells (the block never wraps a row -- see FRAME_COUNT's doc
	# comment on the ATLAS_COLUMNS alignment invariant).
	for i in biome_count:
		var biome_name: String = BiomeClassifier.KNOWN_BIOMES[i]
		for variant in VARIANTS_PER_BIOME:
			var block_start := (i * VARIANTS_PER_BIOME + variant) * FRAME_COUNT
			for frame in FRAME_COUNT:
				var frame_image := _biome_frame_image(biome_name, variant, frame)
				_blit_tile(image, frame_image, block_start + frame)

	var earth_image := Image.create(ART_TILE_SIZE, ART_TILE_SIZE, false, Image.FORMAT_RGBA8)
	earth_image.fill(EARTH_COLOR)
	_blit_tile(image, earth_image, _earth_linear())

	for structure_id in ProceduralStructureSprite.STRUCTURE_IDS:
		var structure_image := _structure_sprite_generator.generate_image(structure_id)
		_blit_tile(image, structure_image, _structure_linear(structure_id))

	for piece_id in BuildingPiece.PIECE_IDS:
		var piece_image := _building_piece_sprite_generator.generate_image(piece_id)
		_blit_tile(image, piece_image, _building_piece_linear(piece_id))

	for near_index in biome_count:
		for far_index in biome_count:
			if far_index == near_index:
				continue
			var near_biome: String = BiomeClassifier.KNOWN_BIOMES[near_index]
			var far_biome: String = BiomeClassifier.KNOWN_BIOMES[far_index]
			for mask in range(1, DIRECTION_MASK_COUNT + 1):
				var directions := _directions_from_mask(mask)
				for variant in BLEND_VARIANTS:
					var blend_image := _blend_image(near_biome, far_biome, directions, variant)
					_blit_tile(image, blend_image, _blend_linear(near_biome, far_biome, mask, variant))

		# Corner-carve tiles (see corner_direction_for), the first two of
		# THREE families for the two real shoreline corner shapes:
		#   - ocean-owning (CONVEX corner: an ocean cell carved toward a land
		#     neighbor poking into it).
		#   - land-owning (CONCAVE corner: a land cell carved toward the
		#     ocean poking into it) -- the case a hard square notch was
		#     still showing up for before this pass.
		# near_index == ocean's own index is skipped for both -- ocean never
		# carves toward/from itself, and corner_direction_for never asks
		# for it.
		var corner_biome: String = BiomeClassifier.KNOWN_BIOMES[near_index]
		if corner_biome != "ocean":
			for corner_mask in range(1, CORNER_MASK_COUNT + 1):
				var corner_directions := _corner_directions_from_mask(corner_mask)
				for variant in BLEND_VARIANTS:
					var convex_image := _corner_image("ocean", corner_biome, corner_directions, variant)
					_blit_tile(image, convex_image, _corner_linear("ocean", corner_biome, corner_directions, variant))

					var concave_image := _corner_image(corner_biome, "ocean", corner_directions, variant)
					_blit_tile(image, concave_image, _corner_linear(corner_biome, "ocean", corner_directions, variant))

	# The THIRD corner family: land/land (see corner_direction_for's own doc
	# comment) -- two different LAND biomes meeting only at a shared tile
	# corner, or a real right-angle corner between two land biomes (both
	# reachable before this pass; the right-angle one used to silently bake
	# OCEAN's texture instead, since _corner_linear's land-owning branch used
	# to ignore other_biome entirely). Every ordered pair of DISTINCT land
	# biomes gets its own reserved slot, same nested shape as the blend loop
	# above.
	for own_index in biome_count:
		var own_land_biome: String = BiomeClassifier.KNOWN_BIOMES[own_index]
		if own_land_biome == "ocean":
			continue
		for other_index in biome_count:
			var other_land_biome: String = BiomeClassifier.KNOWN_BIOMES[other_index]
			if other_land_biome == "ocean" or other_land_biome == own_land_biome:
				continue
			for corner_mask in range(1, CORNER_MASK_COUNT + 1):
				var corner_directions := _corner_directions_from_mask(corner_mask)
				for variant in BLEND_VARIANTS:
					var corner_image := _corner_image(own_land_biome, other_land_biome, corner_directions, variant)
					_blit_tile(
						image, corner_image,
						_land_land_corner_linear(own_land_biome, other_land_biome, corner_mask, variant)
					)

	return image


## Builds a grid-laid-out TileSet: VARIANTS_PER_BIOME procedural tiles per known
## biome, one player-placeable "earth" tile, one dedicated tile per known
## placed structure (ProceduralStructureSprite.STRUCTURE_IDS -- campfire,
## furnace), then a directional blend tile for every ordered pair of distinct
## biomes x every non-empty cardinal-direction subset (DIRECTION_MASK_COUNT
## masks) x VARIANTS_PER_BIOME. The atlas image itself is cached to disk
## after the first build (see ATLAS_VERSION/_build_atlas_pixels) -- only the
## TileSet/TileSetAtlasSource metadata below (cheap, no pixel work) runs on
## every call regardless of cache state.
func build_tile_set() -> TileSet:
	var biome_count := BiomeClassifier.KNOWN_BIOMES.size()
	var total_cells := _land_land_corner_base_linear() + _land_land_corner_family_size()
	var rows := int(ceil(float(total_cells) / ATLAS_COLUMNS))

	var image: Image = null
	if _atlas_cache.has_valid_cache(ATLAS_VERSION, atlas_cache_path, atlas_version_path):
		image = _atlas_cache.load_image(atlas_cache_path)
	if image == null:
		image = _build_atlas_pixels(biome_count, rows)
		_atlas_cache.save(image, ATLAS_VERSION, atlas_cache_path, atlas_version_path)

	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(image)
	source.texture_region_size = Vector2i(ART_TILE_SIZE, ART_TILE_SIZE)

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

	# Earth, structures, building pieces, and blend tiles stay static
	# single-cell tiles.
	source.create_tile(_grid_coords(_earth_linear()))
	for structure_id in ProceduralStructureSprite.STRUCTURE_IDS:
		source.create_tile(_grid_coords(_structure_linear(structure_id)))
	for piece_id in BuildingPiece.PIECE_IDS:
		source.create_tile(_grid_coords(_building_piece_linear(piece_id)))
	for linear_index in range(_blend_base_linear(), total_cells):
		source.create_tile(_grid_coords(linear_index))

	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(ART_TILE_SIZE, ART_TILE_SIZE)
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
				if not blend.is_empty():
					atlas_coords = atlas_coords_for_directional_blend(
						biome_name, blend.partner, blend.directions, variant
					)
				else:
					# Water/land is never dither-blended (see above), but a
					# cell whose tile-grid corner is a real right-angle
					# (land on BOTH cardinal sides of one diagonal, from
					# either the water side OR the land side) OR a genuine
					# diagonal-only land/land touch (see corner_direction_for)
					# still gets an actual carved-corner tile on this same
					# opaque base layer, instead of a hard square notch.
					var diagonal_neighbors := _diagonal_neighbor_biomes(chunk, x, y, origin, global_biome_lookup)
					var corner := corner_direction_for(biome_name, neighbors, diagonal_neighbors)
					if corner.is_empty():
						atlas_coords = atlas_coords_for_biome(biome_name, variant)
					else:
						atlas_coords = atlas_coords_for_corner(biome_name, corner.partner, corner.directions, variant)
			tile_map_layer.set_cell(global, 0, atlas_coords)


## Paints a chunk's ROOF layer -- a separate TileMapLayer from `paint()`'s
## floor/wall layer, since a roof piece shares its cell with the floor
## beneath it (see Chunk.roof_modifications). Only touches cells that
## actually have a roof modification; everything else on this layer is left
## alone.
##
## `hidden_cells` (local cell -> true) is what makes roof hide-on-enter
## possible: a cell listed there is ERASED instead of painted, so the player
## can see inside while standing under it, and calling this again with a
## smaller/empty `hidden_cells` repaints whatever is no longer hidden. The
## caller (EarthChunkManager) is expected to pass the current room's cells
## while the player is indoors, and {} otherwise.
func paint_roofs(
	tile_map_layer: TileMapLayer, chunk: Chunk, origin: Vector2i = Vector2i.ZERO, hidden_cells: Dictionary = {}
) -> void:
	for local in chunk.roof_modifications:
		var global: Vector2i = origin + local
		if hidden_cells.has(local):
			tile_map_layer.erase_cell(global)
		else:
			tile_map_layer.set_cell(global, 0, atlas_coords_for_modification(chunk.roof_modifications[local]))


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


## The DIAGONAL neighbor biomes of a local chunk cell, keyed by direction --
## the corner-carve counterpart of _neighbor_biomes, used only for the
## diagonal-only land/land corner case (see corner_direction_for's own doc
## comment). Same in/out-of-chunk resolution as _neighbor_biomes, just over
## ProceduralTerrainSprite.CORNER_DIRECTIONS (the 4 diagonals) instead of
## _DIRECTIONS (the 4 cardinals).
func _diagonal_neighbor_biomes(
	chunk: Chunk, x: int, y: int, origin: Vector2i, global_biome_lookup: Callable
) -> Dictionary:
	var neighbors := {}
	for direction in ProceduralTerrainSprite.CORNER_DIRECTIONS:
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


## How far (in tiles) shore influence reaches into open water. A single
## tile's own local gradient only spans 16px -- too thin a band for the
## water shader's shore-reflection wave to be visible as real interference
## at screen scale (reported: "waves don't produce interference"). Rings
## 1..RING_MAX-1 extend that influence outward as flat per-ring tiles (see
## ProceduralShoreDistanceSprite.generate_ring_image); ring_distance >=
## RING_MAX reads as open water. 4 tiles (64px) gives the wave pattern real
## room to read as bands spreading from the coast without making every small
## pond's entire surface "shore".
const RING_MAX := 4


## The atlas coordinate of the WaterFx overlay tile for an ocean cell:
## `ring_distance` tiles from the nearest land (0 == touches land directly,
## using its own cardinal `land_directions` for a precise per-pixel edge
## gradient; 1..RING_MAX-1 == a flat per-ring tile; >= RING_MAX == open
## water). `land_directions` only matters at ring_distance 0 -- pass [] for
## ring_distance >= 1. Order-independent at ring 0 (reduced to a mask,
## matching atlas_coords_for_directional_blend's convention).
func atlas_coords_for_water_overlay(land_directions: Array, ring_distance: int = 0) -> Vector2i:
	if ring_distance >= RING_MAX:
		return Vector2i(0, 0)
	if ring_distance == 0:
		if land_directions.is_empty():
			return Vector2i(0, 0)
		return Vector2i(_direction_mask(land_directions), 0)
	return Vector2i(DIRECTION_MASK_COUNT + ring_distance, 0)


## A small, separate TileSet for the GPU water overlay layer (see
## EarthChunkManager.set_water_layer): one flat "deep water" tile, one per
## cardinal land-direction mask at ring 0 (DIRECTION_MASK_COUNT = 15,
## touching-land precision), and one flat tile per ring 1..RING_MAX-1 -- all
## holding real shore-distance DATA (see ProceduralShoreDistanceSprite)
## rather than art. water_shader.gd samples it as a texture channel to blend
## and animate everything continuously on the GPU. No animation-frame
## bookkeeping needed here at all: unlike the old baked shore/rain tiles,
## every bit of motion (waves, shore reflection, raindrop ripples) is
## computed in the shader from TIME and world position, not by swapping tile
## frames.
func build_water_overlay_tile_set() -> TileSet:
	var total := 1 + DIRECTION_MASK_COUNT + (RING_MAX - 1)
	var image := Image.create(total * ART_TILE_SIZE, ART_TILE_SIZE, false, Image.FORMAT_RGBA8)
	image.blit_rect(
		_shore_distance_generator.generate_deep_water_image(),
		Rect2i(Vector2i.ZERO, Vector2i(ART_TILE_SIZE, ART_TILE_SIZE)), Vector2i.ZERO
	)
	for mask in range(1, DIRECTION_MASK_COUNT + 1):
		var land_directions := _directions_from_mask(mask)
		var distance_image := _shore_distance_generator.generate_image(land_directions)
		image.blit_rect(
			distance_image, Rect2i(Vector2i.ZERO, Vector2i(ART_TILE_SIZE, ART_TILE_SIZE)), Vector2i(mask * ART_TILE_SIZE, 0)
		)
	for ring in range(1, RING_MAX):
		var ring_image := _shore_distance_generator.generate_ring_image(ring, RING_MAX)
		image.blit_rect(
			ring_image, Rect2i(Vector2i.ZERO, Vector2i(ART_TILE_SIZE, ART_TILE_SIZE)),
			Vector2i((DIRECTION_MASK_COUNT + ring) * ART_TILE_SIZE, 0)
		)

	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(image)
	source.texture_region_size = Vector2i(ART_TILE_SIZE, ART_TILE_SIZE)
	for i in total:
		source.create_tile(Vector2i(i, 0))

	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(ART_TILE_SIZE, ART_TILE_SIZE)
	tile_set.add_source(source, 0)
	return tile_set
