extends GutTest

## CrushMechanic: the shared momentum-based "crushed underfoot" physics
## check every soft-bodied creature small enough to be at risk uses --
## today, EarthwormPatch.crush (worms) and EarthChunkManager.
## crush_caterpillars_near (caterpillars) both resolve through this same
## class, rather than each owning an independent copy of the threshold
## (see docs/concept/soil_fauna.md's "Generalized to caterpillars too").
## These are the same is_crushed_by cases that used to live directly on
## EarthwormPatch, moved here unchanged in substance -- testing the class
## that actually owns the physics rule now, not the worm specifically.

const CrushMechanic = preload("res://src/world/crush_mechanic.gd")
const CreatureMass = preload("res://src/world/creature_mass.gd")
const PebbleDispersion = preload("res://src/rendering/pebble_dispersion.gd")


## The real, tested boundary this whole mechanic exists to draw: a mouse's
## own momentum must fall under the threshold, and a horse's/player's own
## must clear it -- computed from the SAME real numbers the live game
## actually uses, not invented test-only figures.
func test_is_crushed_by_spares_a_mouses_own_real_momentum():
	var mouse_momentum: float = CreatureMass.mass_kg_for("mouse") * PebbleDispersion.FOOTSTEP_SPEED_MPS
	assert_false(CrushMechanic.is_crushed_by(mouse_momentum))


func test_is_crushed_by_kills_under_a_horses_own_real_momentum():
	var horse_momentum: float = CreatureMass.mass_kg_for("horse") * PebbleDispersion.FOOTSTEP_SPEED_MPS
	assert_true(CrushMechanic.is_crushed_by(horse_momentum))


## The calibration example given directly, back when the worm mechanic
## first shipped: a light creature's step spares something this small, a
## heavy one's kills it. No frog exists in this game -- mouse/squirrel
## stand in for it here, same as they always have.
func test_is_crushed_by_spares_small_creatures_and_kills_under_large_ones():
	for species in ["mouse", "squirrel"]:
		var momentum: float = CreatureMass.mass_kg_for(species) * PebbleDispersion.FOOTSTEP_SPEED_MPS
		assert_false(CrushMechanic.is_crushed_by(momentum), "%s should spare something this small" % species)
	for species in ["horse", "boar", "deer", "bear"]:
		var momentum: float = CreatureMass.mass_kg_for(species) * PebbleDispersion.FOOTSTEP_SPEED_MPS
		assert_true(CrushMechanic.is_crushed_by(momentum), "%s should crush something this small" % species)


func test_is_crushed_by_is_never_true_at_zero_momentum():
	assert_false(CrushMechanic.is_crushed_by(0.0))


func test_the_threshold_is_the_pinned_tuned_constant():
	assert_eq(CrushMechanic.CRUSH_MOMENTUM_THRESHOLD_KG_M_S, 5.0)
