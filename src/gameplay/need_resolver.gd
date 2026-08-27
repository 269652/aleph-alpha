extends RefCounted

## "What do I actually need to get item_id?" (see docs/concept/
## production_chains.md). Walks CraftingRecipeBook recursively from a
## target item, returning the real, ordered set of unmet needs: a missing
## skill level, a missing nearby/built structure, or a missing raw/
## gathered sub-material -- or an empty Array once the target is already
## satisfied. Shared by everything that needs to reason about what's
## missing (Quest's own new additive capability, and future settlement/
## construction reasoning per docs/concept/timber_construction.md's
## "dependency chain" section) rather than each caller re-deriving its own
## one-off resolution logic.
##
## Pure: no RNG, no engine dependency, no mutation of any input Dictionary
## -- mirrors CraftingRecipeBook's own RefCounted, no-side-effect shape.

const CraftingRecipeBook = preload("res://src/gameplay/crafting_recipe_book.gd")
const SkillTree = preload("res://src/gameplay/skill_tree.gd")

## A cheap real safety net (per this doc's own framing), not a realistic
## depth any actual recipe chain here reaches -- every real chain today is
## 1-2 hops deep (e.g. iron_helm -> iron_ingot -> iron_ore/coal). Guards
## against a malicious or accidentally cyclic recipe graph recursing
## forever; pinned by test_cycle_guard_terminates_on_a_cyclic_recipe_graph
## rather than left as an eyeballed number.
const MAX_DEPTH := 20

var _recipe_book: CraftingRecipeBook
var _skill_tree := SkillTree.new()


## `recipe_book` is injectable (defaults to the real CraftingRecipeBook) so
## a test can swap in a fake recipe graph -- see test_need_resolver.gd's
## FakeCyclicRecipeBook.
func _init(recipe_book: CraftingRecipeBook = null) -> void:
	_recipe_book = recipe_book if recipe_book != null else CraftingRecipeBook.new()


## `stock`: item_id -> count currently held (inventory, market stock, or
## whatever the caller's own real stock source is).
## `allocated_nodes`: SkillTree allocated-node Dictionary (Player's own
## shape, read via SkillTree.total_bonus).
## `nearby_structures`: structure_id -> true for every structure currently
## built/nearby (mirrors allocated_nodes's own id -> bool shape).
func resolve(item_id: String, stock: Dictionary, allocated_nodes: Dictionary, nearby_structures: Dictionary) -> Array:
	return _resolve_needs(item_id, 1, stock, allocated_nodes, nearby_structures, 0)


func _resolve_needs(
	item_id: String,
	needed_count: int,
	stock: Dictionary,
	allocated_nodes: Dictionary,
	nearby_structures: Dictionary,
	depth: int
) -> Array:
	# Cheap safety net (see MAX_DEPTH) -- give up silently past a runaway
	# depth rather than recursing forever on a cyclic recipe graph.
	if depth > MAX_DEPTH:
		return []

	var have: int = stock.get(item_id, 0)
	if have >= needed_count:
		return []

	var recipe_id := _recipe_book.recipe_for_output(item_id)
	if recipe_id == "":
		# Bottom case: nothing produces this item -- it's raw/gathered, "go
		# get it from the world," not a broken lookup.
		return [{"kind": "material", "item_id": item_id, "need": needed_count - have}]

	var needs: Array = []

	var structure_id := _recipe_book.recipe_requires_structure(recipe_id)
	if structure_id != "" and not nearby_structures.get(structure_id, false):
		needs.append({"kind": "structure", "item_id": item_id, "structure_id": structure_id})

	var required_skill := _recipe_book.recipe_required_skill(recipe_id)
	if not required_skill.is_empty():
		var have_level: float = _skill_tree.total_bonus(required_skill["stat_name"], allocated_nodes)
		if have_level < required_skill["level"]:
			needs.append({
				"kind": "skill",
				"item_id": item_id,
				"stat_name": required_skill["stat_name"],
				"level": required_skill["level"],
				"have": have_level,
			})

	for input in _recipe_book.recipe_inputs(recipe_id):
		var input_id: String = input["item_id"]
		var input_count: int = input["count"]
		needs.append_array(
			_resolve_needs(input_id, input_count, stock, allocated_nodes, nearby_structures, depth + 1)
		)

	return needs
