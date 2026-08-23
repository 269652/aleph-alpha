extends RefCounted

## Which species /spawn accepts, and the friendly aliases it understands.
##
## The console used to validate against CreatureRenderer.SPECIES_COLORS --
## four entries, a leftover from before every species got a hand-tuned
## anatomy. Anything added to AnimalAnatomy since (deer, horse, bear, both
## snakes...) existed in the world but could not be summoned to look at,
## which is exactly backwards for a debug tool.
##
## Pure lookups so the roster can be tested without a running world.

const AnimalAnatomy = preload("res://src/rendering/animal_anatomy.gd")

## Short names for species whose real ids are qualified. Typing "/spawn
## snake" should work -- being made to guess "nonvenomous_snake" is exactly
## the friction a debug console exists to remove.
const ALIASES := {
	"snake": "nonvenomous_snake",
	"viper": "venomous_snake",
	"wolf": "wolf",
	"cat": "lynx",
}


func _init() -> void:
	pass


## The canonical species id for what the user typed, or "" if unknown.
static func resolve(typed: String) -> String:
	var key := typed.strip_edges().to_lower()
	var resolved: String = ALIASES.get(key, key)
	return resolved if AnimalAnatomy.SPECIES.has(resolved) else ""


## Everything /spawn will accept, for the help text and error messages.
static func spawnable() -> Array:
	var out: Array = []
	out.append_array(AnimalAnatomy.SPECIES)
	for alias in ALIASES:
		if not out.has(alias):
			out.append(alias)
	out.sort()
	return out
