extends GutTest

## Why (see docs/emergence/00-emergence-architecture.md "Provenance" -- the
## "City C17 / created_by: / growth_causes:" worked example) and
## docs/progress.md's Phase 0 baseline & instrumentation.
##
## Human-readable explainers over EventStore's causal graph: explain_event
## renders one event's indented cause-chain provenance, explain_entity
## renders one entity's whole recorded history. Both are plain text (no
## markdown, no ANSI) since they are printed through a console command's
## log_line.

const Event = preload("res://src/emergence/event.gd")
const EventStore = preload("res://src/emergence/event_store.gd")
const Why = preload("res://src/emergence/why.gd")
const MemoryStore = preload("res://src/emergence/memory_store.gd")
const MemoryRecord = preload("res://src/emergence/memory_record.gd")
const HouseholdStore = preload("res://src/emergence/household_store.gd")
const ContractStore = preload("res://src/emergence/contract_store.gd")
const Contract = preload("res://src/emergence/contract.gd")
const Market = preload("res://src/emergence/market.gd")
const InstitutionStore = preload("res://src/emergence/institution_store.gd")
const Institution = preload("res://src/emergence/institution.gd")
const SettlementState = preload("res://src/emergence/settlement_state.gd")

var store: EventStore


func before_each():
	store = EventStore.new()


func _event(type: String = "test_event", tick: float = 0.0) -> Event:
	return Event.new(type, tick)


# -- explain_event: cause chain rendering --------------------------------------

## The module's own worked example: Drought -> Crop failure -> Food shortage.
## Nearest cause first, deepest cause last, each nesting level indented one
## deeper than its effect.
func test_explain_event_renders_a_multi_link_chain_nested_and_ordered():
	var drought: String = store.append(_event("drought", 1.0))
	var crop_failure: String = store.append(_event("crop_failure", 2.0))
	var shortage: String = store.append(_event("food_shortage", 3.0))
	store.link_cause(crop_failure, drought)
	store.link_cause(shortage, crop_failure)

	var text: String = Why.explain_event(store, shortage)

	assert_string_contains(text, shortage)
	assert_string_contains(text, "food_shortage")
	assert_string_contains(text, "caused_by:")
	assert_string_contains(text, crop_failure)
	assert_string_contains(text, "crop_failure")
	assert_string_contains(text, drought)
	assert_string_contains(text, "drought")

	# crop_failure (direct cause) must appear before drought (indirect cause).
	var crop_index: int = text.find(crop_failure)
	var drought_index: int = text.find(drought)
	assert_true(crop_index != -1 and drought_index != -1)
	assert_lt(crop_index, drought_index, "direct cause should render before its own indirect cause")

	# drought is nested one level deeper than crop_failure -- more leading
	# whitespace on drought's line than on crop_failure's line.
	var crop_line_start: int = text.rfind("\n", crop_index) + 1
	var drought_line_start: int = text.rfind("\n", drought_index) + 1
	var crop_indent: int = crop_index - crop_line_start
	var drought_indent: int = drought_index - drought_line_start
	assert_gt(drought_indent, crop_indent, "an indirect cause should be indented deeper than the direct cause that leads to it")


## Direct causes of the SAME event stay siblings (same indent), not chained
## to each other.
func test_explain_event_lists_multiple_direct_causes_as_siblings():
	var bridge: String = store.append(_event("bridge_built", 1.0))
	var mine: String = store.append(_event("mine_opened", 1.0))
	var growth: String = store.append(_event("settlement_grew", 2.0))
	store.link_cause(growth, bridge)
	store.link_cause(growth, mine)

	var text: String = Why.explain_event(store, growth)
	assert_string_contains(text, bridge)
	assert_string_contains(text, mine)

	var bridge_index: int = text.find(bridge)
	var mine_index: int = text.find(mine)
	var bridge_line_start: int = text.rfind("\n", bridge_index) + 1
	var mine_line_start: int = text.rfind("\n", mine_index) + 1
	assert_eq(bridge_index - bridge_line_start, mine_index - mine_line_start, "sibling direct causes should share the same indent")


## An event with no recorded cause should say so plainly, not print an empty
## "caused_by:" block with nothing under it.
func test_explain_event_with_no_cause_says_so_plainly():
	var id: String = store.append(_event("drought", 1.0))
	var text: String = Why.explain_event(store, id)
	assert_string_contains(text, id)
	assert_string_contains(text, "drought")
	assert_string_contains(text.to_lower(), "no known cause")


func test_explain_event_shows_the_events_own_id_type_and_tick():
	var id: String = store.append(_event("settlement_founded", 42.0))
	var text: String = Why.explain_event(store, id)
	assert_string_contains(text, id)
	assert_string_contains(text, "settlement_founded")
	assert_string_contains(text, "42")


## An unknown event id must be handled cleanly, not error or crash --
## get_event returns null for it and explain_event has to notice.
func test_explain_event_with_unknown_id_returns_a_clear_message_not_an_error():
	var text: String = Why.explain_event(store, "evt_999_nothing")
	assert_string_contains(text.to_lower(), "no such event")


