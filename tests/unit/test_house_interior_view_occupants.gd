extends GutTest

## Several people in one room (docs/concept/mage_guild.md pillar 5 and the
## direct ask: "multiple mages can move in and hang around inside of the
## mage guild").
##
## Every interior until now held exactly one resident -- one `_resident`,
## one `resident_cell`. A guild is the first room in the game that holds a
## group, so the view learns to stand several people up without any of them
## standing on the furniture, in the doorway, or on each other.

const HouseInteriorView = preload("res://src/rendering/house_interior_view.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const MageMaster = preload("res://src/gameplay/mage_master.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")

const TILE_SIZE := 16

var view: HouseInteriorView
var renderer: TerrainRenderer


func before_each():
	renderer = TerrainRenderer.new()
	view = HouseInteriorView.new()
	view.build("hall", MageMaster.OCCUPATION, 4242, renderer.build_tile_set(), TILE_SIZE, renderer)
	add_child(view)


func after_each():
	remove_child(view)
	view.free()


func _masters(count: int) -> Array:
	var identities: Array = []
	for i in count:
		identities.append(MageMaster.identity_for(hash("occupant_%d" % i)))
	return identities


# -- where somebody may stand -----------------------------------------------

func test_a_room_offers_somewhere_to_stand():
	assert_gt(view.standing_cells().size(), 0)


func test_nobody_may_stand_in_the_doorway():
	# The door has to stay walkable or there is no way back out.
	assert_false(view.standing_cells().has(view.door_cell))


func test_nobody_may_stand_on_the_furniture():
	for cell in view.standing_cells():
		assert_eq(view.furniture_at(cell), "", "cell %s has %s on it" % [cell, view.furniture_at(cell)])


func test_the_residents_own_cell_is_somewhere_to_stand():
	assert_true(view.standing_cells().has(view.resident_cell))


func test_standing_cells_are_stable_in_order():
	assert_eq(view.standing_cells(), view.standing_cells())


# -- standing a group up ----------------------------------------------------

func test_placing_a_group_stands_every_one_of_them_up():
	var placed: Array = view.place_occupants(_masters(3))
	assert_eq(placed.size(), 3)
	assert_eq(view.occupant_identities().size(), 3)


func test_the_first_of_the_group_is_the_one_the_room_calls_its_resident():
	# So the indoor Talk verb and World's own prompt keep working unchanged.
	var identities: Array = _masters(3)
	view.place_occupants(identities)
	assert_eq(view.resident_identity().seed_value, identities[0].seed_value)
	assert_ne(view.resident_position(), Vector2.INF)


func test_nobody_stands_on_anybody_else():
	view.place_occupants(_masters(3))
	var seen := {}
	for position in view.occupant_positions():
		assert_false(seen.has(position), "two occupants are standing in the same place")
		seen[position] = true


func test_everybody_stands_somewhere_they_are_allowed_to():
	view.place_occupants(_masters(3))
	var allowed := {}
	for cell in view.standing_cells():
		allowed[(Vector2(cell) + Vector2(0.5, 0.5)) * TILE_SIZE] = true
	for position in view.occupant_positions():
		assert_true(allowed.has(position), "somebody is standing at %s, which is not a floor cell" % position)


func test_placing_nobody_leaves_the_room_honestly_empty():
	assert_eq(view.place_occupants([]), [])
	assert_eq(view.occupant_identities(), [])
	assert_null(view.resident_identity())
	assert_eq(view.resident_position(), Vector2.INF)


func test_a_group_larger_than_the_room_stands_up_only_as_many_as_fit():
	var room_for: int = view.standing_cells().size()
	var placed: Array = view.place_occupants(_masters(room_for + 5))
	assert_eq(placed.size(), room_for)


func test_the_same_group_always_stands_in_the_same_places():
	var first: Array = view.occupant_positions()
	view.place_occupants(_masters(3))
	var after: Array = view.occupant_positions()
	assert_eq(first, [])

	var other := HouseInteriorView.new()
	other.build("hall", MageMaster.OCCUPATION, 4242, renderer.build_tile_set(), TILE_SIZE, renderer)
	add_child(other)
	other.place_occupants(_masters(3))
	assert_eq(other.occupant_positions(), after)
	remove_child(other)
	other.free()


func test_a_single_occupant_stands_where_the_lone_resident_always_did():
	view.place_occupants(_masters(1))
	var expected := (Vector2(view.resident_cell) + Vector2(0.5, 0.5)) * TILE_SIZE
	assert_eq(view.occupant_positions()[0], expected)


func test_placing_a_group_twice_does_not_leave_the_first_lot_standing_there():
	view.place_occupants(_masters(3))
	view.place_occupants(_masters(2))
	assert_eq(view.occupant_identities().size(), 2)


## The single-resident path every house in the game already uses must keep
## behaving exactly as it did.
func test_place_resident_still_stands_one_villager_on_the_resident_cell():
	var villager := NpcIdentity.new(99)
	view.place_resident(villager)
	assert_eq(view.resident_identity().seed_value, villager.seed_value)
	assert_eq(view.resident_position(), (Vector2(view.resident_cell) + Vector2(0.5, 0.5)) * TILE_SIZE)
