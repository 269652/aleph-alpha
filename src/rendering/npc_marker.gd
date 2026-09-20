extends Sprite2D

## The cheap local FSM half of docs/concept/npc.md's "Planning architecture":
## walks toward wherever the current schedule entry's location_tag resolves
## to, re-deriving the current entry from elapsed time every frame -- zero
## planner calls mid-day, matching CreatureWander/FishMarker's "pure,
## deterministic, no per-frame AI" philosophy rather than CreatureMarker's
## full sense/perceive/act loop (an NPC just walks its plan, it doesn't hunt
## or flee).

const NpcIdentity = preload("res://src/world/npc_identity.gd")
const NpcPlanner = preload("res://src/world/npc_planner.gd")
const NpcSchedule = preload("res://src/world/npc_schedule.gd")
const WaterErrand = preload("res://src/emergence/water_errand.gd")
const HouseholdWater = preload("res://src/emergence/household_water.gd")
const NpcEconomy = preload("res://src/world/npc_economy.gd")
const NpcInstructionEvaluator = preload("res://src/world/npc_instruction_evaluator.gd")
const CharacterView = preload("res://scenes/character_view.gd")
const CreaturePerception = preload("res://src/gameplay/creature_perception.gd")
const AgentPassability = preload("res://src/gameplay/agent_passability.gd")
const TerrainPassability = preload("res://src/gameplay/terrain_passability.gd")
const TileRouter = preload("res://src/gameplay/tile_router.gd")
const ForagerBehavior = preload("res://src/gameplay/forager_behavior.gd")
const VillageFarm = preload("res://src/gameplay/village_farm.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const ProceduralItemSprite = preload("res://src/rendering/procedural_item_sprite.gd")
const FarmerBehavior = preload("res://src/gameplay/farmer_behavior.gd")
const HuntableQuarry = preload("res://src/gameplay/huntable_quarry.gd")
const Carcass = preload("res://src/rendering/carcass.gd")
const NpcCondition = preload("res://src/world/npc_condition.gd")
const VillagerBehavior = preload("res://src/gameplay/villager_behavior.gd")
const VillageSawmill = preload("res://src/gameplay/village_sawmill.gd")
const VillageCart = preload("res://src/gameplay/village_cart.gd")
const CartLoad = preload("res://src/gameplay/cart_load.gd")
const CartMarker = preload("res://src/rendering/cart_marker.gd")
const LogisticsBehavior = preload("res://src/gameplay/logistics_behavior.gd")
const LumberjackBehavior = preload("res://src/gameplay/lumberjack_behavior.gd")
const SagewerkProduction = preload("res://src/world/sagewerk_production.gd")
const ChoppableTree = preload("res://src/rendering/choppable_tree.gd")
const FelledTree = preload("res://src/rendering/felled_tree.gd")
const Ethogram = preload("res://src/gameplay/ethogram.gd")

## Walking pace -- similar order to CreatureWander.WANDER_SPEED, unhurried.
const WALK_SPEED := 20.0

## Chasing pace, for the one part of a villager's day that is a chase (see
## docs/concept/npc.md, "A hunter runs, and the run is paid for in stamina").
##
## Exactly twice the walk, which is not a new number: it is the same
## doubling the player's own sprint already is of their own base speed
## (Player.SPRINT_SPEED == BASE_SPEED * 2), cross-pinned by test so the two
## cannot drift into two different ideas of what running means. It also
## lands exactly on CreatureMarker.FLEE_SPEED, so a running hunter keeps
## pace with a bolting deer instead of out-sprinting it -- the honest
## outcome: a kill comes from the animal's fear running out before the
## hunter's legs do.
const RUN_SPEED := WALK_SPEED * 2.0

## How close (pixels) to home_position counts as "arrived" for the
## hidden-while-home check below -- move_toward closes in asymptotically
## and rarely lands on the exact float, so "distance == 0.0" would flicker
## visible/invisible near the doorstep. Small relative to a single tile
## (TILE_SIZE 16) and to WALK_SPEED, so it reads as "at the door", not
## "somewhere on the street".
const _ARRIVED_HOME_EPSILON_PX := 1.0

## Real seconds per simulated in-game day, mirroring
## EarthChunkManager.SECONDS_PER_SIMULATED_DAY's existing pacing so a
## village's daily rhythm runs on the same clock as the rest of the world
## sim.
const SECONDS_PER_SIMULATED_DAY := 60.0

var identity: NpcIdentity
var home_position := Vector2.ZERO
## Where this NPC works when their occupation's location_tag isn't one of
## the settlement's 3 shared landmarks (well/stall/gate) -- see
## SettlementGenerator's scope note on not modeling per-occupation buildings
## yet.
var workspot_position := Vector2.ZERO
var landmarks: Dictionary = {}
## The door of this settlement's store, or null when it has none (see
## docs/concept/village_warehouse.md pillar 1's caveat: a cramped site
## houses its people and goes without). Deliberately NOT a fourth entry in
## `landmarks` -- that dictionary is the settlement's three SHARED landmarks,
## and every reader of it treats a key as a schedule location_tag with a prop
## to draw. The store already has a real building standing on it.
##
## Setting it is also what decides whether this villager CARRIES at all: a
## store to walk to is the whole reason a load is held rather than stocked
## on the spot. Through a setter and again from setup_economy so the two can
## be assigned in either order -- VillageRenderer sets the door first, an
## isolated test may not.
var warehouse_position = null:
	set(value):
		warehouse_position = value
		_apply_carry_limit()
var schedule: Array = []

var _elapsed_time := 0.0
var _day_index := 0
var _planner: NpcPlanner.Planner = NpcPlanner.FakeNpcPlanner.new()

## Duck-typed world (biome_at_global) and tile size, mirroring
## CreatureMarker.setup -- lets an NPC tell whether it's standing in water so
## its walk cycle can switch to swimming, same as the player/creatures.
## Without it (fail-open, see _is_in_water), an NPC just never swims.
var _world = null

## Which leg of the trip to the well this villager is on (docs/concept/
## village_water.md mechanism 2). Public because it IS what they are doing,
## and because what they are carrying is read straight off it.
var water_errand := WaterErrand.AT_HOME

## The building this errand's bucket is FOR -- their own house, or the
## farmhouse whose FIELD drinks out of its own tank (docs/concept/
## village_water.md mechanism 3). {} when nobody is on an errand.
##
## LATCHED when they set out rather than re-read each frame: whichever
## building sent them is the building the bucket comes back to. Re-reading
## would let a villager change their mind halfway across the square when
## the other tank crossed its own threshold, and the bucket in their hand
## would silently change what it was for.
var _errand_target: Dictionary = {}

## The nearest this leg has brought them to where the bucket is going, how
## long since that last improved (see ERRAND_PATIENCE_SECONDS), and how
## long they stay off the errand once a leg has defeated them.
var _errand_closest_px := INF
var _errand_stalled_seconds := 0.0
var _errand_retry_in := 0.0
## Where the errand is sending them right now, "" when they are not on one.
var _errand_location_tag := ""
## The tag the last processed frame actually walked toward -- what
## current_location_tag reports when no errand is running.
var _last_location_tag := "home"
var _tile_size := 16

## Which tiles this villager may not step into -- building footprints (see
## AgentPassability). Invalid until setup() binds a world that can answer,
## and left invalid for one that cannot, so an unbound marker walks exactly
## as it always did.
var _wall_tiles := Callable()

## How much A* a single villager may spend on one route (see
## docs/concept/navigation.md). A chunk is 32x32, so 1024 tiles is a full
## chunk-wide search; this allows that plus headroom for re-expansion, and
## caps the worst case directly rather than trusting the goal to be near.
const ROUTE_NODE_BUDGET := 1500

## The smallest gap between two recomputes of a route. A villager walking
## to a fixed doorstep pays for ONE search; this only matters for a moving
## destination (a hunter's quarry), where the goal tile can change every
## frame and an unthrottled A* would run every frame with it.
const ROUTE_RECOMPUTE_SECONDS := 0.5

## Tiles still to walk (TileRouter), the destination they were computed
## for, and time since that computation. Empty route means "no detour
## needed or none found" -- either way the villager walks straight at its
## target and _slid_along_walls keeps it out of walls.
var _route: Array = []
var _route_goal_tile := Vector2i(2147483647, 2147483647)
var _route_age := 0.0

## How much longer each tile takes to cross than open flat ground (see
## AgentPassability) -- water is slow but crossable, so a villager routes
## round a river when there is a dry way and wades when there is not.
var _route_cost := Callable()
var _perception := CreaturePerception.new()

## docs/concept/npc.md "Needs and the local production economy": this
## villager's hunger/gold/production state, mirroring the daily-plan
## FSM's own "cheap local execution" pattern -- null until setup_economy is
## called (see VillageRenderer._build_npc), so a marker built without an
## economy (e.g. an isolated rendering test) simply carries no needs state
## rather than crashing.
var economy: NpcEconomy = null

## Which occupations work real, individual quarry they walk to and take
## themselves, rather than only reading their region's aggregate
## (docs/concept/npc.md, "Work against the real world, not against a
## number") -- and which KIND, because the two are found and taken through
## different machinery:
##
## - "creature": a real CreatureMarker in the shared creature group,
##   filtered by HuntableQuarry and struck with the same take_damage() a
##   wolf's own bite calls.
## - "fish": a real FishMarker, which no group indexes -- the chunk manager
##   owns those. Found and taken through the two world hooks the player's
##   own rod and a diving bird already use (nearest_fish_position,
##   catch_nearest_fish).
##
## The farmer and the herbalist are absent from THIS table and stay
## absent -- but no longer because they have nothing real to work. They
## work ground rather than individuals: a fixed field of tiles their own
## farmhouse owns, found by geometry rather than by scanning, and tended
## through the FarmPlot lifecycle instead of struck. See _step_farm below
## and docs/concept/village_farms.md. What follows was the reason before
## that existed, and is kept because it still explains why they are not
## quarry:
##
## there is no crop entity standing in the world to harvest the way there
## is an animal or a fish, and vegetation_density_near is a field, not a
## thing. Inventing one
## to make the third producer symmetrical is exactly the premature system
## that doc warns against -- real crop entities belong to the
## farm/mill/bakery chain when it comes.
const QUARRY_KIND_BY_OCCUPATION := {"hunter": "creature", "fisher": "fish"}

## How far a villager's rod reaches over the water, and therefore how close
## to the fish they walk before stopping on the bank.
## Player.FISH_CATCH_RADIUS's own value, test-pinned
## (test_cast_distance_matches_the_players_own_rod): a villager's rod is
## the player's rod, and that constant's own doc comment already says what
## the number is for -- "generous enough to cover a pond fish a few tiles
## out while standing at the shore". Much longer than
## HuntableQuarry.STRIKE_DISTANCE_PX for the obvious reason: a spear has to
## touch the deer, a line does not.
const CAST_DISTANCE_PX := 64.0

## How often a villager actually looks around for quarry, cached in
## between. CreatureMarker.SENSE_INTERVAL's own value, test-pinned
## (test_a_villager_looks_around_as_often_as_a_creature_senses): finding
## quarry means walking the whole creature group, which that marker's own
## _scan_nearby_creatures doc comment already calls out as O(n^2) across a
## loaded population, and its answer -- "the expensive part of the AI ...
## runs at most this often, cached in between, rather than every frame" --
## is the same answer for the same cost. A villager looking for a deer is
## the same expensive part of the same AI.
const QUARRY_SCAN_INTERVAL := 0.25

## This villager's hunt, or null for anyone whose occupation does not take
## real quarry -- the same null-until-wired pattern `economy` above uses,
## so a marker built without one behaves byte-for-byte as before. Built by
## setup_economy, which is where the occupation is first read.
##
## ForagerBehavior decides WHEN (look around, commit, arrive, strike),
## HuntableQuarry decides WHAT (a living, wild, non-boss, untamed animal),
## and this marker owns the world effect, exactly the split
## LumberjackBehavior/LumberjackMarker already use for the axe.
var _forager: ForagerBehavior = null

## This villager's own stamina and fitness (NpcCondition). Public like
## `economy`: what a body has left is worth reading from outside, and the
## hunt tests drive it directly. Live per-marker state, not persisted --
## the same lifetime their schedule and their hunger already have.
var condition := NpcCondition.new()

## The real animal this villager has committed to, or null. Never assumed
## to still be there: every phase re-checks it through HuntableQuarry,
## since it can be killed by a predator, flee, or have its chunk unload
## between one frame and the next.
var _quarry = null

## "creature", "fish", or "" for a villager whose work is not taken from
## the world one individual at a time. Set by setup_economy from
## QUARRY_KIND_BY_OCCUPATION above.
var _quarry_kind := ""

## The GLOBAL tiles this villager's own farmhouse owns and they therefore
## work (docs/concept/village_farms.md). Assigned by VillageRenderer, which
## is the only thing that knows which farmhouse is whose; empty for every
## villager who does not farm, and for a farmer whose village has not
## raised a farmhouse yet -- who then keeps the regional drip they always
## had.
var field_cells: Array[Vector2i] = []

## The sentinel stock_building_cell carries when this villager has none -- a
## village that has not raised one yet, or a villager there was no room for.
## Not Vector2i.ZERO: that is a real world tile.
const NO_STOCK_BUILDING := Vector2i(-2147483648, -2147483648)

## The GLOBAL tile of the building this villager fills with what they
## produce, or NO_STOCK_BUILDING. A farmer's own farmhouse; a fisher's own
## house, since a fisher lives in an ordinary one and there is no separate
## building to hang a pond on (docs/concept/village_ponds.md).
##
## Named for the JOB it does rather than for the farmer who had it first:
## the harvest chain below is the same chain for both, and a field called
## farmhouse_cell holding a fisher's cottage would be a lie in the one place
## a reader goes to check where a catch went.
##
## Assigned by VillageRenderer alongside the ground this villager works,
## which is the only thing that knows whose is whose.
##
## What a harvest needs, and what it did not have. Asked for directly:
## *"make sure wheat grows and is harvested which increases farmhouse stock
## which gets transported to city stock"*. The middle of that chain did not
## exist -- a villager's harvest went straight into the village market, so
## the farmhouse they grew it for never held a grain of it and nothing was
## ever carried anywhere. See _work_field_cell and
## haul_stock_to_village.
var stock_building_cell: Vector2i = NO_STOCK_BUILDING

## The sentinel sawmill_cell carries when this villager has none.
const NO_SAWMILL := Vector2i(-2147483648, -2147483648)

## The store this villager carts for, and the producers whose shelves they
## empty into it -- GLOBAL anchor cells, handed over by VillageRenderer the
## same way a sawyer is handed their mill. NO_STORE for every villager who
## is not this village's carter (docs/concept/village_warehouse.md,
## Mechanism 4).
const NO_STORE := Vector2i(-2147483648, -2147483648)
var store_cell: Vector2i = NO_STORE
var producer_cells: Array[Vector2i] = []

## The Bollerwagen this carter pulls (a CartMarker), or null. The goods ride
## ON IT -- a cart left standing is a cart with the timber still in it, which
## is the whole point of the trade having one (Mechanism 5).
var cart = null

var _carter: LogisticsBehavior = null
var _round_shelf: Vector2i = NO_STORE

## The GLOBAL tile of the sawmill this villager works, or NO_SAWMILL
## (docs/concept/village_timber.md). Assigned by VillageRenderer, the only
## thing that knows which mill is whose -- the same shape stock_building_cell has.
##
## Reported in play: "The sawmill also never produces any beams and doesn't
## even have a dedicated worker".
var sawmill_cell: Vector2i = NO_SAWMILL

## How hard one swing bites, and the sawyer's own phase machine. Both are
## the tile-scale Lumberjack's (LumberjackMarker.FELL_DAMAGE,
## LumberjackBehavior) -- a villager swinging an axe is not a second
## mechanic, it is the same one with a different caller.
const FELL_DAMAGE := 5.0

var _sawyer: LumberjackBehavior = null
var _timber_target: Node2D = null
var _carried_logs := 0
var _shaping_elapsed := 0.0

## This villager's farm work, or null for anyone who does not farm -- the
## same null-until-wired shape `_forager` above uses, built by
## setup_economy where the occupation is first read. The very same
## FarmerBehavior phase machine the placeable Farm's own worker runs
## (docs/concept/npc_farm_production.md): walking out to a bed, kneeling
## over it and getting up again is one action whoever is doing it.
var _farmer: FarmerBehavior = null

## What this villager's field grows ("wheat"/"herb"), or "" -- from
## VillageFarm.CROP_BY_OCCUPATION.
var _field_crop := ""

## Index into `field_cells` of the tile currently committed to, or -1.
var _field_index := -1

## Whether real field work is in hand right now. Gates the regional
## production drip exactly as _on_real_quarry does for the hunter: a
## villager is paid for what their own ground actually yielded, never for
## that AND an ambient number at the same time.
var _on_real_field := false

## Whether this villager's own store has already been carried in since their
## work block ended.
##
## The haul is the END of the block, and an end happens once. Reported live
## with the farmhouse panel open: "der Farmer scheint was zu ernten und
## läuft dann zum Farmhouse aber es wird kein Weizen eingelagert" -- it ran
## on EVERY off-clock frame, so anything reaching the store outside the work
## block was drained again within a frame and a store could never hold a
## thing overnight.
##
## One flag for the field and the pond alike: a villager works one or the
## other, both carry their take in at the same moment, and two flags would
## be two places to forget to clear.
var _carried_in_since_work := false

## Whether the store's round is in flight right now: a carter on the clock,
## with the shaft in their hands. Read by is_on_real_work, exactly as
## _on_real_field and _on_real_work_timber are.
var _on_real_round := false

## How close counts as standing on a plot: half a tile, so a villager on
## the tile is working it rather than walking the last few pixels onto its
## exact centre. In tiles, against the real tile size setup() was given,
## rather than a pixel count that would silently mean something else at
## another tile size.
const FIELD_REACH_TILES := 0.5

## How far the water runs from the bed a farmer is working: one tile, the
## beds they could reach without moving. See _water_the_beds_around.
const TEND_REACH_TILES := 1

## The throttle above: seconds since the last real scan, what it found, and
## a count of the real scans performed. Starts already due, so the first
## working frame of a day knows whether quarry is there rather than drawing
## the conjured drip for an interval while standing next to a deer. The
## count exists so a test can prove the throttle really holds -- exactly
## what CreatureMarker._creature_scan_count exists for.
var _quarry_scan_elapsed := QUARRY_SCAN_INTERVAL
var _scanned_quarry = null
var _quarry_scan_count := 0

## Whether real quarry is available to this villager RIGHT NOW -- committed
## to, or merely standing within reach. What NpcEconomy.step reads to know
## the regional drip does not apply (see its own on_real_quarry doc).
##
## Deliberately wider than "currently committed": docs/concept/npc.md keeps
## the aggregate path as the fallback for a village whose chunks hold NO
## loaded animals, not as a top-up for the seconds between one kill and the
## next. Paid only for committed time, a hunter would still draw most of
## their income from a number -- the drip runs at
## NpcProduction.PRODUCTION_RATE_PER_SECOND x the regional headcount, which
## across a look-around interval and a walk outruns a real deer several
## times over, and hunting would stay decorative.
var _on_real_quarry := false

## An optional standing instruction script (docs/concept/
## npc_instructions.md, "Execution / wiring") -- null for every NPC by
## default, parallel to `economy`'s own null-checked pattern above, so a
## marker with no assigned instruction is byte-for-byte unaffected. When
## set, holds the parsed AST Dictionary NpcInstructionParser.parse(source)
## ["ast"] produces ({"kind": "instruct", "rules": [...]}) -- the same shape
## NpcInstructionEvaluator.evaluate consumes directly.
var instruction_script = null

## This NPC's real held items (docs/concept/npc_instructions.md, the
## per-NPC/household inventory `_instruction_frame()` reads for
## `inventory_at_least`). A real Dictionary (item_id -> int count), NOT
## null-checked like `economy`/`instruction_script` above -- an empty
## inventory is a valid real state (an NPC that genuinely holds nothing),
## not an absence to guard against. Read/written via NpcInventory's pure
## add/remove/count_of helpers (src/world/npc_inventory.gd).
var inventory := {}


## Swaps in a different planner (e.g. a future real LLM-backed one) -- see
## NpcPlanner.Planner. Defaults to the deterministic FakeNpcPlanner.
func set_planner(planner: NpcPlanner.Planner) -> void:
	_planner = planner


## Gives the NPC the world it senses, enabling water-awareness. See
## CreatureMarker.setup, which this mirrors exactly.
func setup(world, tile_size: int) -> void:
	_world = world
	_tile_size = tile_size
	# Built ONCE here, not per frame: this predicate is called up to three
	# times per villager per frame by the router, and allocating a
	# fresh lambda each time is exactly the kind of per-frame churn the
	# creature-blocker cache already exists to avoid. Invalid when the
	# world cannot answer, which the gate reads as "nothing is solid" --
	# the same duck-typed fail-open _is_in_water makes.
	_wall_tiles = AgentPassability.blocked_predicate_for(world)
	_route_cost = AgentPassability.cost_scale_for(world)


## Builds this villager's NpcEconomy from its already-assigned `identity`
## (must be set first -- see VillageRenderer._build_npc) and `market`, the
## VillageMarket instance shared by every NpcMarker of the same settlement.
## `household_wallet` is this villager's own persistent household purse
## (EarthChunkManager.household_wallet_for_villager). Optional and
## duck-typed like every other world hook here -- null keeps the economy's
## own ephemeral wallet, which is all an isolated test ever needs.
func setup_economy(market, household_wallet = null) -> void:
	economy = NpcEconomy.new(identity.seed_value, identity.occupation, market)
	economy.bind_household_wallet(household_wallet)
	_quarry = null
	_quarry_kind = String(QUARRY_KIND_BY_OCCUPATION.get(identity.occupation, ""))
	_forager = ForagerBehavior.new() if _quarry_kind != "" else null
	_field_crop = VillageFarm.crop_for(identity.occupation)
	_field_index = -1
	_on_real_field = false
	_farmer = FarmerBehavior.new() if _field_crop != "" else null
	_apply_carry_limit()


## What a villager with a store to carry to may hold before their hands are
## full -- and it is 0.0, which means hauling is WIRED BUT NOT SWITCHED ON.
##
## Reported live against 0.0.2: *"now no stock gets produced anywhere"*.
## Turning carrying on in a real village inserts the villager's hands into
## the middle of a chain another pass had just built. _step_farm calls
## haul_stock_to_village the moment a farmer goes off the clock, which
## empties the farmhouse straight into NpcEconomy.record_real_harvest -- and
## with a carry limit that goes to the HANDS, not the market. Nothing then
## reaches the village until that villager accumulates a whole load AND
## completes a walk to the door. Producers that GATHER are worse: _gather
## takes nothing more once the hands are full, so they stop dead.
##
## Neither showed up in tests because both sides were honest in isolation:
## every marker built by a test sets no warehouse_position, so carry_limit
## stayed 0 and every existing assertion passed.
##
## The channel, the drive, the wiring, the carried load and all of their
## tests stay exactly as they are. What is switched off is only the caller
## that opts a REAL villager in. Raising this to NpcEconomy.CARRY_LIMIT is
## the whole of switching hauling back on, once delivery is proven to
## complete in a running village rather than in a unit test.
const HAULING_CARRY_LIMIT := 0.0


## A villager with a store to carry to holds their take until they reach it;
## one without keeps stocking the village outright, which is what a
## settlement that went without a store still needs them to do.
func _apply_carry_limit() -> void:
	if economy == null:
		return
	economy.carry_limit = HAULING_CARRY_LIMIT if warehouse_position != null else 0.0


func _process(delta: float) -> void:
	_elapsed_time += delta
	# Real day-rollover replanning (docs/progress.md's Interrupt/Replan
	# Handling row: "today's schedule always runs to completion and only
	# re-plans on day rollover"). That claim was previously FALSE in code:
	# _day_index was declared but never incremented, and `schedule` was
	# only ever computed once, the first time it was empty, and never
	# cleared again -- so plan_day() ran exactly ONCE per NPC for their
	# entire existence, not once per in-game day as every doc comment in
	# this file already claimed. current_day is derived the same way
	# _current_hour() already derives hour-of-day, from this NPC's own
	# local _elapsed_time clock -- no dependency on the world's real clock.
	var current_day := int(_elapsed_time / SECONDS_PER_SIMULATED_DAY)
	if schedule.is_empty() or current_day != _day_index:
		_day_index = current_day
		schedule = _planner.plan_day(identity, _day_index)

	# THIS villager's own hour, not the village's. Reported live: "every once
	# in a while all villagers go to the well at the same time and then walk
	# away a bit later all at the same time.. that looks very weird". Every
	# villager read the same world hour, so a whole village rose, worked,
	# drank and slept in step to the second -- see NpcSchedule.personal_hour
	# for the shift that is each villager's own.
	var entry := NpcSchedule.current_entry_for(
		schedule, _hour_of_day(), 0 if identity == null else identity.seed_value
	)
	# The trip to the well (docs/concept/village_water.md). An errand
	# outranks a TIMETABLE -- being in the middle of carrying a bucket is a
	# fact, where a schedule entry is only an intention -- so it replaces
	# the entry here. It deliberately ranks BELOW the hunger interrupt just
	# after it: a starving villager puts the bucket down, because thirst
	# answered from a household tank is never as urgent as having nothing
	# to eat.
	_step_water_errand(delta)
	_sync_carried_item()
	if WaterErrand.overrides_schedule(water_errand):
		entry = {
			"time_block": entry.get("time_block", ""),
			"location_tag": _errand_location_tag,
			"activity": "fetch_water",
		}

	# A real, urgent need overrides wherever today's ordinary schedule says
	# to be right now (docs/progress.md's Interrupt/Replan Handling row: "a
	# need crossing a threshold") -- without this, hunger only ever
	# resolved through NpcEconomy.step's own background market transaction
	# (see that function), which never checks WHERE the NPC actually is, so
	# a starving villager kept visibly standing at/walking to their
	# scheduled spot the whole time, reading as oblivious to their own
	# need. Checked BEFORE instruction_script below so an explicit,
	# player-authored standing instruction still has the final say when it
	# actually produces an action -- this is only ever the fallback default.
	# ... unless working IS eating for them. A producer standing in a region
	# that still yields feeds itself free from its own harvest (see
	# NpcEconomy.feeds_itself_from_work), so sending it to the stall trades
	# a meal it already has for one it has to buy. Worse, measured live
	# (tools/probe_village_hunting.gd): a real hunter went hungry about
	# twelve seconds in with an empty village market and an empty purse,
	# and then never worked again for the remaining 227 simulated seconds,
	# because this interrupt fires every frame and not working is exactly
	# what stopped them producing the food they had been sent to buy. The
	# interrupt is for villagers who must BUY, which is what npc.md
	# describes it as; a producer whose region has genuinely collapsed is
	# one of them again, so the famine chain stays intact.
	if (
		economy != null
		and economy.needs.is_hungry()
		# A villager with a field of their own feeds themselves from work
		# exactly as a producer whose region still yields does: the crop
		# they are standing in becomes real market stock they can buy from,
		# so this interrupt would pull them off the very work that answers
		# it. For a herbalist that is not a nicety but the difference
		# between working and starving -- they are not in
		# NpcProduction.PRODUCER_ITEM_BY_OCCUPATION at all, so the drip
		# never fed them, and a market with nothing in it cannot either:
		# hungry, they would walk to the well, fail to buy, and never
		# return to the field that would have stocked it. The same famine
		# deadlock the producer branch already exists to avoid.
		and not _works_their_own_field()
		and not economy.feeds_itself_from_work(_world, position)
		# ...and there has to BE a meal at the end of the walk. The two
		# guards above were written for exactly this deadlock and cover only
		# producers and villagers with a field; a merchant, a blacksmith, a
		# guard and a nurse are none of those. MEASURED on a real village
		# (tools/probe_village_market.gd, the whole settlement ticked): a
		# merchant was hungry for 1589 of 1801 ticks with an empty purse,
		# and every one of their 825 scheduled "work at the stall" ticks was
		# overridden and spent at a well with nothing on it -- so they never
		# worked, never earned, and stayed hungry for ever. The interrupt is
		# for villagers who must BUY (see above); a villager who CANNOT buy
		# gains nothing by going and loses the only thing that could change
		# either number. See NpcEconomy.can_obtain_a_meal.
		and economy.can_obtain_a_meal(_world, position)
	):
		entry = {"time_block": entry.get("time_block", ""), "location_tag": "well", "activity": "eat"}
	if instruction_script != null:
		var action: Variant = NpcInstructionEvaluator.evaluate(instruction_script, _instruction_frame())
		if action != null:
			entry = _entry_for_instructed_action(action)
	var location_tag: String = entry.get("location_tag", "home")
	_last_location_tag = location_tag
	var is_working: bool = entry.get("activity", "") == "work"
	var target := _resolve_location(location_tag)
	# A hunter with a real animal in reach goes to the animal, not to the
	# decorative prop their schedule calls a workspot (docs/concept/npc.md,
	# "Work against the real world, not against a number"). Returns null
	# whenever there is no real quarry in hand, and then the ordinary
	# schedule target below is unchanged -- which is also the fallback an
	# unloaded chunk's village keeps running on.
	var quarry_target = _step_hunt(delta, is_working)
	if quarry_target != null:
		target = quarry_target
	# A farmer or a herbalist with a real field of their own goes out to it
	# rather than to the decorative prop their schedule calls a workspot --
	# the same override, for the same reason, as the hunter's above (see
	# docs/concept/village_farms.md). Null for everyone else, and for a
	# village that has not raised a farmhouse yet.
	var field_target = _step_farm(delta, is_working)
	if field_target != null:
		target = field_target
	# And a fisher with a pond of their own works it, for exactly the same
	# reason and with the same override (docs/concept/village_ponds.md).
	var pond_target = _step_pond(delta, is_working)
	if pond_target != null:
		target = pond_target
	# And a villager with a real NEED of their own answers it, wherever
	# today's schedule says to be (docs/concept/npc_social_life.md). The same
	# override shape, for the same reason, as the two above -- the schedule
	# says where a villager would BE, drives say what they DO. Null for a
	# villager with nothing pressing, and then the schedule simply stands.
	#
	# Deliberately LAST of the three: real work against the real world
	# outranks a need, so a hunter mid-chase finishes the chase. Hunger is
	# not here at all -- it keeps the dedicated interrupt above, which
	# carries guards (a producer who feeds itself, a villager with their own
	# field) that a whole famine chain was measured into and that this
	# generic layer has no way to express.
	# A lumberjack with a mill of their own works timber -- out to a real
	# tree, back to the mill, and the mill squares beams. The same override
	# shape, and the same place in the chain, as the hunt and the field
	# (docs/concept/village_timber.md).
	var timber_target = _step_timber(delta, is_working)
	if timber_target != null:
		target = timber_target
	# And the village's carter walks the store's round -- producer to store
	# and back, with the wagon behind them. The same override shape, and the
	# same place in the chain, as the mill and the field
	# (docs/concept/village_warehouse.md, Mechanism 4).
	var round_target = _step_cart(delta, is_working)
	if round_target != null:
		target = round_target
	var need_target = _step_needs(delta, not is_on_real_work())
	if need_target != null:
		target = need_target
	# Only the chase is run, and only while there is still a gap to close:
	# inside _reach() the hunt returns the villager's own position, so the
	# spear is never wound up at a sprint. Everything else -- the walk to a
	# field, a stall, the well or home, and every villager who is not a
	# hunter -- is the unhurried walk it always was.
	var running := _is_chasing_at_a_run(quarry_target)
	condition.advance(delta, economy.needs.hunger if economy != null else 0.0, running)
	var before := position
	# Two layers, and the order matters.
	#
	# ROUTE first: the slide below is a local reflex and cannot detour, so
	# a villager whose doorstep sits behind its own house has nowhere to
	# slide to and would press into the wall forever ("add proper
	# wayfinding / routing"). _steer_toward returns the next waypoint of a
	# real route when one is needed, or `target` itself when the way is
	# clear.
	#
	# SLIDE second, and it stays underneath rather than being replaced: a
	# route can go stale mid-walk (a house raised across it), and
	# _slid_along_walls is what guarantees a stale route still never ends
	# inside a wall. It also knows about farm rails, which the router does
	# not, and it asks the same question the wall's own collision body is
	# spawned from -- so a door and a floor stay walkable and going indoors
	# is untouched.
	var steer := _steer_toward(target, delta)
	position = _slid_along_walls(
		position, position.move_toward(steer, (RUN_SPEED if running else WALK_SPEED) * delta)
	)
	_update_animation(position - before)
	# Hidden once actually arrived home on a "home"-tagged entry -- a house
	# is now a real whole-building entity (docs/concept/building.md
	# "Buildings are entities; interiors are scenes"), so a villager
	# visibly idling/sleeping in plain view on their own doorstep every
	# night read as "sleeping outside the front door". Mirrors
	# EarthChunkManager's existing conversion-worker "hidden while working
	# inside a structure" pattern (CONVERSION_WORKER_BY_STRUCTURE /
	# _sync_conversion_worker), one rule per NPC instead of a table of
	# structures. Keyed on the tag, not merely "arrived somewhere", so
	# standing at a shared landmark (e.g. the stall) never hides an NPC.
	_at_home = (
		quarry_target == null
		and field_target == null
		and location_tag == "home"
		# A villager pouring a bucket into their own tank is standing at
		# their own door, and must not vanish indoors while doing it --
		# the errand would end invisibly and the whole point of carrying a
		# visible bucket would be lost on its last step.
		and not WaterErrand.is_running(water_errand)
		and position.distance_to(home_position) < _ARRIVED_HOME_EPSILON_PX
	)
	visible = not _at_home
	_sync_market_stand(is_working)
	if economy != null:
		economy.step(delta, is_working, _world, position, _on_real_quarry or _on_real_field)


## How long two villagers stand together once they have met. Long enough to
## read as a conversation from across the square rather than a collision,
## short enough that a village does not seize up in gossip -- and it is what
## the SOCIAL half of the day is made of, so it is pinned by
## test_a_conversation_really_ends rather than left as a comment.
const CONVERSATION_SECONDS := 4.0

## How far a villager will go looking for somebody to talk to. Company is the
## need a villager can always put off (it is last in the ethogram's own
## villager wirings), so this is deliberately a neighbourly distance and not
## a village-wide search: you stop for someone you were passing anyway.
const COMPANY_REACH_PX := 160.0


## One frame of the sawmill trade (docs/concept/village_timber.md). Returns
## where this villager should walk because of real timber work, or null when
## they have none and the ordinary schedule should decide.
##
## The third sibling of _step_hunt and _step_farm, on the same four seams
## (find -> position -> reach -> act) and built on the tile-scale
## Lumberjack's own phase machine: SEEKING -> APPROACHING -> FELLING ->
## CARRYING -> DEPOSIT. Nothing about felling is reinvented -- it is
## ChoppableTree.take_damage, staged the way the player's own axe stages it.
##
## Two jobs, not one, which is what a sawyer's day actually is: fetch logs
## to the mill, and work the mill. VillageSawmill.next_action picks between
## them from what the mill is holding.
func _step_timber(delta: float, is_working: bool):
	if not VillageSawmill.works_timber(identity.occupation) or sawmill_cell == NO_SAWMILL:
		return null
	if _world == null or not _world.has_method("deposit_to_structure_at"):
		return null
	if not is_working:
		# Off the clock the trunk is dropped rather than paused, exactly as
		# the field is -- a villager never wakes up still walking to a tree
		# they chose the evening before -- and the day's beams go in.
		_abandon_timber()
		haul_sawmill_stock_to_village()
		return null
	if _sawyer == null:
		_sawyer = LumberjackBehavior.new()
	_on_real_work_timber = true

	var mill := _cell_centre(sawmill_cell)
	# Working the mill only counts while standing AT it: a beam is squared
	# at the sawmill, not carried around half-finished.
	if (
		_sawyer.phase == LumberjackBehavior.Phase.SEEKING
		and VillageSawmill.next_action(_mill_stock("log")) == VillageSawmill.SHAPE
	):
		if position.distance_to(mill) > _field_reach():
			return mill
		_shape_a_beam(delta)
		return position

	match _sawyer.phase:
		LumberjackBehavior.Phase.SEEKING:
			_shaping_elapsed = 0.0
			_sawyer.advance(delta)
			var tree := _nearest_workable_tree(mill)
			if tree == null or not _sawyer.can_commit():
				return null
			_timber_target = tree
			_sawyer.begin_approach()
			return tree.position
		LumberjackBehavior.Phase.APPROACHING:
			if not _timber_still_there():
				return null
			if position.distance_to(_timber_target.position) <= _field_reach():
				_sawyer.arrive()
			return _timber_target.position
		LumberjackBehavior.Phase.FELLING:
			if not _timber_still_there():
				return null
			_swing_at_timber(delta)
			return position
		LumberjackBehavior.Phase.CARRYING:
			if position.distance_to(mill) <= _field_reach():
				_sawyer.arrive_home()
			return mill
		LumberjackBehavior.Phase.DEPOSIT:
			if _sawyer.advance_deposit(delta):
				_deposit_logs()
				_sawyer.finish_deposit()
			return position
	return null


## Drops whatever trunk this villager was working. Called when they go off
## the clock, and whenever the tree they committed to stops being there.
func _abandon_timber() -> void:
	if _sawyer != null and _sawyer.phase != LumberjackBehavior.Phase.SEEKING:
		_sawyer.abort()
	_timber_target = null
	_carried_logs = 0
	_shaping_elapsed = 0.0
	_on_real_work_timber = false


func _timber_still_there() -> bool:
	if _timber_target != null and is_instance_valid(_timber_target):
		return true
	_timber_target = null
	if _sawyer != null:
		_sawyer.abort()
	return false


## The nearest tree this MILL's sawyer may work -- a trunk already LYING in
## the mill's range first, then the nearest standing one. Range is measured
## from the mill, not from the villager, so a village fells its own wood
## rather than following a trail of trunks across the map.
##
## A woodcutter finishes what is already down before putting another one on
## the ground. This used to skip felled trees outright, so a trunk left
## lying -- by the player, by weather, or by this villager themselves when
## they went off the clock and dropped it (_abandon_timber) -- stayed there
## for ever while they walked past it to fell another. Reported live: "there
## are lying two felled trees around the sawmill and the worker doesn't
## bring them in".
func _nearest_workable_tree(mill: Vector2) -> Node2D:
	var lying := _nearest_timber(mill, true)
	return lying if lying != null else _nearest_timber(mill, false)


func _nearest_timber(mill: Vector2, felled: bool) -> Node2D:
	var best: Node2D = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group(ChoppableTree.GROUP_NAME):
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		if node.is_felled() != felled:
			continue
		if not VillageSawmill.is_in_range(mill, node.position, _tile_size):
			continue
		var distance: float = position.distance_to(node.position)
		if distance < best_distance:
			best = node
			best_distance = distance
	return best


## One swing, staged exactly as the player's own axe stages it: fell the
## trunk, take the canopy off, then buck CUTS_TO_CLEAR lengths off the bare
## trunk, each one a real log.
## Each stage is read off the TRUNK rather than off a local mirror of it.
## The mirror assumed every trunk this villager meets is one they felled
## themselves, which stopped being true the moment they started finishing
## trunks already lying there (see _nearest_workable_tree): a half-worked one
## would have been re-limbed and credited the wrong number of cuts.
func _swing_at_timber(delta: float) -> void:
	if not _sawyer.advance(delta):
		return  # the swing is not ready yet this tick
	if not _timber_target.is_felled():
		_timber_target.take_damage(FELL_DAMAGE)
		return
	if not _timber_target.canopy_removed():
		_timber_target.take_damage(FELL_DAMAGE)  # the canopy comes off, no log yet
		return
	# buck_for_worker, not take_damage: the drop through WorldItemBus is
	# right for a player's axe and wrong for a worker who also carries the
	# same cut home, which made every swing create the timber twice -- once
	# as a pile nobody collects and once in the mill's own stock.
	_carried_logs += _timber_target.buck_for_worker()
	if not _timber_still_there() or _timber_target.cuts_left() <= 0:
		_timber_target = null
		_sawyer.start_carry()


func _deposit_logs() -> void:
	if _carried_logs > 0:
		_world.deposit_to_structure_at(sawmill_cell.x, sawmill_cell.y, "log", _carried_logs)
	_carried_logs = 0


func _mill_stock(item_id: String) -> int:
	if not _world.has_method("structure_stock_at"):
		return 0
	return int(_world.structure_stock_at(sawmill_cell.x, sawmill_cell.y, item_id))


## Squaring a beam at the mill. SagewerkProduction's own shaping time and
## its own log cost -- slow, skilled, wasteful work, and never a second set
## of numbers. The logs are really taken out of the mill's stock and the
## beam really put back into it.
func _shape_a_beam(delta: float) -> void:
	_shaping_elapsed += delta
	if _shaping_elapsed < SagewerkProduction.SHAPE_SECONDS_PER_BEAM:
		return
	_shaping_elapsed = 0.0
	if not _world.has_method("withdraw_from_structure_at"):
		return
	if not _world.withdraw_from_structure_at(
		sawmill_cell.x, sawmill_cell.y, "log", VillageSawmill.LOGS_PER_BEAM
	):
		return
	_world.deposit_to_structure_at(sawmill_cell.x, sawmill_cell.y, "beam", 1)
	# Paid at the saw when the village has a store to cart it to
	# (docs/concept/village_warehouse.md, Mechanism 7) -- the beam stays on
	# the mill's shelf for the carter, so the village is credited when it
	# really arrives at the store rather than here. The same pay, for the
	# same work; what moved is where the beam is.
	if economy != null and _village_has_a_store():
		economy.record_harvest_wage("beam", 1)


## Carries the mill's finished BEAMS into the village's own stock -- the
## other half of the chain, and the same one the farmhouse already runs
## (haul_stock_to_village): cut in the wood, squared at the mill,
## carried to the village.
##
## Beams only. The logs a mill is holding are its own raw material, and
## carrying those off would be carrying away the very thing the sawmill
## exists to work.
##
## Only in a village with NO store. Where one stands, the beams stay on the
## mill's shelf for the carter and the sawyer is paid at the saw (see
## _shape_a_beam) -- Mechanism 7, the same split the farmhouse keeps.
##
## Credited through the same record_real_harvest a farmer's crop uses, so a
## beam is paid for exactly once, at the moment it actually arrives rather
## than at the saw. All-or-nothing per unit, mirroring
## withdraw_from_structure_at itself, and a no-op for a villager with no
## mill, an empty one, or a world that cannot answer.
func haul_sawmill_stock_to_village() -> void:
	if sawmill_cell == NO_SAWMILL or economy == null or _world == null:
		return
	# A village with a store leaves its shelves to the carter (docs/concept/
	# village_warehouse.md, Mechanism 7) -- the same rule the farmhouse
	# already follows, and the same bug on the other producer: reported with
	# the mill's own panel in shot reading "Stored: 0 / 60, Beam x0, Log x0",
	# *"The sawmill also doesn't produce beams or plangs or logs"*. It
	# produced them all along; the sawyer carried every one off the shelf at
	# the end of every work block, so the mill you clicked was always empty
	# and the carter arrived at a shelf somebody had already emptied.
	if _village_has_a_store():
		return
	if not _world.has_method("withdraw_from_structure_at"):
		return
	var carried := 0
	while _world.withdraw_from_structure_at(sawmill_cell.x, sawmill_cell.y, "beam", 1):
		carried += 1
	if carried > 0:
		economy.record_real_harvest("beam", carried)


var _on_real_work_timber := false


## Whether this villager is doing REAL work against the real world right## Whether this villager is doing REAL work against the real world right
## now -- working a field of their own, or on a real quarry.
##
## Reported in play: "No crops (wheat) grow and get harvested.. it plants
## then nothing happens it worked before". The needs layer used to read
## "busy" as "_step_farm returned somewhere to walk THIS FRAME", and
## _step_farm returns null between actions -- while seeking, and through the
## re-commit pause. In those frames a farmer read as idle, so thirst (which
## crosses its threshold roughly every sixteen seconds) walked them to the
## well; they planted a bed, left, and it withered before they came back.
##
## These two flags are the real answer, and they already existed for exactly
## this distinction: NpcEconomy reads the same pair to know whether to run
## the regional drip, precisely because "has a job on" is not the same
## question as "is walking somewhere".
func is_on_real_work() -> bool:
	return _on_real_quarry or _on_real_field or _on_real_work_timber or _on_real_round


## Whether this villager is mid-conversation right now -- standing still,
## facing whoever they are talking to. Read by the tests and by anything
## that wants to know why a villager is not walking.
func is_talking() -> bool:
	return _talk_remaining > 0.0


## Puts this villager into a conversation. Called on BOTH sides when two
## meet, because a conversation has two people in it: the one who walked
## over and the one who was stood there.
func begin_conversation(with_marker: Node, seconds: float = CONVERSATION_SECONDS) -> void:
	_talk_remaining = seconds
	_talking_to = with_marker
	if economy != null:
		economy.needs.satisfy(Ethogram.DRIVE_COMPANY)


var _talk_remaining := 0.0
var _talking_to: Node = null


## How near the well or their own door a villager has to get before that
## leg of the water errand counts as walked. Deliberately looser than
## NEED_REACH_PX's single pixel: a landmark is a place to stand around,
## not a point to hit, and a villager who can never quite reach it is a
## villager who never stops fetching water.
const ERRAND_REACH_PX := 6.0

## How far a villager may walk WITHOUT GETTING ANY NEARER to where the
## bucket is going, before they put it down.
##
## A villager can be stopped dead: routing plans around what it can see
## (TileRouter) and _slid_along_walls refuses the rest, but neither can
## promise a way through, so without a give-up rule a villager pressed
## against something walks at it for ever. Measured on the probe village
## (tools/probe_farm_water.gd): one of three field workers ended a 600s
## run still `to_well`, 104 px short of a well it had had 570 seconds to
## reach, having worked 156 of 6000 ticks against its own baseline of
## 2750. It never farmed again.
##
## Patience is measured in PROGRESS, not in time, and that distinction is
## not academic -- it is the second bug this constant has had. A time
## budget scaled from the straight-line distance looked equivalent and was
## not: merging real routing made villagers walk round buildings instead
## of into them, a route is longer than the line it replaces, and every
## well trip in the probe village stopped completing (farmer 1: 5 trips
## and 51 tendings became 0 and 8, its beds dry for 5110 of 6000 ticks)
## while the villagers walked perfectly well the whole time.
##
## So: far enough to round a building, because a detour genuinely takes
## you AWAY from the target for a while, and that is not being stuck.
const ERRAND_DETOUR_PX := 320.0
const ERRAND_PATIENCE_SECONDS := ERRAND_DETOUR_PX / WALK_SPEED

## What counts as getting nearer at all -- a quarter tile, so float noise
## on a villager standing still never reads as progress.
const ERRAND_PROGRESS_PX := 4.0

## How long they get on with their day before setting out again, once a leg
## has defeated them. Without it they turn round at the door and walk into
## the same wall immediately, which is the stall this replaces rather than
## fixes. One simulated day: they try again tomorrow.
const ERRAND_RETRY_SECONDS := SECONDS_PER_SIMULATED_DAY


## One frame of the trip to the well (docs/concept/village_water.md).
##
## Reads the household's own tank rather than any schedule: nobody is ever
## SENT to fetch water, they go when their own house runs dry, which is
## what staggers the village instead of emptying it into the square at once.
##
## A villager with no world, or none of their own house to find, simply
## never sets out -- an NPC in an unloaded chunk or a test fixture is not
## on an errand, it has nowhere to be on one.
func _step_water_errand(delta: float) -> void:
	_errand_retry_in = maxf(0.0, _errand_retry_in - delta)
	# No world to fetch from, or an errand whose target has somehow been
	# lost: put the bucket down rather than walk one leg further. Nothing
	# produces the second case today, but a villager stranded mid-square
	# holding a bucket forever is exactly the failure this errand exists
	# to replace.
	if _world == null or (WaterErrand.is_running(water_errand) and _errand_target.is_empty()):
		_put_the_bucket_down(0.0)
		return

	var was := water_errand
	if not WaterErrand.is_running(water_errand):
		if _errand_retry_in > 0.0:
			_errand_location_tag = ""
			return
		# Home and still short: set out (again, if one bucket was not
		# enough -- see WaterErrand's own note on why the loop lives here).
		_errand_target = _thirsty_building()
		water_errand = WaterErrand.begin_if_due(_tank_level_of(_errand_target))
		if not WaterErrand.is_running(water_errand):
			_errand_target = {}
	elif position.distance_to(_resolve_location(_errand_location_tag)) <= ERRAND_REACH_PX:
		water_errand = WaterErrand.arrived(water_errand)
		if water_errand == WaterErrand.AT_HOME:
			# They just finished pouring -- into whatever sent them.
			_world.pour_bucket_into_house(
				_errand_target["chunk_coord"], _errand_target["origin_local"]
			)
			_errand_target = {}
	else:
		# Still walking this leg. Getting nearer is all that is asked --
		# take as long as the way round needs (see
		# ERRAND_PATIENCE_SECONDS); make no headway at all and the bucket
		# goes down.
		var distance := position.distance_to(_resolve_location(_errand_location_tag))
		if distance < _errand_closest_px - ERRAND_PROGRESS_PX:
			_errand_closest_px = distance
			_errand_stalled_seconds = 0.0
		else:
			_errand_stalled_seconds += delta
			if _errand_stalled_seconds > ERRAND_PATIENCE_SECONDS:
				_put_the_bucket_down(ERRAND_RETRY_SECONDS)
		return

	if water_errand != was:
		_errand_closest_px = INF
		_errand_stalled_seconds = 0.0
	_errand_location_tag = WaterErrand.location_tag_for(water_errand)


## Off the errand, empty-handed, and not setting out again for `retry_in`
## seconds. The bucket goes back by the door; nothing is spilled and
## nothing is poured, because they never filled it.
func _put_the_bucket_down(retry_in: float) -> void:
	water_errand = WaterErrand.AT_HOME
	_errand_target = {}
	_errand_location_tag = ""
	_errand_closest_px = INF
	_errand_stalled_seconds = 0.0
	_errand_retry_in = maxf(_errand_retry_in, retry_in)


## The building this villager must fetch water for right now, or {} when
## neither of theirs is short.
##
## Their own house FIRST, always: people before plants, the same order the
## farmhouse's own drinking reserve keeps (HouseholdWater.spare_for_crops).
## Then the farmhouse they work, whose field drinks out of its own tank and
## whose beds stop being watered when it runs down.
func _thirsty_building() -> Dictionary:
	if _world == null:
		return {}
	var house := _house_of_their_own()
	if not house.is_empty() and _world.water_trip_due_at(house):
		return house
	# The whole errand or none of it: a world that can say a tank is low
	# but cannot be poured into would strand somebody at the farmhouse
	# door holding a full bucket forever. (_house_of_their_own already
	# answers {} for such a world, which is why this only guards here.)
	if not _world.has_method("water_trip_due_at") or not _world.has_method("pour_bucket_into_house"):
		return {}
	var farmhouse := _farmhouse_of_their_own()
	if not farmhouse.is_empty() and _world.water_trip_due_at(farmhouse):
		return farmhouse
	return {}


## This villager's own house, as a building record -- {} when the world
## cannot say. Found at their own doorstep, which is where home_position
## already points.
func _house_of_their_own() -> Dictionary:
	if _world == null or not _world.has_method("building_door_near"):
		return {}
	if not _world.has_method("water_trip_due_at") or not _world.has_method("pour_bucket_into_house"):
		return {}
	return _world.building_door_near(home_position, 1.0)


## The FARMHOUSE this villager works, as a building record -- {} for
## everyone else. Checked by id rather than assumed from
## stock_building_cell alone, because that field holds a FISHER's own
## cottage too (see its own note), and a cottage has no field to water.
func _farmhouse_of_their_own() -> Dictionary:
	if stock_building_cell == NO_STOCK_BUILDING or _world == null:
		return {}
	if not _world.has_method("building_at_global"):
		return {}
	var record: Dictionary = _world.building_at_global(
		stock_building_cell.x, stock_building_cell.y
	)
	if String(record.get("id", "")) != VillageFarm.FARM_BUILDING_ID:
		return {}
	return record


## The one cell the farmhouse is reached from -- the same doorstep rule
## building_door_near keeps, rather than its anchor, which is a cell the
## building itself stands on. A villager who walked to the anchor would
## pour the bucket standing inside the farmhouse's own art.
func _farmhouse_doorstep() -> Vector2i:
	return stock_building_cell + BuildingCatalog.doorstep_of(VillageFarm.FARM_BUILDING_ID)


## Whether the bucket in this villager's hand is for the field rather than
## for their own kitchen -- which is what makes the walk home a walk to the
## farmhouse (see _resolve_location).
func _errand_is_for_the_farmhouse() -> bool:
	return (
		WaterErrand.is_running(water_errand)
		and stock_building_cell != NO_STOCK_BUILDING
		and String(_errand_target.get("id", "")) == VillageFarm.FARM_BUILDING_ID
	)


## Whether this building's tank says somebody must go. Asked of the world
## rather than computed here, so the marker and the building can never
## disagree about what "low" means -- and a farmhouse is sent sooner than a
## household is, which is the world's rule to keep, not the marker's.
## Nothing to fetch for reads as a full tank.
func _tank_level_of(building: Dictionary) -> float:
	if building.is_empty():
		return HouseholdWater.TANK_LITRES
	return 0.0 if _world.water_trip_due_at(building) else HouseholdWater.TANK_LITRES


## One generator for the whole village. Its texture cache is static and
## keyed by id, so twelve villagers on twelve errands share two bucket
## textures between them rather than rebuilding a 32x32 image each.
static var _item_art := ProceduralItemSprite.new()

## What the CharacterView is currently showing in their hand, so a frame
## that changed nothing touches nothing.
var _shown_carried := ""


## Puts what they are carrying into the view's tool slot -- or takes it
## out of their hand again.
##
## This is the whole of docs/concept/village_water.md pillar 2: what a
## villager is doing has to be answerable by LOOKING at them. carried_item
## has always SAID what is in their hand; without this it went nowhere and
## the errand ran invisibly, which is the half of the report that reads
## *"it's not visible what they are doing"*.
##
## A view that is not in the tree yet is left alone WITHOUT recording what
## it would have been shown, so the next frame tries again --
## CharacterView.equip_weapon writes straight to its slot node and has no
## pending-value stash (see CharacterPreviewDiorama's own note).
func _sync_carried_item() -> void:
	var carried := carried_item()
	if carried == _shown_carried:
		return
	if _character_view == null or not _character_view.is_node_ready():
		return
	_shown_carried = carried
	if carried == "":
		_character_view.unequip_slot("tool")
		return
	_character_view.equip_weapon(_item_art.texture_for(carried))


## What is in this villager's hands right now: "" for nothing, otherwise
## WaterErrand.BUCKET_EMPTY or BUCKET_FULL. The renderer's whole input for
## making the errand legible.
func carried_item() -> String:
	return WaterErrand.carried(water_errand)


## Where this villager is headed right now, errand included -- what a
## readout or a test should ask rather than reaching into the schedule.
func current_location_tag() -> String:
	if WaterErrand.is_running(water_errand):
		return _errand_location_tag
	return String(_last_location_tag)


## How near a villager has to get before a need counts as answered -- the
## same "arrived" grain the home check below already uses.
const NEED_REACH_PX := _ARRIVED_HOME_EPSILON_PX


## One frame of catering to this villager's own needs. Returns where they
## should walk because of a real need, or null when nothing is pressing and
## the ordinary schedule should decide.
##
## The visible half of docs/concept/npc_social_life.md: thirst walks them to
## the well and drinking really answers it, tiredness walks them home and
## resting really answers it. A need that is answered the moment they arrive
## is what stops a villager standing at the well forever.
##
## `free_to_answer` is false while a hunter is mid-chase or a farmer is in
## their own field: real work against the real world outranks a need.
func _step_needs(delta: float, free_to_answer: bool):
	if _talk_remaining > 0.0:
		# Mid-conversation: stand where you are and face them. Returning our
		# OWN position is how every other override here says "stay put".
		#
		# Checked BEFORE free_to_answer on purpose: a villager does not walk
		# off mid-sentence because quarry wandered past. At CONVERSATION_
		# SECONDS the most that costs a hunter is four seconds of a chase.
		_talk_remaining -= delta
		if _talking_to != null and is_instance_valid(_talking_to):
			face_movement(_talking_to.position - position)
		return position
	if economy == null or not free_to_answer:
		return null
	# Built once and kept: the decision names an intent and a place, and the
	# context is what knows WHO is standing there -- a conversation needs the
	# villager, not the coordinate.
	var context := _villager_context()
	var decision := _behavior.decide(context)
	var at = decision["target"]
	if at == null:
		return null
	if position.distance_to(at) <= _reach_for(String(decision["intent"])):
		_answer_need(String(decision["intent"]), context.get("who"))
		return position if _talk_remaining > 0.0 else null
	return at


## How near counts as arrived, per intent.
##
## A PLACE is reached to the pixel (NEED_REACH_PX): a villager stands on
## their own doorstep. A PERSON never is -- two villagers cannot occupy the
## same pixel, they stand a body apart -- so talking reaches a tile, which is
## what "close enough to speak to" means on this grid. Found by a test that
## put two villagers two pixels apart and watched them fail to notice each
## other.
func _reach_for(intent: String) -> float:
	return float(_tile_size) if intent == VillagerBehavior.SOCIALIZE else NEED_REACH_PX


## Reaching the place a need sent you to is what answers it.
func _answer_need(intent: String, who) -> void:
	if intent == VillagerBehavior.DRINK:
		economy.needs.satisfy(Ethogram.DRIVE_THIRST)
	elif intent == VillagerBehavior.REST:
		economy.needs.satisfy(Ethogram.DRIVE_REST)
	elif intent == VillagerBehavior.HAUL:
		# Reaching the door is what puts the load down, the same way reaching
		# the well is what answers the thirst. This is the moment a village's
		# stock actually arrives somewhere (village_warehouse.md mechanism 3);
		# until now it had no location at all.
		economy.deliver_load()
	elif intent == VillagerBehavior.SOCIALIZE and who != null and is_instance_valid(who):
		# Both sides, because a conversation has two people in it -- the one
		# who walked over and the one who was stood there. Without this the
		# other villager keeps walking and it reads as being talked AT.
		begin_conversation(who)
		who.begin_conversation(self)


## What this villager needs and what they can see that answers it.
##
## Hunger's own gain is deliberately withheld: it keeps the dedicated
## interrupt in _process, whose guards a famine chain was measured into.
## Publishing it here too would have both layers steering at once.
func _villager_context() -> Dictionary:
	var drives: Dictionary = economy.needs.gains().duplicate()
	drives[Ethogram.DRIVE_HUNGER] = 0.0
	# What this villager is CARRYING, which is not on any clock and so is
	# absent from gains() by construction. It has to be published explicitly:
	# BehaviorKernel reads an unmentioned gate as wide open, and though
	# VillagerBehavior now closes that door on its own side, a marker that
	# stayed silent would still be telling a villager nothing about their own
	# hands.
	drives[Ethogram.DRIVE_BURDEN] = economy.burden()
	var context := {"position": position, "drives": drives, "home": home_position}
	if landmarks.has("well"):
		context[Ethogram.WATER] = landmarks["well"]
	if warehouse_position != null:
		context[Ethogram.WAREHOUSE] = warehouse_position
	# Somebody to talk to, asked of the world the same duck-typed way every
	# other world hook here is. One nearest neighbour rather than a list:
	# you stop for the person you were passing, not for the best of everyone
	# in the village.
	var neighbour = _nearest_neighbour()
	if neighbour != null:
		context[Ethogram.COMPANY] = [neighbour.position]
		context["who"] = neighbour
	return context


func _nearest_neighbour():
	if _world == null or not _world.has_method("nearest_npc_near"):
		return null
	return _world.nearest_npc_near(position, COMPANY_REACH_PX, self)


var _behavior := VillagerBehavior.new()


## Whether this villager is inside their own house right now -- the exact
## "arrived home on a home-tagged entry" state the hide rule above reads,
## exposed so the world can put them in their room when the player walks in
## (docs/concept/building.md "Residents inside") and so the doorstep scans
## (EarthChunkManager.nearest_npc_near) skip someone who is actually
## indoors rather than offering "Talk" through the wall.
func is_at_home() -> bool:
	return _at_home


var _at_home := false


## Drives the bound CharacterView's walk cycle from the actual movement this
## frame -- previously nothing called set_facing/is_moving/set_movement_state
## after the marker moved, so every villager's walk animation sat frozen in
## IDLE despite visibly walking (reported: "NPCs don't have walk or swim
## animation").
## `to`, with any part of the step that walks into a real wall taken out of
## it -- and nothing else changed.
##
## Reported live: "houses should also block NPCs and animals". An NpcMarker
## is a Sprite2D that moves by one position.move_toward per frame, so the
## StaticBody2D on a wall (EarthChunkManager._spawn_piece_collision) has
## never had the slightest effect on one and villagers walked through their
## own houses.
##
## It SLIDES rather than stopping dead, which is both what the same
## collision does to the player (move_and_slide) and what this marker
## actually needs: there is no pathfinding here, only a straight line at
## the target, so a villager who stopped the instant they touched a wall
## would stand against it for good -- and their own front door is reached
## by walking AT the house. Blocked head-on, they keep whichever single
## axis of the step is open, which carries them along the wall to the door.
## Boxed in on both, they stay put, exactly as _step's own "nowhere to go"
## already means stand still.
##
## Asks the world the same question the wall's own collision body is
## spawned from, so what stops a player and what stops a villager can never
## disagree. A DOOR and a FLOOR are walkable pieces, so going indoors is
## untouched.
##
## GROUND TOO STEEP TO CLIMB is refused here too. The router plans around a
## cliff, but a route is only a plan: when none exists (the goal is behind
## the cliff, or the budget ran out) the villager falls back to walking
## straight at its target, and without this check that fallback walked up
## the cliff. Caught by test_a_villager_never_climbs_a_cliff during the
## reconciliation with main -- the slide is the ONE place every step
## passes through, so terrain belongs in it rather than in a second gate
## beside it.
func _slid_along_walls(from: Vector2, to: Vector2) -> Vector2:
	if _world == null or from == to:
		return to
	if (
		not _world.has_method("piece_blocks_movement_at_global")
		and not _world.has_method("fence_blocks_step_global")
		and not _world.has_method("slope_at_global")
	):
		return to
	if not _blocked_step(from, to):
		return to
	var along_x := Vector2(to.x, from.y)
	if not is_equal_approx(to.x, from.x) and not _blocked_step(from, along_x):
		return along_x
	var along_y := Vector2(from.x, to.y)
	if not is_equal_approx(to.y, from.y) and not _blocked_step(from, along_y):
		return along_y
	return from


## Whether stepping from `from` to `point` is refused -- by a wall standing
## ON the destination, or by a farm rail standing on the LINE between the
## two (docs/concept/village_farms.md, "The rail stands on the inner
## edge"). The two are different questions on purpose: a wall is a tile you
## cannot be in, a rail is an edge you cannot cross, and the ring round a
## field stays ordinary ground a villager may walk along.
func _blocked_step(from: Vector2, point: Vector2) -> bool:
	var tile := Vector2i(floori(point.x / _tile_size), floori(point.y / _tile_size))
	if _world.has_method("slope_at_global") and not TerrainPassability.is_passable(
		_world.slope_at_global(tile.x, tile.y)
	):
		return true
	if (
		_world.has_method("piece_blocks_movement_at_global")
		and _world.piece_blocks_movement_at_global(tile.x, tile.y)
	):
		return true
	if not _world.has_method("fence_blocks_step_global"):
		return false
	# A field's rails stand on its INNER edge (see "The rail stands on the
	# inner edge"), so the one villager they shut out is the farmer whose
	# beds they enclose. Reported live: "The farmer doesn't farm anymore" --
	# measured on a real village, two of three villagers with a field worked
	# no bed at all, frozen in APPROACHING nine pixels from their own soil,
	# refused the last step into it.
	#
	# A gate exists for this (docs/concept/village_farms.md, "The gate"),
	# but reaching one needs pathfinding a Sprite2D walking a single
	# move_toward per frame does not have -- the commit that gave rails
	# their hitbox said so itself: "boxed in on both, they stay put".
	#
	# So the worker may cross into ground they themselves work, and nothing
	# else changes: every other rail still stops them, a neighbour's
	# included, and no other villager is exempt from any rail.
	if field_cells.has(tile):
		return false
	var here := Vector2i(floori(from.x / _tile_size), floori(from.y / _tile_size))
	return _world.fence_blocks_step_global(here.x, here.y, tile.x, tile.y)


func _update_animation(moved: Vector2) -> void:
	if _character_view == null:
		return
	var is_moving := moved.length() > 0.01
	if is_moving:
		face_movement(moved)
	_character_view.is_moving = is_moving
	if _is_in_water():
		_character_view.set_movement_state(CharacterView.MovementState.SWIMMING)
	elif is_moving:
		_character_view.set_movement_state(CharacterView.MovementState.WALKING)
	else:
		_character_view.set_movement_state(CharacterView.MovementState.IDLE)


## Fails open (never swimming) without a world -- same shape as
## CreatureMarker's water checks, which all guard on _world != null.
func _is_in_water() -> bool:
	if _world == null:
		return false
	var tile := Vector2i(floori(position.x / _tile_size), floori(position.y / _tile_size))
	return _perception.is_on(_world, tile, "water")


func _current_hour() -> int:
	return int(_hour_of_day())


## The world's own hour of the day, as a real number -- the clock a villager
## then shifts a little of their own (NpcSchedule.personal_hour). A float
## because a whole-hour clock can only ever turn a village's day in one
## tick, which is the lockstep this exists to break.
func _hour_of_day() -> float:
	return fmod(_elapsed_time / SECONDS_PER_SIMULATED_DAY, 1.0) * 24.0


## Builds the flat context Dictionary NpcInstructionEvaluator's condition
## primitives read (docs/concept/npc_instructions.md, "Execution / wiring":
## "context is a flat Dictionary ... nothing that isn't already live
## state") -- this NPC's own hunger need (the one live need signal NpcMarker
## already carries via `economy`) and its real `inventory` Dictionary, now
## that src/world/npc_inventory.gd exists to back it. An NPC that holds
## nothing genuinely reports an empty inventory here -- the primitives' own
## fail-open/empty-is-not-an-error convention (see
## npc_instruction_primitives.gd) still applies, it's just backed by real
## state now instead of always being stubbed.
func _instruction_frame() -> Dictionary:
	var needs := {}
	if economy != null:
		needs["hunger"] = economy.needs.hunger
	return {"inventory": inventory, "needs": needs}


## Adapts an instruction action descriptor (NpcInstructionPrimitives' own
## {"fn": "haul"/"gather", ...} shape) into the same {location_tag, activity}
## shape an ordinary schedule entry already has, reusing _resolve_location's
## existing tag lookup (home/landmark/workspot fallback) rather than a new
## spatial-query layer -- the real nearest-X spatial query
## npc_instruction_effects.gd will eventually use is a later step (docs/
## concept/npc_instructions.md, "Execution / wiring"). Both v1 actions read
## as "work" for the economy step underneath, same as any other work entry.
func _entry_for_instructed_action(action: Dictionary) -> Dictionary:
	match action.get("fn", ""):
		"haul":
			return {"location_tag": action.get("destination_tag", "home"), "activity": "work"}
		"gather":
			return {"location_tag": action.get("resource_tag", "home"), "activity": "work"}
	return {"location_tag": "home", "activity": "idle"}


## "home" is this NPC's own house; a shared landmark tag (well/stall/gate)
## resolves to the settlement's landmark; anything else (a work tag with no
## dedicated building yet, e.g. "field"/"forge") falls back to this NPC's
## personal workspot rather than an unresolved position.
## The market stand this villager sells from, or null for a villager who
## keeps none (see VillageRenderer, docs/concept/village_market_square.md).
##
## Owned by the renderer, driven from here: a stand is up only while its
## trader is behind it, and this marker is the only thing that knows where
## its trader is standing this frame.
##
## Taken in the moment it is handed over, rather than left at Node2D's own
## default of visible: a village that loads at night would otherwise flash
## its whole market up for the one frame before the first _process, and a
## stand nobody has reached yet is not up. Same setter-does-the-wiring shape
## as warehouse_position above.
var market_stand: Node2D = null:
	set(value):
		market_stand = value
		if market_stand != null and is_instance_valid(market_stand):
			market_stand.visible = false

## How close counts as being behind your own stand: one tile. A trader
## standing on the square beside their own trestle is selling from it.
## Derived from the world's own tile size rather than chosen, so a stand's
## reach cannot drift away from the grid it stands on (pinned by
## test_a_traders_reach_over_their_own_stand_is_one_tile).
const STAND_REACH_TILES := 1


func market_stand_reach() -> float:
	return float(_tile_size * STAND_REACH_TILES)


## Whether a market stand is UP: its trader is on the clock AND within reach
## of it.
##
## Reported live with an unattended stand in shot: "the market stands should
## only be put up when an NPC stands behind them to sell goods". A trestle
## and a board are not architecture -- a real stand is carried out in the
## morning, stood up for as long as somebody is behind it, and taken in
## again. Both halves are needed: a merchant passing their own stand on the
## way home at night is not selling from it.
static func stand_is_up(is_working: bool, distance_to_stand: float, reach: float) -> bool:
	return is_working and distance_to_stand <= reach


## Puts this villager's own stand up or takes it in, from where they are
## standing this frame. A villager who keeps no stand is left alone, the
## same fail-open shape every other world hook here uses.
func _sync_market_stand(is_working: bool) -> void:
	if market_stand == null or not is_instance_valid(market_stand):
		return
	market_stand.visible = stand_is_up(
		is_working, position.distance_to(market_stand.position), market_stand_reach()
	)


## Where to actually aim this frame: the next waypoint of a real route
## when one is needed, or `target` itself when the way is clear, no route
## was found, or this villager has no world to ask.
##
## Falling back to `target` on a failed search is deliberate. A route that
## cannot be found (goal unreachable, or budget spent) must not stop a
## villager walking -- it only means they walk the old, direct way, with
## the gate keeping them out of walls exactly as before.
func _steer_toward(target: Vector2, delta: float) -> Vector2:
	_route_age += delta
	if not _wall_tiles.is_valid() or _tile_size <= 0:
		return target
	var here := _tile_of(position)
	var goal := _tile_of(target)
	if here == goal:
		return target  # final approach, inside the destination tile
	if goal != _route_goal_tile and _route_age >= ROUTE_RECOMPUTE_SECONDS:
		_route_goal_tile = goal
		_route_age = 0.0
		_route = TileRouter.route(here, goal, _wall_tiles, ROUTE_NODE_BUDGET, _route_cost)
	# Drop whatever has already been walked. A villager can cross more than
	# one waypoint in a frame at RUN_SPEED, so this is a loop, not an if.
	while not _route.is_empty() and _tile_of(position) == _route[0]:
		_route.remove_at(0)
	if _route.is_empty():
		return target
	return _tile_centre(_route[0])


func _tile_of(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / _tile_size), floori(point.y / _tile_size))


