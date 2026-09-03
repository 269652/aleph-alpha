extends Sprite2D

const PixelNoise = preload("res://src/rendering/pixel_noise.gd")

## A swimming pond/ocean fish -- deliberately lightweight compared to
## CreatureMarker: no needs/perception/behavior AI, just CreatureWander's pure
## idle-drift pattern (see creature_wander.gd) confined to water tiles, so a
## small pond's fish read as "alive" without wandering up onto the grass.
## Caught via Player's fishing rod interaction (see FishRenderer,
## EarthChunkManager's fish spawn/despawn wiring).

const CreatureWander = preload("res://src/rendering/creature_wander.gd")
const HoverTargetFinder = preload("res://src/rendering/hover_target_finder.gd")
const SimulationLod = preload("res://src/gameplay/simulation_lod.gd")

## How much open water the fish keeps around its center on every side --
## roughly the sprite's half-extent, so no part of the fish visually overlaps
## the beach regardless of which way it's pointing (the reported "stranded at
## the shoreline" look was its flank/nose hanging over land while the center
## was still on the last water pixel). Pinned by
## test_fish_clearance_keeps_it_clear_of_the_waterline.
const CLEARANCE_PX := 6.0

## The compass points around a candidate position that must all be water for
## the move to count (see CLEARANCE_PX).
const _CLEARANCE_PROBES: Array[Vector2] = [
	Vector2(CLEARANCE_PX, 0), Vector2(-CLEARANCE_PX, 0),
	Vector2(0, CLEARANCE_PX), Vector2(0, -CLEARANCE_PX),
]

## Headings tried in order when the current heading would beach the fish:
## straight first, then increasingly sharp deflections to either side, then a
## full reversal -- so a fish meeting the shore slides along it (or turns
## back) instead of freezing in place for the whole direction interval.
const _DEFLECTION_TURNS: Array[float] = [
	0.0, PI / 4.0, -PI / 4.0, PI / 2.0, -PI / 2.0, 3.0 * PI / 4.0, -3.0 * PI / 4.0, PI
]

## How far ahead (px) the fish's WANDER TARGET is checked for open water,
## before the heading is smoothed toward it -- a fixed lookahead, independent
## of delta/speed, so the shore is anticipated a beat early instead of being
## reacted to right as it's reached. Without this, a wander/attraction target
## that kept re-pointing at the shore pulled the smoothed heading straight
## back toward land every single frame even while the MOVEMENT step below
## kept deflecting it away again right after -- pull-then-deflect, every
## frame, read as flickering right at the water's edge (reported: "avoid
## trying to turn into the border of the water so that the fish doesn't
## flicker when repelled from the edge").
const _SHORE_LOOKAHEAD_PX := 24.0

## How fast a fish can turn to face a new heading, in radians/sec.
## CreatureWander's own target heading only changes once per
## DIRECTION_CHANGE_INTERVAL (1.5s) -- applying it instantly made a fish swim
## in a dead-straight line for a second and a half, then teleport its
## heading, which read as robotic rather than swimming (the reported "still
## don't move naturally"). Turning gradually toward the target instead, and
## rotating the sprite to face it, reads as a fish actually steering. Pinned
## by test_heading_turn_rate_is_bounded_per_frame.
const TURN_RATE := 3.0

var home := Vector2.ZERO
var wander_seed := 0
var species := "goldfish"

var _wander := CreatureWander.new()
var _elapsed_time := 0.0
var _world = null
var _tile_size := 16

