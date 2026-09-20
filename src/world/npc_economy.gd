extends RefCounted

## Per-NPC economic loop tying together hunger (NpcNeeds), gold (Wallet), and
## the local production economy (docs/concept/npc.md "Needs and the local
## production economy"): a producer gathers real food into its village's
## shared VillageMarket while working and earns real gold doing it; anyone
## who goes hungry tries to eat. Held by NpcMarker and driven once per frame
## from _process -- pure logic, no engine dependency, so it's fully
## unit-testable without a live scene tree (mirrors CreatureNeeds/
## CreatureBehavior's own extracted-pure-logic split).
##
## -- Design/judgment calls (see docs/concept/npc.md's own open framing) --
##
## Producers self-feed for FREE from their own currently-active production,
## no gold or market transaction, rather than round-tripping through the
## market like a non-producer -- the doc only describes non-producers as
## BUYING; a producer eating from their own literal occupation is the
## natural reading. This is gated on genuinely active, nonzero real yield
## right now (is_working AND NpcProduction.yield_per_second() > 0.0), not
## unconditional: a producer whose region has totally collapsed (e.g. zero
## herbivores left) has nothing to self-feed from either, and falls through
## to the paid market like anyone else -- so a severe-enough drought/game
## scarcity can genuinely starve a producer too, not just everyone else,
## which is the causal chain docs/concept/npc.md's Lifecycle/famine section
## needs underneath it.
##
## Gold flow is a real two-faucet model (docs/concept/economy.md), not a
## closed-loop simulation: a producer earns NpcProduction.YIELD_TO_GOLD_RATE
## gold per food unit the instant it's gathered (independent of whether that
## unit is ever bought), and a buyer's VillageMarket.VILLAGE_LOCAL_FOOD_PRICE
## gold is simply spent (there is no player market yet for it to flow into).
## The two rates are deliberately different (see NpcProduction's own doc
## comment) rather than collapsing into one currency-conserving number.
##
## -- Where a NON-producer's gold comes from (VillageWages) --
##
## The gold faucet above is gated on is_producer(), so for a long time the
## five non-producer occupations of NpcIdentity.OCCUPATIONS started at zero
## gold, could never afford VillageMarket.VILLAGE_LOCAL_FOOD_PRICE, and
## stayed hungry forever regardless of weather, harvest or market stock --
## hunger was an occupation constant rather than an economy. npc.md says a
## non-producer eats "by buying it, out of their own wallet" but never says
## where that wallet fills up. VillageWages answers that: a producing
## household's gross is split, the village's derived share accrues in a
## shared purse, and a villager who cannot afford a meal draws one
## subsistence wage back out of it before trying to buy. A blacksmith now
## stays fed because a hunter's catch funded the village, which is the
## specialization npc.md calls "real rather than cosmetic".
##
## The purse BALANCE lives as metadata on the VillageMarket itself. That
## object is already exactly the scope the purse needs -- one instance per
## settlement, shared by every NpcMarker of that village (see
## VillageRenderer.spawn_village) -- so the savings are per-village for the
## same reason the stock is, and they share the market's lifetime too: a
## chunk reload regenerates an empty market AND an empty purse, the same
## known "regenerates on revisit, no persistence" simplification village
## stock already accepts, rather than inventing a second, longer-lived
## storage with different rules. Metadata rather than a field because
## village_market.gd holds no economy logic of its own; when a settlement
## save format eventually carries this float, purse_of/_set_purse are the
## only two places that have to change.

const NpcNeeds = preload("res://src/world/npc_needs.gd")
const NpcProduction = preload("res://src/world/npc_production.gd")
const VillageWages = preload("res://src/world/village_wages.gd")
const VillageMarket = preload("res://src/world/village_market.gd")
const Wallet = preload("res://src/gameplay/wallet.gd")

## Metadata key under which a settlement's shared purse balance is kept on
## its VillageMarket -- see the file doc comment.
const PURSE_META := "village_purse_gold"

