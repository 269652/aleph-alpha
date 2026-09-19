extends RefCounted

## What a mage guild is FOR (docs/concept/magic.md, 2026-09-19 section).
##
## settlement_charter.gd already gates a `mage_guild` at CITY tier, so the
## way to one is through a village the player helped grow. That was only
## half a trade -- a gate with nothing behind it is a locked door in a
## field. This is the other half: behind the gate, a guild TEACHES.
##
## It is also the access layer magic.md's compilation gate was always going
## to need and which did not exist in code at all. Three facts had no home:
##
## 1. **A known-spell set distinct from the world's catalogue.** SpellBook.
##    has() conflates "this spell exists" with "you can cast it", so nothing
##    could ever GRANT a spell. Every access mechanism magic.md brainstormed
##    (scroll-learning, compiling, an NPC studying a traded scroll) is a
##    write to a per-caster set that nothing had.
## 2. **A gold-for-knowledge transaction.** Nothing in the game charged gold
##    for a permanent capability.
## 3. **A structure gate on magic.** Nothing checked where you were standing.
##
## Tuition is those three for the case where the AST is already authored
## (there is no spell-editor UI yet, so there is nothing to compile FROM --
## SpellBook says as much in its own header). When the editor lands,
## compiling reuses all three unchanged and adds only its own price curve.
##
## Pure: no scene tree, no world. The caller supplies "am I standing at a
## guild" (see Player._has_structure_near_player) and decides whether to
## adopt the known-spell list this hands back.

const SpellCost = preload("res://src/gameplay/spell_cost.gd")
const SpellExecutor = preload("res://src/gameplay/spell_executor.gd")
const RarityTier = preload("res://src/gameplay/rarity_tier.gd")
const Shop = preload("res://src/gameplay/shop.gd")

## What a caster knows at birth. Everything else in the catalogue is a
## purchase. This MUST contain whatever Player.DEFAULT_CAST_SPELL_ID binds
## the cast key to -- a character who cannot cast the spell the game binds
## to their own cast button is a bug, not a gate (pinned by
## test_the_starting_set_contains_whatever_the_cast_key_is_bound_to).
const STARTING_SPELL_IDS: Array[String] = ["fire_bolt"]

## The structure that has to be standing within reach, and the one
## settlement_charter.gd gates at CITY tier. Named here rather than inlined
## at the call site so a refusal can point at it by id.
const GUILD_BUILDING_ID := "mage_guild"

## The price anchor: the shop's own meal. A tuned gold-per-power constant
## would be an invented third price; a RATIO between two things the game
## already prices is not. Price a spell in bread and it stays honest when
## bread moves.
const MEAL_ITEM_ID := "cooked_meat"

## How many meals one point of derived spell power is worth. The one free
## parameter in this file, and it encodes a real design claim rather than a
## taste: **a spell is a permanent capability, so it sits in the weight
## class of a building blueprint** -- dearer than any tool or weapon on the
## merchant's shelf, never dearer than the dearest thing on it. That claim
## is asserted against the live Shop catalogue in
## tests/unit/test_spell_tuition.gd ("the anchor constant, pinned by the
## design claim it encodes"), which is what makes this number falsifiable
## instead of eyeballed: it admits roughly 10..20 and nothing outside.
const MEALS_PER_POWER_UNIT := 16.0

## Refusal reasons. The first is a caller error (you cannot price a spell
## the world does not have); the other three are the real player-facing
## ones, and each points somewhere: at the charter ladder, at the rest of
## the catalogue, at a sum of money.
const UNKNOWN_SPELL := "unknown_spell"
const NO_GUILD := "no_guild"
const ALREADY_KNOWN := "already_known"
const CANNOT_AFFORD := "cannot_afford"

var _cost := SpellCost.new()
var _executor := SpellExecutor.new()
var _rarity := RarityTier.new()


## Gold per point of spell power, read off the shop's live meal price rather
## than typed. Static so callers/UI can quote the anchor without holding an
## instance.
static func gold_per_power_unit() -> float:
	return MEALS_PER_POWER_UNIT * float(Shop.CATALOG.get(MEAL_ITEM_ID, 0))


