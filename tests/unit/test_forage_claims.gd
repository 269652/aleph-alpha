extends GutTest

## ForageClaims -- which bloom each pollinator is currently flying to, so two
## flyers don't queue up behind the same one (see docs/concept/flora.md).
##
## Measured cause: 62.1% of co-located pollinator pairs held the SAME target
## bloom, because 86.5% of foraging decisions have exactly one candidate
## inside the distance band, leaving the per-flyer scatter seed nothing to
## choose between.

const ForageClaims = preload("res://src/gameplay/forage_claims.gd")

var claims: ForageClaims


func before_each():
	claims = ForageClaims.new()


func test_a_claimed_bloom_is_visible_to_other_flyers():
	claims.claim(Vector2(100, 100), 1)
	var near := claims.claimed_positions_near(Vector2(100, 100), 50.0)
	assert_eq(near.size(), 1)
	assert_eq(near[0], Vector2(100, 100))


func test_claims_outside_the_radius_are_not_reported():
	claims.claim(Vector2(1000, 1000), 1)
	assert_eq(claims.claimed_positions_near(Vector2(0, 0), 50.0).size(), 0)


## A flyer must not be blocked by its OWN claim -- it still holds one while
## re-deciding, and demoting its own target would make it abandon a bloom it
## is already on the way to.
func test_a_flyer_does_not_see_its_own_claim():
	claims.claim(Vector2(100, 100), 7)
	assert_eq(
		claims.claimed_positions_near(Vector2(100, 100), 50.0, 7).size(), 0,
		"a flyer should not be warned off the bloom it claimed itself"
	)
	assert_eq(
		claims.claimed_positions_near(Vector2(100, 100), 50.0, 8).size(), 1,
		"but another flyer should still see it"
	)


func test_releasing_frees_the_bloom():
	claims.claim(Vector2(100, 100), 1)
	claims.release(1)
	assert_eq(claims.claimed_positions_near(Vector2(100, 100), 50.0).size(), 0)


func test_releasing_an_unknown_flyer_is_harmless():
	claims.release(999)
	assert_eq(claims.claim_count(), 0)


# -- leak safety -------------------------------------------------------------
#
# This table is written every time a pollinator commits to a bloom, by every
# pollinator on screen, for as long as the world is loaded. It must be bounded
# by the number of LIVE flyers, never by how long the session has run.


## The bound that makes leaks structurally impossible: one claim per flyer.
## Re-claiming replaces, so a flyer that forgets to release still occupies
## exactly one slot rather than accumulating one per bloom it ever visited.
func test_a_flyer_holds_only_one_claim_at_a_time():
	for i in 500:
		claims.claim(Vector2(float(i) * 10.0, 0.0), 42)
	assert_eq(claims.claim_count(), 1, "re-claiming must replace, not accumulate")


func test_the_table_never_outgrows_the_number_of_flyers():
	for flyer in 20:
		for repeat in 50:
			claims.claim(Vector2(float(repeat) * 10.0, 0.0), flyer)
	assert_eq(claims.claim_count(), 20)


## Godot recycles instance ids, so a brand-new flyer can be handed the id of
## one that despawned without releasing. Claiming under a reused id must take
## the slot over rather than leaving the dead flyer's bloom claimed forever.
func test_a_reused_flyer_id_takes_over_the_stale_claim():
	claims.claim(Vector2(100, 100), 5)
	claims.claim(Vector2(900, 900), 5)  # same id, new flyer, new bloom
	assert_eq(claims.claim_count(), 1)
	assert_eq(claims.claimed_positions_near(Vector2(100, 100), 50.0).size(), 0,
		"the stale bloom must not stay claimed")
	assert_eq(claims.claimed_positions_near(Vector2(900, 900), 50.0).size(), 1)


## The despawn path the chunk manager needs: when a chunk unloads it frees its
## flyers, and every one of their claims has to go with them.
func test_releasing_many_flyers_at_once_drops_all_their_claims():
	for flyer in 10:
		claims.claim(Vector2(float(flyer) * 10.0, 0.0), flyer)
	claims.release_many([0, 1, 2, 3, 4])
	assert_eq(claims.claim_count(), 5)
	for flyer in 5:
		assert_eq(
			claims.claimed_positions_near(Vector2(float(flyer) * 10.0, 0.0), 1.0).size(), 0
		)


func test_release_all_empties_the_table():
	for flyer in 10:
		claims.claim(Vector2(float(flyer) * 10.0, 0.0), flyer)
	claims.release_all()
	assert_eq(claims.claim_count(), 0)


func test_several_flyers_claiming_different_blooms_are_all_reported():
	claims.claim(Vector2(0, 0), 1)
	claims.claim(Vector2(10, 0), 2)
	claims.claim(Vector2(20, 0), 3)
	assert_eq(claims.claimed_positions_near(Vector2(0, 0), 100.0).size(), 3)
