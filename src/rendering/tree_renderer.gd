extends RefCounted

const TreePlacement = preload("res://src/world/tree_placement.gd")
const PixelNoise = preload("res://src/rendering/pixel_noise.gd")
const Chunk = preload("res://src/world/chunk.gd")
const ChoppableTree = preload("res://src/rendering/choppable_tree.gd")
const ProceduralTreeSprite = preload("res://src/rendering/procedural_tree_sprite.gd")
const TreeGenome = preload("res://src/gameplay/tree_genome.gd")
const WindSway = preload("res://src/rendering/wind_sway.gd")
const DropShadow = preload("res://src/rendering/drop_shadow.gd")
const TreeGrowth = preload("res://src/gameplay/tree_growth.gd")
const TreeSpecies = preload("res://src/world/tree_species.gd")
const BuildingPiece = preload("res://src/gameplay/building_piece.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")
const TreePhenology = preload("res://src/world/tree_phenology.gd")

## A tree's WORLD footprint (see ProceduralTreeSprite.WORLD_SIZE) -- derived
## from the art size through ProceduralTreeSprite's own (not ArtResolution's
## shared) DETAIL_MULTIPLIER/SPRITE_SCALE rather than equal to it, since the
## art is authored DETAIL_MULTIPLIER times oversized and drawn scaled back
## down (see docs/concept/art_resolution.md). Shadow and collision size off
## this, so they stay matched to the tree's actual world presence.
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


## How much snow lies on a canopy right now -- the live weather fact
## EarthChunkManager._snow_depth already tracks for the GROUND (see
## SnowLayer/docs/concept/seasons.md's CANOPY_SNOW section), pushed here so a
## newly spawned tree's canopy is already dressed for it (see _texture_for).
##
## This is the SPAWN path only, mirroring set_wind_strength's own
## store-and-forward shape. An already-standing tree is dressed by a
## different mechanism entirely -- EarthChunkManager.sync_tree_season pushes
## the same live depth straight to each loaded ChoppableTree's own
## set_ripe_fruit, the same way it already pushes season/turn -- because
## this renderer holds no reference to trees once they are spawned (see
## EarthChunkManager._loaded_trees).
var _snow_coverage := 0.0


func set_snow_coverage(coverage: float) -> void:
	_snow_coverage = coverage


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
			var index := y * chunk.width + x
			var biome_name := chunk.biome[index]
			if not _tree_placement.has_tree_at(global_x, global_y, biome_name):
				continue
			# A river never changes chunk.biome itself (see
			# docs/concept/rivers.md's Rendering section), so the forest-cell
			# check above can't see it on its own -- reported live: "trees
			# grow in rivers". Size-checked so a Chunk built without ever
			# setting is_river (every pre-existing test fixture) is treated
			# as "no rivers" rather than an index error.
			if chunk.blocks_ground_cover(index):
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
			var tree := _build_tree_node(position, _seeded_age(global_x, global_y))
			tree.position = position
			parent.add_child(tree)
			spawned.append(tree)

	return spawned


## A real forest has an age structure -- some trees decades older than
## others, a few genuinely ancient (see TreeGrowth's own "old growth" doc
## comment; asked directly: "make trees another 30% bigger, varying by
## age"). A bare INF default (this file's own age_seconds=INF convention
## for "always been here") would give every original-forest tree the exact
## same size with zero variation, which reads as a planted grove, not a
## real stand.
##
## Deterministic from the tile, like _stand_position right above -- a
## regenerated/reloaded chunk must show the identical forest, not one that
## reshuffles its own trees' ages.
##
## Ranges from freshly mature up through DOUBLE OLD_GROWTH_SECONDS, so the
## full curve is genuinely represented across a real forest: some trees
## barely past maturity, some mid-way through their old-growth years, and
## some -- the ones landing at or past OLD_GROWTH_SECONDS itself -- true
## old growth at the ceiling.
func _seeded_age(global_x: int, global_y: int) -> float:
	var t := float(PixelNoise.range_index(global_x * 15485863 + global_y, 409, 0, 1001)) / 1000.0
	return lerp(TreeGrowth.MATURITY_SECONDS, TreeGrowth.OLD_GROWTH_SECONDS * 2.0, t)


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
	# The canopy art is authored ProceduralTreeSprite.DETAIL_MULTIPLIER times
	# oversized for pixel detail; scaling it back down is what keeps the
	# tree's world footprint unchanged (see docs/concept/art_resolution.md).
	# NOT ArtResolution.SPRITE_SCALE -- trees use their own, larger,
	# tree-specific multiplier now (see that constant's own doc comment).
	sprite.scale = Vector2.ONE * ProceduralTreeSprite.SPRITE_SCALE
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


