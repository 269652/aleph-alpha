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
## A barrier built across flowing water to pond it (see
## docs/concept/rivers.md). Its own category rather than a wall variant
## because the questions it answers are different: it must be placed IN
## water rather than on buildable ground, it holds back a real hydraulic
## head, and it must stay out of the building span solver.
const CATEGORY_DAM := "dam"

## Materials, in progression order along the existing gather -> craft ->
## smelt chain.
const MATERIAL_WOOD := "wood"
const MATERIAL_STONE := "stone"
## The timber tier (see docs/concept/timber_construction.md): a real
## Anno-style upgrade path above plain wood, sourced from a Sägewerk supply
## chain (log -> beam/plank) rather than gathered wood placed directly.
const MATERIAL_TIMBER := "timber"

## Every piece the game knows how to build.
const PIECE_IDS: Array[String] = [
	"wood_floor", "wood_wall", "wood_door", "wood_window", "wood_roof",
	"stone_floor", "stone_wall", "stone_door", "stone_window", "stone_roof",
	# Timber tier -- real consumers for beam/plank (see
	# docs/concept/woodworking.md's own "beam/plank have no consumers yet"
	# gap). Appended, not interleaved, per this file's existing convention.
	"timber_wall", "timber_floor",
	# Water infrastructure (see docs/concept/rivers.md). Appended, not
	# interleaved, per this file's existing convention.
	"stone_dam",
]

