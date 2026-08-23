extends RefCounted

## Material property vector + traversal-tool viability check. Pure logic.
##
## Per docs/concept/materials.md: every material carries a small, fixed
## property vector -- this is the "mineral" track of that doc's deliberate
## two-track split (fixed/reliable), not the DNA-driven organic track (see
## dna.md/evolution.md), which is out of scope here. This is the shared data
## the impact-resolution model (impact_resolver.gd) and the traversal-tool
## check below both read from.
##
## Density is expressed relative to water (water == 1.0) so buoyancy is a
## direct density comparison. All other scalars are small "8-bit" numbers
## (roughly 0..10) per materials.md's determinism/legibility goal. Unknown
## materials/properties fall back to DEFAULT_PROPERTIES, mirroring
## material_damage.gd's existing default-fallback convention.

const DEFAULT_PROPERTIES: Dictionary = {
	"density": 1.0,
	"hardness": 1.0,
	"toughness": 1.0,
	"elasticity": 1.0,
	"sharpness_capacity": 1.0,
	"flammability": 1.0,
	"conductivity": 1.0,
	"decay_rate": 1.0,
}

const MATERIALS: Dictionary = {
	"wood": {
		"density": 0.6,
		"hardness": 3.0,
		"toughness": 6.0,
		"elasticity": 5.0,
		"sharpness_capacity": 3.0,
		"flammability": 8.0,
		"conductivity": 1.0,
		"decay_rate": 6.0,
	},
	"flesh": {
		"density": 1.05,
		"hardness": 1.0,
		"toughness": 4.0,
		"elasticity": 3.0,
		"sharpness_capacity": 0.0,
		"flammability": 2.0,
		"conductivity": 3.0,
		"decay_rate": 9.0,
	},
	"stone": {
		"density": 2.5,
		"hardness": 7.0,
		"toughness": 5.0,
		"elasticity": 1.0,
		"sharpness_capacity": 4.0,
		"flammability": 0.0,
		"conductivity": 1.0,
		"decay_rate": 1.0,
	},
	"iron": {
		"density": 7.8,
		"hardness": 8.0,
		"toughness": 7.0,
		"elasticity": 2.0,
		"sharpness_capacity": 8.0,
		"flammability": 0.0,
		"conductivity": 9.0,
		"decay_rate": 3.0,
	},
	"obsidian": {
		"density": 2.4,
		"hardness": 9.0,
		"toughness": 1.0,
		"elasticity": 0.0,
		"sharpness_capacity": 10.0,
		"flammability": 0.0,
		"conductivity": 1.0,
		"decay_rate": 0.0,
	},
	"fiber": {
		"density": 0.3,
		"hardness": 1.0,
		"toughness": 7.0,
		"elasticity": 6.0,
		"sharpness_capacity": 0.0,
		"flammability": 7.0,
		"conductivity": 1.0,
		"decay_rate": 7.0,
	},
}

## Water's relative density -- the buoyancy cutoff for RAFT viability.
## See test_iron_is_not_viable_raft_material / test_wood_is_viable_raft_material.
const WATER_DENSITY: float = 1.0

## Minimum toughness a material needs to serve as a GRAPPLE_ROPE. This "8-bit"
## vector has no separate tensile-strength scalar, so toughness (resistance
## to fracture under stress) stands in for it -- the closest of the 8
## documented scalars to "won't snap under load". See
## test_fiber_is_viable_grapple_rope_material /
## test_obsidian_is_not_viable_grapple_rope_material.
const ROPE_MIN_TOUGHNESS: float = 5.0


## A single named scalar from `material`'s property vector. Unknown
## materials, and unknown properties on known materials, both fall back to
## DEFAULT_PROPERTIES.
func property_value(material: String, property_name: String) -> float:
	var vector: Dictionary = MATERIALS.get(material, DEFAULT_PROPERTIES)
	return vector.get(property_name, DEFAULT_PROPERTIES.get(property_name, 1.0))


## Real mass in kilograms for `volume_cm3` of `material` -- density is
## already expressed in real g/cm^3 (relative to water == 1.0 g/cm^3, see
## DEFAULT_PROPERTIES' own doc comment), so this is exactly density x volume,
## the same "density x volume" shape StoneSize.mass_kg_for uses for a stone's
## sphere volume, generalized to an arbitrary item (see item_catalog.gd's
## weapon mass wiring). Feeds the shared momentum model (docs/concept/
## materials.md's momentum = mass * velocity, impact_resolver.gd/
## throwable.gd) for weapons/tools the same way StoneSize.mass_kg_for feeds
## it for loose stone.
func mass_kg_for(material: String, volume_cm3: float) -> float:
	var density_g_per_cm3 := property_value(material, "density")
	return density_g_per_cm3 * volume_cm3 / 1000.0


## Traversal-tool viability per docs/concept/transportation.md's "Traversal
## tools" section: a raft needs a buoyant (low-density) material, a grapple
## rope needs a tough material. Unknown tool types are never viable.
func is_viable_for_tool(material: String, tool_type: String) -> bool:
	match tool_type:
		"raft":
			return property_value(material, "density") < WATER_DENSITY
		"grapple_rope":
			return property_value(material, "toughness") >= ROPE_MIN_TOUGHNESS
		_:
			return false
