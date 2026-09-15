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
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const NpcMarker = preload("res://src/rendering/npc_marker.gd")
const VillageMarket = preload("res://src/world/village_market.gd")
const ProceduralLandmarkSprite = preload("res://src/rendering/procedural_landmark_sprite.gd")
const ProceduralCharacterSprite = preload("res://src/rendering/procedural_character_sprite.gd")
const HeroAppearance = preload("res://src/rendering/hero_appearance.gd")
const CharacterViewScene = preload("res://scenes/character_view.tscn")
const CharacterView = preload("res://scenes/character_view.gd")
const DropShadow = preload("res://src/rendering/drop_shadow.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")

## Villagers are rendered with the player's own CharacterView (see
## _build_npc), so there are deliberately no villager-specific body size
## constants here -- the previous ones drifted out of sync with
## CharacterView and left NPCs legless.

var _settlement_generator := SettlementGenerator.new()
var _village_layout := VillageLayout.new()
var _landmark_sprite := ProceduralLandmarkSprite.new()
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
## Not attempted as a hard collision guarantee the way road/building
## siting is -- fine for a decorative prop a few tiles from a door.
const _WORKSPOT_OFFSET_TILES := 4.0

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
	var settlement := _settlement_generator.generate_settlement(
		chunk_coord, chunk_origin_tiles, chunk_size, tile_size
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
	var building_ids: Array = []
	for i in npcs.size():
		var seed_value := hash("%d_%d_house_%d" % [chunk_coord.x, chunk_coord.y, i])
		building_ids.append(BuildingCatalog.choose_house_id(npcs[i].occupation, npcs[i].genome, seed_value))

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
		var layout_seed := hash("%d_%d_village_layout" % [chunk_coord.x, chunk_coord.y])
		var is_buildable := func(cell: Vector2i) -> bool:
			var g: Vector2i = chunk_coord * chunk_size + cell
			return world.is_buildable_terrain_at(g.x, g.y) if world.has_method("is_buildable_terrain_at") else true
		var is_occupied := func(cell: Vector2i) -> bool:
			var g: Vector2i = chunk_coord * chunk_size + cell
			return world.modification_at_global(g.x, g.y) != "" if world.has_method("modification_at_global") else false
		var result := _village_layout.layout(building_ids, chunk_size, layout_seed, is_buildable, is_occupied)
		plots = result["plots"]

		if world.has_method("build_at_global"):
			for local_cell in result["road_cells"]:
				var g: Vector2i = chunk_coord * chunk_size + local_cell
				world.build_at_global(g.x, g.y, TerrainRenderer.TRAIL_TILE_ID)

		for plot in plots:
			var building_index: int = plot["building_index"]
			var building_seed := hash("%d_%d_house_%d" % [chunk_coord.x, chunk_coord.y, building_index])
			world.place_building(chunk_coord, plot["origin"], plot["building_id"], plot["facing"], building_seed, "")
			var doorstep_global: Vector2i = chunk_coord * chunk_size + plot["doorstep"]
			var doorstep_position := Vector2(
				(doorstep_global.x + 0.5) * tile_size, (doorstep_global.y + 0.5) * tile_size
			)
			door_positions[building_index] = doorstep_position
			stand_positions[building_index] = doorstep_position + Vector2(0, _STAND_OFFSET_TILES * tile_size)

	# Tells the world this settlement exists, duck-typed exactly like
	# place_building above -- world == null or lacking the method is
	# skipped rather than crashing. EarthChunkManager owns deciding whether
	# this is genuinely a FIRST founding (a chunk reload must not re-record
	# one). `plots` (computed above, possibly empty) lets it grant each
	# actually-placed house's ownership through the unified id scheme.
	if world != null and world.has_method("record_settlement_founded_if_new"):
		world.record_settlement_founded_if_new(chunk_coord, npcs, plots)

	var spawned: Array[Node2D] = []
	for landmark_id in settlement.landmarks:
		spawned.append(_build_landmark(landmark_id, settlement.landmarks[landmark_id], parent))
	for i in npcs.size():
		var npc_marker := _build_npc(settlement, i, door_positions[i], tile_size, parent, world, market)
		spawned.append(npc_marker)
		# A merchant gets a second, PERSONAL trading stand at their own house,
		# on top of the one shared village-square stall -- otherwise every
		# merchant in the village routes to the same single stall, which reads
		# as one shop rather than several villagers who each trade (see
		# docs/concept/npc.md).
		if npcs[i].occupation == "merchant":
			spawned.append(_build_landmark("stall", stand_positions[i], parent))
		# Every OTHER occupation whose own work location isn't already one of
		# the settlement's 3 shared landmarks (merchant/stall and guard/gate
		# both already have something real there) gets a real prop of their
		# own at their personal workspot -- a farmer's field, a blacksmith's
		# forge, a fisher's dock, an herbalist's garden -- instead of an
		# invisible position they simply stood on empty grass at.
		var work_tag: String = NpcIdentity.WORK_LOCATION_BY_OCCUPATION.get(npcs[i].occupation, "")
		if work_tag != "" and not settlement.landmarks.has(work_tag):
			spawned.append(_build_landmark(work_tag, npc_marker.workspot_position, parent))
	return spawned


## The settlement's shared well/stall/gate, a merchant's personal trading
## stand, and a farmer/blacksmith/fisher/herbalist's own workspot prop --
## real, visible props NPC schedules walk to. Tagged with its own
## `landmark_id` as node metadata so a caller (chiefly tests, since several
## distinct landmark kinds can now exist side by side in the same spawned
## list) can tell exactly which prop a given node is without resorting to
## comparing raw positions.
func _build_landmark(landmark_id: String, position: Vector2, parent: Node2D) -> Sprite2D:
	var landmark := Sprite2D.new()
	landmark.texture = _landmark_sprite.generate_texture(landmark_id)
	landmark.set_meta("landmark_id", landmark_id)
	# Art is authored DETAIL_MULTIPLIER times oversized for pixel detail;
	# scaling it back keeps the world footprint unchanged (see
	# docs/concept/art_resolution.md).
	landmark.scale = Vector2.ONE * ArtResolution.SPRITE_SCALE
	landmark.position = position
	var size: Vector2i = ProceduralLandmarkSprite.SIZES.get(landmark_id, Vector2i(20, 20))
	landmark.add_child(_drop_shadow.make_shadow(int(size.x * 0.8), size.y * 0.5 - 1.0))
	parent.add_child(landmark)
	return landmark


## `home_position` is this villager's own house's DOORSTEP position (the
## real cell they actually walk up to, on the road -- see spawn_village) --
## not a house-anchor point -- so a villager standing at home is standing
## somewhere it could actually have walked to. `world` is forwarded into
## NpcMarker.setup so villagers are water-aware (swim animation) exactly
## like the player and wild creatures.
func _build_npc(
	settlement: Dictionary, index: int, home_position: Vector2, tile_size: int, parent: Node2D, world = null, market = null
) -> NpcMarker:
	var identity = settlement.npcs[index]

	var marker := NpcMarker.new()
	marker.identity = identity
	marker.home_position = home_position
	marker.workspot_position = home_position + Vector2(0, _WORKSPOT_OFFSET_TILES * tile_size)
	marker.landmarks = settlement.landmarks
	marker.position = home_position
	if world != null:
		marker.setup(world, tile_size)
	if market != null:
		marker.setup_economy(market)

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