## Per-piece definition.
##   category          see CATEGORY_* above
##   material          see MATERIAL_*
##   encloses          does it stop the enclosure flood fill (see RoomDetector)?
##   walkable          can a body pass through its cell?
##   durability        hit points before it breaks
##   cost              item_id -> count consumed to place it
##   support_capacity  see docs/concept/timber_construction.md#real-statics --
##                     the "load-bearing flag or support-capacity number"
##                     that doc's own Material-pipeline section names: >0.0
##                     for a load-bearing piece (every CATEGORY_WALL piece,
##                     across every material tier -- generalizing pillar 1's
##                     "a Balken is load-bearing, a Planke is not" beyond just
##                     timber), 0.0 for everything else. Mirrors durability's
##                     own already-tuned wood < timber < stone progression
##                     rather than a fresh eyeballed number -- BuildingStatics
##                     itself still uses one fixed span limit for every
##                     material this pass (see that file's own doc comment),
##                     so this field is regression-tested/real but not yet
##                     consumed by the span-length computation -- a named,
##                     staged upgrade, not a divergence (see this doc's
##                     "Interaction with other docs" section on materials.md).
##
## The door row is the one worth reading twice: it BOTH encloses and is
## walkable. That combination is what makes a house a house you can enter --
## a piece that only enclosed would seal the building shut, and one that
## only was walkable would leave a hole in the wall.
const _PIECES := {
	"wood_floor": {
		"category": CATEGORY_FLOOR, "material": MATERIAL_WOOD,
		"encloses": false, "walkable": true, "durability": 40.0,
		"cost": {"wood": 1}, "support_capacity": 0.0,
	},
	"wood_wall": {
		"category": CATEGORY_WALL, "material": MATERIAL_WOOD,
		"encloses": true, "walkable": false, "durability": 60.0,
		"cost": {"wood": 2}, "support_capacity": 60.0,
	},
	"wood_door": {
		"category": CATEGORY_DOOR, "material": MATERIAL_WOOD,
		"encloses": true, "walkable": true, "durability": 45.0,
		"cost": {"wood": 3}, "support_capacity": 0.0,
	},
	"wood_window": {
		"category": CATEGORY_WINDOW, "material": MATERIAL_WOOD,
		"encloses": true, "walkable": false, "durability": 35.0,
		"cost": {"wood": 2}, "support_capacity": 0.0,
	},
	"wood_roof": {
		"category": CATEGORY_ROOF, "material": MATERIAL_WOOD,
		"encloses": false, "walkable": true, "durability": 40.0,
		"cost": {"wood": 2}, "support_capacity": 0.0,
	},
	"stone_floor": {
		"category": CATEGORY_FLOOR, "material": MATERIAL_STONE,
		"encloses": false, "walkable": true, "durability": 110.0,
		"cost": {"stone": 2}, "support_capacity": 0.0,
	},
	"stone_wall": {
		"category": CATEGORY_WALL, "material": MATERIAL_STONE,
		"encloses": true, "walkable": false, "durability": 160.0,
		"cost": {"stone": 3}, "support_capacity": 160.0,
	},
	"stone_door": {
		"category": CATEGORY_DOOR, "material": MATERIAL_STONE,
		"encloses": true, "walkable": true, "durability": 120.0,
		"cost": {"stone": 3, "wood": 2}, "support_capacity": 0.0,
	},
	"stone_window": {
		"category": CATEGORY_WINDOW, "material": MATERIAL_STONE,
		"encloses": true, "walkable": false, "durability": 90.0,
		"cost": {"stone": 2}, "support_capacity": 0.0,
	},
	"stone_roof": {
		"category": CATEGORY_ROOF, "material": MATERIAL_STONE,
		"encloses": false, "walkable": true, "durability": 110.0,
		"cost": {"stone": 2, "wood": 1}, "support_capacity": 0.0,
	},
	# Timber tier (see docs/concept/timber_construction.md): a real Sägewerk
	# supply chain, above plain gathered wood but not the stone tier.
	# Pillar 1 -- a Balken (beam) is the load-bearing structural piece, a
	# Planke (plank) is not -- so the wall costs beam, the floor costs
	# plank, mirroring that division mechanically rather than just
	# cosmetically. Durability sits between wood and stone: real squared,
	# hewn timber framing outperforms a raw wood plank/pole build.
	# support_capacity is real now (see the field doc above) -- this was the
	# piece the concept doc's own "Real statics" section named as the future
	# work; that future work is this file's changes below.
	"timber_wall": {
		"category": CATEGORY_WALL, "material": MATERIAL_TIMBER,
		"encloses": true, "walkable": false, "durability": 90.0,
		"cost": {"beam": 2}, "support_capacity": 90.0,
	},
	"timber_floor": {
		"category": CATEGORY_FLOOR, "material": MATERIAL_TIMBER,
		"encloses": false, "walkable": true, "durability": 70.0,
		"cost": {"plank": 2}, "support_capacity": 0.0,
	},
	# A dry-stacked stone check dam (see docs/concept/rivers.md's "Dams").
	#
	# Costs `rock`, NOT `stone`: rock is what picking up a pebble and
	# smashing a boulder both yield, so a dam is buildable from what a river
	# bank actually offers, whereas `stone` is the MINED output and would
	# gate dams behind a pickaxe for no good reason. 6 of them because a
	# hand-stacked dam is a real pile of rock, not a token.
	#
	# support_capacity 0.0 keeps it out of BuildingStatics' span solver: a
	# dam holds back water, not a roof, and a run of them across a channel
	# must never be mistaken for an unsupported cantilever and collapsed.
	# Its real failure mode is hydraulic instead -- see
	# DamImpoundment.failure_depth_m, where sliding is derived from the
	# stone's own weight and friction.
	"stone_dam": {
		"category": CATEGORY_DAM, "material": MATERIAL_STONE,
		"encloses": true, "walkable": false, "durability": 140.0,
		"cost": {"rock": 6}, "support_capacity": 0.0,
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


## Does this piece hold up other pieces (see docs/concept/timber_construction
## .md#real-statics-a-support-graph-over-the-piece-grid)? Derived from
## support_capacity being positive rather than a separate stored flag -- the
## concept doc names this as one field ("a load-bearing flag or support-
## capacity number"), not two that could disagree. Unknown ids answer false,
## matching encloses' own "a non-piece never encloses" convention -- a typo
## must never silently carry load.
static func is_load_bearing(piece_id: String) -> bool:
	return support_capacity_of(piece_id) > 0.0


## See the support_capacity field doc above the _PIECES dict. 0.0 for an
## unknown id or a non-load-bearing piece.
static func support_capacity_of(piece_id: String) -> float:
	return _PIECES.get(piece_id, {}).get("support_capacity", 0.0)


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
