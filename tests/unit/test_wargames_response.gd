extends GutTest

## WarGamesResponse (docs/concept/easter_eggs.md's WarGames secret console
## command): a single, original, deadpan homage line printed by the hidden
## `/globalthermonuclearwar` console command (scenes/world.gd's dispatcher,
## never listed in /help). The film's own dialogue is Copyrighted text this
## project must not quote (docs/concept/easter_eggs.md pillar 4 -- "homage
## over reproduction") -- these tests pin both "there is a real line" and
## "that line is not a transcript of the film's own famous lines", so the
## no-quoting rule stays enforced by something stronger than a comment.

const WarGamesResponse = preload("res://src/gameplay/wargames_response.gd")

var response: WarGamesResponse


func before_each():
	response = WarGamesResponse.new()


func test_response_line_is_a_real_nonempty_line():
	assert_true(response.response_line().length() > 0)


func test_response_line_is_deterministic():
	assert_eq(response.response_line(), response.response_line())


## Homage, not reproduction: must not contain the film's own famous lines
## (verbatim or near-verbatim), case-insensitively.
func test_response_line_does_not_quote_the_films_famous_dialogue():
	var line: String = response.response_line().to_lower()
	var forbidden_phrases := [
		"shall we play a game",
		"the only winning move",
		"a strange game",
		"how about a nice game of chess",
	]
	for phrase in forbidden_phrases:
		assert_false(line.contains(phrase), "should not quote: %s" % phrase)
