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


## Reported live: "the performance gets worse the longer you play."
## EarthChunkManager._known_settlement_ids() calls events_of_type
## every SETTLEMENT_STEP_INTERVAL for the rest of the session, and a naive
## implementation scans the WHOLE store -- every trade, crush, birth,
## market tick, memory exchange, every event of every kind ever recorded,
## not just settlement foundings -- so this one query gets slower with
## every unrelated thing that has ever happened, forever. Fixed with a
## type index (_by_type, the same "append indexes, read reads the index"
## shape _by_entity already uses for events_for_entity) so this scales
## with how many events of THIS type exist, not the store's total size.
## These pin the observable contract the index must preserve, not the
## complexity itself (GDScript/GUT has no reliable way to assert Big-O
## directly) -- the real before/after evidence is a live long-session
## --perf-report run, not a unit test.
func test_events_of_type_is_unaffected_by_unrelated_event_volume():
	for i in 200:
		store.append(_event("noise_%d" % (i % 11)))
	store.append(_event("drought"))
	for i in 200:
		store.append(_event("noise_%d" % (i % 11)))
	store.append(_event("drought"))
	assert_eq(store.events_of_type("drought").size(), 2)
	assert_eq(store.events_of_type("nonexistent_type"), [])


func test_events_of_type_preserves_insertion_order():
	var first := _event("drought", 1.0)
	var second := _event("drought", 2.0)
	store.append(_event("noise"))
	store.append(first)
	store.append(_event("noise"))
	store.append(second)
	var result := store.events_of_type("drought")
	assert_eq(result[0].tick, 1.0)
	assert_eq(result[1].tick, 2.0)


## The type index must be rebuilt on load, not just on live append -- a
## save restored mid-session and then queried (e.g. the very next
## step_settlements tick) must see every settlement founded before the
## save, not just ones founded after it.
func test_events_of_type_reflects_events_restored_via_from_dicts():
	store.append(_event("drought"))
	store.append(_event("crop_failure"))
	store.append(_event("drought"))
	var restored := EventStore.from_dicts(store.to_dicts())
	assert_eq(restored.events_of_type("drought").size(), 2)
	assert_eq(restored.events_of_type("crop_failure").size(), 1)


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


# -- the (entity, type) index ------------------------------------------------
#
# Reported live, again: "at a fresh start FPS is 60-100 but when running the
# game for a while it cripples to 5-10 fps". Same failure family as the
# events_of_type scan above (FPS regression round 14), one index over: the
# callers that had to be fixed there ask "what did THIS entity do, of THIS
# kind" -- EarthChunkManager._production_counts_for_settlement,
# _villagers_in_settlement, _households_in_settlement -- and every one of
# them called events_for_entity(settlement_id) and then filtered the result
# by type in GDScript.
#
# events_for_entity materialises a fresh Array[Event] holding EVERY event
# that entity was ever an actor or witness in, so the filter cost is the
# entity's WHOLE lifetime history no matter how few events actually match.
# A settlement's history grows every settlement step forever -- by design:
# "SUCCESSES are deliberately NOT guarded ... each one is real goods that
# were really made" (_settlement_production_outcome) -- so the work per step
# grows with how long the session has been running, and the total grows
# quadratically. That is the whole "gets slower the longer you play" shape.
#
# These pin the observable contract the index must preserve. The size
# assertion in test_..._is_unaffected_by_that_entitys_unrelated_event_volume
# is deliberately stronger than round 14's equivalent: it pins that the read
# yields ONLY the matching events, which is what makes a caller's own loop
# cost scale with matches rather than with history.

func test_events_for_entity_of_type_filters_by_both_entity_and_type():
	var mine := _event("production_succeeded")
	mine.actors = ["settlement:0_0"]
	var wrong_type := _event("npc_settled")
	wrong_type.actors = ["settlement:0_0"]
	var wrong_entity := _event("production_succeeded")
	wrong_entity.actors = ["settlement:9_9"]
	store.append(mine)
	store.append(wrong_type)
	store.append(wrong_entity)

	var result := store.events_for_entity_of_type("settlement:0_0", "production_succeeded")
	assert_eq(result.size(), 1)
	assert_eq(result[0].id, mine.id)


