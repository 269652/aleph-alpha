extends GutTest

## AssemblyId: an emergent item's id IS a content hash of its canonical
## structure.
##
## The requirement driving every test here is that a player who attaches the
## pommel before the grip has built the SAME sword -- so the id must be an
## isomorphism invariant of the part/joint graph, not a function of the order
## the player happened to list things in. A false SPLIT (one real item, two
## ids) is the failure that matters most: it breaks stacking, trading, and the
## save round-trip all at once.

const AssemblyId = preload("res://src/gameplay/assembly_id.gd")
const MaterialProperties = preload("res://src/gameplay/material_properties.gd")

## One gram in kilograms -- the finest reading of a real balance, and so the
## precision floor the volume quantum is calibrated against.
const GRAM_KG := 0.001


func _part(material: String, geometry: String, role: String) -> Dictionary:
	return {"material": material, "geometry": geometry, "role": role}


func _sword(blade_material: String = "iron") -> Dictionary:
	return {
		"pattern": "sword",
		"parts": [
			{
				"material": blade_material,
				"geometry": "blade",
				"role": "edge",
				"length_cm": 70.0,
				"width_cm": 4.5,
				"treatment": {"sharpening": 0.75},
			},
			{"material": "wood", "geometry": "rod", "role": "grip", "length_cm": 12.0},
			{"material": "bronze", "geometry": "disc", "role": "pommel", "width_cm": 5.0},
		],
		"joints": [
			{"kind": "tang", "a": 0, "b": 1},
			{"kind": "peened", "a": 1, "b": 2},
		],
	}


# --- order independence: the property the whole design exists for ---


func test_two_assemblies_differing_only_in_part_order_share_an_id():
	var blade := _part("iron", "blade", "edge")
	var grip := _part("wood", "rod", "grip")
	var blade_first := {
		"pattern": "sword",
		"parts": [blade, grip],
		"joints": [{"kind": "tang", "a": 0, "b": 1}],
	}
	var grip_first := {
		"pattern": "sword",
		"parts": [grip, blade],
		"joints": [{"kind": "tang", "a": 1, "b": 0}],
	}
	assert_eq(AssemblyId.assembly_id(blade_first), AssemblyId.assembly_id(grip_first))


func test_listing_the_joints_in_a_different_order_shares_an_id():
	var forward := _sword()
	var reversed := _sword()
	reversed["joints"] = [reversed["joints"][1], reversed["joints"][0]]
	assert_eq(AssemblyId.assembly_id(forward), AssemblyId.assembly_id(reversed))


## Every one of the 6 orderings of a 3-part sword must land on one id, not
## just the one pair a single swap happens to cover.
func test_every_permutation_of_a_three_part_sword_shares_one_id():
	var base := _sword()
	var ids := {}
	for order in [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]:
		ids[AssemblyId.assembly_id(_reordered(base, order))] = true
	assert_eq(ids.size(), 1, "all 6 listings are the same sword")


## Relabels `assembly` so that canonical position i holds the part originally
## at order[i], remapping every joint index to match -- i.e. the same physical
## object, described in a different order.
func _reordered(assembly: Dictionary, order: Array) -> Dictionary:
	var parts: Array = assembly["parts"]
	var new_parts := []
	var old_to_new := {}
	for new_index in order.size():
		new_parts.append(parts[order[new_index]])
		old_to_new[order[new_index]] = new_index
	var new_joints := []
	for joint in assembly["joints"]:
		var moved: Dictionary = joint.duplicate(true)
		moved["a"] = old_to_new[joint["a"]]
		moved["b"] = old_to_new[joint["b"]]
		new_joints.append(moved)
	return {"pattern": assembly["pattern"], "parts": new_parts, "joints": new_joints}


# --- the hard case: two structurally interchangeable identical parts ---


