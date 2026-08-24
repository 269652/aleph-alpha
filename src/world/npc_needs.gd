extends RefCounted

## An NPC's hunger need (docs/concept/npc.md "Needs and the local production
## economy": "NPCs get real hunger, not just villagers-as-scenery. Same
## shape as creature_needs.gd (hunger rises per second, is_hungry(),
## feed())") -- a genuinely new wiring for NpcMarker, which carries no needs
## state today, but the identical pattern already proven for wild/tamed
## animals, not a new design.
##
## Deliberately hunger-only: the spec's own scope is hunger, not thirst, so
## this mirrors CreatureNeeds' SHAPE (hash-seeded stagger via seed_value,
## per-second rise, is_hungry()/feed()) as a standalone module rather than
## reusing/extending CreatureNeeds itself -- bolting an unused thirst field
## onto an NPC would misrepresent what this pass actually simulates.

## Per-simulated-second rise rate -- same magnitude as
## CreatureNeeds.HUNGER_RATE_PER_SECOND (0.02), so a villager runs on the
## same lived-experience pace as any other creature in this world rather
## than a separately-tuned NPC clock. Verified behaviorally
## (test_becomes_hungry_once_past_the_threshold), not by asserting the
## number -- same convention as CreatureNeeds' own doc comment.
const HUNGER_RATE_PER_SECOND := 0.02

## An NPC actively seeks food (buys from the village market, or self-feeds
## if a producer -- see NpcEconomy) once hunger passes this fraction. Same
## value as CreatureNeeds.HUNGRY_THRESHOLD.
const HUNGRY_THRESHOLD := 0.5

var hunger := 0.0

## How far into its own hunger cycle a freshly-created NPC starts, at most.
## Same value and reasoning as CreatureNeeds.START_STAGGER: deliberately
## below HUNGRY_THRESHOLD (no NPC spawns already starving), high enough that
## a village's onsets spread across the run-up instead of every villager
## queuing at the market on the same tick.
const START_STAGGER := 0.45


## `seed_value` staggers where this individual starts in its own hunger
## cycle -- see START_STAGGER's doc comment. Defaults to 0 (exactly empty
## start) so a caller that doesn't care keeps the simplest behavior.
func _init(seed_value: int = 0) -> void:
	if seed_value == 0:
		return
	hunger = _stagger(seed_value)


## Hash-derived rather than RandomNumberGenerator, matching the deterministic
## "the same individual always rolls the same" idiom used throughout the
## world sim (CreatureNeeds, TallGrass, FlowerPatch, TreeGenome).
func _stagger(seed_value: int) -> float:
	var roll := float(absi(hash("%d_hunger_need" % seed_value)) % 10000) / 10000.0
	return roll * START_STAGGER


func advance(delta_seconds: float) -> void:
	hunger = clampf(hunger + HUNGER_RATE_PER_SECOND * delta_seconds, 0.0, 1.0)


func is_hungry() -> bool:
	return hunger >= HUNGRY_THRESHOLD


func feed() -> void:
	hunger = 0.0
