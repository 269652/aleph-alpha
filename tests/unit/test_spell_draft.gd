extends GutTest

## Red-first spec for composing a spell out of motes (docs/concept/
## spell_weaving.md). A draft is an ordered row of socketed atom ids plus a
## delivery method, and the whole feature stands on one hinge: the row has
## to become a REAL spell through the real pipeline, not through a second
## interpreter written for the crafting screen.
##
## So the load-bearing tests here are the round trips --
## SpellParser.parse(SpellDraft.source_for(draft)) must return a cast rule
## whose atoms, order and delivery are the draft's -- plus the sweep that
## rebuilds every authored SpellBook entry as a draft and requires this
## module's validation rules to accept content the world already ships.
##
## The other half is that ORDER is load-bearing: adjacent motes react,
## reversing a pair is a different reaction (or a penalty), and reordering
## must never change the price.

const SpellDraft = preload("res://src/gameplay/spell_draft.gd")
const SpellMote = preload("res://src/gameplay/spell_mote.gd")
const SpellParser = preload("res://src/gameplay/spell_parser.gd")
const SpellExecutor = preload("res://src/gameplay/spell_executor.gd")
const SpellCost = preload("res://src/gameplay/spell_cost.gd")
const SpellBook = preload("res://src/gameplay/spell_book.gd")
const SpellSchools = preload("res://src/gameplay/spell_schools.gd")
const SpellAtomCatalog = preload("res://src/gameplay/spell_atom_catalog.gd")
const RarityTier = preload("res://src/gameplay/rarity_tier.gd")

var parser: SpellParser
var executor: SpellExecutor
var cost: SpellCost
var book: SpellBook
var catalog: SpellAtomCatalog
var rarity: RarityTier


func before_each():
	parser = SpellParser.new()
	executor = SpellExecutor.new()
	cost = SpellCost.new()
	book = SpellBook.new()
	catalog = SpellAtomCatalog.new()
	rarity = RarityTier.new()


## The cast rule a draft's own source text parses to, asserting along the
## way that it parsed at all -- every round-trip test starts here.
func _rule_for(draft: Dictionary) -> Dictionary:
	var source: String = SpellDraft.source_for(draft)
	var result: Dictionary = parser.parse(source)
	assert_true(result["ok"], "a draft produced unparsable source: %s\n%s" % [result["errors"], source])
	if not result["ok"]:
		return {}
	var rule = executor.cast_rule(result["ast"])
	assert_not_null(rule, "a draft's spell has no cast rule:\n%s" % source)
	return rule if rule != null else {}


func _atoms_of_rule(rule: Dictionary) -> Array:
	var atoms: Array = []
	for step in rule.get("pipeline", []):
		atoms.append(String(step.get("atom", "")))
	return atoms


# -- the hinge: a draft is a real spell -------------------------------------


func test_a_draft_compiles_to_a_spell_the_real_parser_accepts():
	var draft: Dictionary = SpellDraft.make(["frost_damage", "freeze"], "projectile")
	var rule: Dictionary = _rule_for(draft)
	assert_eq(_atoms_of_rule(rule), ["frost_damage", "freeze"], "the socket row is the pipeline")
	assert_eq(executor.delivery_for(rule), "projectile", "delivery must survive the trip")


func test_socket_order_survives_the_round_trip():
	var forwards: Dictionary = SpellDraft.make(["fire_damage", "ignite"], "touch")
	var backwards: Dictionary = SpellDraft.make(["ignite", "fire_damage"], "touch")
	assert_eq(_atoms_of_rule(_rule_for(forwards)), ["fire_damage", "ignite"])
	assert_eq(_atoms_of_rule(_rule_for(backwards)), ["ignite", "fire_damage"])


func test_every_delivery_round_trips():
	for delivery in SpellDraft.DELIVERIES:
		var draft: Dictionary = SpellDraft.make(["minor_heal"], String(delivery))
		assert_eq(executor.delivery_for(_rule_for(draft)), String(delivery), "%s was lost" % delivery)


