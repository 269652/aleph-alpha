extends GutTest

## CompanionRouter: path -> {route, item_id}. Pure lookup, no I/O -- the
## glue (companion_server.gd) owns actually dispatching to a view from the
## returned route id. item_id is only ever populated for item_detail.

const CompanionRouter = preload("res://src/companion_server/companion_router.gd")


func test_root_routes_to_the_character_sheet():
	assert_eq(CompanionRouter.route_for("/").route, "character_sheet")


func test_items_routes_to_the_item_catalog():
	assert_eq(CompanionRouter.route_for("/items").route, "item_catalog")


func test_companions_routes_to_companions():
	assert_eq(CompanionRouter.route_for("/companions").route, "companions")


func test_an_unknown_path_routes_to_not_found():
	assert_eq(CompanionRouter.route_for("/nonexistent").route, "not_found")


func test_port_is_pinned_to_a_fixed_value():
	# Named/tested per CLAUDE.md's no-eyeballed-constants rule -- 8731 was
	# picked to avoid the common dev-server defaults (3000, 5000, 8000, 8080)
	# a player's machine might already have something bound to.
	assert_eq(CompanionRouter.PORT, 8731)


# -- item detail path (/items/<id>) -------------------------------------------


func test_an_item_id_is_extracted_from_the_item_detail_path():
	var routed := CompanionRouter.route_for("/items/iron_sword")
	assert_eq(routed.route, "item_detail")
	assert_eq(routed.item_id, "iron_sword")


func test_items_with_an_empty_remainder_is_not_found_not_item_detail():
	assert_eq(CompanionRouter.route_for("/items/").route, "not_found")


func test_a_path_merely_starting_with_items_but_not_a_slash_is_not_item_detail():
	# "/itemsfoo" must not be mistaken for "/items" + "foo" -- the router
	# matches the "/items/" prefix WITH its trailing slash for exactly
	# this reason.
	assert_eq(CompanionRouter.route_for("/itemsfoo").route, "not_found")


func test_bare_items_is_still_the_catalog_not_item_detail():
	assert_eq(CompanionRouter.route_for("/items").route, "item_catalog")
