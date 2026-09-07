extends Node2D

## The visible marker over one AntColony mound cell (see
## ProceduralAntMoundSprite/IllustratedAntMoundSprite, docs/concept/
## soil_fauna.md). Still does not move, flee, or need FRAME-BY-FRAME
## behaviour the way a real creature does (see AntColony's own doc
## comment on why a mound is a background population effect, not an
## individually-simulated creature) -- but it is no longer purely inert
## either: it now re-checks its own colony's growth_fraction on a slow
## cadence and grows its own sprite to match (see docs/concept/
## soil_fauna.md "Mound size grows with the colony" -- requested
## directly: "it should be half a human high and grow with the colony").
## AntForagerMarker is still the thing that actually animates every
## frame, spawned separately per successful forage.

const ProceduralAntMoundSprite = preload("res://src/rendering/procedural_ant_mound_sprite.gd")
const IllustratedAntMoundSprite = preload("res://src/rendering/illustrated_ant_mound_sprite.gd")
const HoverTargetFinder = preload("res://src/rendering/hover_target_finder.gd")
const AntColony = preload("res://src/world/ant_colony.gd")

const GROUP_NAME := "ant_mound"

## How often this mound re-checks its own colony's growth_fraction and
## re-applies its sprite scale -- population moves over simulated DAYS
## (AntColony.SECONDS_PER_SIMULATED_DAY), so anything faster than a
## handful of real seconds would be spending per-frame cost on a number
## that is, for all practical purposes, motionless between checks.
const RESIZE_INTERVAL_SECONDS := 5.0

## Which of the illustrated sheet's variants this mound picks (see
## IllustratedAntMoundSprite.frame_for) -- ignored on the procedural
## fallback, which has no per-instance variation at all. Set before
## add_child, same convention as every other marker's per-instance fields
## (e.g. DecomposerMarker.wander_seed).
var mound_seed := 0

## The real AntColony this mound belongs to, and which cell within it --
## optional, duck-typed-by-convention the same way AntForagerMarker's own
## `_world`/`_colony` default to null for isolated testability. Without
## it, this marker simply reads as a founding-colony's own smallest
## mound forever (growth_fraction 0.0) and never resizes -- the same
## graceful no-op every other optional-world marker in this codebase
## falls back to.
var _colony: AntColony = null
var _cell := Vector2i.ZERO

var _sprite: Sprite2D
var _resize_accumulator := 0.0

static var _procedural_generator := ProceduralAntMoundSprite.new()
static var _illustrated_generator := IllustratedAntMoundSprite.new()


## `colony`/`cell` -- the real mound this marker represents. Mirrors
## AntForagerMarker.setup's own shape (minus a `world` reference: this
## marker never touches world state, only reads the colony's own
## population). Call before add_child, same convention as every other
## marker's setup().
func setup(colony: AntColony, cell: Vector2i) -> void:
	_colony = colony
	_cell = cell


func _ready() -> void:
	add_to_group(GROUP_NAME)
	add_to_group(HoverTargetFinder.GROUP_NAME)
	_sprite = Sprite2D.new()
	add_child(_sprite)
	_apply_growth(_growth_fraction())


## Founding size (0.0) with no colony wired up -- the same "optional
## world, safe default" fallback AntForagerMarker's own _colony already
## uses.
func _growth_fraction() -> float:
	if _colony == null:
		return 0.0
	return _colony.growth_fraction_at(_cell)


func _apply_growth(growth_fraction: float) -> void:
	if _illustrated_generator.has_variants():
		_sprite.texture = _illustrated_generator.frame_for(mound_seed)
		_sprite.scale = Vector2.ONE * _illustrated_generator.marker_scale(growth_fraction)
	else:
		_sprite.texture = _procedural_generator.generate_texture()
		_sprite.scale = Vector2.ONE * ProceduralAntMoundSprite.world_scale_for(growth_fraction)


## Nothing to do without a real colony wired up -- skipped entirely
## rather than accumulating toward a check that would always read the
## same 0.0 default anyway.
const PerfProbe = preload("res://src/rendering/perf_probe.gd")


func _process(delta: float) -> void:
	PerfProbe.begin("ant_mound._process")
	PerfProbe.count_instance("ant_mound (live)")
	_process_impl(delta)
	PerfProbe.end("ant_mound._process")


func _process_impl(delta: float) -> void:
	if _colony == null:
		return
	_resize_accumulator += delta
	if _resize_accumulator < RESIZE_INTERVAL_SECONDS:
		return
	_resize_accumulator = 0.0
	_apply_growth(_growth_fraction())


## For World's mouse-hover tooltip (see docs/concept/soil_fauna.md "Ants at
## half their old size, and finally hoverable") -- there is deliberately no
## separate queen sprite to hover (real queens are sessile and unseen
## outside the nest), so THIS is the one place a player can actually read
## anything about a colony living here rather than only inferring it from
## worker traffic and mound size. Reports the real population number once
## a colony is wired up (see "What the player actually sees" in that same
## doc section); falls back to the plain name otherwise, the same
## optional-world fallback every accessor on this marker already uses.
##
## Also reports the real STORED food quantity (`food_stored_at`), not
## `panel_state`'s own derived percentage -- requested directly ("the ant
## mount should show how much food is on stock in the hover tooltip", see
## docs/concept/soil_fauna.md "A real food stock number, not just a
## percentage, on hover"): a fraction answers "is this colony food-secure",
## a genuinely different question from "how much is actually in the
## larder". Joins this same tooltip (not the bar panel) since this is
## already where a raw number is interpolated into hover text, for
## population.
func get_display_name() -> String:
	if _colony == null:
		return "Ant Mound"
	return "Ant Mound (population %d, food %d)" % [
		int(round(_colony.population_at(_cell))), int(round(_colony.food_stored_at(_cell)))
	]


## For World's real hover panel (see docs/concept/soil_fauna.md "A mound's
## own hover panel") -- the same bar-and-percentage card every wild
## creature's own CreatureMarker.animal_state() already feeds
## (CreaturePanel.set_state), reading this mound's real food-supply
## fraction under its own label rather than a creature's health. No level
## (a mound has none) and never "invested" (a mound is never tamed) --
## both would show CreaturePanel rows that make no sense for a mound.
## Falls back to a founding mound's own reading (0.0 food availability,
## the same "optional world" graceful default get_display_name/
## _growth_fraction already use) without a real colony wired up.
func panel_state() -> Dictionary:
	var food_fraction := 0.0
	if _colony != null:
		food_fraction = _colony.food_availability_fraction(_cell)
	return {
		"name": "Ant Mound",
		"show_level": false,
		"bar_label": "Food",
		"health_fraction": food_fraction,
		"invested": false,
	}
