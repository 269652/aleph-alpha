extends GutTest

## InteriorTemplates (docs/concept/building.md "Entering"): authored room
## shapes per interior_family (cottage/house/manor -- BuildingCatalog's own
## `interior_family_of` values), several variants each, seed-picked so the
## same house always gets the same interior. Furniture THEME is composed
## in, not hand-duplicated per occupation: each shape's `F` slots are
## filled from HouseDecor.furniture_set_for(occupation) -- the SAME
## occupation-reasoned table the old per-tile system already used -- so
## "several variants x 8 occupations" is shape-variants x furniture-sets,
## not 24+ hand-typed grids repeating the same rooms.

const InteriorTemplates = preload("res://src/gameplay/interior_templates.gd")
const HouseDecor = preload("res://src/gameplay/house_decor.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")

const _FAMILIES := ["cottage", "house", "manor"]
const _OCCUPATIONS := ["farmer", "blacksmith", "merchant", "guard", "fisher", "herbalist", "hunter", "nurse"]


func test_every_building_catalog_interior_family_has_at_least_two_variants():
	for building_id in BuildingCatalog.BUILDING_IDS:
		var family: String = BuildingCatalog.interior_family_of(building_id)
		assert_gte(InteriorTemplates.variant_count(family), 2, family)


func test_choosing_a_variant_is_deterministic_for_the_same_seed():
	var a := InteriorTemplates.choose_variant_index("cottage", 42)
	var b := InteriorTemplates.choose_variant_index("cottage", 42)
	assert_eq(a, b)


func test_choosing_a_variant_stays_in_range():
	for seed_value in 50:
		var index := InteriorTemplates.choose_variant_index("manor", seed_value)
		assert_between(index, 0, InteriorTemplates.variant_count("manor") - 1, str(seed_value))


func test_an_unknown_family_falls_back_rather_than_crashing():
	assert_gt(InteriorTemplates.variant_count("not_a_real_family"), 0)
	var result := InteriorTemplates.furnish("not_a_real_family", "farmer", 1)
	assert_false(result.is_empty())


# -- every template, every family, every variant: real, valid geometry ------

func test_every_template_is_fully_enclosed_with_exactly_one_door_on_the_south_wall():
	for family in _FAMILIES:
		for variant_index in InteriorTemplates.variant_count(family):
			var grid: Array = InteriorTemplates.grid_for(family, variant_index)
			var size: Vector2i = InteriorTemplates.grid_size(grid)
			var door_count := 0
			var door_row := -1
			for y in size.y:
				var row: String = grid[y]
				for x in size.x:
					var ch := row[x]
					if ch == "D":
						door_count += 1
						door_row = y
					elif x == 0 or y == 0 or x == size.x - 1 or y == size.y - 1:
						assert_eq(ch, "#", "%s variant %d border cell (%d,%d) must be wall" % [family, variant_index, x, y])
			assert_eq(door_count, 1, "%s variant %d" % [family, variant_index])
			assert_eq(door_row, size.y - 1, "%s variant %d door must be on the south (last) row" % [family, variant_index])


func test_every_floor_and_furniture_slot_is_enclosed_reachable_from_the_door():
	for family in _FAMILIES:
		for variant_index in InteriorTemplates.variant_count(family):
			var grid: Array = InteriorTemplates.grid_for(family, variant_index)
			var size: Vector2i = InteriorTemplates.grid_size(grid)
			var door_cell := InteriorTemplates.door_cell_of(grid)
			# Flood fill from one cell north of the door (the real room,
			# not the door cell itself) -- every non-wall cell in the
			# whole grid must be reachable this way, proving the room is
			# one single enclosed space with no stray disconnected floor.
			var start := door_cell + Vector2i(0, -1)
			var frontier: Array = [start]
			var visited := {start: true}
			while not frontier.is_empty():
				var cell: Vector2i = frontier.pop_back()
				for delta: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var neighbor: Vector2i = cell + delta
					if visited.has(neighbor):
						continue
					if neighbor.x < 0 or neighbor.y < 0 or neighbor.x >= size.x or neighbor.y >= size.y:
						continue
					var ch: String = grid[neighbor.y][neighbor.x]
					if ch == "#":
						continue
					visited[neighbor] = true
					frontier.append(neighbor)
			for y in size.y:
				for x in size.x:
					var ch: String = grid[y][x]
					if ch == "." or ch == "F":
						assert_true(visited.has(Vector2i(x, y)), "%s variant %d (%d,%d) unreachable" % [family, variant_index, x, y])