## The case a naive "sort the parts, remap the indices" canonicaliser gets
## WRONG. Two identical iron heads, one on the grip and one on the pommel:
## which head went where is not a fact about the object, so swapping them is
## the same object and must be one id. A stable sort leaves the tied heads in
## input order, so the remapped joints come out different and the id splits.
func test_swapping_two_interchangeable_identical_parts_shares_an_id():
	var head := _part("iron", "spike", "head")
	var grip := _part("wood", "rod", "grip")
	var pommel := _part("stone", "disc", "pommel")
	var head_zero_on_grip := {
		"pattern": "pick",
		"parts": [head, head.duplicate(true), grip, pommel],
		"joints": [{"kind": "socket", "a": 0, "b": 2}, {"kind": "socket", "a": 1, "b": 3}],
	}
	var head_one_on_grip := {
		"pattern": "pick",
		"parts": [head, head.duplicate(true), grip, pommel],
		"joints": [{"kind": "socket", "a": 1, "b": 2}, {"kind": "socket", "a": 0, "b": 3}],
	}
	assert_eq(
		AssemblyId.assembly_id(head_zero_on_grip), AssemblyId.assembly_id(head_one_on_grip)
	)


## ...but identical parts must NOT collapse genuinely different topologies.
## Two heads both socketed onto one haft (a double-headed tool) is not the
## same object as head-onto-head-onto-haft (a chain), even though the part
## list is byte-identical.
func test_identical_parts_in_a_different_topology_get_different_ids():
	var head := _part("iron", "spike", "head")
	var haft := _part("wood", "rod", "haft")
	var star := {
		"pattern": "pick",
		"parts": [head, head.duplicate(true), haft],
		"joints": [{"kind": "socket", "a": 2, "b": 0}, {"kind": "socket", "a": 2, "b": 1}],
	}
	var chain := {
		"pattern": "pick",
		"parts": [head, head.duplicate(true), haft],
		"joints": [{"kind": "socket", "a": 0, "b": 1}, {"kind": "socket", "a": 1, "b": 2}],
	}
	assert_ne(AssemblyId.assembly_id(star), AssemblyId.assembly_id(chain))


## A joint is directional -- a tang runs from the blade INTO the grip, not the
## other way round -- so reversing one must be a different object.
func test_reversing_a_joints_direction_changes_the_id():
	var forward := _sword()
	var backward := _sword()
	backward["joints"][0] = {"kind": "tang", "a": 1, "b": 0}
	assert_ne(AssemblyId.assembly_id(forward), AssemblyId.assembly_id(backward))


# --- content sensitivity ---


func test_swapping_one_material_changes_the_id():
	assert_ne(AssemblyId.assembly_id(_sword("iron")), AssemblyId.assembly_id(_sword("bronze")))


func test_changing_a_joint_kind_changes_the_id():
	var pinned := _sword()
	pinned["joints"][0] = {"kind": "riveted", "a": 0, "b": 1}
	assert_ne(AssemblyId.assembly_id(_sword()), AssemblyId.assembly_id(pinned))


func test_changing_the_pattern_changes_the_id():
	var dagger := _sword()
	dagger["pattern"] = "dagger"
	assert_ne(AssemblyId.assembly_id(_sword()), AssemblyId.assembly_id(dagger))


func test_dropping_a_part_changes_the_id():
	var hiltless := _sword()
	hiltless["parts"] = [hiltless["parts"][0], hiltless["parts"][1]]
	hiltless["joints"] = [{"kind": "tang", "a": 0, "b": 1}]
	assert_ne(AssemblyId.assembly_id(_sword()), AssemblyId.assembly_id(hiltless))


# --- determinism ---


func test_ids_are_stable_across_separate_canonicalisations():
	var first := AssemblyId.assembly_id(_sword())
	var second := AssemblyId.assembly_id(_sword())
	assert_eq(first, second)


func test_canonicalising_twice_gives_the_same_canonical_form():
	assert_eq(AssemblyId.canonical_form(_sword()), AssemblyId.canonical_form(_sword()))


func test_canonicalising_does_not_mutate_the_assembly_it_was_given():
	var sword := _sword()
	var before := str(sword)
	AssemblyId.canonical_form(sword)
	assert_eq(str(sword), before)


func test_an_id_is_prefixed_and_fixed_width():
	var id: String = AssemblyId.assembly_id(_sword())
	assert_true(id.begins_with("asm_"), "ids are namespaced so a save can tell them apart")
	assert_eq(id.length(), 4 + 16, "asm_ + 64 hash bits as hex")


