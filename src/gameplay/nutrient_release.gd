extends RefCounted

## The generic, species-blind core of the Material DSL (see
## docs/concept/material_dsl.md): resolves a real bite-scale impact against
## a food's organic material, and, on a genuine crush, converts its real
## composition into meter-ready nutrient amounts. Pure and content-driven --
## it does not know or care who is eating, which is what makes "implicitly
## the same for all species" fall out of the caller side rather than needing
## to be built per species.

const FoodComposition = preload("res://src/gameplay/food_composition.gd")
const ImpactResolver = preload("res://src/gameplay/impact_resolver.gd")
const OrganicMaterialProperties = preload("res://src/gameplay/organic_material_properties.gd")

## A new named calibration point on materials.md's one damage model, a third
## alongside CrushMechanic's footstep scale and ImpactResolver.T_CRUSH's own
## combat scale -- each its own physical situation, none reused verbatim.
## Comfortably clears T_CRUSH against fruit_flesh's own toughness (see
## test_bite_momentum_actually_clears_the_crush_threshold), the real "a
## crushing force is applied" check rather than an assumed pass.
const BITE_MOMENTUM_KG_M_S: float = 4.5

## The contact geometry a bite delivers -- teeth closing flat against soft
## pulp, the same "blunt face" ImpactResolver already models for a footstep
## or a blunt weapon, not an edge or a point.
const BITE_GEOMETRY: String = "blunt"

## Every crushable food resolves against this one organic material for now
## (see organic_material_properties.gd) -- composition varies per food,
## physical response does not, at least until a food needs its own (a
## harder, unripe fruit, say).
const BITE_MATERIAL: String = "fruit_flesh"

## Converts "fraction of one whole fruit" into "meter-ready units".
## Calibrated so a whole apple's sugar content (0.10) lands in the same
## ballpark as today's flat Player.EAT_HUNGER_RELIEF (0.4) -- the real,
## composition-derived number replacing the old guess, not a wildly
## different scale: 0.4 / 0.10 = 4.0.
const NUTRIENT_UNIT_SCALE: float = 4.0


## `food_id`'s real nutrient yield from one whole-item bite: `{"crushed":
## bool, "water": float, "sugar": float, "vitamins": float}`. An unmodeled
## food, or a bite that somehow does not resolve to "crush" (never happens
## at BITE_MOMENTUM_KG_M_S against fruit_flesh today, but checked for real
## rather than assumed), releases nothing.
static func consume(food_id: String) -> Dictionary:
	var composition: Dictionary = FoodComposition.new().composition_for(food_id)
	if composition.is_empty():
		return {"crushed": false, "water": 0.0, "sugar": 0.0, "vitamins": 0.0}
	var resolver := ImpactResolver.new(OrganicMaterialProperties.new())
	var verdict := resolver.resolve_impact(BITE_MOMENTUM_KG_M_S, BITE_GEOMETRY, BITE_MATERIAL)
	if verdict != "crush":
		return {"crushed": false, "water": 0.0, "sugar": 0.0, "vitamins": 0.0}
	return {
		"crushed": true,
		"water": float(composition.get("water", 0.0)) * NUTRIENT_UNIT_SCALE,
		"sugar": float(composition.get("sugar", 0.0)) * NUTRIENT_UNIT_SCALE,
		"vitamins": float(composition.get("vitamins", 0.0)) * NUTRIENT_UNIT_SCALE,
	}
