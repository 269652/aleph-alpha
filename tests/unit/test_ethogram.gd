extends GutTest

## The ethogram: the shared channel basis, the species records, and how a
## genome expresses receptors (see docs/concept/ethogram.md §1, §3, §4, §6).
## A species is data here; the tests are about what that data guarantees.

const Ethogram = preload("res://src/gameplay/ethogram.gd")
const DnaCrossover = preload("res://src/gameplay/dna_crossover.gd")

const SMELLING_SPECIES := ["boar", "deer", "horse", "robin", "fly"]


# -- the basis ---------------------------------------------------------------

func test_the_smell_channels_are_the_first_five_channels_of_the_basis():
	assert_eq(Ethogram.SMELL_CHANNELS, ["sugar", "decay", "green", "musk", "smoke"])
	for index in Ethogram.SMELL_CHANNELS.size():
		assert_eq(Ethogram.CHANNELS[index], Ethogram.SMELL_CHANNELS[index])


func test_the_basis_also_carries_the_non_smell_channels_the_mammal_ladder_needs():
	for channel in ["predator", "player", "flesh", "forage", "water", "mate"]:
		assert_true(Ethogram.CHANNELS.has(channel), channel)
	assert_false(Ethogram.CHANNELS.has("danger"), "danger is a verdict, not a feature")


func test_every_channel_is_named_exactly_once():
	var seen := {}
	for channel in Ethogram.CHANNELS:
		assert_false(seen.has(channel), "duplicate channel %s" % channel)
		seen[channel] = true


# -- species records ---------------------------------------------------------

## The five receptor sets that used to be Olfaction.RECEPTORS.
func test_the_five_noses_moved_from_olfaction_are_all_here():
	for species in SMELLING_SPECIES:
		assert_true(Ethogram.has_nose(species), species)


func test_an_unknown_species_has_no_nose_and_expresses_nothing():
	assert_false(Ethogram.has_nose("nonesuch"))
	assert_true(Ethogram.express("nonesuch").is_empty())


## A new molecule cannot silently be invisible to half the roster.
func test_every_nose_covers_every_smell_channel():
	for species in Ethogram.SPECIES:
		if not Ethogram.has_nose(species):
			continue  # a record that is only a clock (the kingfisher) has nothing to cover
		var expressed := Ethogram.express(species)
		for channel in Ethogram.SMELL_CHANNELS:
			assert_true(expressed["sensitivity"].has(channel), "%s cannot detect %s" % [species, channel])
			assert_true(expressed["valence"].has(channel), "%s has no valence for %s" % [species, channel])


func test_every_species_names_a_body_plan():
	for species in Ethogram.SPECIES:
		assert_ne(String(Ethogram.SPECIES[species].get("body_plan", "")), "", species)


# -- expression: genotype to receptors --------------------------------------

func test_expression_with_no_genome_is_the_species_template():
	var expressed := Ethogram.express("boar")
	var template: Dictionary = Ethogram.SPECIES["boar"]["smell"]
	for channel in Ethogram.SMELL_CHANNELS:
		assert_almost_eq(expressed["sensitivity"][channel], float(template["sensitivity"][channel]), 0.0001)
		assert_almost_eq(expressed["valence"][channel], float(template["valence"][channel]), 0.0001)


## A land mammal's record is merged over its body plan's defaults, so the
## non-smell channels the ladder listens on are always present.
func test_a_mammal_expresses_its_body_plan_defaults_too():
	var expressed := Ethogram.express("deer")
	assert_almost_eq(expressed["sensitivity"]["predator"], 1.0, 0.0001)
	assert_almost_eq(expressed["valence"]["predator"], -1.0, 0.0001, "the default answer to a predator is to leave")
	assert_almost_eq(expressed["sensitivity"]["player"], 1.0, 0.0001)
	assert_almost_eq(expressed["valence"]["player"], -1.0, 0.0001, "...and to a person")
	assert_almost_eq(expressed["valence"]["flesh"], 0.0, 0.0001, "a herbivore wants nothing from prey")
	assert_almost_eq(expressed["valence"]["forage"], 1.0, 0.0001)
	assert_almost_eq(expressed["valence"]["water"], 1.0, 0.0001)
	assert_almost_eq(expressed["valence"]["mate"], 1.0, 0.0001)


## Expression hands back fresh Dictionaries: a caller that adjusts what it
## was given (the mammal adapter flips valences) must not edit the species.
func test_expression_is_a_copy_not_the_record():
	var expressed := Ethogram.express("boar")
	expressed["valence"]["decay"] = 42.0
	assert_ne(Ethogram.express("boar")["valence"]["decay"], 42.0)


