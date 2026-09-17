extends SceneTree

## Dev tool: how much of a settlement's own event history one assessment of
## it walks, as that history grows (FPS regression round 16, see
## docs/concept/soil_fauna.md).
##
## Reported live: "at a fresh start FPS is 60-100 but when running the game
## for a while it cripples to 5-10 fps". The question a probe answers that a
## unit test cannot is the ASYMPTOTIC one -- not "is the answer still
## correct" but "does the cost stop growing" -- and waiting for a real save
## to organically accumulate a long history is far slower and far less
## controlled than founding a settlement and appending one.
##
## Same shape as round 14's follow-up probe (that one timed
## `step_settlements` against settlement COUNT; this one measures history
## DEPTH, the axis that round left untouched). Run it identically against
## `origin/main` and a fix branch and compare the columns.
##
## Reads EventStore's read odometer (`events_read`) rather than a wall
## clock: it is deterministic, it is machine-independent, and it measures
## the thing that actually grows. Wall-clock ms is reported alongside it
## for scale, and is the only noisy column here.
##
## Usage: godot --headless --path . -s tools/probe_settlement_history_cost.gd
##        [-- <depth> <depth> ...]
## Every measurement founds a settlement, which generates that chunk for
## real (tens of seconds each), so the default sweep is not quick -- pass a
## shorter list of depths when iterating.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const EntityRef = preload("res://src/emergence/entity_ref.gd")
const Event = preload("res://src/emergence/event.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")

## The settlement's history depths to measure at. Deliberately spans an
## order of magnitude: a linear cost shows up as a straight line through
## these, a bounded one as a flat one.
const HISTORY_DEPTHS := [0, 50, 100, 200, 400, 800]

## Always the same chunk, so terrain (and therefore the settlement's real
## capacity, production and classification path) is identical at every
## depth -- the history is the only thing that varies.
const CHUNK_COORD := Vector2i(47, 47)


func _initialize() -> void:
	var depths: Array = HISTORY_DEPTHS
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		depths = []
		for arg in args:
			depths.append(int(arg))
	print("settlement history depth -> events walked by ONE assessment")
	print("%10s %16s %14s %10s" % ["history", "events_walked", "walked/event", "ms"])
	for depth in depths:
		var measured := _measure(depth)
		var per_event := "n/a"
		if depth > 0:
			per_event = "%.1f" % (float(measured["walked"]) / float(depth))
		print(
			"%10d %16d %14s %10.1f"
			% [depth, measured["walked"], per_event, measured["ms"]]
		)
	quit()


## One settlement carrying `history_events` events of ordinary settlement
## traffic, assessed once. Returns how many events the store handed out
## doing it, and how long it took.
func _measure(history_events: int) -> Dictionary:
	var layer := TileMapLayer.new()
	var entities := Node2D.new()
	var creatures := Node2D.new()
	var manager = EarthChunkManager.new(layer, entities, creatures)
	manager.record_settlement_founded_if_new(
		CHUNK_COORD, [NpcIdentity.new(1), NpcIdentity.new(2)]
	)
	var settlement_id := EntityRef.for_settlement(CHUNK_COORD)
	var store = manager.event_store()

	# Every one names the settlement as its actor, so every one lands in
	# that settlement's entity index -- what the real contract and
	# production traffic does to it over a long session.
	var actors: Array[String] = [settlement_id]
	for i in history_events:
		var noise = Event.new("contract_fulfilled", 0.0)
		noise.actors = actors.duplicate()
		store.append(noise)

	store.take_events_read()
	var started := Time.get_ticks_usec()
	manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)
	var elapsed_usec := Time.get_ticks_usec() - started
	var walked: int = store.take_events_read()

	layer.free()
	entities.free()
	creatures.free()
	return {"walked": walked, "ms": float(elapsed_usec) / 1000.0}
