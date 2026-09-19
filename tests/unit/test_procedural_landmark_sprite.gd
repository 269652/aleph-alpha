extends GutTest

## ProceduralLandmarkSprite: art for a settlement's well/stall/gate (see
## VillageRenderer) -- previously invisible positions NPCs walked to.

const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const ProceduralLandmarkSprite = preload("res://src/rendering/procedural_landmark_sprite.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")

var generator := ProceduralLandmarkSprite.new()


func test_every_landmark_id_renders_at_its_pinned_size():
	for landmark_id in ProceduralLandmarkSprite.LANDMARK_IDS:
		var size: Vector2i = ProceduralLandmarkSprite.SIZES[landmark_id]
		var image := generator.generate_image(landmark_id)
		assert_eq(Vector2i(image.get_width(), image.get_height()), size, "wrong size for %s" % landmark_id)


func test_is_deterministic():
	for landmark_id in ProceduralLandmarkSprite.LANDMARK_IDS:
		assert_eq(
			generator.generate_image(landmark_id).get_data(),
			generator.generate_image(landmark_id).get_data()
		)


func test_the_three_landmarks_look_different_from_each_other():
	var well := generator.generate_image("well")
	var stall := generator.generate_image("stall")
	var gate := generator.generate_image("gate")
	assert_ne(well.get_data(), stall.get_data())
	assert_ne(stall.get_data(), gate.get_data())
	assert_ne(well.get_data(), gate.get_data())


func test_has_transparent_corners():
	for landmark_id in ProceduralLandmarkSprite.LANDMARK_IDS:
		var image := generator.generate_image(landmark_id)
		assert_eq(image.get_pixel(0, 0).a, 0.0, "%s should have a transparent corner" % landmark_id)


## The well must read as a well: stone ring AND dark water core, not one
## flat blob.
func test_well_has_both_stone_and_water_pixels():
	var image := generator.generate_image("well")
	assert_true(_has_color_near(image, ProceduralLandmarkSprite.STONE_COLOR), "well should have stone pixels")
	assert_true(_has_color_near(image, ProceduralLandmarkSprite.WATER_COLOR), "well should have water pixels")


## The stall must carry both awning stripe colors.
func test_stall_awning_is_striped_in_two_colors():
	var image := generator.generate_image("stall")
	assert_true(_has_color_near(image, ProceduralLandmarkSprite.AWNING_A))
	assert_true(_has_color_near(image, ProceduralLandmarkSprite.AWNING_B))


# -- per-occupation workspot props (see VillageRenderer, npc_planner.gd's
# FakeNpcPlanner._WORK_LOCATION_BY_OCCUPATION -- reported: "the houses...
# maybe we need... enough different blueprints", and the same follow-up ask
# to close the remaining gap: a farmer/blacksmith/fisher/herbalist's own
# workspot was an invisible position they walked to and stood on empty
# grass, unlike merchant (personal stall) and guard (shared gate), which
# both already had something real there) ---------------------------------

## field (farmer), forge (blacksmith), dock (fisher), garden (herbalist) --
## the same tag names FakeNpcPlanner._WORK_LOCATION_BY_OCCUPATION already
## uses for these occupations' work location_tag, so the prop a player sees
## is literally the place the schedule sends that villager.
func test_every_occupation_workspot_prop_exists_in_the_catalog():
	for landmark_id in ["field", "forge", "dock", "garden"]:
		assert_true(ProceduralLandmarkSprite.LANDMARK_IDS.has(landmark_id), landmark_id)


func test_every_landmark_looks_different_from_every_other():
	var seen: Array[PackedByteArray] = []
	for landmark_id in ProceduralLandmarkSprite.LANDMARK_IDS:
		var data := generator.generate_image(landmark_id).get_data()
		for other in seen:
			assert_ne(data, other, landmark_id)
		seen.append(data)


## The field must read as tilled soil with real crop growth on it, not a
## bare dirt rectangle -- a farmer's plot should look worked.
func test_field_has_both_soil_and_crop_pixels():
	var image := generator.generate_image("field")
	assert_true(_has_color_near(image, ProceduralLandmarkSprite.SOIL_COLOR), "field should have soil pixels")
	assert_true(_has_color_near(image, ProceduralLandmarkSprite.CROP_COLOR), "field should have crop pixels")


