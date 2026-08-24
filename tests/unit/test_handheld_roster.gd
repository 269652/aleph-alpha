extends GutTest

## HandheldRoster (docs/concept/easter_eggs.md's "hidden retro handheld"
## entry): pure data describing which of this project's OWN, ALREADY-BUILT
## wildlife species (src/world/creature_info.gd/AnimalAnatomy.SPECIES) the
## handheld's mini-game can field, at which tier, with what battle stats --
## and the deterministic (roll-in, species-out) encounter picker the battle
## view uses to decide which wild creature a fresh encounter starts with.
##
## Deliberately NOT the Easter-egg cameo creatures from other stages
## (squallmaw/coilnecca/champ/krampus's world-boss siblings etc.) -- per the
## doc, "starring miniature... versions of this project's own already-built
## roster", i.e. the real wildlife roster, at common tier (deer/wolf/boar/
## bear/lynx) and the Germany-region legendary tier (krampus/lindwurm/
## rubezahl).
##
## Every stat here is a first-pass placeholder (no real playtesting data for
## this project's Easter eggs yet -- same situation JoustMatch's own doc
## comment documents) but pinned by relative-property tests below rather
## than left as isolated eyeballed literals -- the same "pin the
## relationship, not just the number" discipline test_creature_info.gd's own
## Kraken/Squallmaw tests already use.

const HandheldRoster = preload("res://src/gameplay/handheld_roster.gd")

var roster: HandheldRoster


func before_each():
	roster = HandheldRoster.new()


## --- roster membership: exactly the doc's own species list ---


func test_common_species_are_exactly_the_docs_five():
	var expected: Array = ["deer", "wolf", "boar", "bear", "lynx"]
	var actual := roster.common_species()
	actual.sort()
	expected.sort()
	assert_eq(actual, expected)


func test_legendary_species_are_exactly_the_docs_three():
	var expected: Array = ["krampus", "lindwurm", "rubezahl"]
	var actual := roster.legendary_species()
	actual.sort()
	expected.sort()
	assert_eq(actual, expected)


func test_all_species_is_common_plus_legendary_with_no_overlap():
	var all := roster.all_species()
	for species in roster.common_species():
		assert_true(all.has(species))
	for species in roster.legendary_species():
		assert_true(all.has(species))
	assert_eq(all.size(), roster.common_species().size() + roster.legendary_species().size())


func test_tier_for_common_species_is_common():
	assert_eq(roster.tier_for("deer"), HandheldRoster.TIER_COMMON)


func test_tier_for_legendary_species_is_legendary():
	assert_eq(roster.tier_for("lindwurm"), HandheldRoster.TIER_LEGENDARY)


func test_is_legendary_true_only_for_the_legendary_three():
	assert_true(roster.is_legendary("krampus"))
	assert_false(roster.is_legendary("deer"))


## --- stats: every roster species has a complete, positive stat block ---


func test_every_roster_species_has_a_stat_block_with_all_four_fields():
	for species in roster.all_species():
		var stats := roster.stats_for(species)
		assert_true(stats.has("hp"))
		assert_true(stats.has("attack"))
		assert_true(stats.has("defense"))
		assert_true(stats.has("speed"))


func test_every_roster_species_has_strictly_positive_stats():
	for species in roster.all_species():
		var stats := roster.stats_for(species)
		assert_true(float(stats["hp"]) > 0.0, species)
		assert_true(float(stats["attack"]) > 0.0, species)
		assert_true(float(stats["defense"]) > 0.0, species)
		assert_true(float(stats["speed"]) > 0.0, species)


func test_stats_for_returns_a_copy_not_the_shared_dictionary():
	var a := roster.stats_for("deer")
	a["hp"] = -999.0
	var b := roster.stats_for("deer")
	assert_ne(b["hp"], -999.0)


func test_stats_for_unknown_species_returns_empty_dictionary():
	assert_eq(roster.stats_for("not_a_real_species"), {})


## --- relative property: every legendary outclasses every common on HP ---


func test_every_legendary_has_more_hp_than_every_common():
	var common_max_hp := 0.0
	for species in roster.common_species():
		common_max_hp = maxf(common_max_hp, float(roster.stats_for(species)["hp"]))
	for species in roster.legendary_species():
		assert_true(float(roster.stats_for(species)["hp"]) > common_max_hp, species)


func test_every_legendary_has_more_attack_than_every_common():
	var common_max_attack := 0.0
	for species in roster.common_species():
		common_max_attack = maxf(common_max_attack, float(roster.stats_for(species)["attack"]))
	for species in roster.legendary_species():
		assert_true(float(roster.stats_for(species)["attack"]) > common_max_attack, species)


## --- encounter_species: deterministic roll-in, species-out ---


func test_encounter_species_is_deterministic_for_the_same_roll():
	var a := roster.encounter_species(0.42)
	var b := roster.encounter_species(0.42)
	assert_eq(a, b)


func test_encounter_species_below_legendary_chance_picks_a_legendary():
	var species := roster.encounter_species(0.0)
	assert_true(roster.is_legendary(species))


func test_encounter_species_above_legendary_chance_picks_a_common():
	var species := roster.encounter_species(HandheldRoster.LEGENDARY_ENCOUNTER_CHANCE + 0.01)
	assert_false(roster.is_legendary(species))


func test_encounter_species_covers_every_common_species_across_its_roll_range():
	# (i + 0.5) rather than a bare i/count -- landing exactly on a bucket
	# boundary is at the mercy of float rounding noise in the round trip
	# through encounter_species' own division; the midpoint of each bucket
	# has no such ambiguity.
	var seen := {}
	var count := roster.common_species().size()
	for i in count:
		var roll: float = (
			HandheldRoster.LEGENDARY_ENCOUNTER_CHANCE
			+ (1.0 - HandheldRoster.LEGENDARY_ENCOUNTER_CHANCE) * ((float(i) + 0.5) / float(count))
		)
		seen[roster.encounter_species(roll)] = true
	assert_eq(seen.size(), count)


func test_encounter_species_covers_every_legendary_species_across_its_roll_range():
	var seen := {}
	var count := roster.legendary_species().size()
	for i in count:
		var roll: float = HandheldRoster.LEGENDARY_ENCOUNTER_CHANCE * ((float(i) + 0.5) / float(count))
		seen[roster.encounter_species(roll)] = true
	assert_eq(seen.size(), count)


func test_encounter_species_rejects_a_roll_of_exactly_one_gracefully():
	# 1.0 is outside the half-open [0,1) range every other caller (randf())
	# actually produces, but must not crash or index out of bounds.
	var species := roster.encounter_species(1.0)
	assert_true(roster.all_species().has(species))
