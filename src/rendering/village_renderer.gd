extends RefCounted

const ArtResolution = preload("res://src/rendering/art_resolution.gd")

## Chunk-based spawn/despawn of a procedurally generated village (see
## SettlementGenerator, docs/concept/npc.md) -- real HouseBlueprint-stamped
## houses (see _stamp_house) plus walking NpcMarker villagers, wearing the
## same hero-appearance engine the player uses (HeroAppearance/
## ProceduralCharacterSprite), keyed by occupation instead of class. Same
## "one call per chunk load, deterministic, returns spawned nodes for the
## caller to free" shape as TreeRenderer/CreatureRenderer/FishRenderer --
## except houses themselves are chunk modifications, not spawned nodes (see
## spawn_village's own doc comment).

const SettlementGenerator = preload("res://src/world/settlement_generator.gd")
const NpcMarker = preload("res://src/rendering/npc_marker.gd")
const ProceduralLandmarkSprite = preload("res://src/rendering/procedural_landmark_sprite.gd")
const ProceduralCharacterSprite = preload("res://src/rendering/procedural_character_sprite.gd")
const HeroAppearance = preload("res://src/rendering/hero_appearance.gd")
const CharacterViewScene = preload("res://scenes/character_view.tscn")
const CharacterView = preload("res://scenes/character_view.gd")
const DropShadow = preload("res://src/rendering/drop_shadow.gd")
const HouseBlueprint = preload("res://src/gameplay/house_blueprint.gd")
const BuildingPiece = preload("res://src/gameplay/building_piece.gd")
const PixelNoise = preload("res://src/rendering/pixel_noise.gd")
const CreaturePerception = preload("res://src/gameplay/creature_perception.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")

## Villagers are rendered with the player's own CharacterView (see
## _build_npc), so there are deliberately no villager-specific body size
## constants here -- the previous ones drifted out of sync with
## CharacterView and left NPCs legless.

var _settlement_generator := SettlementGenerator.new()
var _landmark_sprite := ProceduralLandmarkSprite.new()
var _character_sprite := ProceduralCharacterSprite.new()
var _appearance := HeroAppearance.new()
var _drop_shadow := DropShadow.new()
var _house_blueprint := HouseBlueprint.new()

## Roughly 1-in-this-many houses is stone rather than wood -- most villages
## read as a wood-built settlement, with the occasional stone house for
## visual variety, deterministic per house.
const _STONE_HOUSE_CHANCE_DENOMINATOR := 4

## How far a house's origin may be nudged off its ring-layout anchor to
## escape a water pocket (a chunk's dominant biome only gates the whole
## CHUNK, not every individual cell -- see BiomeClassifier.dominant_biome --
## so a grassland-dominant chunk can still have a pond/river cutting through
## it). Comfortably larger than one house footprint's own diagonal, so a
## small pond doesn't strand a house with nowhere to go; a house that still
## can't find dry ground within this radius is skipped rather than forced
## into the water (see _stamp_house).
const _WATER_AVOIDANCE_SEARCH_RADIUS_TILES := 6

## How far outside the door a merchant's personal trading stand sits (see
## _build_stands_for_merchants) -- close enough to read as "this villager's
## own stand", clear of the door cell and the house's wall thickness.
const _STAND_OFFSET_TILES := 2


## Spawns this chunk's village (real stamped houses, landmark props, and NPC
## markers, the last two as children of `parent`) if SettlementGenerator
## places one here, given the chunk's dominant_biome (see BiomeClassifier.
## dominant_biome -- ocean/mountain never qualify). Returns [] on a chunk
## with no settlement.
##
## `world` is the owning EarthChunkManager (duck-typed: only
## stamp_structure_at_global is actually called), the same object every
## other renderer's spawn call already receives. A village house is not a
## decorative sprite with a painted-on door any more -- it's a real
## HouseBlueprint assembly of floor/wall/door/roof pieces stamped into the
## world exactly the way the player's own building pieces are (see
## docs/concept/building.md#one-system-two-builders), so it produces no
## Node2D of its own; only the returned door position (used for the
## villager's home_position) comes out of stamping a house. `world == null`
## (an isolated rendering test/tool that doesn't need real chunk mutation)
## skips stamping entirely rather than crashing -- same fail-open shape as
## _water_layer/_roof_layer elsewhere in this codebase -- and falls back to
## the raw anchor position so callers still get a sensible home_position.
func spawn_village(
	parent: Node2D,
	chunk_coord: Vector2i,
	chunk_origin_tiles: Vector2i,
	chunk_size: int,
	tile_size: int,
	dominant_biome: String,
	world = null
) -> Array[Node2D]:
	if not _settlement_generator.has_settlement_at(chunk_coord, dominant_biome):
		return []
	var settlement := _settlement_generator.generate_settlement(
		chunk_coord, chunk_origin_tiles, chunk_size, tile_size
	)

	var spawned: Array[Node2D] = []
	var house_positions: Array = settlement.house_positions
	var npcs: Array = settlement.npcs
	var door_positions: Array[Vector2] = []
	var stand_positions: Array[Vector2] = []
	for i in house_positions.size():
		var house := _stamp_house(chunk_coord, i, house_positions[i], npcs[i], tile_size, world)
		door_positions.append(house.door)
		stand_positions.append(house.stand)
	for landmark_id in settlement.landmarks:
		spawned.append(_build_landmark(landmark_id, settlement.landmarks[landmark_id], parent))
	for i in npcs.size():
		var npc_marker := _build_npc(settlement, i, door_positions[i], tile_size, parent, world)
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
		# invisible position they simply stood on empty grass at (reported
		# directly as the remaining gap after houses themselves got real
		# variety: "no per-occupation building beyond the shared landmarks
		# and a merchant's own stand").
		var work_tag: String = NpcIdentity.WORK_LOCATION_BY_OCCUPATION.get(npcs[i].occupation, "")
		if work_tag != "" and not settlement.landmarks.has(work_tag):
			spawned.append(_build_landmark(work_tag, npc_marker.workspot_position, parent))
	return spawned


