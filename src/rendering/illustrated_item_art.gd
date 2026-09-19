extends RefCounted

## Real illustrated art for one item, by address -- the piece that was
## missing between the three halves docs/concept/illustrated_art_addressing.md
## already specified and shipped.
##
## That doc's Status list carried "Rendering: Player/CharacterView drawing
## held-item animations by address" as ⬜ from the day the convention
## landed, and the gap was wider than it looked: nothing anywhere called
## IllustratedArtLoader at all. It appeared only inside OTHER files' doc
## comments. So the registry knew ~100 subjects, the resolver knew the
## fallback lattice, the loader knew how to slice and anchor a sheet, and
## not one pixel of the real art on disk ever reached the screen -- every
## item still drew ProceduralItemSprite's generated shape.
##
## Reported directly: *"Can you wire the real tool sprites? Axe is
## currently using procedural sprite, but should use the illustrated one"*,
## and *"Sword as well"*.
##
## This chains the three: registry entry -> resolved address (against the
## REAL file tree, which is the half that never existed -- the resolver
## takes `address_exists` as a Callable precisely so it never touches a
## disk itself) -> loaded, keyed, anchored frames -> an ImageTexture.
##
## `texture_for` is the one every call site wants: illustrated when there
## is art, generated when there is not. A subject with no art behaves
## exactly as it did before this file existed, which is what makes wiring
## it up safe for all ~100 at once rather than one id at a time.

const IllustratedArtRegistry = preload("res://src/rendering/illustrated_art_registry.gd")
const IllustratedArtResolver = preload("res://src/rendering/illustrated_art_resolver.gd")
const IllustratedArtLoader = preload("res://src/rendering/illustrated_art_loader.gd")
const ProceduralItemSprite = preload("res://src/rendering/procedural_item_sprite.gd")

## Where a subject's own art tree is rooted (the doc's "The address").
const ART_ROOT := "res://assets/sprites"

## The canvas an illustrated frame is fitted to. ProceduralItemSprite.SIZE
## on purpose, not a number of its own: an illustrated icon then drops into
## the hotbar slot, the dropped-item sprite and the armour rig exactly where
## the generated one stood, so no call site re-scales and
## ProceduralItemSprite.world_scale_for keeps meaning what it meant. Pinned
## by test_an_illustrated_icon_is_the_same_size_as_the_generated_one_it_
## replaces.
const CANVAS_SIZE := Vector2i(ProceduralItemSprite.SIZE, ProceduralItemSprite.SIZE)

## Only `footprint` reads this, and no item context uses that anchor -- a
## placed structure's tile size is EarthChunkManager's business, not an
## inventory icon's. Passed as the loader's documented ignored argument.
const _UNUSED_TILE_SIZE := ProceduralItemSprite.SIZE

var _registry := IllustratedArtRegistry.new()
var _loader := IllustratedArtLoader.new()
var _procedural := ProceduralItemSprite.new()

## address string -> ImageTexture (or null, cached as "known absent").
## The hotbar asks per frame; a 328x300 PNG must be read, keyed and
## anchored once, not sixty times a second.
var _texture_cache: Dictionary = {}
var _frames_cache: Dictionary = {}


## The file an address names (docs/concept/illustrated_art_addressing.md,
## "The address"). Pure -- no disk, no registry.
static func path_for(
	subject: String, context: String, season: String, state: String, animation: String
) -> String:
	return "%s/%s/%s/%s/%s/%s.png" % [ART_ROOT, subject, context, season, state, animation]


## Which address actually serves (subject, context, state, animation),
## resolved against the REAL tree. `is_procedural` true means this subject
## has nothing drawn for it and the caller keeps its generated sprite.
func resolve(
	subject: String, context: String, state := "", animation := "still", season := "any"
) -> Dictionary:
	if not _registry.has_subject(subject):
		return _procedural_address(context, season, state, animation)
	var entry := _registry.entry_for(subject)
	var wanted_state: String = state if state != "" else String(entry.get("base_state", ""))
	return IllustratedArtResolver.resolve(
		context, season, wanted_state, animation, entry,
		func(c: String, se: String, st: String, a: String) -> bool:
			return ResourceLoader.exists(path_for(subject, c, se, st, a))
	)


