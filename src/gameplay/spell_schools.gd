extends RefCounted

## The traditions a mage master can be proficient in (docs/concept/
## mage_guild.md mechanism 1): a **partition** of spell_atom_catalog.gd.
##
## This exists because of that doc's pillar 2 -- who came to a guild decides
## what can be learned there. That only means anything if a master's
## proficiency is narrower than "magic". A school is the unit of narrowness.
##
## Named for what they DO rather than for the catalog's `category` field they
## mostly follow, because a school is a tradition a person spends a life in
## and `category` is a cost-model grouping. They are close but not the same:
## `slow` is control-category and cryomancy-school, because the tradition
## that teaches you to freeze a thing is the one that teaches you to slow it.
##
## **Exhaustive and disjoint, test-pinned both ways.** An atom in no school
## is a spell nobody in the world could ever teach, and an atom in two is a
## master claiming another's trade. tests/unit/test_spell_schools.gd will
## fail the moment a new atom is added to the catalog without a home here,
## which is the point: the catalog is where atoms get added, and this is
## what makes forgetting loud.

const SpellExecutor = preload("res://src/gameplay/spell_executor.gd")
const SpellAtomCatalog = preload("res://src/gameplay/spell_atom_catalog.gd")

## In a fixed order, so a roster, a readout or an offer list never reshuffles
## between two looks at it.
const SCHOOL_IDS: Array[String] = [
	"pyromancy",
	"cryomancy",
	"galvanism",
	"venefice",
	"mending",
	"kinetics",
	"wayfaring",
	"mentalism",
	"vivimancy",
	"conjury",
]

## school -> its atoms. Every atom in SpellAtomCatalog appears exactly once.
const _ATOMS_BY_SCHOOL := {
	# Fire, and what fire leaves behind.
	"pyromancy": ["fire_damage", "ignite"],
	# Cold, and what cold does to a body before it kills it.
	"cryomancy": ["frost_damage", "freeze", "slow"],
	# The spark: the bolt and the lamp are one trade.
	"galvanism": ["shock_damage", "illuminate"],
	# Poisons and rot -- the slow trades.
	"venefice": ["poison_damage", "blight"],
	# Keeping a body whole, whether by closing it or by covering it.
	"mending": ["minor_heal", "major_heal", "shield"],
	# Force on a body: shove it, draw it, pin it, make it heavy.
	"kinetics": ["push", "pull", "root", "gravity_shift"],
	# Going, and seeing, at a distance.
	"wayfaring": ["teleport", "portal", "reveal"],
	# Minds rather than bodies.
	"mentalism": ["calm", "fear"],
	# Life itself, which is its own trade and a feared one.
	"vivimancy": ["accelerate_growth", "induce_mutation", "suppress_mutation"],
	# Calling a thing into being.
	"conjury": ["summon_wisp"],
}

## The depth band a master's proficiency runs in. Deliberately the ATOM
## CATALOG'S OWN 1..3 tier band rather than a second scale of this file's
## own invention -- test-pinned against the live catalog, so a catalog that
## grew a tier 4 would fail here rather than silently making the deepest
## atoms unteachable by anyone.
const MIN_DEPTH := 1
const MAX_DEPTH := 3

## Lazily built reverse index (atom_id -> school). Static so the walk over
## the table happens once for the whole game, not once per lookup -- same
## static-cache convention as SpellBook._cache.
static var _school_by_atom: Dictionary = {}
static var _executor: SpellExecutor = null
static var _catalog: SpellAtomCatalog = null


static func atoms_of(school: String) -> Array:
	return _ATOMS_BY_SCHOOL.get(school, []).duplicate()


## The school this atom belongs to, or "" for an atom no school claims
## (which the tests make impossible for any real atom, so in practice this
## means "not an atom at all").
static func school_of(atom_id: String) -> String:
	if _school_by_atom.is_empty():
		for school in SCHOOL_IDS:
			for known_atom in _ATOMS_BY_SCHOOL.get(school, []):
				_school_by_atom[known_atom] = school
	return _school_by_atom.get(atom_id, "")


## The atom ids a spell's cast pipeline actually calls, in pipeline order.
## [] for anything the book cannot produce a castable rule for.
static func atoms_in_spell(book, spell_id: String) -> Array:
	if book == null or not book.has(spell_id):
		return []
	var ast = book.ast_for(spell_id)
	if ast == null:
		return []
	if _executor == null:
		_executor = SpellExecutor.new()
	var rule = _executor.cast_rule(ast)
	if rule == null:
		return []
	var atoms: Array = []
	for step in rule.get("pipeline", []):
		atoms.append(String(step.get("atom", "")))
	return atoms


## The ONE school a spell belongs to, or "" when its atoms cross schools.
##
## A cross-school spell is a real and interesting category rather than an
## error -- there is simply no single master who can teach it, which is
## exactly what a spell braiding two traditions should cost. The authored
## book is held to containing none (see the tests), because an unteachable
## spell sitting quietly in the catalogue is a hole nobody would notice.
static func school_of_spell(book, spell_id: String) -> String:
	var atoms := atoms_in_spell(book, spell_id)
	if atoms.is_empty():
		return ""
	var school := school_of(atoms[0])
	for atom_id in atoms:
		if school_of(atom_id) != school:
			return ""
	return school


## How deep a spell runs: the tier of its DEEPEST atom. A spell is exactly
## as hard to teach as its hardest verb -- one tier-3 atom in an otherwise
## tier-1 pipeline still needs an archmage. 0 for an unknown spell.
static func depth_of_spell(book, spell_id: String) -> int:
	var atoms := atoms_in_spell(book, spell_id)
	if atoms.is_empty():
		return 0
	if _catalog == null:
		_catalog = SpellAtomCatalog.new()
	var deepest := 0
	for atom_id in atoms:
		if _catalog.has(atom_id):
			deepest = maxi(deepest, _catalog.tier(atom_id))
	return deepest
