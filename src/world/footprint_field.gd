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
const LIFETIME_SECONDS := SeasonCycle.SECONDS_PER_DAY * 0.5

var _prints: Array[Dictionary] = []
var _generation := 0


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
func advance(now: float) -> void:
	for i in range(_prints.size() - 1, -1, -1):
		if now - _prints[i].spawned_at >= LIFETIME_SECONDS:
			_prints.remove_at(i)
			_generation += 1
