extends GutTest

## BossPhaseKits (docs/concept/worldbosses.md's Krampus encounter-design
## section): hand-authored phase/ability kits for world bosses that haven't
## gone through the emergent fitness-promotion pipeline
## (world_boss_fitness.gd) and its one-shot LLM PhaseGenerator -- debug-
## spawned bosses like Krampus need SOME kit to fight with today. Same
## {"hp_threshold", "ability"} shape PhaseGenerator produces (see
## BossPhase), so a hand-authored kit and a real promoted individual's
## baked phases are interchangeable to whatever reads them.

const BossPhaseKits = preload("res://src/gameplay/boss_phase_kits.gd")
const BossPhase = preload("res://src/gameplay/boss_phase.gd")

var kits: BossPhaseKits


func before_each():
	kits = BossPhaseKits.new()


func test_has_kit_true_for_krampus():
	assert_true(kits.has_kit("krampus"))


func test_has_kit_false_for_an_unregistered_species():
	assert_false(kits.has_kit("herbivore"))
	assert_false(kits.has_kit("totally_unknown_species"))


func test_kit_for_unregistered_species_is_an_empty_array_not_a_crash():
	assert_eq(kits.kit_for("herbivore"), [])


func test_krampus_kit_has_the_documented_three_abilities():
	var kit := kits.kit_for("krampus")
	var names: Array = []
	for phase in kit:
		names.append(phase["ability"])
	assert_true(names.has("chain_lash"))
	assert_true(names.has("terrifying_roar"))
	assert_true(names.has("chain_shackle"))


## Every phase entry must be shaped exactly like WorldBossFitness.
## PhaseGenerator's output -- BossPhase (and anything downstream) has no
## reason to know or care whether a kit was hand-authored or LLM-generated.
func test_krampus_kit_entries_are_phase_generator_shaped():
	for phase in kits.kit_for("krampus"):
		assert_true(phase.has("hp_threshold"), "every entry needs hp_threshold")
		assert_true(phase.has("ability"), "every entry needs ability")
		assert_true(phase["hp_threshold"] is float, "hp_threshold must be a float")


## Mutating a returned kit must never corrupt the shared source table --
## same defensive-copy discipline as SpellAtomCatalog.spec().
func test_kit_for_returns_a_defensive_copy():
	var first := kits.kit_for("krampus")
	first.clear()
	assert_gt(kits.kit_for("krampus").size(), 0, "the shared kit table must be unaffected")


## Real end-to-end sanity: Krampus's actual kit, read through BossPhase,
## produces the two-ability phase-2 moment his own docs describe.
func test_krampus_kit_reads_correctly_through_boss_phase():
	var phase := BossPhase.new()
	var kit := kits.kit_for("krampus")
	var names := phase.active_ability_names(kit, 0.5)
	assert_eq(names.size(), 2)
	assert_true(names.has("chain_lash"))
	assert_true(names.has("terrifying_roar"))
