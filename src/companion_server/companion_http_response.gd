extends RefCounted

## Pure formatting of a complete HTTP/1.1 response as raw bytes from
## (status, content_type, body) -- no socket, mirrors
## companion_http_request.gd's framing exactly.
##
## Every response closes the connection unconditionally: Tier 1 never keeps
## one alive across requests (one GET, one response, done -- see
## companion_server.md's local transport section), so Connection: close is
## always sent rather than being a per-request decision.

const _STATUS_TEXT := {
	200: "OK",
	404: "Not Found",
}


static func build(status: int, content_type: String, body: String) -> PackedByteArray:
	var body_bytes := body.to_utf8_buffer()
	var status_text: String = _STATUS_TEXT.get(status, "Unknown")
	var header := "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [
		status, status_text, content_type, body_bytes.size()
	]
	var out := header.to_utf8_buffer()
	out.append_array(body_bytes)
	return out
