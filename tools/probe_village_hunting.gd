extends SceneTree

## Does a village hunter ever actually have something to hunt?
##
## docs/concept/npc.md's "Work against the real world" section names its own
## limitation -- a villager can only take what is LOADED -- so the feature
## could be correctly wired and still never fire in play. This measures
## that against real chunks, real settlements and real spawned creatures
## near Berlin, the way probe_village_industry.gd measures whether a sawmill
## plot exists at all:
##
## 1. How many real hunter villagers a walk east of Berlin actually meets.
## 2. For each, whether real huntable quarry stands within
##    HuntableQuarry.SEARCH_RADIUS_PX of where that hunter works.
## 3. For one of them, how much real meat and hide reach the market over a
##    simulated stretch -- against what the old conjured drip would have
##    paid over the same stretch, so the two are comparable rather than
##    asserted.
##
## Two structural notes for the next probe that spawns real world nodes:
##
## - `_initialize`, not `_init`. A SceneTree script is constructed BEFORE
##   its `root` Window exists, so anything that adds nodes has to wait for
##   the main loop to start. (probe_village_industry.gd can use `_init`
##   because it only calls pure modules and never touches the tree.)
## - Everything heavy is `load()`ed at RUNTIME rather than `preload`ed. A
##   `-s` script is compiled before the project's autoloads are registered,
##   so preloading EarthChunkManager -- which references the WorldItemBus
##   singleton -- fails to compile with "Identifier not found". GUT does not
##   hit this because it loads its test scripts at runtime too.

const CHUNK_SIZE := 32
## How many chunk-widths east of Berlin to walk. Settlements are sparse
## (~1 in 30 habitable chunks), so this is sized to meet several rather
## than to be exhaustive.
const STEPS := 40
const SIMULATED_SECONDS := 240.0
const SLICE := 0.1

var _huntable_quarry
var _npc_production


func _initialize() -> void:
	var EarthChunkManager = load("res://src/world/earth_chunk_manager.gd")
	var EarthChunkGenerator = load("res://src/world/earth_chunk_generator.gd")
	var GeoCoordinates = load("res://src/world/geo_coordinates.gd")
	_huntable_quarry = load("res://src/gameplay/huntable_quarry.gd")
	_npc_production = load("res://src/world/npc_production.gd")

	var geo = GeoCoordinates.new()
	var berlin := Vector2i(
		geo.tile_for_longitude(13.405, EarthChunkGenerator.WORLD_WIDTH_TILES),
		geo.tile_for_latitude(52.52, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	)

	# ONE manager walked across the map, the way a player actually moves --
	# chunks load and evict incrementally around them. Far cheaper than a
	# fresh manager per sample, and a more honest picture of what is loaded
	# at any moment than a purpose-built snapshot would be.
	var tile_map_layer := TileMapLayer.new()
	var entities := Node2D.new()
	var creatures := Node2D.new()
	root.add_child(tile_map_layer)
	root.add_child(entities)
	root.add_child(creatures)
	var manager = EarthChunkManager.new(tile_map_layer, entities, creatures)

	var hunters_seen := {}
	var hunters_with_quarry := {}
	var distances: Array = []
	var best_hunter = null

	for step in STEPS:
		manager.update(berlin + Vector2i(step * CHUNK_SIZE, 0))
		for hunter in _hunters_in(manager):
			var key: int = hunter.identity.seed_value
			hunters_seen[key] = true
			var quarry = _huntable_quarry.nearest(
				root.get_tree().get_nodes_in_group(_huntable_quarry.QUARRY_GROUP_NAME),
				hunter.workspot_position
			)
			if quarry == null:
				continue
			if not hunters_with_quarry.has(key):
				distances.append(hunter.workspot_position.distance_to(quarry.position))
			hunters_with_quarry[key] = true
			if best_hunter == null:
				best_hunter = hunter

	print("-- real huntable quarry near a real village hunter, walking east from Berlin --")
	print("chunk-widths walked:                     %d" % STEPS)
	print("distinct hunter villagers met:           %d" % hunters_seen.size())
	if hunters_seen.size() > 0:
		print(
			"hunters that ever had quarry in reach:   %d (%.1f%%)"
			% [
				hunters_with_quarry.size(),
				100.0 * float(hunters_with_quarry.size()) / float(hunters_seen.size()),
			]
		)
	if not distances.is_empty():
		distances.sort()
		print(
			"distance to nearest quarry (px):         min %.0f  median %.0f  max %.0f (reach %.0f)"
			% [
				distances[0],
				distances[distances.size() / 2],
				distances[distances.size() - 1],
				_huntable_quarry.SEARCH_RADIUS_PX,
			]
		)

	if best_hunter != null and is_instance_valid(best_hunter):
		_measure_one_hunt(best_hunter, manager)
	else:
		print("no hunter with quarry in reach survived to be simulated")
	quit()


## Runs one real hunter forward and reports what the village actually got,
## against what the old conjured drip would have paid over the same stretch.
func _measure_one_hunt(hunter, manager) -> void:
	var market = hunter.economy.market
	var meat_before: float = market.stock.get("meat", 0.0)
	var hide_before: float = market.stock.get("hide", 0.0)
	var creatures_before := root.get_tree().get_nodes_in_group(_huntable_quarry.QUARRY_GROUP_NAME).size()
	var headcount: float = manager.herbivore_population_near(hunter.workspot_position)

	var elapsed := 0.0
	while elapsed < SIMULATED_SECONDS:
		hunter._process(SLICE)
		elapsed += SLICE

	var creatures_after := root.get_tree().get_nodes_in_group(_huntable_quarry.QUARRY_GROUP_NAME).size()
	var drip: float = _npc_production.PRODUCTION_RATE_PER_SECOND * headcount * SIMULATED_SECONDS
	print("")
	print("-- one real hunter, %.0f simulated seconds --" % SIMULATED_SECONDS)
	print("regional herbivore headcount:            %.3f" % headcount)
	print("loaded creatures before / after:         %d / %d" % [creatures_before, creatures_after])
	print("real meat into the market:               %.2f" % (market.stock.get("meat", 0.0) - meat_before))
	print("real hide into the market:               %.2f" % (market.stock.get("hide", 0.0) - hide_before))
	print("what the old conjured drip would pay:    %.2f" % drip)


## Every hunter villager in every village this manager currently holds.
## Duck-typed rather than `is NpcMarker`, since NpcMarker is loaded at
## runtime here (see the file doc comment) and is not a static type.
func _hunters_in(manager) -> Array:
	var found: Array = []
	for chunk_coord in manager._loaded_villages:
		for node in manager._loaded_villages[chunk_coord]:
			if not is_instance_valid(node) or not node.has_method("setup_economy"):
				continue
			var identity = node.get("identity")
			if identity != null and identity.occupation == "hunter":
				found.append(node)
	return found
