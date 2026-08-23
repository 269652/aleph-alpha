extends GutTest

## PollinatorForaging (see docs/concept/flora.md).
##
## These exist because two shipped bugs were each one assertion away from
## being caught: a pollinator that landed on a bloom but never registered the
## visit (so it re-targeted the same flower forever), and one that kept
## choosing a flower it had already drained.

const PollinatorForaging = preload("res://src/gameplay/pollinator_foraging.gd")
const ScentField = preload("res://src/world/scent_field.gd")


const TILE_SIZE := 16.0


func _flower(position: Vector2, nectar: float = 1.0) -> Dictionary:
	return {"position": position, "species": "rose", "nectar": nectar}


## A bloom a known number of TILES away along +x -- so distance-ordering
## assertions read in the same units the constants are expressed in.
func _at_tiles(tiles: float, nectar: float = 1.0) -> Dictionary:
	return _flower(Vector2(tiles * TILE_SIZE, 0.0), nectar)


func test_the_nearest_full_flower_is_chosen():
	var chosen := PollinatorForaging.choose_target(
		Vector2.ZERO, [_flower(Vector2(100, 0)), _flower(Vector2(20, 0))], []
	)
	assert_eq(chosen["position"], Vector2(20, 0))


## A drained bloom is not worth flying to.
## An UNCHECKED flower is always worth flying to, empty or not: a pollinator
## cannot see nectar from a distance, it lands to find out (reported:
## "somehow they know it's empty without checking for nectar first"). What
## makes a bloom unavailable is having personally checked it -- see
## test_a_freshly_checked_flower_is_not_immediately_revisited.
func test_an_empty_but_unchecked_flower_is_still_chosen():
	var chosen := PollinatorForaging.choose_target(
		Vector2.ZERO, [_flower(Vector2(10, 0), 0.0)], []
	)
	assert_false(chosen.is_empty())


## THE bug: a visited flower must be skipped, or the pollinator bounces off
## the same bloom forever.
func test_a_visited_flower_is_skipped_for_the_next_one():
	# Equidistant enough to be tied on distance, so memory is what decides
	# (see SCATTER_BAND_TILES -- across a wider gap the nearer bloom wins
	# whether or not it was recently visited).
	var flowers := [_at_tiles(2.0), _at_tiles(2.8)]
	var visited := PollinatorForaging.remember_visit([], Vector2(2.0 * TILE_SIZE, 0.0), 0.0)
	var chosen := PollinatorForaging.choose_target(Vector2.ZERO, flowers, visited, 0.0)
	assert_almost_eq(chosen["position"].x / TILE_SIZE, 2.8, 0.01)


## Visited positions are rebuilt from tile coords each query, so exact float
## equality would silently never match -- the comparison must tolerate a
## small offset or the memory is useless.
func test_visit_memory_matches_a_nearly_identical_position():
	# Asserted through the PREFERENCE (see choose_target): the remembered
	# flower is the nearer of the two, so it can only lose to the other if
	# the nudged position was recognised as the same flower. Both blooms sit
	# inside SCATTER_BAND_TILES of each other, so they are genuinely tied on
	# distance and memory is what decides -- with a wider gap distance would
	# rightly win regardless of what was remembered.
	var flowers := [_at_tiles(2.0), _at_tiles(2.8)]
	var nudged := Vector2(2.0 * TILE_SIZE + PollinatorForaging.LANDING_DISTANCE * 0.4, 0.0)
	var visited := PollinatorForaging.remember_visit([], nudged, 0.0)
	assert_almost_eq(
		PollinatorForaging.choose_target(Vector2.ZERO, flowers, visited, 0.0)["position"].x
			/ TILE_SIZE,
		2.8, 0.01,
		"a position within landing distance is the same flower"
	)


## Visit memory RANKS, it does not blacklist. Measured before this changed: a
## pollinator drained the four flowers in its reach in the first simulated
## minute and then did nothing at all for the next nine, resuming only once
## VISIT_MEMORY_SECONDS expired -- even though every one of those flowers was
## back to full nectar within ~20s (NECTAR_REGEN_PER_SECOND). The memory was
## 30x the refill time it is documented to be measured against, so it vetoed
## a meadow that had already recovered (reported: "when all nearby are empty
## butterflies and bees stop foraging completely and just drift around
## meaninglessly"). A remembered flower that has REFILLED is worth visiting
## again -- it just loses to any unvisited one.
## Visit memory now VETOES for its duration and then expires, rather than
## merely ranking. Requested: "butterflies should forget which flowers they
## visited after a reasonable time so they can check same flowers again after
## a while to see if nectar restocked." So a bloom checked a moment ago is
## off the table, and the SAME bloom is back on it once the memory ages out
## (VISIT_MEMORY_SECONDS, deliberately set a little longer than a bloom takes
## to refill -- see NECTAR_REGEN_PER_SECOND).
func test_a_freshly_checked_flower_is_not_immediately_revisited():
	var visited := PollinatorForaging.remember_visit([], Vector2(10, 0), 0.0)
	var chosen := PollinatorForaging.choose_target(
		Vector2.ZERO, [_flower(Vector2(10, 0), 1.0)], visited, 1.0
	)
	assert_true(chosen.is_empty(), "it should not re-land on a bloom it checked a second ago")


