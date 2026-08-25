extends RefCounted

## Derives a real labor-hours requirement for a ConstructionProject's own
## blueprint_id from its real CraftingRecipeBook recipe (see docs/concept/
## timber_construction.md's "Unloaded / offscreen fidelity" subsection).
##
## There is no HouseBlueprint.total_labor_hours field anywhere real today --
## blueprint_id on a real ConstructionProject is a CraftingRecipeBook recipe
## id (e.g. "sagewerk", "storage"), not a HouseBlueprint id. So this sums
## the recipe's own real input material counts (recipe_book.recipe_inputs)
## and scales by a named, test-pinned HOURS_PER_UNIT_MATERIAL constant,
## grounded in "a structure needing more raw material to assemble genuinely
## takes more labor to put together" -- the same proportional-to-real-
## quantity reasoning SagewerkProduction's own LOG_COST_PER_BEAM/
## SHAPE_SECONDS_PER_BEAM asymmetry already uses (more material in, more
## time to work it), not an arbitrary flat number per project.
##
## Deliberately its own small, pure, static-function module (mirroring
## ConstructionStartHysteresis's own "small fresh module, not a reuse of
## something contract-specific" shape) -- separately testable from both
## ConstructionProject (a data holder, no recipe-book dependency) and
## ConstructionProjectStore (the collection + persistence split).

## Labor-hours of assembly work one unit of a recipe's own input material
## demands, once gathered -- raising a structure from stacked material
## (fitting, joining, raising into place) is real skilled labor scaled by
## how much material there is to work, not a flat per-project cost
## regardless of size. Calibrated so a small real recipe (`storage`: 12
## wood + 4 plank = 16 units -> 24 hours) sits on the order of a real few-
## day build for a small shed by a single builder (HOURS_PER_BUILDER_PER_DAY
## in construction_catchup.gd), the same vernacular-construction pace this
## doc's own "Vernacular settlements grow one building at a time" grounding
## names -- test-pinned (test_construction_labor.gd) rather than an
## eyeballed comment alone, per this project's no-manual-tuning rule.
const HOURS_PER_UNIT_MATERIAL := 1.5


## The real labor-hours a project building `blueprint_id` requires, derived
## from `recipe_book`'s own real input material counts. 0.0 for an unknown
## blueprint_id (recipe_inputs already returns an empty Array for one).
## Pure, deterministic -- no state, no RNG.
static func labor_hours_required(blueprint_id: String, recipe_book) -> float:
	var total := 0.0
	for input in recipe_book.recipe_inputs(blueprint_id):
		total += float(input["count"]) * HOURS_PER_UNIT_MATERIAL
	return total
