extends GutTest

## World._update_interaction_prompt used to run on EVERY frame with no
## throttle at all -- unlike its sibling _update_hover_tooltip, which is
## already gated to ~30 Hz via HOVER_REFRESH_INTERVAL specifically because
## an unthrottled per-frame scan there was a measured real cost. This one
## chains through up to three unbounded linear scans (EarthChunkManager.
## nearest_npc_near, .nearest_liftable_stone_near, Player.
## nearest_kickable_dropped_item_near) every time the player isn't already
## near an NPC or holding something -- the common case -- so it needed the
## same kind of accumulator-gated throttle.
##
## World itself has no direct unit tests in general (see
## test_world_inventory_wiring.gd's own framing): this wires up only the
## plain fields _maybe_update_interaction_prompt/_update_interaction_prompt
## actually read, on a World.new() deliberately never add_child()'d, the
## same convention test_world_streaming_budget.gd and
## test_world_inventory_wiring.gd already use.

const World = preload("res://scenes/world.gd")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const CraftingWindow = preload("res://scenes/crafting_window.gd")
const SkillTreeWindow = preload("res://scenes/skill_tree_window.gd")
const QuestLogWindow = preload("res://scenes/quest_log_window.gd")
const ConversationWindow = preload("res://scenes/conversation_window.gd")
const PlayerScene = preload("res://scenes/player.tscn")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const HouseInteriorView = preload("res://src/rendering/house_interior_view.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")
const NpcMarker = preload("res://src/rendering/npc_marker.gd")

const TILE_SIZE := TerrainRenderer.TILE_SIZE
const INTERVAL := World.INTERACTION_PROMPT_REFRESH_INTERVAL


## Counts real calls into nearest_npc_near -- the FIRST of the three
## unbounded scans _update_interaction_prompt chains through on every call
## that isn't gated away by world_hint_visible_for, and therefore proof the
## expensive scan ran (or was correctly skipped) regardless of what it
## would have found. Left unloaded (no .update() call), so the real
## implementation's own loop over an empty _loaded_villages already returns
## null on its own -- no need to fake that part too.
class SpyChunkManager extends EarthChunkManager:
	var nearest_npc_near_calls := 0

	# Mirrors the parent's full signature, `excluding` included: a villager
	# looking for company asks this same question from their own position and
	# passes themselves in (see EarthChunkManager.nearest_npc_near's own doc
	# comment), so an override that drops the parameter no longer matches the
	# parent and this whole file stops loading. Forwarded rather than
	# ignored -- this spy exists to COUNT the scan, not to change it.
	func nearest_npc_near(
		pixel_position: Vector2, max_distance: float, excluding: NpcMarker = null
	) -> NpcMarker:
		nearest_npc_near_calls += 1
		return super.nearest_npc_near(pixel_position, max_distance, excluding)


var world: World
var manager: SpyChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var player: Player
var interaction_prompt: Label
var inventory_window: PanelContainer
var crafting_window: CraftingWindow
var skill_window: SkillTreeWindow
var quest_log_window: QuestLogWindow
var conversation_window: ConversationWindow


func before_each():
	# Deliberately NOT add_child()'d -- only the plain fields
	# _update_interaction_prompt actually reads are wired by hand. Kept in
	# their own local vars (rather than only reachable via world._foo) so
	# after_each can free them explicitly -- world.free() does not cascade
	# to them, since they were never actually added as its children.
	#
	# EVERY window World._any_gameplay_window_open reads must be wired here,
	# each explicitly hidden: a window left unassigned is a Nil whose
	# is_open() call is a script error (not a quiet "closed"), and one left
	# at its default visibility counts as open -- their _ready() is what
	# normally hides them, and _ready() never runs on a bare .new().
	world = World.new()
	interaction_prompt = Label.new()
	world._interaction_prompt = interaction_prompt
	inventory_window = PanelContainer.new()
	inventory_window.visible = false
	world._inventory_window = inventory_window
	crafting_window = CraftingWindow.new()
	crafting_window.visible = false
	world._crafting_window = crafting_window
	skill_window = SkillTreeWindow.new()
	skill_window.visible = false
	world._skill_window = skill_window
	quest_log_window = QuestLogWindow.new()
	quest_log_window.visible = false
	world._quest_log_window = quest_log_window
	conversation_window = ConversationWindow.new()
	conversation_window.visible = false
	world._conversation_window = conversation_window

	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	manager = SpyChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	world._chunk_manager = manager

	# A real Player, in a real tree (nearest_kickable_dropped_item_near
	# needs get_tree()), not holding anything and with no stones/dropped
	# items loaded anywhere -- the "nothing nearby" common case, so all
	# three scans actually run to completion on every un-throttled call.
	player = PlayerScene.instantiate()
	player.name = str(multiplayer.get_unique_id())
	add_child(player)
	player.setup(manager, TILE_SIZE)


