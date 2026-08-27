extends RefCounted

## Caches the player's GitHub access token from a completed Device Flow
## authorization (see docs/licensing.md's "Personal / GitHub-bound keys")
## so re-verifying identity on a later launch doesn't require the
## interactive browser round-trip every single time -- only re-hitting
## GET /user with the cached token, which is what actually makes this a
## real per-launch identity check rather than a one-time flag. Same shape
## as LicenseStore: real FileAccess I/O, so this takes an explicit path
## rather than hardcoding where user:// resolves to, letting tests point
## it at a real temp file.
##
## Unlike license.txt, this is never hand-placed by a player -- purely
## internal, automatic bookkeeping -- so one fixed path is enough (no
## candidate-path list to search).


static func default_path() -> String:
	return "user://github_token.txt"


static func read_token(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text().strip_edges()


static func write_token(path: String, token: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(token.strip_edges())
	return true


## Removes a cached token GitHub itself rejected (revoked, expired, the
## player revoked app access in their GitHub settings) -- without this,
## a dead token would keep being silently retried and failing forever
## instead of falling back to a fresh interactive device flow.
static func clear_token(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