## How often a swimming fish spawns a water-ripple disturbance (see
## EarthChunkManager.record_water_disturbance).
##
## Unhurried on purpose: a fish glides, it doesn't thrash, so its surface
## trace is an occasional swirl rather than a continuous churn. It is also
## the single biggest consumer of the shared, fixed-size disturbance buffer
## -- there are many fish and only one player -- and at 0.4s they crowded
## every other wake out of it so fast that nothing was visible at all.
##
## A RANGE rather than one constant, and each fish additionally starts at its
## own phase (see ripple_phase_offset): with a fixed interval and a shared
## zero start, an entire shoal fired its rings on the same tick forever,
## which reads as a mechanism rather than as wildlife.
##
## Widened again, 1.1-2.6 -> 6.0-12.0, once "unhurried" turned out to still
## not be unhurried ENOUGH (reported live, from the diorama's small,
## always-visible pond, once its fish first ran through this real timing:
## "the fish still produce ripples all the time -- only fast move flap boost
## should produce ripples like in the real ingame"). The correlation
## (a ripple only ever fires inside a flap burst -- see _step_water_ripple)
## was already correct; what wasn't checked before is whether bursts
## themselves are RARE enough relative to how long one stays visible.
## WaterShader.RIPPLE_LIFETIME (2.2s) means a burst's own last ring is still
## fading 0.6 + 2.2 = 2.8s after the burst starts -- at the old 1.1-2.6s
## range, the NEXT burst was scheduled to start before that decay even
## finished, so consecutive bursts' visible rings overlapped almost every
## time (measured directly on a real running fish, not just estimated:
## visibly quiet only 4% of the time). Test-pinned against that exact
## relationship, not eyeballed: test_ripples_stay_occasional_not_continuous_
## by_the_numbers derives the expected visible fraction straight from these
## constants + RIPPLE_LIFETIME, and test_a_swimming_fish_actually_goes_
## quiet_between_bursts_most_of_the_time simulates several real minutes of
## continuous swimming and measures it directly, so any future change to
## either side of this relationship (burst timing, or WaterShader's own
## fade duration) gets re-checked automatically.
const RIPPLE_INTERVAL_MIN := 6.0
const RIPPLE_INTERVAL_MAX := 12.0

## Where this fish is in its ripple cycle when it first starts swimming, so
## a shoal spawned on the same frame does not pulse in unison. Bounded by one
## full maximum interval -- any more would just wrap.
static func ripple_phase_offset(seed_value: int) -> float:
	return PixelNoise.unit(seed_value, 101, 0) * RIPPLE_INTERVAL_MAX


## The wait before this fish's `index`-th ripple. Varies per fish AND along
## each fish's own sequence, so no fish is metronomic and no two share a
## rhythm.
static func ripple_interval(seed_value: int, index: int) -> float:
	var unit := PixelNoise.unit(seed_value, 202, index)
	return RIPPLE_INTERVAL_MIN + (RIPPLE_INTERVAL_MAX - RIPPLE_INTERVAL_MIN) * unit
var _water_ripple_accumulator := 0.0
## Negative until this fish's first swim step has staggered it (see
## _step_water_ripple); it cannot be seeded at construction because
## wander_seed is assigned afterwards.
var _water_ripple_interval := -1.0
var _ripple_index := 0

## A single tail wag isn't one poke at the surface -- it's several quick
## strokes in a row, which is what actually reads as "wagging" and leaves a
## short streak/wake behind the fish (reported: "It should produce a streak
## of rings but only when wagging the tail, so that the interference creates
## a forward pattern, just like when the player walks through water").
## Deliberately short and tight so a whole burst still counts as roughly one
## entry against the unhurried ripple budget above (RIPPLE_INTERVAL_MIN's own
## doc comment on the shared disturbance buffer) -- a cluster of closely
## spaced rings, not a sustained churn. Spacing widened per a follow-up
## request ("slower bursts please").
const TAIL_WAG_RING_COUNT := 3
const TAIL_WAG_RING_SPACING := 0.3

## How much faster a fish swims WHILE a wag burst is in flight -- the actual
## fast tail flap driving the ring streak, not just cosmetic timing (reported
## follow-up: "also only when they flap tail fast"). The rest of the time a
## fish just glides at CreatureWander.WANDER_SPEED.
const FLAP_SPEED_MULTIPLIER := 2.0

