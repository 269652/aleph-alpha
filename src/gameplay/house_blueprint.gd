extends RefCounted

## A CATALOG of named house shapes, each a seed away from a real piece list
## (see docs/concept/building.md#one-system-two-builders and
## docs/concept/building.md#a-blueprint-catalog-not-one-box).
##
## This is what makes an NPC village house a REAL house rather than a
## painted sprite: the settlement generator stamps blueprints built from the
## very same pieces the player places by hand, so a villager's house
## encloses a real room the player can walk into, on the same terms as one
## they built themselves.
##
## Before this, every village house was the exact same 5x4 wall-ring box --
## reported directly: "the houses the npcs build are minimal and don't look
## neat and diverse... we want blueprints which function as a template/
## recipe for npcs building their houses... enough different blueprints
## that every house in a village can look different." Now there are many
## named shapes (see BLUEPRINT_IDS), each built from three safe, tested
## geometric primitives -- a rectangle, a door punched through one wall,
## windows punched through others, and (for the L-shaped entries) a corner
## notch carved out -- rather than hand-pixeled ASCII floor plans that could
## silently produce an invalid room. Which blueprint a given villager builds
## is their own choice (see choose_blueprint_id), tied to their occupation
## (what they can plausibly build/afford) and personality (a light nudge
## toward the showier or plainer end of that occupation's own options) --
## docs/concept/npc.md's own "personality should be DNA derived" ask is what
## choose_blueprint_id's genome parameter is for.
##
## Pure logic -- returns cells, places nothing. The caller decides where the
## footprint sits in the world and how the pieces get into a chunk.

const BuildingPiece = preload("res://src/gameplay/building_piece.gd")
const PixelNoise = preload("res://src/rendering/pixel_noise.gd")
const NpcGenome = preload("res://src/world/npc_genome.gd")

const _NEIGHBORS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]

## The smallest footprint that can hold an interior: a wall ring plus at
## least one interior cell needs 3x3.
const MINIMUM_FOOTPRINT := 3

## Every blueprint's shape recipe: `footprint` (the bounding rectangle),
## `windows` (how many window pieces get punched into the wall ring,
## deterministically placed per seed -- see build), and an optional `notch`
## (a Rect2i, in footprint-local coordinates, carved out of one corner for a
## genuinely non-rectangular, L-shaped silhouette -- see _carve_notch).
## Ordered PLAIN -> SHOWY within each occupation's own pool below
## (BLUEPRINT_POOL_BY_OCCUPATION), smallest/plainest first.
const _BLUEPRINTS := {
	"hut_tiny": {"footprint": Vector2i(3, 3), "windows": 0},
	"cottage_small": {"footprint": Vector2i(4, 4), "windows": 1},
	"cottage_window_pair": {"footprint": Vector2i(5, 4), "windows": 2},
	"cottage_wide": {"footprint": Vector2i(6, 4), "windows": 2},
	"cottage_tall": {"footprint": Vector2i(4, 6), "windows": 2},
	"cottage_bright": {"footprint": Vector2i(5, 5), "windows": 3},
	"cottage_L_small": {"footprint": Vector2i(6, 5), "windows": 1, "notch": Rect2i(4, 0, 2, 2)},
	"manor_wide": {"footprint": Vector2i(7, 5), "windows": 3},
	"manor_grand": {"footprint": Vector2i(6, 6), "windows": 4},
	"manor_L_wide": {"footprint": Vector2i(7, 6), "windows": 2, "notch": Rect2i(0, 4, 3, 2)},
}

## Every blueprint id this catalog knows how to build, in the same order as
## `_BLUEPRINTS` (Dictionary key order is insertion order in GDScript).
const BLUEPRINT_IDS: Array[String] = [
	"hut_tiny", "cottage_small", "cottage_window_pair", "cottage_wide", "cottage_tall",
	"cottage_bright", "cottage_L_small", "manor_wide", "manor_grand", "manor_L_wide",
]

