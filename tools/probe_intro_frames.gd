extends SceneTree

## Every Nth frame the intro actually plays, laid out side by side at native
## size, so "are the crops right" is answered by looking. A crop that reads
## the wrong cell, catches a divider, or keeps the sheet's own timestamp
## caption is obvious here and invisible in a constant.

const OUT := "res://tools/intro_grid_renders/frames.png"
const EVERY := 8


func _init() -> void:
	var IntroSplashSheet = load("res://src/rendering/intro_splash_sheet.gd")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT).get_base_dir())
	var frames: Array = IntroSplashSheet.new().generate_textures()
	print("frames: %d" % frames.size())
	if frames.is_empty():
		quit()
		return
	var shown: Array = []
	for i in frames.size():
		if i % EVERY == 0:
			shown.append(frames[i].get_image())
	var width: int = int(shown[0].get_width())
	var height: int = int(shown[0].get_height())
	var sheet := Image.create(width * shown.size(), height, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.15, 0.0, 0.15, 1.0))  # magenta backdrop: any gap shows
	for i in shown.size():
		sheet.blit_rect(shown[i], Rect2i(0, 0, width, height), Vector2i(width * i, 0))
	sheet.resize(sheet.get_width() * 2, sheet.get_height() * 2, Image.INTERPOLATE_NEAREST)
	sheet.save_png(OUT)
	print("saved %s  (every %dth frame, %dx%d each)" % [OUT, EVERY, width, height])
	quit()
