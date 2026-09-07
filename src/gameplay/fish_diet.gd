extends RefCounted

## What each fish eats (see docs/concept/aquatic_foraging.md's "Revised
## (2026-09-07): real per-species diet and forage-coupled mass").
##
## Mirrors FlyerDiet's own shape exactly (see that file's own doc comment):
## the table that makes "trout eat insects, bluegill eat plants and insects"
## a STRUCTURAL fact rather than an `if species == "trout"` buried in a
## marker. FishMarker already carries a real per-instance `species` field
## (set at spawn for rendering, see ProceduralFishSprite.SPECIES_IDS) --
## this is what finally reads it for something behavioural.
##
## Pure static lookups, no instance state: asked at every forage scan.

const FOOD_VEGETATION := "vegetation"
const FOOD_INVERTEBRATES := "invertebrates"

const FOOD_TYPES := [FOOD_VEGETATION, FOOD_INVERTEBRATES]

## Real bluegill are genuine omnivorous sunfish (algae/plant matter AND
## insects/small invertebrates); koi (ornamental carp) are famously
## indiscriminate omnivores; common goldfish (same carp family as koi)
## graze algae/plant matter and also take small invertebrates. All three
## get the identical broad diet -- the real distinction in this roster is
## trout, below.
##
## Real trout are overwhelmingly insectivorous/carnivorous -- aquatic
## insect larvae (mayfly/caddisfly/midge nymphs) are the entire basis of
## fly-fishing; plant matter barely features in a real trout's diet. Gets
## the same narrow, single-food-type shape FlyerDiet already gives the
## kingfisher (FOOD_FISH only) rather than a padded-out omnivore list.
const DIET_BY_SPECIES := {
	"bluegill": [FOOD_VEGETATION, FOOD_INVERTEBRATES],
	"koi": [FOOD_VEGETATION, FOOD_INVERTEBRATES],
	"goldfish": [FOOD_VEGETATION, FOOD_INVERTEBRATES],
	"trout": [FOOD_INVERTEBRATES],
}


## Every food this species eats. An unrecognized species eats nothing
## rather than erroring -- a species missing from the table simply doesn't
## forage, the same "missing from the table simply doesn't feed" contract
## FlyerDiet.foods_for already has.
static func foods_for(species: String) -> Array:
	return DIET_BY_SPECIES.get(species, [])


static func eats(species: String, food: String) -> bool:
	return foods_for(species).has(food)
