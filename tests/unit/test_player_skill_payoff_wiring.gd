extends GutTest

## Three wedges of the skill web that bought nothing
## (docs/concept/skill_payoff.md).
##
## Measured there, and still true: the web grants 26 distinct stat keys and
## the running game reads five of them. `Player._apply_skill_stat` has
## exactly two branches -- `max_health` and `attack_damage` -- and the other
## twenty-one keys are summed faithfully into `Player.skill_bonus` and read
## by nothing.
##
## Two of them are the cheapest wins in the whole table, and the doc says so
## itself:
##
## - **`spell_efficiency`** (3 nodes). `SpellExecutor.cost_for(rule,
##   governing_stat)` really takes the stat and really discounts the cost
##   through `SpellCost.efficiency` -- and `Player`'s cast sites called
##   `cost_for(rule)` and let the argument default to 0.0. The consumer
##   existed; the argument did not.
## - **`max_mana`** (6 nodes, more than any other key in the web). Nothing
##   added it to anything, so every point a mage spent on their own resource
##   pool did nothing at all.

const PlayerScene = preload("res://scenes/player.tscn")
const SpellBook = preload("res://src/gameplay/spell_book.gd")
const SpellExecutor = preload("res://src/gameplay/spell_executor.gd")
const NodePayoff = preload("res://src/gameplay/node_payoff.gd")

var player


func before_each():
	player = PlayerScene.instantiate()
	add_child(player)
	player.max_mana = 50.0
	player.mana = player.max_mana


func after_each():
	player.queue_free()


func _fire_bolt_rule() -> Dictionary:
	var executor := SpellExecutor.new()
	return executor.cast_rule(SpellBook.new().ast_for("fire_bolt"))


# -- the pool a mage buys -------------------------------------------------

func test_a_point_in_max_mana_really_deepens_the_pool():
	var before: float = player.max_mana
	player._apply_skill_stat("max_mana", 20.0)
	assert_almost_eq(player.max_mana, before + 20.0, 0.0001)


## And it fills what it added, the same courtesy `max_health` already pays:
## a node that raised your ceiling and left you short of it would read as a
## downgrade.
func test_deepening_the_pool_fills_what_it_added():
	player.mana = player.max_mana
	player._apply_skill_stat("max_mana", 20.0)
	assert_almost_eq(player.mana, player.max_mana, 0.0001)


## But it never overfills a character who was already spent.
func test_it_does_not_top_up_a_drained_mage():
	player.mana = 0.0
	player._apply_skill_stat("max_mana", 20.0)
	assert_almost_eq(player.mana, 20.0, 0.0001, "the new headroom, not a free refill")


# -- the discount a mage buys ---------------------------------------------

## The function has always taken the stat. The cast site never passed it.
func test_the_cast_site_passes_the_efficiency_the_character_bought():
	var rule := _fire_bolt_rule()
	var executor := SpellExecutor.new()
	assert_lt(
		executor.cost_for(rule, 1.0), executor.cost_for(rule, 0.0),
		"precondition: the consumer really discounts"
	)
	for name in ["cast_spell", "cast_woven"]:
		var body := _function_body(name)
		assert_false(body.is_empty(), "precondition: %s was found" % name)
		assert_true(
			body.contains('cost_for(rule, skill_bonus("spell_efficiency"))'),
			"%s must pay the price this character actually pays" % name
		)


## Through the real cast, not the source: a character with the stat spends
## less of their own pool on the same spell.
func test_a_trained_mage_spends_less_mana_on_the_same_spell():
	player.mana = player.max_mana
	assert_true(player.cast_spell("fire_bolt"))
	var plain: float = player.max_mana - player.mana

	var trained = PlayerScene.instantiate()
	add_child(trained)
	trained.max_mana = 50.0
	trained.mana = trained.max_mana
	# The real allocation, through the web's own node: `focus_1` is the
	# Mage wedge's first ring-one focus node and it grants spell_efficiency.
	trained.allocated_nodes["focus_1"] = true
	assert_gt(
		trained.skill_bonus("spell_efficiency"), 0.0,
		"precondition: the node really grants the stat"
	)
	assert_true(trained.cast_spell("fire_bolt"))
	var discounted: float = trained.max_mana - trained.mana
	trained.queue_free()

	assert_gt(plain, 0.0, "precondition: casting really costs something")
	assert_lt(discounted, plain, "the three nodes a mage spent must buy something")


# -- and the tooltip stops calling them declared --------------------------

## `NodePayoff` renders a stat nothing reads as *declared*, and
## `test_node_payoff.gd` holds its lists against what `scenes/player.gd`
## really does. Wiring a stat without moving it is the lie in the other
## direction.
func test_the_payoff_table_counts_both_as_wired():
	assert_true(NodePayoff.WIRED_STATS.has("spell_efficiency"))
	assert_true(NodePayoff.WIRED_STATS.has("max_mana"))


func _function_body(name: String) -> String:
	var source := FileAccess.get_file_as_string("res://scenes/player.gd")
	var start := source.find("func %s(" % name)
	if start < 0:
		return ""
	var rest := source.substr(start)
	var next := rest.find("\nfunc ")
	return rest if next < 0 else rest.substr(0, next)
