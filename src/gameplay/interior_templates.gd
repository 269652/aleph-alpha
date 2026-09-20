extends RefCounted

## Authored house interiors (docs/concept/building.md "Entering"): a real
## room plan per BuildingCatalog interior_family (cottage/house/manor),
## several variants each, seed-picked so the same house always gets the
## same interior on every visit -- "small outside, big inside", the point
## of the whole pass. v2: multi-room plans (a cottage's bedroom and hearth
## room, a house's bedroom / main room / back room, a manor's four), the
## resident's REAL occupation deciding what stands in each typed slot
## (HouseDecor.piece_for_slot -- a smith's workshop slot is an anvil, a
## farmer's a barrel; a merchant sits on a couch, a farmer on a chair),
## windows on the outer wall, a candle or two for light, and one cell the
## resident stands on when they are home.
##
## Grid convention (GRAMMAR): `#` wall -- the outer wall or an interior
## partition (rooms connect through gaps, no interior door piece); `w` a
## window, outer wall only and never on the door row (the facade); `.`
## floor; `D` the one exterior door, on the south/last row (matches
## BuildingCatalog's own door-on-the-south-edge convention); `@` the cell
## the resident stands on (exactly one, interior floor); slot letters, all
## interior: `B` bed, `T` table, `C` chair or couch, `R` rug, `S` shelf or
## cupboard, `P` picture, `K` hearth, `W` the occupation's own workshop
## piece, `L` a light. Every template is fully enclosed, every non-wall
## cell reachable from the door, validated directly by
## test_interior_templates.gd -- authored by hand as plain rectangles.

const HouseDecor = preload("res://src/gameplay/house_decor.gd")
const PixelNoise = preload("res://src/rendering/pixel_noise.gd")

const GRAMMAR := "#w.D@BTCRSPKWL"

## The "occupation" a player's OWN house is furnished for: every slot is
## plain floor (no candles either) -- you decorate your own home (docs/
## concept/housing.md), it does not come pre-furnished for somebody else.
const UNFURNISHED := "unfurnished"

const _WALL_PIECE_ID := "wood_wall"
const _WINDOW_PIECE_ID := "wood_window"
const _FLOOR_PIECE_ID := "wood_floor"
const _DOOR_PIECE_ID := "wood_door"

const _COTTAGE_VARIANTS: Array = [
	[
		"##w###w##",
		"#B.L#K.T#",
		"#...#..C#",
		"#R..#...#",
		"#....@..#",
		"#S....W.#",
		"####D####",
	],
	[
		"##w###w##",
		"#K.T.#B.#",
		"#..C.#..#",
		"#....#L.#",
		"#.@..#..#",
		"#R....W.#",
		"####D####",
	],
	[
		"##w###w##",
		"#S.....B#",
		"#...#...#",
		"#K..#L..#",
		"#T..#...#",
		"#C.@....#",
		"#..W....#",
		"####D####",
	],
]

const _HOUSE_VARIANTS: Array = [
	[
		"##w####w###",
		"#B.L#K..T.#",
		"#...#.....#",
		"#R..#..C..#",
		"#....@....#",
		"####.######",
		"#S.W.....P#",
		"#####D#####",
	],
	[
		"###w###w###",
		"#K..T.#B..#",
		"#.C...#..L#",
		"#.....#R..#",
		"#..@......#",
		"######.####",
		"#W.......S#",
		"#####D#####",
	],
	[
		"##w#####w##",
		"#T..C#S...#",
		"#K...#..B.#",
		"#....#..L.#",
		"#.@.......#",
		"#.........#",
		"#R..W...P.#",
		"#####D#####",
	],
]

const _MANOR_VARIANTS: Array = [
	[
		"##w###w###w##",
		"#B.L.#K..T..#",
		"#....#.....C#",
		"#R...#......#",
		"#.....@.....#",
		"######.######",
		"#S..W#.P....#",
		"#....#..C...#",
		"#.........R.#",
		"######D######",
	],
	[
		"##w###w###w##",
		"#K..T.#S...B#",
		"#..C..#....L#",
		"#.....#R....#",
		"#..@........#",
		"###.###.#####",
		"#W....#.....#",
		"#.....#..P..#",
		"#.....#..C..#",
		"#######D#####",
	],
	[
		"###w###w##w##",
		"#B..L#T...K.#",
		"#R...#..C...#",
		"#....#......#",
		"#......@....#",
		"######.######",
		"#P...#W.....#",
		"#..S........#",
		"#....#....C.#",
		"######D######",
	],
]

## A hall is a WORKPLACE, not a home (docs/concept/building.md, "A hall is
## a workplace"): the City Hall, the warehouse, the trade hall and the mage
## guild all share this family, and not one of them is anybody's bedroom.
##
## No `B` slot anywhere, deliberately and test-pinned -- a bed in a City
## Hall is exactly the kind of thing a later plan reintroduces by
## copy-paste. What a hall has instead is **one big open room** with real
## standing space (a cottage's best plan leaves 32 open cells; the poorest
## of these leaves 52, which is what lets several masters stand in one
## without standing on the furniture -- see HouseInteriorView.
## standing_cells) plus side chambers through wall gaps, so it still keeps
## the same "more than one room" shape houses and manors do.
##
## The occupation still decides the furnishing through the same
## HouseDecor.piece_for_slot every house uses, so one shape serves a mage
## guild's workbench and bookshelves and a warehouse's crates and
## cupboards without a second table anywhere.
const _HALL_VARIANTS: Array = [
	[
		"##w#####w####",
		"#K.........S#",
		"#....T.T....#",
		"#L..C.@.C..P#",
		"#...........#",
		"#.###.#.###.#",
		"#S..#...#..W#",
		"#...#.L.#..R#",
		"######D######",
	],
	[
		"###w###w#####",
		"#S.........K#",
		"#..T.T.T....#",
		"#L.C.@.C...P#",
		"#...........#",
		"#.#####.###.#",
		"#.#..R..#..W#",
		"#.#.L...#..S#",
		"######D######",
	],
	[
		"#####w#w#####",
		"#....K.K....#",
		"#...........#",
		"#L..T.@.T..L#",
		"#..C.....C..#",
		"#.###.#.###.#",
		"#S.#...#..P.#",
		"#..#.R.#...W#",
		"######D######",
	],
]