## Witnesses count, exactly as they do for events_for_entity -- the index is
## a narrowing of that same relation, not a different one.
func test_events_for_entity_of_type_indexes_witnesses_as_well_as_actors():
	var witnessed := _event("settlement_founded")
	witnessed.actors = ["npc:1"]
	witnessed.witnesses = ["settlement:0_0"]
	store.append(witnessed)
	assert_eq(store.events_for_entity_of_type("settlement:0_0", "settlement_founded").size(), 1)


func test_events_for_entity_of_type_preserves_insertion_order():
	for tick in [1.0, 2.0, 3.0]:
		var event := _event("production_succeeded", tick)
		event.actors = ["settlement:0_0"]
		store.append(event)
	var result := store.events_for_entity_of_type("settlement:0_0", "production_succeeded")
	assert_eq([result[0].tick, result[1].tick, result[2].tick], [1.0, 2.0, 3.0])


func test_events_for_entity_of_type_is_empty_for_an_unknown_entity_or_type():
	var event := _event("production_succeeded")
	event.actors = ["settlement:0_0"]
	store.append(event)
	assert_eq(store.events_for_entity_of_type("settlement:nope", "production_succeeded"), [])
	assert_eq(store.events_for_entity_of_type("settlement:0_0", "nope"), [])


## The point of the whole index: the answer must not carry -- and so a
## caller must not walk -- the rest of this entity's own history.
func test_events_for_entity_of_type_is_unaffected_by_that_entitys_unrelated_event_volume():
	var settlement := "settlement:0_0"
	for i in 500:
		var noise := _event("contract_fulfilled_%d" % (i % 7))
		noise.actors = [settlement]
		store.append(noise)
	var real := _event("production_succeeded")
	real.actors = [settlement]
	real.tags = ["cooked_meat"]
	store.append(real)
	for i in 500:
		var noise := _event("contract_fulfilled_%d" % (i % 7))
		noise.actors = [settlement]
		store.append(noise)

	assert_eq(store.events_for_entity(settlement).size(), 1001, "history really is that long")
	var result := store.events_for_entity_of_type(settlement, "production_succeeded")
	assert_eq(result.size(), 1, "the read yields only the matching event, not the history")
	assert_eq(result[0].tags, ["cooked_meat"])


## The index must be rebuilt on load, not just on live append -- a restored
## save queried on its very next settlement step must see what happened
## before the save.
func test_events_for_entity_of_type_reflects_events_restored_via_from_dicts():
	var event := _event("npc_settled")
	event.actors = ["npc:1"]
	event.witnesses = ["settlement:0_0"]
	store.append(event)
	var restored := EventStore.from_dicts(store.to_dicts())
	assert_eq(restored.events_for_entity_of_type("settlement:0_0", "npc_settled").size(), 1)
	assert_eq(restored.events_for_entity_of_type("npc:1", "npc_settled").size(), 1)


# -- several types at once (_households_in_settlement's SETTLING_EVENT_TYPES) --

## Merged in the store's own insertion order, NOT grouped by type: the
## caller this exists for (_households_in_settlement) dedupes by household
## as it walks, so "who settled first" has to stay the real answer.
func test_events_for_entity_of_types_merges_in_insertion_order():
	var settlement := "settlement:0_0"
	var types := ["npc_settled", "player_settled", "npc_settled"]
	for i in types.size():
		var event := _event(types[i], float(i))
		event.actors = ["actor:%d" % i]
		event.witnesses = [settlement]
		store.append(event)

	var result := store.events_for_entity_of_types(settlement, ["npc_settled", "player_settled"])
	assert_eq(result.size(), 3)
	assert_eq([result[0].tick, result[1].tick, result[2].tick], [0.0, 1.0, 2.0])


func test_events_for_entity_of_types_ignores_types_the_entity_never_had():
	var event := _event("npc_settled")
	event.witnesses = ["settlement:0_0"]
	store.append(event)
	var result := store.events_for_entity_of_types(
		"settlement:0_0", ["npc_settled", "player_settled", "player_house_settled"]
	)
	assert_eq(result.size(), 1)


