extends Sprite2D

## A single creature: senses its surroundings each frame and acts on them via
## the pure decision modules (CreatureNeeds/CreaturePerception/CreatureBehavior),
## and is damageable. Draws a tiny always-on health sliver above its sprite
## (see _health_bar_*); its name/level/full HP readout lives in a HUD panel
## instead (see CreaturePanel/World._update_creature_panels), not floating
## text attached to the creature in world-space.
##
## Behavior summary: herbivores (calm) graze food terrain, drink at water, and
## flee predators and the player; predators (aggressive) hunt and eat
## herbivores when hungry, attack the player when strong, and flee it when
## weakened. Until setup() is called with a world, a marker just idle-wanders
## (harmless fallback used by tests/tools that don't need full AI).
##
## Known simplifications (see docs/progress.md): sensing is O(nearby creatures)
## per frame with no spatial index; killing prey/being killed doesn't decrement
## the region's aggregate EcosystemSimulation population (it reseeds on the
## next chunk reload); creatures aren't replicated to multiplayer clients.

const CreatureWander = preload("res://src/rendering/creature_wander.gd")
const CreatureInfo = preload("res://src/world/creature_info.gd")
const CreatureNeeds = preload("res://src/gameplay/creature_needs.gd")
const CreaturePerception = preload("res://src/gameplay/creature_perception.gd")
const CreatureBehavior = preload("res://src/gameplay/creature_behavior.gd")
const Health = preload("res://src/gameplay/health.gd")
const LootTable = preload("res://src/gameplay/loot_table.gd")
const Knockback = preload("res://src/gameplay/knockback.gd")
const HealthBar = preload("res://src/gameplay/health_bar.gd")
const AnimalReproduction = preload("res://src/gameplay/animal_reproduction.gd")

## Small always-visible health bar above the sprite.
const HEALTH_BAR_WIDTH := 14.0
const HEALTH_BAR_HEIGHT := 2.0
const HEALTH_BAR_OFFSET_Y := -12.0
const HEALTH_BAR_BG_COLOR := Color(0.1, 0.1, 0.1, 0.85)
const HEALTH_BAR_FILL_COLOR := Color(0.8, 0.15, 0.15)

## Godot group names for spatial queries.
const GROUP_NAME := "creature"
const PLAYER_GROUP := "player"

## How far (pixels) a creature can sense other creatures/players, and how far
## (tiles) it scans terrain for food/water.
const SENSE_RADIUS := 80.0
const SENSE_RADIUS_TILES := 6

## Movement speeds (px/s) for each intent -- fleeing/hunting are urgent and
## faster than a leisurely graze or idle wander (see CreatureWander).
const FLEE_SPEED := 40.0
const HUNT_SPEED := 36.0
const SEEK_SPEED := 28.0

## The expensive part of the AI -- scanning nearby nodes and terrain tiles --
## runs at most this often (seconds), cached in between, rather than every
## frame. Movement is still applied every frame off the cached senses, so it
## stays smooth while keeping per-frame cost low with many creatures loaded.
const SENSE_INTERVAL := 0.25

## Predator melee against the player: reach, damage, and cooldown between hits.
const ATTACK_RANGE := 16.0
const ATTACK_DAMAGE := 6.0
const ATTACK_COOLDOWN := 0.8

## How close a predator must get to a herbivore to catch and eat it, and the
## (one-shot-lethal) damage it deals on catching.
const PREDATION_RANGE := 12.0
const PREDATION_DAMAGE := 1000.0

## How long a knockback shove plays out over, in seconds (Hammerwatch-style
## slide, not an instant teleport -- see Knockback.step).
const KNOCKBACK_DURATION := 0.15

## Bioenergetic condition gained per feeding event (see AnimalReproduction).
## Two-to-three good meals lift a creature over the reproduction threshold.
const FEED_ENERGY := 0.25

## Seconds per animation frame (all actions have 2 frames, see
## ProceduralAnimalAnimation.FRAME_COUNTS).
const ANIMATION_FRAME_DURATION := 0.3

