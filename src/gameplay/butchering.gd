extends RefCounted

## Which parts a carcass yields, in the order a swing removes them, and how
## much meat a skilled cut gets out of the same carcass -- see
## docs/concept/carrion.md, SkillTree's butchering_1/2 nodes. Pure and
## engine-free like every other tuned-logic module in this codebase.

## hide -> skin cut first (real butchery does this, and it's in the way of
## everything else); meat -> the muscle cut; guts -> the viscera, last,
## because unlike the other two it doesn't become an inventory item -- it
## spawns a real world entity (see CarcassGuts) rather than dropping.
const PART_ORDER := ["hide", "meat", "guts"]

const HIDE_COUNT := 1
const BASE_MEAT_COUNT := 2


static func hits_required() -> int:
	return PART_ORDER.size()


## Which part hit index `hit_index` removes -- "" past the last one or for a
## negative index, so a caller can just check for an empty string rather
## than bounds-check itself.
static func part_for_hit(hit_index: int) -> String:
	if hit_index < 0 or hit_index >= PART_ORDER.size():
		return ""
	return PART_ORDER[hit_index]


## How much meat one butchering yields, boosted by an allocated meat_yield
## skill bonus (see SkillTree.total_bonus) -- a trained cut wastes less of
## the same carcass. Rounded to a whole item count.
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
static func meat_count(meat_yield_bonus: float, mass_ratio: float = 1.0) -> int:
	return int(round((BASE_MEAT_COUNT + meat_yield_bonus) * maxf(mass_ratio, 0.0)))
