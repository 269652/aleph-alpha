extends RefCounted

## An emergent item's id IS a content hash of its canonical structure.
##
## Two real, verified bugs made this necessary before any emergent item could
## exist at all (see docs/concept/item_identity.md):
##   - scenes/player.gd:860-862 loads inventory with
##     `if _item_catalog.has(entry.id)` and :866-868 does the same for
##     equipment with a `continue` -- any id the static ItemCatalog does not
##     know is SILENTLY DROPPED, so every crafted item would evaporate on
##     save/load;
##   - src/gameplay/item_stack.gd:45 `can_stack_with` compares ids and nothing
##     else, so two different items sharing an id would merge and one would be
##     silently lost.
## A content-addressed id fixes both from one end: an id that IS the structure
## cannot name two different structures, so id-only stacking becomes correct
## rather than a bug, and a CraftedItemRegistry keyed by that id gives the
## loader something to resolve unknown ids against.
##
## ## The assembly shape this accepts
##
## A plain Dictionary -- deliberately NOT the Part/Joint/PartGraph classes
## being built in parallel, so the two can land independently and compose
## later. Everything is optional; unknown fields are carried into the id
## rather than dropped (see test_an_unrecognised_part_field_still_affects_the_id),
## which is what makes the shape forward-compatible:
##
##     {
##       "pattern": "sword",                       # optional String
##       "parts": [                                # small, <= 8 by design
##         {
##           "material": "iron",                   # any string keys/values
##           "geometry": "blade",
##           "role": "edge",
##           "length_cm": 70.0,                    # any *_cm key: real cm
##           "treatment": {"sharpening": 0.75},    # 0..1 process levels
##         }, ...
##       ],
##       "joints": [
##         {"kind": "tang", "a": 0, "b": 1},       # a/b index into "parts"
##       ],
##     }
##
## `a` -> `b` is DIRECTIONAL (a tang runs from the blade into the grip, not the
## other way round). Any float under a key ending `_cm` is a real-world
## centimetre measurement; every other float is a 0..1 process level. Joint
## endpoints that do not index a real part are kept verbatim in a separate
## `dangling_joints` list rather than crashing -- a save file must never be
## able to take the game down.
##
## ## How order-independence is achieved, and where it stops
##
## A player who attaches the pommel before the grip has built the SAME sword,
## so the id must be an invariant of the part/joint graph up to isomorphism.
## That is a real graph-canonicalisation problem and the honest answer for the
## bounded case here is three stages, not a sort:
##
##  1. **Quantize** every continuous field to integers (below), so the
##     canonical form contains no floats at all and cannot vary with float
##     formatting.
##  2. **Colour refinement** (1-WL): a part's colour starts as its own content
##     and is repeatedly replaced by a hash of itself plus the sorted multiset
##     of (joint, direction, neighbour colour) around it, for as many rounds as
##     there are parts -- which is more than enough for 1-WL to stabilise.
##     This alone separates parts that a plain content sort ties: two identical
##     iron heads, one on the grip and one on the pommel, get different colours
##     because their neighbourhoods differ.
##  3. **Exhaustive tie-breaking** inside whatever orbits survive refinement.
##     Parts sharing a refined colour AND identical content are genuinely
##     interchangeable, so every ordering of them is enumerated and the
##     lexicographically smallest serialization wins. Because the orbits are
##     themselves order-independent, the *set* of candidate orderings is the
##     same for any listing of the same object, so the minimum is too.
##
## **The limit, stated honestly.** Stage 3 is capped at MAX_ORBIT_PERMUTATIONS
## orderings. Past that cap -- which needs seven or more mutually
## interchangeable parts in a vertex-transitive arrangement, e.g. a closed ring
## of seven identical links -- the canonical form degrades to the stage-2
## refinement invariant, and says so via its `exact` field. That fallback is
## still fully deterministic and still order-independent (it never splits one
## object into two ids, which is the failure that would actually hurt), but it
## is an invariant rather than a certificate: 1-WL cannot distinguish some
## pathologically regular graphs, so two genuinely different such assemblies
## could in principle collide. No real item is that graph, and the flag makes
## the degradation visible instead of silent. Do not read more generality into
## this than that.

