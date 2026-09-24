extends GutTest

## The transient visual for one spell atom's effect (docs/concept/
## spell_runtime.md) -- thin Node-composition glue over tested pure
## generation (ProceduralSpellEffectSprite), the same boundary this
## codebase's other cosmetic marker nodes already sit on. Covers only "does
## it show the right art and clean up after itself," not tween timing.

const SpellEffectMarker = preload("res://src/rendering/spell_effect_marker.gd")
const ProceduralSpellEffectSprite = preload("res://src/rendering/procedural_spell_effect_sprite.gd")

var marker: SpellEffectMarker


func before_each():
	marker = SpellEffectMarker.new()
	add_child(marker)


func after_each():
	if is_instance_valid(marker):
		remove_child(marker)
		marker.free()
	# A test that calls play() and asserts immediately, without awaiting the
	# full beat, ends with an in-flight halo still parented to this test
	# node -- marker.free() above kills the MARKER's own Tween (Godot binds
	# a create_tween() result to its owning node's lifetime), which is
	# where the halo's OWN queue_free was scheduled as the sequence's last
	# step, so that step never runs and the halo is orphaned. Left alone, a
	# LATER test's naive "first MeshInstance2D" scan would find THAT stray
	# halo instead of its own. Swept here rather than worked around at each
	# call site, so no test has to know this about any other test.
	for child in get_children():
		if child is MeshInstance2D:
			child.free()


func test_play_sets_the_atoms_own_procedural_texture():
	marker.play("fire_damage")
	var expected := ProceduralSpellEffectSprite.new().texture_for("fire_damage")
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


# -- spell_vfx.md: illustrated-or-procedural, plus both shaders -----------

const IllustratedSpellEffectArt = preload("res://src/rendering/illustrated_spell_effect_art.gd")
const SpellImpactDistortionShader = preload("res://src/rendering/spell_impact_distortion_shader.gd")
const SpellGlowShader = preload("res://src/rendering/spell_glow_shader.gd")


## `play` now routes through the illustrated-or-procedural bridge rather
## than calling ProceduralSpellEffectSprite directly -- with no illustrated
## art on disk yet (spell_vfx.md's own honest Status), the pixels are
## byte-identical to the old direct call, so this is the same assertion
## the original test made, now pinned against the bridge it actually goes
## through.
func test_play_draws_through_the_illustrated_bridge():
	marker.play("fire_damage")
	var expected := IllustratedSpellEffectArt.new().texture_for("fire_damage")
	assert_eq(marker.texture.get_image().get_data(), expected.get_image().get_data())


## fire_damage is a burst-family atom (SpellImpactDistortionShader.
## atom_gets_distortion), so casting it must warp the screen behind it.
func test_a_burst_family_atom_gets_the_distortion_material():
	marker.play("fire_damage")
	assert_not_null(marker.material, "a burst-family cast must warp the world behind it")
	assert_eq(marker.material.shader, SpellImpactDistortionShader.material_for().shader)


## freeze is a ring-family atom -- settling into place, not a sudden
## release -- and must not warp the screen (spell_vfx.md's own gate).
func test_a_non_burst_atom_gets_no_distortion_material():
	marker.play("freeze")
	assert_null(marker.material, "a ring settling into place must not warp the world")


func _spawned_halo() -> MeshInstance2D:
	for child in get_children():
		if child is MeshInstance2D:
			return child
	return null


## Every atom, burst or not, gets the ambient glow -- light spilling onto
## the scene is universal (spell_vfx.md), unlike the burst-only warp.
func test_every_cast_spawns_a_glow_halo_sibling():
	marker.play("freeze")
	var halo := _spawned_halo()
	assert_not_null(halo, "even a non-burst atom must cast some light")
	assert_true(halo.material is ShaderMaterial)
	assert_eq(halo.material.shader, SpellGlowShader.material_for("freeze").shader)


## The halo is tinted for the atom actually cast, the same colour table the
## sprite itself reads -- so a halo and its own sprite can never visibly
## disagree about what colour that atom is.
func test_the_halo_is_tinted_for_the_cast_atom():
	marker.play("fire_damage")
	var halo := _spawned_halo()
	var expected: Color = ProceduralSpellEffectSprite.color_for("fire_damage")
	var tint: Vector3 = halo.material.get_shader_parameter("glow_color")
	assert_almost_eq(tint.x, expected.r, 0.001)
	assert_almost_eq(tint.y, expected.g, 0.001)
	assert_almost_eq(tint.z, expected.b, 0.001)


## The halo sits BEHIND the effect sprite (a lower draw index) -- light
## spilling outward reads correctly only if the sprite's own crisp
## silhouette draws on top of it, not the other way around.
func test_the_halo_draws_behind_the_effect_sprite():
	marker.play("fire_damage")
	var halo := _spawned_halo()
	assert_lt(halo.get_index(), marker.get_index())


## The halo must not outlive the marker it belongs to, or every cast leaks
## a node into the world forever.
func test_the_halo_is_freed_once_the_animation_completes():
	marker.play("fire_damage")
	var halo := _spawned_halo()
	assert_not_null(halo, "precondition: a halo was really spawned")
	await get_tree().create_timer(
		SpellEffectMarker.GROW_DURATION + SpellEffectMarker.HOLD_DURATION + SpellEffectMarker.FADE_DURATION + 0.2
	).timeout
	assert_false(is_instance_valid(halo), "the halo should have queue_free'd itself by now")


## Both shaders are driven by the SAME progress clock as the marker's own
## grow/hold/fade beat -- checked by sampling mid-flight rather than only
## at the two extremes, so a wiring bug that leaves `progress` stuck at 0
## cannot hide behind an untested middle.
func test_progress_is_advancing_partway_through_the_beat():
	marker.play("fire_damage")
	var halo := _spawned_halo()
	await get_tree().create_timer(SpellEffectMarker.GROW_DURATION + 0.01).timeout
	var halo_progress: float = halo.material.get_shader_parameter("progress")
	var distortion_progress: float = marker.material.get_shader_parameter("progress")
	assert_gt(halo_progress, 0.0, "the halo's own clock must have moved by the end of the grow window")
	assert_gt(distortion_progress, 0.0, "the distortion's own clock must have moved by the end of the grow window")


## Caught in review before this ever ran: the shader's own GLSL default for
## grow_fraction/hold_fraction happens to resemble the real derived values
## closely enough to look right by accident. This pins the REAL number, not
## a lookalike -- if the marker's own durations are ever retuned and the
## halo is not repointed at the new derivation, this fails.
func test_the_halo_receives_the_markers_own_derived_grow_and_hold_fractions():
	marker.play("fire_damage")
	var halo := _spawned_halo()
	var total: float = SpellEffectMarker.GROW_DURATION + SpellEffectMarker.HOLD_DURATION + SpellEffectMarker.FADE_DURATION
	var expected_grow: float = SpellEffectMarker.GROW_DURATION / total
	var expected_hold: float = SpellEffectMarker.HOLD_DURATION / total
	assert_almost_eq(
		float(halo.material.get_shader_parameter("grow_fraction")), expected_grow, 0.0001
	)
	assert_almost_eq(
		float(halo.material.get_shader_parameter("hold_fraction")), expected_hold, 0.0001
	)
