extends RefCounted

## Per-chunk wild mushroom fruiting simulation -- see
## docs/concept/mushrooms.md's "Where and when a flush happens". Unlike
## WildCropPatch's continuous 0..1 growth, a cell here is binary: fruiting
## or not, because a real fruiting body appears fully formed (see that
## doc's pillar 1). Mirrors EarthwormPatch's shape more than
## WildCropPatch's: a fixed set of possible SITES is decided once at
## construction (the mycelium, always there, exactly like a fixed set of
## earthworm burrows), and advance() only ever rolls against that small
## fixed set, never the whole chunk grid -- the same "bounded by
## construction" idiom leaf_litter.md's own pillar 3 names, avoiding a real
## per-step full-grid scan.
##
## One instance per chunk covers ALL six species together, deliberately
## NOT WildCropPatch's "one instance per crop, partitioned territory"
## shape: two different real mushroom species fruiting near each other in
## the same patch of forest floor is completely normal (unlike two root
## crops occupying the identical tile, which reads as a rendering
## collision) -- so each SITE is assigned one eligible species once, at
## construction, and a cell's fruiting event is purely "is this site
## fruiting right now", never a cross-species collision to resolve.
##
## PixelNoise throughout, never Godot's string hash -- the same lesson
## soil_fauna.md/ant_colony.gd already learned (a raw hash() correlates
## neighbouring cells; this project has hit that clustering bug several
## times).

const MushroomSpecies = preload("res://src/world/mushroom_species.gd")
const PixelNoise = preload("res://src/rendering/pixel_noise.gd")
const CrushMechanic = preload("res://src/world/crush_mechanic.gd")

## Fraction of biome-eligible cells that are even a possible mushroom SITE
## at all (the mycelium footprint) -- real mycelium networks are patchy,
## not everywhere eligible ground actually has one. Close to
## TallGrass.SEED_CHANCE (0.20) rather than far below it as originally set
## (0.05): reported live, repeatedly, across an identification-gate
## removal AND a debug /mushroom force-command -- a real forager finding
## mushrooms in season is not this rare, and a mechanic nobody can ever
## actually encounter during normal play isn't doing its job (see
## MUSHROOM_WORLD_WIDTH's own doc comment for the same finding applied to
## size instead of count).
const SITE_CHANCE := 0.15

## Hard cap on sites per chunk. Doubled alongside SITE_CHANCE so the
## higher chance actually manifests instead of being capped away
## immediately -- still a scattered handful relative to a whole chunk's
## cell count, not a full carpet.
const MAX_SITES := 60

## Of the real sites, how many already happen to be fruiting the moment a
## chunk is first generated -- a freshly-loaded chunk should not always
## read as uniformly empty (the mycelium was already there; see class doc
## comment). Raised alongside SITE_CHANCE/MAX_SITES (see their own doc
## comments): most sites still are NOT fruiting at any given moment, since
## a real fruiting body only stands for a while (SPENT_SECONDS) out of a
## much longer dormant span, but a genuinely findable fraction of them
## now are.
const INITIAL_FRUITING_CHANCE := 0.35

## How long a fruiting body stands before it's spent and its site can roll
## again -- applies whether it was picked or simply left alone (a real
## fruiting body doesn't last forever either way). Mirrors EarthwormPatch's
## post-predation `recovery` countdown in SHAPE (a cooldown before a site
## can produce again), not value.
const SPENT_SECONDS := 240.0

## Per-step base chance a site starts fruiting when flush_drive is at its
## theoretical maximum (1.0) -- flush_drive SCALES this base rate rather
## than being the raw per-step chance itself. Raised alongside SITE_CHANCE/
## MAX_SITES/INITIAL_FRUITING_CHANCE (see their own doc comments): new
## fruiting during ongoing play should keep pace with the now-denser site
## population, not lag behind it.
const FLUSH_CHANCE_PER_STEP := 0.15

## Independent PixelNoise salts, one per distinct kind of roll, so they
## never correlate with each other -- the same convention AntColony's own
## _FORAGE_SALT/_CARRY_SALT/_WINDFALL_SALT triple already establishes.
const _SITE_SALT := 8191
const _SPECIES_SALT := 16183
const _INITIAL_SALT := 24571
const _FLUSH_SALT := 32771

var _width: int
var _height: int
var _seed_value: int
var _step_count: int = 0

