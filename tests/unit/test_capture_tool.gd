extends GutTest

## CaptureTool: which tool an animal's body plan actually requires (see
## docs/concept/taming.md's "Any animal, the right tool"). Pure and
## engine-free -- reads AnimalAnatomy/CreatureInfo data only, no RNG, no
## nodes -- same split as taming.gd itself.

const CaptureTool = preload("res://src/gameplay/capture_tool.gd")


# -- required_tool_for --------------------------------------------------------

## An ordinary herbivore has legs and a neck, and is nowhere near mouse-scale
## or world-boss-scale: Roped.
func test_a_herbivore_needs_the_lasso():
	assert_eq(CaptureTool.required_tool_for("horse"), CaptureTool.LASSO)
	assert_eq(CaptureTool.required_tool_for("deer"), CaptureTool.LASSO)


## Predators join the Roped class too -- same body plan (legs, a neck), just
## harder to hold once caught (that harshness lives in Taming.break_free_chance,
## not here).
func test_a_predator_also_needs_the_lasso():
	assert_eq(CaptureTool.required_tool_for("wolf"), CaptureTool.LASSO)


## Legless species have no neck to loop a rope over: Snared.
func test_a_snake_needs_the_snare():
	assert_eq(CaptureTool.required_tool_for("venomous_snake"), CaptureTool.SNARE)
	assert_eq(CaptureTool.required_tool_for("nonvenomous_snake"), CaptureTool.SNARE)


## World-boss-scale creatures get their own tool -- required_tool_for still
## names it (the reinforced rope is real and craftable today), even though
## Taming.can_be_tamed keeps refusing them regardless of tool.
func test_a_world_boss_needs_the_reinforced_rope():
	assert_eq(CaptureTool.required_tool_for("lindwurm"), CaptureTool.REINFORCED_ROPE)
	assert_eq(CaptureTool.required_tool_for("krampus"), CaptureTool.REINFORCED_ROPE)


## Mouse is the anchor for the trap-vs-lasso size cutoff: at-or-below its own
## world_scale is Trapped.
func test_a_mouse_needs_the_trap():
	assert_eq(CaptureTool.required_tool_for("mouse"), CaptureTool.TRAP)


## A species AnimalAnatomy has never heard of returns "" -- that is how the
## ambient-flyer roster (a wholly separate architecture) is excluded from
## this function; they are handled by is_ambient_flyer_species instead.
func test_an_unknown_species_needs_no_tool_from_this_function():
	assert_eq(CaptureTool.required_tool_for("not_a_real_species"), "")
	assert_eq(CaptureTool.required_tool_for("monarch"), "")
	assert_eq(CaptureTool.required_tool_for("sparrow"), "")


# -- is_ambient_flyer_species --------------------------------------------------

func test_butterflies_and_bees_are_ambient_flyers():
	assert_true(CaptureTool.is_ambient_flyer_species("monarch"))
	assert_true(CaptureTool.is_ambient_flyer_species("swallowtail"))
	assert_true(CaptureTool.is_ambient_flyer_species("blue_morpho"))
	assert_true(CaptureTool.is_ambient_flyer_species("bee"))


func test_small_birds_are_ambient_flyers():
	assert_true(CaptureTool.is_ambient_flyer_species("sparrow"))
	assert_true(CaptureTool.is_ambient_flyer_species("robin"))


func test_ordinary_creatures_are_not_ambient_flyers():
	assert_false(CaptureTool.is_ambient_flyer_species("horse"))
	assert_false(CaptureTool.is_ambient_flyer_species("wolf"))
	assert_false(CaptureTool.is_ambient_flyer_species("mouse"))


func test_an_unknown_species_is_not_an_ambient_flyer():
	assert_false(CaptureTool.is_ambient_flyer_species("not_a_real_species"))
