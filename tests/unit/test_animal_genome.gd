extends GutTest

## The animal genome, in its first real shape (docs/concept/animal_genetics.md
## §1-2, docs/concept/ethogram.md §4): a plain String -> float Dictionary
## derived from an individual's own wander_seed, holding exactly the genes
## something in production reads and not one more. Today those are the
## receptor genes the ethogram expresses; the seven genes animal_genetics.md
## specifies join as their readers get built.

const AnimalGenome = preload("res://src/gameplay/animal_genome.gd")
const Ethogram = preload("res://src/gameplay/ethogram.gd")


# -- the anti-dead-weight guard animal_genetics.md specifies -----------------

func test_every_gene_has_a_named_production_reader():
	for gene in AnimalGenome.GENE_NAMES:
		assert_true(AnimalGenome.GENE_READERS.has(gene), "%s has no reader" % gene)
	for gene in AnimalGenome.GENE_READERS:
		assert_true(AnimalGenome.GENE_NAMES.has(gene), "%s is read but is not a gene" % gene)


func test_every_named_reader_module_exists():
	for gene in AnimalGenome.GENE_READERS:
		var path: String = AnimalGenome.GENE_READERS[gene]
		assert_true(ResourceLoader.exists(path), path)


## Slice 4 adds one non-receptor gene, boldness (a personality gene, not a
## receptor -- see ethogram.md §9); the receptor genes are still exactly one
## per smell channel and nothing else besides those two kinds.
func test_the_receptor_genes_and_boldness_are_the_only_genes_so_far():
	for channel in Ethogram.SMELL_CHANNELS:
		assert_true(AnimalGenome.GENE_NAMES.has(Ethogram.RECEPTOR_GENE_PREFIX + channel), channel)
	assert_true(AnimalGenome.GENE_NAMES.has(Ethogram.BOLDNESS))
	assert_eq(AnimalGenome.GENE_NAMES.size(), Ethogram.SMELL_CHANNELS.size() + 1)


# -- derivation from the seed -------------------------------------------------

func test_a_genome_is_deterministic_from_its_seed():
	assert_eq(AnimalGenome.for_seed(42), AnimalGenome.for_seed(42))
	assert_ne(AnimalGenome.for_seed(42), AnimalGenome.for_seed(43))


func test_a_genome_carries_every_gene_as_a_fraction():
	for seed_value in range(1, 200):
		var genome := AnimalGenome.for_seed(seed_value)
		for gene in AnimalGenome.GENE_NAMES:
			assert_true(genome.has(gene), gene)
			assert_true(genome[gene] >= 0.0 and genome[gene] <= 1.0, "%s = %f" % [gene, genome[gene]])


## Most individuals are close to their species: the distribution is
## bell-shaped around the template, the same shape FlyerPersonality gives
## boldness. A population of freaks would not read as a species.
func test_the_population_centres_on_the_species_template():
	var total := 0.0
	var extreme := 0
	var count := 0
	for seed_value in range(1, 400):
		var gene: float = AnimalGenome.for_seed(seed_value)["receptor_decay"]
		total += gene
		count += 1
		if gene < 0.1 or gene > 0.9:
			extreme += 1
	assert_almost_eq(total / float(count), Ethogram.NEUTRAL_RECEPTOR_GENE, 0.05)
	assert_lt(float(extreme) / float(count), 0.1, "extremes are rare")
	assert_gt(extreme, 0, "...but they exist")


## Genes vary independently: an individual with a keen nose for one molecule
## is not thereby keen on all of them.
func test_genes_vary_independently_of_one_another():
	var agree := 0
	for seed_value in range(1, 200):
		var genome := AnimalGenome.for_seed(seed_value)
		if (genome["receptor_decay"] > 0.5) == (genome["receptor_sugar"] > 0.5):
			agree += 1
	assert_gt(agree, 60)
	assert_lt(agree, 140)


## The genome expresses through the ethogram: this is the reader the guard
## above names, exercised rather than merely listed.
func test_a_seeded_genome_expresses_through_the_ethogram():
	var typical := Ethogram.express("boar")["sensitivity"]["decay"]
	var differs := 0
	for seed_value in range(1, 50):
		var expressed: float = Ethogram.express("boar", AnimalGenome.for_seed(seed_value))["sensitivity"]["decay"]
		if absf(expressed - typical) > 0.001:
			differs += 1
	assert_gt(differs, 40, "almost every individual has its own nose")


# -- slice 4: boldness, a personality gene, bell-shaped like the rest -------

## Most individuals are close to the population median, and the extremes are
## rare -- the same shape every other gene here uses (the mean of two
## independent halves), now pinned for the one gene that isn't a receptor.
func test_boldness_is_bell_shaped_around_the_neutral_gene():
	var total := 0.0
	var extreme := 0
	var count := 0
	for seed_value in range(1, 400):
		var gene: float = AnimalGenome.for_seed(seed_value)[Ethogram.BOLDNESS]
		total += gene
		count += 1
		if gene < 0.1 or gene > 0.9:
			extreme += 1
	assert_almost_eq(total / float(count), Ethogram.NEUTRAL_BOLDNESS_GENE, 0.05)
	assert_lt(float(extreme) / float(count), 0.1, "extremes are rare")
	assert_gt(extreme, 0, "...but they exist")
