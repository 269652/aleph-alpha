extends RefCounted

## Pure logic behind the in-game companion-browser overlay (see
## docs/concept/companion_server.md's "In-game overlay" section):
## `html_to_bbcode` turns the companion server's real HTML response into
## Godot BBCode a RichTextLabel can render, and `resolve_href` turns a
## clicked link's href into the next full URL to fetch. The real
## HTTPRequest/RichTextLabel/Node glue that calls these lives in
## scenes/companion_browser_overlay.gd and is deliberately NOT unit-tested
## -- the same "real socket I/O isn't something a headless test suite
## should exercise" boundary companion_server.gd's own doc comment already
## draws for the server side of this exact same transport.
##
## Scoped to exactly the tag surface companion_page_shell.gd and the four
## Tier 1 view generators actually emit (verified by grepping
## src/companion_server/*.gd before writing this): h1/h2, p, ul/li,
## strong/b, em/i, a href, br, table/tr/th/td, plus the structural wrappers
## (html/body/div/span/nav) that get unwrapped rather than rendered. This
## is not a general HTML parser and never needs to be one, since the only
## HTML it will ever consume is HTML this same codebase generates.

## Named HTML entities this codebase's own HTML is known to emit
## (companion_pagination's "&laquo;"/"&raquo;" Prev/Next arrows included),
## decoded last so an already-escaped "&lt;" can never be misread as a real
## tag delimiter by the tag-conversion passes above it.
const _NAMED_ENTITIES := {
	"&amp;": "&",
	"&lt;": "<",
	"&gt;": ">",
	"&quot;": "\"",
	"&apos;": "'",
	"&#39;": "'",
	"&laquo;": "«",
	"&raquo;": "»",
}


static func html_to_bbcode(html: String) -> String:
	var text := html

	# Escape any literal bracket ALREADY in the source FIRST, before any real
	# BBCode bracket is inserted below -- so real game content (an item name,
	# say) can never be misread as markup. Safe to do blindly across the
	# whole string: raw HTML tags are delimited by "<"/">", never "["/"]", so
	# this cannot disturb any tag the passes below still need to match.
	text = text.replace("[", "[lb]").replace("]", "[rb]")

	text = _strip_block(text, "head")
	text = _strip_block(text, "form")
	text = _strip_self_closing(text, "img")

	text = _convert_tables(text)

	# Structural wrappers: drop the tag, keep whatever it wrapped. `nav`
	# specifically wraps the page shell's own real "/", "/items", "/companions"
	# links -- unwrapping it (rather than stripping it like head/form) is what
	# keeps those links alive for the <a> pass below.
	for tag in ["html", "body", "div", "span", "nav"]:
		text = _unwrap(text, tag)
	text = _strip_regex(text, "(?s)<!DOCTYPE[^>]*>")

	text = text.replace("<h1>", "[font_size=24][b]").replace("</h1>", "[/b][/font_size]\n\n")
	text = text.replace("<h2>", "[b]").replace("</h2>", "[/b]\n\n")
	text = text.replace("<p>", "").replace("</p>", "\n\n")
	text = text.replace("<ul>", "").replace("</ul>", "")
	text = text.replace("<li>", "• ").replace("</li>", "\n")
	text = text.replace("<strong>", "[b]").replace("</strong>", "[/b]")
	text = text.replace("<b>", "[b]").replace("</b>", "[/b]")
	text = text.replace("<em>", "[i]").replace("</em>", "[/i]")
	text = text.replace("<i>", "[i]").replace("</i>", "[/i]")
	for br in ["<br>", "<br/>", "<br />"]:
		text = text.replace(br, "\n")

	text = _convert_links(text)

	# Catch-all: anything not explicitly handled above (meta/title survive
	# only if head-stripping somehow missed them, a future tag this doc's
	# tag survey didn't anticipate, ...) loses its tag syntax rather than
	# leaking raw "<...>" noise into the rendered page.
	text = _strip_regex(text, "<[^>]+>")

	return _decode_entities(text)


