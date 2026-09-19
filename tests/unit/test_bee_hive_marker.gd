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
const ProceduralTreeSprite = preload("res://src/rendering/procedural_tree_sprite.gd")

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


## FPS regression round 13: the RESIZE_INTERVAL_SECONDS-second tick comes from a Timer
## child now, not from an engine _process paying ~7 us of dispatch every
## frame to add a delta and return; the timer drives the same _process.
func test_the_tick_comes_from_a_timer_not_from_engine_frames():
	assert_false(marker.is_processing(), "no per-frame dispatch")
	var timer := marker.get_node_or_null("TickTimer") as Timer
	assert_not_null(timer, "the Timer child that stands in for the frames")
	assert_almost_eq(timer.wait_time, BeeHiveMarker.RESIZE_INTERVAL_SECONDS, 0.0001)
	# is_stopped(), not autostart: Godot's own Timer CLEARS autostart the
	# moment it acts on it (NOTIFICATION_READY starts the timer and sets
	# autostart false), so reading it back from a marker already in the tree
	# can only ever be false. Asserting the timer is genuinely RUNNING is
	# what this line was always trying to say, and it is true of the real
	# marker either way.
	assert_false(timer.is_stopped(), "running the moment the marker is in the tree")
	assert_false(timer.one_shot, "and it keeps ticking")


func test_a_tick_without_a_colony_is_the_same_harmless_no_op_as_before():
	var timer := marker.get_node("TickTimer") as Timer
	timer.timeout.emit()
	pass_test("no colony: _process returns before touching anything, exactly as a direct call does")


# -- hanging from the branch, not standing on the ground --------------------
#
# Reported live: *"Beehives should not be built on grass... they need a tree
# branch to build it please"*. Placement is EarthChunkManager's half (a hive
# is only ever sited on a tile a real tree stands on -- see
# test_earth_chunk_manager_bees.gd); this is the other half, which is that
# the comb then has to be drawn up IN that tree rather than at the foot of
# its trunk, where it read as sitting on the grass beside it.


func test_the_hive_hangs_up_in_the_tree_rather_than_at_the_foot_of_its_trunk():
	assert_lt(
		marker.hive_sprite().position.y, 0.0,
		"a hive drawn at its own tile's centre sits on the ground, not on a branch"
	)


## Inside the canopy, not floating above the crown or stuck on the trunk.
## Bounded against the real drawn height of a real tree (see
## ProceduralTreeSprite.WORLD_SIZE/VISUAL_SCALE, whose origin is the FOOT of
## the trunk with the canopy drawn above it) rather than against a number
## chosen here, so tree art and hive height cannot drift apart.
func test_the_hive_hangs_within_the_real_canopy_of_a_real_tree():
	var tree_height: float = (
		float(ProceduralTreeSprite.WORLD_SIZE.y) * ProceduralTreeSprite.VISUAL_SCALE
	)
	var hang: float = -marker.hive_sprite().position.y
	assert_gt(hang, tree_height * 0.3, "still down among the roots")
	assert_lt(hang, tree_height, "hanging in mid-air above the crown")


## The NODE stays on the ground even though the sprite is drawn up in the
## branches -- Y-sorting compares node origins, so a hive whose own origin
## floated up into the canopy would draw behind things it stands in front of.
## The same split CaterpillarMarker._climb_height_px already keeps for
## climbing a trunk, and what test_stays_exactly_where_placed is really about.
func test_the_marker_itself_stays_on_the_ground_it_sorts_by():
	assert_eq(marker.position, Vector2(200, 150))
	assert_eq(marker.global_position, Vector2(200, 150))


## A branch does not move as the colony grows: a founding hive and a full
## one hang at exactly the same height, only drawn at different sizes.
func test_a_hive_hangs_at_the_same_height_whatever_size_its_colony_is():
	var founding: float = marker.hive_sprite().position.y
	var colony := _colony_with_one_hive()
	marker.setup(null, colony, colony.hive_cells()[0])
	marker._process(BeeHiveMarker.RESIZE_INTERVAL_SECONDS)
	assert_eq(marker.hive_sprite().position.y, founding)
