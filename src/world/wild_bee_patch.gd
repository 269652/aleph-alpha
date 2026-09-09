extends RefCounted

## Per-chunk solitary/wild bee nest population -- see docs/concept/
## bees.md's "Wild bee nests" section. Deliberately a MUCH lighter
## system than BeeColony: no queen, no worker caste, no shared colony,
## no honey, no swarming -- real solitary bees are genuinely solitary,
## each female provisioning her own few brood cells in her own hole
## with no economy to speak of. "Residents" here is a stand-in for "more
## brood cells provisioned, more females now working this same hole" --
## the same abstraction level BeeColony's own "colony strength" already
## sits at, not a literal egg/larva/adult pipeline.
##
## Deliberately shaped like EarthwormPatch -- deterministic PixelNoise-
## seeded placement, a hard per-chunk cap, advance(delta) -- rather than
## sharing a base class with it (see DesertScrub's own doc comment on
## why three similar things beats a premature abstraction).
##
## Unlike BeeColony, a nest that loses its nearby forage relocates
## (should_relocate_at/relocate_to) but is never harvested, never
## swarms, and tracks no honey at all -- correct biology, not an
## arbitrary simplification (see bees.md's own real-world grounding).

const PixelNoise = preload("res://src/rendering/pixel_noise.gd")
const BeeColony = preload("res://src/world/bee_colony.gd")
const EarthwormPatch = preload("res://src/world/earthworm_patch.gd")

## Real cavity-nesting solitary bees need a real tree/deadwood source
## for their hole -- the same tree-bearing biome set BeeColony.
## HIVE_BIOMES already uses, for the identical real reason (a hive
## hangs from a branch; a solitary nest is a hole in a twig/old stem --
## both need a real tree nearby).
const NEST_BIOMES := {"grassland": true, "forest": true, "rainforest": true}

## Chance a given tree-bearing cell holds a nest hole. Real solitary-bee
## nest density is considerably HIGHER than a single honeybee colony's
## own hive density -- many individual females, each working her own
## hole, rather than one shared superorganism per territory -- pinned
## ABOVE BeeColony.HIVE_CHANCE, an ordering, not an eyeballed number.
const NEST_CHANCE := 0.03

## Hard cap per chunk. Solitary nests are individually far less
## significant a landmark than a whole honeybee colony's hive, so more
## of them sharing a chunk reads correctly rather than as clutter.
const MAX_NESTS := 3

## Chance, per call to advance(), that a resident female forages nearby
## flowers this step -- mirrors BeeColony.FORAGE_CHANCE's own "small
## per-step chance, ongoing background activity" reasoning.
const FORAGE_CHANCE := 0.1

## A resident's own local sensing/forage range -- reuses BeeColony's own
## real, already-tuned forage radius directly rather than a second,
## independently-chosen number for the identical real behaviour (a bee
## foraging near its nest).
const FORAGE_RADIUS_TILES := BeeColony.FORAGE_RADIUS_TILES
const SENSE_RADIUS_TILES := BeeColony.SENSE_RADIUS_TILES

## How much weight a single forage outcome carries in the recent-success
## EMA -- mirrors AntColony/BeeColony's own FORAGE_SUCCESS_EMA_RATE
## exactly, the identical "neither twitchy nor sluggish" reasoning.
const FORAGE_SUCCESS_EMA_RATE := 0.3

## A sustained recent-success EMA below this floor means the nest's own
## nearby forage has genuinely dried up, not just one unlucky trip --
## the one absconding trigger a wild nest keeps (see bees.md's own
## "Wild bee nests": no honey to lose, just a real, if less dramatic,
## reason to choose a different hole).
const RELOCATE_FORAGE_THRESHOLD := 0.1

## The founding resident: one female, alone, working her own hole.
const STARTING_RESIDENTS := 1.0

## A freshly-seeded (or freshly relocated-to) nest's own starting
## forage-success EMA -- deliberately NEUTRAL, not 0.0 (which
## should_relocate_at would misread as "already failing," see that
## method's own doc comment): a real solitary bee choosing a new hole
## picked it because the spot looked viable, she has not yet "learned"
## it is barren the way a sustained run of real failed trips would
## teach her. Above RELOCATE_FORAGE_THRESHOLD by construction, so a
## brand new nest is never born already flagged for relocation.
const STARTING_FORAGE_SUCCESS := 0.5

## How many residents worth of brood a single nest hole can plausibly
## support before it reads as genuinely crowded -- real solitary bees do
## nest gregariously (several females sharing the same favourable patch
## of deadwood, each still working her own hole), so a modest handful
## rather than one is the correct real ceiling.
const MAX_RESIDENTS_PER_NEST := 3.0

## Chance, per call to advance(), that a nest with real sustained forage
## success gains one more resident -- small and per-step, the same
## "ongoing background activity, not a single guaranteed burst" shape
## FORAGE_CHANCE/BeeColony.BUD_CHANCE already use.
const GROWTH_CHANCE := 0.02

