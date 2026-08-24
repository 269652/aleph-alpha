extends GutTest

## HouseBlueprint: a CATALOG of named house shapes, each a seed away from a
## real piece list (see docs/concept/building.md#one-system-two-builders
## and docs/concept/building.md#a-blueprint-catalog-not-one-box).
##
## This is what makes an NPC village house a REAL house: the settlement
## generator stamps blueprints made of the same pieces the player places by
## hand, so anything true of a player's house is true of a villager's.
## Before this, every village house was the exact same 5x4 wall-ring box --
## reported directly: "the houses the npcs build are minimal and don't look
## neat and diverse... we want blueprints which function as a template/
## recipe for npcs building their houses... enough different blueprints
## that every house in a village can look different." Now there are many
## named shapes (small huts through wide/tall/bright cottages to L-shaped
## manors), spanning real footprint sizes, window counts, and -- for the L
## shapes -- a genuinely non-rectangular silhouette, all built from the same
## safe, tested geometric primitives (a rectangle, a door punched through
## one wall, windows punched through others, a corner notch carved out) so
## every single one is provably a real, enclosable room, not hand-pixeled
## ASCII art that could silently break.

const HouseBlueprint = preload("res://src/gameplay/house_blueprint.gd")
const BuildingPiece = preload("res://src/gameplay/building_piece.gd")
const RoomDetector = preload("res://src/gameplay/room_detector.gd")
const NpcGenome = preload("res://src/world/npc_genome.gd")

var blueprint: HouseBlueprint


func before_each():
	blueprint = HouseBlueprint.new()


# -- the catalog itself -------------------------------------------------------

func test_the_catalog_has_enough_blueprints_for_a_whole_village_to_look_different():
	# SettlementGenerator.POPULATION is 5 -- comfortably more blueprints than
	# that so even one settlement never has to repeat a shape, with margin
	# for a player visiting several villages before patterns repeat.
	assert_gte(HouseBlueprint.BLUEPRINT_IDS.size(), 8)


func test_every_blueprint_id_is_unique():
	var seen := {}
	for blueprint_id in HouseBlueprint.BLUEPRINT_IDS:
		assert_false(seen.has(blueprint_id), "duplicate blueprint id: %s" % blueprint_id)
		seen[blueprint_id] = true


func test_footprint_for_is_known_for_every_catalog_entry():
	for blueprint_id in HouseBlueprint.BLUEPRINT_IDS:
		var footprint: Vector2i = blueprint.footprint_for(blueprint_id)
		assert_gte(footprint.x, HouseBlueprint.MINIMUM_FOOTPRINT, blueprint_id)
		assert_gte(footprint.y, HouseBlueprint.MINIMUM_FOOTPRINT, blueprint_id)


## Real diversity, not just a longer list of the same size -- otherwise
## "enough blueprints" is technically true but visually meaningless.
func test_footprints_are_not_all_the_same_size():
	var seen := {}
	for blueprint_id in HouseBlueprint.BLUEPRINT_IDS:
		seen[blueprint.footprint_for(blueprint_id)] = true
	assert_gt(seen.size(), 1, "every blueprint has the exact same footprint")


func test_an_unknown_blueprint_id_builds_nothing():
	assert_eq(blueprint.build("not_a_real_blueprint", 1).size(), 0)
	assert_eq(blueprint.build_roofs("not_a_real_blueprint", 1).size(), 0)


# -- every blueprint is a REAL, enclosable house -------------------------------

## The whole point, for every single catalog entry: a generated house must
## actually enclose a room, exactly as a hand-built one does. If this fails
## for even one blueprint, that blueprint's houses are scenery, not
## buildings.
func test_every_blueprint_encloses_exactly_one_real_room():
	for blueprint_id in HouseBlueprint.BLUEPRINT_IDS:
		var pieces := blueprint.build(blueprint_id, 3)
		var rooms := RoomDetector.new().find_rooms(pieces)
		assert_eq(rooms.size(), 1, "%s should enclose exactly one room" % blueprint_id)
		assert_gt(rooms[0].size(), 0, blueprint_id)


func test_every_blueprint_has_exactly_one_door():
	for blueprint_id in HouseBlueprint.BLUEPRINT_IDS:
		for seed_value in range(6):
			var pieces := blueprint.build(blueprint_id, seed_value)
			var doors := 0
			for cell in pieces:
				if BuildingPiece.category_of(pieces[cell]) == BuildingPiece.CATEGORY_DOOR:
					doors += 1
			assert_eq(doors, 1, "%s seed %d should have exactly one way in" % [blueprint_id, seed_value])


