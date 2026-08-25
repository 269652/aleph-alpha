extends RefCounted

## The dependency-chain priority decision from docs/concept/timber_
## construction.md's "Storage, logistics, and the autonomous dependency
## chain" section: given a target recipe and what a settlement has on hand
## right now, decide whether the real priority should be "build the missing
## producer first" or "the existing shortfall/regional-trade path already
## covers this".
##
## Rebuilt on the real, general NeedResolver (src/gameplay/need_resolver.gd,
## see docs/concept/production_chains.md) instead of the old bespoke
## composition of CraftingRecipeBook + Smelting.can_smelt this doc's own
## gap note used to describe -- NeedResolver's recursive walk already
## answers exactly this question for ANY recipe (missing structure, missing
## skill, missing sub-material, however many hops down), not a one-hop
## smelting-specific lookup.

const NeedResolver = preload("res://src/gameplay/need_resolver.gd")

enum Priority { READY, BUILD_PRODUCER_FIRST, SHORTFALL }

## Structures that satisfy the "heat_source" abstract requires_structure
## category (see CraftingRecipeBook.recipe_requires_structure's own doc
## comment) -- mirrors Player._has_heat_source/_meets_requires_structure's
## own "campfire or furnace" translation exactly. NeedResolver itself takes
## a flat nearby_structures Dictionary and does not know about this
## abstraction (deliberately -- see production_chains.md's own "Open
## questions"); each caller resolves it into that Dictionary the same way
## Player.gd does, and this is this caller's version of that translation.
const _HEAT_SOURCE_STRUCTURE_IDS := ["campfire", "furnace"]


## Decides the priority for building `recipe_id` given `local_stock`
## (item_id -> count), `present_structure_ids` (structures already known to
## be present nearby, e.g. from EarthChunkManager.has_structure_near
## checks), and `allocated_nodes` (a SkillTree allocated-node Dictionary,
## Player.allocated_nodes's own shape -- defaults to empty, "no skills
## allocated," for a caller that doesn't have a specific NPC/settlement
## skill pool to check against yet). An unknown recipe id is treated as
## READY -- there is nothing real this function can meaningfully block an
## unknown recipe on.
##
## Any "structure" or "skill" need anywhere in NeedResolver's recursive walk
## reports BUILD_PRODUCER_FIRST: both name something that must exist before
## the recipe can happen AT ALL, regardless of how much material is on
## hand -- go build the structure (or train/staff the skill) first, ahead
## of the project that needed it. With no structure/skill need but a real
## "material" need, it's SHORTFALL -- the existing regional-trade/shortfall
## path already covers a pure materials gap. No need at all is READY.
func decide(
	recipe_id: String,
	local_stock: Dictionary,
	present_structure_ids: Array,
	recipe_book,
	allocated_nodes: Dictionary = {}
) -> int:
	if not recipe_book.recipe_ids().has(recipe_id):
		return Priority.READY

	# NeedResolver.resolve walks from an OUTPUT item, not a recipe id (see
	# its own doc comment, and production_chains.md's worked example B) --
	# recipe_output() names that item so a recipe whose id differs from its
	# own output (e.g. log_to_balken -> "beam") still resolves the RIGHT
	# recipe node, not a phantom "nothing produces log_to_balken" material
	# need. This also means a recipe whose output is ALREADY fully stocked
	# reports READY outright (nothing more needs to happen) rather than
	# checking its inputs regardless -- a deliberate, small behavioral
	# widening over the old can_craft-only check, matching NeedResolver's
	# own "already satisfied" base case (see test_an_already_stocked_
	# output_is_ready_even_with_no_input_material below).
	var output_item_id: String = recipe_book.recipe_output(recipe_id)["item_id"]
	var nearby_structures := _nearby_structures_dict(present_structure_ids)
	var needs: Array = NeedResolver.new(recipe_book).resolve(
		output_item_id, local_stock, allocated_nodes, nearby_structures
	)
	if needs.is_empty():
		return Priority.READY

	for need in needs:
		if need["kind"] == "structure" or need["kind"] == "skill":
			return Priority.BUILD_PRODUCER_FIRST
	return Priority.SHORTFALL


## Expands a flat list of present structure ids into the nearby_structures
## Dictionary NeedResolver expects -- every present id maps true, PLUS
## "heat_source" -> true if a campfire or furnace is among them (see
## _HEAT_SOURCE_STRUCTURE_IDS's own doc comment).
func _nearby_structures_dict(present_structure_ids: Array) -> Dictionary:
	var nearby := {}
	for structure_id in present_structure_ids:
		nearby[structure_id] = true
	for heat_source_id in _HEAT_SOURCE_STRUCTURE_IDS:
		if present_structure_ids.has(heat_source_id):
			nearby["heat_source"] = true
	return nearby
