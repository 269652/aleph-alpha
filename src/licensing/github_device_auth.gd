extends Node

## Real HTTP glue for GitHub's OAuth Device Flow (see docs/licensing.md's
## "Personal / GitHub-bound keys", github_device_flow.gd for the pure
## decision logic this delegates to). A Node because HTTPRequest -- Godot's
## async HTTP client -- must be a scene tree node; not an autoload, since
## this is only ever needed while the license/settings UI is actively
## checking a GitHub-bound key, not for the whole game session.
##
## Deliberately NOT unit-tested (no GUT test file) -- real network calls
## against real GitHub endpoints aren't something a headless test suite
## should be making, the same "engine side effects aren't unit-tested"
## boundary this project already draws for settings_overlay.gd/world.gd/
## self_integrity.gd's own Node glue. Everything ABOVE the actual HTTP
## call (response parsing, the authorized/pending/expired/denied decision)
## lives in github_device_flow.gd instead, fully unit-tested with fake
## JSON dictionaries -- this file's only real job is fetching the real
## response and handing it there.
##
## CLIENT_ID is a Device Flow public Client ID -- safe to embed in shipped
## source. Device Flow exists specifically so a distributed client never
## needs a client secret; nothing here ever holds or transmits one.

const GithubDeviceFlow = preload("res://src/licensing/github_device_flow.gd")

const CLIENT_ID := "Ov23lincY1zx7okSxpKP"
const DEVICE_CODE_URL := "https://github.com/login/device/code"
const TOKEN_URL := "https://github.com/login/oauth/access_token"
const USER_URL := "https://api.github.com/user"
const GRANT_TYPE := "urn:ietf:params:oauth:grant-type:device_code"
## read:user is the minimum scope that lets GET /user return a numeric
## `id` -- no repo access, no write access, nothing beyond confirming
## who's authenticating.
const SCOPE := "read:user"

## Emitted once GitHub returns a user_code the player needs to enter at
## `verification_uri` -- the UI shows both.
signal user_code_ready(user_code: String, verification_uri: String)
## Emitted once the player has approved in their browser and polling
## picked up the resulting access token.
signal authorized(access_token: String)
## Emitted on any unrecoverable failure (denied, expired, network error,
## a device-code request that never got a valid response). `reason` is
## for logs only -- the UI shows a generic message, same "generic failure
## message" rule docs/licensing.md already applies to license checks.
signal failed(reason: String)
## Emitted after fetch_user_id() resolves.
signal user_id_fetched(ok: bool, user_id: int)

var _device_code := ""
var _poll_interval := 5.0
var _poll_timer: Timer
var _http_device_code: HTTPRequest
var _http_poll: HTTPRequest
var _http_user: HTTPRequest


## Built in _init(), not _ready() -- a Node's own _init() can add children
## to itself immediately (they don't need to be in a live tree yet), so a
## caller doing `var auth := GithubDeviceAuth.new(); parent.add_child(auth);
## auth.start_device_flow()` all in the same frame doesn't hit a null
## HTTPRequest: _ready() is deferred to end-of-frame and wouldn't have run
## yet at that third call.
func _init() -> void:
	_http_device_code = HTTPRequest.new()
	add_child(_http_device_code)
	_http_device_code.request_completed.connect(_on_device_code_response)

	_http_poll = HTTPRequest.new()
	add_child(_http_poll)
	_http_poll.request_completed.connect(_on_poll_response)

	_http_user = HTTPRequest.new()
	add_child(_http_user)
	_http_user.request_completed.connect(_on_user_response)

	_poll_timer = Timer.new()
	_poll_timer.one_shot = false
	_poll_timer.timeout.connect(_poll_once)
	add_child(_poll_timer)


