extends Sprite2D

## A fish-eating bird (kingfisher) -- cruises like an ambient flyer
## (AmbientFlyerMovement) until it commits to a dive on nearby water (see
## PiscivoreBirdBehavior), then visibly drops toward the water, resolves a
## grab-or-miss, and on a successful grab, actually decrements the real
## aquatic population -- the same EcosystemSimulation.record_catch the
## player's own fishing rod calls (see EarthChunkManager.catch_nearest_fish),
## so a heavily-birded cove is measurably fished down over time too. See
## docs/concept/ecosystem_dynamics.md's "fish-eating birds" (A new aerial
## tier).

const AmbientFlyerMovement = preload("res://src/rendering/ambient_flyer_movement.gd")
const PiscivoreBirdBehavior = preload("res://src/gameplay/piscivore_bird_behavior.gd")
const PiscivoreAppetite = preload("res://src/gameplay/piscivore_appetite.gd")
const ProceduralFishSprite = preload("res://src/rendering/procedural_fish_sprite.gd")
const FishRenderer = preload("res://src/rendering/fish_renderer.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")
const HoverTargetFinder = preload("res://src/rendering/hover_target_finder.gd")

## How far below cruise altitude the sprite visibly drops at the bottom of a
## dive -- a simple vertical offset "descent" (a kingfisher dives essentially
## straight down), not a full 3D swoop.
const DIVE_DEPTH_PX := 10.0

var home := Vector2.ZERO
var wander_seed := 0
var species := "kingfisher"

## `world` (duck-typed fish_population_near(pixel_position)/
## record_fish_catch_near(pixel_position, count), the same contract
## EarthChunkManager provides) drives both the dive decision and the catch's
## real effect; left unset (default null), the bird just cruises forever,
## the same isolated-test fallback other markers use.
var _world = null
var _movement: AmbientFlyerMovement
var _behavior := PiscivoreBirdBehavior.new()
var _elapsed_time := 0.0
var _dive_attempts := 0
## The fish currently in this bird's beak, shown while it carries its catch.
var _carried_fish: Sprite2D = null
## The specific fish this bird is hunting.
##
## Held from the moment it starts hovering, because the strike has to resolve
## against the fish it aimed at. Resolving against "whatever is nearest NOW"
## meant the target had swum on during the hover and the dive -- a second or
## two of swimming -- so the grab found nothing, no fish appeared in the beak,
## and the bird went on to strike at some other fish somewhere else later.
var _target_fish: Node2D = null

## How hungry this bird is, and what it is doing about it (see
## PiscivoreAppetite). Without an appetite the bird hunted continuously and
## would work a pond until nothing was left in it.
var _hunger := PiscivoreAppetite.STARTING_HUNGER
var _activity := PiscivoreAppetite.ACTIVITY_HUNT
## Where this bird is building. Chosen once, so nest trips go somewhere
## consistent rather than to a fresh random point each time.
var _nest_site = null
## Re-picked on this interval, so a sated bird moves between things to do
## rather than perching forever.
const ACTIVITY_INTERVAL := 12.0
var _activity_elapsed := 0.0
var _fish_sprite := ProceduralFishSprite.new()
var _cruise_position := Vector2.ZERO


func _ready() -> void:
	add_to_group(HoverTargetFinder.GROUP_NAME)


func setup(world, movement: AmbientFlyerMovement) -> void:
	_world = world
	_movement = movement


## For World's mouse-hover animal-name tooltip.
func get_display_name() -> String:
	return species.capitalize()