const _FORAGE_SALT := 51797
const _GROWTH_SALT := 900403

var _width: int
var _height: int
var _biome: PackedStringArray
var _seed_value: int
var _step_count: int = 0

## Vector2i cell -> true. The nest holes a chunk seeds at construction --
## fixed until relocate_to moves one, mirroring BeeColony._hives'
## identical shape.
var _nests: Dictionary = {}
var _residents: Dictionary = {}
var _forage_success: Dictionary = {}

## Per-cell warmth EMA, mirroring AntColony/BeeColony.record_warmth
## exactly -- see record_warmth's own doc comment for the weight.
var _warmth: Dictionary = {}
## Whether this nest is CURRENTLY in its winter die-off state -- tracked
## explicitly (not re-derived from warmth alone) so the residents-to-brood
## and brood-to-residents transitions in advance() each fire exactly ONCE
## per real crossing of EarthwormPatch.COLD_CUTOFF, not every tick while
## warmth stays on one side of it.
var _dormant: Dictionary = {}
## The hidden overwintering brood a nest banked the moment it last went
## dormant -- what residents_at() re-hatches FROM in spring (see
## advance()'s own die-off/re-hatch block). Not a literal egg/larva
## count, the same abstraction level `_residents` already sits at.
var _brood: Dictionary = {}

## Mirrors AntColony/BeeColony.SECONDS_PER_SIMULATED_DAY exactly.
const SECONDS_PER_SIMULATED_DAY := 60.0


func _init(seed_value: int, width: int, height: int, biome: PackedStringArray) -> void:
	_seed_value = seed_value
	_width = width
	_height = height
	_biome = biome
	_seed_initial_nests()


func nest_cells() -> Array:
	return _nests.keys()


func has_nest(cell: Vector2i) -> bool:
	return _nests.has(cell)


## Mirrors BeeColony's own _retired/mark_retired/is_retired trio exactly
## (see that class's own doc comments for the full reasoning) -- a
## per-OBJECT flag, set once by EarthChunkManager._unload_chunk the moment
## this patch's own _wild_bee_patches[chunk_coord] entry is erased, so a
## still-in-flight BeeForagerMarker resolving a lone resident's real trip
## (_resolve_arrival_at_hive) can notice its own nest's chunk is gone
## rather than silently touching an object nobody can reach any more.
## WildBeePatch gets its own duplicate flag/methods rather than sharing
## BeeColony's, the same "no shared base class" choice this whole file's
## own header doc comment already makes for every other mechanism.
var _retired := false


func mark_retired() -> void:
	_retired = true


func is_retired() -> bool:
	return _retired


func residents_at(cell: Vector2i) -> float:
	return _residents.get(cell, STARTING_RESIDENTS)


func forage_success_at(cell: Vector2i) -> float:
	return _forage_success.get(cell, STARTING_FORAGE_SUCCESS)


func brood_at(cell: Vector2i) -> float:
	return _brood.get(cell, 0.0)


func is_dormant_at(cell: Vector2i) -> bool:
	return _dormant.get(cell, false)


## Mirrors AntColony/BeeColony.record_warmth exactly -- same soil, same
## real climate+season signal (see EarthChunkManager._refresh_bee_warmth,
## which now drives both). Same weight as FORAGE_SUCCESS_EMA_RATE (see
## that constant's own doc comment): warmth is not structurally twitchier
## or sluggisher than forage success either.
func record_warmth(cell: Vector2i, warmth: float) -> void:
	var current: float = _warmth.get(cell, 1.0)
	_warmth[cell] = lerpf(current, clampf(warmth, 0.0, 1.0), FORAGE_SUCCESS_EMA_RATE)


## Records whether one resident's real foraging trip actually found
## nectar -- mirrors AntColony/BeeColony.record_forage_result's own EMA
## shape exactly, without a honey deposit: a wild nest has nowhere to
## store surplus at all (see bees.md).
func record_forage_result(cell: Vector2i, succeeded: bool) -> void:
	var current: float = _forage_success.get(cell, STARTING_FORAGE_SUCCESS)
	var target := 1.0 if succeeded else 0.0
	_forage_success[cell] = lerpf(current, target, FORAGE_SUCCESS_EMA_RATE)


## Grows the resident count on a small per-step chance, gated on real
## sustained forage success -- never above MAX_RESIDENTS_PER_NEST, and
## never at all without real forage success feeding it (a nest with no
## track record yet defaults to 0.0, the same "unset EMA reads as no
## luck yet" fallback BeeColony's own _forage_success already has).
func advance(delta_seconds: float) -> void:
	_step_count += 1
	for cell in _nests:
		_step_dormancy(cell)
		if is_dormant_at(cell):
			continue
		# Growth needs a real, actually-recorded trip -- the neutral
		# forage_success_at default (see STARTING_FORAGE_SUCCESS) answers
		# "is this nest failing" honestly for should_relocate_at, but must
		# never itself count as evidence of real success for growth.
		if not _forage_success.has(cell):
			continue
		if forage_success_at(cell) <= 0.0:
			continue
		if residents_at(cell) >= MAX_RESIDENTS_PER_NEST:
			continue
		if PixelNoise.unit(_seed_value + _step_count + _GROWTH_SALT, cell.x, cell.y) < GROWTH_CHANCE:
			_residents[cell] = minf(MAX_RESIDENTS_PER_NEST, residents_at(cell) + 1.0)


