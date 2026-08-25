extends GutTest

## NpcIdentity (docs/concept/npc.md "Identity: each NPC has a name,
## occupation, a small set of personality traits, a driving need/goal"):
## deterministic per-seed identity generation. Relationships (also part of
## Identity per the doc) are deliberately deferred -- see NpcIdentity's own
## doc comment.

const NpcIdentity = preload("res://src/world/npc_identity.gd")


func test_same_seed_produces_the_same_identity():
	var a := NpcIdentity.new(42)
	var b := NpcIdentity.new(42)
	assert_eq(a.npc_name, b.npc_name)
	assert_eq(a.occupation, b.occupation)
	assert_eq(a.personality_trait, b.personality_trait)
	assert_eq(a.need, b.need)


func test_different_seeds_can_differ():
	var seen_names := {}
	var seen_occupations := {}
	for seed_value in range(40):
		var identity := NpcIdentity.new(seed_value)
		seen_names[identity.npc_name] = true
		seen_occupations[identity.occupation] = true
	assert_gt(seen_names.size(), 1)
	assert_gt(seen_occupations.size(), 1)


func test_seed_value_is_stored_for_reuse_by_a_renderer():
	assert_eq(NpcIdentity.new(77).seed_value, 77)


func test_name_is_non_empty():
	for seed_value in range(20):
		assert_gt(NpcIdentity.new(seed_value).npc_name.length(), 0)


## WORK_LOCATION_BY_OCCUPATION is the one shared source both NpcPlanner
## (which location_tag a villager's schedule sends them to) and
## VillageRenderer (which landmark prop, if any, actually stands there) read
## from -- see docs/concept/building.md's "close the remaining gap" note.
## Every known occupation must have a mapped work location, or a villager of
## that occupation would silently get no location_tag at all.
func test_every_occupation_has_a_mapped_work_location():
	for occupation in NpcIdentity.OCCUPATIONS:
		assert_true(
			NpcIdentity.WORK_LOCATION_BY_OCCUPATION.has(occupation),
			"no work location mapped for %s" % occupation
		)
		assert_gt(NpcIdentity.WORK_LOCATION_BY_OCCUPATION[occupation].length(), 0, occupation)


func test_occupation_is_always_a_known_occupation():
	for seed_value in range(40):
		var identity := NpcIdentity.new(seed_value)
		assert_true(
			NpcIdentity.OCCUPATIONS.has(identity.occupation),
			"unexpected occupation: %s" % identity.occupation
		)


func test_personality_trait_is_always_known():
	for seed_value in range(40):
		var identity := NpcIdentity.new(seed_value)
		assert_true(NpcIdentity.PERSONALITY_TRAITS.has(identity.personality_trait))


## The follow-up ask: personality should be DNA derived, not an independent
## flat roll -- personality_trait must be exactly the genome's own
## dominant_trait(), not a second unrelated pick that merely happens to
## agree.
func test_personality_trait_is_derived_from_the_npcs_own_genome():
	for seed_value in range(20):
		var identity := NpcIdentity.new(seed_value)
		assert_eq(identity.personality_trait, identity.genome.dominant_trait())


func test_genome_carries_a_gene_for_every_personality_trait():
	var identity := NpcIdentity.new(11)
	for trait_name in NpcIdentity.PERSONALITY_TRAITS:
		assert_true(identity.genome.traits.has(trait_name), trait_name)


func test_need_is_always_known():
	for seed_value in range(40):
		var identity := NpcIdentity.new(seed_value)
		assert_true(NpcIdentity.NEEDS.has(identity.need))


## Every known occupation should actually appear across enough samples --
## otherwise the "pick" logic silently favors a subset.
func test_every_occupation_appears_across_enough_samples():
	var seen := {}
	for seed_value in range(300):
		seen[NpcIdentity.new(seed_value).occupation] = true
	for occupation in NpcIdentity.OCCUPATIONS:
		assert_true(seen.has(occupation), "occupation never appeared: %s" % occupation)


## docs/concept/npc.md "Needs and the local production economy": hunter
## (a producer, distinct from farmer) and nurse (a new non-producer
## village-care role) both join the occupation roster this pass.
func test_hunter_and_nurse_are_valid_occupations():
	assert_true(NpcIdentity.OCCUPATIONS.has("hunter"))
	assert_true(NpcIdentity.OCCUPATIONS.has("nurse"))
