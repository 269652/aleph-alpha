extends GutTest

## Asked directly: *"Gold should only be conjured by the travelling
## merchant"* (docs/concept/traveling_merchants.md, "The merchant is the
## ONLY faucet").
##
## traveling_merchants.md's own opening already claimed this -- "a village's
## gold used to come from nowhere... a traveling merchant is the faucet that
## replaces it" -- and it was not true. Two other places minted gold with
## nothing behind them. These tests are what makes the claim real rather
## than aspirational, so they are written against the SOURCE: an invariant
## about where gold may come from cannot be checked from inside one module.

const VillageWages = preload("res://src/world/village_wages.gd")


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func _body(path: String, function_name: String) -> String:
	var source := _read(path)
	var start := source.find("func %s" % function_name)
	assert_gt(start, -1, "the premise: %s must still exist in %s" % [function_name, path])
	var body_end := source.find("\nfunc ", start + 1)
	return source.substr(start, body_end - start)


## Faucet one: a coin per food unit gathered, whether or not anyone ever
## bought it. A producer's work earns the village GOODS now; the merchant
## pays for those.
func test_gathering_no_longer_mints_a_coin_as_the_arrow_lands():
	var source := _read("res://src/world/npc_economy.gd")
	assert_false(source.contains("func _earn("), "the minting split is gone, not merely unused")
	assert_false(
		source.contains("YIELD_TO_GOLD_RATE)"),
		"nothing converts a gathered unit into gold any more"
	)


## And a producer is not left unpaid: they draw from the purse through the
## same wage everyone else does, which was already written for exactly this.
func test_a_producer_draws_from_the_purse_like_everybody_else():
	var body := _body("res://src/world/npc_economy.gd", "_draw_subsistence_wage")
	assert_false(
		body.contains("is_producer("),
		"the wage is not gated on occupation: %s" % body
	)


## Faucet two: the estate tax credited the purse and debited nobody.
func test_the_estate_tax_is_taken_out_of_somebody_before_it_is_paid_in():
	var body := _body("res://src/world/earth_chunk_manager.gd", "_collect_estate_tax")
	assert_true(body.contains("VillageWages.tax_debits("), "it asks who can pay: %s" % body)
	assert_true(
		body.contains("spend(") or body.contains("_debit"),
		"and the coins really leave their wallets"
	)
	var debit_at: int = maxi(body.find("tax_debits("), 0)
	var deposit_at := body.find("deposit_to_purse(")
	assert_gt(deposit_at, -1, "the premise: it still credits the purse")
	assert_lt(debit_at, deposit_at, "collected first, credited after")


## The whole-coin remainder is carried rather than rounded away or rounded
## up: a kossaet owes 0.25 a day and a Wallet holds integers, so a step that
## rounded would either forgive a real debt or quadruple it.
func test_the_fractional_tax_is_carried_rather_than_rounded():
	var body := _body("res://src/world/earth_chunk_manager.gd", "_collect_estate_tax")
	assert_true(body.contains("carry"), "the fraction is kept for next time: %s" % body)


## The invariant itself: nothing anywhere credits the purse except the
## merchant's sale and the tax that was just taken out of real wallets.
## A third caller is a third faucet, whatever it is called.
func test_nothing_else_anywhere_pays_gold_into_the_purse():
	var allowed := ["_step_merchant_visits", "_collect_estate_tax"]
	var offenders: Array = []
	for path in [
		"res://src/world/earth_chunk_manager.gd",
		"res://src/world/npc_economy.gd",
		"res://src/world/village_market.gd",
		"res://src/world/village_wages.gd",
	]:
		var source := _read(path)
		var chunks: PackedStringArray = source.split("\nfunc ")
		for i in range(1, chunks.size()):
			var chunk := chunks[i]
			if not chunk.contains("deposit_to_purse("):
				continue
			var function_name := chunk.substr(0, maxi(chunk.find("("), 0))
			# The definition of deposit_to_purse itself, and the helper it
			# is built on, are the mechanism -- not a caller of it.
			if function_name.begins_with("deposit_to_purse") or function_name.begins_with("_set_purse"):
				continue
			if allowed.has(function_name):
				continue
			offenders.append("%s: %s" % [path.get_file(), function_name])
	assert_eq(offenders, [], "a third faucet: %s" % str(offenders))


## The loophole the test above leaves: `deposit_to_purse` is not the only
## way to WRITE the purse -- `_set_purse` is, and a new caller of that could
## reopen the faucet without ever naming the guarded function.
##
## So every other writer must be a TRANSFER: it moves gold between the purse
## and a wallet in the same breath. The subsistence wage is one (it debits
## the purse and credits a wallet); anything that writes the purse without
## touching a wallet is minting.
func test_every_other_writer_of_the_purse_moves_gold_rather_than_making_it():
	var source := _read("res://src/world/npc_economy.gd")
	var chunks: PackedStringArray = source.split("\nfunc ")
	var offenders: Array = []
	var checked := 0
	for i in range(1, chunks.size()):
		var chunk := chunks[i]
		if not chunk.contains("_set_purse("):
			continue
		var function_name := chunk.substr(0, maxi(chunk.find("("), 0))
		if function_name.begins_with("_set_purse") or function_name.begins_with("deposit_to_purse"):
			continue  # the mechanism itself, and the one guarded faucet
		checked += 1
		if not (chunk.contains("wallet.add(") or chunk.contains("wallet.spend(")):
			offenders.append(function_name)
	assert_gt(checked, 0, "the premise: something else writes the purse")
	assert_eq(offenders, [], "writes the purse without moving it to anybody: %s" % str(offenders))


## And the levy half of VillageWages -- the old faucet's arithmetic -- must
## stay out of the live path. Its functions still exist and are still
## tested, but nothing in src/ may call them again: rewiring them is exactly
## how the conjured coin would come back.
func test_the_old_levy_arithmetic_is_not_wired_to_anything():
	var live: Array = []
	for path in [
		"res://src/world/npc_economy.gd",
		"res://src/world/earth_chunk_manager.gd",
		"res://src/rendering/npc_marker.gd",
	]:
		var source := _read(path)
		for call in ["VillageWages.levy_on(", "VillageWages.take_home_of(", "VillageWages.deposit("]:
			if source.contains(call):
				live.append("%s: %s" % [path.get_file(), call])
	assert_eq(live, [], "the levy is wired back in: %s" % str(live))
