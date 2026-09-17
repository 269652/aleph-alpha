extends RefCounted

## One blueprint laid out in planner mode: a site, a thing intended to
## stand there, and when it was planned. See docs/concept/planner_mode.md.
##
## A plan is a RECORD, never a builder (that doc's pillar 1: planning is
## not building). Placing one costs nothing, spends nothing and changes no
## terrain -- every material and labour hour still falls at the moment
## somebody actually raises it, through ConstructionProject/
## ConstructionLabor and BuildingCatalog.cost_of. That split is what keeps
## planner mode from becoming a second, cheaper way to build.
##
## Mirrors ConstructionProject/Household's own shape exactly: a
## deterministic id derived from a real already-known key rather than an
## allocated counter, so two calls describing the same site and blueprint
## always resolve to the same plan and the ledger needs no counter of its
## own to protect from collision.

const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

## Pavement is the Road tier's own laid surface (docs/concept/
## infrastructure.md), not a second kind of road invented for the planner
## -- the same tile a village lays for its streets, so anything already
## true of a street is true of a planned pavement once it is built.
const PAVEMENT_BLUEPRINT_ID := TerrainRenderer.ROAD_TILE_ID

var id: String
## The chunk this plan's footprint sits in.
var chunk_coord: Vector2i
## The footprint's own local origin cell within that chunk.
var origin: Vector2i
var blueprint_id: String
## world_age_seconds when the player laid it down.
var planned_at: float


func _init(
	chunk_coord_value: Vector2i, origin_value: Vector2i, blueprint_id_value: String,
	planned_at_value: float
) -> void:
	chunk_coord = chunk_coord_value
	origin = origin_value
	blueprint_id = blueprint_id_value
	planned_at = planned_at_value
	id = plan_id(chunk_coord_value, origin_value, blueprint_id_value)


## Deterministic from the site and the blueprint, never allocated -- see
## this file's own doc comment.
static func plan_id(chunk_coord_value: Vector2i, origin_value: Vector2i, blueprint_id_value: String) -> String:
	return "%d,%d:%d,%d:%s" % [
		chunk_coord_value.x, chunk_coord_value.y,
		origin_value.x, origin_value.y, blueprint_id_value
	]


## Whether this is a thing the game can already build. Deliberately reads
## the REAL catalogue rather than a planner-specific list: the concept
## doc's "one vocabulary" rule exists so a palette cannot drift from what
## the world can actually raise.
static func is_plannable(blueprint_id_value: String) -> bool:
	if blueprint_id_value == PAVEMENT_BLUEPRINT_ID:
		return true
	return BuildingCatalog.has_building(blueprint_id_value)


## The cells this blueprint would occupy, planted at `origin`.
##
## An unknown blueprint returns EMPTY rather than a guessed single cell:
## silently planning a 1x1 for a typo would put a wireframe somewhere
## nothing can ever be built, which is worse than refusing outright.
static func footprint_cells(blueprint_id_value: String, origin_value: Vector2i) -> Array:
	if blueprint_id_value == PAVEMENT_BLUEPRINT_ID:
		return [origin_value]
	if BuildingCatalog.has_building(blueprint_id_value):
		return BuildingCatalog.footprint_cells(blueprint_id_value, origin_value)
	return []


## What the palette calls it. Pavement is not a BuildingCatalog entry, so
## it carries its own name; everything else uses the catalogue's own.
static func display_name_of(blueprint_id_value: String) -> String:
	if blueprint_id_value == PAVEMENT_BLUEPRINT_ID:
		return "Pavement"
	return BuildingCatalog.display_name_of(blueprint_id_value)
