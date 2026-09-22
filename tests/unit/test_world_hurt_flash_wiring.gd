extends GutTest

## docs/concept/feedback.md: `World._on_player_answered` read a row's
## `message` and its `float_text` and threw the `flash` field away -- the
## table told it three things about every act and it drew two.
##
## Source-level for the same reason test_world_arrival_card.gd and
## test_world_first_light.gd are: World is an 8500-line scene script, and a
## pure module nothing calls is exactly the failure this overhaul was
## diagnosing. The RULE is pinned behaviourally in test_hurt_flash.gd; what
## is pinned here is that World really reads it.

const HurtFlash = preload("res://src/ui/hurt_flash.gd")
const Answerback = preload("res://src/gameplay/answerback.gd")


func _function_body(name: String) -> String:
	var source := FileAccess.get_file_as_string("res://scenes/world.gd")
	var start := source.find("func %s(" % name)
	if start < 0:
		return ""
	var rest := source.substr(start)
	var next := rest.find("\nfunc ")
	return rest if next < 0 else rest.substr(0, next)


func test_the_answer_handler_reads_the_flash_field_at_all():
	var body := _function_body("_on_player_answered")
	assert_false(body.is_empty(), "precondition: the handler was found")
	assert_true(body.contains('"flash"'), "the third thing the table says is read")


## Through the module, not a second opinion written again in World.
func test_who_flashes_is_the_modules_decision():
	var body := _function_body("_on_player_answered")
	assert_true(body.contains("HurtFlash.flashes_for"), "World asks rather than decides")


## And how red it goes comes from the row's own severity, so a scratch and a
## near-killing blow do not look the same.
func test_the_colour_comes_from_the_module_and_the_rows_own_severity():
	var body := _function_body("_flash_screen") + _function_body("_on_player_answered")
	assert_true(body.contains("HurtFlash.peak_colour_for"), "the red is the module's")
	assert_true(body.contains('"severity"'), "and it scales with what the blow cost")


## The fade is the module's duration too -- not a number World picked, which
## is how one flash could outlast the gate on the next and stack.
func test_the_flash_fades_over_the_modules_own_duration():
	var body := _function_body("_flash_screen")
	assert_false(body.is_empty(), "precondition: World really draws one")
	assert_true(body.contains("HurtFlash.SECONDS"))


## It is drawn and then gone: a full-screen tint left parented to the UI
## would sit over every window for the rest of the session.
func test_the_flash_frees_itself():
	var body := _function_body("_flash_screen")
	assert_true(body.contains("queue_free"), "a flash that stays is a filter")
