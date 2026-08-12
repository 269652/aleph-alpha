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
## Scope note: house positions are single-tile anchors (rendered as one
## structure sprite each, see VillageRenderer), not multi-tile footprints via
## BuildingBlueprint -- a deliberate Phase 1 simplification, see
## docs/progress.md's NPC section.

const NpcIdentity = preload("res://src/world/npc_identity.gd")

## Fixed villager count per settlement -- small and constant for now rather
## than population-simulated (see docs/concept/npc.md's lifecycle/aging,
## still unstarted).
const POPULATION := 5

## Roughly 1-in-this-many habitable chunks hosts a settlement -- sparse, so
## villages read as discoverable landmarks rather than carpeting the map.
const SETTLEMENT_CHANCE_DENOMINATOR := 30

## Villages need dry, walkable land -- never afloat or on a cliff face.
const _UNINHABITABLE_BIOMES := {"ocean": true, "mountain": true}

## Houses ring the village center at this radius; the 3 shared landmarks sit
## closer in, at the center itself.
const _HOUSE_RING_RADIUS_TILES := 6
const _LANDMARK_OFFSETS_TILES := {
	"well": Vector2i(0, 0),
	"stall": Vector2i(2, 0),
	"gate": Vector2i(-2, 0),
}


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
func generate_settlement(
	chunk_coord: Vector2i, chunk_origin_tiles: Vector2i, chunk_size: int, tile_size: int
) -> Dictionary:
	var center_tile := chunk_origin_tiles + Vector2i(chunk_size / 2, chunk_size / 2)
	var center_pos := Vector2((center_tile.x + 0.5) * tile_size, (center_tile.y + 0.5) * tile_size)

	var landmarks := {}
	for landmark in _LANDMARK_OFFSETS_TILES:
		var offset: Vector2i = _LANDMARK_OFFSETS_TILES[landmark]
		landmarks[landmark] = center_pos + Vector2(offset.x * tile_size, offset.y * tile_size)

	var house_positions: Array[Vector2] = []
	var npcs: Array[NpcIdentity] = []
	for i in POPULATION:
		var seed_value := hash("%d_%d_villager_%d" % [chunk_coord.x, chunk_coord.y, i])
		npcs.append(NpcIdentity.new(seed_value))
		house_positions.append(_house_position(center_pos, tile_size, i))

	return {"house_positions": house_positions, "landmarks": landmarks, "npcs": npcs}


func _house_position(center_pos: Vector2, tile_size: int, index: int) -> Vector2:
	var angle := float(index) / float(POPULATION) * TAU
	var radius_px := _HOUSE_RING_RADIUS_TILES * tile_size
	return center_pos + Vector2(cos(angle), sin(angle)) * radius_px