var needs: NpcNeeds
var wallet: Wallet
var occupation: String
var market  # VillageMarket, shared by every NpcMarker of the same settlement

## The settlement's own purse, bound by the caller that knows which
## settlement this is (see bind_settlement_purse). Null for a bare economy,
## which then keeps its market's own meta.
var _settlement_purse = null

var _production := NpcProduction.new()
var _accumulated_yield := 0.0

## This household's own unbanked take-home gold. Take-home is a fraction of
## goods into the village market -- no coin is minted for them, since the
## merchant is the only faucet (docs/concept/traveling_merchants.md) -- and
## a Wallet holds only whole gold, so it accrues here and is banked a coin
## at a time -- the same carry-until-it-crosses-a-whole-unit idiom
## _accumulated_yield already runs on. Truncating per earning instead would
## round every producer's income to zero and silently hand the whole gross
## to the purse.

# -- the load in a villager's hands (village_warehouse.md mechanism 3) ------

## How many trips fill a village that has no store at all -- one person's
## load against VillageMarket.HOUSEHOLD_CORNERS_CAPACITY. This is the tuned
## number of the whole mechanic, and it is tuned by what it implies about
## the BUILDING: a load that filled a storeless village in one trip would
## make the warehouse pointless, and one that took a hundred would make
## hauling the only thing a villager ever did. Four trips fill a village
## that keeps its stock in its corners; forty fill one that has a roof for
## it. Pinned, with that second ratio, by
## test_a_load_is_a_quarter_of_what_a_village_keeps_without_a_store.
const TRIPS_TO_FILL_A_STORELESS_VILLAGE := 4

## What one villager carries in one trip, in the same units as market stock.
const CARRY_LIMIT := (
	VillageMarket.HOUSEHOLD_CORNERS_CAPACITY / float(TRIPS_TO_FILL_A_STORELESS_VILLAGE)
)

## What this villager is holding and has not put down yet; item_id -> units.
var carried: Dictionary = {}

## How much this villager may hold before their hands are full. 0.0 -- the
## default -- means they do not carry at all, and everything they take goes
## straight into the village's stock the way it always did. That covers
## every caller written before a warehouse existed AND every village whose
## site could not spare the ground for one (village_warehouse.md, pillar 1's
## caveat): nowhere to carry to must never mean nothing is stocked.
##
## Deliberately the same shape as VillageMarket.storage_capacity, for the
## same reason: a limit that depends on which buildings are standing belongs
## to whoever knows that, not to the object that has to respect it.
## VillageRenderer opts a villager in when a store really stands.
var carry_limit: float = 0.0


## The shared purse of the settlement `a_market` belongs to, in gold. Static
## because the balance belongs to the village, not to any one villager who
## happens to read it. A market that has never been levied holds nothing.
static func purse_of(a_market) -> float:
	if a_market == null:
		return 0.0
	return float(a_market.get_meta(PURSE_META, 0.0))


## Pays `gold` into a settlement's shared purse -- the public counterpart
## to purse_of, for money arriving from OUTSIDE the village's own levy
## (docs/concept/traveling_merchants.md: a merchant buys goods and pays for
## them). The levy split below keeps its own private setter because it
## moves gold that is already inside the village; this brings new gold in.
static func deposit_to_purse(a_market, gold: float) -> void:
	if a_market == null or gold <= 0.0:
		return
	_set_purse(a_market, purse_of(a_market) + gold)


static func _set_purse(a_market, gold: float) -> void:
	if a_market == null:
		return
	a_market.set_meta(PURSE_META, gold)


