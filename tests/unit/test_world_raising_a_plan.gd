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
## drives the real raising path on a real ledger, a real chunk manager and a
## real player, and asks the only question that matters: is the tile THERE
## afterwards.
##
## Reported a THIRD time -- *"Planned nodes (e.g. pavement) still can't be
## actually built by the player or hired NPCs... there should be tooltips
## with hotkeys for both actions"* -- and that is when the two actions became
## two keys with a prompt of their own. The single `_raise_plan_within_reach`
## these tests first drove is gone: it offered the hire, then fell through to
## your own hands, so one press did one of three things and nothing on screen
## said which. Each half is now its own function, `_raise_plan_yourself` and
## `_hire_builder_for_plan`, and refuses in its own terms.

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

	assert_true(world._raise_plan_yourself(player), "the wireframe was found")

	assert_ne(_tile_at(_site), "", "the pavement is really on the ground")


## And the wireframe comes down with it -- a plan left standing would draw a
## blueprint over its own road.
func test_raising_a_plan_takes_its_wireframe_down():
	_plan_pavement_at(_site)
	world._raise_plan_yourself(player)
	assert_true(world._build_plans.plans().is_empty(), "the plan became a building")


## Out of reach is out of reach, and nothing is built by accident.
func test_a_plan_across_the_map_is_not_raised_from_where_you_stand():
	var far: Vector2i = _site + Vector2i(PlanRaising.REACH_TILES * 4, 0)
	_plan_pavement_at(far)

	assert_false(world._raise_plan_yourself(player), "nothing within reach")

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

	assert_true(world._raise_plan_yourself(player))

	assert_ne(_tile_at(_site), "", "somebody standing there is not in your way")


## A villager you know well enough WILL take the job -- and if the wage
## cannot actually move (they have no household purse to pay into, which is
## every villager the household store has never heard of), hiring fails.
##
## REVERSED, deliberately, when the two actions became two keys: this used to
## fall through to your own hands, because one key that refuses is a key that
## does nothing. That fall-through is what made the outcome unpredictable --
## the player could not tell whether they had hired somebody, paid nothing
## and built it, or been refused. Hiring now refuses as hiring, and your own
## hands are one key over, always available (the test below).
func test_a_hire_that_cannot_be_paid_does_not_quietly_become_your_own_work():
	_villager_beside_the_player(1.0)
	_plan_pavement_at(_site)
	assert_null(
		chunk_manager.household_wallet_for_villager(4242),
		"premise: this villager has no household purse for the wage to land in"
	)

	assert_true(world._hire_builder_for_plan(player), "the wireframe was found")

	assert_eq(_tile_at(_site), "", "an unpayable hire is a refusal, not a free build")

	assert_true(world._raise_plan_yourself(player), "and your own hands are one key over")
	assert_ne(_tile_at(_site), "", "which lays it")


## And with an empty purse of your own: a player who cannot afford a wage
## can still do the work.
func test_a_broke_player_can_still_lay_pavement_themselves():
	var villager := _villager_beside_the_player(1.0)
	chunk_manager.record_settlement_founded_if_new(CHUNK, [villager.identity], [])
	player.wallet = Wallet.new()
	_plan_pavement_at(_site)

	assert_true(world._raise_plan_yourself(player))

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

	assert_true(world._hire_builder_for_plan(player))

	assert_ne(_tile_at(_site), "", "the hired builder really laid it")
	assert_lt(player.wallet.balance, before, "and the wage really moved")


# -- two actions, two keys, and a prompt that says so -----------------------
#
# Reported a third time: *"Planned nodes (e.g. pavement) still can't be
# actually built by the player or hired NPCs... there should be tooltips with
# hotkeys for both actions"*.
#
# The tests above prove the mechanism works when it is called. What was
# missing is any way for a player to know it exists, and any way to CHOOSE
# between the two things it does. Both hung off the talk key, which offered
# the hire first and fell through to your own hands -- and the floating
# prompt, standing at a wireframe, said "Talk (G)", because a wireframe is
# raised in a village and there is nearly always a villager in range.
#
# So: the two context slots the keybindings already keep for exactly this
# ("What they do is decided by whatever is under the cursor and the state it
# is in"), one each, and a prompt that names the plan and both keys.