## ## The canopy is on the CLOCK, not on the simulation
##
## (see docs/concept/seasons.md, "The canopy is on the clock, not on the
## simulation".) This was three pushed fields -- `season`, `turning_into`,
## `turn_progress` -- with `season` starting as an EMPTY STRING, written from
## exactly one place: EarthChunkManager._sync_tree_season (now the public,
## clock-driven sync_tree_season), reachable only from
## step_fruiting, reachable only from World._process behind
## _owns_ecosystem_simulation() and a ~1s accumulator. Two real consequences:
## the initial awaited chunk load builds its trees before that ever fires, so
## a fresh world's first chunks arrived with no season at all and fell through
## IllustratedTree._FALLBACK_SEASON to summer leaf (green trees in the snow,
## corrected a moment later); and on a JOINED CLIENT, which owns no
## simulation, the tick never runs at all and every tree stays summer-green in
## every season for the whole session.
##
## Which picture a tree wears is a pure function of the world clock -- a
## RENDERING concern, exactly like the seasonal tint on the ground beside it
## (SeasonalFoliage), and not a simulation-ownership one. So the renderer
## holds the CLOCK and derives the canopy from it (see canopy_state), off the
## same SeasonCycle year fraction every other season reader uses.
##
## That also removes the unset state rather than papering over it: there is no
## way to be in it. A renderer nobody has pushed anything into reads the
## clock's own zero -- the first instant of spring, which for a canopy is bare
## wood -- instead of looking like a healthy summer tree standing in the snow.
var _world_age_seconds := 0.0
var _season_cycle := SeasonCycle.new()


## Moves the clock the canopies are drawn against. The ONLY way to change the
## season new trees are built in -- see the note above for why it is a clock
## and not a season string.
func set_world_age_seconds(seconds: float) -> void:
	_world_age_seconds = seconds


## Which canopy picture trees are wearing right now, as
## {season, turning_into, turn_progress} -- the frame, the frame it is turning
## INTO and how far along, so a tree that loads mid-turn arrives part-turned
## like its neighbours rather than snapping to whichever stage it was built in.
##
## `season` here is a canopy KEY -- which of IllustratedTree's four frames --
## and NOT a claim about what month it is: the first instant of spring is
## still bare wood. `EarthChunkManager.current_season()` is the calendar, for
## the HUD.
##
## Off TreePhenology rather than SeasonTransition, which is what keeps winter
## bare (see docs/concept/seasons.md, "Winter stays bare: the canopy has its
## own phenology"). The ground and the crown still share one clock, one set of
## names and one quantiser; what they no longer share is the curve, because a
## turn a lawn expresses as an imperceptible colour lerp a canopy expresses as
## a much denser, much pinker picture painted over bare branches -- which is
## how blossom ended up in the snow.
##
## Derived here rather than in each caller so the trees about to be built, the
## trees already loaded (EarthChunkManager.sync_tree_season hands this very
## dictionary on to them) and anything else that asks cannot drift apart.
func canopy_state() -> Dictionary:
	var stage := TreePhenology.canopy_state_at(_season_cycle.year_fraction(_world_age_seconds))
	return {
		"season": stage["from"],
		"turning_into": stage["to"],
		"turn_progress": stage["progress"],
	}


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
	var canopy := canopy_state()
	var season: String = canopy["season"]
	var turning_into: String = canopy["turning_into"]
	var turn_progress: float = canopy["turn_progress"]
	# Snow belongs in the key for the same reason turn_progress does: a
	# tree spawned mid-snowfall is a different picture from one spawned
	# before it started, and the cache must not hand back a stale one.
	var snow_level := ProceduralTreeSprite.snow_level(_snow_coverage)
	var key := "%s_%s_%s_%.2f_%.2f" % [species_id, season, turning_into, turn_progress, snow_level]
	if not _texture_cache.has(key):
		_texture_cache[key] = _tree_sprite_generator.generate_texture_with_fruit(
			genome.species_bias, hash(species_id), 0, season, turning_into, turn_progress, 1.0,
			_snow_coverage
		)
	return _texture_cache[key]
