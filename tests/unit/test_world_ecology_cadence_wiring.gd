extends GutTest

## World's batched ecology steps run on a StepCadence (FPS regression round
## 13, src/gameplay/step_cadence.gd): every chunk-manager step in
## _step_ecology_batch runs once per StepCadence.INTERVAL_SECONDS with the
## time it waited, not once per frame. Driven live here on a bare World with
## a counting stand-in for the chunk manager -- the same shape the four
## test_world_ecology_batch_*.gd files already use -- because the contract
## is behavioural: how often each step is called, and with how much time.

const World = preload("res://scenes/world.gd")
const StepCadence = preload("res://src/gameplay/step_cadence.gd")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const PlayerScene = preload("res://scenes/player.tscn")

const FRAME := 1.0 / 60.0


## Counts every step call and sums the seconds handed over -- a real
## EarthChunkManager (World types the field) with every batched step
## overridden, the same shape test_world_ecology_batch_*.gd use; never
## loaded, so nothing real runs underneath.
class CountingManager extends EarthChunkManager:
	var calls: Dictionary = {}
	var seconds: Dictionary = {}

	func _note(name: String, elapsed: float) -> void:
		calls[name] = int(calls.get(name, 0)) + 1
		seconds[name] = float(seconds.get(name, 0.0)) + elapsed

	func step_worms(d: float) -> void: _note("worms", d)
	func step_fruiting(d: float, _player_pixel: Vector2) -> void: _note("fruiting", d)
	func step_ecosystem(d: float) -> void: _note("ecosystem", d)
	func step_forage(d: float) -> void: _note("forage", d)
	func step_tree_spread(d: float) -> void: _note("tree_spread", d)
	func step_tree_growth() -> void: _note("tree_growth", 0.0)
	func step_ground_food(d: float) -> void: _note("ground_food", d)
	func step_flies(d: float) -> void: _note("flies", d)
	func step_carried_food(d: float) -> void: _note("carried_food", d)
	func step_tall_grass(d: float) -> void: _note("tall_grass", d)
	func step_aquatic_vegetation(d: float) -> void: _note("aquatic_vegetation", d)
	func step_aquatic_invertebrates(d: float) -> void: _note("aquatic_invertebrates", d)
	func step_wild_crops(d: float) -> void: _note("wild_crops", d)
	func step_wild_mushrooms(d: float) -> void: _note("wild_mushrooms", d)
	func step_farm_plots(d: float) -> void: _note("farm_plots", d)
	func step_ants(d: float) -> void: _note("ants", d)
	func step_bees(d: float) -> void: _note("bees", d)
	func step_leaf_litter(d: float) -> void: _note("leaf_litter", d)
	func step_footprints() -> void: _note("footprints", 0.0)
	func step_flowers(d: float) -> void: _note("flowers", d)
	func step_desert_scrub(d: float) -> void: _note("desert_scrub", d)
	func step_tundra_lichen(d: float) -> void: _note("tundra_lichen", d)
	func step_settlements(d: float) -> void: _note("settlements", d)
	func step_npc_encounters(d: float) -> void: _note("npc_encounters", d)
	func step_regional_trade(d: float) -> void: _note("regional_trade", d)


## World keeps two steps of its own in the same batch (herbivore food
## consumption, reproduction); a bare World cannot run their real bodies,
## so this subclass records them the same way the manager records its.
class TestWorld extends World:
	var recorder: CountingManager = null

	func _step_herbivore_food_consumption(delta: float) -> void:
		recorder._note("herbivore_food", delta)

	func _step_reproduction(delta: float) -> void:
		recorder._note("reproduction", delta)


const WORLD_STEPS: Array[String] = ["herbivore_food", "reproduction"]

const CHUNK_MANAGER_STEPS: Array[String] = [
	"worms", "ecosystem", "forage", "tree_spread", "tree_growth", "ground_food", "flies", "carried_food",
	"tall_grass", "aquatic_vegetation", "aquatic_invertebrates", "wild_crops", "wild_mushrooms",
	"farm_plots", "ants", "bees", "leaf_litter", "footprints", "flowers", "desert_scrub",
	"tundra_lichen", "settlements", "npc_encounters", "regional_trade",
]

var world: TestWorld
var manager: CountingManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D


func before_each():
	world = TestWorld.new()
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	manager = CountingManager.new(tile_map_layer, entities_parent, creatures_parent)
	world.recorder = manager
	world._chunk_manager = manager


func after_each():
	world.free()
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


func _frames(count: int, delta: float = FRAME) -> void:
	for frame in count:
		world._step_ecology_batch(delta, null)


func test_one_interval_of_frames_runs_every_chunk_manager_step_exactly_once():
	_frames(roundi(StepCadence.INTERVAL_SECONDS / FRAME))
	for step in CHUNK_MANAGER_STEPS + WORLD_STEPS:
		assert_eq(manager.calls.get(step, 0), 1, "%s runs once per interval, not once per frame" % step)


func test_four_intervals_of_frames_run_every_step_four_times_with_the_time_they_waited():
	_frames(roundi(StepCadence.INTERVAL_SECONDS / FRAME) * 4)
	for step in CHUNK_MANAGER_STEPS + WORLD_STEPS:
		assert_eq(manager.calls.get(step, 0), 4, step)
	for step in ["tall_grass", "leaf_litter", "ants", "bees"]:
		assert_between(
			manager.seconds[step], StepCadence.INTERVAL_SECONDS * 3.0 - FRAME, StepCadence.INTERVAL_SECONDS * 4.0 + FRAME,
			"%s is handed all the time that passed, minus at most the interval still accumulating at the cut-off" % step
		)


func test_a_single_frame_as_long_as_the_interval_runs_everything_once_as_the_older_tests_expect():
	world._step_ecology_batch(1.0, null)
	for step in CHUNK_MANAGER_STEPS:
		assert_eq(manager.calls.get(step, 0), 1, step)
	assert_almost_eq(manager.seconds["tall_grass"], 1.0, 0.0001, "the whole frame, nothing lost")


func test_the_steps_are_spread_over_the_intervals_frames_not_stacked_on_one():
	var frames := roundi(StepCadence.INTERVAL_SECONDS / FRAME)
	var busiest := 0
	var before := 0
	for frame in frames:
		world._step_ecology_batch(FRAME, null)
		var total := 0
		for step in CHUNK_MANAGER_STEPS:
			total += int(manager.calls.get(step, 0))
		busiest = maxi(busiest, total - before)
		before = total
	assert_lte(busiest, ceili(float(CHUNK_MANAGER_STEPS.size()) / float(frames)) + 1, "no single frame carries the whole batch")


## Fruiting details trees around the player, so it needs one: with none it
## is skipped, with one it runs on the same cadence as everything else.
func test_fruiting_runs_on_the_cadence_only_when_there_is_a_player_to_detail_around():
	_frames(roundi(StepCadence.INTERVAL_SECONDS / FRAME))
	assert_eq(manager.calls.get("fruiting", 0), 0, "no player, nothing to detail around")
	var player := PlayerScene.instantiate()
	add_child_autofree(player)
	for frame in roundi(StepCadence.INTERVAL_SECONDS / FRAME):
		world._step_ecology_batch(FRAME, player)
	assert_eq(manager.calls.get("fruiting", 0), 1, "one interval, one fruiting pass")
