extends PanelContainer

## Player-facing surface for the real Live Dialogue System pipeline
## (docs/concept/dialogue.md: world state -> DialogueContext.build -> frame
## -> NpcVoice -> DialogueTopic -> DialogueMove -> DialogueBeat ->
## OfflineRenderer -> the sentence) -- opens on the existing "talk" key
## (default G), exactly as that doc's own Status section names it. Same
## "toggle window, built entirely in code" shape InventoryWindow/
## CraftingWindow/QuestLogWindow already use, but built around ONE open
## conversation rather than a persistent list: World calls open_for(...)
## fresh every time a conversation starts, rather than refreshing this
## window in place against ongoing world state.
##
## World hands this window a greeting (NpcInteraction/NpcGreeting's own
## line -- this window never builds one itself) and a fixed list of
## already-built Beats (DialogueMove's top-k for this moment, each already
## packaged by DialogueBeat.build). This window's only pipeline dependency
## is OfflineRenderer, used purely for wording -- the one stage dialogue.md's
## "pure core, thin glue" pillar assigns to the window itself. Choosing a
## topic emits topic_chosen so World can burn it in the real NpcSeenLedger;
## this window holds no ledger of its own, the same division CraftingWindow
## draws between "I show a button" and "World decides whether pressing it
## changes anything real".
##
## The topic list is fixed for the lifetime of one open_for(...) call --
## World does not re-fetch/re-rank mid-conversation. A beat is removed from
## the on-screen list once chosen (so the same line cannot be asked for
## twice in one sitting), but the REMAINING beats' own salience/decay do not
## recompute until the conversation is reopened. A real, honestly-named
## scope line (see docs/progress.md) rather than a live re-ranking loop.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const OfflineRenderer = preload("res://src/dialogue/offline_renderer.gd")
const DialogueBeat = preload("res://src/dialogue/dialogue_beat.gd")

signal topic_chosen(topic_id: String)

var _beats: Array = []
var _name_label: Label
var _response_label: Label
var _topics_container: VBoxContainer


func _ready() -> void:
	visible = false
	# A fixed window footprint regardless of topic count -- the scroll
	# container below absorbs overflow, same reasoning every other
	# gameplay window's own doc comment gives for its identical shape.
	custom_minimum_size = Vector2(480, 380)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", UiTheme.TITLE_FONT_SIZE)
	root.add_child(_name_label)

	_response_label = Label.new()
	_response_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_response_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	_topics_container = VBoxContainer.new()
	_topics_container.add_theme_constant_override("separation", 6)
	_topics_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_topics_container)

	var farewell := Button.new()
	farewell.text = "Farewell"
	farewell.pressed.connect(func(): visible = false)
	root.add_child(farewell)


func toggle() -> void:
	visible = not visible


func is_open() -> bool:
	return visible


## Starts a fresh conversation. `speaker_name`/`greeting` are shown as-is
## (already real, already worded text from NpcIdentity/NpcInteraction);
## `beats` is DialogueMove's top-k, each already run through
## DialogueBeat.build, in ranked order. A beat whose own `kind` is
## DialogueBeat.KIND_DEFLECT (nothing salient left to say) is shown
## directly as the response instead of becoming a button -- offering the
## player a button to click for "nothing more to say" would be a strange
## thing to do with an honest empty answer (dialogue.md pillar 2).
func open_for(npc_id: String, speaker_name: String, greeting: String, beats: Array) -> void:
	visible = true
	_name_label.text = speaker_name
	_response_label.text = greeting

	var deflects := beats.filter(func(b): return str(b.get("kind", "")) == DialogueBeat.KIND_DEFLECT)
	if not deflects.is_empty():
		_response_label.text = "%s\n\n%s" % [greeting, OfflineRenderer.render(deflects[0])]

	_beats = beats.filter(func(b): return str(b.get("kind", "")) != DialogueBeat.KIND_DEFLECT)
	_rebuild_topic_list()


func _rebuild_topic_list() -> void:
	for child in _topics_container.get_children():
		_topics_container.remove_child(child)
		child.queue_free()
	if _beats.is_empty():
		_topics_container.add_child(_empty_label())
		return
	for beat in _beats:
		_topics_container.add_child(_topic_button(beat))


func _empty_label() -> Label:
	var label := Label.new()
	label.text = "Nothing more to ask about right now."
	label.modulate = Color(1, 1, 1, 0.5)
	return label


func _topic_button(beat: Dictionary) -> Button:
	var button := Button.new()
	button.text = OfflineRenderer.choice_label_for(beat)
	button.pressed.connect(func(): _on_topic_chosen(beat))
	return button


## Renders the beat's real answer as the new response, burns it (via the
## signal -- World owns the real NpcSeenLedger, see this file's own doc
## comment), and drops the button so the same line cannot be picked twice
## in one sitting. remove_child (not queue_free alone) inside
## _rebuild_topic_list: this runs synchronously from the button's OWN
## pressed handler, and Object.free() refuses to free a locked object
## mid-signal-emission -- the same fix CraftingWindow/QuestLogWindow's own
## refresh() already documents.
func _on_topic_chosen(beat: Dictionary) -> void:
	_response_label.text = OfflineRenderer.render(beat)
	_beats.erase(beat)
	topic_chosen.emit(str(beat.get("topic_id", "")))
	_rebuild_topic_list()
