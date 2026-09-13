extends "res://src/world/stock_conversion_production.gd"

## The Bakery's own production (docs/concept/milling_and_baking.md): flour
## -> bread, the second StockConversionProduction instance. One flour per
## loaf (the chain's cost is its three buildings and the time, not a hidden
## loss rate), baked in fired batches -- slower per unit than the Mill's
## steady grinding (pinned against MillProduction in test_mill_
## production.gd). No oven fuel is modeled yet -- a named Open Question in
## the concept doc, not a silent omission.

## Flour consumed per loaf.
const FLOUR_PER_BREAD := 1.0

## Seconds of baking per loaf.
const BAKE_SECONDS_PER_BREAD := 10.0


func _init() -> void:
	super(FLOUR_PER_BREAD, BAKE_SECONDS_PER_BREAD)
