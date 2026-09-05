extends RefCounted

## Renders Player.to_save_dict()'s bonded_companions list -- a plain
## [{"species": String}, ...] array, nothing richer persisted today. See
## docs/concept/companion_server.md's Companions section for why this is
## deliberately narrower than a full bestiary (no encounter-tracking
## mechanism exists anywhere in this codebase to build one from).

const CompanionPageShell = preload("res://src/companion_server/companion_page_shell.gd")


static func render(save_dict: Dictionary) -> String:
	var companions: Array = save_dict.get("bonded_companions", [])
	var body: String
	if companions.is_empty():
		body = "<p>No companions yet -- tame or net one to see it here.</p>"
	else:
		body = "<ul>"
		for companion in companions:
			body += "<li>%s</li>" % String(companion.get("species", "?"))
		body += "</ul>"
	return CompanionPageShell.wrap("Companions", body)
