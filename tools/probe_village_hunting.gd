extends SceneTree

## Does a village hunter ever actually have something to hunt?
##
## docs/concept/npc.md's "Work against the real world" section names its own
## limitation -- a villager can only take what is LOADED -- so the feature
## could be correctly wired and still never fire in play. This measures that
## against real chunks, real settlements and real spawned creatures near
## Berlin, the way probe_village_industry.gd measures whether a sawmill plot
## exists at all:
##
## 1. How many real hunter villagers a walk east of Berlin actually meets.
## 2. How far the nearest real quarry was from where each of them works --
##    measured with NO reach limit, so a MISS reports a real distance. That
##    is probe_village_industry.gd's own discipline ("for the misses, how
##    far the nearest forest cell was"), so any change to a hunter's reach
##    is grounded in a measurement rather than guessed at.
## 3. For one hunter that really has quarry in reach, how much real meat and
##    hide reach the market over a simulated stretch -- against what the old
##    conjured drip would have paid over the same stretch.
##
## Three structural notes for the next probe that spawns real world nodes.
## All three were learned the hard way here, each one silently producing a
## plausible-looking zero rather than an error:
##
## - **Work in `_process`, not `_init` or `_initialize`.** A SceneTree script
##   is constructed before its `root` Window exists, so `_init` cannot touch
##   the tree at all. `_initialize` can add children -- but `root` is not
##   yet live, so those children never get `_ready()`, which means
##   `add_to_group` never runs and every `get_nodes_in_group` comes back
##   empty. A probe that queried groups from `_initialize` measured 25
##   spawned creatures as 0 huntable ones and read like a broken feature.
## - **`load()` at runtime, do not `preload`.** A `-s` script is compiled
##   before the project's autoloads are registered, so preloading
##   EarthChunkManager -- which references the WorldItemBus singleton --
##   fails to compile with "Identifier not found". GUT avoids this because
##   it loads its test scripts at runtime too.
## - **Ask the SceneTree for groups directly.** `self.get_nodes_in_group`,
##   not `root.get_tree().get_nodes_in_group`, which can hand back null.

const CHUNK_SIZE := 32
## How many chunk-widths east of Berlin to walk. Settlements are sparse
## (~1 in 30 habitable chunks), so this is sized to meet several rather than
## to be exhaustive.
const STEPS := 40
const SIMULATED_SECONDS := 240.0
const SLICE := 0.1

var _huntable_quarry
var _npc_production
var _manager
var _origin: Vector2i
var _step := -1

var _hunters_seen := {}
var _hunters_with_quarry := {}
var _hunters_measured := {}
var _hunters_with_nothing_alive := {}
var _creature_counts: Array = []
var _distances: Array = []


