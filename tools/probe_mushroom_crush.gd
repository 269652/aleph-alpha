extends SceneTree

## Dev tool: does a step on a wild mushroom actually crush it?
##
## Reported live: "Mushroom crush sounds are gone". The sound is played in
## exactly one place (World._client_process) and only inside the branch
## `if _chunk_manager.crush_mushroom_at(...)`, so "no sound" has three
## possible causes that reasoning cannot tell apart:
##   1. no mushrooms are fruiting where the player walks,
##   2. crush_mushroom_at returns false when it should return true,
##   3. the audio itself is broken.
## (3) is already covered by tests/unit/test_interaction_sfx_player.gd, which
## loads and plays the real clip. This probe measures (1) and (2) against real
## generated chunks rather than a fixture.
##
## Usage: godot --headless --path . -s tools/probe_mushroom_crush.gd
##        [-- <chunk_x> <chunk_y> ...]

const CrushMechanic = preload("res://src/world/crush_mechanic.gd")
const PebbleDispersion = preload("res://src/rendering/pebble_dispersion.gd")

## Same graph problem tools/probe_settlement_history_cost.gd records: this
## script's constants resolve while the autoloads are still coming up, and
## preloading the deepest-graph script in the project hands back a bare
## GDScript whose `new` does not exist yet.
var EarthChunkManager

## Ordinary countryside, away from the curated river courses -- the ground a
## player actually walks over.
const CHUNK_COORDS := [Vector2i(47, 47), Vector2i(48, 47), Vector2i(47, 48)]

## A walking adult: World._player_step_momentum_kg_m_s is the live mass times
## PebbleDispersion.FOOTSTEP_SPEED_MPS.
const PLAYER_MASS_KG := 70.0


func _initialize() -> void:
	EarthChunkManager = load("res://src/world/earth_chunk_manager.gd")
	var coords: Array = CHUNK_COORDS
	var args := OS.get_cmdline_user_args()
	if args.size() >= 2:
		coords = []
		for i in range(0, args.size() - 1, 2):
			coords.append(Vector2i(int(args[i]), int(args[i + 1])))

	var momentum := PLAYER_MASS_KG * PebbleDispersion.FOOTSTEP_SPEED_MPS
	print("step momentum %.1f kg m/s, threshold %.1f -> is_crushed_by=%s" % [
		momentum, CrushMechanic.CRUSH_MOMENTUM_THRESHOLD_KG_M_S,
		CrushMechanic.is_crushed_by(momentum),
	])
	print("%10s %8s %8s %9s %8s %8s" % [
		"chunk", "sites", "blocked", "fruiting", "crushed", "refused",
	])
	var total_fruiting := 0
	var total_crushed := 0
	for coord in coords:
		var measured := _measure(coord, momentum)
		total_fruiting += int(measured["fruiting"])
		total_crushed += int(measured["crushed"])
		print("%10s %8d %8d %9d %8d %8d" % [
			str(coord), measured["sites"], measured["blocked"], measured["fruiting"],
			measured["crushed"], measured["refused"],
		])
	print("TOTAL fruiting=%d crushed=%d" % [total_fruiting, total_crushed])
	if total_fruiting == 0:
		print("VERDICT: nothing to crush -- no mushroom is fruiting on this ground at all.")
	elif total_crushed == 0:
		print("VERDICT: mushrooms are there and crush_mushroom_at refuses every one.")
	else:
		print("VERDICT: stepping on a fruiting mushroom DOES crush it; the sound's own branch is reached.")
	quit()


## One chunk: how many mushrooms are standing, and how many of them a real
## player step actually crushes.
func _measure(chunk_coord: Vector2i, momentum: float) -> Dictionary:
	var layer := TileMapLayer.new()
	var entities := Node2D.new()
	var creatures := Node2D.new()
	var manager = EarthChunkManager.new(layer, entities, creatures)
	# update() is how a chunk really loads (the same call the tests use); it
	# takes the player's own global TILE, so a probe walks in the way the game
	# does rather than reaching for a private loader.
	var center_pixel := _chunk_center_pixel(chunk_coord)
	manager.update(chunk_coord * EarthChunkManager.CHUNK_SIZE
		+ Vector2i(EarthChunkManager.CHUNK_SIZE / 2, EarthChunkManager.CHUNK_SIZE / 2))

	# The sim itself, before any of the manager's own filtering -- so a chunk
	# with sites but no fruiting bodies reads differently from one the blocker
	# mask emptied outright.
	# Reaching into _mushroom_sims rather than adding a public accessor for a
	# probe's benefit: the question is what the sim was BUILT with, and no
	# shipping caller needs to ask that.
	var sim = manager._mushroom_sims.get(chunk_coord)
	var sites := -1  # -1 distinguishes "no sim at all" from "a sim with no sites"
	if sim != null:
		sites = sim.site_count()
	var blocked := _blocked_cells(manager, chunk_coord)
	if not manager.is_chunk_loaded(chunk_coord):
		print("  (chunk %s never loaded -- update() did not reach it)" % str(chunk_coord))

	var fruiting: Array = manager.mushrooms_near(center_pixel, 9999)
	var crushed := 0
	var refused := 0
	for entry in fruiting:
		if manager.crush_mushroom_at(entry["position"], momentum):
			crushed += 1
		else:
			refused += 1

	layer.free()
	entities.free()
	creatures.free()
	return {
		"sites": sites, "blocked": blocked,
		"fruiting": fruiting.size(), "crushed": crushed, "refused": refused,
	}


## How many of this chunk's cells the growth mask refuses, counted through the
## manager's own public predicate rather than through the mask it built.
func _blocked_cells(manager, chunk_coord: Vector2i) -> int:
	var chunk_size: int = EarthChunkManager.CHUNK_SIZE
	var blocked := 0
	for y in chunk_size:
		for x in chunk_size:
			var g := chunk_coord * chunk_size + Vector2i(x, y)
			if manager.is_water_at_global(g.x, g.y):
				blocked += 1
	return blocked


func _chunk_center_pixel(chunk_coord: Vector2i) -> Vector2:
	var TerrainRenderer = load("res://src/rendering/terrain_renderer.gd")
	var chunk_size: int = EarthChunkManager.CHUNK_SIZE
	var center_tile := chunk_coord * chunk_size + Vector2i(chunk_size / 2, chunk_size / 2)
	return Vector2(center_tile) * TerrainRenderer.TILE_SIZE
