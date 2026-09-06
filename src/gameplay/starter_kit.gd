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
	# Reported: "give the player a glass bottle and butterfly net from the
	# start" -- added here too so a player who picks their own kit can
	# still choose the capture DSL's catch/release/bottle loop
	# (docs/concept/capture_dsl.md) on purpose, the same discoverability
	# reasoning fishing_rod already had.
	"butterfly_net", "glass_bottle",
]

const MAX_CHOICES := 3

## Always-valid, per main_menu.gd's own "_selected_class defaults to
## warrior" convention: a player who never opens this tab still starts a
## real, coherent kit rather than being blocked or spawning empty-handed.
## fishing_rod specifically preserves the OLD fixed kit's exact "discover
## the fishing loop" intent for that untouched-default case; stone_pickaxe
## keeps mining reachable (Player._pickaxe_power()'s own doc comment: a
## pickaxe mines ore, anything else has ZERO mining power -- a hard gate,
## not a soft one, so this item can't be the one that moves).
##
## iron_axe, not crude_blade (2026-09-06, see docs/concept/starting_kit.md's
## "The default couldn't chop wood"): reported directly, "now I can't fell
## any trees anymore" -- traced to a real player's own live save, Starting
## Kit tab never opened, holding crude_blade (a sword: MaterialDamage's
## 0.5x wood) because it was the default's only WEAPON-kind item and
## Player.grant_starter_items auto-equips the first one of those it finds.
## iron_axe carries the real 3.0x wood multiplier AND, being kind: "tool"
## rather than "weapon", is now the first TOOL-kind entry instead -- so the
## do-nothing default auto-equips it exactly the same way. Combat trades
## down (no weapon-kind item left in the default at all, so a do-nothing
## player fights at UNARMED_DAMAGE times the axe's own 0.8x flesh
## multiplier rather than crude_blade's real weapon_damage) -- accepted:
## wood-chopping is this game's far larger, more central ongoing mechanic,
## and real combat gear is still one Starting Kit tab away for anyone who
## wants it. Still exactly MAX_CHOICES (3) entries.
const DEFAULT_CHOICES := ["iron_axe", "stone_pickaxe", "fishing_rod"]


static func is_valid_choice(item_id: String) -> bool:
	return POOL.has(item_id)