var home := Vector2.ZERO
var wander_seed := 0
var info: CreatureInfo

## Per-action generated frame textures, filled lazily on first use of each
## action (see _animation_step) -- a marker typically only ever plays 2-3 of
## the 5 actions, so generating all upfront would be wasted work.
var _animation_frames: Dictionary = {}  # action String -> Array[ImageTexture]
var _animation := preload("res://src/rendering/procedural_animal_animation.gd").new()
var _current_action := "walk"

var _wander := CreatureWander.new()
var _needs := CreatureNeeds.new()
## Bioenergetic condition (see AnimalReproduction / ecosystem_dynamics.md):
## rises when the creature eats, decays over time, and gates reproduction
## together with health and a birth cooldown. Starts moderate so a fresh herd
## doesn't instantly breed.
var energy := 0.5
var _seconds_since_birth := 0.0
var _perception := CreaturePerception.new()
var _behavior := CreatureBehavior.new()
var _health := Health.new()
var _loot_table := LootTable.new()
var _knockback := Knockback.new()
var _health_bar := HealthBar.new()
var _health_bar_bg: ColorRect
var _health_bar_fill: ColorRect
var _elapsed_time := 0.0
var _attack_cooldown_remaining := 0.0
var _world = null
var _tile_size := 16

var _knockback_remaining := Vector2.ZERO
var _knockback_time_remaining := 0.0

## Throttled-sensing cache (see SENSE_INTERVAL). Starts "due" so the very first
## _process senses immediately rather than idling for a quarter second.
var _sense_accumulator := SENSE_INTERVAL
var _cached_threats: Array = []
var _cached_prey: Array = []
var _cached_food_direction := Vector2.ZERO
var _cached_water_direction := Vector2.ZERO


func _ready() -> void:
	add_to_group(GROUP_NAME)

	_health_bar_bg = ColorRect.new()
	_health_bar_bg.color = HEALTH_BAR_BG_COLOR
	_health_bar_bg.size = Vector2(HEALTH_BAR_WIDTH, HEALTH_BAR_HEIGHT)
	_health_bar_bg.position = Vector2(-HEALTH_BAR_WIDTH / 2.0, HEALTH_BAR_OFFSET_Y)
	add_child(_health_bar_bg)

	_health_bar_fill = ColorRect.new()
	_health_bar_fill.color = HEALTH_BAR_FILL_COLOR
	_health_bar_fill.size = Vector2(HEALTH_BAR_WIDTH, HEALTH_BAR_HEIGHT)
	_health_bar_fill.position = _health_bar_bg.position
	add_child(_health_bar_fill)

	_update_health_bar()


## Gives the creature the world it senses (duck-typed biome_at_global) and the
## tile size, enabling full AI. Without it, _process falls back to wander.
func setup(world, tile_size: int) -> void:
	_world = world
	_tile_size = tile_size


func _process(delta: float) -> void:
	_elapsed_time += delta
	_attack_cooldown_remaining = maxf(0.0, _attack_cooldown_remaining - delta)

	if _knockback_time_remaining > 0.0:
		var result := _knockback.step(_knockback_remaining, _knockback_time_remaining, delta)
		position += result.step
		_knockback_remaining = result.remaining
		_knockback_time_remaining = result.time_remaining
		return  # a shove overrides normal AI movement while it plays out

	if _world == null or info == null:
		_wander_step(delta)
		return

	_needs.advance(delta)
	energy = AnimalReproduction.decay(energy, delta)
	_seconds_since_birth += delta
	_current_action = "walk"  # overridden below by whatever the AI actually does
	_satisfy_needs_in_place()

	# Expensive sensing (node-group scans + terrain tile scans) is throttled and
	# cached; cheap behavior + movement still run every frame off the cache.
	_sense_accumulator += delta
	if _sense_accumulator >= SENSE_INTERVAL:
		_sense_accumulator = 0.0
		_cached_threats = _nearby_in_group(PLAYER_GROUP) + _nearby_threat_creatures()
		_cached_prey = _nearby_prey_creatures()
		_cached_food_direction = _food_direction()
		_cached_water_direction = _water_direction()

	var decision := _behavior.decide({
		"position": position,
		"temperament": info.temperament,
		"is_predator": info.is_predator,
		"health_fraction": info.health / info.max_health,
		"hungry": _needs.is_hungry(),
		"thirsty": _needs.is_thirsty(),
		"threats": _positions_of(_cached_threats),
		"prey": _positions_of(_cached_prey),
		"food_direction": _cached_food_direction,
		"water_direction": _cached_water_direction,
	})

	_apply_decision(decision, _cached_threats, _cached_prey, delta)
	_animation_step()


