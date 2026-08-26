extends RefCounted

## Walk-to-a-point-then-pick-a-new-one behavior for the character preview
## diorama's ambient stroll (see docs/concept/character_creator_preview_
## scene.md) -- the same shape CreatureWander/creature_movement_gate.gd
## already use for ambient creature movement in the real world, scaled
## down to one character in a small pen. Pure: no nodes, no Godot-specific
## state beyond plain Vector2/Rect2 math, so CharacterPreviewDiorama (the
## only Godot-coupled piece) can drive an actual CharacterView from it
## without this class knowing CharacterView exists.

## How close counts as "reached" -- world units. Not zero: a real target
## would take longer and longer to truly hit exactly as floating-point
## steps shrink toward it, so an arrival radius is what actually lets the
## stroll move on to a new target in finite time.
const ARRIVAL_RADIUS := 2.0

## A plausible ambient walking pace, world units/second -- for reference,
## CharacterView's own WALK_CYCLE_SPEED animates the leg swing at a fixed
## cadence regardless of how fast the node's .position itself moves, so
## this only has to look reasonable, not match any other constant exactly.
const WALK_SPEED := 8.0


## `position` moved toward `target` by `speed * delta` world units, never
## overshooting past `target` in a single step (a large delta -- a lag
## spike, or a low-framerate diorama tucked in a menu -- must still land
## exactly ON the target, not fly past it and start oscillating).
static func advance(position: Vector2, target: Vector2, delta: float, speed: float = WALK_SPEED) -> Vector2:
	var to_target := target - position
	var distance := to_target.length()
	if distance <= 0.001:
		return position
	var step := speed * delta
	if step >= distance:
		return target
	return position + to_target.normalized() * step


## Whether `position` is close enough to `target` to count as arrived (see
## ARRIVAL_RADIUS's own doc comment).
static func has_arrived(position: Vector2, target: Vector2) -> bool:
	return position.distance_to(target) <= ARRIVAL_RADIUS


## A new random target within `bounds` (world units) -- `rng` is an
## injected RandomNumberGenerator rather than Godot's global RNG so a
## caller that wants reproducible ambient motion (or a test) can seed it,
## the same seeded-RNG convention this codebase's other placement/roll
## logic already follows.
static func pick_target(bounds: Rect2, rng: RandomNumberGenerator) -> Vector2:
	return Vector2(
		rng.randf_range(bounds.position.x, bounds.position.x + bounds.size.x),
		rng.randf_range(bounds.position.y, bounds.position.y + bounds.size.y)
	)


## A random point strictly within `radius` of `center` -- for anything
## confined to a genuinely ROUND area (a pond), where pick_target's own
## square Rect2 would overshoot the boundary at its corners by a factor of
## sqrt(2). sqrt(rng) on the radius, not a plain uniform roll, so points
## land evenly across the disc's own AREA rather than bunching toward the
## centre -- a thin ring near the edge covers far more area than an equally
## thin ring near the centre, and a uniform radius roll would sample both
## just as often. The same formula CharacterPreviewLayout.generate() already
## used inline for the pond's fish spawn positions, pulled out here so
## CharacterPreviewDiorama's own ongoing fish-target picking can share it
## instead of quietly disagreeing on shape (reported live: "fish are still
## spawned on land" -- a fish's own wander TARGET, picked from a square,
## could land up to 41% further from the pond's centre than its spawn point
## ever could).
static func random_point_in_circle(center: Vector2, radius: float, rng: RandomNumberGenerator) -> Vector2:
	var angle := rng.randf_range(0.0, TAU)
	var sampled_radius := sqrt(rng.randf()) * radius
	return center + Vector2(cos(angle), sin(angle)) * sampled_radius