## The forge must read as a forge: a stone furnace AND glowing embers, not
## just a grey block.
func test_forge_has_both_stone_and_ember_pixels():
	var image := generator.generate_image("forge")
	assert_true(_has_color_near(image, ProceduralLandmarkSprite.STONE_COLOR), "forge should have stone pixels")
	assert_true(_has_color_near(image, ProceduralLandmarkSprite.EMBER_COLOR), "forge should have ember pixels")


## The dock must read as real wooden planking over water, not a plain plank
## on grass.
func test_dock_has_both_wood_and_water_pixels():
	var image := generator.generate_image("dock")
	assert_true(_has_color_near(image, ProceduralLandmarkSprite.WOOD_COLOR), "dock should have wood pixels")
	assert_true(_has_color_near(image, ProceduralLandmarkSprite.WATER_COLOR), "dock should have water pixels")


## The garden must read as a real herb bed: tilled soil AND herb foliage,
## and that foliage must be its OWN colour, not the same green a farmer's
## crop uses (they should not read as the same plot).
func test_garden_has_both_soil_and_its_own_herb_color():
	var image := generator.generate_image("garden")
	assert_true(_has_color_near(image, ProceduralLandmarkSprite.SOIL_COLOR), "garden should have soil pixels")
	assert_true(_has_color_near(image, ProceduralLandmarkSprite.HERB_COLOR), "garden should have herb pixels")
	assert_false(
		_has_color_near(image, ProceduralLandmarkSprite.CROP_COLOR),
		"garden herbs should read as their own thing, not a farmer's crop"
	)


## Reported live: "there are 3 wells and one stand all over the place."
## A village has exactly ONE well, on its own square (docs/concept/
## village_growth.md's street-village grounding: "a widened square at the
## middle carrying the well, the market stall and the civic building").
## The other two were HUNTERS: a hunter's workspot prop is tagged
## "hunting_ground", which had no drawing of its own and so fell through
## generate_image's unknown-id fallback to the WELL's -- measured on the
## real load path, not deduced (tools/probe_village_props.gd: every hunter
## in every sampled village stood a second well-looking prop out in the
## fields behind the houses, and a village rolling two hunters showed
## three wells in total).
##
## The fallback below is still right for a genuinely unknown id; what was
## wrong is that a real, shipped occupation's own workspot was reaching it.
func test_a_hunters_workspot_prop_is_not_drawn_as_the_villages_own_well():
	assert_ne(
		generator.generate_image("hunting_ground").get_data(),
		generator.generate_image("well").get_data(),
		"a hunter's spot must be its own thing, not a second well"
	)


## The cross-pin that would have caught the above: every occupation this
## game actually ships works somewhere, and VillageRenderer renders a prop
## at that tag for any of them the settlement's shared landmarks do not
## already cover. A tag this catalog cannot draw does not fail loudly -- it
## quietly draws a well, which is exactly how three of them ended up in one
## village. Driven off NpcIdentity's own table rather than a hand-copied
## list, so a NEW occupation with a new work tag fails here instead of in
## somebody's screenshot.
## An occupation's workplace is either a PROP this catalog draws, or a real
## BUILDING the village raises -- and it must be one of the two, because
## anything else falls back to the well and plants a spurious well at that
## villager's workspot. A lumberjack works at the sawmill, which is a real
## building now, so the rule had to grow rather than the lumberjack being
## forced to own a prop that would stand on top of it.
func test_every_occupation_works_somewhere_that_can_actually_be_drawn():
	for occupation in NpcIdentity.WORK_LOCATION_BY_OCCUPATION:
		var work_tag: String = NpcIdentity.WORK_LOCATION_BY_OCCUPATION[occupation]
		assert_true(
			ProceduralLandmarkSprite.LANDMARK_IDS.has(work_tag) or BuildingCatalog.has_building(work_tag),
			"%s works at '%s', which is neither a prop nor a building -- it would fall back to the well" % [occupation, work_tag]
		)


## A hunter's spot reads as a hunter's: a wooden rack with a hide stretched
## on it (the drying rack a real hunter's kill actually ends up on), so it
## cannot be mistaken for the well, the stall's awning, or a farmer's crop.
func test_hunting_ground_has_both_wood_and_hide_pixels():
	var image := generator.generate_image("hunting_ground")
	assert_true(_has_color_near(image, ProceduralLandmarkSprite.WOOD_COLOR), "the rack should be wooden")
	assert_true(_has_color_near(image, ProceduralLandmarkSprite.HIDE_COLOR), "a hide should hang on it")
	assert_false(
		_has_color_near(image, ProceduralLandmarkSprite.WATER_COLOR),
		"nothing on a hunter's rack is the well's dark water"
	)


