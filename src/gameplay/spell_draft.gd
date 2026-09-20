extends RefCounted

## Composing a spell out of motes (docs/concept/spell_weaving.md).
##
## A draft is an ordered row of socketed atom ids plus a delivery method:
##
##   {"atoms": ["frost_damage", "freeze"], "delivery": "projectile"}
##
## and the hinge of the whole feature is source_for(): a draft compiles to
## DSL text in spell_book.gd's exact shape, which SpellParser parses and
## SpellExecutor casts. There is no second interpreter for player-made
## spells, no second cost model (cost_of is SpellCost's verdict on the same
## pipeline the parser emits) and no second rarity scale (rarity_of is
## RarityTier.tier_from_complexity, the derivation rarity_tier.gd already
## documents for spell gems). A composed spell is not LIKE a book spell;
## it is one.
##
## The second idea is that ORDER is load-bearing. Adjacent motes react, the
## reaction table is keyed on ORDERED pairs, and reversing a pair is a
## different result -- frost then fire raises steam, fire then frost is
## quenched and costs you effect. Reordering never changes the price
## (SpellCost's composition cost reads a multiset): order buys effect,
## never a discount.
##
## Pure: RefCounted, static functions, no scene tree, no world access, no
## file access, no singleton.

const SpellAtomCatalog = preload("res://src/gameplay/spell_atom_catalog.gd")
const SpellCost = preload("res://src/gameplay/spell_cost.gd")
const SpellSchools = preload("res://src/gameplay/spell_schools.gd")
const RarityTier = preload("res://src/gameplay/rarity_tier.gd")

## The four delivery methods the runtime actually has: SpellExecutor reads
## one off `on cast(ARG)` and SpellCost prices exactly these four. An
## unlisted string is REFUSED rather than passed through, because
## SpellCost.delivery_multiplier silently prices an unknown delivery as
## touch -- a spell that costs the wrong thing forever is worse than a
## refusal a player can read.
const DELIVERIES: Array[String] = ["self", "touch", "projectile", "area"]

## A summon needs physical space to resolve in (docs/concept/magic.md,
## constraint layer 2) -- you cannot throw one. The authored book agrees:
## its only summon, call_wisp, is self-delivered. Held against the book
## rather than asserted in the abstract by
## test_every_authored_book_spell_validates_as_a_draft.
const SUMMON_CATEGORY := "summon"
const SUMMON_DELIVERIES: Array[String] = ["self", "touch"]

## How many motes a draft may socket.
##
## This is SpellCost.SPAM_PENALTY's number, not this module's opinion. That
## penalty charges SPAM_PENALTY^k for the k-th repeat of a mote, and four
## sockets is exactly where repeating has cost MORE THAN DOUBLE face price
## (1.35^3 = 2.46; 1.35^2 = 1.82). A shorter row never makes spam hurt; a
## longer one only sells more of it, and widens the reaction bound below
## for nothing. Both sides of that inequality are pinned by
## test_the_socket_count_is_where_repetition_has_doubled_in_price, so
## retuning SPAM_PENALTY fails there rather than drifting quietly.
##
## It is also exactly enough room to reach the one rarity band no single
## mote can: four summon_wisp motes clear RarityTier's rare/legendary
## boundary and three do not.
const MAX_SOCKETS := 4

## Per-pair bounds on a reaction's effect multiplier. Every entry in the
## table sits inside them (test_every_pair_in_the_table_sits_inside_the_
## named_bounds), which is what lets the whole-draft bound below be a
## product of caps rather than a search over drafts.
const MAX_PAIR_MULTIPLIER := 1.5
const MIN_PAIR_MULTIPLIER := 0.7

const REACTION_CONFLAGRATION := "conflagration"
const REACTION_CONDUCTION := "conduction"
const REACTION_FLASH_FREEZE := "flash_freeze"
const REACTION_STEAM := "steam"
const REACTION_QUENCHED := "quenched"

