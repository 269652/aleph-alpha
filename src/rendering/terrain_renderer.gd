extends RefCounted

const BiomeClassifier = preload("res://src/world/biome_classifier.gd")
const Chunk = preload("res://src/world/chunk.gd")
const ProceduralTerrainSprite = preload("res://src/rendering/procedural_terrain_sprite.gd")
const ProceduralStructureSprite = preload("res://src/rendering/procedural_structure_sprite.gd")
const ProceduralBuildingPieceSprite = preload("res://src/rendering/procedural_building_piece_sprite.gd")
const BuildingPiece = preload("res://src/gameplay/building_piece.gd")
const RoofShape = preload("res://src/rendering/roof_shape.gd")
const ProceduralShoreDistanceSprite = preload("res://src/rendering/procedural_shore_distance_sprite.gd")
const TerrainAtlasCache = preload("res://src/rendering/terrain_atlas_cache.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")
const PixelNoise = preload("res://src/rendering/pixel_noise.gd")
const IllustratedTerrainSprite = preload("res://src/rendering/illustrated_terrain_sprite.gd")
const ProceduralHillshadeSprite = preload("res://src/rendering/procedural_hillshade_sprite.gd")
const ProceduralRiverFlowSprite = preload("res://src/rendering/procedural_river_flow_sprite.gd")

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
## startup (a one-time cost -- TerrainAtlasCache keys the whole baked atlas
## to ATLAS_VERSION, so this only runs again when that bumps). Raised from
## 3 to match VARIANTS_PER_BIOME-adjacent variety once the curved-boundary
## wobble (see ProceduralTerrainSprite.blend_edge_wobble) gave each variant
## a genuinely different shape to show, not just re-speckled pixels around
## one identical straight line -- with only 3 shapes, a long biome border
## would still visibly repeat every third tile.
## atlas_coords_for_directional_blend folds the caller's 0..VARIANTS_PER_BIOME
## variant into this range, so callers don't care about the difference.
const BLEND_VARIANTS := 7

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

const ATLAS_VERSION := "art_resolution_v23_pitched_roof_variants"

## Overridable so tests never touch the real user:// cache (see
## TerrainAtlasCache) -- production code (EarthChunkManager) never sets
## these, so it always gets the real cache.
var atlas_cache_path := TerrainAtlasCache.CACHE_PATH
var atlas_version_path := TerrainAtlasCache.VERSION_PATH

var _terrain_sprite_generator := ProceduralTerrainSprite.new()
var _structure_sprite_generator := ProceduralStructureSprite.new()
var _building_piece_sprite_generator := ProceduralBuildingPieceSprite.new()
var _shore_distance_generator := ProceduralShoreDistanceSprite.new()
var _hillshade_generator := ProceduralHillshadeSprite.new()
var _river_flow_generator := ProceduralRiverFlowSprite.new()
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


## Returns the atlas coordinate for an earth-modification blend tile (see
## earth_dominant_blend_for/paint()'s modifications branch): neighbor_biome
## is the real land biome this earth cell is dithering toward, `directions`
## is every cardinal direction that neighbor lies in.
func atlas_coords_for_earth_blend(neighbor_biome: String, directions: Array, variant_index: int = 0) -> Vector2i:
	var mask := _direction_mask(directions)
	return _grid_coords(_earth_blend_linear(neighbor_biome, mask, variant_index))


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


