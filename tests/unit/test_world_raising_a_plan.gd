extends GutTest

## Raising a wireframe, driven for real (docs/concept/planner_mode.md).
##
## Reported in play, twice: *"Planning works, but building it / hiring a
## builder does not yet seem to work"*, and after the first round of fixes,
## *"It's still not possible to build a planned entity like pavement"*.
##
## Every existing test of this path is a SOURCE-CONTRACT test on the function
## bodies (test_world_planner_mode_wiring.gd's own header explains why), so
## every one of them passes on code that cannot raise a single tile. This
## drives the real `_raise_plan_within_reach` on a real ledger, a real chunk
## manager and a real player, and asks the only question that matters: is
## the tile THERE afterwards.

const World = preload("res://scenes/world.gd")
const PlayerScene = preload("res://scenes/player.tscn")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const BuildPlan = preload("res://src/world/build_plan.gd")
const BuildPlanLedger = preload("res://src/world/build_plan_ledger.gd")
const BuildPlanPersistence = preload("res://src/world/build_plan_persistence.gd")
const PlanWireframeLayer = preload("res://src/rendering/plan_wireframe_layer.gd")
const NpcTrustStore = preload("res://src/world/npc_trust_store.gd")
const PlanRaising = preload("res://src/gameplay/plan_raising.gd")
const CraftingWindow = preload("res://scenes/crafting_window.gd")
const QuestLogWindow = preload("res://scenes/quest_log_window.gd")
const ConversationWindow = preload("res://scenes/conversation_window.gd")
const SkillTreeWindow = preload("res://scenes/skill_tree_window.gd")

const TILE_SIZE := TerrainRenderer.TILE_SIZE
const CHUNK := Vector2i(0, 0)

var world: World
var chunk_manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var player: Player
var _site: Vector2i


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	add_child_autofree(tile_map_layer)
	add_child_autofree(entities_parent)
	add_child_autofree(creatures_parent)
	chunk_manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	chunk_manager._load_chunk(CHUNK)

	player = PlayerScene.instantiate()
	player.name = str(multiplayer.get_unique_id())
	add_child(player)
	_site = _a_clear_cell()
	player.position = (Vector2(_site) + Vector2(0.5, 0.5)) * TILE_SIZE
	player.setup(chunk_manager, TILE_SIZE)

	world = World.new()
	world._chunk_manager = chunk_manager
	world._build_plans = BuildPlanLedger.new()
	world._build_plan_store = BuildPlanPersistence.new()
	world._npc_trust = NpcTrustStore.new()
	world._plan_wireframes = PlanWireframeLayer.new()
	world._plan_wireframes.configure(world._build_plans, EarthChunkManager.CHUNK_SIZE, TILE_SIZE)
	add_child_autofree(world._plan_wireframes)


func after_each():
	remove_child(player)
	player.free()
	world.free()


## A cell in the loaded chunk with nothing on it, so a plan can really be
## laid there and a tile can really land.
func _a_clear_cell() -> Vector2i:
	for y in range(2, EarthChunkManager.CHUNK_SIZE - 2):
		for x in range(2, EarthChunkManager.CHUNK_SIZE - 2):
			if chunk_manager.modification_at_global(x, y) == "":
				return Vector2i(x, y)
	fail_test("no clear cell in the loaded chunk")
	return Vector2i(4, 4)


func _plan_pavement_at(cell: Vector2i) -> void:
	var planned: String = world._build_plans.plan(
		CHUNK, cell - CHUNK * EarthChunkManager.CHUNK_SIZE, BuildPlan.PAVEMENT_BLUEPRINT_ID,
		0.0, func(_cell: Vector2i) -> bool: return true
	)
	assert_ne(planned, "", "precondition: the ledger really accepted the plan at %s" % str(cell))


func _tile_at(cell: Vector2i) -> String:
	return chunk_manager.modification_at_global(cell.x, cell.y)


# -- pavement, alone in the wilderness -------------------------------------

## The plainest case there is: a plan, a player standing on it, nobody else
## anywhere near, and no materials needed. Pavement is not a recipe.
func test_a_player_standing_at_a_pavement_plan_really_lays_it():
	_plan_pavement_at(_site)
	assert_eq(_tile_at(_site), "", "precondition: nothing is there yet")

	assert_true(world._raise_plan_within_reach(player), "the wireframe was found")

	assert_ne(_tile_at(_site), "", "the pavement is really on the ground")