## Real-world grounding: a smith works, and a hand perceives, to the
## millimetre. Sub-millimetre variation is not a different sword -- and if it
## minted an id, the id space would be unbounded, since every float would be
## its own item. Pinned by test_the_dimension_quantum_is_one_real_millimetre /
## test_sub_millimetre_length_differences_do_not_mint_a_new_id.
const DIMENSION_QUANTUM_CM := 0.1

## Real-world grounding: sharpening (and every other process level) is not a
## continuum in practice, it is a ladder of perceptibly distinct stages. A real
## waterstone progression runs roughly #220 / #400 / #1000 / #3000 / #6000 /
## #8000 -- six stones -- with "blunt" below the first and "stropped on
## leather" above the last: eight steps from dull to razor. Finer than that is
## a distinction no hand and no cut can make, so honing a blade mints at most
## nine ids across its whole life instead of one per stroke. Pinned by
## test_the_treatment_ladder_has_one_step_per_real_whetstone_stage /
## test_sharpening_across_its_full_range_mints_a_bounded_number_of_ids.
const TREATMENT_LEVELS := 8

## Real-world grounding: a balance reads to the gram, so a volume difference
## that cannot move a scale must not mint an id. One quantum of the DENSEST
## material the game models has to weigh under a gram for that to hold.
##
## Re-derived 2026-08-28, exactly as
## test_the_volume_quantum_is_finer_than_a_balance_can_read's own doc comment
## says it must be: the densest modelled material used to be iron at 7.8 g/cm^3
## (0.1 cm^3 = 0.78 g, comfortably under), but material_properties.gd's
## conductivity/organics pass added GOLD at 19.30 g/cm^3 -- two and a half times
## denser -- and 0.1 cm^3 of gold is 1.93 g, which a balance reads plainly. The
## quantum halves to 0.05 cm^3, where one quantum of gold is 0.97 g (still
## under) and ten quanta are 9.7 g (still plainly perceptible, so it is not
## needlessly fine either). Pinned against MaterialProperties' own densities by
## that test and by test_the_volume_quantum_is_no_finer_than_it_needs_to_be,
## which bracket it from both sides.
const VOLUME_QUANTUM_CM3 := 0.05

## How many candidate orderings stage 3 will enumerate before falling back to
## the refinement invariant.
##
## Refinement already separates every part with a distinguishable
## neighbourhood, so an orbit only survives when parts are *genuinely*
## interchangeable -- a matched pair of heads, a ring of identical rivets. 720
## is 6!, the full symmetric group on six such parts: three quarters of the
## 8-part design ceiling, at a worst case of 720 candidate serializations.
## Beyond it the exhaustive search stops being the cheap path and the invariant
## takes over. Pinned by
## test_the_orbit_budget_is_the_full_symmetric_group_on_six_parts /
## test_six_interchangeable_parts_still_canonicalise_exactly /
## test_past_the_budget_the_form_says_it_is_an_invariant_not_a_certificate.
const MAX_ORBIT_PERMUTATIONS := 720

## Any part/joint field whose key ends in `_cm` is a real-world centimetre
## measurement and `_cm3` a real-world volume; every other float is a 0..1
## process level and quantizes to the TREATMENT_LEVELS ladder. (`_cm3` is
## checked first only for clarity -- "volume_cm3" does not end in "_cm", so the
## two suffixes cannot actually collide.)
const _DIMENSION_SUFFIX := "_cm"
const _VOLUME_SUFFIX := "_cm3"

## FNV-1a, twice, over the canonical serialization's UTF-8 bytes.
##
## Deliberately NOT Godot's `hash()`. Two reasons, both load-bearing:
##   - `hash()` correlates badly across near-identical inputs, and this project
##     has been bitten by exactly that twice (see pixel_noise.gd's own doc
##     comment: a frozen size bucket, whole rows of leaves at one angle). The
##     inputs here ARE near-identical by construction -- two swords differing
##     in one millimetre of blade.
##   - an id lives in a save file forever. `hash()` is an engine
##     implementation detail with no cross-version guarantee; FNV-1a is a
##     published byte-exact specification, so a save written today still reads
##     after a Godot upgrade.
##
## One 32-bit pass is not enough identity for a trading economy (~1e-4
## collision chance across a thousand items), so two independent passes give
## 64 bits: different offset basis, different odd multiplier, and opposite byte
## order, so the two passes never see the same input sequence. Both multipliers
## are chosen small enough that a masked 32-bit accumulator times the prime
## still fits in a signed 64-bit int, so nothing ever overflows.
const _FNV_OFFSET_BASIS := 0x811C9DC5
const _FNV_PRIME := 16777619
## The FNV basis XOR the golden-ratio constant 0x9E3779B9, and the same odd
## mixing prime pixel_noise.gd already uses -- a different starting point and a
## different multiplier, not a second opinion on the same one.
const _REVERSE_OFFSET_BASIS := 0x1F2BEA7C
const _REVERSE_PRIME := 668265263
const _WORD_MASK := 0xFFFFFFFF