## A REGRESSION PIN, not a driver: this exact string was produced by the
## implementation and is frozen here so an accidental change to the
## canonicalisation, the byte encoding, or the hash constants -- any of which
## would silently orphan every crafted item in every existing save -- fails
## loudly instead. Changing this literal is only ever correct alongside a
## deliberate save migration.
const PINNED_SWORD_ID := "asm_b613300e00eeb751"


func test_a_known_assembly_hashes_to_its_pinned_id():
	assert_eq(AssemblyId.assembly_id(_sword()), PINNED_SWORD_ID)


# --- quantization: the id space must stay bounded ---


## Real grounding: a smith works and a player perceives an object to the
## millimetre. Sub-millimetre variation is not a different sword, and if it
## minted an id the id space would be unbounded (every float would be its own
## item).
func test_the_dimension_quantum_is_one_real_millimetre():
	assert_almost_eq(AssemblyId.DIMENSION_QUANTUM_CM, 0.1, 0.0001)


func test_dimensions_are_quantized_to_whole_millimetres():
	assert_eq(AssemblyId.quantize_dimension_cm(70.0), 700)
	assert_eq(AssemblyId.quantize_dimension_cm(70.04), 700, "rounds down within the quantum")
	assert_eq(AssemblyId.quantize_dimension_cm(70.06), 701, "rounds up across it")


func test_sub_millimetre_length_differences_do_not_mint_a_new_id():
	var a := _sword()
	var b := _sword()
	b["parts"][0]["length_cm"] = 70.02
	assert_eq(AssemblyId.assembly_id(a), AssemblyId.assembly_id(b))


func test_a_whole_millimetre_length_difference_does_mint_a_new_id():
	var a := _sword()
	var b := _sword()
	b["parts"][0]["length_cm"] = 70.1
	assert_ne(AssemblyId.assembly_id(a), AssemblyId.assembly_id(b))


## The densest material MaterialProperties currently models, read from the
## model rather than named here. Which material that is has already changed
## once (iron, until copper's 8.96 g/cm^3 arrived with the alloy work), so the
## calibration below deliberately asserts the physical INVARIANT rather than
## the material's identity -- naming it would make this test fail every time
## the roster grows, including when the quantum is still perfectly correct.
func _densest_modelled_material() -> String:
	var properties := MaterialProperties.new()
	var densest := ""
	var best := 0.0
	for material in MaterialProperties.MATERIALS:
		var density := properties.property_value(material, "density")
		if density > best:
			best = density
			densest = material
	return densest


## Real grounding, DERIVED from the shipped material model rather than
## retyped: a kitchen/apothecary balance reads to the gram, so a volume
## difference that cannot move a scale must not be allowed to mint an id. The
## worst case is the DENSEST material the game models -- one quantum of it has
## to weigh under a gram.
##
## Reading MaterialProperties' own densities is what stops the two from
## drifting. Add a material dense enough to break the bound and this fails,
## forcing the quantum to be re-derived instead of the claim quietly becoming
## false.
func test_the_volume_quantum_is_finer_than_a_balance_can_read():
	var properties := MaterialProperties.new()
	var densest := _densest_modelled_material()
	var quantum_mass_kg := properties.mass_kg_for(densest, AssemblyId.VOLUME_QUANTUM_CM3)
	assert_lt(
		quantum_mass_kg,
		GRAM_KG,
		"one quantum of %s (the densest modelled) must not move a balance" % densest
	)


## And it is not needlessly finer than that either. A quantum ten times LARGER
## would be perceptible -- it puts nearly ten grams of the densest material on
## the scale -- so 0.05cm^3 is close to the coarsest quantum that still hides
## under the threshold, not an arbitrarily small one multiplying the reachable
## id space for precision no hand can use.
func test_the_volume_quantum_is_no_finer_than_it_needs_to_be():
	var properties := MaterialProperties.new()
	var densest := _densest_modelled_material()
	var ten_quanta_kg := properties.mass_kg_for(densest, AssemblyId.VOLUME_QUANTUM_CM3 * 10.0)
	assert_gt(ten_quanta_kg, GRAM_KG, "ten quanta of %s DO read on a balance" % densest)


