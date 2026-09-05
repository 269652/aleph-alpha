extends GutTest

## CompanionHttpRequest: pure parsing of a raw HTTP/1.1 request into
## {method, path} -- no sockets, no I/O (see docs/concept/companion_server.md).
## Mirrors github_device_flow.gd's pure/glue split: the real TCPServer glue
## (CompanionServer) hands already-read bytes here; this only ever sees
## plain PackedByteArray/String fixtures.

const CompanionHttpRequest = preload("res://src/companion_server/companion_http_request.gd")


func test_parses_method_and_path_from_a_get_request_line():
	var raw := "GET /items HTTP/1.1\r\nHost: 127.0.0.1:8731\r\n\r\n".to_utf8_buffer()
	var parsed := CompanionHttpRequest.parse(raw)
	assert_true(parsed.ok)
	assert_eq(parsed.method, "GET")
	assert_eq(parsed.path, "/items")


func test_parses_the_root_path():
	var raw := "GET / HTTP/1.1\r\n\r\n".to_utf8_buffer()
	var parsed := CompanionHttpRequest.parse(raw)
	assert_true(parsed.ok)
	assert_eq(parsed.path, "/")


func test_strips_a_query_string_from_the_path():
	# Tier 1 has no route that reads query params -- routing is by path only,
	# so a query string must not leak into what the router matches against.
	var raw := "GET /items?foo=bar HTTP/1.1\r\n\r\n".to_utf8_buffer()
	var parsed := CompanionHttpRequest.parse(raw)
	assert_eq(parsed.path, "/items")


func test_empty_input_is_not_ok():
	var parsed := CompanionHttpRequest.parse(PackedByteArray())
	assert_false(parsed.ok)


func test_garbage_input_is_not_ok():
	var parsed := CompanionHttpRequest.parse("not an http request at all".to_utf8_buffer())
	assert_false(parsed.ok)


func test_method_is_read_verbatim_routing_decides_what_to_do_with_a_non_get():
	# Tier 1 serves GET only, but that policy belongs to the glue that reads
	# this result (companion_server.gd), not the parser -- the parser's only
	# job is reporting what the client actually sent.
	var raw := "POST /items HTTP/1.1\r\n\r\n".to_utf8_buffer()
	var parsed := CompanionHttpRequest.parse(raw)
	assert_true(parsed.ok)
	assert_eq(parsed.method, "POST")


# -- query string parsing (search/pagination on /items) ----------------------


func test_query_is_an_empty_dictionary_when_there_is_no_question_mark():
	var raw := "GET /items HTTP/1.1\r\n\r\n".to_utf8_buffer()
	var parsed := CompanionHttpRequest.parse(raw)
	assert_eq(parsed.query, {})


func test_query_parses_a_single_key_value_pair():
	var raw := "GET /items?q=sword HTTP/1.1\r\n\r\n".to_utf8_buffer()
	var parsed := CompanionHttpRequest.parse(raw)
	assert_eq(parsed.query, {"q": "sword"})


func test_query_parses_multiple_pairs_separated_by_ampersand():
	var raw := "GET /items?q=sword&page=2 HTTP/1.1\r\n\r\n".to_utf8_buffer()
	var parsed := CompanionHttpRequest.parse(raw)
	assert_eq(parsed.query, {"q": "sword", "page": "2"})


func test_a_plus_in_the_query_decodes_to_a_space():
	# Form-GET convention, not generic URI decoding -- String.uri_decode()
	# alone does NOT turn "+" into a space (that's RFC 3986 vs.
	# application/x-www-form-urlencoded), so this must be handled
	# explicitly rather than assumed free from the engine.
	var raw := "GET /items?q=iron+sword HTTP/1.1\r\n\r\n".to_utf8_buffer()
	var parsed := CompanionHttpRequest.parse(raw)
	assert_eq(parsed.query.q, "iron sword")


func test_percent_encoding_in_the_query_decodes():
	var raw := "GET /items?q=iron%20sword HTTP/1.1\r\n\r\n".to_utf8_buffer()
	var parsed := CompanionHttpRequest.parse(raw)
	assert_eq(parsed.query.q, "iron sword")


func test_a_repeated_key_lets_the_last_value_win():
	var raw := "GET /items?q=a&q=b HTTP/1.1\r\n\r\n".to_utf8_buffer()
	var parsed := CompanionHttpRequest.parse(raw)
	assert_eq(parsed.query.q, "b")


func test_a_key_with_no_equals_sign_decodes_to_an_empty_value():
	var raw := "GET /items?q HTTP/1.1\r\n\r\n".to_utf8_buffer()
	var parsed := CompanionHttpRequest.parse(raw)
	assert_eq(parsed.query.q, "")


func test_a_key_with_a_trailing_equals_sign_decodes_to_an_empty_value():
	var raw := "GET /items?q= HTTP/1.1\r\n\r\n".to_utf8_buffer()
	var parsed := CompanionHttpRequest.parse(raw)
	assert_eq(parsed.query.q, "")


func test_an_empty_segment_from_a_stray_ampersand_produces_no_entry():
	# A browser address bar can genuinely produce "a&&b" (a stray extra
	# "&"), and a trailing "&" is just as real -- neither should mint a
	# bogus {"": ...} entry.
	var raw := "GET /items?q=a&&page=2 HTTP/1.1\r\n\r\n".to_utf8_buffer()
	var parsed := CompanionHttpRequest.parse(raw)
	assert_false(parsed.query.has(""))
	assert_eq(parsed.query.size(), 2)
