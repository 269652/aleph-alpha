extends RefCounted

## Floral scent as a diffusing field (see docs/concept/flora.md#scent-as-a-
## diffusing-field).
##
## Every blooming flower emits scent, and concentration at a point is the SUM
## of every nearby flower's contribution. That superposition is the whole
## point of the system: a dense clump is not merely "more flowers", it is a
## genuinely stronger signal than the same flowers scattered thinly -- which
## is what makes clumping mechanically meaningful, and what gives butterflies
## and bees a reason to gather at meadows instead of wandering uniformly.
##
## Pollinators read the field two ways: spawn rate scales with local
## concentration, and movement biases up its gradient. Nothing places a
## butterfly at a flower -- they accumulate there because that is where the
## signal is strongest.
##
## Honest scope note: real floral scent is a volatile-organic-compound plume
## dispersing with distance and wind. This models the steady-state
## concentration only, not individual molecules or wind advection -- the same
## stylized-approximation stance WaterShader takes for waves, and the right
## fidelity for a top-down tile game.
##
## Pure functions over a plain Array of {"position": Vector2, "species":
## String} dictionaries: no nodes, no RandomNumberGenerator, fully testable
## offline.

const FlowerSpecies = preload("res://src/world/flower_species.gd")

## How far a single flower's scent carries, in tiles. Beyond this it
## contributes exactly nothing, which keeps concentration_at O(nearby) for
## callers that pre-cull rather than O(every flower in the world).
const RADIUS_TILES := 6.0

## Ceiling on how much a rich meadow can multiply pollinator spawning. Real
## meadows do get busier, but an unbounded multiplier would let one huge
## flower field spawn a swarm that never stops growing.
const MAX_SPAWN_MULTIPLIER := 4.0

## How much concentration is needed to reach roughly half of the bonus --
## sets where "a few flowers" becomes "a meadow".
const SPAWN_HALF_POINT := 3.0

## Step used when sampling the field to estimate its gradient, in tiles.
## Small enough to track a patch, large enough not to sit inside a single
## flower's own falloff cusp.
const GRADIENT_SAMPLE_TILES := 1.0


func _init() -> void:
	pass


## A single flower's contribution at `distance_tiles`, as a fraction of its
## own scent strength: full at the source, tapering to nothing at
## RADIUS_TILES. Squared so the falloff is steep near the flower and gentle
## at the fringe, which makes a clump's core read distinctly stronger than
## its edges rather than the patch being a flat plateau.
static func falloff(distance_tiles: float) -> float:
	if distance_tiles >= RADIUS_TILES:
		return 0.0
	var t := 1.0 - clampf(distance_tiles, 0.0, RADIUS_TILES) / RADIUS_TILES
	return t * t


## Total scent at `point` (world pixels): every blooming flower's strength
## scaled by its falloff, summed. `season` gates which species are actually
## advertising (see FlowerSpecies.scent_strength).
static func concentration_at(
	point: Vector2, flowers: Array, season: String, tile_size: float
) -> float:
	if tile_size <= 0.0:
		return 0.0
	var total := 0.0
	for flower in flowers:
		var strength := FlowerSpecies.scent_strength(String(flower["species"]), season)
		if strength <= 0.0:
			continue  # present, but not in bloom -- nothing to smell
		var distance_tiles: float = point.distance_to(flower["position"]) / tile_size
		total += strength * falloff(distance_tiles)
	return total


## A unit vector pointing up the concentration gradient -- the direction a
## pollinator should drift to find a richer patch. Vector2.ZERO where there
## is nothing to smell (or at a perfectly flat spot), so callers can fall
## back to their ordinary wander rather than being nudged by noise.
##
## Estimated by sampling rather than differentiated analytically: the field
## is a sum of many falloff curves, and sampling stays correct if that
## formula is ever retuned.
static func gradient_direction(
	point: Vector2, flowers: Array, season: String, tile_size: float
) -> Vector2:
	var step := GRADIENT_SAMPLE_TILES * tile_size
	var east := concentration_at(point + Vector2(step, 0.0), flowers, season, tile_size)
	var west := concentration_at(point - Vector2(step, 0.0), flowers, season, tile_size)
	var south := concentration_at(point + Vector2(0.0, step), flowers, season, tile_size)
	var north := concentration_at(point - Vector2(0.0, step), flowers, season, tile_size)
	var gradient := Vector2(east - west, south - north)
	if gradient.length() <= 0.0001:
		return Vector2.ZERO
	return gradient.normalized()


## How much more often pollinators should spawn here than over bare ground.
## 1.0 where nothing blooms, rising toward MAX_SPAWN_MULTIPLIER as the field
## thickens -- a saturating curve, so a meadow gets busy but never unbounded.
static func pollinator_spawn_multiplier(concentration: float) -> float:
	if concentration <= 0.0:
		return 1.0
	var saturation := concentration / (concentration + SPAWN_HALF_POINT)
	return 1.0 + (MAX_SPAWN_MULTIPLIER - 1.0) * saturation
