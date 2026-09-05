extends RefCounted

## Flies: the creature that wants what everything else avoids (see
## docs/concept/olfaction.md).
##
## They exist to make rot MEAN something. Without them a rotting windfall is
## just food nobody wants, which is indistinguishable from no food at all --
## with them it is somebody's larder, and a cloud over a windfall is the
## player's visible cue that it has gone over.
##
## Pure and engine-free: how many flies a thing draws, and where each one is
## relative to it. Spawning them is the caller's job.

const Olfaction = preload("res://src/gameplay/olfaction.gd")

## The most flies one source can draw. A bound rather than a behaviour: a
## swarm is a handful of specks that reads as a cloud, and past that it is
## just cost.
const MAX_SWARM := 6

## How attractive a thing has to be before a single fly bothers.
const SWARM_THRESHOLD := 0.25

## How attractive it has to be to draw a FULL swarm.
const SWARM_SATURATION := 1.1

## How wide a swarm hangs around its source, in pixels, and how fast it churns.
const SWARM_RADIUS_PX := 7.0
const SWARM_TURNS_PER_SECOND := 0.55


## How many flies this smell draws at this range.
##
## Read through a fly's own nose, so it is the same judgement every other
## animal makes -- flies are not a special case, they simply have different
## receptors (see Ethogram.SPECIES).
static func swarm_size_for(mixture: Dictionary, distance_tiles: float) -> int:
	var pull := Olfaction.attraction_to("fly", mixture, distance_tiles)
	if pull <= SWARM_THRESHOLD:
		return 0
	var span := maxf(SWARM_SATURATION - SWARM_THRESHOLD, 0.0001)
	var fraction := clampf((pull - SWARM_THRESHOLD) / span, 0.0, 1.0)
	return clampi(int(ceil(fraction * float(MAX_SWARM))), 1, MAX_SWARM)


## Where the `index`th fly of a swarm sits relative to its source, `elapsed`
## seconds in.
##
## They ORBIT rather than flying to a point and stopping, which is what makes a
## cloud read as a cloud, and each one starts at its own angle so a swarm is
## not one fly drawn six times.
static func swarm_offset(index: int, elapsed: float) -> Vector2:
	var phase := float(index) * TAU / float(MAX_SWARM)
	var angle := elapsed * TAU * SWARM_TURNS_PER_SECOND + phase
	# Each fly keeps its own radius, so the cloud has depth rather than being
	# a ring.
	var radius := SWARM_RADIUS_PX * (0.45 + 0.55 * float((index * 7) % 5) / 4.0)
	# Slightly elliptical and bobbing, because flies do not orbit tidily. The
	# two axes run at different frequencies, so they can peak together and
	# carry a fly further than its own radius -- bounded so the swarm stays a
	# cloud over its source rather than occasionally flinging one out.
	return Vector2(
		cos(angle) * radius, sin(angle * 1.3) * radius * 0.6
	).limit_length(SWARM_RADIUS_PX)