## "earlier_atom>later_atom" -> what that ORDER produces. Ordered keys are
## the whole point: a smith's quench after a heat is not a heat after a
## quench, and `quenched` exists as a PENALTY entry rather than as a
## missing one because doing it backwards is worse than not doing it.
##
## The multiplier scales the spell's EFFECT at resolution, never its cost
## (spell_weaving.md pillar 6). Small on purpose: five pairs a player can
## actually learn beat twenty-five nobody discovers.
const _REACTIONS := {
	# Flame set to something already catching: the pair Magicka built a
	# game out of, and the strongest thing this table allows.
	"fire_damage>ignite":
	{
		"id": REACTION_CONFLAGRATION,
		"epithet": "Conflagration",
		"multiplier": MAX_PAIR_MULTIPLIER,
	},
	# Melt first, then put current through the melt. magic.md's own
	# example: "Shock on standing water conducts".
	"frost_damage>shock_damage":
	{
		"id": REACTION_CONDUCTION,
		"epithet": "Galvanic",
		"multiplier": 1.4,
	},
	# Chill a thing before you bind it and the binding takes at once.
	"frost_damage>freeze":
	{
		"id": REACTION_FLASH_FREEZE,
		"epithet": "Flashfrost",
		"multiplier": 1.35,
	},
	# Cold then heat: steam, magic.md's other named interaction.
	"frost_damage>fire_damage":
	{
		"id": REACTION_STEAM,
		"epithet": "Scalding",
		"multiplier": 1.25,
	},
	# Heat then cold: the fire goes out. The one entry below 1.0, and the
	# reason a socket row is a decision rather than a bag.
	"fire_damage>frost_damage":
	{
		"id": REACTION_QUENCHED,
		"epithet": "Quenched",
		"multiplier": MIN_PAIR_MULTIPLIER,
	},
}

## What a composed spell is called: "<epithet> <noun>". The epithet comes
## from the strongest reaction the ORDER produced, or from the first mote's
## tradition when the order produced none -- so a name changes when the
## order changes, which is how a hotbar can tell two drafts of the same
## motes apart. The noun comes from the last mote's category, because the
## last thing in a pipeline is what the spell leaves behind.
##
## One word per school and one per category, swept exhaustively by
## test_every_mote_in_the_catalog_can_name_a_spell so a new school or
## category fails there rather than shipping a spell called " Bolt".
const _SCHOOL_EPITHETS := {
	"pyromancy": "Cinder",
	"cryomancy": "Rime",
	"galvanism": "Arc",
	"venefice": "Verdigris",
	"mending": "Mercy",
	"kinetics": "Heavy",
	"wayfaring": "Far",
	"mentalism": "Whisper",
	"vivimancy": "Quickening",
	"conjury": "Summoner's",
}

const _CATEGORY_NOUNS := {
	"damage": "Bolt",
	"heal": "Balm",
	"control": "Bind",
	"movement": "Shove",
	"defense": "Ward",
	"summon": "Call",
	"utility": "Sight",
	"biological": "Graft",
	"perceptual": "Glimmer",
	"spatial": "Step",
}

## Shown for a draft that cannot be named -- an empty row, or one holding a
## mote no catalog knows. A socket screen still has to draw those, and an
## empty title bar reads as a bug rather than as a refusal.
const FALLBACK_NAME := "Unwoven Draft"

const REFUSAL_EMPTY_DRAFT := "empty_draft"
const REFUSAL_UNKNOWN_ATOM := "unknown_atom"
const REFUSAL_TOO_MANY_SOCKETS := "too_many_sockets"
const REFUSAL_UNKNOWN_DELIVERY := "unknown_delivery"
const REFUSAL_DELIVERY_REJECTS_ATOM := "delivery_rejects_atom"

## Built once for the whole game rather than once per call -- the same
## static-cache convention SpellSchools and SpellBook already use.
static var _catalog: SpellAtomCatalog = null
static var _cost: SpellCost = null
static var _rarity: RarityTier = null


static func _atoms() -> SpellAtomCatalog:
	if _catalog == null:
		_catalog = SpellAtomCatalog.new()
	return _catalog


static func _prices() -> SpellCost:
	if _cost == null:
		_cost = SpellCost.new()
	return _cost


static func _bands() -> RarityTier:
	if _rarity == null:
		_rarity = RarityTier.new()
	return _rarity


## The draft shape, in one place, so no caller has to remember the keys.
static func make(atom_ids: Array, delivery: String) -> Dictionary:
	return {"atoms": atom_ids.duplicate(), "delivery": delivery}


static func atoms_of(draft: Dictionary) -> Array:
	var atoms: Array = []
	for atom_id in draft.get("atoms", []):
		atoms.append(String(atom_id))
	return atoms


static func delivery_of(draft: Dictionary) -> String:
	return String(draft.get("delivery", "touch"))


# --- the compile ------------------------------------------------------------


