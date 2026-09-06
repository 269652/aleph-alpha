extends RefCounted

## Karma and Luck (see docs/concept/karma_and_luck.md).
##
## Karma is a permanent ledger of named events, changed by discrete calls
## from wherever those events actually happen (World's crush pass,
## QuestLog). Luck is a bounded [-1, 1] lens on Karma that existing
## deterministic formulas (Taming.break_free_chance, OreYield.yields) read
## -- never a new source of randomness. This project deliberately has no
## random rolls in its actual gameplay systems (see secret_d20.gd's own
## doc comment); Luck nudges numbers those formulas already produce, it
## never adds a new roll of its own.
##
## Pure and engine-free, matching every other rules module in this
## codebase (Taming, GroundForageBehavior, etc.) -- no nodes, no
## persistence, no RNG held here.

## Asked directly: "stepping on a worm should give -1 Karma." Applies
## identically to a caterpillar OR millipede crush -- CrushMechanic already
## treats all three as the same physical event (see its own doc comment,
## and docs/concept/soil_fauna.md's "Generalized to millipedes too"), and
## to either the player's own step or any creature's, since the request
## asked for every crush to count, not just the player's own deliberate
## ones. The constant's own name predates the millipede joining -- kept
## rather than renamed, since a rename would touch every already-shipped,
## tested call site for a purely cosmetic reason; this doc comment and
## karma_and_luck.md's own event table are the cross-reference.
const WORM_OR_CATERPILLAR_CRUSH_PENALTY := 1.0

## Asked directly: "Abandoning a quest as well [-1 Karma]."
const QUEST_ABANDON_PENALTY := 1.0

## Asked directly: "Helping an NPC +1 Karma" -- every quest this codebase
## actually implements today is literally one NPC's own stated need (see
## docs/concept/quests.md pillar 1), so fulfilling one and helping the NPC
## who asked for it are the same event, not two separate mechanisms.
const QUEST_FULFILLED_REWARD := 1.0

## Karma magnitude at which Luck saturates, in EITHER direction (so -15.0
## is the floor as much as 15.0 is the ceiling). Shares Taming.
## AFFINITY_CEILING's own value deliberately, not by coincidence: both
## represent "the practical ceiling of investing in this axis at all," so
## both use the same scale rather than each inventing its own.
const KARMA_CEILING := 15.0


## Karma -> Luck, always in [-1.0, 1.0]. Saturates at KARMA_CEILING in
## either direction -- bounded in both directions, so a lifetime of good
## deeds can bias a roll but never guarantee it, the same "harder, never
## impossible" principle Taming.AFFINITY_MAX_REDUCTION_FRACTION already
## established for a different stat.
static func luck_for(karma: float) -> float:
	return clampf(karma, -KARMA_CEILING, KARMA_CEILING) / KARMA_CEILING
