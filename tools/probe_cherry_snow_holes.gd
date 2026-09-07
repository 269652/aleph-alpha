extends SceneTree

## Dev tool: investigates a live report -- "the cherry tree's snow
## accumulation is wrong and fills holes with white instead of accumulating
## snow on branches per branch" -- by rendering the real composited canopy
## and by directly comparing the season canopy's own alpha mask against the
## snow frame's own alpha mask, pixel for pixel, at the exact box size
## _composite_illustrated actually blends them at.
##
## Root-caused and fixed (see ProceduralTreeSprite._snowed_canopy's own doc
## comment and test_illustrated_tree.gd's
## test_no_species_snows_into_a_transparent_canopy_gap): the snow frame is a
## SEPARATE drawing from the season canopy, so the two silhouettes never
## line up pixel for pixel -- _diagnose below measures exactly that RAW
## source-image mismatch (real and unaffected by the fix; it is what made
## the bug possible in the first place), while the saved contact sheets show
## the actual COMPOSITED result through the real, now-fixed, pipeline
## (generate_image_with_fruit), which no longer paints into the mismatch.
## Kept as a dev tool for the next time a similar "two independently-drawn
## masks composited without checking each other" defect needs measuring, on
## this feature or a future one shaped the same way.
##
## Headless-safe: everything here is _scaled_piece/generate_image_with_fruit,
## which only touch Image/ImageTexture, no live viewport readback.
## Usage: godot --headless --path . -s tools/probe_cherry_snow_holes.gd

const ProceduralTreeSprite = preload("res://src/rendering/procedural_tree_sprite.gd")
const TreeSpecies = preload("res://src/world/tree_species.gd")
const IllustratedTree = preload("res://src/rendering/illustrated_tree.gd")

const OUT_DIR := "C:/Users/morrossl/AppData/Local/Temp/claude/C--Users-morrossl-Documents-Private-aleph-alpha/7f4eaa1a-f89f-4477-b7cb-4c0ca010a1aa/scratchpad/"
const SNOWABLE_CANOPIES := ["winter", "spring", "autumn"]
const SPECIES_TO_CHECK := ["cherry", "walnut", "apple"]
const UPSCALE := 3


func _bias_for(species: String) -> float:
	for step in 201:
		var bias := float(step) / 200.0
		if TreeSpecies.species_for_bias(bias) == species:
			return bias
	return 0.0


## Diagnostic mask: for the box _composite_illustrated actually blends the
## season canopy and the snow frame at, colours each pixel by which of the
## two SOURCE images has real content there (before compositing, so this is
## the raw silhouette mismatch the fix now guards against, not a live check
## of the running code -- see this file's own header) --
##   transparent = neither
##   green       = season canopy only (real canopy, no snow drawn there yet)
##   RED         = SNOW ONLY, canopy transparent -- exactly what made the
##                 reported bug possible: the snow frame's OWN drawing has
##                 paint somewhere this season's canopy has no branch at
##                 all. Pre-fix, full coverage painted this red area solid
##                 white -- a gap filled in, not a twig dressed. Post-fix,
##                 _snowed_canopy refuses to paint here at all (gated on the
##                 canopy's own alpha), so this area now stays exactly
##                 whatever the plain canopy already was.
##   blue        = both -- snow legitimately settling on a real branch
func _diagnose(sprite: ProceduralTreeSprite, species_id: String, season: String) -> Dictionary:
	var box: Rect2i = sprite.illustrated_canopy_box(species_id, 7, season)
	var canopy_image: Image = sprite._scaled_piece(species_id, season, "canopy", box.size)
	var snow_image: Image = sprite._scaled_piece(species_id, ProceduralTreeSprite.SNOW_CANOPY_KEY, "canopy", box.size)
	var mask := Image.create(box.size.x, box.size.y, false, Image.FORMAT_RGBA8)
	var canopy_only := 0
	var snow_only_hole := 0
	var both := 0
	var neither := 0
	if canopy_image != null and snow_image != null:
		for y in box.size.y:
			for x in box.size.x:
				var c := canopy_image.get_pixel(x, y).a > ProceduralTreeSprite.ALPHA_PAINTED
				var s := snow_image.get_pixel(x, y).a >= ProceduralTreeSprite.ALPHA_VISIBLE
				if c and s:
					mask.set_pixel(x, y, Color(0.2, 0.4, 1.0, 1.0))
					both += 1
				elif c:
					mask.set_pixel(x, y, Color(0.1, 0.7, 0.2, 1.0))
					canopy_only += 1
				elif s:
					mask.set_pixel(x, y, Color(1.0, 0.05, 0.05, 1.0))
					snow_only_hole += 1
				else:
					neither += 1
	mask.resize(box.size.x * UPSCALE, box.size.y * UPSCALE, Image.INTERPOLATE_NEAREST)
	var out_name := "diag_%s_%s.png" % [species_id, season]
	mask.save_png(OUT_DIR + out_name)
	return {
		"canopy_only": canopy_only,
		"snow_only_hole": snow_only_hole,
		"both": both,
		"neither": neither,
		"box": box,
		"file": out_name,
	}


func _render_contact_sheet(sprite: ProceduralTreeSprite, species: String, bias: float) -> void:
	var coverages := [0.0, 0.35, 0.7, 1.0]
	var cell := ProceduralTreeSprite.SIZE * UPSCALE
	var sheet := Image.create(
		cell.x * coverages.size(), cell.y * SNOWABLE_CANOPIES.size(), false, Image.FORMAT_RGBA8
	)
	for row in SNOWABLE_CANOPIES.size():
		var season: String = SNOWABLE_CANOPIES[row]
		for col in coverages.size():
			var coverage: float = coverages[col]
			var image := sprite.generate_image_with_fruit(bias, 7, 0, season, "", 0.0, 1.0, coverage)
			var big := image.duplicate()
			big.resize(cell.x, cell.y, Image.INTERPOLATE_NEAREST)
			sheet.blit_rect(big, Rect2i(Vector2i.ZERO, cell), Vector2i(col * cell.x, row * cell.y))
	var out_name := "contact_%s.png" % species
	sheet.save_png(OUT_DIR + out_name)
	print("  saved contact sheet %s (rows=%s, cols(coverage)=%s)" % [out_name, SNOWABLE_CANOPIES, coverages])


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	for species in SPECIES_TO_CHECK:
		var sprite := ProceduralTreeSprite.new()
		var bias := _bias_for(species)
		print("== %s (bias=%.3f) ==" % [species, bias])
		for season in SNOWABLE_CANOPIES:
			var stats := _diagnose(sprite, species, season)
			var box: Rect2i = stats["box"]
			print(
				(
					"  %-7s box=%dx%d  canopy_only=%-6d both=%-6d "
					+ "SNOW_ONLY_HOLE=%-6d  (hole/total_snow=%.1f%%)  -> %s"
				) % [
					season, box.size.x, box.size.y,
					stats["canopy_only"], stats["both"], stats["snow_only_hole"],
					100.0 * float(stats["snow_only_hole"]) / maxf(1.0, float(stats["snow_only_hole"] + stats["both"])),
					stats["file"],
				]
			)
		_render_contact_sheet(sprite, species, bias)
	print("Done. Files in %s" % OUT_DIR)
	quit()