func test_a_flower_is_worth_checking_again_once_the_memory_expires():
	var visited := PollinatorForaging.remember_visit([], Vector2(10, 0), 0.0)
	var later := PollinatorForaging.VISIT_MEMORY_SECONDS + 1.0
	var chosen := PollinatorForaging.choose_target(
		Vector2.ZERO, [_flower(Vector2(10, 0), 1.0)], visited, later
	)
	assert_false(chosen.is_empty(), "once forgotten, the bloom is worth checking again")
	assert_eq(chosen["position"], Vector2(10, 0))


## ...but among blooms that are equally close, an unvisited one still WINS
## over a slightly nearer remembered one, so the pollinator works its way
## across a patch instead of re-drinking a single bloom (the original reason
## the memory exists). Only within SCATTER_BAND_TILES, though -- memory is a
## tie-breaker, not a licence to cross the meadow (see
## test_a_far_bloom_is_never_targeted_while_near_ones_are_available).
func test_an_unvisited_flower_is_preferred_over_a_nearer_remembered_one():
	var flowers := [_at_tiles(2.0), _at_tiles(2.8)]
	var visited := PollinatorForaging.remember_visit([], Vector2(2.0 * TILE_SIZE, 0.0), 0.0)
	var chosen := PollinatorForaging.choose_target(Vector2.ZERO, flowers, visited, 1.0)
	assert_almost_eq(
		chosen["position"].x / TILE_SIZE, 2.8, 0.01,
		"unvisited wins over an equally-close remembered bloom"
	)


## "Nothing to commit to" now means every bloom in reach has been CHECKED by
## this flyer, not that every bloom happens to be empty (which it has no way
## of knowing until it lands).
func test_nothing_is_chosen_only_when_every_bloom_has_been_checked():
	var flowers := [_flower(Vector2(10, 0), 0.0), _flower(Vector2(30, 0), 0.0)]
	var one_checked := PollinatorForaging.remember_visit([], Vector2(30, 0), 0.0)
	assert_false(
		PollinatorForaging.choose_target(Vector2.ZERO, flowers, one_checked, 0.0).is_empty(),
		"the unchecked bloom is still worth investigating"
	)

	var both_checked := PollinatorForaging.remember_visit(one_checked, Vector2(10, 0), 0.0)
	assert_true(
		PollinatorForaging.choose_target(Vector2.ZERO, flowers, both_checked, 0.0).is_empty(),
		"with both already checked there is nothing here -- go and search elsewhere"
	)


## A pollinator whose own neighbourhood is worked out must be able to look
## FURTHER, not give up: real bees forage well beyond the few metres a single
## scent plume carries. Pinned as a relation, not a bare number -- the ranged
## search only means anything if it reaches past where scent alone does.
func test_the_ranged_search_reaches_further_than_scent_alone():
	assert_gt(PollinatorForaging.FORAGE_SEARCH_TILES, ScentField.RADIUS_TILES)


## And when even the ranged search finds nothing, it must MOVE rather than
## orbit -- a relocation step big enough to actually leave the area it just
## searched, or it would simply re-search the same empty ground forever.
func test_a_relocation_step_actually_leaves_the_searched_area():
	assert_gt(PollinatorForaging.RELOCATION_STEP_TILES, ScentField.RADIUS_TILES)


## Relocation has to be LEASHED, or the cure is worse than the disease.
## Measured with an unleashed relocation: a flyer with nothing to eat random-
## walked 93 tiles from where it spawned, and when a full meadow appeared
## back at its spawn it saw zero flowers, drank nothing, and ended 97 tiles
## away -- drift had become an absorbing state (reported: "don't resume
## foraging when they encounter new flowers"; they never encounter any). The
## leash must still be wider than the ranged search, or ranging out to a
## neighbouring patch would be pointless...
func test_the_relocation_leash_still_allows_a_full_ranged_search():
	assert_gt(PollinatorForaging.MAX_RELOCATION_TILES, PollinatorForaging.FORAGE_SEARCH_TILES)


## ...but must stay inside the chunk neighbourhood the flower lookup actually
## covers (EarthChunkManager.flowers_near only scans the 3x3 chunks around
## the flyer, and only loaded ones have flower patches at all), or a flyer
## that wandered past it is permanently blind no matter what is really there.
func test_the_relocation_leash_stays_within_the_flower_lookups_reach():
	assert_lt(PollinatorForaging.MAX_RELOCATION_TILES, 32.0)


