extends PanelContainer

## A slot Control you can drag an item out of and/or drop an item onto.
##
## Godot's drag-and-drop is virtual-method based (_get_drag_data /
## _can_drop_data / _drop_data), which plain code-built PanelContainers can't
## participate in -- this is the one small subclass that does, with the actual
## behavior injected as Callables so both the inventory grid and the HUD
## hotbar can reuse it without either knowing about the other.
##
## `drag_payload` is what this slot offers when dragged (null == not
## draggable). Drop targets receive that same payload and decide via
## `can_accept` whether they'll take it.

## The payload this slot hands over when dragged; null makes it drop-only.
var drag_payload = null

## func(payload) -> bool: whether a drop of `payload` is allowed here.
## Unset makes this slot drag-only (it accepts nothing).
var can_accept: Callable = Callable()

## func(payload) -> void: apply an accepted drop.
var dropped: Callable = Callable()

## func() -> Control: optional floating preview drawn under the cursor while
## dragging. Godot requires it be set during _get_drag_data.
var make_preview: Callable = Callable()


func _get_drag_data(_at_position: Vector2):
	if drag_payload == null:
		return null
	if make_preview.is_valid():
		set_drag_preview(make_preview.call())
	return drag_payload


func _can_drop_data(_at_position: Vector2, data) -> bool:
	if not can_accept.is_valid():
		return false
	return can_accept.call(data)


func _drop_data(_at_position: Vector2, data) -> void:
	if dropped.is_valid():
		dropped.call(data)
