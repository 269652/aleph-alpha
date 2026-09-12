extends GutTest

## EarthChunkManager's side of the player's simulation-density knobs
## (docs/concept/ecosystem_dynamics.md "Simulation density: the player's own
## knobs"): the manager holds one density per knob, sanitised on the way in,
## and the three ceilings read it -- the two forager dispatch gates through
## SimulationSettings.scaled_cap with the colony's own floor of one, the
## pollinator spawn pass and offspring cap through the budget's density
## multiplier. The dispatch gates are pinned as source contracts, the same
## way test_world_crush_wiring.gd pins World's crush loop: standing up a real
## colony with a real population just to watch one comparison is not worth
## the fight, and the arithmetic itself is SimulationSettings' own tested
## function.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const SimulationSettings = preload("res://src/gameplay/simulation_settings.gd")


var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)


func after_each():
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


func _body_of(function_name: String) -> String:
	var source := FileAccess.get_file_as_string("res://src/world/earth_chunk_manager.gd")
	var start := source.find("func %s(" % function_name)
	assert_gt(start, -1, "the premise: %s must still exist" % function_name)
	var body_end := source.find("\nfunc ", start + 1)
	return source.substr(start, body_end - start)


func test_every_knob_starts_at_full_density():
	for knob in SimulationSettings.KNOBS:
		assert_eq(manager.population_density(knob), 1.0, knob)


func test_a_density_is_stored_sanitised():
	manager.set_population_density("ant_foragers", 0.25)
	assert_eq(manager.population_density("ant_foragers"), 0.25)
	manager.set_population_density("bee_foragers", 4.0)
	assert_eq(manager.population_density("bee_foragers"), 1.0, "clamped: a knob only lowers a ceiling")
	manager.set_population_density("pollinators", NAN)
	assert_eq(manager.population_density("pollinators"), 1.0, "NaN falls back to the default")


func test_an_unknown_knob_is_ignored_and_reads_as_full():
	manager.set_population_density("bogus", 0.1)
	assert_eq(manager.population_density("bogus"), 1.0)


func test_the_ant_dispatch_gate_scales_the_colonys_cap_by_the_knob_with_a_floor_of_one():
	var body := _body_of("_dispatch_forager")
	assert_true(
		body.contains('SimulationSettings.scaled_cap(colony.active_forager_cap_at(cell), _population_density["ant_foragers"], 1)'),
		"the gate must compare against the scaled cap, never the raw one"
	)


func test_the_bee_dispatch_gate_scales_the_colonys_cap_by_the_knob_with_a_floor_of_one():
	var body := _body_of("_dispatch_bee_forager")
	assert_true(
		body.contains('SimulationSettings.scaled_cap(colony.active_forager_cap_at(cell), _population_density["bee_foragers"], 1)'),
		"the gate must compare against the scaled cap, never the raw one"
	)


func test_both_pollinator_ceilings_read_the_knob():
	var source := FileAccess.get_file_as_string("res://src/world/earth_chunk_manager.gd")
	assert_true(
		source.contains('AmbientFlyerRenderer.max_flyers_per_chunk(_pollinator_multiplier_for(chunk_coord), _population_density["pollinators"])'),
		"the offspring cap"
	)
	var spawn_at := source.find("_ambient_flyer_renderer.spawn_ambient_flyers(")
	assert_gt(spawn_at, -1)
	# The call's own closing paren sits alone on its line; the argument list
	# runs up to it.
	var call_end := source.find("\n\t)", spawn_at)
	assert_gt(call_end, spawn_at)
	assert_true(
		source.substr(spawn_at, call_end - spawn_at).contains('_population_density["pollinators"]'),
		"the spawn pass"
	)