func test_every_blueprint_has_walls_floors_and_a_door():
	for blueprint_id in HouseBlueprint.BLUEPRINT_IDS:
		var pieces := blueprint.build(blueprint_id, 2)
		var categories := {}
		for cell in pieces:
			categories[BuildingPiece.category_of(pieces[cell])] = true
		for category in [BuildingPiece.CATEGORY_FLOOR, BuildingPiece.CATEGORY_WALL, BuildingPiece.CATEGORY_DOOR]:
			assert_true(categories.has(category), "%s needs %s pieces" % [blueprint_id, category])


func test_every_blueprint_is_deterministic():
	for blueprint_id in HouseBlueprint.BLUEPRINT_IDS:
		assert_eq(blueprint.build(blueprint_id, 9), blueprint.build(blueprint_id, 9), blueprint_id)


func test_every_blueprint_stays_within_its_own_footprint():
	for blueprint_id in HouseBlueprint.BLUEPRINT_IDS:
		var footprint: Vector2i = blueprint.footprint_for(blueprint_id)
		for cell in blueprint.build(blueprint_id, 4):
			assert_between(cell.x, 0, footprint.x - 1, blueprint_id)
			assert_between(cell.y, 0, footprint.y - 1, blueprint_id)


func test_every_blueprints_roofs_cover_only_real_floor_cells():
	for blueprint_id in HouseBlueprint.BLUEPRINT_IDS:
		var pieces := blueprint.build(blueprint_id, 1)
		var roofs := blueprint.build_roofs(blueprint_id, 1)
		assert_gt(roofs.size(), 0, "%s should be roofed" % blueprint_id)
		for cell in roofs:
			assert_eq(BuildingPiece.category_of(roofs[cell]), BuildingPiece.CATEGORY_ROOF, blueprint_id)
			assert_eq(
				BuildingPiece.category_of(pieces.get(cell, "")), BuildingPiece.CATEGORY_FLOOR,
				"%s roofs a cell (%s) that isn't real floor" % [blueprint_id, cell]
			)


func test_material_follows_the_requested_tier_for_every_blueprint():
	for blueprint_id in HouseBlueprint.BLUEPRINT_IDS:
		var stone := blueprint.build(blueprint_id, 1, BuildingPiece.MATERIAL_STONE)
		for cell in stone:
			assert_eq(BuildingPiece.material_of(stone[cell]), BuildingPiece.MATERIAL_STONE, blueprint_id)


## Different seeds give visibly different houses within the SAME blueprint
## too -- a village of five identical "cottage_small" huts is the same
## problem the old single-box design had, just renamed.
func test_different_seeds_place_the_door_differently_within_one_blueprint():
	var doors := {}
	for seed_value in range(20):
		var pieces := blueprint.build(HouseBlueprint.BLUEPRINT_IDS[0], seed_value)
		for cell in pieces:
			if BuildingPiece.category_of(pieces[cell]) == BuildingPiece.CATEGORY_DOOR:
				doors[cell] = true
	assert_gt(doors.size(), 1, "houses should not all have their door in the same place")


# -- windows: real variety, actually placed ------------------------------------

func test_window_count_varies_across_the_catalog():
	var counts := {}
	for blueprint_id in HouseBlueprint.BLUEPRINT_IDS:
		var pieces := blueprint.build(blueprint_id, 1)
		var window_count := 0
		for cell in pieces:
			if BuildingPiece.category_of(pieces[cell]) == BuildingPiece.CATEGORY_WINDOW:
				window_count += 1
		counts[window_count] = true
	assert_gt(counts.size(), 1, "every blueprint has the exact same window count")


func test_at_least_one_blueprint_has_no_windows_at_all():
	var found := false
	for blueprint_id in HouseBlueprint.BLUEPRINT_IDS:
		var pieces := blueprint.build(blueprint_id, 1)
		var has_window := false
		for cell in pieces:
			if BuildingPiece.category_of(pieces[cell]) == BuildingPiece.CATEGORY_WINDOW:
				has_window = true
				break
		if not has_window:
			found = true
			break
	assert_true(found, "a small, plain hut with no windows should still exist in the catalog")


func test_at_least_one_blueprint_has_multiple_windows():
	var found := false
	for blueprint_id in HouseBlueprint.BLUEPRINT_IDS:
		var pieces := blueprint.build(blueprint_id, 1)
		var window_count := 0
		for cell in pieces:
			if BuildingPiece.category_of(pieces[cell]) == BuildingPiece.CATEGORY_WINDOW:
				window_count += 1
		if window_count >= 2:
			found = true
			break
	assert_true(found, "a bright, well-lit house should exist in the catalog")


