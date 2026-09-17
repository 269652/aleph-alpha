extends GutTest

## CaveDescent: where one layer connects to the next, and what it takes to
## go down (see docs/concept/underground.md "Descent: a pitch, not a
## staircase").
##
## Layers connect through a real aven/pitch -- a place where the deeper
## layer's own void geometry happens to open directly under a cell you can
## stand on in the layer above. Nothing is placed: finding a way down is
## an exploration result, which is exactly why it is worth finding.

const CaveDescent = preload("res://src/world/cave_descent.gd")
const Strata = preload("res://src/world/strata.gd")

var descent: CaveDescent


func before_each():
	descent = CaveDescent.new()


# -- a pitch needs standing room above and a space below -------------------

func test_a_natural_passage_over_a_natural_passage_is_a_pitch():
	assert_true(descent.is_pitch(Strata.KIND_VOID, Strata.KIND_VOID))


func test_your_own_working_over_a_natural_passage_is_a_pitch():
	# Digging down onto a cave system is how real mines break into real
	# caves, and it is the whole payoff of the layer above's dig verb.
	assert_true(descent.is_pitch(Strata.KIND_TUNNEL, Strata.KIND_VOID))


func test_there_is_no_pitch_through_solid_rock():
	for above in [Strata.KIND_SOLID, Strata.KIND_ORE]:
		assert_false(
			descent.is_pitch(above, Strata.KIND_VOID),
			"%s above is not somewhere you can stand" % above
		)


func test_there_is_no_pitch_into_solid_rock():
	# A floor with rock under it is a floor. Nothing to drop into.
	for below in [Strata.KIND_SOLID, Strata.KIND_ORE]:
		assert_false(descent.is_pitch(Strata.KIND_VOID, below))


func test_a_mined_tunnel_below_is_not_a_natural_pitch():
	# Somebody else's working underneath is a real connection, but not
	# THIS mechanism -- a pitch is geology, not construction. Kept
	# separate so the two can diverge (a worked shaft can be gated and
	# claimed; a natural aven cannot).
	assert_false(descent.is_pitch(Strata.KIND_VOID, Strata.KIND_TUNNEL))


# -- the light gate --------------------------------------------------------

func test_descending_needs_a_light():
	assert_false(
		descent.can_descend(Strata.KIND_VOID, Strata.KIND_VOID, 0),
		"the dark zone has no light at all -- going down without one is not a choice"
	)
	assert_true(descent.can_descend(Strata.KIND_VOID, Strata.KIND_VOID, 1))


func test_a_light_does_not_conjure_a_pitch():
	assert_false(descent.can_descend(Strata.KIND_SOLID, Strata.KIND_VOID, 3))


func test_the_real_caving_standard_is_three_independent_lights():
	# The standing safety rule is three per person, because a cave with no
	# light is not "dark", it is a place you cannot leave.
	assert_eq(CaveDescent.RECOMMENDED_LIGHT_SOURCES, 3)
	assert_false(descent.is_adequately_equipped(2))
	assert_true(descent.is_adequately_equipped(3))


func test_the_game_gates_at_one_light_while_recording_the_real_standard():
	# A deliberate, documented divergence: the real standard is recorded
	# so a warning can use it, but demanding three torches to step down a
	# pitch would be tedium rather than tension.
	assert_lt(CaveDescent.MINIMUM_LIGHT_SOURCES, CaveDescent.RECOMMENDED_LIGHT_SOURCES)
	assert_eq(CaveDescent.MINIMUM_LIGHT_SOURCES, 1)


# -- walking the layer stack -----------------------------------------------

func test_layer_below_follows_the_real_depth_order():
	assert_eq(descent.layer_below(Strata.LAYER_TOPSOIL_REGOLITH), Strata.LAYER_BEDROCK)
	assert_eq(descent.layer_below(Strata.LAYER_BEDROCK), Strata.LAYER_DEEP_BEDROCK)
	assert_eq(descent.layer_below(Strata.LAYER_DEEP_BEDROCK), Strata.LAYER_HYDROTHERMAL)


func test_there_is_nothing_below_the_deepest_layer():
	assert_eq(descent.layer_below(Strata.LAYER_HYDROTHERMAL), "")


func test_layer_above_walks_back_up():
	assert_eq(descent.layer_above(Strata.LAYER_BEDROCK), Strata.LAYER_TOPSOIL_REGOLITH)
	assert_eq(descent.layer_above(Strata.LAYER_HYDROTHERMAL), Strata.LAYER_DEEP_BEDROCK)


func test_there_is_nothing_above_the_shallowest_layer():
	assert_eq(descent.layer_above(Strata.LAYER_TOPSOIL_REGOLITH), "")


func test_an_unknown_layer_has_no_neighbours():
	assert_eq(descent.layer_below("not_a_layer"), "")
	assert_eq(descent.layer_above("not_a_layer"), "")


func test_every_layer_but_the_last_has_somewhere_to_go():
	for i in Strata.LAYERS.size() - 1:
		assert_ne(descent.layer_below(Strata.LAYERS[i]), "")
