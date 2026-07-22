extends RefCounted

## Emergent settlement reputation (docs/concept/factions.md): a faction's score
## is a legibility-layer aggregate, stored per faction_id, implicitly 0.0 for
## any faction not yet present. Scores are clamped to [MIN_SCORE, MAX_SCORE].

const MIN_SCORE: float = -100.0
const MAX_SCORE: float = 100.0

## Tier thresholds (inclusive lower bound), monotonically increasing:
## score < NEUTRAL_THRESHOLD -> "hostile"
## score < FRIENDLY_THRESHOLD -> "neutral"
## score < HONORED_THRESHOLD -> "friendly"
## otherwise -> "honored"
const NEUTRAL_THRESHOLD: float = 0.0
const FRIENDLY_THRESHOLD: float = 25.0
const HONORED_THRESHOLD: float = 75.0

var reputation: Dictionary = {}


## Non-mutating read of a faction's stored score, defaulting to 0.0.
func reputation_for(faction_id: String, reputation: Dictionary) -> float:
	if reputation.has(faction_id):
		return reputation[faction_id]
	return 0.0


## Returns a new dictionary with faction_id's score adjusted by delta and
## clamped to [MIN_SCORE, MAX_SCORE]. Does not mutate the passed-in dictionary.
func adjust(faction_id: String, delta: float, reputation: Dictionary) -> Dictionary:
	var result: Dictionary = reputation.duplicate()
	var current: float = reputation_for(faction_id, reputation)
	result[faction_id] = clampf(current + delta, MIN_SCORE, MAX_SCORE)
	return result


## Buckets a score into its named tier.
func tier_for(score: float) -> String:
	if score < NEUTRAL_THRESHOLD:
		return "hostile"
	if score < FRIENDLY_THRESHOLD:
		return "neutral"
	if score < HONORED_THRESHOLD:
		return "friendly"
	return "honored"