## The atom list in the AST's own shape -- [{atom, params}] -- so the cost
## model prices EXACTLY what the parser would emit from source_for(). Each
## mote is written at its catalog reference magnitude/duration, which is
## also the value spell_cost.gd assumes when a parameter is absent: a mote
## casts at its own reference strength, and per-atom tuning is a later
## surface that will ride this same function.
static func pipeline_of(draft: Dictionary) -> Array:
	var pipeline: Array = []
	for atom_id in atoms_of(draft):
		pipeline.append({"atom": atom_id, "params": _reference_params(atom_id)})
	return pipeline


static func _reference_params(atom_id: String) -> Dictionary:
	var params: Dictionary = {}
	if not _atoms().has(atom_id):
		return params
	if _atoms().scales_with_magnitude(atom_id):
		params["magnitude"] = _atoms().mag_ref(atom_id)
	if _atoms().scales_with_duration(atom_id):
		params["duration"] = _atoms().dur_ref(atom_id)
	return params


## Whole numbers are written as whole numbers ("6", not "6.0") so composed
## source reads exactly like the authored entries in spell_book.gd.
static func _number_text(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return String.num(value, 2)


static func _step_text(atom_id: String) -> String:
	var params: Dictionary = _reference_params(atom_id)
	if params.is_empty():
		return atom_id
	var parts: Array = []
	# Magnitude before duration, the order spell_book.gd's own two-parameter
	# entry (warding_skin) writes them in.
	if params.has("magnitude"):
		parts.append("magnitude: %s" % _number_text(float(params["magnitude"])))
	if params.has("duration"):
		parts.append("duration: %s" % _number_text(float(params["duration"])))
	return "%s(%s)" % [atom_id, ", ".join(parts)]


## The player's composition as real DSL text, in spell_book.gd's exact
## format:
##
##   spell "Rime Bind" { on cast(projectile) when wielder.mana >= @cost:
##     frost_damage(magnitude: 6) |> freeze(duration: 2) }
##
## The guard is the book's own `wielder.mana >= @cost` rather than a fixed
## number, so a composed spell is affordability-checked by the same rule
## every authored one is.
static func source_for(draft: Dictionary) -> String:
	var steps: Array = []
	for atom_id in atoms_of(draft):
		steps.append(_step_text(atom_id))
	return (
		'spell "%s" { on cast(%s) when wielder.mana >= @cost: %s }'
		% [name_for(draft), delivery_of(draft), " |> ".join(steps)]
	)


# --- price, and only SpellCost's -------------------------------------------


## What the caster actually spends. SpellCost's paid_mana on the same
## pipeline the parser would emit -- never a second price for the same
## spell.
static func cost_of(draft: Dictionary, governing_stat: float = 0.0) -> float:
	return _prices().paid_mana(pipeline_of(draft), delivery_of(draft), governing_stat)


## The derived power price, the term stats can never change. This is the
## number RarityTier.tier_from_complexity is documented to read.
static func complexity_of(draft: Dictionary) -> float:
	return _prices().derived_base(pipeline_of(draft), delivery_of(draft))


static func cast_time_of(draft: Dictionary, haste_stat: float = 0.0) -> float:
	return _prices().cast_time(pipeline_of(draft), delivery_of(draft), haste_stat)


## The draft's rarity band, derived from its complexity -- the same
## derivation rarity_tier.gd documents for spell gems, and the only way to
## reach `legendary`, which no single mote ever is (spell_mote.gd's
## rarity_of).
static func rarity_of(draft: Dictionary) -> String:
	return _bands().tier_from_complexity(complexity_of(draft))


# --- refusals, each of them a sentence -------------------------------------


static func _refusal(code: String, reason: String) -> Dictionary:
	return {"code": code, "reason": reason}


## {"ok": bool, "refusals": [{code, reason}]}. Every reason is a printable
## sentence naming the offender, because a bare `false` in a socket screen
## is a player wondering which of five things is wrong.
##
## Checks run in the order a player would fix them: the row itself, then
## its motes, then how it is thrown.
static func validate(draft: Dictionary) -> Dictionary:
	var refusals: Array = []
	var atoms := atoms_of(draft)
	var delivery := delivery_of(draft)
	if atoms.is_empty():
		refusals.append(
			_refusal(
				REFUSAL_EMPTY_DRAFT,
				"An empty draft is not a spell yet: socket at least one mote before weaving it."
			)
		)
	if atoms.size() > MAX_SOCKETS:
		refusals.append(
			_refusal(
				REFUSAL_TOO_MANY_SOCKETS,
				(
					"A weave holds %d motes at most, and this one socketed %d."
					% [MAX_SOCKETS, atoms.size()]
				)
			)
		)
	for atom_id in atoms:
		if not _atoms().has(atom_id):
			refusals.append(
				_refusal(
					REFUSAL_UNKNOWN_ATOM,
					"There is no mote called '%s' anywhere in this world." % atom_id
				)
			)
	if not DELIVERIES.has(delivery):
		refusals.append(
			_refusal(
				REFUSAL_UNKNOWN_DELIVERY,
				(
					"'%s' is not a way to deliver a spell; it must be %s."
					% [delivery, " or ".join(DELIVERIES)]
				)
			)
		)
	else:
		for atom_id in atoms:
			if _atoms().has(atom_id) and _atoms().category(atom_id) == SUMMON_CATEGORY:
				if not SUMMON_DELIVERIES.has(delivery):
					refusals.append(
						_refusal(
							REFUSAL_DELIVERY_REJECTS_ATOM,
							(
								"%s needs space at hand to resolve in and cannot be delivered by %s."
								% [_atoms_display(atom_id), delivery]
							)
						)
					)
	return {"ok": refusals.is_empty(), "refusals": refusals}


static func _atoms_display(atom_id: String) -> String:
	return atom_id.capitalize()


# --- order is the craft ----------------------------------------------------


## The reaction table as a list, for a codex screen and for the bounds
## sweep. Each entry carries the ordered pair it fires on.
static func reaction_pairs() -> Array:
	var pairs: Array = []
	for key in _REACTIONS:
		var entry: Dictionary = (_REACTIONS[key] as Dictionary).duplicate()
		entry["pair"] = String(key).split(">")
		pairs.append(entry)
	return pairs


## Every reaction the CURRENT ORDER produces, in socket order. Adjacent
## pairs only -- a mote between two others is a mote between them -- so
## swapping two motes visibly changes the answer.
static func reactions_of(draft: Dictionary) -> Array:
	var found: Array = []
	var atoms := atoms_of(draft)
	for i in range(atoms.size() - 1):
		var key := "%s>%s" % [atoms[i], atoms[i + 1]]
		if not _REACTIONS.has(key):
			continue
		var reaction: Dictionary = (_REACTIONS[key] as Dictionary).duplicate()
		reaction["socket"] = i
		reaction["between"] = [atoms[i], atoms[i + 1]]
		found.append(reaction)
	return found


## The product of every reaction the order produced -- what the resolution
## layer multiplies an atom's magnitude by. 1.0 for a row that reacts with
## nothing, and never above max_reaction_multiplier().
static func reaction_multiplier(draft: Dictionary) -> float:
	var total := 1.0
	for reaction in reactions_of(draft):
		total *= float(reaction["multiplier"])
	return total


## The ceiling, by CONSTRUCTION rather than by searching the space of
## drafts: a full row has MAX_SOCKETS - 1 adjacencies and every pair in the
## table is capped at MAX_PAIR_MULTIPLIER, so nothing can multiply past
## their product.
static func max_reaction_multiplier() -> float:
	return pow(MAX_PAIR_MULTIPLIER, MAX_SOCKETS - 1)


## The strongest reaction the order produced, or {} for a row that reacted
## with nothing. Strongest means largest multiplier, ties going to the
## earliest socket, so the name a draft wears is deterministic.
static func dominant_reaction(draft: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	for reaction in reactions_of(draft):
		if best.is_empty() or float(reaction["multiplier"]) > float(best["multiplier"]):
			best = reaction
	return best


## "<epithet> <noun>": the reaction's word if the order made one, else the
## first mote's tradition; the noun from the last mote's category. Two
## drafts holding the same motes in different orders therefore read
## differently in a hotbar, which is the point of ordering them at all.
static func name_for(draft: Dictionary) -> String:
	var atoms := atoms_of(draft)
	if atoms.is_empty():
		return FALLBACK_NAME
	var epithet := ""
	var reaction := dominant_reaction(draft)
	if not reaction.is_empty():
		epithet = String(reaction["epithet"])
	else:
		epithet = String(_SCHOOL_EPITHETS.get(SpellSchools.school_of(atoms[0]), ""))
	var noun := ""
	var last := String(atoms[atoms.size() - 1])
	if _atoms().has(last):
		noun = String(_CATEGORY_NOUNS.get(_atoms().category(last), ""))
	if epithet == "" or noun == "":
		return FALLBACK_NAME
	return "%s %s" % [epithet, noun]