const _VARIANTS_BY_FAMILY := {
	"cottage": _COTTAGE_VARIANTS,
	"house": _HOUSE_VARIANTS,
	"manor": _MANOR_VARIANTS,
	"hall": _HALL_VARIANTS,
}


## Whether this family has plans of its own, or is borrowing the
## cottage's through the fail-open default below.
##
## Public because that default is quiet by design and therefore dangerous
## by accident: "hall" fell through it and was furnished as a BEDROOM for
## as long as nothing happened indoors, and nobody noticed until three mage
## masters were standing in one. test_interior_templates.gd holds the
## catalog's every real family to being either planned or *declared* as
## borrowing, so the next family cannot repeat it silently.
static func has_own_plans(interior_family: String) -> bool:
	return _VARIANTS_BY_FAMILY.has(interior_family)


## A family with no plans of its own falls back to the plainest real shape
## (cottage) rather than crashing, the same fail-open convention this
## project uses throughout for an unexpected occupation/id. Still true of
## "workshop" and "farmstead" (the sawmill, blacksmith, brewery and
## farmhouse) -- see has_own_plans above for why that is declared rather
## than left implicit.
static func _variants_for(interior_family: String) -> Array:
	return _VARIANTS_BY_FAMILY.get(interior_family, _COTTAGE_VARIANTS)


static func variant_count(interior_family: String) -> int:
	return _variants_for(interior_family).size()


## Deterministic for the same (interior_family, seed_value) pair -- the
## same house's own seed (its BuildingCatalog record's "seed" field)
## always picks the same interior on every visit.
static func choose_variant_index(interior_family: String, seed_value: int) -> int:
	return PixelNoise.range_index(seed_value, 0, 0, variant_count(interior_family))


static func grid_for(interior_family: String, variant_index: int) -> Array:
	return _variants_for(interior_family)[variant_index]


static func grid_size(grid: Array) -> Vector2i:
	return Vector2i((grid[0] as String).length(), grid.size())


static func door_cell_of(grid: Array) -> Vector2i:
	for y in grid.size():
		var row: String = grid[y]
		var x := row.find("D")
		if x != -1:
			return Vector2i(x, y)
	return Vector2i.ZERO


## The real, per-house result HouseInteriorView consumes: a flat local
## Vector2i -> "wall"/"window"/"floor"/"door"/<a real BuildingPiece.
## CATEGORY_FURNITURE id> map, `size`, `door_cell` (the local cell
## HouseInteriorView aligns the exit to), `resident_cell` (where the
## villager stands when home -- always a floor cell) and `light_cells`
## (every candle placed). Slots resolve through HouseDecor.piece_for_slot
## for the resident's own occupation; UNFURNISHED turns every slot into
## bare floor.
static func furnish(interior_family: String, occupation: String, seed_value: int) -> Dictionary:
	var variant_index := choose_variant_index(interior_family, seed_value)
	var grid := grid_for(interior_family, variant_index)
	var size := grid_size(grid)
	var cells := {}
	var resident_cell := Vector2i.ZERO
	var light_cells: Array = []
	for y in size.y:
		var row: String = grid[y]
		for x in size.x:
			var local := Vector2i(x, y)
			var ch := row[x]
			if ch == "#":
				cells[local] = "wall"
			elif ch == "w":
				cells[local] = "window"
			elif ch == "D":
				cells[local] = "door"
			elif ch == "." :
				cells[local] = "floor"
			elif ch == "@":
				cells[local] = "floor"
				resident_cell = local
			elif occupation == UNFURNISHED:
				cells[local] = "floor"
			else:
				cells[local] = HouseDecor.piece_for_slot(ch, occupation)
				if ch == "L":
					light_cells.append(local)
	return {
		"size": size, "door_cell": door_cell_of(grid), "cells": cells, "variant_index": variant_index,
		"resident_cell": resident_cell, "light_cells": light_cells,
	}


## The shape as real BuildingPiece ids -- wall/window/door pieces and
## wood_floor everywhere else, furniture slots included -- the "ground
## grid" FurniturePlacement.can_place reads to decide where a player may
## put a piece inside their own house (docs/concept/housing.md).
static func piece_grid(interior_family: String, seed_value: int) -> Dictionary:
	var shape := furnish(interior_family, UNFURNISHED, seed_value)
	var grid := {}
	for local in shape["cells"]:
		match shape["cells"][local]:
			"wall":
				grid[local] = _WALL_PIECE_ID
			"window":
				grid[local] = _WINDOW_PIECE_ID
			"door":
				grid[local] = _DOOR_PIECE_ID
			_:
				grid[local] = _FLOOR_PIECE_ID
	return grid
