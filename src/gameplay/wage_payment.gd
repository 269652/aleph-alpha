extends RefCounted

## Gold actually moving from one purse to another.
##
## docs/concept/npc_instructions.md lists *"any actual wage-payment flow"*
## as unbuilt for the whole NPC system; this is the first real one, built
## for planner mode's hire-a-builder (docs/concept/planner_mode.md's
## pillar 5: build-it-yourself and hire-somebody are the same construction
## paid for differently -- this is the "paid" half).
##
## ONE function rather than a spend and an add at the call site, and that
## is the entire point: a debit that succeeded next to a credit that did
## not is money destroyed, and a credit without a debit is money invented.
## Doing both here, in an order that cannot half-happen, is what makes
## "gold is conserved" a property rather than a hope.

const Wallet = preload("res://src/gameplay/wallet.gd")


## Moves `amount` from `payer` to `payee`. True only if it really moved.
##
## Refuses and moves NOTHING when either purse is missing, when the amount
## is not a real payment, or when the payer cannot afford it. A missing
## payee is a real state, not a defensive nicety: a villager with no
## household has no wallet (see EarthChunkManager.
## household_wallet_for_villager, which returns null for exactly that), and
## charging the player for a wage nobody received would be the worst
## possible outcome.
static func pay(payer: Wallet, payee: Wallet, amount: int) -> bool:
	if payer == null or payee == null:
		return false
	if amount <= 0:
		return false
	# spend() is what decides affordability, so the credit below can only
	# ever run against a debit that really happened.
	if not payer.spend(amount):
		return false
	payee.add(amount)
	return true
