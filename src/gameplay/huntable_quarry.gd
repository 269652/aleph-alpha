extends RefCounted

const Butchering = preload("res://src/gameplay/butchering.gd")
const CreatureMass = preload("res://src/world/creature_mass.gd")

## What a village hunter is allowed to put a spear into, which one is
## nearest, and what the kill actually gives (see docs/concept/npc.md, "Work against the real world, not
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

## The group a hunter looks in. CreatureMarker.GROUP_NAME's own value,
## test-pinned to it (test_quarry_is_looked_for_in_the_creature_group) for
## the same reason the radius is: named here so this module states where
## quarry lives without importing the 3000-line marker that puts it there.
const QUARRY_GROUP_NAME := "creature"

## What one blow from a hunting villager takes off. CreatureMarker.
## ATTACK_DAMAGE's own value -- a villager bringing a deer down is doing
## exactly what a wolf does to the same deer, so it lands the same blow.
## That is LumberjackMarker.FELL_DAMAGE's own reasoning for matching
## Player.BASE_CHOP_DAMAGE ("an axe swing is an axe swing regardless of who
## swings it") pointed at the other verb, and it means a hunt takes as long
## as a predation does rather than as long as a number nobody chose.
## Test-pinned (test_strike_damage_matches_a_predators_own_bite).
const STRIKE_DAMAGE := 6.0

## How close a villager must be to land that blow, and therefore how close
## counts as having arrived. LumberjackMarker.ARRIVE_DISTANCE_PX's own
## value, test-pinned: "close enough to work on it" is one rule, not two.
## Small relative to a tile (TerrainRenderer.TILE_SIZE is 16) because
## move_toward closes asymptotically -- an exact-equality arrival would
## never fire at all.
const STRIKE_DISTANCE_PX := 4.0


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


## How much real meat `candidate` carries: exactly what a player butchering
## that same animal's carcass would cut out of it
## (Butchering.meat_count), against the animal's OWN live mass at this
## moment relative to its species reference (docs/concept/metabolism.md) --
## the same ratio CreatureMarker._spawn_carcass_if_eligible stamps onto the
## carcass it leaves. A well-fed deer feeds the village better than a
## starved one, and neither is a number this module invented.
##
## No skill bonus: SkillTree's butchering/meat_yield nodes are the player's
## to earn (docs/concept/carrion.md), so a villager gets the plain cut.
##
## 0 for nothing and for anything without a species record. Fail-open on
## the mass reading itself -- a candidate that cannot report its live mass
## yields the flat, mass-blind count, which is what every caller predating
## metabolism already got.
static func meat_yield_of(candidate) -> int:
	if candidate == null or not is_instance_valid(candidate):
		return 0
	var info = candidate.get("info")
	if info == null:
		return 0
	return Butchering.meat_count(0.0, _mass_ratio_of(candidate, info))


static func _mass_ratio_of(candidate, info) -> float:
	if not candidate.has_method("current_mass_kg"):
		return 1.0
	var reference_mass := CreatureMass.mass_kg_for(info.species)
	if reference_mass <= 0.0:
		return 1.0
	return candidate.current_mass_kg() / reference_mass