## Starts a fresh Device Flow -- requests a device/user code pair from
## GitHub. Emits user_code_ready() on success, failed() otherwise (no
## network, GitHub down, Device Flow not enabled on the OAuth App, etc).
func start_device_flow() -> void:
	var body := "client_id=%s&scope=%s" % [CLIENT_ID.uri_encode(), SCOPE.uri_encode()]
	var headers := ["Accept: application/json", "Content-Type: application/x-www-form-urlencoded"]
	var err := _http_device_code.request(DEVICE_CODE_URL, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		failed.emit("could not start device code request")


func _on_device_code_response(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var json: Variant = JSON.parse_string(body.get_string_from_utf8())
	if response_code != 200 or not (json is Dictionary):
		failed.emit("device code request failed (http %d)" % response_code)
		return
	var parsed := GithubDeviceFlow.parse_device_code_response(json)
	if not parsed.ok:
		failed.emit("malformed device code response")
		return
	_device_code = parsed.device_code
	_poll_interval = float(parsed.interval)
	user_code_ready.emit(parsed.user_code, parsed.verification_uri)
	_poll_timer.start(_poll_interval)


func _poll_once() -> void:
	var body := "client_id=%s&device_code=%s&grant_type=%s" % [
		CLIENT_ID.uri_encode(), _device_code.uri_encode(), GRANT_TYPE.uri_encode()
	]
	var headers := ["Accept: application/json", "Content-Type: application/x-www-form-urlencoded"]
	_http_poll.request(TOKEN_URL, headers, HTTPClient.METHOD_POST, body)


## GitHub's poll endpoint uses the JSON body's `error` field, not the HTTP
## status, to signal pending/denied/expired -- response_code isn't needed
## beyond the "is this even a parseable response" check below.
func _on_poll_response(_result: int, _response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var json: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (json is Dictionary):
		return  # Transient hiccup -- let the next scheduled poll try again.
	var parsed := GithubDeviceFlow.parse_token_poll_response(json)
	match parsed.status:
		"authorized":
			_poll_timer.stop()
			authorized.emit(parsed.access_token)
		"pending":
			pass  # Keep polling at the current interval.
		"slow_down":
			_poll_timer.stop()
			_poll_interval = max(_poll_interval, float(parsed.get("interval", _poll_interval)))
			_poll_timer.start(_poll_interval)
		"expired":
			_poll_timer.stop()
			failed.emit("device code expired")
		"denied":
			_poll_timer.stop()
			failed.emit("player denied authorization")
		_:
			_poll_timer.stop()
			failed.emit("poll error: %s" % parsed.get("reason", "unknown"))


## Confirms who a (cached or freshly authorized) access token actually
## belongs to. Emits user_id_fetched(ok, user_id) -- `ok` false covers
## both a network failure and a token GitHub itself rejects (revoked,
## expired); the caller decides what to do in either case (see World's
## GitHub-bound boot path, which clears a rejected cached token and falls
## back to a fresh interactive flow).
func fetch_user_id(access_token: String) -> void:
	var headers := ["Accept: application/json", "Authorization: token %s" % access_token, "User-Agent: aleph-alfa-license-check"]
	var err := _http_user.request(USER_URL, headers, HTTPClient.METHOD_GET)
	if err != OK:
		user_id_fetched.emit(false, 0)


func _on_user_response(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var json: Variant = JSON.parse_string(body.get_string_from_utf8())
	if response_code != 200 or not (json is Dictionary):
		user_id_fetched.emit(false, 0)
		return
	var parsed := GithubDeviceFlow.parse_user_response(json)
	if not parsed.ok:
		user_id_fetched.emit(false, 0)
		return
	user_id_fetched.emit(true, parsed.user_id)


## Cancels an in-flight device flow (e.g. the player closed the gate
## screen) so a stray poll doesn't keep firing after nothing is listening.
func cancel() -> void:
	_poll_timer.stop()


## Runs a full device flow to completion and returns {"ok": true,
## "access_token": String} or {"ok": false, "reason": String} -- the
## async-friendly counterpart to start_device_flow()'s signals, for a
## caller (World's boot flow) that wants to simply `await` the outcome.
## Still emits user_code_ready() along the way (connect to it separately
## before calling this) so the UI can show the code the moment it's
## available, without waiting for the whole flow to resolve first.
##
## Polls a local result via process_frame rather than awaiting the
## authorized/failed signals directly -- sidesteps any ambiguity about
## multi-argument signal await semantics by only ever depending on
## ordinary signal *connection*, which behaves exactly as documented.
func run_device_flow() -> Dictionary:
	var result: Dictionary = {}
	var on_authorized := func(token: String): result = {"ok": true, "access_token": token}
	var on_failed := func(reason: String): result = {"ok": false, "reason": reason}
	authorized.connect(on_authorized, CONNECT_ONE_SHOT)
	failed.connect(on_failed, CONNECT_ONE_SHOT)
	start_device_flow()
	while result.is_empty():
		await get_tree().process_frame
	return result


## The async-friendly counterpart to fetch_user_id()'s signal. Returns
## {"ok": true, "user_id": int} or {"ok": false}.
func run_fetch_user_id(access_token: String) -> Dictionary:
	var result: Dictionary = {}
	var on_fetched := func(ok: bool, user_id: int): result = {"ok": ok, "user_id": user_id}
	user_id_fetched.connect(on_fetched, CONNECT_ONE_SHOT)
	fetch_user_id(access_token)
	while result.is_empty():
		await get_tree().process_frame
	return result
