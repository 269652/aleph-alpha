extends GutTest

## NpcGenome (docs/concept/npc.md: "personality should be DNA derived" --
## follow-up ask, same "continuous 0..1 gene per trait, seeded" shape as
## tree_genome.gd, generalized to an arbitrary trait-name list rather than
## tree_genome's own fixed fields). traits is a String -> float Dictionary
## specifically so it slots directly into the existing dna_crossover.gd
## utility unchanged -- NPC child inheritance (npc.md's Lifecycle section)
## is a natural follow-up once villagers can have children at all.

const NpcGenome = preload("res://src/world/npc_genome.gd")

const _TRAIT_NAMES := ["friendly", "gruff", "curious", "stoic", "greedy", "kind", "cautious", "bold"]


func test_same_seed_produces_the_same_genome():
	var a := NpcGenome.new(42, _TRAIT_NAMES)
	var b := NpcGenome.new(42, _TRAIT_NAMES)
	assert_eq(a.traits, b.traits)


func test_every_requested_trait_gets_a_gene():
	var genome := NpcGenome.new(1, _TRAIT_NAMES)
	for trait_name in _TRAIT_NAMES:
		assert_true(genome.traits.has(trait_name), trait_name)


func test_every_gene_is_a_fraction_between_zero_and_one():
	for seed_value in range(20):
		var genome := NpcGenome.new(seed_value, _TRAIT_NAMES)
		for trait_name in _TRAIT_NAMES:
			assert_between(genome.traits[trait_name], 0.0, 1.0, trait_name)


func test_different_traits_get_different_genes_not_one_shared_roll():
	var genome := NpcGenome.new(5, _TRAIT_NAMES)
	var seen := {}
	for trait_name in _TRAIT_NAMES:
		seen[genome.traits[trait_name]] = true
	assert_gt(seen.size(), 1, "every trait rolling the exact same value means the genes aren't independent")


func test_dominant_trait_is_always_a_requested_trait_name():
	for seed_value in range(40):
		var genome := NpcGenome.new(seed_value, _TRAIT_NAMES)
		assert_true(_TRAIT_NAMES.has(genome.dominant_trait()))


func test_dominant_trait_is_the_gene_that_actually_rolled_highest():
	for seed_value in [3, 17, 29]:
		var genome := NpcGenome.new(seed_value, _TRAIT_NAMES)
		var expected_best := ""
		var best_value := -1.0
		for trait_name in _TRAIT_NAMES:
			if genome.traits[trait_name] > best_value:
				best_value = genome.traits[trait_name]
				expected_best = trait_name
		assert_eq(genome.dominant_trait(), expected_best)


## Every trait should be able to WIN (be the dominant one) across enough
## samples -- otherwise the "pick" logic silently favors a subset, the same
## coverage guarantee NpcIdentity already pins for occupation.
func test_every_trait_can_be_dominant_across_enough_samples():
	var seen := {}
	for seed_value in range(400):
		seen[NpcGenome.new(seed_value, _TRAIT_NAMES).dominant_trait()] = true
	for trait_name in _TRAIT_NAMES:
		assert_true(seen.has(trait_name), "trait never won dominance: %s" % trait_name)


## The whole point: a genome's traits Dictionary must be directly usable by
## the existing DnaCrossover utility without any adaptation -- this is what
## makes NPC child inheritance (npc.md's Lifecycle section) a natural
## follow-up rather than a new crossover mechanism.
func test_traits_are_directly_usable_by_the_existing_dna_crossover_utility():
	const DnaCrossover = preload("res://src/gameplay/dna_crossover.gd")
	var parent_a := NpcGenome.new(1, _TRAIT_NAMES)
	var parent_b := NpcGenome.new(2, _TRAIT_NAMES)
	var child_traits := DnaCrossover.new().crossover(parent_a.traits, parent_b.traits, 3)
	for trait_name in _TRAIT_NAMES:
		assert_true(child_traits.has(trait_name), trait_name)
