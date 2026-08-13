extends RefCounted

## The catalog of structural pieces a building is assembled from (see
## docs/concept/building.md#pieces). Pure data: placement rules live in
## BuildingPlacement, enclosure in RoomDetector, so this file answers only
## "what is this piece" and never "may it go here".
##
## Every piece occupies one tile and persists as an ordinary chunk
## modification (see EarthChunkManager's MODIFICATIONS_DIR), so structures
## need no save path of their own.

## What a piece is for. The categories are behavioural, not decorative:
## each one answers the enclosure and movement questions differently.
const CATEGORY_FLOOR := "floor"
const CATEGORY_WALL := "wall"
const CATEGORY_DOOR := "door"
const CATEGORY_WINDOW := "window"
const CATEGORY_ROOF := "roof"

## Materials, in progression order along the existing gather -> craft ->
## smelt chain.
const MATERIAL_WOOD := "wood"
const MATERIAL_STONE := "stone"

## Every piece the game knows how to build.
const PIECE_IDS: Array[String] = [
	"wood_floor", "wood_wall", "wood_door", "wood_window", "wood_roof",
	"stone_floor", "stone_wall", "stone_door", "stone_window", "stone_roof",
]

## Per-piece definition.
##   category    see CATEGORY_* above
##   material    see MATERIAL_*
##   encloses    does it stop the enclosure flood fill (see RoomDetector)?
##   walkable    can a body pass through its cell?
##   durability  hit points before it breaks
##   cost        item_id -> count consumed to place it
##
## The door row is the one worth reading twice: it BOTH encloses and is
## walkable. That combination is what makes a house a house you can enter --
## a piece that only enclosed would seal the building shut, and one that
## only was walkable would leave a hole in the wall.
const _PIECES := {
	"wood_floor": {
		"category": CATEGORY_FLOOR, "material": MATERIAL_WOOD,
		"encloses": false, "walkable": true, "durability": 40.0,
		"cost": {"wood": 1},
	},
	"wood_wall": {
		"category": CATEGORY_WALL, "material": MATERIAL_WOOD,
		"encloses": true, "walkable": false, "durability": 60.0,
		"cost": {"wood": 2},
	},
	"wood_door": {
		"category": CATEGORY_DOOR, "material": MATERIAL_WOOD,
		"encloses": true, "walkable": true, "durability": 45.0,
		"cost": {"wood": 3},
	},
	"wood_window": {
		"category": CATEGORY_WINDOW, "material": MATERIAL_WOOD,
		"encloses": true, "walkable": false, "durability": 35.0,
		"cost": {"wood": 2},
	},
	"wood_roof": {
		"category": CATEGORY_ROOF, "material": MATERIAL_WOOD,
		"encloses": false, "walkable": true, "durability": 40.0,
		"cost": {"wood": 2},
	},
	"stone_floor": {
		"category": CATEGORY_FLOOR, "material": MATERIAL_STONE,
		"encloses": false, "walkable": true, "durability": 110.0,
		"cost": {"stone": 2},
	},
	"stone_wall": {
		"category": CATEGORY_WALL, "material": MATERIAL_STONE,
		"encloses": true, "walkable": false, "durability": 160.0,
		"cost": {"stone": 3},
	},
	"stone_door": {
		"category": CATEGORY_DOOR, "material": MATERIAL_STONE,
		"encloses": true, "walkable": true, "durability": 120.0,
		"cost": {"stone": 3, "wood": 2},
	},
	"stone_window": {
		"category": CATEGORY_WINDOW, "material": MATERIAL_STONE,
		"encloses": true, "walkable": false, "durability": 90.0,
		"cost": {"stone": 2},
	},
	"stone_roof": {
		"category": CATEGORY_ROOF, "material": MATERIAL_STONE,
		"encloses": false, "walkable": true, "durability": 110.0,
		"cost": {"stone": 2, "wood": 1},
	},
}


static func has_piece(piece_id: String) -> bool:
	return _PIECES.has(piece_id)


## "" for an unknown id -- callers ask about arbitrary tile ids (a chunk
## modification may be plain earth or a campfire), so this must answer
## rather than crash.
static func category_of(piece_id: String) -> String:
	return _PIECES.get(piece_id, {}).get("category", "")


static func material_of(piece_id: String) -> String:
	return _PIECES.get(piece_id, {}).get("material", "")


## Does this piece stop the enclosure flood fill (see RoomDetector)? A
## non-piece never encloses, so unknown tiles leave a room open.
static func encloses(piece_id: String) -> bool:
	return _PIECES.get(piece_id, {}).get("encloses", false)


## Can a body walk through this cell? Unknown ids default to WALKABLE: a
## typo must never silently wall the player into the world.
static func is_walkable(piece_id: String) -> bool:
	return _PIECES.get(piece_id, {}).get("walkable", true)


static func durability_of(piece_id: String) -> float:
	return _PIECES.get(piece_id, {}).get("durability", 0.0)


## item_id -> count consumed to place this piece. Empty for unknown ids.
static func cost_of(piece_id: String) -> Dictionary:
	return _PIECES.get(piece_id, {}).get("cost", {}).duplicate()


## Every piece of one category, in PIECE_IDS order -- for build menus.
static func pieces_in_category(category: String) -> Array:
	var found := []
	for piece_id in PIECE_IDS:
		if category_of(piece_id) == category:
			found.append(piece_id)
	return found
