extends RefCounted

## A single settlement building project in progress -- the "Settlement
## construction ledger" from docs/concept/timber_construction.md. Mirrors
## Household's own shape (household.gd) exactly: a deterministic id derived
## from a real, already-known key rather than an allocated counter, plus
## that section's own named field list -- footprint origin, blueprint id,
## assigned household, a status enum, labor_hours_accumulated, reserved
## material.
##
## Keyed off a site (chunk_coord + local footprint origin) and a blueprint
## id, the way Household is keyed off a founder id -- two calls describing
## the same site+blueprint always resolve to the same project id, the same
## "deterministic key, not an allocated ID" idiom EntityRef itself already
## documents, so ConstructionProjectStore needs no counter of its own
## protected from collision.
##
## `blueprint_id` is deliberately a real CraftingRecipeBook recipe id, not a
## second "blueprint" vocabulary -- every real structure this ledger can
## reason about (sagewerk, storage, and any future producer) already has a
## real recipe (see that doc's own "Storage... a real CraftingRecipeBook
## recipe" framing).
##
## `labor_hours_accumulated` is a real field with nothing yet advancing it
## forward over elapsed time -- that is construction_catchup.gd's own job
## (this doc's "Offscreen catch-up" section, still ⬜) and stays out of this
## pass's scope; the field exists so a future caller has somewhere real to
## put it, the same "field is real, nothing advances it yet" honesty this
## project's other in-progress systems already carry.

const EntityRef = preload("res://src/emergence/entity_ref.gd")

enum Status { PLANNED, IN_PROGRESS, COMPLETE, ABANDONED }

var id: String
## The settlement chunk this project's footprint sits in.
var chunk_coord: Vector2i
## The footprint's own local origin cell within that chunk.
var origin: Vector2i
var blueprint_id: String
## The household this structure will belong to on completion (see
## property_id / HouseholdStore.grant_property).
var household_id: String
var status: int = Status.PLANNED
var labor_hours_accumulated: float = 0.0
## item_id -> float already drawn down from local stock and committed to
## THIS project -- mirrors StructureStock's item_id -> count shape, but
## per-project rather than per-structure-instance.
var reserved_material: Dictionary = {}


## The deterministic id for a project at this exact (chunk_coord, origin,
## blueprint_id) -- see this file's own header. Exposed separately from
## for_site so a caller (ConstructionProjectStore.find_project) can look a
## project up by its site alone, without constructing a whole
## ConstructionProject first.
static func id_for_site(a_chunk_coord: Vector2i, a_origin: Vector2i, a_blueprint_id: String) -> String:
	return EntityRef.for_kind(
		"construction_project",
		"%d_%d_%d_%d_%s" % [a_chunk_coord.x, a_chunk_coord.y, a_origin.x, a_origin.y, a_blueprint_id]
	)


static func for_site(
	a_chunk_coord: Vector2i, a_origin: Vector2i, a_blueprint_id: String, a_household_id: String
) -> RefCounted:
	var project = new()
	project.id = id_for_site(a_chunk_coord, a_origin, a_blueprint_id)
	project.chunk_coord = a_chunk_coord
	project.origin = a_origin
	project.blueprint_id = a_blueprint_id
	project.household_id = a_household_id
	return project


## The property id HouseholdStore.grant_property should use once this
## project completes -- this doc's own literal "house_<chunk>_<origin>"
## naming (its "Ownership" section), via the SAME EntityRef.for_kind("house",
## ...) idiom EarthChunkManager.record_settlement_founded_if_new already
## uses for a villager's own house id, so a completed ledger house shares
## the identical id shape as a settlement-generation house rather than a
## second naming scheme.
func property_id() -> String:
	return EntityRef.for_kind("house", "%d_%d_%d_%d" % [chunk_coord.x, chunk_coord.y, origin.x, origin.y])