func _initialize() -> void:
	var EarthChunkGenerator = load("res://src/world/earth_chunk_generator.gd")
	var GeoCoordinates = load("res://src/world/geo_coordinates.gd")
	_huntable_quarry = load("res://src/gameplay/huntable_quarry.gd")
	_npc_production = load("res://src/world/npc_production.gd")
	var geo = GeoCoordinates.new()
	_origin = Vector2i(
		geo.tile_for_longitude(13.405, EarthChunkGenerator.WORLD_WIDTH_TILES),
		geo.tile_for_latitude(52.52, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	)


## One walk step per frame. ONE manager walked across the map, the way a
## player actually moves -- chunks load and evict incrementally around them,
## which is a more honest picture of what is loaded at any moment than a
## purpose-built snapshot would be. Returning true ends the run.
func _process(_delta: float) -> bool:
	if _step < 0:
		var EarthChunkManager = load("res://src/world/earth_chunk_manager.gd")
		var tile_map_layer := TileMapLayer.new()
		var entities := Node2D.new()
		var creatures := Node2D.new()
		root.add_child(tile_map_layer)
		root.add_child(entities)
		root.add_child(creatures)
		_manager = EarthChunkManager.new(tile_map_layer, entities, creatures)
		_step = 0
		return false

	if _step < STEPS:
		_manager.update(_origin + Vector2i(_step * CHUNK_SIZE, 0))
		_sample()
		_step += 1
		return false

	_report()
	return true


func _sample() -> void:
	var loaded: Array = get_nodes_in_group(_huntable_quarry.QUARRY_GROUP_NAME)
	for hunter in _hunters_in(_manager):
		var key: int = hunter.identity.seed_value
		_hunters_seen[key] = true
		_creature_counts.append(loaded.size())
		var quarry = _huntable_quarry.nearest(loaded, hunter.workspot_position, INF)
		if quarry == null:
			_hunters_with_nothing_alive[key] = true
			continue
		var distance: float = hunter.workspot_position.distance_to(quarry.position)
		if not _hunters_measured.has(key):
			_distances.append(distance)
			_hunters_measured[key] = true
		if distance <= _huntable_quarry.SEARCH_RADIUS_PX:
			_hunters_with_quarry[key] = true


func _report() -> void:
	print("-- real huntable quarry near a real village hunter, walking east from Berlin --")
	print("chunk-widths walked:                     %d" % STEPS)
	print("distinct hunter villagers met:           %d" % _hunters_seen.size())
	if _hunters_seen.size() > 0:
		print(
			"hunters that ever had quarry in reach:   %d (%.1f%%)"
			% [
				_hunters_with_quarry.size(),
				100.0 * float(_hunters_with_quarry.size()) / float(_hunters_seen.size()),
			]
		)
	print("hunters that saw no live quarry at all:  %d" % _hunters_with_nothing_alive.size())
	if not _creature_counts.is_empty():
		_creature_counts.sort()
		print(
			"huntable creatures loaded at a sighting: min %d  median %d  max %d"
			% [
				_creature_counts[0],
				_creature_counts[_creature_counts.size() / 2],
				_creature_counts[_creature_counts.size() - 1],
			]
		)
	if not _distances.is_empty():
		_distances.sort()
		print(
			"distance to nearest quarry (px):         min %.0f  median %.0f  max %.0f"
			% [_distances[0], _distances[_distances.size() / 2], _distances[_distances.size() - 1]]
		)
		print(
			"a hunter's reach (px):                   %.0f  (%.1f tiles)"
			% [_huntable_quarry.SEARCH_RADIUS_PX, _huntable_quarry.SEARCH_RADIUS_PX / 16.0]
		)

	# Picked from what is loaded NOW, not from somewhere back along the walk:
	# chunks evict behind a moving player, and a hunter whose chunk is gone
	# is a detached node that can find nothing.
	var subject = null
	for hunter in _hunters_in(_manager):
		var quarry = _huntable_quarry.nearest(
			get_nodes_in_group(_huntable_quarry.QUARRY_GROUP_NAME), hunter.workspot_position
		)
		if quarry != null:
			subject = hunter
			break
	if subject != null and subject.is_inside_tree():
		_measure_one_hunt(subject)
	else:
		print("")
		print("no hunter with quarry in reach is loaded right now to simulate")


## Runs one real hunter forward and reports what the village actually got,
## against what the old conjured drip would have paid over the same stretch.
func _measure_one_hunt(hunter) -> void:
	var market = hunter.economy.market
	var meat_before: float = market.stock.get("meat", 0.0)
	var hide_before: float = market.stock.get("hide", 0.0)
	var before := get_nodes_in_group(_huntable_quarry.QUARRY_GROUP_NAME).size()
	var headcount: float = _manager.herbivore_population_near(hunter.workspot_position)

	var elapsed := 0.0
	while elapsed < SIMULATED_SECONDS:
		hunter._process(SLICE)
		elapsed += SLICE

	var after := get_nodes_in_group(_huntable_quarry.QUARRY_GROUP_NAME).size()
	var drip: float = _npc_production.PRODUCTION_RATE_PER_SECOND * headcount * SIMULATED_SECONDS
	print("")
	print("-- one real hunter, %.0f simulated seconds --" % SIMULATED_SECONDS)
	print("regional herbivore headcount:            %.3f" % headcount)
	print("huntable creatures before / after:       %d / %d" % [before, after])
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
