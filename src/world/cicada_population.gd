extends RefCounted

## Decides which of a chunk's real trees host a calling cicada RIGHT NOW
## (see docs/concept/creature_and_footstep_audio.md's "Cicadas" section).
## Reported live: "you can hear cicadas in the environment which don't
## exist... add them please as real ecosystem member and produce cicada
## sounds for each individual" -- what was actually audible was
## grassland_day.mp3's own honestly-credited "Grillen mit Hummeln" (crickets
## with bumblebees, see assets/audio/soundscape/CREDITS.md), not a cicada
## at all, but the underlying ask -- a real cicada presence, not a
## decorative loop -- is a genuine, separate improvement on its own merits.
##
## Real-world grounding: cicadas are the definitive "hot summer day" sound.
## Nymphs spend years underground; adults emerge for only a few summer
## weeks specifically to cling to a tree trunk/branch and call loudly for a
## mate, then die. No adult cicadas exist outside that window, and a real
## adult never leaves its tree. Pure "does this tree host one, right now"
## decision -- deliberately no growth/starvation/persistence economy the
## way AntColony/BeeColony get: a cicada's whole adult presence is short
## enough, and this game's own chunk load/unload cycle frequent enough,
## that a fresh roll per chunk load is an honest simplification of that
## same short-windowed real presence, not a missing feature.

const ACTIVE_SEASON := "summer"

## What fraction of a chunk's real trees host a calling cicada, once the
## season gate passes -- deliberately sparse: a chorus of dozens of trees
## all calling at once would be a wall of noise, not the real "your ear
## picks out an individual cicada or two nearby" experience. A real,
## gameplay-tuned constant (real cicada density varies enormously by
## species/location/emergence year -- no single citable number the way
## e.g. Kleiber's law gave caloric metabolism one), pinned by
## test_tree_density_is_a_real_sparse_fraction_not_eyeballed rather than an
## inline eyeballed number, the same discipline CreatureCallSound.
## CALL_CHANCE_PER_CHECK's own doc comment describes for itself.
const TREE_DENSITY := 0.15


static func is_active_in(season: String) -> bool:
	return season == ACTIVE_SEASON


## `roll_per_tree` is caller-supplied, one roll per tree, same index order
## the caller's own tree list uses -- the same "caller rolls, this pure
## function only decides" split CreatureCallSound.check_call already uses,
## so this stays deterministically testable rather than calling randf()
## itself.
static func cicada_tree_indices(tree_count: int, season: String, roll_per_tree: Array[float]) -> Array[int]:
	var indices: Array[int] = []
	if not is_active_in(season):
		return indices
	for i in tree_count:
		if roll_per_tree[i] < TREE_DENSITY:
			indices.append(i)
	return indices
