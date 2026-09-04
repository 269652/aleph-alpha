extends SceneTree

## Generates the SAMPLE wooden_club combat sheet from WoodenClubSheetPainter
## and writes it where IllustratedItemSprite expects it:
##
##     assets/sprites/items/wooden_club_combat.png
##
## The painter is deterministic, so re-running this reproduces the committed
## file byte-for-byte; a real image-model sheet (see docs/art/
## ai_sprite_prompts.md section 11) replaces the file in place and this tool
## simply stops being the source of it -- re-measure IllustratedItemSprite's
## row bands against the new file the same way every animal sheet's were.
##
## Usage: godot --headless -s tools/generate_wooden_club_sheet.gd
## (then run `godot --headless --import` so the .png.import is regenerated)

const Painter = preload("res://src/rendering/wooden_club_sheet_painter.gd")

const OUTPUT := "res://assets/sprites/items/wooden_club_combat.png"


func _initialize():
	var sheet := Painter.new().paint()
	var error := sheet.save_png(OUTPUT)
	if error != OK:
		push_error("could not write %s: error %d" % [OUTPUT, error])
	else:
		print("wrote %s (%dx%d)" % [OUTPUT, sheet.get_width(), sheet.get_height()])
	quit(0 if error == OK else 1)
