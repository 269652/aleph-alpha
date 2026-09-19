extends GutTest

## MageMaster: docs/concept/mage_guild.md mechanism 2 -- a master is a seed.
##
## Everything about one is derived from a single integer, the same way
## HeroDna/NpcIdentity already derive a whole person from one, so a guild's
## faculty survives a reload without a save format and cannot drift from the
## thing that generated it.

const MageMaster = preload("res://src/gameplay/mage_master.gd")
const SpellSchools = preload("res://src/gameplay/spell_schools.gd")
const SpellBook = preload("res://src/gameplay/spell_book.gd")
const SpellAtomCatalog = preload("res://src/gameplay/spell_atom_catalog.gd")
const RarityTier = preload("res://src/gameplay/rarity_tier.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")
const NpcSkillAllocation = preload("res://src/world/npc_skill_allocation.gd")

var book := SpellBook.new()
var catalog := SpellAtomCatalog.new()


func _seeds(count: int) -> Array:
	var seeds: Array = []
	for i in count:
		seeds.append(hash("master_probe_%d" % i))
	return seeds


# -- a master is a real person, not a label ---------------------------------

func test_a_master_is_a_real_npc_with_a_name():
	var identity = MageMaster.identity_for(1234)
	assert_ne(identity.npc_name, "")


func test_a_master_is_a_mage_and_walks_the_mage_wedge():
	# "the teacher's skills" have to be the same skill system everyone
	# else's are, not a private one.
	var identity = MageMaster.identity_for(1234)
	assert_eq(identity.occupation, MageMaster.OCCUPATION)
	assert_eq(identity.archetype, "mage")
	assert_false(identity.allocated_nodes.is_empty(), "a master must stand somewhere on the real web")


func test_mage_is_never_an_occupation_an_ordinary_villager_rolls():
	# A mage is not a trade a village produces; it is a trade that arrives.
	assert_false(NpcIdentity.OCCUPATIONS.has(MageMaster.OCCUPATION))
	for seed_value in _seeds(200):
		assert_ne(NpcIdentity.new(seed_value).occupation, MageMaster.OCCUPATION)


func test_the_same_seed_is_always_the_same_master():
	assert_eq(MageMaster.school_for(77), MageMaster.school_for(77))
	assert_eq(MageMaster.depth_for(77), MageMaster.depth_for(77))
	assert_eq(MageMaster.identity_for(77).npc_name, MageMaster.identity_for(77).npc_name)


# -- school -----------------------------------------------------------------

func test_a_masters_school_is_always_a_real_school():
	for seed_value in _seeds(100):
		assert_true(SpellSchools.SCHOOL_IDS.has(MageMaster.school_for(seed_value)))


func test_masters_do_not_all_belong_to_one_school():
	# If they did, every guild would teach the same thing and pillar 2 --
	# who came decides what can be learned -- would be decoration.
	var seen := {}
	for seed_value in _seeds(200):
		seen[MageMaster.school_for(seed_value)] = true
	assert_gt(seen.size(), SpellSchools.SCHOOL_IDS.size() / 2,
		"the seed is not really spreading masters across schools")


# -- depth and rarity -------------------------------------------------------

func test_depth_is_always_inside_the_atom_catalogs_own_band():
	for seed_value in _seeds(200):
		assert_between(MageMaster.depth_for(seed_value), SpellSchools.MIN_DEPTH, SpellSchools.MAX_DEPTH)


func test_rarity_is_the_existing_weighted_roll_not_a_new_one():
	var rarity := RarityTier.new()
	for seed_value in _seeds(50):
		assert_eq(MageMaster.rarity_for(seed_value), rarity.roll_tier(seed_value))


func test_depth_rises_with_rarity_and_never_falls():
	var deepest_by_rank := {}
	var rarity := RarityTier.new()
	for seed_value in _seeds(400):
		var rank: int = RarityTier.TIERS.find(MageMaster.rarity_for(seed_value))
		deepest_by_rank[rank] = MageMaster.depth_for(seed_value)
	var ranks: Array = deepest_by_rank.keys()
	ranks.sort()
	for i in range(1, ranks.size()):
		assert_gte(int(deepest_by_rank[ranks[i]]), int(deepest_by_rank[ranks[i - 1]]),
			"a rarer master taught LESS deeply than a commoner one")


