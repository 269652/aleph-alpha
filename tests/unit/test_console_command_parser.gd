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
