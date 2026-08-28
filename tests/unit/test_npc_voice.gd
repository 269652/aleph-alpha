extends GutTest

## NpcVoice (docs/concept/dialogue.md's pipeline, second stage): the 8-entry
## continuous NpcGenome is already generated for every villager, and today
## only its ARGMAX is read (NpcIdentity.personality_trait). This module
## spends the discarded continuous signal on five voice axes and a banded
## voice_key the renderer indexes its phrasing pools by.
##
## Ordering (a kind-maxed genome out-warms a gruff-maxed one) is what this
## file pins. It is deliberately NOT the pin for WHERE the band edges sit --
## see test_npc_voice_band_distribution.gd, which measures those against the
## real generator, because with 8 uniform genes any eyeballed cut lands
## nearly everyone in one band.

const NpcVoice = preload("res://src/dialogue/npc_voice.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")
const NpcGenome = preload("res://src/world/npc_genome.gd")


## A full 8-gene genome at the neutral midpoint, with named genes pushed to
## an extreme -- the shape NpcGenome produces, so nothing here tests against
## a partial Dictionary the real game would never hand over.
func _genome(overrides: Dictionary) -> Dictionary:
	var traits := {}
	for gene in NpcIdentity.PERSONALITY_TRAITS:
		traits[gene] = 0.5
	for gene in overrides:
		traits[gene] = overrides[gene]
	return traits


func _maxed(genes: Array) -> Dictionary:
	var overrides := {}
	for gene in genes:
		overrides[gene] = 1.0
	return _genome(overrides)


func test_axes_are_the_five_the_spec_names():
	var expected: Array[String] = ["warmth", "bluntness", "verbosity", "hedging", "self_interest"]
	assert_eq(NpcVoice.AXES, expected)


func test_axes_for_produces_a_value_for_every_axis():
	var axes := NpcVoice.axes_for(_genome({}))
	assert_eq(axes.size(), NpcVoice.AXES.size())
	for axis_name in NpcVoice.AXES:
		assert_true(axes.has(axis_name), axis_name)


## The whole reason this module exists: every one of the 8 genes must move
## at least one axis, or that gene's continuous signal is still discarded --
## exactly the waste NpcVoice was written to stop.
func test_every_personality_gene_moves_at_least_one_axis():
	for gene in NpcIdentity.PERSONALITY_TRAITS:
		var used := false
		for axis_name in NpcVoice.AXES:
			if NpcVoice.genes_of(axis_name).has(gene):
				used = true
		assert_true(used, "gene never read by any axis: %s" % gene)


func test_axis_values_stay_within_zero_and_one_for_real_genomes():
	for seed_value in range(200):
		var axes := NpcVoice.axes_for(NpcGenome.new(seed_value, NpcIdentity.PERSONALITY_TRAITS).traits)
		for axis_name in NpcVoice.AXES:
			assert_between(float(axes[axis_name]), 0.0, 1.0, axis_name)


## A genome with no genes at all reads as exactly neutral rather than as the
## floor -- a missing gene means "no signal", not "the lowest possible".
func test_an_empty_genome_reads_as_neutral_on_every_axis():
	var axes := NpcVoice.axes_for({})
	for axis_name in NpcVoice.AXES:
		assert_almost_eq(float(axes[axis_name]), 0.5, 0.0001, axis_name)


func test_a_kind_genome_out_warms_a_gruff_one():
	var kind := NpcVoice.axes_for(_maxed(["kind", "friendly"]))
	var gruff := NpcVoice.axes_for(_maxed(["gruff", "greedy"]))
	assert_gt(float(kind["warmth"]), float(gruff["warmth"]))


func test_a_gruff_bold_genome_is_blunter_than_a_cautious_friendly_one():
	var blunt := NpcVoice.axes_for(_maxed(["gruff", "bold"]))
	var soft := NpcVoice.axes_for(_maxed(["cautious", "friendly"]))
	assert_gt(float(blunt["bluntness"]), float(soft["bluntness"]))


func test_a_curious_friendly_genome_is_more_verbose_than_a_stoic_gruff_one():
	var talker := NpcVoice.axes_for(_maxed(["curious", "friendly"]))
	var quiet := NpcVoice.axes_for(_maxed(["stoic", "gruff"]))
	assert_gt(float(talker["verbosity"]), float(quiet["verbosity"]))


func test_a_cautious_stoic_genome_hedges_more_than_a_bold_gruff_one():
	var hedger := NpcVoice.axes_for(_maxed(["cautious", "stoic"]))
	var flat := NpcVoice.axes_for(_maxed(["bold", "gruff"]))
	assert_gt(float(hedger["hedging"]), float(flat["hedging"]))


func test_a_greedy_bold_genome_is_more_self_interested_than_a_kind_friendly_one():
	var grasping := NpcVoice.axes_for(_maxed(["greedy", "bold"]))
	var giving := NpcVoice.axes_for(_maxed(["kind", "friendly"]))
	assert_gt(float(grasping["self_interest"]), float(giving["self_interest"]))


