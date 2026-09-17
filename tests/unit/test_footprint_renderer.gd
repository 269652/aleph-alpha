extends GutTest

## FootprintRenderer: builds/fills MultiMeshInstance2D nodes from a
## FootprintField's individual stamps. Deliberately simpler than
## LeafLitterRenderer -- a footprint is static once stamped, so this
## needs no per-frame vertex-shader motion/atlas/INSTANCE_CUSTOM payload,
## just Godot's own built-in per-instance Transform2D on three plain
## MultiMeshInstance2D nodes (one per real surface). That simplicity is
## exactly what makes fill()'s own actual output directly testable here
## (get_instance_transform_2d readback) rather than deferred to a higher
## wiring test the way LeafLitterRenderer's own lossy INSTANCE_CUSTOM
## packing has to be (see test_leaf_litter_renderer.gd's own doc comment).

const FootprintRenderer = preload("res://src/rendering/footprint_renderer.gd")
const ProceduralFootprintSprite = preload("res://src/rendering/procedural_footprint_sprite.gd")

var renderer: FootprintRenderer
var parent: Node2D


func before_each():
	renderer = FootprintRenderer.new()
	parent = Node2D.new()
	add_child_autofree(parent)


func _print(position: Vector2, side: String, surface: String, heading: Vector2) -> Dictionary:
	return {"position": position, "side": side, "surface": surface, "heading": heading, "spawned_at": 0.0}


func _print_sized(position: Vector2, side: String, surface: String, heading: Vector2, size_scale: float) -> Dictionary:
	var p := _print(position, side, surface, heading)
	p["size_scale"] = size_scale
	return p


func test_build_multimeshes_makes_one_per_real_surface():
	var mmis := renderer.build_multimeshes(parent)
	for surface in FootprintRenderer.SURFACES:
		assert_true(mmis.has(surface), "%s should have its own MultiMeshInstance2D" % surface)
		assert_true(mmis[surface] is MultiMeshInstance2D)
	assert_eq(parent.get_child_count(), FootprintRenderer.SURFACES.size())


func test_fill_with_no_prints_leaves_every_surface_empty():
	var mmis := renderer.build_multimeshes(parent)
	renderer.fill(mmis, [])
	for surface in FootprintRenderer.SURFACES:
		assert_eq(mmis[surface].multimesh.instance_count, 0)


func test_fill_groups_prints_by_their_own_surface():
	var mmis := renderer.build_multimeshes(parent)
	var prints: Array = [
		_print(Vector2(0, 0), "left", "snow", Vector2.UP),
		_print(Vector2(1, 1), "right", "snow", Vector2.UP),
		_print(Vector2(2, 2), "left", "grass", Vector2.UP),
	]
	renderer.fill(mmis, prints)
	assert_eq(mmis["snow"].multimesh.instance_count, 2)
	assert_eq(mmis["grass"].multimesh.instance_count, 1)
	assert_eq(mmis["forest"].multimesh.instance_count, 0)


func test_an_unrecognized_surface_falls_back_to_grass_rather_than_being_dropped():
	var mmis := renderer.build_multimeshes(parent)
	renderer.fill(mmis, [_print(Vector2.ZERO, "left", "lava", Vector2.UP)])
	assert_eq(mmis["grass"].multimesh.instance_count, 1, "an unknown surface should still render somewhere, not vanish")


## Transform readback tests (position/rotation/mirror) live in
## test_footprint_renderer_smoke.gd instead -- MultiMesh.get_instance_
## transform_2d does not round-trip under --headless (confirmed directly:
## a minimal isolated probe returned a zeroed transform under --headless
## and the correct one under --rendering-driver opengl3), the same real
## GPU-readback limitation test_leaf_litter_renderer_smoke.gd's own doc
## comment already documents for this project.

func test_refilling_replaces_the_previous_contents_rather_than_appending():
	var mmis := renderer.build_multimeshes(parent)
	renderer.fill(mmis, [_print(Vector2.ZERO, "right", "snow", Vector2.UP)])
	renderer.fill(mmis, [_print(Vector2.ZERO, "right", "snow", Vector2.UP), _print(Vector2(1, 1), "left", "snow", Vector2.UP)])
	assert_eq(mmis["snow"].multimesh.instance_count, 2)


