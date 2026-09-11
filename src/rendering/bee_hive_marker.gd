extends Node2D

## The visible marker over one BeeColony hive cell -- see
## ProceduralBeehiveSprite/IllustratedBeehiveSprite, docs/concept/bees.md.
## Mirrors AntMoundMarker's own shape (re-checks its colony's
## growth_fraction on a slow cadence, joins both the hover-tooltip and
## HUD-panel contracts) with two real additions no mound has any
## precedent for: real illustrated art picks a DISCRETE growth-stage
## frame (see IllustratedBeehiveSprite.growth_stage_index) rather than
## continuously rescaling one fixed variant, and this is a genuinely
## player-interactive structure -- get_hover_actions/harvest -- since an
## ant mound is never harvested at all.

const ProceduralBeehiveSprite = preload("res://src/rendering/procedural_beehive_sprite.gd")
const IllustratedBeehiveSprite = preload("res://src/rendering/illustrated_beehive_sprite.gd")
const HoverTargetFinder = preload("res://src/rendering/hover_target_finder.gd")
const BeeColony = preload("res://src/world/bee_colony.gd")
const BeeQueenMarker = preload("res://src/rendering/bee_queen_marker.gd")
const Item = preload("res://src/gameplay/item.gd")
const ItemStack = preload("res://src/gameplay/item_stack.gd")

const GROUP_NAME := "bee_hive"

## Mirrors AntMoundMarker.RESIZE_INTERVAL_SECONDS exactly: population
## moves over simulated DAYS, so anything faster than a handful of real
## seconds would spend per-frame cost on a number that is, for all
## practical purposes, motionless between checks.
const RESIZE_INTERVAL_SECONDS := 5.0

## How many real harvest hits break a hive down completely -- pinned to
## IllustratedBeehiveSprite's own real destruction-sheet frame count
## (row 2 of beehive.png has exactly 8 drawn stages), not an
## independently-chosen tuning number: the destruction ANIMATION and the
## hit-count BUDGET are the same 8 by construction (see docs/concept/
## bees.md's "Harvesting honey").
const HARVEST_HITS_TO_DESTROY := 8

## How much real honey one harvest hit yields, capped by whatever the
## colony actually has stored (see BeeColony.withdraw_honey) -- a hive
## struck when nearly empty still costs the swing but yields
## proportionally little, honestly, rather than a flat guaranteed amount
## regardless of the colony's real state.
const HONEY_YIELD_PER_HIT := 2.0

## The real BeeColony this hive belongs to, and which cell within it --
## optional, the same "graceful no-op without a colony" contract
## AntMoundMarker's own `_colony` already has. `_world` is new: unlike a
## mound (never player-interactive, never needs to call back into the
## world), a harvested-to-destruction hive needs a real site search for
## where it re-establishes, which only EarthChunkManager can do -- the
## same "colony owns the abstract economy, EarthChunkManager owns the
## real ground" split this whole feature already keeps everywhere else.
var _world = null
var _colony: BeeColony = null
var _cell := Vector2i.ZERO

var _sprite: Sprite2D
var _resize_accumulator := 0.0

## How many real harvest hits have landed so far. 0 means harvesting has
## not started at all -- the sprite still shows a real GROWTH frame, not
## a harvest one (see _apply_growth/_show_harvest_frame's own gating).
var _harvest_hits_landed := 0

static var _procedural_generator := ProceduralBeehiveSprite.new()
static var _illustrated_generator := IllustratedBeehiveSprite.new()


## `world`/`colony`/`cell` -- the real hive this marker represents.
## Mirrors AntForagerMarker.setup's shape (a `world` reference alongside
## the colony) rather than AntMoundMarker.setup's narrower one (colony
## only), since this marker -- unlike a mound -- genuinely needs to call
## back into the world once harvested to destruction. Call before
## add_child, the same convention every other marker's setup() follows.
func setup(world, colony: BeeColony, cell: Vector2i) -> void:
	_world = world
	_colony = colony
	_cell = cell


func _ready() -> void:
	add_to_group(GROUP_NAME)
	add_to_group(HoverTargetFinder.GROUP_NAME)
	_sprite = Sprite2D.new()
	add_child(_sprite)
	_apply_growth(_growth_fraction())
	# The queen's own real, minimal visual presence -- see BeeQueenMarker's
	# own doc comment. Only for a real, wired-up hive (mirrors this file's
	# own "graceful no-op without a colony" contract): a marker built
	# without setup() has nothing real for her to represent either.
	if _colony != null:
		var queen := BeeQueenMarker.new()
		queen.setup(_colony, _cell)
		add_child(queen)


## Founding size (0.0) with no colony wired up -- mirrors
## AntMoundMarker._growth_fraction's own optional-world default exactly.
func _growth_fraction() -> float:
	if _colony == null:
		return 0.0
	return _colony.growth_fraction_at(_cell)


## A no-op once harvesting has begun (see _harvest_hits_landed's own doc
## comment): the destruction sequence owns the sprite from the first
## landed hit until the marker is gone, growth no longer matters once a
## hive is actively being broken into.
func _apply_growth(growth_fraction: float) -> void:
	if _harvest_hits_landed > 0:
		return
	if _illustrated_generator.has_variants():
		var stage := IllustratedBeehiveSprite.growth_stage_index(growth_fraction)
		_sprite.texture = _illustrated_generator.growth_texture(stage)
		_sprite.scale = Vector2.ONE * _illustrated_generator.marker_scale(growth_fraction)
	else:
		_sprite.texture = _procedural_generator.generate_texture()
		_sprite.scale = Vector2.ONE * ProceduralBeehiveSprite.world_scale_for(growth_fraction)


