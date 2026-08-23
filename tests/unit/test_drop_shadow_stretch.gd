extends GutTest

## DropShadow's silhouette shadows (see drop_shadow.gd / CreatureRenderer /
## CreatureMarker): a creature's own sprite, flipped upside down and anchored
## at its feet, in place of the old fixed round blob -- a proper contact
## shadow, not a circle every animal happens to share.
##
## Length reacts to the sun's elevation the way a real shadow does: overhead
## sun (elevation near 90 deg) casts a short shadow right under the feet,
## while a low sun (elevation near the horizon) drags it out long. Modeled as
## the real projection ratio 1/tan(elevation), clamped so noon doesn't
## collapse a shadow to nothing and dawn/dusk doesn't stretch it to infinity.

const DropShadow = preload("res://src/rendering/drop_shadow.gd")

var shadow: DropShadow


func before_each():
	shadow = DropShadow.new()


func _solid_texture(width: int, height: int) -> ImageTexture:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(1, 1, 1, 1))
	return ImageTexture.create_from_image(image)


func test_overhead_sun_yields_the_shortest_stretch():
	assert_almost_eq(shadow.stretch_for_elevation(90.0), DropShadow.MIN_STRETCH, 0.001)


func test_low_sun_yields_a_longer_stretch_than_a_high_sun():
	var low := shadow.stretch_for_elevation(10.0)
	var high := shadow.stretch_for_elevation(60.0)
	assert_gt(low, high, "a lower sun must cast a longer shadow than a higher one")


func test_stretch_is_clamped_so_a_grazing_sun_never_explodes():
	assert_almost_eq(shadow.stretch_for_elevation(0.5), DropShadow.MAX_STRETCH, 0.001)


func test_stretch_stays_clamped_below_the_horizon_too():
	# Night has no direct sun to cast a shadow, but the caller (CreatureMarker)
	# decides whether to show one at all -- this function just must not blow
	# up or go negative for an out-of-range input.
	var value := shadow.stretch_for_elevation(-20.0)
	assert_between(value, DropShadow.MIN_STRETCH, DropShadow.MAX_STRETCH)


func test_make_silhouette_shadow_flips_the_texture_vertically():
	var sprite: Sprite2D = shadow.make_silhouette_shadow(_solid_texture(10, 14), 6.0)
	assert_true(sprite.flip_v, "a shadow is the creature's shape flipped upside down")
	sprite.free()


func test_make_silhouette_shadow_draws_behind_and_anchors_at_the_feet():
	var sprite: Sprite2D = shadow.make_silhouette_shadow(_solid_texture(10, 14), 6.0)
	assert_true(sprite.show_behind_parent)
	assert_eq(sprite.position, Vector2(0, 6.0))
	sprite.free()


func test_make_silhouette_shadow_is_a_translucent_dark_copy_not_the_real_colors():
	var sprite: Sprite2D = shadow.make_silhouette_shadow(_solid_texture(10, 14), 0.0)
	assert_eq(sprite.modulate, Color(0, 0, 0, DropShadow.SHADOW_ALPHA))
	sprite.free()


func test_make_silhouette_shadow_grows_downward_from_the_feet_not_the_centre():
	# centered=false with a top-anchored offset: stretching scale.y must grow
	# the shadow AWAY from the anchor line (into the ground), not split the
	# growth evenly around a centre the way the old ellipse did.
	var sprite: Sprite2D = shadow.make_silhouette_shadow(_solid_texture(10, 14), 0.0)
	assert_false(sprite.centered)
	assert_eq(sprite.offset.y, 0.0)
	sprite.free()
