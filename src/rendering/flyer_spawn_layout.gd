extends RefCounted

const Courtship = preload("res://src/gameplay/courtship.gd")
const GroundSlide = preload("res://src/gameplay/ground_slide.gd")

## Where a chunk's flyers are PUT, and what species they are (see
## docs/concept/ecosystem_dynamics.md's "Two butterflies meeting").
##
## Pure and engine-free: positions and species names, no nodes. Extracted out
## of AmbientFlyerRenderer._spawn_species so the encounter geometry could be
## MEASURED over hundreds of real chunks without building a single sprite --
## see test_flyer_spawn_layout.gd, which is where the numbers below come from.
##
## ## Why this exists: courtship was geometrically starved
##
## Courtship was built, wired and tested, and the player still never saw it.
## The reason was arithmetic, not logic. A chunk's 2-4 butterflies were placed
## by ranking every one of its 32x32 cells by a hash and taking the top few --
## effectively uniform over 512x512 px -- while two butterflies can only
## notice each other inside Courtship.NOTICE_RADIUS_PX, tethered within
## AmbientFlyerRenderer.BUTTERFLY_RADIUS of their own spawn point. Measured
## over 500 real German chunks, a same-species pair that could EVER meet
## existed in 6.6% of them; one close enough to meet without either flyer
## going anywhere, in 1.0%. The behaviour was unreachable in ~19 chunks out
## of 20 before any other gate applied.
##
## ## What replaced it, and why this shape and not a bigger radius
##
## Butterflies genuinely CONGREGATE. They gather at a stand of nectar
## flowers, at a damp patch (mud-puddling clubs, where dozens crowd onto a
## square metre of wet ground), and at landmarks (hilltopping/lekking). A
## meadow with its butterflies spread evenly across it is the unrealistic
## picture; a meadow with a knot of them at the good spot and empty grass
## elsewhere is the real one. So a chunk's true butterflies are now ONE loose
## aggregation.
##
## That was chosen over simply widening Courtship.NOTICE_RADIUS_PX, which is
## the crudest lever available: the notice radius is a claim about a
## butterfly's eyesight (see SpiralFlight.NOTICE_RADIUS_M for the real
## figure), and inflating it to paper over a spawn-distribution problem would
## have made every OTHER distance in the system lie too.
##
## Bees and birds keep the old scatter, on purpose: a honeybee commutes from
## a hive and works a whole meadow (see PollinatorForaging.FORAGE_SEARCH_TILES
## and GroundForageBehavior's own note about that), and songbirds hold
## territories rather than clubs. Only the butterflies club up.

## World pixels per real metre -- this project's one yardstick (see
## GroundSlide.PX_PER_METER).
const PX_PER_METER := GroundSlide.PX_PER_METER

## How wide an aggregation is.
##
## DERIVED, not chosen: an aggregation whose members cannot reach each other
## is not an aggregation. At this radius the two furthest-apart members of a
## club are exactly Courtship.NOTICE_RADIUS_PX apart -- within noticing
## distance of one another with neither flyer having to move off its own home
## point at all, which is the difference between "they could meet in
## principle" and "they meet".
##
## The real-world check is that the number it lands on is the size a butterfly
## aggregation actually has: about 3 m across, which is a mud-puddling club or
## a single good stand of nectar flowers. Both halves are pinned by
## test_the_aggregation_is_the_size_of_a_real_butterfly_aggregation.
const AGGREGATION_RADIUS_PX := Courtship.NOTICE_RADIUS_PX * 0.5
const AGGREGATION_RADIUS_M := AGGREGATION_RADIUS_PX / PX_PER_METER

## Share of a meadow's butterflies that are a stray of some other species.
##
## A pair can only court its own kind, so drawing each individual
## independently from the pool made same-species neighbours a coin flip even
## once they could reach each other. Real meadows are not one-of-each: a
## species is present because its larval host plant grows there, one female
## lays dozens of eggs on one stand, and what emerges is a local cohort. A
## meadow is therefore mostly one kind -- but not purely one kind, because
## butterflies also wander in from next door, and a meadow that could only
## ever hold one species would be a duller thing than the real one.
const STRAY_SHARE := 0.25


## The per-chunk count roll: a guaranteed min..max, never an independent
## per-cell probability that could plausibly land on zero (see
## AmbientFlyerRenderer's own note, and FishRenderer.target_count).
static func wanted_count(
	chunk_origin: Vector2i, salt: String, min_count: int, max_count: int, cell_total: int
) -> int:
	var count_range := maxi(1, max_count - min_count + 1)
	var count_roll := absi(
		hash("%d_%d_%s_count" % [chunk_origin.x, chunk_origin.y, salt])
	) % count_range
	return clampi(min_count + count_roll, 0, mini(max_count, cell_total))


