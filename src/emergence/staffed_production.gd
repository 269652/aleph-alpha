extends RefCounted

## docs/concept/village_estates.md mechanism 4, wired to real output -- and
## the close of docs/concept/village_growth.md's own standing gap, "the
## ladder's rungs are buildings, not yet production."
##
## Before this a village raised a brewery and had no beer, a farmhouse and
## no grain. VillageLabor said what share of full output a building runs
## at; nothing anywhere multiplied anything by it, so the whole labour
## pyramid was a number nobody spent.
##
## Two kinds of output, because the ladder's rungs are two kinds of
## building:
##
## - **A works runs a recipe.** A staffed farmhouse grows wheat; a staffed
##   brewery brews beer. Whole attempts out, the fraction carried, scaled
##   by VillageLabor.output_scale_for -- so an unstaffed building produces
##   NOTHING however long it stands, which is the pyramid's whole claim.
## - **A saw pit raises what the same hands bring in.** There is no `log`
##   in a village's economy to saw (SettlementGathering gathers `wood`
##   directly), so a sawmill has no recipe to run; what it really does is
##   get more usable timber out of the same labour. That also makes
##   VillageAssembly's own "short of firewood -> build a sawmill" petition
##   TRUE rather than a lie.
##
## The timber multiplier is never below 1.0, and that floor is deliberate:
## docs/concept/village_growth.md's own rule is that a hungry village must
## still be able to cut the timber for the farm that would fix its hunger,
## so gathering may be RAISED by a building and must never be dragged down
## by one. An unstaffed mill is worth nothing, not worth less than nothing.
##
## Pure and static. Every tuned value is pinned by
## test_staffed_production.gd against the relation it produces.

const VillageLabor = preload("res://src/emergence/village_labor.gd")

## Which CraftingRecipeBook recipe each standing building runs.
##
## Three rules, all test-pinned:
## 1. The recipe is really GATED on a structure. An ungated recipe needs no
##    building to run it and is already somebody's household work
##    (OccupationProduction), so running it here too would simply produce
##    the same goods twice for one set of hands.
## 2. The building IS that gate (see structure_satisfied_by for the one
##    documented alias).
## 3. Nothing here duplicates an occupation's own recipe.
##
## Which is why two of the ladder's four works are absent, both
## deliberately and both for a reason the code found rather than chose:
##
## - The **blacksmith** would really run the heat-gated smelts
##   OccupationProduction rules out on principle, and its one ungated tool
##   recipe is already run by the smith's own household. It is a charter
##   building and a real employer of craftsmen; it is not a producer here.
## - The **farmhouse** would run `grow_wheat`, and `grow_wheat` is
##   `automated` -- CraftingRecipeBook.can_craft refuses an automated
##   recipe outright, because it is a real world-standing structure's own
##   production. A farmhouse's grain really does come from its real field
##   (FarmPlot/VillageFarm, docs/concept/village_farms.md), worked by real
##   villagers on real plots, and running it a second time through a market
##   abstraction would be the same crop harvested twice.
##
## So this table is ONE entry, and that entry is the one thing on the
## ladder that genuinely produced nothing before: the brewery. Rule 4,
## test-pinned with the rest -- nothing here is an automated recipe.
const RECIPE_BY_BUILDING := {
	"brewery": "brew_beer",
}

## The ONE alias between a building and the structure id a recipe gates on:
## a farmhouse IS the farm raised as a real multi-tile building rather than
## a single tile, which BuildingCatalog's own entry says in as many words
## ("npc_farm_production.md's Farm, raised as a real building"). Named here
## rather than assumed, so a reader can see there is exactly one.
const _STRUCTURE_ALIAS := {"farmhouse": "farm"}


## The structure id this building satisfies for a recipe gate -- itself,
## unless it is the one documented alias above.
static func structure_satisfied_by(building_id: String) -> String:
	return _STRUCTURE_ALIAS.get(building_id, building_id)