func after_each():
	remove_child(player)
	player.free()
	world.free()
	interaction_prompt.free()
	inventory_window.free()
	crafting_window.free()
	skill_window.free()
	quest_log_window.free()
	conversation_window.free()
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


## The interval itself must be a tested constant (CLAUDE.md), not an
## eyeballed comment -- pinned to the exact value and to the 10-15 Hz band
## the throttle was scoped to (a proximity prompt needs nowhere near 60 Hz
## freshness, same reasoning as HOVER_REFRESH_INTERVAL's own ~30 Hz).
func test_the_refresh_interval_is_pinned_within_the_recommended_band():
	assert_between(INTERVAL, 1.0 / 15.0, 1.0 / 10.0)


func test_the_refresh_interval_is_exactly_pinned():
	assert_eq(INTERVAL, 0.075)


## The core throttle behaviour: two calls whose combined delta stays under
## the interval must not run the expensive scan even once yet.
func test_two_calls_within_the_interval_do_not_run_the_scan():
	world._maybe_update_interaction_prompt(player, INTERVAL * 0.4)
	world._maybe_update_interaction_prompt(player, INTERVAL * 0.4)

	assert_eq(
		manager.nearest_npc_near_calls, 0,
		"0.8x the interval, split across two calls, must not have crossed the threshold yet"
	)


## Once the accumulated delta actually crosses the interval, the scan runs
## -- exactly once, not once per call that happened to be pending.
func test_crossing_the_interval_runs_the_scan_exactly_once():
	world._maybe_update_interaction_prompt(player, INTERVAL * 0.4)
	world._maybe_update_interaction_prompt(player, INTERVAL * 0.4)
	world._maybe_update_interaction_prompt(player, INTERVAL * 0.4)

	assert_eq(
		manager.nearest_npc_near_calls, 1,
		"1.2x the interval, split across three calls, should run the scan exactly once"
	)


## After firing, the accumulator must reset back to zero and wait a full
## interval again -- otherwise it would fire once and then run unthrottled
## on every subsequent call forever.
func test_after_firing_the_accumulator_resets_and_waits_again():
	world._maybe_update_interaction_prompt(player, INTERVAL * 1.5)
	assert_eq(manager.nearest_npc_near_calls, 1, "the first call already crosses the interval once")

	world._maybe_update_interaction_prompt(player, INTERVAL * 0.4)
	assert_eq(
		manager.nearest_npc_near_calls, 1,
		"a call right after firing, before a fresh interval has elapsed, must not re-run the scan"
	)


## A single call whose OWN delta already exceeds the interval (e.g. a lag
## spike, or simply the very first frame after a long pause) must still run
## the scan -- the throttle skips redundant work, it never starves the
## prompt of updates entirely.
func test_a_single_large_delta_still_runs_the_scan():
	world._maybe_update_interaction_prompt(player, INTERVAL * 2.0)

	assert_eq(manager.nearest_npc_near_calls, 1)


## The displayed prompt is cached between throttled calls, not blanked: a
## skipped call must leave _interaction_prompt exactly as the last real
## scan left it (here, hidden -- nothing was ever found), never toggling it
## off just because the scan itself didn't run this frame.
func test_a_throttled_call_leaves_the_prompts_visibility_untouched():
	world._maybe_update_interaction_prompt(player, INTERVAL * 1.5)
	assert_eq(manager.nearest_npc_near_calls, 1)
	var visible_after_real_scan: bool = world._interaction_prompt.visible

	world._interaction_prompt.visible = true  # simulate a stale prior state
	world._maybe_update_interaction_prompt(player, INTERVAL * 0.1)

	assert_eq(manager.nearest_npc_near_calls, 1, "the scan must not have re-run")
	assert_true(
		world._interaction_prompt.visible,
		"a throttled call must leave the prompt exactly as it was, not overwrite it"
	)
	assert_false(visible_after_real_scan, "sanity: the real scan found nothing, so it should have hidden the prompt")


