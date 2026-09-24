extends GutTest

## The transient visual for one spell atom's effect (docs/concept/
## spell_runtime.md) -- thin Node-composition glue over tested pure
## generation (ProceduralSpellEffectSprite, IllustratedSpellEffectSprite),
## the same boundary this codebase's other cosmetic marker nodes already
## sit on. Covers only "does it show the right art and clean up after
## itself," not tween timing.

const SpellEffectMarker = preload("res://src/rendering/spell_effect_marker.gd")
const ProceduralSpellEffectSprite = preload("res://src/rendering/procedural_spell_effect_sprite.gd")
const IllustratedSpellEffectSprite = preload("res://src/rendering/illustrated_spell_effect_sprite.gd")

var marker: SpellEffectMarker


func before_each():
	marker = SpellEffectMarker.new()
	add_child(marker)


func after_each():
	if is_instance_valid(marker):
		remove_child(marker)
		marker.free()


## fire_damage has real illustrated art (IllustratedSpellEffectSprite) --
## the procedural generator is only ever a fallback for an atom that
## doesn't, which no real catalog atom is anymore (see
## test_illustrated_spell_effect_sprite.gd's own test_every_catalog_atom_
## has_a_registered_illustrated_look). Covered by
## test_play_sets_an_unregistered_atoms_procedural_texture below instead.
func test_play_sets_the_atoms_own_illustrated_first_frame():
	marker.play("fire_damage")
	var expected := IllustratedSpellEffectSprite.new().frames_for("fire_damage")[0]
	assert_eq(marker.texture.get_image().get_data(), expected.get_image().get_data())


func test_play_sets_an_unregistered_atoms_procedural_texture():
	marker.play("not_a_real_atom")
	var expected := ProceduralSpellEffectSprite.new().texture_for("not_a_real_atom")
	assert_eq(marker.texture.get_image().get_data(), expected.get_image().get_data())


func test_play_starts_invisible_before_growing_in():
	marker.play("fire_damage")
	assert_almost_eq(marker.scale.x, 0.0, 0.01)
	assert_almost_eq(marker.scale.y, 0.0, 0.01)


func test_play_frees_itself_once_the_animation_completes():
	marker.play("fire_damage")
	await get_tree().create_timer(
		SpellEffectMarker.GROW_DURATION + SpellEffectMarker.HOLD_DURATION + SpellEffectMarker.FADE_DURATION + 0.2
	).timeout
	assert_false(is_instance_valid(marker), "the marker should have queue_free'd itself by now")
