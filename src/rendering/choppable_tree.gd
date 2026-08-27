extends StaticBody2D

## A tree that can be felled with an axe (see Player._perform_attack),
## dropping wood. Deliberately defines NO _process -- thousands of these are
## loaded at once, so any per-frame behavior here would tank the frame rate
## (the same constraint ForageScheduler's centralized ticking exists to
## avoid). take_damage() is only ever called on demand by the attacker, so
## having a script here costs nothing at runtime until that happens.

const Item = preload("res://src/gameplay/item.gd")
const ItemStack = preload("res://src/gameplay/item_stack.gd")
const Health = preload("res://src/gameplay/health.gd")
const ProceduralTreeSprite = preload("res://src/rendering/procedural_tree_sprite.gd")
const TreeGrowth = preload("res://src/gameplay/tree_growth.gd")
const FelledTree = preload("res://src/rendering/felled_tree.gd")
const HoverTargetFinder = preload("res://src/rendering/hover_target_finder.gd")

const GROUP_NAME := "tree"
const MAX_HEALTH := 30.0
const WOOD_DROP_COUNT := 3
const STICK_DROP_COUNT := 2

var health := MAX_HEALTH
var _health := Health.new()

## Set by TreeRenderer so this tree can re-render its own canopy with its
## current ripe-fruit crop (see set_ripe_fruit) -- fruit phenology is driven
## centrally (EarthChunkManager.step_fruiting) only for trees near the player,
## so most trees never pay this cost.
var species_bias := 0.5
var sprite_seed := 0
var _canopy_sprite: Sprite2D
var _ripe_count := -1  # -1 == "never set", so the first update always renders
## The season this tree's canopy is currently drawn in (see IllustratedTree).
## Empty until set, so the first update always renders.
var _season := ""
## The season it is turning INTO, and how far along (see SeasonTransition).
## Part of the drawn state, so a tree redraws as the turn advances rather than
## only when the season name finally changes -- which is what made the change
## happen all at once.
var _turning_into := ""
var _turn_progress := 0.0
## How much of its canopy this tree has actually put out.
##
## Part of the DRAWN state, not just the node scale: a young tree has fewer
## branches, and scaling the whole node drew a sapling as a full-grown tree in
## miniature -- crown, boughs and every twig, only small. Growth reaching the
## canopy is what makes a sapling look like a sapling.
var _drawn_growth := -1.0
var _tree_sprite_generator := ProceduralTreeSprite.new()


func _ready() -> void:
	add_to_group(GROUP_NAME)
	add_to_group(HoverTargetFinder.GROUP_NAME)


## For World's mouse-hover tooltip (see HoverTargetFinder). Names its real
## stage (see docs/concept/woodworking.md): standing, felled-with-canopy, or
## a bare trunk once the crown is off.
func get_display_name() -> String:
	if not _felled:
		return "Tree"
	return "Bare Trunk" if _canopy_removed else "Fallen Tree"


## For World's mouse-hover tooltip (see HoverTargetFinder). Bound to "attack"
## because that is the input Player._chop_step actually reads (see
## Player._perform_attack). A bare trunk additionally offers Saw -- shown
## regardless of whether the player currently has a saw + enough Carpentry
## to actually use it (informational, same "show every possible action"
## convention every other multi-action hover already follows -- see e.g.
## LiftableStone's Pick Up + Kick).
func get_hover_actions() -> Array:
	var actions := [{"verb": "Chop", "action": "attack"}]
	if _felled and _canopy_removed:
		actions.append({"verb": "Saw", "action": "attack"})
	return actions


## Registers the canopy sprite so set_ripe_fruit can swap its texture.
func bind_canopy(sprite: Sprite2D) -> void:
	_canopy_sprite = sprite


## Shows `count` ripe fruits on the canopy, drawn for `season`.
##
## No-op unless something actually changed (avoids regenerating the texture
## every tick) or the canopy isn't bound. Season and crop share one entry
## point because they share one texture: regenerating for a new season would
## otherwise silently drop the fruit already on the tree.
func set_ripe_fruit(
	count: int, for_season: String = "", turning_into: String = "", turn_progress: float = 0.0
) -> void:
	if _canopy_sprite == null:
		return
	if (
		count == _ripe_count
		and for_season == _season
		and turning_into == _turning_into
		and is_equal_approx(turn_progress, _turn_progress)
		and is_equal_approx(_canopy_growth(), _drawn_growth)
	):
		return
	_ripe_count = count
	_season = for_season
	_turning_into = turning_into
	_turn_progress = turn_progress
	_redraw_canopy()


