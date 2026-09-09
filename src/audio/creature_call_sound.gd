extends RefCounted

## Per-species vocalizations (see docs/concept/creature_and_footstep_audio.md).
## Reported live: "each animal should have an individual sound.. (horse,
## robin, boar, sparrow) etc." Pure species->clip lookup + an occasional
## chance-per-check gate, no AudioStreamPlayer/Node dependency -- the same
## "pure model, thin Node" split every other audio module in this codebase
## (`nature_soundscape.gd`, `footstep_sound.gd`) already uses.
##
## Real-world grounding decides which species get an entry at all, the
## same discipline `docs/concept/soundscape.md`'s pillar 3 already applies
## to ambient layers: insects (ants, decomposer bugs, millipede,
## caterpillars, worms), fish, and butterflies are inaudible to a nearby
## human in reality, so they get no entry here rather than a fabricated
## sound just for uniform coverage -- see docs/concept/creature_and_
## footstep_audio.md for the species survey this is scoped from.
##
## A species with no real recording sourced yet simply never calls
## (silent, not an error) -- graceful partial coverage, matching
## `docs/concept/soundscape.md`'s own "ship what's actually sourced, flag
## the rest" convention rather than blocking every species on 100%
## coverage in one pass. See CREDITS.md for attribution and any real-world
## substitutions (e.g. a domestic pig recording standing in for boar --
## same species, Sus scrofa) made where a genuinely species-specific
## recording wasn't available.
const _CLIP_BY_SPECIES := {
	"horse": "res://assets/audio/creatures/horse.ogg",
	"boar": "res://assets/audio/creatures/boar.ogg",
	"sheep": "res://assets/audio/creatures/sheep.ogg",
	"wolf": "res://assets/audio/creatures/wolf.ogg",
	"bear": "res://assets/audio/creatures/bear.ogg",
	"squirrel": "res://assets/audio/creatures/squirrel.ogg",
	"deer": "res://assets/audio/creatures/deer.ogg",
	"robin": "res://assets/audio/creatures/robin.ogg",
	"sparrow": "res://assets/audio/creatures/sparrow.ogg",
	"kingfisher": "res://assets/audio/creatures/kingfisher.mp3",
	# Real bumblebee buzz standing in for both -- a live worker bee's own
	# buzz doesn't differ audibly between managed honeybees and solitary
	# wild bees at this game's scale (see CREDITS.md).
	"honeybee": "res://assets/audio/creatures/bee.ogg",
	"wild_bee": "res://assets/audio/creatures/bee.ogg",
}

## Real bird/mammal calls are occasional events, not continuous -- the
## same `is_eligible`/`check` chance-per-check shape `KrakenTrigger`/
## `NatureSoundscape`'s own hawk-call cameo already use, so a creature
## doesn't vocalize every single check while on screen. 0.01 is a real,
## deliberately low starting point (roughly one call per ~100 checks) --
## not measured against a specific real call-frequency study the way
## e.g. `NatureSoundscape.HAWK_CALL_CHANCE_PER_CHECK` was, but pinned by
## test_call_chance_per_check_is_low_not_constant so it can't silently
## drift toward "constant noise" or "never happens" unnoticed.
const CALL_CHANCE_PER_CHECK := 0.01


static func has_call(species: String) -> bool:
	return _CLIP_BY_SPECIES.has(species)


static func clip_path_for(species: String) -> String:
	return String(_CLIP_BY_SPECIES.get(species, ""))


## `roll` is caller-supplied (the same "caller rolls, this decides"
## split every other chance-gated cameo in this codebase already uses)
## so this stays pure and deterministically testable. A species with no
## sourced call can never fire regardless of how favorable the roll is --
## checked first, before spending the roll on a threshold compare, so a
## silent species reads as "nothing to play," not "always misses."
static func check_call(species: String, roll: float) -> bool:
	if not has_call(species):
		return false
	return roll < CALL_CHANCE_PER_CHECK
