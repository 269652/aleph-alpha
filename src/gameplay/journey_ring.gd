extends RefCounted

## The player-facing half of RegionDifficulty -- see
## docs/concept/journey_rings.md.
##
## RegionDifficulty already turns a chunk's Chebyshev distance from spawn
## into EASY/MEDIUM/HARD, and that tier already decides whether a bear, a
## lion or a venomous snake may exist there at all
## (CreatureRenderer.MIN_DIFFICULTY_TIER_BY_SPECIES). What it has never had
## is a voice: three unnamed bands, no boundary the game ever mentions, no
## sentence that says WHAT CHANGED. A player who walks sixteen chunks out
## crosses from ground where bears cannot spawn to ground where they can,
## and the only evidence is a bear.
##
## This module adds the names, the bounds, the one-line "new and lethal"
## and the packing list each ring implies. It adds a voice to
## RegionDifficulty; it is never a second opinion. Every ring's tier IS
## RegionDifficulty's tier for the same distance, swept 0..400 chunks by
## test_ring_tier_equals_region_difficultys_tier_at_every_distance.
##
## It also, deliberately, cannot say no. There is no can_enter, is_blocked,
## may_pass or is_allowed here, and test_nothing_here_can_refuse_entry reads
## this script's own method list to keep it that way. The world's order is
## enforced by what lives out there and by the cold, never by an invisible
## fence. Walking to the far country at hour one is allowed. Walking back
## is the part that isn't.
##
## Pure: RefCounted, static functions, no scene tree, no world access, no
## file access, no singleton. Preloads RegionDifficulty -- that is the
## whole point -- and nothing else.

const RegionDifficulty = preload("res://src/world/region_difficulty.gd")

## The outermost ring's `outer_chunks`. Earth does not stop, so neither
## does the last ring; `ring_at` treats this as "no outer edge" rather
## than as a number to compare against.
const UNBOUNDED := -1

## The hearth is the INNER THIRD of RegionDifficulty's easy band: the
## ground a player can leave and come back from without packing. A third
## rather than a half so the easy band still has a real "near away" beyond
## it, and rather than a smaller slice so the hearth is not a sliver.
## Integer division of EASY_RADIUS_CHUNKS (15) by this is exact.
const HEARTH_DIVISOR_OF_EASY := 3
const HEARTH_RADIUS_CHUNKS := RegionDifficulty.EASY_RADIUS_CHUNKS / HEARTH_DIVISOR_OF_EASY

## The marches end at the GEOMETRIC MEAN of the two RegionDifficulty radii
## (30^2 == 15 * 60), which for these values is exactly twice the easy
## radius. The medium band is where distance starts doubling rather than
## adding -- 15 to 60 is two factors of two, not one step of +15 and one of
## +30 -- so the honest place to cut it is the point that is the same
## FACTOR from each end. Pinned by
## test_march_radius_is_the_geometric_mean_of_the_two_region_radii, which
## is what holds the relationship if either radius is ever retuned.
const MARCH_EASY_MULTIPLE := 2
const MARCH_RADIUS_CHUNKS := RegionDifficulty.EASY_RADIUS_CHUNKS * MARCH_EASY_MULTIPLE

## What each ring expects a traveller to be carrying. Every one of these
## names a system that already exists and can already kill: PROVISIONS is
## SurvivalMeters' hunger and thirst, WARMTH its is_cold/is_freezing,
## ANSWER_TO_VENOM is VenomModel's stacking damage-over-time -- which only
## `venomous_snake` applies, and `venomous_snake` is one of the exactly
## three species MIN_DIFFICULTY_TIER_BY_SPECIES restricts to HARD. These
## are ids for a caller to render, not display strings.
const DEMAND_PROVISIONS := "provisions"
const DEMAND_WEAPON := "a_weapon_that_kills"
const DEMAND_WARMTH := "warmth"
const DEMAND_LIGHT := "a_light"
const DEMAND_ANSWER_TO_VENOM := "an_answer_to_venom"