## 0.5 is the species template BY DEFINITION: a gene is a deviation from the
## species, and the population mean deviates nowhere.
func test_a_neutral_receptor_gene_reproduces_the_template_exactly():
	var neutral := Ethogram.express("boar", {"receptor_decay": Ethogram.NEUTRAL_RECEPTOR_GENE})
	assert_almost_eq(
		neutral["sensitivity"]["decay"], Ethogram.express("boar")["sensitivity"]["decay"], 0.0001
	)


func test_a_zero_receptor_gene_is_a_specific_anosmia():
	var anosmic := Ethogram.express("boar", {"receptor_decay": 0.0})
	assert_almost_eq(anosmic["sensitivity"]["decay"], 0.0, 0.0001, "the receptor is not expressed at all")
	assert_almost_eq(
		anosmic["sensitivity"]["sugar"], Ethogram.express("boar")["sensitivity"]["sugar"], 0.0001,
		"...and the other receptors are untouched"
	)


func test_receptor_expression_rises_monotonically_with_the_gene():
	var previous := -1.0
	for step in 11:
		var gene := float(step) / 10.0
		var now: float = Ethogram.express("fly", {"receptor_decay": gene})["sensitivity"]["decay"]
		assert_gt(now, previous, "gene %.1f" % gene)
		previous = now


## Only sensitivity is heritable in slice 1; valence is the species' wiring.
func test_a_receptor_gene_never_changes_valence():
	var keen := Ethogram.express("deer", {"receptor_decay": 1.0})
	assert_almost_eq(keen["valence"]["decay"], Ethogram.express("deer")["valence"]["decay"], 0.0001)
	assert_lt(keen["valence"]["decay"], 0.0, "a deer with a keen nose for rot still wants none of it")


func test_a_receptor_gene_for_an_unknown_channel_is_ignored():
	assert_eq(Ethogram.express("boar", {"receptor_moonlight": 1.0}), Ethogram.express("boar"))


func test_a_receptor_gene_outside_the_unit_range_is_clamped():
	var over := Ethogram.express("boar", {"receptor_decay": 7.0})
	var capped := Ethogram.express("boar", {"receptor_decay": 1.0})
	assert_almost_eq(over["sensitivity"]["decay"], capped["sensitivity"]["decay"], 0.0001)
	assert_almost_eq(Ethogram.express("boar", {"receptor_decay": -3.0})["sensitivity"]["decay"], 0.0, 0.0001)


## The inheritance story, end to end, with zero new crossover code: two
## parents' receptor genes go through the unmodified DnaCrossover and the
## child expresses a nose between theirs (give or take the crossover's own
## bounded mutation).
func test_a_child_expresses_a_nose_between_its_parents():
	var parent_a := {"receptor_decay": 0.1}
	var parent_b := {"receptor_decay": 0.9}
	var expressed_a: float = Ethogram.express("fly", parent_a)["sensitivity"]["decay"]
	var expressed_b: float = Ethogram.express("fly", parent_b)["sensitivity"]["decay"]
	var template: float = Ethogram.express("fly")["sensitivity"]["decay"]
	# DnaCrossover nudges by at most MUTATION_AMOUNT of the parents' spread;
	# expressed through the linear law that is this much sensitivity.
	var slack := template * DnaCrossover.MUTATION_AMOUNT * absf(0.9 - 0.1) / Ethogram.NEUTRAL_RECEPTOR_GENE
	var crossover := DnaCrossover.new()
	var seen := {}
	for child_seed in range(1, 21):
		var child := crossover.crossover(parent_a, parent_b, child_seed)
		var expressed_child: float = Ethogram.express("fly", child)["sensitivity"]["decay"]
		assert_gte(expressed_child, minf(expressed_a, expressed_b) - slack - 0.0001, "seed %d" % child_seed)
		assert_lte(expressed_child, maxf(expressed_a, expressed_b) + slack + 0.0001, "seed %d" % child_seed)
		seen["%.4f" % expressed_child] = true
	assert_gt(seen.size(), 1, "children should differ from one another")


# -- body plans and their wirings -------------------------------------------

func test_the_mammal_ladder_puts_fear_before_thirst_before_hunger_before_courtship():
	var gates: Array = []
	for wiring in Ethogram.wirings_for("mammal"):
		gates.append(wiring["gate"])
	var fear := gates.find("fear")
	var thirst := gates.find("thirst")
	var hunger := gates.find("hunger")
	var courtship := gates.find("courtship")
	assert_true(fear >= 0 and thirst >= 0 and hunger >= 0 and courtship >= 0, str(gates))
	assert_lt(fear, thirst)
	assert_lt(thirst, hunger)
	assert_lt(hunger, courtship)


