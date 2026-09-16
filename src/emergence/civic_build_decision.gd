extends RefCounted

## Whether a village raises its town hall right now (docs/concept/
## civic_construction.md "Meeting Hall"; building.md "City Hall over
## time"): the plaza's civic plot is reserved at founding
## (VillageLayout.skeleton), and the hall goes up the way every other
## settlement building does -- one ConstructionProject on the settlement
## ledger, its wood and stone drawn from the village's own market (which
## its spare hands stock over time, see SettlementGathering), its labour
## hours accrued by SettlementSpareCapacity -- never an instant stamp.
##
## Branches, in order:
## - already_standing: a real "city_hall" is present in the settlement
##   (present_structure_ids -- the catalog building's own anchor cell
##   answers the same scan a legacy placeable did). One seat per village.
## - too_small: fewer than CITY_HALL_MIN_HOUSEHOLDS households. A hamlet
##   of two has no need of a civic seat; three households is the smallest
##   village that reads as one (npc_role_consensus.md's "one building,
##   two roles" only means anything once there are hands to convene).
## - no_spare_capacity: everyone works a survival occupation -- the same
##   "a settlement at subsistence does not build" rule SettlementBuild
##   Decision applies, and it must never read as "nothing needed".
## - else SettlementConstruction.try_start: the READY start with its own
##   stock hysteresis (a plan waits, PLANNED, until every input is fully
##   in stock; already_progressing once started). Deliberately NOT
##   SettlementConstruction.advance: ConstructionPriority's producer walk
##   has nothing to say about a hall (nothing produces one), and its
##   shortfall branch would abandon a waiting civic plan in a lean season
##   -- a village keeps its plan and waits.
##
## The owner is the settlement itself (EntityRef.for_settlement) -- a
## commons, not any one household's property: HouseholdStore.grant_
## property is a no-op for an id that is not a household, so completing
## the project grants nobody the hall.
##
## Static-function module, the same explicit-dependencies-in shape
## SettlementConstruction/SettlementBuildDecision already use -- no stored
## state of its own; CITY_HALL_MIN_HOUSEHOLDS is test-pinned
## (test_civic_build_decision.gd), never an eyeballed comment.

const SettlementConstruction = preload("res://src/emergence/settlement_construction.gd")

const CITY_HALL_BUILDING_ID := "city_hall"
const CITY_HALL_MIN_HOUSEHOLDS := 3


## `project_store`: ConstructionProjectStore. `market`: VillageMarket.
## `origin`: the civic plot's LOCAL origin (EarthChunkManager._civic_plot_
## origin_for). `settlement_id`: EntityRef.for_settlement(chunk_coord) --
## the project's owner. `present_structure_ids`/`recipe_book`/
## `household_count`/`spare_capacity`: the settlement's own real state, the
## same values _apply_settlement_build_decision already derives.
static func decide_and_advance(
	project_store,
	market,
	chunk_coord: Vector2i,
	origin: Vector2i,
	settlement_id: String,
	present_structure_ids: Array,
	recipe_book,
	household_count: int,
	spare_capacity: int
) -> Dictionary:
	if present_structure_ids.has(CITY_HALL_BUILDING_ID):
		return {"action": "already_standing"}
	if household_count < CITY_HALL_MIN_HOUSEHOLDS:
		return {"action": "too_small"}
	if spare_capacity <= 0:
		return {"action": "no_spare_capacity"}
	return SettlementConstruction.try_start(
		project_store, market, chunk_coord, origin, CITY_HALL_BUILDING_ID, settlement_id, recipe_book
	)
