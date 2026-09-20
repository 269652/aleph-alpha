extends GutTest

## Red-first spec for an atom as a thing a player can OWN (docs/concept/
## spell_weaving.md). Today the spell stack is complete and closed: the
## parser, the catalog, the cost model and the executor all work, and the
## only thing above them is spell_book.gd's fixed authored table. There is
## no way to acquire a PART of a spell.
##
## The load-bearing tests here are the two that keep this module from
## becoming a second opinion:
##
## - rarity is RarityTier's vocabulary indexed by the atom catalog's own
##   tier, never a second rarity scale (and `legendary` stays unreachable
##   by any single mote, because composition is what earns it);
## - which tiers may DROP at a ring is JourneyRing's own RegionDifficulty
##   band plus one, swept over the whole ring ladder, so a tier-3 mote
##   cannot exist in the starting ring for exactly the reason a bear
##   cannot.

const SpellMote = preload("res://src/gameplay/spell_mote.gd")
const SpellAtomCatalog = preload("res://src/gameplay/spell_atom_catalog.gd")
const SpellSchools = preload("res://src/gameplay/spell_schools.gd")
const RarityTier = preload("res://src/gameplay/rarity_tier.gd")
const JourneyRing = preload("res://src/gameplay/journey_ring.gd")
const RegionDifficulty = preload("res://src/world/region_difficulty.gd")

var catalog: SpellAtomCatalog
var rarity: RarityTier


func before_each():
	catalog = SpellAtomCatalog.new()
	rarity = RarityTier.new()


# -- the mote record --------------------------------------------------------


func test_a_mote_carries_the_catalogs_own_tier_and_category():
	var mote: Dictionary = SpellMote.mote_for("frost_damage")
	assert_eq(mote.get("atom", ""), "frost_damage")
	assert_eq(mote.get("tier", 0), catalog.tier("frost_damage"), "tier must be the catalog's")
	assert_eq(mote.get("category", ""), catalog.category("frost_damage"))


func test_a_mote_names_the_tradition_that_teaches_it():
	var mote: Dictionary = SpellMote.mote_for("frost_damage")
	assert_eq(mote.get("school", ""), SpellSchools.school_of("frost_damage"))
	assert_eq(mote.get("school", ""), "cryomancy", "cold is cryomancy's trade")


func test_every_catalog_atom_has_a_complete_mote():
	for atom_id in catalog.known_ids():
		var mote: Dictionary = SpellMote.mote_for(atom_id)
		for key in ["atom", "name", "school", "category", "tier", "rarity"]:
			assert_true(mote.has(key), "%s's mote is missing %s" % [atom_id, key])
		assert_ne(String(mote["school"]), "", "%s belongs to no tradition" % atom_id)
		assert_ne(String(mote["name"]), "", "%s has no display name" % atom_id)


func test_a_thing_that_is_not_an_atom_has_no_mote():
	var nothing: Dictionary = SpellMote.mote_for("summon_dragon")
	assert_true(nothing.is_empty(), "an unknown atom is not a mote")
	assert_eq(SpellMote.rarity_of("summon_dragon"), "")
	assert_eq(SpellMote.tier_of("summon_dragon"), 0)


func test_the_display_name_is_the_atom_id_made_readable():
	assert_eq(SpellMote.display_name_for("frost_damage"), "Frost Damage")
	assert_eq(SpellMote.display_name_for("summon_wisp"), "Summon Wisp")
	assert_eq(SpellMote.display_name_for("reveal"), "Reveal")


# -- rarity is RarityTier's, never a second scale ---------------------------


func test_rarity_is_rarity_tiers_vocabulary_indexed_by_atom_tier():
	for atom_id in catalog.known_ids():
		var band: String = SpellMote.rarity_of(atom_id)
		assert_true(
			RarityTier.TIERS.has(band), "%s's rarity '%s' is not a RarityTier" % [atom_id, band]
		)
		assert_eq(
			band,
			String(RarityTier.TIERS[catalog.tier(atom_id) - 1]),
			"%s's rarity must be its tier's band" % atom_id
		)


func test_rarity_rises_with_tier():
	assert_eq(SpellMote.rarity_of("fire_damage"), "common", "a tier 1 atom is common")
	assert_eq(SpellMote.rarity_of("freeze"), "uncommon", "a tier 2 atom is uncommon")
	assert_eq(SpellMote.rarity_of("summon_wisp"), "rare", "a tier 3 atom is rare")


func test_no_single_mote_is_ever_legendary():
	# Legendary is what a COMPOSITION reaches (see test_spell_draft.gd's
	# test_four_sockets_is_exactly_the_room_a_legendary_needs). A mote you
	# picked up being top-band would make crafting pointless.
	for atom_id in catalog.known_ids():
		assert_ne(SpellMote.rarity_of(atom_id), "legendary", "%s is a legendary pickup" % atom_id)


# -- the witness table: the first mote is survived, not looted --------------


func test_every_phenomenon_teaches_a_real_atom():
	var phenomena: Array = SpellMote.witnessable_phenomena()
	assert_gt(phenomena.size(), 2, "a world that teaches two things teaches nothing")
	for phenomenon in phenomena:
		var atom_id: String = SpellMote.first_witness_atom_for(phenomenon)
		assert_true(catalog.has(atom_id), "%s teaches '%s', which is not an atom" % [phenomenon, atom_id])


