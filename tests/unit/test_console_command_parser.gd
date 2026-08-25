extends GutTest

const ConsoleCommandParser = preload("res://src/gameplay/console_command_parser.gd")

var parser := ConsoleCommandParser.new()


func test_parses_a_bare_command_with_no_args():
	var result := parser.parse("/day")
	assert_eq(result.command, "day")
	assert_eq(result.args, [])


func test_parses_a_command_with_args():
	var result := parser.parse("/spawn boar 3")
	assert_eq(result.command, "spawn")
	assert_eq(result.args, ["boar", "3"])


func test_leading_slash_is_optional():
	var result := parser.parse("day")
	assert_eq(result.command, "day")


func test_command_is_case_insensitive():
	var result := parser.parse("/DAY")
	assert_eq(result.command, "day")


func test_collapses_extra_whitespace_between_args():
	var result := parser.parse("  /give   iron_axe   1  ")
	assert_eq(result.command, "give")
	assert_eq(result.args, ["iron_axe", "1"])


func test_empty_input_parses_to_an_empty_command():
	var result := parser.parse("")
	assert_eq(result.command, "")
	assert_eq(result.args, [])


func test_whitespace_only_input_parses_to_an_empty_command():
	var result := parser.parse("   ")
	assert_eq(result.command, "")
	assert_eq(result.args, [])


## Reported live: the FIRST command of every session failed. The console
## toggle is bound by PHYSICAL keycode, and on a German layout the physical
## key left of "1" is the "^" DEAD key -- Windows emits nothing when it is
## pressed, buffers it, and emits it together with the NEXT keystroke, i.e.
## after DevConsole.toggle() has already cleared and focused the input field.
## The exact observed line was "^/spawn boar 2".
func test_a_dead_key_character_before_the_slash_is_ignored():
	var result := parser.parse("^/spawn boar 2")
	assert_eq(result.command, "spawn")
	assert_eq(result.args, ["boar", "2"])


## The leading "/" is optional (see test_leading_slash_is_optional), so the
## dead key can also end up glued straight onto a bare command name.
func test_leading_junk_is_ignored_even_without_a_slash():
	var result := parser.parse("^day")
	assert_eq(result.command, "day")


## A dead key that does not compose with the next character can also come out
## as its own token before the command.
func test_leading_junk_separated_by_a_space_is_ignored():
	var result := parser.parse("^ /day")
	assert_eq(result.command, "day")
	assert_eq(result.args, [])


## Junk with no command behind it must collapse onto the existing
## empty-command contract rather than dispatching a garbage command name.
func test_junk_only_input_parses_to_an_empty_command():
	var result := parser.parse("^^")
	assert_eq(result.command, "")
	assert_eq(result.args, [])


## ANTI-SWALLOW GUARD (green before and after): the strip only ever drops a
## LEADING run, so punctuation anywhere else -- here a "/" inside an argument
## -- must survive untouched.
func test_a_slash_inside_an_argument_is_left_alone():
	var result := parser.parse("/journal npc:1/2")
	assert_eq(result.command, "journal")
	assert_eq(result.args, ["npc:1/2"])


## ANTI-SWALLOW GUARD (green before and after): arguments may legitimately
## BEGIN with punctuation (a negative amount), and only the first token is
## ever inspected, so they must come through byte-for-byte.
func test_an_argument_starting_with_punctuation_is_left_alone():
	var result := parser.parse("/gold -25")
	assert_eq(result.command, "gold")
	assert_eq(result.args, ["-25"])
