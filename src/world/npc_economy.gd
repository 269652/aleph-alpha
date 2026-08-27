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


func _gather(delta_seconds: float, world, pixel_position: Vector2) -> void:
	var rate := _production.yield_per_second(occupation, world, pixel_position)
	var gathered := rate * delta_seconds
	_accumulated_yield += gathered
	_deplete_continuous(world, pixel_position, gathered)

	while _accumulated_yield >= NpcProduction.FOOD_UNIT:
		_accumulated_yield -= NpcProduction.FOOD_UNIT
		market.add_stock(_production.item_id_for(occupation), NpcProduction.FOOD_UNIT)
		wallet.add(NpcProduction.YIELD_TO_GOLD_RATE)
		_deplete_discrete_unit(world, pixel_position)


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


func _try_eat(is_working: bool, world, pixel_position: Vector2) -> void:
	if is_working and _production.is_producer(occupation):
		var current_yield := _production.yield_per_second(occupation, world, pixel_position)
		if current_yield > 0.0:
			needs.feed()  # a free bite from their own active harvest -- see file doc comment
			return
	if market.buy_meal(wallet) != "":
		needs.feed()
