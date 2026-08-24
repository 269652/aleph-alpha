extends RefCounted

## Pure data model behind docs/concept/easter_eggs.md's "world's smallest
## Pokédex"-style catch-list screen for the "hidden retro handheld" entry --
## which HandheldRoster species this player has caught (via HandheldCatch)
## on this handheld. Deliberately in-memory/session-only, not persisted to
## PlayerSave -- the same "no persistence layer built for this family of
## Easter eggs yet" scope call every sibling module here already makes
## (SeaCaveGuardian's own challenge state, AncientTerminal's
## has_been_found -- none of them survive a restart today either).
##
## Zero mechanical weight (pillar 2): nothing here is ever read by anything
## that affects real gameplay -- entries() exists purely for
## HandheldBattleView's dex screen to render.

const HandheldRoster = preload("res://src/gameplay/handheld_roster.gd")

var _caught: Dictionary = {}
var _roster := HandheldRoster.new()


func mark_caught(species: String) -> void:
	_caught[species] = true


func has_caught(species: String) -> bool:
	return _caught.has(species)


func caught_count() -> int:
	return _caught.size()


func total_species() -> int:
	return _roster.all_species().size()


## Progress toward a "full" collection, 0.0 (nothing caught) to 1.0 (every
## roster species caught) -- purely for a progress readout, no mechanical
## effect (pillar 2).
func caught_fraction() -> float:
	var total := total_species()
	if total <= 0:
		return 0.0
	return float(caught_count()) / float(total)


## One row per roster species, common tier first then legendary (the same
## "easy finds before rare ones" order a real collection screen reads
## naturally in), each {species, tier, caught} -- the dex screen's own data
## source. A caller wanting the display name renders `species.capitalize()`
## itself, matching CreatureInfo.display_name's own convention, rather than
## this pure data model owning presentation strings.
func entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for species in _roster.common_species():
		out.append({"species": species, "tier": HandheldRoster.TIER_COMMON, "caught": has_caught(species)})
	for species in _roster.legendary_species():
		out.append({"species": species, "tier": HandheldRoster.TIER_LEGENDARY, "caught": has_caught(species)})
	return out
