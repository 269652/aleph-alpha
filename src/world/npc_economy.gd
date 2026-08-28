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
const Wallet = preload("res://src/gameplay/wallet.gd")

## Metadata key under which a settlement's shared purse balance is kept on
## its VillageMarket -- see the file doc comment.
const PURSE_META := "village_purse_gold"

var needs: NpcNeeds
var wallet: Wallet
var occupation: String
var market  # VillageMarket, shared by every NpcMarker of the same settlement

var _production := NpcProduction.new()
var _accumulated_yield := 0.0

## This household's own unbanked take-home gold. Take-home is a fraction of
## a single gold coin per gathered food unit (VillageWages.take_home_of) and
## a Wallet holds only whole gold, so it accrues here and is banked a coin
## at a time -- the same carry-until-it-crosses-a-whole-unit idiom
## _accumulated_yield already runs on. Truncating per earning instead would
## round every producer's income to zero and silently hand the whole gross
## to the purse.
var _take_home_carry := 0.0


## The shared purse of the settlement `a_market` belongs to, in gold. Static
## because the balance belongs to the village, not to any one villager who
## happens to read it. A market that has never been levied holds nothing.
static func purse_of(a_market) -> float:
	if a_market == null:
		return 0.0
	return float(a_market.get_meta(PURSE_META, 0.0))


static func _set_purse(a_market, gold: float) -> void:
	if a_market == null:
		return
	a_market.set_meta(PURSE_META, gold)


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
func step(delta_seconds: float, is_working: bool, world, pixel_position: Vector2) -> void:
	needs.advance(delta_seconds)
	if is_working and _production.is_producer(occupation):
		_gather(delta_seconds, world, pixel_position)
	if needs.is_hungry():
		_try_eat(is_working, world, pixel_position)


## Land health (docs/concept/world.md "Land health: overharvesting leaves a
## lasting mark, not just a slower respawn"): only "farmer" reads/depletes
## vegetation_density_near -- hunter/fisher read a different resource pool
## entirely (herbivore/fish population) and must not also drain vegetation.
const _VEGETATION_HARVESTING_OCCUPATION := "farmer"


func _gather(delta_seconds: float, world, pixel_position: Vector2) -> void:
	var rate := _production.yield_per_second(occupation, world, pixel_position)
	var gathered := rate * delta_seconds
	_accumulated_yield += gathered

	# The exact same real yield just gathered ALSO leaves this region's real
	# standing vegetation -- previously a farmer only ever READ this number,
	# never removed anything from it (only weather ever moved it). This is
	# what makes sustained NPC farming, not just the player's, a real
	# land-health depletion driver (see EarthChunkManager.
	# record_vegetation_harvest_near / EcosystemSimulation.
	# record_vegetation_harvest). Duck-typed fail-open, matching the rest of
	# this codebase's world-duck-typing: a world without the hook (an older
	# double, or a caller that hasn't wired it) is a harmless no-op.
	if (
		occupation == _VEGETATION_HARVESTING_OCCUPATION
		and world != null
		and world.has_method("record_vegetation_harvest_near")
	):
		world.record_vegetation_harvest_near(pixel_position, gathered)

	while _accumulated_yield >= NpcProduction.FOOD_UNIT:
		_accumulated_yield -= NpcProduction.FOOD_UNIT
		market.add_stock(_production.item_id_for(occupation), NpcProduction.FOOD_UNIT)
		_earn(float(NpcProduction.YIELD_TO_GOLD_RATE))


## Splits one food unit's gross gold between the village purse and this
## producing household's own wallet, at VillageWages' derived levy rate. The
## split creates and destroys no gold (VillageWages.take_home_of is the exact
## complement of levy_on); the only gold that ever sits outside both is this
## household's sub-coin carry.
func _earn(gross_gold: float) -> void:
	_set_purse(market, VillageWages.deposit(purse_of(market), gross_gold))
	_take_home_carry += VillageWages.take_home_of(gross_gold)
	while _take_home_carry >= 1.0:  # 1.0 == one whole coin, the only amount a Wallet can hold
		_take_home_carry -= 1.0
		wallet.add(1)


func _try_eat(is_working: bool, world, pixel_position: Vector2) -> void:
	if is_working and _production.is_producer(occupation):
		var current_yield := _production.yield_per_second(occupation, world, pixel_position)
		if current_yield > 0.0:
			needs.feed()  # a free bite from their own active harvest -- see file doc comment
			return
	_draw_subsistence_wage()
	if market.buy_meal(wallet) != "":
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
func _draw_subsistence_wage() -> void:
	if wallet.can_afford(VillageWages.subsistence_wage()):
		return
	if not market.can_buy_meal():
		return
	var payout := VillageWages.pay_subsistence(purse_of(market))
	var paid := int(payout["paid"])
	if paid <= 0:
		return  # the village cannot afford a whole wage -- leave its purse exactly as it was
	wallet.add(paid)
	_set_purse(market, float(payout["purse"]))