## Makes `household_wallet` the purse this villager earns into and spends
## from, in place of the one created below.
##
## Reported live as "all villagers have 0 gold". They were earning all
## along -- the producer faucet and the subsistence wage both worked -- but
## into a Wallet created fresh in _init, on an NpcEconomy owned by an
## NpcMarker that is regenerated from scratch on every chunk load. The
## persistent Household wallet (HouseholdStore -- the unit Household's own
## doc comment calls "this project's real, persistent unit") never received
## a coin, so a villager's whole working life evaporated the moment the
## player walked away, and every readout of their purse honestly said zero.
##
## Whatever was already in hand is carried over rather than dropped: an
## economy may work for a moment before its household is resolved, and
## silently losing that gold would be a second, quieter version of the same
## bug. Passing null is a harmless no-op, so a villager with no household
## (an isolated test, a world that cannot answer) keeps its own wallet
## exactly as before.
func bind_household_wallet(household_wallet) -> void:
	if household_wallet == null or household_wallet == wallet:
		return
	var in_hand := wallet.balance
	wallet = household_wallet
	if in_hand > 0:
		wallet.add(in_hand)


func _init(seed_value: int, an_occupation: String, a_market) -> void:
	needs = NpcNeeds.new(seed_value)
	wallet = Wallet.new()
	occupation = an_occupation
	market = a_market


## Advances hunger, gathers real food into the shared market if this NPC is
## a producer currently working, and tries to eat if hungry. `world`/
## `pixel_position` feed NpcProduction's real weather-tied yield read;
## `is_working` gates production (and the free self-feed path) to the
## "work" schedule activity, not idle/sleep/socialize time.
## `on_real_quarry` switches the regional drip OFF: this producer is
## currently working a real animal or fish they walked to and struck
## themselves (docs/concept/npc.md, "Work against the real world, not
## against a number"), and record_real_catch below is what pays them for
## it. Crediting both would pay a hunter twice for one deer. Defaults to
## false, so every caller that predates real quarry -- and every villager
## whose chunk holds none -- keeps the aggregate fallback npc.md's own
## "a villager can only hunt what is LOADED" limitation depends on.
##
## Deliberately gates only _gather, not _try_eat: a hunter standing over a
## fresh kill has food in their hands, which is exactly what the free
## self-feed is about.
func step(
	delta_seconds: float,
	is_working: bool,
	world,
	pixel_position: Vector2,
	on_real_quarry := false
) -> void:
	needs.advance(delta_seconds)
	if is_working and not on_real_quarry and _production.is_producer(occupation):
		_gather(delta_seconds, world, pixel_position)
	if needs.is_hungry():
		_try_eat(is_working, world, pixel_position)


## Credits `count` whole units of this producer's own real item -- the meat
## off an animal this villager actually killed, or a fish they actually
## took (docs/concept/npc.md, "Work against the real world, not against a
## number") -- to the village market, and pays for them at exactly the rate
## a gathered unit earns. A unit of meat is worth a unit of meat however it
## was obtained; the kill changes where food comes from, not its price.
##
## Books NO depletion of its own, unlike _gather/_deplete_continuous. A
## real kill has already reported itself: CreatureMarker._die() is the
## single choke point every death routes through, and its own doc comment
## records a merge that left two record_death_at calls there and counted
## every wild death twice. The same holds for a real fish, taken through
## EarthChunkManager.record_fish_catch_near. This is the paying half only.
##
## A no-op for a non-producer (nothing to credit it as) and for a count of
## zero (a strike that did not land a kill).
func record_real_catch(count: int) -> void:
	if count <= 0 or not _production.is_producer(occupation):
		return
	_stock(_production.item_id_for(occupation), float(count))


## Credits `count` units of `item_id` really harvested off this villager's
## own field (docs/concept/village_farms.md) -- stocked in the village
## market and paid at the same rate a gathered unit earns, exactly like
## record_real_catch, and with no regional depletion for the same reason:
## the crop was grown, not taken from a standing population.
##
## Separate from record_real_catch for two real reasons, not for symmetry.
## That one credits whatever PRODUCER_ITEM_BY_OCCUPATION says the
## occupation DRIPS -- "fruit" for a farmer, which is not the wheat
## standing in the field -- and the herbalist is not in that table at all,
## so it would pay them nothing for a crop they really grew. The item id
## says what it is, so this needs no occupation table.
func record_real_harvest(item_id: String, count: int) -> void:
	if count <= 0 or item_id == "":
		return
	_stock(item_id, float(count))


