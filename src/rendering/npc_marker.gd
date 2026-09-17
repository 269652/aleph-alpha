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
const NpcEconomy = preload("res://src/world/npc_economy.gd")
const NpcInstructionEvaluator = preload("res://src/world/npc_instruction_evaluator.gd")
const CharacterView = preload("res://scenes/character_view.gd")
const CreaturePerception = preload("res://src/gameplay/creature_perception.gd")
const ForagerBehavior = preload("res://src/gameplay/forager_behavior.gd")
const VillageFarm = preload("res://src/gameplay/village_farm.gd")
const FarmerBehavior = preload("res://src/gameplay/farmer_behavior.gd")
const HuntableQuarry = preload("res://src/gameplay/huntable_quarry.gd")
const Carcass = preload("res://src/rendering/carcass.gd")
const NpcCondition = preload("res://src/world/npc_condition.gd")
const VillagerBehavior = preload("res://src/gameplay/villager_behavior.gd")
const VillageSawmill = preload("res://src/gameplay/village_sawmill.gd")
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
var _tile_size := 16
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
var _canopy_off := false
var _cuts_left := 0
var _carried_logs := 0
var _target_growth_scale := 1.0
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

	var entry := NpcSchedule.current_entry(schedule, _current_hour())
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
	):
		entry = {"time_block": entry.get("time_block", ""), "location_tag": "well", "activity": "eat"}
	if instruction_script != null:
		var action: Variant = NpcInstructionEvaluator.evaluate(instruction_script, _instruction_frame())
		if action != null:
			entry = _entry_for_instructed_action(action)
	var location_tag: String = entry.get("location_tag", "home")
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
	position = position.move_toward(target, (RUN_SPEED if running else WALK_SPEED) * delta)
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
		and position.distance_to(home_position) < _ARRIVED_HOME_EPSILON_PX
	)
	visible = not _at_home
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
			_canopy_off = false
			_cuts_left = 0
			_target_growth_scale = float(tree.growth_scale)
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


## The nearest standing tree this MILL's sawyer may work -- measured from
## the mill, not from the villager, so a village fells its own wood rather
## than following a trail of trunks across the map.
func _nearest_workable_tree(mill: Vector2) -> Node2D:
	var best: Node2D = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group(ChoppableTree.GROUP_NAME):
		if not is_instance_valid(node) or node.is_felled():
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
func _swing_at_timber(delta: float) -> void:
	if not _sawyer.advance(delta):
		return  # the swing is not ready yet this tick
	if not _timber_target.is_felled():
		_timber_target.take_damage(FELL_DAMAGE)
		return
	if not _canopy_off:
		_canopy_off = true
		_cuts_left = FelledTree.CUTS_TO_CLEAR
		_timber_target.take_damage(FELL_DAMAGE)  # the canopy comes off, no log yet
		return
	_carried_logs += FelledTree.logs_per_cut(_target_growth_scale)
	_cuts_left -= 1
	_timber_target.take_damage(FELL_DAMAGE)
	if _cuts_left <= 0:
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


## Carries the mill's finished BEAMS into the village's own stock -- the
## other half of the chain, and the same one the farmhouse already runs
## (haul_stock_to_village): cut in the wood, squared at the mill,
## carried to the village.
##
## Beams only. The logs a mill is holding are its own raw material, and
## carrying those off would be carrying away the very thing the sawmill
## exists to work.
##
## Credited through the same record_real_harvest a farmer's crop uses, so a
## beam is paid for exactly once, at the moment it actually arrives rather
## than at the saw. All-or-nothing per unit, mirroring
## withdraw_from_structure_at itself, and a no-op for a villager with no
## mill, an empty one, or a world that cannot answer.
func haul_sawmill_stock_to_village() -> void:
	if sawmill_cell == NO_SAWMILL or economy == null or _world == null:
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
	return _on_real_quarry or _on_real_field or _on_real_work_timber


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
	var day_fraction := fmod(_elapsed_time / SECONDS_PER_SIMULATED_DAY, 1.0)
	return int(day_fraction * 24.0)


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
func _resolve_location(tag: String) -> Vector2:
	if tag == "home":
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
		haul_stock_to_village()
		return null
	# A villager with a farmhouse has real work whether or not any single
	# plot wants attention this instant, so the regional drip is off for
	# the whole work block rather than flickering with the crop cycle.
	_on_real_field = true
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
			if _world.has_method("water_farm_plot_at_global"):
				_world.water_farm_plot_at_global(cell.x, cell.y)
	_water_the_beds_around(cell)


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
		return
	if economy != null:
		economy.record_real_harvest(crop_id, count)


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
		haul_stock_to_village()
		return null
	_cast_elapsed += delta
	if _cast_elapsed >= CAST_SECONDS:
		_cast_elapsed = 0.0
		_work_pond()
	return _cell_centre(pond_cells[0])


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
