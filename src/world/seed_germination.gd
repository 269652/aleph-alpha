extends RefCounted

## What it takes for a seed lying on the ground to become a sapling (see
## docs/concept/seed_dispersal.md).
##
## Pure and engine-free: this answers whether a seed CAN root here, how likely
## it is to, and whether the ground is wet enough to start. Turning it into a
## plant is the caller's job.

const TreeRooting = preload("res://src/world/tree_rooting.gd")

## How likely a seed is to take on ground that is entirely bare, and on ground
## that is entirely thick turf.
##
## Bare earth being the far better seedbed is true, and is the reason
## disturbance drives succession in the first place: a seed that lands in thick
## grass mostly fails and the same seed on scraped ground mostly takes. It is
## also what makes clearing a patch the way a player deliberately starts a
## wood, and it makes the trampled dirt of a path (see PathScarring, which
## already renders worn tiles as earth) a nursery rather than merely a scar.
##
## Grass is a perfectly good seedbed too -- both its shades; the light and dark
## speckle is one tile, not two kinds of ground. Bare earth is BETTER, not
## uniquely possible: seed takes in a meadow all the time, which is how meadows
## exist. An earlier pass had turf at 0.08, which made grass a near-failure and
## would have meant nothing ever seeded except on a path.
##
## What is NOT a seedbed is ground with no soil in it at all -- water, bare
## rock, sand, anything above the tree line -- and that is a separate question,
## answered by can_germinate rather than by a low chance here.
const BARE_EARTH_CHANCE := 0.8
const THICK_TURF_CHANCE := 0.5

## How wet the ground must be before a seed starts rooting.
##
## Rain is the trigger, which is what makes it a thing the player waits for
## rather than a weather texture. Sits at the moisture rain itself delivers
## (see WeatherModel.soil_moisture), so "it rained" and "seeds are rooting"
## are the same event rather than two thresholds that can drift apart.
const ROOTING_MOISTURE := 0.85


## Whether this ground could take a seed at all.
##
## Delegates the biome question to TreeRooting, which is the one answer to
## "can something grow here" -- water, bare rock, sand and everything above the
## tree line are not seedbeds however bare they are.
static func can_germinate(biome_name: String, _bare_earth: float) -> bool:
	return TreeRooting.can_root_in(biome_name)


## How likely a seed on this ground is to take, 0 to 1.
##
## `bare_earth` is how exposed the soil is: 0 is thick turf, 1 is scraped
## ground.
static func germination_chance(biome_name: String, bare_earth: float) -> float:
	if not can_germinate(biome_name, bare_earth):
		return 0.0
	return lerpf(THICK_TURF_CHANCE, BARE_EARTH_CHANCE, clampf(bare_earth, 0.0, 1.0))


## Whether the ground is wet enough for a seed to start rooting.
static func is_rooting_weather(soil_moisture: float) -> bool:
	return soil_moisture >= ROOTING_MOISTURE


## Whether this is still a seed, and therefore still food.
##
## Once it has rooted it is not a seed any more, so a bird that would have
## eaten it leaves the seedling alone.
static func is_edible_seed(has_rooted: bool) -> bool:
	return not has_rooted
