extends RefCounted

## Real average adult body mass, kilograms, per fish species -- see
## docs/concept/aquatic_foraging.md's "Revised (2026-09-07): real
## per-species diet and forage-coupled mass". The target FishGrowth grows a
## fish's own mass_kg toward, and (see docs/concept/fishing.md's own
## "Revised (2026-09-07)" section) the ceiling a caught fish's real weight
## is measured against.
##
## Mirrors CreatureMass._REAL_MASS_KG's own convention exactly (see that
## file's own doc comment) -- a real, commonly-cited reference figure for
## that real species, never invented.

## Real average adult body mass, kilograms, for every species
## ProceduralFishSprite can draw. Ordered smallest to largest.
##
## bluegill: a real North American sunfish rarely exceeds ~0.5kg; a
## representative adult is well under that.
## goldfish: common (non-fancy) goldfish, well-grown in open water rather
## than tank-stunted -- a real, substantial adult, not the small aquarium
## norm.
## trout: a representative adult catch weight (stocked rainbow trout
## commonly land in this range; wild browns vary more widely, but this is
## the honest "typical good catch" figure, not a trophy outlier).
## koi: real ornamental koi (domesticated carp) genuinely dwarf the other
## three species in this roster -- a representative mature pond koi, well
## short of a giant show specimen.
const _ADULT_MASS_KG := {
	"bluegill": 0.25,
	"goldfish": 0.4,
	"trout": 0.5,
	"koi": 3.5,
}

## Falls back here for any species this table hasn't caught up with --
## goldfish-scale, the roster's own middle-of-the-road reference, rather
## than a second invented number.
const _DEFAULT_MASS_KG := 0.4


static func mass_kg_for(species: String) -> float:
	return _ADULT_MASS_KG.get(species, _DEFAULT_MASS_KG)