func test_the_source_wears_the_spell_books_own_shape():
	# Not "similar to" the book's format -- the same guard, the same block
	# kind, the same cast event, compared field by field against a real
	# authored entry.
	var draft: Dictionary = SpellDraft.make(["fire_damage", "ignite"], "projectile")
	var result: Dictionary = parser.parse(SpellDraft.source_for(draft))
	assert_true(result["ok"], "draft source did not parse")
	var ast: Dictionary = result["ast"]
	var authored = book.ast_for("cinder_lash")
	assert_not_null(authored, "the book entry this is measured against is gone")
	assert_eq(ast["kind"], authored["kind"], "a draft must be a 'spell' block like the book's")
	var mine: Dictionary = executor.cast_rule(ast)
	var theirs: Dictionary = executor.cast_rule(authored)
	assert_eq(mine["event"], theirs["event"])
	assert_eq(mine["guard"]["op"], theirs["guard"]["op"], "the book guards on mana >= @cost")
	assert_eq(String(mine["guard"]["lhs"]), String(theirs["guard"]["lhs"]))
	assert_eq(String(mine["guard"]["rhs"]), String(theirs["guard"]["rhs"]))
	assert_eq(String(ast["name"]), SpellDraft.name_for(draft), "the block is named for the draft")


func test_each_mote_is_emitted_at_its_catalog_reference_strength():
	# A mote casts at its own reference magnitude/duration -- the same value
	# spell_cost.gd assumes when a parameter is absent, so the written
	# source and the price can never disagree.
	var draft: Dictionary = SpellDraft.make(["fire_damage", "shield", "ignite"], "touch")
	var rule: Dictionary = _rule_for(draft)
	for step in rule["pipeline"]:
		var atom_id: String = String(step["atom"])
		var params: Dictionary = step["params"]
		if catalog.scales_with_magnitude(atom_id):
			assert_eq(
				float(params.get("magnitude", -1.0)),
				catalog.mag_ref(atom_id),
				"%s was written at the wrong magnitude" % atom_id
			)
		if catalog.scales_with_duration(atom_id):
			assert_eq(
				float(params.get("duration", -1.0)),
				catalog.dur_ref(atom_id),
				"%s was written at the wrong duration" % atom_id
			)


# -- one cost model, and it is SpellCost's ----------------------------------


func test_cost_is_spell_costs_verdict_on_the_parsed_pipeline():
	var draft: Dictionary = SpellDraft.make(["frost_damage", "freeze"], "area")
	var rule: Dictionary = _rule_for(draft)
	for stat in [0.0, 50.0]:
		assert_almost_eq(
			SpellDraft.cost_of(draft, float(stat)),
			cost.paid_mana(rule["pipeline"], "area", float(stat)),
			0.0001,
			"the draft priced itself differently from the spell it compiles to"
		)


func test_cast_time_is_spell_costs_too():
	var draft: Dictionary = SpellDraft.make(["summon_wisp"], "self")
	var rule: Dictionary = _rule_for(draft)
	assert_almost_eq(
		SpellDraft.cast_time_of(draft, 40.0), cost.cast_time(rule["pipeline"], "self", 40.0), 0.0001
	)


func test_complexity_and_rarity_are_the_shared_scales():
	var draft: Dictionary = SpellDraft.make(["fire_damage", "ignite"], "projectile")
	var rule: Dictionary = _rule_for(draft)
	assert_almost_eq(
		SpellDraft.complexity_of(draft), cost.derived_base(rule["pipeline"], "projectile"), 0.0001
	)
	assert_eq(
		SpellDraft.rarity_of(draft),
		rarity.tier_from_complexity(SpellDraft.complexity_of(draft)),
		"a draft's rarity must be RarityTier's, derived from its complexity"
	)


func test_an_empty_draft_costs_nothing():
	var draft: Dictionary = SpellDraft.make([], "self")
	assert_eq(SpellDraft.cost_of(draft, 0.0), 0.0)
	assert_eq(SpellDraft.complexity_of(draft), 0.0)


# -- how many sockets, and why exactly that many ----------------------------


func test_the_socket_count_is_where_repetition_has_doubled_in_price():
	# MAX_SOCKETS is SpellCost.SPAM_PENALTY's number, not this module's
	# opinion: the last socket is the first one where repeating a mote has
	# cost more than DOUBLE face price. Both sides are asserted, so
	# retuning SPAM_PENALTY fails here instead of quietly drifting.
	assert_gt(
		pow(SpellCost.SPAM_PENALTY, SpellDraft.MAX_SOCKETS - 1),
		2.0,
		"the last socket does not yet make spam hurt"
	)
	assert_lte(
		pow(SpellCost.SPAM_PENALTY, SpellDraft.MAX_SOCKETS - 2),
		2.0,
		"spam already hurt a socket earlier -- the row is longer than it needs to be"
	)