func test_the_named_phenomena_teach_what_they_are():
	assert_eq(SpellMote.first_witness_atom_for("froze"), "frost_damage")
	assert_eq(SpellMote.first_witness_atom_for("envenomated"), "poison_damage")
	assert_eq(SpellMote.first_witness_atom_for("warmed_at_a_fire"), "fire_damage")
	assert_eq(SpellMote.first_witness_atom_for("caught_in_a_storm"), "shock_damage")
	assert_eq(SpellMote.first_witness_atom_for("hungry_in_the_dark"), "illuminate")


func test_a_phenomenon_nobody_lives_through_teaches_nothing():
	assert_eq(SpellMote.first_witness_atom_for("read_a_book"), "")


func test_no_two_phenomena_teach_the_same_mote():
	var seen: Dictionary = {}
	for phenomenon in SpellMote.witnessable_phenomena():
		var atom_id: String = SpellMote.first_witness_atom_for(phenomenon)
		assert_false(seen.has(atom_id), "%s teaches %s, already taught by %s" % [phenomenon, atom_id, seen.get(atom_id, "")])
		seen[atom_id] = phenomenon


func test_witnessing_never_teaches_deeper_than_the_hearth_would_drop():
	# Suffering is a head start, not a shortcut: the deepest thing an
	# experience can hand you is what the ground you are standing on would
	# have dropped anyway. Pinned against the cap, not against a literal 1.
	var hearth_cap: int = SpellMote.drop_tier_cap_for_ring(0)
	for phenomenon in SpellMote.witnessable_phenomena():
		var atom_id: String = SpellMote.first_witness_atom_for(phenomenon)
		assert_lte(catalog.tier(atom_id), hearth_cap, "%s teaches past the hearth's cap" % phenomenon)


# -- drop caps are JourneyRing's bands, never a second pacing ---------------


func test_the_drop_cap_is_the_rings_own_difficulty_band_plus_one():
	var rings: Array = JourneyRing.rings()
	for i in range(rings.size()):
		var band: int = int(rings[i]["tier"])
		assert_eq(
			SpellMote.drop_tier_cap_for_ring(i),
			SpellMote.MIN_ATOM_TIER + band,
			"%s's cap disagrees with its RegionDifficulty band" % rings[i]["id"]
		)


func test_the_cap_never_falls_as_you_walk_outward():
	var rings: Array = JourneyRing.rings()
	for i in range(rings.size() - 1):
		assert_lte(
			SpellMote.drop_tier_cap_for_ring(i),
			SpellMote.drop_tier_cap_for_ring(i + 1),
			"the cap falls between ring %d and %d" % [i, i + 1]
		)


func test_a_tier_three_mote_cannot_drop_in_the_starting_ring():
	assert_false(SpellMote.can_drop_at_ring("summon_wisp", 0), "conjury in the hearth")
	assert_false(SpellMote.can_drop_at_ring("portal", 0))
	assert_false(SpellMote.can_drop_at_ring("freeze", 0), "even tier 2 waits for the marches")
	assert_true(SpellMote.can_drop_at_ring("fire_damage", 0), "the hearth still drops tier 1")


func test_the_outermost_rings_cap_is_the_catalogs_deepest_tier():
	# Every atom must be obtainable SOMEWHERE, or the catalog carries dead
	# content nobody can ever hold.
	var deepest: int = 0
	for atom_id in catalog.known_ids():
		deepest = maxi(deepest, catalog.tier(atom_id))
	var last: int = JourneyRing.rings().size() - 1
	assert_eq(SpellMote.drop_tier_cap_for_ring(last), deepest, "the far country cannot drop everything")
	for atom_id in catalog.known_ids():
		assert_true(SpellMote.can_drop_at_ring(atom_id, last), "%s can never be found" % atom_id)


func test_the_catalogs_tier_range_matches_the_difficulty_bands():
	# The derivation "band ordinal + 1" is only total because the catalog
	# has exactly as many tiers as RegionDifficulty has bands. A catalog
	# that grew a tier 4 must fail HERE, loudly, rather than quietly
	# shipping an atom no ring can ever drop.
	var deepest: int = 0
	for atom_id in catalog.known_ids():
		deepest = maxi(deepest, catalog.tier(atom_id))
	assert_eq(deepest, RegionDifficulty.Tier.size(), "atom tiers and difficulty bands have drifted apart")


func test_a_ring_index_off_the_end_of_the_ladder_is_clamped():
	var last: int = JourneyRing.rings().size() - 1
	assert_eq(SpellMote.drop_tier_cap_for_ring(-3), SpellMote.drop_tier_cap_for_ring(0))
	assert_eq(SpellMote.drop_tier_cap_for_ring(last + 9), SpellMote.drop_tier_cap_for_ring(last))


func test_the_droppable_list_grows_outward_and_is_stable():
	var near: Array = SpellMote.droppable_atoms_at_ring(0)
	var far: Array = SpellMote.droppable_atoms_at_ring(JourneyRing.rings().size() - 1)
	assert_gt(near.size(), 0, "the hearth drops nothing at all")
	assert_gt(far.size(), near.size(), "distance buys no breadth")
	for atom_id in near:
		assert_true(far.has(atom_id), "%s drops near but not far" % atom_id)
	assert_eq(near, SpellMote.droppable_atoms_at_ring(0), "two looks, two answers")