func test_every_wiring_names_a_gate_real_channels_and_an_approach():
	var wirings := Ethogram.wirings_for("mammal")
	assert_gt(wirings.size(), 0)
	for wiring in wirings:
		assert_ne(String(wiring.get("gate", "")), "", str(wiring))
		assert_ne(String(wiring.get("approach", "")), "", str(wiring))
		var channels: Array = wiring.get("channels", [])
		assert_gt(channels.size(), 0, str(wiring))
		for channel in channels:
			assert_true(Ethogram.CHANNELS.has(channel), "%s is not a channel" % channel)


## "All animals search for food when they are hungry" is written ONCE, as the
## wiring that listens on every smell channel plus the one that listens on
## forage; a species gets it by having a nose, not by having code.
func test_the_mammal_ladder_hunts_by_nose_through_one_shared_wiring():
	var by_nose := []
	for wiring in Ethogram.wirings_for("mammal"):
		if wiring["channels"] == Ethogram.SMELL_CHANNELS:
			by_nose.append(wiring)
	assert_eq(by_nose.size(), 1)
	assert_eq(by_nose[0]["gate"], "hunger")
	assert_eq(by_nose[0]["approach"], "seek_food")


func test_a_body_plan_without_wirings_yet_returns_none_rather_than_pretending():
	assert_eq(Ethogram.wirings_for("bird"), [])
	assert_eq(Ethogram.wirings_for("nonesuch"), [])


## Same reason as expression: the ladder is data a caller may want to reorder
## for itself (an instruction override, slice 5) without editing the species.
func test_wirings_are_a_copy_not_the_record():
	var wirings := Ethogram.wirings_for("mammal")
	wirings.clear()
	assert_gt(Ethogram.wirings_for("mammal").size(), 0)


## The land-mammal adapter runs every CreatureMarker species, most of which
## have no record yet, on the mammal ladder: a body-plan override expresses
## that plan's defaults for ANY species and layers the species' own nose on
## top when it has one.
func test_a_body_plan_override_expresses_that_plans_defaults_for_any_species():
	var lynx := Ethogram.express("lynx", {}, "mammal")
	assert_almost_eq(lynx["valence"]["predator"], -1.0, 0.0001)
	assert_false(lynx["sensitivity"].has("decay"), "no record, no nose")
	var robin := Ethogram.express("robin", {}, "mammal")
	assert_almost_eq(robin["valence"]["predator"], -1.0, 0.0001, "the override's defaults")
	assert_almost_eq(
		robin["sensitivity"]["decay"], float(Ethogram.SPECIES["robin"]["smell"]["sensitivity"]["decay"]),
		0.0001, "...under the species' own nose"
	)


# -- slice 2: danger is no longer a verdict ------------------------------------

## The fear wiring listens on what the OTHER thing is; the species valence
## says whether that is something to flee, fight or ignore.
func test_the_fear_wiring_listens_on_predator_and_player():
	var fear := []
	for wiring in Ethogram.wirings_for("mammal"):
		if wiring["gate"] == "fear":
			fear.append(wiring)
	assert_eq(fear.size(), 1)
	assert_eq(fear[0]["channels"], ["predator", "player"])
	assert_eq(fear[0]["approach"], "attack")
	assert_eq(fear[0]["avoid"], "flee")


## The smell wiring carries the interest floor ScentForaging used to keep
## for itself: below it an animal will not cross a field.
func test_the_smell_wiring_carries_the_interest_floor():
	assert_gt(Ethogram.SMELL_INTEREST_FLOOR, 0.0)
	for wiring in Ethogram.wirings_for("mammal"):
		if wiring["channels"] == Ethogram.SMELL_CHANNELS:
			assert_almost_eq(wiring["floor"], Ethogram.SMELL_INTEREST_FLOOR, 0.0)


# -- slice 3: drive profiles are species data ----------------------------------

const SeasonCycle = preload("res://src/world/season_cycle.gd")


## The land-mammal clock is what CreatureNeeds always ran: hunger over 50 s,
## thirst over 33 s, urgent from half way, a meal resets, a herd staggers.
func test_the_mammal_profile_is_the_creature_needs_clock():
	var profile := Ethogram.drive_profile("", "mammal")
	assert_almost_eq(profile["hunger"]["rise_seconds"], 1.0 / 0.02, 0.0001)
	assert_almost_eq(profile["thirst"]["rise_seconds"], 1.0 / 0.03, 0.0001)
	assert_almost_eq(profile["hunger"]["threshold"], 0.5, 0.0)
	assert_almost_eq(profile["thirst"]["threshold"], 0.5, 0.0)
	assert_almost_eq(profile["hunger"]["stagger"], 0.45, 0.0)
	assert_gte(profile["hunger"]["meal"], 1.0, "a meal resets a mammal")


