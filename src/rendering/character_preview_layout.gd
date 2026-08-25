extends RefCounted

## Pure, seeded placement math for the character preview diorama (see
## docs/concept/character_creator_preview_scene.md) -- where the pond,
## trees, pebbles, and grass clumps sit within a given footprint. Same
## seed, same layout (the design doc's "Determinism" pillar) -- no Godot
## nodes here at all; CharacterPreviewDiorama is the only piece that turns
## a Result into actual scene nodes.

## The real world's own grassland rules, reused rather than restated: how
## densely a meadow covers clear ground (TallGrass.SEED_CHANCE) and the
## smooth-noise field that decides WHICH cells that share lands on
## (FIELD_NOISE_SCALE) -- see the grass scatter in generate(). Preloaded as
## a pure data/rule source; no TallGrass simulation is ever run here.
const TallGrass = preload("res://src/world/tall_grass.gd")
const PixelNoise = preload("res://src/rendering/pixel_noise.gd")
## The tree ART's own world size -- procedural_tree_sprite, not tree_renderer,
## so this pure module stays free of the ChoppableTree/collision dependency
## chain while still deriving its placement margins from the real thing (see
## tree_bounds).
const ProceduralTreeSprite = preload("res://src/rendering/procedural_tree_sprite.gd")

## Pond radius as a fraction of the footprint's shorter side.
const POND_RADIUS_FRACTION := 0.22
const TREE_COUNT := 2
const PEBBLE_COUNT := 5
const FISH_COUNT := 2
## How much of the pond's own radius a fish is allowed to roam within, as a
## fraction -- kept well under 1.0 so a fish's own drawn BODY (not just its
## centre point) never overhangs the shore. Tightened from 0.8 (reported
## live: "the fish spawns outside the pond") -- a fish's own art measures
## roughly 4.4 world units from its centre to its longest edge
## (ProceduralFishSprite.WORLD_SIZE * ArtResolution.SPRITE_SCALE *
## FishRenderer.FISH_WORLD_SCALE, halved), which at 0.8 * a ~21-unit pond
## radius left as little as ~0.4 units of clearance for a fish spawned at
## the very edge of its own allowed band -- not always enough once that
## body extends outward from its own centre in a random direction. 0.6
## leaves a real, comfortable margin instead. CharacterPreviewDiorama's own
## ongoing swim-target picking (_pick_new_fish_target) uses this exact same
## fraction, not a separate hand-copied number, so a fish's SPAWN position
## and its later wander targets can never quietly drift out of sync.
const FISH_SAFE_RADIUS_FRACTION := 0.6
## World units kept clear around each tree -- both for the pebble/grass
## scatter below and for CharacterPreviewDiorama's own obstacle-avoiding
## stroll (see is_clear).
const TREE_MARGIN := 6.0
## World units between grass-clump anchors -- matches roughly one ground
## tile, since IllustratedGrassPatch.fill_band's own doc comment describes
## one cell_specs entry as covering about one 16x16 tile.
const GRASS_CLUMP_SPACING := 16.0
## How far outside the pond's rim a pebble can land -- keeps them reading
## as "at the water's edge," not scattered loose in the grass.
const PEBBLE_RIM_BAND := 4.0
## Extra clearance beyond the pond's own radius, kept between the pond and
## whichever footprint edge it sits closest to -- enough that the pond
## still reads as a whole, real shape and not visually clipped by the
## diorama's own boundary, while still sitting close enough to read as "at
## the edge" rather than centred (reported live: "the fish pond should be
## at the edge").
const POND_EDGE_MARGIN := 4.0


class Result:
	var pond_center: Vector2
	var pond_radius: float
	var tree_positions: Array[Vector2] = []
	var pebble_positions: Array[Vector2] = []
	var fish_positions: Array[Vector2] = []
	var grass_positions: Array[Vector2] = []

	## Whether `point` is clear of every obstacle this layout placed --
	## outside the pond and away from every tree by TREE_MARGIN. The one
	## predicate both the grass/pebble scatter below and
	## CharacterPreviewDiorama's own stroll-target rejection sampling share,
	## so "what counts as an obstacle" is defined in exactly one place.
	func is_clear(point: Vector2) -> bool:
		if point.distance_to(pond_center) <= pond_radius:
			return false
		for tree_position in tree_positions:
			if point.distance_to(tree_position) < TREE_MARGIN:
				return false
		return true


