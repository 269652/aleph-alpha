extends GutTest

## The visible marker over one AntColony mound cell -- see
## ProceduralAntMoundSprite, docs/concept/soil_fauna.md. Still does not
## move, flee, or need FRAME-BY-FRAME behaviour the way a real creature
## does (see AntColony's own doc comment on why a mound is a background
## population effect, not an individually-simulated creature) -- but it is
## no longer purely inert either: it now re-checks its own colony's
## growth_fraction on a slow cadence and grows its own sprite to match
## (see "Mound size grows with the colony").

const AntMoundMarker = preload("res://src/rendering/ant_mound_marker.gd")
const ProceduralAntMoundSprite = preload("res://src/rendering/procedural_ant_mound_sprite.gd")
const IllustratedAntMoundSprite = preload("res://src/rendering/illustrated_ant_mound_sprite.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")
const HoverTargetFinder = preload("res://src/rendering/hover_target_finder.gd")
const AntColony = preload("res://src/world/ant_colony.gd")
const AntPopulationModel = preload("res://src/world/ant_population_model.gd")


func _colony() -> AntColony:
	var biome := PackedStringArray()
	for i in 64:
		biome.append("grassland")
	return AntColony.new(42, 8, 8, biome)

var marker: AntMoundMarker


func before_each():
	marker = AntMoundMarker.new()
	marker.position = Vector2(200, 150)
	marker.mound_seed = 3
	add_child_autofree(marker)


func test_joins_the_ant_mound_group():
	assert_true(marker.is_in_group(AntMoundMarker.GROUP_NAME))


## See docs/concept/soil_fauna.md "Ants at half their old size, and finally
## hoverable".
func test_joins_the_hoverable_group():
	assert_true(marker.is_in_group(HoverTargetFinder.GROUP_NAME))


func test_get_display_name_names_it_an_ant_mound():
	assert_eq(marker.get_display_name(), "Ant Mound")


## docs/concept/soil_fauna.md's own "What the player actually sees" names
## this directly: a mound's hover tooltip is the one place a player can
## read an exact population figure, not only infer it from traffic/size.
func test_get_display_name_reports_real_population_once_a_colony_is_set_up():
	var colony := _colony()
	var cell: Vector2i = colony.mound_cells()[0]
	var linked := AntMoundMarker.new()
	linked.mound_seed = 3
	linked.setup(colony, cell)
	add_child_autofree(linked)
	assert_string_contains(linked.get_display_name(), str(int(round(colony.population_at(cell)))))


## Real illustrated mound art now exists (see IllustratedAntMoundSprite) --
## checked first, same has_X()-gated fallback convention every other
## optional illustrated-art seam in this codebase uses.
func test_has_a_real_mound_sprite_texture():
	var sprite := marker.get_child(0) as Sprite2D
	assert_not_null(sprite.texture)
	assert_eq(Vector2i(sprite.texture.get_width(), sprite.texture.get_height()), IllustratedAntMoundSprite.CANVAS_SIZE)


## Same "gigantic" failure class DecomposerMarker's own ant/bug sprite hit
## once (never applied any world scale at all) -- pinned directly rather
## than trusted by inspection. Illustrated art uses its own measured-from-
## the-real-art scale (see IllustratedAntMoundSprite.marker_scale), not the
## procedural generator's fixed scale. No setup() call at all here (see
## its own doc comment) -- a mound with no colony wired up reads at
## growth_fraction 0.0, the same founding-colony default a real one
## starts at.
func test_sprite_is_drawn_at_its_real_tiny_world_size_not_the_raw_art_canvas():
	var sprite := marker.get_child(0) as Sprite2D
	assert_eq(sprite.scale, Vector2.ONE * IllustratedAntMoundSprite.new().marker_scale(0.0))


## Two mounds with the same seed should look identical; different seeds
## should be free to differ -- the same determinism/spread guarantee
## IllustratedAntMoundSprite.frame_for itself already pins, checked here
## through the marker so a future rewiring can't silently drop it.
func test_same_seed_picks_the_same_variant():
	var other := AntMoundMarker.new()
	other.mound_seed = 3
	add_child_autofree(other)
	var sprite_a := marker.get_child(0) as Sprite2D
	var sprite_b := other.get_child(0) as Sprite2D
	assert_eq(sprite_a.texture, sprite_b.texture)