static func resolve_href(base_url: String, href: String) -> String:
	if href.begins_with("http://") or href.begins_with("https://"):
		return href
	if href.begins_with("/"):
		return base_url + href
	return base_url + "/" + href


## Removes `<tag ...>...</tag>` (and its content) entirely -- for blocks with
## nothing worth showing (a <style> sheet, a non-functional <form>).
static func _strip_block(text: String, tag: String) -> String:
	return _strip_regex(text, "(?s)<%s[^>]*>.*?</%s>" % [tag, tag])


## Removes a void/self-closing element like <img ...> -- no closing tag, no
## content to preserve.
static func _strip_self_closing(text: String, tag: String) -> String:
	return _strip_regex(text, "<%s[^>]*/?>" % tag)


static func _strip_regex(text: String, pattern: String) -> String:
	var regex := RegEx.new()
	regex.compile(pattern)
	return regex.sub(text, "", true)


## Drops `<tag ...>` and `</tag>` but keeps whatever was between them.
static func _unwrap(text: String, tag: String) -> String:
	var result := _strip_regex(text, "<%s[^>]*>" % tag)
	return result.replace("</%s>" % tag, "")


## Manual search+splice rather than RegEx.sub()'s own backreference syntax --
## the same technique _convert_tables/_decode_entities already use below, kept
## consistent rather than depending on a second substitution mechanism.
static func _convert_links(text: String) -> String:
	var regex := RegEx.new()
	regex.compile('<a[^>]*href="([^"]*)"[^>]*>')
	var matches := regex.search_all(text)
	var result := ""
	var cursor := 0
	for regex_match in matches:
		result += text.substr(cursor, regex_match.get_start() - cursor)
		result += "[url=%s]" % regex_match.get_string(1)
		cursor = regex_match.get_end()
	result += text.substr(cursor)
	return result.replace("</a>", "[/url]")


## Each real <table> the companion server renders has a <th> header row
## deciding its real column count (companion_item_catalog_view.gd's shape) --
## a plain global replace can convert th/td/tr uniformly, but the column
## count itself needs counting per-table, which is why this walks matches by
## hand instead of a single regex.sub().
static func _convert_tables(text: String) -> String:
	var table_regex := RegEx.new()
	table_regex.compile("(?s)<table[^>]*>(.*?)</table>")
	var matches := table_regex.search_all(text)
	if matches.is_empty():
		return text

	var th_regex := RegEx.new()
	th_regex.compile("<th[^>]*>")

	var result := ""
	var cursor := 0
	for regex_match in matches:
		result += text.substr(cursor, regex_match.get_start() - cursor)
		var inner: String = regex_match.get_string(1)
		var column_count := th_regex.search_all(inner).size()
		var cells := _unwrap(inner, "tr")
		cells = cells.replace("<th>", "[cell]").replace("</th>", "[/cell]")
		cells = cells.replace("<td>", "[cell]").replace("</td>", "[/cell]")
		result += "[table=%d]%s[/table]\n\n" % [maxi(column_count, 1), cells]
		cursor = regex_match.get_end()
	result += text.substr(cursor)
	return result


static func _decode_entities(text: String) -> String:
	for entity in _NAMED_ENTITIES:
		text = text.replace(entity, _NAMED_ENTITIES[entity])

	var numeric_regex := RegEx.new()
	numeric_regex.compile("&#(\\d+);")
	var matches := numeric_regex.search_all(text)
	# Walk in reverse so each earlier replacement's start/end offsets are
	# still valid for the ones still to come -- an in-place forward
	# replace-by-index would shift everything after the first hit.
	for i in range(matches.size() - 1, -1, -1):
		var regex_match := matches[i]
		var code_point := int(regex_match.get_string(1))
		text = text.substr(0, regex_match.get_start()) + char(code_point) + text.substr(regex_match.get_end())
	return text
