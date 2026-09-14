extends RefCounted

## The catalog of whole-building entities (docs/concept/building.md
## "Buildings are entities; interiors are scenes"). Pure data, the same
## "what is this, never may it go here" framing BuildingPiece keeps for
## the legacy piece model: a building is ONE id with a rectangular
## footprint in tiles, a door on its south edge and a doorstep just outside
## it, drawn as one sprite from one sheet that follows the one asset
## contract every existing building sheet already does (see SHEET_COLUMNS/
## SHEET_ROWS and the ROW_* order below -- blacksmith.png, farmhouse.png,
## sawmill.png, warehouse.png, city_hall.png are all exactly this grid).
##
## Placement (EarthChunkManager.place_building), village layout
## (VillageLayout) and interiors (InteriorTemplates/HouseInteriorView) all
## read this file and never the other way round.

const PixelNoise = preload("res://src/rendering/pixel_noise.gd")
const NpcGenome = preload("res://src/world/npc_genome.gd")

## Every building the game knows how to place, in a fixed order.
const BUILDING_IDS: Array[String] = ["house_small", "house_medium", "house_large"]

## The reserved chunk-modification id every NON-anchor footprint cell
## carries (the anchor cell carries the building id itself, exactly like a
## single-tile placeable does today). Never a building, never placeable by
## hand; exists so every existing "is this cell built on" check
## (`modification_at_global != ""`) keeps answering correctly for the whole
## footprint with no new query anywhere.
const FOOTPRINT_TILE_ID := "building_footprint"

## The asset contract (docs/concept/building.md "Asset contract"): one
## 1536x1024 sheet per building id, eight columns by five lifecycle rows,
## black background, magenta cell dividers.
const SHEET_COLUMNS := 8
const SHEET_ROWS := 5
const ROW_CONSTRUCTION := 0  # eight stages, left to right
const ROW_ACTIVE := 1  # smoke, lit windows -- an eight-frame loop
const ROW_IDLE := 2
const ROW_BURNING := 3
const ROW_RUINED := 4
const CONSTRUCTION_STAGES := SHEET_COLUMNS

## Per-id definition.
##   footprint        width x depth in tiles
##   interior_family  which InteriorTemplates family this building enters into
##   capacity         how many residents it houses
##   labor_hours      construction labor (ConstructionLabor's unit), grows with size
##   cost             item_id -> count, the material a build consumes
## Door/doorstep are derived (see door_of/doorstep_of), sheet paths by id
## (see sheet_of) -- one convention, not per-entry data that could drift.
## Tuned values are illustrative and pinned by ordering in
## test_building_catalog.gd (a bigger house costs and takes more), per this
## project's "tested functions, not eyeballed comments" rule.
const _BUILDINGS := {
	"house_small": {
		"footprint": Vector2i(2, 2), "interior_family": "cottage", "capacity": 1,
		"labor_hours": 6.0, "cost": {"wood": 12},
	},
	"house_medium": {
		"footprint": Vector2i(3, 2), "interior_family": "house", "capacity": 2,
		"labor_hours": 10.0, "cost": {"wood": 20, "stone": 4},
	},
	"house_large": {
		"footprint": Vector2i(4, 3), "interior_family": "manor", "capacity": 3,
		"labor_hours": 16.0, "cost": {"wood": 32, "stone": 10},
	},
}

## Which houses an occupation tends toward -- weighted by repetition, ordered
## plain -> showy, the same convention HouseBlueprint.BLUEPRINT_POOL_BY_
## OCCUPATION established (and the same reasoning: a farmer or fisher keeps a
## small working household, a merchant builds to show). Every real
## NpcIdentity occupation has an entry; an unknown occupation falls back to
## the whole catalog.
const HOUSE_POOL_BY_OCCUPATION := {
	"farmer": ["house_small", "house_small", "house_medium"],
	"fisher": ["house_small", "house_small", "house_medium"],
	"guard": ["house_small", "house_medium"],
	"herbalist": ["house_small", "house_medium", "house_medium"],
	"hunter": ["house_small", "house_small", "house_medium"],
	"nurse": ["house_medium", "house_medium", "house_large"],
	"blacksmith": ["house_medium", "house_medium", "house_large"],
	"merchant": ["house_medium", "house_large", "house_large", "house_large"],
}

