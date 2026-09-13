extends "res://src/rendering/structure_conversion_marker.gd"

## The Bakery's Baker (docs/concept/milling_and_baking.md): bakes the flour
## in the Bakery's own StructureStock into bread -- real food -- at
## BakeryProduction's pinned pace. See StructureConversionMarker for the
## shared mechanics.

const BakeryProduction = preload("res://src/world/bakery_production.gd")


func _init() -> void:
	input_item_id = "flour"
	output_item_id = "bread"
	display_name = "Baker"
	_production = BakeryProduction.new()
