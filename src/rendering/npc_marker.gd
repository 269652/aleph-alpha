extends Sprite2D

## The cheap local FSM half of docs/concept/npc.md's "Planning architecture":
## walks toward wherever the current schedule entry's location_tag resolves
## to, re-deriving the current entry from elapsed time every frame -- zero
## planner calls mid-day, matching CreatureWander/FishMarker's "pure,
## deterministic, no per-frame AI" philosophy rather than CreatureMarker's
## full sense/perceive/act loop (an NPC just walks its plan, it doesn't hunt
## or flee).

const NpcIdentity = preload("res://src/world/npc_identity.gd")
const NpcPlanner = preload("res://src/world/npc_planner.gd")
const NpcSchedule = preload("res://src/world/npc_schedule.gd")
const NpcEconomy = preload("res://src/world/npc_economy.gd")
const NpcInstructionEvaluator = preload("res://src/world/npc_instruction_evaluator.gd")
const CharacterView = preload("res://scenes/character_view.gd")
const CreaturePerception = preload("res://src/gameplay/creature_perception.gd")

## Walking pace -- similar order to CreatureWander.WANDER_SPEED, unhurried.
const WALK_SPEED := 20.0

## Real seconds per simulated in-game day, mirroring
## EarthChunkManager.SECONDS_PER_SIMULATED_DAY's existing pacing so a
## village's daily rhythm runs on the same clock as the rest of the world
## sim.
const SECONDS_PER_SIMULATED_DAY := 60.0

var identity: NpcIdentity
var home_position := Vector2.ZERO
## Where this NPC works when their occupation's location_tag isn't one of
## the settlement's 3 shared landmarks (well/stall/gate) -- see
## SettlementGenerator's scope note on not modeling per-occupation buildings
## yet.
var workspot_position := Vector2.ZERO
var landmarks: Dictionary = {}
var schedule: Array = []

var _elapsed_time := 0.0
var _day_index := 0
var _planner: NpcPlanner.Planner = NpcPlanner.FakeNpcPlanner.new()

## Duck-typed world (biome_at_global) and tile size, mirroring
## CreatureMarker.setup -- lets an NPC tell whether it's standing in water so
## its walk cycle can switch to swimming, same as the player/creatures.
## Without it (fail-open, see _is_in_water), an NPC just never swims.
var _world = null
var _tile_size := 16
var _perception := CreaturePerception.new()

## docs/concept/npc.md "Needs and the local production economy": this
## villager's hunger/gold/production state, mirroring the daily-plan
## FSM's own "cheap local execution" pattern -- null until setup_economy is
## called (see VillageRenderer._build_npc), so a marker built without an
## economy (e.g. an isolated rendering test) simply carries no needs state
## rather than crashing.
var economy: NpcEconomy = null

## An optional standing instruction script (docs/concept/
## npc_instructions.md, "Execution / wiring") -- null for every NPC by
## default, parallel to `economy`'s own null-checked pattern above, so a
## marker with no assigned instruction is byte-for-byte unaffected. When
## set, holds the parsed AST Dictionary NpcInstructionParser.parse(source)
## ["ast"] produces ({"kind": "instruct", "rules": [...]}) -- the same shape
## NpcInstructionEvaluator.evaluate consumes directly.
var instruction_script = null

## This NPC's real held items (docs/concept/npc_instructions.md, the
## per-NPC/household inventory `_instruction_frame()` reads for
## `inventory_at_least`). A real Dictionary (item_id -> int count), NOT
## null-checked like `economy`/`instruction_script` above -- an empty
## inventory is a valid real state (an NPC that genuinely holds nothing),
## not an absence to guard against. Read/written via NpcInventory's pure
## add/remove/count_of helpers (src/world/npc_inventory.gd).
var inventory := {}


## Swaps in a different planner (e.g. a future real LLM-backed one) -- see
## NpcPlanner.Planner. Defaults to the deterministic FakeNpcPlanner.
func set_planner(planner: NpcPlanner.Planner) -> void:
	_planner = planner


## Gives the NPC the world it senses, enabling water-awareness. See
## CreatureMarker.setup, which this mirrors exactly.
func setup(world, tile_size: int) -> void:
	_world = world
	_tile_size = tile_size


## Builds this villager's NpcEconomy from its already-assigned `identity`
## (must be set first -- see VillageRenderer._build_npc) and `market`, the
## VillageMarket instance shared by every NpcMarker of the same settlement.
func setup_economy(market) -> void:
	economy = NpcEconomy.new(identity.seed_value, identity.occupation, market)


