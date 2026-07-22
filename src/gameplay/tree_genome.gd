extends RefCounted

## A tree's heritable traits, deterministic from a seed -- the "DNA" driving
## how it grows and reproduces (Phase 1/Flora-adjacent: individual-tree
## genetics, not just the aggregate vegetation density model). mutate()
## produces a child genome with traits nudged from the parent's rather than
## rerolled from scratch, so a spreading forest's traits drift gradually
## instead of resetting every generation.

const MIN_SPREAD_RADIUS := 2.0
const MAX_SPREAD_RADIUS := 8.0
const MIN_MATURITY_TIME := 20.0
const MAX_MATURITY_TIME := 60.0

## How far (as a fraction of each trait's own range) a mutation can nudge a
## trait from its parent's value.
const MUTATION_AMOUNT := 0.15

var seed_value: int
var fruit_yield: float  # 0..1: how often/heavily this tree fruits once mature
var species_bias: float  # 0..1: 0 = always drops nuts, 1 = always drops fruit
var spread_radius: float  # tiles a seed can land within
var maturity_time: float  # seconds until this tree can fruit/spread


func _init(a_seed_value: int) -> void:
	seed_value = a_seed_value
	fruit_yield = _trait_fraction("fruit_yield")
	species_bias = _trait_fraction("species_bias")
	spread_radius = lerpf(MIN_SPREAD_RADIUS, MAX_SPREAD_RADIUS, _trait_fraction("spread_radius"))
	maturity_time = lerpf(MIN_MATURITY_TIME, MAX_MATURITY_TIME, _trait_fraction("maturity_time"))


## A child genome whose traits are nudged from this one's by up to
## MUTATION_AMOUNT of each trait's range, clamped back into valid bounds.
func mutate(mutation_seed: int):
	var child = get_script().new(hash("%d_%d_mutate" % [seed_value, mutation_seed]))
	child.fruit_yield = _nudge(fruit_yield, 0.0, 1.0, mutation_seed, "fruit_yield")
	child.species_bias = _nudge(species_bias, 0.0, 1.0, mutation_seed, "species_bias")
	child.spread_radius = _nudge(spread_radius, MIN_SPREAD_RADIUS, MAX_SPREAD_RADIUS, mutation_seed, "spread_radius")
	child.maturity_time = _nudge(maturity_time, MIN_MATURITY_TIME, MAX_MATURITY_TIME, mutation_seed, "maturity_time")
	return child


func _nudge(value: float, min_value: float, max_value: float, mutation_seed: int, trait_name: String) -> float:
	var range_size := max_value - min_value
	var direction := (_trait_fraction("%d_%s_dir" % [mutation_seed, trait_name]) - 0.5) * 2.0  # -1..1
	return clampf(value + direction * MUTATION_AMOUNT * range_size, min_value, max_value)


## A deterministic pseudo-random fraction in [0, 1] for a named trait, derived
## from this genome's seed.
func _trait_fraction(trait_name: String) -> float:
	return float(absi(hash("%d_%s" % [seed_value, trait_name])) % 10000) / 10000.0
