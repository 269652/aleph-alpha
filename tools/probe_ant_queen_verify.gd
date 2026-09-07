extends SceneTree

## Real-render verification for the new procedural ant queen -- not a
## code-only trace (this codebase's own hard-won discipline for exactly
## this kind of sprite work, see tools/probe_bee_queen_verify.gd's
## identical precedent). Dumps the worker "ant" and new "queen" procedural
## silhouettes side by side, scaled by the SAME real ArtResolution.
## SPRITE_SCALE both actually render at in game (AntForagerMarker's own
## procedural fallback branch, AntQueenMarker's identical one) -- so the
## comparison shows the real relative on-screen size and shape, not two
## independently-chosen crops.

const ProceduralDecomposerSprite = preload("res://src/rendering/procedural_decomposer_sprite.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")


func _init() -> void:
	var gen := ProceduralDecomposerSprite.new()

	var worker_image := gen.generate_image("ant")
	print("worker ant image: ", worker_image.get_size(), " canvas SIZE=", ProceduralDecomposerSprite.SIZE)
	_save_backed(worker_image, "user://verify_ant_worker.png")

	var queen_image := gen.generate_image("queen")
	print("queen image: ", queen_image.get_size(), " canvas QUEEN_SIZE=", ProceduralDecomposerSprite.QUEEN_SIZE)
	_save_backed(queen_image, "user://verify_ant_queen.png")

	var worker_scaled := _scaled(worker_image, ArtResolution.SPRITE_SCALE)
	var queen_scaled := _scaled(queen_image, ArtResolution.SPRITE_SCALE)
	print(
		"at the SAME real ArtResolution.SPRITE_SCALE both actually render at: worker width=",
		worker_scaled.get_width(), "px queen width=", queen_scaled.get_width(),
		"px ratio=", float(queen_scaled.get_width()) / float(worker_scaled.get_width())
	)

	# Canvas sized to what's actually being drawn (not a guessed constant)
	# so neither figure clips, both standing on a shared bottom baseline.
	var margin := 20
	var canvas_w := worker_scaled.get_width() + queen_scaled.get_width() + margin * 3
	var canvas_h := maxi(worker_scaled.get_height(), queen_scaled.get_height()) + margin * 2
	var canvas := Image.create(canvas_w, canvas_h, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0.55, 0.55, 0.55, 1.0))
	canvas.blend_rect(
		worker_scaled, Rect2i(Vector2i.ZERO, worker_scaled.get_size()),
		Vector2i(margin, canvas_h - margin - worker_scaled.get_height())
	)
	canvas.blend_rect(
		queen_scaled, Rect2i(Vector2i.ZERO, queen_scaled.get_size()),
		Vector2i(margin * 2 + worker_scaled.get_width(), canvas_h - margin - queen_scaled.get_height())
	)
	canvas.save_png("user://verify_worker_vs_queen_real_scale.png")
	print("saved comparison -> user://verify_worker_vs_queen_real_scale.png")
	print("dumped to: ", OS.get_user_data_dir())
	quit()


func _scaled(image: Image, sprite_scale: float) -> Image:
	var scaled := image.duplicate() as Image
	scaled.resize(
		maxi(1, int(round(image.get_width() * sprite_scale * 20.0))),
		maxi(1, int(round(image.get_height() * sprite_scale * 20.0))),
		Image.INTERPOLATE_NEAREST
	)
	return scaled


func _save_backed(image: Image, path: String) -> void:
	var img := image.duplicate() as Image
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	img.resize(img.get_width() * 8, img.get_height() * 8, Image.INTERPOLATE_NEAREST)
	var backed := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	backed.fill(Color(0.55, 0.55, 0.55, 1.0))
	backed.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i.ZERO)
	backed.save_png(path)
