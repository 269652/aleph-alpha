extends SceneTree

## Dev tool: scans real terrain slope/aspect along curated rivers' courses
## and reports the real hillshade alpha that would paint each riverbank
## tile, at a range of real, plausible sun elevations -- answering "how dark
## does hillshade actually get near a real riverbank, and why" without
## needing a live screenshot.
## Usage: godot --headless -s tools/scan_riverbank_hillshade.gd -- [river_name]
## With no river_name, scans every curated river and reports the single
## worst tile found across all of them.

const EarthElevationSource = preload("res://src/world/earth_elevation_source.gd")
const TerrainRelief = preload("res://src/world/terrain_relief.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const RiverCatalog = preload("res://src/world/river_catalog.gd")
const HillshadeShader = preload("res://src/rendering/hillshade_shader.gd")
const ProceduralHillshadeSprite = preload("res://src/rendering/procedural_hillshade_sprite.gd")

const WORLD_WIDTH_TILES := 39960
const WORLD_HEIGHT_TILES := 19980

var _elevation := EarthElevationSource.new()
var _relief := TerrainRelief.new()
var _geo := GeoCoordinates.new()


func _initialize():
	var args := OS.get_cmdline_user_args()
	var rivers := RiverCatalog.new()
	var polylines := rivers.tile_polylines(WORLD_WIDTH_TILES, WORLD_HEIGHT_TILES)

	var river_names: Array = args.duplicate() if args.size() > 0 else polylines.keys()

	var sun_elevations: Array[float] = [1.0, 2.0, 3.0, 5.0, 8.0, 10.0, 15.0, 20.0, 35.0, 50.0, 90.0]
	var global_worst := {}
	for sun_elev in sun_elevations:
		global_worst[sun_elev] = {"alpha": -1.0}

	for river_name in river_names:
		if not polylines.has(river_name):
			print("Unknown river: %s" % river_name)
			continue
		var points: Array = polylines[river_name]
		var river_worst := {}
		for sun_elev in sun_elevations:
			river_worst[sun_elev] = {"alpha": -1.0}
		var max_slope_seen := 0.0
		var max_slope_where := Vector2.ZERO
		var sample_count := 0

		var offsets: Array[float] = [-8.0, -5.0, -3.0, -2.0, -1.0, 0.0, 1.0, 2.0, 3.0, 5.0, 8.0]
		var steps_per_segment := 8

		for i in range(points.size() - 1):
			var a: Vector2 = points[i]
			var b: Vector2 = points[i + 1]
			var tangent: Vector2 = b - a
			if tangent.length() > 0.0001:
				tangent = tangent.normalized()
			else:
				tangent = Vector2(1, 0)
			var perp := Vector2(-tangent.y, tangent.x)

			for step in steps_per_segment:
				var t := float(step) / float(steps_per_segment)
				var p: Vector2 = a.lerp(b, t)
				for offset in offsets:
					var tile: Vector2 = p + perp * offset
					var gx := int(round(tile.x))
					var gy := int(round(tile.y))
					var lat := _geo.latitude_for_tile(gy, WORLD_HEIGHT_TILES)
					var lon := _geo.longitude_for_tile(gx, WORLD_WIDTH_TILES)
					var gradient := _relief.gradient_at(_elevation, lat, lon)
					var slope := _relief.slope_degrees_from_gradient(gradient.x, gradient.y)
					var aspect := _relief.aspect_degrees_from_gradient(gradient.x, gradient.y)
					sample_count += 1

					if slope > max_slope_seen:
						max_slope_seen = slope
						max_slope_where = Vector2(lat, lon)

					for sun_elev in sun_elevations:
						var alpha: float = HillshadeShader.shadow_alpha(slope, aspect, sun_elev, 180.0)
						if alpha > river_worst[sun_elev]["alpha"]:
							river_worst[sun_elev] = {
								"alpha": alpha, "slope": slope, "aspect": aspect,
								"lat": lat, "lon": lon, "gx": gx, "gy": gy
							}
						if alpha > global_worst[sun_elev]["alpha"]:
							global_worst[sun_elev] = river_worst[sun_elev].duplicate()
							global_worst[sun_elev]["river"] = river_name

		print("--- %s: %d samples, max slope %.2f deg at (%.5f, %.5f) ---" % [
			river_name, sample_count, max_slope_seen, max_slope_where.x, max_slope_where.y
		])
		for sun_elev in sun_elevations:
			var w = river_worst[sun_elev]
			if w["alpha"] < 0.0:
				continue
			print("  sun_elev=%.0f -> alpha=%.3f (slope=%.1f, aspect=%.1f) at (%.5f, %.5f)" % [
				sun_elev, w["alpha"], w["slope"], w["aspect"], w["lat"], w["lon"]
			])

	print("")
	print("=== WORST ACROSS ALL SCANNED RIVERS ===")
	for sun_elev in sun_elevations:
		var w = global_worst[sun_elev]
		if w["alpha"] < 0.0:
			continue
		print("sun_elev=%.0f -> alpha=%.3f (slope=%.1f, aspect=%.1f) river=%s tile=(%d,%d) latlon=(%.5f,%.5f)" % [
			sun_elev, w["alpha"], w["slope"], w["aspect"], w["river"], w["gx"], w["gy"], w["lat"], w["lon"]
		])

	# For the single worst case at a realistic sun elevation (35 deg --
	# mid-morning/afternoon in spring), print a transect of slope BINS
	# across neighbouring tiles, to see whether the quantized atlas would
	# actually show a smooth gradient or a hard-edged blob there.
	for probe_elev in [2.0, 35.0]:
		var worst = global_worst[probe_elev]
		if not worst.has("gx"):
			continue
		print("")
		print("=== alpha transect (real, unquantized) around worst %.0f-deg-sun tile (%d,%d) ===" % [probe_elev, worst["gx"], worst["gy"]])
		for dy in range(-4, 5):
			var row := ""
			for dx in range(-4, 5):
				var gx: int = worst["gx"] + dx
				var gy: int = worst["gy"] + dy
				var lat := _geo.latitude_for_tile(gy, WORLD_HEIGHT_TILES)
				var lon := _geo.longitude_for_tile(gx, WORLD_WIDTH_TILES)
				var gradient := _relief.gradient_at(_elevation, lat, lon)
				var slope := _relief.slope_degrees_from_gradient(gradient.x, gradient.y)
				var aspect := _relief.aspect_degrees_from_gradient(gradient.x, gradient.y)
				var alpha: float = HillshadeShader.shadow_alpha(slope, aspect, probe_elev, 180.0)
				row += "%4.2f " % alpha
			print(row)

		print("--- same transect, through the QUANTIZED atlas bins actually painted in-game ---")
		for dy in range(-4, 5):
			var row := ""
			for dx in range(-4, 5):
				var gx: int = worst["gx"] + dx
				var gy: int = worst["gy"] + dy
				var lat := _geo.latitude_for_tile(gy, WORLD_HEIGHT_TILES)
				var lon := _geo.longitude_for_tile(gx, WORLD_WIDTH_TILES)
				var gradient := _relief.gradient_at(_elevation, lat, lon)
				var slope := _relief.slope_degrees_from_gradient(gradient.x, gradient.y)
				var aspect := _relief.aspect_degrees_from_gradient(gradient.x, gradient.y)
				var slope_bin := ProceduralHillshadeSprite.slope_bin_for(slope)
				var aspect_bin := ProceduralHillshadeSprite.aspect_bin_for(aspect) if slope > 0.0 else 0
				var baked_slope := ProceduralHillshadeSprite.slope_for_bin(slope_bin)
				var baked_aspect := ProceduralHillshadeSprite.aspect_for_bin(aspect_bin) if slope > 0.0 else -1.0
				var alpha: float = HillshadeShader.shadow_alpha(baked_slope, baked_aspect, probe_elev, 180.0)
				row += "%4.2f " % alpha
			print(row)

	quit()
