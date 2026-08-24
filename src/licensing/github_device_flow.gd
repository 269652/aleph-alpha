extends RefCounted

## Pure decision logic for GitHub's OAuth Device Flow (docs/licensing.md's
## "Personal / GitHub-bound keys"). Parses already-fetched JSON response
## bodies into a small, uniform shape -- no HTTPRequest, no network, no
## polling/timers of its own. The real HTTP glue (GithubDeviceAuth) fetches
## the real responses and hands the decoded Dictionaries here, the same
## pure/glue split every other licensing module in this project already
## uses (SerialVerifier/LicenseGate, SignatureRing/SelfIntegrity).
##
## Device Flow exists specifically so a distributed client never needs a
## client secret (docs.github.com/en/apps/oauth-apps/building-oauth-apps/
## authorizing-oauth-apps#device-flow) -- only a public Client ID, safe to
## embed in shipped source.


## Whether a serial's bound GitHub user id is satisfied by the identity
## that actually authenticated. `bound_user_id == 0` means "not bound to
## any GitHub account" (see SerialCodec's own doc comment) -- accepts
## anyone, same as an ordinary unbound key.
static func identity_satisfies_binding(bound_user_id: int, actual_user_id: int) -> bool:
	return bound_user_id == 0 or bound_user_id == actual_user_id


## Parses the response body of POST https://github.com/login/device/code.
## Returns {"ok": true, "device_code": String, "user_code": String,
## "verification_uri": String, "expires_in": int, "interval": int} on a
## well-formed response, or {"ok": false} if any required field is
## missing -- a malformed response here can't be recovered from, so there
## is nothing more specific for a caller to branch on.
static func parse_device_code_response(json: Dictionary) -> Dictionary:
	var required := ["device_code", "user_code", "verification_uri", "expires_in", "interval"]
	for key in required:
		if not json.has(key):
			return {"ok": false}
	return {
		"ok": true,
		"device_code": json.device_code,
		"user_code": json.user_code,
		"verification_uri": json.verification_uri,
		"expires_in": json.expires_in,
		"interval": json.interval,
	}


## Parses the response body of POST https://github.com/login/oauth/
## access_token (grant_type=urn:ietf:params:oauth:grant-type:device_code).
## Returns one of:
##   {"status": "authorized", "access_token": String} -- the player approved
##   {"status": "pending"} -- keep polling at the same interval
##   {"status": "slow_down", "interval": int} -- keep polling, slower
##   {"status": "expired"} -- the user_code expired; restart the flow
##   {"status": "denied"} -- the player explicitly declined
##   {"status": "error", "reason": String} -- anything else (a rarer
##     GitHub error code, or a response shaped like neither a success nor
##     a recognized error) -- none of these are recoverable by polling
##     again, so they all collapse to one generic status rather than
##     needing to be named individually.
static func parse_token_poll_response(json: Dictionary) -> Dictionary:
	if json.has("access_token"):
		return {"status": "authorized", "access_token": json.access_token}
	var error: String = json.get("error", "")
	match error:
		"authorization_pending":
			return {"status": "pending"}
		"slow_down":
			return {"status": "slow_down", "interval": json.get("interval", 0)}
		"expired_token":
			return {"status": "expired"}
		"access_denied":
			return {"status": "denied"}
		_:
			return {"status": "error", "reason": error if not error.is_empty() else "unrecognized response"}


## Parses the response body of GET https://api.github.com/user (with the
## access token in the Authorization header). Returns {"ok": true,
## "user_id": int, "login": String} or {"ok": false} if `id` is missing --
## `id` is the stable, non-renameable identifier a serial is actually
## bound to (see SerialCodec's own doc comment for why not `login`).
static func parse_user_response(json: Dictionary) -> Dictionary:
	if not json.has("id"):
		return {"ok": false}
	return {"ok": true, "user_id": json.id, "login": json.get("login", "")}