## Earth-modification counterpart of dominant_blend_for (see paint()'s
## modifications branch) -- the fifth distinct root cause behind a report of
## "grass to dirt path reads as a hard edge, and the corner where they meet
## is a hard square": paint()'s modifications branch short-circuited straight
## to the single flat EARTH_COLOR tile before ever consulting neighbor
## biomes, so a built or PathScarring-worn earth cell (see
## src/world/path_scarring.gd) never got ANY border treatment at all,
## regardless of what real ground surrounded it -- not a repeat of any of
## the four prior corner-blend rounds above, which were all real-biome-pair
## logic and never touched the separate modification-tile system.
##
## Unlike dominant_blend_for, there is no "same biome, stay pure" skip and no
## priority gate: earth has no real biome identity of its own to compare
## against, so it always concedes to whatever real, unmodified ground
## borders it (see _neighbor_biomes' exclude_modified_neighbors param, which
## keeps two adjacent earth cells -- a multi-tile worn path or built floor --
## from dithering a seam against each other's pre-modification biome). Ocean
## is skipped, mirroring dominant_blend_for's own "land never blends toward
## ocean" rule -- the shoreline transition stays the GPU WaterFx overlay's
## job alone. Because every differing direction qualifies unconditionally
## (no priority filtering to exclude a two-perpendicular-sides case the way
## a corner-carve family exists to catch elsewhere), a shared corner between
## two active directions is already handled by the SAME directional-blend
## mask (generate_multi_directional_blend_image_from dithers a shared corner
## between active directions on its own -- see that function's own doc
## comment) -- no separate earth corner-carve family is needed or reachable.
func earth_dominant_blend_for(neighbor_biomes: Dictionary) -> Dictionary:
	var directions_by_biome := {}
	for direction in neighbor_biomes:
		var neighbor: String = neighbor_biomes[direction]
		if neighbor == "" or neighbor == "ocean":
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


## Which of `biome_name`'s geometric tile CORNERS (see
## ProceduralTerrainSprite.CORNER_DIRECTIONS) should be carved toward a
## different biome -- {"partner": <biome>, "directions": Array of diagonal
## Vector2i toward it}, or an empty Dictionary if this cell has no corner
## case at all.
##
## Covers every real corner shape an irregular biome map actually produces,
## not just a clean rectangle's -- three families total (see
## docs/concept/terrain_borders.md's "Diagonal corners" section for the full
## picture; atlas_coords_for_corner/_corner_linear route each to its own
## atlas cells):
##   - CONVEX (this cell is ocean, land pokes into it on two perpendicular
##     cardinal sides -- a peninsula tip narrowing the water).
##   - CONCAVE (this cell is land, water pokes into it on two perpendicular
##     cardinal sides -- a bay/inlet tip narrowing the land).
##   - MIXED-PARTNER (this cell is flanked by two DIFFERENT other biomes on
##     its two perpendicular cardinal sides -- e.g. grassland north, desert
##     east, routine on a real coastline or biome map where one biome's own
##     borders rarely line up with another's -- carved toward whichever
##     neighbor wins BLEND_PRIORITY, deterministic tie-break, same
##     convention as dominant_blend_for. Used to be gated to
##     `biome_name == "ocean"` only, leaving every land/land three-biome
##     corner an unblended hard corner; generalized to every biome_name,
##     since the underlying dominance rule never actually depended on ocean
##     being involved.)
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
			else:
				# horizontal != vertical, and neither equals biome_name
				# (checked above) -- a real corner with two DIFFERENT
				# flanking neighbors, carved toward whichever dominates
				# BLEND_PRIORITY (see this function's own doc comment).
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


## Deterministic tie-break for a mixed-biome corner (see
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


## Linear atlas index where the earth-modification blend family begins --
## right after the whole land/land corner family (see
## earth_dominant_blend_for). A FOURTH, differently-shaped family alongside
## the three corner-carve ones above: earth is always the "own"/near side
## (see paint()'s modifications branch), so this only needs one slot per
## real land-biome partner (no NxN pair space -- earth itself is never a
## `other_biome`/partner for any real biome's own blend or corner).
func _earth_blend_base_linear() -> int:
	return _land_land_corner_base_linear() + _land_land_corner_family_size()


## One slot per real land biome (ocean is excluded -- see
## earth_dominant_blend_for) x every non-empty cardinal-direction subset x
## BLEND_VARIANTS -- mirrors _land_corner_base_linear's sibling family
## shape (single-biome-indexed, not pair-indexed), sized on
## DIRECTION_MASK_COUNT instead of CORNER_MASK_COUNT since this is a
## directional-blend family, not a corner-carve one.
func _earth_blend_family_size() -> int:
	return _land_biome_count() * DIRECTION_MASK_COUNT * BLEND_VARIANTS


## Linear atlas index of one earth-modification blend tile, indexed by the
## real land-biome partner's ordinal within the 6 land biomes (skip ocean's
## own KNOWN_BIOMES index 0, same "- 1" convention _land_land_corner_linear
## uses).
func _earth_blend_linear(neighbor_biome: String, mask: int, variant: int) -> int:
	var neighbor_ordinal := BiomeClassifier.KNOWN_BIOMES.find(neighbor_biome) - 1
	return (
		_earth_blend_base_linear()
		+ neighbor_ordinal * DIRECTION_MASK_COUNT * BLEND_VARIANTS
		+ (mask - 1) * BLEND_VARIANTS + (variant % BLEND_VARIANTS)
	)


