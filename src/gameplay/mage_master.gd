extends RefCounted

## A mage guild's master (docs/concept/mage_guild.md mechanism 2): a real
## person, derived entirely from one integer seed.
##
## The whole point of this file is that pillar's claim -- **a building is a
## house, not a faculty.** Raising a mage guild builds somewhere for masters
## to be; who actually turns up decides what can be learned there. So a
## master is not a lookup on the building, it is a person with a tradition
## and a depth, and the teachable set falls out of those two facts with no
## per-master list anywhere.
##
## Nothing about a master is stored but the seed, the same way HeroDna and
## NpcIdentity already derive a whole character from one. A guild's faculty
## therefore survives a reload without a save format of its own, and cannot
## drift from the thing that generated it.

const SpellSchools = preload("res://src/gameplay/spell_schools.gd")
const RarityTier = preload("res://src/gameplay/rarity_tier.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")

## The trade a master holds. Forced-only on NpcIdentity -- never rolled by
## an ordinary villager, because a mage is not a trade a village produces;
## it is a trade that arrives.
const OCCUPATION := "mage"

## How deep a master of each rarity runs, in the ATOM CATALOG'S own tier
## band. Rarity is `rarity_tier.roll_tier`'s existing weighted roll (common
## 65% / uncommon 25% / rare 8% / legendary 2%) -- this table only says what
## that roll MEANS here, and adds no weight of its own. An archmage is
## therefore about one master in ten because the existing roll already said
## so, which is exactly the "rare teachers who can teach special rare
## spells" the design asks for.
const DEPTH_BY_RARITY := {
	"common": 1,
	"uncommon": 2,
	"rare": 3,
	"legendary": 3,
}

## What a master of each depth is called. Depth, not rarity: a rare and a
## legendary master both run to the bottom of their school, and a player
## meeting them cares about what they can teach, not which roll produced
## them.
const TITLE_BY_DEPTH := {
	1: "Adept",
	2: "Magister",
	3: "Archmage",
}

static var _rarity: RarityTier = null
static var _book = null


## The world's catalogue, for the readouts (title/display name) that have
## to agree with what this master will actually teach but are not handed a
## book by their caller. Cached, like SpellBook's own parse cache.
static func _shared_book():
	if _book == null:
		_book = load("res://src/gameplay/spell_book.gd").new()
	return _book


## Seeded pick, routed through a % 10000 reduction first -- the exact idiom
## NpcIdentity._index uses, and for the same reason (Godot's String hash can
## freeze `% count` into one bucket for salted strings sharing a suffix).
static func _index(seed_value: int, salt: String, count: int) -> int:
	if count <= 0:
		return 0
	return (absi(hash("%d_%s" % [seed_value, salt])) % 10000) % count


## The tradition this master spent their life in.
static func school_for(seed_value: int) -> String:
	return SpellSchools.SCHOOL_IDS[_index(seed_value, "mage_school", SpellSchools.SCHOOL_IDS.size())]


## Unchanged from the roll every gem and loot drop already uses.
static func rarity_for(seed_value: int) -> String:
	if _rarity == null:
		_rarity = RarityTier.new()
	return _rarity.roll_tier(seed_value)


## How deep into their own school this master runs, in the atom catalog's
## 1..3 tier band.
##
## Two floors, and the second one was measured rather than reasoned about
## (tools/probe_mage_guild.gd): an "Adept of Conjury" taught NOTHING,
## because conjury's only spell is depth 3 while a common master ran to
## depth 1 -- and a guild of three such masters taught one spell between
## them. A master who cannot pass on a single thing is a person standing in
## a room for no reason.
##
## The fix is not a patch but the honest reading: **you cannot hold a
## tradition whose shallowest work is beyond you.** If you are of a school
## at all, you can teach its entry; what rarity buys is running DEEPER than
## that, which stays rare in every school that has shallow work to be rare
## against. Nobody dabbles in calling things into being, so every conjurer
## is an archmage of it -- and finding a conjurer at all is then the gate,
## which is its own kind of rare.
##
## `book` is the catalogue the entry depth is read from, and it DEFAULTS to
## the world's own rather than to null on purpose: an earlier cut made it
## optional, so depth_for(seed) and depth_for(seed, book) could disagree
## about the same master while teaches() quietly used the second -- exactly
## the drift a readout and its mechanics must never have between them.
## Callers pass a book only to ask about a different catalogue.
static func depth_for(seed_value: int, book = null) -> int:
	var catalogue = book if book != null else _shared_book()
	var depth: int = DEPTH_BY_RARITY.get(rarity_for(seed_value), SpellSchools.MIN_DEPTH)
	var entry: int = SpellSchools.entry_depth_of(catalogue, school_for(seed_value))
	return clampi(maxi(depth, entry), SpellSchools.MIN_DEPTH, SpellSchools.MAX_DEPTH)


## The master as a real villager: name, genome, personality, appearance and
## a real allocation on the SAME skill web every other NPC and the player
## walk (see NpcSkillAllocation). Built fresh per call rather than cached,
## matching how every other caller in the project treats NpcIdentity.
static func identity_for(seed_value: int) -> NpcIdentity:
	return NpcIdentity.new(seed_value, OCCUPATION)


## "Archmage of Conjury" -- derived from school and depth, so a readout can
## never disagree with what the master will actually teach.
static func title_for(seed_value: int) -> String:
	var rank: String = TITLE_BY_DEPTH.get(depth_for(seed_value), TITLE_BY_DEPTH[SpellSchools.MIN_DEPTH])
	return "%s of %s" % [rank, school_for(seed_value).capitalize()]


## "Mirabel Ashdown, Archmage of Conjury".
static func display_name_for(seed_value: int) -> String:
	return "%s, %s" % [identity_for(seed_value).npc_name, title_for(seed_value)]


## Whether this master will teach `spell_id`. One rule, no list: every atom
## of the spell must be in their school, and the spell must not run deeper
## than they do.
##
## A spell whose atoms CROSS schools has no school at all
## (SpellSchools.school_of_spell returns ""), so no master teaches it --
## which is the intended cost of braiding two traditions, not an oversight.
static func teaches(book, spell_id: String, seed_value: int) -> bool:
	var school := SpellSchools.school_of_spell(book, spell_id)
	if school == "" or school != school_for(seed_value):
		return false
	var depth := SpellSchools.depth_of_spell(book, spell_id)
	return depth > 0 and depth <= depth_for(seed_value, book)


## Everything this master would teach, out of the world's whole catalogue,
## in a stable order.
static func teachable(book, seed_value: int) -> Array:
	if book == null:
		return []
	var offered: Array = []
	for spell_id in book.known_ids():
		if teaches(book, spell_id, seed_value):
			offered.append(spell_id)
	offered.sort()
	return offered
