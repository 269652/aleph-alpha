extends RefCounted

## Human-readable explainers over EventStore's causal graph (see
## docs/emergence/00-emergence-architecture.md "Provenance" -- this is the
## same indented shape as that doc's own "City C17 / created_by: /
## growth_causes:" worked example, adapted to what EventStore actually
## records).
##
## Two entry points: explain_event walks one event's cause chain, indented
## one level deeper per hop back through the graph; explain_entity lists one
## entity's whole recorded history in the order it happened. Both return
## plain text -- no markdown, no ANSI -- since a console command prints them
## straight through log_line. Pure and engine-free, matching EventStore's own
## FileAccess-free convention.

const Event = preload("res://src/emergence/event.gd")
const EventStore = preload("res://src/emergence/event_store.gd")
const MemoryStore = preload("res://src/emergence/memory_store.gd")
const MemoryRecord = preload("res://src/emergence/memory_record.gd")
const HouseholdStore = preload("res://src/emergence/household_store.gd")
const ContractStore = preload("res://src/emergence/contract_store.gd")
const Contract = preload("res://src/emergence/contract.gd")
const Market = preload("res://src/emergence/market.gd")
const InstitutionStore = preload("res://src/emergence/institution_store.gd")
const Institution = preload("res://src/emergence/institution.gd")
const SettlementState = preload("res://src/emergence/settlement_state.gd")
const SettlementTier = preload("res://src/emergence/settlement_tier.gd")
const WorldBossStore = preload("res://src/emergence/world_boss_store.gd")
const WorldBoss = preload("res://src/emergence/world_boss.gd")
const Governance = preload("res://src/emergence/governance.gd")

const _INDENT := "  "
## Same default as EventStore.cause_chain -- a belt-and-suspenders cap on top
## of the visited set below, so a pathologically long (but acyclic) chain
## still can't grow the recursion or the printed trace without bound.
const _MAX_DEPTH := 16


## Renders one event's provenance trace: its own id/type/tick on the first
## line, then a "caused_by:" block of its DIRECT causes, each recursively
## expanded one indent level deeper for THAT cause's own causes, and so on up
## the chain. An event with no known cause says so plainly instead of
## printing an empty block; an unknown event id gets a short message instead
## of erroring.
##
## Recursion is bounded by a visited set (not just a depth cap) so a cyclic
## cause graph -- a malformed but possible state, same as
## EventStore.cause_chain guards against -- still returns promptly instead of
## looping forever.
static func explain_event(store: EventStore, event_id: String) -> String:
	var event: Event = store.get_event(event_id)
	if event == null:
		return "no such event: %s" % event_id

	var lines: Array[String] = [_event_line(event)]
	lines.append(_INDENT + "caused_by:")
	var visited := {event_id: true}
	_append_causes(store, event, 2, visited, lines)
	return "\n".join(lines)


## Appends `event`'s direct causes at `depth` indent levels, then recurses
## into each cause's own direct causes at depth+1 -- the "nearest cause
## first, deepest cause last" order EventStore.cause_chain documents, but
## rendered as nested indentation rather than a flat list so a reader can see
## WHICH cause led to which. A cause with no further causes of its own prints
## its own "(no known cause)" leaf rather than silently stopping, so every
## branch of the trace visibly terminates.
##
## `visited` is shared across the whole recursion (not reset per branch) so a
## cycle anywhere in the graph is cut the moment it would revisit an event --
## the same safety EventStore.cause_chain gives itself with its own visited
## set -- and `depth` is capped at _MAX_DEPTH as a second, independent bound.
static func _append_causes(store: EventStore, event: Event, depth: int, visited: Dictionary, lines: Array[String]) -> void:
	if depth > _MAX_DEPTH:
		return
	var causes: Array[Event] = store.causes_of(event.id)
	if causes.is_empty():
		lines.append(_INDENT.repeat(depth) + "(no known cause)")
		return
	for cause in causes:
		if visited.has(cause.id):
			lines.append(_INDENT.repeat(depth) + _event_line(cause) + " (already shown above)")
			continue
		visited[cause.id] = true
		lines.append(_INDENT.repeat(depth) + _event_line(cause))
		_append_causes(store, cause, depth + 1, visited, lines)