# -- scatter: don't all fly the same route -----------------------------------
#
# Measured before this existed: eight pollinators standing in the same spot
# with the same six flowers in front of them all chose the identical bloom
# (x=100) every time -- choose_target was purely "nearest wins", so every
# flyer in an area computed the same answer, conga-lined along one route, and
# only the leader ever got nectar (reported: "flyers should randomly select
# the next flowers from the nearest so that not all bees and butterflies fly
# the same route following each other and only the first gets nectar").


## Blooms spaced closely enough to be genuinely tied on distance -- which is
## the only situation scatter applies to now (see SCATTER_BAND_TILES). Spread
## these out and the nearest rightly wins for everyone.
func test_pollinators_in_the_same_spot_do_not_all_pick_the_same_flower():
	var flowers: Array = []
	for i in 6:
		flowers.append(_at_tiles(2.0 + float(i) * 0.25))
	var chosen := {}
	for pollinator in 8:
		var target := PollinatorForaging.choose_target(
			Vector2.ZERO, flowers, [], 0.0, hash("pollinator_%d" % pollinator)
		)
		chosen[target["position"]] = true
	assert_gt(chosen.size(), 1, "identical pollinators must not converge on one bloom")


## Scatter must not become "fly anywhere": the pool is the NEAREST few, so a
## pollinator still works the patch in front of it rather than crossing the
## meadow.
func test_the_scatter_pool_is_drawn_from_the_nearest_blooms_only():
	var flowers: Array = []
	for i in 12:
		flowers.append(_flower(Vector2(100.0 + float(i) * 25.0, 0.0)))
	var furthest_allowed := 100.0 + float(PollinatorForaging.NEAREST_CANDIDATE_POOL - 1) * 25.0
	for pollinator in 40:
		var target := PollinatorForaging.choose_target(
			Vector2.ZERO, flowers, [], 0.0, hash("pollinator_%d" % pollinator)
		)
		assert_lte(
			target["position"].x, furthest_allowed,
			"should still pick from the nearest blooms, not fly across the meadow"
		)


## Deterministic per pollinator: the same flyer facing the same meadow makes
## the same choice, so behaviour is reproducible rather than depending on
## global RNG state.
func test_the_same_pollinator_makes_the_same_choice_for_the_same_meadow():
	var flowers: Array = []
	for i in 6:
		flowers.append(_flower(Vector2(100.0 + float(i) * 25.0, 0.0)))
	var first := PollinatorForaging.choose_target(Vector2.ZERO, flowers, [], 0.0, 12345)
	var second := PollinatorForaging.choose_target(Vector2.ZERO, flowers, [], 0.0, 12345)
	assert_eq(first["position"], second["position"])


## THE REAL-WORLD REGRESSION. Measured in a live Berlin world (real chunks,
## real FlowerPatch data, one real monarch, 24 sampled commits): mean chosen
## distance 5.83 tiles against a mean nearest-available of 4.26, worst commit
## 14.40 tiles, and 9 of those 24 commits more than 2 tiles worse than the
## nearest bloom on offer -- "chose 8.5 (nearest 3.2)", "chose 11.7 (nearest
## 7.8)". Reported as "it's moving past dozens of flowers and doesn't even
## check if they have nectar".
##
## Cause: picking uniformly among a fixed COUNT of nearest blooms. In a real
## meadow the third-nearest is routinely 2-3x further than the first, so two
## thirds of commits were to a visibly-further flower. The synthetic 1/2/3-
## tile fixtures below could never catch it, because at that spacing the
## pool's spread is negligible -- which is exactly why this shipped green.
##
## The guard: whatever is chosen must never be more than SCATTER_BAND_TILES
## further than the nearest bloom actually available.
func test_a_realistic_meadow_never_commits_far_past_the_nearest_bloom():
	var flowers := [_at_tiles(2.0), _at_tiles(4.5), _at_tiles(9.0)]
	for pollinator in 200:
		var target := PollinatorForaging.choose_target(
			Vector2.ZERO, flowers, [], 0.0, hash("pollinator_%d" % pollinator)
		)
		var chosen_tiles: float = target["position"].x / TILE_SIZE
		assert_lte(
			chosen_tiles - 2.0, PollinatorForaging.SCATTER_BAND_TILES,
			"committed to a bloom %.1f tiles out with one at 2.0 available" % chosen_tiles
		)


## The other half of the same rule: blooms that really ARE near-equidistant
## still scatter, so a swarm doesn't queue up behind one flower. Both wants
## are legitimate -- distance decides, and scatter breaks genuine ties.
func test_near_equidistant_blooms_still_scatter():
	var flowers := [_at_tiles(2.0), _at_tiles(2.3), _at_tiles(2.5)]
	var chosen := {}
	for pollinator in 60:
		var target := PollinatorForaging.choose_target(
			Vector2.ZERO, flowers, [], 0.0, hash("pollinator_%d" % pollinator)
		)
		chosen[target["position"].x] = true
	assert_gt(chosen.size(), 1, "genuinely tied blooms must still spread the swarm")