## The STOCKING half, without the pay -- what a delivery into the village's
## own store is worth to the village (Mechanism 7). The producer was already
## paid at the scythe; this is the moment the goods become something the
## village can sell.
func record_delivered_goods(item_id: String, count: int) -> void:
	if count <= 0 or item_id == "":
		return
	_stock(item_id, float(count))


## Credits `count` units of something a real take produced ALONGSIDE the
## food -- the hide off a hunted animal (HuntableQuarry.hide_yield_of).
##
## Deliberately pays nothing, unlike record_real_catch. A hide feeds nobody
## and no villager buys one, so there is no local sale to pay for; its value
## arrives when a travelling cart buys it out of the market
## (docs/concept/traveling_merchants.md, MerchantVisit.buy_list()). Paying at
## the kill would be the conjured faucet that doc exists to close, pointed
## at a second good.
##
## Any producer may record one -- the item id says what it is, so this
## needs no occupation table -- and a count of zero is a no-op.
func record_byproduct(item_id: String, count: int) -> void:
	if count <= 0 or item_id == "":
		return
	_stock(item_id, float(count))


func _gather(delta_seconds: float, world, pixel_position: Vector2) -> void:
	# Full hands take nothing more. Not "the surplus is discarded": every
	# unit gathered costs the region a real herbivore, crop or fish through
	# the two depletion calls below, so a producer who kept working with
	# nowhere to put the take would go on killing for units nobody can hold.
	# The walk to the store is what makes room, which is the whole point.
	if _hands_are_full():
		return
	var rate := _production.yield_per_second(occupation, world, pixel_position)
	var gathered := rate * delta_seconds
	_accumulated_yield += gathered
	_deplete_continuous(world, pixel_position, gathered)

	while _accumulated_yield >= NpcProduction.FOOD_UNIT:
		if _hands_are_full():
			break
		_accumulated_yield -= NpcProduction.FOOD_UNIT
		_stock(_production.item_id_for(occupation), NpcProduction.FOOD_UNIT)
		_deplete_discrete_unit(world, pixel_position)


## What this villager is holding, in the same units as market stock.
func carried_total() -> float:
	var total := 0.0
	for item_id in carried:
		total += float(carried[item_id])
	return total


## The gate Ethogram.DRIVE_BURDEN reads: 0 until this villager's hands are
## full, 1 the moment they are.
##
## A STEP, not a ramp, and that is not a simplification. The haul wiring is
## the only one listening on the store, so any gain above zero fires it --
## a ramp would send a villager off with one apple in hand and they would
## never do a day's work again. What presses is being full.
func burden() -> float:
	return 1.0 if _hands_are_full() else 0.0


## Puts everything in this villager's hands into the village's stock: what
## reaching the store door does (NpcMarker._answer_need). Returns how much
## was really delivered.
##
## The market's own ceiling still applies through add_stock, so a full store
## turns a full villager away exactly as it already turns a producer away
## (village_warehouse.md mechanism 2). With no market to deliver into,
## nothing is delivered and the load stays in hand rather than evaporating.
func deliver_load() -> float:
	if market == null:
		return 0.0
	var delivered := carried_total()
	for item_id in carried:
		market.add_stock(item_id, float(carried[item_id]))
	carried.clear()
	return delivered


## Takes one meal out of what this villager is carrying. True when they
## really ate.
##
## Only FOOD: a carter's load is whatever the round picked up, and nobody
## is fed by a log. The first food item in the load, in stock order, the
## same deterministic pick VillageMarket.buy_meal makes.
func _eat_from_the_load() -> bool:
	if market == null:
		return false
	for item_id in carried:
		if not market.is_food(item_id):
			continue
		if float(carried[item_id]) < VillageMarket.FOOD_UNITS_PER_MEAL:
			continue
		carried[item_id] = float(carried[item_id]) - VillageMarket.FOOD_UNITS_PER_MEAL
		if float(carried[item_id]) <= 0.0:
			carried.erase(item_id)
		return true
	return false


