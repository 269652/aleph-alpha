extends GutTest

## InteriorTemplates (docs/concept/building.md "Entering"): the authored
## room shapes an entered house switches to -- v2 grammar: multi-room
## layouts (interior `#` partitions with gaps), `w` windows on the outer
## wall, `L` light cells, one `@` cell the resident stands on, and typed
## furniture slots (B bed, T table, C chair/couch, R rug, S shelf/cupboard,
## P picture, K hearth, W workshop piece) that HouseDecor.piece_for_slot
## resolves per occupation -- so a smith's house has an anvil where a
## farmer's has a barrel, rather than one seed-random rectangle. Every
## template is validated here directly, not spot-checked.

const InteriorTemplates = preload("res://src/gameplay/interior_templates.gd")
const HouseDecor = preload("res://src/gameplay/house_decor.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const BuildingPiece = preload("res://src/gameplay/building_piece.gd")

const _FAMILIES := ["cottage", "house", "manor"]
const _OCCUPATIONS := ["farmer", "blacksmith", "merchant", "guard", "fisher", "herbalist", "hunter", "nurse"]
const _SLOT_LETTERS := ["B", "T", "C", "R", "S", "P", "K", "W", "L"]


func _every_grid() -> Array:
	var out: Array = []
	for family in _FAMILIES:
		for variant_index in InteriorTemplates.variant_count(family):
			out.append({"family": family, "variant": variant_index, "grid": InteriorTemplates.grid_for(family, variant_index)})
	return out


func _is_wall(ch: String) -> bool:
	return ch == "#" or ch == "w"


func test_every_building_catalog_interior_family_has_at_least_two_variants():
	for building_id in BuildingCatalog.BUILDING_IDS:
		var family := BuildingCatalog.interior_family_of(building_id)
		assert_gte(InteriorTemplates.variant_count(family), 2, family)


func test_choosing_a_variant_is_deterministic_for_the_same_seed():
	assert_eq(InteriorTemplates.choose_variant_index("cottage", 42), InteriorTemplates.choose_variant_index("cottage", 42))


func test_choosing_a_variant_stays_in_range():
	for family in _FAMILIES:
		for seed_value in 40:
			assert_between(InteriorTemplates.choose_variant_index(family, seed_value), 0, InteriorTemplates.variant_count(family) - 1)


func test_an_unknown_family_falls_back_rather_than_crashing():
	assert_gt(InteriorTemplates.variant_count("not_a_family"), 0)
	assert_false(InteriorTemplates.furnish("not_a_family", "farmer", 1).is_empty())


# -- every template, every family, every variant: real, valid geometry ------

func test_every_character_is_in_the_grammar_and_every_row_is_the_same_width():
	for entry in _every_grid():
		var grid: Array = entry["grid"]
		var width: int = (grid[0] as String).length()
		for y in grid.size():
			var row: String = grid[y]
			assert_eq(row.length(), width, "%s variant %d row %d width" % [entry["family"], entry["variant"], y])
			for x in row.length():
				assert_true(InteriorTemplates.GRAMMAR.contains(row[x]), "%s variant %d (%d,%d): '%s' is not in the grammar" % [entry["family"], entry["variant"], x, y, row[x]])


func test_every_template_is_fully_enclosed_with_exactly_one_door_on_the_south_wall():
	for entry in _every_grid():
		var grid: Array = entry["grid"]
		var size: Vector2i = InteriorTemplates.grid_size(grid)
		var door_count := 0
		var door_row := -1
		for y in size.y:
			var row: String = grid[y]
			for x in size.x:
				var ch := row[x]
				var on_border := x == 0 or y == 0 or x == size.x - 1 or y == size.y - 1
				if ch == "D":
					door_count += 1
					door_row = y
				elif on_border:
					assert_true(_is_wall(ch), "%s variant %d border cell (%d,%d) must be wall or window" % [entry["family"], entry["variant"], x, y])
				elif ch == "w":
					fail_test("%s variant %d: a window at (%d,%d) is not on the outer wall" % [entry["family"], entry["variant"], x, y])
				if ch == "w" and y == size.y - 1:
					fail_test("%s variant %d: a window on the door row (the facade) at (%d,%d)" % [entry["family"], entry["variant"], x, y])
		assert_eq(door_count, 1, "%s variant %d" % [entry["family"], entry["variant"]])
		assert_eq(door_row, size.y - 1, "%s variant %d door must be on the south (last) row" % [entry["family"], entry["variant"]])


func test_every_non_wall_cell_is_reachable_from_the_door_across_every_room():
	for entry in _every_grid():
		var grid: Array = entry["grid"]
		var size: Vector2i = InteriorTemplates.grid_size(grid)
		var door_cell := InteriorTemplates.door_cell_of(grid)
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
				if _is_wall(grid[neighbor.y][neighbor.x]):
					continue
				visited[neighbor] = true
				frontier.append(neighbor)
		for y in size.y:
			for x in size.x:
				var ch: String = grid[y][x]
				if not _is_wall(ch) and ch != "D":
					assert_true(visited.has(Vector2i(x, y)), "%s variant %d (%d,%d) '%s' unreachable" % [entry["family"], entry["variant"], x, y, ch])


func test_slots_and_the_resident_cell_are_interior_never_on_the_border():
	for entry in _every_grid():
		var grid: Array = entry["grid"]
		var size: Vector2i = InteriorTemplates.grid_size(grid)
		for y in size.y:
			var row: String = grid[y]
			for x in size.x:
				if _SLOT_LETTERS.has(row[x]) or row[x] == "@":
					assert_true(x > 0 and y > 0 and x < size.x - 1 and y < size.y - 1, "%s variant %d (%d,%d)" % [entry["family"], entry["variant"], x, y])


func test_every_template_has_exactly_one_resident_cell_and_at_least_one_light():
	for entry in _every_grid():
		var grid: Array = entry["grid"]
		var residents := 0
		var lights := 0
		for row in grid:
			residents += (row as String).count("@")
			lights += (row as String).count("L")
		assert_eq(residents, 1, "%s variant %d" % [entry["family"], entry["variant"]])
		assert_gte(lights, 1, "%s variant %d needs a light source" % [entry["family"], entry["variant"]])


## "Small outside, big inside": a house and a manor are more than one
## room -- at least one interior partition wall each (a cottage may be a
## single room).
func test_houses_and_manors_have_more_than_one_room():
	for entry in _every_grid():
		if entry["family"] == "cottage":
			continue
		var grid: Array = entry["grid"]
		var size: Vector2i = InteriorTemplates.grid_size(grid)
		var interior_walls := 0
		for y in range(1, size.y - 1):
			for x in range(1, size.x - 1):
				if grid[y][x] == "#":
					interior_walls += 1
		assert_gt(interior_walls, 0, "%s variant %d is a single room" % [entry["family"], entry["variant"]])


# -- HouseDecor.piece_for_slot: the occupation decides what fills a slot ----

func test_every_slot_letter_resolves_to_a_real_furniture_piece_for_every_occupation():
	for occupation in _OCCUPATIONS:
		for letter in _SLOT_LETTERS:
			var piece_id := HouseDecor.piece_for_slot(letter, occupation)
			assert_true(BuildingPiece.has_piece(piece_id), "%s/%s -> '%s'" % [occupation, letter, piece_id])
			assert_eq(BuildingPiece.category_of(piece_id), BuildingPiece.CATEGORY_FURNITURE, "%s/%s -> %s" % [occupation, letter, piece_id])


func test_the_workshop_slot_is_the_occupations_own_tool():
	assert_eq(HouseDecor.piece_for_slot("W", "blacksmith"), "anvil")
	assert_eq(HouseDecor.piece_for_slot("W", "herbalist"), "workbench")
	assert_eq(HouseDecor.piece_for_slot("W", "farmer"), "barrel")
	assert_eq(HouseDecor.piece_for_slot("W", "fisher"), "crate")
	assert_eq(HouseDecor.piece_for_slot("W", "hunter"), "chest")


func test_a_merchant_sits_on_a_couch_and_shelves_books_while_a_farmer_has_a_chair_and_a_cupboard():
	assert_eq(HouseDecor.piece_for_slot("C", "merchant"), "couch")
	assert_eq(HouseDecor.piece_for_slot("C", "farmer"), "wood_chair")
	assert_eq(HouseDecor.piece_for_slot("S", "merchant"), "wood_bookshelf")
	assert_eq(HouseDecor.piece_for_slot("S", "farmer"), "cupboard")


func test_every_home_has_a_hearth_a_bed_and_a_candle_regardless_of_occupation():
	for occupation in _OCCUPATIONS:
		assert_eq(HouseDecor.piece_for_slot("K", occupation), "hearth", occupation)
		assert_eq(HouseDecor.piece_for_slot("B", occupation), "wood_bed", occupation)
		assert_eq(HouseDecor.piece_for_slot("L", occupation), "candle", occupation)


func test_an_unknown_letter_or_occupation_still_furnishes_something_real():
	assert_true(BuildingPiece.has_piece(HouseDecor.piece_for_slot("W", "not_an_occupation")))
	assert_true(BuildingPiece.has_piece(HouseDecor.piece_for_slot("C", "not_an_occupation")))


# -- furnish(): the real per-house result HouseInteriorView will consume ----

func test_furnish_returns_a_value_for_every_grid_cell_with_exactly_one_door():
	var result := InteriorTemplates.furnish("cottage", "farmer", 7)
	var size: Vector2i = result["size"]
	assert_gt(size.x, 0)
	assert_gt(size.y, 0)
	var cells: Dictionary = result["cells"]
	assert_eq(cells.size(), size.x * size.y)
	var seen_door := 0
	for local in cells:
		if cells[local] == "door":
			seen_door += 1
	assert_eq(seen_door, 1)


func test_furnish_maps_walls_windows_floor_and_slots_and_exposes_resident_and_light_cells():
	var result := InteriorTemplates.furnish("house", "blacksmith", 3)
	var grid: Array = InteriorTemplates.grid_for("house", result["variant_index"])
	var cells: Dictionary = result["cells"]
	var size: Vector2i = result["size"]
	for y in size.y:
		for x in size.x:
			var ch: String = grid[y][x]
			var value: String = cells[Vector2i(x, y)]
			match ch:
				"#": assert_eq(value, "wall", str(Vector2i(x, y)))
				"w": assert_eq(value, "window", str(Vector2i(x, y)))
				"D": assert_eq(value, "door", str(Vector2i(x, y)))
				".", "@": assert_eq(value, "floor", str(Vector2i(x, y)))
				_: assert_eq(value, HouseDecor.piece_for_slot(ch, "blacksmith"), str(Vector2i(x, y)))
	var resident_cell: Vector2i = result["resident_cell"]
	assert_eq(cells[resident_cell], "floor", "the resident stands on a floor cell")
	assert_eq(grid[resident_cell.y][resident_cell.x], "@")
	var light_cells: Array = result["light_cells"]
	assert_gt(light_cells.size(), 0)
	for cell in light_cells:
		assert_eq(cells[cell], "candle")


func test_the_same_shape_is_furnished_differently_for_a_smith_and_a_farmer():
	var smith := InteriorTemplates.furnish("cottage", "blacksmith", 5)
	var farmer := InteriorTemplates.furnish("cottage", "farmer", 5)
	assert_eq(smith["variant_index"], farmer["variant_index"], "precondition: same shape")
	assert_true(smith["cells"].values().has("anvil"), "a smith's home has an anvil")
	assert_false(farmer["cells"].values().has("anvil"), "a farmer's does not")
	assert_true(farmer["cells"].values().has("barrel"), "a farmer's home has a barrel")


func test_furnish_is_deterministic_for_the_same_seed():
	var a := InteriorTemplates.furnish("house", "hunter", 11)
	var b := InteriorTemplates.furnish("house", "hunter", 11)
	assert_eq(a["cells"], b["cells"])
	assert_eq(a["resident_cell"], b["resident_cell"])


func test_furnish_the_same_seed_across_every_real_occupation_never_crashes():
	for occupation in _OCCUPATIONS:
		for family in _FAMILIES:
			var result := InteriorTemplates.furnish(family, occupation, hash(occupation + family))
			assert_false(result.is_empty(), "%s/%s" % [family, occupation])


## InteriorTemplates.UNFURNISHED (a player's own house starts empty -- you
## decorate your own home, see docs/concept/housing.md): every slot is
## plain floor, the shape is otherwise identical.
func test_the_unfurnished_occupation_turns_every_slot_into_floor():
	var bare := InteriorTemplates.furnish("manor", InteriorTemplates.UNFURNISHED, 6)
	var furnished := InteriorTemplates.furnish("manor", "merchant", 6)
	assert_eq(bare["size"], furnished["size"])
	assert_eq(bare["door_cell"], furnished["door_cell"])
	for local in bare["cells"]:
		var value: String = bare["cells"][local]
		assert_true(value in ["wall", "window", "door", "floor"], "%s: %s" % [str(local), value])
	assert_true(bare["light_cells"].is_empty(), "no candles either -- the room is truly bare")


## piece_grid: the wall/door/floor grid FurniturePlacement reads to decide
## where a player may put furniture (walls and doors are never floor).
func test_piece_grid_maps_the_shape_to_real_piece_ids():
	var grid: Dictionary = InteriorTemplates.piece_grid("cottage", 7)
	var shape := InteriorTemplates.furnish("cottage", InteriorTemplates.UNFURNISHED, 7)
	assert_eq(grid.size(), shape["cells"].size())
	for local in shape["cells"]:
		match shape["cells"][local]:
			"wall": assert_eq(grid[local], "wood_wall", str(local))
			"window": assert_eq(grid[local], "wood_window", str(local))
			"door": assert_eq(grid[local], "wood_door", str(local))
			_: assert_eq(grid[local], "wood_floor", str(local))
