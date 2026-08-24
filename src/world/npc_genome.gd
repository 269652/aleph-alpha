extends RefCounted

## An NPC's heritable trait genes (docs/concept/npc.md: "personality should
## be DNA derived" -- follow-up ask). Same "continuous 0..1 gene per trait,
## deterministic from a seed" shape as tree_genome.gd, generalized to an
## arbitrary trait-name list passed in by the caller rather than
## tree_genome's own fixed fields -- NpcIdentity hands in
## PERSONALITY_TRAITS, but nothing here is personality-specific.
##
## `traits` is a plain String -> float Dictionary specifically so it slots
## directly into the existing dna_crossover.gd utility with no adaptation --
## an NPC's genome is already shaped for the two-parent crossover a future
## child-inheritance pass (npc.md's Lifecycle section, "villagers... can
## have children with each other using the same DNA-cross... model
## players.md defines for players") would need, not a new mechanism.
##
## Before this, personality_trait was one flat categorical roll -- a single
## hash pick among 8 names, unrelated to anything else about the NPC. This
## replaces that with 8 independent continuous genes and an EXPRESSED trait
## (dominant_trait) derived from them, the same "genotype underneath, one
## visible phenotype on top" shape TreeGenome/HeroDna already use elsewhere
## in this codebase -- and, unlike the flat roll, gives other systems (e.g.
## HouseBlueprint's occupation/personality-driven choice) a continuous
## strength to read instead of just a yes/no category match.

var seed_value: int
var traits: Dictionary  # trait_name -> float in [0, 1]


func _init(a_seed_value: int, trait_names: Array) -> void:
	seed_value = a_seed_value
	traits = {}
	for trait_name in trait_names:
		traits[trait_name] = _trait_fraction(trait_name)


## The single gene that rolled highest -- the one EXPRESSED trait other
## systems can still read as a plain categorical label, same as the flat
## roll this genome replaced. Ties (vanishingly unlikely with hash-derived
## floats) resolve to whichever trait was inserted first, same as any other
## first-match scan in this codebase.
func dominant_trait() -> String:
	var best_name := ""
	var best_value := -1.0
	for trait_name in traits:
		if traits[trait_name] > best_value:
			best_value = traits[trait_name]
			best_name = trait_name
	return best_name


## A deterministic pseudo-random fraction in [0, 1] for a named trait,
## derived from this genome's seed -- mirrors TreeGenome._trait_fraction
## exactly.
func _trait_fraction(trait_name: String) -> float:
	return float(absi(hash("%d_%s" % [seed_value, trait_name])) % 10000) / 10000.0
