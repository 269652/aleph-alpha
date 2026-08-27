extends GutTest

## A part is (material, geometry, role) -- docs/concept/emergent_crafting.md.
##
## Volume is DERIVED from the geometry's real dimensions rather than stored as
## its own field, so a part cannot claim a mass its own shape contradicts. Each
## formula below is ordinary solid geometry against the primitive
## docs/concept/materials.md's "Shape and assembly" section already commits to.

var ItemPart: GDScript = preload("res://src/gameplay/item_part.gd")
var MaterialProperties: GDScript = preload("res://src/gameplay/material_properties.gd")


func _edge(material: String = "iron") -> RefCounted:
	return ItemPart.new(
		material, ItemPart.GEOMETRY_EDGE, ItemPart.ROLE_WORKING,
		{"length_cm": 80.0, "width_cm": 4.5, "thickness_cm": 0.5, "angle_deg": 20.0}
	)


# -- volume: real solid geometry, one primitive at a time ------------------

## A blade is a wedge: a triangular prism of length x width x back-thickness,
## so its volume is half the enclosing box. An 80cm x 4.5cm arming-sword blade
## 0.5cm thick at the spine is 0.5 x 80 x 4.5 x 0.5 = 90 cm^3 -- which at
## iron's 7.8 g/cm^3 is the ~0.7 kg a real 80cm blade actually masses.
func test_an_edge_part_takes_its_volume_from_the_wedge_it_is() -> void:
	assert_almost_eq(_edge().volume_cm3(), 90.0, 0.0001)


## A point is a cone: base radius = length x tan(half the included apex
## angle), volume = pi r^2 L / 3. A 6cm spike of 30 degrees included angle
## has r = 6 x tan(15) = 1.6077cm, so V = pi x 1.6077^2 x 6 / 3 = 16.234 cm^3.
func test_a_point_part_takes_its_volume_from_the_cone_it_is() -> void:
	var spike: RefCounted = ItemPart.new(
		"iron", ItemPart.GEOMETRY_POINT, ItemPart.ROLE_WORKING,
		{"length_cm": 6.0, "angle_deg": 30.0}
	)
	var radius: float = 6.0 * tan(deg_to_rad(15.0))
	assert_almost_eq(spike.volume_cm3(), PI * radius * radius * 6.0 / 3.0, 0.0001)


## A flat/face is a rectangular slab: width x height x thickness.
func test_a_face_part_takes_its_volume_from_the_slab_it_is() -> void:
	var guard: RefCounted = ItemPart.new(
		"iron", ItemPart.GEOMETRY_FACE, ItemPart.ROLE_STRUCTURE,
		{"width_cm": 20.0, "height_cm": 2.0, "thickness_cm": 0.8}
	)
	assert_almost_eq(guard.volume_cm3(), 32.0, 0.0001)


## A haft is a cylinder: pi (d/2)^2 x length.
func test_a_haft_part_takes_its_volume_from_the_cylinder_it_is() -> void:
	var grip: RefCounted = ItemPart.new(
		"wood", ItemPart.GEOMETRY_HAFT, ItemPart.ROLE_GRIP,
		{"length_cm": 11.0, "diameter_cm": 3.2}
	)
	assert_almost_eq(grip.volume_cm3(), PI * 1.6 * 1.6 * 11.0, 0.0001)


## Bulk is a mass concentration with no working shape of its own, so it is the
## equivalent SPHERE of its diameter -- the same convention StoneSize.mass_kg_for
## already uses to give a loose stone a real mass.
func test_a_bulk_part_takes_its_volume_from_the_sphere_it_is() -> void:
	var pommel: RefCounted = ItemPart.new(
		"iron", ItemPart.GEOMETRY_BULK, ItemPart.ROLE_COUNTERWEIGHT,
		{"diameter_cm": 4.5}
	)
	assert_almost_eq(pommel.volume_cm3(), PI * pow(4.5, 3.0) / 6.0, 0.0001)