## The band has to be tight enough that a clearly-closer bloom always wins
## (the 2.0-vs-4.5 case above turns on this)...
func test_the_scatter_band_is_tight_enough_to_prefer_a_clearly_nearer_bloom():
	assert_lt(PollinatorForaging.SCATTER_BAND_TILES, 2.5)


## ...and wide enough that blooms a normal flower-spacing apart still count
## as tied, or scatter collapses to "always the single nearest" and the
## conga-line comes back.
func test_the_scatter_band_is_wide_enough_to_admit_a_genuine_tie():
	assert_gt(PollinatorForaging.SCATTER_BAND_TILES, 0.5)


## REGRESSION, pinned with explicit distances: nearness dominates, always.
##
## Measured before this held: with the three nearest blooms sitting in visit
## memory, a pollinator's targets over 200 seeds were the ones 20, 50 and 100
## tiles away -- it flew past a refilled bloom one tile from its nose to cross
## the meadow (reported: "they ignore most flowers and target some much
## further away than the nearest"). The unvisited/remembered split was being
## applied to the WHOLE candidate list before distance was considered, so any
## unvisited flower at any range outranked every remembered one however close.
## Since a continuously-foraging flyer remembers precisely its own local
## patch, that systematically drove it away from it.
func test_a_far_bloom_is_never_targeted_while_near_ones_are_available():
	var flowers := [
		_at_tiles(1.0), _at_tiles(2.0), _at_tiles(3.0),
		_at_tiles(20.0), _at_tiles(50.0), _at_tiles(100.0),
	]
	# Every near bloom recently visited -- and long since refilled.
	var visited: Array = []
	for tiles in [1.0, 2.0, 3.0]:
		visited = PollinatorForaging.remember_visit(
			visited, Vector2(tiles * TILE_SIZE, 0.0), 0.0
		)
	# With every NEAR bloom already checked, the answer is usually "nothing
	# here" -- the caller then searches (relocates) rather than committing to
	# a bloom 20+ tiles away. Either way the guarantee is the same one this
	# test has always made: it must not cross the meadow.
	#
	# Counted rather than asserted inside the branch: once the veto made
	# "nothing here" the normal answer, an assertion that only ran when
	# something WAS chosen stopped running at all, and the test passed for
	# 200 iterations while checking nothing.
	var crossed_the_meadow := 0
	for pollinator in 200:
		var target := PollinatorForaging.choose_target(
			Vector2.ZERO, flowers, visited, 30.0, hash("pollinator_%d" % pollinator)
		)
		if not target.is_empty() and target["position"].x / TILE_SIZE > 3.0:
			crossed_the_meadow += 1
	assert_eq(
		crossed_the_meadow, 0,
		"must forage the near patch, not cross the meadow to an unvisited bloom"
	)


## The same guarantee with nothing remembered at all, and with the flowers
## handed over in a deliberately unhelpful order -- the pool must be the
## nearest by DISTANCE, not by however the flower index happened to list them.
func test_the_near_pool_is_by_distance_not_by_list_order():
	var flowers := [
		_at_tiles(100.0), _at_tiles(2.0), _at_tiles(50.0),
		_at_tiles(1.0), _at_tiles(20.0), _at_tiles(3.0),
	]
	for pollinator in 200:
		var target := PollinatorForaging.choose_target(
			Vector2.ZERO, flowers, [], 0.0, hash("pollinator_%d" % pollinator)
		)
		assert_lte(target["position"].x / TILE_SIZE, 3.0, "pool must be the nearest three")


## Visit memory still does its job, but only WITHIN the near pool: among
## blooms that are all close by, an unvisited one still wins.
func test_visit_memory_still_breaks_ties_among_the_near_blooms():
	# All three within SCATTER_BAND_TILES of each other, so they are tied on
	# distance and memory is what separates them.
	var flowers := [_at_tiles(2.0), _at_tiles(2.4), _at_tiles(2.8)]
	var visited: Array = []
	for tiles in [2.0, 2.4]:
		visited = PollinatorForaging.remember_visit(
			visited, Vector2(tiles * TILE_SIZE, 0.0), 0.0
		)
	for pollinator in 50:
		var target := PollinatorForaging.choose_target(
			Vector2.ZERO, flowers, visited, 30.0, hash("pollinator_%d" % pollinator)
		)
		assert_almost_eq(
			target["position"].x / TILE_SIZE, 2.8, 0.01,
			"the one near bloom it hasn't just drained should win among near candidates"
		)


## And scatter still holds once nearness has been enforced.
func test_near_blooms_are_still_scattered_across():
	var flowers := [_at_tiles(1.0), _at_tiles(2.0), _at_tiles(3.0), _at_tiles(40.0)]
	var chosen := {}
	for pollinator in 40:
		var target := PollinatorForaging.choose_target(
			Vector2.ZERO, flowers, [], 0.0, hash("pollinator_%d" % pollinator)
		)
		chosen[target["position"].x] = true
	assert_gt(chosen.size(), 1, "pollinators must still spread across the near blooms")


