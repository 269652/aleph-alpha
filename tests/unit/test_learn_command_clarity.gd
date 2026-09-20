extends GutTest

## `/learn` -- the player's access path to a mage guild's tuition
## (docs/concept/magic.md's 2026-09-19 section). No argument lists what a
## guild in reach would teach and what each lesson costs; an argument takes
## that lesson.
##
## There is no guild interaction UI yet (the doc names that as an open gap),
## so this is the honest first hand on the mechanic -- the same "a real
## command before a real UI" scope `/gold` and `/craft` already established.
##
## Pinned from source text rather than by driving a real World node (needs a
## full chunk manager, see test_earth_chunk_manager.gd's runtime), the same
## shape as test_mushroom_command_clarity.gd.

const SpellTuition = preload("res://src/gameplay/spell_tuition.gd")


func _source() -> String:
	return FileAccess.get_file_as_string("res://scenes/world.gd")


func _learn_command_body() -> String:
	var source := _source()
	var start := source.find("func _handle_learn_command(")
	assert_gt(start, -1, "World._handle_learn_command should still exist")
	var end := source.find("\nfunc ", start + 1)
	if end == -1:
		end = source.length()
	return source.substr(start, end - start)


func test_the_command_is_registered_in_the_dispatch_table():
	var source := _source()
	var match_start := source.find("func _on_console_command(")
	assert_gt(match_start, -1, "World._on_console_command should still exist")
	var match_end := source.find("\nfunc ", match_start + 1)
	var dispatch := source.substr(match_start, match_end - match_start)
	assert_string_contains(dispatch, "\"learn\":")
	assert_string_contains(dispatch, "_handle_learn_command(args, local_player)")


func test_the_help_text_mentions_the_command():
	var source := _source()
	var help_start := source.find("Commands: /day")
	assert_gt(help_start, -1, "the help text should still start with /day")
	var help_end := source.find(")", help_start)
	var help := source.substr(help_start, help_end - help_start)
	assert_string_contains(help, "/learn")


## The real logic lives in SpellTuition (its own tests pin the price, the
## refusal order and the conserving spend) reached through Player.learn_spell
## -- this command must call through to it, never price or gate a lesson
## itself.
func test_the_command_calls_through_to_the_players_own_learn():
	var body := _learn_command_body()
	assert_string_contains(body, "learn_spell(")


func test_the_listing_quotes_the_guilds_own_price():
	# "come back with 40 more gold" needs a player who was told the price
	# first, so a bare /learn has to be a real price list.
	var body := _learn_command_body()
	assert_string_contains(body, "tuition_for(")
	assert_string_contains(body, "spells_a_guild_would_teach(")


## A refusal is the feature (magic.md): the command must report WHICH gate
## refused, not a bare "no". Matched on SpellTuition's own constants rather
## than on copies of their string values, so the reason vocabulary has one
## statement -- and checked against the real constant map, so a typo in a
## match arm cannot quietly pass this.
func test_the_command_reports_every_refusal_reason_by_name():
	var body := _learn_command_body()
	var constants: Dictionary = (SpellTuition as GDScript).get_script_constant_map()
	for reason_name in ["UNKNOWN_SPELL", "OUTSIDE", "ALREADY_KNOWN", "NO_MASTER", "CANNOT_AFFORD"]:
		assert_true(constants.has(reason_name), "SpellTuition.%s must exist" % reason_name)
		assert_string_contains(body, "SpellTuition.%s" % reason_name)


## "come back with 40 more gold", never a bare "you can't" -- the money
## branch has to read the price AND the shortfall the refusal carries.
func test_the_money_refusal_quotes_both_the_price_and_the_shortfall():
	var body := _learn_command_body()
	assert_string_contains(body, '"tuition"')
	assert_string_contains(body, '"short"')


## The standing refusal points at the charter ladder by naming the building
## a city has to be big enough to raise.
func test_the_standing_refusal_names_the_building_the_charter_gates():
	var body := _learn_command_body()
	assert_string_contains(body, '"building_id"')
	assert_string_contains(body, "SpellTuition.GUILD_BUILDING_ID")


## "Nobody here teaches that" is the refusal that turns into a reason to
## travel, so it has to name the tradition and the depth to look for.
func test_the_no_master_refusal_names_the_school_and_the_depth():
	var body := _learn_command_body()
	assert_string_contains(body, '"school"')
	assert_string_contains(body, '"depth"')


## An apprenticeship is to a person: the listing names who is in the room
## and a landed lesson names who gave it.
func test_the_command_names_the_masters_rather_than_the_building():
	var body := _learn_command_body()
	assert_string_contains(body, "masters_here(")
	assert_string_contains(body, "MageMaster.display_name_for(")


func test_the_command_needs_a_local_player_like_every_other_one():
	var body := _learn_command_body()
	assert_string_contains(body, "local_player == null")
