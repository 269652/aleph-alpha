extends Resource

## A reusable, data-driven material definition for equipment/clothing items:
## how much they weigh dry, how much extra weight they hold when soaked, and
## (used by WetnessTracker) how fast they absorb/dry.

## Weight of the item with zero water absorbed.
@export var weight: float = 0.0
## Extra weight added at full (1.0) water saturation.
@export var water_weight: float = 0.0
## How fast wetness rises per second while submerged, in wetness units.
@export var absorption_rate: float = 0.1
## How fast wetness falls per second while not submerged, in wetness units.
@export var dry_rate: float = 0.05


## Total weight of the item at a given wetness fraction in [0.0, 1.0].
func effective_weight(wetness: float) -> float:
	return weight + wetness * water_weight
