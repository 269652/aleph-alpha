extends RefCounted

## Derives a region's wildlife-difficulty tier from its distance (in chunks)
## to the world's spawn point -- see
## docs/concept/ecosystem_dynamics.md#region-difficulty-gating-the-roster-by-player-readiness.
## Deliberately NOT derived from real-world danger statistics or manual
## per-country curation (see that doc section for why) -- just biome
## plausibility (unchanged, existing per-species pools) plus this one
## transparent, game-design distance gradient, the same shape genre
## convention (Terraria's layers, Diablo's acts, Valheim's biome rings)
## already uses.

enum Tier { EASY, MEDIUM, HARD }

## Chunk-distance (Chebyshev, matching EarthChunkManager's own radius math
## e.g. LOAD_RADIUS) thresholds -- within EASY_RADIUS_CHUNKS is EASY, within
## MEDIUM_RADIUS_CHUNKS is MEDIUM, beyond is HARD. Real Earth chunks are
## ~32km each (see earth_chunk_generator.gd), so these correspond to
## roughly "same metro area" (EASY), "same country/region" (MEDIUM), and
## "far abroad" (HARD) bands, without hardcoding any actual place name.
const EASY_RADIUS_CHUNKS := 15
const MEDIUM_RADIUS_CHUNKS := 60


## `spawn_chunk_coord` is passed in rather than hardcoded, so this stays a
## pure function of two coordinates -- callers (EarthChunkManager) own
## which coordinate actually counts as "spawn."
func tier_at(chunk_coord: Vector2i, spawn_chunk_coord: Vector2i) -> Tier:
	var distance := maxi(
		absi(chunk_coord.x - spawn_chunk_coord.x), absi(chunk_coord.y - spawn_chunk_coord.y)
	)
	if distance <= EASY_RADIUS_CHUNKS:
		return Tier.EASY
	if distance <= MEDIUM_RADIUS_CHUNKS:
		return Tier.MEDIUM
	return Tier.HARD
