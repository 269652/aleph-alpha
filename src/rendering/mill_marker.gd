extends "res://src/rendering/structure_conversion_marker.gd"

## The Mill's Miller (docs/concept/milling_and_baking.md): grinds the wheat
## in the Mill's own StructureStock into flour, at MillProduction's pinned
## pace. See StructureConversionMarker for the shared mechanics.

const MillProduction = preload("res://src/world/mill_production.gd")


func _init() -> void:
	input_item_id = "wheat"
	output_item_id = "flour"
	display_name = "Miller"
	_production = MillProduction.new()