static func generate(seed_value: int, footprint: Vector2) -> Result:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var result := Result.new()

	result.pond_radius = minf(footprint.x, footprint.y) * POND_RADIUS_FRACTION
	result.pond_center = _pond_center_near_an_edge(result.pond_radius, footprint, rng)

	var tree_area := tree_bounds(footprint)
	for i in TREE_COUNT:
		result.tree_positions.append(_position_clear_of_pond(result, tree_area, rng))

	for i in PEBBLE_COUNT:
		var angle := rng.randf_range(0.0, TAU)
		var radius := result.pond_radius + rng.randf_range(0.0, PEBBLE_RIM_BAND)
		result.pebble_positions.append(result.pond_center + Vector2(cos(angle), sin(angle)) * radius)

	for i in FISH_COUNT:
		# Anywhere strictly inside the pond -- sqrt(rng) so points land
		# evenly across the disc's own AREA rather than bunching near the
		# centre (a plain uniform radius, with no correction, oversamples
		# the middle since a ring's area grows with radius).
		var angle := rng.randf_range(0.0, TAU)
		var radius := sqrt(rng.randf()) * result.pond_radius * FISH_SAFE_RADIUS_FRACTION
		result.fish_positions.append(result.pond_center + Vector2(cos(angle), sin(angle)) * radius)

	# A clump on EVERY clear cell carpeted the whole footprint at ~100%
	# coverage -- five times what a real meadow has -- and since each clump
	# draws IllustratedGrassPatch.CARD_COUNT overlapping FULL-TILE cards, the
	# result read as a hedge the hero was buried in rather than a field he
	# walks through (reported live: grass tufts several times his height).
	# The cards themselves are the right size and always were: one card is
	# IllustratedGrassPatch.WORLD_SIZE (16 world units), exactly one
	# TerrainRenderer.TILE_SIZE, and neither this diorama nor the real
	# world's own EarthChunkManager._sync_grass_sprites scales the
	# MultiMeshInstance2D at all -- so this is a DENSITY fix, not a scale one.
	#
	# The density reuses the real world's own meadow rule rather than
	# inventing a diorama-only number: TallGrass.SEED_CHANCE is the reference
	# grassland coverage TallGrass.FIELD_NOISE_THRESHOLD is itself pinned to,
	# and WHICH cells get that share is decided by the same smooth noise
	# field TallGrass._seed_initial_patches thresholds, indexed by CELL (not
	# world position) because FIELD_NOISE_SCALE is per-tile.
	#
	# Kept as "the highest-noise SHARE of the clear cells" rather than
	# TallGrass's own "every cell above the threshold": a chunk is 32x32
	# cells, where a fixed threshold averages out to SEED_CHANCE, but this
	# footprint is only ~6x6 -- less than one noise lattice cell across, so a
	# threshold there is all-or-nothing per seed and would leave whole heroes
	# standing in a bald diorama. Taking the share directly gives every seed
	# the real world's coverage while the noise still decides where the
	# meadow drifts, so the kept cells still clump instead of speckling.
	var columns := int(footprint.x / GRASS_CLUMP_SPACING)
	var rows := int(footprint.y / GRASS_CLUMP_SPACING)
	var scored: Array[Dictionary] = []
	for cell_y in rows:
		for cell_x in columns:
			var candidate := Vector2(
				(float(cell_x) + 0.5) * GRASS_CLUMP_SPACING,
				(float(cell_y) + 0.5) * GRASS_CLUMP_SPACING
			)
			if not result.is_clear(candidate):
				continue
			scored.append({
				"position": candidate,
				"field": PixelNoise.smooth(
					seed_value,
					float(cell_x) * TallGrass.FIELD_NOISE_SCALE,
					float(cell_y) * TallGrass.FIELD_NOISE_SCALE
				),
			})
	scored.sort_custom(func(a, b): return a["field"] > b["field"])
	# At least one clump whatever the rounding says -- a diorama with no
	# grass at all in it is never the right answer.
	var keep := mini(maxi(1, int(round(float(scored.size()) * TallGrass.SEED_CHANCE))), scored.size())
	for i in keep:
		var kept: Vector2 = scored[i]["position"]
		result.grass_positions.append(kept)

	return result


