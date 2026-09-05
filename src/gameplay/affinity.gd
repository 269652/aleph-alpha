extends RefCounted

## The vector arithmetic under the ethogram (docs/concept/ethogram.md §6).
##
## A stimulus is a feature vector, an animal is a sensitivity vector (what it
## can detect) and a valence vector (what it makes of detecting it), and
## everything the behaviour kernel decides is a product of the three. Kept as
## its own module rather than a corner of the kernel because the same sums
## are the plan for pathogens, immunity and pharmacology later (ethogram.md
## §8): a tropism vector against expressed receptors is `pull` with different
## names on the axes.
##
## Vectors are plain String -> float Dictionaries, the shape Olfaction's
## mixtures and receptors already have, so nothing has to be converted to use
## this. A channel missing from any of the three contributes exactly nothing:
## an animal with no receptor for smoke does not merely not care about smoke,
## it cannot detect it.
##
## Pure, static, no engine dependency, no RNG.

## Fallback heading so a creature exactly overlapping what it is fleeing (or
## approaching) still moves somewhere rather than producing a zero-length,
## no-op direction. Moved here verbatim from CreatureBehavior.
const OVERLAP_FALLBACK := Vector2.UP


## What this thing MEANS to this animal: features weighted by how well each is
## detected and by what detecting it does. Positive draws, negative repels,
## near zero is noise. `channels` restricts the sum to a subset of the basis;
## empty means every channel the stimulus carries.
static func pull(
	features: Dictionary, sensitivity: Dictionary, valence: Dictionary, channels: Array = []
) -> float:
	var total := 0.0
	for channel in _channels_of(features, channels):
		total += (
			float(features.get(channel, 0.0))
			* float(sensitivity.get(channel, 0.0))
			* float(valence.get(channel, 0.0))
		)
	return total


## How much this animal NOTICES this thing, regardless of whether it likes it:
## the same sum without the valence. Olfaction's perceived_strength.
static func loudness(features: Dictionary, sensitivity: Dictionary, channels: Array = []) -> float:
	var total := 0.0
	for channel in _channels_of(features, channels):
		total += float(features.get(channel, 0.0)) * float(sensitivity.get(channel, 0.0))
	return total


## A RANKING weight by distance, not physics: 1 at the source, strictly
## decreasing, never zero. Between two stimuli of equal pull the nearer wins,
## which is what makes "flee the nearest threat" fall out of a sum. How far a
## thing can be sensed at all is the sense's own business (Olfaction.dilution,
## CreatureMarker.SENSE_RADIUS); the kernel never drops a stimulus a sense
## chose to report, so this has no cutoff.
static func proximity(distance: float) -> float:
	return 1.0 / (1.0 + maxf(distance, 0.0))


static func toward(origin: Vector2, target: Vector2) -> Vector2:
	var direction := target - origin
	if direction.length() < 0.001:
		return OVERLAP_FALLBACK
	return direction.normalized()


static func away_from(origin: Vector2, target: Vector2) -> Vector2:
	var direction := origin - target
	if direction.length() < 0.001:
		return OVERLAP_FALLBACK
	return direction.normalized()


static func _channels_of(features: Dictionary, channels: Array) -> Array:
	if channels.is_empty():
		return features.keys()
	return channels
