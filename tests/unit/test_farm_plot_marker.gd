extends GutTest

## The visible, player-facing counterpart to FarmPlot (docs/concept/
## farming.md's "farming loop") -- wraps one FarmPlot instance and draws its
## current state (tilled soil + growth-staged crop leaves, the SAME
## IllustratedCropSprite art wild carrot/potato patches already use). Mirrors
## test_wild_crop_marker.gd's real-scene-tree/real-art setup.

const FarmPlotMarker = preload("res://src/rendering/farm_plot_marker.gd")
const FarmPlot = preload("res://src/gameplay/farm_plot.gd")
const IllustratedGrassPatch = preload("res://src/rendering/illustrated_grass_patch.gd")
const IllustratedWheatPatch = preload("res://src/rendering/illustrated_wheat_patch.gd")
## The bed's soil has to cover exactly one REAL world tile, not a number of
## its own -- see test_a_bed_draws_a_full_tile_of_tilled_earth.
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

var marker: FarmPlotMarker


func before_each():
	marker = FarmPlotMarker.new()


func after_each():
	if is_instance_valid(marker):
		marker.free()


func test_joins_the_farm_plot_group():
	add_child_autofree(marker)
	assert_true(marker.is_in_group(FarmPlotMarker.GROUP_NAME))


func test_starts_with_an_empty_plot():
	add_child_autofree(marker)
	assert_eq(marker.plot.state, "empty")


func test_till_and_plant_starts_growth():
	add_child_autofree(marker)
	var planted := marker.till_and_plant("carrot", 42)
	assert_true(planted)
	assert_eq(marker.plot.state, "growing")
	assert_eq(marker.plot.crop_id, "carrot")


func test_till_and_plant_refuses_to_disturb_a_growing_plot():
	add_child_autofree(marker)
	marker.till_and_plant("carrot", 42)
	var replanted := marker.till_and_plant("potato", 7)
	assert_false(replanted, "a live crop must never be silently overwritten")
	assert_eq(marker.plot.crop_id, "carrot")


func test_till_and_plant_refuses_to_disturb_a_ready_plot():
	add_child_autofree(marker)
	marker.till_and_plant("carrot", 42)
	_grow_to_ready(marker)
	var replanted := marker.till_and_plant("potato", 7)
	assert_false(replanted, "an unharvested ready crop must never be silently overwritten")
	assert_eq(marker.plot.state, "ready")


func test_till_and_plant_succeeds_again_over_a_withered_plot():
	add_child_autofree(marker)
	marker.till_and_plant("carrot", 42)
	marker.plot.advance(marker.plot.growth_time * FarmPlot.WATER_GRACE_FRACTION + 0.01)
	assert_eq(marker.plot.state, "withered")
	var replanted := marker.till_and_plant("potato", 7)
	assert_true(replanted)
	assert_eq(marker.plot.state, "growing")
	assert_eq(marker.plot.crop_id, "potato")


func test_advance_ticks_the_underlying_plot():
	add_child_autofree(marker)
	marker.till_and_plant("carrot", 42)
	marker.advance(1.0)
	assert_eq(marker.plot.time_growing, 1.0)


func test_water_resets_the_neglect_clock_while_growing():
	add_child_autofree(marker)
	marker.till_and_plant("carrot", 42)
	marker.advance(marker.plot.growth_time * FarmPlot.WATER_GRACE_FRACTION - 0.1)
	var watered := marker.water()
	assert_true(watered)
	assert_eq(marker.plot.time_since_watered, 0.0)


func test_water_is_a_noop_with_nothing_planted():
	add_child_autofree(marker)
	var watered := marker.water()
	assert_false(watered)


func test_harvest_on_a_ready_plot_returns_a_positive_count_and_clears_the_leaves():
	add_child_autofree(marker)
	marker.till_and_plant("carrot", 42)
	_grow_to_ready(marker)
	var result: Dictionary = marker.harvest()
	assert_eq(result["crop_id"], "carrot")
	assert_gt(result["count"], 0)
	assert_eq(marker.plot.state, "empty")


func test_harvest_on_a_growing_plot_is_a_noop():
	add_child_autofree(marker)
	marker.till_and_plant("carrot", 42)
	var result: Dictionary = marker.harvest()
	assert_eq(result["crop_id"], "")
	assert_eq(result["count"], 0)
	assert_eq(marker.plot.state, "growing")


