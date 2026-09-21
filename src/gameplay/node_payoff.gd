extends RefCounted

## What a skill-web node actually DOES to you (docs/concept/skill_payoff.md).
##
## Measured before this module existed, against skill_web.gd and its two
## legacy tables: the web grants 26 distinct stat keys and the running game
## reads 5 of them. The other 21 are summed into `Player.skill_bonus`
## faithfully and read by nothing, and the tooltip shows all of them the same
## way -- a stat name and a number. The first point a character spends buys
## "+10 max_health", which is a sentence about an accumulator slot rather
## than about anything the player has watched happen.
##
## The rule here is one line: a node is rendered by calling the REAL consumer
## function twice -- once at the bonus the character already has, once at the
## bonus this node would give them -- and showing both. "+4 taming_affinity"
## becomes "escape chance 42% -> 36%" because `Taming.break_free_chance` was
## asked, not because a number was reworded. Where no consumer exists the row
## says `declared` and shows the raw totals: an invented effect would be a lie
## the player cannot check, and it would take the pressure off wiring the
## thing up for real.
##
## Pure: a RefCounted of static functions. No scene tree, no world, no file
## access, no singletons -- the shape spell_cost.gd, errand_delivery.gd and
## species_bite.gd already use. The character's own live numbers arrive as a
## plain `facts` Dictionary from whoever is drawing the tooltip; the wiring
## into SkillWebView is a separate change (see the doc's Status list).

const Butchering = preload("res://src/gameplay/butchering.gd")
const CraftingRecipeBook = preload("res://src/gameplay/crafting_recipe_book.gd")
const CreatureInfo = preload("res://src/world/creature_info.gd")
const MeleeAttack = preload("res://src/gameplay/melee_attack.gd")
const SpeciesBite = preload("res://src/gameplay/species_bite.gd")
const SpellExecutor = preload("res://src/gameplay/spell_executor.gd")
const Taming = preload("res://src/gameplay/taming.gd")

## The unit of a stat nothing reads yet. A row carrying this is the module
## refusing to make something up -- the view prints the stat's own name and
## says so plainly.
const UNIT_DECLARED := "declared"

## Which direction of `delta` is good news. Escape chance and mana cost fall;
## meat and bites-survived rise. The view needs to know before it picks a
## colour, and the consumer is the only thing that knows.
const BETTER_HIGHER := "higher"
const BETTER_LOWER := "lower"

## Every stat key this file can render through a real function, and the
## subset of those the LIVE game already feeds the web's bonus into.
##
## The two lists are identical again as of 2026-09-21, and that is the point:
## `spell_efficiency` spent a while in the first and not the second, because
## `SpellExecutor.cost_for(rule, governing_stat)` really took the stat and
## really discounted the cost while `Player`'s cast sites called
## `cost_for(rule)` and let the argument default to 0.0 -- a sentence that
## was true of the function and false of the game. Both cast sites pass it
## now, and `max_mana` (six nodes, more than any other key in the web)
## reached `_apply_skill_stat` in the same pass. test_node_payoff.gd reads
## scenes/player.gd and holds both lists to what that file actually does, so
## a stat cannot be listed as wired without the wiring.
const CONSUMER_STATS := [
	"max_health",
	"attack_damage",
	"meat_yield",
	"carpentry_level",
	"taming_affinity",
	"spell_efficiency",
	"max_mana",
]
const WIRED_STATS := [
	"max_health",
	"attack_damage",
	"meat_yield",
	"carpentry_level",
	"taming_affinity",
	"spell_efficiency",
	"max_mana",
]

## The audit these figures come from (docs/concept/skill_payoff.md,
## 2026-09-20, inert count corrected 2026-09-21 when `max_mana` gained a
## consumer):
## how many distinct stat keys the whole web grants, and how many of them
## nothing can render because nothing consumes them. Both are recomputed from
## the live SkillWeb by test_node_payoff.gd rather than trusted -- so adding a
## stat, or finally wiring one up, fails the suite until the number here (and
## the count in the doc that quotes it) is corrected.
const WEB_STAT_COUNT_AT_AUDIT := 26
const INERT_STAT_COUNT_AT_AUDIT := 19

## `scenes/player.gd`'s own `const UNARMED_DAMAGE := 5.0`, restated here for
## the reason sprint_cost.gd restates its tile size: a pure rule module must
## not preload a CharacterBody2D script. Pinned against the real one by test,
## and only ever a fallback -- the view passes the live value in `facts`.
const PLAYER_UNARMED_DAMAGE := 5.0