# -- mass: consumes MaterialProperties, never reimplements it --------------

func test_part_mass_is_the_shared_density_times_its_own_derived_volume() -> void:
	var mp: RefCounted = MaterialProperties.new()
	assert_almost_eq(_edge().mass_kg(), mp.mass_kg_for("iron", 90.0), 0.0000001)


func test_an_iron_blade_masses_about_what_a_real_arming_sword_blade_does() -> void:
	# 0.70 kg for an 80cm blade. If a volume formula were wrong by an order of
	# magnitude this is the assertion that would catch it.
	assert_between(_edge().mass_kg(), 0.6, 0.8)


func test_the_same_shape_in_a_lighter_material_masses_less() -> void:
	assert_lt(_edge("wood").mass_kg(), _edge("iron").mass_kg())


# -- span and cross-section: what the graph's later layers actually read ----

## span_cm is the part's extent along its principal axis. Channel routing needs
## a real path LENGTH in cm (see docs/concept/emergent_crafting.md) and the
## leverage rule needs a real lever arm; both read this.
func test_span_is_the_principal_length_of_each_geometry() -> void:
	assert_almost_eq(_edge().span_cm(), 80.0, 0.0001, "an edge spans its length")
	var pommel: RefCounted = ItemPart.new(
		"iron", ItemPart.GEOMETRY_BULK, ItemPart.ROLE_COUNTERWEIGHT, {"diameter_cm": 4.5}
	)
	assert_almost_eq(pommel.span_cm(), 4.5, 0.0001, "a bulk spans its diameter")


## A slab's principal axis is its LONGER in-plane dimension, not whichever the
## caller happened to name "width" -- a 20x2 crossguard spans 20cm either way.
func test_a_face_spans_its_longer_in_plane_dimension_whichever_it_is_called() -> void:
	var wide: RefCounted = ItemPart.new(
		"iron", ItemPart.GEOMETRY_FACE, ItemPart.ROLE_STRUCTURE,
		{"width_cm": 20.0, "height_cm": 2.0, "thickness_cm": 0.8}
	)
	var tall: RefCounted = ItemPart.new(
		"iron", ItemPart.GEOMETRY_FACE, ItemPart.ROLE_STRUCTURE,
		{"width_cm": 2.0, "height_cm": 20.0, "thickness_cm": 0.8}
	)
	assert_almost_eq(wide.span_cm(), 20.0, 0.0001)
	assert_almost_eq(tall.span_cm(), 20.0, 0.0001)


## cross_section_cm2 is the area of a cut made ACROSS the span -- the section
## that actually carries load, and therefore what a joint's strength is capped
## by (see part_joint.gd's load_capacity).
func test_cross_section_is_the_area_of_a_cut_across_the_span() -> void:
	assert_almost_eq(_edge().cross_section_cm2(), 0.5 * 4.5 * 0.5, 0.0001,
		"an edge's section is its wedge: half width x back thickness")
	var grip: RefCounted = ItemPart.new(
		"wood", ItemPart.GEOMETRY_HAFT, ItemPart.ROLE_GRIP,
		{"length_cm": 11.0, "diameter_cm": 3.2}
	)
	assert_almost_eq(grip.cross_section_cm2(), PI * 1.6 * 1.6, 0.0001,
		"a haft's section is its circle")


func test_a_face_section_is_its_shorter_in_plane_dimension_times_thickness() -> void:
	var guard: RefCounted = ItemPart.new(
		"iron", ItemPart.GEOMETRY_FACE, ItemPart.ROLE_STRUCTURE,
		{"width_cm": 20.0, "height_cm": 2.0, "thickness_cm": 0.8}
	)
	assert_almost_eq(guard.cross_section_cm2(), 2.0 * 0.8, 0.0001)