# -- peer claims: don't queue up behind another flyer ------------------------
#
# Measured in a real world: 62.1% of pollinator pairs within four tiles of
# each other were flying to the SAME bloom, because the distance band holds
# exactly one candidate 86.5% of the time and the per-flyer scatter seed then
# has nothing to choose between. The leader drains it and the followers
# arrive at an empty flower -- mean nectar found on arrival was 0.182
# (reported: "there are still butterfly chains happening where each butterfly
# flies to the same next flower").
#
# Claims DEMOTE rather than exclude. A claim is a statement of intent, not
# ownership: it must never make a flyer skip a closer bloom, and never leave
# it with nothing to do.


func test_a_bloom_another_flyer_is_heading_for_is_passed_over():
	var flowers := [_at_tiles(2.0), _at_tiles(2.4)]
	var claimed := [Vector2(2.0 * TILE_SIZE, 0.0)]
	for pollinator in 40:
		var target := PollinatorForaging.choose_target(
			Vector2.ZERO, flowers, [], 0.0, hash("pollinator_%d" % pollinator), claimed
		)
		assert_almost_eq(
			target["position"].x / TILE_SIZE, 2.4, 0.01,
			"should head for the bloom no one else has committed to"
		)


## The demotion rule: when EVERY candidate in the band is spoken for, the
## flyer still goes to one rather than stalling. Chaining is better than
## drifting with nothing to do.
func test_a_claimed_bloom_is_still_chosen_when_it_is_the_only_one():
	var flowers := [_at_tiles(2.0)]
	var claimed := [Vector2(2.0 * TILE_SIZE, 0.0)]
	var target := PollinatorForaging.choose_target(
		Vector2.ZERO, flowers, [], 0.0, 1234, claimed
	)
	assert_false(target.is_empty(), "a claimed bloom beats no bloom at all")
	assert_almost_eq(target["position"].x / TILE_SIZE, 2.0, 0.01)


## And claims must never break the distance guarantee: a claimed bloom right
## next to the flyer still wins over an unclaimed one across the meadow.
## Demotion happens strictly WITHIN the band, so it can never pull a flyer
## past a much closer flower (the bug fixed by SCATTER_BAND_TILES).
func test_a_claim_never_sends_a_flyer_past_a_much_closer_bloom():
	var flowers := [_at_tiles(2.0), _at_tiles(30.0)]
	var claimed := [Vector2(2.0 * TILE_SIZE, 0.0)]
	for pollinator in 40:
		var target := PollinatorForaging.choose_target(
			Vector2.ZERO, flowers, [], 0.0, hash("pollinator_%d" % pollinator), claimed
		)
		assert_almost_eq(
			target["position"].x / TILE_SIZE, 2.0, 0.01,
			"a claim must not be worth crossing the meadow to avoid"
		)


## Claims are matched with the same positional tolerance as visit memory --
## a bloom's world position is rebuilt from its cell on every query, so exact
## float equality would silently never match and the whole mechanism would
## quietly do nothing.
func test_a_claim_matches_a_nearly_identical_position():
	var flowers := [_at_tiles(2.0), _at_tiles(2.4)]
	var nudged := Vector2(2.0 * TILE_SIZE + PollinatorForaging.LANDING_DISTANCE * 0.4, 0.0)
	var target := PollinatorForaging.choose_target(
		Vector2.ZERO, flowers, [], 0.0, 99, [nudged]
	)
	assert_almost_eq(
		target["position"].x / TILE_SIZE, 2.4, 0.01,
		"a claim within landing distance is the same bloom"
	)


## Unclaimed candidates still scatter among themselves -- avoiding peers must
## not collapse the swarm onto one alternative.
func test_unclaimed_blooms_still_scatter():
	var flowers := [_at_tiles(2.0), _at_tiles(2.3), _at_tiles(2.5), _at_tiles(2.7)]
	var claimed := [Vector2(2.0 * TILE_SIZE, 0.0)]
	var chosen := {}
	for pollinator in 60:
		var target := PollinatorForaging.choose_target(
			Vector2.ZERO, flowers, [], 0.0, hash("pollinator_%d" % pollinator), claimed
		)
		chosen[target["position"].x] = true
	assert_gt(chosen.size(), 1, "the remaining blooms must still spread the swarm")


## Passing no claims at all leaves every existing property untouched.
func test_no_claims_behaves_exactly_as_before():
	var flowers := [_at_tiles(2.0), _at_tiles(2.4)]
	var with_empty := PollinatorForaging.choose_target(Vector2.ZERO, flowers, [], 0.0, 77, [])
	var without := PollinatorForaging.choose_target(Vector2.ZERO, flowers, [], 0.0, 77)
	assert_eq(with_empty["position"], without["position"])