const PerfProbe = preload("res://src/rendering/perf_probe.gd")


func _process(delta: float) -> void:
	PerfProbe.begin("bee_hive._process")
	PerfProbe.count_instance("bee_hive (live)")
	_process_impl(delta)
	PerfProbe.end("bee_hive._process")


func _process_impl(delta: float) -> void:
	if _colony == null or _harvest_hits_landed > 0:
		return
	_resize_accumulator += delta
	if _resize_accumulator < RESIZE_INTERVAL_SECONDS:
		return
	_resize_accumulator = 0.0
	_apply_growth(_growth_fraction())


## Mirrors AntMoundMarker.get_display_name's own shape exactly, against
## the honey-denominated numbers this hive actually tracks -- see
## bees.md's "Tooltip distinction": this and WildBeeNestMarker.
## get_display_name report genuinely different information (a wild
## nest's own text never mentions honey at all, because there genuinely
## is none to report), which is what makes the two read as real,
## different animals rather than a reskin of one mechanic.
## Reports real queen state too (see BeeQueenMarker/BeeColony.
## has_queen_at) -- the same existing tooltip contract the population/
## honey numbers already use, rather than a separate hoverable entity
## just for her: a queenless hive reads "requeening" plus real progress
## toward BeeColony.REQUEENING_DAYS, an observable consequence of losing
## her without inventing new UI surface for it.
func get_display_name() -> String:
	if _colony == null:
		return "Honeybee Hive"
	var base := "Honeybee Hive (population %d, honey %d)" % [
		int(round(_colony.population_at(_cell))), int(round(_colony.honey_stored_at(_cell)))
	]
	if _colony.has_queen_at(_cell):
		return base
	var percent := int(round(_colony.requeening_progress_at(_cell) * 100.0))
	return "%s -- queenless, requeening (%d%%)" % [base, percent]


## The one hover action this marker offers -- "attack" reuses the
## identical input action ChoppableTree/SmashableStone already dispatch
## a swing through (see player.gd's own _harvest_beehive_step, wired
## alongside _chop_step/_smash_step in the same family, not a new input
## verb).
func get_hover_actions() -> Array:
	return [{"verb": "Harvest", "action": "attack"}]


## Mirrors AntMoundMarker.panel_state's own shape exactly, labelled
## "Honey" rather than "Food" -- the real quantity a player can actually
## walk away with, not a creature's health.
func panel_state() -> Dictionary:
	var honey_fraction := 0.0
	if _colony != null:
		honey_fraction = _colony.honey_availability_fraction(_cell)
	return {
		"name": "Honeybee Hive",
		"show_level": false,
		"bar_label": "Honey",
		"health_fraction": honey_fraction,
		"invested": false,
	}


## Called by player.gd's own _harvest_beehive_step, the same "player
## swings at a stationary world object" contract ChoppableTree.
## take_damage/SmashableStone.smash already establish. Extracts real
## honey (capped by what the colony actually has -- see
## BeeColony.withdraw_honey, "one number, two roles" in bees.md), drops
## it as a real item, and advances the destruction sequence. The FINAL
## hit frees this marker and asks the world to relocate the colony (see
## bees.md's "Absconding") -- the colony's own real population and any
## honey left un-harvested carry over to wherever it re-establishes; a
## hive struck to structural collapse is NOT the same as the colony
## being wiped out.
##
## Safe with no colony wired up at all (a marker built without setup()):
## frees itself immediately rather than crashing reaching for a null
## _colony, the same "narrows, doesn't break" shape every other
## optional-world accessor in this codebase already has.
func harvest() -> void:
	if _colony == null:
		queue_free()
		return
	_harvest_hits_landed += 1
	var yielded := _colony.withdraw_honey(_cell, HONEY_YIELD_PER_HIT)
	if yielded > 0.0:
		WorldItemBus.item_dropped.emit(
			ItemStack.new(Item.new("honey", "Honey", "food", 20), maxi(1, int(ceil(yielded)))), position
		)
	_show_harvest_frame()
	if _harvest_hits_landed >= HARVEST_HITS_TO_DESTROY:
		_destroy_and_relocate()


## Row 2's own destruction frames, selected by real hit count -- never
## by growth fraction (see IllustratedBeehiveSprite.harvest_frame_index's
## own doc comment). No procedural equivalent sequence: a genuinely real,
## named gap (see bees.md) rather than an invented substitute -- the
## procedural fallback simply keeps its last-drawn texture through a
## harvest it cannot visually represent, until the marker is gone.
func _show_harvest_frame() -> void:
	if not _illustrated_generator.has_variants():
		return
	var index := IllustratedBeehiveSprite.harvest_frame_index(_harvest_hits_landed)
	_sprite.texture = _illustrated_generator.harvest_texture(index)
	_sprite.scale = Vector2.ONE * _illustrated_generator.marker_scale(_growth_fraction())


func _destroy_and_relocate() -> void:
	if _world != null and _world.has_method("relocate_bee_hive_after_harvest"):
		_world.relocate_bee_hive_after_harvest(_colony, _cell)
	queue_free()
