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

var renderer: FootprintRenderer
var parent: Node2D


func before_each():
	renderer = FootprintRenderer.new()
	parent = Node2D.new()
	add_child_autofree(parent)


func _print(position: Vector2, side: String, surface: String, heading: Vector2) -> Dictionary:
	return {"position": position, "side": side, "surface": surface, "heading": heading, "spawned_at": 0.0}


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
