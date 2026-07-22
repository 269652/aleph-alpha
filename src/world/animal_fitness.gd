extends RefCounted

## Deterministic DNA-driven traits and mate-selection scoring for animal
## individuals (Evolution's "Genetic Phenotype Generation" /
## "Mate-Attractiveness Scoring" / "DNA-Driven Fitness Attributes"). Traits
## are derived from a seed with the same hash-fraction pattern as
## tree_genome.gd's _trait_fraction, so a given individual's phenotype is
## reproducible from its seed alone rather than stored separately.

## Weights fitness_score assigns to each trait; must sum to 1.0 so the score
## stays a weighted average in the traits' own [0,1] range.
const STRENGTH_WEIGHT := 0.4
const AGILITY_WEIGHT := 0.35
const COAT_VIBRANCY_WEIGHT := 0.25


## A deterministic phenotype for seed_value: strength (raw physical power),
## agility (speed/evasion), and coat_vibrancy (visual distinctiveness driving
## the "rare-colored individual" mate/player appeal) -- each a fraction in
## [0,1].
func phenotype_for(seed_value: int) -> Dictionary:
	return {
		"strength": _trait_fraction(seed_value, "strength"),
		"agility": _trait_fraction(seed_value, "agility"),
		"coat_vibrancy": _trait_fraction(seed_value, "coat_vibrancy"),
	}


## Combines a phenotype's traits into one fitness value. A weighted average
## (weights sum to 1.0) keeps the score in [0,1] and guarantees every trait
## visibly moves it.
func fitness_score(phenotype: Dictionary) -> float:
	return (
		phenotype["strength"] * STRENGTH_WEIGHT
		+ phenotype["agility"] * AGILITY_WEIGHT
		+ phenotype["coat_vibrancy"] * COAT_VIBRANCY_WEIGHT
	)


## 0..1 mate compatibility between two individuals: half rewards both being
## generally fit (a strong, agile, vibrant pairing), half rewards similarity
## across their individual traits (birds-of-a-feather compatibility). Both
## halves are order-independent, so the result is symmetric by construction.
func mate_attractiveness(a_phenotype: Dictionary, b_phenotype: Dictionary) -> float:
	var combined_fitness := (fitness_score(a_phenotype) + fitness_score(b_phenotype)) / 2.0
	var similarity := 1.0 - _average_trait_difference(a_phenotype, b_phenotype)
	return combined_fitness * 0.6 + similarity * 0.4


func _average_trait_difference(a_phenotype: Dictionary, b_phenotype: Dictionary) -> float:
	var trait_keys := ["strength", "agility", "coat_vibrancy"]
	var total_difference := 0.0
	for trait_key in trait_keys:
		total_difference += absf(a_phenotype[trait_key] - b_phenotype[trait_key])
	return total_difference / trait_keys.size()


func _trait_fraction(seed_value: int, trait_name: String) -> float:
	return float(absi(hash("%d_%s" % [seed_value, trait_name])) % 10000) / 10000.0
