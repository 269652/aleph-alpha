extends GutTest

## The visible marker over one BeeColony hive cell -- see
## ProceduralBeehiveSprite/IllustratedBeehiveSprite, docs/concept/bees.md.
## Mirrors test_ant_mound_marker.gd's own shape (group membership,
## display name, hover panel, growth-over-time), and adds what a mound
## has no precedent for at all: a real player harvest interaction
## (get_hover_actions/harvest) that yields honey, advances a real
## destruction sequence, and -- on the final hit -- frees the marker and
## hands off to the world for absconding (see BeeColony.abscond_to).

const BeeHiveMarker = preload("res://src/rendering/bee_hive_marker.gd")
const ProceduralBeehiveSprite = preload("res://src/rendering/procedural_beehive_sprite.gd")
const IllustratedBeehiveSprite = preload("res://src/rendering/illustrated_beehive_sprite.gd")
const HoverTargetFinder = preload("res://src/rendering/hover_target_finder.gd")
const BeeColony = preload("res://src/world/bee_colony.gd")

const WIDTH := 16
const HEIGHT := 16


func _all_grassland() -> PackedStringArray:
	var biome := PackedStringArray()
	biome.resize(WIDTH * HEIGHT)
	for i in biome.size():
		biome[i] = "grassland"
	return biome


## Mirrors test_bee_colony.gd's own _colony_with_one_hive helper exactly
## -- HIVE_CHANCE is deliberately far sparser than an ant mound's own, so
## a single arbitrary seed is not reliably guaranteed to land one.
func _colony_with_one_hive() -> BeeColony:
	for seed_value in range(1, 200):
		var colony := BeeColony.new(seed_value, WIDTH, HEIGHT, _all_grassland())
		if colony.hive_cells().size() > 0:
			return colony
	fail_test("no seed in [1, 200) placed a single hive")
	return null


## Duck-typed world: the one method a harvested-to-destruction hive calls
## back into (see BeeHiveMarker.harvest's own doc comment).
class StubWorld:
	var relocate_calls: Array = []
	func relocate_bee_hive_after_harvest(colony: BeeColony, cell: Vector2i) -> void:
		relocate_calls.append({"colony": colony, "cell": cell})


var marker: BeeHiveMarker


func before_each():
	marker = BeeHiveMarker.new()
	marker.position = Vector2(200, 150)
	add_child_autofree(marker)


func test_joins_the_bee_hive_group():
	assert_true(marker.is_in_group(BeeHiveMarker.GROUP_NAME))


func test_joins_the_hoverable_group():
	assert_true(marker.is_in_group(HoverTargetFinder.GROUP_NAME))


func test_get_display_name_names_it_a_honeybee_hive():
	assert_eq(marker.get_display_name(), "Honeybee Hive")


func test_get_hover_actions_offers_a_harvest_verb():
	var actions := marker.get_hover_actions()
	assert_eq(actions.size(), 1)
	assert_eq(actions[0].get("verb"), "Harvest")


func test_stays_exactly_where_placed():
	assert_eq(marker.position, Vector2(200, 150))


# -- hover panel --------------------------------------------------------

func test_panel_state_with_no_colony_reads_as_a_founding_hive():
	var state := marker.panel_state()
	assert_eq(state.get("name"), "Honeybee Hive")
	assert_almost_eq(float(state.get("health_fraction")), 0.0, 0.001)


func test_panel_state_never_shows_a_level_or_a_condition_row():
	var colony := _colony_with_one_hive()
	var cell: Vector2i = colony.hive_cells()[0]
	marker.setup(null, colony, cell)
	var state := marker.panel_state()
	assert_eq(state.get("show_level"), false)
	assert_eq(state.get("invested"), false)


func test_panel_state_bar_is_labelled_honey_and_reads_the_real_fraction():
	var colony := _colony_with_one_hive()
	var cell: Vector2i = colony.hive_cells()[0]
	marker.setup(null, colony, cell)
	var state := marker.panel_state()
	assert_eq(state.get("bar_label"), "Honey")
	assert_almost_eq(
		float(state.get("health_fraction")), colony.honey_availability_fraction(cell), 0.001
	)


