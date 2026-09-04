extends SceneTree

## Dev tool: says what the hydrology field thinks one global tile is --
## river, lake, sea or dry -- plus the nearest CURATED river's distance.
##
## The two can disagree by design since the unified water surface began
## painting lakes and baked channels alongside curated rivers, so this is
## how to tell a stale test premise from a real stray paint.
##
## Usage: godot --headless --path . -s tools/probe_tile.gd -- x y [x y ...]

const HydrologyData = preload("res://src/world/hydrology_data.gd")
const HydrologyField = preload("res://src/world/hydrology_field.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const RiverCatalog = preload("res://src/world/river_catalog.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var data := HydrologyData.new()
	if not data.load_from(HydrologyData.DEFAULT_DIRECTORY):
		print("probe_tile: no bake at %s" % HydrologyData.DEFAULT_DIRECTORY)
		quit()
		return
	var field := HydrologyField.new(
		data, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	var catalog := RiverCatalog.new()

	var i := 0
	while i + 1 < args.size():
		var x := int(args[i])
		var y := int(args[i + 1])
		i += 2
		var probe: Dictionary = field.probe(x, y, 0.6)
		var curated: Dictionary = catalog.nearest_river_at(
			x, y, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
		)
		var geometry: Dictionary = field.nearest_channel_geometry(x, y)
		print("(%d, %d)" % [x, y])
		print("   hydrology kind : %s   sea=%s  lake_across=%.3f" % [
			probe.get("kind", "?"), str(probe.get("sea", false)),
			float(probe.get("lake_across", 0.0)),
		])
		print("   depth          : %.2f m   discharge=%.1f  half_width=%.2f" % [
			float(probe.get("depth_m", 0.0)), float(probe.get("discharge", 0.0)),
			float(probe.get("half_width_tiles", 0.0)),
		])
		print("   baked channel  : %s" % (
			"none in reach" if geometry.is_empty()
			else "%.2f tiles away, bearing %.1f" % [
				float(geometry["distance_tiles"]), float(geometry["course_bearing_deg"])
			]
		))
		print("   curated river  : %.2f tiles away" % float(curated.get("distance_tiles", -1.0)))
	quit()
