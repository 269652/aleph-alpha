extends GutTest

## CompanionRouter: path -> route id. Pure lookup, no I/O -- the glue
## (companion_server.gd) owns actually dispatching to a view from the
## returned id.

const CompanionRouter = preload("res://src/companion_server/companion_router.gd")


func test_root_routes_to_the_character_sheet():
	assert_eq(CompanionRouter.route_for("/"), "character_sheet")


func test_items_routes_to_the_item_catalog():
	assert_eq(CompanionRouter.route_for("/items"), "item_catalog")


func test_companions_routes_to_companions():
	assert_eq(CompanionRouter.route_for("/companions"), "companions")


func test_an_unknown_path_routes_to_not_found():
	assert_eq(CompanionRouter.route_for("/nonexistent"), "not_found")


func test_port_is_pinned_to_a_fixed_value():
	# Named/tested per CLAUDE.md's no-eyeballed-constants rule -- 8731 was
	# picked to avoid the common dev-server defaults (3000, 5000, 8000, 8080)
	# a player's machine might already have something bound to.
	assert_eq(CompanionRouter.PORT, 8731)