func test_volumes_are_quantized_to_whole_quanta():
	assert_eq(AssemblyId.quantize_volume_cm3(120.0), 2400)
	assert_eq(AssemblyId.quantize_volume_cm3(120.02), 2400, "rounds down within the quantum")
	assert_eq(AssemblyId.quantize_volume_cm3(120.03), 2401, "rounds up across it")


## A reader of a canonical form (CraftedItemRegistry's real mass) has to get
## back the volume that went in, or a crafted item's mass would be quantization
## error rather than physics.
func test_a_quantized_volume_round_trips_back_to_real_cubic_centimetres():
	assert_almost_eq(
		AssemblyId.dequantize_volume_cm3(AssemblyId.quantize_volume_cm3(120.0)), 120.0, 0.0001
	)


## Volume must quantize on its OWN suffix, not fall through to the treatment
## ladder -- 120.0 read as a 0..1 process level would land on rung 960 and two
## swords differing by a cubic centimetre would collide.
func test_a_volume_field_is_not_mistaken_for_a_process_level():
	var a := _sword()
	var b := _sword()
	a["parts"][0]["volume_cm3"] = 120.0
	b["parts"][0]["volume_cm3"] = 121.0
	assert_ne(AssemblyId.assembly_id(a), AssemblyId.assembly_id(b))


func test_sub_quantum_volume_differences_do_not_mint_a_new_id():
	var a := _sword()
	var b := _sword()
	a["parts"][0]["volume_cm3"] = 120.0
	b["parts"][0]["volume_cm3"] = 120.02
	assert_eq(AssemblyId.assembly_id(a), AssemblyId.assembly_id(b))


## Real grounding: sharpening is not a continuum in practice, it is a ladder
## of perceptibly distinct stages. A real waterstone progression runs roughly
## #220 / #400 / #1000 / #3000 / #6000 / #8000 -- six stones -- with "blunt"
## below the first and "stropped" above the last, which is eight steps from
## dull to razor. Anything finer is a distinction no hand and no cut can make.
func test_the_treatment_ladder_has_one_step_per_real_whetstone_stage():
	assert_eq(AssemblyId.TREATMENT_LEVELS, 8)


func test_treatments_are_quantized_to_the_ladders_rungs():
	assert_eq(AssemblyId.quantize_treatment(0.0), 0)
	assert_eq(AssemblyId.quantize_treatment(1.0), AssemblyId.TREATMENT_LEVELS)
	assert_eq(AssemblyId.quantize_treatment(0.5), 4)


## THE bound that matters: honing a blade must not mint a new item per
## whetstone stroke. A thousand strokes across the full range can only ever
## produce the nine rungs of the ladder (0 through TREATMENT_LEVELS).
func test_sharpening_across_its_full_range_mints_a_bounded_number_of_ids():
	var ids := {}
	for step in 1000:
		var honed := _sword()
		honed["parts"][0]["treatment"]["sharpening"] = float(step) / 999.0
		ids[AssemblyId.assembly_id(honed)] = true
	assert_eq(ids.size(), AssemblyId.TREATMENT_LEVELS + 1)


# --- collision resistance and dispersion ---


## 600 genuinely different assemblies across four independent axes must be 600
## different ids. A false MERGE here would silently turn one player's bronze
## dagger into another's iron sword on a trade.
func test_many_distinct_assemblies_get_distinct_ids():
	var ids := {}
	var expected := 0
	for material in ["iron", "bronze", "wood", "stone", "obsidian", "bone"]:
		for geometry in ["blade", "spike", "disc", "rod", "plate"]:
			for length_mm in [100, 200, 300, 400, 500]:
				for sharpening in [0.0, 0.25, 0.5, 0.75]:
					expected += 1
					var assembly := {
						"pattern": "tool",
						"parts": [
							{
								"material": material,
								"geometry": geometry,
								"role": "head",
								"length_cm": float(length_mm) / 10.0,
								"treatment": {"sharpening": sharpening},
							},
							_part("wood", "rod", "haft"),
						],
						"joints": [{"kind": "socket", "a": 0, "b": 1}],
					}
					ids[AssemblyId.assembly_id(assembly)] = true
	assert_eq(ids.size(), expected)


