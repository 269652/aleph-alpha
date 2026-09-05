extends GutTest

## Pure logic behind the in-game companion-browser overlay (see
## docs/concept/companion_server.md's "In-game overlay" section): converting
## the companion server's real HTML response into Godot BBCode a
## RichTextLabel can render, and resolving a clicked link's href into the
## next full URL to fetch. The real HTTPRequest/RichTextLabel/Node glue that
## calls these lives in scenes/companion_browser_overlay.gd and is
## deliberately NOT unit-tested here -- same boundary companion_server.gd's
## own doc comment already draws for real socket I/O.
##
## Scoped to exactly the tag surface companion_page_shell.gd and the four
## Tier 1 view generators actually emit (verified by grepping
## src/companion_server/*.gd before writing this, not guessed at): this is
## not a general HTML parser, and never needs to be one, since the only HTML
## this ever consumes is HTML this same codebase generates.

const CompanionBrowser = preload("res://src/companion_server/companion_browser.gd")
const CompanionPageShell = preload("res://src/companion_server/companion_page_shell.gd")


func test_strips_the_head_and_its_style_block_entirely():
	var html := "<head><style>body { color: red; }</style></head><body>Hi</body>"
	var bbcode := CompanionBrowser.html_to_bbcode(html)
	assert_eq(bbcode.strip_edges(), "Hi")


func test_unwraps_structural_wrappers_keeping_their_content():
	var html := '<html><body><div class="page"><span class="emoji">🎒</span> Sheet</div></body></html>'
	var bbcode := CompanionBrowser.html_to_bbcode(html)
	assert_eq(bbcode.strip_edges(), "🎒 Sheet")
	assert_false(bbcode.contains("<"), "no raw tag should leak through")


func test_h1_becomes_bold_larger_bbcode():
	var bbcode := CompanionBrowser.html_to_bbcode("<h1>Character Sheet</h1>")
	assert_true(bbcode.contains("[b]"))
	assert_true(bbcode.contains("Character Sheet"))
	assert_true(bbcode.contains("[/b]"))


func test_paragraph_and_line_break_read_as_separate_lines():
	var bbcode := CompanionBrowser.html_to_bbcode("<p>First</p><p>Second</p>")
	var lines := bbcode.strip_edges().split("\n")
	# Both lines of real text must survive, each on its own line -- exactly
	# what a paragraph means -- however many blank separator lines land
	# between them.
	var non_empty: Array = []
	for line in lines:
		if line.strip_edges() != "":
			non_empty.append(line.strip_edges())
	assert_eq(non_empty, ["First", "Second"])


func test_unordered_list_items_become_bullet_lines():
	var bbcode := CompanionBrowser.html_to_bbcode("<ul><li>One</li><li>Two</li></ul>")
	assert_true(bbcode.contains("One"))
	assert_true(bbcode.contains("Two"))
	# One's line must not also contain Two's text -- each li is its own line.
	for line in bbcode.split("\n"):
		if line.contains("One"):
			assert_false(line.contains("Two"))


func test_strong_and_em_become_bbcode_emphasis():
	var bbcode := CompanionBrowser.html_to_bbcode("<strong>bold</strong> and <em>italic</em>")
	assert_true(bbcode.contains("[b]bold[/b]"))
	assert_true(bbcode.contains("[i]italic[/i]"))


func test_a_href_becomes_a_clickable_bbcode_url():
	var bbcode := CompanionBrowser.html_to_bbcode('<a href="/items">Item Catalog</a>')
	assert_eq(bbcode.strip_edges(), "[url=/items]Item Catalog[/url]")


func test_br_becomes_a_newline():
	var bbcode := CompanionBrowser.html_to_bbcode("Line one<br>Line two")
	assert_true(bbcode.contains("Line one\nLine two"))


## The real shape companion_item_catalog_view.gd's rows produce: a header row
## of <th> deciding the column count, then <td> data rows -- see
## companion_router.md's own "table/tr/th/td" note.
func test_table_becomes_a_bbcode_table_with_the_real_column_count():
	var html := (
		"<table><tr><th>Name</th><th>Kind</th></tr>"
		+ "<tr><td>Carrot</td><td>food</td></tr></table>"
	)
	var bbcode := CompanionBrowser.html_to_bbcode(html)
	assert_true(bbcode.contains("[table=2]"), "2 real <th> columns")
	assert_true(bbcode.contains("[/table]"))
	assert_true(bbcode.contains("[cell]Name[/cell]"))
	assert_true(bbcode.contains("[cell]Carrot[/cell]"))


