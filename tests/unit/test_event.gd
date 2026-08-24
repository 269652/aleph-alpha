extends GutTest

## Event (see docs/emergence/00-emergence-architecture.md "Event sourcing" and
## docs/emergence/02-history-memory-rumors.md's Event schema).
##
## One immutable node in the world's causal event graph. Pure data plus the
## round-trip its own persistence needs -- the id/consequences bookkeeping
## belongs to EventStore, not here (see test_event_store.gd).

const Event = preload("res://src/emergence/event.gd")


func test_carries_its_type_tick_and_location():
	var event := Event.new("settlement_founded", 120.0, Vector2(64.0, 128.0))
	assert_eq(event.type, "settlement_founded")
	assert_eq(event.tick, 120.0)
	assert_eq(event.location, Vector2(64.0, 128.0))


func test_location_defaults_to_zero_for_a_non_spatial_event():
	var event := Event.new("village_endangerment_warning", 0.0)
	assert_eq(event.location, Vector2.ZERO)


func test_actors_causes_and_witnesses_start_empty():
	var event := Event.new("settlement_founded", 0.0)
	assert_eq(event.actors, [])
	assert_eq(event.causes, [])
	assert_eq(event.consequences, [])
	assert_eq(event.witnesses, [])
	assert_eq(event.tags, [])


func test_importance_and_visibility_have_sane_defaults():
	var event := Event.new("settlement_founded", 0.0)
	assert_eq(event.importance, 0.0)
	assert_eq(event.visibility, "local")


## Round-trips every field, since EventStorePersistence's whole job depends on
## this being lossless (see test_event_store_persistence.gd).
func test_to_dict_and_from_dict_round_trip_every_field():
	var event := Event.new("settlement_founded", 42.0, Vector2(1.0, 2.0))
	event.id = "evt_0_settlement_founded"
	event.actors = ["settlement:0_0"]
	event.causes = ["evt_x"]
	event.consequences = ["evt_y"]
	event.witnesses = ["npc:1", "npc:2"]
	event.evidence = ["house ruin"]
	event.importance = 0.75
	event.visibility = "regional"
	event.tags = ["founding"]

	var restored := Event.from_dict(event.to_dict())

	assert_eq(restored.id, event.id)
	assert_eq(restored.type, event.type)
	assert_eq(restored.tick, event.tick)
	assert_eq(restored.location, event.location)
	assert_eq(restored.actors, event.actors)
	assert_eq(restored.causes, event.causes)
	assert_eq(restored.consequences, event.consequences)
	assert_eq(restored.witnesses, event.witnesses)
	assert_eq(restored.evidence, event.evidence)
	assert_eq(restored.importance, event.importance)
	assert_eq(restored.visibility, event.visibility)
	assert_eq(restored.tags, event.tags)
