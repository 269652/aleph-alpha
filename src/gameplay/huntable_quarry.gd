extends RefCounted

## What a village hunter is allowed to put a spear into, and which one is
## nearest (see docs/concept/npc.md, "Work against the real world, not
## against a number").
##
## The predicate half of the hunt: ForagerBehavior decides WHEN a villager
## commits, walks and strikes, NpcMarker owns the world effect, and this
## decides WHAT counts. It is the direct analogue of
## LumberjackMarker._nearest_standing_tree's "live, still-standing" filter,
## pulled out into a pure module because an animal has four ways of being
## off-limits where a tree has one -- and because every one of those four
## is a design rule worth pinning in a test rather than burying in a scan
## loop.
##
## Duck-typed on the candidate, the same convention as the rest of this
## codebase's world reads (CreatureMarker.setup, NpcProduction): anything
## exposing `position` and `info` can be offered, and the optional
## questions fail OPEN -- a node that cannot answer is_tame() is wild.
## Nothing here imports CreatureMarker, so the whole rule set is testable
## headlessly against plain stubs.
##
## The four exclusions, each grounded in something already live rather than
## chosen:
##
## 1. **Not a predator.** NpcProduction keys a hunter's entire yield to
##    world.herbivore_population_near -- the regional number a hunter
##    already reads counts PREY. Taking wolves while being paid by the deer
##    count would be two mechanics disagreeing about what hunting is.
## 2. **Not a world boss.** BossAggro (docs/concept/worldbosses.md) turns a
##    boss hostile the moment it takes real damage. A villager wandering
##    out of the plaza and waking one is not a hunt, it is an accident the
##    village cannot survive -- and CreatureMarker.take_damage's own boss
##    branch makes it a coin-flip whether the blow even lands.
## 3. **Not tamed.** A tame animal belongs to somebody
##    (docs/concept/taming.md); Taming.is_tame is the same trust threshold
##    the player earns. A village that eats the player's tamed mount is a
##    bug, not emergence.
## 4. **Alive, and still really here.** Zero health is a Carcass's job (see
##    docs/concept/carrion.md), and a creature killed earlier this frame
##    stays in the "creature" group until the frame boundary -- the exact
##    hazard LumberjackMarker._target_still_here calls out for trees.

## How far a villager ranges from where they stand looking for quarry.
## LumberjackMarker.SEARCH_RADIUS_PX's own value, and test-pinned to it
## (test_search_radius_matches_the_lumberjacks_own_range) rather than
## copied as a literal: both are "a village worker ranges out toward the
## treeline/the herd rather than working their own doorstep", and two
## independently-picked radii for one behaviour would drift apart the first
## time either was touched. Not imported, to keep a gameplay rule free of a
## rendering-layer dependency.
const SEARCH_RADIUS_PX := 250.0


## Whether `candidate` is a real, living, wild, ordinary animal a village
## hunter may take. False for null, for anything without a species record,
## and for each of the four exclusions above.
static func is_quarry(candidate) -> bool:
	if candidate == null:
		return false
	if not is_instance_valid(candidate):
		return false
	if candidate.is_queued_for_deletion():
		return false
	var info = candidate.get("info")
	if info == null:
		return false
	if info.health <= 0.0:
		return false
	if info.is_predator or info.is_world_boss:
		return false
	if candidate.has_method("is_tame") and candidate.is_tame():
		return false
	return true


## The nearest quarry in `candidates` within `max_distance` of
## `from_position`, or null. Non-quarry is skipped no matter how close it
## is -- a tamed cow underfoot never shortens the walk to a real deer.
## Inclusive bound, matching LumberjackMarker._nearest_standing_tree's own
## `distance <= best_distance`.
static func nearest(
	candidates: Array, from_position: Vector2, max_distance := SEARCH_RADIUS_PX
):
	var best = null
	var best_distance := max_distance
	for candidate in candidates:
		if not is_quarry(candidate):
			continue
		var distance: float = from_position.distance_to(candidate.position)
		if distance <= best_distance:
			best = candidate
			best_distance = distance
	return best
