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
		_is_buildable_local(chunk_coord, chunk_size, world) if world != null else Callable()
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
	var farm_fields := _fenced_farm_fields(chunk_coord, chunk_size, world)
	for landmark_id in settlement.landmarks:
		spawned.append(_build_landmark(landmark_id, settlement.landmarks[landmark_id], parent))
	for i in npcs.size():
		var workspot = _grounded_position(
			door_positions[i] + Vector2(0, _WORKSPOT_OFFSET_TILES * tile_size), tile_size, world, false
		)
		var npc_marker := _build_npc(settlement, i, door_positions[i], workspot, tile_size, parent, world, market)
		spawned.append(npc_marker)
		npc_markers.append(npc_marker)
		# A merchant gets a second, PERSONAL trading stand at their own house,
		# on top of the one shared village-square stall -- otherwise every
		# merchant in the village routes to the same single stall, which reads
		# as one shop rather than several villagers who each trade (see
		# docs/concept/npc.md).
		if npcs[i].occupation == "merchant":
			var stand = _grounded_position(stand_positions[i], tile_size, world, false)
			if stand != null:
				spawned.append(_build_landmark("stall", stand, parent, true))
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
		if work_tag != "" and not settlement.landmarks.has(work_tag) and workspot != null:
			spawned.append(_build_landmark(work_tag, workspot, parent, true))
	_hand_out_farm_fields(npcs, npc_markers, farm_fields)
	return spawned


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
	var result := _village_layout.layout(building_ids, chunk_size, layout_seed, is_buildable, is_occupied)
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

	_place_industry_if_missing(chunk_coord, chunk_size, world)
	_place_warehouse_if_missing(chunk_coord, chunk_size, world)
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
func _is_buildable_local(chunk_coord: Vector2i, chunk_size: int, world) -> Callable:
	return func(cell: Vector2i) -> bool:
		var g: Vector2i = chunk_coord * chunk_size + cell
		if world.has_method("is_water_at_global"):
			return not world.is_water_at_global(g.x, g.y)
		if world.has_method("is_buildable_ground_at"):
			return world.is_buildable_ground_at(g.x, g.y)
		return world.is_buildable_terrain_at(g.x, g.y) if world.has_method("is_buildable_terrain_at") else true


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
func _place_industry_if_missing(chunk_coord: Vector2i, chunk_size: int, world) -> void:
	if not world.has_method("place_building"):
		return
	if world.has_method("buildings_in_chunk"):
		for record in world.buildings_in_chunk(chunk_coord):
			if record.get("id", "") == INDUSTRY_BUILDING_ID:
				return

	var plot := VillageLayout.industry_plot(
		INDUSTRY_BUILDING_ID, chunk_size, VillageLayout.seed_for(chunk_coord),
		_is_buildable_local(chunk_coord, chunk_size, world),
		_is_forest_local(chunk_coord, chunk_size, world),
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
## Derived from the skeleton, so it costs nothing and needs nothing stored.
func _is_street_row(chunk_coord: Vector2i, chunk_size: int, world, y: int) -> bool:
	var bones := VillageLayout.skeleton(
		chunk_size, VillageLayout.seed_for(chunk_coord), _is_buildable_local(chunk_coord, chunk_size, world)
	)
	var street_y: int = bones["street_y"]
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


## Every farmhouse's own field, worked out and FENCED (docs/concept/
## village_farms.md): `{origin -> the global cells that farmhouse works}`,
## in the same (y, x) order _farmhouse_origins returns.
##
## Called before any villager or prop is placed, because both are grounded
## against what is already built: a prop placed first would have rails
## dropped through it, and a villager's own field has to exist before they
## can be handed it.
func _fenced_farm_fields(chunk_coord: Vector2i, chunk_size: int, world) -> Dictionary:
	if world == null:
		return {}
	var origins := _farmhouse_origins(chunk_coord, world)
	if origins.is_empty():
		return {}
	var is_buildable := _is_buildable_local(chunk_coord, chunk_size, world)
	var is_occupied := _is_occupied_local(chunk_coord, chunk_size, world)
	var fields: Dictionary = {}
	for origin in origins:
		fields[origin] = _workable_field_of(
			origin, origins, chunk_coord, chunk_size, is_buildable, is_occupied, world
		)
	_fence_the_fields(chunk_coord, chunk_size, fields, is_buildable, is_occupied, world)
	return fields


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
func _hand_out_farm_fields(npcs: Array, npc_markers: Array, fields: Dictionary) -> void:
	if fields.is_empty() or npc_markers.size() < npcs.size():
		return
	var origins: Array = fields.keys()
	var next_farmhouse := 0
	for i in npcs.size():
		if VillageFarm.crop_for(npcs[i].occupation) == "":
			continue
		if next_farmhouse >= origins.size():
			return
		npc_markers[i].field_cells = fields[origins[next_farmhouse]]
		next_farmhouse += 1


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
func _build_landmark(landmark_id: String, position: Vector2, parent: Node2D, personal: bool = false) -> Sprite2D:
	var landmark := Sprite2D.new()
	landmark.texture = _landmark_texture(landmark_id, position)
	landmark.set_meta("landmark_id", landmark_id)
	landmark.set_meta("personal", personal)
	# Art is authored DETAIL_MULTIPLIER times oversized for pixel detail;
	# scaling it back keeps the world footprint unchanged (see
	# docs/concept/art_resolution.md).
	landmark.scale = Vector2.ONE * ArtResolution.SPRITE_SCALE
	landmark.position = position
	var size: Vector2i = ProceduralLandmarkSprite.SIZES.get(landmark_id, Vector2i(20, 20))
	landmark.add_child(_drop_shadow.make_shadow(int(size.x * 0.8), size.y * 0.5 - 1.0))
	parent.add_child(landmark)
	return landmark


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
	return _landmark_sprite.generate_texture(landmark_id)


## `home_position` is this villager's own house's DOORSTEP position (the
## real cell they actually walk up to, on the road -- see spawn_village) --
## not a house-anchor point -- so a villager standing at home is standing
## somewhere it could actually have walked to. `world` is forwarded into
## NpcMarker.setup so villagers are water-aware (swim animation) exactly
## like the player and wild creatures.
func _build_npc(
	settlement: Dictionary, index: int, home_position: Vector2, workspot, tile_size: int,
	parent: Node2D, world = null, market = null
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
