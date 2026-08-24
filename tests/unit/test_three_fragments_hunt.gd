extends GutTest

## ThreeFragmentsHunt (docs/concept/easter_eggs.md's "Three Fragments -- a
## hunt about the hunt"): the pure aggregation logic over the three source
## eggs' own found-signals -- AncientTerminal.has_been_found(),
## SignedSecretRoom.has_been_found(), WarGamesResponse.has_been_found() (via
## World's own forwarding getters). Deliberately takes plain booleans, not
## those three modules themselves, so it is testable fully independently of
## them -- the same "pure decision module, caller supplies the real
## primitive" shape KrakenTrigger/BridgekeeperEncounter already use.
##
## should_trigger latches permanently via mark_triggered -- true exactly once,
## the moment all three are first held together, never again afterwards, so a
## caller polling this every frame doesn't re-fire the bonus every frame the
## player still happens to be holding all three.

const ThreeFragmentsHunt = preload("res://src/gameplay/three_fragments_hunt.gd")

var hunt: ThreeFragmentsHunt


func before_each():
	hunt = ThreeFragmentsHunt.new()


func test_has_all_fragments_false_with_none():
	assert_false(hunt.has_all_fragments(false, false, false))


func test_has_all_fragments_false_with_only_two():
	assert_false(hunt.has_all_fragments(true, true, false))


func test_has_all_fragments_true_with_all_three():
	assert_true(hunt.has_all_fragments(true, true, true))


func test_should_trigger_false_until_all_three_are_held():
	assert_false(hunt.should_trigger(true, true, false))
	assert_false(hunt.should_trigger(true, false, true))
	assert_false(hunt.should_trigger(false, true, true))


func test_should_trigger_true_the_moment_all_three_are_held():
	assert_true(hunt.should_trigger(true, true, true))


func test_not_triggered_until_marked():
	assert_false(hunt.has_triggered())


func test_mark_triggered_latches_true():
	hunt.mark_triggered()
	assert_true(hunt.has_triggered())


## Once latched, should_trigger never fires again -- holding all three
## doesn't re-grant the bonus every frame it's polled.
func test_should_trigger_false_after_already_triggered():
	hunt.mark_triggered()
	assert_false(hunt.should_trigger(true, true, true))


func test_bonus_message_is_a_real_nonempty_line():
	assert_true(hunt.bonus_message().length() > 0)


## Homage over reproduction (pillar 4): the payoff is this project's own
## original flavor moment, not a reference to Ready Player One's own Copper/
## Jade/Crystal Keys or "Easter egg" language lifted from the film/book.
func test_bonus_message_does_not_reference_rp1s_own_key_names():
	var line: String = hunt.bonus_message().to_lower()
	var forbidden_phrases := ["copper key", "jade key", "crystal key", "oasis", "halliday"]
	for phrase in forbidden_phrases:
		assert_false(line.contains(phrase), "should not reference: %s" % phrase)


func test_fragment_and_bonus_item_ids_are_distinct_nonempty_strings():
	var ids := [
		ThreeFragmentsHunt.TERMINAL_FRAGMENT_ITEM_ID,
		ThreeFragmentsHunt.SECRET_ROOM_FRAGMENT_ITEM_ID,
		ThreeFragmentsHunt.WARGAMES_FRAGMENT_ITEM_ID,
		ThreeFragmentsHunt.BONUS_ITEM_ID,
	]
	for id in ids:
		assert_true(String(id).length() > 0)
	assert_eq(ids.size(), 4)
	var unique := {}
	for id in ids:
		unique[id] = true
	assert_eq(unique.size(), 4, "all four item ids should be distinct")
