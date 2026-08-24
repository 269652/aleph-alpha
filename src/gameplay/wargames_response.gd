extends RefCounted

## Pure flavor content for docs/concept/easter_eggs.md's WarGames Easter
## egg: a hidden `/globalthermonuclearwar` console command (scenes/world.gd's
## dispatcher, never listed in /help -- see console_command_parser.gd for
## the parse-then-dispatch shape every secret console command reuses).
##
## RP1's Halliday is explicitly obsessed with the 1983 film; its most famous
## line is cultural shorthand at this point, not something that needs
## quoting to reference (docs/concept/easter_eggs.md's own words). The
## film's actual dialogue is copyrighted text this project must not
## reproduce (pillar 4, "homage over reproduction") -- RESPONSE_LINE below
## is fully original wording that nods at the premise (a war-game simulation
## concluding the sensible move is not to play it) without quoting the
## film, enforced by test_wargames_response.gd's own "does not contain the
## film's famous lines" check rather than left as an unverified comment.

const RESPONSE_LINE := "SYSTEM: Simulating global thermonuclear war... complete. Every scenario ends the same way. Recommendation: close this terminal and go outside."


## The one deadpan line printed back by /globalthermonuclearwar.
func response_line() -> String:
	return RESPONSE_LINE