## A chunk is CHUNK_SIZE tiles square and a tile is ~1 km at world scale.
## Both are restated here rather than preloaded, the same reason Lithology
## gives for restating KM_PER_TILE and BuilderMarker gives for restating
## CHUNK_SIZE: a small pure module should not pull in EarthChunkManager's
## whole streaming layer just to multiply by 32. The agreement is pinned by
## test_chunk_size_agrees_with_the_chunk_manager and
## test_km_per_tile_agrees_with_the_world_scale instead of asserted by
## construction.
##
## (Note for anyone chasing the other scale: TerrainRenderer.TILE_SIZE is
## 16 WORLD UNITS per tile, an engine figure, and CaveZonation's 1.426 m
## per tile is the underground's play scale. Neither is the surface map's
## metres. The surface is Lithology.KM_PER_TILE, itself pinned to
## EarthChunkGenerator.TILES_PER_DEGREE.)
const CHUNK_SIZE_TILES := 32
const KM_PER_TILE := 1.0
const METRES_PER_KM := 1000.0
const METRES_PER_CHUNK := CHUNK_SIZE_TILES * KM_PER_TILE * METRES_PER_KM

## The journey outward, innermost first. Bounds are inclusive chunk
## distances; each ring begins one chunk past the previous one's outer
## edge, with no gap and no overlap
## (test_the_table_runs_outward_from_zero_with_no_gap_and_no_overlap).
##
## `demands` grows strictly outward and every entry of a nearer ring
## appears in every further one -- the packing list is cumulative because
## distance is, which is the historical shape too: provisions first, then
## a weapon, then warmth, then light.
const RINGS: Array[Dictionary] = [
	{
		"id": "hearth",
		"name": "The Hearth",
		"inner_chunks": 0,
		"outer_chunks": HEARTH_RADIUS_CHUNKS,
		"tier": RegionDifficulty.Tier.EASY,
		"description": "Nothing here kills you that you did not walk up to first.",
		"demands": [],
	},
	{
		"id": "commons",
		"name": "The Commons",
		"inner_chunks": HEARTH_RADIUS_CHUNKS + 1,
		"outer_chunks": RegionDifficulty.EASY_RADIUS_CHUNKS,
		"tier": RegionDifficulty.Tier.EASY,
		"description":
		"Worked ground nobody is watching: boar that stand their ground, and weather that does not stop for you.",
		"demands": [DEMAND_PROVISIONS],
	},
	{
		"id": "marches",
		"name": "The Marches",
		"inner_chunks": RegionDifficulty.EASY_RADIUS_CHUNKS + 1,
		"outer_chunks": MARCH_RADIUS_CHUNKS,
		"tier": RegionDifficulty.Tier.MEDIUM,
		"description":
		"The last ground anyone has a name for. Predators hunt here rather than pass through.",
		"demands": [DEMAND_PROVISIONS, DEMAND_WEAPON],
	},
	{
		"id": "wilds",
		"name": "The Wilds",
		"inner_chunks": MARCH_RADIUS_CHUNKS + 1,
		"outer_chunks": RegionDifficulty.MEDIUM_RADIUS_CHUNKS,
		"tier": RegionDifficulty.Tier.MEDIUM,
		"description":
		"No fire out here but the one you light. Cold and distance do more damage than teeth.",
		"demands": [DEMAND_PROVISIONS, DEMAND_WEAPON, DEMAND_WARMTH],
	},
	{
		"id": "far_country",
		"name": "The Far Country",
		"inner_chunks": RegionDifficulty.MEDIUM_RADIUS_CHUNKS + 1,
		"outer_chunks": UNBOUNDED,
		"tier": RegionDifficulty.Tier.HARD,
		"description":
		"Bear, lion and venomous snake live only out here, and nothing is coming to find you.",
		"demands":
		[
			DEMAND_PROVISIONS,
			DEMAND_WEAPON,
			DEMAND_WARMTH,
			DEMAND_LIGHT,
			DEMAND_ANSWER_TO_VENOM,
		],
	},
]


