extends RefCounted

## Procedural village placement (docs/concept/npc.md: "Similar to minecraft
## there should be procedural generated NPC populations; villages and so").
## Sparse and deterministic per chunk -- same "regenerates identically on
## revisit" philosophy as TreeRenderer/CreatureRenderer -- gated to habitable
## biomes, with a small fixed roster of NpcIdentity villagers and
## non-overlapping house anchor positions arranged around 3 shared landmarks
## every settlement always has (well/stall/gate), so an NpcPlanner schedule
## referencing any of those tags always resolves to a real place.
##
## `house_positions` are ANCHOR points, one per villager -- VillageRenderer
## is what turns each anchor into a real multi-tile HouseBlueprint structure
## (walls, floor, door, roof, actually stamped into the chunk), centred
## roughly on the anchor. This module only decides WHERE that anchor sits,
## not what gets built there.

const VillageFarm = preload("res://src/gameplay/village_farm.gd")
const SettlementFoodDemand = preload("res://src/emergence/settlement_food_demand.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")
const VillageLayout = preload("res://src/world/village_layout.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const VillageEstates = preload("res://src/emergence/village_estates.gd")
const VillageCart = preload("res://src/gameplay/village_cart.gd")
const VillageSawmill = preload("res://src/gameplay/village_sawmill.gd")

## The FOUNDING roster: how many villagers a settlement is founded with.
## Not a ceiling -- docs/concept/village_growth.md's own arrivals mechanism
## settles further households over time (EarthChunkManager.admit_household),
## and generate_settlement takes the settlement's real population so those
## newcomers are generated too. Villager `i` is keyed to index `i` whatever
## the population is, so growing a village never shifts who its founders
## are (test-pinned, test_settlement_generator.gd).
##
## Ten, asked for directly: *"please increase the village sizes from 5
## houses to 10 initial and then it should grow by itself; adding new
## houses new trades"*. The second half is a constraint on the first --
## VillageGrowth's ladder is spaced in founding rosters so that a village
## founded at this size still has trades left to grow into, rather than
## being founded already owing itself every rung (test-pinned,
## test_village_growth.gd).
const POPULATION := 10

## Which food trades exist, how many of them a village needs and which one
## its land feeds it with all live in SettlementFoodDemand -- this module only
## applies the answer to the roster.

## Roughly 1-in-this-many habitable chunks hosts a settlement -- sparse, so
## villages read as discoverable landmarks rather than carpeting the map.
const SETTLEMENT_CHANCE_DENOMINATOR := 30

## Villages need dry, walkable, open land -- never afloat, on a cliff
## face, or (docs/concept/building.md: "houses / buildings... not in the
## forest") standing in the forest itself, where the sheer density of real
## trees would leave a village perpetually fighting to find any footprint
## the NPCs haven't already had to fell first (see EarthChunkManager.
## is_buildable_terrain_at/VillageRenderer._find_dry_origin for the SAME
## rule applied per-tile to individual scattered trees in an otherwise
## habitable biome).
const _UNINHABITABLE_BIOMES := {"ocean": true, "mountain": true, "forest": true}

## Houses ring the village center at roughly this radius -- wide enough that
## each house's real footprint (see VillageRenderer._HOUSE_FOOTPRINT, 5x4
## tiles) sits apart as a settlement rather than a huddle of overlapping
## structures. Each house also gets a small seeded radius/angle jitter so the
## ring reads as grown, not compass-drawn.
const _HOUSE_RING_RADIUS_TILES := 9
const _HOUSE_RADIUS_JITTER_TILES := 1.5
const _HOUSE_ANGLE_JITTER := 0.22

## The 3 shared landmarks (well, stall, gate) are placed by VillageLayout.
## skeleton -- on the plaza and at the street's entrance -- see
## generate_settlement below.


## Deterministic per chunk_coord: whether this chunk hosts a settlement.
## dominant_biome gates habitability -- ocean/mountain chunks never do,
## regardless of the roll (see BiomeClassifier.dominant_biome for how a
## chunk's single dominant biome is derived).
func has_settlement_at(chunk_coord: Vector2i, dominant_biome: String) -> bool:
	if _UNINHABITABLE_BIOMES.has(dominant_biome):
		return false
	var roll := absi(hash("%d_%d_settlement" % [chunk_coord.x, chunk_coord.y])) % SETTLEMENT_CHANCE_DENOMINATOR
	return roll == 0


## Builds this chunk's settlement: POPULATION villagers (deterministic
## NpcIdentity per index), one house anchor position each arranged in a ring
## around the chunk's center, and the 3 shared landmark positions. Callers
## should only call this after confirming has_settlement_at.
## `population` defaults to the founding roster; a caller holding the
## settlement's REAL household count (VillageRenderer, off
## EarthChunkManager.household_count_for_settlement) passes that instead,
## so a village that has taken households in generates them too.
## `region` is what the village's own land is standing on -- anything
## exposing NpcProduction's three world accessors (the live world, or a
## SettlementGranary.SeededRegion). It decides which food trade the roster
## is staffed with; omitting it falls back to farming, so every caller that
## predates this keeps a roster it can still feed.
func generate_settlement(
	chunk_coord: Vector2i, chunk_origin_tiles: Vector2i, chunk_size: int, tile_size: int,
	population: int = POPULATION, is_dry := Callable(), region = null
) -> Dictionary:
	# The well, stall and gate stand where the village's own street plan
	# puts them -- on the plaza, at the street's entrance (see
	# VillageLayout.skeleton) -- so the props and the paving agree, rather
	# than at fixed offsets from the chunk centre that ignore the street.
	# `is_dry` is the square's own siting predicate (VillageLayout.
	# plaza_x0_for): a square whose designed centre is water slides along
	# the street, and the well/stall/gate must slide with it or the props
	# and the paving disagree. A caller with no world to ask omits it and
	# gets the designed centre, exactly as before.
	var skeleton := VillageLayout.skeleton(chunk_size, VillageLayout.seed_for(chunk_coord), is_dry)
	var landmarks := {}
	for landmark in skeleton["landmarks"]:
		var cell: Vector2i = chunk_origin_tiles + skeleton["landmarks"][landmark]
		landmarks[landmark] = Vector2((cell.x + 0.5) * tile_size, (cell.y + 0.5) * tile_size)
	# The fallback ring (a villager whose plot fits nowhere keeps it, see
	# VillageRenderer) is centred on the square's own well, so it still
	# reads as "around the village square".
	var center_pos: Vector2 = landmarks["well"]

	var house_positions: Array[Vector2] = []
	var npcs: Array[NpcIdentity] = []
	for i in maxi(population, 0):
		var seed_value := hash("%d_%d_villager_%d" % [chunk_coord.x, chunk_coord.y, i])
		npcs.append(NpcIdentity.new(seed_value))
		house_positions.append(_house_position(chunk_coord, center_pos, tile_size, i))

	# The FOUNDING roster is staffed exactly as it was founded -- its own
	# demand, then its carter, then its sawyer -- so a village that has grown
	# still has the founders it was founded with. Only then does the grown
	# village's larger demand conscript, and it takes NEWCOMERS first and
	# never the wagon or the saw (docs/concept/village_economy_balance.md
	# mechanism 6): a real field feeds two households, so a village of
	# fifteen asks for eight producers, and a single pass off the end of the
	# whole roster reached the founding carter and handed the wagon to
	# somebody else on every reload.
	_staff_food_producers(npcs, region, mini(npcs.size(), POPULATION))
	_staff_the_carter(npcs)
	_staff_the_sawyer(npcs)
	_staff_food_producers(npcs, region, npcs.size(), true)

	return {"house_positions": house_positions, "landmarks": landmarks, "npcs": npcs}


## Staffs this roster with as many food producers as the village's own
## DEMAND asks for, in the trade its own LAND feeds it with.
##
## Asked for directly: *"Make it driven by demand."* What this replaced was
## "if nobody in this roster farms, make the last one a farmer" -- exactly
## one food producer, whatever the village's size and whatever it was
## standing on. That rule came from a real report ("No Farmhouses":
## occupations are drawn uniformly from nine, so five villagers missed both
## farmer and herbalist in two of three founded villages) and it fixed that,
## but it could not grow with a village and it could not tell a lakeside
## from a meadow.
##
## Both halves are SettlementFoodDemand's, and neither could be written until
## the food model's two sides had been measured against each other -- see
## docs/concept/settlement_food_calibration.md, which is also where the
## honest gaps live.
##
## Conscription comes off the END of the roster and only takes villagers who
## are not already feeding the village, so it is deterministic per chunk and
## leaves the earlier founders exactly as they rolled.
##
## `count` is how much of the roster this pass sees -- the founding ten, or
## the whole grown village -- and `keep_the_wagon_and_the_saw` is the grown
## village's rule: a carter or a sawyer the founding conscripted is not
## re-conscripted into a field, because growth is additive and the wagon
## is not handed round.
static func _staff_food_producers(
	npcs: Array, region, count: int = -1, keep_the_wagon_and_the_saw: bool = false
) -> void:
	if npcs.is_empty():
		return
	var seen: int = npcs.size() if count < 0 else mini(count, npcs.size())
	if seen <= 0:
		return
	var needed := SettlementFoodDemand.producers_needed(seen)
	var have := 0
	for i in seen:
		if SettlementFoodDemand.FOOD_TRADES.has(npcs[i].occupation):
			have += 1
	if have >= needed:
		return
	var trade := SettlementFoodDemand.trade_for(region)
	var index: int = seen - 1
	while have < needed and index >= 0:
		var occupation: String = npcs[index].occupation
		var spared: bool = keep_the_wagon_and_the_saw and (
			VillageCart.walks_the_round(occupation) or VillageSawmill.works_timber(occupation)
		)
		if not SettlementFoodDemand.FOOD_TRADES.has(occupation) and not spared:
			npcs[index] = NpcIdentity.new(npcs[index].seed_value, trade)
			have += 1
		index -= 1


## Makes sure this village has somebody to cart, if nobody rolled it
## (docs/concept/village_warehouse.md, Mechanism 4).
##
## Reported live with the empty store in shot: *"the warehouse stays
## empty"*. Hauling is a trade now, and unlike the mill -- which only stands
## where there is timber -- a STORE stands in every village from founding.
## A village with a store and nobody to walk its round is a village whose
## producers keep their own output for ever.
##
## Measured before this existed (tools/probe_carter_rosters.gd, over the 75
## real grassland villages in rows 0-5): 7 of them, 9.3%, had nobody to cart
## at all. Exactly the shape of the "No Farmhouses" report that
## _staff_food_producers above answers, so this answers it the same way:
## ONE villager, taken off the END of the roster and only from somebody the
## village's food demand has not already claimed, so the founders are left
## exactly as they rolled and a village never goes hungry for its wagon.
##
## Deliberately after _staff_food_producers, not before: food outranks
## logistics when a small roster cannot staff both.
static func _staff_the_carter(npcs: Array) -> void:
	if npcs.is_empty():
		return
	# Scoped to the FOUNDING roster on both halves -- who is looked for and
	# who is taken. Asking the whole grown roster instead would let a
	# newcomer who happened to roll carter call off a conscription the
	# founding ten had already made, handing that founder their old trade
	# back on the village's next visit.
	var founders: int = mini(npcs.size(), POPULATION)
	for i in founders:
		if VillageCart.walks_the_round(npcs[i].occupation):
			return
	# Off the end of the FOUNDING roster, not the end of the current one: a
	# village that has grown must not hand the wagon to a newcomer and give
	# the old carter their rolled trade back. Growth is additive here, and
	# founders keep who they are (test_growing_never_changes_who_the_
	# founders_are pins exactly that).
	var index: int = founders - 1
	while index >= 0:
		if not SettlementFoodDemand.FOOD_TRADES.has(npcs[index].occupation):
			npcs[index] = NpcIdentity.new(npcs[index].seed_value, VillageCart.OCCUPATION)
			return
		index -= 1


## Makes sure this village has somebody to work timber, if nobody rolled it
## (docs/concept/village_timber.md, "Somebody in the village has the trade").
##
## Reported in play with the mill's own panel in shot: *"The sawmill also
## doesn't produce beams or plangs or logs"*. A mill with nobody whose trade
## is timber produces exactly nothing -- the very report this trade was added
## for, back when the occupations were nine, returning quietly when a tenth
## was added: a trade is rolled by index, so `carter` re-rolled every
## villager, and _staff_the_carter above takes one off the end of the roster
## who may well have been the only sawyer.
##
## Measured before this existed (tools/probe_trades_after_conscription.gd,
## the 75 real grassland villages in rows 0-5): 14 of them, 18.7%, had nobody
## to work a mill.
##
## Deliberately LAST of the three, and it will not take a food producer or
## the carter the two calls above just placed: food outranks logistics, and
## logistics outranks timber, when a small roster cannot staff all three.
##
## A sawyer in a village with no timber in reach is not wasted -- they keep
## the regional drip every villager without a worksite already lives on, the
## same honest fallback a farmer with no farmhouse has.
static func _staff_the_sawyer(npcs: Array) -> void:
	if npcs.is_empty():
		return
	var founders: int = mini(npcs.size(), POPULATION)
	for i in founders:
		if VillageSawmill.works_timber(npcs[i].occupation):
			return
	var index: int = founders - 1
	while index >= 0:
		var occupation: String = npcs[index].occupation
		if (
			not SettlementFoodDemand.FOOD_TRADES.has(occupation)
			and not VillageCart.walks_the_round(occupation)
		):
			npcs[index] = NpcIdentity.new(npcs[index].seed_value, VillageSawmill.OCCUPATION)
			return
		index -= 1


## A ring position with a small deterministic per-house radius/angle jitter
## (seeded per chunk+index) so the layout reads organic while staying exactly
## reproducible on revisit.
func _house_position(chunk_coord: Vector2i, center_pos: Vector2, tile_size: int, index: int) -> Vector2:
	# Deliberately still spaced by the FOUNDING roster, not the current
	# population: this is only the fallback anchor for a villager whose plot
	# fit nowhere, and re-spacing it as the village grows would silently move
	# every existing villager's fallback position every time one arrived.
	var base_angle := float(index) / float(POPULATION) * TAU
	var angle := base_angle + (_unit_float(chunk_coord, index, "angle") - 0.5) * 2.0 * _HOUSE_ANGLE_JITTER
	var radius_tiles := _HOUSE_RING_RADIUS_TILES + (_unit_float(chunk_coord, index, "radius") - 0.5) * 2.0 * _HOUSE_RADIUS_JITTER_TILES
	return center_pos + Vector2(cos(angle), sin(angle)) * radius_tiles * tile_size


func _unit_float(chunk_coord: Vector2i, index: int, salt: String) -> float:
	return float(absi(hash("%d_%d_house_%d_%s" % [chunk_coord.x, chunk_coord.y, index, salt])) % 10000) / 10000.0


## The house each villager of `npcs` would be given at `chunk_coord`, by
## the SAME per-index seed VillageRenderer stamps them with.
##
## Shared so that anything asking "would a village fit here" asks about the
## houses that would really be built -- the village finder asks exactly
## that before sending a player somewhere (EarthChunkManager.
## find_nearest_village), and a second copy of this rule would let it
## answer about different houses than the ones the renderer then places.
## The grandest house a FOUNDING household may raise: the one its estate
## lives in, and every household is founded at the bottom estate
## (VillageEstates.STARTING_ESTATE).
##
## Asked directly: *"The village should not produce Manors from the
## beginning only cottages and once all villagers needs are stable in the
## green they can upgrade to houses"*. Measured before fixing: the first
## grassland village on the map founded a manor and three houses on day one,
## because the choice read the villager's TRADE and never their standing.
##
## Read from the estate layer rather than named here, so the two cannot
## disagree about what a kossaet lives in (docs/concept/village_estates.md,
## mechanism 1). Rising out of it is that layer's own business -- a whole
## ration, a station held for a real season, and the charter building
## standing.
static func _founding_house_entitlement() -> String:
	return VillageEstates.house_id_for(VillageEstates.STARTING_ESTATE)


static func house_ids_for(chunk_coord: Vector2i, npcs: Array) -> Array:
	var ids: Array = []
	for i in npcs.size():
		var seed_value := hash("%d_%d_house_%d" % [chunk_coord.x, chunk_coord.y, i])
		ids.append(BuildingCatalog.choose_house_id(
			npcs[i].occupation, npcs[i].genome, seed_value, _founding_house_entitlement()
		))
	return ids