## Personality nudge -- HouseBlueprint.choose_blueprint_id's own rule,
## verbatim: a showy dominant trait lands in the pool's upper (larger) half,
## a plain one in its lower half, anything else picks uniformly.
const _SHOWY_TRAITS := {"bold": true, "greedy": true}
const _PLAIN_TRAITS := {"cautious": true, "stoic": true}


static func has_building(building_id: String) -> bool:
	return _BUILDINGS.has(building_id)


## Vector2i.ZERO for an unknown id -- a caller asking "how big" for a typo
## gets a clear zero rather than a crash.
static func footprint_of(building_id: String) -> Vector2i:
	return _BUILDINGS.get(building_id, {}).get("footprint", Vector2i.ZERO)


## The door: on the footprint's bottom (south) row, at the middle of the
## front. Every sheet is drawn south-facing, so this is where the drawn door
## actually is.
static func door_of(building_id: String) -> Vector2i:
	var footprint := footprint_of(building_id)
	return Vector2i(footprint.x / 2, footprint.y - 1)


## The one cell a building is entered from: just south of the door, outside
## the footprint (a road cell in a laid-out village).
static func doorstep_of(building_id: String) -> Vector2i:
	return door_of(building_id) + Vector2i(0, 1)


## Where this building's sheet is expected ("" for an unknown id). Whether
## the file actually exists yet is the renderer's question, not the
## catalog's -- a missing sheet falls back to ProceduralBuildingPlaceholder
## Sprite there.
static func sheet_of(building_id: String) -> String:
	if not has_building(building_id):
		return ""
	return "res://assets/sprites/buildings/%s.png" % building_id


static func interior_family_of(building_id: String) -> String:
	return _BUILDINGS.get(building_id, {}).get("interior_family", "")


static func capacity_of(building_id: String) -> int:
	return _BUILDINGS.get(building_id, {}).get("capacity", 0)


static func labor_hours_of(building_id: String) -> float:
	return _BUILDINGS.get(building_id, {}).get("labor_hours", 0.0)


static func cost_of(building_id: String) -> Dictionary:
	return _BUILDINGS.get(building_id, {}).get("cost", {}).duplicate()


## Every cell the building occupies when its top-left corner stands at
## `origin` -- the door included, the doorstep not. [] for an unknown id.
static func footprint_cells(building_id: String, origin: Vector2i) -> Array:
	var cells := []
	var footprint := footprint_of(building_id)
	for y in footprint.y:
		for x in footprint.x:
			cells.append(origin + Vector2i(x, y))
	return cells


## The one occupancy predicate every seam reads (ground-cover blocking, the
## tree apron, water reclaim, siting): a building's anchor id or the
## footprint marker. A legacy BuildingPiece or a single-tile placeable is
## its own thing and answers false here.
static func occupies(tile_id: String) -> bool:
	return has_building(tile_id) or tile_id == FOOTPRINT_TILE_ID


## Which house a villager builds -- their occupation's own pool, nudged by
## their dominant personality trait, seeded so the same villager always
## builds the same house.
static func choose_house_id(occupation: String, genome: NpcGenome, seed_value: int) -> String:
	var pool: Array = HOUSE_POOL_BY_OCCUPATION.get(occupation, BUILDING_IDS)
	var index := PixelNoise.range_index(seed_value, 7, 11, pool.size())
	var dominant := genome.dominant_trait()
	if _SHOWY_TRAITS.has(dominant):
		var upper_half_size := maxi(pool.size() / 2, 1)
		var upper_roll := PixelNoise.range_index(seed_value, 13, 17, upper_half_size)
		index = maxi(index, pool.size() - upper_half_size + upper_roll)
	elif _PLAIN_TRAITS.has(dominant):
		var lower_half_size := maxi(pool.size() / 2, 1)
		index = mini(index, PixelNoise.range_index(seed_value, 19, 23, lower_half_size))
	return pool[index]
