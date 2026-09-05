extends RefCounted

## Following a smell to its source (see docs/concept/olfaction.md).
##
## Olfaction says what things smell of and what an animal makes of them; this
## turns that into somewhere to walk. Without it the whole system is a set of
## numbers nothing reads.
##
## Since docs/concept/ethogram.md (slice 2) the ranking itself is the
## behaviour kernel's: a smelled source becomes a stimulus that carries its
## own loudness at this range (Olfaction.dilution, the physics of smell) and
## BehaviorKernel.best_stimulus picks the best-smelling one on the smell
## channels with the individual's expressed receptors -- so a genome reaches
## the choice, and a boar born without a decay receptor is not led to
## carrion the species would go to. This file is the smell-sense adapter:
## sources in, stimuli out, and "which one, for this animal".
##
## Pure and engine-free, like the rest of the behaviour modules: this picks a
## target and says when an animal has arrived. Moving it, and taking the food,
## is the caller's job -- the same shape GrazerForaging and PiscivoreAppetite
## already use.

const Olfaction = preload("res://src/gameplay/olfaction.gd")
const Ethogram = preload("res://src/gameplay/ethogram.gd")
const BehaviorKernel = preload("res://src/gameplay/behavior_kernel.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

## How close an animal must be to actually take the food, in pixels.
##
## Much shorter than smelling range: an animal smells a windfall across a
## meadow and has to walk to it, which is the whole point of a gradient.
const EAT_DISTANCE_PX := 6.0

## Below this an animal is not interested enough to cross a field for it --
## the smell wiring's floor in the ethogram, not a second number.
const MIN_INTEREST := Ethogram.SMELL_INTEREST_FLOOR


## Whether this species hunts for food by smell at all -- that is, whether
## its ethogram record carries a nose (docs/concept/ethogram.md §3).
static func forages_by_smell(species: String) -> bool:
	return Ethogram.has_nose(species)


## Smelled sources ({position, mixture}, EarthChunkManager.smells_near's own
## shape) as stimuli the kernel can rank: each keeps its position, mixture
## and anything else it carried, and gains its `strength` at this range --
## Olfaction.dilution, so the kernel ranks by how loud a smell really is
## here rather than by its unit-free distance ranking.
static func stimuli_from(position: Vector2, sources: Array) -> Array:
	var stimuli: Array = []
	for source in sources:
		var at: Vector2 = source["position"]
		var tiles := position.distance_to(at) / float(TerrainRenderer.TILE_SIZE)
		var stimulus: Dictionary = source.duplicate()
		stimulus["strength"] = Olfaction.dilution(tiles)
		stimuli.append(stimulus)
	return stimuli


## The most appealing smell in reach, as the source dictionary itself, or an
## empty dictionary when nothing is worth walking to.
##
## Attraction already accounts for distance (see Olfaction.dilution), so the
## nearer of two identical smells wins because it is LOUDER -- not because
## of a tiebreak rule bolted on afterwards. `genome` is this individual's
## receptor genes; empty means the species template.
static func best_source(
	species: String, position: Vector2, sources: Array, genome: Dictionary = {}
) -> Dictionary:
	if not forages_by_smell(species):
		return {}
	var best := BehaviorKernel.best_stimulus(
		Ethogram.express(species, genome), Ethogram.SMELL_CHANNELS, position,
		stimuli_from(position, sources), 1.0, MIN_INTEREST, true
	)
	if best.is_empty():
		return {}
	return best["stimulus"]


## Whether an animal at `position` has reached the food at `target`.
static func can_eat(position: Vector2, target: Vector2) -> bool:
	return position.distance_to(target) <= EAT_DISTANCE_PX