## ## Pitched roof variants (docs/concept/building.md "How a house reads
## from above")
##
## A FIFTH family, alongside the three corner-carve ones and the earth
## blend. Village roofs used to paint one flat tile per material, which
## from above reads as a brick patio rather than a building -- reported as
## houses that "don't resemble houses at all". A roof cell's tile now
## depends on its CONTEXT within its own building (see RoofShape): a shade
## band for the pitch, and an outward-edge mask for the silhouette. That is
## the same "resolve appearance from neighbours at paint time" shape the
## blend/corner families already use, so it needs no new BuildingPiece ids
## and no save-format change -- a roof is still one chunk modification per
## cell.
##
## Ordered so the material is the outermost index, mirroring every other
## family's own "one contiguous block per subject" layout.
const ROOF_VARIANT_MATERIALS: Array[String] = [
	BuildingPiece.MATERIAL_WOOD, BuildingPiece.MATERIAL_STONE
]

## Every outward-edge combination of the 4 cardinal sides, INCLUDING zero
## (a fully interior roof cell, which must draw no rim at all) -- unlike
## DIRECTION_MASK_COUNT's blend masks, where an empty mask means "no blend
## tile is needed" and so is never reserved.
const ROOF_EDGE_MASK_COUNT := 16


func _roof_variant_base_linear() -> int:
	return _earth_blend_base_linear() + _earth_blend_family_size()


func _roof_variant_family_size() -> int:
	return ROOF_VARIANT_MATERIALS.size() * RoofShape.TOTAL_SHADE_BANDS * ROOF_EDGE_MASK_COUNT


func _roof_variant_linear(material: String, band: int, mask: int) -> int:
	var material_ordinal: int = maxi(ROOF_VARIANT_MATERIALS.find(material), 0)
	return (
		_roof_variant_base_linear()
		+ material_ordinal * RoofShape.TOTAL_SHADE_BANDS * ROOF_EDGE_MASK_COUNT
		+ band * ROOF_EDGE_MASK_COUNT
		+ mask
	)


## The atlas coordinate for one roof cell, given the pitch band and outward
## edge mask RoofShape computed for it. Out-of-range values clamp rather
## than index past the family -- a caller that got this wrong should show a
## flat roof tile, not garbage from a neighbouring family.
func atlas_coords_for_roof_variant(material: String, band: int, mask: int) -> Vector2i:
	var safe_band := clampi(band, 0, RoofShape.TOTAL_SHADE_BANDS - 1)
	var safe_mask := clampi(mask, 0, ROOF_EDGE_MASK_COUNT - 1)
	return _grid_coords(_roof_variant_linear(material, safe_band, safe_mask))


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
	return _terrain_sprite_generator.generate_multi_directional_blend_image_from(near_image, far_image, directions, variant)


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

	# Earth-modification blend tiles (see earth_dominant_blend_for/paint()'s
	# modifications branch): a built or PathScarring-worn earth cell now
	# dithers its own flat texture toward whichever real land biome borders
	# it, the same treatment every real biome pair already gets above,
	# instead of always being one dead-flat unblended square regardless of
	# neighbors (reported: a grass-to-dirt-path boundary read as a hard
	# edge, with the corner where they met a hard square). Ocean is
	# excluded, mirroring every other family's own "land never blends
	# toward ocean" scope limit -- the shoreline stays the GPU WaterFx
	# overlay's job alone.
	var earth_flat_image := Image.create(ART_TILE_SIZE, ART_TILE_SIZE, false, Image.FORMAT_RGBA8)
	earth_flat_image.fill(EARTH_COLOR)
	for neighbor_index in biome_count:
		var neighbor_biome: String = BiomeClassifier.KNOWN_BIOMES[neighbor_index]
		if neighbor_biome == "ocean":
			continue
		for mask in range(1, DIRECTION_MASK_COUNT + 1):
			var directions := _directions_from_mask(mask)
			for variant in BLEND_VARIANTS:
				var neighbor_image := _normalized_for_compositing(_biome_frame_image(neighbor_biome, variant, 0))
				var earth_blend_image := _terrain_sprite_generator.generate_multi_directional_blend_image_from(
					earth_flat_image, neighbor_image, directions, variant
				)
				_blit_tile(image, earth_blend_image, _earth_blend_linear(neighbor_biome, mask, variant))

	# Pitched roof variants (see _roof_variant_base_linear): one tile per
	# material x pitch band x outward-edge mask, so a roof cell can be
	# painted from its own context within its building rather than from one
	# flat per-material tile.
	for roof_material in ROOF_VARIANT_MATERIALS:
		for band in RoofShape.TOTAL_SHADE_BANDS:
			for edge_mask in ROOF_EDGE_MASK_COUNT:
				var roof_image := _building_piece_sprite_generator.generate_roof_variant_image(
					roof_material, band, edge_mask
				)
				_blit_tile(image, roof_image, _roof_variant_linear(roof_material, band, edge_mask))

	return image


