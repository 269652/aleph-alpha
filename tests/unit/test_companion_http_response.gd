extends GutTest

## CompanionHttpResponse: builds a complete raw HTTP/1.1 response as bytes
## from (status, content_type, body) -- pure formatting, no socket, same
## framing as companion_http_request.gd.

const CompanionHttpResponse = preload("res://src/companion_server/companion_http_response.gd")


func test_a_200_response_has_the_right_status_line():
	var text := CompanionHttpResponse.build(200, "text/html", "<p>hi</p>").get_string_from_utf8()
	assert_true(text.begins_with("HTTP/1.1 200 OK\r\n"))


func test_a_404_response_has_the_right_status_line():
	var text := CompanionHttpResponse.build(404, "text/html", "not found").get_string_from_utf8()
	assert_true(text.begins_with("HTTP/1.1 404 Not Found\r\n"))


func test_content_type_header_is_present():
	var text := CompanionHttpResponse.build(200, "text/html", "x").get_string_from_utf8()
	assert_true(text.contains("Content-Type: text/html\r\n"))


func test_content_length_matches_the_bodys_real_utf8_byte_length_not_its_character_count():
	# "café" is 4 characters but 5 UTF-8 bytes (é is 2 bytes) -- Content-Length
	# must count bytes actually written, or a real HTTP client reading exactly
	# that many bytes would truncate a multi-byte body.
	var text := CompanionHttpResponse.build(200, "text/plain", "café").get_string_from_utf8()
	assert_true(text.contains("Content-Length: 5\r\n"))


func test_connection_close_header_is_present():
	# Tier 1 never keeps a connection alive across requests -- one request,
	# one response, one close (see companion_server.gd).
	var text := CompanionHttpResponse.build(200, "text/html", "x").get_string_from_utf8()
	assert_true(text.contains("Connection: close\r\n"))


func test_the_body_follows_a_blank_line_and_is_exactly_preserved():
	var text := CompanionHttpResponse.build(200, "text/html", "<p>hi</p>").get_string_from_utf8()
	assert_true(text.ends_with("\r\n\r\n<p>hi</p>"))