## One event summarized as "<id> (<type> @ tick <tick>)" -- used both for the
## explained event's own header line and for each cause line underneath it.
static func _event_line(event: Event) -> String:
	return "%s (%s @ tick %s)" % [event.id, event.type, event.tick]


## Renders one entity's whole recorded history: one line per event it was an
## actor or witness in (store.events_for_entity), in the order it happened.
## An entity nothing has ever recorded says so plainly instead of returning
## an empty string.
static func explain_entity(store: EventStore, entity_id: String) -> String:
	var events: Array[Event] = store.events_for_entity(entity_id)
	if events.is_empty():
		return "%s: no recorded history" % entity_id

	var lines: Array[String] = ["%s:" % entity_id]
	for event in events:
		lines.append(_INDENT + _event_line(event))
	return "\n".join(lines)


## Renders one entity's whole set of MEMORIES (see MemoryRecord) -- what
## /remember prints. Distinct from explain_entity: history is the
## authoritative record of what an entity was part of, memory is that
## entity's own possibly-wrong recollection, so source type and confidence
## are what actually matters on each line, not just which events.
static func explain_memories(store: MemoryStore, entity_id: String) -> String:
	var memories: Array[MemoryRecord] = store.memories_for(entity_id)
	if memories.is_empty():
		return "%s: no memories" % entity_id

	var lines: Array[String] = ["%s:" % entity_id]
	for memory in memories:
		lines.append(_INDENT + "%s (%s, confidence %s)" % [
			memory.event_id, memory.source_type, String.num(memory.confidence, 2)
		])
	return "\n".join(lines)


## Renders the household `entity_id` belongs to -- id, members, property.
## Looked up by MEMBER, not by household id directly, since a player is far
## more likely to know an NPC's own name/id than the household id it was
## derived from.
static func explain_household(store: HouseholdStore, entity_id: String) -> String:
	var household = store.household_for(entity_id)
	if household == null:
		return "%s: no household" % entity_id

	var lines: Array[String] = [
		"%s:" % household.id,
		_INDENT + "members: %s" % ", ".join(household.members),
	]
	if household.property.is_empty():
		lines.append(_INDENT + "property: (none)")
	else:
		lines.append(_INDENT + "property: %s" % ", ".join(household.property))
	return "\n".join(lines)


## Renders every contract `entity_id` is a party to -- id, type, status, and
## the other parties, so a player can see what an entity is bound by
## without cross-referencing a separate parties list by hand.
static func explain_contracts(store: ContractStore, entity_id: String) -> String:
	var contracts: Array[Contract] = store.contracts_for(entity_id)
	if contracts.is_empty():
		return "%s: no contracts" % entity_id

	var lines: Array[String] = ["%s:" % entity_id]
	for contract in contracts:
		lines.append(_INDENT + "%s (%s, %s) with %s" % [
			contract.id, contract.type, contract.status, ", ".join(contract.parties)
		])
	return "\n".join(lines)


## Renders one settlement's market -- stock and derived price per item it
## holds any of. `entity_id` is cosmetic (the header line only): the market
## itself carries no id of its own, MarketStore keys it by settlement.
static func explain_market(market: Market, entity_id: String) -> String:
	if market.stock.is_empty():
		return "%s: no stock" % entity_id

	var lines: Array[String] = ["%s:" % entity_id]
	var item_ids: Array = market.stock.keys()
	item_ids.sort()
	for item_id in item_ids:
		lines.append(_INDENT + "%s: %d (price %s)" % [
			item_id, market.stock_of(item_id), String.num(market.price_for(item_id), 2)
		])
	return "\n".join(lines)


