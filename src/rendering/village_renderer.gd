extends RefCounted

## Chunk-based spawn/despawn of a procedurally generated village (see
## SettlementGenerator, docs/concept/npc.md) -- real whole-BUILDING houses
## (docs/concept/building.md "Buildings are entities; interiors are
## scenes") laid out on a real road (VillageLayout) plus walking NpcMarker
## villagers, wearing the same hero-appearance engine the player uses
## (HeroAppearance/ProceduralCharacterSprite), keyed by occupation instead
## of class. Same "one call per chunk load, deterministic, returns spawned
## nodes for the caller to free" shape as TreeRenderer/CreatureRenderer/
## FishRenderer -- except houses themselves are chunk entities (see
## EarthChunkManager.place_building), not spawned nodes of their own, the
## same way they were chunk MODIFICATIONS (not spawned nodes) under the
## older piece model this replaces.

const SettlementGenerator = preload("res://src/world/settlement_generator.gd")
const VillageLayout = preload("res://src/world/village_layout.gd")
const VillageFarm = preload("res://src/gameplay/village_farm.gd")
const VillagePond = preload("res://src/gameplay/village_pond.gd")
const VillageSawmill = preload("res://src/gameplay/village_sawmill.gd")
const VillageCart = preload("res://src/gameplay/village_cart.gd")
const CartMarker = preload("res://src/rendering/cart_marker.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const NpcMarker = preload("res://src/rendering/npc_marker.gd")
const VillageMarket = preload("res://src/world/village_market.gd")
const ProceduralLandmarkSprite = preload("res://src/rendering/procedural_landmark_sprite.gd")
const ProceduralCharacterSprite = preload("res://src/rendering/procedural_character_sprite.gd")
const HeroAppearance = preload("res://src/rendering/hero_appearance.gd")
const CharacterViewScene = preload("res://scenes/character_view.tscn")
const CharacterView = preload("res://scenes/character_view.gd")
const DropShadow = preload("res://src/rendering/drop_shadow.gd")
const LandmarkSheet = preload("res://src/rendering/landmark_sheet.gd")
const IllustratedStructureSprite = preload("res://src/rendering/illustrated_structure_sprite.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")
const CivicBuildDecision = preload("res://src/emergence/civic_build_decision.gd")
const EntityRef = preload("res://src/emergence/entity_ref.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")

## Villagers are rendered with the player's own CharacterView (see
## _build_npc), so there are deliberately no villager-specific body size
## constants here -- the previous ones drifted out of sync with
## CharacterView and left NPCs legless.

var _settlement_generator := SettlementGenerator.new()
var _village_layout := VillageLayout.new()
var _landmark_sprite := ProceduralLandmarkSprite.new()
## Owns the sheet loading, black keying and per-sheet frame cache a
## prop's real art is read through (see LandmarkSheet.frame_image) --
## the same one buildings already draw their variants with.
var _structure_sprite := IllustratedStructureSprite.new()
var _character_sprite := ProceduralCharacterSprite.new()
var _appearance := HeroAppearance.new()
var _drop_shadow := DropShadow.new()

## How far south of a merchant's own doorstep their personal trading stand
## sits -- close enough to read as "this villager's own stand", clear of
## the door cell and the building's own footprint. Every building faces
## south in this pass (VillageLayout's own single street orientation), so
## "south of the doorstep" is simply further down the same road.
const _STAND_OFFSET_TILES := 2


## Each villager gets a personal workspot south of their own house, for
## occupations whose work tag isn't one of the settlement's 3 shared
## landmarks (see NpcMarker._resolve_location, and this file's own
## WORK_LOCATION_BY_OCCUPATION-driven prop spawning in spawn_village).
const _WORKSPOT_OFFSET_TILES := 4.0

## How far from its nominal spot a prop or landmark may be nudged to find
## real, dry ground (see _grounded_position).
##
## This exists because the offsets above used to be taken on faith: a
## workspot was four tiles south of the door and a merchant's stand two,
## with no terrain check of any kind. Reported from a real session with a
## screenshot -- a farmer's field, a forge and a stall floating ON a river,
## and a villager standing in it -- because a village street that runs
## along a riverbank puts that blind offset straight into the water. Five
## tiles is enough to step a prop back onto the bank without moving it so
## far it stops reading as that villager's own.
const _PROP_SEARCH_RADIUS_TILES := 5

## The one works every village raises at its own timber (docs/concept/
## village_growth.md mechanism 1). Placed at FOUNDING alongside the houses
## rather than raised over time: a village the player discovers has been
## standing for years, and its mill is part of the fabric it was founded
## with -- the hall and the ladder's later rungs are what it visibly grows
## during play (VillageGrowth, EarthChunkManager._apply_village_growth_
## decision). A village with no timber in reach honestly has none.
const INDUSTRY_BUILDING_ID := "sawmill"

## The villager who digs a pond (docs/concept/village_ponds.md). A fisher
## lives in an ordinary house, so their own house is what carries this and
## what the pond is sited against.
const FISHER_OCCUPATION := "fisher"

## Bright daylight -- spawn_village's own default for `sun_elevation_deg`
## when a caller doesn't pass one. Kept (even though this pass's own
## buildings don't yet vary their art by time of day -- see
## docs/concept/building.md's Status list) so every existing caller stays
## source-compatible; a later pass wiring the sheet's own ACTIVE row to
## night/occupancy will need it again.
const DEFAULT_SUN_ELEVATION_DEG := 45.0
const _NIGHT_ELEVATION_THRESHOLD_DEG := 0.0


## Whether it's dark enough for a settlement to read as "after dark" (see
## docs/concept/housing.md#night-lighting-ambient) -- the EXACT same
## elevation-at-or-below-zero boundary scenes/world.gd already uses to
## decide day/night for its own sky tint and Easter-egg sightings.
func is_night(sun_elevation_deg: float) -> bool:
	return sun_elevation_deg <= _NIGHT_ELEVATION_THRESHOLD_DEG


## Spawns this chunk's village (a real road, real whole-building houses,
## landmark props, and NPC markers, the last two as children of `parent`)
## if SettlementGenerator places one here, given the chunk's dominant_biome
## (see BiomeClassifier.dominant_biome -- ocean/mountain never qualify).
## Returns [] on a chunk with no settlement.
##
## `world` is the owning EarthChunkManager (duck-typed: place_building/
## build_at_global/is_buildable_terrain_at/modification_at_global/record_
## settlement_founded_if_new are the methods actually called), the same
## object every other renderer's spawn call already receives. `world ==
## null` (an isolated rendering test/tool that doesn't need real chunk
## mutation) skips placement entirely rather than crashing -- same
## fail-open shape as every other optional world hook in this codebase --
## and every villager falls back to their own old ring-anchor position
## (still computed by SettlementGenerator) as a `home_position`, so
## NpcMarker always has somewhere real to report even with no world.
func spawn_village(
	parent: Node2D,
	chunk_coord: Vector2i,
	chunk_origin_tiles: Vector2i,
	chunk_size: int,
	tile_size: int,
	dominant_biome: String,
	world = null,
	sun_elevation_deg: float = DEFAULT_SUN_ELEVATION_DEG
) -> Array[Node2D]:
	if not _settlement_generator.has_settlement_at(chunk_coord, dominant_biome):
		return []
	# One founding, one set of ground answers and one square (see
	# _buildable_memo and _skeleton_memo).
	_buildable_memo.clear()
	_skeleton_memo.clear()
	# The settlement's REAL population, not the founding roster: households
	# move in over time (docs/concept/village_growth.md mechanism 3), and a
	# newcomer nobody ever spawns is a household the player can never meet.
	# 0 (a settlement never recorded, or a world that cannot answer) falls
	# back to the founding roster rather than spawning an empty village --
	# the same duck-typed fail-open shape every other world hook here uses.
	var settlement := _settlement_generator.generate_settlement(
		chunk_coord, chunk_origin_tiles, chunk_size, tile_size,
		_population_for(chunk_coord, world),
		# The square's own siting (VillageLayout.plaza_x0_for) -- the well,
		# stall and gate must be derived from the SAME square the layout
		# and the paving below use, or a riverside village's props stand
		# where its square isn't.
		_is_buildable_local(chunk_coord, chunk_size, world) if world != null else Callable(),
		# What this village's own land feeds it with (SettlementDemand.
		# trade_for): the SEEDED region, so the roster is the same on every
		# visit and does not drift with the weather. A world that cannot
		# answer falls back to farming, like every other hook here.
		(
			world.seeded_region_for_chunk(chunk_coord)
			if world != null and world.has_method("seeded_region_for_chunk") else null
		)
	)

	# One VillageMarket per settlement, shared by every villager built below
	# (see NpcMarker.setup_economy) -- docs/concept/npc.md "Needs and the
	# local production economy": a producer's real surplus must be visible
	# to every consumer of the SAME village, not siloed per NPC. Freshly
	# created on every spawn_village call, same as the rest of this
	# settlement's state -- a chunk reload regenerates an empty market, the
	# same known "regenerates identically on revisit, no persistence"
	# simplification trees/creatures already accept (see docs/progress.md).
	var market := VillageMarket.new()

	var npcs: Array = settlement.npcs
	# One building id per villager, chosen from their own occupation +
	# personality (see BuildingCatalog.choose_house_id) -- VillageLayout
	# only decides WHERE each one actually lands, never WHICH.
	var building_ids: Array = SettlementGenerator.house_ids_for(chunk_coord, npcs)

	# door_positions[i]/stand_positions[i] default to the villager's own
	# old ring anchor -- overwritten below for every plot VillageLayout
	# actually placed (world != null and has place_building); a villager
	# whose building fit nowhere keeps this fallback, the same honest
	# "left without a house" outcome the old per-house siting search could
	# already reach.
	var door_positions: Array[Vector2] = settlement.house_positions.duplicate()
	var stand_positions: Array[Vector2] = settlement.house_positions.duplicate()
	# Every plot VillageLayout actually placed -- forwarded to
	# record_settlement_founded_if_new below so it can grant each villager's
	# real house ownership through the unified ConstructionProject id scheme
	# (docs/concept/building.md "One house id") instead of a synthetic one.
	# Stays empty when there is no world or no real placement happened.
	var plots: Array = []

	if world != null and world.has_method("place_building"):
		# NPCs/landmarks/market are never persisted (see this function's
		# own doc comment: "a chunk reload regenerates an empty market"),
		# so re-deriving them fresh on every load is correct BY DESIGN --
		# but buildings ARE persisted (Chunk.buildings), and VillageLayout
		# has no idea a settlement it's laying out fresh already has real
		# buildings sitting in chunk.modifications from an earlier load.
		# Without this check, is_occupied would see those cells as
		# occupied (correctly), VillageLayout would find NEW clear spots
		# for the SAME building_ids and place them there too, and every
		# reload would grow the village a second set of houses on top of
		# the first -- a real bug caught by a real reload probe, not
		# merely theorized: only re-run placement when no DWELLING is
		# persisted for this chunk yet; once one is, recover each
		# villager's OWN existing building instead (see the else branch
		# below).
		var existing_buildings: Array = (
			world.buildings_in_chunk(chunk_coord) if world.has_method("buildings_in_chunk") else []
		)
		# What decides the branch is a DWELLING, not a building. A save can
		# hold this village's mill and its paving and not one home --
		# measured in the real world (tools/probe_village_ghost.gd: chunks
		# (668,143) and (670,144) near lat 48.6 lon 12.7, five villagers
		# each, zero dwellings), written by a build from before the
		# founding gate below existed. There is nothing to recover there,
		# and the double-placement this branch guards against cannot
		# happen either: a village with no house cannot grow a second set
		# of them.
		var existing_dwellings := 0
		for record in existing_buildings:
			if BuildingCatalog.capacity_of(record.get("id", "")) > 0:
				existing_dwellings += 1
		if existing_dwellings == 0:
			# A site that cannot take a single house is not a village.
			# Reported in play ("Some villages have no houses") and
			# measured against the real world near lat 48.6 lon 12.7
			# (tools/probe_village_houses_live.gd): 3 of 6 real villages
			# stood with paved streets, a sawmill and five villagers, and
			# not one dwelling. One of those chunks is 100% water by the
			# same rule the water surface paints with -- a village founded
			# in the middle of a lake -- and the other two are 50% and 68%
			# water. BiomeClassifier knows nothing of hydrology, so a lake
			# still reads as "grassland" and SettlementGenerator settles
			# it; every house is then refused for the honest reason that
			# the ground really is water. Carrying on regardless is what
			# was wrong. Nothing is founded here at all now -- no streets,
			# no mill, no villagers, no settlement record -- rather than a
			# ghost village nobody can live in.
			if not _place_new_village(
				chunk_coord, chunk_size, tile_size, building_ids, npcs, world,
				plots, door_positions, stand_positions
			):
				return []
		else:
			_recover_existing_village(chunk_coord, chunk_size, tile_size, npcs, world, existing_buildings, plots, door_positions, stand_positions)

	# Tells the world this settlement exists, duck-typed exactly like
	# place_building above -- world == null or lacking the method is
	# skipped rather than crashing. EarthChunkManager owns deciding whether
	# this is genuinely a FIRST founding (a chunk reload must not re-record
	# one). `plots` (computed above, possibly empty) lets it grant each
	# actually-placed house's ownership through the unified id scheme.
	if world != null and world.has_method("record_settlement_founded_if_new"):
		world.record_settlement_founded_if_new(chunk_coord, npcs, plots)

	# Every shared landmark on real ground before anything reads it -- the
	# props below AND every villager's schedule resolve through this same
	# dictionary (NpcMarker.landmarks), so grounding it once fixes both. A
	# landmark with nowhere real to stand is dropped entirely rather than
	# left floating; _resolve_location already falls back to the villager's
	# own workspot for a tag it cannot find.
	settlement.landmarks = _grounded_landmarks(settlement.landmarks, tile_size, world)

	# The door of this settlement's store, for every villager built below
	# (docs/concept/village_warehouse.md mechanism 3). Read off the building
	# that really STANDS, not off the plan: a cramped site houses its people
	# and goes without one (pillar 1's caveat), and the reload branch never
	# runs the founding placement at all. null is the honest answer for a
	# village with no store, and a villager who gets it keeps stocking the
	# market outright.
	var warehouse_door = _warehouse_door(chunk_coord, chunk_size, tile_size, world)

	var spawned: Array[Node2D] = []
	# Every villager's own marker, by roster index -- the farm fields below
	# are handed out per villager, and only this loop knows which marker is
	# whose.
	var npc_markers: Array = []
	# The fields and their fences are worked out BEFORE any prop is placed,
	# because a personal workspot prop is grounded against what is already
	# built (see _grounded_position): fencing afterwards would drop rails
	# through a farmer's own field prop and a blacksmith's forge.
	# After every last cell of paving is down -- a farmhouse paves its own
	# doorstep as it is placed, and that is exactly what turns a long break
	# in a street row into a short one -- and before the first rail, so a
	# hole that becomes paving is a gate rather than somewhere a fence is
	# then laid across the road.
	_close_short_street_gaps(chunk_coord, chunk_size, world)
	var farm_fields := _fenced_farm_fields(
		chunk_coord, chunk_size, world, _landmark_cells(settlement.landmarks, tile_size)
	)
	# After the farms: a pond must not be dug through ground a farmhouse has
	# already claimed for its beds, and the beds are only known once
	# _fenced_farm_fields has worked them out.
	var fisher_ponds := _dig_fisher_ponds_if_missing(chunk_coord, chunk_size, world)
	# Where this village's market really is: cells OF its square, one per
	# merchant (see VillageLayout.market_stand_cells). Worked out before the
	# landmark loop because the square's own stall IS the first of them --
	# it is pitched with the rest below and only while somebody is behind
	# it, rather than standing empty on the paving for ever.
	var merchant_indices: Array[int] = []
	for i in npcs.size():
		if npcs[i].occupation == "merchant":
			merchant_indices.append(i)
	var market_stands := _market_stand_positions(
		chunk_coord, chunk_size, tile_size, world, merchant_indices.size()
	)
	# The square's canonical trading spot IS the first stand, not a cell
	# beside it: a villager who resolves the `stall` tag (and every merchant
	# past the ones the square had room for) must walk to somewhere a stand
	# really stands. Without this the tag keeps the planned cell, which
	# _grounded_landmarks may already have nudged off it.
	if not market_stands.is_empty():
		settlement.landmarks["stall"] = market_stands[0]
	for landmark_id in settlement.landmarks:
		if landmark_id == "stall":
			continue  # pitched with the market below, and only when tended
		var landmark := _build_landmark(landmark_id, settlement.landmarks[landmark_id], parent)
		if landmark != null:
			spawned.append(landmark)
	for i in npcs.size():
		var workspot = _grounded_position(
			door_positions[i] + Vector2(0, _WORKSPOT_OFFSET_TILES * tile_size), tile_size, world, false
		)
		var npc_marker := _build_npc(
			settlement, i, door_positions[i], workspot, tile_size, parent, world, market, warehouse_door
		)
		spawned.append(npc_marker)
		npc_markers.append(npc_marker)
		# A merchant trades at their OWN stand, on the village square (see
		# docs/concept/village_market_square.md). Reported live with a stand
		# in shot, pitched in long grass well off the paving: "the market
		# stands should only be put up when an NPC stands behind them to
		# sell goods ... also the stand should ... be placed on the plaza
		# anyways". Both halves were one bug -- a personal stand used to be
		# pitched two tiles south of that merchant's own front door, out in
		# the meadow, and nobody ever stood behind it because
		# NpcMarker._resolve_location sends every merchant to
		# landmarks["stall"], the square's single stall.
		#
		# A merchant with no stand (a square with less room than the village
		# has merchants) keeps trading at the square's own spot, which is
		# the same honest shortfall a village with more farmers than
		# farmhouse plots already accepts.
		var stand_slot := merchant_indices.find(i)
		if stand_slot >= 0 and stand_slot < market_stands.size():
			var stand_position: Vector2 = market_stands[stand_slot]
			var stand := _build_landmark("stall", stand_position, parent, true)
			if stand != null:
				spawned.append(stand)
			# A COPY, not the settlement's shared dictionary: overriding the
			# tag in place would send every villager in the village to this
			# one merchant's trestle.
			var own_landmarks: Dictionary = settlement.landmarks.duplicate()
			own_landmarks["stall"] = stand_position
			npc_marker.landmarks = own_landmarks
			npc_marker.market_stand = stand
		# Every OTHER occupation whose own work location isn't already one of
		# the settlement's 3 shared landmarks (merchant/stall and guard/gate
		# both already have something real there) gets a real prop of their
		# own at their personal workspot -- a farmer's field, a blacksmith's
		# forge, a fisher's dock, an herbalist's garden -- instead of an
		# invisible position they simply stood on empty grass at.
		# No dry ground for this villager's trade means no prop, rather than
		# a field on the river. Their workspot then falls back to their own
		# doorstep (see _build_npc), so they still have somewhere real to be.
		var work_tag: String = NpcIdentity.WORK_LOCATION_BY_OCCUPATION.get(npcs[i].occupation, "")
		# ...unless their workplace is a real BUILDING the village already
		# raises. A lumberjack works at the sawmill, and the sawmill is not a
		# prop: asking for one falls back to the well art, so every
		# lumberjack was standing a second, spurious well in the middle of
		# the village. The mill _place_industry_if_missing raised is where
		# they work.
		if (
			work_tag != "" and not settlement.landmarks.has(work_tag)
			and not BuildingCatalog.has_building(work_tag) and workspot != null
		):
			var prop := _build_landmark(work_tag, workspot, parent, true)
			if prop != null:
				spawned.append(prop)
	_hand_out_farm_fields(npcs, npc_markers, farm_fields, chunk_coord, chunk_size)
	_hand_out_fisher_ponds(npcs, npc_markers, fisher_ponds, chunk_coord, chunk_size)
	_hand_out_the_sawmill(npcs, npc_markers, chunk_coord, chunk_size, world)
	_hand_out_the_store_round(npcs, npc_markers, chunk_coord, chunk_size, world, parent, spawned)
	return spawned


## Tells every villager whose trade is hauling which store is theirs, whose
## shelves are on their round, and which wagon they pull
## (docs/concept/village_warehouse.md, Mechanism 4).
##
## The sawmill handout's own sibling, and deliberately the same shape: read
## what really STANDS off world.buildings_in_chunk rather than off the plan,
## because a cramped site houses its people and goes without a store
## (pillar 1's caveat) and a reloaded village never re-runs the founding
## placement at all. A village with no store has no carter's work in it, and
## its carters keep the ordinary schedule.
##
## The wagon goes into `spawned`, which is what the chunk frees when the
## player walks out -- a cart is not a node this renderer leaks behind. That
## is not hypothetical: a porter and a cart left alive on every load/unload
## cycle is the measured cause of the reported framerate decay.
func _hand_out_the_store_round(
	npcs: Array, npc_markers: Array, chunk_coord: Vector2i, chunk_size: int, world,
	parent: Node2D, spawned: Array[Node2D]
) -> void:
	if world == null or not world.has_method("buildings_in_chunk") or npc_markers.size() < npcs.size():
		return
	var store = null
	var producers: Array[Vector2i] = []
	for record in world.buildings_in_chunk(chunk_coord):
		var building_id: String = record.get("id", "")
		if building_id == VillageLayout.WAREHOUSE_BUILDING_ID:
			if store == null:
				store = record["origin_local"]
		elif BuildingCatalog.PRODUCTION_BUILDING_IDS.has(building_id):
			producers.append(record["origin_local"])
	if store == null:
		return
	# The store is also a real place on the village's own map, so a carter's
	# schedule resolves to it the way a sawyer's resolves to the mill.
	# Without this their work tag names somewhere that does not exist and
	# they fall back to a decorative workspot.
	var footprint := BuildingCatalog.footprint_of(VillageLayout.WAREHOUSE_BUILDING_ID)
	var store_centre := Vector2(
		(float((store as Vector2i).x + chunk_coord.x * chunk_size) + float(footprint.x) * 0.5) * TerrainRenderer.TILE_SIZE,
		(float((store as Vector2i).y + chunk_coord.y * chunk_size) + float(footprint.y) * 0.5) * TerrainRenderer.TILE_SIZE
	)
	var store_cell: Vector2i = chunk_coord * chunk_size + (store as Vector2i)
	var round_cells: Array[Vector2i] = []
	for producer_origin in producers:
		round_cells.append(chunk_coord * chunk_size + producer_origin)
	for i in npcs.size():
		npc_markers[i].landmarks[VillageCart.WORK_LOCATION] = store_centre
		if not VillageCart.walks_the_round(npcs[i].occupation):
			continue
		npc_markers[i].store_cell = store_cell
		npc_markers[i].producer_cells = round_cells.duplicate()
		# One wagon each, standing at the store where its carter starts: a
		# cart is a real thing on the map, and two carters sharing one would
		# have each of them emptying the other's load.
		var cart := CartMarker.new()
		cart.position = store_centre
		parent.add_child(cart)
		spawned.append(cart)
		npc_markers[i].cart = cart


## Tells every villager whose trade is timber which sawmill is theirs
## (docs/concept/village_timber.md). One mill per village, so unlike the
## farmhouses there is nothing to pair off -- every sawyer works the one the
## village raised.
##
## A village with no timber in reach raised no mill, and its sawyer honestly
## has no sawmill work; they keep the regional drip every villager without a
## worksite already lives on.
func _hand_out_the_sawmill(
	npcs: Array, npc_markers: Array, chunk_coord: Vector2i, chunk_size: int, world
) -> void:
	if world == null or not world.has_method("buildings_in_chunk") or npc_markers.size() < npcs.size():
		return
	var mill = null
	for record in world.buildings_in_chunk(chunk_coord):
		if record.get("id", "") == VillageSawmill.SAWMILL_BUILDING_ID:
			mill = record["origin_local"]
			break
	if mill == null:
		return
	# The mill is also a real place on the village's own map, so a sawyer's
	# schedule resolves to it like a merchant's resolves to the stall.
	# Without this their work tag names somewhere that does not exist and
	# they fall back to a decorative workspot.
	var footprint := BuildingCatalog.footprint_of(VillageSawmill.SAWMILL_BUILDING_ID)
	var mill_centre := Vector2(
		(float((mill as Vector2i).x + chunk_coord.x * chunk_size) + float(footprint.x) * 0.5) * TerrainRenderer.TILE_SIZE,
		(float((mill as Vector2i).y + chunk_coord.y * chunk_size) + float(footprint.y) * 0.5) * TerrainRenderer.TILE_SIZE
	)
	for i in npcs.size():
		npc_markers[i].landmarks["sawmill"] = mill_centre
		if VillageSawmill.works_timber(npcs[i].occupation):
			npc_markers[i].sawmill_cell = chunk_coord * chunk_size + (mill as Vector2i)


## First-ever placement for this settlement (see spawn_village's own
## existing_buildings gate) -- computes a fresh VillageLayout, places
## every plot's building, and lays roads. Mutates `plots`/`door_positions`/
## `stand_positions` in place (GDScript Arrays are reference types, so
## spawn_village's own locals update directly) rather than returning a
## tuple.
## Returns whether this really is a village: false when the layout could
## not fit a single house, which is spawn_village's own signal to found
## nothing here at all. Nothing is written in that case -- the streets and
## the mill below are reached only once at least one dwelling has a plot,
## because a paved square with a sawmill and no houses is exactly the
## reported bug.
func _place_new_village(
	chunk_coord: Vector2i, chunk_size: int, tile_size: int, building_ids: Array, npcs: Array, world,
	plots: Array, door_positions: Array, stand_positions: Array
) -> bool:
	var layout_seed := VillageLayout.seed_for(chunk_coord)
	var is_buildable := _is_buildable_local(chunk_coord, chunk_size, world)
	var is_occupied := _is_occupied_local(chunk_coord, chunk_size, world)
	# The works' ground is spoken for BEFORE a single house plot is
	# assigned -- docs/concept/village_growth.md pillar 1: the reservation
	# exists "so a sawmill never has to hunt for room after the fact", and
	# "reservations cost nothing until something is actually raised on
	# them". The square, the civic plot and the store are reserved in the
	# skeleton itself; the works cannot be, because where they go depends on
	# where the timber is, which a seeded layout cannot know.
	#
	# Measured when the founding roster grew from five to ten: a mill needs
	# clear ground within INDUSTRY_FOREST_REACH_TILES of real forest and
	# outside it, which on a chunk with a forest edge is a band a couple of
	# tiles deep. Ten houses reach it where five did not, and every village
	# with timber in reach silently stopped getting a mill at all.
	var industry := _industry_plot_for(chunk_coord, chunk_size, world, is_buildable, is_occupied)
	var result := _village_layout.layout(
		building_ids, chunk_size, layout_seed, is_buildable,
		_occupied_or_reserved(is_occupied, _reserved_cells(industry))
	)
	# EVERY villager, not merely one. Asked for directly: "They should only
	# settle where there's enough space and the square wins; houses should
	# just be moved further away connected by streets". The layout already
	# walks street after street looking for that room, so a roster it still
	# cannot house is a site that genuinely has none -- and founding there
	# is what left a riverside chunk with a market square and one house
	# (chunk (661,139) near lat 49.8 lon 10.6).
	if not VillageLayout.houses_everyone(result, building_ids):
		return false

	# Buildings BEFORE roads -- place_building's own occupancy check
	# refuses a plot whose doorstep cell is already non-empty in
	# chunk.modifications (see its own doc comment), and a plot's doorstep
	# IS one of VillageLayout's own road_cells. Stamping roads first would
	# write "trail" into every doorstep before place_building ever saw it,
	# so EVERY placement would refuse itself over its own future front
	# step -- a real bug this ordering had until caught by a real
	# end-to-end EarthChunkManager probe (test_village_renderer.gd's own
	# StubWorld never caught this: its build_at_global records road cells
	# into a separate dict from the one modification_at_global reads, so
	# the two never actually collided there the way they do for real).
	for plot in result["plots"]:
		plots.append(plot)
		var building_index: int = plot["building_index"]
		var building_seed := hash("%d_%d_house_%d" % [chunk_coord.x, chunk_coord.y, building_index])
		# The house remembers its villager (occupation + NpcIdentity seed --
		# see place_building): NPCs are regenerated on every load, only the
		# building persists, and the interior/resident logic needs to know
		# whose house this is.
		var resident = npcs[building_index]
		world.place_building(
			chunk_coord, plot["origin"], plot["building_id"], plot["facing"], building_seed, "",
			resident.occupation, resident.seed_value
		)
		var doorstep_global: Vector2i = chunk_coord * chunk_size + plot["doorstep"]
		var doorstep_position := Vector2(
			(doorstep_global.x + 0.5) * tile_size, (doorstep_global.y + 0.5) * tile_size
		)
		door_positions[building_index] = doorstep_position
		stand_positions[building_index] = doorstep_position + Vector2(0, _STAND_OFFSET_TILES * tile_size)

	# Streets are the Road tier (docs/concept/infrastructure.md): a LAID
	# surface with its own tile that never wears, blocks vegetation and
	# walks a little faster -- not the worn trail they were first drawn as
	# (older saves' trail streets are repaved on load, see EarthChunkManager.
	# _migrate_village_trails_to_roads).
	if world.has_method("build_at_global"):
		for local_cell in result["road_cells"]:
			var g: Vector2i = chunk_coord * chunk_size + local_cell
			world.build_at_global(g.x, g.y, TerrainRenderer.ROAD_TILE_ID)

	# The store BEFORE the works, and the order is load-bearing. The store
	# stands on a fixed reserved plot beside the square and cannot move; the
	# works is sited wherever there is timber and a clear road spur back to
	# the street, and that spur is searched for against what is already
	# standing. Placed the other way round, a spur laid first gets CUT: the
	# store's own placement lifts every road cell under its footprint (see
	# place_building_over_roads) and restores only its doorstep, so a mill
	# whose spur happened to run through the reserved plot was left with no
	# road home. Caught by test_the_real_sawmill_is_walkable_back_to_the_
	# street_on_road, which no stub-world test could see -- StubWorld's
	# build_at_global records road cells into a different dict from the one
	# modification_at_global reads, so the two never collide there.
	_place_warehouse_if_missing(chunk_coord, chunk_size, world)
	_place_industry_if_missing(chunk_coord, chunk_size, world)
	_place_civic_if_missing(chunk_coord, chunk_size, world)
	_place_farms_if_missing(chunk_coord, chunk_size, npcs, world)
	return true


## A reload: this settlement's homes are already persisted from an earlier
## load (spawn_village's own existing_dwellings gate). Matches
## each villager to their OWN existing building by the SAME deterministic
## per-index seed place_building was given the first time it was placed --
## no new persistence needed, since that seed already uniquely identifies
## "villager i's own house" and is already stored on the building's own
## record. A villager whose seed matches nothing (should not happen for a
## village this function itself placed, but a foreign/edited save is
## possible) simply keeps their fallback ring-anchor position, the same
## honest "left without a house" shape spawn_village's own doc comment
## already describes. Mutates in place, same convention as
## _place_new_village.
func _recover_existing_village(
	chunk_coord: Vector2i, chunk_size: int, tile_size: int, npcs: Array, world,
	existing_buildings: Array, plots: Array, door_positions: Array, stand_positions: Array
) -> void:
	_lay_plaza_if_missing(chunk_coord, chunk_size, world)
	# Every village keeps a store, including one founded before there was
	# such a thing to keep (docs/concept/village_warehouse.md pillar 1).
	# Without this an older save would reload forever without one, since
	# this branch never runs the founding placement at all -- the same
	# reason the hall is raised here too. Ahead of the works for the same
	# road-spur reason _place_new_village gives.
	_place_warehouse_if_missing(chunk_coord, chunk_size, world)
	_place_industry_if_missing(chunk_coord, chunk_size, world)
	_place_civic_if_missing(chunk_coord, chunk_size, world)
	_place_farms_if_missing(chunk_coord, chunk_size, npcs, world)
	for i in npcs.size():
		var expected_seed := hash("%d_%d_house_%d" % [chunk_coord.x, chunk_coord.y, i])
		# A NEWCOMER's house was raised by the growth ladder, not stamped at
		# founding, so it carries none of the founding per-index seeds. Ask
		# the world who owns what instead -- without this every household
		# that ever moved in would stand forever on its fallback ring
		# anchor, outside the house it actually owns.
		var owned_origin = (
			world.house_origin_for_villager(chunk_coord, npcs[i].seed_value)
			if world.has_method("house_origin_for_villager") else null
		)
		for record in existing_buildings:
			if record.get("seed", -1) != expected_seed and record.get("origin_local") != owned_origin:
				continue
			var building_id: String = record["id"]
			var origin_local: Vector2i = record["origin_local"]
			plots.append({"building_index": i, "origin": origin_local, "building_id": building_id})
			# A record persisted before the house remembered its villager
			# (see place_building's occupation/resident_seed) heals here: the
			# per-index seed match above already identifies exactly whose
			# house it is, so the missing fields are written back once and
			# an old save's houses read as lived-in from their next visit on.
			if record.get("resident_seed", 0) == 0 and world.has_method("set_building_resident"):
				world.set_building_resident(chunk_coord, origin_local, npcs[i].occupation, npcs[i].seed_value)
			var doorstep_global: Vector2i = chunk_coord * chunk_size + origin_local + BuildingCatalog.doorstep_of(building_id)
			var doorstep_position := Vector2(
				(doorstep_global.x + 0.5) * tile_size, (doorstep_global.y + 0.5) * tile_size
			)
			door_positions[i] = doorstep_position
			stand_positions[i] = doorstep_position + Vector2(0, _STAND_OFFSET_TILES * tile_size)
			break


## Where a VILLAGE may site: anything that is not water.
##
## A village fells the trees it needs -- docs/concept/building.md's own
## "the NPCs / Player must first fell all trees to make space for the
## building" -- and both real placement paths already do it for real
## (place_building and build_at_global call _clear_vegetation_on_cells and
## _block_ground_cover_on_cells on what they write), so wooded ground is
## ground a village clears, not ground it refuses.
##
## This used to ask is_buildable_ground_at, which refuses the forest BIOME
## outright. Measured on real terrain near 51.2N 13.6E: that cost 10 of 22
## villages (45%) their plaza, and with no plaza there is no civic plot and
## so no city hall -- forest was the blocker in every single failing case,
## water in none of them. Refusing a village its civic centre over trees it
## would have cleared in an afternoon is the wrong trade.
##
## Deliberately scoped to the village generator. The PLAYER's own build
## gate (is_buildable_terrain_at, which also refuses a tile with a tree
## still standing on it) is untouched: a player fells trees by hand and
## should still be told when one is in the way, while a village founding
## itself simply clears its site.
##
## Water is the rule that does not move, and a world that cannot answer
## any of these is treated as open ground -- the same duck-typed fail-open
## shape every other world hook in this file uses.
## Global cell -> whether a village may build on that GROUND, for the life of
## one spawn_village call. Cleared at the top of every call; never long-lived.
##
## This is a real cache, not a micro-optimisation. `is_water_at_global` is a
## hydrology probe, and a founding asks it about the same cells thousands of
## times over: the layout walks the streets, the store and the works and the
## hall each site themselves, every farmstead runs a whole-chunk search, and
## the fences ask again per cell. Measured on one real chunk load, the
## farmstead search alone ran for minutes (see _place_farms_if_missing).
##
## Occupancy and paving are deliberately NOT cached beside it: both really do
## change during a founding -- that is the entire point of placing buildings
## and stamping roads -- and a stale answer there would let two plots claim
## one cell. The ground itself does not move while a village is being
## founded, which is what makes THIS one exact.
var _buildable_memo: Dictionary = {}

## This village's own skeleton, computed once per founding rather than once
## per question.
##
## VillageLayout.skeleton is pure for a given chunk and ground, but it is not
## CHEAP: it scans columns looking for somewhere dry to put the square.
## _is_street_row's own comment used to say that deriving from it "costs
## nothing" -- measured, one real founding made 106,722 skeleton calls, and
## that one line was 21 of the 25 seconds the village took. _field_fits_at
## asks _is_street_row about every cell of every candidate field ring, and a
## farmstead pushed off the street searches the whole chunk for a ring.
##
## Safe for exactly the reason _buildable_memo is: the square is derived from
## ground, and ground does not move while a village is being founded.
var _skeleton_memo: Dictionary = {}


## The skeleton for this chunk, from the cache above.
func _bones(chunk_coord: Vector2i, chunk_size: int, world) -> Dictionary:
	var key := Vector3i(chunk_coord.x, chunk_coord.y, chunk_size)
	if not _skeleton_memo.has(key):
		_skeleton_memo[key] = VillageLayout.skeleton(
			chunk_size, VillageLayout.seed_for(chunk_coord),
			_is_buildable_local(chunk_coord, chunk_size, world)
		)
	return _skeleton_memo[key]


func _is_buildable_local(chunk_coord: Vector2i, chunk_size: int, world) -> Callable:
	var memo := _buildable_memo
	return func(cell: Vector2i) -> bool:
		var g: Vector2i = chunk_coord * chunk_size + cell
		if memo.has(g):
			return memo[g]
		var answer := true
		if world.has_method("is_water_at_global"):
			answer = not world.is_water_at_global(g.x, g.y)
		elif world.has_method("is_buildable_ground_at"):
			answer = world.is_buildable_ground_at(g.x, g.y)
		elif world.has_method("is_buildable_terrain_at"):
			answer = world.is_buildable_terrain_at(g.x, g.y)
		memo[g] = answer
		return answer


func _is_occupied_local(chunk_coord: Vector2i, chunk_size: int, world) -> Callable:
	return func(cell: Vector2i) -> bool:
		var g: Vector2i = chunk_coord * chunk_size + cell
		return world.modification_at_global(g.x, g.y) != "" if world.has_method("modification_at_global") else false


## Whether this cell is paving the village has ALREADY laid -- what lets a
## growth plot's tie-back cross a street it meets rather than reading that
## junction as blocked ground (VillageLayout._frontage_spur). A world that
## cannot answer reports nothing paved, which costs the tie-back reach and
## never invents a road that is not there.
func _is_paved_local(chunk_coord: Vector2i, chunk_size: int, world) -> Callable:
	return func(cell: Vector2i) -> bool:
		if not world.has_method("modification_at_global"):
			return false
		var g: Vector2i = chunk_coord * chunk_size + cell
		return world.modification_at_global(g.x, g.y) == TerrainRenderer.ROAD_TILE_ID


## The village's own works at its own timber, and the road spur that joins
## them to the street (VillageLayout.industry_plot). Idempotent by the one
## check that matters -- a real `sawmill` already standing anywhere in this
## chunk -- so a reload never raises a second one, and an OLDER village
## (its houses persisted before the mill existed, or founded when no timber
## stood in reach) gains one on its next visit, the same self-healing shape
## _lay_plaza_if_missing already has.
##
## Building BEFORE the spur, for exactly the reason _place_new_village
## paves its streets after its houses: place_building refuses a plot whose
## doorstep is already modified, and the doorstep IS the spur's first cell.
##
## No resident: nobody lives in a sawmill (BuildingCatalog.capacity_of ==
## 0), so the occupation/resident_seed a house record carries are left
## empty here rather than invented.
## Where this village's works would stand -- ONE call, asked both by the
## founding layout (which reserves the ground) and by the placement itself,
## so the plot a village keeps free and the plot it then builds on can never
## be two different answers.
func _industry_plot_for(
	chunk_coord: Vector2i, chunk_size: int, world, is_buildable: Callable, is_occupied: Callable
) -> Dictionary:
	return VillageLayout.industry_plot(
		INDUSTRY_BUILDING_ID, chunk_size, VillageLayout.seed_for(chunk_coord),
		is_buildable, _is_forest_local(chunk_coord, chunk_size, world), is_occupied,
		Callable(), _is_paved_local(chunk_coord, chunk_size, world)
	)


## Every LOCAL cell a sited plot needs kept clear: its footprint, its
## doorstep and the whole road spur that joins it back to the street. The
## spur as much as the building -- a mill whose path home was built over is
## a mill the village cannot walk to, which industry_plot itself refuses to
## site in the first place.
static func _reserved_cells(plot: Dictionary) -> Dictionary:
	var reserved: Dictionary = {}
	if plot.is_empty():
		return reserved
	for cell in BuildingCatalog.footprint_cells(plot["building_id"], plot["origin"]):
		reserved[cell] = true
	reserved[plot["doorstep"]] = true
	for cell in plot["road_spur"]:
		reserved[cell] = true
	return reserved


## `is_occupied`, widened by ground this village has already spoken for --
## the same seam VillageLayout.layout already takes, so a reservation needs
## no new parameter anywhere and reads to the layout exactly like something
## already standing there.
static func _occupied_or_reserved(is_occupied: Callable, reserved: Dictionary) -> Callable:
	if reserved.is_empty():
		return is_occupied
	return func(cell: Vector2i) -> bool:
		return reserved.has(cell) or bool(is_occupied.call(cell))


func _place_industry_if_missing(chunk_coord: Vector2i, chunk_size: int, world) -> void:
	if not world.has_method("place_building"):
		return
	if world.has_method("buildings_in_chunk"):
		for record in world.buildings_in_chunk(chunk_coord):
			if record.get("id", "") == INDUSTRY_BUILDING_ID:
				return

	var plot := _industry_plot_for(
		chunk_coord, chunk_size, world,
		_is_buildable_local(chunk_coord, chunk_size, world),
		_is_occupied_local(chunk_coord, chunk_size, world)
	)
	if plot.is_empty():
		return

	var placed: bool = world.place_building(
		chunk_coord, plot["origin"], INDUSTRY_BUILDING_ID, Vector2i(0, 1),
		hash("%d_%d_industry" % [chunk_coord.x, chunk_coord.y]), "", "", 0
	)
	if not placed or not world.has_method("build_at_global"):
		return
	for local_cell in plot["road_spur"]:
		var g: Vector2i = chunk_coord * chunk_size + local_cell
		world.build_at_global(g.x, g.y, TerrainRenderer.ROAD_TILE_ID)


## Whether `y` is one of this village's own street ROWS -- paved or not.
##
## The founding layout paves a further street only between its own
## doorsteps, so a street row has unpaved GAPS in it. Those gaps are still
## street: a village that sows or fences in one puts crops and rails in the
## middle of its own road, with paving either side (measured on real
## villages -- tools/probe_village_map.gd), and it made the field frames
## inconsistent, since a field under a paved stretch correctly got no north
## wall while the one beside it got a rail.
##
## Derived from the skeleton, so it needs nothing stored -- but it does NOT
## cost nothing, which this comment claimed for a long time and which cost a
## founding 21 seconds. It goes through _bones, which computes the skeleton
## once per founding; called directly it is a column scan per cell.
func _is_street_row(chunk_coord: Vector2i, chunk_size: int, world, y: int) -> bool:
	var street_y: int = _bones(chunk_coord, chunk_size, world)["street_y"]
	return y >= street_y and (y - street_y) % VillageLayout.STREET_PITCH_TILES == 0


## Paves over the short holes this village leaves in its own street rows
## (see VillageLayout.short_street_gap_cells). Asked for directly, with the
## broken stretch in shot: *"When there's only a free gap of 1-2 tiles
## between two street tiles it should close the gap between them"* -- the
## founding layout paves only between the doorsteps it actually joined, so
## every real village came out with a one-tile hole punched through its own
## street.
##
## Run AFTER every last cell of paving is down -- the works, the hall, and
## each farmhouse's own doorstep, which is laid as that farmhouse is placed
## and is exactly what turns a long break in a street row into a short one
## -- and BEFORE the first rail, so a field's frame is decided against the
## finished street: a hole that becomes paving is a gate, not somewhere to
## stand a fence across a road.
##
## Idempotent like everything else here: a cell already paved is no longer a
## gap, so a reload closes the same holes and builds nothing twice.
func _close_short_street_gaps(chunk_coord: Vector2i, chunk_size: int, world) -> void:
	if world == null or not world.has_method("build_at_global"):
		return
	var is_buildable := _is_buildable_local(chunk_coord, chunk_size, world)
	var is_occupied := _is_occupied_local(chunk_coord, chunk_size, world)
	var is_free := func(cell: Vector2i) -> bool:
		return is_buildable.call(cell) and not is_occupied.call(cell)
	var street_y: int = VillageLayout.skeleton(
		chunk_size, VillageLayout.seed_for(chunk_coord), is_buildable
	)["street_y"]
	for cell in VillageLayout.short_street_gap_cells(
		_is_paved_local(chunk_coord, chunk_size, world), is_free,
		chunk_size, street_y, VillageLayout.STREET_GAP_CLOSE_TILES
	):
		var g: Vector2i = chunk_coord * chunk_size + cell
		world.build_at_global(g.x, g.y, TerrainRenderer.ROAD_TILE_ID)


## Where this village's market stands stand, in world pixels -- `count` of
## them, on the square's own paved cells (see VillageLayout.
## market_stand_cells and docs/concept/village_market_square.md).
##
## Filtered against what is REALLY paved rather than against the plan: a
## village whose square never got laid (nowhere dry for one, see
## VillageLayout.plaza_x0_for) has no market to pitch, and a stand on bare
## ground is exactly the thing this replaced. That filter is also the whole
## of "clear the long grass around it": paving is a built surface
## (EarthChunkManager._is_built_surface), and every ground-cover sim in the
## chunk blocks a built surface, so a stand on the square's own stones has
## no tall grass, flowers, scrub or lichen under it or beside it -- with no
## second clearing mechanism of its own to keep in step.
##
## A world that cannot answer (an isolated rendering test with no paving at
## all) keeps every planned cell, the same duck-typed fail-open shape every
## other world hook in this file uses.
func _market_stand_positions(
	chunk_coord: Vector2i, chunk_size: int, tile_size: int, world, count: int
) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	# No world means no paving and so no square to pitch a market on -- and
	# _bones cannot even be asked, since the skeleton's own siting predicate
	# reads the ground. Same guard every other world-reading step here has.
	if count <= 0 or world == null:
		return positions
	var cells: Array = VillageLayout.market_stand_cells(_bones(chunk_coord, chunk_size, world), count)
	var can_ask: bool = world != null and world.has_method("modification_at_global")
	for cell in cells:
		var global_cell: Vector2i = chunk_coord * chunk_size + cell
		if can_ask and not TerrainRenderer.is_road_tile(
			world.modification_at_global(global_cell.x, global_cell.y)
		):
			continue
		positions.append(
			Vector2((global_cell.x + 0.5) * tile_size, (global_cell.y + 0.5) * tile_size)
		)
	return positions


## Every farmhouse's own field, worked out and FENCED (docs/concept/
## village_farms.md): `{origin -> the global cells that farmhouse works}`,
## in the same (y, x) order _farmhouse_origins returns.
##
## Called before any villager or prop is placed, because both are grounded
## against what is already built: a prop placed first would have rails
## dropped through it, and a villager's own field has to exist before they
## can be handed it.
## The GLOBAL cells the village's shared landmarks really stand on.
##
## A landmark is a NODE, not a persisted tile, so nothing that reads
## `modification_at_global` can see one -- and the farm fences are laid
## AFTER the landmarks are grounded. That is how a rail came to be driven
## straight through the well the moment it moved off the square's own
## paving (docs/concept/village_market_square.md).
func _landmark_cells(landmarks: Dictionary, tile_size: int) -> Dictionary:
	var cells: Dictionary = {}
	for landmark_id in landmarks:
		var at: Vector2 = landmarks[landmark_id]
		cells[Vector2i(floori(at.x / float(tile_size)), floori(at.y / float(tile_size)))] = true
	return cells


func _fenced_farm_fields(
	chunk_coord: Vector2i, chunk_size: int, world, reserved: Dictionary = {}
) -> Dictionary:
	if world == null:
		return {}
	var origins := _farmhouse_origins(chunk_coord, world)
	if origins.is_empty():
		return {}
	var is_buildable := _is_buildable_local(chunk_coord, chunk_size, world)
	var occupied_by_tile := _is_occupied_local(chunk_coord, chunk_size, world)
	# A shared landmark counts as occupied ground for the whole farm pass --
	# beds and rails alike. Neither a crop nor a fence belongs in the village
	# well.
	var is_occupied := func(cell: Vector2i) -> bool:
		if reserved.has(chunk_coord * chunk_size + cell):
			return true
		return occupied_by_tile.call(cell)
	var fields: Dictionary = {}
	for origin in origins:
		fields[origin] = _workable_field_of(
			origin, origins, chunk_coord, chunk_size, is_buildable, is_occupied, world
		)
	_fence_the_fields(chunk_coord, chunk_size, fields, is_buildable, is_occupied, world)
	_clear_rails_with_nothing_to_enclose(chunk_coord, chunk_size, fields, world)
	_clear_the_beds(fields, world)
	return fields


## Fells whatever is standing in the beds a farmstead has just claimed
## (docs/concept/village_farms.md, "A farmstead clears its own ground").
##
## Reported in play with the enclosure in shot: *"the Farmhouse should clear
## trees in its bed enclosure"*. A fence around six beds with an oak in the
## middle of them is not a field -- and the beds were the one real placement
## here that never felled what was in its way, because they are ground handed
## to a farmer rather than written tiles.
##
## Exactly the enclosed cells and no margin: a village fells the timber it
## needs, not the wood it is standing near. The fence ring itself is left to
## the rails, which clear their own cells as they are built.
##
## Idempotent -- a cleared cell has nothing left to clear -- so it runs on
## every visit and heals a village founded before this existed, the same
## self-healing shape _clear_rails_with_nothing_to_enclose above already has.
func _clear_the_beds(fields: Dictionary, world) -> void:
	if world == null or not world.has_method("clear_vegetation_at_global"):
		return
	var cells: Array = []
	for origin in fields:
		cells.append_array(fields[origin])
	if cells.is_empty():
		return
	world.clear_vegetation_at_global(cells)


## Rails that are not on any real frame, taken down.
##
## Reported live with the village in shot: *"There's a bed enclosure without
## a Farmhouse"*, and again after the first sweep landed: *"there are still
## fenced enclosures without a corresponding Farmhouse or Fisher"*. A field
## is only ever fenced around a farmhouse that really stands (see
## _fenced_farm_fields) -- but the rails are real persisted tiles, so a
## farmhouse that goes AFTERWARDS, razed or reclaimed for standing in water,
## leaves its whole frame behind for ever.
##
## Measured against MEMBERSHIP of a frame this visit really derived, not
## against distance to a surviving building. The first pass used distance
## because a farmhouse's field is re-derived on every visit against what is
## standing at the time -- including the rails the last visit laid -- so "is
## this rail in today's frame" looked like it might not be a stable question,
## and asking it unstably would have each visit pull up the last one's fence.
##
## It IS stable, measured across four real villages and the 113 rails between
## them (test_the_sweep_takes_no_rail_a_real_founding_laid): every rail a
## founding really lays sits on its own farmhouse's ring or its own pond's
## ring on the next visit too, and not one of them needed the reach slack the
## distance rule was giving away. What that slack DID keep standing is a
## frame left by a razed farmhouse that happened to lie near a surviving one
## -- which is exactly the report.
##
## A fisher's pond is fenced with the SAME rails (docs/concept/
## village_ponds.md: "a similar 3x2 enclosure"), so its own water's ring
## counts as a real frame exactly as a field's does -- without that the sweep
## would pull up every pond fence in the village.
##
## Reconciled on every visit rather than hooked to the removal itself: the
## same idempotent self-healing shape _lay_plaza_if_missing and
## _place_industry_if_missing already have, and it heals a save whose
## farmhouse went before this existed.
func _clear_rails_with_nothing_to_enclose(
	chunk_coord: Vector2i, chunk_size: int, fields: Dictionary, world
) -> void:
	if not world.has_method("modification_at_global") or not world.has_method("destroy_at_global"):
		return
	# Every cell a real frame may stand on this visit: each farmhouse's own
	# ring around its own beds.
	var framed: Dictionary = {}
	for origin in fields:
		var beds: Array[Vector2i] = []
		for cell in fields[origin]:
			beds.append((cell as Vector2i) - chunk_coord * chunk_size)
		if beds.is_empty():
			continue
		for rail in VillageFarm.fence_cells(beds, origin, VillageFarm.FARM_BUILDING_ID):
			framed[rail] = true

	var rails: Array = []
	var water: Array[Vector2i] = []
	for y in chunk_size:
		for x in chunk_size:
			var cell := Vector2i(x, y)
			var g: Vector2i = chunk_coord * chunk_size + cell
			var tile_id := String(world.modification_at_global(g.x, g.y))
			if VillagePond.is_pond_tile(tile_id):
				water.append(cell)
			elif VillageFarm.is_fence_tile(tile_id):
				rails.append(cell)
	# A pond's own ring is every cell touching its water, on the diagonal as
	# well as the orthogonal -- the same closed ring VillageFarm.fence_cells
	# draws around beds, read here off the water that is really there rather
	# than off a plan, because a pond that was only partly dug still has a
	# frame around what it got.
	for cell in water:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				framed[cell + Vector2i(dx, dy)] = true

	for cell in rails:
		if framed.has(cell):
			continue
		var g: Vector2i = chunk_coord * chunk_size + (cell as Vector2i)
		world.destroy_at_global(g.x, g.y)


## Hands every villager who farms the field their OWN farmhouse works
## (docs/concept/village_farms.md). Pairs them in roster order with the
## farmhouses in (y, x) order -- the order _farmhouse_origins already
## guarantees -- so the same villager gets the same field on every reload
## without anything being persisted, exactly the property the ownership rule
## itself has.
##
## A village with more farmers than farmhouses (nowhere left with room for
## another field) leaves the rest on the regional drip they always had,
## which is the honest outcome rather than two villagers tending one field.
func _hand_out_farm_fields(
	npcs: Array, npc_markers: Array, fields: Dictionary, chunk_coord: Vector2i, chunk_size: int
) -> void:
	if fields.is_empty() or npc_markers.size() < npcs.size():
		return
	var origins: Array = fields.keys()
	var next_farmhouse := 0
	for i in npcs.size():
		if VillageFarm.crop_for(npcs[i].occupation) == "":
			continue
		if next_farmhouse >= origins.size():
			return
		var origin: Vector2i = origins[next_farmhouse]
		npc_markers[i].field_cells = fields[origin]
		# WHICH farmhouse, not just which ground: a harvest fills the
		# farmhouse this villager works for, and the village gets it when
		# they carry it in (NpcMarker._store_harvest /
		# haul_farmhouse_stock_to_village). Global, like field_cells --
		# `fields` is keyed by the LOCAL origin _farmhouse_origins returns.
		npc_markers[i].stock_building_cell = chunk_coord * chunk_size + origin
		next_farmhouse += 1


## Digs every fisher's own pond, fenced like a farmhouse's beds (see
## docs/concept/village_ponds.md). Asked for directly: *"The Fisher should
## build a similar 3x2 enclosure but filled with water and a pond with river
## water physics and fish swimming in it which reproduce"*.
##
## Sited against the fisher's OWN house, which is the building that carries
## their occupation -- a fisher lives in an ordinary house, so there is no
## separate building to hang this on the way a farmhouse carries a field.
##
## Idempotent by the same shape everything else here uses: a cell that is
## already water reads as occupied, so `is_free` refuses it, no rectangle
## fits over a pond that is already there, and a reload digs nothing twice.
func _dig_fisher_ponds_if_missing(chunk_coord: Vector2i, chunk_size: int, world) -> Dictionary:
	var ponds: Dictionary = {}
	if world == null or not world.has_method("build_at_global"):
		return ponds
	if not world.has_method("buildings_in_chunk"):
		return ponds
	var is_buildable := _is_buildable_local(chunk_coord, chunk_size, world)
	var is_occupied := _is_occupied_local(chunk_coord, chunk_size, world)
	var is_free := func(cell: Vector2i) -> bool:
		if cell.x < 0 or cell.y < 0 or cell.x >= chunk_size or cell.y >= chunk_size:
			return false
		return is_buildable.call(cell) and not is_occupied.call(cell)
	for record in world.buildings_in_chunk(chunk_coord):
		if String(record.get("occupation", "")) != FISHER_OCCUPATION:
			continue
		var origin: Vector2i = record["origin_local"]
		var building_id: String = record.get("id", "")
		if _has_pond_already(chunk_coord, chunk_size, world, origin, building_id):
			ponds[origin] = _pond_water_near(chunk_coord, chunk_size, world, origin, building_id)
			continue
		var water: Array = VillagePond.pond_cells(origin, building_id, is_free)
		if water.is_empty():
			continue  # no room beside this house -- honestly, no pond
		ponds[origin] = water
		for cell in water:
			var g: Vector2i = chunk_coord * chunk_size + (cell as Vector2i)
			world.build_at_global(g.x, g.y, VillagePond.POND_TILE_ID)
		# Stocked as it is dug: empty water is a hole, and a pond's fish only
		# breed from fish that are already in it (VillagePond.step is
		# logistic, so nothing grows from nothing). A village stocks its own
		# pond, which is what a village actually does.
		if world.has_method("stock_pond_at"):
			var first: Vector2i = chunk_coord * chunk_size + (water[0] as Vector2i)
			world.stock_pond_at(first.x, first.y)
		# The frame, on the field's own rule and through the field's own
		# skips: another farm's crop, a building, paving (the gate), and
		# ground nothing may stand on.
		for rail in VillageFarm.fence_cells(water, origin, building_id):
			var cell: Vector2i = rail
			if not is_free.call(cell):
				continue
			var tile_id := VillageFarm.fence_tile_for(VillageFarm.fence_facing(cell, water))
			if tile_id == "":
				continue
			var g: Vector2i = chunk_coord * chunk_size + cell
			world.build_at_global(g.x, g.y, tile_id)
	return ponds


## The water already standing in this house's own reach, in the same local
## cells pond_cells would have returned -- what a RELOAD hands the fisher,
## since the pond was dug on an earlier visit and is not dug again.
func _pond_water_near(
	chunk_coord: Vector2i, chunk_size: int, world, origin: Vector2i, building_id: String
) -> Array:
	var water: Array = []
	if not world.has_method("modification_at_global"):
		return water
	for cell in VillageFarm.field_cells(origin, building_id):
		var local: Vector2i = cell
		if local.x < 0 or local.y < 0 or local.x >= chunk_size or local.y >= chunk_size:
			continue
		var g: Vector2i = chunk_coord * chunk_size + local
		if VillagePond.is_pond_tile(world.modification_at_global(g.x, g.y)):
			water.append(local)
	return water


## Hands every fisher the water they work and the building they fill -- the
## same pairing, in the same roster order, that _hand_out_farm_fields does
## for a farmer, and for the same reason: this is the only thing that knows
## whose pond is whose.
func _hand_out_fisher_ponds(
	npcs: Array, npc_markers: Array, ponds: Dictionary, chunk_coord: Vector2i, chunk_size: int
) -> void:
	if ponds.is_empty() or npc_markers.size() < npcs.size():
		return
	var origins: Array = ponds.keys()
	var next_pond := 0
	for i in npcs.size():
		if npcs[i].occupation != FISHER_OCCUPATION:
			continue
		if next_pond >= origins.size():
			return
		var origin: Vector2i = origins[next_pond]
		var water: Array = ponds[origin]
		next_pond += 1
		if water.is_empty():
			continue
		var global_water: Array[Vector2i] = []
		for cell in water:
			global_water.append(chunk_coord * chunk_size + (cell as Vector2i))
		npc_markers[i].pond_cells = global_water
		# Their own house is the building they fill: a fisher lives in an
		# ordinary one, so the pond's own origin IS their stock building.
		npc_markers[i].stock_building_cell = chunk_coord * chunk_size + origin


## Whether this house already has water in reach.
##
## "A pond cell is occupied, so no pond fits there again" is NOT enough on
## its own, and a reload proved it: the cells of the pond already dug are
## refused, another rectangle in the same reach still fits, and the fisher
## gets a SECOND pond every time the chunk loads. The question a reload has
## to ask is whether this house has a pond at all, not whether one
## particular rectangle is free.
func _has_pond_already(
	chunk_coord: Vector2i, chunk_size: int, world, origin: Vector2i, building_id: String
) -> bool:
	if not world.has_method("modification_at_global"):
		return false
	for cell in VillageFarm.field_cells(origin, building_id):
		var local: Vector2i = cell
		if local.x < 0 or local.y < 0 or local.x >= chunk_size or local.y >= chunk_size:
			continue
		var g: Vector2i = chunk_coord * chunk_size + local
		if VillagePond.is_pond_tile(world.modification_at_global(g.x, g.y)):
			return true
	return false


## Raises each farmhouse's real fence around the beds its villager works
## (docs/concept/village_farms.md, "The fence around the beds"; asked for
## directly: "the farmhouse should build a fence around the bed so no
## animals enter").
##
## Laid only AFTER every field has been worked out, and never on ANY
## farmhouse's bed: two farmsteads near each other share the ground between
## them, so one farm's fence line can be the other farm's crop, and fencing
## as we go would put rails through it.
##
## Cells the village has already built on are left exactly as they are.
## Where that cell is the village's own paving, that is the GATE -- the way
## the farmer walks in, and the reason a farmhouse takes street frontage at
## all. A fence laid across the road would wall the village off from its own
## farm.
##
## Idempotent by the same shape everything else here uses: a rail already
## standing reads as occupied and is skipped, so a reload re-derives the
## same ring and builds nothing twice.
func _fence_the_fields(
	chunk_coord: Vector2i, chunk_size: int, fields: Dictionary,
	is_buildable: Callable, is_occupied: Callable, world
) -> void:
	if not world.has_method("build_at_global") or fields.is_empty():
		return
	var beds: Dictionary = {}
	for origin in fields:
		for global_cell in fields[origin]:
			beds[(global_cell as Vector2i) - chunk_coord * chunk_size] = true
	for origin in fields:
		var local_beds: Array = []
		for global_cell in fields[origin]:
			local_beds.append((global_cell as Vector2i) - chunk_coord * chunk_size)
		for rail in VillageFarm.fence_cells(local_beds, origin, VillageFarm.FARM_BUILDING_ID):
			var cell: Vector2i = rail
			if cell.x < 0 or cell.y < 0 or cell.x >= chunk_size or cell.y >= chunk_size:
				continue
			if beds.has(cell):
				continue  # the neighbouring farm's crop, not this farm's fence line
			if not is_buildable.call(cell) or is_occupied.call(cell):
				continue  # water, a building, or paving -- the paving being the gate
			# Deliberately NOT skipped for standing on a street ROW, the way
			# a BED is (_workable_field_of). Reported with the bed circled:
			# "it's still not fully enclosing the bed" -- a field sits below
			# the house it belongs to, so one whole side of its frame lands
			# on the next street row, and measured on real villages
			# (tools/probe_village_map.gd) most of those cells carry no
			# paving at all: a 3-wide gap under a field with the frame
			# closed on every other side. An unpaved gap is not a gate, and
			# a rail along the edge of a road is a fence beside a road. The
			# gate is the PAVING, which is_occupied already leaves open
			# above. Sowing in a street row stays forbidden: a crop in the
			# roadway is the thing that rule was really about.
			# The rail's own tile id carries which side of the field it
			# closes, so the sheet's four orientation columns still draw
			# correctly on a reload that remembers nothing else about it.
			var tile_id := VillageFarm.fence_tile_for(VillageFarm.fence_facing(cell, local_beds))
			if tile_id == "":
				continue
			var g: Vector2i = chunk_coord * chunk_size + cell
			world.build_at_global(g.x, g.y, tile_id)


## Every farmhouse standing in this chunk, in (y, x) order -- a stable
## order the ownership rule and the pairing above can both rely on.
func _farmhouse_origins(chunk_coord: Vector2i, world) -> Array:
	if not world.has_method("buildings_in_chunk"):
		return []
	var origins: Array = []
	for record in world.buildings_in_chunk(chunk_coord):
		if record.get("id", "") == VillageFarm.FARM_BUILDING_ID:
			origins.append(record["origin_local"])
	origins.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y if a.y != b.y else a.x < b.x
	)
	return origins


