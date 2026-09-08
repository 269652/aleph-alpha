extends RefCounted

## Ambient nature soundscape mixing -- see docs/concept/soundscape.md for the
## full design (real-world grounding, layered-composition rationale, the
## exact rule tables this implements). Pure decision logic, no scene/node/
## EarthChunkManager dependency -- same "caller does the real-world
## computation, this module only decides" shape as KrakenTrigger/
## EasterEggSightings' own is_night handling, so this is fully unit-testable
## with plain String/bool inputs.

## Every asset this system can play. Flat by design (not nested per biome):
## a "layer" is an independent, separately-volumed thing that can be active
## at once alongside any other -- see docs/concept/soundscape.md's own
## "Layered composition, not a lookup table" pillar.
const LAYERS := {
	"ocean": "res://assets/audio/soundscape/ocean.ogg",
	"forest_day": "res://assets/audio/soundscape/forest_day.mp3",
	"forest_winter": "res://assets/audio/soundscape/forest_winter.mp3",
	"grassland_day": "res://assets/audio/soundscape/grassland_day.mp3",
	"rainforest_day": "res://assets/audio/soundscape/rainforest_day.wav",
	"rainforest_night": "res://assets/audio/soundscape/rainforest_night.ogg",
	"temperate_night": "res://assets/audio/soundscape/temperate_night.ogg",
	"wind": "res://assets/audio/soundscape/wind.ogg",
	"rain": "res://assets/audio/soundscape/rain.ogg",
	"storm": "res://assets/audio/soundscape/storm.ogg",
	"mountain_hawk_call": "res://assets/audio/soundscape/mountain_hawk_call.ogg",
}

## Real tuned constants (design decisions from docs/concept/soundscape.md's
## own mechanism tables, pinned by test_nature_soundscape.gd rather than left
## as eyeballed comments).
##
## Grassland's winter cut, not swap: real crickets/bumblebees go quiet in
## winter, but no dedicated grassland-winter recording was sourced (unlike
## forest, which has one) -- see docs/concept/soundscape.md's own bed table.
const GRASSLAND_WINTER_VOLUME := 0.2

## Desert/tundra/mountain share ONE wind recording (see docs/concept/
## soundscape.md's real-world grounding: the acoustic difference between
## them is what else ISN'T layered on top, not the wind itself) at three
## distinct, pinned volumes rather than one flat shared number -- tundra
## (the starkest, coldest of the three) is loudest, desert quietest.
const DESERT_WIND_VOLUME := 0.7
const TUNDRA_WIND_VOLUME := 1.0
const MOUNTAIN_WIND_VOLUME := 0.85

## Reference full-bed volume -- every bed plays at this unless a rule above
## (grassland's winter cut) says otherwise.
const FULL_BED_VOLUME := 1.0


## The complete set of layers that should be audible right now, as
## {layer_name: volume}. Omits anything that should NOT be playing entirely
## (never lists a layer at 0.0) so a caller can crossfade toward exactly this
## set and stop everything else -- see docs/concept/soundscape.md's
## "Playback" section.
func layer_mix(
	biome: String, season: String, _weather: String, is_night: bool, _is_snowing: bool
) -> Dictionary:
	return _biome_bed(biome, season, is_night)


## The one biome bed layer -- see docs/concept/soundscape.md's own bed table
## for the exact day/night/season rule per biome.
func _biome_bed(biome: String, season: String, is_night: bool) -> Dictionary:
	match biome:
		"ocean":
			# Waves don't follow the calendar or the clock.
			return {"ocean": FULL_BED_VOLUME}
		"forest":
			if is_night:
				return {"temperate_night": FULL_BED_VOLUME}
			if season == "winter":
				return {"forest_winter": FULL_BED_VOLUME}
			return {"forest_day": FULL_BED_VOLUME}
		"grassland":
			if is_night:
				return {"temperate_night": FULL_BED_VOLUME}
			var volume := GRASSLAND_WINTER_VOLUME if season == "winter" else FULL_BED_VOLUME
			return {"grassland_day": volume}
		"rainforest":
			# Aseasonal by design -- see docs/concept/soundscape.md's real-
			# world grounding on why rainforest gets no winter swap.
			if is_night:
				return {"rainforest_night": FULL_BED_VOLUME}
			return {"rainforest_day": FULL_BED_VOLUME}
		"desert":
			return {"wind": DESERT_WIND_VOLUME}
		"tundra":
			return {"wind": TUNDRA_WIND_VOLUME}
		"mountain":
			return {"wind": MOUNTAIN_WIND_VOLUME}
		_:
			return {}


## STUB -- not yet implemented.
func hawk_call_eligible(_biome: String, _is_night: bool) -> bool:
	return false


## STUB -- not yet implemented.
func check_hawk_call(_biome: String, _is_night: bool, _roll: float) -> bool:
	return false