func test_a_full_draft_of_the_deepest_motes_reaches_legendary():
	# No single mote is ever legendary (test_spell_mote.gd). A full row of
	# the deepest one is -- and a row one shorter is not, which is what
	# makes "legendary is something you make" a fact rather than a slogan.
	var full: Array = []
	for i in range(SpellDraft.MAX_SOCKETS):
		full.append("summon_wisp")
	var short_row: Array = full.slice(0, SpellDraft.MAX_SOCKETS - 1)
	assert_eq(SpellDraft.rarity_of(SpellDraft.make(full, "touch")), "legendary")
	assert_ne(SpellDraft.rarity_of(SpellDraft.make(short_row, "touch")), "legendary")
	assert_ne(SpellMote.rarity_of("summon_wisp"), "legendary", "the mote itself must not be")


# -- refusals are sentences -------------------------------------------------


func _refusal_codes(draft: Dictionary) -> Array:
	var codes: Array = []
	var verdict: Dictionary = SpellDraft.validate(draft)
	for refusal in verdict["refusals"]:
		codes.append(String(refusal["code"]))
		var reason: String = String(refusal["reason"])
		assert_gt(reason.length(), 20, "'%s' is not a sentence" % reason)
		assert_true(reason.ends_with("."), "'%s' is not a sentence" % reason)
	return codes


func test_a_sound_draft_is_accepted_with_nothing_to_say():
	var verdict: Dictionary = SpellDraft.validate(SpellDraft.make(["fire_damage", "ignite"], "projectile"))
	assert_true(verdict["ok"], "a plain two-mote draft was refused: %s" % str(verdict["refusals"]))
	assert_eq(verdict["refusals"].size(), 0)


func test_an_empty_socket_row_is_refused_by_name():
	var draft: Dictionary = SpellDraft.make([], "self")
	assert_false(SpellDraft.validate(draft)["ok"])
	assert_true(_refusal_codes(draft).has(SpellDraft.REFUSAL_EMPTY_DRAFT))


func test_a_mote_that_is_not_an_atom_is_refused_and_named():
	var draft: Dictionary = SpellDraft.make(["fire_damage", "summon_dragon"], "touch")
	assert_true(_refusal_codes(draft).has(SpellDraft.REFUSAL_UNKNOWN_ATOM))
	var verdict: Dictionary = SpellDraft.validate(draft)
	assert_string_contains(String(verdict["refusals"][0]["reason"]), "summon_dragon")


func test_too_many_sockets_is_refused_and_says_how_many_there_are():
	var too_many: Array = []
	for i in range(SpellDraft.MAX_SOCKETS + 1):
		too_many.append("fire_damage")
	var draft: Dictionary = SpellDraft.make(too_many, "touch")
	assert_true(_refusal_codes(draft).has(SpellDraft.REFUSAL_TOO_MANY_SOCKETS))
	assert_string_contains(String(SpellDraft.validate(draft)["refusals"][0]["reason"]), str(SpellDraft.MAX_SOCKETS))


func test_a_row_of_exactly_max_sockets_is_accepted():
	# The boundary, both sides of it: MAX_SOCKETS is a limit, not an
	# off-by-one that quietly costs the player their last socket.
	var full: Array = []
	for i in range(SpellDraft.MAX_SOCKETS):
		full.append("fire_damage")
	assert_true(SpellDraft.validate(SpellDraft.make(full, "touch"))["ok"], "the last socket was refused")
	full.append("fire_damage")
	assert_false(SpellDraft.validate(SpellDraft.make(full, "touch"))["ok"], "one past the limit was allowed")


func test_anything_validate_accepts_compiles_to_source_the_parser_accepts():
	# The contract between the two halves of this module: a draft the
	# socket screen would let you weave must always produce text the real
	# parser reads. A refusal is the gate; unparsable source never is.
	var rows: Array = [
		["fire_damage"],
		["frost_damage", "freeze"],
		["shield", "illuminate"],
		["summon_wisp"],
		["fire_damage", "ignite", "fire_damage", "ignite"],
	]
	for row in rows:
		for delivery in SpellDraft.DELIVERIES:
			var draft: Dictionary = SpellDraft.make(row, String(delivery))
			if not SpellDraft.validate(draft)["ok"]:
				continue
			var result: Dictionary = parser.parse(SpellDraft.source_for(draft))
			assert_true(
				result["ok"],
				"an accepted draft produced unparsable source: %s" % SpellDraft.source_for(draft)
			)
			assert_eq(_atoms_of_rule(_rule_for(draft)), row, "the row changed on the way through")