## The failure mode pixel_noise.gd documents this project being bitten by
## twice: Godot's string hash() correlates across near-identical inputs, so a
## run of neighbouring values froze into one bucket. 512 assemblies one
## millimetre apart must scatter across the whole id space, not clump.
func test_neighbouring_assemblies_scatter_across_the_id_space():
	var buckets := {}
	for step in 512:
		var assembly := _sword()
		assembly["parts"][0]["length_cm"] = 10.0 + float(step) * AssemblyId.DIMENSION_QUANTUM_CM
		var nibble: String = AssemblyId.assembly_id(assembly).substr(4, 1)
		buckets[nibble] = int(buckets.get(nibble, 0)) + 1
	assert_eq(buckets.size(), 16, "every one of the 16 leading nibbles is reached")
	var fullest := 0
	for nibble in buckets:
		fullest = maxi(fullest, int(buckets[nibble]))
	assert_lt(fullest, 96, "no bucket holds 3x its 32-sample share")


# --- documented limits ---


## Six mutually interchangeable parts is 6! = 720 orderings, exactly the
## search budget, so the canonical form is still an exact certificate.
func test_six_interchangeable_parts_still_canonicalise_exactly():
	var form := AssemblyId.canonical_form(_identical_bundle(6))
	assert_true(form["exact"])


## Seven is 5040 orderings, past the budget, so the id falls back to a
## colour-refinement invariant -- still deterministic and still
## order-independent, but no longer provably collision-free for pathological
## graphs. The form says so rather than pretending.
func test_past_the_budget_the_form_says_it_is_an_invariant_not_a_certificate():
	var form := AssemblyId.canonical_form(_identical_bundle(7))
	assert_false(form["exact"])


func test_the_orbit_budget_is_the_full_symmetric_group_on_six_parts():
	assert_eq(AssemblyId.MAX_ORBIT_PERMUTATIONS, 720)


## Even on the fallback path the id must not depend on listing order. A closed
## ring of seven identical links is the worst case for this: it is
## vertex-transitive, so refinement never separates anything and all seven
## parts stay in one orbit, past the budget. Listed here twice with the links
## scrambled into a genuinely different order.
func test_the_fallback_path_is_still_order_independent():
	var ring := _identical_ring(7)
	assert_false(AssemblyId.canonical_form(ring)["exact"], "this really is the fallback path")
	var scrambled := _reordered(ring, [0, 2, 4, 6, 1, 3, 5])
	assert_ne(str(ring["joints"]), str(scrambled["joints"]), "the two listings really differ")
	assert_eq(AssemblyId.assembly_id(ring), AssemblyId.assembly_id(scrambled))


func _identical_bundle(count: int) -> Dictionary:
	var parts := []
	for _i in count:
		parts.append(_part("iron", "rod", "filler"))
	return {"pattern": "bundle", "parts": parts, "joints": []}


func _identical_ring(count: int) -> Dictionary:
	var ring := _identical_bundle(count)
	var joints := []
	for index in count:
		joints.append({"kind": "link", "a": index, "b": (index + 1) % count})
	ring["joints"] = joints
	ring["pattern"] = "chain"
	return ring


# --- degenerate input must never crash ---


func test_an_empty_assembly_still_gets_an_id():
	assert_true(AssemblyId.assembly_id({}).begins_with("asm_"))


func test_a_single_part_assembly_with_no_joints_gets_an_id():
	var shard := {"pattern": "shard", "parts": [_part("obsidian", "flake", "edge")], "joints": []}
	assert_true(AssemblyId.assembly_id(shard).begins_with("asm_"))


## An unknown extra field must be carried into the id rather than dropped --
## this shape is deliberately forward-compatible with the Part/Joint classes
## being built in parallel, and a field the canonicaliser silently ignored
## would merge two items that later turn out to differ.
func test_an_unrecognised_part_field_still_affects_the_id():
	var plain := _sword()
	var engraved := _sword()
	engraved["parts"][0]["inscription"] = "aleph"
	assert_ne(AssemblyId.assembly_id(plain), AssemblyId.assembly_id(engraved))