## Builds a grid-laid-out TileSet: VARIANTS_PER_BIOME procedural tiles per known
## biome, one player-placeable "earth" tile, one dedicated tile per known
## placed structure (ProceduralStructureSprite.STRUCTURE_IDS -- campfire,
## furnace), then a directional blend tile for every ordered pair of distinct
## biomes x every non-empty cardinal-direction subset (DIRECTION_MASK_COUNT
## masks) x VARIANTS_PER_BIOME. The atlas image itself is cached to disk
## after the first build (see ATLAS_VERSION/_build_atlas_pixels), and the
## built TileSet is then memoized per PROCESS (see _tile_set_cache).
##
## The metadata pass below was previously described here as "cheap, no pixel
## work". It is not cheap: it wraps a 2048x5120 image in an ImageTexture and
## calls create_tile() for all 10,240 atlas cells, which measured 8.8s per
## call -- and EarthChunkManager._init calls it once per instance, i.e. once
## per test fixture, which is where most of the headless suite's runtime went.
func build_tile_set() -> TileSet:
	var cached_key := _tile_set_cache_key()
	if cached_key != "" and _tile_set_cache.has(cached_key):
		return _tile_set_cache[cached_key]

	var biome_count := BiomeClassifier.KNOWN_BIOMES.size()
	var total_cells := _roof_variant_base_linear() + _roof_variant_family_size()
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

	# Keyed AFTER the build, not before: when no cache existed the pre-build
	# key is empty, and the freshly saved atlas is what the next caller will
	# fingerprint.
	var built_key := _tile_set_cache_key()
	if built_key != "":
		_tile_set_cache[built_key] = tile_set
	return tile_set


## Built TileSets, shared by the whole process and keyed by the identity of
## the atlas they were built from.
##
## Safe to share because nothing in this codebase ever mutates a built
## TileSet -- add_source/create_tile/remove_tile appear only in this file and
## in snow_layer.gd, on their own freshly built sets -- so every TileMapLayer
## can point at one instance. Same process-level-memo shape
## IllustratedAnimalSprite._frame_cache and IllustratedCropSprite already use.
##
## Costs ~42 MB of RGBA8 per distinct key held for the process lifetime. In
## practice that is the production atlas plus, in a full headless test run,
## test_terrain_renderer.gd's two dedicated test paths.
static var _tile_set_cache: Dictionary = {}


## The identity of the atlas this renderer would build right now: the version
## it demands, where it reads and writes, the version string actually on
## disk, and the md5 of the cached pixels themselves. Everything that can
## make two build_tile_set() calls produce different tiles is in here --
## which is what makes sharing one TileSet between callers sound, and what
## makes a test that rewrites the cache file mid-run correctly get a rebuild
## (test_build_tile_set_rebuilds_after_the_cached_atlas_changes_on_disk).
##
## Empty when there is no usable cache on disk. That case must never be
## memoized BEFORE the build: the call is about to generate and save a new
## atlas, so a later call at the same key would legitimately see different
## pixels. Hashing the file rather than trusting its timestamp is deliberate
## -- FileAccess.get_modified_time has one-second resolution, and the cache
## tests rewrite the same path several times inside one second.
func _tile_set_cache_key() -> String:
	if not FileAccess.file_exists(atlas_cache_path):
		return ""
	if not FileAccess.file_exists(atlas_version_path):
		return ""
	var file := FileAccess.open(atlas_version_path, FileAccess.READ)
	var on_disk_version := file.get_as_text()
	file.close()
	return "%s|%s|%s|%s|%s" % [
		ATLAS_VERSION,
		atlas_cache_path,
		atlas_version_path,
		on_disk_version,
		FileAccess.get_md5(atlas_cache_path),
	]


