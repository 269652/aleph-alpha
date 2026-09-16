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
		# merely theorized: only re-run placement on a genuinely first
		# load (no buildings persisted for this chunk yet); on a reload,
		# recover each villager's OWN existing building instead (see the
		# else branch below).
		var existing_buildings: Array = (
			world.buildings_in_chunk(chunk_coord) if world.has_method("buildings_in_chunk") else []
		)
		if existing_buildings.is_empty():
			_place_new_village(chunk_coord, chunk_size, tile_size, building_ids, npcs, world, plots, door_positions, stand_positions)
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


## First-ever placement for this settlement (see spawn_village's own
## existing_buildings gate) -- computes a fresh VillageLayout, places
## every plot's building, and lays roads. Mutates `plots`/`door_positions`/
## `stand_positions` in place (GDScript Arrays are reference types, so
## spawn_village's own locals update directly) rather than returning a
## tuple.
func _place_new_village(
	chunk_coord: Vector2i, chunk_size: int, tile_size: int, building_ids: Array, npcs: Array, world,
	plots: Array, door_positions: Array, stand_positions: Array
) -> void:
	var layout_seed := VillageLayout.seed_for(chunk_coord)
	var is_buildable := _is_buildable_local(chunk_coord, chunk_size, world)
	var is_occupied := _is_occupied_local(chunk_coord, chunk_size, world)
	var result := _village_layout.layout(building_ids, chunk_size, layout_seed, is_buildable, is_occupied)

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


## A reload: this settlement's buildings are already persisted from an
## earlier load (spawn_village's own existing_buildings gate). Matches
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
	for i in npcs.size():
		var expected_seed := hash("%d_%d_house_%d" % [chunk_coord.x, chunk_coord.y, i])
		for record in existing_buildings:
			if record.get("seed", -1) != expected_seed:
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


## The two world predicates VillageLayout reads, translated from chunk-
## local cells to the world's own global-tile queries -- duck-typed like
## every other world call in this file (a world lacking the method is
## treated as open, buildable ground). A village sites on the GROUND
## (EarthChunkManager.is_buildable_ground_at: water and the forest biome
## refuse, a standing tree does not -- placing a building or paving a road
## fells it), not on the player's own fell-the-trees-first rule
## (is_buildable_terrain_at, the fallback for a world without the ground
## query): found live, one tree on the plaza square vetoed the whole plaza
## and the town hall with it in most real settlement chunks.
func _is_buildable_local(chunk_coord: Vector2i, chunk_size: int, world) -> Callable:
	return func(cell: Vector2i) -> bool:
		var g: Vector2i = chunk_coord * chunk_size + cell
		if world.has_method("is_buildable_ground_at"):
			return world.is_buildable_ground_at(g.x, g.y)
		return world.is_buildable_terrain_at(g.x, g.y) if world.has_method("is_buildable_terrain_at") else true


func _is_occupied_local(chunk_coord: Vector2i, chunk_size: int, world) -> Callable:
	return func(cell: Vector2i) -> bool:
		var g: Vector2i = chunk_coord * chunk_size + cell
		return world.modification_at_global(g.x, g.y) != "" if world.has_method("modification_at_global") else false


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
	var skeleton := VillageLayout.skeleton(chunk_size, VillageLayout.seed_for(chunk_coord))
	var doorstep: Vector2i = chunk_coord * chunk_size + skeleton["civic_plot"]["doorstep"]
	if TerrainRenderer.is_road_tile(world.modification_at_global(doorstep.x, doorstep.y)):
		return
	var plaza: Rect2i = skeleton["plaza"]
	var is_buildable := _is_buildable_local(chunk_coord, chunk_size, world)
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