## Waters and advances in small steps (never exceeding the grace window)
## until the plot reaches "ready" -- same idiom test_farm_plot.gd's own
## _grow_to_ready uses, driven through the MARKER's own advance()/water()
## rather than poking the plot directly, so this exercises the exact same
## call shape a real tick + tend loop would.
func _grow_to_ready(a_marker: FarmPlotMarker) -> void:
	var step: float = a_marker.plot.growth_time / 10.0
	for i in 12:
		a_marker.water()
		a_marker.advance(step)


# -- wheat renders as bending blades, not IllustratedCropSprite's flat -----
# -- leaves -- see docs/concept/long_grass.md's "A second atlas family: ----
# -- farmed wheat" and docs/concept/npc_farm_production.md (the autonomous --
# -- Farm/Farmer already plants and harvests real "wheat", but had no real --
# -- crop art at all until this) -----------------------------------------


func test_current_wheat_season_defaults_sensibly_before_any_advance():
	add_child_autofree(marker)
	assert_eq(marker.current_wheat_season(), IllustratedWheatPatch.DEFAULT_SEASON)


func test_advance_records_the_season_it_was_given():
	add_child_autofree(marker)
	marker.advance(0.0, "autumn")
	assert_eq(marker.current_wheat_season(), "autumn")


func test_advance_still_accepts_no_season_and_ticks_growth_exactly_as_before():
	add_child_autofree(marker)
	marker.till_and_plant("carrot", 42)
	marker.advance(1.0)
	assert_eq(marker.plot.time_growing, 1.0)


func test_a_carrot_plot_does_not_render_as_bending_wheat():
	add_child_autofree(marker)
	marker.till_and_plant("carrot", 42)
	assert_false(marker.is_rendering_bending_wheat())


func test_an_empty_plot_does_not_render_as_bending_wheat():
	add_child_autofree(marker)
	assert_false(marker.is_rendering_bending_wheat())


func test_a_growing_wheat_plot_renders_as_bending_blades():
	add_child_autofree(marker)
	marker.till_and_plant("wheat", 42)
	assert_true(marker.is_rendering_bending_wheat())
	assert_eq(marker.wheat_blade_count(), IllustratedGrassPatch.CARD_COUNT)


func test_a_ready_wheat_plot_still_renders_as_bending_blades():
	add_child_autofree(marker)
	marker.till_and_plant("wheat", 42)
	_grow_to_ready(marker)
	assert_eq(marker.plot.state, "ready")
	assert_true(marker.is_rendering_bending_wheat())


func test_harvesting_wheat_clears_the_bending_blades():
	add_child_autofree(marker)
	marker.till_and_plant("wheat", 42)
	_grow_to_ready(marker)
	marker.harvest()
	assert_eq(marker.plot.state, "empty")
	assert_false(marker.is_rendering_bending_wheat())
	assert_eq(marker.wheat_blade_count(), 0)


## Replanting the SAME plot with a different crop must fully switch render
## paths, not leave stale wheat blades sitting behind the new crop's leaves
## (a real class of bug this codebase has hit before -- stale visuals left
## over from a previous state).
func test_replanting_wheat_over_with_carrot_switches_away_from_bending_blades():
	add_child_autofree(marker)
	marker.till_and_plant("wheat", 42)
	_grow_to_ready(marker)
	marker.harvest()
	marker.till_and_plant("carrot", 7)
	assert_false(marker.is_rendering_bending_wheat())
	assert_eq(marker.wheat_blade_count(), 0)


func test_a_withered_wheat_plot_still_renders_blades_tinted_the_same_withered_color():
	add_child_autofree(marker)
	marker.till_and_plant("wheat", 42)
	marker.advance(marker.plot.growth_time * FarmPlot.WATER_GRACE_FRACTION + 0.01)
	assert_eq(marker.plot.state, "withered")
	assert_true(marker.is_rendering_bending_wheat())


# -- no bed draws a mound any more -----------------------------------------
#
# Reported with the beds circled, twice. First: "what's the round procedural
# dark blob? Can you remove it and keep just the wheat please" -- answered
# then by hiding ProceduralSoilSprite's mound for WHEAT only, since under a
# root crop the mound was the crop's own ground.
#
# Then: "remove the brown mound blob we have illustrated soil now". Real
# illustrated tilled earth (soil.png, nine variants) now covers the whole
# tile under every bed, so the mound has nothing left to do -- and a herb
# bed, which is not wheat, was still drawing one with no crop art over it:
# a brown blob on brown ground, which is exactly what the screenshot shows.
# The mound is gone entirely rather than hidden for a second crop id.