## Stamps one villager's house as a real HouseBlueprint structure centred
## roughly on `anchor` (the old ring-layout position), and returns
## {"door": Vector2, "stand": Vector2} -- the door is what the villager
## should actually walk home to, since it's the one cell of the house
## guaranteed to be both walkable and on the structure's edge (walking to the
## raw anchor/centre would just as often land an NPC in the middle of a wall
## or floor cell); the stand is one step further out in the same direction,
## for a merchant's personal trading stand (see spawn_village). Both fall
## back to `anchor` when nothing is actually stamped (no world, an empty
## footprint, or no dry ground nearby -- see _find_dry_origin), the same
## fail-open shape as the rest of this function.
##
## `npc` (the villager's own NpcIdentity) is what makes the house THEIRS:
## HouseBlueprint.choose_blueprint_id picks a real named shape from
## `npc.occupation`'s own pool, nudged by `npc.genome`'s dominant
## personality trait (docs/concept/npc.md's "personality should be DNA
## derived") -- a farmer's hut, a merchant's bright manor, and everything
## between, instead of the one fixed 5x4 box every villager used to get.
func _stamp_house(chunk_coord: Vector2i, index: int, anchor: Vector2, npc: NpcIdentity, tile_size: int, world) -> Dictionary:
	var seed_value := hash("%d_%d_house_%d" % [chunk_coord.x, chunk_coord.y, index])
	var blueprint_id := _house_blueprint.choose_blueprint_id(npc.occupation, npc.genome, seed_value)
	var footprint := _house_blueprint.footprint_for(blueprint_id)
	var anchor_tile := Vector2i(floori(anchor.x / tile_size), floori(anchor.y / tile_size))
	var raw_origin := anchor_tile - footprint / 2

	if world == null or not world.has_method("stamp_structure_at_global"):
		return {"door": anchor, "stand": anchor}

	var material := (
		BuildingPiece.MATERIAL_STONE
		if PixelNoise.value(seed_value, index, 0) % _STONE_HOUSE_CHANCE_DENOMINATOR == 0
		else BuildingPiece.MATERIAL_WOOD
	)
	var pieces := _house_blueprint.build(blueprint_id, seed_value, material)
	if pieces.is_empty():
		return {"door": anchor, "stand": anchor}

	var origin_tile = _find_dry_origin(raw_origin, footprint, world)
	if origin_tile == null:
		return {"door": anchor, "stand": anchor}  # no dry ground nearby -- skip rather than build in water

	var roofs := _house_blueprint.build_roofs(blueprint_id, seed_value, material)
	world.stamp_structure_at_global(chunk_coord, origin_tile, pieces, roofs)

	var door_local := _door_cell(pieces)
	var door_global: Vector2i = origin_tile + door_local
	var door_position := Vector2((door_global.x + 0.5) * tile_size, (door_global.y + 0.5) * tile_size)

	var facing := _door_facing_direction(door_local, pieces)
	var stand_global := door_global + facing * _STAND_OFFSET_TILES
	var stand_position := Vector2((stand_global.x + 0.5) * tile_size, (stand_global.y + 0.5) * tile_size)

	return {"door": door_position, "stand": stand_position}


## Which way the door opens outward: the OPPOSITE direction from wherever
## its one true FLOOR neighbour sits (see HouseBlueprint._wall_candidates --
## a valid door/window cell always has exactly one floor neighbour, so this
## is well-defined for every blueprint shape, rectangular or notched).
## Previously assumed a plain box's 4 sides directly from the door's raw
## (x, y) -- correct for every rectangular blueprint, but would have
## silently defaulted to "east" for a door landing on an L-shaped
## blueprint's own notch-exposed edge (not one of the box's outer 4 sides
## at all), pointing a merchant's personal trading stand at a wall instead
## of open ground.
func _door_facing_direction(door_local: Vector2i, pieces: Dictionary) -> Vector2i:
	var offsets: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	for offset in offsets:
		var neighbor: Vector2i = door_local + offset
		if BuildingPiece.category_of(pieces.get(neighbor, "")) == BuildingPiece.CATEGORY_FLOOR:
			return -offset
	return Vector2i(1, 0)  # never happens for a real door cell; stays safe regardless