## Paints every cell of a chunk's biome grid onto a TileMapLayer, offset by
## origin (in tile coordinates) -- used to place a chunk at its global
## position when streaming multiple chunks onto one shared TileMapLayer. A
## cell with a player-made modification (see Chunk.modifications) paints that
## instead of its generated biome tile -- an EARTH_TILE_ID cell (built floor
## OR PathScarring's worn-ground dirt, see src/world/path_scarring.gd) now
## blends toward whichever real, unmodified biome cardinally borders it (see
## earth_dominant_blend_for), instead of always painting one dead-flat
## EARTH_COLOR square regardless of neighbors -- reported (screenshot): a
## grass-to-dirt-path boundary read as a hard edge, with the corner where
## they met a hard square. Every other modification (structures, building
## pieces) stays exactly as before: deliberately man-made, flat-edged, never
## organically blended into the ground. Otherwise, if any cardinal neighbor
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
##
## A corner whose flanking edges blend ALREADY covers is deliberately left to
## blend, not carved -- see _corner_directions_not_covered_by_blend's own doc
## comment for why a plain "corner always wins" rule (tried first) regressed
## real, intentional multi-edge dithering.
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
				var tile_id: String = chunk.modifications[local]
				if tile_id == EARTH_TILE_ID:
					var variant := variant_index_for_position(global.x, global.y)
					var neighbors := _neighbor_biomes(chunk, x, y, origin, global_biome_lookup, true)
					var earth_blend := earth_dominant_blend_for(neighbors)
					if earth_blend.is_empty():
						atlas_coords = atlas_coords_for_modification(tile_id)
					else:
						atlas_coords = atlas_coords_for_earth_blend(earth_blend.partner, earth_blend.directions, variant)
				else:
					atlas_coords = atlas_coords_for_modification(tile_id)
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
				# Diagonals are needed for the DIAGONAL-ONLY corner case (two
				# land biomes touching at a single tile-grid corner -- the
				# outer corner of a staircase boundary, see
				# corner_direction_for). They must be gathered BEFORE the
				# corner call, not inside the no-blend fallback below: a
				# staircase cell almost always has a real cardinal blend too,
				# so gathering them only when blend came back empty meant the
				# diagonal-only branch could never fire on exactly the cells
				# it exists for, and a grass/forest staircase kept its hard
				# corners (reported: "the biome borders still contain hard
				# corners").
				var diagonal_neighbors := _diagonal_neighbor_biomes(
					chunk, x, y, origin, global_biome_lookup
				)
				var corner := _corner_directions_not_covered_by_blend(
					corner_direction_for(biome_name, neighbors, diagonal_neighbors), blend
				)
				if not corner.is_empty():
					# A real tile-grid right-angle (see corner_direction_for)
					# blend structurally could never have expressed for
					# these specific directions -- carve it, even when blend
					# also found something real on a genuinely unrelated
					# edge of this same cell.
					atlas_coords = atlas_coords_for_corner(biome_name, corner.partner, corner.directions, variant)
				elif not blend.is_empty():
					atlas_coords = atlas_coords_for_directional_blend(
						biome_name, blend.partner, blend.directions, variant
					)
				else:
					# Neither a blend nor a corner applies: a cell with no
					# differing cardinal neighbour and no diagonal-only touch is
					# plain interior ground. `corner` above is already computed
					# WITH diagonals, so reaching here genuinely means
					# corner_direction_for found nothing -- there is no second,
					# more thorough corner check left to fall back to.
					atlas_coords = atlas_coords_for_biome(biome_name, variant)
			tile_map_layer.set_cell(global, 0, atlas_coords)


