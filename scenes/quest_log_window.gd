extends PanelContainer

## Player-facing surface for the real, live quest system (src/emergence/
## quest.gd's stateless production-shortfall projection + QuestLog's own
## accept/abandon/reconcile commitment layer, see docs/concept/
## karma_and_luck.md's "Quest lifecycle: accept, abandon, fulfil") -- toggle U.
##
## Reported gap, confirmed by reading the code directly rather than assumed:
## QuestLog.reconcile already runs every frame in World, correctly
## auto-fulfilling (+1 Karma) and cleaning up any accepted quest whose real
## shortage resolves -- but nothing anywhere ever called QuestLog.accept or
## QuestLog.abandon, and there was no UI at all showing a quest even
## existed. A player could not so much as SEE this system running, let
## alone engage with it; `reconcile`'s own auto-fulfil logic had never once
## fired for a real player before this, only in tests that hand-populate
## accepted_quest_ids directly.
##
## Two sections, same "toggle window, refresh from live state" shape
## InventoryWindow/CraftingWindow already use: ACCEPTED (this player's own
## commitment record, cross-referenced back against the live projection for
## display text) and AVAILABLE (live, not-yet-accepted production-shortfall
## quests). World passes every settlement the world currently knows about
## (see EarthChunkManager.all_production_shortfall_quests) -- not actually
## distance-filtered to "near the player" yet, despite this file's own
## `nearby_quests` parameter name below; a real proximity filter is a
## natural, separate follow-up once settlements outnumber a screenful.
## World owns the actual QuestLog.accept/abandon calls this window's own
## signals request -- purely glue, same division of responsibility
## CraftingWindow's craft_requested signal already uses.

const QuestLog = preload("res://src/emergence/quest_log.gd")
const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

signal accept_requested(offer_id: String)
signal abandon_requested(offer_id: String)

var _item_catalog := ItemCatalog.new()
var _accepted_container: VBoxContainer
var _available_container: VBoxContainer
var _last_refresh_signature := ""


func _ready() -> void:
	visible = false
	# A fixed window footprint regardless of quest count -- the scroll
	# container below absorbs overflow, same reasoning CraftingWindow's own
	# doc comment gives for its identical shape.
	custom_minimum_size = Vector2(480, 420)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var title := Label.new()
	title.text = "Quests"
	title.add_theme_font_size_override("font_size", UiTheme.TITLE_FONT_SIZE)
	root.add_child(title)

	var hint := Label.new()
	hint.text = "Real households short on real materials -- help nearby, or check what you've already promised."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(1, 1, 1, 0.6)
	root.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	var sections := VBoxContainer.new()
	sections.add_theme_constant_override("separation", 12)
	sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(sections)

	sections.add_child(_section_header("Accepted"))
	_accepted_container = VBoxContainer.new()
	_accepted_container.add_theme_constant_override("separation", 6)
	sections.add_child(_accepted_container)

	sections.add_child(_section_header("Available Nearby"))
	_available_container = VBoxContainer.new()
	_available_container.add_theme_constant_override("separation", 6)
	sections.add_child(_available_container)


func _section_header(text: String) -> Label:
	var header := Label.new()
	header.text = text
	header.add_theme_font_size_override("font_size", UiTheme.BASE_FONT_SIZE + 2)
	header.add_theme_color_override("font_color", UiTheme.ACCENT)
	return header


func toggle() -> void:
	visible = not visible


func is_open() -> bool:
	return visible


