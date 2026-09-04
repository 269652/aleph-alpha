extends SceneTree

## Diagnostic: measures the REAL pixel content of every tree canopy sheet on
## disk, both via SpriteSheetLoader (imported resource, what the game
## actually uses) and via a raw Image.load_from_file (bypasses the .import
## cache entirely), to tell apart a stale-cache false alarm from a real
## content regression -- see docs/progress.md's "canopy_cherry.png grew a
## real fifth column" entry for the precedent this follows.
##
## Usage: godot --headless -s tools/measure_canopy_sheets.gd

const CompositeSheetSlicer = preload("res://src/rendering/composite_sheet_slicer.gd")
const SpriteSheetLoader = preload("res://src/rendering/sprite_sheet_loader.gd")

const SHEETS := [
	"res://assets/sprites/trees/composite_cherry.png",
	"res://assets/sprites/trees/composite_walnut.png",
	"res://assets/sprites/trees/composite_acorn.png",
	"res://assets/sprites/trees/composite_hazelnut.png",
	"res://assets/sprites/trees/composite_pine.png",
	"res://assets/sprites/trees/composite_apple.png",
	"res://assets/sprites/trees/canopy_cherry.png",
]


func _initialize():
	for path in SHEETS:
		print("\n=== %s ===" % path)
		print("  ResourceLoader.exists: %s   FileAccess.file_exists: %s" % [
			ResourceLoader.exists(path), FileAccess.file_exists(path)
		])

		var loaded := SpriteSheetLoader.load_image(path)
		if loaded == null:
			print("  SpriteSheetLoader: MISSING (null)")
		else:
			_report("SpriteSheetLoader (imported)", loaded)

		if FileAccess.file_exists(path):
			var raw := Image.load_from_file(path)
			_report("Image.load_from_file (raw)", raw)
			if loaded != null:
				var same_size: bool = loaded.get_size() == raw.get_size()
				print("  raw vs imported: same size=%s" % same_size)
		else:
			print("  Image.load_from_file (raw): no plain file on disk")
	quit()


func _report(label: String, image: Image) -> void:
	print("  [%s] %dx%d format=%d" % [label, image.get_width(), image.get_height(), image.get_format()])
	if image.get_format() != Image.FORMAT_RGBA8:
		image = image.duplicate()
		image.convert(Image.FORMAT_RGBA8)
	var regions := CompositeSheetSlicer.regions_in(image)
	print("    regions_in -> %d regions:" % regions.size())
	for r in regions:
		print("      %s" % r)
	# Column content profile across the TOP band only (canopy strip), at
	# 1px-x resolution down the full sheet height, independent of the
	# blob-merge logic -- shows the raw number of separate humps of content
	# regardless of how regions_in grouped them.
	if regions.is_empty():
		return
	var band_bottom: int = regions[0].position.y + regions[0].size.y
	# Use a generous top-band height guess: twice the first region's height,
	# or the sheet's own height if that overshoots -- just needs to cover
	# the canopy strip without reaching into the trunk/fruit rows below.
	var scan_bottom: int = mini(band_bottom + regions[0].size.y, image.get_height())
	var had_content := false
	var run_start := -1
	var runs: Array = []
	for x in image.get_width():
		var any_content := false
		for y in range(0, scan_bottom, 3):
			if not CompositeSheetSlicer.is_background(image.get_pixel(x, y)):
				any_content = true
				break
		if any_content and not had_content:
			run_start = x
		elif not any_content and had_content:
			runs.append([run_start, x - 1])
		had_content = any_content
	if had_content:
		runs.append([run_start, image.get_width() - 1])
	print("    raw column-content runs in canopy band (y 0..%d), min-width-filtered NONE: %d runs" % [scan_bottom, runs.size()])
	for run in runs:
		print("      x %d..%d (width %d)" % [run[0], run[1], run[1] - run[0] + 1])
