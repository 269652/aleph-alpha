extends GutTest

## The full progression loop, end to end, exactly as docs/concept/progression.md
## and docs/concept/skills.md describe it: a real player action earns XP, XP
## rolls a level and grants a skill point, spending that point in the skill
## window allocates a real node on the live Player, and a keystone's own
## bonus reaches the character -- all through the SAME objects and signals
## World actually wires (see World._build_skill_window/_refresh_skill_window).
##
## Every one of those links already has its own dedicated unit test elsewhere:
## test_experience_track.gd for the XP curve in isolation, test_player_skill_web.gd
## for Player<->SkillWeb (via a _with_points() shortcut that assigns
## unspent_points directly, never through gain_experience), and
## test_skill_tree_window_web.gd for SkillTreeWindow<->a bare, hand-fed SkillWeb
## (never a real Player). None of them puts a real Player's real experience/
## allocated_nodes/unlocked_keystones through a real SkillTreeWindow the way
## World does -- so "the UI reflects it" has, until now, only ever meant "the
## production code that would presumably do this exists", not "a window fed
## this player's real state actually renders it". This file closes that seam:
## it drives the window through its own public signals (node_clicked ->
## node_allocated/keystone_unlocked), handles them exactly the way
## World._on_skill_node_allocated/_on_skill_keystone_unlocked do, and reads the
## result back off the window's own web view rather than off Player alone.

const PlayerScene = preload("res://scenes/player.tscn")
const SkillTreeWindow = preload("res://scenes/skill_tree_window.gd")
const SkillWebView = preload("res://scenes/skill_web_view.gd")
const SkillWeb = preload("res://src/gameplay/skill_web.gd")
const KeystonePassive = preload("res://src/gameplay/keystone_passive.gd")

var player: Player
var window: SkillTreeWindow
var web := SkillWeb.new()


func before_each():
	player = PlayerScene.instantiate()
	add_child(player)
	window = SkillTreeWindow.new()
	add_child(window)
	# The same two calls World._refresh_skill_window makes, and the same two
	# signal routes World._build_skill_window wires to the local Player --
	# see those functions' own doc comments in scenes/world.gd.
	window.node_allocated.connect(func(node_id):
		if player.allocate_skill(node_id):
			_sync_window())
	window.keystone_unlocked.connect(func(keystone_id):
		if player.unlock_keystone(keystone_id):
			_sync_window())


func after_each():
	remove_child(player)
	player.free()
	remove_child(window)
	window.free()


func _sync_window() -> void:
	window.configure_web(player.skill_web, player.character_class, player.dna_resonance,
		player.dna_seed)
	window.refresh(player.experience.unspent_points, player.allocated_nodes,
		player.unlocked_keystones)


# --- XP, from a real action, actually reaches a spendable point -----------

## Player.XP_PER_KILL is exactly what _perform_attack awards per killing blow
## against a level-1 creature (see that function's own comment) -- a handful
## of real kills, not a lump sum invented for this test. None of
## test_player_skill_web.gd's tests ever call gain_experience at all; they all
## seed unspent_points directly through the _with_points() shortcut.
func test_a_handful_of_real_kills_worth_of_xp_grants_a_spendable_point():
	player.apply_class("warrior", {})
	assert_eq(player.experience.unspent_points, 0)

	for i in 5:
		player.gain_experience(Player.XP_PER_KILL)

	assert_gt(player.experience.unspent_points, 0,
		"a handful of real kills should have crossed at least one level")


# --- unlock -> the WINDOW (not just Player) reflects it --------------------

func test_clicking_a_takeable_node_in_the_window_allocates_it_on_the_real_player_and_the_window_shows_it_owned():
	player.apply_class("warrior", {})
	player.gain_experience(9999)
	_sync_window()
	var target: String = web.nodes_in_ring("warrior", 1)[0]
	assert_eq(window.web_view.state_of(target), SkillWebView.STATE_TAKEABLE,
		"test setup: the target node should read as takeable before the click")

	window.web_view.click_at(window.web_view.world_to_view(web.position_of(target)))

	assert_true(player.allocated_nodes.get(target, false),
		"the click should have reached Player.allocate_skill through the real signal chain")
	assert_eq(window.web_view.state_of(target), SkillWebView.STATE_ALLOCATED,
		"the window's own web view should now show this node as owned, not just Player")


## The keystone half of the same loop, plus the stat payoff docs/concept/
## skills.md and progression.md both call for: a keystone_passive.gd effect
## observably applied to the player, not just a flag going true.
func test_clicking_a_keystone_in_the_window_unlocks_it_on_the_player_shows_it_owned_and_grants_its_real_bonus():
	player.apply_class("warrior", {})
	player.gain_experience(9999)
	_sync_window()
	for node_id in ["vitality_1", "vitality_2", "juggernaut"]:
		window.web_view.click_at(window.web_view.world_to_view(web.position_of(node_id)))
	assert_true(player.allocated_nodes.get("juggernaut", false),
		"test setup: the path to iron_skin should already be walked")
	var before_health := player.max_health
	var granted: float = KeystonePassive.new().bonus_for("iron_skin")["bonus_amount"]
	assert_eq(window.web_view.state_of("iron_skin"), SkillWebView.STATE_TAKEABLE,
		"test setup: iron_skin should read as takeable once its path and gate are met")

	window.web_view.click_at(window.web_view.world_to_view(web.position_of("iron_skin")))

	assert_true(player.unlocked_keystones.get("iron_skin", false),
		"the click should have reached Player.unlock_keystone through the real signal chain")
	assert_eq(window.web_view.state_of("iron_skin"), SkillWebView.STATE_ALLOCATED,
		"the window has to show the keystone as owned once unlocked")
	assert_almost_eq(player.max_health, before_health + granted, 0.001,
		"iron_skin's own real bonus_amount has to land on the live character, not just flip a flag")
