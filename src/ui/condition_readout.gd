extends RefCounted

## What the HUD tells the player is currently wrong with them.
##
## The survival bars have always shown RESERVES -- food, water, stamina,
## warmth -- which say how much of something is left, not what it is doing to
## you. Nothing on screen said you were bleeding, ill, or chilled through, and
## after the wound and cold-exposure passes a player could be walking toward
## sepsis or hypothermia with no indication at all.
##
## Pure, so the priority order is testable without standing up World -- the
## same split EscapeAction and HotkeyRouting already use.

const ColdExposure = preload("res://src/gameplay/cold_exposure.gd")

## Worst first, and a FIXED order: the line must not reshuffle itself frame to
## frame as conditions come and go, or it becomes something the player has to
## re-read rather than glance at.
##
## Illness leads because it is the one that does not go away on its own;
## bleeding next because it is the one with the shortest fuse; the rest are
## the ordinary neglect meters, which the bars beside this line already show
## in detail.
const SEPARATOR := "  ·  "

## What an undiagnosed illness is allowed to say.
##
## `Sickness`'s own contract is that an undiagnosed sickness exposes only its
## vague severity, never which sickness it is -- so the HUD must not name it,
## or the readout becomes the diagnosis and the Herbalist loop this game is
## building has nothing left to do.
const UNDIAGNOSED := "Unwell"


## The status line for a player's condition, or "" when there is nothing worth
## saying. `state` carries only what this needs, so the module stays testable
## without a Player: wound_stacks, sickness_id, sickness_diagnosed,
## cold_exposure, starving, dehydrated, exhausted.
static func text(state: Dictionary) -> String:
	var parts: Array[String] = []

	var sickness_id := String(state.get("sickness_id", ""))
	if not sickness_id.is_empty():
		if bool(state.get("sickness_diagnosed", false)):
			parts.append(sickness_id.replace("_", " ").capitalize())
		else:
			parts.append(UNDIAGNOSED)

	if int(state.get("wound_stacks", 0)) > 0:
		parts.append("Bleeding")

	# Only once the chill is past the harmless stage. A warning that is always
	# on means nothing, and the mild stage of hypothermia is exactly the one a
	# body corrects by itself (see ColdExposure.RISK_THRESHOLD).
	if float(state.get("cold_exposure", 0.0)) >= ColdExposure.RISK_THRESHOLD:
		parts.append("Chilled through")

	if bool(state.get("starving", false)):
		parts.append("Starving")
	if bool(state.get("dehydrated", false)):
		parts.append("Parched")
	if bool(state.get("exhausted", false)):
		parts.append("Exhausted")

	return SEPARATOR.join(parts)


## The same readout, read straight off a Player. Kept separate from `text` so
## the rules above stay testable without a Player instance at all.
static func text_for(player) -> String:
	if player == null:
		return ""
	return text({
		"sickness_id": player.sickness_id,
		"sickness_diagnosed": player.sickness_diagnosed,
		"wound_stacks": player.wound_stacks(),
		"cold_exposure": player.cold_exposure,
		"starving": player.survival.is_starving(),
		"dehydrated": player.survival.is_dehydrated(),
		"exhausted": player.survival.is_exhausted(),
	})