## Strips out any of `corner`'s diagonal directions whose flanking cardinal
## edges are BOTH already being dithered by `blend` -- what's left (if
## anything) is genuinely inexpressible by blend, and should be carved
## instead of silently dropped.
##
## Reported directly, as a follow-up after the land/land corner family
## itself landed: "still sharp corners at diagonal borders". A cell can have
## a genuinely real corner on ONE diagonal while an entirely UNRELATED
## cardinal side also qualifies for ordinary dithering toward some THIRD,
## lower-priority neighbor biome -- checking blend first (the original
## order) let that unrelated edge silently steal the whole tile's treatment
## before the real corner was ever even asked about. Measured directly
## against real generated chunks near Berlin: 553 of 1065 real land/land
## corner-eligible cells (52%) were starved this way, plus 20 of 2448 real
## ocean corners (a smaller pre-existing instance of the same bug, since an
## ocean cell's own BLEND_PRIORITY(0) is the lowest possible and can never be
## the LOWER-priority side of a blend, so only its LAND-owning concave corner
## case was ever actually at risk).
##
## A blanket "corner always wins" fix (tried first) regressed real,
## INTENTIONAL multi-edge blending instead: a cell whose two perpendicular
## differing neighbors are the SAME lower-priority biome (e.g. grassland
## notched by desert on both east and south) is a real corner geometrically,
## but dominant_blend_for is not merely "also willing" to handle it -- for
## THAT specific case blend and corner describe the exact same fact, and the
## existing, tested, intentional behavior is a soft dithered fringe across
## both edges (test_paint_blends_a_corner_toward_multiple_differing_
## neighbors), not a carved corner. The distinguishing rule: a corner
## direction survives only when NEITHER of its two flanking cardinal edges
## is one blend already chose to dither -- if EITHER flank is already being
## dithered toward some partner, this corner's own carved shape (which may
## pick a DIFFERENT dominant partner than that edge's own dither, see
## _dominant_corner_partner) would sit awkwardly against/inside an edge
## already getting its own separate treatment, so it defers to the simpler,
## already-decided blend instead of adding a second, possibly-conflicting
## treatment on top of it. This also naturally covers the exact case blend
## only ever picks up STRICTLY LOWER-priority neighbors for in the first
## place (a corner whose own flanking neighbors are BOTH priority >=
## biome_name's own could never have a flank blend-covered at all, so
## nothing here ever excludes it) without needing to re-derive that priority
## comparison independently -- which also keeps this correct against
## dominant_blend_for's own ocean exclusion (ocean is never a blend partner
## regardless of priority -- see that function's own doc comment); checking
## blend's ACTUAL returned directions, not a re-derived priority comparison,
## is what makes that automatic.
func _corner_directions_not_covered_by_blend(corner: Dictionary, blend: Dictionary) -> Dictionary:
	if corner.is_empty():
		return corner
	var blend_directions: Array = blend.get("directions", [])
	var surviving := []
	for corner_direction in corner.directions:
		var horizontal := Vector2i(corner_direction.x, 0)
		var vertical := Vector2i(0, corner_direction.y)
		if blend_directions.has(horizontal) or blend_directions.has(vertical):
			continue
		surviving.append(corner_direction)
	if surviving.is_empty():
		return {}
	return {"partner": corner.partner, "directions": surviving}


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
	# Classified ONCE for the whole chunk rather than per cell: RoofShape
	# groups the chunk's roof cells into buildings (a flood fill) before it
	# can say anything about any single cell's pitch, so asking per cell
	# would redo that grouping for every tile.
	#
	# Deliberately classified over ALL of the chunk's roof cells, not just
	# the visible ones: a cell hidden because the player is standing inside
	# that room is still part of its building's shape, so excluding it would
	# re-cut the roof's silhouette (and re-run its ridge) every time someone
	# walks through a door.
	var classified := RoofShape.classify_all(chunk.roof_modifications)
	for local in chunk.roof_modifications:
		var global: Vector2i = origin + local
		if hidden_cells.has(local):
			tile_map_layer.erase_cell(global)
			continue
		var shape: Dictionary = classified.get(local, {})
		var piece_id: String = chunk.roof_modifications[local]
		tile_map_layer.set_cell(global, 0, atlas_coords_for_roof_variant(
			BuildingPiece.material_of(piece_id), shape.get("band", 0), shape.get("mask", 0)
		))