## Scatter never overrides the rules that DO apply: a bloom this pollinator
## has already checked stays unchosen no matter which flyer is asking.
##
## Nectar level is deliberately NOT one of those rules any more. A pollinator
## cannot see how full a flower is from across the meadow -- it finds out by
## landing -- so a drained-but-unchecked bloom is still a candidate (reported:
## "somehow they know it's empty without checking for nectar first"). What
## takes a bloom off the table is having personally visited it, until that
## memory ages out.
func test_scatter_never_picks_an_already_visited_bloom():
	var near_visited := Vector2(10, 0)
	var flowers := [_flower(near_visited, 1.0), _flower(Vector2(200, 0), 1.0)]
	var visited := PollinatorForaging.remember_visit([], near_visited, 0.0)
	for pollinator in 20:
		var target := PollinatorForaging.choose_target(
			Vector2.ZERO, flowers, visited, 0.0, hash("p_%d" % pollinator)
		)
		# Either nothing (the far bloom is outside the scatter band, so there
		# is genuinely nothing near worth taking) or the far one -- never the
		# bloom this flyer just checked.
		assert_ne(
			target.get("position", Vector2.INF), near_visited,
			"a bloom it just checked is never a candidate"
		)


## The other half: an unchecked bloom IS worth flying to even with no nectar
## left in it, because the pollinator has no way of knowing that yet.
func test_an_unvisited_but_drained_bloom_is_still_worth_checking():
	var flowers := [_flower(Vector2(10, 0), 0.0)]
	var target := PollinatorForaging.choose_target(Vector2.ZERO, flowers, [], 0.0, 1)
	assert_false(target.is_empty(), "it must fly over and check rather than divine the nectar level")


## And once every bloom in reach has been checked, there is nothing to commit
## to -- the caller ranges elsewhere instead of re-landing on a flower it
## just found empty (which is what orbiting a spent bloom looked like).
func test_nothing_is_chosen_once_every_bloom_in_reach_has_been_checked():
	var flowers := [_flower(Vector2(10, 0), 1.0), _flower(Vector2(30, 0), 1.0)]
	var visited := PollinatorForaging.remember_visit([], Vector2(10, 0), 0.0)
	visited = PollinatorForaging.remember_visit(visited, Vector2(30, 0), 0.0)
	assert_true(PollinatorForaging.choose_target(Vector2.ZERO, flowers, visited, 0.0, 1).is_empty())


func test_an_empty_meadow_yields_no_target():
	assert_true(PollinatorForaging.choose_target(Vector2.ZERO, [], []).is_empty())


# -- memory now EXPIRES rather than being merely count-bounded ---------------
#
# Explicit correction: "bees and butterflies should remember emptied flowers
# for only 10 minutes or so". A pollinator that just drained the only nearby
# bloom used to be stuck avoiding it (and, combined with the scent gradient
## still pulling toward a drained flower -- see ambient_flyer_marker.gd --
# orbiting it) for the rest of the session, since the old memory only forgot
# by COUNT (its oldest entry), not by time.

func test_a_recently_visited_flower_stays_forgotten_within_the_memory_window():
	# Still remembered => still passed over for an alternative. (It is no
	# longer REFUSED outright when it's the only nectar left -- see
	# test_a_remembered_flower_that_has_refilled_is_still_worth_visiting.)
	var visited := PollinatorForaging.remember_visit([], Vector2(2.0 * TILE_SIZE, 0.0), 100.0)
	var chosen := PollinatorForaging.choose_target(
		Vector2.ZERO, [_at_tiles(2.0), _at_tiles(2.8)], visited,
		100.0 + PollinatorForaging.VISIT_MEMORY_SECONDS - 1.0
	)
	assert_almost_eq(
		chosen["position"].x / TILE_SIZE, 2.8, 0.01,
		"should still be remembered just under the window"
	)


func test_a_visited_flower_becomes_choosable_again_after_the_memory_window():
	var visited := PollinatorForaging.remember_visit([], Vector2(10, 0), 100.0)
	var chosen := PollinatorForaging.choose_target(
		Vector2.ZERO, [_flower(Vector2(10, 0))], visited,
		100.0 + PollinatorForaging.VISIT_MEMORY_SECONDS + 1.0
	)
	assert_false(chosen.is_empty(), "an aged-out flower should be visitable again")


func test_remember_visit_prunes_expired_entries_so_memory_does_not_grow_forever():
	var visited: Array = []
	# 1000s between each visit, comfortably past VISIT_MEMORY_SECONDS (600s) --
	# every entry but the most recent handful should have aged out by the end.
	for i in 50:
		visited = PollinatorForaging.remember_visit(visited, Vector2(float(i) * 50.0, 0.0), float(i) * 1000.0)
	assert_lt(visited.size(), 50, "expired visits should have been pruned, not kept forever")


