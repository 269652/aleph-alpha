extends RefCounted

## Which seed actually becomes a plant (see docs/concept/flora.md#how-far-
## apart-flowers-stand-escape-from-the-parent).
##
## Reported live: flowers "spread or grow way too dense... the seeds should be
## carried a bit further by the wind and birds so it leaves more space between
## individual flowers".
##
## The dispersal kernel was not the thing that was wrong. Real wind dispersal
## IS heavy tailed -- most seed lands within a body-width or two of the parent
## (see WindDispersal / concept/seed_dispersal.md), and flattening that into a
## uniform scatter to buy spacing would replace a true mechanism with a
## cosmetic one. What was missing is the other half of the real process:
## **where seed lands and where a plant stands are two different
## distributions.** Seed that falls at its parent's foot overwhelmingly dies --
## it competes with an established root system for the same water and light,
## it sits in the highest concentration of that plant's own pathogens, and it
## is exactly where that plant's seed predators are already looking. Only the
## fraction that escapes the parent's neighbourhood becomes a plant. That is
## the Janzen-Connell effect, and it is the standard explanation for why a
## meadow reads as spaced individuals rather than as a mat around each parent.
##
## So this module is the ESTABLISHMENT distribution, and it is the only thing
## in the flower code that decides how far apart two plants may stand. It runs
## at every point a flower comes into being -- the baked meadow
## (MeadowSpread), rain rooting lying seed (FlowerPatch.root_seeds), and an
## animal dropping carried seed (FlowerPatch.plant) -- because a spacing rule
## some paths could route around would silently refill exactly the gaps it
## opened.
##
## Pure and engine-free: cells in, yes/no out.

## How close two flowers may stand, in tiles.
##
## Deliberately species-blind. Pathogen and seed-predator pressure is
## conspecific, but competition for light and root space is not -- two
## different forbs crowding the same handspan of soil shade each other exactly
## as much -- and the reported problem is about plants standing shoulder to
## shoulder, whatever they are.
##
## Bounded on both sides by test rather than by eye (see
## test_flower_establishment.gd): wide enough that no two flowers can stand in
## touching cells, side by side OR corner to corner (so it must exceed
## sqrt(2)); narrow enough that a meadow still holds a workable local density
## of blooms for a pollinator's circuit (see concept/flora.md#trap-lining) --
## this rule opens gaps between individuals, it does not empty the meadow.
##
## Note what this is NOT: it is a MINIMUM, not a lattice. It says how close
## two plants may stand and nothing at all about how far apart they end up, so
## clumps still form wherever the seed rain concentrates.
const MIN_SPACING_TILES := 2.5


## Whether a seed landing on `cell` can root there, given the plants already
## standing.
##
## `occupied` is anything iterating Vector2i cells -- an Array of them, or a
## Dictionary keyed by them (FlowerPatch holds cell -> species, MeadowSpread
## accumulates a list; both must read the same rule rather than each growing
## a copy of it).
##
## The spacing is a minimum, so a plant exactly `spacing_tiles` away does not
## block: it is "no closer than", not "further than".
static func is_clear(cell: Vector2i, occupied, spacing_tiles: float = MIN_SPACING_TILES) -> bool:
	var limit := spacing_tiles * spacing_tiles
	for other in occupied:
		var dx := float(cell.x - other.x)
		var dy := float(cell.y - other.y)
		# Real distance, not a bounding box: a square gate would refuse a cell
		# further away in a corner than one it accepts along an axis.
		if dx * dx + dy * dy < limit:
			return false
	return true


## ## A whole seed rain at once
##
## `is_clear` answers for one seed against plants that already stand -- the
## live case, where a bird drops seed into a meadow that is already there.
## Worldgen has the other problem: a whole lineage of seed landing at once,
## none of it standing yet, and no meaningful order to consider it in.
##
## Considering it in SOME order (place, then gate the next against it, and so
## on) makes the answer depend on where the sweep started -- and a chunk
## generator's sweep starts at its own chunk, so two chunks would place
## different plants on their shared boundary and the seams would be visible.
## This rule is instead order-independent: within a neighbourhood the seed
## with the most vigour takes, and which one that is does not depend on who
## asked or in what order. Every chunk therefore computes the identical answer
## for the identical ground.
##
## `rain` is an Array of {"cell": Vector2i, "rank": int} -- `rank` being that
## seed's own vigour, which the caller derives from the seed's own identity
## (never from its position in the list, which is exactly the order-dependence
## this avoids). Returns the surviving entries, untouched, in input order.
##
## Note this is deliberately not a MAXIMAL packing: where two strong seeds
## exclude a third between them, that gap stays open rather than being filled
## by a later pass. A meadow with gaps in it is the point.
static func survivors(rain: Array, spacing_tiles: float = MIN_SPACING_TILES) -> Array:
	var index := {}
	for entry in rain:
		var key := _bucket_of(entry["cell"], spacing_tiles)
		if not index.has(key):
			index[key] = []
		index[key].append(entry)

	var out: Array = []
	var limit := spacing_tiles * spacing_tiles
	for entry in rain:
		var cell: Vector2i = entry["cell"]
		var key := _bucket_of(cell, spacing_tiles)
		var beaten := false
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				for rival in index.get(key + Vector2i(dx, dy), []):
					var offset := Vector2(cell - rival["cell"])
					if offset.length_squared() >= limit:
						continue
					if _outranks(rival, entry):
						beaten = true
						break
				if beaten:
					break
			if beaten:
				break
		if not beaten:
			out.append(entry)
	return out


## A strict total order over the rain, so a dead heat still yields ONE plant.
## Vigour first; the cell breaks the tie, because two seeds on the same cell
## are the same plant anyway (the caller keys its meadow by cell, so they
## collapse).
static func _outranks(a: Dictionary, b: Dictionary) -> bool:
	if a["rank"] != b["rank"]:
		return a["rank"] > b["rank"]
	if a["cell"].x != b["cell"].x:
		return a["cell"].x > b["cell"].x
	return a["cell"].y > b["cell"].y


## Bucket edge = the spacing, which is what makes the 3x3 sweeps above
## sufficient: two cells less than `spacing_tiles` apart cannot differ by more
## than one bucket on either axis. floori (not integer division) because half
## the world has negative tile coordinates, and truncation toward zero would
## fold the two cells either side of the origin into one bucket.
static func _bucket_of(cell: Vector2i, spacing_tiles: float) -> Vector2i:
	var size := maxf(spacing_tiles, 0.001)
	return Vector2i(floori(float(cell.x) / size), floori(float(cell.y) / size))
