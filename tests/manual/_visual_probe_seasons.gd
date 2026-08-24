extends Node2D

## Throwaway probe: captures one season's landscape view for README
## screenshots. Run once per season (see OS.get_cmdline_user_args) --
## deliberately NOT a multi-season loop in one process: constructing a
## second EarthChunkManager after freeing the first's nodes crashed the
## engine silently (no GDScript-level error, just a clean-looking exit) --
## not investigated further since one-process-per-season sidesteps it
## entirely and matches the already-proven single-shot probe shape.
## Not part of the game, not kept in the tree after use (matches this
## project's "probe scripts deleted after use" convention).

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")

const OUT_DIR := "C:/Users/morrossl/AppData/Local/Temp/claude/C--Users-morrossl-Documents-Private-aleph-alfa--claude-worktrees-vigilant-burnell-9704bd/fecac872-c626-440f-8120-7ad060118fe9/scratchpad/"

# Middle of each season's own quarter of the year, so nothing lands on a
# transition edge.
const SEASON_AGES := {
	"spring": SeasonCycle.SECONDS_PER_YEAR * 0.125,
	"summer": SeasonCycle.SECONDS_PER_YEAR * 0.375,
	"autumn": SeasonCycle.SECONDS_PER_YEAR * 0.625,
	"winter": SeasonCycle.SECONDS_PER_YEAR * 0.875,
}

# Same tile the spring run's own candidate scan already picked (2361 trees) --
# reused for every season so all four screenshots show the SAME landscape,
# not four different ones. Tree/terrain PLACEMENT is deterministic and does
# not depend on season, only appearance does.
const CHOSEN_TILE := Vector2i(21438, 4120)


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var season_name: String = args[0] if args.size() > 0 else "spring"
	if not SEASON_AGES.has(season_name):
		push_error("Unknown season: %s" % season_name)
		get_tree().quit(1)
		return

	var tile_map_layer := TileMapLayer.new()
	add_child(tile_map_layer)
	var entities_parent := Node2D.new()
	add_child(entities_parent)
	var creatures_parent := Node2D.new()
	add_child(creatures_parent)

	var manager := EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	manager.set_world_age_seconds(SEASON_AGES[season_name])
	# Syncs _tree_renderer.season BEFORE any tree spawns via update() below
	# (see earth_chunk_manager.gd's _sync_tree_season -- only reached through
	# step_fruiting, not automatically on update()).
	manager.step_fruiting(EarthChunkManager.FRUITING_INTERVAL, Vector2(CHOSEN_TILE) * TerrainRenderer.TILE_SIZE)
	manager.update(CHOSEN_TILE)
	manager.step_tall_grass(0.0)

	var cam := Camera2D.new()
	cam.position = Vector2(CHOSEN_TILE.x * TerrainRenderer.TILE_SIZE, CHOSEN_TILE.y * TerrainRenderer.TILE_SIZE)
	cam.zoom = Vector2(1.4, 1.4)
	cam.enabled = true
	add_child(cam)
	cam.make_current()

	print("season=%s ready, waiting for render" % season_name)
	await get_tree().process_frame
	for i in 12:
		await get_tree().process_frame

	var img := get_viewport().get_texture().get_image()
	var out_path := OUT_DIR + "season_%s.png" % season_name
	img.save_png(out_path)
	print("saved %s" % out_path)
	get_tree().quit()
