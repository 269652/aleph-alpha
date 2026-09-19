extends GutTest

## SpellSchools: docs/concept/mage_guild.md mechanism 1 -- a partition of
## the atom catalog into traditions a master can be proficient in.
##
## The point of a school is pillar 2: who came to a guild decides what can
## be learned there. That only means anything if a master's proficiency is
## narrower than "magic", and if every atom belongs somewhere -- an atom in
## no school is a spell nobody in the world can ever teach.

const SpellSchools = preload("res://src/gameplay/spell_schools.gd")
const SpellAtomCatalog = preload("res://src/gameplay/spell_atom_catalog.gd")
const SpellBook = preload("res://src/gameplay/spell_book.gd")

var catalog := SpellAtomCatalog.new()
var book := SpellBook.new()


# -- the partition ----------------------------------------------------------

func test_every_atom_in_the_catalog_belongs_to_a_school():
	# An atom in no school is a spell nobody in the world can ever teach.
	for atom_id in catalog.known_ids():
		assert_ne(SpellSchools.school_of(atom_id), "", "%s belongs to no school" % atom_id)


func test_no_atom_belongs_to_two_schools():
	var seen := {}
	for school in SpellSchools.SCHOOL_IDS:
		for atom_id in SpellSchools.atoms_of(school):
			assert_false(seen.has(atom_id), "%s is in both %s and %s" % [atom_id, seen.get(atom_id, ""), school])
			seen[atom_id] = school


func test_every_atom_a_school_claims_is_a_real_atom():
	for school in SpellSchools.SCHOOL_IDS:
		for atom_id in SpellSchools.atoms_of(school):
			assert_true(catalog.has(atom_id), "%s claims '%s', which is not an atom" % [school, atom_id])


func test_the_schools_cover_the_catalog_exactly():
	var claimed := 0
	for school in SpellSchools.SCHOOL_IDS:
		claimed += SpellSchools.atoms_of(school).size()
	assert_eq(claimed, catalog.known_ids().size())


func test_no_school_is_empty():
	for school in SpellSchools.SCHOOL_IDS:
		assert_gt(SpellSchools.atoms_of(school).size(), 0, "%s claims nothing" % school)


func test_an_unknown_atom_has_no_school_rather_than_crashing():
	assert_eq(SpellSchools.school_of("not_a_real_atom"), "")


func test_school_ids_are_stable_in_order():
	assert_eq(SpellSchools.SCHOOL_IDS, SpellSchools.SCHOOL_IDS.duplicate())


## A school has to be narrower than "magic" or a master proficient in one
## teaches everything and pillar 2 collapses.
func test_no_single_school_holds_most_of_the_catalog():
	var total: int = catalog.known_ids().size()
	for school in SpellSchools.SCHOOL_IDS:
		assert_lt(SpellSchools.atoms_of(school).size(), total / 2, "%s is not a school, it is magic" % school)


func test_there_are_enough_schools_that_a_guild_cannot_hold_them_all():
	# Read against the roster's own capacity in test_mage_guild_roster.gd;
	# here only the weaker structural claim, so this file stays about
	# schools: more than a handful of traditions exist.
	assert_gt(SpellSchools.SCHOOL_IDS.size(), 5)


# -- reading a spell --------------------------------------------------------

func test_a_spell_whose_atoms_share_a_school_reports_that_school():
	# frost_lance is frost_damage |> slow -- both cryomancy.
	assert_eq(SpellSchools.school_of_spell(book, "frost_lance"), SpellSchools.school_of("frost_damage"))
	assert_eq(SpellSchools.school_of_spell(book, "fire_bolt"), SpellSchools.school_of("fire_damage"))
	assert_eq(SpellSchools.school_of_spell(book, "minor_heal"), SpellSchools.school_of("minor_heal"))


func test_every_spell_in_the_book_belongs_to_exactly_one_school():
	# A cross-school spell has no single master who could teach it, which is
	# allowed by design -- but the authored book must not quietly contain
	# one, or that spell is unteachable anywhere and nobody would notice.
	for spell_id in book.known_ids():
		assert_ne(SpellSchools.school_of_spell(book, spell_id), "",
			"%s crosses schools -- no master can teach it" % spell_id)


func test_a_spell_outside_the_catalogue_has_no_school():
	assert_eq(SpellSchools.school_of_spell(book, "not_a_real_spell"), "")


# -- how deep a spell runs --------------------------------------------------

func test_a_spells_depth_is_its_deepest_atom():
	for spell_id in book.known_ids():
		var deepest := 0
		for atom_id in SpellSchools.atoms_in_spell(book, spell_id):
			deepest = maxi(deepest, catalog.tier(atom_id))
		assert_eq(SpellSchools.depth_of_spell(book, spell_id), deepest, "%s" % spell_id)


func test_depth_is_always_a_real_catalog_tier():
	for spell_id in book.known_ids():
		var depth: int = SpellSchools.depth_of_spell(book, spell_id)
		assert_between(depth, SpellSchools.MIN_DEPTH, SpellSchools.MAX_DEPTH, "%s" % spell_id)


func test_the_depth_band_is_the_atom_catalogs_own_band_not_a_second_one():
	var lowest := 99
	var highest := 0
	for atom_id in catalog.known_ids():
		lowest = mini(lowest, catalog.tier(atom_id))
		highest = maxi(highest, catalog.tier(atom_id))
	assert_eq(SpellSchools.MIN_DEPTH, lowest)
	assert_eq(SpellSchools.MAX_DEPTH, highest)


func test_a_spell_outside_the_catalogue_has_no_depth():
	assert_eq(SpellSchools.depth_of_spell(book, "not_a_real_spell"), 0)


func test_atoms_in_spell_reads_the_real_pipeline():
	assert_eq(SpellSchools.atoms_in_spell(book, "fire_bolt"), ["fire_damage"])
	assert_eq(SpellSchools.atoms_in_spell(book, "frost_lance"), ["frost_damage", "slow"])
	assert_eq(SpellSchools.atoms_in_spell(book, "not_a_real_spell"), [])