func _tile_centre(tile: Vector2i) -> Vector2:
	return Vector2(
		tile.x * _tile_size + _tile_size * 0.5, tile.y * _tile_size + _tile_size * 0.5
	)


func _resolve_location(tag: String) -> Vector2:
	if tag == "home":
		# Mid-errand, "home" is wherever the bucket is GOING. A farmer
		# carrying water for their own field walks it to the FARMHOUSE
		# (docs/concept/village_water.md mechanism 3) -- resolving to their
		# own doorstep would have them pour the field's water into their
		# kitchen and the beds would never get any.
		if _errand_is_for_the_farmhouse():
			return _cell_centre(_farmhouse_doorstep())
		return home_position
	if landmarks.has(tag):
		return landmarks[tag]
	return workspot_position


## The CharacterView rendering this villager (see VillageRenderer._build_npc).
## The marker itself is a Sprite2D for historical reasons but no longer draws
## its own texture -- the view owns the visuals, so body proportions and the
## walk animation are shared with the player rather than duplicated.
var _character_view: Node2D


func bind_character_view(view: Node2D) -> void:
	_character_view = view


## Points the villager the way it is walking, so NPCs face their direction
## of travel like the player does.
func face_movement(direction: Vector2) -> void:
	if _character_view != null:
		_character_view.set_facing(direction)