## The real art for this address, or null when the subject has none --
## null is the caller's cue to keep its generated sprite.
func illustrated_texture_for(
	subject: String, context: String, state := "", animation := "still", season := "any"
) -> ImageTexture:
	var frames := frames_for(subject, context, state, animation, season)
	return null if frames.is_empty() else frames[0]


## Every frame of the resolved address, in order -- one entry for a still,
## several for a real animation row (the registry's own `animations` timing
## says how to play them; this only returns the pictures).
func frames_for(
	subject: String, context: String, state := "", animation := "still", season := "any"
) -> Array[ImageTexture]:
	var address := resolve(subject, context, state, animation, season)
	if address.is_procedural:
		return []
	var key := "%s|%s|%s|%s|%s" % [
		subject, address.context, address.season, address.state, address.animation
	]
	if not _frames_cache.has(key):
		_frames_cache[key] = _build_frames(subject, address)
	return _frames_cache[key]


## What a call site draws: the illustrated picture when one exists, the
## generated one when it does not -- always at CANVAS_SIZE, so it drops in
## exactly where the generated sprite stood.
##
## The fitting matters for `pivot` contexts. The loader's pivot anchor
## deliberately returns the WHOLE authored cell (220x300 for the axe in
## hand) so a grip point stays at the same pixel across frames, and
## CharacterView.equip_weapon sets `offset = -texture.get_height() / 2` --
## a 300px-tall texture displaces the grip by ten times what a 32px one
## does. Scaling the whole cell UNIFORMLY is compatible with the pivot
## contract rather than a violation of it: every pixel keeps its position
## relative to every other, so the grip point stays put, just at a
## different resolution. `center` contexts are already canvas-fitted by the
## loader and pass through untouched.
func texture_for(subject: String, context: String, state := "", animation := "still") -> ImageTexture:
	var illustrated := illustrated_texture_for(subject, context, state, animation)
	if illustrated == null:
		return _procedural.texture_for(subject)
	var key := "fitted|%s|%s|%s|%s" % [subject, context, state, animation]
	if not _texture_cache.has(key):
		_texture_cache[key] = _fitted(illustrated)
	return _texture_cache[key]


## `texture` scaled uniformly so its longest side is CANVAS_SIZE -- itself
## when it already is, so nothing the loader already fitted is resampled a
## second time.
static func _fitted(texture: ImageTexture) -> ImageTexture:
	var longest := maxi(texture.get_width(), texture.get_height())
	var target: int = maxi(CANVAS_SIZE.x, CANVAS_SIZE.y)
	if longest == target or longest <= 0:
		return texture
	var image := texture.get_image()
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	var scale := float(target) / float(longest)
	image.resize(
		maxi(1, int(round(float(texture.get_width()) * scale))),
		maxi(1, int(round(float(texture.get_height()) * scale))),
		Image.INTERPOLATE_LANCZOS
	)
	return ImageTexture.create_from_image(image)


func _build_frames(subject: String, address: Dictionary) -> Array[ImageTexture]:
	var entry := _registry.entry_for(subject)
	var contexts: Dictionary = entry.get("contexts", {})
	var declared: Dictionary = contexts.get(address.context, {})
	var images := _loader.load_row(
		path_for(subject, address.context, address.season, address.state, address.animation),
		String(declared.get("anchor", "center")),
		entry.get("chroma_key", Color(1.0, 0.0, 1.0)),
		float(entry.get("chroma_key_tolerance", 0.25)),
		CANVAS_SIZE,
		_UNUSED_TILE_SIZE
	)
	var out: Array[ImageTexture] = []
	for image in images:
		out.append(ImageTexture.create_from_image(image))
	return out


static func _procedural_address(
	context: String, season: String, state: String, animation: String
) -> Dictionary:
	return {
		"is_procedural": true, "context": context,
		"season": season, "state": state, "animation": animation,
	}