## Which blueprints an occupation tends toward -- weighted by repetition (a
## name appearing more than once in its own pool is picked more often), the
## same "simple pool, no probability table" convention CreatureRenderer's
## biome species pools already use. Ordered plain -> showy within each pool
## (see choose_blueprint_id's own showy/plain personality bias). A generic
## fallback (the whole catalog) covers any occupation not listed here.
const BLUEPRINT_POOL_BY_OCCUPATION := {
	"farmer": ["hut_tiny", "cottage_small", "cottage_small", "cottage_wide"],
	"fisher": ["hut_tiny", "hut_tiny", "cottage_small", "cottage_tall"],
	"guard": ["hut_tiny", "cottage_small", "cottage_small", "cottage_tall"],
	"herbalist": ["cottage_small", "cottage_window_pair", "cottage_bright", "cottage_L_small"],
	"blacksmith": ["cottage_wide", "cottage_wide", "manor_wide", "cottage_L_small"],
	"merchant": ["cottage_bright", "manor_wide", "manor_grand", "manor_L_wide"],
}

## Personality traits that nudge a choice toward the SHOWY (larger/later)
## end of an occupation's own pool, vs. the PLAIN (smaller/earlier) end --
## docs/concept/npc.md's "personality should be DNA derived" ask, applied as
## a light NUDGE rather than an override: occupation still decides the pool
## itself (what a villager can plausibly build), personality only colors
## WHERE in that pool the choice lands. A neutral trait (not listed either
## way) picks uniformly across the whole pool.
const _SHOWY_TRAITS := {"bold": true, "greedy": true}
const _PLAIN_TRAITS := {"cautious": true, "stoic": true}


## The bounding-rectangle size a blueprint occupies -- Vector2i.ZERO for an
## unknown id, so a caller asking "how big is this" for a typo gets a clear
## zero rather than a crash.
func footprint_for(blueprint_id: String) -> Vector2i:
	return _BLUEPRINTS.get(blueprint_id, {}).get("footprint", Vector2i.ZERO)


## Which named blueprint `occupation` (see NpcIdentity.OCCUPATIONS) picks,
## nudged by `genome`'s own dominant personality trait -- a real, seeded
## choice, not the whole catalog shuffled uniformly. An occupation with no
## dedicated pool (a future addition to NpcIdentity.OCCUPATIONS that this
## catalog hasn't caught up to yet) falls back to the entire BLUEPRINT_IDS
## catalog rather than crashing.
func choose_blueprint_id(occupation: String, genome: NpcGenome, seed_value: int) -> String:
	var pool: Array = BLUEPRINT_POOL_BY_OCCUPATION.get(occupation, BLUEPRINT_IDS)
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


## The house's ground-plane pieces: Vector2i cell (relative to the
## footprint's top-left) -> piece_id. A wall ring around a floor interior
## (notched into an L for the entries that declare one -- see
## `_BLUEPRINTS`), with exactly one door and `recipe.windows` windows
## punched through the wall ring.
##
## Returns an empty Dictionary for an unknown blueprint_id -- a caller
## asking for a typo'd id gets nothing rather than a malformed house.
func build(blueprint_id: String, seed_value: int, material: String = BuildingPiece.MATERIAL_WOOD) -> Dictionary:
	if not _BLUEPRINTS.has(blueprint_id):
		return {}
	var recipe: Dictionary = _BLUEPRINTS[blueprint_id]
	var footprint: Vector2i = recipe.footprint

	var pieces := _rectangle_pieces(footprint, material)
	if recipe.has("notch"):
		_carve_notch(pieces, recipe.notch, material)

	var candidates := _wall_candidates(pieces, footprint)
	if candidates.is_empty():
		return {}  # never happens for a real catalog entry; stays safe regardless

	var door_cell: Vector2i = candidates[PixelNoise.range_index(seed_value, footprint.x, footprint.y, candidates.size())]
	pieces[door_cell] = _piece(BuildingPiece.CATEGORY_DOOR, material)

	var window_candidates := candidates.duplicate()
	window_candidates.erase(door_cell)
	var window_count: int = recipe.get("windows", 0)
	for i in mini(window_count, window_candidates.size()):
		var pick_index := PixelNoise.range_index(seed_value, i + 1, footprint.x + footprint.y, window_candidates.size())
		var window_cell: Vector2i = window_candidates[pick_index]
		pieces[window_cell] = _piece(BuildingPiece.CATEGORY_WINDOW, material)
		window_candidates.remove_at(pick_index)

	return pieces


