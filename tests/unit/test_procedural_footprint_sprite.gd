extends GutTest

## ProceduralFootprintSprite: no real hand-illustrated footprint/boot art
## exists anywhere in this project yet (confirmed by a dedicated search
## before writing this file) -- generates a real, simple, recognizable
## sole shape directly, the same "procedural first, real art can replace
## it later" precedent ProceduralMushroomSprite/LeafLitterAtlas's own
## procedural fallback already establish. One canonical shape per surface
## ("snow"/"grass"/"forest") -- left vs right is a render-time horizontal
## flip (see FootprintRenderer), not a second generated shape, the same
## flip_h idiom AntForagerMarker/DecomposerMarker's own facing already
## uses.

const ProceduralFootprintSprite = preload("res://src/rendering/procedural_footprint_sprite.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")
const GroundSlide = preload("res://src/gameplay/ground_slide.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

var sprite: ProceduralFootprintSprite


func before_each():
	sprite = ProceduralFootprintSprite.new()


func _has_opaque_pixel(image: Image) -> bool:
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.5:
				return true
	return false


func test_draws_a_real_non_blank_shape_for_every_real_surface():
	for surface in ["snow", "grass", "forest", "underwater"]:
		var image := sprite.generate_image(surface)
		assert_true(_has_opaque_pixel(image), "%s should draw a real print, not a blank canvas" % surface)


func test_an_unknown_surface_falls_back_rather_than_crashing():
	var image := sprite.generate_image("lava")
	assert_true(_has_opaque_pixel(image))


## "Stamped ... with displacement" (reported live) -- a real pressed-in
## mark needs more than one flat fill colour: a darker core (the actual
## depression) plus a distinctly different rim tone (material pushed up
## at the edge), not a single-colour silhouette.
func test_the_print_has_at_least_two_distinct_opaque_tones_not_one_flat_fill():
	var image := sprite.generate_image("snow")
	var seen_colors := {}
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if c.a > 0.5:
				seen_colors[c] = true
	assert_gt(seen_colors.size(), 1, "a real stamped print should show more than one opaque tone")


## Different surfaces must not all secretly render the identical look --
## snow, grass, forest, and underwater are visually distinct grounds.
func test_different_surfaces_look_different_from_each_other():
	var snow := sprite.generate_image("snow").get_data()
	var grass := sprite.generate_image("grass").get_data()
	var forest := sprite.generate_image("forest").get_data()
	var underwater := sprite.generate_image("underwater").get_data()
	assert_ne(snow, grass)
	assert_ne(grass, forest)
	assert_ne(snow, forest)
	assert_ne(underwater, snow)
	assert_ne(underwater, grass)
	assert_ne(underwater, forest)


func test_generate_texture_returns_a_real_texture():
	var texture := sprite.generate_texture("snow")
	assert_not_null(texture)
	assert_true(_has_opaque_pixel(texture.get_image()))


## A real footprint is longer than it is wide (heel to toe > side to
## side) -- not a plain round blob, which would read as a paw print or a
## puddle rather than a human print.
func test_the_print_reads_longer_than_it_is_wide():
	assert_gt(ProceduralFootprintSprite.SIZE.y, ProceduralFootprintSprite.SIZE.x)


## Real average adult shoe length, converted via GroundSlide.PX_PER_METER
## -- the same real-human-scale idiom FootstepGait's own STRIDE_LENGTH_
## METERS/STANCE_WIDTH_METERS already use, not an eyeballed pixel count.
func test_world_scale_is_derived_from_a_real_meter_measurement_not_eyeballed():
	var expected := (
		ProceduralFootprintSprite.PRINT_LENGTH_METERS * GroundSlide.PX_PER_METER
		/ float(ProceduralFootprintSprite.SIZE.y)
	)
	assert_almost_eq(ProceduralFootprintSprite.PRINT_WORLD_SCALE, expected, 0.0001)


## Art authored at ArtResolution.DETAIL_MULTIPLIER-times oversize, same
## "more art pixels per world unit, identical world layout" convention
## every other entity sprite in this codebase already follows.
func test_canvas_is_authored_at_the_shared_detail_multiplier():
	assert_eq(ProceduralFootprintSprite.SIZE.x % ArtResolution.DETAIL_MULTIPLIER, 0)
	assert_eq(ProceduralFootprintSprite.SIZE.y % ArtResolution.DETAIL_MULTIPLIER, 0)


# -- real ground visibility (see docs/concept/snow_cover.md "Grass/forest --
# prints were already wired but effectively invisible") -- reported live:
# "footsteps only show when snow is visible... they should generally show
# up lighter for grassland and forest even without snow... a bit deeper in
# forest ground." Confirmed by rendering real swatches (composited onto
# TerrainRenderer.BIOME_COLORS at real PRINT_WORLD_SCALE) that the ORIGINAL
# grass/forest tones read as near-invisible: grass's rim was barely
# distinguishable in luminance from grassland's own ground color, and
# forest's rim was actually DARKER than forest's own ground -- the
# opposite of "pushed-up material catching the light". These tests pin
# real, test-checked luminance-contrast margins against TerrainRenderer's
# own ground colors -- CLAUDE.md: tuned values are tested, never eyeballed.

## A real, perceptible luminance step at 8-bit precision (>30 of 255
## levels) -- not a hair's-breadth technically-true difference nobody
## would actually notice on screen.
const _MIN_CONTRAST := 0.12


static func _luminance(c: Color) -> float:
	return 0.3 * c.r + 0.59 * c.g + 0.11 * c.b


## The core is "the actual depression" (see the class's own doc comment)
## -- it must read distinctly darker than the real ground it's pressed
## into, not just a different hue at the same brightness.
func test_grass_core_reads_visibly_darker_than_the_real_grassland_ground():
	var tones: Dictionary = ProceduralFootprintSprite._TONES_BY_SURFACE["grass"]
	var ground: Color = TerrainRenderer.BIOME_COLORS["grassland"]
	assert_lt(_luminance(tones["core"]), _luminance(ground) - _MIN_CONTRAST)


## The rim is "material pushed up and catching the light" -- it must read
## distinctly LIGHTER than the real ground, not blend into it.
func test_grass_rim_reads_visibly_lighter_than_the_real_grassland_ground():
	var tones: Dictionary = ProceduralFootprintSprite._TONES_BY_SURFACE["grass"]
	var ground: Color = TerrainRenderer.BIOME_COLORS["grassland"]
	assert_gt(_luminance(tones["rim"]), _luminance(ground) + _MIN_CONTRAST)


func test_forest_core_reads_visibly_darker_than_the_real_forest_ground():
	var tones: Dictionary = ProceduralFootprintSprite._TONES_BY_SURFACE["forest"]
	var ground: Color = TerrainRenderer.BIOME_COLORS["forest"]
	assert_lt(_luminance(tones["core"]), _luminance(ground) - _MIN_CONTRAST)


func test_forest_rim_reads_visibly_lighter_than_the_real_forest_ground():
	var tones: Dictionary = ProceduralFootprintSprite._TONES_BY_SURFACE["forest"]
	var ground: Color = TerrainRenderer.BIOME_COLORS["forest"]
	assert_gt(_luminance(tones["rim"]), _luminance(ground) + _MIN_CONTRAST)


## The literal ask: forest should read "a bit deeper" than grassland --
## its own core-to-ground contrast (how much darker the depression reads
## than the ground it's pressed into) must exceed grassland's own, not
## just independently clear the same flat floor.
func test_forest_reads_a_bit_deeper_than_grassland():
	var grass_tones: Dictionary = ProceduralFootprintSprite._TONES_BY_SURFACE["grass"]
	var forest_tones: Dictionary = ProceduralFootprintSprite._TONES_BY_SURFACE["forest"]
	var grass_drop := (
		_luminance(TerrainRenderer.BIOME_COLORS["grassland"]) - _luminance(grass_tones["core"])
	)
	var forest_drop := (
		_luminance(TerrainRenderer.BIOME_COLORS["forest"]) - _luminance(forest_tones["core"])
	)
	assert_gt(forest_drop, grass_drop, "forest's own depression should read deeper than grassland's")


## "Lighter... for grassland and forest" means subtler than snow's own
## dramatic near-white flash, not literally brighter than it -- both
## surfaces' rims must stay visibly below snow's own rim brightness.
func test_grass_and_forest_stay_subtler_than_snows_own_rim_brightness():
	var snow_rim: Color = ProceduralFootprintSprite._TONES_BY_SURFACE["snow"]["rim"]
	for surface in ["grass", "forest"]:
		var rim: Color = ProceduralFootprintSprite._TONES_BY_SURFACE[surface]["rim"]
		assert_lt(_luminance(rim), _luminance(snow_rim), "%s's rim should read subtler than snow's" % surface)


# -- underwater (see docs/concept/snow_cover.md/rivers.md) -- asked directly:
# -- "underwater footprints should be tinted". Real: standing water in a
# -- depression reads measurably darker than the same ground dry (wet
# -- soil loses diffuse reflectance once its surface pores fill with
# -- water) -- unlike every dry surface above, whose RIM is pushed-up
# -- material catching the light (so it reads LIGHTER than the ground),
# -- a water-filled print has no equivalent "catches the light" edge: both
# -- core AND rim read darker here, distinguished from plain wet mud by a
# -- real blue shift rather than by brightness.

func test_underwater_core_reads_visibly_darker_than_either_dry_ground():
	var core: Color = ProceduralFootprintSprite._TONES_BY_SURFACE["underwater"]["core"]
	for biome in ["grassland", "forest"]:
		var ground: Color = TerrainRenderer.BIOME_COLORS[biome]
		assert_lt(_luminance(core), _luminance(ground) - _MIN_CONTRAST, "vs %s" % biome)


## Unlike grass/forest's own rim (deliberately LIGHTER than the ground --
## see the class comment above), underwater's rim stays darker too: a
## puddle's edge is soggy, compressed ground, not material catching light.
func test_underwater_rim_reads_darker_than_either_dry_ground_not_lighter():
	var rim: Color = ProceduralFootprintSprite._TONES_BY_SURFACE["underwater"]["rim"]
	for biome in ["grassland", "forest"]:
		var ground: Color = TerrainRenderer.BIOME_COLORS[biome]
		assert_lt(_luminance(rim), _luminance(ground), "vs %s" % biome)


## The one thing that must actually say "water", not just "dark mud":
## a real blue shift, clearly beyond what grass/forest's own (brown/warm)
## cores show.
func test_underwater_core_reads_distinctly_blue_shifted():
	var core: Color = ProceduralFootprintSprite._TONES_BY_SURFACE["underwater"]["core"]
	assert_gt(core.b, core.r, "should read blue-dominant, like pooled water")
	assert_gt(core.b, core.g)
	for surface in ["grass", "forest"]:
		var other: Color = ProceduralFootprintSprite._TONES_BY_SURFACE[surface]["core"]
		assert_gt(core.b - core.r, other.b - other.r, "more blue-shifted than %s's own core" % surface)