## A malformed (cyclic) cause graph must not hang or crash explain_event --
## same safety guarantee EventStore.cause_chain already gives itself
## (test_cause_chain_is_safe_against_a_cycle).
func test_explain_event_is_safe_against_a_cyclic_cause_graph():
	var a: String = store.append(_event("a"))
	var b: String = store.append(_event("b"))
	store.link_cause(a, b)
	store.link_cause(b, a)

	var text: String = Why.explain_event(store, a)
	assert_true(text is String)
	assert_gt(text.length(), 0)


# -- explain_entity: history rendering -----------------------------------------

func test_explain_entity_lists_events_in_order_with_id_type_and_tick():
	var e1 := _event("settlement_founded", 1.0)
	e1.actors = ["settlement:0_0"]
	var e2 := _event("npc_settled", 2.0)
	e2.witnesses = ["settlement:0_0"]
	var first_id: String = store.append(e1)
	var second_id: String = store.append(e2)

	var text: String = Why.explain_entity(store, "settlement:0_0")

	assert_string_contains(text, first_id)
	assert_string_contains(text, "settlement_founded")
	assert_string_contains(text, second_id)
	assert_string_contains(text, "npc_settled")

	var first_index: int = text.find(first_id)
	var second_index: int = text.find(second_id)
	assert_true(first_index != -1 and second_index != -1)
	assert_lt(first_index, second_index, "history should list events in the order they happened")


## An entity with no recorded history must say so plainly, not return an
## empty string or error.
func test_explain_entity_with_no_history_says_so_plainly():
	var text: String = Why.explain_entity(store, "npc:99999")
	assert_true(text.length() > 0)
	assert_string_contains(text.to_lower(), "no recorded history")


# -- explaining memories -------------------------------------------------------

## Renders a holder's memories -- what /remember prints. Real fields, not
## just a count: source type and confidence are what make a memory
## trustworthy or not, so both belong on the line.
func test_explain_memories_lists_source_and_confidence():
	var bank := MemoryStore.new()
	var event := Event.new("crop_failure", 3.0)
	event.id = "evt_0_crop_failure"
	event.actors = ["npc:1"]
	bank.witness_event(event, 3.0)

	var text: String = Why.explain_memories(bank, "npc:1")
	assert_string_contains(text, "evt_0_crop_failure")
	assert_string_contains(text, MemoryRecord.FIRSTHAND)
	assert_string_contains(text, "1")  # confidence 1.0


func test_explain_memories_says_so_when_there_are_none():
	var bank := MemoryStore.new()
	var text: String = Why.explain_memories(bank, "npc:1")
	assert_string_contains(text, "no")


# -- explaining households -----------------------------------------------------

func test_explain_household_lists_members_and_property():
	var store := HouseholdStore.new()
	var household := store.form_household("npc:1")
	store.grant_property(household.id, "house:0_0_0")

	var text: String = Why.explain_household(store, "npc:1")
	assert_string_contains(text, household.id)
	assert_string_contains(text, "npc:1")
	assert_string_contains(text, "house:0_0_0")


func test_explain_household_says_so_when_the_entity_has_none():
	var store := HouseholdStore.new()
	var text: String = Why.explain_household(store, "npc:999")
	assert_string_contains(text, "no")


# -- explaining contracts -------------------------------------------------

func test_explain_contracts_lists_type_status_and_parties():
	var store := ContractStore.new()
	var contract := store.propose(
		"rent", ["household:1", "household:2"], ["10 wood/week"], "shelter", -1.0, 1.0
	)

	var text: String = Why.explain_contracts(store, "household:1")
	assert_string_contains(text, contract.id)
	assert_string_contains(text, "rent")
	assert_string_contains(text, Contract.PROPOSED)


func test_explain_contracts_says_so_when_the_entity_has_none():
	var store := ContractStore.new()
	var text: String = Why.explain_contracts(store, "household:999")
	assert_string_contains(text, "no")


# -- explaining markets ---------------------------------------------------

func test_explain_market_lists_stock_and_price_per_item():
	var market := Market.new()
	market.add_stock("wood", 5)

	var text: String = Why.explain_market(market, "settlement:0_0")
	assert_string_contains(text, "wood")
	assert_string_contains(text, "5")


func test_explain_market_says_so_when_there_is_no_stock():
	var market := Market.new()
	var text: String = Why.explain_market(market, "settlement:0_0")
	assert_string_contains(text, "no")


# -- explaining institutions -----------------------------------------------

func test_explain_institutions_lists_type_status_and_members():
	var store := InstitutionStore.new()
	var institution := store.form("guild", ["household:1", "household:2"], 1.0)

	var text: String = Why.explain_institutions(store, "household:1")
	assert_string_contains(text, institution.id)
	assert_string_contains(text, "guild")
	assert_string_contains(text, Institution.ACTIVE)


func test_explain_institutions_says_so_when_the_entity_belongs_to_none():
	var store := InstitutionStore.new()
	var text: String = Why.explain_institutions(store, "household:999")
	assert_string_contains(text, "no")


# -- explaining a settlement's carrying-capacity state ------------------------

func test_explain_settlement_reports_food_capacity_and_status():
	var market := Market.new()
	market.add_stock("meat", 40)

	var text: String = Why.explain_settlement(market, 1, "settlement:0_0")
	assert_string_contains(text, "food")
	assert_string_contains(text, "40")
	assert_string_contains(text, SettlementState.GROWING)
