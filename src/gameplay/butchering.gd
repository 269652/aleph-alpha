extends RefCounted

## Which parts a carcass yields, in the order a swing removes them, and how
## much meat a skilled cut gets out of the same carcass -- see
## docs/concept/carrion.md, SkillTree's butchering_1/2 nodes. Pure and
## engine-free like every other tuned-logic module in this codebase.

const CreatureMass = preload("res://src/world/creature_mass.gd")

## hide -> skin cut first (real butchery does this, and it's in the way of
## everything else); meat -> the muscle cut; guts -> the viscera, last,
## because unlike the other two it doesn't become an inventory item -- it
## spawns a real world entity (see CarcassGuts) rather than dropping.
const PART_ORDER := ["hide", "meat", "guts"]

const HIDE_COUNT := 1
const BASE_MEAT_COUNT := 2

## The one animal this game had already costed, and its real live weight in
## kilograms. Everything else's cut is derived against this pair rather than
## hand-tuned per species, so adding a creature to a biome pool tomorrow
## cannot ship it worth nothing and nobody eyeballs eleven numbers.
##
## The mass is a literal because a GDScript const cannot call a function,
## and it is pinned against CreatureMass's own row by test
## (test_the_reference_mass_is_that_animals_own_real_mass) so the two cannot
## drift apart.
const REFERENCE_SPECIES := "boar"
const REFERENCE_MASS_KG := 90.0

## What fraction of a wild animal's live weight comes off it as usable meat.
##
## A real figure, not a game number: dressing percentage for wild game runs
## about 50-60% of live weight as carcass, of which roughly two-thirds is
## boned-out meat -- so about a third of the animal. Field-dressing guides
## for deer put the usable yield at 35-40% of live weight.
const EDIBLE_FRACTION := 0.35

## Kilograms of animal per "Raw Meat" item. Not chosen: the consequence of
## the reference row above (90 kg, two steaks), so the species the game had
## already balanced keeps exactly the count it had.
const KG_PER_MEAT := REFERENCE_MASS_KG * EDIBLE_FRACTION / float(BASE_MEAT_COUNT)


static func hits_required() -> int:
	return PART_ORDER.size()


## Which part hit index `hit_index` removes -- "" past the last one or for a
## negative index, so a caller can just check for an empty string rather
## than bounds-check itself.
static func part_for_hit(hit_index: int) -> String:
	if hit_index < 0 or hit_index >= PART_ORDER.size():
		return ""
	return PART_ORDER[hit_index]


## How many steaks an average `species` carcass carries, before any skill
## bonus or live-mass correction: its own real body mass through a real
## edible fraction, in the units the reference row fixes above.
##
## Fails OPEN on an animal the world has no mass for -- the flat count every
## caller got before this existed -- the same convention `mass_ratio` uses,
## and never less than one steak: a kill worth nothing at all is the exact
## thing deriving this was meant to prevent.
static func base_meat_for(species: String) -> int:
	if not CreatureMass.knows(species):
		return BASE_MEAT_COUNT
	var mass := CreatureMass.mass_kg_for(species)
	if mass <= 0.0:
		return BASE_MEAT_COUNT
	return maxi(1, int(roundf(mass * EDIBLE_FRACTION / KG_PER_MEAT)))


## How much meat one butchering yields: the species' own cut
## (`base_meat_for`), boosted by an allocated meat_yield skill bonus (see
## SkillTree.total_bonus) -- a trained cut wastes less of the same carcass --
## and scaled by how heavy this particular animal really was. Rounded to a
## whole item count.
##
## `species` defaults to "" (the flat reference count) so every caller that
## predates it behaves exactly as before.
##
## `mass_ratio` is the killed animal's own real, live, unified mass at
## time of death (docs/concept/metabolism.md) relative to its species'
## CreatureMass reference -- default 1.0 (the flat, mass-blind count every
## caller predating this parameter still gets) so a real, well-fed kill
## yields more meat and a starved one yields less, instead of every same-
## species carcass giving the identical amount regardless of how healthy
## the animal actually was. Clamped to never go negative (a real ratio
## can't -- Metabolism's own starvation floor keeps it well above zero --
## but this is checked for real rather than assumed).
static func meat_count(
	meat_yield_bonus: float, mass_ratio: float = 1.0, species: String = ""
) -> int:
	return int(round((base_meat_for(species) + meat_yield_bonus) * maxf(mass_ratio, 0.0)))