func _process(delta: float) -> void:
	_elapsed_time += delta
	if schedule.is_empty():
		schedule = _planner.plan_day(identity, _day_index)

	var entry := NpcSchedule.current_entry(schedule, _current_hour())
	if instruction_script != null:
		var action: Variant = NpcInstructionEvaluator.evaluate(instruction_script, _instruction_frame())
		if action != null:
			entry = _entry_for_instructed_action(action)
	var target := _resolve_location(entry.get("location_tag", "home"))
	var before := position
	position = position.move_toward(target, WALK_SPEED * delta)
	_update_animation(position - before)
	if economy != null:
		economy.step(delta, entry.get("activity", "") == "work", _world, position)


## Drives the bound CharacterView's walk cycle from the actual movement this
## frame -- previously nothing called set_facing/is_moving/set_movement_state
## after the marker moved, so every villager's walk animation sat frozen in
## IDLE despite visibly walking (reported: "NPCs don't have walk or swim
## animation").
func _update_animation(moved: Vector2) -> void:
	if _character_view == null:
		return
	var is_moving := moved.length() > 0.01
	if is_moving:
		face_movement(moved)
	_character_view.is_moving = is_moving
	if _is_in_water():
		_character_view.set_movement_state(CharacterView.MovementState.SWIMMING)
	elif is_moving:
		_character_view.set_movement_state(CharacterView.MovementState.WALKING)
	else:
		_character_view.set_movement_state(CharacterView.MovementState.IDLE)


## Fails open (never swimming) without a world -- same shape as
## CreatureMarker's water checks, which all guard on _world != null.
func _is_in_water() -> bool:
	if _world == null:
		return false
	var tile := Vector2i(floori(position.x / _tile_size), floori(position.y / _tile_size))
	return _perception.is_on(_world, tile, "water")


func _current_hour() -> int:
	var day_fraction := fmod(_elapsed_time / SECONDS_PER_SIMULATED_DAY, 1.0)
	return int(day_fraction * 24.0)


## Builds the flat context Dictionary NpcInstructionEvaluator's condition
## primitives read (docs/concept/npc_instructions.md, "Execution / wiring":
## "context is a flat Dictionary ... nothing that isn't already live
## state") -- this NPC's own hunger need (the one live need signal NpcMarker
## already carries via `economy`) and its real `inventory` Dictionary, now
## that src/world/npc_inventory.gd exists to back it. An NPC that holds
## nothing genuinely reports an empty inventory here -- the primitives' own
## fail-open/empty-is-not-an-error convention (see
## npc_instruction_primitives.gd) still applies, it's just backed by real
## state now instead of always being stubbed.
func _instruction_frame() -> Dictionary:
	var needs := {}
	if economy != null:
		needs["hunger"] = economy.needs.hunger
	return {"inventory": inventory, "needs": needs}


## Adapts an instruction action descriptor (NpcInstructionPrimitives' own
## {"fn": "haul"/"gather", ...} shape) into the same {location_tag, activity}
## shape an ordinary schedule entry already has, reusing _resolve_location's
## existing tag lookup (home/landmark/workspot fallback) rather than a new
## spatial-query layer -- the real nearest-X spatial query
## npc_instruction_effects.gd will eventually use is a later step (docs/
## concept/npc_instructions.md, "Execution / wiring"). Both v1 actions read
## as "work" for the economy step underneath, same as any other work entry.
func _entry_for_instructed_action(action: Dictionary) -> Dictionary:
	match action.get("fn", ""):
		"haul":
			return {"location_tag": action.get("destination_tag", "home"), "activity": "work"}
		"gather":
			return {"location_tag": action.get("resource_tag", "home"), "activity": "work"}
	return {"location_tag": "home", "activity": "idle"}


## "home" is this NPC's own house; a shared landmark tag (well/stall/gate)
## resolves to the settlement's landmark; anything else (a work tag with no
## dedicated building yet, e.g. "field"/"forge") falls back to this NPC's
## personal workspot rather than an unresolved position.
func _resolve_location(tag: String) -> Vector2:
	if tag == "home":
		return home_position
	if landmarks.has(tag):
		return landmarks[tag]
	return workspot_position


## The CharacterView rendering this villager (see VillageRenderer._build_npc).
## The marker itself is a Sprite2D for historical reasons but no longer draws
## its own texture -- the view owns the visuals, so body proportions and the
## walk animation are shared with the player rather than duplicated.
var _character_view: Node2D


func bind_character_view(view: Node2D) -> void:
	_character_view = view


## Points the villager the way it is walking, so NPCs face their direction
## of travel like the player does.
func face_movement(direction: Vector2) -> void:
	if _character_view != null:
		_character_view.set_facing(direction)