## The cardinal neighbor biomes of a local chunk cell, keyed by direction
## (see _DIRECTIONS). Neighbors inside the chunk read straight off its biome
## grid; neighbors outside it are resolved via `global_biome_lookup` when
## provided (asked with the neighbor's *global* tile coordinate), and omitted
## when the lookup is invalid or answers "" (unknown).
##
## `exclude_modified_neighbors` (used only by paint()'s earth-modification
## branch, see earth_dominant_blend_for): when true, an IN-CHUNK neighbor
## that itself carries a modification is omitted entirely instead of
## reporting its underlying pre-modification biome. Without this, two
## adjacent earth cells (a multi-tile worn path or built floor) would each
## treat the other's original ground biome as a differing neighbor and
## dither a seam straight through the middle of what should read as one
## uniform patch of dirt -- chunk.biome is never actually overwritten by a
## modification, only shadowed by it (see Chunk.modifications), so a plain
## lookup can't otherwise tell the two apart. Out-of-chunk neighbors keep
## going through global_biome_lookup unchanged either way -- that callable
## has no visibility into a neighboring chunk's modifications at all, the
## same pre-existing blind spot the ordinary biome-to-biome blend/corner
## system already has at chunk seams.
func _neighbor_biomes(
	chunk: Chunk, x: int, y: int, origin: Vector2i, global_biome_lookup: Callable,
	exclude_modified_neighbors: bool = false
) -> Dictionary:
	var neighbors := {}
	for direction in _DIRECTIONS:
		var nx: int = x + direction.x
		var ny: int = y + direction.y
		if nx >= 0 and nx < chunk.width and ny >= 0 and ny < chunk.height:
			if exclude_modified_neighbors and chunk.modifications.has(Vector2i(nx, ny)):
				continue
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


## The atlas coordinate of the HillshadeFx overlay tile for a real slope/
## aspect reading (see terrain_relief.gd, docs/concept/terrain_relief.md's
## "Hillshading" section) -- quantized into ProceduralHillshadeSprite's
## small slope-bin x aspect-bin grid, since real slope/aspect are
## continuous and don't fit a bounded atlas the way shore-distance's
## enumerable land-direction masks do (see that generator's own doc
## comment). `aspect_deg` below 0 (terrain_relief.gd's flat-ground
## sentinel) always resolves to the single shared flat tile, same as
## slope_deg at or near 0 -- both read as "no meaningful direction".
func atlas_coords_for_hillshade(slope_deg: float, aspect_deg: float) -> Vector2i:
	if slope_deg <= 0.001 or aspect_deg < 0.0:
		return Vector2i(0, 0)
	var slope_bin := ProceduralHillshadeSprite.slope_bin_for(slope_deg)
	var aspect_bin := ProceduralHillshadeSprite.aspect_bin_for(aspect_deg)
	return Vector2i(1 + slope_bin * ProceduralHillshadeSprite.ASPECT_BINS + aspect_bin, 0)


## A small, separate TileSet for the GPU hillshade overlay layer: one flat
## "no slope" tile plus one tile per (slope bin, aspect bin) combination --
## SLOPE_BINS x ASPECT_BINS total, each holding real quantized slope/aspect
## DATA (see ProceduralHillshadeSprite) rather than art. hillshade_shader.gd
## samples it as a texture channel and shades continuously on the GPU from
## the real, live sun position -- same "bake data once, animate on the GPU
## from a live uniform" shape build_water_overlay_tile_set already
## established for shore distance + weather.
func build_hillshade_overlay_tile_set() -> TileSet:
	var hillshade_total := 1 + ProceduralHillshadeSprite.SLOPE_BINS * ProceduralHillshadeSprite.ASPECT_BINS
	var hillshade_image := Image.create(hillshade_total * ART_TILE_SIZE, ART_TILE_SIZE, false, Image.FORMAT_RGBA8)
	hillshade_image.blit_rect(
		_hillshade_generator.generate_flat_image(),
		Rect2i(Vector2i.ZERO, Vector2i(ART_TILE_SIZE, ART_TILE_SIZE)), Vector2i.ZERO
	)
	for slope_bin in ProceduralHillshadeSprite.SLOPE_BINS:
		for aspect_bin in ProceduralHillshadeSprite.ASPECT_BINS:
			var index := 1 + slope_bin * ProceduralHillshadeSprite.ASPECT_BINS + aspect_bin
			var slope_deg := ProceduralHillshadeSprite.slope_for_bin(slope_bin)
			var aspect_deg := ProceduralHillshadeSprite.aspect_for_bin(aspect_bin)
			var tile_image := _hillshade_generator.generate_image(slope_deg, aspect_deg)
			hillshade_image.blit_rect(
				tile_image, Rect2i(Vector2i.ZERO, Vector2i(ART_TILE_SIZE, ART_TILE_SIZE)),
				Vector2i(index * ART_TILE_SIZE, 0)
			)

	var hillshade_source := TileSetAtlasSource.new()
	hillshade_source.texture = ImageTexture.create_from_image(hillshade_image)
	hillshade_source.texture_region_size = Vector2i(ART_TILE_SIZE, ART_TILE_SIZE)
	for i in hillshade_total:
		hillshade_source.create_tile(Vector2i(i, 0))

	var hillshade_tile_set := TileSet.new()
	hillshade_tile_set.tile_size = Vector2i(ART_TILE_SIZE, ART_TILE_SIZE)
	hillshade_tile_set.add_source(hillshade_source, 0)
	return hillshade_tile_set


