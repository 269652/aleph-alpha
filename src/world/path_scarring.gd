extends RefCounted
## Path scarring: repeated walking wears grass into visible dirt paths;
## unwalked tiles slowly recover. Pure logic — worn tiles can be rendered
## via TerrainRenderer's EARTH_TILE_ID modification system.
##
## ## The trail tier (docs/concept/infrastructure.md's "path -> trail -> road")
##
## A path re-textured once at WORN_THRESHOLD and then nothing further was
## ever perceptible, however much more it was walked -- the wear NUMBER kept
## climbing underneath (`wear_at` genuinely reaches MAX_WEAR, and
## `speed_multiplier` genuinely keeps rising with it), but nothing rendered,
## named, or otherwise let a player tell "crossed once" from "walked to the
## ground" apart. Reported as "path scarring only is computed once and
## walking back and forth doesn't deepen it" -- true of what could be SEEN,
## not of the number itself.
##
## `TRAIL_THRESHOLD` is deliberately NOT a new, separately-tuned number: it
## IS `MAX_WEAR`. Inventing a threshold ABOVE the existing ceiling would be
## unreachable; one BELOW it would just be WORN_THRESHOLD picked twice. The
## ceiling this module already enforces -- "as compacted as this ground can
## ever get" -- already names exactly the state a trail is.
const WEAR_PER_STEP := 0.08
const WORN_THRESHOLD := 1.0
const DECAY_PER_SECOND := 0.01
const MAX_WEAR := 1.5
const TRAIL_THRESHOLD := MAX_WEAR

## How much faster fully compacted ground is to walk than rough ground.
##
## Paths have worn in and rendered as earth since this module was written, and
## they did NOTHING: walking the same line every day changed the picture and
## not the walk. A trodden path is faster than rough ground -- that is why real
## desire paths form at all -- and without the benefit the loop is open at both
## ends, since habit makes a path and the path makes nothing.
##
## A real convenience rather than a highway. Bracketed from both sides by
## test_the_advantage_is_worth_having_and_not_absurd, so neither edge can drift
## into "pointless" or "the only way to travel".
const WORN_SPEED_BONUS := 0.18


## What ground worn to `wear` does to how fast it is crossed.
##
## Continuous rather than a switch at WORN_THRESHOLD: real ground compacts
## progressively under repeated use, so a half-worn track already helps a
## little -- which is also what makes the loop reinforce smoothly instead of
## paying out all at once. Never below 1.0: a path is never a hindrance.
static func speed_multiplier(wear: float) -> float:
	var compacted := clampf(wear, 0.0, MAX_WEAR) / MAX_WEAR
	return 1.0 + WORN_SPEED_BONUS * compacted

var _wear: Dictionary = {}


func step_on(tile: Vector2i) -> void:
	_wear[tile] = minf(_wear.get(tile, 0.0) + WEAR_PER_STEP, MAX_WEAR)


func advance(delta: float) -> void:
	if delta <= 0.0:
		return
	var decay := DECAY_PER_SECOND * delta
	for tile in _wear.keys():
		var remaining: float = _wear[tile] - decay
		if remaining <= 0.0:
			_wear.erase(tile)
		else:
			_wear[tile] = remaining


func wear_at(tile: Vector2i) -> float:
	return _wear.get(tile, 0.0)


func is_worn(tile: Vector2i) -> bool:
	return wear_at(tile) >= WORN_THRESHOLD


## Sustained, heavier use of an already-worn path (docs/concept/
## infrastructure.md) -- a strictly deeper tier of is_worn, not a separate
## state: every trail is also worn (TRAIL_THRESHOLD > WORN_THRESHOLD), but
## most worn tiles are not yet trails.
func is_trail(tile: Vector2i) -> bool:
	return wear_at(tile) >= TRAIL_THRESHOLD


func worn_tiles(threshold: float = WORN_THRESHOLD) -> Array:
	var result: Array = []
	for tile in _wear:
		if _wear[tile] >= threshold:
			result.append(tile)
	return result


func trail_tiles() -> Array:
	return worn_tiles(TRAIL_THRESHOLD)


func tracked_tile_count() -> int:
	return _wear.size()