## Grazing/drinking happen wherever the creature already stands on the right
## terrain -- herbivores eat food biomes, everyone drinks at water. (Predators
## don't graze; they feed by catching prey, handled in _apply_decision.)
func _satisfy_needs_in_place() -> void:
	var tile := _current_tile()
	if _needs.is_thirsty() and _perception.is_on(_world, tile, "water"):
		_needs.drink()
		_current_action = "drink"
	if _needs.is_hungry() and not info.is_predator and _perception.is_on(_world, tile, "food"):
		_needs.feed()
		_gain_energy()
		_current_action = "eat"


## Eating raises bioenergetic condition (see AnimalReproduction) -- called
## wherever the creature actually feeds (grazing, dropped fruit, or predation).
func _gain_energy() -> void:
	energy = AnimalReproduction.feed(energy, FEED_ENERGY)


## Whether this creature is in condition to reproduce right now: well-fed,
## healthy, and past its birth cooldown (see AnimalReproduction / the
## bioenergetics section of concept/ecosystem_dynamics.md). World checks this
## for near creatures and spawns an offspring when true.
func can_reproduce() -> bool:
	if info == null or info.max_health <= 0.0:
		return false
	return AnimalReproduction.can_reproduce(energy, info.health / info.max_health, _seconds_since_birth)


## Called by World after this creature births an offspring: pays the energy
## cost (dropping it below the threshold) and restarts the birth cooldown, so
## it can't immediately breed again.
func on_reproduced() -> void:
	energy = AnimalReproduction.energy_after_birth(energy)
	_seconds_since_birth = 0.0


## Called by the world loop when this creature consumes a dropped food ground
## item (see World._step_herbivore_food_consumption) -- trees feed animals.
func on_ate_food() -> void:
	_needs.feed()
	_gain_energy()
	_current_action = "eat"


## Swaps the sprite among this action's generated frames (see
## ProceduralAnimalAnimation): walking legs alternate, attacks lunge, eating/
## drinking dips the head, swimming bobs half-submerged. The action itself is
## set as a side effect of what the AI actually did this frame (_apply_decision/
## _satisfy_needs_in_place), with an on-water check overriding to "swim".
func _animation_step() -> void:
	if info == null:
		return
	if _world != null and _perception.is_on(_world, _current_tile(), "water"):
		_current_action = "swim"

	if not _animation_frames.has(_current_action):
		_animation_frames[_current_action] = _animation.generate_textures(
			info.species, _current_action, wander_seed
		)
	var frames: Array = _animation_frames[_current_action]
	texture = frames[int(_elapsed_time / ANIMATION_FRAME_DURATION) % frames.size()]


func _apply_decision(decision: Dictionary, threats: Array, prey: Array, delta: float) -> void:
	match decision.intent:
		"flee":
			position += decision.direction * FLEE_SPEED * delta
		"attack":
			position += decision.direction * HUNT_SPEED * delta
			_try_attack(_nearest_node(threats))
			_current_action = "attack"
		"hunt":
			position += decision.direction * HUNT_SPEED * delta
			_try_eat(_nearest_node(prey))
			_current_action = "attack"
		"seek_water":
			position += decision.direction * SEEK_SPEED * delta
		"seek_food":
			position += decision.direction * SEEK_SPEED * delta
		"search_water", "search_food":
			# Need exists but the resource isn't in sight -- range outward to
			# look for it, rather than orbiting home like idle wander.
			position += _wander.roam_direction(_elapsed_time, wander_seed) * SEEK_SPEED * delta
		_:
			_wander_step(delta)


