extends RefCounted

## Pure per-chunk wild-crop simulation (carrot, potato) -- see
## docs/concept/wild_crops.md. Deliberately near-identical to TallGrass's own
## contract (seed on grassland at chunk creation, grow 0..1 over time, spread
## into adjacent grassland on a throttled tick) rather than a new shape:
## a wild root crop and wild grass are the same kind of thing in this world
## sim, just rarer and slower.
##
## One instance per chunk PER CROP (a chunk holds a separate carrot sim and
## potato sim, not one sim juggling both) -- `crop_id` folds into every hash
## so two crops seeded with the same chunk seed_value don't correlate.
##
## No animal-carried seed dispersal (TallGrass's mouse scatter-hoarding
## equivalent) -- spreading here is purely the adjacent-cell throttled tick,
## a deliberate scope cut (see the concept doc's Status list).

const TallGrass = preload("res://src/world/tall_grass.gd")
const TreeGenome = preload("res://src/gameplay/tree_genome.gd")

## Chance (0..1) a given grassland cell starts with a crop patch. Well below
## TallGrass.SEED_CHANCE (0.20) -- a meadow is mostly grass with the
## occasional carrot in it, not the other way around. Pinned below
## TallGrass.SEED_CHANCE by test_seed_chance_and_cap_are_far_rarer_than_grass
## rather than left an eyeballed comment (CLAUDE.md).
const SEED_CHANCE := 0.03

## Hard cap on patches per chunk -- lower than TallGrass.MAX_PATCHES (205),
## a wild crop population is meant to read as scattered finds, not a field.
const MAX_PATCHES := 20

## A root crop's real growing season is meaningfully longer than a grazed
## grass tuft's regrowth time; this pins that as an explicit, tested ratio
## against TallGrass.GROWTH_RATE rather than an independent eyeballed
## number (CLAUDE.md).
const GROWTH_RATE_SLOWDOWN := 4.0
## Growth (0..1) gained per second of advance().
const GROWTH_RATE := TallGrass.GROWTH_RATE / GROWTH_RATE_SLOWDOWN

## Seconds between spread ticks -- slower than TallGrass.SPREAD_INTERVAL
## (30s): a scattered wild crop find spreads more gradually than a grass
## field regrowing.
const SPREAD_INTERVAL := 90.0
## Max new patches created per spread tick.
const SPREAD_PER_TICK := 1

## Every crop that shares the wild-crop cell space, in a fixed order --
## used ONLY to partition territory (see _in_this_crops_territory) so two
## crops seeded independently can never claim the same cell. Reported live:
## "carrots render potatoes as crop" -- two markers stacked on the exact
## same tile, one per crop, each seeded with no knowledge of the other,
## read as one confused/wrong plant. Must list every crop_id ever passed to
## WildCropPatch.new -- an id missing from this list silently never gets
## any cells. Mirrors EarthChunkManager.WILD_CROP_IDS; the two lists must
## be kept in sync (only 2 crops exist today, so this coupling is cheap;
## worth a real shared source of truth if a third crop is ever added).
const _CROP_TERRITORY_ORDER := ["carrot", "potato"]

## Root Vigor -- a heritable size/quality trait, same "average of two
## salted-hash draws" bell shape FlyerPersonality._bell uses for boldness
## (FlyerPersonality.BELL_HALVES), mirrored here rather than reinvented so
## the same "unremarkable middle at 0.5, real spread either side" statistical
## shape applies. Two draws (not one) is what makes the distribution a real
## bell rather than a flat 0..1 -- see get_vigor's own doc comment for the
## default this produces for an unplanted cell.
##
## _seed_vigor deliberately does NOT copy FlyerPersonality._unit's own salt
## shape byte-for-byte, though -- see AnimalGenome._unit's doc comment
## (src/gameplay/animal_genome.gd): two salts identical except for one
## trailing digit ahead of an otherwise-fixed suffix come out CORRELATED
## under Godot's String hash, not independent, which fattens the
## distribution's tails well past a true two-draw average (measured r=0.57
## for AnimalGenome's own "_animal_genome" suffix; FlyerPersonality's
## "_personality" shape happens to measure a milder r=0.26, low enough to
## scrape under ITS OWN tests' budget by luck, not by design -- so mirroring
## it byte-for-byte here would have carried the same latent bug forward
## without any of this crop code's own tests being tight enough to catch
## it by luck too). This crop's own
## test_prize_threshold_actually_selects_about_the_top_decile_of_seeded_vigor
## (test_wild_crop_marker.gd) DID catch it empirically the first time
## (measured ~22.75% at/above the promised top decile, not ~10%) before
## _seed_vigor was changed to vary salt LENGTH per half
## ("x".repeat(half + 1), AnimalGenome's own fix) instead of its trailing
## digit.
const VIGOR_BELL_HALVES := 2