## The season this tree is currently drawn in.
## The canopy fraction this tree draws at, quantised the way the sprite cache
## quantises it -- so a tree growing by a hair does not count as a change and
## rebuild its texture every frame.
func _canopy_growth() -> float:
	return ProceduralTreeSprite.growth_level(growth_scale)


func _redraw_canopy() -> void:
	if _canopy_sprite == null or _season == "":
		return
	_drawn_growth = _canopy_growth()
	_canopy_sprite.texture = _tree_sprite_generator.generate_texture_with_fruit(
		species_bias,
		sprite_seed,
		maxi(_ripe_count, 0),
		_season,
		_turning_into,
		_turn_progress,
		_drawn_growth
	)


func current_season() -> String:
	return _season


## The crop currently drawn on this tree. Lets a season change redraw the
## canopy without knowing, or losing, the fruit already on it.
func ripe_fruit_count() -> int:
	return maxi(_ripe_count, 0)


## Reduces health; felling drops nothing yet (see docs/concept/woodworking.md
## -- the tree is a real thing lying there, not a loot spray) and frees the
## tree once fully worked up (its collision goes with it, same as any other
## queue_free()'d node). A swing lands on this tree.
##
## Standing, it takes damage until it FALLS -- and then it is still there, on
## its side, holding all its timber. Fallen, the FIRST swing limbs the crown
## off (sticks); every swing after that bucks one length off the bare trunk
## into logs, until the trunk is used up. See saw_up() for the alternative,
## tool+skill-gated way to finish a bare trunk in one action instead.
func take_damage(amount: float) -> void:
	if _felled:
		if not _canopy_removed:
			_remove_canopy()
		else:
			_cut_up()
		return
	health = _health.take_damage(health, amount)
	if _health.is_dead(health):
		_fall()


## Whether this tree has been felled and is lying there.
func is_felled() -> bool:
	return _felled


var _felled := false
## Whether the crown has already been limbed off (see _remove_canopy) --
## once true, further swings work the bare trunk itself.
var _canopy_removed := false
var _cuts_left := FelledTree.CUTS_TO_CLEAR


## Topples the tree: same sprite, on its side, still carrying its timber.
func _fall() -> void:
	_felled = true
	_canopy_removed = false
	_cuts_left = FelledTree.CUTS_TO_CLEAR
	rotation = FelledTree.FALLEN_ROTATION * float(FelledTree.fall_direction(sprite_seed))
	# A fallen trunk lies ON the ground rather than standing on it, so it stops
	# blocking the way and stops sorting like a standing tree.
	z_index = -1
	for child in get_children():
		if child is CollisionShape2D:
			child.set_deferred("disabled", true)


## The first swing on a freshly-felled tree: limbs the crown off as sticks.
## Real forestry practice (limb before bucking), not an invented game step --
## see docs/concept/woodworking.md. Does not consume one of the trunk's own
## CUTS_TO_CLEAR.
##
## Actually swaps what's drawn, not just the state flag -- reported live: a
## tree still showed its full canopy after this fired, since flipping
## _canopy_removed alone never told the canopy sprite to redraw.
func _remove_canopy() -> void:
	_canopy_removed = true
	var sticks_count := FelledTree.sticks_from_canopy(growth_scale)
	WorldItemBus.item_dropped.emit(
		ItemStack.new(Item.new("stick", "Stick", "material", 40), sticks_count), position
	)
	if _canopy_sprite != null:
		_canopy_sprite.texture = _tree_sprite_generator.generate_bare_trunk_texture(
			species_bias, sprite_seed, _season
		)


## Bucks one length off the bare trunk into a real log.
func _cut_up() -> void:
	var log_count := FelledTree.logs_per_cut(growth_scale)
	_cuts_left -= 1
	WorldItemBus.item_dropped.emit(
		ItemStack.new(Item.new("log", "Log", "material", 20), log_count), position
	)
	if _cuts_left <= 0:
		queue_free()


