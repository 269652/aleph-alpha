extends RefCounted

## CaptureTool: which real-world tool a species' body plan actually needs to
## be caught with (see docs/concept/taming.md's "Any animal, the right
## tool"). A lasso loops over a head and neck; that only ever made sense for
## a legged creature with one to loop it over. This module is what makes the
## tool follow the animal's actual anatomy instead of a hand-maintained
## species allow-list -- a new species dropped into AnimalAnatomy is
## automatically catchable with the right gear the moment it exists.
##
## Pure and engine-free -- no nodes, no RNG -- same shape as taming.gd
## itself: this decides WHAT tool a species needs; the caller (the player's
## throw interaction) owns matching that against what is actually equipped.

const AnimalAnatomy = preload("res://src/rendering/animal_anatomy.gd")
const CreatureInfo = preload("res://src/world/creature_info.gd")
const AmbientFlyerRenderer = preload("res://src/rendering/ambient_flyer_renderer.gd")

const LASSO := "lasso"
const SNARE := "snare"
const NET := "butterfly_net"
const TRAP := "trap"
const REINFORCED_ROPE := "reinforced_rope"

## The trap-vs-lasso size cutoff. Anything at or below this scale needs a
## Trap rather than a Lasso: a rope loop has a real minimum practical
## diameter (see taming.md's real-world grounding), the same reason field
## biologists reach for a box trap on a mouse rather than a smaller rope.
##
## A fixed literal, not a live AnimalAnatomy.profile_for("mouse") reference
## (which is what this was until mice were sized up for visibility -- see
## docs/progress.md): mouse's own world_scale is a rendering/legibility
## tuning knob, not a definition of "how big can something be and still need
## a trap" -- coupling the two meant a purely cosmetic mouse-size change
## would silently flip squirrel/arctic_fox/sheep/lynx from Lasso to Trap the
## moment mouse's own scale crossed theirs. Set to exactly today's mouse
## world_scale (0.40) so mouse itself keeps needing a Trap (see
## test_a_mouse_needs_the_trap) while every other species' tool requirement
## stays exactly as it was.
const TRAP_WORLD_SCALE_CEILING: float = 0.40


## The tool `species`' body plan actually requires, or "" if AnimalAnatomy
## does not know this species at all -- which is how the ambient-flyer
## roster (butterflies, bees, small birds) is excluded here: they are not
## part of AnimalAnatomy.SPECIES, a wholly separate architecture, and are
## handled by is_ambient_flyer_species instead.
##
## World-boss-scale species still get a real answer (REINFORCED_ROPE) here,
## even though Taming.can_be_tamed refuses them regardless of tool -- the
## reinforced rope is real and craftable today (taming.md: "The reinforced
## rope is real and craftable today; what it is for is written down and
## waiting"), and this function's job is naming the tool a body plan needs,
## not deciding who may currently be tamed. That refusal lives in
## Taming.can_be_tamed, on purpose, so the two questions ("what tool fits
## this body" vs "is this species tameable at all right now") stay separate.
static func required_tool_for(species: String) -> String:
	if not AnimalAnatomy.has_profile(species):
		return ""
	if CreatureInfo.WORLD_BOSS_SPECIES.has(species):
		return REINFORCED_ROPE
	if AnimalAnatomy.SERPENT_SPECIES.has(species):
		return SNARE
	var world_scale: float = AnimalAnatomy.profile_for(species).get("world_scale", 1.0)
	if world_scale <= TRAP_WORLD_SCALE_CEILING:
		return TRAP
	return LASSO


## True for anything in the ambient-flyer roster (butterflies, bees, small
## birds) -- AmbientFlyerRenderer's own species pools, not a second list
## authored here. These are not part of AnimalAnatomy.SPECIES at all: a
## wholly separate rendering/simulation architecture (see
## ambient_flyer_marker.gd/ambient_flyer_renderer.gd), so they get their own
## check rather than folding into required_tool_for.
static func is_ambient_flyer_species(species: String) -> bool:
	return (
		AmbientFlyerRenderer.BUTTERFLY_SPECIES_POOL.has(species)
		or AmbientFlyerRenderer.BIRD_SPECIES_POOL.has(species)
	)