func test_a_delivery_the_executor_does_not_know_is_refused_rather_than_mispriced():
	# SpellCost.delivery_multiplier silently prices an unknown delivery as
	# touch. A spell that costs the wrong thing forever is worse than a
	# refusal, so this must be caught here.
	assert_eq(cost.delivery_multiplier("hurled"), cost.delivery_multiplier("touch"), "the silent misprice this refusal exists for")
	var draft: Dictionary = SpellDraft.make(["fire_damage"], "hurled")
	assert_true(_refusal_codes(draft).has(SpellDraft.REFUSAL_UNKNOWN_DELIVERY))


func test_a_summon_cannot_be_thrown():
	# magic.md constraint layer 2: a summon needs physical space to resolve
	# in. Every authored summon in the book is self-delivered.
	assert_true(_refusal_codes(SpellDraft.make(["summon_wisp"], "projectile")).has(SpellDraft.REFUSAL_DELIVERY_REJECTS_ATOM))
	assert_true(_refusal_codes(SpellDraft.make(["summon_wisp"], "area")).has(SpellDraft.REFUSAL_DELIVERY_REJECTS_ATOM))
	assert_true(SpellDraft.validate(SpellDraft.make(["summon_wisp"], "self"))["ok"], "a summon at the caster is fine")


func test_every_authored_book_spell_validates_as_a_draft():
	# A composition rule that refuses content the world already ships is a
	# bug in the rule. Every entry in the authored book is rebuilt as a
	# draft -- its own atoms, its own delivery -- and must pass.
	for spell_id in book.known_ids():
		var ast = book.ast_for(spell_id)
		assert_not_null(ast, "%s does not parse" % spell_id)
		var rule = executor.cast_rule(ast)
		assert_not_null(rule, "%s has no cast rule" % spell_id)
		var draft: Dictionary = SpellDraft.make(
			SpellSchools.atoms_in_spell(book, spell_id), executor.delivery_for(rule)
		)
		var verdict: Dictionary = SpellDraft.validate(draft)
		assert_true(verdict["ok"], "the authored spell %s is not a legal draft: %s" % [spell_id, verdict["refusals"]])


# -- order is load-bearing --------------------------------------------------


func _reaction_ids(draft: Dictionary) -> Array:
	var ids: Array = []
	for reaction in SpellDraft.reactions_of(draft):
		ids.append(String(reaction["id"]))
	return ids


func test_fire_beside_ignite_is_a_conflagration():
	var ids: Array = _reaction_ids(SpellDraft.make(["fire_damage", "ignite"], "projectile"))
	assert_eq(ids, [SpellDraft.REACTION_CONFLAGRATION])
	assert_gt(SpellDraft.reaction_multiplier(SpellDraft.make(["fire_damage", "ignite"], "projectile")), 1.0)


func test_the_same_two_motes_reversed_are_a_different_reaction():
	# The heat-then-quench asymmetry every real craft has: cold then heat
	# raises steam, heat then cold snuffs the spell out.
	var steam: Dictionary = SpellDraft.make(["frost_damage", "fire_damage"], "projectile")
	var quench: Dictionary = SpellDraft.make(["fire_damage", "frost_damage"], "projectile")
	assert_eq(_reaction_ids(steam), [SpellDraft.REACTION_STEAM])
	assert_eq(_reaction_ids(quench), [SpellDraft.REACTION_QUENCHED])
	assert_gt(SpellDraft.reaction_multiplier(steam), 1.0, "steam should be worth making")
	assert_lt(SpellDraft.reaction_multiplier(quench), 1.0, "doing it backwards must cost you")


func test_reordering_changes_the_reaction_set_but_never_the_price():
	# Pillar 6: order buys effect, never a discount. If a clever order also
	# paid less, the cost model would be advisory.
	var one: Dictionary = SpellDraft.make(["fire_damage", "ignite"], "touch")
	var other: Dictionary = SpellDraft.make(["ignite", "fire_damage"], "touch")
	assert_ne(_reaction_ids(one), _reaction_ids(other), "swapping two motes changed nothing")
	assert_almost_eq(SpellDraft.cost_of(one, 0.0), SpellDraft.cost_of(other, 0.0), 0.0001)
	assert_almost_eq(SpellDraft.complexity_of(one), SpellDraft.complexity_of(other), 0.0001)


