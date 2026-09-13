extends SceneTree

## Dev tool: searches for a real tile satisfying BOTH halves of
## test_a_river_reach_can_be_both_fish_water_and_under_the_flow_overlay --
## interior ocean biome (WaterAreaSurvey.is_interior_water's rule: the tile
## and all 8 neighbours are "ocean") AND within RiverCatalog's painted apron
## (RIVER_HALF_WIDTH_TILES + RIVER_BANK_APRON_TILES) of a curated river's
## course (nearest_river_at's distance_tiles) -- because the original pinned
## fixture (Vector2i(20542, 4242), found on the Rhine) no longer reads as
## ocean biome there.
##
## RESULT (2026-09-13): zero hits. `all` mode walks every curated river's
## entire smoothed course (not sampled points -- the whole corridor) and
## finds no qualifying tile anywhere; the nearest actual ocean-biome tile to
## the old fixture is 500+ tiles away (`nearest_ocean` mode). The test now
## uses a synthetic hydrology bake instead (see
## test_fish_renderer.gd's _synthetic_sea_field()) -- kept here in case the
## real bake or elevation source changes again and a natural fixture becomes
## findable, or for the same search over some other biome/course pair.
##
## Usage: godot --headless --path . -s tools/probe_fish_river_fixture.gd -- <mode> [arg]
##   box [radius]       -- sweep a (2*radius+1) box around the ORIGINAL fixture (default radius 80)
##   river <Name>        -- walk that one curated river's whole smoothed corridor
##   all                 -- walk every curated river's corridor
##   nearest_ocean [x y] [max_radius] [stride] -- coarse scan for the nearest plain-ocean tile
##   diag [x y]          -- print biome/elevation/hydrology/river-distance detail for one tile

const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const RiverCatalog = preload("res://src/world/river_catalog.gd")

const ORIGINAL_FIXTURE := Vector2i(20542, 4242)

const _NEIGHBOR_STEPS := [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]

## Wide enough to comfortably bracket the apron (2.75 tiles today) plus the
## interior-water neighbour ring, without blowing up the per-step cost.
const _PERP_MARGIN := 6
const _STEP_TILES := 1.0

var generator: EarthChunkGenerator
var apron: float


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := "box"
	if args.size() > 0:
		mode = args[0]

	generator = EarthChunkGenerator.new()
	apron = RiverCatalog.RIVER_HALF_WIDTH_TILES + RiverCatalog.RIVER_BANK_APRON_TILES
	print("apron = %.2f tiles; hydrology bake loaded: %s" % [apron, generator.has_hydrology()])

	match mode:
		"box":
			var radius := 80
			if args.size() > 1 and args[1].is_valid_int():
				radius = int(args[1])
			_sweep_box(ORIGINAL_FIXTURE, radius)
		"river":
			if args.size() < 2:
				print("river mode needs a name, e.g. -- river Rhine")
			else:
				_walk_river(args[1])
		"all":
			for river_name in RiverCatalog.RIVERS:
				_walk_river(river_name)
		"nearest_ocean":
			var x2 := ORIGINAL_FIXTURE.x
			var y2 := ORIGINAL_FIXTURE.y
			var max_radius := 2000
			var stride := 16
			if args.size() > 1 and args[1].is_valid_int():
				x2 = int(args[1])
			if args.size() > 2 and args[2].is_valid_int():
				y2 = int(args[2])
			if args.size() > 3 and args[3].is_valid_int():
				max_radius = int(args[3])
			if args.size() > 4 and args[4].is_valid_int():
				stride = int(args[4])
			_nearest_ocean(Vector2i(x2, y2), max_radius, stride)
		"diag":
			var x := ORIGINAL_FIXTURE.x
			var y := ORIGINAL_FIXTURE.y
			if args.size() > 2 and args[1].is_valid_int() and args[2].is_valid_int():
				x = int(args[1])
				y = int(args[2])
			_diag(x, y)
		_:
			print("unknown mode: %s" % mode)
	quit()


