extends RefCounted

## An atom as a thing a player can OWN (docs/concept/spell_weaving.md).
##
## The magic DSL is finished and nobody can write in it: spell_parser.gd,
## spell_atom_catalog.gd, spell_cost.gd and spell_executor.gd are all real,
## and the only thing above them is spell_book.gd's FIXED authored table.
## There is no way to acquire a part of a spell. A mote is that missing
## noun -- one atom, with the display name, tradition, tier and rarity a
## socket screen needs to draw it -- plus the two rules that say where one
## comes from: what you have to LIVE THROUGH to be given your first, and
## how deep a mote the ground you are standing on may drop.
##
## Pure: RefCounted, static functions, no scene tree, no world access, no
## file access, no singleton. It preloads the four modules it refuses to
## have a second opinion about -- the catalog (tier and category), the
## schools (tradition), RarityTier (the rarity words the rest of the game
## already uses) and JourneyRing (the ladder drops are paced against) --
## and nothing else.
##
## Deliberately NOT an inventory and NOT a drop roller: which motes a given
## player holds is a caller's state, and chance belongs to RarityTier's own
## roll_tier. This answers "what is this mote" and "may one drop here".

const SpellAtomCatalog = preload("res://src/gameplay/spell_atom_catalog.gd")
const SpellSchools = preload("res://src/gameplay/spell_schools.gd")
const RarityTier = preload("res://src/gameplay/rarity_tier.gd")
const JourneyRing = preload("res://src/gameplay/journey_ring.gd")

## The catalog's shallowest tier. Named because the drop cap is stated as a
## RELATIONSHIP to it ("this ring's difficulty band, plus the shallowest
## tier there is") rather than as a table of literals -- see
## drop_tier_cap_for_ring.
const MIN_ATOM_TIER := 1

## The phenomena the world can teach a first mote with. Every one of them
## is a system that ALREADY exists and can already hurt you, which is the
## whole point: magic here is survived before it is studied (spell_
## weaving.md pillar 3). The ids are for a caller to raise, not display
## strings.
const PHENOMENON_FROZE := "froze"
const PHENOMENON_ENVENOMATED := "envenomated"
const PHENOMENON_WARMED_AT_A_FIRE := "warmed_at_a_fire"
const PHENOMENON_CAUGHT_IN_A_STORM := "caught_in_a_storm"
const PHENOMENON_HUNGRY_IN_THE_DARK := "hungry_in_the_dark"
const PHENOMENON_CLIMBED_HARD_GROUND := "climbed_ground_that_fought_back"
const PHENOMENON_HUNTED := "hunted"

## phenomenon -> the atom that phenomenon teaches, in a fixed order so a
## "what the world has taught you" list never reshuffles between two looks.
##
## The mapping is INJECTIVE (test_no_two_phenomena_teach_the_same_mote): no
## two experiences hand you the same mote, so nothing that happens to you
## is redundant. And every atom here is within drop_tier_cap_for_ring(0) --
## pinned against the cap rather than against a literal 1 -- because
## suffering is a head start, not a shortcut past the walking.
##
## Seven of twenty-five atoms have a witness. The other eighteen are found,
## and found further out; a world that taught you everything by hurting you
## would leave nothing to go and look for.
const _WITNESS_ATOMS := {
	# SurvivalMeters.is_freezing: the cold that is already killing you.
	PHENOMENON_FROZE: "frost_damage",
	# VenomModel's stacking bite -- the only species that applies it is
	# venomous_snake, which lives only in the far country.
	PHENOMENON_ENVENOMATED: "poison_damage",
	# The campfire placeable (ItemCatalog "campfire"): the first fire most
	# players stand at is one they lit on purpose.
	PHENOMENON_WARMED_AT_A_FIRE: "fire_damage",
	# WeatherModel's "storm" state.
	PHENOMENON_CAUGHT_IN_A_STORM: "shock_damage",
	# SurvivalMeters.is_starving after VillageRenderer.is_night -- wanting
	# to see is what teaches light, not admiring it.
	PHENOMENON_HUNGRY_IN_THE_DARK: "illuminate",
	# TerrainPassability.speed_multiplier on ground steep enough to fight
	# you: being slowed is how you learn to slow something else.
	PHENOMENON_CLIMBED_HARD_GROUND: "slow",
	# A predator that chose you (BossAggro's chase, and the flight side of
	# ThreatAvoidantWander seen from the wrong end).
	PHENOMENON_HUNTED: "fear",
}

## Lazily built, static so the catalog is constructed once for the whole
## game rather than once per lookup -- the same convention SpellSchools'
## own _catalog/_executor cache uses.
static var _catalog: SpellAtomCatalog = null


static func _atoms() -> SpellAtomCatalog:
	if _catalog == null:
		_catalog = SpellAtomCatalog.new()
	return _catalog


