extends RefCounted

## Path -> {route, item_id}. Pure lookup; companion_server.gd's glue owns
## actually dispatching to a view from the route id this returns. item_id
## is only ever populated for the item_detail route.

## Port the companion server listens on -- named/tested per CLAUDE.md's
## no-eyeballed-constants rule. 8731 avoids the common dev-server defaults
## (3000, 5000, 8000, 8080) a player's machine might already have bound.
## Pinned by test_port_is_pinned_to_a_fixed_value.
const PORT := 8731

## Trailing slash is load-bearing: matching bare "/items" (no slash) would
## let a path like "/itemsfoo" falsely extract "foo" as an item id.
const _ITEM_DETAIL_PREFIX := "/items/"

const _ROUTES := {
	"/": "character_sheet",
	"/items": "item_catalog",
	"/companions": "companions",
}


static func route_for(path: String) -> Dictionary:
	if path.begins_with(_ITEM_DETAIL_PREFIX):
		var item_id := path.substr(_ITEM_DETAIL_PREFIX.length())
		if item_id != "":
			return {"route": "item_detail", "item_id": item_id}
		return {"route": "not_found", "item_id": ""}
	return {"route": _ROUTES.get(path, "not_found"), "item_id": ""}