func test_reactions_are_adjacent_only():
	# A mote between them is a mote between them.
	var apart: Dictionary = SpellDraft.make(["fire_damage", "minor_heal", "ignite"], "touch")
	assert_eq(_reaction_ids(apart), [], "motes reacted across a socket")


func test_a_single_mote_and_an_empty_row_react_with_nothing():
	assert_eq(SpellDraft.reactions_of(SpellDraft.make(["fire_damage"], "touch")).size(), 0)
	assert_eq(SpellDraft.reaction_multiplier(SpellDraft.make([], "self")), 1.0)


func test_every_pair_in_the_table_sits_inside_the_named_bounds():
	var pairs: Array = SpellDraft.reaction_pairs()
	assert_gt(pairs.size(), 2, "a reaction table of two pairs is not a craft")
	for pair in pairs:
		var multiplier: float = float(pair["multiplier"])
		assert_lte(multiplier, SpellDraft.MAX_PAIR_MULTIPLIER, "%s exceeds the per-pair cap" % pair["id"])
		assert_gte(multiplier, SpellDraft.MIN_PAIR_MULTIPLIER, "%s sinks below the per-pair floor" % pair["id"])
		assert_ne(String(pair["epithet"]), "", "%s has no name to call a spell by" % pair["id"])


func test_the_whole_draft_bound_is_a_product_of_per_pair_caps():
	# By construction, never by searching the space: a full row has
	# MAX_SOCKETS - 1 adjacencies and each one is capped.
	assert_almost_eq(
		SpellDraft.max_reaction_multiplier(),
		pow(SpellDraft.MAX_PAIR_MULTIPLIER, SpellDraft.MAX_SOCKETS - 1),
		0.0001,
		"the bound is not the product of the per-pair caps"
	)


func test_no_full_row_can_pass_the_bound():
	var alternating: Dictionary = SpellDraft.make(
		["fire_damage", "ignite", "fire_damage", "ignite"], "projectile"
	)
	assert_eq(SpellDraft.reactions_of(alternating).size(), 2, "the reacting pairs are the adjacent ones")
	assert_lte(SpellDraft.reaction_multiplier(alternating), SpellDraft.max_reaction_multiplier())


# -- a composed spell has a name you recognise ------------------------------


func test_a_name_is_deterministic_and_reads_as_a_spell():
	# A row that reacts with nothing wears its first mote's TRADITION, so
	# this pair is deliberately one the reaction table has no entry for.
	var draft: Dictionary = SpellDraft.make(["frost_damage", "slow"], "projectile")
	var name: String = SpellDraft.name_for(draft)
	assert_eq(name, SpellDraft.name_for(draft), "two looks, two names")
	assert_eq(name.split(" ").size(), 2, "'%s' does not read as a spell name" % name)
	assert_eq(SpellDraft.reactions_of(draft).size(), 0, "this pair was meant to be inert")
	assert_string_contains(name, "Rime")


func test_the_name_changes_when_the_order_changes_the_reaction():
	var lit: Dictionary = SpellDraft.make(["fire_damage", "ignite"], "projectile")
	var unlit: Dictionary = SpellDraft.make(["ignite", "fire_damage"], "projectile")
	assert_ne(SpellDraft.name_for(lit), SpellDraft.name_for(unlit), "the order is invisible in the name")
	assert_string_contains(SpellDraft.name_for(lit), "Conflagration")


func test_every_mote_in_the_catalog_can_name_a_spell():
	# A new catalog category or a new school must fail HERE rather than
	# shipping a spell called " Bolt".
	for atom_id in catalog.known_ids():
		var name: String = SpellDraft.name_for(SpellDraft.make([atom_id], "touch"))
		var words: PackedStringArray = name.split(" ")
		assert_eq(words.size(), 2, "%s named a spell '%s'" % [atom_id, name])
		for word in words:
			assert_gt(String(word).length(), 1, "%s named a spell '%s'" % [atom_id, name])


func test_an_unnameable_draft_still_has_a_name():
	# Refused drafts are still shown in a socket screen; a nameless one
	# would render as an empty row.
	assert_ne(SpellDraft.name_for(SpellDraft.make([], "self")), "")
	assert_ne(SpellDraft.name_for(SpellDraft.make(["summon_dragon"], "self")), "")