func _try_attack(target: Node) -> void:
	if target == null or _attack_cooldown_remaining > 0.0:
		return
	if position.distance_to(target.position) > ATTACK_RANGE:
		return
	if target.has_method("take_damage"):
		target.take_damage(ATTACK_DAMAGE)
		_attack_cooldown_remaining = ATTACK_COOLDOWN


func _try_eat(target: Node) -> void:
	if target == null:
		return
	if position.distance_to(target.position) > PREDATION_RANGE:
		return
	if target.has_method("take_damage"):
		target.take_damage(PREDATION_DAMAGE)
	_needs.feed()
	_gain_energy()


func _wander_step(delta: float) -> void:
	position = _wander.step_position(home, position, _elapsed_time, delta, wander_seed)


func _current_tile() -> Vector2i:
	return Vector2i(floori(position.x / _tile_size), floori(position.y / _tile_size))


func _food_direction() -> Vector2:
	if not _needs.is_hungry() or info.is_predator:
		return Vector2.ZERO
	return _perception.nearest_direction(_current_tile(), _world, SENSE_RADIUS_TILES, "food")


func _water_direction() -> Vector2:
	if not _needs.is_thirsty():
		return Vector2.ZERO
	return _perception.nearest_direction(_current_tile(), _world, SENSE_RADIUS_TILES, "water")


func _nearby_in_group(group: String) -> Array:
	var result: Array = []
	for node in get_tree().get_nodes_in_group(group):
		if node == self:
			continue
		if position.distance_to(node.position) <= SENSE_RADIUS:
			result.append(node)
	return result


## Other creatures within sense range that are predators to me (a herbivore's
## threats). Predators aren't threatened by other creatures, only by the player.
func _nearby_threat_creatures() -> Array:
	if info.is_predator:
		return []
	var result: Array = []
	for node in _nearby_in_group(GROUP_NAME):
		if node.info != null and node.info.is_predator:
			result.append(node)
	return result


## Herbivores within sense range that a predator can hunt.
func _nearby_prey_creatures() -> Array:
	if not info.is_predator:
		return []
	var result: Array = []
	for node in _nearby_in_group(GROUP_NAME):
		if node.info != null and not node.info.is_predator:
			result.append(node)
	return result


## Cached node lists can span several frames (see SENSE_INTERVAL); a cached
## target may have been freed (eaten/killed) since -- skip invalid instances.
func _positions_of(nodes: Array) -> Array:
	var positions: Array = []
	for node in nodes:
		if is_instance_valid(node):
			positions.append(node.position)
	return positions


func _nearest_node(nodes: Array) -> Node:
	var best: Node = null
	var best_distance := -1.0
	for node in nodes:
		if not is_instance_valid(node):
			continue
		var distance := position.distance_squared_to(node.position)
		if best == null or distance < best_distance:
			best = node
			best_distance = distance
	return best


## Reduces info.health; on death, drops the species' loot into the world (via
## WorldItemBus, so world.gd spawns the ground items) and frees this marker.
func take_damage(amount: float) -> void:
	if info == null:
		return
	info.health = _health.take_damage(info.health, amount)
	_update_health_bar()
	if _health.is_dead(info.health):
		_drop_loot()
		queue_free()


func _update_health_bar() -> void:
	if info == null or _health_bar_fill == null:
		return
	_health_bar_fill.size.x = _health_bar.fill_width(info.health, info.max_health, HEALTH_BAR_WIDTH)


func _drop_loot() -> void:
	for stack in _loot_table.drops_for(info.species):
		WorldItemBus.item_dropped.emit(stack, position)


## Starts a shove of `force` total displacement, played out smoothly over
## KNOCKBACK_DURATION (see _process/Knockback.step) rather than teleporting
## instantly. A knockback already in progress is replaced by the new one.
func apply_knockback(force: Vector2) -> void:
	_knockback_remaining = force
	_knockback_time_remaining = KNOCKBACK_DURATION
