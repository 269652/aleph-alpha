extends RefCounted

## The four real cave zones by distance from an entrance, the light that
## reaches them, and the temperature they hold (see
## docs/concept/underground.md "The four cave zones, and why the deep one
## is a refuge").
##
## Speleobiology's standard zonation -- entrance, twilight, transition,
## deep cave -- and the two properties of it that carry real gameplay
## weight:
##
## - Below the twilight zone there is NO light at all. lighting.md's first
##   pillar ("night is dim, never pitch black") is justified explicitly by
##   moonlight, starlight and skyglow; none of those exists underground,
##   so the justification does not travel down here and neither does the
##   rule. This is a principled exception, not a contradiction.
## - The deep zone sits at its locality's mean annual surface temperature
##   whatever the weather is doing above it, which makes it a real refuge
##   from both heat and frost rather than only a place to raid.
##
## The boundary distances are real orders of magnitude, not exact numbers
## a player ever sees: real zone boundaries depend heavily on passage
## geometry (a sinuous passage goes dark far sooner than a straight one),
## so these stand for a typical passage rather than claiming a universal
## figure.

const ZONE_ENTRANCE := "entrance"
const ZONE_TWILIGHT := "twilight"
const ZONE_TRANSITION := "transition"
const ZONE_DEEP := "deep"

## Shallowest first -- also the order walking inward passes through them.
const ZONES: Array[String] = [ZONE_ENTRANCE, ZONE_TWILIGHT, ZONE_TRANSITION, ZONE_DEEP]

## Play-scale metres per tile, from the player's own real height
## (TerrainRenderer.TILE_SIZE / GroundSlide.PX_PER_METER). Restated rather
## than preloaded, same reasoning as CaveNetwork's own copy, and pinned
## against it by test_metres_per_tile_agrees_with_the_cave_network.
const METRES_PER_TILE := 1.426

## The drip line: surface plants and surface species persist for the first
## few metres inside a mouth, which is why the entrance zone is a real
## ecological zone rather than a rendering nicety.
const ENTRANCE_END_TILES := 3.5

## Where usable daylight runs out -- a few tens of metres into a typical
## passage, and the boundary below which photosynthesis is impossible.
const TWILIGHT_END_TILES := 21.0

## How far surface air exchange still swings the temperature. Past this
## the cave holds its own climate.
const TRANSITION_END_TILES := 105.0

## Depth at which daylight falls to 1/e of its value at the mouth. Real
## light loss in a passage is dominated by absorption at the walls rather
## than by inverse-square spreading, so it goes exponentially, and it is
## cut to exactly zero at the twilight boundary.
const DAYLIGHT_EFOLD_TILES := 4.0

## How much of the outside swing each zone still feels, 1.0 being fully
## exposed and 0.0 being the cave's own constant climate.
const SURFACE_COUPLING := {
	ZONE_ENTRANCE: 1.0,
	ZONE_TWILIGHT: 0.55,
	ZONE_TRANSITION: 0.15,
	ZONE_DEEP: 0.0,
}


## Which zone sits this many tiles in from the entrance.
func zone_at(distance_tiles: float) -> String:
	var distance := maxf(distance_tiles, 0.0)
	if distance < ENTRANCE_END_TILES:
		return ZONE_ENTRANCE
	if distance < TWILIGHT_END_TILES:
		return ZONE_TWILIGHT
	if distance < TRANSITION_END_TILES:
		return ZONE_TRANSITION
	return ZONE_DEEP


## How much of the outside daylight reaches this far in, in [0,1].
## EXACTLY zero at and beyond the twilight boundary -- not asymptotically
## small. A floor that never quite reached zero would quietly make a
## carried light cosmetic, which is the opposite of what the underground
## needs it to be.
func daylight_fraction_at(distance_tiles: float) -> float:
	var distance := maxf(distance_tiles, 0.0)
	if distance >= TWILIGHT_END_TILES:
		return 0.0
	return exp(-distance / DAYLIGHT_EFOLD_TILES)


## Whether this zone has no daylight whatsoever, and therefore needs a
## carried light source to be navigable at all.
func is_absolutely_dark(zone: String) -> bool:
	return zone == ZONE_TRANSITION or zone == ZONE_DEEP


## The air temperature in this zone, given the locality's mean annual
## surface temperature and what the surface is doing right now. The deep
## zone ignores the second entirely; the entrance zone is the second.
func temperature_c_at(
	zone: String, mean_annual_surface_c: float, surface_now_c: float
) -> float:
	var coupling: float = SURFACE_COUPLING.get(zone, 1.0)
	return lerpf(mean_annual_surface_c, surface_now_c, coupling)