func test_stays_exactly_where_placed():
	assert_eq(marker.position, Vector2(200, 150))


# -- Mound size grows with the colony (see docs/concept/soil_fauna.md's
# own section by that name) -------------------------------------------

## setup() before add_child, same convention as every other optional-
## world marker in this codebase -- a real colony's own current growth
## fraction should size the sprite from the very first frame, not wait
## for the first periodic re-check.
func test_setup_sizes_the_sprite_from_the_real_colonys_growth_fraction_immediately():
	var colony := _colony()
	var cell: Vector2i = colony.mound_cells()[0]
	for i in 20:
		colony.record_forage_result(cell, true)
		colony.record_moisture(cell, 1.0)
	for i in 400:
		colony.advance(AntColony.SECONDS_PER_SIMULATED_DAY)
	var grown := AntMoundMarker.new()
	grown.mound_seed = 3
	grown.setup(colony, cell)
	add_child_autofree(grown)

	var sprite := grown.get_child(0) as Sprite2D
	var expected := IllustratedAntMoundSprite.new().marker_scale(colony.growth_fraction_at(cell))
	assert_almost_eq(sprite.scale.x, expected, 0.001)
	var default_sprite := marker.get_child(0) as Sprite2D
	assert_gt(sprite.scale.x, default_sprite.scale.x, "a thriving colony's mound should already read bigger than a no-colony default")


## A mound a player watches over a real session should visibly, if
## slowly, grow -- setup() alone (at a founding population) is not enough
## to prove this; the marker must re-check on its own over time as the
## SAME colony object's population keeps changing.
func test_mound_grows_larger_over_time_as_its_colony_grows():
	var colony := _colony()
	var cell: Vector2i = colony.mound_cells()[0]
	var growing := AntMoundMarker.new()
	growing.mound_seed = 3
	growing.setup(colony, cell)
	add_child_autofree(growing)
	var sprite := growing.get_child(0) as Sprite2D
	var before := sprite.scale.x

	for i in 20:
		colony.record_forage_result(cell, true)
		colony.record_moisture(cell, 1.0)
	for i in 400:
		colony.advance(AntColony.SECONDS_PER_SIMULATED_DAY)
	growing._process(AntMoundMarker.RESIZE_INTERVAL_SECONDS + 1.0)

	assert_gt(sprite.scale.x, before, "the marker should have re-checked its own colony and grown")


## Re-checking is throttled, not every-frame -- a tiny delta must not
## already trigger a resize (population moves over simulated DAYS; a
## per-frame recheck would spend real cost on a number that has not
## meaningfully moved since the last one).
func test_does_not_resize_faster_than_its_own_throttle():
	var colony := _colony()
	var cell: Vector2i = colony.mound_cells()[0]
	var growing := AntMoundMarker.new()
	growing.mound_seed = 3
	growing.setup(colony, cell)
	add_child_autofree(growing)
	var sprite := growing.get_child(0) as Sprite2D
	var before := sprite.scale.x

	for i in 20:
		colony.record_forage_result(cell, true)
		colony.record_moisture(cell, 1.0)
	for i in 400:
		colony.advance(AntColony.SECONDS_PER_SIMULATED_DAY)
	growing._process(0.1)  # well under RESIZE_INTERVAL_SECONDS

	assert_almost_eq(sprite.scale.x, before, 0.0001, "a sub-throttle tick should not have re-checked yet")


## No setup() call at all -- _process must not crash reaching for a null
## colony, and the sprite should simply stay at its founding-size default
## forever (see test_sprite_is_drawn_at_its_real_tiny_world_size_not_the_
## raw_art_canvas's own no-setup convention).
func test_process_with_no_colony_set_up_does_not_crash_or_change_size():
	var sprite := marker.get_child(0) as Sprite2D
	var before := sprite.scale.x
	marker._process(AntMoundMarker.RESIZE_INTERVAL_SECONDS + 1.0)
	assert_almost_eq(sprite.scale.x, before, 0.0001)