## The `condition` of an animal that is unhurt and has not yet fought the
## rope: `Taming.effective_condition(1.0, 0.0)`, which is the worst case a
## handler faces and therefore the honest one to quote before a catch. Not an
## invented 1.0 -- pinned against that function by test.
const FRESH_ANIMAL_CONDITION := 1.0

# -- relevance weights ---------------------------------------------------
#
# Two weights, and they define their own ceiling: LIVE + EVIDENCE == 1.0, so
# "a live stat this character has evidence for" IS a full-relevance node and
# no third constant exists to drift away from the other two.

## A stat some real function consumes is already worth noticing, whoever you
## are.
const LIVE_STAT_SCORE := 0.4

## ...and worth this much more again when the character owns the thing that
## reads it: a spell in the book, a companion on the rope, a weapon in hand.
## The larger of the two deliberately -- pillar 5 of the doc is that the same
## node is worth different amounts to two characters, and that only shows if
## evidence outweighs mere existence.
const EVIDENCE_SCORE := 0.6

## What a number nothing reads is worth to anybody: nothing. Pillar 1 stated
## as arithmetic. Any friendlier value here would sort inert nodes above live
## ones for a character with no evidence yet, which is precisely the tooltip
## this module exists to stop.
const INERT_STAT_SCORE := 0.0

## stat key -> the `build_facts` count that proves this character owns the
## thing that reads it. Every one is a number the view can read off real live
## state (SpellBook's known ids, the companion list, the equipped item, the
## recipe gate, damage actually taken) -- never anything invented here.
const EVIDENCE_FACTS := {
	"max_health": "damage_taken",
	"attack_damage": "weapon_count",
	"meat_yield": "carcasses_butchered",
	"carpentry_level": "locked_recipe_count",
	"taming_affinity": "companion_count",
	"spell_efficiency": "spell_count",
}


# -- the preview ---------------------------------------------------------

## One row per stat `node_stats` grants, each rendered by running its
## consumer twice.
##
## `node_stats` is the shape `SkillWeb.node_info` already emits --
## [{stat_name, bonus_amount}, ...] -- so a caller can pass a node's own stat
## and, for a DNA-flavoured node, whichever variant it is showing.
## `current_bonuses` is {stat_key: what the character already has}, i.e.
## `Player.skill_bonus(key)` per key: this module never accumulates anything
## of its own, for the same reason Player.skill_bonus doesn't.
## `consumers` is {stat_key: {label, unit, better, wired, evaluate: Callable}}
## -- `default_consumers` builds the real one.
##
## Two grants of the same key (a node whose variant names the stat it already
## grants) are summed into ONE row before evaluation, so a preview can never
## double-count a stat, and so the consumer is asked about the character's
## real resulting total rather than twice about halves of it.
static func preview_for(node_stats: Array, current_bonuses: Dictionary, consumers: Dictionary) -> Array:
	var rows: Array = []
	var granted: Dictionary = _summed_grants(node_stats)
	for stat_key in granted:
		var bonus: float = granted[stat_key]
		var current := float(current_bonuses.get(stat_key, 0.0))
		var consumer: Dictionary = consumers.get(stat_key, {})
		if not consumer.has("evaluate"):
			# Nothing reads this. The only honest before/after is the raw
			# total the web is summing, said in the stat's own name.
			rows.append({
				"stat": stat_key,
				"label": _humanize(stat_key),
				"before": current,
				"after": current + bonus,
				"delta": bonus,
				"unit": UNIT_DECLARED,
				"better": BETTER_HIGHER,
				"wired": false,
			})
			continue
		var evaluate: Callable = consumer["evaluate"]
		var before := float(evaluate.call(current))
		var after := float(evaluate.call(current + bonus))
		rows.append({
			"stat": stat_key,
			"label": String(consumer.get("label", _humanize(stat_key))),
			"before": before,
			"after": after,
			"delta": after - before,
			"unit": String(consumer.get("unit", "")),
			"better": String(consumer.get("better", BETTER_HIGHER)),
			"wired": bool(consumer.get("wired", false)),
		})
	return rows


## The stat keys among `node_stats` that nothing can render -- the honest
## measure of how much of the web is still inert. Defaults to CONSUMER_STATS
## as the yardstick so a caller can ask the question without first building a
## registry; pass a live registry to ask it of a particular character (whose
## missing facts may leave a consumer unregistered).
static func stats_without_consumers(node_stats: Array, consumers: Dictionary = {}) -> Array:
	var known: Array = CONSUMER_STATS if consumers.is_empty() else consumers.keys()
	var missing: Array = []
	for stat_key in _summed_grants(node_stats):
		if not known.has(stat_key):
			missing.append(stat_key)
	return missing