## One frame of the hunt. Returns where this villager should walk right now
## because of real quarry, or null when there is none and the ordinary
## schedule should decide -- which is also what the economy reads to know
## whether to run its regional drip (see NpcEconomy.step's on_real_quarry).
##
## Mirrors LumberjackMarker's own _step_seeking/_step_approaching/
## _step_felling trio, compressed into one function because neither hunt
## has a carry or a deposit: the catch goes straight into the village
## market the moment it is taken, and adding a haul for symmetry would mean
## inventing a building to haul it to.
##
## One skeleton for both quarry kinds, with the four things that genuinely
## differ behind _find_quarry / _quarry_position / _reach / _take_quarry: a
## deer and a trout are approached, lost and given up on in exactly the
## same way, and writing that twice is how the two drift apart.
func _step_hunt(delta: float, is_working: bool):
	if _forager == null:
		return null
	if not is_working:
		# Working real quarry is work. Off the clock -- asleep, eating,
		# socialising, or following a standing instruction -- it is dropped
		# rather than paused, so a villager never wakes up still locked
		# onto an animal that wandered off hours ago.
		if _forager.phase != ForagerBehavior.Phase.SEEKING:
			_forager.abort()
		_quarry = null
		_scanned_quarry = null
		_quarry_scan_elapsed = QUARRY_SCAN_INTERVAL
		_on_real_quarry = false
		return null
	match _forager.phase:
		ForagerBehavior.Phase.SEEKING:
			# advance() is a no-op outside TAKING; this is just the
			# look-around clock ticking, same as the Lumberjack's own.
			_forager.advance(delta)
			# Asked every working frame, not only once the look-around
			# interval is up: the answer decides whether the regional
			# fallback applies at all (see _on_real_quarry), which is a
			# question about the region, not about this villager's own
			# readiness to walk. The underlying scan is throttled and
			# cached (see _quarry_in_reach), so asking costs nothing most
			# frames.
			var found = _quarry_in_reach(delta)
			_on_real_quarry = found != null
			if found == null or not _forager.can_commit():
				return null
			_quarry = found
			_scanned_quarry = null
			_forager.begin_approach()
			return _quarry.position
		ForagerBehavior.Phase.APPROACHING:
			var approach_position = _quarry_position()
			if approach_position == null:
				return _give_up_on_quarry()
			_on_real_quarry = true
			if position.distance_to(approach_position) <= _reach():
				_forager.arrive()
			return approach_position
		ForagerBehavior.Phase.TAKING:
			var quarry_position = _quarry_position()
			if quarry_position == null:
				return _give_up_on_quarry()
			_on_real_quarry = true
			# Quarry can break away mid-hunt -- a spooked deer runs, a
			# shoal drifts downstream. Close the gap again rather than
			# striking from across the meadow, and let the strike clock
			# wait with it: nobody winds up a spear at a full run.
			if position.distance_to(quarry_position) > _reach():
				return quarry_position
			if _forager.advance(delta):
				_take_quarry()
			# Standing still, not walking the last few pixels onto the
			# quarry: a hunter plants their feet to strike, and a fisher
			# who closed the last of a rod's reach would be standing in
			# the river.
			return position
	return null


