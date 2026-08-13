extends RefCounted

const ArtResolution = preload("res://src/rendering/art_resolution.gd")

## Chunk-based spawn/despawn of a procedurally generated village (see
## SettlementGenerator, docs/concept/npc.md) -- houses (ProceduralHouseSprite)
## plus walking NpcMarker villagers, wearing the same hero-appearance engine
## the player uses (HeroAppearance/ProceduralCharacterSprite), keyed by
## occupation instead of class. Same "one call per chunk load, deterministic,
## returns spawned nodes for the caller to free" shape as
## TreeRenderer/CreatureRenderer/FishRenderer.

const SettlementGenerator = preload("res://src/world/settlement_generator.gd")
const NpcMarker = preload("res://src/rendering/npc_marker.gd")
const ProceduralHouseSprite = preload("res://src/rendering/procedural_house_sprite.gd")
const ProceduralLandmarkSprite = preload("res://src/rendering/procedural_landmark_sprite.gd")
const ProceduralCharacterSprite = preload("res://src/rendering/procedural_character_sprite.gd")
const HeroAppearance = preload("res://src/rendering/hero_appearance.gd")
const CharacterViewScene = preload("res://scenes/character_view.tscn")
const CharacterView = preload("res://scenes/character_view.gd")
const DropShadow = preload("res://src/rendering/drop_shadow.gd")

## Villagers are rendered with the player's own CharacterView (see
## _build_npc), so there are deliberately no villager-specific body size
## constants here -- the previous ones drifted out of sync with
## CharacterView and left NPCs legless.

var _settlement_generator := SettlementGenerator.new()
var _house_sprite := ProceduralHouseSprite.new()
var _landmark_sprite := ProceduralLandmarkSprite.new()
var _character_sprite := ProceduralCharacterSprite.new()
var _appearance := HeroAppearance.new()
var _drop_shadow := DropShadow.new()


## Spawns this chunk's village (houses + NPC markers, as children of
## `parent`) if SettlementGenerator places one here, given the chunk's
## dominant_biome (see BiomeClassifier.dominant_biome -- ocean/mountain never
## qualify). Returns [] on a chunk with no settlement. `world` (duck-typed
## biome_at_global, same contract as CreatureRenderer/FishRenderer) is handed
## to... nothing yet (NpcMarker doesn't sense terrain), accepted for
## signature symmetry with the other renderers and future use.
func spawn_village(
	parent: Node2D,
	chunk_coord: Vector2i,
	chunk_origin_tiles: Vector2i,
	chunk_size: int,
	tile_size: int,
	dominant_biome: String,
	_world = null
) -> Array[Node2D]:
	if not _settlement_generator.has_settlement_at(chunk_coord, dominant_biome):
		return []
	var settlement := _settlement_generator.generate_settlement(
		chunk_coord, chunk_origin_tiles, chunk_size, tile_size
	)

	var spawned: Array[Node2D] = []
	var house_positions: Array = settlement.house_positions
	for i in house_positions.size():
		spawned.append(_build_house(chunk_coord, i, house_positions[i], parent))
	for landmark_id in settlement.landmarks:
		spawned.append(_build_landmark(landmark_id, settlement.landmarks[landmark_id], parent))
	var npcs: Array = settlement.npcs
	for i in npcs.size():
		spawned.append(_build_npc(settlement, i, tile_size, parent))
	return spawned


func _build_house(chunk_coord: Vector2i, index: int, position: Vector2, parent: Node2D) -> Sprite2D:
	var house := Sprite2D.new()
	var seed_value := hash("%d_%d_house_%d" % [chunk_coord.x, chunk_coord.y, index])
	house.texture = _house_sprite.generate_texture(seed_value)
	# Art is authored DETAIL_MULTIPLIER times oversized for pixel detail;
	# scaling it back keeps the world footprint unchanged (see
	# docs/concept/art_resolution.md).
	house.scale = Vector2.ONE * ArtResolution.SPRITE_SCALE
	house.position = position
	# Shadow sized from THIS house's rolled size (see
	# ProceduralHouseSprite.size_for) -- houses come in 3 sizes now.
	var size := _house_sprite.size_for(seed_value)
	house.add_child(_drop_shadow.make_shadow(int(size.x * 0.8), size.y * 0.5 - 1.0))
	parent.add_child(house)
	return house


## The settlement's shared well/stall/gate, previously invisible positions
## NPC schedules walked to -- now real, visible props of the village square.
func _build_landmark(landmark_id: String, position: Vector2, parent: Node2D) -> Sprite2D:
	var landmark := Sprite2D.new()
	landmark.texture = _landmark_sprite.generate_texture(landmark_id)
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
## landmarks (see NpcMarker._resolve_location, SettlementGenerator's scope
## note on not modeling per-occupation buildings yet). Far enough out that
## the villager stands clear of the bigger house sprites (up to ~3 tiles
## tall, see ProceduralHouseSprite.SIZES).
const _WORKSPOT_OFFSET_TILES := 4.0


func _build_npc(settlement: Dictionary, index: int, tile_size: int, parent: Node2D) -> NpcMarker:
	var identity = settlement.npcs[index]
	var home_position: Vector2 = settlement.house_positions[index]

	var marker := NpcMarker.new()
	marker.identity = identity
	marker.home_position = home_position
	marker.workspot_position = home_position + Vector2(0, _WORKSPOT_OFFSET_TILES * tile_size)
	marker.landmarks = settlement.landmarks
	marker.position = home_position

	# Villagers use the SAME CharacterView the player does, rather than a
	# hand-assembled torso-plus-head. The old version had neither legs nor
	# arms (reported: "npcs have no legs") and carried its own size
	# constants, which had silently fallen out of sync with CharacterView's
	# and missed the art-resolution pass entirely. Sharing the view means
	# body proportions, resolution and walk animation can only ever come
	# from one place.
	marker.add_child(_drop_shadow.make_shadow(
		int(CharacterView.BODY_SIZE.x * 0.9), CharacterView.BODY_SIZE.y * 0.5 - 1.0
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