func _hands_are_full() -> bool:
	return carry_limit > 0.0 and carried_total() >= carry_limit


## The one seam every deposit this villager makes passes through: into the
## village's stock outright, or into their own hands first when they carry.
func _stock(item_id: String, amount: float) -> void:
	if carry_limit <= 0.0:
		market.add_stock(item_id, amount)
		return
	carried[item_id] = float(carried.get(item_id, 0.0)) + amount


## Real depletion counterpart to NpcProduction.yield_per_second's read: the
## exact same real yield just gathered ALSO leaves this region's real
## standing resource, not just this NPC's own food/gold. Previously only
## "farmer" had this wired (see docs/concept/world.md "Land health:
## overharvesting leaves a lasting mark, not just a slower respawn"); a
## working farmer/hunter/fisher NPC only ever READ vegetation_density_near/
## herbivore_population_near/fish_population_near, never removed anything
## from them (only weather/predation/the player ever moved those numbers).
## This is what makes sustained NPC production, not just the player's own
## foraging/hunting/fishing, a real depletion driver for all three regional
## pools.
##
## Split into two functions (2026-08-26 fix) because the three occupations
## do NOT have the same real-world cost per call. farmer/hunter here call
## EarthChunkManager hooks that are pure aggregate-population arithmetic
## (record_vegetation_harvest_near, record_death_at) -- harmless to call
## every single frame with the tiny fractional `gathered` amount actually
## produced that frame, so they stay wired continuously, right where the
## farmer depletion always was:
## - farmer  -> vegetation_density_near   -> record_vegetation_harvest_near
## - hunter  -> herbivore_population_near -> record_death_at(is_predator=false,
##             the same non-predator branch a wild kill of prey or the
##             player's own weapon already reports through)
## fisher is handled separately by _deplete_discrete_unit below -- see its
## own doc comment for why it can't share this per-frame path.
## Duck-typed fail-open per occupation, matching the rest of this codebase's
## world-duck-typing: a world missing the relevant hook (an older double, or
## a caller that hasn't wired it) is a harmless no-op, not a crash.
func _deplete_continuous(world, pixel_position: Vector2, gathered: float) -> void:
	if world == null:
		return
	match occupation:
		"farmer":
			if world.has_method("record_vegetation_harvest_near"):
				world.record_vegetation_harvest_near(pixel_position, gathered)
		"hunter":
			if world.has_method("record_death_at"):
				world.record_death_at(pixel_position, false, gathered)


## Fisher's depletion counterpart to _deplete_continuous above, deliberately
## NOT called every frame. Unlike record_vegetation_harvest_near/
## record_death_at (pure aggregate-population arithmetic, safe to call every
## frame with a tiny fractional amount), EarthChunkManager.
## record_fish_catch_near ALSO finds-and-queue_frees one real on-screen
## FishMarker within BIRD_CATCH_RADIUS every single call, regardless of how
## small `count` is -- it's built for PiscivoreBirdMarker's one-call-per-
## real-catch contract (paced seconds apart by that marker's own cruise/dive/
## cooldown state machine), not a continuous per-frame drip.
##
## _gather() runs once per rendered frame while a fisher works (NpcMarker.
## _process calls NpcEconomy.step() unthrottled), so calling this from
## _deplete_continuous the way farmer/hunter do would delete a real fish
## roughly every frame -- far more aggressively than the yield-proportional
## depletion this feature intends, and easily visible right at a fisher's
## own "dock" work location where fish spawn (see npc_planner.gd). Instead
## this is only called from _gather's existing FOOD_UNIT-accumulation loop
## above, once per whole food unit actually gathered -- the same discrete
## cadence a real catch already has for PiscivoreBirdMarker, and the same
## gate that loop already uses for the market stock/wallet gold update.
## Duck-typed fail-open, same convention as _deplete_continuous.
func _deplete_discrete_unit(world, pixel_position: Vector2) -> void:
	if world == null:
		return
	if occupation == "fisher" and world.has_method("record_fish_catch_near"):
		world.record_fish_catch_near(pixel_position, NpcProduction.FOOD_UNIT)