## Rebuilds both sections against the CURRENT live quest list and the
## player's own accepted_quest_ids -- a no-op when nothing relevant has
## changed since the last call (same memoized-signature shape
## CraftingWindow.refresh already uses). `nearby_quests` is named for the
## intended eventual scope (see this file's own header doc comment) -- today
## World actually passes every known settlement's quests, unfiltered; this
## window itself has no concept of distance either way. An accepted
## offer_id no longer present in `nearby_quests` (its settlement's shortage
## already resolved a frame before this exact refresh, or a future distance
## filter drops it) is deliberately
## still shown, decoded from the offer_id itself -- a player's own log
## should never silently blank an entry they still have to abandon out of.
func refresh(nearby_quests: Array, accepted_quest_ids: Array) -> void:
	var signature := "%s|%s" % [_signature_for(nearby_quests), ",".join(accepted_quest_ids)]
	if signature == _last_refresh_signature:
		return
	_last_refresh_signature = signature

	# remove_child (not queue_free alone): refresh() can run synchronously
	# from inside a card's OWN button press handler (click -> *_requested ->
	# World -> refresh, all on the same call stack), and Object.free()
	# refuses to free a locked object mid-signal-emission -- same fix
	# CraftingWindow.refresh's own doc comment already documents.
	for child in _accepted_container.get_children():
		_accepted_container.remove_child(child)
		child.queue_free()
	for child in _available_container.get_children():
		_available_container.remove_child(child)
		child.queue_free()

	var quests_by_offer_id := {}
	for quest in nearby_quests:
		quests_by_offer_id[QuestLog.offer_id_for(quest)] = quest

	if accepted_quest_ids.is_empty():
		_accepted_container.add_child(_empty_label("No quests accepted yet."))
	for offer_id in accepted_quest_ids:
		var quest: Dictionary = quests_by_offer_id.get(offer_id, _quest_from_offer_id(offer_id))
		_accepted_container.add_child(_build_card(quest, offer_id, true))

	var available: Array = nearby_quests.filter(
		func(q): return not accepted_quest_ids.has(QuestLog.offer_id_for(q))
	)
	if available.is_empty():
		_available_container.add_child(_empty_label("Nothing needs your help nearby right now."))
	for quest in available:
		_available_container.add_child(_build_card(quest, QuestLog.offer_id_for(quest), false))


func _empty_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.modulate = Color(1, 1, 1, 0.5)
	return label


## Best-effort reconstruction from an offer_id alone (QuestLog.offer_id_for's
## own "production:<household_id>:<recipe_id>" format) for an accepted quest
## the live projection no longer names -- enough to still show SOMETHING
## real rather than blank, at the cost of not knowing `missing`/`occupation`
## anymore (the projection genuinely doesn't have them once the household's
## shortage itself is what stopped being current).
func _quest_from_offer_id(offer_id: String) -> Dictionary:
	var parts := offer_id.split(":")
	if parts.size() != 3:
		return {}
	return {"household_id": parts[1], "recipe_id": parts[2], "missing": []}


## One quest's card: who needs what, and an Accept/Abandon button.
## `occupation` (added specifically for this display -- see
## test_the_quest_names_the_households_own_occupation) reads far better
## than the household's own internal id; a quest reconstructed from a bare
## offer_id (see _quest_from_offer_id) has no occupation and falls back to
## the household_id itself, humanized.
func _build_card(quest: Dictionary, offer_id: String, accepted: bool) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)

	var who := Label.new()
	var occupation: String = quest.get("occupation", "")
	who.text = (
		"The %s" % occupation.capitalize() if occupation != ""
		else "Household %s" % String(quest.get("household_id", "?")).capitalize()
	)
	who.add_theme_font_size_override("font_size", UiTheme.BASE_FONT_SIZE + 1)
	text.add_child(who)

	var need := Label.new()
	need.text = _needs_line(quest.get("missing", []))
	need.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	need.modulate = Color(1, 1, 1, 0.75)
	text.add_child(need)

	var button := Button.new()
	button.text = "Abandon" if accepted else "Accept"
	button.pressed.connect(
		func():
			if accepted:
				abandon_requested.emit(offer_id)
			else:
				accept_requested.emit(offer_id)
	)
	row.add_child(button)

	return card


## "needs 3 Iron Ore" / "needs 2 Wood, 1 Rock" / "needs nothing further right
## now" (the last: a quest whose shortage resolved in the frame between
## World's own live query and this exact refresh -- `missing` empty is a
## real, valid, momentary state, not an error, since reconcile() removes it
## from accepted_quest_ids on the very next tick regardless).
func _needs_line(missing: Array) -> String:
	if missing.is_empty():
		return "needs nothing further right now"
	var parts: Array[String] = []
	for entry in missing:
		var item_id: String = entry.get("item_id", "")
		var display_name := item_id.capitalize()
		if _item_catalog.has(item_id):
			display_name = _item_catalog.make(item_id).display_name
		parts.append("%d %s" % [int(entry.get("need", 0)), display_name])
	return "needs " + ", ".join(parts)


func _signature_for(nearby_quests: Array) -> String:
	var offer_ids: Array[String] = []
	for quest in nearby_quests:
		offer_ids.append(QuestLog.offer_id_for(quest))
	offer_ids.sort()
	return ",".join(offer_ids)
