extends GutTest

## scenes/world.tscn's ground-effects TileMapLayers (WaterFx/RiverFlowFx/
## SnowFx/HillshadeFx) all share z_index=-1 (see test_earth_chunk_manager.gd's
## own "ground decor gets its own non-y-sorted layer" comment block), so
## Godot's 2D draw order between them is decided purely by scene-tree
## SIBLING ORDER: a later sibling at the same z_index draws on top.
##
## Reported: "the flow animations don't work" -- RiverFlowShader's
## translucent (streak_color=Color(0.75,0.88,1.0), max alpha 0.35, see
## river_flow_shader.gd) streaks were invisible in live play, painted over a
## dark, grooved, tile-boundary-aligned static pattern instead. That pattern
## is HillshadeShader's own overlay: a near-black tint (up to alpha 0.55,
## see hillshade_shader.gd's MAX_SHADOW_ALPHA) painted over EVERY loaded
## cell -- including river cells, since _paint_hillshade_overlay never
## checks EarthChunkGenerator.is_river_at_global the way
## _paint_river_flow_overlay does -- pinned already by
## test_hillshade_overlay_paints_a_real_tile_for_every_loaded_cell in
## test_earth_chunk_manager.gd. Because RiverFlowFx was inserted as a
## sibling BEFORE HillshadeFx in scenes/world.tscn, HillshadeFx's darker,
## higher-alpha overlay painted on top of and visually swamped
## RiverFlowFx's paler, more translucent streaks on every river tile.
func test_river_flow_layer_is_a_later_sibling_than_hillshade_layer():
	var world_scene: PackedScene = load("res://scenes/world.tscn")
	var world: Node = world_scene.instantiate()
	var river_flow_index: int = world.get_node("RiverFlowFx").get_index()
	var hillshade_index: int = world.get_node("HillshadeFx").get_index()
	assert_gt(
		river_flow_index, hillshade_index,
		"RiverFlowFx must be a LATER sibling than HillshadeFx (both z_index=-1) so its " +
		"streaks draw ON TOP of hillshade's darker overlay instead of being occluded by it"
	)
	world.free()


## Same reasoning against SnowFx: it too shares z_index=-1 and, per
## world.tscn's original ordering, was also a later sibling than
## RiverFlowFx (drawn on top of it). Whatever SnowFx paints on a snowed
## river tile must not be able to occlude the flow streaks either.
func test_river_flow_layer_is_a_later_sibling_than_snow_layer():
	var world_scene: PackedScene = load("res://scenes/world.tscn")
	var world: Node = world_scene.instantiate()
	var river_flow_index: int = world.get_node("RiverFlowFx").get_index()
	var snow_index: int = world.get_node("SnowFx").get_index()
	assert_gt(
		river_flow_index, snow_index,
		"RiverFlowFx must be a LATER sibling than SnowFx (both z_index=-1) so its streaks " +
		"draw ON TOP of anything SnowFx paints instead of being occluded by it"
	)
	world.free()