func test_get_display_name_reports_real_population_and_honey_once_a_colony_is_set_up():
	var colony := _colony_with_one_hive()
	var cell: Vector2i = colony.hive_cells()[0]
	var linked := BeeHiveMarker.new()
	linked.setup(null, colony, cell)
	add_child_autofree(linked)
	var name := linked.get_display_name()
	assert_string_contains(name, str(int(round(colony.population_at(cell)))))
	assert_string_contains(name, str(int(round(colony.honey_stored_at(cell)))))


# -- growth-stage art (see IllustratedBeehiveSprite) -------------------------

func test_has_a_real_hive_sprite_texture():
	var sprite := marker.get_child(0) as Sprite2D
	assert_not_null(sprite.texture)
	assert_eq(
		Vector2i(sprite.texture.get_width(), sprite.texture.get_height()),
		IllustratedBeehiveSprite.CANVAS_SIZE
	)


func test_sprite_is_drawn_at_its_real_tiny_world_size_not_the_raw_art_canvas():
	var sprite := marker.get_child(0) as Sprite2D
	assert_eq(sprite.scale, Vector2.ONE * IllustratedBeehiveSprite.new().marker_scale(0.0))


func test_setup_sizes_the_sprite_from_the_real_colonys_growth_fraction_immediately():
	var colony := _colony_with_one_hive()
	var cell: Vector2i = colony.hive_cells()[0]
	for i in 400:
		colony.record_forage_result(cell, true)
		colony.advance(BeeColony.SECONDS_PER_SIMULATED_DAY)
	var grown := BeeHiveMarker.new()
	grown.setup(null, colony, cell)
	add_child_autofree(grown)

	var sprite := grown.get_child(0) as Sprite2D
	var expected_index := IllustratedBeehiveSprite.growth_stage_index(colony.growth_fraction_at(cell))
	var expected_texture := IllustratedBeehiveSprite.new().growth_texture(expected_index)
	assert_eq(sprite.texture, expected_texture)


func test_hive_grows_larger_over_time_as_its_colony_grows():
	var colony := _colony_with_one_hive()
	var cell: Vector2i = colony.hive_cells()[0]
	var growing := BeeHiveMarker.new()
	growing.setup(null, colony, cell)
	add_child_autofree(growing)
	var sprite := growing.get_child(0) as Sprite2D
	var before := sprite.scale.x

	# One successful trip per simulated DAY cannot outpace a real
	# population's own daily upkeep (HONEY_PER_BEE_PER_DAY) -- mirrors
	# test_ant_mound_marker.gd's own "many trips per simulated day"
	# shape exactly, for the identical reason.
	for i in 400:
		for trip in 50:
			colony.record_forage_result(cell, true)
		colony.advance(BeeColony.SECONDS_PER_SIMULATED_DAY)
	growing._process(BeeHiveMarker.RESIZE_INTERVAL_SECONDS + 1.0)

	assert_gt(sprite.scale.x, before, "the marker should have re-checked its own colony and grown")


func test_does_not_resize_faster_than_its_own_throttle():
	var colony := _colony_with_one_hive()
	var cell: Vector2i = colony.hive_cells()[0]
	var growing := BeeHiveMarker.new()
	growing.setup(null, colony, cell)
	add_child_autofree(growing)
	var sprite := growing.get_child(0) as Sprite2D
	var before := sprite.scale.x

	for i in 400:
		colony.record_forage_result(cell, true)
		colony.advance(BeeColony.SECONDS_PER_SIMULATED_DAY)
	growing._process(0.1)

	assert_almost_eq(sprite.scale.x, before, 0.0001, "a sub-throttle tick should not have re-checked yet")


func test_process_with_no_colony_set_up_does_not_crash_or_change_size():
	var sprite := marker.get_child(0) as Sprite2D
	var before := sprite.scale.x
	marker._process(BeeHiveMarker.RESIZE_INTERVAL_SECONDS + 1.0)
	assert_almost_eq(sprite.scale.x, before, 0.0001)


# -- harvesting: the one genuinely new player-interaction mechanic -----------

func test_harvest_with_no_colony_frees_the_marker_without_crashing():
	var colony := _colony_with_one_hive()
	var cell: Vector2i = colony.hive_cells()[0]
	var lone := BeeHiveMarker.new()
	add_child_autofree(lone)
	lone.harvest()
	assert_true(lone.is_queued_for_deletion())