func _diag(x: int, y: int) -> void:
	var biome := generator.biome_at_global(x, y)
	var elevation := generator.elevation_at_global(x, y)
	var macro := generator.macro_elevation_at_global(x, y)
	var probe := generator.hydrology_at_global(x, y)
	var nearest := generator.river_catalog().nearest_river_at(
		x, y, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	print("(%d, %d): biome=%s elevation=%.6f macro=%.6f sea_level=%.6f" % [
		x, y, biome, elevation, macro, EarthChunkGenerator.EARTH_SEA_LEVEL
	])
	print("  hydrology probe: %s" % str(probe))
	print("  nearest river: %s  distance=%.3f  (apron=%.2f)  course_fraction=%.4f" % [
		nearest.name, nearest.distance_tiles, apron, nearest.course_fraction
	])


func _is_ocean(x: int, y: int) -> bool:
	return generator.biome_at_global(x, y) == "ocean"


func _is_interior_ocean(x: int, y: int) -> bool:
	if not _is_ocean(x, y):
		return false
	for step in _NEIGHBOR_STEPS:
		if not _is_ocean(x + step.x, y + step.y):
			return false
	return true


func _check_and_report(x: int, y: int, found: Dictionary) -> bool:
	var key := Vector2i(x, y)
	if found.has(key):
		return false
	if not _is_interior_ocean(x, y):
		return false
	var nearest := generator.river_catalog().nearest_river_at(
		x, y, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	if nearest.distance_tiles > apron:
		return false
	found[key] = true
	print("HIT %s  river=%s  distance=%.3f (apron %.2f)  course_fraction=%.4f" % [
		key, nearest.name, nearest.distance_tiles, apron, nearest.course_fraction
	])
	return true


## Coarse strided box scan for the closest-ish plain "ocean"-biome tile to
## `center` -- no interior/river-apron requirement, just "does ocean exist
## at all anywhere near here, and roughly how far." Trades precision (hits
## are only found to within `stride` tiles) for being able to cover a large
## radius at all: cost is O((radius/stride)^2), not O(radius^2).
func _nearest_ocean(center: Vector2i, max_radius: int, stride: int = 16) -> void:
	print("Coarse scan (stride %d) out to radius %d around %s for ANY ocean-biome tile ..." % [stride, max_radius, center])
	var best_dist := INF
	var best_tile := Vector2i.ZERO
	var hits := 0
	for dy in range(-max_radius, max_radius + 1, stride):
		for dx in range(-max_radius, max_radius + 1, stride):
			var x := center.x + dx
			var y := center.y + dy
			if _is_ocean(x, y):
				hits += 1
				var d := Vector2(dx, dy).length()
				if d < best_dist:
					best_dist = d
					best_tile = Vector2i(x, y)
	if hits == 0:
		print("no ocean tile found within radius %d (stride %d) -- ocean is farther than that, at this resolution" % [max_radius, stride])
	else:
		print("closest-found ocean tile (to within stride %d): %s, ~%.0f tiles away (%d total hits at this stride)" % [stride, best_tile, best_dist, hits])


func _sweep_box(center: Vector2i, radius: int) -> void:
	print("Sweeping %dx%d box around %s ..." % [radius * 2 + 1, radius * 2 + 1, center])
	var found := {}
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			_check_and_report(center.x + dx, center.y + dy, found)
	print("box done: %d hits" % found.size())


## Walk river_name's whole smoothed corridor: every segment, stepped finely
## along its length, with a perpendicular sweep _PERP_MARGIN tiles either
## side of the centreline.
func _walk_river(river_name: String) -> void:
	var polylines := RiverCatalog.tile_polylines(
		EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	if not polylines.has(river_name):
		print("unknown river: %s" % river_name)
		return
	var points: Array = polylines[river_name]
	var total_length := 0.0
	for i in range(points.size() - 1):
		total_length += points[i].distance_to(points[i + 1])
	print("%s: %d smoothed course points, ~%.1f tiles long" % [river_name, points.size(), total_length])

	var found := {}
	var checked := 0
	for i in range(points.size() - 1):
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var seg := b - a
		var length := seg.length()
		if length < 0.0001:
			continue
		var direction := seg / length
		var normal := Vector2(-direction.y, direction.x)
		var steps := int(ceil(length / _STEP_TILES))
		for s in range(steps + 1):
			var t := float(s) / float(steps)
			var point := a.lerp(b, t)
			for perp in range(-_PERP_MARGIN, _PERP_MARGIN + 1):
				var candidate := point + normal * float(perp)
				var cx := int(round(candidate.x))
				var cy := int(round(candidate.y))
				checked += 1
				_check_and_report(cx, cy, found)
	print("%s: checked ~%d candidates, %d hits" % [river_name, checked, found.size()])