func test_no_crop_draws_a_mound_any_more():
	add_child_autofree(marker)
	for crop_id in ["wheat", "herb", "carrot", "potato"]:
		marker.till_and_plant(crop_id, 42)
		assert_false(
			marker.is_showing_soil(),
			"%s stands on illustrated tilled earth, not on a blob" % crop_id
		)


func test_a_harvested_bed_draws_no_mound_either():
	add_child_autofree(marker)
	marker.till_and_plant("carrot", 7)
	_grow_to_ready(marker)
	marker.harvest()
	assert_eq(marker.plot.state, "empty")
	assert_false(marker.is_showing_soil())


## Removing the mound must not take the illustrated tilled earth with it --
## a root crop still stands on real ground.
##
## Wheat is deliberately NOT the case asserted here: the soil sheet's own
## cells carry a soft dark vignette, so a tile of it under wheat reads as a
## blob too, and it is hidden there on its own report ("now there are brown
## blobs instead of the planted wheat"). Two different browns, two reports,
## two rules.
func test_a_root_crop_still_stands_on_real_tilled_earth():
	add_child_autofree(marker)
	marker.till_and_plant("carrot", 7)
	assert_not_null(marker.soil_ground(), "a root crop grows in real earth")
	assert_true(marker.soil_ground().visible)
	assert_false(marker.is_showing_soil(), "and still draws no mound")



# -- the tilled ground a bed stands on -------------------------------------
#
# See docs/concept/village_farms.md, "A bed stands on real tilled earth".
# The mound above is a ROOT crop's own ground and is hidden for wheat; that
# left a wheat bed standing on the untouched meadow it was tilled out of.
# Nothing ever drew the ground a bed IS. soil.png does.


func test_a_bed_draws_a_full_tile_of_tilled_earth():
	add_child_autofree(marker)
	# Ploughed first: ground nobody has ever worked is grass, not a bed (see
	# "the ploughed bed" section below).
	marker.till_and_plant("wheat", 42)
	var ground: Sprite2D = marker.soil_ground()
	assert_not_null(ground, "a bed should stand on drawn soil")
	assert_not_null(ground.texture, "with real art on it")
	assert_true(ground.visible)
	var drawn := ground.texture.get_size() * ground.scale
	assert_almost_eq(
		drawn.x, float(TerrainRenderer.TILE_SIZE), 0.01, "soil should cover exactly one tile across"
	)
	assert_almost_eq(drawn.y, float(TerrainRenderer.TILE_SIZE), 0.01, "and one tile down")


## Under the mound and under the crop, always -- it is the ground, so
## anything a bed grows has to sit on top of it.
func test_the_tilled_earth_draws_beneath_the_mound_and_the_crop():
	add_child_autofree(marker)
	var ground: Sprite2D = marker.soil_ground()
	assert_lt(ground.z_index, FarmPlotMarker.MOUND_Z_INDEX, "the mound sits ON the soil")
	assert_lt(ground.z_index, FarmPlotMarker.LEAVES_Z_INDEX, "and so does the crop")


## REVERSED AGAIN, and this reversal is the player's own clarification of
## what the three "brown blob" reports were actually about: *"Die Erde war am
## Ende ohne Blobs... einfach der neue Sprite soil.png und bevor dem
## einpflanzen auf soil_mound.png ... lasse nur den prozedual generierten
## blob weg."*
##
## So the complaint was never the illustrated earth -- it was
## ProceduralSoilSprite's own drawn mound. soil.png goes back under every
## bed, wheat included; soil_mound.png goes on a bed that has been ploughed
## and not yet sown; and the procedural blob stays gone for good.
func test_a_wheat_bed_stands_on_illustrated_earth_but_never_the_procedural_blob():
	add_child_autofree(marker)
	marker.till_and_plant(FarmPlotMarker.WHEAT_CROP_ID, 42)

	assert_false(marker.is_showing_soil(), "the procedural mound stays gone")
	assert_true(marker.soil_ground().visible, "but the illustrated earth is the ground it stands on")