func test_unknown_id_falls_back_to_the_well():
	assert_eq(
		generator.generate_image("not_a_landmark").get_data(),
		generator.generate_image("well").get_data()
	)


func test_generate_texture_returns_an_image_texture():
	var texture := generator.generate_texture("gate")
	assert_eq(texture.get_width(), ProceduralLandmarkSprite.SIZES["gate"].x)


func _has_color_near(image: Image, target: Color) -> bool:
	for y in image.get_height():
		for x in image.get_width():
			var p := image.get_pixel(x, y)
			if p.a > 0.0 and Vector3(p.r, p.g, p.b).distance_to(Vector3(target.r, target.g, target.b)) < 0.04:
				return true
	return false


# -- how big a prop really is beside the buildings it stands among ----------

const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")


## Reported live with the village in shot: "the stands are way too big".
##
## A prop's SIZES entry is its real world width, and LandmarkSheet.world_
## scaled_image scales whatever art is supplied to exactly that -- so this
## number, not the art, is what decides how big a stall looks. At 52 world
## pixels it stood 3.25 tiles wide on a 16-pixel grid: wider than the
## cottages it sells in front of, and nearly as wide as the city hall.
##
## A market stall is a table under an awning -- narrower than the cottage it
## sells in front of, which is the rule this number is derived from rather
## than a width chosen for itself (see
## test_a_stall_is_strictly_narrower_than_the_smallest_cottage below, and
## docs/concept/village_market_square.md). Two tiles was exactly the smallest
## cottage's own width, which is equal rather than narrower -- reported a
## second time, with the square in shot: "the stand is too big and it's
## placed ontop of a house".
func test_a_stall_is_narrower_than_a_cottage_and_wider_than_a_post():
	var width: int = ProceduralLandmarkSprite.SIZES["stall"].x
	assert_lt(width, TerrainRenderer.TILE_SIZE * 2, "narrower than the smallest cottage")
	assert_gt(width, TerrainRenderer.TILE_SIZE, "and still a table, not a post")


## Whatever a stall's width becomes, its drawn proportions have to stay the
## ones the art was authored in -- a stall squashed or stretched to fit a
## new width would be a different bug wearing the fix's clothes.
func test_shrinking_the_stall_kept_its_proportions():
	var stall: Vector2i = ProceduralLandmarkSprite.SIZES["stall"]
	assert_almost_eq(
		float(stall.y) / float(stall.x), 44.0 / 52.0, 0.03,
		"the same aspect the stall was drawn at, just smaller"
	)


# -- a stall is narrower than what it sells in front of ---------------------
#
# Reported twice. First *"the stands are way too big"*, which cut the stall
# from 52 to 32; then, with the square in shot, *"the stand is too big and
# it's placed ontop of a house"*. 32 is exactly 2 tiles, and the smallest
# house in the catalog is exactly 2 tiles wide -- the rule the cut was made
# against was "narrower than the cottages it sells in front of", and equal is
# not narrower.

## The narrowest house a village can raise, in tiles -- read off the catalog
## rather than restated, so a new, smaller cottage makes this fail loudly.
func _narrowest_house_tiles() -> int:
	var narrowest := 99
	for building_id in BuildingCatalog.BUILDING_IDS:
		if BuildingCatalog.capacity_of(building_id) <= 0:
			continue
		narrowest = mini(narrowest, BuildingCatalog.footprint_of(building_id).x)
	return narrowest


func test_a_stall_is_strictly_narrower_than_the_smallest_cottage():
	var stall_tiles := (
		float(ProceduralLandmarkSprite.SIZES["stall"].x) / float(TerrainRenderer.TILE_SIZE)
	)
	assert_lt(
		stall_tiles, float(_narrowest_house_tiles()),
		"a stall is a table under an awning, not a building"
	)


## And still wide enough to read as a table with an awning over it rather
## than a post: over a tile of frontage.
func test_a_stall_is_still_wider_than_a_single_tile():
	assert_gt(float(ProceduralLandmarkSprite.SIZES["stall"].x) / float(TerrainRenderer.TILE_SIZE), 1.0)