## `wanted` cells of this chunk, ranked by a per-cell hash so the chosen
## subset reads as scattered rather than clustered in raster order (the same
## technique as FishRenderer._spawn_target_count). This is what bees and
## birds still get.
static func scattered_cells(
	chunk_origin: Vector2i, width: int, height: int, salt: String, wanted: int
) -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	for y in height:
		var global_y := chunk_origin.y + y
		for x in width:
			candidates.append(Vector2i(chunk_origin.x + x, global_y))
	candidates.sort_custom(
		func(a, b): return _spawn_rank(a.x, a.y, salt) < _spawn_rank(b.x, b.y, salt)
	)
	var chosen: Array[Vector2i] = []
	for i in mini(wanted, candidates.size()):
		chosen.append(candidates[i])
	return chosen


static func _spawn_rank(global_x: int, global_y: int, salt: String) -> float:
	return float(absi(hash("%d_%d_%s" % [global_x, global_y, salt])) % 10000) / 10000.0


## The species of a flyer placed on a given cell, drawn independently per
## cell. Still what bees and birds use -- a hive's foragers are all one
## species anyway, and two sparrows are two sparrows.
static func species_at_cell(pool: Array[String], cell: Vector2i, salt: String) -> String:
	if pool.is_empty():
		return ""
	var seed_value := absi(hash("%d_%d_%s_species" % [cell.x, cell.y, salt]))
	return pool[seed_value % pool.size()]


## Where this chunk's butterflies club up: one point per chunk, kept a full
## AGGREGATION_RADIUS_PX inside the chunk's own edges.
##
## Inside its own chunk, and not merely mostly: a chunk's flyers are freed
## with the chunk, so a club that spilled over the boundary would put
## butterflies in a neighbour's airspace and then take them away again when
## the wrong chunk unloaded.
##
## Hash-placed rather than steered onto the chunk's actual flowers, which
## would be the obvious refinement and is deliberately not done here: the
## renderer does not know where the blooms are at spawn time, and the flyers
## find them for themselves within seconds anyway (see AmbientFlyerMarker's
## `_origin` relocation, which re-centres a pollinator's territory on ground
## that actually feeds it).
static func aggregation_site(
	chunk_origin: Vector2i, width: int, height: int, tile_size: int, salt: String
) -> Vector2:
	var chunk_px := Vector2(width, height) * float(tile_size)
	var margin := minf(AGGREGATION_RADIUS_PX, minf(chunk_px.x, chunk_px.y) * 0.5)
	var span := chunk_px - Vector2(margin, margin) * 2.0
	var corner := Vector2(chunk_origin) * float(tile_size)
	return corner + Vector2(margin, margin) + Vector2(
		span.x * _unit_hash("%d_%d_%s_site_x" % [chunk_origin.x, chunk_origin.y, salt]),
		span.y * _unit_hash("%d_%d_%s_site_y" % [chunk_origin.x, chunk_origin.y, salt])
	)


## `wanted` spawn points, all inside this chunk's one aggregation.
static func aggregated_positions(
	chunk_origin: Vector2i, width: int, height: int, tile_size: int, salt: String, wanted: int
) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if wanted <= 0:
		return out
	var site := aggregation_site(chunk_origin, width, height, tile_size, salt)
	for i in wanted:
		out.append(site + _member_offset(chunk_origin, salt, i))
	return out


## One member's offset from the club's centre. Uniform over the DISC (hence
## the square root on the radius, not the radius itself) -- without it every
## club would be a ring with a hole in the middle, which is a distribution
## nothing in nature has.
static func _member_offset(chunk_origin: Vector2i, salt: String, member_index: int) -> Vector2:
	var key := "%d_%d_%s_%d" % [chunk_origin.x, chunk_origin.y, salt, member_index]
	var angle := _unit_hash(key + "_angle") * TAU
	var radius := AGGREGATION_RADIUS_PX * sqrt(_unit_hash(key + "_radius"))
	return Vector2.from_angle(angle) * radius


## Which species one member of this chunk's club is: the chunk's DOMINANT
## species, or occasionally a stray of another kind (see STRAY_SHARE).
static func aggregation_species(
	pool: Array[String], chunk_origin: Vector2i, salt: String, member_index: int
) -> String:
	if pool.is_empty():
		return ""
	var dominant_index := absi(
		hash("%d_%d_%s_dominant" % [chunk_origin.x, chunk_origin.y, salt])
	) % pool.size()
	var dominant: String = pool[dominant_index]
	if pool.size() == 1:
		return dominant
	var key := "%d_%d_%s_%d_stray" % [chunk_origin.x, chunk_origin.y, salt, member_index]
	if _unit_hash(key) >= STRAY_SHARE:
		return dominant
	var others: Array[String] = []
	for species in pool:
		if species != dominant:
			others.append(species)
	return others[absi(hash(key + "_which")) % others.size()]


## A stable 0..1 from a key -- the same "hash, modulo, divide" the rest of
## this file's determinism is built on.
static func _unit_hash(key: String) -> float:
	return float(absi(hash(key)) % 10000) / 10000.0
