extends RefCounted

## Per-chunk record of individual footprint stamps (see FootstepGait,
## docs/concept/snow_cover.md's "Footprints" / docs/concept/
## infrastructure.md's path-scarring framing). Reported live: "real
## footstep prints with left/right footprints spaced apart and stamped
## into the snow with displacement... also proper pathscarring for grass
## and forest tiles" -- one field/renderer pair serves all three surfaces,
## distinguished only by each print's own `surface` key.
##
## Mirrors LeafLitterField's exact shape -- plain Dictionary-per-instance
## data, no scene nodes, created at chunk load and erased at unload (see
## EarthChunkManager._footprint_fields), GPU-instanced by
## FootprintRenderer rather than one Node2D per print. Deliberately a
## SIMPLER mirror, not a full copy of LeafLitterField's own animation
## machinery: a footprint is static once stamped -- no wind drift, no
## settle transition, no multi-stage colour decay -- so there is nothing
## here to age except lifetime pruning itself.
##
## Each print is a plain Dictionary:
##   position   -- the real sub-tile world position the foot actually
##                  landed (base walker position + FootstepGait.
##                  print_offset), not a tile-quantized cell.
##   side       -- "left" or "right" (see FootstepGait.step_if_due).
##   surface    -- "snow"/"grass"/"forest" -- which
##                  ProceduralFootprintSprite look this print renders with,
##                  and which of PATH_SCAR_BIOMES/snow it was stamped on.
##   heading    -- the real travel direction at the moment of the step
##                  (Vector2, need not be normalized) -- the renderer
##                  orients each print's toe along this.
##   spawned_at -- world_age_seconds when this print was stamped. Drives
##                  LIFETIME_SECONDS pruning only.
##   size_scale -- how big a mark THIS print's own walker left, driven by
##                  its real mass (CreatureMass.linear_scale_for_mass_
##                  ratio against the player's own reference mass -- see
##                  EarthChunkManager.record_footstep). 1.0 is today's
##                  existing fixed print size (the player's own, by
##                  construction); FootprintRenderer multiplies this
##                  straight into the render transform's own scale.

const SeasonCycle = preload("res://src/world/season_cycle.gd")

## How long an individual footprint stamp lingers before fading back into
## unmarked ground -- a real design knob (the same category
## AntColony.FORAGE_RADIUS_TILES's own doc comment names: real judgement,
## not a physically-measurable constant), expressed as a fraction of a
## real in-game day rather than a raw eyeballed second count, so it stays
## in proportion if the day length itself is ever retuned. Deliberately
## far shorter than LeafLitterField.LIFETIME (0.75 real YEARS) -- a
## footprint is an ephemeral mark, not persistent litter, unlike the snow
## depth reduction and PathScarring wear this sits alongside (both keep
## their own, much longer-lived clocks entirely unchanged by this file).
## Asked for directly: "Ok make the half life time 2 minutes" -- so a print
## is at HALF strength two real minutes after it is stamped, half of that
## again two minutes later, and so on. A half-life is exponential by
## definition, which is also the honest shape for a mark weathering away:
## a fresh print loses its crisp edge quickly and the last ghost of it
## lingers.
const HALF_LIFE_SECONDS := 2.0 * 60.0

## Below this strength a print is no longer visible on any ground, so
## keeping the record costs iteration and draw calls for something nobody
## can see -- which, in a project that has fought sixteen rounds of frame
## rate decay, is not a harmless simplification.
const VISIBLE_FLOOR := 0.02

## How long a print is worth keeping, DERIVED from the half-life rather than
## carried as a second, independent number that could contradict it: the
## time for a print to fade below VISIBLE_FLOOR.
##
## This replaces a flat 30 real minutes. Those were asked for first, and
## then a two-minute half-life was asked for, and the two cannot both be
## true -- two minutes of half-life puts a print under 2% strength after
## about eleven, not thirty. The half-life is the later and more specific
## instruction, so it wins, and this follows it instead of arguing with it.
## Pinned by test_a_print_is_kept_exactly_as_long_as_it_can_be_seen.
const LIFETIME_SECONDS := HALF_LIFE_SECONDS * 5.643856189774724  # log2(1 / VISIBLE_FLOOR)

