extends GutTest

## Gold actually moving from the player to the villager who took the job
## (see WagePayment, docs/concept/planner_mode.md). docs/concept/
## npc_instructions.md lists "any actual wage-payment flow" as unbuilt for
## the whole NPC system; this is the first real one.
##
## Pure over two Wallets, so every branch -- including the ones that must
## move nothing -- is reachable without a villager or a world.

const WagePayment = preload("res://src/gameplay/wage_payment.gd")
const Wallet = preload("res://src/gameplay/wallet.gd")


func _wallet(balance: int) -> Wallet:
	var wallet := Wallet.new()
	wallet.add(balance)
	return wallet


func test_a_paid_wage_leaves_one_purse_and_arrives_in_the_other():
	var payer := _wallet(100)
	var payee := _wallet(5)
	assert_true(WagePayment.pay(payer, payee, 20))
	assert_eq(payer.balance, 80)
	assert_eq(payee.balance, 25)


## The whole reason this is one function rather than two calls at the call
## site: a debit that succeeded and a credit that did not is money
## destroyed, and a credit without a debit is money invented.
func test_gold_is_conserved_exactly():
	var payer := _wallet(100)
	var payee := _wallet(5)
	WagePayment.pay(payer, payee, 20)
	assert_eq(payer.balance + payee.balance, 105, "no gold created, none destroyed")


func test_a_payer_who_cannot_afford_it_pays_nothing_at_all():
	var payer := _wallet(10)
	var payee := _wallet(0)
	assert_false(WagePayment.pay(payer, payee, 20))
	assert_eq(payer.balance, 10, "and keeps every coin")
	assert_eq(payee.balance, 0, "and the villager is not paid out of nowhere")


## Exactly affordable is affordable -- an off-by-one here would refuse a
## job the player can just barely pay for, which reads as a bug.
func test_paying_with_exactly_enough_succeeds():
	var payer := _wallet(20)
	assert_true(WagePayment.pay(payer, _wallet(0), 20))
	assert_eq(payer.balance, 0)


## A missing purse must move nothing rather than crash -- a villager with
## no household has no wallet to be paid into, and that is a real state
## (see EarthChunkManager.household_wallet_for_villager, which returns
## null for one).
func test_a_missing_purse_on_either_side_moves_nothing():
	var payer := _wallet(100)
	assert_false(WagePayment.pay(payer, null, 20))
	assert_eq(payer.balance, 100, "the player is not charged for a wage nobody received")
	assert_false(WagePayment.pay(null, _wallet(0), 20))


## A wage of nothing is not a payment, and must not read as a successful
## one -- otherwise a misconfigured zero wage would look like everybody
## works for free.
func test_a_wage_of_nothing_is_not_a_payment():
	var payer := _wallet(100)
	assert_false(WagePayment.pay(payer, _wallet(0), 0))
	assert_false(WagePayment.pay(payer, _wallet(0), -5))
	assert_eq(payer.balance, 100)