## Whether this frame is spent running down real quarry.
##
## A property of the BEHAVIOUR rather than of a job title: it asks for a
## CREATURE quarry being closed on, which by QUARRY_KIND_BY_OCCUPATION makes
## the hunter the only villager it can ever be true for. A fisher's quarry is
## a fish -- nobody sprints at a trout, and a rod already reaches
## CAST_DISTANCE_PX without closing the gap at all.
##
## False once inside _reach(): the strike is made standing (see _step_hunt's
## own "nobody winds up a spear at a full run"), so those last few pixels
## cost no wind. False with no wind left, which is what drops a blown hunter
## back to a walk mid-chase -- they keep following, they just stop gaining.
func _is_chasing_at_a_run(quarry_target) -> bool:
	if _quarry_kind != "creature" or quarry_target == null:
		return false
	if position.distance_to(quarry_target) <= _reach():
		return false
	return condition.can_run()


## Whether this villager has real ground of their own to work -- a farming
## occupation AND a farmhouse whose field they were actually given.
func _works_their_own_field() -> bool:
	return _farmer != null and _field_crop != "" and not field_cells.is_empty()


## The tile of this villager's own field they should be at right now, or
## null when they have no field, are off the clock, or have nothing to do
## on it this instant.
##
## Deliberately the same shape as _step_hunt above and the placeable Farm's
## own worker below it, but the differences are real and are why this is
## not folded into either: a field tile cannot flee, be killed by a wolf,
## or be taken by somebody else mid-walk, so there is no "the target is
## gone" branch at all -- the ground is still there. What DOES change under
## the villager is what the ground NEEDS, which is re-read on arrival
## rather than remembered from when they set out.
##
## Every world call is duck-typed and fails closed: a world that cannot
## answer simply has no field in it, and the villager keeps the schedule
## and the regional drip they always had.
func _step_farm(delta: float, is_working: bool):
	if _farmer == null or _field_crop == "" or field_cells.is_empty() or _world == null:
		return null
	if not is_working:
		# Off the clock -- asleep, eating, socialising -- the field is
		# dropped rather than paused, so a villager never wakes up still
		# walking to a bed they chose the evening before.
		if _farmer.phase != FarmerBehavior.Phase.SEEKING:
			_farmer.abort()
		_field_index = -1
		_on_real_field = false
		# ...and what the farmhouse is holding goes to the village. The end
		# of the work block is the moment a day's cut crop is carried in,
		# and it is the one point reached every day whatever the crop cycle
		# is doing -- a field with beds in it always has SOMETHING worth a
		# visit (VillageFarm.next_action's thirstiest-bed fallback), so
		# "nothing left to do" never reliably arrives.
		#
		# ONCE, though. See _carried_in_since_work.
		_carry_the_store_in()
		return null
	# A villager with a farmhouse has real work whether or not any single
	# plot wants attention this instant, so the regional drip is off for
	# the whole work block rather than flickering with the crop cycle.
	_on_real_field = true
	_carried_in_since_work = false
	match _farmer.phase:
		FarmerBehavior.Phase.SEEKING:
			_farmer.advance(delta)  # a no-op outside WORKING; ticks the re-commit clock
			var index := VillageFarm.next_action(_field_states())
			if index == -1 or not _farmer.can_commit():
				return null
			_field_index = index
			_farmer.begin_approach()
			return _cell_centre(field_cells[index])
		FarmerBehavior.Phase.APPROACHING:
			var approach := _cell_centre(field_cells[_field_index])
			if position.distance_to(approach) <= _field_reach():
				_farmer.arrive()
			return approach
		FarmerBehavior.Phase.WORKING:
			if _farmer.advance(delta):
				_work_field_cell()
				_field_index = -1
				_farmer.finish_work()
			# Standing over the bed, not walking the last pixels onto its
			# exact centre: you kneel where you are.
			return position
	return null