## A spell's power: spell_cost.gd's own `derived_base` -- the SAME number
## that already prices every cast's mana, and the one magic.md's scrolls
## section already nominates for pricing a vessel. No second measure of "how
## big is this spell" is invented here. 0.0 for anything the book cannot
## produce a castable rule for.
func power_of(book, spell_id: String) -> float:
	if book == null or not book.has(spell_id):
		return 0.0
	var ast = book.ast_for(spell_id)
	if ast == null:
		return 0.0
	var rule = _executor.cast_rule(ast)
	if rule == null:
		return 0.0
	return _cost.derived_base(rule.get("pipeline", []), _executor.delivery_for(rule))


## The rarity band that power falls in, via the already-pure, already-tested
## mapping gem pricing uses (rarity_tier.tier_from_complexity) against the
## identical score.
func tier_of(book, spell_id: String) -> String:
	return _rarity.tier_from_complexity(power_of(book, spell_id))


## What a guild charges to teach `spell_id`: power x the meal anchor, kicked
## up a step where the power crosses into a rarer band. Linear in power, NOT
## exponential in LOC -- magic.md already ruled that the author's
## exponential compile cost is paid once and "never re-charged to learners",
## so billing a student the compile curve would charge one design twice.
## 0 for a spell the catalogue does not hold; never free for one it does.
func tuition_for(book, spell_id: String) -> int:
	var power := power_of(book, spell_id)
	if power <= 0.0:
		return 0
	var priced := power * gold_per_power_unit() * _rarity.stat_multiplier(tier_of(book, spell_id))
	return maxi(1, int(round(priced)))


## The catalogue minus what this caster already knows, in a stable order so
## a guild's offer list does not reshuffle between two looks at it.
func teachable(book, known_ids: Array) -> Array:
	if book == null:
		return []
	var offered: Array = []
	for spell_id in book.known_ids():
		if not known_ids.has(spell_id):
			offered.append(spell_id)
	offered.sort()
	return offered


## Why a guild will not teach this, or {} when it will -- the same shape
## settlement_charter.refusal_for established: empty means nothing is wrong,
## otherwise a dict naming the fact. A guild that answers "no" is useless; a
## guild that answers WHY is a quest hook, so the money case carries both
## the price and the shortfall ("come back with 40 more gold", never a bare
## no) and the standing case carries the building id to point at.
##
## Order matters and is part of the contract: a spell the world does not
## have cannot be priced at all, and standing in a field is the first thing
## wrong with the attempt, not the last.
func refusal_for(
	book, spell_id: String, known_ids: Array, gold: int, at_guild: bool
) -> Dictionary:
	if book == null or not book.has(spell_id):
		return {"spell_id": spell_id, "reason": UNKNOWN_SPELL}
	if not at_guild:
		return {"spell_id": spell_id, "reason": NO_GUILD, "building_id": GUILD_BUILDING_ID}
	if known_ids.has(spell_id):
		return {"spell_id": spell_id, "reason": ALREADY_KNOWN}
	var price := tuition_for(book, spell_id)
	if gold < price:
		return {
			"spell_id": spell_id,
			"reason": CANNOT_AFFORD,
			"tuition": price,
			"short": price - gold,
		}
	return {}


## Pays for and takes a lesson. Returns
## {ok, gold: what was actually charged, known: the caller's new list,
## refusal: why not}.
##
## Gold moves ONLY on a learn that lands -- the same conserving discipline
## village_estates.md's baskets and guild_relief.gd's chest hold themselves
## to. `known_ids` is never mutated: the caller decides whether to adopt the
## list this hands back, the same way EstateAscension hands back a verdict
## rather than moving a household itself.
func learn(book, spell_id: String, known_ids: Array, wallet, at_guild: bool) -> Dictionary:
	var gold: int = wallet.balance if wallet != null else 0
	var refusal := refusal_for(book, spell_id, known_ids, gold, at_guild)
	if not refusal.is_empty():
		return {"ok": false, "gold": 0, "known": known_ids.duplicate(), "refusal": refusal}
	var price := tuition_for(book, spell_id)
	# Belt and braces: refusal_for already cleared the price against the same
	# balance, so a refused spend here would mean the wallet moved under us.
	# Reported as the money refusal it is rather than silently teaching free.
	if not wallet.spend(price):
		return {
			"ok": false,
			"gold": 0,
			"known": known_ids.duplicate(),
			"refusal": {
				"spell_id": spell_id,
				"reason": CANNOT_AFFORD,
				"tuition": price,
				"short": maxi(0, price - gold),
			},
		}
	var known := known_ids.duplicate()
	known.append(spell_id)
	return {"ok": true, "gold": price, "known": known, "refusal": {}}
