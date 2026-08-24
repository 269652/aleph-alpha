extends GutTest

## EventStore (see docs/emergence/00-emergence-architecture.md "Event
## sourcing"/"Simulation authority" and
## docs/emergence/07-implementation-roadmap.md Phase 1).
##
## The authoritative append-only log of the world's causal event graph. Pure
## and engine-free -- FileAccess lives in EventStorePersistence, not here (see
## test_event_store_persistence.gd), matching this project's
## pure-module/engine-glue split.

const Event = preload("res://src/emergence/event.gd")
const EventStore = preload("res://src/emergence/event_store.gd")

var store: EventStore


func before_each():
	store = EventStore.new()


func _event(type: String = "test_event", tick: float = 0.0) -> Event:
	return Event.new(type, tick)


# -- appending and ids --------------------------------------------------------

func test_append_assigns_an_id():
	var id: String = store.append(_event())
	assert_ne(id, "")


## Deterministic and sortable, so a developer reading a log can tell at a
## glance which event came first and what kind it was.
func test_ids_are_deterministic_ordinal_and_type():
	var first: String = store.append(_event("settlement_founded"))
	var second: String = store.append(_event("npc_settled"))
	assert_eq(first, "evt_0_settlement_founded")
	assert_eq(second, "evt_1_npc_settled")


func test_get_event_returns_the_appended_event():
	var id: String = store.append(_event("settlement_founded", 12.0))
	var fetched = store.get_event(id)
	assert_eq(fetched.type, "settlement_founded")
	assert_eq(fetched.tick, 12.0)


func test_get_event_returns_null_for_an_unknown_id():
	assert_null(store.get_event("evt_999_nothing"))


func test_size_counts_appended_events():
	assert_eq(store.size(), 0)
	store.append(_event())
	store.append(_event())
	assert_eq(store.size(), 2)


func test_all_ids_are_in_insertion_order():
	var first: String = store.append(_event("a"))
	var second: String = store.append(_event("b"))
	var third: String = store.append(_event("c"))
	assert_eq(store.all_ids(), [first, second, third])


# -- entity history ------------------------------------------------------------

## An entity's history is every event it was an ACTOR or WITNESS in, in the
## order they happened -- this is what /history <entity_id> answers.
func test_events_for_entity_finds_events_where_it_is_an_actor():
	var event := _event("settlement_founded")
	event.actors = ["settlement:0_0"]
	store.append(event)
	var history := store.events_for_entity("settlement:0_0")
	assert_eq(history.size(), 1)
	assert_eq(history[0].type, "settlement_founded")


func test_events_for_entity_finds_events_where_it_is_a_witness():
	var event := _event("npc_settled")
	event.witnesses = ["settlement:0_0"]
	store.append(event)
	assert_eq(store.events_for_entity("settlement:0_0").size(), 1)


func test_events_for_entity_ignores_events_it_has_no_part_in():
	var event := _event("settlement_founded")
	event.actors = ["settlement:1_1"]
	store.append(event)
	assert_eq(store.events_for_entity("settlement:0_0"), [])


func test_events_for_entity_is_in_the_order_they_happened():
	var e1 := _event("first")
	e1.actors = ["npc:1"]
	var e2 := _event("second")
	e2.actors = ["npc:1"]
	store.append(e1)
	store.append(e2)
	var history := store.events_for_entity("npc:1")
	assert_eq(history[0].type, "first")
	assert_eq(history[1].type, "second")


# -- cause / consequence linking ----------------------------------------------

## The whole point: naming a cause when appending B automatically links A's
## consequences to include B. A caller cannot forget to wire the reverse
## direction -- exactly the class of bug ("two ends of one link, only one
## kept in sync") this project's own postmortems keep finding.
func test_appending_with_a_cause_links_the_reverse_consequence_automatically():
	var cause_id: String = store.append(_event("drought"))
	var effect_id: String = store.append(_event("crop_failure"))
	store.link_cause(effect_id, cause_id)

	assert_eq(store.get_event(cause_id).consequences, [effect_id])
	assert_eq(store.get_event(effect_id).causes, [cause_id])


func test_causes_of_returns_the_actual_cause_events():
	var cause_id: String = store.append(_event("drought"))
	var effect_id: String = store.append(_event("crop_failure"))
	store.link_cause(effect_id, cause_id)
	var causes := store.causes_of(effect_id)
	assert_eq(causes.size(), 1)
	assert_eq(causes[0].type, "drought")


