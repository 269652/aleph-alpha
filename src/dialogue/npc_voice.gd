extends RefCounted

## How a villager SOUNDS, derived from the genome they already have
## (docs/concept/dialogue.md's pipeline, second stage). Every NpcIdentity
## carries a full 8-entry continuous NpcGenome, and until now exactly one
## number of it was ever read: NpcGenome.dominant_trait(), the argmax, which
## collapses eight independent floats into one categorical label. Everything
## else -- the 7 losing genes, and how far the winner won by -- was
## generated and thrown away every time a settlement loaded. That discarded
## signal is what makes two villagers who are both nominally "gruff" sound
## like different people, so this module spends it.
##
## Five axes, each a contrast between two genes that raise it and two that
## lower it, then a band per axis, then one voice_key: "<axis>_<band>", e.g.
## "bluntness_high". OfflineRenderer indexes its phrasing pools by that key,
## and it is half of the AI seam's cache key (voice_key, topic_id, kind,
## fact_band) -- which is why the key names a VOICE and never an NPC.
##
## Pure: Dictionary in, Dictionary out, no Node and no world access. The
## genome Dictionary this takes is exactly `identity.genome.traits`, handed
## over unchanged.

## The five axes, in the order a tie between two equally extreme axes is
## broken -- first listed wins, same first-match convention as
## NpcGenome.dominant_trait().
const AXES: Array[String] = ["warmth", "bluntness", "verbosity", "hedging", "self_interest"]

## Ordered low -> high; "mid" is the band a villager lands in on an axis
## they are unremarkable on.
const BANDS: Array[String] = ["low", "mid", "high"]

## Which of NpcIdentity.PERSONALITY_TRAITS' 8 genes pull each axis up and
## which pull it down. Two of each, so an axis is a contrast between two
## real dispositions rather than a rename of one gene -- a villager is blunt
## because they are gruff and bold AND not cautious or friendly, which is a
## thing eight independent genes can say and one argmax label cannot.
##
## Every gene appears at least once (pinned by test_npc_voice.gd) -- a gene
## read by no axis would be back to being generated and discarded, the exact
## waste this module exists to stop. `curious` is read once, by verbosity:
## it is the one gene whose plain-language meaning maps to a single
## conversational behaviour (asking, at length) rather than to a tension
## between two.
const AXIS_GENES := {
	"warmth": {"raises": ["friendly", "kind"], "lowers": ["gruff", "greedy"]},
	"bluntness": {"raises": ["gruff", "bold"], "lowers": ["cautious", "friendly"]},
	"verbosity": {"raises": ["curious", "friendly"], "lowers": ["stoic", "gruff"]},
	"hedging": {"raises": ["cautious", "stoic"], "lowers": ["bold", "gruff"]},
	"self_interest": {"raises": ["greedy", "bold"], "lowers": ["kind", "friendly"]},
}

## What a gene the genome does not carry is worth. A missing gene means "no
## signal", which is the midpoint, not the floor -- reading it as 0.0 would
## silently drag every axis that names it toward its low band.
const NEUTRAL_GENE := 0.5

## MEASURED, not chosen: the 1/3 and 2/3 quantiles of each axis over 6000
## real villagers drawn through the real generator (SettlementGenerator
## picks the villages, NpcIdentity rolls the genomes) -- literally the
## output of measure_band_edges below, pinned by
## test_npc_voice_band_distribution.gd, which re-measures and fails if these
## drift.
##
## An eyeballed cut cannot work here and the same test proves both halves of
## why. Cutting [0, 1] into even thirds leaves 68-80% of a real village in
## the middle band on every axis, because a 4-gene contrast concentrates at
## its mean; and reading the genome the way the game does today -- one
## argmax gene, "strong" over some high number -- brands 1 - 0.85^8 = 72.8%
## of villagers strong. Both produce one voice, not fifteen.
##
## Each axis carries its own pair rather than one shared pair: the genes are
## hash-derived rather than truly uniform, so the five axes do not land on
## quite the same distribution (hedging's middle band is the widest at
## 0.150, self_interest's the most off-centre). One shared pair would tilt
## the axes that differ.
const BAND_EDGES := {
	"warmth": {"low": 0.429825, "high": 0.560625},
	"bluntness": {"low": 0.433225, "high": 0.563225},
	"verbosity": {"low": 0.443075, "high": 0.561075},
	"hedging": {"low": 0.4161, "high": 0.5665},
	"self_interest": {"low": 0.44595, "high": 0.57995},
}


## Both genes that raise this axis and both that lower it, as one flat list
## -- what "this axis reads that gene" means.
static func genes_of(axis_name: String) -> Array[String]:
	var genes: Array[String] = []
	for gene in AXIS_GENES[axis_name]["raises"]:
		genes.append(gene)
	for gene in AXIS_GENES[axis_name]["lowers"]:
		genes.append(gene)
	return genes


## One axis, in [0, 1]: the mean of the genes that raise it minus the mean
## of the genes that lower it, re-centred on 0.5. Means rather than sums so
## an axis stays comparable if a later pass gives one three genes.
##
## Note what this does to the spread, because it is the whole reason the
## bands below are measured: a contrast of four independent uniforms has
## sd = 1/sqrt(48) = 0.144, so a real population sits almost entirely
## between 0.2 and 0.8 and NEVER fills [0, 1] evenly.
static func axis_value(axis_name: String, traits: Dictionary) -> float:
	var raises := _gene_mean(AXIS_GENES[axis_name]["raises"], traits)
	var lowers := _gene_mean(AXIS_GENES[axis_name]["lowers"], traits)
	return clampf(0.5 + (raises - lowers) * 0.5, 0.0, 1.0)