## The whole journey, outward. Returned directly rather than duplicated:
## a `const` container is read-only at runtime in Godot 4, so a caller
## cannot edit the table out from under the next one.
static func rings() -> Array[Dictionary]:
	return RINGS


## Index into `rings()` for a chunk distance from spawn. Negative distances
## are impossible from `distance_chunks` (Chebyshev of absolute deltas) but
## are clamped to the hearth rather than trusted, so a caller that computed
## a distance some other way cannot fall off the front of the table.
static func ring_index_at(distance: int) -> int:
	if distance <= 0:
		return 0
	for i in range(RINGS.size()):
		var outer: int = RINGS[i]["outer_chunks"]
		if outer == UNBOUNDED or distance <= outer:
			return i
	return RINGS.size() - 1


## The ring containing this chunk distance from spawn.
static func ring_at(distance: int) -> Dictionary:
	return RINGS[ring_index_at(distance)]


## The RegionDifficulty.Tier of the ring at this distance. This is the
## function that must never disagree with RegionDifficulty.tier_at, and the
## reason the ring bounds are read from its constants rather than retyped.
static func tier_at_distance(distance: int) -> int:
	return ring_at(distance)["tier"]


## What the ground at this distance expects a traveller to be carrying.
static func demands_at(distance: int) -> Array:
	return ring_at(distance)["demands"]


## Chebyshev, the same convention RegionDifficulty.tier_at computes inline
## and EarthChunkManager's LOAD_RADIUS math already uses -- a square ring of
## chunks, not a circle, because chunk streaming is square.
static func distance_chunks(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


## The ring newly entered by a step from `from_distance` to `to_distance`,
## or `{}` when both sit in the same ring.
##
## This exists so a caller can raise the crossing card exactly once, on the
## step that crossed, and never again while the player wanders inside the
## ring -- a banner that re-fires every frame teaches the player to stop
## reading banners.
##
## Inward crossings report too: coming home is also news, and a caller that
## wants only outward ones can compare `ring_index_at` on the two distances
## itself. A jump of several rings (a teleport, a load) reports the ring
## actually landed in rather than every ring passed over, because that is
## the one the player now has to survive.
static func crossing_between(from_distance: int, to_distance: int) -> Dictionary:
	var from_index: int = ring_index_at(from_distance)
	var to_index: int = ring_index_at(to_distance)
	if from_index == to_index:
		return {}
	return RINGS[to_index]


## This chunk distance in metres, so a player-facing card can say how far
## out this is in a unit a person owns rather than in chunks.
static func metres_from_spawn(distance: int) -> float:
	return float(distance) * METRES_PER_CHUNK


## The play-scale tile, in pixels, and the pixels a real metre is
## (GroundSlide.PX_PER_METER -- the player-height yardstick every other
## real-world-grounded size in this codebase is read against). Restated
## rather than preloaded for the same purity reason KM_PER_TILE is, and
## pinned against their real sources by test.
const TILE_SIZE_PX := 16
const PX_PER_METRE := 11.22


## How far `distance` chunks really is ON FOOT, in metres of ground.
##
## This project carries a deliberate scale fiction (see
## src/world/cave_network.gd's own note on it): the SAME chunk is 32 km of
## real Earth on the map and about 45 m of ground underfoot at play scale.
## Both are true and neither is a bug -- but they answer different
## questions, and a distance is only meaningful once it says which one it
## is.
##
## `metres_from_spawn` above is the planet's answer, and is what a map, a
## latitude or a climate band must use. THIS is the player's answer, and
## is what any line a player reads about walking somewhere must use: the
## same scale `SprintCost.burst_distance_metres` measures a sprint in, so
## "the village is 340 m away" and "one burst carries 80 m" are numbers
## that can honestly be compared.
##
## Found in adversarial review: this module reported the far country as
## 1 952 000 m while test_sprint_cost.gd measured the safe ring at 684 m
## from the same RegionDifficulty radii. Neither was wrong; the same word
## was doing two jobs.
static func walking_metres_from_spawn(distance: int) -> float:
	return float(distance) * float(CHUNK_SIZE_TILES) * float(TILE_SIZE_PX) / PX_PER_METRE
