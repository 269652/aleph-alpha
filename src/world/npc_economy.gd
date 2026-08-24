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

const NpcNeeds = preload("res://src/world/npc_needs.gd")
const NpcProduction = preload("res://src/world/npc_production.gd")
const Wallet = preload("res://src/gameplay/wallet.gd")

var needs: NpcNeeds
var wallet: Wallet
var occupation: String
var market  # VillageMarket, shared by every NpcMarker of the same settlement

var _production := NpcProduction.new()
var _accumulated_yield := 0.0


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
		wallet.add(NpcProduction.YIELD_TO_GOLD_RATE)


func _try_eat(is_working: bool, world, pixel_position: Vector2) -> void:
	if is_working and _production.is_producer(occupation):
		var current_yield := _production.yield_per_second(occupation, world, pixel_position)
		if current_yield > 0.0:
			needs.feed()  # a free bite from their own active harvest -- see file doc comment
			return
	if market.buy_meal(wallet) != "":
		needs.feed()
