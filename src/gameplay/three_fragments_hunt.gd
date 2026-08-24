extends RefCounted

## "Three Fragments -- a hunt about the hunt" (docs/concept/easter_eggs.md):
## the honest way to honor RP1's whole three-key, three-gate structure
## without copying its specific invented content (the Copper/Jade/Crystal
## Keys are the book's own plot, not just "80s culture" the way WarGames or
## Zork are) is an ORIGINAL three-stage hunt built out of eggs already on
## this project's list -- the signed secret room (Atari *Adventure* homage),
## the Zork-homage ancient terminal, and the WarGames secret console command
## each quietly leave behind one small, unremarkable "fragment" item, no
## fanfare. Holding all three at once triggers one final bonus discovery.
##
## PURE AGGREGATION LOGIC ONLY: this module takes plain booleans ("does the
## player currently hold each fragment"), never AncientTerminal/
## SignedSecretRoom/WarGamesResponse (or Inventory/Item) themselves -- the
## same "caller supplies the real primitive, module only decides" shape
## KrakenTrigger/BridgekeeperEncounter already use elsewhere in this family.
## That keeps this module fully testable independent of the three source
## eggs, per this stage's own task ("tested independently of the three
## source eggs"). scenes/world.gd is the one place that actually reads
## Player.inventory.has(...) for each fragment id and feeds the three
## resulting bools in here.
##
## GRANTING THE FRAGMENTS is NOT this module's job -- world.gd grants each
## fragment item (via ItemCatalog + Player.inventory.add) the FIRST time each
## source egg's own has_been_found() flips from false to true, mirroring
## "no fanfare, easy to miss the significance of any one": a fragment is
## just another inert item that happens to land in the pack alongside
## whatever else that egg already does (the terminal's prose, the secret
## room's credit banner, the WarGames response line) -- nothing marks it as
## special at the moment it's granted. This module only decides once all
## three fragments are simultaneously held.
##
## THE FINAL BONUS DISCOVERY -- the doc leaves this deliberately open ("TBD
## what... deliberately left open, ... whoever implements this gets to
## invent the actual payoff"). The creative call made here: the three
## fragments -- individually inert junk with no visible connection to each
## other -- turn out to physically interlock, and the joined piece carries
## one line scratched on its underside, echoing (at the meta level) the
## exact gesture the signed secret room itself pays tribute to: a quiet,
## personal signature left for whoever is thorough enough to notice. It's
## the collection's own hunt rewarding the *player specifically* for
## completing it, the same way Robinett's original room rewarded whoever
## found it -- an homage to the shape of that gesture, not a copy of RP1's
## invented Key/OASIS content (enforced by this module's own "does not
## reference RP1's own key names" test). Still zero mechanical weight
## (pillar 2): BONUS_ITEM_ID is exactly as inert as the three fragments that
## produce it, and BONUS_MESSAGE is pure flavor text, nothing else.
##
## should_trigger() latches permanently via mark_triggered() -- true exactly
## once, the instant all three fragments are first held together, and never
## again afterwards even if world.gd polls this every frame while the
## player keeps carrying all three (the same "check before, poll after"
## latch shape AncientTerminal/SignedSecretRoom/WarGamesResponse's own
## has_been_found()/mark_found() already use).

## item_id for each of the three fragments -- see item_catalog.gd's own
## entries for display name/kind (all "material", zero weapon_damage/mass:
## purely inert, matching this whole family's "zero mechanical weight"
## design pillar).
const TERMINAL_FRAGMENT_ITEM_ID := "terminal_fragment"
const SECRET_ROOM_FRAGMENT_ITEM_ID := "secret_room_token"
const WARGAMES_FRAGMENT_ITEM_ID := "wargames_punch_card"

## item_id for the one-time bonus item granted the moment all three
## fragments are first held together (see this module's own doc comment for
## why this specific payoff was chosen).
const BONUS_ITEM_ID := "curious_keepsake"

const BONUS_MESSAGE := "Three unremarkable scraps -- a shard of circuit board, a tarnished token, a scorched punch card -- turn out, in your hands, to interlock at the edges. Nothing happens. But on the underside of the joined piece, scratched by someone who never expected it to be read: \"you weren't supposed to find all three. nice work.\""

var _triggered := false


## True the moment every one of the three fragments is represented -- pure
## boolean AND, no state, no memory of what happened before this call.
func has_all_fragments(
	has_terminal_fragment: bool, has_secret_room_fragment: bool, has_wargames_fragment: bool
) -> bool:
	return has_terminal_fragment and has_secret_room_fragment and has_wargames_fragment


## True exactly once -- the first call where has_all_fragments would be true
## AND the bonus hasn't already fired. False before that (missing at least
## one fragment) and false after (already latched via mark_triggered), so a
## caller can safely call this every frame without re-granting the bonus
## every frame the player still happens to be carrying all three.
func should_trigger(
	has_terminal_fragment: bool, has_secret_room_fragment: bool, has_wargames_fragment: bool
) -> bool:
	if _triggered:
		return false
	return has_all_fragments(has_terminal_fragment, has_secret_room_fragment, has_wargames_fragment)


func mark_triggered() -> void:
	_triggered = true


func has_triggered() -> bool:
	return _triggered


## The bonus discovery's flavor text (see this module's own doc comment for
## why this specific payoff was chosen) -- the caller (scenes/world.gd)
## displays this however fits its own UI, reusing the same on-screen banner
## every other cameo in this doc uses.
func bonus_message() -> String:
	return BONUS_MESSAGE