## >0 while a burst is playing out; counts down one ring at a time.
var _wag_rings_remaining := 0
var _wag_spacing_accumulator := 0.0
## True for exactly the frames _wag_rings_remaining was >0 BEFORE this
## frame's ripple step ran -- read by _process to speed up movement during a
## flap. Captured separately from _wag_rings_remaining itself because that
## counter is decremented mid-step, before _process gets a chance to read it.
var _is_flapping := false

## The fish's own position the last time _step_water_ripple ran -- null
## (unset) until the first call, since "did it move" needs a prior sample.
## Mirrors Player._step_water_ripples' own gate on genuinely moving through
## the water: a fish that can't move (boxed into a single water tile) must
## never ripple, no matter how long it sits there.
var _last_ripple_check_position: Variant = null
## The fish's smoothed swim heading -- turns gradually toward CreatureWander's
## target each frame (see TURN_RATE) rather than snapping to it, and drives
## the sprite's rotation so the fish visibly faces the way it's swimming.
var _current_heading := Vector2.RIGHT

## A world position this fish steers toward instead of its normal wander
## target (see EarthChunkManager.set_attraction_point, driven by a cast
## fishing line -- Player._fishing_step) -- null for "no attraction, wander
## normally". Still goes through the same turn-rate smoothing and shore
## deflection as ordinary wandering, so an attracted fish steers in, not
## teleports, and never follows a lure up onto the beach.
var attract_target = null

## Once within this many pixels of attract_target, resume normal wandering
## instead of trying to close the last few pixels exactly (avoids jittering
## in place on top of the target).
const _ATTRACTION_STOP_DISTANCE := 6.0


## For World's mouse-hover animal-name tooltip.
func get_display_name() -> String:
	return species.capitalize()


func _ready() -> void:
	add_to_group(HoverTargetFinder.GROUP_NAME)
	# World gathers every fish each frame as a flow-overlay wader, so a
	# fish ripples the still water it swims in (docs/concept/hydrology.md).
	add_to_group("fish")


func set_attraction(target: Vector2) -> void:
	attract_target = target


func clear_attraction() -> void:
	attract_target = null


## `world` (duck-typed biome_at_global, same contract as CreatureMarker.setup)
## lets the fish check a candidate step is still over water before committing
## to it. Left unset (default null), the fish swims unconfined -- the same
## isolated-test fallback CreatureMarker uses.
func setup(world, tile_size: int) -> void:
	_world = world
	_tile_size = tile_size


## Overrides the wander scale this fish's own unconfined swimming uses (see
## CreatureWander.wander_radius/wander_speed's own doc comment) -- for a
## caller whose water body is much smaller than the real world's own
## WANDER_RADIUS, most obviously the character preview diorama's pond.
func configure_wander(radius: float, speed: float) -> void:
	_wander.wander_radius = radius
	_wander.wander_speed = speed


## Advances this fish through exactly the SAME unconfined wander _process
## already runs whenever _world is null (see that branch below, which calls
## _step_unconfined_wander directly since ITS OWN _elapsed_time/ripple step
## already ran once in _process's shared preamble) -- exposed as a public
## method so a caller that keeps this fish's own _process disabled
## (set_process(false), the character preview diorama's own convention for
## every fish it places -- its real WANDER_RADIUS/pond-size mismatch means
## it must drive fish manually rather than let them free-run) can still step
## it through the real algorithm once per frame, instead of reimplementing
## swimming from scratch (reported live: "fish don't swim like in the real
## game" -- the diorama's own point-to-point movement never was this
## algorithm at all). Unlike _process's branch, this owns its own
## _elapsed_time/ripple advance -- nothing else is ticking this fish's
## clock for it.
func step_wander(delta: float) -> void:
	_elapsed_time += delta
	_step_water_ripple(delta)
	_step_unconfined_wander(delta)


func _step_unconfined_wander(delta: float) -> void:
	var before := position
	position = _wander.step_position(home, position, _elapsed_time, delta, wander_seed)
	_face_along(position - before)


