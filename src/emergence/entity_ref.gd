extends RefCounted

## Canonical entity-reference IDs for the emergence substrate (see
## docs/emergence/00-emergence-architecture.md "Entity model" and
## docs/roadmap.md's "Emergence substrate" section).
##
## A reference is "<kind>:<key>" -- built from whatever deterministic key an
## entity already has (an NPC's seed_value, a settlement's chunk_coord) rather
## than a newly-allocated counter. This is the same "deterministic key, not an
## allocated ID" idiom TreeGenome/CreatureInfo/NpcIdentity already use
## everywhere else, and it means no new counter has to be persisted or
## protected from collision just to hand out entity IDs -- the same key an
## entity is already found by IS its emergence identity.

const _SEPARATOR := ":"


static func for_kind(kind: String, key) -> String:
	return "%s%s%s" % [kind, _SEPARATOR, str(key)]


## A settlement's key is its chunk coordinate -- the same key
## settlement_generator/EarthChunkManager already index settlements by, so
## this needs no new bookkeeping of its own.
static func for_settlement(chunk_coord: Vector2i) -> String:
	return for_kind("settlement", "%d_%d" % [chunk_coord.x, chunk_coord.y])


## An NPC's key is its seed_value -- the same deterministic seed NpcIdentity
## already derives its whole identity from.
static func for_npc(seed_value: int) -> String:
	return for_kind("npc", seed_value)


static func kind_of(entity_id: String) -> String:
	if not entity_id.contains(_SEPARATOR):
		return ""
	return entity_id.split(_SEPARATOR, true, 1)[0]


## Splits on the FIRST colon only, so a key that itself looks colon-adjacent
## (a coordinate pair like "3_-7") is never truncated.
static func key_of(entity_id: String) -> String:
	if not entity_id.contains(_SEPARATOR):
		return ""
	var parts := entity_id.split(_SEPARATOR, true, 1)
	return parts[1] if parts.size() > 1 else ""


static func is_valid(entity_id: String) -> bool:
	return entity_id != "" and kind_of(entity_id) != "" and key_of(entity_id) != ""