## Renders every institution `entity_id` has ever belonged to, active or
## dissolved -- id, type, status, and fellow members.
static func explain_institutions(store: InstitutionStore, entity_id: String) -> String:
	var institutions: Array[Institution] = store.institutions_for(entity_id)
	if institutions.is_empty():
		return "%s: no institutions" % entity_id

	var lines: Array[String] = ["%s:" % entity_id]
	for institution in institutions:
		lines.append(_INDENT + "%s (%s, %s) with %s" % [
			institution.id, institution.type, institution.status, ", ".join(institution.members)
		])
	return "\n".join(lines)


## Renders one settlement's carrying-capacity state -- food stock, derived
## capacity, current household count, and the GROWING/STABLE/DECLINING
## classification those two numbers produce (see SettlementState). Takes
## the market and household count directly rather than the stores
## themselves, since the caller (a console command) already has to look
## the market up by settlement id anyway.
## `active_institutions`/`production_counts` are optional (default to "none
## yet") so every existing caller keeps working unchanged -- Emergence
## Phase 9's tier/specialization are additive, not a breaking change to
## explain_settlement's own established shape.
## `institution_type_counts` is optional (defaults to "no history yet") so
## every existing caller keeps working unchanged -- Emergence Phase 13's
## governance/legitimacy are additive, the same shape Phase 9's tier/
## specialization params already established.
static func explain_settlement(
	market,
	household_count: int,
	entity_id: String,
	active_institutions: int = 0,
	production_counts: Dictionary = {},
	institution_type_counts: Dictionary = {}
) -> String:
	var food := SettlementState.food_stock(market)
	var capacity := SettlementState.carrying_capacity(market)
	var status := SettlementState.status_for(household_count, capacity)
	var tier := SettlementTier.tier_for(household_count, active_institutions, production_counts.size())
	var governance_form := Governance.form_for(institution_type_counts)
	var legitimacy := Governance.legitimacy_for(status)
	var text := (
		"%s:\n%sfood: %d (capacity %d)\n%shouseholds: %d\n%sstatus: %s\n%stier: %s"
		+ "\n%sgovernance: %s\n%slegitimacy: %s"
	) % [
		entity_id, _INDENT, food, capacity, _INDENT, household_count, _INDENT, status, _INDENT, tier,
		_INDENT, governance_form, _INDENT, legitimacy
	]
	var specialization := SettlementTier.specialization_for(production_counts)
	if specialization != "":
		text += "\n%sspecialization: %s" % [_INDENT, specialization]
	return text


## Renders every promotion a real individual has ever had (active or
## defeated -- WorldBossStore.bosses_for keeps history the same way
## InstitutionStore.institutions_for does), most recent first is not
## required since a real individual is promoted at most once while active
## and defeats are terminal, so chronological order already reads clearly.
static func explain_world_boss(store: WorldBossStore, individual_id: String) -> String:
	var bosses: Array[WorldBoss] = store.bosses_for(individual_id)
	if bosses.is_empty():
		return "%s: no world-boss promotion" % individual_id

	var lines: Array[String] = ["%s:" % individual_id]
	for boss in bosses:
		lines.append(
			_INDENT
			+ "%s (%s, %s) score %.1f / threshold %.1f, %d phase(s)"
			% [boss.id, boss.species, boss.status, boss.score, boss.threshold, boss.phases.size()]
		)
	return "\n".join(lines)


## Renders a settlement's real, currently-discoverable production-shortfall
## quests (see Quest.production_shortfall_quests_for, Emergence Phase 12) --
## a plain list, not indexed by any id of its own, since a quest here is a
## live projection with no persistent identity to key on.
static func explain_quests(quests: Array) -> String:
	if quests.is_empty():
		return "no production-shortfall quests right now"

	var lines: Array[String] = []
	for quest in quests:
		var missing_parts: Array[String] = []
		for entry in quest["missing"]:
			missing_parts.append("%d %s" % [entry["need"], entry["item_id"]])
		lines.append(
			"%s needs %s for %s (%s)"
			% [quest["household_id"], ", ".join(missing_parts), quest["recipe_id"], quest["settlement_id"]]
		)
	return "\n".join(lines)
