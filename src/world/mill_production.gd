extends "res://src/world/stock_conversion_production.gd"

## The Mill's own production (docs/concept/milling_and_baking.md): wheat ->
## flour, a StockConversionProduction instance with the Mill's pinned
## constants. Real-world grounding, from that doc: a village mill stone-
## grinds the WHOLE kernel and sifts nothing away ("wholemeal, not white"),
## so the cost is a whole unit of wheat per flour, not a fractional
## extraction rate -- and a quern-house grinds grain steadily as it
## arrives, so a unit of flour takes less time than the Bakery's fired
## batch takes per loaf (MILL_SECONDS_PER_FLOUR < BakeryProduction.BAKE_
## SECONDS_PER_BREAD). Both relationships are pinned by test_mill_
## production.gd rather than left as comments.

## Wheat consumed per unit of flour.
const WHEAT_PER_FLOUR := 1.0

## Seconds of grinding per unit of flour.
const MILL_SECONDS_PER_FLOUR := 4.0


func _init() -> void:
	super(WHEAT_PER_FLOUR, MILL_SECONDS_PER_FLOUR)