## The GLOBAL tiles a farmhouse at `origin` really works: the compact
## rectangle VillageFarm.field_rect lays out (3x2 or 2x3 -- asked for
## directly, and where the yield table peaks), over ground that IT owns
## (another farmhouse may be nearer to some of it), inside this chunk, dry,
## and with nothing standing on it -- the village's own paving included,
## since a doorstep is a road.
##
## Empty for a farmhouse with no room for a whole rectangle anywhere in
## reach, which is the honest answer: a ragged handful of cells has a ragged
## border, and that is what read as broken fencing in play.
func _workable_field_of(
	origin: Vector2i, origins: Array, chunk_coord: Vector2i, chunk_size: int,
	is_buildable: Callable, is_occupied: Callable, world
) -> Array[Vector2i]:
	var renderer := self
	var is_free := func(cell: Vector2i) -> bool:
		if cell.x < 0 or cell.y < 0 or cell.x >= chunk_size or cell.y >= chunk_size:
			return false
		if VillageFarm.owner_of(cell, origins, VillageFarm.FARM_BUILDING_ID) != origin:
			return false  # the neighbouring farmstead's ground, not this one's
		if renderer._is_street_row(chunk_coord, chunk_size, world, cell.y):
			return false  # a village does not sow in its own road
		return is_buildable.call(cell) and not is_occupied.call(cell)
	var rect = VillageFarm.field_rect(origin, VillageFarm.FARM_BUILDING_ID, is_free)
	var worked: Array[Vector2i] = []
	if rect == null:
		return worked
	for y in range((rect as Rect2i).position.y, (rect as Rect2i).end.y):
		for x in range((rect as Rect2i).position.x, (rect as Rect2i).end.x):
			worked.append(chunk_coord * chunk_size + Vector2i(x, y))
	return worked