## Whatever the committed tile needs RIGHT NOW -- re-read rather than
## remembered, since a crop can ripen or wither during the walk out to it.
func _work_field_cell() -> void:
	if _field_index < 0 or _field_index >= field_cells.size():
		return
	var cell: Vector2i = field_cells[_field_index]
	# What the beds get is paid for out of the farmhouse's own tank
	# (docs/concept/village_water.md mechanism 3). A farmhouse down to its
	# household's drinking reserve cannot water at all -- and that refusal
	# is the mechanism, not a failure case: it is what makes somebody walk
	# to the well for the FIELD, which is the errand this whole feature
	# exists to make visible.
	var paid_for := _draw_crop_water()
	match VillageFarm.action_for(_field_plot_at(cell)):
		"harvest":
			if not _world.has_method("harvest_farm_plot_at_global"):
				return
			var result: Dictionary = _world.harvest_farm_plot_at_global(cell.x, cell.y)
			var count: int = int(result.get("count", 0))
			var crop_id: String = String(result.get("crop_id", _field_crop))
			if count > 0:
				_store_harvest(crop_id, count)
		"plant":
			if _world.has_method("till_and_plant_farm_plot_at_global"):
				_world.till_and_plant_farm_plot_at_global(cell.x, cell.y, _field_crop)
		"water":
			if paid_for and _world.has_method("water_farm_plot_at_global"):
				_world.water_farm_plot_at_global(cell.x, cell.y)
	if paid_for:
		_water_the_beds_around(cell)