func test_consequences_of_returns_the_actual_consequence_events():
	var cause_id: String = store.append(_event("drought"))
	var effect_id: String = store.append(_event("crop_failure"))
	store.link_cause(effect_id, cause_id)
	var consequences := store.consequences_of(cause_id)
	assert_eq(consequences.size(), 1)
	assert_eq(consequences[0].type, "crop_failure")


## The full causal chain, per the module's own worked example:
## Drought -> Crop failure -> Food shortage -> Price increase.
func test_cause_chain_walks_back_through_multiple_links():
	var drought: String = store.append(_event("drought"))
	var crop_failure: String = store.append(_event("crop_failure"))
	var shortage: String = store.append(_event("food_shortage"))
	store.link_cause(crop_failure, drought)
	store.link_cause(shortage, crop_failure)

	var chain := store.cause_chain(shortage)
	var chain_ids: Array = []
	for event in chain:
		chain_ids.append(event.id)
	assert_eq(chain_ids, [crop_failure, drought])


func test_cause_chain_of_a_rootless_event_is_empty():
	var id: String = store.append(_event("drought"))
	assert_eq(store.cause_chain(id), [])


## A malformed graph (a cycle) must not hang the debugger -- bounded by a
## visited set as well as depth.
func test_cause_chain_is_safe_against_a_cycle():
	var a: String = store.append(_event("a"))
	var b: String = store.append(_event("b"))
	store.link_cause(a, b)
	store.link_cause(b, a)
	var chain := store.cause_chain(a, 50)
	assert_lt(chain.size(), 10, "a cycle should not blow up the trace")


# -- querying -------------------------------------------------------------

func test_events_of_type_filters_by_type():
	store.append(_event("drought"))
	store.append(_event("crop_failure"))
	store.append(_event("drought"))
	assert_eq(store.events_of_type("drought").size(), 2)


func test_events_in_window_filters_by_tick_inclusive():
	store.append(_event("a", 10.0))
	store.append(_event("b", 20.0))
	store.append(_event("c", 30.0))
	var window := store.events_in_window(10.0, 20.0)
	assert_eq(window.size(), 2)


# -- persistence round trip (pure, no FileAccess) ------------------------------

func test_to_dicts_and_from_dicts_round_trip_a_whole_store():
	var cause_id: String = store.append(_event("drought", 1.0))
	var effect_id: String = store.append(_event("crop_failure", 2.0))
	store.link_cause(effect_id, cause_id)

	var restored := EventStore.from_dicts(store.to_dicts())

	assert_eq(restored.size(), 2)
	assert_eq(restored.all_ids(), store.all_ids())
	assert_eq(restored.get_event(cause_id).consequences, [effect_id])
	assert_eq(restored.get_event(effect_id).causes, [cause_id])


## The restored store must keep assigning fresh ids correctly -- resuming the
## ordinal counter from where it left off, not restarting it and colliding
## with events that already exist.
func test_a_restored_store_continues_the_id_sequence_without_colliding():
	store.append(_event("a"))
	store.append(_event("b"))
	var restored := EventStore.from_dicts(store.to_dicts())
	var new_id: String = restored.append(_event("c"))
	assert_eq(new_id, "evt_2_c")
	assert_eq(restored.get_event(new_id).type, "c")


# -- entity enumeration (for SimulationMetrics) -------------------------------

func test_all_entity_ids_lists_every_distinct_actor_and_witness():
	var e1 := _event("a")
	e1.actors = ["npc:1"]
	e1.witnesses = ["settlement:0_0"]
	var e2 := _event("b")
	e2.actors = ["npc:2"]
	store.append(e1)
	store.append(e2)
	var ids: Array[String] = store.all_entity_ids()
	assert_eq(ids.size(), 3)
	assert_true(ids.has("npc:1"))
	assert_true(ids.has("npc:2"))
	assert_true(ids.has("settlement:0_0"))


func test_all_entity_ids_lists_each_entity_once_even_with_many_events():
	var e1 := _event("a")
	e1.actors = ["npc:1"]
	var e2 := _event("b")
	e2.actors = ["npc:1"]
	store.append(e1)
	store.append(e2)
	assert_eq(store.all_entity_ids(), ["npc:1"])