## The atom catalog's own tier, or 0 for a thing that is not an atom --
## the same "unrecognized contributes nothing" convention spell_cost.gd's
## atom_cost uses for an unknown atom.
static func tier_of(atom_id: String) -> int:
	if not _atoms().has(atom_id):
		return 0
	return _atoms().tier(atom_id)


static func category_of(atom_id: String) -> String:
	if not _atoms().has(atom_id):
		return ""
	return _atoms().category(atom_id)


## The tradition that teaches this mote -- SpellSchools', not a second
## grouping of the same atoms.
static func school_of(atom_id: String) -> String:
	return SpellSchools.school_of(atom_id)


## The mote's rarity band: RarityTier's OWN vocabulary, indexed by the
## atom's own tier. Not a second rarity scale, and not a roll -- a mote's
## band is a fact about the atom, the same way a spell gem's band is a fact
## about its complexity (rarity_tier.gd's tier_from_complexity).
##
## Note what this deliberately cannot reach: RarityTier's fourth band,
## `legendary`. The deepest atom there is is tier 3 -> `rare`, so no mote
## you PICK UP is ever top-band. Legendary is what a composition earns
## (spell_draft.gd's rarity_of), which is the whole argument for having a
## crafting screen at all.
static func rarity_of(atom_id: String) -> String:
	var tier := tier_of(atom_id)
	if tier <= 0:
		return ""
	return String(RarityTier.TIERS[clampi(tier - 1, 0, RarityTier.TIERS.size() - 1)])


## "frost_damage" -> "Frost Damage". Godot's own String.capitalize() is the
## snake_case-to-Title-Case rule, so the display name is DERIVED from the
## id rather than a second hand-written table that could drift from the
## catalog the day an atom is added.
static func display_name_for(atom_id: String) -> String:
	return atom_id.capitalize()


## The whole record a socket screen needs, or {} for a thing that is not an
## atom (same convention as tier_of above).
static func mote_for(atom_id: String) -> Dictionary:
	if not _atoms().has(atom_id):
		return {}
	return {
		"atom": atom_id,
		"name": display_name_for(atom_id),
		"school": school_of(atom_id),
		"category": category_of(atom_id),
		"tier": tier_of(atom_id),
		"rarity": rarity_of(atom_id),
	}


## Every phenomenon that teaches something, in the table's fixed order.
static func witnessable_phenomena() -> Array:
	return _WITNESS_ATOMS.keys()


## The mote a phenomenon hands you the first time you live through it, or
## "" for an experience that teaches nothing. Most experiences teach
## nothing: the table is short on purpose.
static func first_witness_atom_for(phenomenon: String) -> String:
	return String(_WITNESS_ATOMS.get(phenomenon, ""))


## The deepest atom tier that may DROP at a journey ring: the ring's own
## RegionDifficulty band ordinal plus MIN_ATOM_TIER. EASY ground drops
## tier 1, MEDIUM up to tier 2, HARD up to tier 3.
##
## This is a derivation, not a table. A summon_wisp mote cannot exist in
## the hearth for EXACTLY the reason a bear cannot -- the hearth is EASY --
## so magic's pacing and the ecosystem's pacing can never drift apart
## (journey_rings.md pillar 1, borrowed wholesale). Retune JourneyRing's
## bands and these caps follow for free.
##
## The identity is only total because the catalog has as many tiers as
## RegionDifficulty has bands; test_the_catalogs_tier_range_matches_the_
## difficulty_bands fails loudly if that ever stops being true, rather than
## letting a tier-4 atom become quietly undroppable.
##
## An index off either end of the ladder is clamped rather than trusted --
## a caller that computed a ring index some other way cannot fall off the
## front of the table (JourneyRing.ring_index_at's own convention).
static func drop_tier_cap_for_ring(ring_index: int) -> int:
	var rings: Array = JourneyRing.rings()
	var index := clampi(ring_index, 0, rings.size() - 1)
	return MIN_ATOM_TIER + int(rings[index]["tier"])


## Whether this atom is deep enough ground to be found here at all. Says
## nothing about the odds -- that is the loot layer's and RarityTier's.
static func can_drop_at_ring(atom_id: String, ring_index: int) -> bool:
	var tier := tier_of(atom_id)
	if tier <= 0:
		return false
	return tier <= drop_tier_cap_for_ring(ring_index)


## Every mote this ring may yield, sorted so a drop table, a readout or a
## test never depends on the catalog's own insertion order.
static func droppable_atoms_at_ring(ring_index: int) -> Array:
	var eligible: Array = []
	for atom_id in _atoms().known_ids():
		if can_drop_at_ring(String(atom_id), ring_index):
			eligible.append(String(atom_id))
	eligible.sort()
	return eligible