## One farmhouse per villager who actually farms (docs/concept/
## village_farms.md). A farmer and a herbalist in the same village get one
## each -- that is what "so you can build multiple farms" means, and it is
## why the field's ownership rule has to be per-farmhouse.
##
## Sited on the village's own street frontage like any other growth
## building, with ONE added condition: the ground around it must really
## have room for a whole field rectangle (see _field_fits_at). A farmhouse
## with nowhere to farm is a farmhouse that should not have been raised, so
## a rejected frontage simply keeps the walk going rather than settling for
## it.
##
## Idempotent on how many already stand, the same self-healing shape
## _place_industry_if_missing and _lay_plaza_if_missing already have: a
## reload never raises a second set, and an older village whose farmer
## never had a farmhouse gains one on its next visit.
##
## The doorstep is paved AFTER the building goes up, for exactly the reason
## _place_new_village places its houses before its roads: place_building
## refuses a plot whose doorstep is already modified.
func _place_farms_if_missing(chunk_coord: Vector2i, chunk_size: int, npcs: Array, world) -> void:
	if world == null or not world.has_method("place_building"):
		return
	var wanted := 0
	for npc in npcs:
		if VillageFarm.crop_for(npc.occupation) != "":
			wanted += 1
	if wanted == 0:
		return  # nobody here farms, so nothing here needs a farmhouse
	var standing := 0
	if world.has_method("buildings_in_chunk"):
		for record in world.buildings_in_chunk(chunk_coord):
			if record.get("id", "") == VillageFarm.FARM_BUILDING_ID:
				standing += 1

	var is_buildable := _is_buildable_local(chunk_coord, chunk_size, world)
	var is_occupied := _is_occupied_local(chunk_coord, chunk_size, world)
	var is_paved := _is_paved_local(chunk_coord, chunk_size, world)
	var renderer := self
	var accepts_origin := func(origin: Vector2i) -> bool:
		return renderer._field_fits_at(
			origin, chunk_coord, chunk_size, world, is_buildable, is_occupied
		)
	for index in range(standing, wanted):
		var plot: Dictionary = VillageLayout.next_street_plot(
			VillageFarm.FARM_BUILDING_ID, chunk_size, VillageLayout.seed_for(chunk_coord),
			is_buildable, is_occupied, is_buildable, accepts_origin, is_paved
		)
		if plot.is_empty():
			# No frontage left -- which on a village hemmed in by water is
			# the normal case, not the rare one. Measured on chunk
			# (661,139) near lat 49.8 lon 10.6, reported in play as "no
			# farmers": next_street_plot returns nothing at all there for a
			# 3x2 farmhouse, while SIXTY origins elsewhere in the same
			# chunk fit one, every one with a full field ring. A farmstead
			# does not need frontage the way a house does; it needs open
			# ground and a path home, which is what the sawmill's own
			# siting already gives.
			plot = VillageLayout.outskirt_plot(
				VillageFarm.FARM_BUILDING_ID, chunk_size, VillageLayout.seed_for(chunk_coord),
				is_buildable, is_occupied, accepts_origin, is_buildable
			)
		if plot.is_empty():
			return  # nowhere at all with room for a field -- honestly, no farm
		# Over the paving, not beside it: a street-frontage plot's own
		# doorstep IS a road cell by the time this runs (the streets were
		# laid at founding), and an ordinary place_building refuses a plot
		# whose doorstep is already modified -- the exact rule
		# _place_new_village orders its own houses-before-roads around.
		# _place_civic_if_missing already reaches for the same tool.
		var building_seed := hash("%d_%d_farmhouse_%d" % [chunk_coord.x, chunk_coord.y, index])
		var placed: bool = (
			world.place_building_over_roads(
				chunk_coord, plot["origin"], VillageFarm.FARM_BUILDING_ID, building_seed, ""
			)
			if world.has_method("place_building_over_roads")
			else world.place_building(
				chunk_coord, plot["origin"], VillageFarm.FARM_BUILDING_ID, plot["facing"],
				building_seed, "", "", 0
			)
		)
		if not placed:
			return
		if world.has_method("build_at_global"):
			# The doorstep, and the path back to the street when this
			# farmstead stands away from it (outskirt_plot's own spur --
			# a farm nobody can walk to is not part of the village).
			var paving: Array = [plot["doorstep"]]
			paving.append_array(plot.get("road_spur", []))
			for local_cell in paving:
				var g: Vector2i = chunk_coord * chunk_size + (local_cell as Vector2i)
				world.build_at_global(g.x, g.y, TerrainRenderer.ROAD_TILE_ID)


