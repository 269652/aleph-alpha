extends GutTest

## Pure decision logic for GitHub Device Flow (docs/licensing.md's
## "Personal / GitHub-bound keys") -- parses already-fetched JSON
## responses into a small, uniform shape. No HTTPRequest, no network: the
## real HTTP glue (GithubDeviceAuth) hands this already-decoded
## Dictionaries and acts on what comes back, the same pure/glue split
## every other licensing module in this project uses.

const GithubDeviceFlow = preload("res://src/licensing/github_device_flow.gd")


# -- identity_satisfies_binding ----------------------------------------

func test_an_unbound_serial_accepts_any_identity():
	assert_true(GithubDeviceFlow.identity_satisfies_binding(0, 999))


func test_a_bound_serial_accepts_the_matching_identity():
	assert_true(GithubDeviceFlow.identity_satisfies_binding(123, 123))


func test_a_bound_serial_rejects_a_different_identity():
	assert_false(GithubDeviceFlow.identity_satisfies_binding(123, 456))


# -- parse_device_code_response (POST /login/device/code) ---------------

func test_parses_a_well_formed_device_code_response():
	var json := {
		"device_code": "abc123",
		"user_code": "WDJB-MJHT",
		"verification_uri": "https://github.com/login/device",
		"expires_in": 900,
		"interval": 5,
	}
	var result := GithubDeviceFlow.parse_device_code_response(json)
	assert_true(result.ok)
	assert_eq(result.device_code, "abc123")
	assert_eq(result.user_code, "WDJB-MJHT")
	assert_eq(result.verification_uri, "https://github.com/login/device")
	assert_eq(result.expires_in, 900)
	assert_eq(result.interval, 5)


func test_rejects_a_device_code_response_missing_a_required_field():
	var json := {"device_code": "abc123", "user_code": "WDJB-MJHT"}
	assert_false(GithubDeviceFlow.parse_device_code_response(json).ok)


func test_rejects_a_non_dictionary_device_code_response():
	assert_false(GithubDeviceFlow.parse_device_code_response({}).ok)


# -- parse_token_poll_response (POST /login/oauth/access_token) ---------

func test_a_successful_poll_reports_authorized_with_the_token():
	var json := {"access_token": "gho_abc123", "token_type": "bearer", "scope": ""}
	var result := GithubDeviceFlow.parse_token_poll_response(json)
	assert_eq(result.status, "authorized")
	assert_eq(result.access_token, "gho_abc123")


func test_authorization_pending_reports_pending():
	var json := {"error": "authorization_pending"}
	assert_eq(GithubDeviceFlow.parse_token_poll_response(json).status, "pending")


func test_slow_down_reports_slow_down():
	var json := {"error": "slow_down", "interval": 10}
	var result := GithubDeviceFlow.parse_token_poll_response(json)
	assert_eq(result.status, "slow_down")
	assert_eq(result.interval, 10)


func test_expired_token_reports_expired():
	var json := {"error": "expired_token"}
	assert_eq(GithubDeviceFlow.parse_token_poll_response(json).status, "expired")


func test_access_denied_reports_denied():
	var json := {"error": "access_denied"}
	assert_eq(GithubDeviceFlow.parse_token_poll_response(json).status, "denied")


## GitHub's device flow can return other, rarer error codes too
## (incorrect_client_credentials, incorrect_device_code,
## device_flow_disabled, unsupported_grant_type) -- none of these are
## recoverable by polling again, so they all collapse to a single
## generic "error" status rather than needing to be named individually.
func test_an_unrecognized_error_reports_a_generic_error_status():
	var json := {"error": "incorrect_client_credentials"}
	assert_eq(GithubDeviceFlow.parse_token_poll_response(json).status, "error")


func test_a_response_with_neither_token_nor_error_reports_a_generic_error_status():
	assert_eq(GithubDeviceFlow.parse_token_poll_response({}).status, "error")


# -- parse_user_response (GET /user) -------------------------------------

func test_parses_a_well_formed_user_response():
	var json := {"id": 123456, "login": "octocat"}
	var result := GithubDeviceFlow.parse_user_response(json)
	assert_true(result.ok)
	assert_eq(result.user_id, 123456)
	assert_eq(result.login, "octocat")


func test_rejects_a_user_response_missing_id():
	assert_false(GithubDeviceFlow.parse_user_response({"login": "octocat"}).ok)


func test_rejects_a_non_dictionary_user_response():
	assert_false(GithubDeviceFlow.parse_user_response({}).ok)