# -- keenness: docs/concept/materials.md's "edge (length, angle -> keenness --
# -- potential)", the reason angle_deg is a required edge dimension ---------
#
# Grounded in real sharpening practice, not eyeballed: cutlers and woodworkers
# grind razors and scalpels at ~15 degrees included and felling-axe bits at
# ~40, and those two are exactly the ends of the useful range -- below 15 you
# are limited by the steel, not the angle, and at 40 you have a splitting
# wedge rather than a cutter. So the angle term is a straight line between
# those two real numbers, scaling the material's own sharpness_capacity.

func test_a_razor_ground_edge_realizes_the_materials_full_sharpness_capacity() -> void:
	var mp: RefCounted = MaterialProperties.new()
	var razor: RefCounted = ItemPart.new(
		"obsidian", ItemPart.GEOMETRY_EDGE, ItemPart.ROLE_WORKING,
		{"length_cm": 10.0, "width_cm": 2.0, "thickness_cm": 0.2,
		 "angle_deg": ItemPart.KEEN_ANGLE_DEG}
	)
	assert_almost_eq(
		razor.keenness(), mp.property_value("obsidian", "sharpness_capacity"), 0.0001
	)


func test_an_axe_ground_edge_is_a_splitting_wedge_with_no_keenness_left() -> void:
	var bit: RefCounted = ItemPart.new(
		"iron", ItemPart.GEOMETRY_EDGE, ItemPart.ROLE_WORKING,
		{"length_cm": 10.0, "width_cm": 6.0, "thickness_cm": 2.0,
		 "angle_deg": ItemPart.WEDGE_ANGLE_DEG}
	)
	assert_almost_eq(bit.keenness(), 0.0, 0.0001)


func test_the_two_sharpening_angles_are_the_real_razor_and_axe_bit_numbers() -> void:
	assert_almost_eq(ItemPart.KEEN_ANGLE_DEG, 15.0, 0.0001,
		"a razor/scalpel bevel -- below this the steel, not the angle, is the limit")
	assert_almost_eq(ItemPart.WEDGE_ANGLE_DEG, 40.0, 0.0001,
		"a felling-axe bit -- a splitting wedge, not a cutter")


func test_a_keener_grind_beats_a_fatter_one_in_the_same_material() -> void:
	assert_gt(_edge().keenness(), _edge().keenness() * 0.0,
		"a 20-degree iron edge has real keenness")
	var fat: RefCounted = ItemPart.new(
		"iron", ItemPart.GEOMETRY_EDGE, ItemPart.ROLE_WORKING,
		{"length_cm": 80.0, "width_cm": 4.5, "thickness_cm": 0.5, "angle_deg": 32.0}
	)
	assert_gt(_edge().keenness(), fat.keenness())


func test_obsidian_out_keens_iron_at_the_identical_grind() -> void:
	var glass: RefCounted = _edge("obsidian")
	assert_gt(glass.keenness(), _edge("iron").keenness(),
		"obsidian's sharpness_capacity 10 beats iron's 8 at the same angle")


func test_only_an_edge_has_keenness_at_all() -> void:
	var grip: RefCounted = ItemPart.new(
		"iron", ItemPart.GEOMETRY_HAFT, ItemPart.ROLE_GRIP,
		{"length_cm": 11.0, "diameter_cm": 3.2}
	)
	assert_almost_eq(grip.keenness(), 0.0, 0.0001, "a haft has no edge to be keen")


# -- the material vector reaches later layers through the part -------------

func test_a_part_reports_its_own_materials_properties() -> void:
	var mp: RefCounted = MaterialProperties.new()
	assert_almost_eq(
		_edge("obsidian").property_value("toughness"),
		mp.property_value("obsidian", "toughness"), 0.0001
	)


# -- malformed parts are rejected explicitly, never silently mis-massed ----
#
# The alternative -- letting an unknown material fall through to
# DEFAULT_PROPERTIES' density 1.0 -- would hand back a confident, wrong mass,
# which is exactly the "fails later in a confusing way" this rejects.

func test_a_well_formed_part_is_valid_and_has_no_error() -> void:
	assert_true(_edge().is_valid())
	assert_eq(_edge().validation_error(), "")


