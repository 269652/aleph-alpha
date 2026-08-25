extends GutTest

## The Sägewerk's Lumberjack -- a small, purpose-built walker Node2D
## (mirrors DecomposerMarker's own doc comment on why this is NOT the full
## NpcMarker stack). SEEKING (find the nearest real standing ChoppableTree)
## -> APPROACHING -> FELLING (the SAME ChoppableTree.take_damage loop a
## player's axe uses) -> CARRYING -> DEPOSIT (credits the Sägewerk's own log
## stock, which separately shapes into beam/plank -- see
## docs/concept/timber_construction.md).

const LumberjackMarker = preload("res://src/rendering/lumberjack_marker.gd")
const LumberjackBehavior = preload("res://src/gameplay/lumberjack_behavior.gd")
const ChoppableTree = preload("res://src/rendering/choppable_tree.gd")
const HoverTargetFinder = preload("res://src/rendering/hover_target_finder.gd")

var marker: LumberjackMarker
var tree: ChoppableTree
var _drops: Array = []


func before_each():
	_drops = []
	WorldItemBus.item_dropped.connect(_record)
	marker = LumberjackMarker.new()
	marker.home = Vector2(100, 100)
	marker.position = Vector2(100, 100)
	add_child_autofree(marker)


func after_each():
	if WorldItemBus.item_dropped.is_connected(_record):
		WorldItemBus.item_dropped.disconnect(_record)
	if is_instance_valid(tree):
		tree.free()


func _record(stack, _position) -> void:
	_drops.append(stack)


func _standing_tree_at(at: Vector2) -> ChoppableTree:
	var t := ChoppableTree.new()
	t.position = at
	add_child_autofree(t)
	return t


func test_joins_the_lumberjack_group():
	assert_true(marker.is_in_group(LumberjackMarker.GROUP_NAME))


func test_joins_the_hoverable_group():
	assert_true(marker.is_in_group(HoverTargetFinder.GROUP_NAME))


func test_stays_near_home_while_no_tree_is_in_reach():
	for i in 30:
		marker._process(0.5)
	assert_lt(marker.position.distance_to(marker.home), LumberjackMarker.WANDER_RADIUS_PX * 2.0)


## The full loop, end to end: a nearby standing tree is found, walked to,
## felled, bucked into logs, and the Lumberjack carries the haul home --
## eventually depositing enough logs at the Sägewerk to shape real beam or
## plank output (see SagewerkProduction).
func _has_shaped_output() -> bool:
	for stack in _drops:
		if stack.item.id == "beam" or stack.item.id == "plank":
			return true
	return false


func test_the_full_loop_eventually_yields_beam_or_plank_at_home():
	tree = _standing_tree_at(Vector2(110, 100))
	for i in 4000:
		marker._process(0.25)
		if _has_shaped_output():
			break
	assert_true(_has_shaped_output(), "a full seek/fell/carry/deposit loop should eventually shape real output")


## Felling really does fell the SAME tree a player's axe would -- no
## separate mechanic, just a different caller (see
## docs/concept/timber_construction.md's own framing).
func test_felling_actually_fells_and_clears_the_real_tree():
	tree = _standing_tree_at(Vector2(102, 100))
	for i in 4000:
		marker._process(0.25)
		if is_instance_valid(tree) and tree.is_queued_for_deletion():
			break
	assert_true(tree.is_queued_for_deletion(), "the Lumberjack should have fully worked up the tree")


## Once carrying a load home, the Lumberjack goes back to seeking rather
## than getting stuck.
func test_returns_to_seeking_after_a_full_deposit():
	tree = _standing_tree_at(Vector2(102, 100))
	for i in 4000:
		marker._process(0.25)
		if _has_shaped_output():
			break
	marker._process(1.0)
	assert_eq(marker._behavior.phase, LumberjackBehavior.Phase.SEEKING)


func test_get_display_name_reports_lumberjack():
	assert_eq(marker.get_display_name(), "Lumberjack")