func test_harvest_withdraws_real_honey_from_the_colony():
	var colony := _colony_with_one_hive()
	var cell: Vector2i = colony.hive_cells()[0]
	marker.setup(StubWorld.new(), colony, cell)
	var before := colony.honey_stored_at(cell)
	marker.harvest()
	assert_lt(colony.honey_stored_at(cell), before)


func test_harvest_drops_a_real_honey_item():
	var colony := _colony_with_one_hive()
	var cell: Vector2i = colony.hive_cells()[0]
	marker.setup(StubWorld.new(), colony, cell)
	var dropped: Array = []
	var on_drop := func(item_stack, world_position):
		dropped.append({"item_stack": item_stack, "position": world_position})
	WorldItemBus.item_dropped.connect(on_drop)
	marker.harvest()
	WorldItemBus.item_dropped.disconnect(on_drop)
	assert_eq(dropped.size(), 1)
	assert_eq(dropped[0]["item_stack"].item.id, "honey")
	assert_gt(dropped[0]["item_stack"].count, 0)


func test_harvest_of_an_already_empty_hive_drops_nothing():
	var colony := _colony_with_one_hive()
	var cell: Vector2i = colony.hive_cells()[0]
	colony.withdraw_honey(cell, colony.honey_stored_at(cell))
	marker.setup(StubWorld.new(), colony, cell)
	var dropped: Array = []
	var on_drop := func(item_stack, world_position):
		dropped.append(item_stack)
	WorldItemBus.item_dropped.connect(on_drop)
	marker.harvest()
	WorldItemBus.item_dropped.disconnect(on_drop)
	assert_eq(dropped.size(), 0)


func test_harvest_advances_the_destruction_sprite():
	var colony := _colony_with_one_hive()
	var cell: Vector2i = colony.hive_cells()[0]
	marker.setup(StubWorld.new(), colony, cell)
	marker.harvest()
	var sprite := marker.get_child(0) as Sprite2D
	assert_eq(sprite.texture, IllustratedBeehiveSprite.new().harvest_texture(0))


func test_repeated_harvest_progresses_through_the_destruction_sequence():
	var colony := _colony_with_one_hive()
	var cell: Vector2i = colony.hive_cells()[0]
	marker.setup(StubWorld.new(), colony, cell)
	for i in 3:
		marker.harvest()
	var sprite := marker.get_child(0) as Sprite2D
	assert_eq(sprite.texture, IllustratedBeehiveSprite.new().harvest_texture(2))


## The final hit frees the marker and hands off to the world for
## absconding -- the colony's own population/honey survive (see
## BeeColony.abscond_to), a hive struck to structural collapse is not
## the same as the colony being wiped out.
func test_the_final_hit_frees_the_marker_and_asks_the_world_to_relocate():
	var colony := _colony_with_one_hive()
	var cell: Vector2i = colony.hive_cells()[0]
	var world := StubWorld.new()
	marker.setup(world, colony, cell)
	for i in BeeHiveMarker.HARVEST_HITS_TO_DESTROY:
		marker.harvest()
	assert_true(marker.is_queued_for_deletion())
	assert_eq(world.relocate_calls.size(), 1)
	assert_eq(world.relocate_calls[0]["cell"], cell)


func test_hits_short_of_the_final_one_never_ask_the_world_to_relocate():
	var colony := _colony_with_one_hive()
	var cell: Vector2i = colony.hive_cells()[0]
	var world := StubWorld.new()
	marker.setup(world, colony, cell)
	for i in BeeHiveMarker.HARVEST_HITS_TO_DESTROY - 1:
		marker.harvest()
	assert_false(marker.is_queued_for_deletion())
	assert_eq(world.relocate_calls.size(), 0)


## HARVEST_HITS_TO_DESTROY is pinned to the real destruction sheet's own
## frame count, not an arbitrary tuning number (see bees.md's "Harvesting
## honey").
func test_harvest_hits_to_destroy_matches_the_real_destruction_frame_count():
	assert_eq(BeeHiveMarker.HARVEST_HITS_TO_DESTROY, IllustratedBeehiveSprite.new().harvest_frame_count())