## The time window alone no longer bounds this usefully. Once foraging
## actually runs continuously (rather than idling out most of the memory
## window, as it did while visits were vetoed), a pollinator banks a visit
## every few seconds -- measured at 205 live entries after 15 simulated
## minutes, and it scales with forage rate. Every entry is distance-checked
## against every candidate flower on every sniff, for every pollinator on
## screen, so this is the same per-frame cost the chunk manager already had
## to cap when scoring meadows (see _POLLINATOR_PROBE_LIMIT). Keeping only
## the most recent N is sound: those are the flowers still within reach.
func test_visit_memory_is_bounded_even_under_continuous_foraging():
	var visited: Array = []
	# 400 visits a few seconds apart -- all well inside VISIT_MEMORY_SECONDS,
	# so the time window prunes none of them.
	for i in 400:
		visited = PollinatorForaging.remember_visit(
			visited, Vector2(float(i) * 50.0, 0.0), float(i) * 3.0
		)
	assert_lte(
		visited.size(), PollinatorForaging.MAX_REMEMBERED_VISITS,
		"visit memory must stay bounded when a pollinator forages continuously"
	)


## The cap must not silently shorten the effective memory to nothing -- it
## still has to cover the flowers a pollinator can actually reach.
func test_the_visit_memory_cap_still_covers_a_full_forage_radius():
	assert_gt(PollinatorForaging.MAX_REMEMBERED_VISITS, 16)


## Capping keeps the RECENT visits, not the stalest ones -- dropping the
## newest would re-target the bloom it just drained.
func test_the_most_recent_visit_survives_the_cap():
	var visited: Array = []
	for i in 400:
		visited = PollinatorForaging.remember_visit(
			visited, Vector2(float(i) * 50.0, 0.0), float(i) * 3.0
		)
	var newest := Vector2(399.0 * 50.0, 0.0)
	# The most recent visit is what MUST survive being capped -- otherwise the
	# pollinator forgets the bloom it just checked and immediately re-lands on
	# it. With memory now vetoing rather than ranking (see choose_target),
	# that shows up directly: the bloom is refused while remembered.
	var flowers := [_flower(newest)]
	assert_true(
		PollinatorForaging.choose_target(newest, flowers, visited, 400.0 * 3.0).is_empty(),
		"the just-checked bloom must still be remembered, so it is not re-chosen"
	)
	var remembered := false
	for entry in visited:
		if entry["position"].distance_to(newest) < 1.0:
			remembered = true
	assert_true(remembered, "the most recent visit must survive the cap")


## Memory is now scaled to how fast a bloom actually refills, not to a flat
## ten minutes: a pollinator should come back and re-check once the flower has
## plausibly restocked (requested: "butterflies should forget which flowers
## they visited after a reasonable time so they can check same flowers again
## after a while to see if nectar restocked. Should refill nectar over one
## minute"). Ten minutes against a one-minute refill wrote a meadow off for
## ten times longer than it took to recover.
func test_visit_memory_is_scaled_to_the_refill_time():
	var refill_seconds := 1.0 / PollinatorForaging.NECTAR_REGEN_PER_SECOND
	assert_gt(PollinatorForaging.VISIT_MEMORY_SECONDS, refill_seconds)
	assert_lt(PollinatorForaging.VISIT_MEMORY_SECONDS, refill_seconds * 3.0)


func test_a_drink_lasts_long_enough_to_look_deliberate():
	assert_gt(PollinatorForaging.DRINK_SECONDS, 1.0)


func test_nectar_regenerates():
	assert_gt(PollinatorForaging.NECTAR_REGEN_PER_SECOND, 0.0)


# -- what a flyer is STEERED toward, not just what it targets -----------------
#
# Visit memory vetoed re-TARGETING a bloom the flyer had just worked, but the
# scent gradient went on pulling it toward that same bloom at
# AmbientFlyerMarker.SCENT_STEER_WEIGHT (0.55 -- more than the wander).
# So the flyer hung in front of one flower it was not allowed to land on,
# forever (reported: "most butterflies stall in front of a single flower
# instead of wandering randomly in search for new unvisited flowers").
#
# A butterfly that has just worked a flower is not drawn back to it. What it
# cannot target, it must not be steered toward either.

func test_a_bloom_this_flyer_just_worked_stops_pulling_on_it():
	var flowers := [{"position": Vector2(40, 0), "nectar": 1.0}]
	var visited := PollinatorForaging.remember_visit([], Vector2(40, 0), 0.0)
	assert_true(
		PollinatorForaging.unvisited_only(flowers, [], 0.0).size() == 1,
		"precondition: it pulls before it has been visited"
	)
	assert_eq(
		PollinatorForaging.unvisited_only(flowers, visited, 0.0).size(), 0,
		"a bloom it just drained must stop advertising to it"
	)


## Only to THIS flyer, and only for as long as it remembers: once the memory
## ages out the bloom is worth smelling again, which is what makes a meadow
## get re-worked instead of abandoned.
func test_a_forgotten_bloom_pulls_again():
	var flowers := [{"position": Vector2(40, 0), "nectar": 1.0}]
	var visited := PollinatorForaging.remember_visit([], Vector2(40, 0), 0.0)
	assert_eq(
		PollinatorForaging.unvisited_only(
			flowers, visited, PollinatorForaging.VISIT_MEMORY_SECONDS + 1.0
		).size(),
		1
	)