## Whether a farmhouse at `origin` would really have somewhere to sow: a
## whole 3x2 or 2x3 rectangle of its own, inside the chunk, not water, with
## nothing standing on it.
##
## This used to count LOOSE cells of the reachable ring against a minimum.
## Counting and fitting stopped being the same question when
## the field became a rectangle (docs/concept/village_farms.md): ground with
## four scattered free cells and no rectangle in it would raise a farmhouse
## whose villager then has nowhere at all to sow.
##
## Deliberately asks the SAME function that lays the field out
## (VillageFarm.field_rect), rather than a second rule that agrees with it
## today -- a siting gate that can drift from the thing it gates is a
## farmhouse with no field waiting to happen. Ownership is not consulted
## here: no other farmhouse stands yet at siting time, and the field this
## one finally works is re-derived once they all do.
func _field_fits_at(
	origin: Vector2i, chunk_coord: Vector2i, chunk_size: int, world,
	is_buildable: Callable, is_occupied: Callable
) -> bool:
	var renderer := self
	var is_free := func(cell: Vector2i) -> bool:
		if cell.x < 0 or cell.y < 0 or cell.x >= chunk_size or cell.y >= chunk_size:
			return false
		if renderer._is_street_row(chunk_coord, chunk_size, world, cell.y):
			return false
		return is_buildable.call(cell) and not is_occupied.call(cell)
	return VillageFarm.field_rect(origin, VillageFarm.FARM_BUILDING_ID, is_free) != null