## Real centimetres -> whole millimetres. The integer count of quanta, not a
## rounded float: the canonical form must contain no floats at all, or float
## formatting becomes part of the id.
static func quantize_dimension_cm(centimetres: float) -> int:
	return int(round(centimetres / DIMENSION_QUANTUM_CM))


## Real cubic centimetres -> whole VOLUME_QUANTUM_CM3 quanta.
static func quantize_volume_cm3(cubic_centimetres: float) -> int:
	return int(round(cubic_centimetres / VOLUME_QUANTUM_CM3))


## The inverse, so a reader of a canonical form (CraftedItemRegistry's real
## mass, say) never has to know the quantum to decode a stored volume.
static func dequantize_volume_cm3(quanta: int) -> float:
	return float(quanta) * VOLUME_QUANTUM_CM3


## A 0..1 process level -> its rung on the TREATMENT_LEVELS ladder. Not
## clamped: a caller that hands over an out-of-range level gets an
## out-of-range rung rather than a silently flattened one, so a bug upstream
## stays visible instead of merging two different items.
static func quantize_treatment(level: float) -> int:
	return int(round(level * float(TREATMENT_LEVELS)))


## The deterministic normal form of `assembly` -- see the class doc for the
## three stages and the documented limit. `exact` is true when the form is a
## full canonical certificate and false when it degraded to the refinement
## invariant. Never mutates the assembly it is given.
static func canonical_form(assembly: Dictionary) -> Dictionary:
	var raw_parts: Array = assembly.get("parts", [])
	var raw_joints: Array = assembly.get("joints", [])
	var pattern := String(assembly.get("pattern", ""))

	var part_forms: Array = []
	var part_keys: Array = []
	for part in raw_parts:
		var form = _quantized(part, "")
		part_forms.append(form)
		part_keys.append(_serialize(form))

	# [serialized fields, a, b, fields] for joints that index real parts;
	# anything else is kept verbatim so a corrupt save affects the id without
	# being able to crash the canonicaliser.
	var joint_forms: Array = []
	var dangling: Array = []
	for joint in raw_joints:
		var fields: Dictionary = (joint as Dictionary).duplicate(true)
		var a := int(fields.get("a", -1))
		var b := int(fields.get("b", -1))
		fields.erase("a")
		fields.erase("b")
		var quantized: Dictionary = _quantized(fields, "")
		if a < 0 or b < 0 or a >= part_forms.size() or b >= part_forms.size():
			var kept: Dictionary = quantized.duplicate(true)
			kept["a"] = a
			kept["b"] = b
			dangling.append(kept)
			continue
		joint_forms.append([_serialize(quantized), a, b, quantized])
	# Carried through rather than re-derived, so canonicalising an ALREADY
	# canonical form is a no-op. CraftedItemRegistry stores canonical forms and
	# re-registers what it read back off disk; if a second pass dropped these,
	# a reloaded save would mint a fresh id for an item it already had.
	for joint in assembly.get("dangling_joints", []):
		dangling.append(_quantized(joint, ""))
	dangling = _sorted_by_serialization(dangling)

	var colours := _refined_colours(part_keys, joint_forms)
	var sort_keys: Array = []
	for index in part_keys.size():
		sort_keys.append(colours[index] + "|" + part_keys[index])

	var groups := {}
	for index in sort_keys.size():
		if not groups.has(sort_keys[index]):
			groups[sort_keys[index]] = []
		groups[sort_keys[index]].append(index)
	var group_keys: Array = groups.keys()
	group_keys.sort()

	if _orderings_needed(group_keys, groups) > MAX_ORBIT_PERMUTATIONS:
		return _invariant_form(pattern, part_forms, sort_keys, colours, joint_forms, dangling)

	var best_form: Dictionary = {}
	var best_text := ""
	for ordering in _orderings(group_keys, groups):
		var candidate := _form_for_ordering(pattern, part_forms, joint_forms, dangling, ordering)
		var text := _serialize(candidate)
		if best_text == "" or text < best_text:
			best_text = text
			best_form = candidate
	return best_form