## A window is never placed on a footprint corner -- a corner window would
## open onto the wall's own thickness, same rule the door already follows.
func test_windows_never_land_on_a_corner():
	for blueprint_id in HouseBlueprint.BLUEPRINT_IDS:
		var footprint: Vector2i = blueprint.footprint_for(blueprint_id)
		for seed_value in range(6):
			var pieces := blueprint.build(blueprint_id, seed_value)
			for cell in pieces:
				if BuildingPiece.category_of(pieces[cell]) != BuildingPiece.CATEGORY_WINDOW:
					continue
				var on_corner: bool = (
					(cell.x == 0 or cell.x == footprint.x - 1)
					and (cell.y == 0 or cell.y == footprint.y - 1)
				)
				assert_false(on_corner, "%s seed %d: window at corner %s" % [blueprint_id, seed_value, cell])


# -- L-shaped blueprints: a genuinely non-rectangular silhouette --------------

## At least one blueprint must have a real notch -- fewer cells than its
## own bounding rectangle -- or "diverse silhouettes" is just a marketing
## claim over a pile of same-shaped boxes.
func test_at_least_one_blueprint_has_a_non_rectangular_silhouette():
	var found := false
	for blueprint_id in HouseBlueprint.BLUEPRINT_IDS:
		var footprint: Vector2i = blueprint.footprint_for(blueprint_id)
		var pieces := blueprint.build(blueprint_id, 1)
		if pieces.size() < footprint.x * footprint.y:
			found = true
			break
	assert_true(found, "at least one blueprint should carve a corner notch out of its bounding rectangle")


# -- blueprint selection: NPC choice, not raw noise ----------------------------

const _TRAIT_NAMES := ["friendly", "gruff", "curious", "stoic", "greedy", "kind", "cautious", "bold"]


func test_choose_blueprint_id_always_returns_a_real_catalog_entry():
	for seed_value in range(30):
		var genome := NpcGenome.new(seed_value, _TRAIT_NAMES)
		var chosen := blueprint.choose_blueprint_id("farmer", genome, seed_value)
		assert_true(HouseBlueprint.BLUEPRINT_IDS.has(chosen), "seed %d: %s" % [seed_value, chosen])


func test_choose_blueprint_id_is_deterministic():
	var genome := NpcGenome.new(7, _TRAIT_NAMES)
	assert_eq(
		blueprint.choose_blueprint_id("merchant", genome, 7),
		blueprint.choose_blueprint_id("merchant", genome, 7)
	)


func test_unknown_occupations_fall_back_to_the_whole_catalog_rather_than_crashing():
	var genome := NpcGenome.new(1, _TRAIT_NAMES)
	var chosen := blueprint.choose_blueprint_id("not_a_real_occupation", genome, 1)
	assert_true(HouseBlueprint.BLUEPRINT_IDS.has(chosen))


## Every known occupation must actually be able to pick more than one
## blueprint -- otherwise "tied to occupation" degenerates into "every
## farmer's house is blueprint X", exactly the sameness this whole change
## exists to fix.
func test_every_occupation_can_choose_more_than_one_blueprint():
	const NpcIdentity = preload("res://src/world/npc_identity.gd")
	for occupation in NpcIdentity.OCCUPATIONS:
		var seen := {}
		for seed_value in range(60):
			var genome := NpcGenome.new(seed_value, _TRAIT_NAMES)
			seen[blueprint.choose_blueprint_id(occupation, genome, seed_value)] = true
		assert_gt(seen.size(), 1, "%s never varies its house choice" % occupation)


## A "bold"/"greedy"-dominant NPC should, on average, land on a LARGER
## (more floor-cell) house than a "cautious"/"stoic"-dominant one with the
## same occupation -- the actual, measurable shape of "personality nudges
## the choice" rather than an assertion that only checks the code ran.
func test_showy_personalities_trend_toward_bigger_houses_than_plain_ones():
	var showy_total := 0
	var showy_count := 0
	var plain_total := 0
	var plain_count := 0
	for seed_value in range(200):
		var genome := NpcGenome.new(seed_value, _TRAIT_NAMES)
		var chosen := blueprint.choose_blueprint_id("merchant", genome, seed_value)
		var footprint: Vector2i = blueprint.footprint_for(chosen)
		var area := footprint.x * footprint.y
		var dominant := genome.dominant_trait()
		if dominant == "bold" or dominant == "greedy":
			showy_total += area
			showy_count += 1
		elif dominant == "cautious" or dominant == "stoic":
			plain_total += area
			plain_count += 1
	assert_gt(showy_count, 0, "precondition: at least one showy-dominant sample")
	assert_gt(plain_count, 0, "precondition: at least one plain-dominant sample")
	var showy_average := float(showy_total) / float(showy_count)
	var plain_average := float(plain_total) / float(plain_count)
	assert_gt(showy_average, plain_average, "showy personalities should trend toward bigger houses")
