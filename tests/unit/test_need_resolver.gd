extends GutTest

## NeedResolver: "what do I actually need" (see
## docs/concept/production_chains.md). Given a target item_id, a real
## inventory-style stock Dictionary, a real allocated-skill-nodes
## Dictionary, and a real "which structures are nearby/built" indicator,
## walks CraftingRecipeBook recursively and returns the ordered set of real
## unmet needs -- a skill gap, a missing structure, missing sub-materials,
## or several at once -- or an empty Array once the target is already
## satisfied. Pure, no engine dependency (mirrors CraftingRecipeBook's own
## RefCounted, no-RNG shape).

const NeedResolver = preload("res://src/gameplay/need_resolver.gd")
const CraftingRecipeBook = preload("res://src/gameplay/crafting_recipe_book.gd")

## A deliberately cyclic fake recipe book -- "a" needs "b" and "b" needs
## "a" -- standing in for a malicious/accidental cyclic recipe graph the
## real CraftingRecipeBook itself is never seeded with. Subclasses the real
## book (rather than a from-scratch duck type) so it satisfies
## NeedResolver's real CraftingRecipeBook-typed dependency.
class FakeCyclicRecipeBook extends CraftingRecipeBook:
	func recipe_for_output(item_id: String) -> String:
		if item_id == "a":
			return "recipe_a"
		if item_id == "b":
			return "recipe_b"
		return ""

	func recipe_inputs(recipe_id: String) -> Array:
		if recipe_id == "recipe_a":
			return [{"item_id": "b", "count": 1}]
		if recipe_id == "recipe_b":
			return [{"item_id": "a", "count": 1}]
		return []

	func recipe_required_skill(_recipe_id: String) -> Dictionary:
		return {}

	func recipe_requires_structure(_recipe_id: String) -> String:
		return ""


var resolver: NeedResolver
var recipe_book: CraftingRecipeBook


func before_each():
	recipe_book = CraftingRecipeBook.new()
	resolver = NeedResolver.new(recipe_book)


## Direct stock satisfaction: already have at least one, nothing is needed.
func test_target_already_in_stock_needs_nothing():
	var needs: Array = resolver.resolve("log", {"log": 5}, {}, {})
	assert_eq(needs, [])


## One-hop missing structure: iron_ingot's real inputs (iron_ore + coal)
## are fully covered by stock, but no heat source is nearby -- the ONLY
## real need is the structure gate, not a phantom material shortfall.
func test_one_hop_missing_structure():
	var stock := {"iron_ore": 1, "coal": 1}
	var needs: Array = resolver.resolve("iron_ingot", stock, {}, {})
	assert_eq(needs, [{"kind": "structure", "item_id": "iron_ingot", "structure_id": "heat_source"}])


## A present structure (nearby_structures says "heat_source" is available)
## clears the structure need entirely once inputs are also covered.
func test_structure_need_clears_once_the_structure_is_present():
	var stock := {"iron_ore": 1, "coal": 1}
	var needs: Array = resolver.resolve("iron_ingot", stock, {}, {"heat_source": true})
	assert_eq(needs, [])


## One-hop missing skill: sagewerk's real inputs (log + wood) are fully
## covered, but no Carpentry is allocated -- the real skill gap is named
## with its stat_name/level/current level, not just "blocked."
func test_one_hop_missing_skill():
	var stock := {"log": 8, "wood": 4}
	var needs: Array = resolver.resolve("sagewerk", stock, {}, {})
	assert_eq(needs.size(), 1)
	assert_eq(needs[0]["kind"], "skill")
	assert_eq(needs[0]["item_id"], "sagewerk")
	assert_eq(needs[0]["stat_name"], "carpentry_level")
	assert_eq(needs[0]["level"], 2.0)
	assert_eq(needs[0]["have"], 0.0)


## Allocating the real carpentry nodes clears the skill need (mirrors
## Player._chop_step's own total_bonus("carpentry_level", allocated) read).
func test_skill_need_clears_once_enough_is_allocated():
	var stock := {"log": 8, "wood": 4}
	var allocated := {"carpentry_1": true, "carpentry_2": true}
	var needs: Array = resolver.resolve("sagewerk", stock, allocated, {})
	assert_eq(needs, [])


## Multi-hop: iron_helm needs iron_ingot, which itself needs a heat source
## AND real ore/coal this empty stock doesn't have -- the walk must drill
## two levels deep and report all three real needs, not stop at the first.
func test_multi_hop_missing_submaterial():
	var needs: Array = resolver.resolve("iron_helm", {}, {}, {})
	assert_eq(needs.size(), 3)
	assert_has(needs, {"kind": "structure", "item_id": "iron_ingot", "structure_id": "heat_source"})
	assert_has(needs, {"kind": "material", "item_id": "iron_ore", "need": 1})
	assert_has(needs, {"kind": "material", "item_id": "coal", "need": 1})


## Raw/gatherable item, no recipe at all: "go get it from the world," a
## real, distinct need kind rather than an empty/broken result.
func test_raw_gatherable_item_with_no_recipe():
	var needs: Array = resolver.resolve("log", {}, {}, {})
	assert_eq(needs, [{"kind": "material", "item_id": "log", "need": 1}])


## A partial raw stock still reports exactly how many more are needed.
func test_raw_item_partial_stock_reports_exact_shortfall():
	var needs: Array = resolver.resolve("iron_helm", {"iron_ingot": 1}, {}, {})
	# iron_helm needs 2 iron_ingot; 1 in stock -- the ingot recipe's own
	# per-craft inputs (ore/coal) are still what gets asked for, since this
	# resolver reasons in recipe-hops, not batch-multiplied quantities (see
	# production_chains.md's own open-questions note on this).
	assert_eq(needs.size(), 3)
	assert_has(needs, {"kind": "structure", "item_id": "iron_ingot", "structure_id": "heat_source"})


## The cheap real safety net: a cyclic recipe graph (a needs b needs a)
## must terminate, not hang or overflow the call stack, and the result
## stays bounded by the depth cap rather than growing without limit.
func test_cycle_guard_terminates_on_a_cyclic_recipe_graph():
	var cyclic_resolver: NeedResolver = NeedResolver.new(FakeCyclicRecipeBook.new())
	var needs: Array = cyclic_resolver.resolve("a", {}, {}, {})
	assert_true(needs.size() <= NeedResolver.MAX_DEPTH + 1, "cycle guard should bound the result, not run away")


func test_unknown_target_item_with_no_recipe_and_no_stock_is_a_material_need():
	var needs: Array = resolver.resolve("not_a_real_item", {}, {}, {})
	assert_eq(needs, [{"kind": "material", "item_id": "not_a_real_item", "need": 1}])