## Seeded from the bed's own tile, so a 3x2 bed is not six copies of one
## tile, and any given bed looks the same every time it is drawn -- the same
## determinism convention every other seeded art pick here follows.
func test_neighbouring_beds_differ_while_each_bed_stays_itself():
	var variants := {}
	for x in 3:
		for y in 2:
			var tile := Vector2i(x, y)
			var first: int = FarmPlotMarker.soil_variant_for(tile)
			assert_eq(first, FarmPlotMarker.soil_variant_for(tile), "tile %s must be stable" % tile)
			variants[first] = true
	assert_gt(variants.size(), 1, "a whole bed of one variant is a tiled-looking bed")


## Superseded by the same clarification: a wheat bed keeps its tilled
## ground, because ploughed earth is what a field looks like.
func test_a_wheat_bed_keeps_its_tilled_ground():
	add_child_autofree(marker)
	marker.till_and_plant("wheat", 42)
	assert_true(marker.is_showing_tilled_ground(), "a ploughed field reads as ploughed")


func test_a_harvested_wheat_bed_keeps_its_tilled_ground():
	add_child_autofree(marker)
	marker.till_and_plant("wheat", 42)
	_grow_to_ready(marker)
	marker.harvest()
	assert_true(marker.is_showing_tilled_ground(), "cut, and still ploughed ground")


## And a root crop keeps the ground it is grown in.
func test_a_root_crop_keeps_its_tilled_ground():
	add_child_autofree(marker)
	marker.till_and_plant("carrot", 7)
	assert_true(marker.is_showing_tilled_ground())


# -- every crop a village really sows has to be visible on the bed ---------

const VillageFarm = preload("res://src/gameplay/village_farm.gd")


## Reported live with the field in shot: "it plows the soil but then the
## soil mound sprites don't appear and nothing gets planted, nothing grows
## and nothing gets harvested".
##
## MEASURED on a real village before anything was touched
## (tools/probe_village_farming.gd): the field's villager was a HERBALIST,
## every bed really was sown (`sown=herb`), the crop really grew
## (`grown=29.5/57.2`), beds really withered and 8 real herbs reached the
## village market over one stretch of work. Not one of them was ever drawn:
## IllustratedCropSprite has entries for carrot and potato only, so
## leaf_texture("herb", ...) returns null -- and a Sprite2D that is VISIBLE
## with a null texture draws nothing at all, over a full tile of bare
## tilled soil. From the player's side that is indistinguishable from a
## field where nothing happens.
##
## So this is the cross-pin, driven off VillageFarm's own table rather than
## a hand-copied list: a crop a village can sow that its bed cannot draw
## fails HERE, not in somebody's screenshot.
func test_every_crop_a_village_farm_sows_really_draws_something():
	for occupation in VillageFarm.CROP_BY_OCCUPATION:
		var crop_id: String = VillageFarm.CROP_BY_OCCUPATION[occupation]
		var bed := FarmPlotMarker.new()
		add_child_autofree(bed)
		assert_true(bed.till_and_plant(crop_id, 11), "%s should plant" % crop_id)
		assert_true(
			bed.is_drawing_a_crop(),
			"a %s bed grows, withers and is harvested invisibly" % crop_id
		)


## ...and it must still be drawn once it is ripe, not only as a seedling.
func test_every_crop_a_village_farm_sows_is_still_drawn_when_ready():
	for occupation in VillageFarm.CROP_BY_OCCUPATION:
		var crop_id: String = VillageFarm.CROP_BY_OCCUPATION[occupation]
		var bed := FarmPlotMarker.new()
		add_child_autofree(bed)
		bed.till_and_plant(crop_id, 11)
		_grow_to_ready(bed)
		assert_eq(bed.plot.state, "ready", crop_id)
		assert_true(bed.is_drawing_a_crop(), "a ripe %s bed draws nothing" % crop_id)


## A visible sprite carrying no texture is the exact shape of the bug above,
## so the query a bed answers has to be "is there really art on screen",
## not "is the node visible".
func test_an_empty_bed_draws_no_crop():
	add_child_autofree(marker)
	assert_false(marker.is_drawing_a_crop(), "nothing is sown, so nothing is drawn")


