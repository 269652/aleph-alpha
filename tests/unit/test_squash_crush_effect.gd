extends GutTest

## Procedural "crushed" fallback for a small creature with no dedicated
## crushed artwork of its own (see docs/concept/soil_fauna.md's "Crushed
## underfoot" family). CaterpillarMarker, AntForagerMarker, and
## DecomposerMarker all share this identical transform -- three real call
## sites, past the "three similar things beats a premature abstraction"
## line this codebase's own docs already draw elsewhere. Applied directly to
## whatever sprite/texture a marker is already showing at the moment it
## dies, so no new art asset is needed at all.

const SquashCrushEffect = preload("res://src/rendering/squash_crush_effect.gd")


func test_apply_flattens_the_sprite_vertically():
	var sprite := Sprite2D.new()
	sprite.scale = Vector2.ONE
	SquashCrushEffect.apply(sprite)
	assert_almost_eq(sprite.scale.y, SquashCrushEffect.VERTICAL_SQUASH, 0.001)
	assert_almost_eq(sprite.scale.x, 1.0, 0.001, "only the vertical axis should flatten")
	sprite.free()


func test_apply_preserves_whatever_horizontal_scale_the_sprite_already_had():
	var sprite := Sprite2D.new()
	sprite.scale = Vector2(2.5, 1.0)
	SquashCrushEffect.apply(sprite)
	assert_almost_eq(sprite.scale.x, 2.5, 0.001, "an existing horizontal scale should be left alone")
	sprite.free()


func test_apply_tints_the_sprite_dark_and_reddish():
	var sprite := Sprite2D.new()
	SquashCrushEffect.apply(sprite)
	assert_eq(sprite.modulate, SquashCrushEffect.TINT)
	sprite.free()


func test_linger_seconds_is_a_real_pinned_constant():
	assert_gt(SquashCrushEffect.LINGER_SECONDS, 0.0)