## A fish is always "swimming" (it's a fish), but it doesn't always have
## open water to actually push through -- gated on genuinely having moved
## since the last call (see _last_ripple_check_position), the same
## requirement Player._step_water_ripples applies to the player. Each trigger
## starts a short TAIL_WAG_RING_COUNT-ring burst (see that constant's doc
## comment) rather than firing a single ring.
func _step_water_ripple(delta: float) -> void:
	if _world == null:
		_is_flapping = false
		return

	if _wag_rings_remaining > 0:
		# A burst already in flight plays out on its own clock, independent
		# of the movement gate below -- only STARTING a new one is gated on
		# actually moving. Still flapping for this whole frame, even on the
		# tick that empties the counter below (the ring/speed-up belongs to
		# THIS frame, not next frame).
		_is_flapping = true
		_wag_spacing_accumulator += delta
		if _wag_spacing_accumulator >= TAIL_WAG_RING_SPACING:
			_wag_spacing_accumulator = 0.0
			_emit_ripple()
			_wag_rings_remaining -= 1
		return

	var moved: bool = _last_ripple_check_position != null and position != _last_ripple_check_position
	_last_ripple_check_position = position
	if not moved:
		_water_ripple_accumulator = 0.0  # no gliding credit while genuinely stationary
		_is_flapping = false
		return

	if _water_ripple_interval < 0.0:
		# First swim step. Staggered here rather than in _init because
		# wander_seed is assigned by the renderer AFTER construction, so it
		# isn't known yet at build time.
		_water_ripple_accumulator = ripple_phase_offset(wander_seed)
		_water_ripple_interval = ripple_interval(wander_seed, 0)
	_water_ripple_accumulator += delta
	if _water_ripple_accumulator < _water_ripple_interval:
		_is_flapping = false
		return
	_water_ripple_accumulator = 0.0
	_ripple_index += 1
	# Re-roll the wait every time, so this fish's own rhythm is irregular
	# rather than a fixed tick.
	_water_ripple_interval = ripple_interval(wander_seed, _ripple_index)
	_wag_rings_remaining = TAIL_WAG_RING_COUNT
	_wag_spacing_accumulator = 0.0
	_is_flapping = true
	_emit_ripple()
	_wag_rings_remaining -= 1


func _emit_ripple() -> void:
	if _world.has_method("record_water_disturbance"):
		_world.record_water_disturbance(position)


## How fast, and for how long, a startled fish bolts.
##
## A missed strike has to be legible from the water's side too: the fish that
## got away should visibly get away, in a fast straight burst quite unlike its
## usual meander (see PiscivoreBirdMarker).
const BOLT_SPEED := 90.0
const BOLT_SECONDS := 0.9
## A startled fish snaps around instead of easing into its turn.
const BOLT_TURN_MULTIPLIER := 6.0

var _bolt_direction := Vector2.ZERO
var _bolt_remaining := 0.0


## Startles this fish into a fast dash directly away from `threat`.
func bolt_from(threat: Vector2) -> void:
	var away := position - threat
	if away.length() < 0.001:
		# Directly underneath: any direction beats normalising a zero vector,
		# which is the ill-conditioned step behind this project's old
		# flee-jitter bugs.
		away = Vector2.UP
	_bolt_direction = away.normalized()
	_bolt_remaining = BOLT_SECONDS


## Whether this fish is currently fleeing -- the caller skips its ordinary
## wander while it is.
func is_bolting() -> bool:
	return _bolt_remaining > 0.0


## Distance-based update rate (see SimulationLod; mirrors CreatureMarker's and
## AmbientFlyerMarker's own _lod_step). Returns the time to advance by, or
## NEGATIVE when this frame should be skipped entirely.
##
## There are many fish in every loaded chunk and almost none of them are ever
## on screen (the same case SimulationLod's own doc comment makes for
## creatures generally), so a fish far from the player advances in fewer,
## larger steps instead of paying full per-frame cost for swim/shore/ripple
## logic nobody is close enough to see.
##
## Negative rather than zero as the skip signal, because zero is a legitimate
## step (a caller passing 0.0 expects state to settle, not to be ignored).
## The accumulated time is handed to the update when it does run, so a
## skipped frame is never LOST time -- a fish far from the player still lives
## at exactly the same rate, just in fewer, larger steps.
var _lod_accumulated := 0.0