## The roof layer, covering the interior. Separate from `build` because
## roofs sit ABOVE the room rather than on its plane (see
## BuildingPlacement), so they live on their own layer. Only ever covers
## real FLOOR cells -- a notched blueprint's missing corner gets no roof,
## same as it gets no wall/floor.
func build_roofs(
	blueprint_id: String, seed_value: int, material: String = BuildingPiece.MATERIAL_WOOD
) -> Dictionary:
	var pieces := build(blueprint_id, seed_value, material)
	var roofs := {}
	for cell in pieces:
		if BuildingPiece.category_of(pieces[cell]) == BuildingPiece.CATEGORY_FLOOR:
			roofs[cell] = _piece(BuildingPiece.CATEGORY_ROOF, material)
	return roofs


## A plain wall-ring rectangle: every edge cell of `footprint` is a wall,
## everything inside is floor. The shared starting point every blueprint
## (rectangular or notched) builds from.
func _rectangle_pieces(footprint: Vector2i, material: String) -> Dictionary:
	var pieces := {}
	for x in footprint.x:
		for y in footprint.y:
			var cell := Vector2i(x, y)
			var on_edge := x == 0 or y == 0 or x == footprint.x - 1 or y == footprint.y - 1
			pieces[cell] = _piece(BuildingPiece.CATEGORY_WALL if on_edge else BuildingPiece.CATEGORY_FLOOR, material)
	return pieces


## Carves `notch` (a Rect2i in the same local coordinates as `pieces`) out
## of an already-built rectangle, turning an ordinary box into an L
## silhouette: every cell inside `notch` is removed entirely (no piece at
## all -- it reads as bare ground outside the building, not a hole in it),
## and any FLOOR cell left newly bordering a removed cell is upgraded to a
## WALL, since it now sits on the notch's own freshly exposed boundary.
## Mutates `pieces` in place.
func _carve_notch(pieces: Dictionary, notch: Rect2i, material: String) -> void:
	for x in range(notch.position.x, notch.position.x + notch.size.x):
		for y in range(notch.position.y, notch.position.y + notch.size.y):
			pieces.erase(Vector2i(x, y))
	var to_wall := []
	for cell in pieces:
		if BuildingPiece.category_of(pieces[cell]) != BuildingPiece.CATEGORY_FLOOR:
			continue
		for offset in _NEIGHBORS:
			if not pieces.has(cell + offset):
				to_wall.append(cell)
				break
	for cell in to_wall:
		pieces[cell] = _piece(BuildingPiece.CATEGORY_WALL, material)


## Every WALL cell where a door or window may plausibly go: exactly one
## cardinal neighbour is real FLOOR (it connects straight into the interior,
## on one side only) and at least one cardinal neighbour is missing from
## `pieces` entirely (real exterior, whether the plain outside of a
## rectangle or a notch's own freshly exposed edge). This single rule
## naturally excludes every kind of corner without needing to special-case
## rectangular vs. L-shaped blueprints:
##   - an ordinary rectangle CORNER touches zero floor cells cardinally (the
##     interior is diagonal from it, not adjacent), so it never has "exactly
##     one" floor neighbour and is excluded automatically.
##   - an L-shape's INNER corner (the cell right where the notch cuts in)
##     borders floor on TWO sides at once, also failing "exactly one" and
##     getting excluded the same way.
func _wall_candidates(pieces: Dictionary, footprint: Vector2i) -> Array:
	var candidates := []
	for x in footprint.x:
		for y in footprint.y:
			var cell := Vector2i(x, y)
			if BuildingPiece.category_of(pieces.get(cell, "")) != BuildingPiece.CATEGORY_WALL:
				continue
			var floor_neighbors := 0
			var has_outside_neighbor := false
			for offset in _NEIGHBORS:
				var neighbor := cell + offset
				if not pieces.has(neighbor):
					has_outside_neighbor = true
				elif BuildingPiece.category_of(pieces[neighbor]) == BuildingPiece.CATEGORY_FLOOR:
					floor_neighbors += 1
			if floor_neighbors == 1 and has_outside_neighbor:
				candidates.append(cell)
	return candidates


func _piece(category: String, material: String) -> String:
	return "%s_%s" % [material, category]
