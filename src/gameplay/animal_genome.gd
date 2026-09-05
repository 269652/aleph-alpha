extends RefCounted

## The animal genome (docs/concept/animal_genetics.md §1-2; docs/concept/
## ethogram.md §4): a plain `String -> float` Dictionary with values in
## [0, 1], because that is exactly the shape DnaCrossover.crossover consumes
## and NpcGenome/FlyerPersonality already produce. No container class for
## the genes themselves; this is a namespace of static funcs over that
## Dictionary, in the style of AnimalReproduction and LifeCycle.
##
## Which genes exist is governed by animal_genetics.md's anti-dead-weight
## rule -- "as many as have readers, and not one more" -- enforced
## structurally by GENE_READERS and the two tests that check it. Today the
## only production reader is the ethogram, so the only genes are the receptor
## genes it expresses: one per smell channel, 0.5 being the species template
## (Ethogram.NEUTRAL_RECEPTOR_GENE), 0 a specific anosmia, 1 a receptor at
## twice the species' sensitivity. The seven genes animal_genetics.md
## specifies (strength, agility, coat_vibrancy, size, fertility, hardiness,
## docility) join this list as their readers get built, not before.
##
## for_seed() is how every wild land mammal gets its genome today: derived
## from its own wander_seed, which the world already persists, so an
## individual's nose survives a chunk unload and reload without a byte of
## new save state. Two-parent inheritance (animal_genetics.md §3,
## `from_parents`) is that doc's own slice -- births still spawn a fresh
## individual (World._step_reproduction), which is honestly ⬜ there.

const Ethogram = preload("res://src/gameplay/ethogram.gd")

const ETHOGRAM_PATH := "res://src/gameplay/ethogram.gd"

## Ordered, because animal_genetics.md's V2 save record writes the floats
## positionally. One receptor gene per smell channel, in channel order.
const GENE_NAMES: Array[String] = [
	"receptor_sugar", "receptor_decay", "receptor_green", "receptor_musk", "receptor_smoke",
]

## Each gene's production reader, by res:// path -- the registry
## test_every_gene_has_a_named_production_reader and
## test_every_named_reader_module_exists keep honest.
const GENE_READERS := {
	"receptor_sugar": ETHOGRAM_PATH,
	"receptor_decay": ETHOGRAM_PATH,
	"receptor_green": ETHOGRAM_PATH,
	"receptor_musk": ETHOGRAM_PATH,
	"receptor_smoke": ETHOGRAM_PATH,
}

## A gene is the mean of this many independent hash-derived fractions, which
## makes the population bell-shaped around 0.5 rather than flat: most
## individuals are close to their species, and a freak nose is rare. The
## same shape, for the same reason, as FlyerPersonality.BELL_HALVES.
const BELL_HALVES := 2


## The genome an individual is born with when it had no parents: every wild
## animal a chunk seeds. Deterministic from `seed_value` (the marker's own
## wander_seed).
static func for_seed(seed_value: int) -> Dictionary:
	var genome := {}
	for gene in GENE_NAMES:
		genome[gene] = _bell(seed_value, gene)
	return genome


static func _bell(seed_value: int, gene: String) -> float:
	var total := 0.0
	for half in BELL_HALVES:
		total += _unit(seed_value, gene, half)
	return total / float(BELL_HALVES)


## A deterministic fraction in [0, 1), the same hash-derived shape the rest of
## the world uses for per-individual variation rather than RNG state.
static func _unit(seed_value: int, gene: String, index: int) -> float:
	var salted := "%d_%s_%d_animal_genome" % [seed_value, gene, index]
	return float(absi(hash(salted)) % 10000) / 10000.0
