extends RefCounted

## What each ambient flyer eats (see docs/concept/soil_fauna.md's "Bird diet,
## as a first-class concept").
##
## This is the table that makes "robins eat worms, sparrows eat seeds" a
## STRUCTURAL fact rather than an `if species == "robin"` buried in a marker.
## A species with FOOD_WORMS in its diet is handed a worm world and a
## ground-forage brain when it spawns (see AmbientFlyerRenderer._build_marker);
## a species without one is not, and therefore cannot hunt worms however the
## shared marker code changes later.
##
## Deliberately NOT CreatureInfo.DIET_BY_SPECIES, which is display-only HUD
## flavour text ("Grazer", "Hunter") that nothing behavioural reads. This one
## is behavioural.
##
## Food types are plain strings so the follow-on work slots in without a
## redesign: FOOD_SEEDS already sits on the sparrow waiting for a seed sim
## (same patch-sim contract, same ground-forage state machine, a
## seeds_near/take_seed_at pair on the chunk manager), and FOOD_FRUIT is here
## for when fruit trees can be foraged -- at which point a robin gains it as a
## second diet entry and nothing else has to move.
##
## Pure static lookups, no instance state: this is asked at spawn time and on
## every forage sniff.

const FOOD_WORMS := "worms"
const FOOD_SEEDS := "seeds"
const FOOD_FRUIT := "fruit"
const FOOD_FISH := "fish"
const FOOD_NECTAR := "nectar"
const FOOD_CATERPILLARS := "caterpillars"
const FOOD_ANTS := "ants"

const FOOD_TYPES := [
	FOOD_WORMS, FOOD_SEEDS, FOOD_FRUIT, FOOD_FISH, FOOD_NECTAR, FOOD_CATERPILLARS, FOOD_ANTS,
]

## Foods a flyer has to LAND to eat -- the ones that put it through the
## descend/sit/peck/resume cycle (see GroundForageBehavior). Fish is not one
## of them (a kingfisher dives, see PiscivoreBirdBehavior), and neither is
## nectar (a pollinator settles on the bloom itself, see PollinatorForaging).
## Fruit IS one -- fallen fruit sits on the ground exactly like a worm does
## (see docs/concept/ecosystem_dynamics.md's frugivory section). So is a
## ground-based caterpillar (see FOOD_CATERPILLARS's own doc comment) --
## the same descend-and-peck a robin already does for a worm. So is a live
## ant (see FOOD_ANTS's own doc comment) -- the identical cycle again, just
## against EarthChunkManager.ants_near/take_ant_near instead.
const GROUND_FOODS := [FOOD_WORMS, FOOD_SEEDS, FOOD_FRUIT, FOOD_CATERPILLARS, FOOD_ANTS]

## Real robins are insectivores that hunt worms by sight from the ground, AND
## genuine omnivores that switch onto soft fruit/berries once it's available
## (especially outside the breeding season) -- the second diet entry this
## file's own doc comment already flagged as the natural next step once fruit
## trees could be foraged (see docs/concept/flora.md#bird-endozoochory).
## Real sparrows are granivores working seed heads and bare soil. All three
## are ground feeders, which is why they share one behaviour and differ only
## in what they are looking for.
## WHICH tree fruit a fruit-eater will actually take. FOOD_FRUIT alone is too
## coarse now that three named species drop very different things: a robin
## takes the soft fruit and the nuts alike, while a sparrow's bill is built
## for hard seed and nuts, not for soft cherries. A species listed under
## FOOD_FRUIT with no entry here eats any fruit.
const FRUIT_SPECIES_BY_FLYER := {
	"robin": ["cherry", "walnut", "apple"],
	"sparrow": ["walnut"],
	# Real blackbirds take soft fruit just like a robin does (both real
	# thrushes -- see docs/concept/seasonal_behavior.md, "Blackbird: new
	# species, real population, real diet shift").
	"blackbird": ["cherry", "walnut", "apple"],
}


## Whether `species` will take this particular tree fruit. Keeps the
## coarse-grained diet check (eats) as the gate for "does it forage fruit at
## all", and narrows only WHICH fruit once it is looking.
static func eats_fruit_species(species: String, fruit_species: String) -> bool:
	if not eats(species, FOOD_FRUIT):
		return false
	if not FRUIT_SPECIES_BY_FLYER.has(species):
		return true
	return FRUIT_SPECIES_BY_FLYER[species].has(fruit_species)