## The village's civic seat, standing on the plaza's own reserved plot.
##
## Placed at FOUNDING, like the houses and the mill, and for the same
## reason: a village the player DISCOVERS has been standing for years, and
## its seat is part of the fabric it was founded with. The over-time build
## (CivicBuildDecision, EarthChunkManager._apply_civic_build_decision) is
## real and tested and stays exactly as it is -- it now covers a village
## that grows INTO the threshold during play, rather than being the only
## way a hall ever appears.
##
## That distinction mattered in practice: reported three times as simply
## missing. The over-time path needs roughly 20 wood and 10 stone gathered
## and then 45 labour-hours accrued, which is a couple of real hours beside
## the village and longer still for a poor one now that productivity scales
## the crew, so a player who walks into a village never saw a hall at all.
##
## Idempotent on the one check that matters -- a real hall already standing
## in this chunk -- so a reload never raises a second and an older village
## gains one on its next visit, the same self-healing shape the plaza and
## the mill already have. A village below the threshold, or one whose
## square was never paved, honestly gets none.
## Every village is founded with a store standing (docs/concept/
## village_warehouse.md): VillageLayout reserves a plot for it beside the
## square, and this raises it there.
##
## Deliberately has NO household threshold, unlike the hall below. A hamlet
## of two has no need of a civic seat, but it very much needs somewhere to
## put the harvest -- that is the whole of pillar 1, and it is why the
## warehouse left VillageGrowth's ladder rather than moving down it.
##
## "If missing" for the same reason the hall's own placement is: this runs
## on every load, not only at founding, so it must be the thing that decides
## a store already stands rather than raising a second one beside the first.
##
## Uses place_building_over_roads, like the hall and NOT like the sawmill.
## The reason is the doorstep. This runs after the streets are stamped (see
## _place_new_village's own "Buildings BEFORE roads" comment), and this
## plot's door opens straight onto the main street -- so by the time it runs,
## its own doorstep is already paved, and plain place_building refuses a plot
## whose doorstep cell is non-empty. It would refuse itself over its own
## front step, every time. The sawmill escapes this only because
## industry_plot sites it away from the street and lays its own spur
## afterwards.
##
## Unlike the hall, this does NOT first require every footprint cell to be
## road: the hall stands ON the paved square, while this stands on ordinary
## ground beside it. Only the doorstep is shared with the street.
func _place_warehouse_if_missing(chunk_coord: Vector2i, chunk_size: int, world) -> void:
	if not world.has_method("place_building_over_roads"):
		return
	var building_id := VillageLayout.WAREHOUSE_BUILDING_ID
	var standing: Array = world.buildings_in_chunk(chunk_coord) if world.has_method("buildings_in_chunk") else []
	for record in standing:
		if record.get("id", "") == building_id:
			return

	var plot: Dictionary = VillageLayout.skeleton(
		chunk_size, VillageLayout.seed_for(chunk_coord),
		_is_buildable_local(chunk_coord, chunk_size, world)
	)["warehouse_plot"]
	# A village whose square could not be sited has no plot beside it
	# either -- honest, the same way no plaza means no hall.
	if plot.is_empty():
		return

	world.place_building_over_roads(
		chunk_coord, plot["origin"], building_id,
		hash("%d_%d_warehouse" % [chunk_coord.x, chunk_coord.y]), ""
	)


