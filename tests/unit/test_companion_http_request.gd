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
