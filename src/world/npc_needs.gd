extends RefCounted

## An NPC's hunger need (docs/concept/npc.md "Needs and the local production
## economy": "NPCs get real hunger, not just villagers-as-scenery. Same
## shape as creature_needs.gd (hunger rises per second, is_hungry(),
## feed())").
##
## This used to be a standalone copy of CreatureNeeds' shape. Since
## docs/concept/ethogram.md slice 3 it is a FACADE over the one drive clock
## every animal shares (Drives) with the villager profile from the ethogram
## (Ethogram.drive_profile("", "villager")): the same pace as any other
## creature in this world -- a villager runs on the same lived-experience
## clock rather than a separately-tuned NPC one -- and hunger only, because
## the spec's own scope is hunger and thirst has no villager-side consumer;
## simulating an unused thirst would misrepresent what this pass does. The
## API is unchanged for NpcEconomy/NpcMarker and every test; the numbers
## below are re-exported from the profile for callers that read them.

const Drives = preload("res://src/gameplay/drives.gd")
const Ethogram = preload("res://src/gameplay/ethogram.gd")

const BODY_PLAN := "villager"

## Per-simulated-second rise rate -- verified behaviorally
## (test_becomes_hungry_once_past_the_threshold), not by asserting the number.
static var HUNGER_RATE_PER_SECOND: float = (
	1.0 / float(Ethogram.drive_profile("", BODY_PLAN)[Ethogram.DRIVE_HUNGER]["rise_seconds"])
)

## An NPC actively seeks food (buys from the village market, or self-feeds
## if a producer -- see NpcEconomy) once hunger passes this fraction.
static var HUNGRY_THRESHOLD: float = float(
	Ethogram.drive_profile("", BODY_PLAN)[Ethogram.DRIVE_HUNGER]["threshold"]
)

## How far into its own hunger cycle a freshly-created NPC starts, at most:
## below HUNGRY_THRESHOLD (no NPC spawns already starving), high enough that
## a village's onsets spread across the run-up instead of every villager
## queuing at the market on the same tick.
static var START_STAGGER: float = float(
	Ethogram.drive_profile("", BODY_PLAN)[Ethogram.DRIVE_HUNGER]["stagger"]
)

var _drives: Drives

var hunger: float:
	get:
		return _drives.level(Ethogram.DRIVE_HUNGER)
	set(value):
		_drives.levels[Ethogram.DRIVE_HUNGER] = clampf(value, 0.0, 1.0)


## `seed_value` staggers where this individual starts in its own hunger
## cycle -- see START_STAGGER. Defaults to 0 (exactly empty start) so a
## caller that doesn't care keeps the simplest behavior.
func _init(seed_value: int = 0) -> void:
	_drives = Drives.new(Ethogram.drive_profile("", BODY_PLAN), seed_value)


func advance(delta_seconds: float) -> void:
	_drives.advance(delta_seconds)


func is_hungry() -> bool:
	return _drives.is_urgent(Ethogram.DRIVE_HUNGER)


func feed() -> void:
	_drives.satisfy(Ethogram.DRIVE_HUNGER)


## The need as the behaviour kernel's gate (Drives.gains).
func gains() -> Dictionary:
	return _drives.gains()