func _process(delta: float) -> void:
	_elapsed_time += delta
	if _movement == null:
		return
	_sync_carried_fish()

	_step_appetite(delta)

	if _behavior.phase == PiscivoreBirdBehavior.Phase.CRUISE:
		if _activity == PiscivoreAppetite.ACTIVITY_HUNT:
			_step_hunting(delta)
		else:
			_step_idle_life(delta)
	else:
		# Committed to a strike: hold station horizontally and animate the
		# vertical drop. Carrying rides ABOVE the water rather than in it --
		# the bird has the fish and is leaving with it.
		# A hovering kingfisher TRACKS its fish -- it holds station over the
		# thing it is about to hit, which is also what keeps the strike
		# landing where the fish actually is.
		if (
			_behavior.phase == PiscivoreBirdBehavior.Phase.HOVERING
			and _target_fish != null
			and is_instance_valid(_target_fish)
		):
			_cruise_position = _target_fish.position
			position.x = _cruise_position.x
		var depth := _behavior.dive_progress() * DIVE_DEPTH_PX
		if _behavior.phase == PiscivoreBirdBehavior.Phase.CARRYING:
			depth = -CARRY_LIFT_PX
		position.y = _cruise_position.y + depth
		var was_carrying := _behavior.phase == PiscivoreBirdBehavior.Phase.CARRYING
		var resolved := _behavior.advance(delta)
		if resolved:
			_resolve_strike()
		if was_carrying and _behavior.phase != PiscivoreBirdBehavior.Phase.CARRYING:
			_swallow_catch()


## How far above its cruise line the bird rises while carrying a fish off, and
## how far it will travel to hunt one.
const CARRY_LIFT_PX := 5.0
## Above the bird, so the catch is never hidden behind it.
const CARRIED_FISH_Z_INDEX := 2
const HUNT_RANGE_PX := 220.0
## Close enough to hold station over and strike at.
const STRIKE_DISTANCE_PX := 6.0


## Ages this bird's appetite and, on an interval, decides what it should be
## doing about it (see PiscivoreAppetite).
func _step_appetite(delta: float) -> void:
	_hunger = PiscivoreAppetite.hunger_after(_hunger, delta)
	_activity_elapsed += delta
	# A hungry bird switches to hunting the moment it is hungry; a sated one
	# only re-picks on the interval, so it sticks with what it is doing long
	# enough for the player to see what that is.
	if PiscivoreAppetite.is_hungry(_hunger):
		_activity = PiscivoreAppetite.ACTIVITY_HUNT
		return
	if _activity_elapsed < ACTIVITY_INTERVAL and _activity != PiscivoreAppetite.ACTIVITY_HUNT:
		return
	_activity_elapsed = 0.0
	_activity = PiscivoreAppetite.activity_for(
		_hunger, hash("%d_%d_activity" % [wander_seed, int(_elapsed_time / ACTIVITY_INTERVAL)])
	)


## What a bird does when it is not hungry.
##
## It used to do nothing else at all -- hunting was the whole of its life, so
## between strikes it sat waiting out a cooldown. A sated bird now ranges over
## its territory, sits and digests, or carries material to a nest site.
func _step_idle_life(delta: float) -> void:
	var before := position
	match _activity:
		PiscivoreAppetite.ACTIVITY_PERCH:
			pass  # sitting still and digesting; the wing animation carries it
		PiscivoreAppetite.ACTIVITY_NEST:
			if _nest_site == null:
				# Somewhere of its own, near home but off the water.
				_nest_site = home + Vector2(
					float(absi(hash(wander_seed)) % 64) - 32.0,
					float(absi(hash(wander_seed + 7)) % 64) - 48.0
				)
			var to_nest: Vector2 = _nest_site - position
			if to_nest.length() > 4.0:
				position += to_nest.normalized() * _movement.speed * delta
		_:
			# Patrol: the ordinary wide wander, which is what reads at a
			# distance as a bird going about its day.
			position = _movement.step_position(home, position, _elapsed_time, delta, wander_seed)
	_cruise_position = position
	var moved := position - before
	if moved.length() > 0.001:
		rotation = moved.angle()