## How far a spread child's vigor can drift from its parent's, as a fraction
## of vigor's own 0..1 range -- mirrors TreeGenome.MUTATION_AMOUNT's exact
## "nudge by a clamped random direction x this amount x range" shape.
## Reusing TreeGenome's own already-tested constant value directly (rather
## than an independently chosen number) rather than a second, arbitrary
## figure with no relationship to the first -- both are "how much can one
## generation's heritable trait drift from its parent's" and there is no
## reason a root crop's vigor should drift at some other unrelated rate.
const VIGOR_MUTATION_AMOUNT := TreeGenome.MUTATION_AMOUNT


## Whether cell (x, y) belongs to `crop_id`'s share of the partition --
## every grassland cell in the world belongs to EXACTLY ONE crop's
## territory (or, for a crop_id missing from _CROP_TERRITORY_ORDER, to
## none), independent of any particular chunk's own seed_value, so two
## sims covering the SAME chunk can never both claim the same cell.
static func _in_this_crops_territory(crop_id: String, x: int, y: int) -> bool:
	var index := _CROP_TERRITORY_ORDER.find(crop_id)
	if index < 0:
		return false
	var bucket := absi(hash("%d_%d_wild_crop_territory" % [x, y])) % _CROP_TERRITORY_ORDER.size()
	return bucket == index

var _crop_id: String
var _width: int
var _height: int
var _biome: PackedStringArray
var _seed_value: int

## Vector2i cell -> growth float (0..1; 1 is mature).
var _patches: Dictionary = {}
## Vector2i cell -> vigor float (0..1) -- Root Vigor, a heritable size/quality
## trait, independent of growth (see docs/concept/wild_crops.md's "Root
## Vigor" section and get_vigor's own doc comment for the default).
var _vigor: Dictionary = {}
var _spread_accumulator := 0.0
var _spread_tick := 0


func _init(crop_id: String, seed_value: int, width: int, height: int, biome: PackedStringArray) -> void:
	_crop_id = crop_id
	_seed_value = seed_value
	_width = width
	_height = height
	_biome = biome
	_seed_initial_patches()


func get_patch_cells() -> Array:
	return _patches.keys()


func has_crop(cell: Vector2i) -> bool:
	return _patches.has(cell)


func get_growth(cell: Vector2i) -> float:
	return _patches.get(cell, 0.0)


## Root Vigor for `cell`, 0..1 -- a heritable size/quality trait, distinct
## from growth (how far along THIS specimen is) the same way FlyerPersonality
## keeps boldness distinct from age. Defaults to 0.5, the unremarkable
## middle, for any cell not in `_vigor` -- an unplanted cell, or a save from
## before vigor existed -- same convention FlyerPersonality.boldness_of
## already uses for an empty trait dictionary.
func get_vigor(cell: Vector2i) -> float:
	return _vigor.get(cell, 0.5)


## Advances growth on every patch and, on a throttled interval, lets mature
## patches spread into adjacent grassland cells. Mirrors TallGrass.advance
## (and FlowerPatch/DesertScrub/TundraLichen's identical shape), including
## how `growth_modifier` (see SeasonCycle.growth_modifier) scales only the
## growth increment, never spread timing -- spread stays on the wall clock
## across all five patch sims, a deliberate, tested, cross-species
## consistency (see test_advance_grows_slower_in_winter_than_in_summer_for_
## the_same_elapsed_time's siblings in each patch type's own test file).
##
## A root crop does not STOP growing in winter, it goes dormant:
## growth_modifier's own floor is 0.2, not 0, the "modulates, doesn't gate"
## rule docs/concept/seasons.md sets out. A crop already mature stays mature
## and stays pullable -- the tops die back, the tuber overwinters
## underground.
func advance(delta: float, growth_modifier: float) -> void:
	for cell in _patches:
		_patches[cell] = minf(_patches[cell] + delta * GROWTH_RATE * growth_modifier, 1.0)

	_spread_accumulator += delta
	while _spread_accumulator >= SPREAD_INTERVAL:
		_spread_accumulator -= SPREAD_INTERVAL
		_spread_tick += 1
		_step_spread()


