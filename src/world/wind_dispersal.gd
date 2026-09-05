extends RefCounted

## Where the wind puts a seed (see docs/concept/seed_dispersal.md).
##
## Pure and engine-free: this answers "how far and which way", and the caller
## decides whether anything can actually grow where it lands.

const PixelNoise = preload("res://src/rendering/pixel_noise.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

## ## Weight classes
##
## Weight is the single property that decides how far a seed travels, and it is
## the whole reason plants have different seeds: a dandelion seed and an acorn
## fall from the same height in the same wind and land a hundred metres apart.
## That difference is why meadows colonise faster than woods.
##
## Expressed as a terminal-velocity analogue -- lower is lighter and drifts
## further -- in the order the real seeds fall.
const WEIGHT_FLOWER_SEED := 0.08  # plumed or dust-fine, built for wind
## A fallen leaf (see docs/concept/leaf_litter.md's wind-driven relocation
## section), NOT a seed at all -- reused here anyway because a settled
## leaf being nudged along the ground by ambient wind is the same
## lightness-vs-force question this file already answers for seeds. Placed
## above WEIGHT_FLOWER_SEED (a leaf's flat blade is not a real wind-
## dispersal adaptation like a dandelion's own plume) but below
## WEIGHT_BERRY_PIP (a leaf's large surface-area-to-mass ratio still makes
## it tumble and skitter across open ground far more readily than a small,
## solid pip -- an ordinary autumn breeze, not a gale). Pinned by
## test_a_leaf_sits_between_a_flower_seed_and_a_berry_pip.
const WEIGHT_LEAF := 0.15
const WEIGHT_BERRY_PIP := 0.3  # small, but no plume
const WEIGHT_TREE_FRUIT := 0.7  # carried by animals, not air
const WEIGHT_NUT := 1.0  # drops within a crown-width, always

## How far the wind can carry the lightest seed at full strength, in tiles.
const MAX_DRIFT_TILES := 20.0

## How far the LIGHTEST seed scatters with no wind at all -- it still has to
## land somewhere, it just does not go far. Independent of the wind's
## direction and strength, so a dead calm does not stack every seed on the
## parent.
const CALM_SCATTER_TILES := 4.0

## How much of that still-air scatter the HEAVIEST seed gets.
##
## Still air is not still, and the difference matters: a plume goes somewhere
## on the faintest movement of the air -- that is what a plume is FOR -- while
## an acorn drops through it and lands under the tree. The calm scatter used
## to be weight-blind, so on a still day a dandelion seed and an acorn fell
## into the same little circle. That was not a cosmetic error: a prevailing
## wind is a breeze rather than a gale, so this term is most of what decides
## how far apart plants end up standing (see FlowerEstablishment), and with it
## weight-blind and small, a flower's whole lineage piled onto its parent and
## exactly one plant grew there. Reported as flowers "growing way too dense"
## with too little "space between individual flowers".
##
## Calibrated so the heaviest class keeps EXACTLY the drop it always had
## (0.3 x 4.0 = the old 1.2 tiles, a crown-width, pinned by test) -- making
## the plume drift further must not quietly drag the acorn along with it.
const HEAVY_SEED_SCATTER_FRACTION := 0.3

## Nothing travels further than this, whatever the wind. A bound rather than a
## behaviour: the tail of a heavy-tailed distribution has no natural end, and a
## seed that leaves the loaded world is a seed that quietly vanishes.
const MAX_TRAVEL_TILES := MAX_DRIFT_TILES + CALM_SCATTER_TILES

## How heavy the tail is.
##
## Real wind dispersal is heavy tailed: the bulk of a plant's seed falls within
## a few body-widths and a small fraction goes a very long way. That tail is
## what actually colonises new ground -- a uniform scatter gives neither a
## dense home patch nor any pioneers. Raising this concentrates seed closer in
## and makes the far-flung ones rarer.
const TAIL_POWER := 3.0


## Where this seed lands, relative to the plant that shed it.
##
## `weight` is one of the WEIGHT_ constants, `direction` the day's wind (a unit
## vector) and `strength` its force, 0 calm to 1 gale.
static func landing_offset(
	seed_value: int, weight: float, direction: Vector2, strength: float
) -> Vector2:
	var lightness := clampf(1.0 - clampf(weight, 0.0, 1.0), 0.0, 1.0)
	var force := clampf(strength, 0.0, 1.0)

	# Heavy-tailed distance: a uniform roll raised to a power spends most of
	# its range near zero, so most seed lands close and a little goes far.
	var roll := float(PixelNoise.range_index(seed_value, 71, 0, 1000)) / 999.0
	var reach := pow(roll, TAIL_POWER)

	# Downwind: along the day's wind, scaled by how hard it blows and how
	# little the seed weighs. A nut in a gale barely moves; a plumed seed in
	# the same gale crosses the meadow.
	var downwind := direction.normalized() * reach * force * lightness * MAX_DRIFT_TILES

	# Scatter: where it would have gone with no wind at all. Independent of the
	# wind, so a dead calm still spreads seed around the parent -- but NOT
	# independent of the seed, because still air is not still and a plume rides
	# it while an acorn falls through it (see HEAVY_SEED_SCATTER_FRACTION).
	var angle := float(PixelNoise.range_index(seed_value, 73, 0, 360)) * PI / 180.0
	var spread := sqrt(float(PixelNoise.range_index(seed_value, 79, 0, 1000)) / 999.0)
	var buoyancy := HEAVY_SEED_SCATTER_FRACTION + (1.0 - HEAVY_SEED_SCATTER_FRACTION) * lightness
	var scatter := Vector2(cos(angle), sin(angle)) * spread * CALM_SCATTER_TILES * buoyancy

	var offset := (downwind + scatter) * TerrainRenderer.TILE_SIZE
	var limit := MAX_TRAVEL_TILES * TerrainRenderer.TILE_SIZE
	return offset.limit_length(limit)


## ## leaf_ground_drift: repeated wind nudges to litter ALREADY on the ground
##
## Reported directly: "make the wind blowing through leaves make the tumble
## and swirl more smoothly? it's a hard back forth motion atm". Measured
## directly (tools/probe_wind_offset_spread.gd) what landing_offset itself
## does for WEIGHT_LEAF under a strong, steady wind: of 30 samples, only 17
## (57%) landed within 30 degrees of the wind's own heading, and 9 (30%)
## landed more than 90 degrees off -- genuinely backwards relative to the
## wind, several nearly exactly opposite it. That is the right design for
## landing_offset's actual job (a seed falling ONCE really does scatter
## near its parent on a still day regardless of which way any breeze
## blows -- see this file's own CALM_SCATTER_TILES/HEAVY_SEED_SCATTER_
## FRACTION reasoning), but the wrong one for a leaf ALREADY settled on
## the ground, nudged by the SAME ambient wind repeatedly over time: real
## windblown litter mostly skitters ALONG the wind's own heading, with
## only mild lateral wobble, not a fresh independent random direction on
## every single nudge -- landing_offset's own fully-independent 0-360
## degree scatter angle reads as the leaf being yanked back and forth
## across consecutive nudges instead. landing_offset itself is left
## untouched (seed/flower dispersal already depends on its current
## scatter behaviour); this is a dedicated formula for the one caller
## (LeafLitterField's own throttled wind-dispersal roll) that needs
## directional coherence across many repeated nudges of the SAME
## already-settled object, not landing_offset's independent-per-call
## contract.

## How far the drift angle may wander from the wind's own heading. The one
## property that actually matters is staying under 90 degrees (see
## test_leaf_drift_wobble_never_reaches_a_right_angle in
## test_wind_dispersal.gd): that guarantees a strictly positive dot product
## with the wind direction, i.e. every nudge makes real forward progress
## along the wind, never sideways-or-worse. 45 sits at exactly half that
## structural ceiling -- generous enough for a real leaf's own natural
## side-to-side wobble (a real gust does not carry litter in a perfectly
## straight line) while leaving comfortable margin either side of the
## actual limit, rather than tuning right up against it.
const LEAF_DRIFT_WOBBLE_DEGREES := 45.0

## Where the wind moves a leaf ALREADY settled on the ground, for one
## throttled nudge (see LeafLitterField.advance's own wind-dispersal roll)
## -- see this function's own section doc comment above for why this is a
## separate formula from landing_offset rather than a call to it with
## WEIGHT_LEAF. Reuses the exact same heavy-tailed reach roll and buoyant
## near-field scatter magnitude landing_offset already establishes (so an
## individual nudge's DISTANCE distribution is unchanged, and every
## existing distance-driven consumer -- e.g. LeafLitterRenderer's own
## tumble-turn scaling against MAX_TRANSITION_OFFSET -- still sees the
## same range of journeys) -- only the ANGLE changes, from an independent
## 0-360 degree roll to a bounded wobble around the wind's own heading.
static func leaf_ground_drift(seed_value: int, direction: Vector2, strength: float) -> Vector2:
	var lightness := clampf(1.0 - clampf(WEIGHT_LEAF, 0.0, 1.0), 0.0, 1.0)
	var force := clampf(strength, 0.0, 1.0)

	var roll := float(PixelNoise.range_index(seed_value, 71, 0, 1000)) / 999.0
	var reach := pow(roll, TAIL_POWER)
	var downwind_distance := reach * force * lightness * MAX_DRIFT_TILES

	var spread := sqrt(float(PixelNoise.range_index(seed_value, 79, 0, 1000)) / 999.0)
	var buoyancy := HEAVY_SEED_SCATTER_FRACTION + (1.0 - HEAVY_SEED_SCATTER_FRACTION) * lightness
	var scatter_distance := spread * CALM_SCATTER_TILES * buoyancy

	var wobble_roll := float(PixelNoise.range_index(seed_value, 83, 0, 1000)) / 999.0 * 2.0 - 1.0
	var angle := direction.angle() + deg_to_rad(wobble_roll * LEAF_DRIFT_WOBBLE_DEGREES)

	var offset := Vector2(cos(angle), sin(angle)) * (downwind_distance + scatter_distance) * TerrainRenderer.TILE_SIZE
	var limit := MAX_TRAVEL_TILES * TerrainRenderer.TILE_SIZE
	return offset.limit_length(limit)