## Cruising is now HUNTING: the bird looks for a fish, flies to it, and holds
## station over it before dropping.
##
## It used to wander at random and dive only if that wander happened to carry
## it across water with fish in it -- so a bird whose territory was inland
## essentially never fished (reported: "the kingfisher is mostly stuck in one
## place without fishing anything").
func _step_hunting(delta: float) -> void:
	var before := position
	# Even a hungry bird leaves worked-out water alone (see
	# PiscivoreAppetite.will_hunt) -- this is what actually stops a pond being
	# emptied, rather than merely slowing it down.
	var worth_hunting := false
	if _world != null:
		worth_hunting = PiscivoreAppetite.will_hunt(
			_hunger,
			_world.fish_population_near(position),
			_world.fish_capacity_near(position) if _world.has_method("fish_capacity_near") else 0.0
		)
	var target = (
		_world.nearest_fish_position(position, HUNT_RANGE_PX)
		if _world != null and worth_hunting
		else null
	)
	if target != null and is_instance_valid(target):
		var to_fish: Vector2 = target.position - position
		if to_fish.length() <= STRIKE_DISTANCE_PX:
			_dive_attempts += 1
			if _behavior.begin_hover(hash("%d_%d" % [wander_seed, _dive_attempts])):
				# THIS fish, not whichever is nearest when the strike lands.
				_target_fish = target
			_cruise_position = position
		else:
			position += to_fish.normalized() * _movement.speed * delta
	else:
		position = _movement.step_position(home, position, _elapsed_time, delta, wander_seed)
	_cruise_position = position
	var moved := position - before
	if moved.length() > 0.001:
		rotation = moved.angle()


## The strike lands or it does not, and both are visible: a catch leaves the
## bird carrying a fish, a miss leaves a fish bolting for cover.
func _resolve_strike() -> void:
	if _world == null:
		return
	var fish := _target_fish
	_target_fish = null
	var has_target: bool = fish != null and is_instance_valid(fish)
	if _behavior.did_last_grab_succeed():
		_world.record_fish_catch_near(_cruise_position, 1.0)
		# Taken AT THE FISH, not at where the bird happens to be: the two
		# drift apart over a hover and a dive, and aiming at the bird is why
		# the grab used to come up empty.
		var at: Vector2 = fish.position if has_target else _cruise_position
		var taken: String = _world.catch_nearest_fish(at, STRIKE_DISTANCE_PX * 2.0)
		if taken != "":
			# Fed: a whole inter-meal interval before it is interested again.
			_hunger = PiscivoreAppetite.hunger_after_meal(_hunger)
			_activity_elapsed = ACTIVITY_INTERVAL  # pick something else to do now
		_show_carried_fish(taken != "")
	elif has_target and fish.has_method("bolt_from"):
		# The one that got away actually gets away.
		fish.bolt_from(position)
	elif _world.has_method("startle_fish_near"):
		_world.startle_fish_near(_cruise_position, position, STRIKE_DISTANCE_PX * 2.0)


## A fish visibly in the beak, so a successful strike reads as a catch rather
## than as a bird bobbing.
func _show_carried_fish(caught: bool) -> void:
	if not caught or _carried_fish != null:
		return
	_carried_fish = Sprite2D.new()
	_carried_fish.texture = _fish_sprite.generate_texture("goldfish", wander_seed)
	_carried_fish.scale = Vector2.ONE * ArtResolution.SPRITE_SCALE * FishRenderer.FISH_WORLD_SCALE
	# `top_level`, like the creature health bars and shadows: a plain child
	# would inherit the bird's ROTATION, and this bird rotates to face its
	# flight direction, so the fish would swing around it like a hammer throw.
	# Its position is synced each frame instead (see _sync_carried_fish).
	_carried_fish.top_level = true
	_carried_fish.z_index = CARRIED_FISH_Z_INDEX
	add_child(_carried_fish)
	_sync_carried_fish()


## Keeps the carried fish just under the bird's beak. Manual because the
## sprite is top_level -- see _show_carried_fish.
func _sync_carried_fish() -> void:
	if _carried_fish == null:
		return
	_carried_fish.global_position = global_position + Vector2(0.0, CARRY_LIFT_PX)


func _swallow_catch() -> void:
	if _carried_fish != null:
		_carried_fish.queue_free()
		_carried_fish = null
