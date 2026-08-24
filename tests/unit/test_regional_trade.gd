extends GutTest

## RegionalTrade: cross-settlement resource transfer (see
## docs/concept/regional_trade.md, docs/emergence/07-implementation-
## roadmap.md Phase 14 "trade networks").

const RegionalTrade = preload("res://src/emergence/regional_trade.gd")


# -- has_surplus: a real safety margin, never trading down to the edge -----

func test_stock_well_above_need_has_surplus():
	assert_true(RegionalTrade.has_surplus(20, 3))


func test_stock_exactly_at_need_has_no_surplus():
	assert_false(RegionalTrade.has_surplus(3, 3))


func test_stock_just_below_the_margin_has_no_surplus():
	var need := 3
	assert_false(RegionalTrade.has_surplus(need + RegionalTrade.MIN_SURPLUS - 1, need))


func test_stock_exactly_at_the_margin_has_surplus():
	var need := 3
	assert_true(RegionalTrade.has_surplus(need + RegionalTrade.MIN_SURPLUS, need))


# -- chunk_coord_of / distance_between: read back from the real settlement id

func test_chunk_coord_of_parses_the_real_settlement_key():
	assert_eq(RegionalTrade.chunk_coord_of("settlement:5_-3"), Vector2i(5, -3))


func test_chunk_coord_of_an_unrecognized_id_is_the_origin():
	assert_eq(RegionalTrade.chunk_coord_of("not_a_settlement_id"), Vector2i.ZERO)


func test_distance_between_two_settlements_is_real_euclidean_distance():
	var distance := RegionalTrade.distance_between("settlement:0_0", "settlement:3_4")
	assert_eq(distance, 5.0)  # real 3-4-5 triangle


func test_distance_between_a_settlement_and_itself_is_zero():
	assert_eq(RegionalTrade.distance_between("settlement:1_1", "settlement:1_1"), 0.0)
