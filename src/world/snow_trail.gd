extends RefCounted

const WeatherModel = preload("res://src/world/weather_model.gd")

## Footprints in snow: walking displaces it, and fresh snow fills the tracks
## back in.
##
## The same shape as PathScarring, which already wears grass into dirt paths:
## walking marks a tile and the world slowly undoes it. What UNDOES it is the
## difference -- a path through grass grows back on its own, while footprints
## sit there until it snows again. That is why a trail across a field lasts
## through a clear cold day and is gone after a fall.
##
## Pure logic over tiles, like PathScarring. Drawing the tracks is the
## renderer's job.

## How much snow one step displaces, and how deep a track can get. Snow only
## goes so flat: past that it is trodden bare and further walking changes
## nothing.
const TREAD_PER_STEP := 0.34
const MAX_TREAD := 1.0

## How much displacement is already visible. One step has to show, or the whole
## feature is a number nobody can read.
const VISIBLE_TREAD := 0.3

## How long a steady snowfall takes to fill a track in completely.
##
## Measured in WEATHER SPELLS, and FASTER than covering bare ground: a
## footprint is a shallow depression that drifts full quickly, while burying a
## whole field takes longer. This was twelve real minutes -- longer than a
## whole weather spell -- so a snowfall always ended before it could fill
## anything, and tracks cut on the first walk stayed for good (reported).
const SECONDS_TO_FILL := WeatherModel.WEATHER_PERIOD_SECONDS * 0.35

## Below this a track is forgotten entirely, rather than kept at nearly-zero
## forever -- otherwise a long walk leaves the map remembering every tile ever
## stepped on.
const FORGET_BELOW := 0.02

var _tread: Dictionary = {}  # Vector2i tile -> displacement 0..1


## Marks a tile as walked on.
func step_on(tile: Vector2i) -> void:
	_tread[tile] = minf(float(_tread.get(tile, 0.0)) + TREAD_PER_STEP, MAX_TREAD)


## Fills tracks in while it is snowing. Nothing happens when it is not: tracks
## do not fade on their own.
func advance(delta_seconds: float, snowing: bool) -> void:
	if not snowing or delta_seconds <= 0.0:
		return
	var filled := delta_seconds / SECONDS_TO_FILL
	for tile in _tread.keys():
		var left: float = float(_tread[tile]) - filled
		if left <= FORGET_BELOW:
			_tread.erase(tile)
		else:
			_tread[tile] = left


## How much snow has been displaced here, 0 untouched to 1 trodden bare.
func tread_at(tile: Vector2i) -> float:
	return float(_tread.get(tile, 0.0))


## Tiles carrying a visible track, for the renderer.
func trodden_tiles(threshold: float = VISIBLE_TREAD) -> Array:
	var out: Array = []
	for tile in _tread:
		if float(_tread[tile]) >= threshold:
			out.append(tile)
	return out


func tracked_tile_count() -> int:
	return _tread.size()
