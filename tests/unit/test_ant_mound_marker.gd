extends GutTest

## The visible, static marker over one AntColony mound cell -- see
## ProceduralAntMoundSprite, docs/concept/soil_fauna.md. Deliberately inert:
## a mound does not move, flee, or need per-frame behaviour of its own (see
## AntColony's own doc comment on why a mound is a background population
## effect, not an individually-simulated creature) -- this is purely "stand
## here and be visible", the rendering-only counterpart to a data-only
## AntColony mound cell.

const AntMoundMarker = preload("res://src/rendering/ant_mound_marker.gd")
const ProceduralAntMoundSprite = preload("res://src/rendering/procedural_ant_mound_sprite.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")

var marker: AntMoundMarker


func before_each():
	marker = AntMoundMarker.new()
	marker.position = Vector2(200, 150)
	add_child_autofree(marker)


func test_joins_the_ant_mound_group():
	assert_true(marker.is_in_group(AntMoundMarker.GROUP_NAME))


func test_has_a_real_mound_sprite_texture():
	var sprite := marker.get_child(0) as Sprite2D
	assert_not_null(sprite.texture)
	assert_eq(sprite.texture.get_width(), ProceduralAntMoundSprite.SIZE)


## Same "gigantic" failure class DecomposerMarker's own ant/bug sprite hit
## once (never applied any world scale at all) -- pinned directly rather
## than trusted by inspection.
func test_sprite_is_drawn_at_its_real_tiny_world_size_not_the_raw_art_canvas():
	var sprite := marker.get_child(0) as Sprite2D
	assert_eq(sprite.scale, Vector2.ONE * ProceduralAntMoundSprite.MOUND_WORLD_SCALE)


func test_stays_exactly_where_placed():
	assert_eq(marker.position, Vector2(200, 150))