## How much this node matters to THIS character right now, in [0, 1].
##
## Per stat: INERT_STAT_SCORE for a stat with no consumer at all,
## LIVE_STAT_SCORE for one a real function consumes, plus EVIDENCE_SCORE when
## `build_facts` shows the character owns the thing that function serves (see
## EVIDENCE_FACTS). Summed across the node's stats and clamped, so a node
## granting two live evidenced stats is simply "as relevant as it gets"
## rather than twice as relevant as the ceiling.
##
## Deliberately coarse. It exists so a view can sort or highlight -- "these
## three reachable nodes would change something you are actually doing" -- not
## to rank two mage nodes against each other, which is a build decision and
## belongs to the player.
static func relevance_for(node_stats: Array, build_facts: Dictionary) -> float:
	var total := 0.0
	for stat_key in _summed_grants(node_stats):
		if not CONSUMER_STATS.has(stat_key):
			total += INERT_STAT_SCORE
			continue
		total += LIVE_STAT_SCORE
		var fact_key := String(EVIDENCE_FACTS.get(stat_key, ""))
		if fact_key != "" and float(build_facts.get(fact_key, 0.0)) > 0.0:
			total += EVIDENCE_SCORE
	return clampf(total, 0.0, 1.0)


# -- the registry of consumers that really exist today -------------------