func _primary_key() -> String:
	return OS.get_keycode_string(world._keybindings.keycode_for("primary_action"))


func _secondary_key() -> String:
	return OS.get_keycode_string(world._keybindings.keycode_for("secondary_action"))


func test_a_wireframe_in_reach_offers_both_actions_with_their_own_keys():
	_plan_pavement_at(_site)

	var prompt: String = world._plan_prompt_for(player)

	assert_true(
		prompt.contains(BuildPlan.display_name_of(BuildPlan.PAVEMENT_BLUEPRINT_ID)),
		"the prompt names what is planned there, found: %s" % prompt
	)
	assert_true(prompt.contains(_primary_key()), "the build key, found: %s" % prompt)
	assert_true(prompt.contains(_secondary_key()), "the hire key, found: %s" % prompt)


## Nothing planted in your path claims a key you do not have a use for.
func test_standing_nowhere_near_a_wireframe_offers_nothing():
	assert_eq(world._plan_prompt_for(player), "")


func test_a_wireframe_across_the_map_offers_nothing():
	_plan_pavement_at(_site + Vector2i(PlanRaising.REACH_TILES + 6, 0))
	assert_eq(world._plan_prompt_for(player), "")


# -- and each key does its own one thing ------------------------------------


## Your own hands, with a villager you know well standing right beside you
## and gold in your purse: no wage moves, because you did not ask anyone.
func test_building_it_yourself_is_its_own_action_and_never_hires():
	var villager := _villager_beside_the_player(1.0)
	chunk_manager.record_settlement_founded_if_new(CHUNK, [villager.identity], [])
	player.wallet.add(100)
	var before: int = player.wallet.balance
	_plan_pavement_at(_site)

	assert_true(world._raise_plan_yourself(player), "the wireframe was found")

	assert_ne(_tile_at(_site), "", "you laid it")
	assert_eq(player.wallet.balance, before, "and nobody was paid for it")


func test_a_paid_hire_through_its_own_key_really_lays_it():
	var villager := _villager_beside_the_player(1.0)
	chunk_manager.record_settlement_founded_if_new(CHUNK, [villager.identity], [])
	player.wallet.add(100)
	var before: int = player.wallet.balance
	_plan_pavement_at(_site)

	assert_true(world._hire_builder_for_plan(player), "the wireframe was found")

	assert_ne(_tile_at(_site), "", "the hired builder really laid it")
	assert_lt(player.wallet.balance, before, "and the wage really moved")


## Asking for a builder when there is nobody to ask is answered, not
## silently turned into your own afternoon's work. The old single key had to
## fall through -- one key cannot refuse and still be useful -- and that is
## exactly what made which-thing-happened unpredictable.
func test_hiring_with_nobody_to_hire_builds_nothing():
	_plan_pavement_at(_site)

	assert_true(world._hire_builder_for_plan(player), "the wireframe was found")

	assert_eq(_tile_at(_site), "", "nobody was hired, so nothing was built")


func test_a_hire_that_cannot_be_paid_builds_nothing_either():
	_villager_beside_the_player(1.0)
	_plan_pavement_at(_site)

	assert_true(world._hire_builder_for_plan(player))

	assert_eq(_tile_at(_site), "", "an unpaid hire is a refusal, not a free build")


## And neither action reaches a wireframe that is not in reach.
func test_neither_action_reaches_across_the_map():
	var far := _site + Vector2i(PlanRaising.REACH_TILES + 6, 0)
	_plan_pavement_at(far)

	assert_false(world._raise_plan_yourself(player))
	assert_false(world._hire_builder_for_plan(player))
	assert_eq(_tile_at(far), "")
