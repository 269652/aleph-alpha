extends StaticBody2D

## A collapsed passage: rubble blocking a way through, cleared only by
## enough delivered momentum -- docs/concept/exploration.md's "Puzzle
## content stays emergent, not hand-authored" first named obstacle type: "a
## collapsed passage that only enough momentum (a heavy enough thrown/pushed
## object ...) can clear."
##
## NOT a bespoke puzzle mechanism: this is a StaticBody2D with a real
## MaterialProperties material (rubble is fallen rock, so "stone" by
## default) that routes every delivered hit through the SAME
## ImpactResolver.resolve_impact call every other hittable thing in this
## world already uses (see SmashableStone/MinableOre for the sibling node
## pattern: a world object with a collision body that responds to being
## hit). No separate "puzzle HP" stat exists anywhere in this file.
##
## Contact geometry is always "blunt": every momentum source wired to this
## obstacle (a thrown or kicked stone, see Player._resolve_stone_impact_
## on_obstacles) hits it round-and-blunt, not edge/point -- the same "blunt"
## contact geometry Player._resolve_thrown_stone_impact already uses for a
## thrown stone striking a creature.
##
## Clearing outcome, a reasoned call (docs/concept/materials.md's "one
## damage model" defines six outcomes: cut/dent/crush/pierce/shatter/
## bounce): "the rubble gives way" maps to CRUSH (the rock mass gets pounded
## apart) or SHATTER (a brittle material's structure fails outright) -- both
## mean the passage opens. cut/pierce don't apply to blunt-vs-mass contact
## at all (ImpactResolver's own match statement never returns them for
## "blunt"); dent/bounce mean the hit landed but wasn't enough, so the
## rubble stays exactly where SmashableStone/MinableOre leave an
## insufficiently-hit target: unchanged.

const ImpactResolver = preload("res://src/gameplay/impact_resolver.gd")
const HoverTargetFinder = preload("res://src/rendering/hover_target_finder.gd")

const GROUP_NAME := "collapsed_passage"

## ImpactResolver outcomes that count as "the rubble gives way" -- see this
## file's own doc comment for the reasoning.
const CLEARING_OUTCOMES := ["crush", "shatter"]

## What the rubble is made of. Defaults to MaterialProperties' "stone"
## entry -- rubble is fallen rock, not a bespoke new material -- but is a
## real, settable field so a POI generator (docs/concept/exploration.md's
## "procedurally-seeded application" language) can later hand it a
## different real material. Named `rubble_material`, not `material` --
## Node2D/CanvasItem already declares a typed `material: Material` property
## (the shader/render material), which a bare-String `material` field here
## would collide with.
var rubble_material := "stone"

var _resolver := ImpactResolver.new()
var _cleared := false


func _ready() -> void:
	add_to_group(GROUP_NAME)
	add_to_group(HoverTargetFinder.GROUP_NAME)


## For World's mouse-hover tooltip (see HoverTargetFinder).
func get_display_name() -> String:
	return "Collapsed Passage"


## For World's mouse-hover tooltip (see HoverTargetFinder). Bound to
## "attack" for the same reason SmashableStone/MinableOre are: it is not the
## input a swing itself reads here (momentum comes from a thrown/kicked
## stone, not a melee swing), but the shared hover-tooltip verb vocabulary.
func get_hover_actions() -> Array:
	return [{"verb": "Clear", "action": "attack"}]


## Whether `momentum` delivered through a blunt contact would clear this
## obstacle, without mutating state -- the pure decision receive_impact()
## below acts on. Exposed separately so a real-world probe (or a pure test)
## can ask the question without side effects.
func resolves_clear(momentum: float) -> bool:
	var outcome := _resolver.resolve_impact(momentum, "blunt", rubble_material)
	return outcome in CLEARING_OUTCOMES


## Delivers `momentum` to the obstacle -- a thrown or kicked stone landing
## on it. Clears (removes itself, opening the passage) if resolves_clear();
## otherwise the rubble stays put, same as any other insufficiently-hit
## target in this world.
func receive_impact(momentum: float) -> void:
	if _cleared or not resolves_clear(momentum):
		return
	_cleared = true
	queue_free()


func is_cleared() -> bool:
	return _cleared