## Where a tree's own POSITION (the foot of its trunk) may land so that its
## whole drawn body stays inside the camera's frame -- which is exactly the
## footprint (see CharacterPreviewDiorama.FOOTPRINT and the camera derived
## from it in main_menu's diorama view). A tree sprite is anchored at the
## trunk foot and drawn upward from there (TreeRenderer._build_tree_node sets
## sprite.offset.y = -ProceduralTreeSprite.SIZE.y * 0.5 at
## ArtResolution.SPRITE_SCALE), so it occupies [x - w/2, x + w/2] x
## [y - h, y]. Derived from the tree art's OWN world size, never an eyeballed
## margin -- if the art ever changes size, this follows it. Previously
## unconstrained, which cut canopies off the top of the frame and trunks off
## its sides (reported live: trees clipped by the frame).
static func tree_bounds(footprint: Vector2) -> Rect2:
	var half_width := float(ProceduralTreeSprite.WORLD_SIZE.x) * 0.5
	var height := float(ProceduralTreeSprite.WORLD_SIZE.y)
	return Rect2(
		Vector2(half_width, height),
		Vector2(
			maxf(footprint.x - float(ProceduralTreeSprite.WORLD_SIZE.x), 0.0),
			maxf(footprint.y - height, 0.0)
		)
	)


## A pond centre close to one randomly-chosen edge of `footprint` -- reads
## as a real feature of a believable little scene (the water continuing
## past the frame, implied rather than a specimen posed dead-centre in an
## empty room). The position ALONG that edge (not toward/away from it) is
## still randomized across the middle band, so the pond doesn't always
## land in a corner either.
static func _pond_center_near_an_edge(pond_radius: float, footprint: Vector2, rng: RandomNumberGenerator) -> Vector2:
	var near_edge := pond_radius + POND_EDGE_MARGIN
	var along_x := rng.randf_range(near_edge, footprint.x - near_edge)
	var along_y := rng.randf_range(near_edge, footprint.y - near_edge)
	match rng.randi() % 4:
		0:
			return Vector2(near_edge, along_y)  # left
		1:
			return Vector2(footprint.x - near_edge, along_y)  # right
		2:
			return Vector2(along_x, near_edge)  # top
		_:
			return Vector2(along_x, footprint.y - near_edge)  # bottom


## A random point inside `bounds`, clear of the pond AND every tree already
## placed in `result.tree_positions` -- rejection sampling rather than
## solving the placement geometrically, since the "clear of what's already
## there" predicate (is_clear) already has to exist for the grass scatter and
## the stroll's own target picking, so reusing it here keeps tree placement
## honest against the exact same rule. `bounds` is the caller's already
## inset sampling rect (see tree_bounds), not the raw footprint: is_clear
## only knows about pond/tree OBSTACLES and has no idea an object has a
## drawn body of its own that the camera frame can cut through. Bounded
## retries rather than an unbounded loop, since a pathological
## footprint/seed combination could in principle leave very little clear
## room.
static func _position_clear_of_pond(result: Result, bounds: Rect2, rng: RandomNumberGenerator) -> Vector2:
	for attempt in 30:
		var candidate := Vector2(
			rng.randf_range(bounds.position.x, bounds.end.x),
			rng.randf_range(bounds.position.y, bounds.end.y)
		)
		if result.is_clear(candidate):
			return candidate
	# The bounds' own centre, not Vector2.ZERO: the old fallback put the
	# trunk foot at the footprint's corner, i.e. three quarters of the tree
	# outside the frame -- the worst possible answer to "no clear spot
	# found". The centre is always fully in frame, and worst case overlaps
	# the pond, which reads far better than a tree sliced in half by the edge.
	return bounds.get_center()