## Takes this visit's water out of the farmhouse this villager works for.
## True when the beds may be wetted.
##
## Fails OPEN for a villager with no farmhouse of their own -- a village
## that has not raised one -- and for a world that cannot answer at all.
## There is no tank to bill it to in either case, and failing closed would
## kill every such field rather than send anybody anywhere.
func _draw_crop_water() -> bool:
	if _farmhouse_of_their_own().is_empty():
		return true
	if not _world.has_method("draw_crop_water_at_global"):
		return true
	return _world.draw_crop_water_at_global(stock_building_cell.x, stock_building_cell.y)


## Where a cut crop goes: into the FARMHOUSE this villager works for, which
## is what the village later carries to market (see
## haul_stock_to_village).
##
## A farmer with no farmhouse -- a village that has not raised one, or one
## there was no room for -- keeps the behaviour they always had and sells it
## where they stand. A harvest that had nowhere to go would otherwise simply
## vanish, which is worse than the missing link this closes.
func _store_harvest(crop_id: String, count: int) -> void:
	if (
		stock_building_cell != NO_STOCK_BUILDING
		and _world != null
		and _world.has_method("deposit_to_structure_at")
	):
		_world.deposit_to_structure_at(stock_building_cell.x, stock_building_cell.y, crop_id, count)
		# Paid at the scythe when the village has a store to cart it to
		# (docs/concept/village_warehouse.md, Mechanism 7): the crop stays
		# on this shelf for the carter, so the village is credited when the
		# goods really arrive there rather than here. The same pay, at the
		# same moment, either way -- what moved is where the goods are.
		if economy != null and _village_has_a_store():
			economy.record_harvest_wage(crop_id, count)
		return
	if economy != null:
		economy.record_real_harvest(crop_id, count)