## A herb grows UP out of the bed it is rooted in.
##
## ProceduralHerbSprite draws the plant filling its canvas from the bottom
## row up (its stem reaches the last row on purpose), so a centred sprite
## would bury the lower half of every herb in the soil. The illustrated
## crops can be centred because their sheets are authored with the plant
## high in the canvas above a baseline; a procedural sprite that fills its
## own canvas cannot. Same root-pinned offset the wheat blades already use
## for exactly this reason (see _redraw_wheat).
func test_a_herb_is_rooted_at_the_bed_not_sunk_into_it():
	add_child_autofree(marker)
	marker.till_and_plant("herb", 3)
	var leaves: Sprite2D = marker._leaves
	assert_false(leaves.centered, "a plant pinned by its middle is half underground")
	assert_almost_eq(
		leaves.offset.y, -float(leaves.texture.get_height()), 0.001,
		"the plant's own bottom row sits on the bed"
	)
	assert_almost_eq(
		leaves.offset.x, -float(leaves.texture.get_width()) * 0.5, 0.001,
		"and it stands in the middle of it"
	)


## ...while an illustrated crop keeps the centring its own sheet baseline
## was authored for -- this must not become one rule for both.
func test_an_illustrated_crop_keeps_its_own_centring():
	add_child_autofree(marker)
	marker.till_and_plant("carrot", 3)
	assert_true(marker._leaves.centered, "carrot art is authored around a baseline")


# -- the ploughed bed: illustrated earth, never the procedural blob --------
#
# Clarified after three rounds of "brown blob" reports: what was wrong was
# the PROCEDURAL mound, not the illustrated earth. "Die Erde war am Ende
# ohne Blobs... einfach der neue Sprite soil.png und bevor dem einpflanzen
# auf soil_mound.png ... lasse nur den prozedual generierten blob weg."
#
# So: soil.png under every bed whatever it grows, soil_mound.png on a bed
# that has been ploughed but not yet sown, and ProceduralSoilSprite's own
# mound gone for good.

const IllustratedSoilMoundSprite = preload("res://src/rendering/illustrated_soil_mound_sprite.gd")


## The tilled ground is the ground, wheat included. It used to be hidden
## under wheat, which is what made a wheat bed look unploughed.
func test_every_bed_stands_on_its_own_tilled_earth_wheat_included():
	for crop_id in ["wheat", "herb", "carrot"]:
		var bed := FarmPlotMarker.new()
		add_child_autofree(bed)
		bed.till_and_plant(crop_id, 11)
		assert_true(bed.is_showing_tilled_ground(), "a %s bed stands on tilled earth" % crop_id)


## A bed that has been ploughed and not yet sown shows the mound -- the
## real, illustrated one.
func test_a_ploughed_bed_that_is_not_yet_sown_shows_the_illustrated_mound():
	add_child_autofree(marker)
	marker.till_and_plant("wheat", 11)
	_grow_to_ready(marker)
	marker.harvest()
	assert_eq(marker.plot.state, "empty", "precondition: cut and waiting to be sown again")
	assert_true(marker.is_showing_mound(), "a ploughed bed waiting for seed shows its mound")


## ...and it is gone the moment something is growing in it, because then the
## crop is what the bed shows.
func test_a_sown_bed_shows_its_crop_and_not_the_mound():
	add_child_autofree(marker)
	marker.till_and_plant("wheat", 11)
	assert_false(marker.is_showing_mound(), "something is growing here")
	assert_true(marker.is_drawing_a_crop())


## Ground nobody has ever ploughed shows neither.
func test_untouched_ground_shows_no_mound():
	add_child_autofree(marker)
	assert_false(marker.is_showing_mound())


## The mound is the illustrated sheet's, never ProceduralSoilSprite's blob
## -- that is the one thing the three reports were actually about.
func test_the_mound_is_the_illustrated_one_never_the_procedural_blob():
	add_child_autofree(marker)
	marker.till_and_plant("wheat", 11)
	_grow_to_ready(marker)
	marker.harvest()
	assert_false(marker.is_showing_soil(), "the procedural mound stays gone")
	var mound: Sprite2D = marker.mound()
	assert_not_null(mound)
	assert_not_null(mound.texture, "the illustrated sheet's own art")
	assert_almost_eq(
		mound.scale.x, IllustratedSoilMoundSprite.new().world_scale(), 0.001,
		"at the world size a bed's mound really is"
	)


## Ground nobody has ever ploughed is grass, not a bed -- the tilled tile
## appears with the plough, not with the marker.
func test_untouched_ground_draws_no_tilled_earth():
	add_child_autofree(marker)
	assert_false(marker.is_showing_tilled_ground())