func test_the_deepest_masters_are_genuinely_rare():
	# "there should be rare teachers which can teach special rare spells" --
	# rare must mean rare. The existing roll (common 65 / uncommon 25 /
	# rare 8 / legendary 2) is what decides, so this pins the consequence
	# rather than a second weight of this file's own.
	var deep := 0
	var sampled := 400
	for seed_value in _seeds(sampled):
		if MageMaster.depth_for(seed_value) >= SpellSchools.MAX_DEPTH:
			deep += 1
	assert_gt(deep, 0, "no master anywhere can teach the deepest magic")
	assert_lt(float(deep) / float(sampled), 0.25, "an archmage in every other guild is not rare")


func test_every_depth_in_the_band_is_actually_reachable():
	var seen := {}
	for seed_value in _seeds(400):
		seen[MageMaster.depth_for(seed_value)] = true
	for depth in range(SpellSchools.MIN_DEPTH, SpellSchools.MAX_DEPTH + 1):
		assert_true(seen.has(depth), "no master is ever depth %d" % depth)


# -- what a master will teach -----------------------------------------------

func _a_master_of(school: String, depth: int) -> int:
	for seed_value in _seeds(4000):
		if MageMaster.school_for(seed_value) == school and MageMaster.depth_for(seed_value) == depth:
			return seed_value
	fail_test("no master of %s at depth %d in the sample" % [school, depth])
	return 0


func test_a_master_teaches_a_spell_of_their_own_school_within_their_depth():
	var school: String = SpellSchools.school_of_spell(book, "fire_bolt")
	var depth: int = SpellSchools.depth_of_spell(book, "fire_bolt")
	var seed_value := _a_master_of(school, depth)
	assert_true(MageMaster.teaches(book, "fire_bolt", seed_value))


func test_a_master_refuses_a_spell_from_another_school():
	var mine: String = SpellSchools.school_of_spell(book, "fire_bolt")
	var other := ""
	for school in SpellSchools.SCHOOL_IDS:
		if school != mine:
			other = school
			break
	var seed_value := _a_master_of(other, SpellSchools.MAX_DEPTH)
	assert_false(MageMaster.teaches(book, "fire_bolt", seed_value),
		"a master of another tradition taught outside it")


func test_a_master_refuses_a_spell_deeper_than_they_run():
	# Same school, one depth short: the school is right and the answer is
	# still no. That is what makes an archmage worth finding.
	for spell_id in book.known_ids():
		var depth: int = SpellSchools.depth_of_spell(book, spell_id)
		if depth <= SpellSchools.MIN_DEPTH:
			continue
		var shallow := _a_master_of(SpellSchools.school_of_spell(book, spell_id), depth - 1)
		assert_false(MageMaster.teaches(book, spell_id, shallow), "%s" % spell_id)


func test_nobody_teaches_a_spell_outside_the_catalogue():
	for seed_value in _seeds(30):
		assert_false(MageMaster.teaches(book, "not_a_real_spell", seed_value))


func test_teachable_lists_exactly_what_this_master_would_teach():
	for seed_value in _seeds(40):
		var offered: Array = MageMaster.teachable(book, seed_value)
		for spell_id in book.known_ids():
			assert_eq(offered.has(spell_id), MageMaster.teaches(book, spell_id, seed_value), "%s" % spell_id)


func test_teachable_is_stable_in_order():
	assert_eq(MageMaster.teachable(book, 99), MageMaster.teachable(book, 99))


func test_somebody_somewhere_teaches_every_spell_in_the_book():
	# An authored spell no master in the world could ever teach is content
	# nobody can reach. Every spell must have SOME master who would.
	for spell_id in book.known_ids():
		var taught := false
		for seed_value in _seeds(2000):
			if MageMaster.teaches(book, spell_id, seed_value):
				taught = true
				break
		assert_true(taught, "%s is unteachable by anyone in the world" % spell_id)


# -- how a master reads ------------------------------------------------------

func test_a_masters_title_names_their_depth_and_their_school():
	for seed_value in _seeds(30):
		var title: String = MageMaster.title_for(seed_value)
		assert_string_contains(title.to_lower(), MageMaster.school_for(seed_value))
		assert_ne(title, "")


func test_a_deeper_master_carries_a_grander_title():
	var shallow := _a_master_of("pyromancy", SpellSchools.MIN_DEPTH)
	var deep := _a_master_of("pyromancy", SpellSchools.MAX_DEPTH)
	assert_ne(MageMaster.title_for(shallow), MageMaster.title_for(deep))


func test_the_display_name_carries_both_the_person_and_the_title():
	var shown: String = MageMaster.display_name_for(4242)
	assert_string_contains(shown, MageMaster.identity_for(4242).npc_name)
	assert_string_contains(shown, MageMaster.title_for(4242))
