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

## The buildings a village raises ON its own laid paving -- the only ones
## whose footprint is cobbled up to its walls rather than showing the
## ground it was raised on (TerrainRenderer.building_ground_tile_for).
##
## Exactly one, and it is not a choice so much as a reading of what the
## village already does: the civic plot IS the paved square, since
## EarthChunkManager._civic_plot_origin_for refuses a plot whose every
## footprint cell is not already a road tile. Every other placement path
## refuses a modified footprint outright -- can_build_house_from_blueprint
## (road_allowed false), _is_clear_settlement_site (unmodified only),
## VillageLayout._street_plot_fits (never the square) -- so no other
## building can ever be standing on paving to begin with.
##
## Reported with three farmhouses in shot, each on its own grey pad: "make
## the farm houses ground grass instead of cobblestone... only buildings
## placed on pavement like the city hall should get the pavement bg".
## Cross-pinned against VillageLayout.CIVIC_BUILDING_ID in
## test_building_ground.gd, so the list and the plot the square reserves
## can never drift apart.
const PAVED_PLOT_BUILDING_IDS: Array[String] = ["city_hall"]


## Whether a village ever raises `building_id` on its own laid paving.
static func stands_on_laid_paving(building_id: String) -> bool:
	return PAVED_PLOT_BUILDING_IDS.has(building_id)

## Production buildings (docs/concept/village_growth.md's growth ladder):
## the works a village raises as it grows -- the sawmill at the forest
## edge first, since timber is the input every later building is made of,
## then the farmhouse, the blacksmith and finally the brewery, the one
## rung raised for comfort rather than survival. Also never homes; the
## trade they house is worked from, not lived in.
##
## The fisher's hut is one of these and is NOT a rung: it is raised over a
## fisher's own dug pond by the pond pass itself (docs/concept/
## village_ponds.md, "The hut on the bank"), the way a farmhouse stands
## over its beds, rather than by the ladder a village climbs. The ladder
## keeps its own list (VillageGrowth.LADDER_BUILDING_IDS), which is what
## lets these two answers differ without either lying.
const PRODUCTION_BUILDING_IDS: Array[String] = [
	"sawmill", "farmhouse", "blacksmith", "brewery", "fisher_hut",
]

## Buildings a settlement's own TIER entitles it to (docs/concept/
## settlement_charter.md): a place may not simply decide to have one, it
## has to BE a town or a city first. Never a home either, and never on the
## growth ladder -- the ladder is what a village climbs to become the kind
## of place that may raise these.
##
## See SettlementCharter.MIN_TIER_BY_BUILDING for which tier each wants.
## That table lives there rather than here because it is a rule about
## SETTLEMENTS, and this file knows nothing about settlements.
const CHARTERED_BUILDING_IDS: Array[String] = ["trade_hall", "mage_guild"]


## Every building this catalog knows, in one list.
##
## Read off the entries themselves rather than by concatenating the four
## lists above, so an invariant written against it cannot be escaped by a
## new entry somebody forgot to add to a list -- which is exactly what a
## hand-maintained union lets happen (test-pinned both ways: every listed
## id is here, and every id here is a real entry).
static func all_building_ids() -> Array:
	return _BUILDINGS.keys()

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