## Atlas coordinate for a real (flow-direction compass bearing, signed
## cross-channel offset, fast flag) triple -- see ProceduralRiverFlowSprite
## and docs/concept/rivers.md, same binned-dimensions indexing shape
## atlas_coords_for_hillshade already established.
func atlas_coords_for_river_flow(angle_deg: float, is_fast: bool) -> Vector2i:
	return ProceduralRiverFlowSprite.atlas_cell_for_index(
		ProceduralRiverFlowSprite.atlas_index_for(
			ProceduralRiverFlowSprite.direction_bin_for(angle_deg),
			1 if is_fast else 0
		)
	)


## A separate TileSet for the GPU river-flow overlay layer:
## DIRECTION_BINS x ACROSS_BINS x SPEED_LEVELS tiles, each holding real
## quantized (flow-direction, signed across-offset, fast-flag) DATA (see
## ProceduralRiverFlowSprite) rather than art. river_flow_shader.gd samples
## it as texture channels and advects the water surface continuously on the
## GPU -- same "bake data once, animate from TIME" shape
## build_hillshade_overlay_tile_set already established.
func build_river_flow_tile_set() -> TileSet:
	var total := ProceduralRiverFlowSprite.total_tiles()
	var columns := ProceduralRiverFlowSprite.ATLAS_COLUMNS
	var rows := int(ceil(float(total) / float(columns)))
	# A 2D grid, not a single row: laid out in one row this atlas would be
	# 73,728 px wide, vastly past the 16,384 GL_MAX_TEXTURE_SIZE common on
	# the integrated GPUs this game targets -- it would simply fail to
	# upload.
	var flow_image := Image.create(
		columns * ART_TILE_SIZE, rows * ART_TILE_SIZE, false, Image.FORMAT_RGBA8
	)
	for speed_index in ProceduralRiverFlowSprite.SPEED_LEVELS:
		for direction_bin in ProceduralRiverFlowSprite.DIRECTION_BINS:
			var index := ProceduralRiverFlowSprite.atlas_index_for(direction_bin, speed_index)
			var cell := ProceduralRiverFlowSprite.atlas_cell_for_index(index)
			var tile_image := _river_flow_generator.generate_image(
				ProceduralRiverFlowSprite.angle_for_bin(direction_bin),
				ProceduralRiverFlowSprite.alpha_for_fast(speed_index == 1)
			)
			flow_image.blit_rect(
				tile_image, Rect2i(Vector2i.ZERO, Vector2i(ART_TILE_SIZE, ART_TILE_SIZE)),
				cell * ART_TILE_SIZE
			)

	var flow_source := TileSetAtlasSource.new()
	flow_source.texture = ImageTexture.create_from_image(flow_image)
	flow_source.texture_region_size = Vector2i(ART_TILE_SIZE, ART_TILE_SIZE)
	for i in total:
		flow_source.create_tile(ProceduralRiverFlowSprite.atlas_cell_for_index(i))

	var flow_tile_set := TileSet.new()
	flow_tile_set.tile_size = Vector2i(ART_TILE_SIZE, ART_TILE_SIZE)
	flow_tile_set.add_source(flow_source, 0)
	return flow_tile_set
