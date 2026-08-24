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

var _found := false


## The one deadpan line printed back by /globalthermonuclearwar.
func response_line() -> String:
	return RESPONSE_LINE


## "Found" state: has_been_found()/mark_found() are the same clean, testable
## boolean signal AncientTerminal/SignedSecretRoom already expose for
## docs/concept/easter_eggs.md's "Three Fragments" hunt to check "has the
## player triggered the WarGames egg" against -- this module only exposes
## the signal; it does not decide what a later system does with it (no
## fragment item, no bonus trigger here; see scenes/world.gd's own
## forwarding getter, has_found_wargames_egg).
func mark_found() -> void:
	_found = true


func has_been_found() -> bool:
	return _found