## `"asm_"` plus 64 hash bits of the canonical form, as hex. The prefix is a
## namespace, so a loader can tell a content-addressed id from a hand-authored
## ItemCatalog id ("iron_sword") at a glance.
static func assembly_id(assembly: Dictionary) -> String:
	return "asm_" + _hash_hex(_serialize(canonical_form(assembly)))


# --- stage 1: quantization -------------------------------------------------


## Recursively replaces every float with its integer quantum count, by the
## key it sits under. Returns new containers throughout, so the caller's
## assembly is never touched.
static func _quantized(value, key_name: String):
	match typeof(value):
		TYPE_DICTIONARY:
			var mapped := {}
			for key in value:
				mapped[String(key)] = _quantized(value[key], String(key))
			return mapped
		TYPE_ARRAY:
			var items: Array = []
			for item in value:
				items.append(_quantized(item, key_name))
			return items
		TYPE_FLOAT:
			if key_name.ends_with(_VOLUME_SUFFIX):
				return quantize_volume_cm3(float(value))
			if key_name.ends_with(_DIMENSION_SUFFIX):
				return quantize_dimension_cm(float(value))
			return quantize_treatment(float(value))
	return value


# --- stage 2: colour refinement -------------------------------------------


## 1-WL refinement: each part's colour becomes a hash of itself plus the sorted
## multiset of (direction, joint, neighbour colour) around it. Run for as many
## rounds as there are parts, which is strictly more than the n-1 needed for
## the partition to stabilise -- cheap enough at this size that detecting the
## fixed point would cost more than the extra rounds.
static func _refined_colours(part_keys: Array, joint_forms: Array) -> Array:
	var colours: Array = []
	for key in part_keys:
		colours.append(_hash_hex(key))
	for _round in part_keys.size():
		var next: Array = []
		for index in part_keys.size():
			var signature := PackedStringArray()
			for joint in joint_forms:
				if joint[1] == index:
					signature.append("out|" + joint[0] + "|" + colours[joint[2]])
				if joint[2] == index:
					signature.append("in|" + joint[0] + "|" + colours[joint[1]])
			signature.sort()
			next.append(_hash_hex(colours[index] + "#" + "&".join(signature)))
		colours = next
	return colours


# --- stage 3: exhaustive tie-breaking inside surviving orbits ---------------


## The product of the orbit factorials, bailing out the moment it passes the
## budget so a pathological assembly can never overflow the multiplication.
static func _orderings_needed(group_keys: Array, groups: Dictionary) -> int:
	var needed := 1
	for key in group_keys:
		var size: int = (groups[key] as Array).size()
		if size > 8:
			return MAX_ORBIT_PERMUTATIONS + 1
		needed *= _factorial(size)
		if needed > MAX_ORBIT_PERMUTATIONS:
			return needed
	return needed


static func _factorial(n: int) -> int:
	var result := 1
	for i in range(2, n + 1):
		result *= i
	return result


## Every ordering of the parts that respects the (order-independent) orbit
## grouping: orbits laid out in sorted-key order, every permutation inside each.
static func _orderings(group_keys: Array, groups: Dictionary) -> Array:
	var result: Array = [[]]
	for key in group_keys:
		var permutations := _permutations(groups[key])
		var next: Array = []
		for prefix in result:
			for permutation in permutations:
				next.append(prefix + permutation)
		result = next
	return result


static func _permutations(items: Array) -> Array:
	if items.size() <= 1:
		return [items.duplicate()]
	var result: Array = []
	for index in items.size():
		var rest: Array = items.duplicate()
		var picked = rest.pop_at(index)
		for tail in _permutations(rest):
			result.append([picked] + tail)
	return result