## A villager runs on the same lived-experience pace as any other creature
## and has no thirst to simulate (docs/concept/npc.md).
func test_the_villager_profile_is_hunger_only_at_the_mammal_pace():
	var profile := Ethogram.drive_profile("", "villager")
	assert_true(profile.has("hunger"))
	assert_false(profile.has("thirst"))
	assert_almost_eq(profile["hunger"]["rise_seconds"], 1.0 / 0.02, 0.0001)
	assert_almost_eq(profile["hunger"]["stagger"], 0.45, 0.0)


## A songbird eats through the day (BirdDigestion): an empty crop fills by
## about 0.7 per meal and empties in an eighth of the world day.
func test_the_bird_profile_is_the_songbird_crop():
	var profile := Ethogram.drive_profile("", "bird")
	assert_almost_eq(profile["hunger"]["rise_seconds"], SeasonCycle.SECONDS_PER_DAY / 8.0, 0.0001)
	assert_almost_eq(profile["hunger"]["threshold"], 1.0 - 0.35, 0.0001)
	assert_almost_eq(profile["hunger"]["meal"], 0.7, 0.0001)
	assert_almost_eq(profile["hunger"]["start"], 1.0, 0.0, "a bird starts empty")


## The kingfisher is a bird with its own appetite: a couple of fish a day,
## a whole inter-meal interval before it is interested again.
func test_the_kingfisher_overrides_the_bird_appetite():
	var profile := Ethogram.drive_profile("kingfisher")
	assert_almost_eq(profile["hunger"]["rise_seconds"], SeasonCycle.SECONDS_PER_DAY / 2.0, 0.0001)
	assert_almost_eq(profile["hunger"]["threshold"], 1.0, 0.0)
	assert_almost_eq(profile["hunger"]["meal"], 1.0, 0.0)
	assert_almost_eq(profile["hunger"]["start"], 1.0, 0.0)
	assert_eq(Ethogram.SPECIES["kingfisher"]["body_plan"], "bird")


func test_a_drive_profile_is_a_copy_not_the_record():
	var profile := Ethogram.drive_profile("", "mammal")
	profile["hunger"]["rise_seconds"] = 1.0
	assert_ne(Ethogram.drive_profile("", "mammal")["hunger"]["rise_seconds"], 1.0)


## Every profile keeps the step its own tests pin: no drive opens its gate
## before its threshold today. A ramp is one `onset` away (ethogram.md §5).
func test_no_profile_opens_a_gate_before_its_threshold_yet():
	for plan in ["mammal", "villager", "bird"]:
		for drive in Ethogram.drive_profile("", plan):
			var entry: Dictionary = Ethogram.drive_profile("", plan)[drive]
			assert_false(entry.has("onset"), "%s.%s" % [plan, drive])


# -- slice 4: a boldness gene raises the fear wiring's floor -----------------
#
# docs/concept/ethogram.md §9. Fear's wiring has always had a floor of zero
# (any sensed predator/player registers), which is already the most-fearful
# state possible -- there is nowhere to go MORE shy. Boldness only moves the
# floor UP, and only past the population median: a gene at or below 0.5
# leaves an individual reacting exactly as every land mammal always has.

const Affinity = preload("res://src/gameplay/affinity.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")


func test_boldness_at_or_below_the_population_median_leaves_the_fear_floor_at_zero():
	for gene in [0.0, 0.25, Ethogram.NEUTRAL_BOLDNESS_GENE]:
		assert_eq(Ethogram.fear_floor(gene), 0.0, "gene %.2f" % gene)


func test_fear_floor_rises_monotonically_past_the_median():
	var previous := 0.0
	for step in range(1, 11):
		var gene: float = Ethogram.NEUTRAL_BOLDNESS_GENE + step * (1.0 - Ethogram.NEUTRAL_BOLDNESS_GENE) / 10.0
		var floor_now := Ethogram.fear_floor(gene)
		assert_gt(floor_now, previous, "gene %.2f" % gene)
		previous = floor_now


## Not Affinity.proximity(0.0) (literally touching): that would put the
## ceiling beyond any distance a running simulation actually produces,
## making the boldest individual's fear wiring unreachable rather than
## merely hard to reach. One tile is the reference instead -- the same
## "right here" scale CreatureBehavior already uses to place a sensed
## direction as a stimulus (DIRECTION_STIMULUS_DISTANCE).
func test_the_boldest_gene_caps_the_floor_at_one_tile_away():
	assert_almost_eq(
		Ethogram.fear_floor(1.0), Affinity.proximity(float(TerrainRenderer.TILE_SIZE)), 0.000001
	)


func test_fear_floor_is_clamped_outside_the_unit_gene_range():
	assert_eq(Ethogram.fear_floor(1.5), Ethogram.fear_floor(1.0))
	assert_eq(Ethogram.fear_floor(-1.0), 0.0)