## Real robins are famous caterpillar-hunters -- caterpillars are what a
## robin feeds its own chicks more than almost anything else, right
## alongside worms (see docs/concept/soil_fauna.md's own bird-diet
## follow-up: "some birds eat caterpillars too"). Originally robin-only; a
## sparrow's granivore bill and a kingfisher's fish-only diet are both a
## poor real-world fit for it, so it stayed narrow rather than spreading
## across every songbird just because the mechanism existed -- but later
## widened to blackbird too (see docs/concept/seasonal_behavior.md,
## "Blackbird: new species, real population, real diet shift"): a second
## real thrush with the identical genuine specialism, not spreading it
## further "just because". Ground-based
## caterpillars only (see EarthChunkManager.caterpillars_near) -- a
## caterpillar up a tree, mid-climb, is a real gap this pass names rather
## than silently drops: gleaning prey off foliage is a genuinely different
## targeting problem from a ground-forage descend-and-peck, and is not
## solved here.
##
## Reported live: "birds should forage live ants" (see docs/concept/
## soil_fauna.md's own "Ants are not bird prey" scope cut, now closed).
## UNLIKE caterpillars above, this is deliberately given to BOTH ground-
## foraging songbirds, not robin-only: real American robins are
## documented generalist ground insectivores that do take ants among
## their varied invertebrate diet (the same "worms, caterpillars, and
## more" pattern this file already gives them), but real house sparrows --
## despite being primarily granivorous -- are ALSO well-documented
## opportunistic ant-eaters, arguably proportionally more so than robins,
## precisely because a ground-foraging, short-grass/bare-soil bird
## routinely crosses ant trails and mounds while working seed heads,
## rather than visually hunting a specific, larger prey item the way a
## robin's own worm/caterpillar hunting already does. Ants target
## EarthChunkManager.ants_near/take_ant_near -- a live forager, never a
## settled corpse (see AntForagerMarker.is_corpse) -- a bird's meal is an
## entirely different event from being crushed underfoot or foraged home
## by another ant, and never plays that death animation.
const DIET_BY_SPECIES := {
	"robin": [FOOD_WORMS, FOOD_FRUIT, FOOD_CATERPILLARS, FOOD_ANTS],
	"sparrow": [FOOD_SEEDS, FOOD_FRUIT, FOOD_ANTS],
	# Real Eurasian blackbirds (Turdus merula) are genuine omnivorous
	# thrushes with essentially the same real broad diet as robin (see
	# docs/concept/seasonal_behavior.md's "Blackbird: new species, real
	# population, real diet shift") -- worms/caterpillars/ants/fruit
	# year-round, but see eats_now() below for the real winter shift
	# toward fruit that robin/sparrow deliberately do NOT get in this pass.
	"blackbird": [FOOD_WORMS, FOOD_FRUIT, FOOD_CATERPILLARS, FOOD_ANTS],
	"kingfisher": [FOOD_FISH],
	"monarch": [FOOD_NECTAR],
	"swallowtail": [FOOD_NECTAR],
	"blue_morpho": [FOOD_NECTAR],
	# "bee" deliberately retired from this table (see docs/concept/
	# bees.md's own "Foraging" section, AmbientFlyerRenderer's own
	# retirement) -- a real BeeForagerMarker/WildBeePatch forager now
	# owns every visible bee, tied to a real hive/nest economy, rather
	# than a decorative flyer with no hive, no population, and nothing
	# behind it but wander+nectar-sip.
}


## Every food this species eats. An unrecognized species eats nothing rather
## than erroring -- a species missing from the table simply doesn't feed,
## which test_every_spawnable_flyer_has_a_diet catches at the roster level.
static func foods_for(species: String) -> Array:
	return DIET_BY_SPECIES.get(species, [])


static func eats(species: String, food: String) -> bool:
	return foods_for(species).has(food)


## Species whose diet genuinely shifts by season -- real blackbirds are
## year-round residents that lean on insects/worms in the warmer months and
## shift toward fruit once insects thin out in winter (see docs/concept/
## seasonal_behavior.md, "Blackbird: new species, real population, real
## diet shift"). Robin/sparrow deliberately keep their existing flat diet
## weighting -- retrofitting the same shift onto them is a named, separate
## follow-up, not done here.
const WINTER_EXCLUDED_FOODS_BY_SPECIES := {
	"blackbird": [FOOD_WORMS, FOOD_CATERPILLARS, FOOD_ANTS],
}


## Whether `species` pursues `food` RIGHT NOW, given the real current
## season -- eats() unless this exact species+food pair is one this species
## seasonally stops pursuing in winter (see WINTER_EXCLUDED_FOODS_BY_
## SPECIES). Every species not in that table, and every season but winter,
## behaves exactly as eats() already did -- the same "safe default
## preserves old behavior" convention this session's other seasonal-
## behavior phases already established.
static func eats_now(species: String, food: String, season: String) -> bool:
	if not eats(species, food):
		return false
	if season == "winter":
		return not WINTER_EXCLUDED_FOODS_BY_SPECIES.get(species, []).has(food)
	return true


## Whether this species feeds on things lying on the ground, and so needs to
## descend, sit down, and peck rather than eating on the wing.
static func forages_on_the_ground(species: String) -> bool:
	for food in foods_for(species):
		if GROUND_FOODS.has(food):
			return true
	return false
