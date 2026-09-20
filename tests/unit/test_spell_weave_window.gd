extends GutTest

## docs/concept/spell_weaving.md: the surface a player arranges motes on.
## The header rewrites itself as they drag, so the consequence of an
## arrangement is visible before it is committed -- the whole of what makes
## composition a craft rather than a form.
##
## Same "toggle window, built in code, tested post-hoc" pattern
## CraftingWindow / QuestLogWindow / ConversationWindow already use.

const SpellWeaveWindow = preload("res://scenes/spell_weave_window.gd")
const SpellDraft = preload("res://src/gameplay/spell_draft.gd")

var window: SpellWeaveWindow


func before_each():
	window = SpellWeaveWindow.new()
	add_child(window)


func after_each():
	window.free()


func _open_with(motes: Dictionary, draft: Dictionary = {}) -> void:
	window.refresh(motes, draft)


# -- the pouch ----------------------------------------------------------

func test_an_empty_pouch_says_so_rather_than_showing_an_empty_box():
	_open_with({})
	assert_string_contains(window.pouch_text().to_lower(), "no")


func test_the_pouch_lists_what_is_owned_with_its_count():
	_open_with({"fire_damage": 2, "ignite": 1})
	var text := window.pouch_text()
	assert_string_contains(text, "2")
	assert_string_contains(text.to_lower(), "fire")


# -- the sockets and the live header ------------------------------------

func test_an_empty_weave_offers_no_spell_and_says_why():
	_open_with({"fire_damage": 1})
	assert_string_contains(window.header_text().to_lower(), "socket")


func test_socketing_a_mote_names_the_spell_and_prices_it():
	_open_with({"fire_damage": 1}, SpellDraft.make(["fire_damage"], "projectile"))
	var header := window.header_text()
	assert_string_contains(header, SpellDraft.name_for(SpellDraft.make(["fire_damage"], "projectile")))
	assert_string_contains(header.to_lower(), "mana")


## The point of order being load-bearing: the header must visibly change
## when two motes are swapped, or the craft is invisible.
func test_swapping_two_motes_changes_what_the_header_says():
	var one := SpellDraft.make(["fire_damage", "frost_damage"], "projectile")
	var other := SpellDraft.make(["frost_damage", "fire_damage"], "projectile")
	_open_with({"fire_damage": 1, "frost_damage": 1}, one)
	var first := window.header_text()
	_open_with({"fire_damage": 1, "frost_damage": 1}, other)
	assert_ne(first, window.header_text(), "the order is the craft, so it must read differently")


func test_a_reacting_pair_is_named_in_the_header():
	var draft := SpellDraft.make(["fire_damage", "ignite"], "projectile")
	var reactions: Array = SpellDraft.reactions_of(draft)
	if reactions.is_empty():
		pass_test("this pair does not react in the current table")
		return
	_open_with({"fire_damage": 1, "ignite": 1}, draft)
	assert_string_contains(
		window.header_text().to_lower(),
		String(reactions[0].get("epithet", "")).to_lower()
	)


# -- committing it ------------------------------------------------------

func test_pressing_weave_asks_for_the_draft_on_screen():
	var draft := SpellDraft.make(["fire_damage"], "projectile")
	_open_with({"fire_damage": 1}, draft)
	var asked: Array = []
	window.weave_requested.connect(func(d): asked.append(d))
	window.request_weave()
	assert_eq(asked.size(), 1)
	assert_eq(SpellDraft.atoms_of(asked[0]), ["fire_damage"])


func test_an_empty_draft_cannot_be_committed():
	_open_with({"fire_damage": 1})
	var asked: Array = []
	window.weave_requested.connect(func(d): asked.append(d))
	window.request_weave()
	assert_eq(asked.size(), 0, "there is nothing to weave")


func test_the_window_opens_and_closes():
	assert_false(window.is_open())
	window.toggle()
	assert_true(window.is_open())
	window.toggle()
	assert_false(window.is_open())