# -- Enter/Leave (docs/concept/building.md "Entering") ----------------------
#
# _update_interaction_prompt's own gating logic for the two new branches --
# is_indoors()/can_leave_building() and building_door_near -- called
# DIRECTLY (bypassing the throttle accumulator, the same "test the real
# function, not just its gate" split test_world_hud.gd's own doc comment
# already draws) so these are unaffected by INTERVAL timing.

func test_no_building_nearby_leaves_the_prompt_hidden():
	world._update_interaction_prompt(player)
	assert_false(world._interaction_prompt.visible)


func test_indoors_but_not_on_the_exit_cell_hides_the_prompt():
	var view := HouseInteriorView.new()
	var renderer := TerrainRenderer.new()
	view.build("cottage", "farmer", 5, renderer.build_tile_set(), TILE_SIZE, renderer)
	add_child(view)
	var avatar := InteriorAvatar.new()
	add_child(avatar)
	player.enter_building(view, avatar)
	# enter_building already placed the avatar one full cell inside the
	# door (16px) -- HouseInteriorView._EXIT_RADIUS_PX (10px) is
	# deliberately smaller than that gap specifically so this stays false
	# right after entering.
	assert_false(player.can_leave_building(), "precondition: freshly entered, not at the door")

	world._update_interaction_prompt(player)

	assert_false(world._interaction_prompt.visible)
	view.free()
	avatar.free()


## The indoors decision itself, as a pure helper (the prompt's own
## _show_interaction_prompt needs a live viewport this file deliberately
## never stands up -- see the note below): Leave on the exit cell, a
## resident within TALK_RADIUS of the avatar anywhere else, otherwise
## nothing. Leave wins on the exit cell even though a cottage's resident
## stands within talk reach of its doorway -- the exit cell is a 10px spot
## you only stand on to leave (see World._indoor_prompt_for).
func test_indoor_prompt_is_talk_near_the_resident_leave_on_the_exit_and_nothing_elsewhere():
	var view := HouseInteriorView.new()
	var renderer := TerrainRenderer.new()
	view.build("cottage", "farmer", 5, renderer.build_tile_set(), TILE_SIZE, renderer)
	add_child(view)
	var avatar := InteriorAvatar.new()
	add_child(avatar)
	player.enter_building(view, avatar)
	assert_eq(world._indoor_prompt_for(player), "", "freshly entered: not at the door, nobody home")

	view.place_resident(NpcIdentity.new(9))
	avatar.position = view.resident_position() + Vector2(TILE_SIZE, 0)
	assert_eq(world._indoor_prompt_for(player), "talk")

	avatar.position = (Vector2(view.door_cell) + Vector2(0.5, 0.5)) * TILE_SIZE
	assert_eq(world._indoor_prompt_for(player), "leave")
	view.free()
	avatar.free()


## The "shows a real Enter/Leave prompt" cases (standing exactly on a real
## doorstep/exit cell) are deliberately NOT covered here: both reach
## _show_interaction_prompt's own get_viewport().get_canvas_transform()
## call, and world is (correctly, per this whole file's own established
## convention) never add_child()'d -- World._ready() is genuinely heavy
## (SelfIntegrity/LicenseGate/a live GitHub check/a full EarthChunkManager)
## and every test here deliberately avoids triggering it. This is not a
## gap specific to Enter/Leave: the pre-existing Talk/Pick branches (see
## this file's own header comment) have never reached that line in any
## test either, for the identical reason -- confirmed directly, not
## assumed: a real attempt crashes with "Cannot call method
## 'get_canvas_transform' on a null value", the exact null-viewport
## failure mode the lack of add_child() predicts. The GATING logic above
## (is_indoors/can_leave_building/building_door_near deciding whether to
## call _show_interaction_prompt at all) is the real, new, tested surface;
## whether the resulting Label actually renders on screen is exercised in
## real play, the same as every other prompt this function shows.