## Whether this villager can eat by simply doing their job right now: a
## producer standing in a region that still yields something real. Exactly
## the condition the free self-feed below turns on, named rather than
## restated so the two can never drift.
##
## NpcMarker reads it too, and that is the point of naming it. A hungry
## villager's schedule is interrupted to walk to the well and buy a meal,
## which is right for a blacksmith and wrong for a hunter, whose food is
## standing in the woods. Measured live (tools/probe_village_hunting.gd): a
## real hunter went hungry about twelve seconds in, with an empty village
## market and an empty purse, and never worked again for the remaining 227
## simulated seconds -- not working is precisely what stopped them
## producing the food they had been sent to buy, and the well had nothing
## on it and never would.
##
## False for a non-producer and for a producer whose region has genuinely
## collapsed, so the famine chain npc.md describes stays intact: nothing
## left to hunt is still nothing to eat.
func feeds_itself_from_work(world, pixel_position: Vector2) -> bool:
	if not _production.is_producer(occupation):
		return false
	return _production.yield_per_second(occupation, world, pixel_position) > 0.0


## Whether walking to the market would ACTUALLY get this villager a meal:
## there is a whole unit of real food within reach, and either they can pay
## for it or their village can advance them the subsistence wage that buys
## one.
##
## A pure query -- it moves no gold, no stock and no purse, so asking must
## never feed anybody.
##
## This is the gate on NpcMarker's hunger interrupt, and the honest general
## form of the rule that file's own comments already state: "The interrupt is
## for villagers who must BUY." A villager who CANNOT buy gains nothing by
## standing at the well and loses the work that is the only thing able to
## change either number.
##
## MEASURED on a real village (tools/probe_village_market.gd, with the whole
## settlement ticked rather than one villager alone): a merchant was hungry
## for 1589 of 1801 ticks with an empty purse, and their schedule's 825
## "work at the stall" ticks were overridden on every single one of them.
## The producer/own-field guards already on that interrupt were written for
## exactly this deadlock and cover neither a merchant, a blacksmith, a guard
## nor a nurse.
##
## The famine chain npc.md describes is untouched: a village with nothing to
## eat still starves. What changes is that its villagers starve AT WORK,
## where they might yet produce something, rather than queueing at a stall
## with nothing on it.
func can_obtain_a_meal(world = null, pixel_position: Vector2 = Vector2.ZERO) -> bool:
	if not market.can_buy_meal() and not _structure_meal_available(world, pixel_position):
		return false
	if wallet.can_afford(VillageWages.subsistence_wage()):
		return true
	return VillageWages.can_pay_subsistence(purse_of(_purse_market()))


## Makes `a_market` the SETTLEMENT PURSE this villager's subsistence wage
## is drawn from, in place of `market`'s own meta.
##
## They are not the same object, and that was the bug.
## EarthChunkManager._step_merchant_visits pays the merchant's gold into
## the settlement's PERSISTED Market (MarketStore.market_for), while the
## wage read purse_of(self.market), the live VillageMarket. PURSE_META is
## set on whichever market object is in hand, so those are two tanks
## sharing one name: a village could be paid and still starve beside its
## own stall.
##
## The persisted one wins, for the same reason bind_household_wallet exists
## at all: a VillageMarket is rebuilt from scratch on every chunk load, so
## a purse kept there dies with the chunk -- *"a villager's whole working
## life evaporated the moment the player walked away"*. A merchant can also
## visit a settlement whose chunk is not loaded, and his gold has to land
## somewhere that still exists when it is.
##
## Passing null is a harmless no-op, so a bare NpcEconomy -- a test, or a
## village with no settlement record yet -- behaves exactly as it did.
func bind_settlement_purse(a_market) -> void:
	if a_market == null:
		return
	_settlement_purse = a_market


## The ONE tank this villager's wage comes out of: the settlement's own
## purse when it has been bound, and otherwise the market they trade at.
## Never both -- the same coin must not be spendable twice.
func _purse_market():
	return market if _settlement_purse == null else _settlement_purse