## Where this settlement's store opens onto the street, in world pixels, or
## null when no store stands here.
##
## Read off world.buildings_in_chunk rather than off VillageLayout, because
## the plan and the ground disagree on purpose: the layout reserves a plot
## only when the site can spare it, the placement can still be refused, and
## a village loaded from a save never re-runs either. What a villager walks
## to has to be a building that is really there.
func _warehouse_door(chunk_coord: Vector2i, chunk_size: int, tile_size: int, world):
	if world == null or not world.has_method("buildings_in_chunk"):
		return null
	var building_id := VillageLayout.WAREHOUSE_BUILDING_ID
	for record in world.buildings_in_chunk(chunk_coord):
		if record.get("id", "") != building_id:
			continue
		var door_global: Vector2i = (
			chunk_coord * chunk_size + record["origin_local"]
			+ BuildingCatalog.doorstep_of(building_id)
		)
		return Vector2((door_global.x + 0.5) * tile_size, (door_global.y + 0.5) * tile_size)
	return null


func _place_civic_if_missing(chunk_coord: Vector2i, chunk_size: int, world) -> void:
	if not world.has_method("place_building_over_roads"):
		return
	var building_id := CivicBuildDecision.CITY_HALL_BUILDING_ID
	var standing: Array = world.buildings_in_chunk(chunk_coord) if world.has_method("buildings_in_chunk") else []
	var houses := 0
	for record in standing:
		if record.get("id", "") == building_id:
			return
		if BuildingCatalog.capacity_of(record.get("id", "")) > 0:
			houses += 1
	if houses < CivicBuildDecision.CITY_HALL_MIN_HOUSEHOLDS:
		return  # a hamlet of two has no need of a civic seat

	# The plot is the paved square itself, so every one of its cells must
	# really BE road -- a village whose centre was water or forest never
	# laid a square, and has nowhere to put a seat.
	var plot: Dictionary = VillageLayout.skeleton(
		chunk_size, VillageLayout.seed_for(chunk_coord),
		_is_buildable_local(chunk_coord, chunk_size, world)
	)["civic_plot"]
	var origin: Vector2i = plot["origin"]
	if not world.has_method("modification_at_global"):
		return
	for local in BuildingCatalog.footprint_cells(building_id, origin) + [plot["doorstep"]]:
		var g: Vector2i = chunk_coord * chunk_size + local
		if not TerrainRenderer.is_road_tile(world.modification_at_global(g.x, g.y)):
			return

	world.place_building_over_roads(
		chunk_coord, origin, building_id, hash("%d_%d_city_hall" % [chunk_coord.x, chunk_coord.y]),
		EntityRef.for_settlement(chunk_coord)
	)


