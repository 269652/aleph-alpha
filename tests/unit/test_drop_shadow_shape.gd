extends GutTest

## DropShadow's per-body proportions (see drop_shadow.gd / CreatureRenderer).
##
## Every creature used to get one fixed oval regardless of build, so a long
## low serpent sat on an egg. The height ratio is now a parameter -- and the
## texture cache had to be re-keyed for it, because caching on width alone
## would hand whatever shape the first same-width caller built to everyone
## after it (a snake silently inheriting a boar's shadow).

const DropShadow = preload("res://src/rendering/drop_shadow.gd")

var shadow: DropShadow


func before_each():
	shadow = DropShadow.new()


func _size_of(sprite: Sprite2D) -> Vector2:
	return sprite.texture.get_size()


func test_a_flatter_ratio_yields_a_flatter_shadow():
	var flat := _size_of(shadow.make_shadow(40, 0.0, 0.15))
	var round_ := _size_of(shadow.make_shadow(40, 0.0, 0.5))
	assert_lt(flat.y, round_.y, "a lower ratio must actually produce a lower ellipse")
	assert_eq(flat.x, round_.x, "width should be unaffected by the ratio")


## The cache-key bug: same width, different ratio must NOT return the shape
## that was built first.
func test_two_ratios_at_the_same_width_do_not_share_a_cached_texture():
	var first := _size_of(shadow.make_shadow(32, 0.0, 0.15))
	var second := _size_of(shadow.make_shadow(32, 0.0, 0.5))
	assert_ne(first.y, second.y, "the cache must key on the ratio too, not just width")


## Identical requests should still be shared rather than rebuilt.
func test_an_identical_request_reuses_its_texture():
	assert_eq(shadow.make_shadow(32, 0.0, 0.3).texture, shadow.make_shadow(32, 0.0, 0.3).texture)


## Existing callers (trees, stones, the player) passed no ratio and must be
## completely unaffected by the new parameter.
func test_omitting_the_ratio_keeps_the_original_proportions():
	assert_eq(
		_size_of(shadow.make_shadow(40, 0.0)),
		_size_of(shadow.make_shadow(40, 0.0, DropShadow.HEIGHT_RATIO))
	)


## However flat the request, a shadow must never collapse to nothing.
func test_a_shadow_never_degenerates_to_a_hairline():
	assert_gte(_size_of(shadow.make_shadow(40, 0.0, 0.01)).y, 3.0)


func test_shadows_stay_translucent_at_any_ratio():
	var image := shadow.make_shadow(40, 0.0, 0.15).texture.get_image()
	var centre := image.get_pixel(image.get_width() / 2, image.get_height() / 2)
	assert_gt(centre.a, 0.0)
	assert_lt(centre.a, 1.0, "a contact shadow must not be opaque black")