func _lod_step(delta: float) -> float:
	_lod_accumulated += delta
	var player = _nearest_player_position()
	if player == null:
		return _take_lod_step()  # nobody to be far from: always full rate
	var interval := SimulationLod.update_interval(position.distance_to(player))
	if _lod_accumulated < interval:
		return -1.0
	return _take_lod_step()


func _take_lod_step() -> float:
	var step := _lod_accumulated
	_lod_accumulated = 0.0
	return step


## Cheap: the player group holds one node in solo play. Cached per frame by
## the caller rather than scanned per fish would be better still, but this is
## already off the hot path for everything nearby.
func _nearest_player_position():
	# Not in the tree (a marker built standalone in a test) means there is no
	# player to measure against, so it runs at full rate.
	if not is_inside_tree():
		return null
	# Cache the player node so this LOD-distance check (run every frame for
	# every fish) doesn't re-query the whole "player" group each time -- just
	# re-look-up when the cached ref is gone (player despawn/respawn).
	if _cached_player == null or not is_instance_valid(_cached_player):
		var players := get_tree().get_nodes_in_group("player")
		if players.is_empty():
			return null
		_cached_player = players[0]
	return _cached_player.position


var _cached_player: Node = null


func _process(frame_delta: float) -> void:
	# Fish far from the player advance in fewer, larger steps (see
	# SimulationLod) -- same time passes, fewer updates to pay for.
	var delta := _lod_step(frame_delta)
	if delta < 0.0:
		return
	if _bolt_remaining > 0.0:
		_bolt_remaining -= delta

	_elapsed_time += delta
	_step_water_ripple(delta)
	if _world == null:
		_step_unconfined_wander(delta)
		return

	# Turn the swim heading gradually toward the target rather than snapping
	# straight to it (see TURN_RATE) -- either an active attraction (a cast
	# line nearby) once far enough from it to matter, or ordinary wandering.
	var target: Vector2
	if _bolt_remaining > 0.0:
		# Fleeing a kingfisher: a hard heading away from the threat, but
		# still just a HEADING. The first version moved the fish directly and
		# returned early, skipping the shore-clearance machinery below --
		# so a startled fish shot straight out of the water and flopped
		# across the grass, with the bird then calmly following it onto land
		# to eat it (reported exactly that way). A panicking fish still
		# cannot leave the water.
		target = _bolt_direction
	elif attract_target != null and position.distance_to(attract_target) > _ATTRACTION_STOP_DISTANCE:
		target = (attract_target - position).normalized()
	else:
		target = _wander.direction_at(home, position, _elapsed_time, wander_seed)

	# Bias the TARGET itself away from land before smoothing toward it -- see
	# _SHORE_LOOKAHEAD_PX's doc comment. Deflection search starts from the
	# RAW target when that's already safe (the common case), but from the
	# fish's OWN current heading once it isn't -- restarting the search from
	# the raw (blocked) target fresh every frame picked whichever nearby
	# deflection happened to clear THAT frame, which could differ from last
	# frame's pick right at a boundary and flicker; searching outward from
	# where the fish is ALREADY safely facing instead finds the same stable
	# answer (turn 0 = keep facing that way) every frame until the
	# constraint genuinely changes. Falls back to the raw target unchanged
	# if nothing clears at all (e.g. a tiny embayment); the movement step's
	# own deflection below still catches that case.
	var deflection_base := target
	if not _has_water_clearance(position + target * _SHORE_LOOKAHEAD_PX):
		deflection_base = _current_heading
	var safe_target := _first_clear_heading(deflection_base, position, _SHORE_LOOKAHEAD_PX)
	if safe_target != Vector2.ZERO:
		target = safe_target

	# A startled fish snaps around rather than easing into the turn -- the
	# whole point of a bolt is that it is sudden.
	var turn_rate := TURN_RATE * (BOLT_TURN_MULTIPLIER if _bolt_remaining > 0.0 else 1.0)
	_current_heading = Vector2.from_angle(
		lerp_angle(_current_heading.angle(), target.angle(), clampf(turn_rate * delta, 0.0, 1.0))
	)

	# A real fast tail flap propels the fish faster than an ordinary glide
	# (see FLAP_SPEED_MULTIPLIER/_is_flapping) -- not just a faster ring
	# cadence. _wander.wander_speed, not the bare CreatureWander.WANDER_SPEED
	# constant -- this is the ONE place in the world-aware _process branch
	# that reads a raw speed rather than going through _wander itself, so a
	# caller overriding wander_speed (configure_wander -- the character
	# preview diorama's own pond, far smaller than any real water body) was
	# silently ignored here even though direction_at/wander_radius already
	# honored the override; the fish's own visible speed stayed real-ocean
	# fast regardless (reported live, alongside the diorama switching this
	# fish onto its real _process for the first time: "fish still don't
	# move natural like ingame").
	var speed := _wander.wander_speed * (FLAP_SPEED_MULTIPLIER if _is_flapping else 1.0)
	if _bolt_remaining > 0.0:
		speed = BOLT_SPEED  # the dash that makes an escape read as an escape

	# Try the (now-smoothed, already shore-biased) heading first; if any part
	# of the fish would still end up over land there, deflect through
	# _DEFLECTION_TURNS until one keeps the whole sprite wet -- and COMMIT
	# that deflection as the new heading, so a fish sliding along a shore
	# visibly turns instead of jumping between unrelated angles frame to
	# frame.
	var safe_heading := _first_clear_heading(_current_heading, position, speed * delta)
	if safe_heading == Vector2.ZERO:
		return  # fully enclosed (a 1-tile pond) -- nowhere clear to go
	position += safe_heading * speed * delta
	_current_heading = safe_heading
	rotation = safe_heading.angle()


