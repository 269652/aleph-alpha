extends RefCounted

## Following a smell to its source (see docs/concept/olfaction.md).
##
## Olfaction says what things smell of and what an animal makes of them; this
## turns that into somewhere to walk. Without it the whole system is a set of
## numbers nothing reads.
##
## Pure and engine-free, like the rest of the behaviour modules: this picks a
## target and says when an animal has arrived. Moving it, and taking the food,
## is the caller's job -- the same shape GrazerForaging and PiscivoreAppetite
## already use.

const Olfaction = preload("res://src/gameplay/olfaction.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

## How close an animal must be to actually take the food, in pixels.
##
## Much shorter than smelling range: an animal smells a windfall across a
## meadow and has to walk to it, which is the whole point of a gradient.
const EAT_DISTANCE_PX := 6.0

## Below this an animal is not interested enough to cross a field for it.
## Without a floor, a creature would trail after the faintest trace of
## something it barely likes instead of getting on with its life.
const MIN_INTEREST := 0.02


## Whether this species hunts for food by smell at all.
static func forages_by_smell(species: String) -> bool:
	return Olfaction.has_nose(species)


## The most appealing smell in reach, as the source dictionary itself, or an
## empty dictionary when nothing is worth walking to.
##
## `sources` are {position, mixture}. Attraction already accounts for distance
## (see Olfaction.dilution), so the nearer of two identical smells wins because
## it is LOUDER -- not because of a tiebreak rule bolted on afterwards.
static func best_source(species: String, position: Vector2, sources: Array) -> Dictionary:
	if not forages_by_smell(species):
		return {}
	var best := {}
	var best_pull := MIN_INTEREST
	for source in sources:
		var at: Vector2 = source["position"]
		var tiles := position.distance_to(at) / float(TerrainRenderer.TILE_SIZE)
		var pull := Olfaction.attraction_to(species, source["mixture"], tiles)
		if pull > best_pull:
			best_pull = pull
			best = source
	return best


## Whether an animal at `position` has reached the food at `target`.
static func can_eat(position: Vector2, target: Vector2) -> bool:
	return position.distance_to(target) <= EAT_DISTANCE_PX
