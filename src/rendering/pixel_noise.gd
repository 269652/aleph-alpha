extends RefCounted

## The shared deterministic randomness every procedural generator draws
## with (see docs/concept/pixel_art_engine.md).
##
## Generators used to seed themselves with Godot's string `hash()` --
## `hash("%d_thing_%d" % [seed, i])`. That correlates badly across
## near-identical inputs, and this project has been bitten by it twice:
##   - a seeded index froze to a single bucket, so every village house came
##     out the same size;
##   - whole ROWS of tree leaves came out at the same angle.
##
## This replaces it with an integer avalanche mix (xorshift-multiply): fast,
## allocation-free (no string built per sample), fully deterministic, and
## well-distributed for the sequential/grid-shaped inputs pixel art actually
## uses. Static so callers don't need an instance.

## Odd 32-bit-ish constants for the mix. Large, odd, and mutually coprime so
## each input dimension spreads across the whole word before mixing.
const _SEED_PRIME := 374761393
const _X_PRIME := 668265263
const _Y_PRIME := 2147483647
const _MIX_PRIME := 1274126177

## Resolution of the unit conversion. Reducing modulo a large power-of-ten
## before dividing keeps the result stable across platforms and avoids the
## low-bit patterning a plain float cast can show.
const _UNIT_RESOLUTION := 1000000


## A well-distributed non-negative integer from a seed and two coordinates.
static func value(seed_value: int, x: int, y: int) -> int:
	var h := seed_value * _SEED_PRIME + x * _X_PRIME + y * _Y_PRIME
	h = (h ^ (h >> 13)) * _MIX_PRIME
	h = h ^ (h >> 16)
	return absi(h)


## `value` mapped into [0, 1).
static func unit(seed_value: int, x: int, y: int) -> float:
	return float(value(seed_value, x, y) % _UNIT_RESOLUTION) / float(_UNIT_RESOLUTION)


## A float in [low, high) -- the "pick a size/length/offset" form.
static func range_value(seed_value: int, x: int, y: int, low: float, high: float) -> float:
	return low + unit(seed_value, x, y) * (high - low)


## An integer in [0, count) -- the "pick one of N options" form. Goes
## through `unit` rather than a raw modulo so a `count` that happens to
## share a factor with the mix constants can't bias the choice (the
## single-bucket failure above was exactly that).
static func range_index(seed_value: int, x: int, y: int, count: int) -> int:
	if count <= 1:
		return 0
	return clampi(int(unit(seed_value, x, y) * float(count)), 0, count - 1)


## Smooth value noise in [0, 1] for organic gradients -- cloud shading, fur
## direction, marbling, dirt mottling. Neighbouring samples stay close
## together, unlike `unit`'s per-pixel scatter. Bilinear between integer
## lattice points with a smoothstep fade, the standard cheap construction.
static func smooth(seed_value: int, x: float, y: float) -> float:
	var x0 := floori(x)
	var y0 := floori(y)
	var fx := _fade(x - float(x0))
	var fy := _fade(y - float(y0))

	var top: float = lerp(unit(seed_value, x0, y0), unit(seed_value, x0 + 1, y0), fx)
	var bottom: float = lerp(unit(seed_value, x0, y0 + 1), unit(seed_value, x0 + 1, y0 + 1), fx)
	return clampf(lerp(top, bottom, fy), 0.0, 1.0)


## Fractal (multi-octave) smooth noise: several `smooth` layers at doubling
## frequency and halving amplitude, for texture that has both broad shape
## and fine grain -- bark, stone, cloth weave.
static func fractal(seed_value: int, x: float, y: float, octaves: int = 3) -> float:
	var total := 0.0
	var amplitude := 1.0
	var frequency := 1.0
	var normalizer := 0.0
	for i in maxi(octaves, 1):
		total += smooth(seed_value + i * 7919, x * frequency, y * frequency) * amplitude
		normalizer += amplitude
		amplitude *= 0.5
		frequency *= 2.0
	return clampf(total / normalizer, 0.0, 1.0)


static func _fade(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)