# -- size_scale: a heavier creature's print renders larger, a lighter -----
# -- one's smaller (see docs/concept/snow_cover.md's "Footprints depend ---
# -- on real mass, not just surface") -- pure transform math, directly ----
# -- testable headlessly without the real-GPU MultiMesh readback ----------
# -- test_footprint_renderer_smoke.gd's own position/rotation/mirror ------
# -- tests need (see that file's own doc comment on why: this reads the ---
# -- Transform2D _transform_for itself RETURNS, never round-tripping it ---
# -- through a MultiMesh at all).

func test_transform_for_scales_by_the_prints_own_size_scale():
	var p := _print_sized(Vector2.ZERO, "right", "snow", Vector2.UP, 2.0)
	var xform: Transform2D = renderer._transform_for(p)
	var expected := ProceduralFootprintSprite.PRINT_WORLD_SCALE * 2.0
	assert_almost_eq(xform.basis_xform(Vector2.RIGHT).length(), expected, 0.001)


func test_transform_for_shrinks_for_a_smaller_size_scale():
	var p := _print_sized(Vector2.ZERO, "right", "snow", Vector2.UP, 0.25)
	var xform: Transform2D = renderer._transform_for(p)
	var expected := ProceduralFootprintSprite.PRINT_WORLD_SCALE * 0.25
	assert_almost_eq(xform.basis_xform(Vector2.RIGHT).length(), expected, 0.001)


## Every pre-existing print dict (no "size_scale" key at all, like every
## helper call above this section) must keep rendering at exactly today's
## fixed size.
func test_transform_for_defaults_size_scale_to_one_with_no_size_scale_key():
	var p := _print(Vector2.ZERO, "right", "snow", Vector2.UP)
	var xform: Transform2D = renderer._transform_for(p)
	assert_almost_eq(xform.basis_xform(Vector2.RIGHT).length(), ProceduralFootprintSprite.PRINT_WORLD_SCALE, 0.001)


# -- the fade is actually drawn ---------------------------------------------
#
# FootprintField.opacity_of says how strongly a print still shows; nobody
# sees that unless the renderer puts it on the instance. Asked for: "add
# decay to the footprints ... make the decay gradually".

const FootprintField = preload("res://src/world/footprint_field.gd")


func _aged_print(decayed: float) -> Dictionary:
	var stamp := _print(Vector2.ZERO, "left", "snow", Vector2.UP)
	stamp["decayed"] = decayed
	return stamp


## MultiMesh instance COLOURS cannot be read back in a headless test the way
## transforms can -- get_instance_color answers (0,0,0,1) whatever was
## written, measured directly on Godot 4.7.2. So these assert the renderer's
## own decision (color_for), which fill() is the sole caller of, plus the one
## buffer property that DOES read back: without use_colors there is nowhere
## for a fade to live at all.
func test_the_buffer_can_carry_a_fade_at_all():
	var mmis := renderer.build_multimeshes(parent)
	renderer.fill(mmis, [_aged_print(0.0)])
	var mm: MultiMesh = (mmis["snow"] as MultiMeshInstance2D).multimesh
	assert_true(mm.use_colors, "a MultiMesh that carries no colours can never show a fade")


func test_a_fresh_print_is_drawn_at_full_strength():
	assert_almost_eq(FootprintRenderer.color_for(_aged_print(0.0)).a, 1.0, 0.001)


func test_a_half_faded_print_is_drawn_half_strength():
	assert_almost_eq(
		FootprintRenderer.color_for(_aged_print(FootprintField.HALF_LIFE_SECONDS)).a, 0.5, 0.01
	)


## The older a print, the fainter it is drawn.
func test_older_prints_are_drawn_fainter_than_younger_ones():
	var fresh := FootprintRenderer.color_for(_aged_print(0.0)).a
	var older := FootprintRenderer.color_for(_aged_print(FootprintField.HALF_LIFE_SECONDS)).a
	var oldest := FootprintRenderer.color_for(_aged_print(FootprintField.HALF_LIFE_SECONDS * 2.0)).a
	assert_gt(fresh, older)
	assert_gt(older, oldest)


## Every print written before decay existed carries no `decayed` key at all,
## and must draw exactly as it always did rather than as a blank.
func test_a_print_from_before_decay_existed_still_draws_solid():
	assert_almost_eq(
		FootprintRenderer.color_for(_print(Vector2.ZERO, "left", "snow", Vector2.UP)).a, 1.0, 0.001
	)
