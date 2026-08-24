extends GutTest

## SimulationMetrics (see src/emergence/simulation_metrics.gd).
##
## A pure summarizer over an EventStore -- counts, per-type breakdown, tick
## range and average importance, plus a compact plain-text report for console
## commands. Exercises both an empty store (every field must still be a sane
## default, not an error) and a populated one against hand-built fixtures
## with known ticks/importances/types.

const Event = preload("res://src/emergence/event.gd")
const EventStore = preload("res://src/emergence/event_store.gd")
const SimulationMetrics = preload("res://src/emergence/simulation_metrics.gd")

var store: EventStore


func before_each():
	store = EventStore.new()


func _event(type: String, tick: float, importance: float = 0.0) -> Event:
	var event := Event.new(type, tick)
	event.importance = importance
	return event


# -- empty store ---------------------------------------------------------

func test_summarize_of_an_empty_store_has_zero_counts():
	var summary: Dictionary = SimulationMetrics.summarize(store)
	assert_eq(summary["event_count"], 0)
	assert_eq(summary["entity_count"], 0)


func test_summarize_of_an_empty_store_has_empty_events_by_type():
	var summary: Dictionary = SimulationMetrics.summarize(store)
	assert_eq(summary["events_by_type"], {})


func test_summarize_of_an_empty_store_has_zero_ticks_not_an_error():
	var summary: Dictionary = SimulationMetrics.summarize(store)
	assert_eq(summary["oldest_tick"], 0.0)
	assert_eq(summary["newest_tick"], 0.0)


func test_summarize_of_an_empty_store_has_zero_average_importance():
	var summary: Dictionary = SimulationMetrics.summarize(store)
	assert_eq(summary["average_importance"], 0.0)


func test_format_report_of_an_empty_store_is_non_empty_and_sane():
	var report: String = SimulationMetrics.format_report(store)
	assert_true(report.length() > 0)
	assert_true(report.contains("0"))


# -- populated store -------------------------------------------------------

## Fixture: 4 events, 3 types, 3 distinct entities (one entity appears
## twice), known ticks and importances so every derived stat can be checked
## by hand.
## drought        tick 5.0  importance 0.2  actor npc:1
## crop_failure   tick 10.0 importance 0.6  actor npc:1, witness settlement:0_0
## crop_failure   tick 12.0 importance 0.4  actor npc:2
## food_shortage  tick 20.0 importance 0.8  witness settlement:0_0
func _populated_store() -> EventStore:
	var s := EventStore.new()

	var drought := _event("drought", 5.0, 0.2)
	drought.actors = ["npc:1"]
	s.append(drought)

	var crop_failure_a := _event("crop_failure", 10.0, 0.6)
	crop_failure_a.actors = ["npc:1"]
	crop_failure_a.witnesses = ["settlement:0_0"]
	s.append(crop_failure_a)

	var crop_failure_b := _event("crop_failure", 12.0, 0.4)
	crop_failure_b.actors = ["npc:2"]
	s.append(crop_failure_b)

	var shortage := _event("food_shortage", 20.0, 0.8)
	shortage.witnesses = ["settlement:0_0"]
	s.append(shortage)

	return s


func test_summarize_event_count_matches_store_size():
	var s := _populated_store()
	assert_eq(SimulationMetrics.summarize(s)["event_count"], 4)


func test_summarize_entity_count_matches_distinct_entities():
	var s := _populated_store()
	# npc:1, npc:2, settlement:0_0 -- 3 distinct, even though npc:1 and
	# settlement:0_0 each show up in more than one event.
	assert_eq(SimulationMetrics.summarize(s)["entity_count"], 3)


func test_summarize_events_by_type_counts_each_type():
	var s := _populated_store()
	var by_type: Dictionary = SimulationMetrics.summarize(s)["events_by_type"]
	assert_eq(by_type["drought"], 1)
	assert_eq(by_type["crop_failure"], 2)
	assert_eq(by_type["food_shortage"], 1)
	assert_eq(by_type.size(), 3)


func test_summarize_oldest_and_newest_tick_span_the_fixture():
	var s := _populated_store()
	var summary: Dictionary = SimulationMetrics.summarize(s)
	assert_eq(summary["oldest_tick"], 5.0)
	assert_eq(summary["newest_tick"], 20.0)


## (0.2 + 0.6 + 0.4 + 0.8) / 4 == 0.5
func test_summarize_average_importance_is_the_mean():
	var s := _populated_store()
	assert_eq(SimulationMetrics.summarize(s)["average_importance"], 0.5)


func test_format_report_of_a_populated_store_is_non_empty_and_sane():
	var s := _populated_store()
	var report: String = SimulationMetrics.format_report(s)
	assert_true(report.length() > 0)
	assert_true(report.contains("4"))
	assert_true(report.contains("drought"))
	assert_true(report.contains("crop_failure"))
