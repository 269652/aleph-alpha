extends GutTest

## `/craft <recipe_id>` -- the dev console's hand-craft command
## (World._handle_craft_command). Pinned from source text rather than by
## driving a real World node (needs a full chunk manager, see
## test_earth_chunk_manager.gd's runtime), the same shape as
## test_mushroom_command_clarity.gd / test_deed_command_wiring.gd. The real
## decision logic lives in CraftingRecipeBook.is_bench_recipe, which
## test_crafting_recipe_book.gd tests for real; this file pins that the
## console actually routes through it.
##
## Why: CraftingRecipeBook is deliberately wider than "what a player can
## make at a bench" (docs/concept/production_chains.md "What the crafting
## menu lists") -- 13 house-blueprint recipes whose output is symbolic of a
## structure and NOT an ItemCatalog item, plus "automated" resolver data.
## Player.craft("small_house") passes the carpentry gate, consumes 30 wood,
## then silently skips the output because has() is false. The crafting
## menu got the filter first (CraftingWindow.bench_recipe_ids, 2026-09-13);
## the console kept routing ANY id in recipe_ids() straight into
## Player.craft, so `/craft small_house` burned the wood and built nothing
## -- and its "Known:" listing advertised exactly those ids.


func _source() -> String:
	return FileAccess.get_file_as_string("res://scenes/world.gd")


func _function_body(source: String, signature: String) -> String:
	var start := source.find(signature)
	assert_gt(start, -1, "%s should still exist" % signature)
	var end := source.find("\nfunc ", start + 1)
	if end == -1:
		end = source.length()
	return source.substr(start, end - start)


func _craft_command_body() -> String:
	return _function_body(_source(), "func _handle_craft_command(")


## The gate is the book's own shared predicate -- the one
## CraftingWindow.bench_recipe_ids composes too -- not a second copy of the
## "not automated and output is an item" rule that could drift from it, and
## it runs BEFORE Player.craft ever sees the id.
func test_the_command_refuses_a_non_bench_recipe_before_it_reaches_player_craft():
	var body := _craft_command_body()
	var gate := body.find("is_bench_recipe(")
	var craft := body.find(".craft(")
	assert_gt(gate, -1, "the command must gate on CraftingRecipeBook.is_bench_recipe")
	assert_gt(craft, -1, "a bench recipe should still be handed to Player.craft")
	assert_lt(gate, craft, "the bench gate must run before Player.craft is called")


## A refused recipe gets a clear reason, not the generic "missing
## ingredients or unknown recipe" line -- which would send a player off to
## gather more wood for a recipe this command can never craft.
func test_a_non_bench_recipe_gets_a_clear_refusal():
	var body := _craft_command_body()
	assert_string_contains(body, "not a bench recipe")


## The "Known:" listing names bench recipes only. The raw recipe_ids()
## would advertise the very ids the gate refuses.
func test_the_known_listing_names_bench_recipes_only():
	var body := _craft_command_body()
	assert_string_contains(body, "bench_recipe_ids(")
	assert_eq(body.find("recipe_ids()"), -1, "the raw recipe_ids() must not be listed as Known")


## GUARD (green before and after): Player.craft itself must NOT grow the
## same gate. Player._try_build_house_from_blueprint calls craft() as its
## atomic material+skill gate and depends on it consuming the wood for
## exactly the house recipes; the refusal belongs to the surfaces a player
## reaches a recipe FROM (menu, console), never to craft() itself.
func test_player_craft_itself_is_not_gated_on_the_bench_predicate():
	var player_source := FileAccess.get_file_as_string("res://scenes/player.gd")
	var craft_body := _function_body(player_source, "func craft(")
	assert_eq(craft_body.find("is_bench_recipe"), -1, "craft() must stay the blueprint path's material gate")
	var build_body := _function_body(player_source, "func _try_build_house_from_blueprint(")
	assert_string_contains(build_body, "craft(")