## The seasonal die-off/re-hatch transition (see docs/concept/
## seasonal_behavior.md, "Wild bee die-off / re-hatch"): a genuinely
## different mechanism shape from AntColony/BeeColony's smooth dormancy_
## multiplier_at throttle -- real solitary bees' adults do not survive a
## freezing winter at all, so this is a population EVENT fired exactly
## once per real crossing of EarthwormPatch.COLD_CUTOFF (using _dormant to
## remember which side of it a nest was on last tick, rather than
## re-deriving it from warmth alone, which would re-fire every tick while
## warmth stays on one side).
func _step_dormancy(cell: Vector2i) -> void:
	var warmth: float = _warmth.get(cell, 1.0)
	var cold := warmth <= EarthwormPatch.COLD_CUTOFF
	var was_dormant := is_dormant_at(cell)
	if cold and not was_dormant:
		# Going into winter: the current resident count IS this year's
		# brood -- what carries to spring is exactly how many cells they
		# provisioned. No overwinter brood mortality modelled (a real,
		# named simplification, see seasonal_behavior.md's deferred
		# follow-ups) -- residents never drops below STARTING_RESIDENTS
		# except via this exact transition, so what gets banked here is
		# always >= it, and re-hatching directly from it below needs no
		# separate floor.
		_brood[cell] = residents_at(cell)
		_residents[cell] = 0.0
		_dormant[cell] = true
	elif not cold and was_dormant:
		# Coming out of winter: a fresh generation of adults emerges from
		# last year's brood, inheriting how good last season was rather
		# than resetting to a fixed seed every year.
		_residents[cell] = brood_at(cell)
		_dormant[cell] = false


## Whether a resident forages nearby THIS step -- mirrors
## AntColony/BeeColony.should_forage exactly, a pure PixelNoise-seeded
## roll. A dormant nest has no one home to send out at all (see
## _step_dormancy) -- residents_at already reads 0.0 for one, but this
## short-circuits before even rolling, the same "cluster and barely feed
## at all" reasoning AntColony/BeeColony's own should_forage fix used.
func should_forage(cell: Vector2i) -> bool:
	if is_dormant_at(cell):
		return false
	return PixelNoise.unit(_seed_value + _step_count + _FORAGE_SALT, cell.x, cell.y) < FORAGE_CHANCE


## The one absconding trigger a wild nest keeps (see this file's own
## header doc comment and bees.md's "Wild bee nests") -- a sustained,
## not momentary, lack of real nearby forage.
func should_relocate_at(cell: Vector2i) -> bool:
	if not has_nest(cell):
		return false
	return forage_success_at(cell) < RELOCATE_FORAGE_THRESHOLD


## Moves this nest's own real resident count to a freshly-searched new
## site -- mirrors BeeColony.abscond_to's own "carry the real numbers
## over, no-op at an invalid destination" shape exactly, minus the honey
## half (there is none). The forage-success EMA does NOT carry over --
## a fresh site gets a fresh trial, the same "no track record yet"
## default every new cell already reads as.
func relocate_to(from_cell: Vector2i, to_cell: Vector2i) -> void:
	if not is_valid_nest_site(to_cell):
		return
	var residents := residents_at(from_cell)
	_nests.erase(from_cell)
	_residents.erase(from_cell)
	_forage_success.erase(from_cell)
	_nests[to_cell] = true
	_residents[to_cell] = residents


## Mirrors BeeColony.is_valid_hive_site exactly, against NEST_BIOMES.
func is_valid_nest_site(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.x >= _width or cell.y < 0 or cell.y >= _height:
		return false
	if _nests.has(cell):
		return false
	return NEST_BIOMES.has(_biome[cell.y * _width + cell.x])


## Mirrors BeeColony._seed_initial_hives exactly, minus the honey/food
## reserve seeding (there is none): every nest founds at STARTING_
## RESIDENTS, a single resident female already established, the same
## "map-generated content starts already established" convention every
## patch-sim in this game follows.
func _seed_initial_nests() -> void:
	for y in _height:
		for x in _width:
			if _nests.size() >= MAX_NESTS:
				return
			if not NEST_BIOMES.has(_biome[y * _width + x]):
				continue
			if PixelNoise.unit(_seed_value, x, y) >= NEST_CHANCE:
				continue
			var cell := Vector2i(x, y)
			_nests[cell] = true
			_residents[cell] = STARTING_RESIDENTS
