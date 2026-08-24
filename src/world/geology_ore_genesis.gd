extends RefCounted

## Layer-aware ore type genesis, extending OrePlacement's coordinate-hash
## shape (docs/concept/geology.md "The four layers" table): the SAME
## deterministic-per-tile approach, just weighted by which real ore
## concentrates in which layer instead of picking uniformly among
## OrePlacement.ORE_TYPES.
##
## Grounded in real ore-deposit geology, not invented tiers -- coal forms in
## shallow sedimentary seams (favoured in topsoil/regolith), iron in banded
## formations through the solid crust (favoured in bedrock, more so in deep
## bedrock), and copper concentrates in real porphyry/epithermal deposits
## fed by circulating hydrothermal fluids (favoured in the hydrothermal
## zone specifically -- the one weighting here tied to a named real deposit
## TYPE, not just "rarer/deeper").

const OrePlacement = preload("res://src/world/ore_placement.gd")
const PixelNoise = preload("res://src/rendering/pixel_noise.gd")

## Per-layer weight over OrePlacement.ORE_TYPES ("iron", "copper", "coal"),
## in that fixed order. Need not sum to 1 -- normalized at pick time -- but
## kept roughly proportioned here for readability. An unknown/unwired layer
## (including the empty string) falls back to OrePlacement's own uniform
## weighting, matching the "extends this exact shape" contract rather than
## silently returning something OrePlacement wouldn't.
const LAYER_WEIGHTS := {
	"topsoil_regolith": {"iron": 0.25, "copper": 0.05, "coal": 0.70},
	"bedrock": {"iron": 0.60, "copper": 0.10, "coal": 0.30},
	"deep_bedrock": {"iron": 0.70, "copper": 0.20, "coal": 0.10},
	"hydrothermal": {"iron": 0.20, "copper": 0.70, "coal": 0.10},
}

## OrePlacement's own effectively-uniform weighting (see its ore_type_at:
## an index picked evenly across ORE_TYPES), used as the fallback for any
## layer this table doesn't know about.
const _UNIFORM_WEIGHTS := {"iron": 1.0, "copper": 1.0, "coal": 1.0}


## The ore type at this global tile for `layer`, deterministic per
## (x, y, layer). Independent of whether a cell is actually ore-bearing --
## same "meaningful only where the caller already knows it's ore" contract
## as OrePlacement.ore_type_at.
func ore_type_at(global_x: int, global_y: int, layer: String) -> String:
	var weights: Dictionary = LAYER_WEIGHTS.get(layer, _UNIFORM_WEIGHTS)
	var total := 0.0
	for ore_type in OrePlacement.ORE_TYPES:
		total += float(weights.get(ore_type, 0.0))
	if total <= 0.0:
		return OrePlacement.ORE_TYPES[0]

	var roll := PixelNoise.unit(hash("geology_ore_genesis_%s" % layer), global_x, global_y) * total
	var running := 0.0
	for ore_type in OrePlacement.ORE_TYPES:
		running += float(weights.get(ore_type, 0.0))
		if roll < running:
			return ore_type
	return OrePlacement.ORE_TYPES[OrePlacement.ORE_TYPES.size() - 1]
