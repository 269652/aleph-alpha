extends RefCounted

## What kind of cave system, if any, lies under a given place (see
## docs/concept/underground.md).
##
## The one entry point the rest of the game needs from the cave-generation
## stack. It composes three independent answers, each of which is a real
## question about the world rather than a knob:
##
##   Lithology     can a cave exist here at all -- does the rock dissolve,
##                 and is it exposed or under permeable cover
##   CaveRecharge  how does water get into it
##   CavePattern   what does that carve (Palmer 1991)
##
## The honest majority answer is PATTERN_NONE: soluble rock is ~16.5% of
## continental bedrock, so most of the planet has nothing underneath it,
## which is what makes finding a cave system mean something.

const Lithology = preload("res://src/world/lithology.gd")
const CaveRecharge = preload("res://src/world/cave_recharge.gd")
const CavePattern = preload("res://src/world/cave_pattern.gd")

var _lithology := Lithology.new()
var _recharge := CaveRecharge.new()
var _pattern := CavePattern.new()


## The Palmer pattern of the cave system under this tile, or
## PATTERN_NONE where there is none.
##
## Every parameter after the coordinates is a real signal this world
## already computes or can derive: `relief` from terrain_relief.md's slope
## field, `has_sinking_channel` from a surface watercourse meeting soluble
## rock (hydrology.md / rivers.md), `seasonality` from the climate
## simulation's own precipitation swing, `hydrothermal_proximity` from how
## close geology.md's hydrothermal layer rises, and `coast_distance_km`
## from the nearest ocean cell.
func pattern_at(
	global_x: int,
	global_y: int,
	relief: float,
	has_sinking_channel: bool,
	seasonality: float,
	hydrothermal_proximity: float,
	coast_distance_km: float
) -> String:
	var rock := _lithology.rock_at(global_x, global_y, relief)
	if _lithology.solubility_of(rock) <= 0.0:
		# No point asking how the water gets in when nothing dissolves.
		return CavePattern.PATTERN_NONE
	var has_cover := _lithology.has_permeable_cover_at(global_x, global_y)
	var mode := _recharge.mode_at(
		has_sinking_channel, has_cover, seasonality, hydrothermal_proximity, coast_distance_km
	)
	return _pattern.pattern_for(rock, mode)


## Whether there is any cave system under this tile at all -- the cheap
## question a caller usually wants before asking which kind.
func has_cave_system(
	global_x: int,
	global_y: int,
	relief: float,
	has_sinking_channel: bool,
	seasonality: float,
	hydrothermal_proximity: float,
	coast_distance_km: float
) -> bool:
	return pattern_at(
		global_x, global_y, relief, has_sinking_channel,
		seasonality, hydrothermal_proximity, coast_distance_km
	) != CavePattern.PATTERN_NONE