## Reported gap, deliberately not attempted this pass (see the concept doc):
## a real <form> needs a submission the static conversion has no path for.
func test_a_search_form_is_dropped_entirely_not_shown_broken():
	var html := (
		'<form><input type="text" name="q"><button type="submit">Search</button></form>'
		+ "<p>Below the form</p>"
	)
	var bbcode := CompanionBrowser.html_to_bbcode(html)
	assert_false(bbcode.contains("Search"))
	assert_true(bbcode.contains("Below the form"))


## Reported gap, deliberately not attempted this pass: Godot's [img] BBCode
## tag expects a resource path, not an arbitrary data: URI.
func test_an_img_tag_is_dropped_entirely_not_shown_broken():
	var html := '<img class="portrait" src="data:image/png;base64,AAAA=="><p>Below the image</p>'
	var bbcode := CompanionBrowser.html_to_bbcode(html)
	assert_false(bbcode.contains("data:image"))
	assert_true(bbcode.contains("Below the image"))


func test_common_html_entities_decode_including_the_pagination_arrows():
	var bbcode := CompanionBrowser.html_to_bbcode(
		"Tom &amp; Jerry &lt;3&gt; said &quot;hi&quot; &laquo; &raquo;"
	)
	assert_eq(bbcode.strip_edges(), 'Tom & Jerry <3> said "hi" « »')


func test_numeric_entities_decode_generically():
	# A right single quotation mark (U+2019), the kind a "don&#8217;t" would use --
	# not one of the named entities above, so this proves the generic numeric
	# fallback rather than a hand-enumerated table.
	var bbcode := CompanionBrowser.html_to_bbcode("don&#8217;t")
	assert_eq(bbcode, "don’t")


## The defensive case CLAUDE.md's "keep concept docs and reality aligned"
## spirit demands be tested, not just asserted in a doc comment: real game
## content (an item name, say) could someday contain a literal bracket, and
## that must never be misread as BBCode markup the way an un-escaped "[img]"
## in a name would be.
func test_a_literal_bracket_in_content_is_escaped_not_read_as_bbcode():
	var bbcode := CompanionBrowser.html_to_bbcode("<p>[Legendary] Sword</p>")
	assert_false(bbcode.contains("[Legendary]"))
	assert_true(bbcode.contains("[lb]Legendary[rb]"))


## Integration-shaped: run the REAL page shell's own output through the
## converter, not just synthetic fixtures -- the same "test against the real
## thing" discipline this codebase applies to its own render paths.
func test_the_real_page_shell_output_converts_with_no_raw_tags_left():
	var html := CompanionPageShell.wrap("Character Sheet", "<p>Hello there</p>")
	var bbcode := CompanionBrowser.html_to_bbcode(html)
	assert_false(bbcode.contains("<"), "no unhandled raw HTML tag should survive")
	assert_false(bbcode.contains(">"))
	assert_true(bbcode.contains("Hello there"))
	assert_true(bbcode.contains("[url=/items]Item Catalog[/url]"), "the real nav link should still work")
	assert_false(bbcode.contains("color-scheme"), "the <style> block must not leak through as text")


func test_resolve_href_appends_an_absolute_path_to_the_base_url():
	var url := CompanionBrowser.resolve_href("http://127.0.0.1:8731", "/items")
	assert_eq(url, "http://127.0.0.1:8731/items")


func test_resolve_href_handles_a_deeper_path():
	var url := CompanionBrowser.resolve_href("http://127.0.0.1:8731", "/items/carrot")
	assert_eq(url, "http://127.0.0.1:8731/items/carrot")


func test_resolve_href_passes_through_an_already_absolute_url():
	var url := CompanionBrowser.resolve_href("http://127.0.0.1:8731", "https://example.com/x")
	assert_eq(url, "https://example.com/x")


func test_resolve_href_tolerates_a_missing_leading_slash():
	var url := CompanionBrowser.resolve_href("http://127.0.0.1:8731", "items")
	assert_eq(url, "http://127.0.0.1:8731/items")
