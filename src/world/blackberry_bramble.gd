extends RefCounted

## Pure per-chunk bramble simulation for a wood's edges and clearings (see
## docs/concept/brambles.md).
##
## Sibling to ForestFern, and the same architecture TallGrass, DesertScrub
## and TundraLichen already are -- deliberately DUPLICATED from them rather
## than abstracted over them, per this project's "three similar things beats
## a premature abstraction" convention. Bracken is what a wood's floor IS; a
## bramble is what it GIVES.
##
## Asked for with the art dropped in -- *"And I added blackberry.png"* -- and
## then directly: *"Forageable, bearing with the seasons"*. The sheet draws
## green fruit, reddening fruit, black fruit and flowers, which is a
## specification: a bramble carrying the same berries all year would throw
## most of that sheet away.
##
## No RandomNumberGenerator: all randomness is hash-derived from the chunk
## seed, so a reloaded chunk reproduces the same thicket.

const SeasonCycle = preload("res://src/world/season_cycle.gd")

## Chance (0..1) that any given forest cell carries a bramble.
##
## Well BELOW ForestFern.SEED_CHANCE, which is the decision -- bracken
## carpets a wood's floor and brambles are scattered through it. The
## ORDERING is pinned by test_brambles_are_scattered_where_bracken_carpets
## rather than asserted here.
const SEED_CHANCE := 0.035

## Hard cap on patches per chunk. Derived from the density above against a
## real EarthChunkManager.CHUNK_SIZE (32) chunk the way ForestFern.MAX_
## PATCHES is, and for the reason TallGrass' own comment records paying for
## once: a cap UNDER what seeding alone asks for on a fully wooded chunk is
## reached at worldgen, which silently truncates the thicket. 32 * 32 *
## 0.035 = 35.84, rounded up.
const MAX_PATCHES := 36

## The biome a bramble grows in. Named rather than inlined, because "which
## ground is a bramble's" is one decision.
const HOME_BIOME := "forest"

## Where "ripe enough to eat" sits on the ripeness curve. Below this the
## fruit is green or reddening and pick() refuses it -- reaching into a
## bramble in June and coming out with blackberries is the kind of small lie
## that makes a world feel unserious.
const MIN_PICKABLE_RIPENESS := 0.75

## Blackberries a ripe patch yields when it is picked.
const FRUIT_PER_PATCH := 3

## The year fraction bearing begins and ends. Flowering runs through spring,
## so fruit only starts to swell at the turn into summer, and the whole crop
## is gone by the turn into winter -- "BARE BY WINTER", which is
## flora.md's own rule for tree fruit and is there because a crop ripening on
## its own unaligned clock is what once put apples under snow.
const BEARING_STARTS := 0.25
const BEARING_ENDS := 0.75

var _width: int
var _height: int
var _biome: PackedStringArray
var _seed_value: int

## Vector2i cell -> true. A bramble has no growth axis of its own: the cane
## is perennial and what changes through the year is its FRUIT, which is a
## pure function of the calendar (see ripeness_at).
var _patches: Dictionary = {}

## Vector2i cell -> the bearing year its fruit was taken in. The calendar is
## the regrowth timer; there is no second one to tune.
var _picked_in_year: Dictionary = {}

## Ground nothing may grow on -- the identical mask ForestFern takes, and for
## the identical reason its own doc records: a river never changes the biome
## array and neither does a building already standing on a reloaded chunk,
## so without it a fresh sim seeds brambles into water and through floors on
## every chunk load.
var _growth_blocked: PackedByteArray

var _blocked: Dictionary = {}


func _init(
	seed_value: int, width: int, height: int, biome: PackedStringArray,
	growth_blocked: PackedByteArray = PackedByteArray()
) -> void:
	_seed_value = seed_value
	_width = width
	_height = height
	_biome = biome
	_growth_blocked = growth_blocked
	_seed_initial_patches()


## How ripe a bramble's fruit is at this point in the year, 0 (nothing on the
## cane) to 1 (black and ready).
##
## A PURE function of the calendar, with no state at all, which is the whole
## pillar: a crop that accumulated on its own clock is what put apples under
## snow. Being pure it is also directly testable at any point of any year
## without stepping a simulation to get there.
##
## Flowering through spring (nothing on the cane), swelling through summer,
## ripe across autumn, and bare again at the turn into winter.
static func ripeness_at(year_fraction: float) -> float:
	var at := fposmod(year_fraction, 1.0)
	if at < BEARING_STARTS or at >= BEARING_ENDS:
		return 0.0
	return clampf((at - BEARING_STARTS) / (BEARING_ENDS - BEARING_STARTS), 0.0, 1.0)


func get_patch_cells() -> Array:
	return _patches.keys()


func has_bramble(cell: Vector2i) -> bool:
	return _patches.has(cell)


## Marks `cells` as built on: the bramble there is gone and nothing puts one
## back while the block stands (see ForestFern.block_cells).
func block_cells(cells: Array) -> void:
	for cell in cells:
		_blocked[cell] = true
		_patches.erase(cell)


func unblock_cells(cells: Array) -> void:
	for cell in cells:
		_blocked.erase(cell)


## Takes this patch's crop, returning how many blackberries it yielded -- 0
## when there is no bramble there, when the fruit is not ripe yet, or when
## this patch has already been picked in this bearing year.
##
## The CANE always survives: a bramble is not an annual, so the same patch
## bears again next autumn. `year` is the bearing year (how many whole years
## have elapsed), which is what makes "already picked" mean "this season"
## rather than "ever".
func pick(cell: Vector2i, year_fraction: float, year: int) -> int:
	if not _patches.has(cell):
		return 0
	if ripeness_at(year_fraction) < MIN_PICKABLE_RIPENESS:
		return 0
	if _picked_in_year.get(cell, -1) == year:
		return 0
	_picked_in_year[cell] = year
	return FRUIT_PER_PATCH


## Whether this patch still has fruit a forager could take right now -- what
## a marker asks to decide whether to draw berries on the cane.
func has_fruit(cell: Vector2i, year_fraction: float, year: int) -> bool:
	if not _patches.has(cell):
		return false
	if ripeness_at(year_fraction) < MIN_PICKABLE_RIPENESS:
		return false
	return _picked_in_year.get(cell, -1) != year


func _is_growth_blocked_at(x: int, y: int) -> bool:
	var index := y * _width + x
	return index < _growth_blocked.size() and _growth_blocked[index] != 0


func _seed_initial_patches() -> void:
	for y in _height:
		for x in _width:
			if _patches.size() >= MAX_PATCHES:
				return
			if _biome[y * _width + x] != HOME_BIOME:
				continue
			if _is_growth_blocked_at(x, y):
				continue
			var roll := float(
				absi(hash("%d_%d_%d_bramble_seed" % [_seed_value, x, y])) % 10000
			) / 10000.0
			if roll < SEED_CHANCE:
				_patches[Vector2i(x, y)] = true