func test_other_blooms_are_untouched_by_one_visit():
	var flowers := [
		{"position": Vector2(40, 0), "nectar": 1.0},
		{"position": Vector2(-90, 30), "nectar": 1.0},
	]
	var visited := PollinatorForaging.remember_visit([], Vector2(40, 0), 0.0)
	var left := PollinatorForaging.unvisited_only(flowers, visited, 0.0)
	assert_eq(left.size(), 1)
	assert_eq(left[0]["position"], Vector2(-90, 30))


# -- tumbling flight ----------------------------------------------------------
#
# The approach was a dead straight line at the target (reported: "they should
# not fly straight to the next found but rather tumble around a bit like real
# butterflies"). Real butterfly flight is famously erratic -- it is an
# anti-predator adaptation, not decoration.

func test_a_tumbling_flyer_does_not_hold_a_straight_line():
	var headings := {}
	for step in 12:
		var heading := PollinatorForaging.tumbled_heading(
			Vector2.RIGHT, 200.0, float(step) * 0.1, 3
		)
		headings[snappedf(heading.angle(), 0.01)] = true
	assert_gt(headings.size(), 3, "the heading has to actually wander about")


## However much it veers, it must always make progress toward the flower --
## a tumble that could point backwards is a flyer that never arrives.
func test_a_tumbling_flyer_always_still_makes_progress():
	for step in 60:
		var heading := PollinatorForaging.tumbled_heading(
			Vector2.RIGHT, 200.0, float(step) * 0.05, 7
		)
		assert_gt(heading.dot(Vector2.RIGHT), 0.0, "it must never veer backwards")


func test_the_heading_stays_a_direction():
	for step in 20:
		var heading := PollinatorForaging.tumbled_heading(
			Vector2.UP, 120.0, float(step) * 0.2, 11
		)
		assert_almost_eq(heading.length(), 1.0, 0.001)


## It settles as it arrives: a flyer still veering at the last moment would
## flutter around the bloom without ever getting close enough to land.
func test_it_steadies_as_it_closes_on_the_flower():
	var far := PollinatorForaging.tumbled_heading(Vector2.RIGHT, 200.0, 0.35, 5)
	var near := PollinatorForaging.tumbled_heading(
		Vector2.RIGHT, PollinatorForaging.LANDING_DISTANCE, 0.35, 5
	)
	assert_gt(
		far.angle_to(Vector2.RIGHT), near.angle_to(Vector2.RIGHT),
		"the closer it gets, the straighter it flies"
	)
	assert_almost_eq(near.angle_to(Vector2.RIGHT), 0.0, 0.05, "and lands cleanly")


## Two butterflies in the same meadow do not flutter in unison.
func test_two_flyers_tumble_differently():
	assert_ne(
		PollinatorForaging.tumbled_heading(Vector2.RIGHT, 200.0, 0.4, 1),
		PollinatorForaging.tumbled_heading(Vector2.RIGHT, 200.0, 0.4, 2)
	)


## The whole point: the path it flies is meaningfully longer than the straight
## line it replaced, and it still gets there.
func test_a_tumbling_flight_is_longer_than_a_straight_one_but_still_arrives():
	var position := Vector2.ZERO
	var target := Vector2(300, 0)
	var travelled := 0.0
	var steps := 0
	while position.distance_to(target) > PollinatorForaging.LANDING_DISTANCE and steps < 4000:
		var heading := PollinatorForaging.tumbled_heading(
			(target - position).normalized(), position.distance_to(target),
			float(steps) * (1.0 / 60.0), 4
		)
		position += heading * 60.0 * (1.0 / 60.0)
		travelled += 1.0
		steps += 1
	assert_lt(steps, 4000, "it has to actually arrive")
	assert_gt(travelled, 300.0 * 1.05, "and by a wanderier route than a straight line")


# -- what is worth flying to ---------------------------------------------------

## Takes WITHERED, not nectar.
##
## Keying this off the nectar level was wrong twice over. Depleted is not
## spent: nectar is a bloom's current contents and refills in about a minute,
## so a drained flower is a full flower that has just been visited. Refusing it
## stopped local pollinators returning to the plants they work, which is most
## of what a local pollinator does.
func test_a_withered_bloom_is_not_worth_flying_to():
	assert_false(PollinatorForaging.is_worth_visiting(true))


func test_a_living_bloom_is_worth_flying_to():
	assert_true(PollinatorForaging.is_worth_visiting(false))


## A flower that has just been drained is still worth coming back to -- the
## nectar refills. This is the case the earlier nectar gate broke.
func test_a_drained_flower_is_still_worth_returning_to():
	assert_true(
		PollinatorForaging.is_worth_visiting(false),
		"a drained bloom is a living bloom with an empty nectary, not a dead one"
	)