func test_events_for_entity_of_types_is_empty_for_an_unknown_entity():
	assert_eq(store.events_for_entity_of_types("settlement:nope", ["npc_settled"]), [])


# -- the most recent event (the record_path_*_if_new family) ------------------

## record_path_worn_if_new/record_trail_formed_if_new and their reclaim
## mirrors only ever look at history.back() -- materialising the whole
## history to read its last element is the same waste one element wide.
func test_latest_event_for_entity_returns_the_most_recently_appended_one():
	for tick in [1.0, 2.0, 3.0]:
		var event := _event("path_worn", tick)
		event.actors = ["path:4_4"]
		store.append(event)
	var latest = store.latest_event_for_entity("path:4_4")
	assert_not_null(latest)
	assert_eq(latest.tick, 3.0)


func test_latest_event_for_entity_is_null_when_the_entity_has_no_history():
	assert_null(store.latest_event_for_entity("path:nope"))


func test_latest_event_for_entity_survives_from_dicts():
	var event := _event("trail_formed", 7.0)
	event.actors = ["path:4_4"]
	store.append(event)
	var restored := EventStore.from_dicts(store.to_dicts())
	assert_eq(restored.latest_event_for_entity("path:4_4").type, "trail_formed")


# -- the read odometer --------------------------------------------------------
#
# What made "the performance gets worse the longer you play" cost fifteen
# FPS-regression rounds to chase is that nothing ever reported how much
# HISTORY a frame walked. PerfReport times sections and counts nodes, but a
# section climbing from 6 ms to 142 ms over seven minutes looks identical
# whether the cause is a growing store, a growing population, or a growing
# anything else -- so each round needed a fresh long session plus a guess.
#
# This counts the one thing those rounds all turned out to be: events
# handed out by a read. It is the store's own cost, in the store's own
# units, and it is what test_earth_chunk_manager's settlement-assessment
# bound asserts against -- a deterministic stand-in for the Big-O that
# GDScript/GUT cannot assert directly.

func test_events_read_counts_the_events_a_whole_entity_read_walked():
	for i in 10:
		var event := _event("noise")
		event.actors = ["settlement:0_0"]
		store.append(event)
	store.take_events_read()
	store.events_for_entity("settlement:0_0")
	assert_eq(store.events_read(), 10)


## The whole point of the narrowed read: it walks the matches, not the
## history. This is the assertion that would have named round 14's root
## cause in one line.
func test_events_read_counts_only_the_matches_for_a_narrowed_read():
	for i in 10:
		var event := _event("noise")
		event.actors = ["settlement:0_0"]
		store.append(event)
	var real := _event("production_succeeded")
	real.actors = ["settlement:0_0"]
	store.append(real)

	store.take_events_read()
	store.events_for_entity_of_type("settlement:0_0", "production_succeeded")
	assert_eq(store.events_read(), 1)


func test_events_read_accumulates_across_reads():
	var event := _event("noise")
	event.actors = ["settlement:0_0"]
	store.append(event)
	store.take_events_read()
	store.events_for_entity("settlement:0_0")
	store.events_for_entity("settlement:0_0")
	assert_eq(store.events_read(), 2)


func test_take_events_read_returns_the_count_and_resets_it():
	var event := _event("noise")
	event.actors = ["settlement:0_0"]
	store.append(event)
	store.take_events_read()
	store.events_for_entity("settlement:0_0")
	assert_eq(store.take_events_read(), 1)
	assert_eq(store.events_read(), 0)


## events_of_type and the latest-event read are on the same odometer -- a
## frame's whole history cost is one number, not one per query shape.
func test_events_read_covers_events_of_type_and_latest_event_for_entity():
	for i in 3:
		var event := _event("drought")
		event.actors = ["region:0_0"]
		store.append(event)
	store.take_events_read()
	store.events_of_type("drought")
	assert_eq(store.events_read(), 3)
	store.take_events_read()
	store.latest_event_for_entity("region:0_0")
	assert_eq(store.events_read(), 1, "reading the newest event walks exactly one")