## Whether this villager's village really has a store to cart goods to.
##
## VillageRenderer hands every villager the door of the store that really
## STANDS in their chunk (null for a site too cramped to raise one, pillar
## 1's caveat), so a villager can tell which world they are in without
## asking anybody.
func _village_has_a_store() -> bool:
	return warehouse_position != null


## How long a fisher works one cast before it lands a fish. Not a fresh
## number: it is FarmerBehavior.WORK_SECONDS, the time this codebase already
## measured for "a villager kneels over a thing and does a piece of work",
## reused so a cast and a planting cost a villager the same effort. Pinned
## against it by test_a_cast_costs_what_a_piece_of_field_work_costs.
const CAST_SECONDS := FarmerBehavior.WORK_SECONDS

## Seconds into the current cast.
var _cast_elapsed := 0.0


## A fisher's own pond work, or null for everyone else -- the same shape
## _step_farm has, and the same override it gets in the work tick.
##
## Off the clock the cast is dropped rather than paused (a villager never
## wakes up mid-cast), and what their house is holding goes to the village:
## the same end-of-block carry a farmer's harvest gets, through the same
## function.
func _step_pond(delta: float, is_working: bool):
	if pond_cells.is_empty():
		return null
	if not is_working:
		_cast_elapsed = 0.0
		_carry_the_store_in()  # once, at the end of the block
		return null
	_cast_elapsed += delta
	_carried_in_since_work = false
	if _cast_elapsed >= CAST_SECONDS:
		_cast_elapsed = 0.0
		_work_pond()
	return _cell_centre(pond_cells[0])


## Carries what this villager's own store is holding into the village --
## once per work block, at its end (see _carried_in_since_work).
func _carry_the_store_in() -> void:
	if _carried_in_since_work:
		return
	_carried_in_since_work = true
	haul_stock_to_village()


## The GLOBAL tiles of this villager's own pond, or empty for everyone who
## does not have one (docs/concept/village_ponds.md). Handed out by
## VillageRenderer beside stock_building_cell, the same way a farmer's
## field_cells is.
var pond_cells: Array[Vector2i] = []

## What a pond yields. The catalog's own fish, and the same id
## NpcProduction.PRODUCER_ITEM_BY_OCCUPATION already pays a fisher in -- a
## pond that produced some other "pond fish" would be a second good nobody
## eats or buys.
const POND_CATCH_ITEM := "fish"


## Takes one fish out of this villager's own pond and puts it in their own
## building -- the fisher's half of the chain the farmer's harvest already
## walks (docs/concept/village_farms.md's "Grown, stored, carried").
##
## A no-op for a villager with no pond, an empty pond, or a world that
## cannot answer: the same fail-open shape every other world hook here uses,
## and a fisher without a pond keeps the open water their quarry model
## already gives them.
func _work_pond() -> void:
	if pond_cells.is_empty() or _world == null:
		return
	if not _world.has_method("catch_pond_fish_at"):
		return
	var water: Vector2i = pond_cells[0]
	if not _world.catch_pond_fish_at(water.x, water.y):
		return  # fished out until it breeds back
	_store_harvest(POND_CATCH_ITEM, 1)


## Carries what the farmhouse is holding into the village's own stock -- the
## other half of the chain: grown in the field, stored at the farmhouse,
## carried to the village.
##
## Credited through the SAME record_real_harvest a farmer without a
## farmhouse uses, so the crop reaches the market and is paid for exactly
## once, at the moment it actually arrives rather than at the scythe.
##
## All-or-nothing per crop, mirroring withdraw_from_structure_at itself: the
## villager either carries what is there or has nothing to carry. A no-op
## for a villager with no farmhouse, an empty one, or a world that cannot
## answer -- the same fail-open shape every other world hook here uses.
func haul_stock_to_village() -> void:
	if stock_building_cell == NO_STOCK_BUILDING or economy == null or _world == null:
		return
	# A village with a store leaves its shelves to the carter (docs/concept/
	# village_warehouse.md, Mechanism 7). Carrying the whole shelf into the
	# abstract ledger at the end of every work block is exactly what made a
	# farmhouse you clicked empty, a store you clicked empty, and the
	# carter's round pointless: *"The FarmHouse seems to be harvesting
	# something but none of it makes it into storage... it's always 0"*.
	if _village_has_a_store():
		return
	if not _world.has_method("withdraw_from_structure_at"):
		return
	var crop := _field_crop if _field_crop != "" else VillageFarm.crop_for(identity.occupation)
	if crop == "" and not pond_cells.is_empty():
		crop = POND_CATCH_ITEM  # a fisher's building holds fish, not a crop
	if crop == "":
		return
	var carried := 0
	while _world.withdraw_from_structure_at(stock_building_cell.x, stock_building_cell.y, crop, 1):
		carried += 1
	if carried > 0:
		economy.record_real_harvest(crop, carried)


## Whatever the farmer just did on `cell`, the beds around it get wet too.
##
## A field capped at ten tiles is more ground than one villager can walk in
## one wither grace -- measured at ZERO wheat per work block without this,
## because every plot died before it ripened and the whole block went on
## replanting ground that died again. The answer is not a bigger number, it
## is what a farmer actually does: you water a BED and the water runs to
## the beds beside it. One trip with a can, or along a furrow, wets the
## ground around where you are standing; it does not wet one plant.
##
## The bed itself is included: a visit with nothing else to do on it is
## still a tending visit, which is what VillageFarm.next_action's own
## thirstiest-bed fallback sends the farmer out for.
##
## Only this villager's OWN field, and only within TEND_REACH_TILES, so a
## farmer never tends their neighbour's ground from across the village.
func _water_the_beds_around(cell: Vector2i) -> void:
	if not _world.has_method("water_farm_plot_at_global"):
		return
	for other in field_cells:
		if absi(other.x - cell.x) > TEND_REACH_TILES or absi(other.y - cell.y) > TEND_REACH_TILES:
			continue
		_world.water_farm_plot_at_global(other.x, other.y)


## This field's plots, in field_cells order -- null for ground nobody has
## tilled yet, which VillageFarm.action_for reads as "plant this first".
func _field_states() -> Array:
	var states: Array = []
	for cell in field_cells:
		states.append(_field_plot_at(cell))
	return states


func _field_plot_at(cell: Vector2i):
	if not _world.has_method("farm_plot_at_global"):
		return null
	return _world.farm_plot_at_global(cell.x, cell.y)


func _cell_centre(cell: Vector2i) -> Vector2:
	return Vector2((float(cell.x) + 0.5) * _tile_size, (float(cell.y) + 0.5) * _tile_size)


func _field_reach() -> float:
	return float(_tile_size) * FIELD_REACH_TILES


