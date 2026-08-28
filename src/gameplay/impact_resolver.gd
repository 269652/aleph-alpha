extends RefCounted

## Momentum + contact-geometry + target-material -> outcome. Pure logic.
##
## Implements docs/concept/materials.md's "One damage model for the whole
## world": impact = momentum (mass * velocity) delivered through a contact
## geometry, resolved against the target's material response, producing one
## of six outcomes: cut, dent, crush, pierce, shatter, bounce. The thresholds
## below are the "calibration tests" that doc's Open Questions section calls
## for -- each is a named, test-pinned constant, not an eyeballed number.

const MaterialProperties: GDScript = preload("res://src/gameplay/material_properties.gd")

## Below this momentum, nothing happens beyond a harmless bounce, regardless
## of geometry or material. See test_low_momentum_always_bounces.
const BOUNCE_MOMENTUM_THRESHOLD: float = 1.0

## Minimum momentum an edge needs to cut. See
## test_edge_at_cut_threshold_cuts_tough_material.
const T_CUT: float = 3.0

## Minimum momentum a point needs to pierce. See
## test_point_at_pierce_threshold_pierces_soft_material.
const T_PIERCE: float = 3.0

## Minimum momentum a blunt face needs to crush -- higher than T_CUT/T_PIERCE
## because blunt trauma needs more delivered force than a concentrated edge
## or point tip. See test_blunt_at_crush_threshold_crushes_tough_material.
const T_CRUSH: float = 4.0

## A target material with toughness below this is brittle enough to shatter
## under a strong-enough hit instead of cleanly cutting/crushing. See
## test_edge_on_brittle_material_shatters_instead_of_cutting.
const T_BRITTLE_TOUGHNESS: float = 3.0

## A point can't pierce a material this hard -- too hard to punch through with
## a concentrated tip.
##
## RE-DERIVED, not merely rescaled, when the hardness column became published
## Vickers (MaterialProperties.HARDNESS_HV). The old 6.0 sat in the gap between
## copper and stone on a legibility scale that no longer exists, and it was an
## eyeballed number besides.
##
## The line it was really drawing turns out to be one the game had already
## named: MaterialProperties.HARD_HARDNESS, the cutoff at which a tooltip
## starts calling a material "hard" -- which is iron's own hardness, the same
## benchmark metal KEEN_SHARPNESS and ItemCompiler.BENCHMARK_BLADE_MATERIAL
## already use. So this is now that one constant rather than a second opinion
## about the same line, exactly the arrangement BRITTLE_TOUGHNESS and
## T_BRITTLE_TOUGHNESS already have: **a point cannot pierce anything the
## player is told is hard.**
##
## Worth recording that the re-derivation is behaviour-PRESERVING: every one of
## the eighteen materials in the table keeps the pierce/dent verdict it had
## under the old 6.0 (flesh, hide, leather, wood, bone, copper and the soft
## metals pierce; iron, stone, obsidian and glass do not), which is the check
## that the old constant was drawing this line and not some other one. Pinned
## by test_a_point_cannot_pierce_anything_the_tooltip_calls_hard.
const PIERCE_HARDNESS_CAP: float = MaterialProperties.HARD_HARDNESS

var _materials: RefCounted = MaterialProperties.new()


## Resolves a single impact into one of: "cut", "dent", "crush", "pierce",
## "shatter", "bounce". `contact_geometry` is one of "edge", "point", "blunt"
## (any other value dents, same as insufficient momentum).
func resolve_impact(momentum: float, contact_geometry: String, material: String) -> String:
	if momentum < BOUNCE_MOMENTUM_THRESHOLD:
		return "bounce"

	var toughness: float = _materials.property_value(material, "toughness")
	var is_brittle: bool = toughness < T_BRITTLE_TOUGHNESS

	match contact_geometry:
		"point":
			var hardness: float = _materials.property_value(material, "hardness")
			if momentum >= T_PIERCE and hardness < PIERCE_HARDNESS_CAP:
				return "pierce"
			return "dent"
		"edge":
			if momentum >= T_CUT:
				return "shatter" if is_brittle else "cut"
			return "dent"
		"blunt":
			if momentum >= T_CRUSH:
				return "shatter" if is_brittle else "crush"
			return "dent"
		_:
			return "dent"