func _try_eat(is_working: bool, world, pixel_position: Vector2) -> void:
	if is_working and feeds_itself_from_work(world, pixel_position):
		needs.feed()  # a free bite from their own active harvest -- see file doc comment
		return
	# ...and failing that, out of the basket in their own hands.
	#
	# Switching hauling on (NpcMarker.HAULING_CARRY_LIMIT) put a producer's
	# take into their HANDS until they walk it to the store, and every
	# other source below looks somewhere ELSE -- the stall, the purse, the
	# village's stores. So a hunter could starve to death carrying five
	# units of meat, and did: measured on a real village the moment
	# hauling went on, the roster fell 10 -> 2 inside one starvation window
	# of founding while the warehouse filled up behind them.
	#
	# Before the wage and the market on purpose: what you are already
	# holding costs the village nothing and is nearer than the stall.
	if _eat_from_the_load():
		needs.feed()
		return
	_draw_subsistence_wage(world, pixel_position)
	if market.buy_meal(wallet) != "":
		needs.feed()
		return
	# Nothing on the stall: the village's own STORES (docs/concept/milling_
	# and_baking.md) -- the persisted Market the merchant stocks and the
	# granary/trade fill, and the Bakery/Storage shelves baked bread ends up
	# on -- are food nobody ever ate before this. So "walk to the stores",
	# duck-typed like every other world read here, at the same meal price
	# and the same all-or-nothing wallet rule buy_meal keeps (see
	# EarthChunkManager.buy_village_meal_near). A world without the hook has
	# no stores to offer.
	if world != null and world.has_method("buy_village_meal_near"):
		if world.buy_village_meal_near(pixel_position, wallet) != "":
			needs.feed()


## Draws one subsistence wage from the village purse for a hungry villager
## who cannot pay for a meal themselves.
##
## Deliberately NOT gated on occupation. A wage is what the village can
## afford to pay anyone it is keeping alive, and a producer whose region has
## collapsed (zero yield, so no free self-feed and no income either -- see
## _try_eat above) is precisely the household docs/concept/npc.md's famine
## chain needs a safety net for. In practice a working producer's own
## take-home already covers the price, so this only ever fires for them once
## their work has genuinely stopped paying.
##
## The affordability gate is what keeps this a subsistence wage rather than
## a salary: one wage buys exactly one meal (VillageWages.subsistence_wage
## IS the market's live meal price), so a villager who has just drawn one
## can afford a meal and cannot draw again. Nobody accumulates a purse-
## funded hoard, and the check reads off VillageWages rather than
## VillageMarket's constant so `market` stays duck-typed here.
##
## Nothing is drawn when the market has nothing to sell: a wage buys exactly
## one meal, so paying it into an empty market buys nobody anything and only
## drains a settlement's savings into pockets during the famine it most
## needs them. VillageMarket.buy_meal is already all-or-nothing for that
## reason -- paying first would sidestep its own refusal.
func _draw_subsistence_wage(world = null, pixel_position: Vector2 = Vector2.ZERO) -> void:
	if wallet.can_afford(VillageWages.subsistence_wage()):
		return
	if not market.can_buy_meal() and not _structure_meal_available(world, pixel_position):
		return
	var purse_market = _purse_market()
	var payout := VillageWages.pay_subsistence(purse_of(purse_market))
	var paid := int(payout["paid"])
	if paid <= 0:
		return  # the village cannot afford a whole wage -- leave its purse exactly as it was
	wallet.add(paid)
	_set_purse(purse_market, float(payout["purse"]))


## Whether the village's own stores hold a whole meal near this villager
## (see _try_eat) -- the merchant's stall or a bakehouse counts as
## somewhere a wage buys a meal, so nobody starves next to a full one just
## because the day's gathering on the stall is bare.
func _structure_meal_available(world, pixel_position: Vector2) -> bool:
	if world == null or not world.has_method("has_village_meal_near"):
		return false
	return world.has_village_meal_near(pixel_position)