## Every stat this codebase can honestly render, wrapped around the function
## that really computes it. Each entry was verified by reading the file it
## names; nothing is registered that the game does not already compute.
##
## `facts` carries the character's own live numbers. A consumer whose fact is
## genuinely missing -- a spell rule for a character with nothing prepared --
## is NOT registered rather than evaluated against a stand-in, so the row
## falls back to `declared` instead of quoting the cost of a spell that does
## not exist. Defaults are used only where a real, named number exists to
## default to (the reference species, Player's own unarmed damage, a fresh
## animal's condition, a reference-mass carcass).
static func default_consumers(facts: Dictionary) -> Dictionary:
	var consumers: Dictionary = {}
	var species := String(facts.get("threat_species", SpeciesBite.REFERENCE_SPECIES))

	# max_health -> how many bites from the thing in front of you it buys.
	# Player._apply_skill_stat really adds this to max_health; SpeciesBite
	# really decides what that species bites for (predator_profiles.md).
	# Health as "a longer bar" is the unreadable version of exactly this.
	var base_health := float(facts.get("base_max_health", SpeciesBite.PLAYER_REFERENCE_MAX_HEALTH))
	var bite := maxf(SpeciesBite.bite_damage_for(species), 0.001)
	consumers["max_health"] = {
		"label": "%s bites survived" % _humanize(species),
		"unit": "bites",
		"better": BETTER_HIGHER,
		"wired": true,
		"evaluate": func(bonus: float) -> float:
			return floorf((base_health + bonus) / bite),
	}

	# attack_damage -> swings to fell the same animal. MeleeAttack.attack_damage
	# is the real swing (weapon or bare hands); Player adds its class bonus and
	# its allocated _skill_attack_bonus on top at the call site, which is what
	# this reproduces. Rendered as SWINGS rather than as damage on purpose: the
	# damage number is the bonus restated, while the swing count is where the
	# threshold lives -- +2 can be worth a whole swing or nothing at all, and
	# that is the build knowledge a passive tree is supposed to teach.
	var melee := MeleeAttack.new()
	var weapon = facts.get("held_weapon", null)
	var unarmed := float(facts.get("unarmed_damage", PLAYER_UNARMED_DAMAGE))
	var class_bonus := float(facts.get("class_attack_bonus", 0.0))
	var target_health := float(facts.get(
		"threat_health", CreatureInfo.MAX_HEALTH_BY_SPECIES.get(species, 0.0)
	))
	if target_health > 0.0:
		consumers["attack_damage"] = {
			"label": "Swings to fell a %s" % species.replace("_", " "),
			"unit": "swings",
			"better": BETTER_LOWER,
			"wired": true,
			"evaluate": func(bonus: float) -> float:
				var damage := melee.attack_damage(weapon, unarmed) + class_bonus + bonus
				return ceilf(target_health / maxf(damage, 0.001)),
		}

	# meat_yield -> meat off one carcass. Butchering.meat_count is the exact
	# function Player._butcher_step hands skill_bonus("meat_yield") to.
	var mass_ratio := float(facts.get("carcass_mass_ratio", 1.0))
	consumers["meat_yield"] = {
		"label": "Meat from one carcass",
		"unit": "meat",
		"better": BETTER_HIGHER,
		"wired": true,
		"evaluate": func(bonus: float) -> float:
			return float(Butchering.meat_count(bonus, mass_ratio)),
	}

	# carpentry_level -> how many gated recipes the gate now lets through.
	# Player._meets_required_skill's rule exactly (a requirement naming this
	# stat, met when the allocated level reaches it), counted over the real
	# recipe book -- so the row says "two more recipes", which is a verb, and
	# not "carpentry level 2", which is a noun nobody can spend.
	var recipe_book := CraftingRecipeBook.new()
	var carpentry_gates: Array = []
	for recipe_id in recipe_book.recipe_ids():
		var requirement: Dictionary = recipe_book.recipe_required_skill(recipe_id)
		if not requirement.is_empty() and String(requirement.get("stat_name", "")) == "carpentry_level":
			carpentry_gates.append(float(requirement.get("level", 0.0)))
	if not carpentry_gates.is_empty():
		consumers["carpentry_level"] = {
			"label": "Carpentry recipes unlocked",
			"unit": "recipes",
			"better": BETTER_HIGHER,
			"wired": true,
			"evaluate": func(bonus: float) -> float:
				var unlocked := 0
				for level in carpentry_gates:
					if bonus >= level:
						unlocked += 1
				return float(unlocked),
		}

	# taming_affinity -> the chance the animal on your rope gets loose. The
	# one stat that has already made the journey from declared to read
	# (taming.md), and the model for every row above: the number the player
	# watched go the wrong way at a bad moment, quoted back at them.
	var condition := float(facts.get("restrained_condition", FRESH_ANIMAL_CONDITION))
	var is_predator := bool(facts.get("restrained_is_predator", false))
	var luck := float(facts.get("luck", 0.0))
	consumers["taming_affinity"] = {
		"label": "Escape chance on the rope",
		"unit": "chance",
		"better": BETTER_LOWER,
		"wired": true,
		"evaluate": func(bonus: float) -> float:
			return Taming.break_free_chance(condition, is_predator, bonus, luck),
	}

	# spell_efficiency -> what your prepared spell costs to cast.
	# SpellExecutor.cost_for really takes this stat and really discounts the
	# cost through SpellCost.efficiency, and Player's two cast sites pass it
	# now (2026-09-21) -- this entry spent a while marked `wired: false`
	# precisely because they did not, which is the most useful bug report
	# this module has filed.
	var spell_rule: Dictionary = facts.get("spell_rule", {})
	if not spell_rule.is_empty():
		var executor := SpellExecutor.new()
		var spell_name := String(facts.get("spell_name", "Your spell"))
		consumers["spell_efficiency"] = {
			"label": "%s mana cost" % spell_name,
			"unit": "mana",
			"better": BETTER_LOWER,
			"wired": true,
			"evaluate": func(bonus: float) -> float:
				return executor.cost_for(spell_rule, bonus),
		}

		# max_mana -> how many of that spell the pool now pays for. The
		# sentence a mage can check: "+10 max_mana" is an accumulator slot,
		# "Frost Lance casts: 3 -> 5" is the thing they watched happen.
		# Registered only alongside a real prepared spell, for the same
		# reason spell_efficiency is: the cost of a spell that does not
		# exist is not a number to quote.
		var base_mana := float(facts.get("base_max_mana", 0.0))
		var efficiency := float(facts.get("spell_efficiency", 0.0))
		var cost := maxf(executor.cost_for(spell_rule, efficiency), 0.001)
		consumers["max_mana"] = {
			"label": "%s casts from a full pool" % spell_name,
			"unit": "casts",
			"better": BETTER_HIGHER,
			"wired": true,
			"evaluate": func(bonus: float) -> float:
				return floorf((base_mana + bonus) / cost),
		}

	return consumers


# -- internals -----------------------------------------------------------

## {stat_key: summed bonus}, in the order the node declared them, so a row
## order is the node's own order and a repeated key is one entry.
static func _summed_grants(node_stats: Array) -> Dictionary:
	var granted: Dictionary = {}
	for entry in node_stats:
		var stat_key := String(entry.get("stat_name", ""))
		if stat_key == "":
			continue
		granted[stat_key] = float(granted.get(stat_key, 0.0)) + float(entry.get("bonus_amount", 0.0))
	return granted


## "trade_margin" -> "Trade Margin". The fallback label, and deliberately no
## prettier than that: a declared stat has no sentence, and dressing its key
## up as one would be the exact dishonesty this module is against.
static func _humanize(stat_key: String) -> String:
	return stat_key.capitalize()
