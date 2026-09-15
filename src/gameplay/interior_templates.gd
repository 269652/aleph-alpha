extends RefCounted

## Authored house interiors (docs/concept/building.md "Entering"): a real
## room shape per BuildingCatalog interior_family (cottage/house/manor),
## several variants each, seed-picked so the same house always gets the
## same interior on every visit -- "small outside, big inside", the point
## of the whole pass. Furniture THEME is composed in rather than hand-
## duplicated per occupation: each shape's `F` slots are filled from
## HouseDecor.furniture_set_for(occupation) -- the SAME occupation-
## reasoned table the old per-tile system already used -- cycling through
## the set when a shape has more slots than the set has items, rather than
## leaving a slot as bare floor (an empty room reads as unfinished). This
## is "several variants x 8 occupations" as shape-variants x furniture-
## sets, not 24+ hand-typed grids repeating the same rooms with different
## letters.
##
## Grid convention: `#` wall, `.` floor, `D` door (exactly one, on the
## south/last row -- matches BuildingCatalog's own door-on-the-south-edge
## convention for the exterior), `F` a furniture slot (always interior,
## never touching the border). Every template is a real, fully enclosed,
## single room reachable from the door with no stray disconnected floor
## (see test_interior_templates.gd's own geometry tests) -- authored by
## hand as plain rectangles rather than anything fancier, since the
## interior's OWN shape is not what "several variants" needs to vary on;
## the furniture theme is.

const HouseDecor = preload("res://src/gameplay/house_decor.gd")
const PixelNoise = preload("res://src/rendering/pixel_noise.gd")

const _COTTAGE_VARIANTS: Array = [
	[
		"#######",
		"#.....#",
		"#.F.F.#",
		"#.....#",
		"#.F.F.#",
		"###D###",
	],
	[
		"#######",
		"#.....#",
		"#F...F#",
		"#.....#",
		"#F...F#",
		"#.....#",
		"###D###",
	],
	[
		"#######",
		"#.....#",
		"#..F..#",
		"#.F.F.#",
		"#.....#",
		"###D###",
	],
]

const _HOUSE_VARIANTS: Array = [
	[
		"#########",
		"#.......#",
		"#.F...F.#",
		"#.......#",
		"#.F.F.F.#",
		"#.......#",
		"####D####",
	],
	[
		"#########",
		"#.F...F.#",
		"#.......#",
		"#.F.F.F.#",
		"#.......#",
		"#.F...F.#",
		"####D####",
	],
	[
		"#########",
		"#.......#",
		"#.F.F.F.#",
		"#.......#",
		"#.F...F.#",
		"#.......#",
		"####D####",
	],
]

const _MANOR_VARIANTS: Array = [
	[
		"###########",
		"#.........#",
		"#.F.....F.#",
		"#.........#",
		"#.F.F.F.F.#",
		"#.........#",
		"#.F.....F.#",
		"#.........#",
		"#####D#####",
	],
	[
		"###########",
		"#.F.....F.#",
		"#.........#",
		"#.F.F.F.F.#",
		"#.........#",
		"#.F.....F.#",
		"#.........#",
		"#.F.....F.#",
		"#####D#####",
	],
	[
		"###########",
		"#.........#",
		"#.F.F.F.F.#",
		"#.........#",
		"#.F.....F.#",
		"#.........#",
		"#.F.F.F.F.#",
		"#.........#",
		"#####D#####",
	],
]

const _VARIANTS_BY_FAMILY := {
	"cottage": _COTTAGE_VARIANTS,
	"house": _HOUSE_VARIANTS,
	"manor": _MANOR_VARIANTS,
}


## An unknown family (should never happen -- BuildingCatalog only ever
## produces "cottage"/"house"/"manor") falls back to the plainest real
## shape (cottage) rather than crashing, the same fail-open convention
## this project uses throughout for an unexpected occupation/id.
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
## Vector2i -> "wall"/"floor"/"door"/<a real BuildingPiece.CATEGORY_
## FURNITURE id> map, `size` (grid dimensions), and `door_cell` (the local
## cell HouseInteriorView aligns to the house's real world doorstep).
## Furniture slots are filled in a fixed, deterministic row-major scan
## order from HouseDecor.furniture_set_for(occupation), cycling through
## the set when there are more slots than items.
static func furnish(interior_family: String, occupation: String, seed_value: int) -> Dictionary:
	var variant_index := choose_variant_index(interior_family, seed_value)
	var grid := grid_for(interior_family, variant_index)
	var size := grid_size(grid)
	var furniture_set := HouseDecor.furniture_set_for(occupation)
	var cells := {}
	var furniture_index := 0
	for y in size.y:
		var row: String = grid[y]
		for x in size.x:
			var local := Vector2i(x, y)
			var ch := row[x]
			if ch == "#":
				cells[local] = "wall"
			elif ch == "D":
				cells[local] = "door"
			elif ch == "F":
				cells[local] = furniture_set[furniture_index % furniture_set.size()]
				furniture_index += 1
			else:
				cells[local] = "floor"
	return {"size": size, "door_cell": door_cell_of(grid), "cells": cells, "variant_index": variant_index}