## And the wireframe comes down with it -- a plan left standing would draw a
## blueprint over its own road.
func test_raising_a_plan_takes_its_wireframe_down():
	_plan_pavement_at(_site)
	world._raise_plan_within_reach(player)
	assert_true(world._build_plans.plans().is_empty(), "the plan became a building")


## Out of reach is out of reach, and nothing is built by accident.
func test_a_plan_across_the_map_is_not_raised_from_where_you_stand():
	var far: Vector2i = _site + Vector2i(PlanRaising.REACH_TILES * 4, 0)
	_plan_pavement_at(far)

	assert_false(world._raise_plan_within_reach(player), "nothing within reach")

	assert_eq(_tile_at(far), "", "and nothing was laid")


# -- with a villager standing beside you ------------------------------------
#
# The case an empty chunk can never reach, and the one a player is actually
# in: wireframes are raised IN villages, so there is nearly always somebody
# within talking range. Everything above passes with nobody there.

const NpcMarker = preload("res://src/rendering/npc_marker.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")
const NpcTrust = preload("res://src/world/npc_trust.gd")
const VillageMarket = preload("res://src/world/village_market.gd")
const Wallet = preload("res://src/gameplay/wallet.gd")


## A real villager standing next to the player, at whatever trust is asked
## for. Registered in `_loaded_villages`, which is the only place
## nearest_npc_near looks.
func _villager_beside_the_player(trust: float) -> NpcMarker:
	var marker := NpcMarker.new()
	marker.identity = NpcIdentity.new(4242)
	marker.position = player.position + Vector2(8, 0)
	marker.home_position = player.position + Vector2(400, 400)
	marker.workspot_position = marker.position
	marker.setup(chunk_manager, TILE_SIZE)
	marker.setup_economy(VillageMarket.new())
	add_child_autofree(marker)
	chunk_manager._loaded_villages[CHUNK] = [marker]
	world._npc_trust.set_trust(marker.identity.seed_value, trust)
	return marker


func test_a_stranger_beside_you_does_not_stop_you_building_it_yourself():
	_villager_beside_the_player(NpcTrust.BASELINE_TRUST)
	_plan_pavement_at(_site)

	assert_true(world._raise_plan_within_reach(player))

	assert_ne(_tile_at(_site), "", "a stranger will not take the job, so you lay it")


## The reported case. A villager you know well enough WILL take the job --
## and if the wage cannot actually move (they have no household purse to pay
## into, which is every villager the household store has never heard of),
## hiring fails. That must not leave the player unable to build it at all:
## they are standing right there, and pavement costs nothing to lay.
func test_a_hire_that_cannot_be_paid_still_lets_you_lay_it_yourself():
	_villager_beside_the_player(1.0)
	_plan_pavement_at(_site)
	assert_null(
		chunk_manager.household_wallet_for_villager(4242),
		"premise: this villager has no household purse for the wage to land in"
	)

	assert_true(world._raise_plan_within_reach(player))

	assert_ne(_tile_at(_site), "", "you laid it yourself rather than being told no")


## And with an empty purse of your own: a player who cannot afford a wage
## can still do the work.
func test_a_broke_player_can_still_lay_pavement_themselves():
	var villager := _villager_beside_the_player(1.0)
	chunk_manager.record_settlement_founded_if_new(CHUNK, [villager.identity], [])
	player.wallet = Wallet.new()
	_plan_pavement_at(_site)

	assert_true(world._raise_plan_within_reach(player))

	assert_ne(_tile_at(_site), "", "no gold is no reason not to lay a paving stone")


## And a hire that CAN be paid really builds it. Pavement asks for no labour
## hours, so the builder's first act is to have finished.
func test_a_paid_hire_really_lays_the_pavement():
	var villager := _villager_beside_the_player(1.0)
	chunk_manager.record_settlement_founded_if_new(CHUNK, [villager.identity], [])
	var purse = chunk_manager.household_wallet_for_villager(villager.identity.seed_value)
	assert_not_null(purse, "premise: this villager has a household purse to be paid into")
	player.wallet.add(100)
	var before: int = player.wallet.balance
	_plan_pavement_at(_site)

	assert_true(world._raise_plan_within_reach(player))

	assert_ne(_tile_at(_site), "", "the hired builder really laid it")
	assert_lt(player.wallet.balance, before, "and the wage really moved")
