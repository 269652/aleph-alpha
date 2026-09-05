extends RefCounted

## Pure parsing of a raw HTTP/1.1 request into {ok, method, path, query} --
## no sockets, no I/O (see docs/concept/companion_server.md's Tier 1 local
## transport section). The real TCPServer glue (companion_server.gd) reads
## bytes off a live connection and hands them here; this only ever sees
## already-read bytes -- mirrors github_device_flow.gd's pure/glue split.
##
## Deliberately reads only the request LINE (method + path + query),
## ignoring every header -- Tier 1 has no route that consults one (no auth,
## no conditional GET, no content negotiation), so parsing headers would be
## dead code with nothing to test against.

static func parse(raw: PackedByteArray) -> Dictionary:
	var text := raw.get_string_from_utf8()
	var line_end := text.find("\r\n")
	var request_line := text if line_end == -1 else text.substr(0, line_end)
	var parts := request_line.split(" ")
	if parts.size() < 2:
		return {"ok": false}
	var method: String = parts[0]
	var raw_path: String = parts[1]
	if method == "" or not raw_path.begins_with("/"):
		return {"ok": false}
	var query_start := raw_path.find("?")
	var path := raw_path if query_start == -1 else raw_path.substr(0, query_start)
	var query := {} if query_start == -1 else _parse_query(raw_path.substr(query_start + 1))
	return {"ok": true, "method": method, "path": path, "query": query}


## application/x-www-form-urlencoded query-string decoding -- the search box
## and pagination links on /items are its only consumers so far. "+" means
## space (a form-encoding convention; String.uri_decode() alone does NOT do
## this, it only does RFC 3986 percent-decoding), and a stray "&&" or a
## trailing "&" must not mint a bogus {"": ""} entry -- a browser address
## bar can genuinely produce either. A repeated key lets the last value win,
## the natural result of assigning into a Dictionary in a loop; no route
## here wants the first instead.
static func _parse_query(query_string: String) -> Dictionary:
	var query := {}
	for segment in query_string.split("&"):
		if segment == "":
			continue
		var eq := segment.find("=")
		var key: String
		var value: String
		if eq == -1:
			key = segment
			value = ""
		else:
			key = segment.substr(0, eq)
			value = segment.substr(eq + 1)
		query[_decode(key)] = _decode(value)
	return query


static func _decode(s: String) -> String:
	return s.replace("+", " ").uri_decode()