## Removes the patch at `cell`, returning true if there was a crop to pull.
## Also forgets its vigor -- a grazed cell has no crop growing in it any
## more, so a re-query (or a re-seed of the same cell some other way) must
## not see a stale value left behind by whatever grew there before.
func graze(cell: Vector2i) -> bool:
	_vigor.erase(cell)
	return _patches.erase(cell)


## A founding cell's own Root Vigor -- the average of VIGOR_BELL_HALVES
## independent salted-hash draws (see VIGOR_BELL_HALVES's own doc comment
## for why the two salts vary by LENGTH, "x".repeat(half + 1), rather than
## by trailing digit).
func _seed_vigor(x: int, y: int) -> float:
	var total := 0.0
	for half in VIGOR_BELL_HALVES:
		var salted := "%s_%d_%d_%d_vigor_%s" % [_crop_id, _seed_value, x, y, "x".repeat(half + 1)]
		total += float(absi(hash(salted)) % 10000) / 10000.0
	return total / float(VIGOR_BELL_HALVES)


## A spread child's Root Vigor: the parent's own vigor, nudged by up to
## VIGOR_MUTATION_AMOUNT of vigor's 0..1 range in a clamped random
## direction -- exactly TreeGenome._nudge's shape. `salt` must be unique per
## spread attempt (see _step_spread's callsite) so two children spreading on
## the same tick from the same parent don't inherit an identical mutation.
func _nudge_vigor(parent_vigor: float, salt: String) -> float:
	var direction := (float(absi(hash("%s_vigor_dir" % salt)) % 10000) / 10000.0 - 0.5) * 2.0  # -1..1
	return clampf(parent_vigor + direction * VIGOR_MUTATION_AMOUNT, 0.0, 1.0)


func _seed_initial_patches() -> void:
	for y in _height:
		for x in _width:
			if _patches.size() >= MAX_PATCHES:
				return
			if _biome[y * _width + x] != "grassland":
				continue
			if not _in_this_crops_territory(_crop_id, x, y):
				continue
			var roll := float(absi(hash("%s_%d_%d_%d_crop_seed" % [_crop_id, _seed_value, x, y])) % 10000) / 10000.0
			if roll < SEED_CHANCE:
				var cell := Vector2i(x, y)
				# Initial crops start mature, like map-generated grass/trees.
				_patches[cell] = 1.0
				_vigor[cell] = _seed_vigor(x, y)


func _step_spread() -> void:
	var mature: Array = []
	for cell in _patches:
		if _patches[cell] >= 1.0:
			mature.append(cell)
	if mature.is_empty():
		return

	for i in SPREAD_PER_TICK:
		if _patches.size() >= MAX_PATCHES:
			return
		var h := absi(hash("%s_%d_%d_%d_crop_spread" % [_crop_id, _seed_value, _spread_tick, i]))
		var parent: Vector2i = mature[h % mature.size()]
		var directions := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
		var target: Vector2i = parent + directions[(h / 7) % directions.size()]
		if target.x < 0 or target.x >= _width or target.y < 0 or target.y >= _height:
			continue
		if _biome[target.y * _width + target.x] != "grassland":
			continue
		if not _in_this_crops_territory(_crop_id, target.x, target.y):
			continue
		if _patches.has(target):
			continue
		_patches[target] = 0.0  # spread crops start immature and must grow
		var mutation_salt := "%s_%d_%d_%d_vigor" % [_crop_id, _seed_value, _spread_tick, i]
		_vigor[target] = _nudge_vigor(_vigor.get(parent, 0.5), mutation_salt)