func test_an_unknown_geometry_is_rejected_and_says_so() -> void:
	var bad: RefCounted = ItemPart.new("iron", "sprocket", ItemPart.ROLE_WORKING, {})
	assert_false(bad.is_valid())
	assert_string_contains(bad.validation_error(), "sprocket")


func test_an_unknown_role_is_rejected_and_says_so() -> void:
	var bad: RefCounted = ItemPart.new(
		"iron", ItemPart.GEOMETRY_BULK, "decoration", {"diameter_cm": 4.0}
	)
	assert_false(bad.is_valid())
	assert_string_contains(bad.validation_error(), "decoration")


func test_an_unmodeled_material_is_rejected_rather_than_silently_massed() -> void:
	var bad: RefCounted = _edge("unobtainium")
	assert_false(bad.is_valid())
	assert_string_contains(bad.validation_error(), "unobtainium")


func test_a_missing_dimension_is_rejected_and_names_the_dimension() -> void:
	var bad: RefCounted = ItemPart.new(
		"iron", ItemPart.GEOMETRY_EDGE, ItemPart.ROLE_WORKING,
		{"length_cm": 80.0, "width_cm": 4.5, "angle_deg": 20.0}
	)
	assert_false(bad.is_valid())
	assert_string_contains(bad.validation_error(), "thickness_cm")


func test_a_non_positive_dimension_is_rejected() -> void:
	var bad: RefCounted = ItemPart.new(
		"wood", ItemPart.GEOMETRY_HAFT, ItemPart.ROLE_GRIP,
		{"length_cm": 0.0, "diameter_cm": 3.2}
	)
	assert_false(bad.is_valid())
	assert_string_contains(bad.validation_error(), "length_cm")


## An included angle of 180 degrees or more is not an angle, it is a flat
## sheet; 0 or less is not a solid at all.
func test_an_impossible_included_angle_is_rejected() -> void:
	var bad: RefCounted = ItemPart.new(
		"iron", ItemPart.GEOMETRY_POINT, ItemPart.ROLE_WORKING,
		{"length_cm": 6.0, "angle_deg": 180.0}
	)
	assert_false(bad.is_valid())
	assert_string_contains(bad.validation_error(), "angle_deg")


## 0.0 is this project's existing "not modeled" value (see Item.mass_kg's own
## doc comment) -- an invalid part answers with it rather than crashing, so a
## malformed graph is caught by validation rather than by a stack trace.
func test_an_invalid_part_answers_zero_instead_of_crashing() -> void:
	var bad: RefCounted = ItemPart.new("iron", "sprocket", ItemPart.ROLE_WORKING, {})
	assert_almost_eq(bad.volume_cm3(), 0.0, 0.0001)
	assert_almost_eq(bad.mass_kg(), 0.0, 0.0001)
	assert_almost_eq(bad.span_cm(), 0.0, 0.0001)
	assert_almost_eq(bad.cross_section_cm2(), 0.0, 0.0001)
	assert_almost_eq(bad.keenness(), 0.0, 0.0001)


# -- determinism -----------------------------------------------------------

func test_two_identically_built_parts_answer_identically() -> void:
	assert_almost_eq(_edge().volume_cm3(), _edge().volume_cm3(), 0.0)
	assert_almost_eq(_edge().mass_kg(), _edge().mass_kg(), 0.0)


## The part owns a COPY of its dimensions: a caller mutating the dictionary it
## passed in must not silently change an already-built part's mass.
func test_a_part_does_not_share_the_dimension_dictionary_it_was_built_from() -> void:
	var dims := {"length_cm": 11.0, "diameter_cm": 3.2}
	var grip: RefCounted = ItemPart.new(
		"wood", ItemPart.GEOMETRY_HAFT, ItemPart.ROLE_GRIP, dims
	)
	var before: float = grip.volume_cm3()
	dims["length_cm"] = 999.0
	assert_almost_eq(grip.volume_cm3(), before, 0.0001)