## How many batches one FULLY staffed building runs per day -- counted in
## the day the settlement's MATERIAL economy runs on (SettlementGathering's
## own, ConstructionCatchup.SECONDS_PER_DAY), because the inputs come off
## and the outputs go onto that same shelf.
##
## The number is not chosen for feel. It is the smallest round figure that
## satisfies the relation below, which is what actually has to be true:
##
## **A works must supply several times more households than it employs.**
## A brewery takes two heads -- a brewer and a pair of hands -- and a
## burgher drinks beer every day. If the brewhouse cannot keep several
## times its own staff in beer it costs the village more labour than it
## returns, and nobody should ever build one.
##
## Pinned by test_a_staffed_works_supplies_more_households_than_it_employs
## against MIN_SELF_SUFFICIENCY_MULTIPLE below, so the rate moves when the
## baskets do rather than stranding a constant.
const BATCHES_PER_BUILDING_PER_DAY := 6.0

## How many times its own headcount a fully staffed works must supply.
## Three, not one: at exactly one the works serves nobody but the people
## working it, which is a village doing the same work twice.
const MIN_SELF_SUFFICIENCY_MULTIPLE := 3.0

## What a fully staffed saw pit is worth to the village's own timber:
## half as much again out of the same hands.
const SAWMILL_TIMBER_BONUS := 0.5
const SAWMILL_BUILDING_ID := "sawmill"


## How many heads of any class this building needs to run at full output --
## its whole workforce, summed.
static func staff_needed_for(building_id: String) -> int:
	return VillageLabor.total_heads(VillageLabor.LABOUR_BY_BUILDING.get(building_id, {}))


## `{"attempts": {recipe_id -> whole attempts now}, "carry": {...}}` for
## everything standing, over `days`.
##
## `carry` is the caller's own sub-unit remainder, carried the same
## whole-units-out way SettlementGathering, SettlementGranary and
## VillageImmigration all already do, so a village assessed often is not
## held back against one assessed rarely. The caller's dictionary is never
## mutated.
static func attempts_over(
	present_building_ids: Array, supply: Dictionary, demand: Dictionary, days: float, carry: Dictionary
) -> Dictionary:
	var next_carry := carry.duplicate()
	var attempts := {}
	if days <= 0.0:
		return {"attempts": attempts, "carry": next_carry}

	# Accrued per RECIPE rather than per building, so two farmhouses are
	# two farmhouses' worth of one recipe rather than two separate carries
	# that each round down to nothing.
	var accrued := {}
	for building_id in present_building_ids:
		var recipe_id: String = RECIPE_BY_BUILDING.get(building_id, "")
		if recipe_id == "":
			continue
		var scale := VillageLabor.output_scale_for(building_id, supply, demand)
		if scale <= 0.0:
			continue
		accrued[recipe_id] = (
			float(accrued.get(recipe_id, 0.0)) + BATCHES_PER_BUILDING_PER_DAY * scale * days
		)

	for recipe_id in accrued:
		var owed: float = float(next_carry.get(recipe_id, 0.0)) + float(accrued[recipe_id])
		var whole := int(floor(owed + 0.000001))
		if whole > 0:
			attempts[recipe_id] = whole
		# maxf for the reason VillageImmigration's own carry needs one: the
		# epsilon that saves a float 0.9999999 can also carry `owed` just
		# past `whole`, and a negative remainder compounds.
		next_carry[recipe_id] = maxf(owed - float(whole), 0.0)
	return {"attempts": attempts, "carry": next_carry}


## What a village's own timber gathering is multiplied by, given what
## stands and who staffs it. 1.0 with no mill, and NEVER below 1.0 (see
## this file's header for why that floor is load-bearing).
##
## A second mill is worth nothing: a village only has so many trees within
## reach, and a multiplier that stacked would make timber free.
static func timber_multiplier_for(
	present_building_ids: Array, supply: Dictionary, demand: Dictionary
) -> float:
	if not present_building_ids.has(SAWMILL_BUILDING_ID):
		return 1.0
	var scale := VillageLabor.output_scale_for(SAWMILL_BUILDING_ID, supply, demand)
	return 1.0 + SAWMILL_TIMBER_BONUS * clampf(scale, 0.0, 1.0)