## Vector2i cell -> species_id String, for every cell that could EVER
## fruit here -- fixed at construction (see class doc comment), bounds all
## later per-step work to this small set.
var _sites: Dictionary = {}

## Subset of _sites' keys currently fruiting -> seconds since it started.
var _fruiting: Dictionary = {}
## Subset of _sites' keys on a post-fruiting cooldown -> seconds remaining.
var _recovery: Dictionary = {}
## Subset of _recovery's keys whose fruiting body didn't just get picked or
## age out quietly, but left a corpse worth showing -> "crushed" or
## "bitten" (see is_corpse/corpse_kind). Rides the identical _recovery
## clock -- cleared alongside it in advance(), never on a second timer --
## the same "a corpse is new ground" shape EarthwormPatch._crushed already
## established (see docs/concept/soil_fauna.md), generalized here to two
## distinct causes instead of one.
var _corpse_kind: Dictionary = {}


func _init(seed_value: int, width: int, height: int, biome: PackedStringArray) -> void:
	_seed_value = seed_value
	_width = width
	_height = height
	_seed_sites(biome)
	_seed_initial_fruiting()


func get_site_cells() -> Array:
	return _sites.keys()


func site_count() -> int:
	return _sites.size()


func get_fruiting_cells() -> Array:
	return _fruiting.keys()


func has_fruiting(cell: Vector2i) -> bool:
	return _fruiting.has(cell)


## The real species this site is (or would be) -- fixed at construction,
## independent of whether it is currently fruiting. "" for a cell with no
## site at all.
func species_at(cell: Vector2i) -> String:
	return String(_sites.get(cell, ""))


## Picks the mushroom at `cell`, starting its recovery cooldown -- returns
## true if there was one to pick. Mirrors WildCropPatch.graze's "just try
## and let the sim decide" contract.
func pick(cell: Vector2i) -> bool:
	if not _fruiting.has(cell):
		return false
	_fruiting.erase(cell)
	_recovery[cell] = SPENT_SECONDS
	return true


## Crushes the fruiting body at `cell` underfoot -- see docs/concept/
## soil_fauna.md "Crushed underfoot", CrushMechanic. Mirrors
## EarthwormPatch.crush exactly: the same shared momentum threshold, the
## same "recover on the identical clock as being taken" shape -- a crushed
## site is not destroyed, only whatever fruiting body was on it at the
## time. Returns false, leaving a fruiting mushroom exactly where it was,
## when there is nothing fruiting there (the identical has_fruiting gate
## pick() already uses) OR when the momentum simply is not enough.
func crush(cell: Vector2i, momentum_kg_m_s: float) -> bool:
	if not has_fruiting(cell):
		return false
	if not CrushMechanic.is_crushed_by(momentum_kg_m_s):
		return false
	_fruiting.erase(cell)
	_recovery[cell] = SPENT_SECONDS
	_corpse_kind[cell] = "crushed"
	return true


## A decomposer's single bite (see docs/concept/soil_fauna.md's fungivory
## follow-up) -- reported live: "when a bug takes a bite" should show real
## bitten art. Mirrors pick()/crush()'s exact has_fruiting gate and
## recovery shape; the only difference from crush() is which corpse_kind
## it leaves behind, so the sprite layer can tell "stepped on" apart from
## "nibbled" (crushed_frame_for vs bitten_frame_for). Unlike crush(), no
## momentum/threshold gate -- an insect bite isn't a weight-emergent
## physics event, it simply happens once a decomposer commits to feeding.
func bite(cell: Vector2i) -> bool:
	if not has_fruiting(cell):
		return false
	_fruiting.erase(cell)
	_recovery[cell] = SPENT_SECONDS
	_corpse_kind[cell] = "bitten"
	return true


## Whether `cell` currently holds a crushed or bitten corpse -- distinct
## from simply having been picked (pick() never sets this) or aged out on
## its own, so the sprite layer can tell "show crushed/bitten art and hold
## it" apart from "just disappear" (mirrors EarthwormPatch.is_corpse).
func is_corpse(cell: Vector2i) -> bool:
	return _corpse_kind.has(cell)


## "crushed", "bitten", or "" (never died, or already recovered) -- what
## the sprite layer picks IllustratedMushroomSprite.crushed_frame_for vs
## bitten_frame_for by.
func corpse_kind(cell: Vector2i) -> String:
	return String(_corpse_kind.get(cell, ""))


