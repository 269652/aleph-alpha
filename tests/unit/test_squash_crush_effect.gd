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


## Reported live: "crushing an ant shows a distorted sprite which is very
## large". An ant's own marker_scale (IllustratedDecomposerSprite.
## marker_scale) is a small fraction, nowhere near 1.0 -- this codebase has
## hit the exact "gigantic ant blobs" failure mode before whenever a scale
## got applied as a flat ABSOLUTE value instead of relative to whatever tiny
## scale a species already draws at (see ProceduralDecomposerSprite's own
## doc comment on that precedent). VERTICAL_SQUASH must flatten relative to
## the sprite's OWN existing scale.y, never overwrite it outright -- 0.35 is
## smaller than a normal sprite's 1.0, but far LARGER than an ant's own real
## tiny scale, which is exactly how "flattened" turned into "distorted and
## huge".
func test_apply_flattens_relative_to_a_tiny_creatures_own_scale_not_to_an_absolute_value():
	var sprite := Sprite2D.new()
	sprite.scale = Vector2(0.08, 0.08)  # representative of a real ant's own marker_scale
	SquashCrushEffect.apply(sprite)
	assert_almost_eq(
		sprite.scale.y, 0.08 * SquashCrushEffect.VERTICAL_SQUASH, 0.0001,
		"a tiny creature's crushed scale must still be smaller than its own live scale, not jump up to 0.35"
	)
	sprite.free()


func test_apply_tints_the_sprite_dark_and_reddish():
	var sprite := Sprite2D.new()
	SquashCrushEffect.apply(sprite)
	assert_eq(sprite.modulate, SquashCrushEffect.TINT)
	sprite.free()


func test_linger_seconds_is_a_real_pinned_constant():
	assert_gt(SquashCrushEffect.LINGER_SECONDS, 0.0)
