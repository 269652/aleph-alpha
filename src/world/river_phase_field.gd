extends RefCounted

## A continuous streak-phase field along a river's own course -- the fix for
## the single worst defect in the old flow shader. See
## docs/concept/rivers.md's "Flow rendering" section.
##
## THE PROBLEM IT SOLVES. The old shader built its streak phase as
## `dot(world_pos, flow_dir)`, where world_pos is absolute canvas space (up
## to ~639,000 units across this world) and flow_dir is quantised to 16
## compass bins and constant across each tile. At any tile edge where the
## bearing changes bin, the chord between the two directions is
## 2*sin(11.25 deg) = 0.390, so the phase differs by
##     639,000 * 0.390 * 0.12 ~= 30,000 cycles
## which, wrapped by the sine, is a UNIFORMLY RANDOM phase reset at that
## edge. Adjacent river cells routinely land in different bins, so the
## pattern restarted on a 16 px lattice -- and that lattice IS the tilemap,
## made visible. It is why the water read as "a tilemap with a filter on it"
## rather than as a river.
##
## THE FIX. Bake a continuous scalar phase potential along the river's own
## centreline instead. Two cells' baked phase then differ by exactly the
## number of streak cycles that fit between them, so the bands are one
## ribbon following the channel, with no basis to disagree about at a tile
## edge. A second consequence matters just as much: because the phase's
## TIME term is then a single global rate rather than a per-tile speed, the
## temporal frequency is identical everywhere, which is what removes the
## aliasing that made fast rivers visibly flow BACKWARDS at low frame rates
## (32 units/s * 0.12 cycles/unit = 3.84 Hz, which at the measured 7 fps
## floor is 0.549 cycles/frame -- past the 0.5 Nyquist limit).

const RiverCatalog = preload("res://src/world/river_catalog.gd")

## Distance between successive streak crests, in TILES of course.
##
## Constant on purpose for this pass. Letting wavelength grow with local
## speed is the physically-truer choice (a periodic marker released at a
## constant rate spaces its crests proportionally to velocity) and is the
## natural refinement -- but it makes the phase an integral of 1/lambda
## along a course whose speed varies per tile, where a constant lambda makes
## it exactly `distance / lambda`: trivially continuous, with no integration
## and no accumulated drift. Speed is expressed through foam and contrast
## instead this pass (see RiverFlowShader).
const STREAK_WAVELENGTH_TILES := 0.55

## How many cycles per second the whole pattern advances, everywhere, at
## every speed. ONE global rate is what guarantees no reach can alias: at
## the measured ~7 fps floor this is 0.107 cycles/frame, comfortably inside
## the 0.5 Nyquist limit with room for the streak's own harmonics.
const STREAK_RATE_HZ := 0.75


## The streak phase, in CYCLES, at a point `course_fraction` along a river
## of `course_length_tiles`. Continuous along the whole course by
## construction.
static func phase_cycles(course_fraction: float, course_length_tiles: float) -> float:
	if course_length_tiles <= 0.0:
		return 0.0
	return (clampf(course_fraction, 0.0, 1.0) * course_length_tiles) / STREAK_WAVELENGTH_TILES


## Only the fractional part of the phase is what a periodic pattern needs,
## and it is all that can be baked into an 8-bit channel -- so this is what
## actually reaches the shader.
static func wrapped_phase(course_fraction: float, course_length_tiles: float) -> float:
	return fposmod(phase_cycles(course_fraction, course_length_tiles), 1.0)


## Total length of a river's course, in tiles, for a given world size.
## Reads the cached tile-space polylines rather than rebuilding them.
static func course_length_tiles(
	river_name: String, world_width: int, world_height: int
) -> float:
	var polylines := RiverCatalog.tile_polylines(world_width, world_height)
	if not polylines.has(river_name):
		return 0.0
	var points: Array = polylines[river_name]
	var total := 0.0
	for i in range(points.size() - 1):
		total += points[i].distance_to(points[i + 1])
	return total