## How much faster a print fades in a downpour than on dry ground. A real
## design knob of the same kind as the half-life, not a measurable constant:
## four is what makes rain matter -- in a downpour the half-life is thirty
## seconds rather than two minutes -- without a shower erasing a trail
## before anybody can follow it.
const RAIN_DECAY_MULTIPLIER := 4.0

const FADE_STEPS := 16

var _prints: Array[Dictionary] = []
var _generation := 0
## The world clock this field last aged against. Starts at the clock's own
## origin rather than at the first advance() call, so a first advance(T)
## ages every print by T -- which is what every caller written before decay
## existed already assumes.
var _last_advanced_at := 0.0


## How fast a print ages right now, as a multiple of its dry pace. `wetness`
## is 0 on dry ground and 1 in a downpour (EarthChunkManager.set_rain's own
## intensity); anything between scales linearly, because drizzle really is
## gentler on a trail than a storm.
static func decay_rate_for(wetness: float) -> float:
	return 1.0 + clampf(wetness, 0.0, 1.0) * (RAIN_DECAY_MULTIPLIER - 1.0)


## How strongly this print still shows: 1.0 the moment it is stamped, 0.0
## when it is spent, and continuously falling in between.
##
## Asked for directly ("make the decay gradually"). What this replaces is a
## print that held full strength for its entire life and then vanished
## between one frame and the next, which is what pruning alone did.
static func opacity_of(stamp: Dictionary) -> float:
	return clampf(pow(0.5, float(stamp.get("decayed", 0.0)) / HALF_LIFE_SECONDS), 0.0, 1.0)


## Which drawn band that opacity falls in -- see FADE_STEPS.
static func fade_band_of(stamp: Dictionary) -> int:
	return int(floor(opacity_of(stamp) * float(FADE_STEPS)))


func add_print(
	position: Vector2, side: String, surface: String, heading: Vector2, now: float, size_scale: float = 1.0
) -> void:
	_prints.append({
		"position": position,
		"side": side,
		"surface": surface,
		"heading": heading,
		"spawned_at": now,
		"size_scale": size_scale,
		# Seconds of DRY-equivalent ageing this print has taken so far. Not
		# derived from spawned_at, because the weather it has lived through
		# is not the weather it is asked about -- see advance().
		"decayed": 0.0,
	})
	_generation += 1


func prints() -> Array[Dictionary]:
	return _prints


func count() -> int:
	return _prints.size()


func generation() -> int:
	return _generation


## Prunes anything past LIFETIME_SECONDS. `now` is the authoritative
## world_age_seconds this step is happening at (see EarthChunkManager.
## step_footprints) -- an explicit absolute clock, not a locally-
## accumulated one, the same convention LeafLitterField.advance already
## uses so a print's lifetime tracks the same clock /ecotest fast-forwards
## along with the rest of the ecosystem.
## `wetness` is how hard it is raining on this chunk right now, 0..1, and it
## is sampled per step rather than stored per print: a print cannot know what
## weather is coming. That is also why decay ACCUMULATES here instead of
## being recomputed from spawned_at -- rain that begins halfway through a
## print's life must hurry only the half that is left of it, not retroactively
## the half it already spent in the sun.
##
## The generation bump is deliberately tied to a print crossing a FADE_STEPS
## band rather than to any change at all: see FADE_STEPS for why rebuilding
## the renderer's buffer every frame is the one thing this must not do.
func advance(now: float, wetness: float = 0.0) -> void:
	var elapsed := maxf(now - _last_advanced_at, 0.0)
	_last_advanced_at = now
	if elapsed <= 0.0:
		return
	var aged := elapsed * decay_rate_for(wetness)
	for i in range(_prints.size() - 1, -1, -1):
		var before := fade_band_of(_prints[i])
		_prints[i]["decayed"] = float(_prints[i].get("decayed", 0.0)) + aged
		if _prints[i]["decayed"] >= LIFETIME_SECONDS:
			_prints.remove_at(i)
			_generation += 1
		elif fade_band_of(_prints[i]) != before:
			_generation += 1