## Every axis of one genome: axis_name -> float in [0, 1].
static func axes_for(traits: Dictionary) -> Dictionary:
	var axes := {}
	for axis_name in AXES:
		axes[axis_name] = axis_value(axis_name, traits)
	return axes


## Which third of the real population this value falls in on this axis.
static func band_of(axis_name: String, value: float) -> String:
	var edges: Dictionary = BAND_EDGES[axis_name]
	if value < float(edges["low"]):
		return "low"
	if value >= float(edges["high"]):
		return "high"
	return "mid"


## Every axis's band: axis_name -> "low" | "mid" | "high".
static func bands_for(traits: Dictionary) -> Dictionary:
	var bands := {}
	for axis_name in AXES:
		bands[axis_name] = band_of(axis_name, axis_value(axis_name, traits))
	return bands


static func key_for(axis_name: String, band: String) -> String:
	return "%s_%s" % [axis_name, band]


## The inverse. Splits on the LAST underscore, because `self_interest`
## carries one of its own -- a caller splitting on the first would read that
## axis as "self".
static func parse_key(voice_key: String) -> Dictionary:
	var cut := voice_key.rfind("_")
	if cut < 0:
		return {"axis": voice_key, "band": ""}
	return {"axis": voice_key.substr(0, cut), "band": voice_key.substr(cut + 1)}


## Every key the renderer needs a phrasing pool for: 5 axes x 3 bands.
static func voice_keys() -> Array[String]:
	var keys: Array[String] = []
	for axis_name in AXES:
		for band in BANDS:
			keys.append(key_for(axis_name, band))
	return keys


## The one key that voices this villager: the axis they are most extreme
## on. Not the highest axis VALUE -- that would just name whichever axis
## happens to sit highest on a middling genome -- but the axis furthest
## outside its own middle band, measured in that axis's own band widths so
## the five are compared on equal terms.
static func voice_key_for(traits: Dictionary) -> String:
	var best_axis := AXES[0]
	var best_extremity := -INF
	for axis_name in AXES:
		var extremity := _extremity(axis_name, axis_value(axis_name, traits))
		if extremity > best_extremity:
			best_extremity = extremity
			best_axis = axis_name
	return key_for(best_axis, band_of(best_axis, axis_value(best_axis, traits)))


## Everything the pipeline downstream of here reads about how this villager
## talks. `voice_key` is the single key on a Beat; `bands` is what the
## renderer's slot logic reads (high bluntness with low verbosity drops
## three of five slots, which needs two axes, not the winner alone);
## `band_keys` is the same five bands already in key form.
static func register_for(traits: Dictionary) -> Dictionary:
	var axes := axes_for(traits)
	var bands := {}
	var band_keys: Array[String] = []
	for axis_name in AXES:
		var band := band_of(axis_name, float(axes[axis_name]))
		bands[axis_name] = band
		band_keys.append(key_for(axis_name, band))
	return {
		"axes": axes,
		"bands": bands,
		"band_keys": band_keys,
		"voice_key": voice_key_for(traits),
	}


## Where BAND_EDGES comes from: the 1/3 and 2/3 quantiles of each axis, over
## a real population of genomes. Kept here rather than in the test that runs
## it so the constants above have an executable derivation instead of a
## comment claiming they were measured once -- re-run it against the real
## generator and it reproduces them (test_npc_voice_band_distribution.gd).
static func measure_band_edges(genomes: Array) -> Dictionary:
	var edges := {}
	for axis_name in AXES:
		var values: Array[float] = []
		for traits in genomes:
			values.append(axis_value(axis_name, traits))
		values.sort()
		edges[axis_name] = {
			"low": _quantile(values, 1.0 / 3.0),
			"high": _quantile(values, 2.0 / 3.0),
		}
	return edges


static func _gene_mean(genes: Array, traits: Dictionary) -> float:
	if genes.is_empty():
		return NEUTRAL_GENE
	var total := 0.0
	for gene in genes:
		total += float(traits.get(gene, NEUTRAL_GENE))
	return total / float(genes.size())


## How far outside its middle band a value sits, in units of that axis's own
## band width. Negative while the value is still inside the middle band --
## a villager average on all five axes is least-average on whichever one
## sits closest to an edge.
static func _extremity(axis_name: String, value: float) -> float:
	var edges: Dictionary = BAND_EDGES[axis_name]
	var low := float(edges["low"])
	var high := float(edges["high"])
	var width := high - low
	if width <= 0.0:
		return 0.0
	if value < low:
		return (low - value) / width
	if value >= high:
		return (value - high) / width
	return -minf(value - low, high - value) / width


## The value below which `fraction` of a sorted sample sits. Picking a real
## sample value (rather than interpolating between two) is what makes the
## resulting edge a cut the population actually splits on.
static func _quantile(sorted_values: Array[float], fraction: float) -> float:
	if sorted_values.is_empty():
		return NEUTRAL_GENE
	var index := clampi(int(floor(sorted_values.size() * fraction)), 0, sorted_values.size() - 1)
	return sorted_values[index]
