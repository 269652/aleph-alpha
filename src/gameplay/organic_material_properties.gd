extends RefCounted

## The organic material track docs/concept/materials.md's "Two material
## tracks" section always declared but never populated (see
## docs/concept/material_dsl.md). Deliberately a SIBLING to
## material_properties.gd, never merged into its MATERIALS table -- that
## file's own doc comment scopes it to the mineral track only.
##
## Identical shape to MaterialProperties on purpose (DEFAULT_PROPERTIES, a
## MATERIALS dict, property_value/mass_kg_for) so ImpactResolver can resolve
## against either one unchanged (see impact_resolver.gd's constructor
## injection) -- one damage model for the whole world, reused rather than
## reimplemented for a softer set of materials.
##
## Still fixed data, not yet DNA-driven -- the "organic materials vary by
## genetics" half of the two-track split remains unbuilt (see dna.md/
## evolution.md, which carry no material-property content today). This is a
## real, if small, first step: composition-bearing organic matter that
## exists and is resolvable, even before it can vary per individual.

const DEFAULT_PROPERTIES: Dictionary = {
	"density": 1.0,
	"hardness": 0.0,
	"toughness": 1.0,
	"elasticity": 1.0,
	"sharpness_capacity": 1.0,
	"flammability": 1.0,
	"conductivity": 0.0,
	"decay_rate": 1.0,
}

const MATERIALS: Dictionary = {
	# Ripe, soft, shell-less fruit pulp (apple/cherry flesh -- see
	# docs/concept/material_dsl.md's Status list for why nuts, with their
	# own separate crack-open mechanic, are not this).
	"fruit_flesh": {
		"density": 0.85,        # mostly water, but cellular air pockets keep
		                         # it a little below water's own 1.0 -- a real
		                         # published range for apple pulp (0.8-0.9).
		# Negligibly soft, on par with the file's own reference for muscle
		# tissue (MaterialProperties' "flesh" is 0.001) -- there is no
		# meaningfully different real hardness datum for plant pulp at this
		# resolution; both are "offers no measurable resistance."
		"hardness": 0.001,
		# Placed just above ImpactResolver.T_BRITTLE_TOUGHNESS (3.0) so a
		# firm bite reads as "crush," not "shatter" -- soft flesh mushes, it
		# does not fracture into shards, the physically-honest verdict for
		# biting into ripe fruit. Below "flesh" muscle tissue's own 4.0:
		# fruit pulp is less cohesive/fibrous than organized muscle, a
		# legibility ordering exactly like every other non-measured column
		# on this vector (see material_properties.gd's own doc comment).
		"toughness": 3.5,
		# Stays deformed once bitten/bruised rather than springing back --
		# low, matching the file's own low end (iron/stone), not muscle's
		# elastic 3.0.
		"elasticity": 1.0,
		"sharpness_capacity": 0.0,   # cannot be sharpened, matches "flesh"
		"flammability": 1.0,         # mostly water; resists ignition fresh
		# Fruit juice is a real, if weak, electrolyte (dissolved sugars and
		# acids) -- the classic "lemon battery" demonstration -- so it
		# conducts meaningfully better than dry organic matter, if nothing
		# in this game currently reads that far down the vector.
		# 100 * sigma / 5.80e7 with sigma ~ 2.0e-2 S/m (typical fruit juice).
		"conductivity": 3.448276e-08,
		"decay_rate": 9.0,           # rots about as fast as flesh does
	},
}


## A single named scalar from `material`'s property vector. Unknown
## materials, and unknown properties on known materials, both fall back to
## DEFAULT_PROPERTIES -- identical fallback shape to MaterialProperties.
func property_value(material: String, property_name: String) -> float:
	var vector: Dictionary = MATERIALS.get(material, DEFAULT_PROPERTIES)
	return vector.get(property_name, DEFAULT_PROPERTIES.get(property_name, 1.0))


## Real mass in kilograms for `volume_cm3` of `material` -- the identical
## density x volume shape MaterialProperties.mass_kg_for uses, kept here so
## anything that eventually wants a real fruit mass (e.g. a thrown apple)
## does not have to reach across tracks for it.
func mass_kg_for(material: String, volume_cm3: float) -> float:
	var density_g_per_cm3 := property_value(material, "density")
	return density_g_per_cm3 * volume_cm3 / 1000.0