## Whether a chunk-local cell is real forest -- the third predicate
## VillageLayout.industry_plot reads, alongside the buildable/occupied pair
## above. Duck-typed like every other world call here: a world that cannot
## answer reports no forest, so an isolated rendering test simply gets no
## mill rather than a crash.
func _is_forest_local(chunk_coord: Vector2i, chunk_size: int, world) -> Callable:
	return func(cell: Vector2i) -> bool:
		if not world.has_method("biome_at_global"):
			return false
		var g: Vector2i = chunk_coord * chunk_size + cell
		return world.biome_at_global(g.x, g.y) == FOREST_BIOME


## How many villagers actually live here: the settlement's own real
## household count (EarthChunkManager.household_count_for_settlement, read
## back out of the persisted event graph), falling back to
## SettlementGenerator.POPULATION when there is no world, no such method,
## or nothing recorded yet.
func _population_for(chunk_coord: Vector2i, world) -> int:
	if world == null or not world.has_method("household_count_for_settlement"):
		return SettlementGenerator.POPULATION
	var count: int = world.household_count_for_settlement(EntityRef.for_settlement(chunk_coord))
	return count if count > 0 else SettlementGenerator.POPULATION


## The one biome string a sawmill's timber comes from -- SettlementGenerator
## already treats exactly this string as the forest (its own
## _UNINHABITABLE_BIOMES), so there is one spelling of it, not two.
const FOREST_BIOME := "forest"


## An older save's village (buildings persisted, laid out before the plaza
## existed) catches up on reload: the plaza is re-derived from
## VillageLayout.skeleton -- nothing persisted -- and paved where the whole
## square is clear (buildable, and either empty or already road). A square
## with a building standing on it (the old layout put houses right where
## the plaza now goes) stays unpaved rather than paving through a house,
## the same honest "no plaza where the square isn't clear" rule the fresh
## layout itself applies. Idempotent: a village whose civic doorstep is
## already road has nothing to do.
func _lay_plaza_if_missing(chunk_coord: Vector2i, chunk_size: int, world) -> void:
	if not (world.has_method("modification_at_global") and world.has_method("build_at_global")):
		return
	var is_buildable := _is_buildable_local(chunk_coord, chunk_size, world)
	var skeleton := VillageLayout.skeleton(
		chunk_size, VillageLayout.seed_for(chunk_coord), is_buildable
	)
	var doorstep: Vector2i = chunk_coord * chunk_size + skeleton["civic_plot"]["doorstep"]
	if TerrainRenderer.is_road_tile(world.modification_at_global(doorstep.x, doorstep.y)):
		return
	var plaza: Rect2i = skeleton["plaza"]
	var cells: Array = []
	for y in range(plaza.position.y, plaza.end.y):
		for x in range(plaza.position.x, plaza.end.x):
			var cell := Vector2i(x, y)
			var g: Vector2i = chunk_coord * chunk_size + cell
			var existing: String = world.modification_at_global(g.x, g.y)
			if not is_buildable.call(cell) or (existing != "" and not TerrainRenderer.is_road_tile(existing)):
				return
			cells.append(g)
	for g in cells:
		world.build_at_global(g.x, g.y, TerrainRenderer.ROAD_TILE_ID)


## Every landmark moved onto real ground, dropping any with nowhere to
## stand. Landmarks may sit on their own PAVING (the well and the stall are
## on the plaza, the gate is on the street), so a road cell is a legal
## place for one -- unlike a workspot prop, which must never stand on the
## road it fronts.
func _grounded_landmarks(landmarks: Dictionary, tile_size: int, world) -> Dictionary:
	var grounded := {}
	for landmark_id in landmarks:
		var position = _grounded_position(landmarks[landmark_id], tile_size, world, true)
		if position != null:
			grounded[landmark_id] = position
	return grounded


## The nearest real, DRY, in-bounds cell to `nominal`, searched outward
## ring by ring up to _PROP_SEARCH_RADIUS_TILES; null when nothing within
## reach works. `allow_road` lets a village-square landmark stand on its
## own paving while keeping a workspot prop off the street and off houses.
##
## A world that cannot answer (an isolated rendering test, no world at all)
## keeps the nominal position -- the same duck-typed fail-open shape every
## other world hook in this file uses, so nothing that worked without a
## world starts returning null.
func _grounded_position(nominal: Vector2, tile_size: int, world, allow_road: bool):
	if world == null or not world.has_method("modification_at_global"):
		return nominal
	var centre := Vector2i(floori(nominal.x / tile_size), floori(nominal.y / tile_size))
	# A prop is somewhere a villager's own schedule sends them, so the
	# ground it stands on has to touch the village's paving. Reported in
	# play: "all procedural stands, wells, beds etc ... are also badly
	# placed" -- open grass five tiles behind a house is real, dry and
	# carries nothing built, so the search below used to stop there and
	# leave a farmer's field or a merchant's own stand sitting in a meadow
	# with no path to it.
	var beside_the_street: Variant = _nearest_prop_cell(centre, tile_size, world, allow_road, true)
	if beside_the_street != null:
		return beside_the_street
	# Nothing within reach touches a street -- keep the prop on real ground
	# rather than losing it, the same fail-open shape the rest of this file
	# uses. A village with no paving at all (an isolated rendering test)
	# lands here every time.
	return _nearest_prop_cell(centre, tile_size, world, allow_road, false)