func test_every_furniture_slot_sits_on_a_floor_cell_never_a_wall_or_the_door():
	for family in _FAMILIES:
		for variant_index in InteriorTemplates.variant_count(family):
			var grid: Array = InteriorTemplates.grid_for(family, variant_index)
			var size: Vector2i = InteriorTemplates.grid_size(grid)
			for y in size.y:
				var row: String = grid[y]
				for x in size.x:
					if row[x] == "F":
						assert_true(x > 0 and y > 0 and x < size.x - 1 and y < size.y - 1, "%s variant %d (%d,%d)" % [family, variant_index, x, y])


# -- furnish(): the real per-house result HouseInteriorView will consume ----

func test_furnish_returns_a_wall_floor_door_and_furniture_cell_for_every_grid_cell():
	var result := InteriorTemplates.furnish("cottage", "farmer", 7)
	var size: Vector2i = result["size"]
	assert_gt(size.x, 0)
	assert_gt(size.y, 0)
	var cells: Dictionary = result["cells"]
	assert_eq(cells.size(), size.x * size.y)
	var seen_door := 0
	for local in cells:
		var value: String = cells[local]
		if value == "door":
			seen_door += 1
	assert_eq(seen_door, 1)


func test_furnish_replaces_every_f_slot_with_a_real_furniture_id_from_the_occupations_set():
	var result := InteriorTemplates.furnish("manor", "merchant", 3)
	var cells: Dictionary = result["cells"]
	var expected_set: Array[String] = HouseDecor.furniture_set_for("merchant")
	var furniture_found := 0
	for local in cells:
		var value: String = cells[local]
		if value == "wall" or value == "floor" or value == "door":
			continue
		assert_true(expected_set.has(value), "%s is not in merchant's own furniture set" % value)
		furniture_found += 1
	assert_gt(furniture_found, 0, "precondition: this template has real furniture slots")


## Cycling: a shape with MORE furniture slots than an occupation's own set
## size reuses set entries rather than leaving a slot as bare floor -- an
## empty room reads as unfinished, and every family's own smallest set
## (guard, 2 items) is smaller than several real shapes' own slot counts.
func test_furnish_cycles_the_furniture_set_when_a_shape_has_more_slots_than_items():
	var result := InteriorTemplates.furnish("manor", "guard", 5)
	var cells: Dictionary = result["cells"]
	var furniture_values: Array = []
	for local in cells:
		var value: String = cells[local]
		if value != "wall" and value != "floor" and value != "door":
			furniture_values.append(value)
	assert_gt(furniture_values.size(), HouseDecor.furniture_set_for("guard").size(), "precondition: more slots than the set has items")
	for value in furniture_values:
		assert_true(HouseDecor.furniture_set_for("guard").has(value))


func test_furnish_is_deterministic_for_the_same_seed():
	var a := InteriorTemplates.furnish("house", "hunter", 11)
	var b := InteriorTemplates.furnish("house", "hunter", 11)
	assert_eq(a["cells"], b["cells"])


func test_furnish_the_same_seed_across_every_real_occupation_never_crashes():
	for occupation in _OCCUPATIONS:
		for family in _FAMILIES:
			var result := InteriorTemplates.furnish(family, occupation, hash(occupation + family))
			assert_false(result.is_empty(), "%s/%s" % [family, occupation])
