extends RefCounted

const GroundSlide = preload("res://src/gameplay/ground_slide.gd")

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
## `cicada` is the deliberate exception among insects: real cicadas are
## among the loudest insects on Earth, easily audible at real distance --
## exactly the OPPOSITE of the silent-insects reasoning above, not a
## contradiction of it (see CicadaMarker/CicadaPopulation for the real,
## tree-anchored, summer-only population this species-key belongs to).
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
	# A real Cicada orni field recording, NOT one of this table's usual
	# CreatureMarker/AmbientFlyerMarker populations -- see CicadaMarker/
	# CicadaPopulation (docs/concept/creature_and_footstep_audio.md's
	# "Cicadas" section) for the real, tree-anchored, summer-only
	# population this species-key now belongs to as well.
	"cicada": "res://assets/audio/creatures/cicada.ogg",
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

## How far (world px) a creature must be from the player to even be
## considered for a call at all -- "nearby", not anywhere in the loaded
## world. Reported live: "you hear a lot of birds even though there
## aren't any... compose the sound from what's actually around you" --
## scanning every loaded creature regardless of distance (the pre-fix
## behavior) is the literal bug that complaint describes.
##
## 35 real metres: further than World.CREATURE_PANELS_RADIUS's own ~20m
## ("wider than melee range... visibly on screen") since sound carries a
## little further than clear sight -- you can hear a bird or a distant
## howl before you can make out what it is -- but still a real, bounded
## "nearby" scope, not the whole loaded chunk radius. A documented
## relationship, not a shared code constant: World is a much heavier
## preload (the whole game orchestrator) than this pure audio module
## should ever pull in just to read one sibling radius.
##
## Converted via GroundSlide.PX_PER_METER, this project's one shared
## px/metre yardstick, rather than a second, independently-invented pixel
## count -- the same idiom every other real-world distance in this
## codebase already uses. This is an ELIGIBILITY gate, not a volume curve:
## actual loudness within this radius still varies continuously via
## Godot's own positional attenuation (see InteractionSfxPlayer's own
## max_distance wiring, tuned to match).
const AUDIBLE_RADIUS_METERS := 35.0
const AUDIBLE_RADIUS_PX := AUDIBLE_RADIUS_METERS * GroundSlide.PX_PER_METER


static func has_call(species: String) -> bool:
	return _CLIP_BY_SPECIES.has(species)


static func clip_path_for(species: String) -> String:
	return String(_CLIP_BY_SPECIES.get(species, ""))


## `roll`/`distance_px` are caller-supplied (the same "caller measures the
## real world, this decides" split every other chance-gated cameo in this
## codebase already uses) so this stays pure and deterministically
## testable. A species with no sourced call, or a distance beyond
## AUDIBLE_RADIUS_PX, can never fire regardless of how favorable the roll
## is -- both checked before spending the roll on a threshold compare, so
## a silent/too-far creature reads as "nothing to play," not "always
## misses."
static func check_call(species: String, roll: float, distance_px: float) -> bool:
	if distance_px > AUDIBLE_RADIUS_PX:
		return false
	if not has_call(species):
		return false
	return roll < CALL_CHANCE_PER_CHECK
