extends RefCounted

## A flower's own life through its season: opening, full, then withering.
##
## Distinct from NECTAR, which is a bloom's current CONTENTS and refills in
## about a minute (see PollinatorForaging.NECTAR_REGEN_PER_SECOND). A drained
## flower is a full flower that has just been visited; a withered flower is one
## at the end of its life. They look different, they mean different things, and
## only one of them is a reason to stop visiting.
##
## Conflating the two is a real bug this replaces: "spent" was drawn, and
## pollinators were told to avoid it, off the nectar level -- so a plant that
## had just been drained read as dead and its local pollinators stopped coming
## back to it, which is most of what a local pollinator does.

const FlowerSpecies = preload("res://src/world/flower_species.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")

## How far through its own bloom window a flower is when it starts to wither.
##
## Late: a flower spends most of its season worth visiting and goes over at the
## end of it. Which part of the YEAR that is depends entirely on the flower --
## a crocus is over before a rose has opened -- which is why this is a fraction
## of the species' own window rather than a date.
const WITHER_PHASE := 0.75


## How far through its bloom window this species is, 0 just opened to 1 gone
## over. Negative when it is not in bloom at all.
##
## `year_fraction` is 0..1 through the year (see SeasonCycle.year_fraction).
static func phase_at(species: String, year_fraction: float) -> float:
	var seasons: Array = FlowerSpecies.profile_for(species)["bloom"]
	if seasons.is_empty():
		return -1.0
	var season_count := SeasonCycle.SEASONS.size()
	var span := 1.0 / float(season_count)
	var position := fposmod(year_fraction, 1.0)
	var index := clampi(int(position * float(season_count)), 0, season_count - 1)
	var season_name: String = SeasonCycle.SEASONS[index]
	if not seasons.has(season_name):
		return -1.0

	# Where this season sits in the species' OWN run of blooming seasons, so a
	# flower that blooms across two seasons opens in the first and withers at
	# the end of the second rather than withering twice.
	var order := _bloom_order(seasons)
	var place := order.find(season_name)
	if place < 0:
		return -1.0
	var within := (position - float(index) * span) / span
	return (float(place) + within) / float(order.size())


## Whether this species is past its best at this point in the year.
static func is_withered(species: String, year_fraction: float) -> bool:
	var phase := phase_at(species, year_fraction)
	if phase < 0.0:
		return false
	return is_withered_at_phase(phase)


static func is_withered_at_phase(phase: float) -> bool:
	return phase >= WITHER_PHASE


## The species' blooming seasons in the order it actually lives through them.
##
## Sorted by the season cycle rather than by however the species listed them,
## and rotated so a window that wraps the year end (a crocus blooming winter
## into spring) reads as one run rather than as two ends of the calendar.
static func _bloom_order(seasons: Array) -> Array:
	var ordered: Array = []
	for season_name in SeasonCycle.SEASONS:
		if seasons.has(season_name):
			ordered.append(season_name)
	if ordered.size() < 2:
		return ordered
	# A wrapping window: the run is broken if the first and last listed seasons
	# are adjacent across the year end.
	var first_index := SeasonCycle.SEASONS.find(ordered[0])
	var last_index := SeasonCycle.SEASONS.find(ordered[ordered.size() - 1])
	var wraps := (
		first_index == 0
		and last_index == SeasonCycle.SEASONS.size() - 1
		and ordered.size() < SeasonCycle.SEASONS.size()
	)
	if wraps:
		# Start at the season after the gap, so winter->spring is one run.
		var rotated: Array = []
		var start := last_index
		for step in SeasonCycle.SEASONS.size():
			var name: String = SeasonCycle.SEASONS[(start + step) % SeasonCycle.SEASONS.size()]
			if seasons.has(name):
				rotated.append(name)
		return rotated
	return ordered