static func _form_for_ordering(
	pattern: String, part_forms: Array, joint_forms: Array, dangling: Array, ordering: Array
) -> Dictionary:
	var position := {}
	for slot in ordering.size():
		position[ordering[slot]] = slot
	var parts: Array = []
	for slot in ordering.size():
		parts.append(part_forms[ordering[slot]])
	var joints: Array = []
	for joint in joint_forms:
		var entry: Dictionary = (joint[3] as Dictionary).duplicate(true)
		entry["a"] = position[joint[1]]
		entry["b"] = position[joint[2]]
		joints.append(entry)
	return {
		"pattern": pattern,
		"parts": parts,
		"joints": _sorted_by_serialization(joints),
		"dangling_joints": dangling,
		"exact": true,
	}


## The documented fallback: parts ordered by their refined colour, joints
## expressed by the COLOURS of their endpoints instead of positions -- so no
## index survives to carry listing order. Order-independent by construction,
## but an invariant rather than a certificate (see the class doc).
static func _invariant_form(
	pattern: String,
	part_forms: Array,
	sort_keys: Array,
	colours: Array,
	joint_forms: Array,
	dangling: Array
) -> Dictionary:
	var keyed_parts: Array = []
	for index in part_forms.size():
		keyed_parts.append([sort_keys[index], part_forms[index]])
	keyed_parts.sort_custom(func(left, right): return left[0] < right[0])
	var parts: Array = []
	for entry in keyed_parts:
		parts.append(entry[1])

	var joints: Array = []
	for joint in joint_forms:
		var entry: Dictionary = (joint[3] as Dictionary).duplicate(true)
		entry["a_colour"] = colours[joint[1]]
		entry["b_colour"] = colours[joint[2]]
		joints.append(entry)

	return {
		"pattern": pattern,
		"parts": parts,
		"joints": _sorted_by_serialization(joints),
		"dangling_joints": dangling,
		"exact": false,
	}


static func _sorted_by_serialization(entries: Array) -> Array:
	var keyed: Array = []
	for entry in entries:
		keyed.append([_serialize(entry), entry])
	keyed.sort_custom(func(left, right): return left[0] < right[0])
	var sorted: Array = []
	for entry in keyed:
		sorted.append(entry[1])
	return sorted


# --- serialization and hashing ---------------------------------------------


## An injective text encoding of a canonical form. Dictionary keys are sorted
## (GDScript preserves insertion order, which is exactly the listing order this
## whole file exists to erase) and strings carry their own length, so no choice
## of delimiter can make two different forms encode the same way -- a collision
## in the encoding would be a collision the hash could never undo.
static func _serialize(value) -> String:
	match typeof(value):
		TYPE_DICTIONARY:
			var keys: Array = (value as Dictionary).keys()
			keys.sort()
			var pairs := PackedStringArray()
			for key in keys:
				pairs.append(_serialize(String(key)) + "=" + _serialize(value[key]))
			return "{" + "|".join(pairs) + "}"
		TYPE_ARRAY:
			var items := PackedStringArray()
			for item in value:
				items.append(_serialize(item))
			return "[" + "|".join(items) + "]"
		TYPE_STRING, TYPE_STRING_NAME:
			var text := String(value)
			return "s%d:%s" % [text.length(), text]
		TYPE_INT:
			return "i%d" % int(value)
		TYPE_BOOL:
			return "b1" if value else "b0"
		TYPE_FLOAT:
			# Should be unreachable after quantization; encoded through the
			# treatment ladder rather than float formatting so that even an
			# unquantized leak stays deterministic.
			return "q%d" % quantize_treatment(float(value))
		TYPE_NIL:
			return "n"
	return "?%s" % str(value)


static func _hash_hex(text: String) -> String:
	var bytes := text.to_utf8_buffer()
	var forward := _FNV_OFFSET_BASIS
	for index in bytes.size():
		forward = ((forward ^ bytes[index]) * _FNV_PRIME) & _WORD_MASK
	var backward := _REVERSE_OFFSET_BASIS
	for index in range(bytes.size() - 1, -1, -1):
		backward = ((backward ^ bytes[index]) * _REVERSE_PRIME) & _WORD_MASK
	return "%08x%08x" % [forward, backward]