## The carter's round: from whichever producer has the most waiting on its
## shelf, to the store's own door, and back (docs/concept/
## village_warehouse.md, Mechanism 4).
##
## The fourth sibling of _step_hunt, _step_farm and _step_timber, on the
## same four seams (find -> position -> reach -> act) and built on the SAME
## LogisticsBehavior phase machine the placeable-scale worker already uses:
## SEEKING -> APPROACHING -> COLLECTING -> CARRYING -> DEPOSITING. Nothing
## about hauling is reinvented; what changed is that a real villager walks
## it rather than a spawned walker ("It should be a real NPC pulling the
## cart, not an additional sprite").
##
## Off the clock the round is dropped rather than paused, exactly as the
## field and the trunk are -- and the cart is left standing WHERE IT IS,
## still holding whatever is in it, which is the feature rather than a gap.
func _step_cart(delta: float, is_working: bool):
	if not VillageCart.walks_the_round(identity.occupation) or store_cell == NO_STORE:
		_on_real_round = false
		return null
	if _world == null or not _world.has_method("structure_stock_contents_at"):
		_on_real_round = false
		return null
	if _carter == null:
		_carter = LogisticsBehavior.new()
	var have_the_shaft := _hold_the_cart()
	if not is_working:
		# Off the clock the wagon is LET GO, not dragged home: it stands
		# where the round ended, still loaded, free for whoever needs it next
		# (docs/concept/village_warehouse.md, Mechanisms 5 and 6).
		if cart != null and is_instance_valid(cart):
			cart.let_go(self)
		# The LEG is kept, though, where it used to be thrown away. A village
		# is wider than a work block is long: measured against a real one, a
		# carter who restarted at SEEKING every morning spent each block
		# walking back out to a shelf they had nearly reached the evening
		# before, and one or two deliveries arrived in ten simulated days
		# (tools/probe_village_store_round.gd). A carter picks up where they
		# left off, which is the only way a round longer than a block ever
		# finishes. Nothing moves while they are off: no target is returned,
		# the phase timers are not advanced, and the schedule has them.
		_on_real_round = false
		return null
	# A carter who has lost the shaft -- the player took it -- drops the
	# round rather than walking it empty-handed. Nothing is emptied into a
	# wagon they are not holding, so goods are never moved into thin air.
	if not have_the_shaft:
		if _carter.phase != LogisticsBehavior.Phase.SEEKING:
			_carter.abort()
		_on_real_round = false
		return null
	# A carter on the clock with the shaft in their hands has real work,
	# whether or not this instant is a walking one -- the same rule, for the
	# same reason, that a farmer with a farmhouse already has (see
	# _on_real_field). Reported in play with the warehouse readout open at
	# "Stored: 0 / 240": *"The porter is moving products (beams, logs) from
	# the sawmill to the warehouse but unloading doesn't put anything into
	# warehouse.. storage is still 0 and goods just vanish"*. Nothing
	# vanished -- the goods were on the wagon. A carter mid-round counted as
	# free to answer a need, and thirst comes up about every seventeen
	# seconds, so a round any longer than that was steered to the well
	# instead of to the store, over and over, with the beams riding along.
	_on_real_round = true

	match _carter.phase:
		LogisticsBehavior.Phase.SEEKING:
			# A wagon with something already on it is a delivery half done,
			# not a fresh round: finish THAT before fetching anything else.
			# The round is dropped at the end of every work block (above), so
			# without this a carter came back on the clock, walked to another
			# shelf and piled more onto a wagon that had never been emptied.
			# Measured against a real village, that left a FULL wagon -- 24
			# beams -- still aboard after ten simulated days, with one or two
			# deliveries arriving in all that time
			# (tools/probe_village_store_round.gd).
			if _wagon_is_loaded() and _carter.resume_carrying():
				return _cell_centre(store_cell)
			_carter.advance(delta)
			if not _carter.can_commit():
				return null
			var shelf := VillageCart.fullest_shelf(_shelves_waiting())
			if shelf.is_empty():
				return null
			_round_shelf = shelf["cell"]
			_carter.begin_approach()
			return _cell_centre(_round_shelf)
		LogisticsBehavior.Phase.APPROACHING:
			if position.distance_to(_cell_centre(_round_shelf)) <= _field_reach():
				_carter.arrive_at_source()
			return _cell_centre(_round_shelf)
		LogisticsBehavior.Phase.COLLECTING:
			if _carter.advance(delta) == LogisticsBehavior.Outcome.COLLECTED:
				_load_the_cart()
			return position
		LogisticsBehavior.Phase.CARRYING:
			if position.distance_to(_cell_centre(store_cell)) <= _field_reach():
				_carter.arrive_at_storage()
			return _cell_centre(store_cell)
		LogisticsBehavior.Phase.DEPOSITING:
			if _carter.advance(delta) == LogisticsBehavior.Outcome.DEPOSITED:
				_unload_the_cart()
			return position
	return null


## Whether this carter's own wagon still has something on it -- the question
## that decides whether a dropped round is resumed or a new one begun (see
## _step_cart's SEEKING leg).
func _wagon_is_loaded() -> bool:
	if cart == null or not is_instance_valid(cart):
		return false
	return CartLoad.total(cart.stock) > 0


## Takes the shaft if the wagon is free, and reports whether this villager
## really has it. A cart somebody else is pulling is never wrested off them
## -- a carter only ever takes a FREE cart, which is what keeps two of them
## from fighting over one (docs/concept/village_warehouse.md, Mechanism 6).
func _hold_the_cart() -> bool:
	if cart == null or not is_instance_valid(cart):
		return false
	cart.take_hold(self)
	return cart.is_held_by(self)


## What each of this village's producers is really holding, in the {cell,
## waiting} shape VillageCart.fullest_shelf reads. Asked of the world every
## time rather than remembered: a shelf fills while the carter is walking.
func _shelves_waiting() -> Array:
	var shelves: Array = []
	for cell in producer_cells:
		var waiting := 0
		var contents: Dictionary = _world.structure_stock_contents_at(cell.x, cell.y)
		for item_id in contents:
			waiting += int(contents[item_id])
		shelves.append({"cell": cell, "waiting": waiting})
	return shelves


## Fills the wagon from the shelf it is standing at, and really takes what
## it loaded off that shelf. What will not fit is left there rather than
## destroyed -- a full cart comes back for the rest.
func _load_the_cart() -> void:
	if cart == null or not is_instance_valid(cart) or not cart.is_held_by(self):
		_carter.abort()
		return
	var contents: Dictionary = _world.structure_stock_contents_at(_round_shelf.x, _round_shelf.y)
	var loaded := 0
	for item_id in contents:
		var wanted := int(contents[item_id])
		if wanted <= 0:
			continue
		var took: int = cart.load_on(String(item_id), wanted)
		if took <= 0:
			continue
		_world.withdraw_from_structure_at(_round_shelf.x, _round_shelf.y, String(item_id), took)
		loaded += took
	if loaded <= 0:
		_carter.abort()


## Empties the wagon into the store, every item id in one arrival at the
## door.
func _unload_the_cart() -> void:
	if cart == null or not is_instance_valid(cart) or not cart.is_held_by(self):
		return
	var unloaded: Dictionary = cart.unload_all()
	for item_id in unloaded:
		var delivered := int(unloaded[item_id])
		_world.deposit_to_structure_at(store_cell.x, store_cell.y, String(item_id), delivered)
		# The village's sellable stock is credited HERE, at the moment the
		# goods really reach the store (docs/concept/village_warehouse.md,
		# Mechanism 7) -- once, for a pile that exists. The producer was
		# already paid at their own scythe.
		if economy != null:
			economy.record_delivered_goods(String(item_id), delivered)


## The nearest real thing this villager may take right now, or null.
##
## A land animal comes out of the shared creature group, filtered by
## HuntableQuarry. A fish comes out of the chunk manager, which is the only
## thing that indexes them -- through nearest_fish_position, the hook a
## diving bird already hunts with. Both duck-typed and fail-open: a world
## that cannot answer simply has no quarry in it, and the villager keeps to
## the regional fallback.
func _find_quarry():
	match _quarry_kind:
		"creature":
			# is_inside_tree(), not get_tree() == null: calling get_tree()
			# on a detached node is an engine error in itself, so asking
			# the safe question is the only way to fail quietly. The engine
			# only runs _process on a node in the tree, but tools and
			# probes drive markers by hand (tools/probe_village_hunting.gd).
			if not is_inside_tree():
				return null
			return HuntableQuarry.nearest(
				get_tree().get_nodes_in_group(HuntableQuarry.QUARRY_GROUP_NAME), position
			)
		"fish":
			if _world == null or not _world.has_method("nearest_fish_position"):
				return null
			return _world.nearest_fish_position(position, HuntableQuarry.SEARCH_RADIUS_PX)
	return null


## Where the committed quarry is NOW, or null if it is gone -- killed by
## something else, fled, taken by another villager, or its chunk unloaded.
## Re-read every frame rather than remembered: both a deer and a fish move,
## and the node can stop being valid between one frame and the next
## (catch_nearest_fish frees its catch outright).
func _quarry_position():
	return _position_of(_quarry)


## Where `quarry` is, or null if it is not something takeable any more.
## Shared by the committed target and the cached scan result, because a
## remembered quarry goes stale in exactly the same ways a committed one
## does.
func _position_of(quarry):
	if quarry == null or not is_instance_valid(quarry) or quarry.is_queued_for_deletion():
		return null
	if _quarry_kind == "creature" and not HuntableQuarry.is_quarry(quarry):
		return null
	return quarry.position


## The nearest quarry, at most one real scan per QUARRY_SCAN_INTERVAL and
## the last answer in between -- CreatureMarker's own cached-senses shape.
## The cached answer is re-validated rather than trusted: between two scans
## a deer can be killed by a wolf and a fish taken by a bird.
func _quarry_in_reach(delta: float):
	_quarry_scan_elapsed += delta
	if _quarry_scan_elapsed < QUARRY_SCAN_INTERVAL:
		return _scanned_quarry if _position_of(_scanned_quarry) != null else null
	_quarry_scan_elapsed = 0.0
	_quarry_scan_count += 1
	_scanned_quarry = _find_quarry()
	return _scanned_quarry


## How close counts as being able to take it -- a spear has to touch the
## deer, a line does not.
func _reach() -> float:
	return CAST_DISTANCE_PX if _quarry_kind == "fish" else HuntableQuarry.STRIKE_DISTANCE_PX


## One blow, or one cast.
func _take_quarry() -> void:
	match _quarry_kind:
		"creature":
			_strike_quarry()
		"fish":
			_cast_at_quarry()


## One blow, through the SAME take_damage() a wolf's own bite and the
## player's own weapon call. Reads the meat off the animal BEFORE the blow,
## because a fatal one frees the node it would have to be read from.
##
## Nothing is credited for a blow that does not kill: half a deer is not
## half a meal, and a wounded animal that escapes fed nobody.
func _strike_quarry() -> void:
	var meat := HuntableQuarry.meat_yield_of(_quarry)
	var hide := HuntableQuarry.hide_yield_of(_quarry)
	var kill_position: Vector2 = _quarry.position
	_quarry.take_damage(HuntableQuarry.STRIKE_DAMAGE)
	if HuntableQuarry.is_quarry(_quarry):
		return  # still standing
	_take_carcass_at(kill_position)
	if economy != null:
		economy.record_real_catch(meat)
		# The hide goes to the market too, unpaid -- a travelling cart is
		# what a hide is worth anything to (see record_byproduct).
		economy.record_byproduct(HuntableQuarry.HIDE_ITEM_ID, hide)
	_end_take()


## One cast, through the SAME EarthChunkManager.catch_nearest_fish the
## player's own rod and a diving bird already use -- which frees the real
## fish and books the harvest against its chunk's aggregate population by
## itself. Nothing else is recorded here: record_fish_catch_near on top of
## it would thin the same shoal twice for one fish.
##
## One fish is one food unit (NpcProduction.FOOD_UNIT), not a mass-scaled
## count the way a carcass is: there is no fish equivalent of
## Butchering.meat_count to read one off, and inventing a conversion would
## be exactly the invented number this whole change exists to remove.
##
## A cast that lands nothing -- the shoal drifted, somebody else got there
## first -- credits nothing and simply casts again on the next beat.
func _cast_at_quarry() -> void:
	if _world == null or not _world.has_method("catch_nearest_fish"):
		return
	var caught: Dictionary = _world.catch_nearest_fish(position, CAST_DISTANCE_PX)
	if String(caught.get("species", "")) == "":
		return
	if economy != null:
		economy.record_real_catch(1)
	_end_take()


## The quarry is taken -- back out to look for the next. The scan is due
## again immediately rather than an interval from now: the rest of the herd
## is standing right there, and an interval spent not knowing that is an
## interval of conjured drip after every single kill.
func _end_take() -> void:
	_quarry = null
	_scanned_quarry = null
	_quarry_scan_elapsed = QUARRY_SCAN_INTERVAL
	_forager.finish_take()


## The quarry is gone -- killed by something else, fled, taken by another
## villager, or its chunk unloaded. Back to looking around, with a fresh
## look-around clock and, for the same reason as above, a scan due now.
func _give_up_on_quarry():
	_quarry = null
	_scanned_quarry = null
	_quarry_scan_elapsed = QUARRY_SCAN_INTERVAL
	_forager.abort()
	return null


## A hunter carries home the animal it killed. Without this, the same meat
## would exist twice: once as this village's market stock and once as a
## carcass anyone could walk up and butcher (CreatureMarker._die leaves one
## for every species LootTable has drops for).
##
## Scoped to the kill site at STRIKE_DISTANCE_PX, so somebody else's kill
## lying in the next clearing is not a hunter's to pick up.
##
## Named simplification: the whole animal goes home, so the guts a real
## field-dressing leaves behind (Butchering's third part, CarcassGuts) are
## not spawned. Wild deaths -- predation, disease, age -- still leave their
## carcasses untouched, so the carrion chain (docs/concept/carrion.md)
## keeps every input it had except the ones a villager personally killed
## and carried off.
func _take_carcass_at(kill_position: Vector2) -> void:
	if not is_inside_tree():
		return
	if not is_inside_tree():
		return
	for node in get_tree().get_nodes_in_group(Carcass.GROUP_NAME):
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		if node.position.distance_to(kill_position) <= HuntableQuarry.STRIKE_DISTANCE_PX:
			node.queue_free()
			return


func _ready() -> void:
	# A villager is a person, and a person is what may pull a cart
	# (CartMarker.PULLER_GROUP).
	add_to_group(CartMarker.PULLER_GROUP)
