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
const BuildingLifecycleSheet = preload("res://src/rendering/building_lifecycle_sheet.gd")
const NpcGenome = preload("res://src/world/npc_genome.gd")

## Every HOUSE the game knows how to place, in a fixed order -- the pool
## choose_house_id draws a villager's home from.
const BUILDING_IDS: Array[String] = ["house_small", "house_medium", "house_large"]

## Civic buildings (docs/concept/civic_construction.md, docs/concept/
## village_growth.md): real catalog entities a village raises as a COMMONS
## -- the hall on its own plaza plot, the warehouse a real physical home
## for VillageMarket's already-real settlement stock -- never a home, kept
## out of BUILDING_IDS so no villager is ever handed one to live in.
const CIVIC_BUILDING_IDS: Array[String] = ["city_hall", "warehouse"]

## Production buildings (docs/concept/village_growth.md's growth ladder):
## the works a village raises as it grows -- the sawmill at the forest
## edge first, since timber is the input every later building is made of,
## then the farmhouse, the blacksmith and finally the brewery, the one
## rung raised for comfort rather than survival. Also never homes; the
## trade they house is worked from, not lived in.
const PRODUCTION_BUILDING_IDS: Array[String] = ["sawmill", "farmhouse", "blacksmith", "brewery"]

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
	# The town hall (CIVIC_BUILDING_IDS): the same wood 20 + stone 10 the
	# legacy single-tile city_hall recipe already charges (CraftingRecipeBook
	# -- one price, not two), more labour than any house; nobody lives in
	# it. Drawn from city_hall.png, which already follows the sheet contract.
	"city_hall": {
		"footprint": Vector2i(4, 3), "interior_family": "hall", "capacity": 0,
		"labor_hours": 45.0, "cost": {"wood": 20, "stone": 10},
	},
	# The growth ladder (docs/concept/village_growth.md). Every one of
	# these is priced ONLY in wood/stone/plant_fibre -- the exact three
	# materials SettlementGathering's spare hands actually gather -- since
	# a rung priced in anything else could never be raised by a village on
	# its own (test-pinned, test_building_catalog.gd). Costs rise strictly
	# along the ladder (sawmill < farmhouse < warehouse < city_hall <
	# blacksmith < brewery): a village pays more for each rung it grows
	# into. labor_hours is always ConstructionLabor.HOURS_PER_UNIT_MATERIAL
	# times the total material, so the rising building's own construction
	# sprite and the ledger agree on how far along it is.
	#
	# The sawmill: the village's first works, sited at the forest edge
	# rather than on the street (VillageLayout.industry_plot) because that
	# is where the timber is. Cheapest rung -- a shed, a saw pit and a log
	# deck, not an enclosed hall.
	"sawmill": {
		"footprint": Vector2i(3, 2), "interior_family": "workshop", "capacity": 0,
		"labor_hours": 30.0, "cost": {"wood": 16, "stone": 4},
	},
	# The farmhouse: the village's own food works (docs/concept/
	# npc_farm_production.md's Farm, raised as a real building rather than
	# a single tile). Timber frame, a stone footing, fibre for thatch and
	# lashing -- the cheapest rung that needs all three materials.
	"farmhouse": {
		"footprint": Vector2i(3, 2), "interior_family": "farmstead", "capacity": 0,
		"labor_hours": 36.0, "cost": {"wood": 14, "stone": 4, "plant_fibre": 6},
	},
	# The warehouse: a real physical home for VillageMarket's already-real
	# settlement stock (civic_construction.md's own Granary). Mostly
	# timber and thatch -- volume to enclose, but no forge and no civic
	# masonry -- so it lands under the hall.
	"warehouse": {
		"footprint": Vector2i(4, 3), "interior_family": "hall", "capacity": 0,
		"labor_hours": 42.0, "cost": {"wood": 22, "plant_fibre": 6},
	},
	# The blacksmith: the first rung that needs stone in real quantity --
	# a forge, a hearth and a chimney are masonry, not carpentry, which is
	# exactly why it sits above the civic hall in price.
	"blacksmith": {
		"footprint": Vector2i(3, 2), "interior_family": "workshop", "capacity": 0,
		"labor_hours": 51.0, "cost": {"wood": 18, "stone": 16},
	},
	# The brewery: the dearest rung, and the only one raised for comfort
	# rather than survival -- a masonry mash floor, a timber-framed hall
	# over it, and fibre for the filtering. A village only builds this
	# once everything it actually needs already stands.
	"brewery": {
		"footprint": Vector2i(3, 3), "interior_family": "workshop", "capacity": 0,
		"labor_hours": 57.0, "cost": {"wood": 22, "stone": 12, "plant_fibre": 4},
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


## A readable name per building, for a readout that has to title itself
## (HousePanel, EarthChunkManager.household_report_at). Catalog data
## because that is what it is: a house has no ItemCatalog entry to borrow a
## display name from, and must not be given one -- an item catalog entry is
## exactly what would put a house on a crafting bench.
const _DISPLAY_NAMES := {
	"house_small": "Cottage",
	"house_medium": "House",
	"house_large": "Manor",
	"city_hall": "City Hall",
	"warehouse": "Warehouse",
	"sawmill": "Sawmill",
	"farmhouse": "Farmhouse",
	"blacksmith": "Smithy",
	"brewery": "Brewery",
}


## The readable name, or a title-cased fallback for an id with no entry --
## a readout that meets an unknown building shows something printable
## rather than nothing.
static func display_name_of(building_id: String) -> String:
	return _DISPLAY_NAMES.get(building_id, building_id.capitalize())


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


# -- variant sheets ------------------------------------------------------
#
# A second, SIMPLER kind of sheet, for buildings there are many real drawn
# versions of: a plain grid of complete buildings, one per cell, black
# background, NO magenta dividers and no lifecycle rows at all. A finished
# building picks one cell by its own seed, so a street of cottages reads as
# a street of DIFFERENT cottages rather than one house repeated down the
# road -- which is what a real village looks like and what one sheet of 25
# hand-drawn variants is for.
#
# Deliberately NOT a replacement for the lifecycle sheet contract above. A
# variant sheet has no construction, burning or ruined rows, so a RISING
# building still draws from the lifecycle sheet's construction row exactly
# as before (EarthChunkManager._sync_construction_site); only the FINISHED
# building prefers a variant (see finished_sheet_for). Purely additive: a
# building with no variant sheet, or one whose file has not been dropped in
# yet, is untouched and falls through the same
# lifecycle-sheet-then-procedural-placeholder chain it always did.

## The supplied sheet's own grid: 25 cottages, five by five.
const VARIANT_SHEET_COLUMNS := 5
const VARIANT_SHEET_ROWS := 5

## Which building ids have a real variant sheet.
##
## All three village HOUSES share the first-tier cottage sheet, and that is
## deliberate rather than lazy: no house had a lifecycle sheet of its own
## at all, so every village house drew as a procedural box -- declaring the
## cottage art for only the smallest tier would leave a street half
## beautiful cottages and half boxes, which reads worse than either
## extreme. The scaler sizes each cell to its own footprint WITHOUT
## distorting it (footprint_frame_texture scales height by the same factor
## as width), so a medium or large house is simply a bigger cottage, and a
## different seed picks a different one of the 25 anyway. When grander art
## for those tiers lands they get their own entries here and nothing else
## changes.
##
## Nothing that is not a home has one: a town hall, a mill or a brewery
## drawn as a cottage would be drawing the wrong building, and each of
## those already has its own real lifecycle sheet.
const _VARIANT_SHEETS := {
	"house_small": "res://assets/sprites/buildings/house_1.png",
	"house_medium": "res://assets/sprites/buildings/house_1.png",
	"house_large": "res://assets/sprites/buildings/house_1.png",
}


## This building's variant sheet, or "" for one that has none. Whether the
## file actually exists yet is the renderer's question, not the catalog's
## -- a missing sheet falls back through finished_sheet_for's own caller,
## exactly like a missing lifecycle sheet already does.
static func variant_sheet_of(building_id: String) -> String:
	return _VARIANT_SHEETS.get(building_id, "")


## Which cell of the variant grid this building draws from, as
## (column, row) -- deterministic from the building's own seed, so a house
## always looks like itself across reloads. Column and row are drawn from
## independent hashes of the same seed so the pair spreads over the whole
## grid rather than walking a diagonal (test-pinned: all 25 are reachable).
static func variant_cell_for(building_id: String, seed_value: int) -> Vector2i:
	var columns := VARIANT_SHEET_COLUMNS
	var rows := VARIANT_SHEET_ROWS
	if variant_sheet_of(building_id) == "":
		return Vector2i.ZERO
	return Vector2i(
		PixelNoise.range_index(seed_value, 29, 31, columns),
		PixelNoise.range_index(seed_value, 37, 41, rows)
	)


## Every sheet a FINISHED building of this id and seed could be drawn
## from, BEST FIRST: `{path, columns, rows, row, column, grid}`. The
## renderer walks the chain and takes the first whose file is really on
## disk, so declaring art that has not been dropped in yet changes
## nothing.
##
## For a house that is: its own lifecycle VARIATION sheet's idle cell
## (house_1_1.png .. house_1_5.png -- the same house it was while it was
## rising, see BuildingLifecycleSheet), then the flat 25-cottage variant
## sheet, then the old 8x5 sheet's idle row. Everything else has only the
## last of those.
##
## `grid` says how that sheet's cells are found, because all three kinds
## are now real: "even" divides the canvas, "gutters" finds dark bands
## between cells, "dividers" finds the bands between magenta lines (see
## VariantSheetGrid).
static func finished_sheet_chain(building_id: String, seed_value: int) -> Array:
	var chain: Array = []
	var variation := BuildingLifecycleSheet.sheet_for(building_id, seed_value)
	if variation != "":
		var idle := BuildingLifecycleSheet.idle_cell_for(seed_value)
		chain.append({
			"path": variation,
			"columns": BuildingLifecycleSheet.COLUMNS, "rows": BuildingLifecycleSheet.ROWS,
			"row": idle.y, "column": idle.x, "grid": "dividers",
		})
	var variant_sheet := variant_sheet_of(building_id)
	if variant_sheet != "":
		var cell := variant_cell_for(building_id, seed_value)
		chain.append({
			"path": variant_sheet, "columns": VARIANT_SHEET_COLUMNS, "rows": VARIANT_SHEET_ROWS,
			"row": cell.y, "column": cell.x, "grid": "gutters",
		})
	chain.append({
		"path": sheet_of(building_id), "columns": SHEET_COLUMNS, "rows": SHEET_ROWS,
		"row": ROW_IDLE, "column": 0, "grid": "even",
	})
	return chain


## The best of that chain. One function, so the live building node and any
## other consumer can never disagree about which picture a finished
## building has.
static func finished_sheet_for(building_id: String, seed_value: int) -> Dictionary:
	return finished_sheet_chain(building_id, seed_value)[0]


## The same for a building that is still RISING, at `progress` in [0, 1].
##
## A house walks its own variation's 24 real build frames -- foundation,
## frames, construction -- so it rises as the house it is going to be.
## Everything else keeps the old 8x5 sheet's single construction row, eight
## stages left to right, exactly as before.
##
## The flat variant sheet never appears here and must not: it draws 25
## FINISHED cottages and no scaffold at all.
static func construction_sheet_chain(building_id: String, seed_value: int, progress: float) -> Array:
	var chain: Array = []
	var variation := BuildingLifecycleSheet.sheet_for(building_id, seed_value)
	if variation != "":
		var cell := BuildingLifecycleSheet.build_cell_for(progress)
		chain.append({
			"path": variation,
			"columns": BuildingLifecycleSheet.COLUMNS, "rows": BuildingLifecycleSheet.ROWS,
			"row": cell.y, "column": cell.x, "grid": "dividers",
		})
	chain.append({
		"path": sheet_of(building_id), "columns": SHEET_COLUMNS, "rows": SHEET_ROWS,
		"row": ROW_CONSTRUCTION, "column": construction_stage_for(progress), "grid": "even",
	})
	return chain


static func construction_sheet_for(building_id: String, seed_value: int, progress: float) -> Dictionary:
	return construction_sheet_chain(building_id, seed_value, progress)[0]


## Where this building's sheet is expected ("" for an unknown id). Whether
## the file actually exists yet is the renderer's question, not the
## catalog's -- a missing sheet falls back to ProceduralBuildingPlaceholder
## Sprite there.
static func sheet_of(building_id: String) -> String:
	if not has_building(building_id):
		return ""
	return "res://assets/sprites/buildings/%s.png" % building_id


## The construction row's stage column for a project `progress` in [0, 1]
## -- the sheet contract's own formula (docs/concept/building.md "Building
## sheets": clampi(floori(progress * 8), 0, 7)), so a rising building
## shows scaffold at 0 and the roofed shell just before it completes.
static func construction_stage_for(progress: float) -> int:
	return clampi(floori(progress * CONSTRUCTION_STAGES), 0, CONSTRUCTION_STAGES - 1)


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


## Whether a real building (its anchor or any footprint cell) stands on
## `cell` or any of its eight neighbours -- BuildingPiece.touches_piece's
## own tree-apron rule (docs/concept/building.md "Placement rules"),
## generalized to whole-building entities: a house keeps a one-cell apron
## clear of trees, so no tree ever stands on its doorstep, whether the
## house is a legacy piece structure or a whole-building entity. Every
## real tree-apron seam (TreeRenderer.spawn_trees, EarthChunkManager.
## _can_root_at, the village stamp's own clearing) checks BOTH this and
## BuildingPiece.touches_piece, never just one.
static func touches_building(modifications: Dictionary, cell: Vector2i) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if occupies(modifications.get(cell + Vector2i(dx, dy), "")):
				return true
	return false


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
