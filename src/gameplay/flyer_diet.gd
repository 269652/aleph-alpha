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

const FOOD_TYPES := [FOOD_WORMS, FOOD_SEEDS, FOOD_FRUIT, FOOD_FISH, FOOD_NECTAR]

## Foods a flyer has to LAND to eat -- the ones that put it through the
## descend/sit/peck/resume cycle (see GroundForageBehavior). Fish is not one
## of them (a kingfisher dives, see PiscivoreBirdBehavior), and neither is
## nectar (a pollinator settles on the bloom itself, see PollinatorForaging).
## Fruit IS one -- fallen fruit sits on the ground exactly like a worm does
## (see docs/concept/ecosystem_dynamics.md's frugivory section).
const GROUND_FOODS := [FOOD_WORMS, FOOD_SEEDS, FOOD_FRUIT]

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


const DIET_BY_SPECIES := {
	"robin": [FOOD_WORMS, FOOD_FRUIT],
	"sparrow": [FOOD_SEEDS, FOOD_FRUIT],
	"kingfisher": [FOOD_FISH],
	"monarch": [FOOD_NECTAR],
	"swallowtail": [FOOD_NECTAR],
	"blue_morpho": [FOOD_NECTAR],
	"bee": [FOOD_NECTAR],
}


## Every food this species eats. An unrecognized species eats nothing rather
## than erroring -- a species missing from the table simply doesn't feed,
## which test_every_spawnable_flyer_has_a_diet catches at the roster level.
static func foods_for(species: String) -> Array:
	return DIET_BY_SPECIES.get(species, [])


static func eats(species: String, food: String) -> bool:
	return foods_for(species).has(food)


## Whether this species feeds on things lying on the ground, and so needs to
## descend, sit down, and peck rather than eating on the wing.
static func forages_on_the_ground(species: String) -> bool:
	for food in foods_for(species):
		if GROUND_FOODS.has(food):
			return true
	return false
