extends RefCounted

## Combines two parents' trait Dictionaries (String trait_name -> float) into
## a child's, deterministic from a seed -- the two-parent counterpart to
## tree_genome.gd's single-parent mutate(). Each shared trait independently
## coin-flips which parent it leans toward (not a blanket average, so a
## child can favor A on one trait and B on another -- real genetic variety),
## then gets a small mutation nudge so it never lands exactly on a parent's
## value. A trait present in only one parent has no counterpart to cross
## against, so it is dropped rather than passed through unchanged.

## How far a mutation can nudge the child's inherited value, as a fraction
## of the spread between the two parents' values for that trait.
const MUTATION_AMOUNT := 0.15

## Fallback absolute nudge range used when both parents share the exact same
## value for a trait (spread would otherwise be zero, leaving nothing to
## nudge by).
const MUTATION_FLOOR := 0.01


func crossover(parent_a_traits: Dictionary, parent_b_traits: Dictionary, child_seed: int) -> Dictionary:
	var child: Dictionary = {}
	for trait_name in parent_a_traits.keys():
		if not parent_b_traits.has(trait_name):
			continue
		var value_a: float = parent_a_traits[trait_name]
		var value_b: float = parent_b_traits[trait_name]
		var inherits_from_a := _trait_fraction(child_seed, trait_name, "inherit") < 0.5
		var inherited_value: float = value_a if inherits_from_a else value_b
		child[trait_name] = _nudge(inherited_value, value_a, value_b, child_seed, trait_name)
	return child


func _nudge(value: float, value_a: float, value_b: float, child_seed: int, trait_name: String) -> float:
	var spread := absf(value_a - value_b)
	if spread == 0.0:
		spread = MUTATION_FLOOR
	var direction := (_trait_fraction(child_seed, trait_name, "mutate") - 0.5) * 2.0  # -1..1
	return value + direction * MUTATION_AMOUNT * spread


## A deterministic pseudo-random fraction in [0, 1] for a named trait, derived
## from the child seed.
func _trait_fraction(child_seed: int, trait_name: String, salt: String) -> float:
	return float(absi(hash("%d_%s_%s" % [child_seed, trait_name, salt])) % 10000) / 10000.0
