extends RefCounted

## The pure rule set behind a village's own sawmill (see docs/concept/
## village_timber.md): whose trade it is, how far a lumberjack ranges for
## timber, and what the mill wants doing next.
##
## The sibling of VillageFarm, and deliberately the same shape -- this
## decides WHAT, LumberjackBehavior decides WHEN, and NpcMarker owns the
## world effect. The same three-part split the hunter and the farmer already
## use.
##
## Reported in play: "The sawmill also never produces any beams and doesn't
## even have a dedicated worker". Both halves of that were true: nothing
## worked the building, and no villager had the trade at all.
##
## Deliberately NOT a second production model. SagewerkProduction already
## turns logs into beams and planks, with costs and shaping times measured
## against real joinery (hewing a round log square wastes sapwood and is
## slow; riving boards off it is cheap and fast) and pinned by its own
## tests. Every number below is read from there rather than invented again.

const SagewerkProduction = preload("res://src/world/sagewerk_production.gd")
const VillageLayout = preload("res://src/world/village_layout.gd")

## The village's timber works -- the catalog's own building, never a second
## id. The same one VillageRenderer already raises at a village's timber.
const SAWMILL_BUILDING_ID := "sawmill"

## Whose trade it is. One occupation, because a sawmill is one person's job
## the way a farmhouse is a farmer's -- and unlike CROP_BY_OCCUPATION there
## is nothing to vary: a lumberjack fells trees, and there is only one kind
## of tree work.
const OCCUPATION := "lumberjack"

## What the mill wants doing right now.
const FELL := "fell"
const SHAPE := "shape"

## Logs it takes to square one beam. SagewerkProduction's own measured cost,
## re-exported rather than repeated -- written out as an int because that is
## what a stock count is, and pinned to the float it comes from by
## test_the_beam_threshold_is_the_sawmills_own_measured_cost.
const LOGS_PER_BEAM := 3

## How far a lumberjack ranges from the mill for timber, in tiles.
##
## Grounded, not chosen: a village sites its sawmill within
## VillageLayout.INDUSTRY_FOREST_REACH_TILES of real standing timber, so the
## sawyer must at minimum be able to reach the wood their own mill was
## placed beside. This is that reach with room to work outward as the near
## trees come down -- a village fells its own wood rather than stripping the
## map, which is what keeps a forest a place rather than a resource bar.
const TIMBER_REACH_TILES := 12


## Whether this occupation works timber at all. The same shape
## VillageFarm.crop_for uses for the field trades: an occupation that is not
## this one has no sawmill work, which is the honest answer for every
## villager who is not a lumberjack.
static func works_timber(occupation: String) -> bool:
	return occupation == OCCUPATION


## What the mill wants next, given how many logs it is holding.
##
## Short of a beam's worth the answer is still FELL: a sawyer who stood at
## the mill waiting for logs nobody was fetching would be a sawmill that
## stops the moment it runs down. Fetching is the other half of the trade,
## not an interruption to it.
static func next_action(log_stock: int) -> String:
	return SHAPE if log_stock >= LOGS_PER_BEAM else FELL


## Whether `at` is timber this mill's own sawyer may work -- within
## TIMBER_REACH_TILES of the mill, measured in real pixels so the caller
## never has to convert.
static func is_in_range(mill_position: Vector2, at: Vector2, tile_size: int) -> bool:
	return mill_position.distance_to(at) <= float(TIMBER_REACH_TILES) * float(tile_size)
