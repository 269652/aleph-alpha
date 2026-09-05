extends RefCounted

## The curated pool a new player picks MAX_CHOICES starting items from at
## character creation (see docs/concept/starting_kit.md for the full
## rationale, including why Torch and three of the four taming tools were
## considered and cut). Mirrors class_archetype.gd's own shape exactly:
## flat consts, a couple of pure query functions, zero UI/blurb text -- that
## lives in main_menu.gd (STARTER_ITEM_BLURBS), the same split CLASS_BLURBS
## already uses for classes.

const POOL := [
	"wooden_club", "crude_blade", "stone_pickaxe", "fishing_rod",
	"lasso", "rough_compass", "iron_sword", "iron_axe",
]

const MAX_CHOICES := 3

## Always-valid, per main_menu.gd's own "_selected_class defaults to
## warrior" convention: a player who never opens this tab still starts a
## real, coherent kit rather than being blocked or spawning empty-handed.
## Three distinct early paths (combat / mining / fishing), and fishing_rod
## specifically preserves the OLD fixed kit's exact "discover the fishing
## loop" intent for that untouched-default case.
const DEFAULT_CHOICES := ["crude_blade", "stone_pickaxe", "fishing_rod"]


static func is_valid_choice(item_id: String) -> bool:
	return POOL.has(item_id)
