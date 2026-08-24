extends GutTest

const CharacterViewScene = preload("res://scenes/character_view.tscn")
const HeroAppearance = preload("res://src/rendering/hero_appearance.gd")
const CAMERA_ZOOM := 4.0

var view: CharacterView


func before_each():
	view = CharacterViewScene.instantiate()
	add_child(view)


func after_each():
	remove_child(view)
	view.free()


func test_dump_v3():
	for seed_value in [1, 12345, 777, 42, 999, 100]:
		var appearance := HeroAppearance.new().appearance_for("warrior", seed_value)
		view.apply_appearance(appearance)
		view.set_movement_state(view.MovementState.IDLE)
		view._process(0.016)

		var canvas := Image.create(400, 400, false, Image.FORMAT_RGBA8)
		canvas.fill(Color(0.2, 0.55, 0.25))
		var origin := Vector2(200, 320)
		var world_to_canvas: float = view.SCALE * CAMERA_ZOOM

		for node_name in ["LegLeft", "LegRight", "Body", "Neck", "ArmLeft", "ArmRight", "Head"]:
			var node: Sprite2D = view.get_node(node_name)
			if not node.visible or node.texture == null:
				continue
			var img: Image = node.texture.get_image()
			var content_w: float = img.get_width() * node.scale.x * world_to_canvas
			var content_h: float = img.get_height() * node.scale.y * world_to_canvas
			var resized: Image = img.duplicate()
			resized.resize(maxi(1, int(round(content_w))), maxi(1, int(round(content_h))), Image.INTERPOLATE_NEAREST)
			var effective_position: Vector2 = node.position + node.offset * node.scale
			var top_left: Vector2 = origin + effective_position * world_to_canvas - Vector2(resized.get_width(), resized.get_height()) * 0.5
			canvas.blend_rect(
				resized,
				Rect2i(Vector2i.ZERO, resized.get_size()),
				Vector2i(round(top_left.x), round(top_left.y))
			)

		canvas.save_png("res://tests/unit/zzdebug_v3_seed%d.png" % seed_value)

	assert_true(true)
