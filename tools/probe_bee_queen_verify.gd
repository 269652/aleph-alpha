extends SceneTree

## Real-render verification for the row-semantics fix + the new queen --
## not a code-only trace (this codebase's own hard-won discipline for
## exactly this kind of sprite work). Kept as the permanent record,
## mirroring tools/probe_worm_sheet.gd's own "keep the probe that
## confirmed it" precedent. Dumps:
## 1. honeybee's now-wired "fly" frame -- should be the level-flight
##    pose (legs tucked, no ground shadow), NOT the walking pose row 0
##    used to be before this fix.
## 2. The queen's own static frame next to a worker's fly frame,
##    composited onto ONE shared-pixel-scale canvas at their REAL
##    relative world_scale/queen_world_scale -- confirms she actually
##    reads bigger on screen, not just via a larger source sheet.
##
## CONFIRMED (2026-09-08): fly frame 0 shows the level-flight silhouette,
## not the walking one. queen_world_scale produces a real, visibly
## larger, more golden figure with an elongated abdomen and a gold crown
## with a red jewel -- roughly 1.6x a worker's own on-screen width at a
## shared zoom, consistent with real queen honeybee biology (~20mm vs a
## worker's ~12-15mm).

const IllustratedBeeSprite = preload("res://src/rendering/illustrated_bee_sprite.gd")

## Arbitrary shared on-screen zoom (px per world tile) -- the SAME value
## for both figures is the entire point: this is what makes the
## comparison a real "how would these look next to each other in the
## game world" check rather than two independently-chosen crops.
const _PX_PER_TILE := 600.0


func _init() -> void:
	var gen := IllustratedBeeSprite.new()

	var worker_frame: Image = gen.generate_textures("honeybee")[0].get_image()
	var worker_scale := gen.world_scale("honeybee")
	print("honeybee fly frame 0: ", worker_frame.get_size(), " world_scale=", worker_scale)
	_save_backed(worker_frame, "user://verify_honeybee_fly_frame0.png")

	var queen_frame: Image = gen.generate_queen_texture().get_image()
	var queen_scale := gen.queen_world_scale()
	print("queen walk frame 0: ", queen_frame.get_size(), " queen_world_scale=", queen_scale)
	_save_backed(queen_frame, "user://verify_queen_frame0.png")

	var worker_scaled := _scaled(worker_frame, worker_scale)
	var queen_scaled := _scaled(queen_frame, queen_scale)
	print(
		"at a shared on-screen zoom: worker width=", worker_scaled.get_width(),
		"px queen width=", queen_scaled.get_width(),
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


func _scaled(frame: Image, world_scale: float) -> Image:
	var px_scale := world_scale * _PX_PER_TILE / IllustratedBeeSprite.TILE_SIZE
	var scaled := frame.duplicate() as Image
	scaled.resize(
		maxi(1, int(round(frame.get_width() * px_scale))),
		maxi(1, int(round(frame.get_height() * px_scale))),
		Image.INTERPOLATE_LANCZOS
	)
	return scaled


func _save_backed(image: Image, path: String) -> void:
	var img := image.duplicate() as Image
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	img.resize(img.get_width() * 2, img.get_height() * 2, Image.INTERPOLATE_NEAREST)
	var backed := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	backed.fill(Color(0.55, 0.55, 0.55, 1.0))
	backed.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i.ZERO)
	backed.save_png(path)
