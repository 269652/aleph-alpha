extends GutTest

## CompanionHtml: a one-line named wrapper around Godot's built-in
## String.xml_escape(true) -- not a reimplementation. Named so a call site
## reads "escape this for HTML" rather than a bare, easy-to-get-the-
## argument-wrong xml_escape(true) scattered around every view.

const CompanionHtml = preload("res://src/companion_server/companion_html.gd")


func test_escapes_angle_brackets_so_a_tag_cannot_be_injected():
	var escaped := CompanionHtml.escape("<b>hi</b>")
	assert_false(escaped.contains("<b>"))
	assert_true(escaped.contains("&lt;b&gt;"))


func test_escapes_ampersand():
	assert_true(CompanionHtml.escape("Tom & Jerry").contains("&amp;"))


func test_escapes_a_double_quote_so_it_cannot_break_out_of_an_attribute():
	var escaped := CompanionHtml.escape('say "hi"')
	assert_false(escaped.contains('"'))
