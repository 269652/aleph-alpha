extends SceneTree

## What a hall actually looks like once furnished, printed as the grid a
## player will walk around in (docs/concept/building.md, "A hall is a
## workplace"). Every variant, for a mage guild and for a warehouse, so
## the one shared shape can be read next to both trades that use it -- and
## so "is there really room for three masters to stand" is answered by
## counting rather than by looking at ASCII and hoping.
##
## Usage: godot --headless -s tools/probe_hall_interior.gd

const InteriorTemplates = preload("res://src/gameplay/interior_templates.gd")
const MageMaster = preload("res://src/gameplay/mage_master.gd")
const MageGuildRoster = preload("res://src/gameplay/mage_guild_roster.gd")

const _GLYPH := {
	"wall": "#", "window": "o", "door": "D", "floor": ".",
	"wood_table": "T", "wood_chair": "c", "couch": "c", "wood_rug": "r",
	"wood_bookshelf": "B", "cupboard": "u", "photo_frame": "p", "hearth": "K",
	"candle": "*", "workbench": "W", "crate": "W", "anvil": "W", "barrel": "W",
	"chest": "W", "wood_bed": "!",
}


func _initialize() -> void:
	for occupation in [MageMaster.OCCUPATION, "merchant"]:
		for variant in InteriorTemplates.variant_count("hall"):
			var grid := InteriorTemplates.grid_for("hall", variant)
			var result := InteriorTemplates.furnish("hall", occupation, _seed_for(variant))
			if result["variant_index"] != variant:
				continue
			_print_room(occupation, variant, result)
	_print_standing_room()
	quit()


## A seed that lands on `variant`, so every plan gets printed rather than
## whichever one one seed happened to choose.
func _seed_for(variant: int) -> int:
	for seed_value in 500:
		if InteriorTemplates.choose_variant_index("hall", seed_value) == variant:
			return seed_value
	return 0


func _print_room(occupation: String, variant: int, result: Dictionary) -> void:
	var size: Vector2i = result["size"]
	var cells: Dictionary = result["cells"]
	print("\n-- hall variant %d, furnished for a %s --" % [variant, occupation])
	for y in size.y:
		var row := ""
		for x in size.x:
			var value := String(cells.get(Vector2i(x, y), "floor"))
			row += String(_GLYPH.get(value, "?"))
		print("  " + row)
	var open := 0
	for local in cells:
		if String(cells[local]) == "floor":
			open += 1
	print("  open floor: %d cells (a full guild needs %d)" % [open, MageGuildRoster.CAPACITY])


func _print_standing_room() -> void:
	print("\n-- room to stand, hall vs cottage --")
	for family in ["cottage", "hall"]:
		var worst := 99999
		for variant in InteriorTemplates.variant_count(family):
			var result := InteriorTemplates.furnish(family, MageMaster.OCCUPATION, _seed_for_family(family, variant))
			var open := 0
			for local in result["cells"]:
				if String(result["cells"][local]) == "floor":
					open += 1
			worst = mini(worst, open)
		print("  %-9s poorest plan leaves %d open cells" % [family, worst])


func _seed_for_family(family: String, variant: int) -> int:
	for seed_value in 500:
		if InteriorTemplates.choose_variant_index(family, seed_value) == variant:
			return seed_value
	return 0
