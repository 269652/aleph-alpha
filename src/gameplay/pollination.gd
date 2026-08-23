extends RefCounted

## Pollen moving from one plant to another, and seed only being set when it
## arrives (see docs/concept/flora.md).
##
## A plant that sets seed on its own is not being pollinated -- it is just
## reproducing, with the pollinator as decoration. Requiring pollen makes the
## bees load-bearing: no bees, no seed, and a meadow that loses its pollinators
## stops renewing itself.
##
## Pure and engine-free: this says who gives pollen, who can receive it, and
## what a carrier is holding after a visit. Remembering what any particular bee
## carries is the caller's job, exactly as PollinatorForaging leaves visit
## memory to the flyer.

const PixelNoise = preload("res://src/rendering/pixel_noise.gd")

const MALE := "male"
const FEMALE := "female"


## Which sex this plant is, from its own seed -- fixed for its life, like its
## colour and its size.
##
## Dioecious: separate male and female plants, which is the arrangement that
## makes a POLLINATOR necessary rather than optional. A perfect flower that can
## pollinate itself needs nobody to visit it.
static func sex_of(seed_value: int) -> String:
	return MALE if PixelNoise.range_index(seed_value, 89, 0, 2) == 0 else FEMALE


## Whether a flower of this sex has pollen to give.
static func gives_pollen(sex: String) -> bool:
	return sex == MALE


## Whether a flower of this sex could set seed at all, given the right pollen.
static func can_set_seed(sex: String, _species: String) -> bool:
	return sex == FEMALE


## Whether pollen of one species does anything for a flower of another.
##
## Species-specific, which is what stops a meadow of mixed flowers
## cross-breeding into one.
static func pollinates(carried_species: String, flower_species: String) -> bool:
	return carried_species != "" and carried_species == flower_species


## What a pollinator is carrying after visiting this flower.
##
## A male flower loads it; a female one leaves it alone, so a single load can
## fertilise more than one plant -- which is why one bee is worth anything at
## all. A later male replaces it: a carrier holds what it touched last.
static func pollen_after_visit(carried: String, species: String, sex: String) -> String:
	return species if gives_pollen(sex) else carried


## Whether this visit actually sets seed: matching pollen, arriving at a flower
## that can receive it.
static func sets_seed(carried: String, species: String, sex: String) -> bool:
	return can_set_seed(sex, species) and pollinates(carried, species)
