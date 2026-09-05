extends RefCounted

## Path -> route id. Pure lookup; companion_server.gd's glue owns actually
## dispatching to a view from the id this returns.

## Port the companion server listens on -- named/tested per CLAUDE.md's
## no-eyeballed-constants rule. 8731 avoids the common dev-server defaults
## (3000, 5000, 8000, 8080) a player's machine might already have bound.
## Pinned by test_port_is_pinned_to_a_fixed_value.
const PORT := 8731

const _ROUTES := {
	"/": "character_sheet",
	"/items": "item_catalog",
	"/companions": "companions",
}


static func route_for(path: String) -> String:
	return _ROUTES.get(path, "not_found")