## The first heading -- trying `base_heading` itself, then each
## _DEFLECTION_TURNS deflection off it, in order -- that keeps the whole
## fish clear of land `probe_distance` px ahead of `from_position`.
## Vector2.ZERO if none does (fully enclosed water, e.g. a 1-tile pond).
## Shared by both the target-smoothing bias (a longer, fixed lookahead) and
## the actual movement step (a short, delta-scaled one) so shore-avoidance
## is computed the same way in both places -- see _SHORE_LOOKAHEAD_PX's doc
## comment on why the two used to disagree and flicker.
func _first_clear_heading(base_heading: Vector2, from_position: Vector2, probe_distance: float) -> Vector2:
	for turn in _DEFLECTION_TURNS:
		var heading := base_heading.rotated(turn)
		if _has_water_clearance(from_position + heading * probe_distance):
			return heading
	return Vector2.ZERO


## Faces the sprite along an actual movement delta -- used by the unconfined
## (no-world) fallback, which doesn't compute a heading of its own.
func _face_along(movement: Vector2) -> void:
	if movement.length() > 0.001:
		_current_heading = movement.normalized()
		rotation = _current_heading.angle()


## True when `center` and every CLEARANCE_PX compass probe around it are over
## water -- i.e. the whole sprite would sit visibly in the water there.
func _has_water_clearance(center: Vector2) -> bool:
	if not _is_water(center):
		return false
	for probe in _CLEARANCE_PROBES:
		if not _is_water(center + probe):
			return false
	return true


func _is_water(pixel_position: Vector2) -> bool:
	var tile_x := int(floor(pixel_position.x / _tile_size))
	var tile_y := int(floor(pixel_position.y / _tile_size))
	return _world.biome_at_global(tile_x, tile_y) == "ocean"