func test_band_of_splits_at_the_pinned_edges():
	for axis_name in NpcVoice.AXES:
		var edges: Dictionary = NpcVoice.BAND_EDGES[axis_name]
		var low: float = edges["low"]
		var high: float = edges["high"]
		assert_eq(NpcVoice.band_of(axis_name, low - 0.01), "low", axis_name)
		assert_eq(NpcVoice.band_of(axis_name, (low + high) * 0.5), "mid", axis_name)
		assert_eq(NpcVoice.band_of(axis_name, high + 0.01), "high", axis_name)


func test_band_of_never_returns_anything_outside_the_three_bands():
	for axis_name in NpcVoice.AXES:
		for step in 21:
			var band := NpcVoice.band_of(axis_name, float(step) / 20.0)
			assert_true(NpcVoice.BANDS.has(band), "%s -> %s" % [axis_name, band])


func test_band_edges_are_ordered_and_inside_the_axis_range():
	for axis_name in NpcVoice.AXES:
		var edges: Dictionary = NpcVoice.BAND_EDGES[axis_name]
		assert_lt(float(edges["low"]), float(edges["high"]), axis_name)
		assert_between(float(edges["low"]), 0.0, 1.0, axis_name)
		assert_between(float(edges["high"]), 0.0, 1.0, axis_name)


func test_voice_keys_are_every_axis_crossed_with_every_band():
	var keys := NpcVoice.voice_keys()
	assert_eq(keys.size(), NpcVoice.AXES.size() * NpcVoice.BANDS.size())
	for axis_name in NpcVoice.AXES:
		for band in NpcVoice.BANDS:
			assert_true(keys.has("%s_%s" % [axis_name, band]), "%s_%s" % [axis_name, band])


## The renderer indexes pools by this string, so its shape is a contract:
## "<axis>_<band>", band last. self_interest carries its own underscore, so
## parse_key must split on the LAST one, never the first.
func test_parse_key_round_trips_even_for_the_underscored_axis():
	for key in NpcVoice.voice_keys():
		var parsed := NpcVoice.parse_key(key)
		assert_true(NpcVoice.AXES.has(parsed["axis"]), key)
		assert_true(NpcVoice.BANDS.has(parsed["band"]), key)
		assert_eq(NpcVoice.key_for(parsed["axis"], parsed["band"]), key)
	assert_eq(NpcVoice.parse_key("self_interest_high")["axis"], "self_interest")
	assert_eq(NpcVoice.parse_key("self_interest_high")["band"], "high")


func test_register_for_carries_axes_bands_and_a_key_per_axis():
	var register := NpcVoice.register_for(_maxed(["gruff", "bold"]))
	assert_eq(register["axes"].size(), NpcVoice.AXES.size())
	assert_eq(register["bands"].size(), NpcVoice.AXES.size())
	assert_eq(register["band_keys"].size(), NpcVoice.AXES.size())
	for axis_name in NpcVoice.AXES:
		assert_eq(
			register["bands"][axis_name],
			NpcVoice.band_of(axis_name, float(register["axes"][axis_name])),
			axis_name
		)
	assert_true(NpcVoice.voice_keys().has(register["voice_key"]), register["voice_key"])
	assert_true(register["band_keys"].has(register["voice_key"]))


## The single voice_key on a Beat is the axis this villager is most extreme
## on -- a gruff, bold, otherwise-average villager is voiced by their
## bluntness, not by whichever axis the AXES array happens to list first.
func test_the_voice_key_is_the_axis_this_genome_is_most_extreme_on():
	assert_eq(
		NpcVoice.voice_key_for(_genome({"gruff": 1.0, "bold": 1.0, "cautious": 0.0, "friendly": 0.0})),
		"bluntness_high"
	)
	assert_eq(
		NpcVoice.voice_key_for(_genome({"cautious": 1.0, "stoic": 1.0, "bold": 0.0, "gruff": 0.0})),
		"hedging_high"
	)
	assert_eq(NpcVoice.voice_key_for(_genome({"gruff": 1.0, "greedy": 1.0, "kind": 0.0, "friendly": 0.0})), "warmth_low")


func test_a_perfectly_average_genome_still_gets_a_key_and_it_is_a_mid_one():
	var key := NpcVoice.voice_key_for(_genome({}))
	assert_true(NpcVoice.voice_keys().has(key), key)
	assert_eq(NpcVoice.parse_key(key)["band"], "mid")


func test_the_same_genome_always_voices_the_same_way():
	var traits := NpcGenome.new(4242, NpcIdentity.PERSONALITY_TRAITS).traits
	assert_eq(NpcVoice.register_for(traits), NpcVoice.register_for(traits))


## Fed straight from a real villager, with no adaptation -- identity.genome.
## traits is exactly the Dictionary this module takes.
func test_a_real_villagers_genome_is_accepted_unchanged():
	var identity := NpcIdentity.new(91)
	var register := NpcVoice.register_for(identity.genome.traits)
	assert_true(NpcVoice.voice_keys().has(register["voice_key"]), register["voice_key"])
