extends RefCounted

## Crop DNA/phenotype system (docs/concept/farming.md's "selective breeding /
## cross-pollination" + "rare crop strain collecting hook"). Builds on
## FarmPlot's seed_value-driven crop pattern without modifying it: two parent
## seed_values combine into a new child seed_value, and child_roll is what
## lets the same parent pair yield varied offspring across repeated attempts.


## Deterministically combines both parents' seed_values with child_roll into
## a new child seed_value. Folding all three inputs into one hash key (rather
## than hashing each separately and mixing) keeps this a single application
## of the project's hash-fraction pattern.
func cross_pollinate(parent_a_seed: int, parent_b_seed: int, child_roll: int) -> int:
	var key := "%d_%d_%d_cross_pollinate" % [parent_a_seed, parent_b_seed, child_roll]
	return absi(hash(key))


## Deterministic 0..1 "how good this plant's traits are" score for a given
## seed_value -- the hook rare-strain collecting reads from.
func trait_rarity_score(seed_value: int) -> float:
	return float(absi(hash("%d_trait_rarity" % seed_value)) % 10000) / 10000.0


## True when a strain's traits meet or exceed rarity_threshold.
func is_rare_strain(seed_value: int, rarity_threshold: float) -> bool:
	return trait_rarity_score(seed_value) >= rarity_threshold
