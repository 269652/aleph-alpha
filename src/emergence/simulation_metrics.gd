extends RefCounted

## Read-only summarizer over an EventStore's causal event graph (see
## src/emergence/event_store.gd).
##
## Pure and engine-free, matching this project's pure-module idiom -- no
## FileAccess, no engine singletons, nothing but arithmetic over what the
## store already exposes. Exists so a console command (or anything else that
## wants a quick health-check of the simulation) can ask "what has actually
## happened so far" without re-deriving the same tallies inline every time --
## one place to get event/entity counts, a per-type breakdown, the tick span
## and the average importance right, instead of scattering ad-hoc loops over
## `store.all_ids()` wherever a summary is needed.

const Event = preload("res://src/emergence/event.gd")
const EventStore = preload("res://src/emergence/event_store.gd")


## Tallies the whole store into a flat Dictionary. Correct for an EMPTY store
## on purpose -- an empty simulation is a normal state (a freshly started
## world, a test fixture), not an error, so every field defaults to a sane
## zero/empty value rather than the caller having to special-case "no events
## yet" before it can even print a summary.
static func summarize(store: EventStore) -> Dictionary:
	var events_by_type: Dictionary = {}
	var oldest_tick := 0.0
	var newest_tick := 0.0
	var importance_total := 0.0

	var ids: Array[String] = store.all_ids()
	for i in ids.size():
		var event: Event = store.get_event(ids[i])
		events_by_type[event.type] = events_by_type.get(event.type, 0) + 1
		importance_total += event.importance
		if i == 0:
			oldest_tick = event.tick
			newest_tick = event.tick
		else:
			oldest_tick = min(oldest_tick, event.tick)
			newest_tick = max(newest_tick, event.tick)

	# Guard the mean explicitly rather than relying on ids.size() staying
	# nonzero by construction -- an empty store must report 0.0, not NaN from
	# a 0.0 / 0.0 divide.
	var average_importance := 0.0
	if not ids.is_empty():
		average_importance = importance_total / ids.size()

	return {
		"event_count": store.size(),
		"entity_count": store.all_entity_ids().size(),
		"events_by_type": events_by_type,
		"oldest_tick": oldest_tick,
		"newest_tick": newest_tick,
		"average_importance": average_importance,
	}


## Renders summarize()'s output as a short, plain-text block -- no markdown,
## no ANSI -- so a console command can hand it straight to log_line. Sorts
## the per-type breakdown alphabetically so repeated runs against the same
## store print identically, rather than following Dictionary insertion order
## (which here happens to be first-seen order, but that is an implementation
## detail this report shouldn't depend on).
static func format_report(store: EventStore) -> String:
	var summary: Dictionary = summarize(store)
	var lines: Array[String] = []

	lines.append("%d events, %d entities tracked" % [summary["event_count"], summary["entity_count"]])

	var events_by_type: Dictionary = summary["events_by_type"]
	if events_by_type.is_empty():
		lines.append("  by type: (none)")
	else:
		var types: Array = events_by_type.keys()
		types.sort()
		var parts: Array[String] = []
		for type in types:
			parts.append("%s x%d" % [type, events_by_type[type]])
		lines.append("  by type: %s" % ", ".join(parts))

	lines.append("  tick range: %s - %s, avg importance %s" % [
		_format_number(summary["oldest_tick"]),
		_format_number(summary["newest_tick"]),
		_format_number(summary["average_importance"]),
	])

	return "\n".join(lines)


## Trims a float to a stable, human-friendly form ("1" not "1.000000",
## "0.35" not "0.35000001") -- String.num keeps the max_digits without
## padding trailing zeros the way "%f" would.
static func _format_number(value: float) -> String:
	return String.num(value, 4)