## Ages every currently-fruiting body (a real one doesn't stand forever,
## picked or not) and every recovering site's cooldown, then -- for every
## site that is neither fruiting nor recovering -- rolls a fresh flush
## against the live `flush_drive` (see MushroomFlush.flush_drive). Bounded
## to _sites, never the whole chunk grid -- see class doc comment.
func advance(delta: float, flush_drive: float) -> void:
	_step_count += 1

	for cell in _fruiting.keys():
		_fruiting[cell] += delta
		if _fruiting[cell] >= SPENT_SECONDS:
			_fruiting.erase(cell)
			_recovery[cell] = SPENT_SECONDS

	for cell in _recovery.keys():
		_recovery[cell] -= delta
		if _recovery[cell] <= 0.0:
			_recovery.erase(cell)
			# Whatever died here is gone by the time the site could fruit
			# fresh again -- the identical clock, never a second one (see
			# _corpse_kind's own doc comment).
			_corpse_kind.erase(cell)

	if flush_drive <= 0.0:
		return
	for cell in _sites:
		if _fruiting.has(cell) or _recovery.has(cell):
			continue
		if should_flush(cell, flush_drive):
			_fruiting[cell] = 0.0


## Forces the nearest real site to `cell` into fruiting immediately,
## bypassing recovery -- a debug/dev-console entry point (see
## World._handle_mushroom_command), never called from the ordinary
## advance() flush path. Real fruiting is a deliberately rare roll
## (SITE_CHANCE/FLUSH_CHANCE_PER_STEP are both small, see their own doc
## comments) -- too slow to demo or verify against on demand, hence this.
## Returns the cell that actually fruited, or Vector2i(-1, -1) if this
## patch has no sites at all (a genuinely site-less biome, e.g. desert,
## has nothing to force -- see _eligible_species_at).
func force_fruit_near(cell: Vector2i) -> Vector2i:
	if _sites.is_empty():
		return Vector2i(-1, -1)
	var nearest: Vector2i = Vector2i.ZERO
	var nearest_distance := -1.0
	for site in _sites.keys():
		var distance: float = (site - cell).length_squared()
		if nearest_distance < 0.0 or distance < nearest_distance:
			nearest = site
			nearest_distance = distance
	_recovery.erase(nearest)
	_fruiting[nearest] = 0.0
	return nearest


## Whether `cell` (a real site) starts fruiting THIS step -- a pure,
## PixelNoise-seeded roll against the site's own position and the sim's
## current step, exactly AntColony.should_forage's shape.
func should_flush(cell: Vector2i, flush_drive: float) -> bool:
	return (
		PixelNoise.unit(_seed_value + _step_count + _FLUSH_SALT, cell.x, cell.y)
		< clampf(flush_drive, 0.0, 1.0) * FLUSH_CHANCE_PER_STEP
	)


func _seed_sites(biome: PackedStringArray) -> void:
	for y in _height:
		for x in _width:
			if _sites.size() >= MAX_SITES:
				return
			var species := _eligible_species_at(x, y, biome)
			if species.is_empty():
				continue
			if PixelNoise.unit(_seed_value + _SITE_SALT, x, y) < SITE_CHANCE:
				_sites[Vector2i(x, y)] = species


func _seed_initial_fruiting() -> void:
	for cell in _sites:
		if PixelNoise.unit(_seed_value + _INITIAL_SALT, cell.x, cell.y) < INITIAL_FRUITING_CHANCE:
			_fruiting[cell] = 0.0


## Which real species (if any) could ever grow at (x, y) -- delegates the
## actual real-world biome eligibility to MushroomSpecies.allows_biome
## (see that method's own doc comment: mycorrhizal species need their real
## host tree's biome, and saprotrophs vary by real species rather than
## sharing one blanket rule). Deterministic per cell.
func _eligible_species_at(x: int, y: int, biome: PackedStringArray) -> String:
	var here: String = biome[y * _width + x]
	var candidates: Array[String] = []
	for id in MushroomSpecies.IDS:
		if _biome_allows(id, here):
			candidates.append(id)
	if candidates.is_empty():
		return ""
	return candidates[PixelNoise.range_index(_seed_value + _SPECIES_SALT, x, y, candidates.size())]


func _biome_allows(species_id: String, biome: String) -> bool:
	return MushroomSpecies.allows_biome(species_id, biome)
