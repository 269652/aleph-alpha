extends RefCounted

## When a creature would rather eat than fight (docs/concept/monsters.md,
## entry 11 -- the Nachzehrer).
##
## Every predator already notices a nearby carcass (CreatureMarker.
## _scan_carrion_stimuli, docs/concept/carrion.md's "opportunistic
## predator/omnivore" gap) -- carrion is just one more option alongside a
## live target, picked up the same CARRION channel every other predator
## already reads. This names the one species for which a corpse OUTRANKS a
## live target outright, rather than merely being noticed alongside one.
##
## Pure: which species this applies to, nothing about distance, stimuli,
## or a live creature -- the same one-line species-gate shape NightMare/
## EcologicalGrudge already use for their own "which species does this
## apply to" questions. The actual stimulus filtering this drives lives on
## CreatureMarker (_carrion_preference_filter), which is what needs a real
## stimulus list to operate on.

const PREFERS_CARRION := {"nachzehrer": true}


static func prefers_carrion(species: String) -> bool:
	return PREFERS_CARRION.has(species)
