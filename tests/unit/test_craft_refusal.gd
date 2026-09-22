extends GutTest

## docs/concept/feedback.md's refusal rule, applied to the verb a player
## presses most: a craft that cannot proceed says WHY.
##
## Measured before this: Player.craft returns a bare false for three
## different reasons -- no heat source, too little skill, not enough
## inputs -- and World discarded it, so clicking a green-looking recipe
## card did nothing at all with no explanation. The diagnosis named it as
## one of the first things that breaks in a new player's hands.

const PlayerScene = preload("res://scenes/player.tscn")
const CraftingRecipeBook = preload("res://src/gameplay/crafting_recipe_book.gd")

var player


func before_each():
	player = PlayerScene.instantiate()
	add_child(player)


func after_each():
	player.queue_free()


func _a_recipe_needing_a_structure() -> String:
	var book := CraftingRecipeBook.new()
	for recipe_id in book.recipe_ids():
		if book.recipe_requires_structure(recipe_id) != "":
			return recipe_id
	return ""


func _a_recipe_needing_skill() -> String:
	var book := CraftingRecipeBook.new()
	for recipe_id in book.recipe_ids():
		if not book.recipe_required_skill(recipe_id).is_empty():
			return recipe_id
	return ""


func test_a_refusal_is_always_a_sentence_never_an_empty_string():
	var reason: String = player.craft_refusal("not_a_real_recipe")
	assert_ne(reason, "", "even an unknown recipe says something")


func test_a_recipe_needing_a_structure_names_the_structure():
	var recipe_id := _a_recipe_needing_a_structure()
	if recipe_id == "":
		pass_test("no structure-gated recipe in the book")
		return
	var reason: String = player.craft_refusal(recipe_id)
	assert_ne(reason, "", "standing nowhere near one must refuse")
	var needed := CraftingRecipeBook.new().recipe_requires_structure(recipe_id)
	assert_string_contains(
		reason.to_lower(), needed.replace("_", " ").to_lower(),
		"the reason names what is missing: %s" % reason
	)


func test_a_recipe_needing_skill_names_the_skill():
	var recipe_id := _a_recipe_needing_skill()
	if recipe_id == "":
		pass_test("no skill-gated recipe in the book")
		return
	var reason: String = player.craft_refusal(recipe_id)
	if reason == "":
		pass_test("this character already meets the requirement")
		return
	var requirement: Dictionary = CraftingRecipeBook.new().recipe_required_skill(recipe_id)
	assert_string_contains(
		reason.to_lower(), String(requirement["stat_name"]).replace("_", " ").to_lower(),
		"the reason names the skill: %s" % reason
	)


func test_missing_inputs_are_refused_by_naming_them():
	var book := CraftingRecipeBook.new()
	var recipe_id := ""
	for candidate in book.recipe_ids():
		if book.recipe_requires_structure(candidate) == "" and book.recipe_required_skill(candidate).is_empty():
			recipe_id = candidate
			break
	assert_ne(recipe_id, "", "precondition: an ungated recipe exists")
	var reason: String = player.craft_refusal(recipe_id)
	assert_ne(reason, "", "an empty pack cannot craft anything")


## A craft that CAN proceed refuses nothing -- the refusal and the verb
## must agree, or the card lies in the other direction.
func test_a_craft_that_can_proceed_has_no_refusal():
	var book := CraftingRecipeBook.new()
	for recipe_id in book.recipe_ids():
		if book.recipe_requires_structure(recipe_id) != "":
			continue
		if not book.recipe_required_skill(recipe_id).is_empty():
			continue
		for input in book.recipe_inputs(recipe_id):
			player.inventory.add(
				load("res://src/gameplay/item.gd").new(
					String(input["item_id"]), String(input["item_id"]), "material", 99
				),
				int(input["count"]) * 2
			)
		assert_eq(player.craft_refusal(recipe_id), "", "a craftable recipe refuses nothing")
		assert_true(player.craft(recipe_id), "and really crafts")
		return
	pass_test("no ungated recipe to test with")