## Saws the ENTIRE remaining bare trunk into beam + plank in one action,
## skipping the per-swing log split -- the tool+skill-gated alternative to
## _cut_up (see docs/concept/woodworking.md). Returns whether it happened:
## false (a no-op) unless this is actually a bare, not-yet-fully-worked
## trunk, so a caller (Player._chop_step) can just try this first and fall
## back to the ordinary chop otherwise.
func saw_up() -> bool:
	if not _felled or not _canopy_removed or _cuts_left <= 0:
		return false
	var beam_count := FelledTree.beams_from_trunk(growth_scale, _cuts_left)
	var plank_count := FelledTree.planks_from_trunk(growth_scale, _cuts_left)
	WorldItemBus.item_dropped.emit(
		ItemStack.new(Item.new("beam", "Beam", "material", 20), beam_count), position
	)
	WorldItemBus.item_dropped.emit(
		ItemStack.new(Item.new("plank", "Plank", "material", 20), plank_count),
		position + Vector2(8, 4)
	)
	_cuts_left = 0
	queue_free()
	return true


## How far grown this tree is, 0..1 (see TreeGrowth). Applied to the whole
## node so canopy, trunk, shadow and collision shrink together -- a seedling
## is a small tree, not a full tree drawn small.
## When this tree was planted, on the world clock. Trees that predate the
## session are already grown and leave this at zero.
var planted_at := 0.0

## A tree's own growth, kept up to date rather than frozen at spawn.
##
## `growth_scale` used to be assigned once by TreeRenderer, from the tree's age
## at the moment it was built, and nothing ever touched it again: a sapling you
## watched stayed a seedling for as long as you watched it, and the only way to
## see one mature was to walk far enough away for its chunk to unload and then
## come back. Reported as newborn trees not maturing properly.
func set_age(age_seconds: float) -> void:
	growth_scale = _tree_growth.scale_at(age_seconds)
	# Growing is a redraw as well as a resize. The guard in set_ripe_fruit
	# compares crop and season, and age is neither, so it would otherwise read
	# a grown tree as "nothing changed" and keep the sapling's canopy.
	_redraw_canopy()


## How many times a bee has visited this tree so far in its CURRENT bearing
## cycle (see FruitingModel.pollination_factor / docs/concept/flora.md), and
## which cycle that count belongs to.
##
## crop_potential is a pure function of the genome and elapsed time -- there
## is no persisted per-tree state anywhere else for a visit to land in, so
## this is where it lives, the same tier as this node's other per-tree state
## (growth_scale, _ripe_count). Deliberately survives only as long as this
## node does: it does NOT persist across a chunk unload/reload or a save,
## which is an explicit simplification for this pass (see docs/progress.md) --
## a chunk that unloads mid-cycle loses count of visits nobody was watching
## anyway, the same way a sapling's growth is re-derived rather than saved.
var _pollination_visits := 0.0
var _pollination_visits_cycle := -1


## Records one bee visit at world time `now`, within a bearing cycle
## `bearing_cycle_seconds` long. Rolls the count over to zero the moment `now`
## falls in a LATER cycle than the one already being counted, so a visit from
## last year can never go on boosting this year's crop.
##
## `visit_weight` defaults to a flat 1.0 (an ordinary visit) but a caller can
## bank more or less, scaled by the visiting bee's own AnimalFitness.
## fitness_score -- see FruitingModel.visit_weight_for_fitness. The
## accumulator is a float rather than an int specifically to hold these
## fractional weights.
func record_pollination_visit(bearing_cycle_seconds: float, now: float, visit_weight: float = 1.0) -> void:
	var cycle := int(floor(now / maxf(bearing_cycle_seconds, 0.0001)))
	if cycle != _pollination_visits_cycle:
		_pollination_visits_cycle = cycle
		_pollination_visits = 0.0
	_pollination_visits += visit_weight


## How many visits (fitness-weighted, see record_pollination_visit) this tree
## has banked in the bearing cycle `now` falls in. Read-only: querying a
## cycle nothing has been recorded in yet (including the very first query on
## a freshly-built tree) simply reads zero rather than resetting anything, so
## this is safe to call as often as fruiting steps run.
func pollination_visits_in_cycle(bearing_cycle_seconds: float, now: float) -> float:
	var cycle := int(floor(now / maxf(bearing_cycle_seconds, 0.0001)))
	if cycle != _pollination_visits_cycle:
		return 0.0
	return _pollination_visits


static var _tree_growth := TreeGrowth.new()

var growth_scale: float = 1.0:
	set(value):
		growth_scale = clampf(value, 0.05, 1.0)
		scale = Vector2.ONE * growth_scale