## `raw_origin` if its whole footprint is dry land already; otherwise the
## nearest (by squared distance, deterministic) candidate origin within
## _WATER_AVOIDANCE_SEARCH_RADIUS_TILES whose whole footprint is dry; null if
## none qualifies. `world` without biome_at_global (a caller that only cares
## about stamp_structure_at_global, e.g. an older/duck-typed test double)
## skips the check entirely and trusts raw_origin, same fail-open shape as
## every other optional-capability check in this codebase.
func _find_dry_origin(raw_origin: Vector2i, footprint: Vector2i, world) -> Variant:
	if not world.has_method("biome_at_global") or _footprint_is_dry(raw_origin, footprint, world):
		return raw_origin
	var offsets: Array[Vector2i] = []
	for dy in range(-_WATER_AVOIDANCE_SEARCH_RADIUS_TILES, _WATER_AVOIDANCE_SEARCH_RADIUS_TILES + 1):
		for dx in range(-_WATER_AVOIDANCE_SEARCH_RADIUS_TILES, _WATER_AVOIDANCE_SEARCH_RADIUS_TILES + 1):
			if dx != 0 or dy != 0:
				offsets.append(Vector2i(dx, dy))
	offsets.sort_custom(func(a, b): return a.length_squared() < b.length_squared())
	for offset in offsets:
		var candidate := raw_origin + offset
		if _footprint_is_dry(candidate, footprint, world):
			return candidate
	return null


func _footprint_is_dry(origin: Vector2i, footprint: Vector2i, world) -> bool:
	for x in footprint.x:
		for y in footprint.y:
			var cell := origin + Vector2i(x, y)
			if world.biome_at_global(cell.x, cell.y) == CreaturePerception.WATER_BIOME:
				return false
	return true


func _door_cell(pieces: Dictionary) -> Vector2i:
	for cell in pieces:
		if BuildingPiece.category_of(pieces[cell]) == BuildingPiece.CATEGORY_DOOR:
			return cell
	return Vector2i.ZERO


## The settlement's shared well/stall/gate, a merchant's personal trading
## stand, and a farmer/blacksmith/fisher/herbalist's own workspot prop --
## previously all invisible positions NPC schedules walked to, now real,
## visible props. Tagged with its own `landmark_id` as node metadata so a
## caller (chiefly tests, since several distinct landmark kinds can now
## exist side by side in the same spawned list) can tell exactly which prop
## a given node is without resorting to comparing raw positions.
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


## Each villager gets a personal workspot south of their own house, for
## occupations whose work tag isn't one of the settlement's 3 shared
## landmarks (see NpcMarker._resolve_location, and this file's own
## WORK_LOCATION_BY_OCCUPATION-driven prop spawning in spawn_village).
## Houses now vary in size per-villager (see HouseBlueprint.BLUEPRINT_IDS),
## so unlike the original fixed 5x4 box this offset is no longer guaranteed
## to clear every possible house footprint -- fine for a decorative prop a
## couple tiles from a door, not attempted as a hard collision guarantee the
## way house placement's own water-avoidance is.
const _WORKSPOT_OFFSET_TILES := 4.0


## `home_position` is this villager's own house's DOOR position (see
## _stamp_house) -- not a house-anchor point -- so a villager standing at
## home is standing somewhere it could actually have walked to. `world` is
## forwarded into NpcMarker.setup so villagers are water-aware (swim
## animation) exactly like the player and wild creatures -- previously
## nothing passed it through, so a villager's walk cycle never left WALKING
## even while crossing water.
func _build_npc(settlement: Dictionary, index: int, home_position: Vector2, tile_size: int, parent: Node2D, world = null) -> NpcMarker:
	var identity = settlement.npcs[index]

	var marker := NpcMarker.new()
	marker.identity = identity
	marker.home_position = home_position
	marker.workspot_position = home_position + Vector2(0, _WORKSPOT_OFFSET_TILES * tile_size)
	marker.landmarks = settlement.landmarks
	marker.position = home_position
	if world != null:
		marker.setup(world, tile_size)

	# Villagers use the SAME CharacterView the player does, rather than a
	# hand-assembled torso-plus-head. The old version had neither legs nor
	# arms (reported: "npcs have no legs") and carried its own size
	# constants, which had silently fallen out of sync with CharacterView's
	# and missed the art-resolution pass entirely. Sharing the view means
	# body proportions, resolution and walk animation can only ever come
	# from one place.
	# CharacterView.BODY_SIZE is the pre-shrink world size -- CharacterView
	# itself now scales down further to CharacterView.SCALE (2/3 of a tree's
	# height, see its own doc comment), so the shadow has to be sized off
	# that same scale or it renders oversized relative to the now-smaller
	# villager standing on it.
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