## Sheets that are NOT eight columns wide.
##
## MEASURED off each sheet's own magenta divider lines
## (tools/probe_building_lifecycle_sheet.gd): sawmill.png, warehouse.png,
## city_hall.png, blacksmith.png and brewery.png are all eight, and
## farmhouse.png is SIX. Its art is therefore on a 256px pitch, and reading
## it at 192 cut 64px off every farmhouse -- rendered
## (tools/probe_building_idle_crops.gd), the tree and the left-hand third of
## the farmyard, with the house itself sitting off-centre in its own frame.
##
## Pinned by test_every_contract_sheet_is_read_with_the_column_count_its_
## art_is_drawn_on, which reads each sheet's real columns rather than
## trusting this table.
const _SHEET_COLUMNS_BY_ID := {"farmhouse": 6}

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
		"footprint": Vector2i(2, 2), "interior_family": "cottage", "capacity": 1, "storage": 20,
		"labor_hours": 6.0, "cost": {"wood": 12},
	},
	"house_medium": {
		"footprint": Vector2i(3, 2), "interior_family": "house", "capacity": 2, "storage": 30,
		"labor_hours": 10.0, "cost": {"wood": 20, "stone": 4},
	},
	# Asked directly, with the manor art: "cottage 2x2; house 3x2; manor 3x3".
	# Was 4x3 -- wider than it was deep, and as wide as the town hall, which
	# is the shape the real manor illustration then had to be squeezed into.
	"house_large": {
		"footprint": Vector2i(3, 3), "interior_family": "manor", "capacity": 3, "storage": 40,
		"labor_hours": 16.0, "cost": {"wood": 32, "stone": 10},
	},
	# The town hall (CIVIC_BUILDING_IDS): the same wood 20 + stone 10 the
	# legacy single-tile city_hall recipe already charges (CraftingRecipeBook
	# -- one price, not two), more labour than any house; nobody lives in
	# it. Drawn from city_hall.png, which already follows the sheet contract.
	"city_hall": {
		"footprint": Vector2i(4, 3), "interior_family": "hall", "capacity": 0, "storage": 0,
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
		"footprint": Vector2i(3, 2), "interior_family": "workshop", "capacity": 0, "storage": 60,
		"labor_hours": 30.0, "cost": {"wood": 16, "stone": 4},
	},
	# The farmhouse: the village's own food works (docs/concept/
	# npc_farm_production.md's Farm, raised as a real building rather than
	# a single tile). Timber frame, a stone footing, fibre for thatch and
	# lashing -- the cheapest rung that needs all three materials.
	"farmhouse": {
		"footprint": Vector2i(3, 2), "interior_family": "farmstead", "capacity": 0, "storage": 60,
		"labor_hours": 36.0, "cost": {"wood": 14, "stone": 4, "plant_fibre": 6},
	},
	# The warehouse: a real physical home for VillageMarket's already-real
	# settlement stock (civic_construction.md's own Granary). Mostly
	# timber and thatch -- volume to enclose, but no forge and no civic
	# masonry -- so it lands under the hall.
	"warehouse": {
		# Three wide, not four: reported live ("should be only 3 tiles wide
		# not 4"), and it matches the art -- warehouse.png's columns are on
		# an exact 192px pitch, and footprint_frame_texture scales a frame
		# by its WIDTH (tile_size * footprint_width), so a warehouse
		# claiming four tiles was drawn a third wider than its own plot.
		# Pinned end to end by
		# test_a_finished_warehouse_is_drawn_exactly_three_tiles_across.
		"footprint": Vector2i(3, 3), "interior_family": "hall", "capacity": 0, "storage": 240,
		"labor_hours": 42.0, "cost": {"wood": 22, "plant_fibre": 6},
	},
	# The blacksmith: the first rung that needs stone in real quantity --
	# a forge, a hearth and a chimney are masonry, not carpentry, which is
	# exactly why it sits above the civic hall in price.
	"blacksmith": {
		"footprint": Vector2i(3, 2), "interior_family": "workshop", "capacity": 0, "storage": 60,
		"labor_hours": 51.0, "cost": {"wood": 18, "stone": 16},
	},
	# The brewery: the dearest rung, and the only one raised for comfort
	# rather than survival -- a masonry mash floor, a timber-framed hall
	# over it, and fibre for the filtering. A village only builds this
	# once everything it actually needs already stands.
	"brewery": {
		"footprint": Vector2i(3, 3), "interior_family": "workshop", "capacity": 0, "storage": 60,
		"labor_hours": 57.0, "cost": {"wood": 22, "stone": 12, "plant_fibre": 4},
	},
	# The chartered buildings (CHARTERED_BUILDING_IDS, docs/concept/
	# settlement_charter.md). Priced in the SAME three materials every
	# other rung is -- the exact three SettlementGathering gathers -- on
	# purpose: a charter is ONE gate, and pricing these in something a
	# settlement cannot get would be a second, hidden gate behind it, so a
	# city that earned its charter still could not raise its own guild
	# hall. They cost strictly more than anything anybody may raise
	# unchartered, because they are what a place builds when it finally
	# can (both test-pinned).
	#
	# The trade hall: the house of the `guild` institutions InstitutionStore
	# already forms out of repeated fulfilled contracts, and the natural
	# home of the relief chest docs/concept/village_estates.md hangs off
	# one. Deep storage because that is what a chest in a hall is.
	#
	# NOT "guild_hall", which is already taken by a 7x7 piece-built PLAYER
	# house blueprint (HouseBlueprint.BLUEPRINTS). Two different things
	# sharing one id is how a recipe book ends up with a duplicate key,
	# which is exactly how this was found.
	"trade_hall": {
		"footprint": Vector2i(3, 3), "interior_family": "hall", "capacity": 0, "storage": 180,
		"labor_hours": 72.0, "cost": {"wood": 24, "stone": 18, "plant_fibre": 6},
	},
	# The mage guild: the compile station docs/concept/magic.md has carried
	# as an open question since it was written ("exact station-tier
	# thresholds for compiling"). The dearest thing in the catalog, and the
	# only one a hamlet or a town may never have at any price.
	"mage_guild": {
		"footprint": Vector2i(3, 3), "interior_family": "hall", "capacity": 0, "storage": 60,
		"labor_hours": 93.0, "cost": {"wood": 28, "stone": 26, "plant_fibre": 8},
	},
	# The fisher's works, standing over their pond the way a farmhouse
	# stands over its beds (docs/concept/village_ponds.md, "The hut on the
	# bank"). Reported live with a screenshot of a dug, fenced, EMPTY
	# enclosure: "it's missing a fisher hut (use farmhouse sprite until
	# illustration exists)".
	#
	# Priced, sized and stocked as the farmhouse it is drawn as: the same
	# 3x2 works beside the same 3x2 patch of worked ground, in the same
	# three materials a village can actually gather. `draws_as` is the
	# whole of the borrowed art -- drop fisher_hut.png in and this one line
	# comes out again, with nothing else to change (see draws_as_of).
	"fisher_hut": {
		"footprint": Vector2i(3, 2), "interior_family": "farmstead", "capacity": 0, "storage": 60,
		"labor_hours": 36.0, "cost": {"wood": 14, "stone": 4, "plant_fibre": 6},
		"draws_as": "farmhouse",
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
	# A sawyer keeps a small working household, like the other trades worked
	# out of doors. Added when test_every_occupation_has_a_pool_and_can_
	# choose_more_than_one_house caught the gap: "lumberjack" reached
	# NpcIdentity.OCCUPATIONS with the sawmill and never got a pool here, so
	# every one of them fell through to the whole catalog.
	"lumberjack": ["house_small", "house_small", "house_medium"],
	# And a carter the same, for the same reason and caught by the same test
	# -- "carter" reached NpcIdentity.OCCUPATIONS with the store round and
	# never got a pool here, so every one of them fell through to the whole
	# catalog, town hall and all.
	"carter": ["house_small", "house_small", "house_medium"],
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
	"trade_hall": "Trade Hall",
	"mage_guild": "Mage Guild",
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
## house_1.png is a page of 25 COTTAGES. All three tiers used to fall back
## to it, which was deliberate while it was the only house art there was:
## declaring it for the smallest tier alone would have left a street half
## beautiful cottages and half boxes. That ended when cottage_* and manor_*
## landed (2026-09-19) -- asked for directly: *"please fix that villages use
## scaled houses for those and use the real illustrations"*.
##
## So the MANOR is off this list. It has manor art of its own now, and a
## manor whose own sheet is missing must fall through to the honest
## procedural placeholder rather than to a picture of a cottage, which is
## precisely what "villages use scaled houses" described. The two smaller
## tiers keep it: for a cottage this page IS cottage art, and the middle
## tier is the one house_1.png was drawn beside.
##
## Nothing that is not a home has one: a town hall, a mill or a brewery
## drawn as a cottage would be drawing the wrong building, and each of
## those already has its own real lifecycle sheet.
const _VARIANT_SHEETS := {
	"house_small": "res://assets/sprites/buildings/house_1.png",
	"house_medium": "res://assets/sprites/buildings/house_1.png",
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


## The yard a building stands in, drawn BEHIND it (see docs/concept/
## building.md, "A building's own yard, drawn behind it"). One sheet of
## whole scenes per building id, each a finished yard at the plot's own
## shape -- a woodpile, a barrel, a bench, a beaten path -- none of which is
## in the building's own sheet, which draws only the house.
##
## Per building id, so declaring one for the farmhouse costs nothing
## anywhere else: every other building answers {} and draws exactly what it
## drew before.
## Each sheet's cells must be the SHAPE of the plot the building stands on,
## because a yard is scaled to the plot's whole rect (see
## IllustratedStructureSprite.plot_background_texture): the farmhouse's
## 1536x1024 cuts into 512x341 cells at 1.50 for its 3x2 plot, the cottage's
## 1254x1254 into 418x418 at 1.00 for its 2x2. Pinned by
## test_every_declared_yard_is_the_shape_of_the_plot_it_fills, so a sheet
## declared against the wrong plot is caught here rather than in a
## screenshot.
const _BACKGROUND_SHEETS := {
	"farmhouse": {
		"path": "res://assets/sprites/buildings/farmhouse_bg_overlay.png",
		"columns": 3, "rows": 3,
	},
	# *"I also added bg overlays for cottages ..."* -- nine square garden
	# scenes for the 2x2 plot a cottage stands on. A cottage is the one
	# building with both a variant sheet and a yard, so a street of them
	# carries 25 houses x 9 gardens rather than nine repeats.
	"house_small": {
		"path": "res://assets/sprites/buildings/cottage_bg_overlay.png",
		"columns": 3, "rows": 3,
	},
}


## Which yard THIS building stands in -- chain-shaped
## ({path, columns, rows, row, column, grid}) so the renderer can hand it to
## footprint_frame_texture unchanged, or {} for a building with no yard art.
##
## Seeded from the building's own seed, the same one its house variant comes
## from, but through its OWN salts: sharing them would tie the two axes
## together, so a given cottage would arrive with the same yard every time
## instead of the yard and the house varying independently. Pinned by
## test_the_yard_does_not_move_in_lockstep_with_the_house_variant.
##
## Two independent hashes rather than one index into nine, for the same
## reason variant_cell_for uses two: one hash split into a row and a column
## walks a diagonal of the grid instead of covering it.
static func background_sheet_for(building_id: String, seed_value: int) -> Dictionary:
	# A building drawn as another (draws_as) stands in that one's yard as
	# well: what is borrowed is the whole picture, the house AND the ground
	# it stands in. Asked for directly once the fisher's hut was up beside
	# its pond -- "the fisher hut should get a yard too" -- because a
	# farmhouse in a yard beside a hut on bare plot reads as one building
	# finished and the other forgotten. Its OWN seed still picks WHICH
	# yard, so the hut and the farmhouse up the street are different
	# pictures.
	var declared := building_id
	if not _BACKGROUND_SHEETS.has(declared):
		declared = draws_as_of(building_id)
	if not _BACKGROUND_SHEETS.has(declared):
		return {}
	var sheet: Dictionary = _BACKGROUND_SHEETS[declared]
	var columns := int(sheet["columns"])
	var rows := int(sheet["rows"])
	return {
		"path": String(sheet["path"]),
		"columns": columns, "rows": rows,
		"column": PixelNoise.range_index(seed_value, 53, 59, columns),
		"row": PixelNoise.range_index(seed_value, 61, 67, rows),
		# An even grid: the sheet is a plain 3x3 with no dividers and no
		# printed labels, so its cells really are on a pitch.
		"grid": "even",
	}


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
		var idle := BuildingLifecycleSheet.idle_cell_for(building_id, seed_value)
		var idle_grid := BuildingLifecycleSheet.grid_for(building_id)
		chain.append({
			"path": variation,
			"columns": int(idle_grid["columns"]), "rows": int(idle_grid["rows"]),
			# The sheet's own, not one kind for all of them: cottage_*/
			# manor_* have no divider line to cut on (see
			# BuildingLifecycleSheet._GRID_8X5).
			"row": idle.y, "column": idle.x,
			"grid": String(idle_grid.get("grid", "dividers")),
		})
	var variant_sheet := variant_sheet_of(building_id)
	if variant_sheet != "":
		var cell := variant_cell_for(building_id, seed_value)
		chain.append({
			"path": variant_sheet, "columns": VARIANT_SHEET_COLUMNS, "rows": VARIANT_SHEET_ROWS,
			"row": cell.y, "column": cell.x, "grid": "gutters",
		})
	chain.append({
		"path": sheet_of(building_id), "columns": sheet_columns_of(building_id), "rows": SHEET_ROWS,
		"row": ROW_IDLE, "column": 0, "grid": "even",
	})
	# The borrowed link, if this building has no art of its own yet -- read
	# with the SHEET's own grid, never the borrower's (see draws_as_of).
	var borrowed := draws_as_of(building_id)
	if borrowed != "":
		chain.append({
			"path": sheet_of(borrowed), "columns": sheet_columns_of(borrowed), "rows": SHEET_ROWS,
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
		var cell := BuildingLifecycleSheet.build_cell_for(building_id, progress)
		var build_grid := BuildingLifecycleSheet.grid_for(building_id)
		chain.append({
			"path": variation,
			"columns": int(build_grid["columns"]), "rows": int(build_grid["rows"]),
			"row": cell.y, "column": cell.x, "grid": "dividers",
		})
	chain.append({
		"path": sheet_of(building_id), "columns": sheet_columns_of(building_id), "rows": SHEET_ROWS,
		"row": ROW_CONSTRUCTION, "column": construction_stage_for(progress, building_id), "grid": "even",
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


## How many columns this building's own contract sheet really has -- eight
## for every sheet but farmhouse.png's six (see _SHEET_COLUMNS_BY_ID).
static func sheet_columns_of(building_id: String) -> int:
	return _SHEET_COLUMNS_BY_ID.get(building_id, SHEET_COLUMNS)


## Whose picture this building borrows until its own is drawn -- "" for
## every building that has its own art (docs/concept/building.md, "Asset
## contract"). A borrowed sheet is the LAST link of the chain, behind the
## building's own, so the day the real file lands it wins with no code
## change; removing the `draws_as` line is then pure tidying.
static func draws_as_of(building_id: String) -> String:
	return String(_BUILDINGS.get(building_id, {}).get("draws_as", ""))


## The construction row's stage column for a project `progress` in [0, 1]
## -- the sheet contract's own formula (docs/concept/building.md "Building
## sheets": clampi(floori(progress * 8), 0, 7)), so a rising building
## shows scaffold at 0 and the roofed shell just before it completes.
## `building_id` names the sheet, because a sheet with fewer columns has
## fewer stages -- farmhouse.png's six, not the eight every other one has,
## and eight stages read off six cells would walk two of them off the end of
## the row. Omitting it keeps the contract's own eight, for a caller that
## only means "the eight-stage row".
static func construction_stage_for(progress: float, building_id: String = "") -> int:
	var stages := sheet_columns_of(building_id) if building_id != "" else CONSTRUCTION_STAGES
	return clampi(floori(progress * stages), 0, stages - 1)


static func interior_family_of(building_id: String) -> String:
	return _BUILDINGS.get(building_id, {}).get("interior_family", "")


## How much of its plot a building's picture leaves as AIR on each side.
##
## Reported live with a screenshot of three cottages in a row: "make the
## cottages a bit smaller and add a padding so they have a gap between them
## and the top doesn't get clipped".
##
## The slicer was not the problem, which is worth recording because it was
## the obvious suspect. Measured on the real sheets, every finished cottage
## frame has ZERO transparent pixels on all four edges -- the cell bands
## are cut tight to the art by construction (VariantSheetGrid) -- and that
## tight crop was then scaled to EXACTLY the plot width. So two houses on
## neighbouring plots touched at the pixel with no street between them, and
## a roof that reaches well above its own plot ran straight into whatever
## stood north of it.
##
## A share rather than a fixed number of tiles, so the air scales with the
## building: a manor stands in proportionally as much ground as a cottage
## does. The trade-off is deliberate -- a bigger building gets a wider gap,
## which reads as a bigger house standing in more of its own land rather
## than as an inconsistent street.
##
## Pinned from both sides by test_building_catalog.gd against what it
## PRODUCES, never as a number somebody liked: two houses on adjacent plots
## must stand at least a quarter of a tile apart (under that it is a seam,
## not a gap, at the size a tile is really drawn), and a building must
## still cover more than three quarters of its own plot (under that it
## stops reading as a building on that ground and starts reading as a model
## of one).
const PLOT_MARGIN_SHARE := 0.09

## A building drawn at less of its plot than the margin above allows, because
## of what the building IS rather than because of the plot it stands on.
##
## Asked directly, with the street in shot: *"also scale down cottage to be
## smaller than house"*. Measured before changing anything
## (tools/probe_building_fit.gd): a cottage drew 26.0 x 26.0 world px against
## a house's 39.5 x 24.0 -- the SMALLEST tier was the tallest building on the
## street. Both are drawn at the same share of their own plot width and the
## plots differ only in width (2x2 against 3x2), so the whole misorder comes
## from the art's aspect: a cottage is drawn square, a house low and wide.
##
## The correction lives here rather than in the sheet reader because how big
## a building is DRAWN is a fact about the building, not about whichever
## sheet its picture came from -- and both the illustrated path and the
## procedural placeholder then read one answer.
##
## Pinned by what it PRODUCES rather than as a number somebody liked, the
## same discipline PLOT_MARGIN_SHARE itself keeps: a cottage must come out
## smaller than a house in both dimensions, and must still cover most of its
## own plot, or it stops reading as a building on that ground.
## It was 0.85, against a cottage whose picture was being cut off above the
## eaves. Un-cutting it (2026-09-20 -- see BuildingLifecycleSheet._GRID_8X5)
## gave every cottage back its roof apex, finial and chimney cap: 31 more
## rows of drawing, about a fifth taller. Drawn at the old share that made
## the cottage the tallest thing on the street again, which is the exact
## misorder this constant exists to correct, so it moves with the art it is
## scaling -- pinned by the same two tests, not by a new number anybody
## liked.
const _DRAW_SCALES := {
	"house_small": 0.80,
}


## The width, in tiles, a building's picture is actually DRAWN at on a
## `footprint_width_tiles`-wide plot -- its own width less
## PLOT_MARGIN_SHARE of air on each side.
##
## The ONE place that answer lives, so the illustrated sheet path and the
## procedural placeholder cannot disagree about how much of a plot a
## building covers. Named apart from IllustratedStructureSprite.drawn_
## width_tiles, which answers a different question for a different thing --
## how wide a single-tile PLACEABLE is drawn, from its catalog twin. A nonsense plot is treated as the smallest real one:
## a building drawn at no width at all is a building nobody can see.
static func drawn_plot_width_tiles(
	footprint_width_tiles: int, building_id: String = ""
) -> float:
	return (
		float(maxi(footprint_width_tiles, 1))
		* (1.0 - 2.0 * PLOT_MARGIN_SHARE)
		* float(_DRAW_SCALES.get(building_id, 1.0))
	)


static func capacity_of(building_id: String) -> int:
	return _BUILDINGS.get(building_id, {}).get("capacity", 0)


## How many units of goods, across all item ids, a building holds
## (docs/concept/building_storage.md). 0 for a building that is not a place
## goods are kept, and for an id the catalog does not know.
##
## The numbers are RATIOS, not absolutes, and each is pinned by a test that
## says what the ratio is for: a workplace holds more than a home (a
## farmhouse has to keep working between collections; a house only keeps what
## one household owns), and the warehouse holds more than anything that feeds
## it (a granary smaller than the farm filling it would never be worth
## hauling to). A hall keeps nothing -- it is where a village decides things.
##
## Read from the entry's own `storage` field so a building's capacity sits
## beside its footprint and its cost rather than in a second table that can
## drift from the first -- the same shape capacity_of already has for
## residents.
static func storage_capacity_of(building_id: String) -> int:
	return _BUILDINGS.get(building_id, {}).get("storage", 0)


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
## builds the same house, and never grander than `entitled_house_id`.
##
## The cap is the whole of "a village does not start with manors". Asked
## directly: *"The village should not produce Manors from the beginning only
## cottages and once all villagers needs are stable in the green they can
## upgrade to houses"*. The estate layer already says which house each
## standing lives in (VillageEstates.house_id_for) and every household is
## founded at the bottom one -- this function simply never asked, so a
## founding merchant, whose pool is medium/large/large/large, raised a manor
## before the village had fed anybody.
##
## A CEILING, not an assignment: the pool is clamped rather than replaced,
## so trade and character still choose within it and a showy merchant
## cottager gets the grandest cottage there is. "" (the default) means no
## cap at all, so a caller that has not been taught about standing yet is
## untouched -- as is an id this catalog does not know, which is no cap
## rather than no house.
static func choose_house_id(
	occupation: String, genome: NpcGenome, seed_value: int, entitled_house_id: String = ""
) -> String:
	var pool: Array = HOUSE_POOL_BY_OCCUPATION.get(occupation, BUILDING_IDS)
	pool = _capped_pool(pool, entitled_house_id)
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


## `pool` with every house grander than `entitled_house_id` dropped --
## BUILDING_IDS' own order IS the ladder, smallest first, so "grander" needs
## no second table. Never empty: a pool with nothing at or below the cap
## falls back to the smallest house there is, because a household always
## lives somewhere.
static func _capped_pool(pool: Array, entitled_house_id: String) -> Array:
	var ceiling := BUILDING_IDS.find(entitled_house_id)
	if ceiling < 0:
		return pool
	var capped: Array = []
	for house_id in pool:
		if BUILDING_IDS.find(house_id) <= ceiling:
			capped.append(house_id)
	return capped if not capped.is_empty() else [BUILDING_IDS[0]]