## The nearest cell to `centre` that a prop may stand on, searched outward
## ring by ring; null when nothing within _PROP_SEARCH_RADIUS_TILES works.
## `require_street_access` additionally demands the cell touch a road.
func _nearest_prop_cell(
	centre: Vector2i, tile_size: int, world, allow_road: bool, require_street_access: bool
):
	for radius in range(0, _PROP_SEARCH_RADIUS_TILES + 1):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue  # only this ring; inner ones were already tried
				var cell := centre + Vector2i(dx, dy)
				if not _prop_cell_is_clear(cell, world, allow_road):
					continue
				if require_street_access and not _touches_road(cell, world):
					continue
				return Vector2((cell.x + 0.5) * tile_size, (cell.y + 0.5) * tile_size)
	return null


## Whether this cell is on the paving or directly beside it -- close enough
## that a villager walking the street can step onto the prop. Four-connected
## like everything else that walks here; a diagonal touch is a corner, not a
## way through.
func _touches_road(cell: Vector2i, world) -> bool:
	for step in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var neighbour: Vector2i = cell + step
		if TerrainRenderer.is_road_tile(world.modification_at_global(neighbour.x, neighbour.y)):
			return true
	return false


## Real buildable ground (no water, no forest -- the SAME is_buildable_
## ground_at rule the village's own plots obey) carrying nothing built,
## or a road when `allow_road`.
func _prop_cell_is_clear(cell: Vector2i, world, allow_road: bool) -> bool:
	if world.has_method("is_buildable_ground_at"):
		if not world.is_buildable_ground_at(cell.x, cell.y):
			return false
	elif world.has_method("is_buildable_terrain_at") and not world.is_buildable_terrain_at(cell.x, cell.y):
		return false
	var existing: String = world.modification_at_global(cell.x, cell.y)
	if existing == "":
		return true
	return allow_road and TerrainRenderer.is_road_tile(existing)


## The settlement's shared well/stall/gate, a merchant's personal trading
## stand, and a farmer/blacksmith/fisher/herbalist's own workspot prop --
## real, visible props NPC schedules walk to. Tagged with its own
## `landmark_id` as node metadata so a caller (chiefly tests, since several
## distinct landmark kinds can now exist side by side in the same spawned
## list) can tell exactly which prop a given node is without resorting to
## comparing raw positions.
## `personal` marks a prop belonging to ONE villager -- a merchant's own
## stand, a farmer's own field -- as opposed to one of the settlement's
## three shared landmarks. The distinction is not cosmetic: a shared
## landmark stands on the village's own paving by design, while a personal
## prop must never stand on the road it fronts, and a merchant's personal
## stand carries the same `stall` id as the square's own, so the id alone
## cannot tell them apart.
## Which village props you cannot walk through.
##
## Reported live: *"The well doesn't have a hitbox.. it should block
## walking"*. Every landmark was a bare Sprite2D with a shadow and nothing
## else, so the player and every villager walked straight through the
## stonework.
##
## Stated as a rule rather than left to whatever the renderer happens to do,
## and deliberately short: a well is a waist-high ring of stone and you
## cannot step into it. A gate is an OPENING in a wall -- a village whose own
## gate blocked its street would be walled in by its entrance -- and a stall
## is a trestle you step up to, not a wall across the square. An unknown prop
## is not solid by accident.
const _SOLID_LANDMARK_IDS := {"well": true}


static func landmark_is_solid(landmark_id: String) -> bool:
	return _SOLID_LANDMARK_IDS.has(landmark_id)


## How much of a solid prop's own drawn size really stops you. Under 1 so a
## body follows the stonework rather than the whole sprite's bounding box,
## which includes the flowers and the roof overhang a shoulder passes under.
const _SOLID_LANDMARK_FOOTPRINT_FRACTION := 0.7

## The ground floor's own collision layer -- mirrors EarthChunkManager.
## GROUND_FLOOR_COLLISION_LAYER's own VALUE (1), restated here rather than
## imported: EarthChunkManager already preloads this renderer, so the
## reverse import would be circular. The same "restate + cross-check" choice
## AntColony.SECONDS_PER_SIMULATED_DAY's own doc comment makes, and
## cross-checked by test_village_renderer.gd so the two cannot drift.
const GROUND_FLOOR_COLLISION_LAYER := 1


func _build_landmark(landmark_id: String, position: Vector2, parent: Node2D, personal: bool = false) -> Sprite2D:
	var texture := _landmark_texture(landmark_id, position)
	if texture == null:
		return null  # no art for this prop: nothing is drawn (see _landmark_texture)
	var landmark := Sprite2D.new()
	landmark.texture = texture
	landmark.set_meta("landmark_id", landmark_id)
	landmark.set_meta("personal", personal)
	# Art is authored DETAIL_MULTIPLIER times oversized for pixel detail;
	# scaling it back keeps the world footprint unchanged (see
	# docs/concept/art_resolution.md).
	landmark.scale = Vector2.ONE * ArtResolution.SPRITE_SCALE
	landmark.position = position
	# Anchored at its FOOT, not its middle (docs/concept/
	# village_market_square.md). A Sprite2D is centre-anchored, so half a
	# prop's height hung SOUTH of the cell it was placed on -- and the
	# stall's cell is the plaza's southernmost row, so its awning landed on
	# the row where the cottages front the street: "the stand ... is placed
	# ontop of a house". The same rule CartMarker already follows, and the
	# one _solid_body_for below already states for the collision box.
	landmark.offset = Vector2(0, -float(landmark.texture.get_height()) * 0.5)
	var size: Vector2i = ProceduralLandmarkSprite.SIZES.get(landmark_id, Vector2i(20, 20))
	# The shadow sits at the prop's own foot, which is now the sprite's
	# origin rather than half a height below it.
	landmark.add_child(_drop_shadow.make_shadow(int(size.x * 0.8), 0.0))
	if landmark_is_solid(landmark_id):
		landmark.add_child(_solid_body_for(size))
	parent.add_child(landmark)
	return landmark


## The body that stops you walking into a solid prop. A child of the prop
## itself, so it moves and is freed with it -- the prop IS the thing in the
## way, and a separately-tracked body would be one more thing to keep in
## step. On the ground floor's own collision layer, the same one every
## wall piece uses (EarthChunkManager.GROUND_FLOOR_COLLISION_LAYER), so
## nothing new has to learn about it.
##
## Sized in the prop's own WORLD units: `size` is the art's own pixel size,
## which is authored DETAIL_MULTIPLIER times oversized (see
## docs/concept/art_resolution.md), and the sprite is scaled back by
## SPRITE_SCALE -- a body that used the raw numbers would be a wall several
## tiles across.
func _solid_body_for(size: Vector2i) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = "LandmarkCollision"
	body.collision_layer = GROUND_FLOOR_COLLISION_LAYER
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	# In the SPRITE's own space: the body is a child of the scaled sprite, so
	# Godot applies that scale to the shape as well.
	rect.size = Vector2(size) * _SOLID_LANDMARK_FOOTPRINT_FRACTION
	shape.shape = rect
	# A prop stands ON its own base, so what stops you is the stonework at
	# its foot rather than a column of air over it. The sprite is anchored at
	# that foot now (see _build_landmark), so the box sits on the origin.
	shape.position = Vector2.ZERO
	body.add_child(shape)
	return body


## A prop's real art if any has been supplied for it, and its procedural
## drawing otherwise (see LandmarkSheet, which owns where that art lives
## and what it has to look like). Asked for directly: the stands, wells and
## beds look out of place beside the pixel art the houses and the city hall
## now have, and this is the one place a supplied PNG takes over -- nothing
## else has to change when one arrives.
##
## Seeded from the prop's own position so a village with two of the same
## prop does not draw the same variant twice, and so a prop looks like
## itself across reloads. Only matters for a prop whose art is a grid; a
## plain single-image sheet has one cell whatever the seed.
func _landmark_texture(landmark_id: String, position: Vector2) -> Texture2D:
	var seed_value := hash("%d_%d_prop" % [int(position.x), int(position.y)])
	# Scaled to the size that prop really is, never assumed to have been
	# authored at it -- see LandmarkSheet.world_scaled_image, and the
	# "huge potato crops" history it cites.
	var image := LandmarkSheet.world_scaled_image(landmark_id, seed_value, _structure_sprite)
	if image != null:
		return ImageTexture.create_from_image(image)
	# No sheet, no prop. The procedural box (ProceduralLandmarkSprite) was
	# the scaffolding that let the whole village system be built and played
	# before any prop art existed, and it did that job. Two props have real
	# art now (LandmarkSheet._SHEETS), and for the six that do not the
	# fallback reads as clutter rather than as a placeholder -- reported
	# live with close-ups of the field's soil-and-crop-dots, the forge's
	# grey box with an orange fire, and the dock's planks standing in blue
	# water: "remove These procedural entities please".
	#
	# The villager still works the spot; there is simply nothing drawn on
	# it until a real sheet is dropped into assets/sprites/landmarks/, which
	# is the same "the moment a file is dropped in" contract the props that
	# DO have art already follow.
	return null


## `home_position` is this villager's own house's DOORSTEP position (the
## real cell they actually walk up to, on the road -- see spawn_village) --
## not a house-anchor point -- so a villager standing at home is standing
## somewhere it could actually have walked to. `world` is forwarded into
## NpcMarker.setup so villagers are water-aware (swim animation) exactly
## like the player and wild creatures.
func _build_npc(
	settlement: Dictionary, index: int, home_position: Vector2, workspot, tile_size: int,
	parent: Node2D, world = null, market = null, warehouse_door = null
) -> NpcMarker:
	var identity = settlement.npcs[index]

	var marker := NpcMarker.new()
	marker.identity = identity
	marker.home_position = home_position
	# A villager whose trade has nowhere dry to happen works at their own
	# door rather than walking into the river to reach a spot that is not
	# there. `workspot` is already grounded by the caller.
	marker.workspot_position = workspot if workspot != null else home_position
	marker.landmarks = settlement.landmarks
	# Before setup_economy, which reads it to decide whether this villager
	# carries their take to a door or stocks the village where they stand.
	marker.warehouse_position = warehouse_door
	marker.position = home_position
	if world != null:
		marker.setup(world, tile_size)
	if market != null:
		# Their own household's persistent purse, so a villager's working
		# life survives the chunk unloading under them.
		var household_wallet = (
			world.household_wallet_for_villager(identity.seed_value)
			if world != null and world.has_method("household_wallet_for_villager") else null
		)
		marker.setup_economy(market, household_wallet)

	# Villagers use the SAME CharacterView the player does, rather than a
	# hand-assembled torso-plus-head. Sharing the view means body
	# proportions, resolution and walk animation can only ever come from
	# one place.
	marker.add_child(_drop_shadow.make_shadow(
		int(CharacterView.BODY_SIZE.x * 0.9 * CharacterView.SCALE),
		CharacterView.BODY_SIZE.y * 0.5 * CharacterView.SCALE - 1.0
	))
	# The marker must be in the tree BEFORE the view is dressed: CharacterView
	# reaches its part sprites through @onready refs, which stay null until
	# the node enters the tree.
	parent.add_child(marker)

	var view := CharacterViewScene.instantiate()
	marker.add_child(view)
	view.apply_appearance(_appearance.appearance_for(identity.occupation, identity.seed_value))
	marker.bind_character_view(view)
	return marker
