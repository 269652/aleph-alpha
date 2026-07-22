extends GutTest

const Wallet = preload("res://src/gameplay/wallet.gd")

var wallet: Wallet


func before_each():
	wallet = Wallet.new()


func test_starts_at_zero():
	assert_eq(wallet.balance, 0)


func test_add_increases_balance():
	wallet.add(10)
	assert_eq(wallet.balance, 10)


func test_add_accumulates_across_calls():
	wallet.add(10)
	wallet.add(5)
	assert_eq(wallet.balance, 15)


func test_spend_succeeds_and_decreases_balance_when_affordable():
	wallet.add(10)
	var result: bool = wallet.spend(4)
	assert_true(result)
	assert_eq(wallet.balance, 6)


func test_spend_fails_and_leaves_balance_unchanged_when_not_affordable():
	wallet.add(10)
	var result: bool = wallet.spend(11)
	assert_false(result)
	assert_eq(wallet.balance, 10)


func test_can_afford_is_true_at_exact_boundary():
	wallet.add(10)
	assert_true(wallet.can_afford(10))


func test_can_afford_is_false_just_above_balance():
	wallet.add(10)
	assert_false(wallet.can_afford(11))


func test_spending_exact_full_balance_leaves_zero():
	wallet.add(10)
	var result: bool = wallet.spend(10)
	assert_true(result)
	assert_eq(wallet.balance, 0)


func test_can_afford_does_not_mutate_balance():
	wallet.add(10)
	wallet.can_afford(10)
	assert_eq(wallet.balance, 10)


func test_negative_add_is_clamped_to_a_no_op():
	wallet.add(10)
	wallet.add(-5)
	assert_eq(wallet.balance, 10)
