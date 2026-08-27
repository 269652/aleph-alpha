extends RefCounted

## "Why can't this chop?" -- the player-facing projection of item_compiler.gd's
## absence reasons. Pure logic. Design doc:
## docs/concept/emergent_crafting.md.
##
## ## Why this is a feature and not a debug aid
##
## Everything in this crafting model is inferred rather than declared, which is
## the whole point and is also its one real risk: a system whose failures are
## silent is unlearnable. A player told only "your saw cannot chop" has to guess
## and will guess wrong (they will file the teeth sharper). A player told the
## plate is too light to carry the blow has learned something TRUE about the
## model and can act on it -- put the steel somewhere heavier.
##
## docs/concept/materials.md's "Learning an emergent system" already commits to
## descriptors-and-discovery over a raw scalar spreadsheet; this is the same
## commitment for affordances, and the reason the compiler carries a reason for
## every absence rather than just a list of what works.
##
## ## It has no opinions of its own
##
## Every string here comes out of ItemCompiler.compile. This file must never
## grow a second explanation of why something cannot cut -- a note that
## disagreed with the physics would be worse than no note at all. It projects,
## it does not decide.

const ItemCompiler: GDScript = preload("res://src/gameplay/item_compiler.gd")

## The crafter an affordance question is answered about when the caller does not
## say. A finished item is being INSPECTED here, not made, so the question is
## what this object can do -- not what a beginner would have managed to build.
const AS_BUILT: float = 1.0


## Why `graph` cannot `wanted_verb`, in a sentence a player can act on, or "" if
## it can.
##
## Three kinds of answer, kept distinct on purpose:
##   - the assembly is not an item at all (no grip, parts not joined, malformed)
##     -- answered with THAT, because "your offcut cannot cut" would imply it
##     was nearly a tool;
##   - the verb is not one this model knows -- said plainly rather than
##     answered with a confident-sounding physical reason for a question nobody
##     asked;
##   - the ordinary case: the compiler's own reason, verbatim.
static func absence_reason(
	graph: RefCounted, wanted_verb: String, crafter_skill: float = AS_BUILT
) -> String:
	if not ItemCompiler.VERBS.has(wanted_verb):
		return "'%s' is not something this model knows how to do" % wanted_verb
	var compiled: Dictionary = ItemCompiler.compile(graph, crafter_skill)
	if not bool(compiled["ok"]):
		var errors: Array = compiled["errors"]
		return "" if errors.is_empty() else String(errors[0])
	var absences: Dictionary = compiled["absences"]
	return String(absences.get(wanted_verb, ""))


## Can it? The positive counterpart, and deliberately the shape a caller wants
## in place of a string test on an item id: `affords(graph, "rip")` is what
## finally lets a PLAYER-BUILT saw work on a real trunk, where
## `Item.is_saw()`'s `id.contains("saw")` never could.
##
## NOTE this is not yet wired to scenes/player.gd -- see item_compiler.gd's own
## Status note. The signature is here because it is the seam, not because
## anything crosses it today.
static func affords(
	graph: RefCounted, wanted_verb: String, crafter_skill: float = AS_BUILT
) -> bool:
	if not ItemCompiler.VERBS.has(wanted_verb):
		return false
	return (ItemCompiler.compile(graph, crafter_skill)["affordances"] as Array).has(wanted_verb)
