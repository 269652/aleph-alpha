extends RefCounted

## Real illustrated art for one spell atom's effect, by address --
## docs/concept/spell_vfx.md's "IllustratedSpellEffectArt", the exact bridge
## role `IllustratedItemArt` fills for items: registry entry -> resolved
## address (against the real file tree) -> loaded, keyed frames ->
## `ImageTexture`, illustrated when one exists, `ProceduralSpellEffectSprite`
## when it does not.
##
## `ai_sprite_prompts.md` section 8 has had complete prompts for all 25
## atoms since 2026-08-28. This is the piece that was missing between them
## and the screen -- the same shape of gap `IllustratedItemArt`'s own doc
## comment named for items: *"the registry knew ~100 subjects... and not one
## pixel of the real art on disk ever reached the screen."*

const IllustratedArtRegistry = preload("res://src/rendering/illustrated_art_registry.gd")
const IllustratedArtResolver = preload("res://src/rendering/illustrated_art_resolver.gd")
const IllustratedArtLoader = preload("res://src/rendering/illustrated_art_loader.gd")
const ProceduralSpellEffectSprite = preload("res://src/rendering/procedural_spell_effect_sprite.gd")

## Where a subject's own art tree is rooted -- the same root every other
## illustrated subject uses (docs/concept/illustrated_art_addressing.md).
const ART_ROOT := "res://assets/sprites"

## docs/concept/spell_vfx.md's address table: the four axes that vary for
## an item mean nothing for a spell atom, so they are fixed rather than
## exposed as parameters nothing would ever want to change.
const _CONTEXT := "effect"
const _SEASON := "any"
const _STATE := "default"
const _ANIMATION := "cast"

## The canvas an illustrated frame is fitted to --
## ProceduralSpellEffectSprite.SIZE on purpose, the same "drop-in
## replacement" contract IllustratedItemArt's own CANVAS_SIZE keeps against
## ProceduralItemSprite.
const CANVAS_SIZE := Vector2i(ProceduralSpellEffectSprite.SIZE, ProceduralSpellEffectSprite.SIZE)

## Only `footprint` anchoring reads this, and no spell-effect context ever
## uses that anchor -- passed through as the loader's documented ignored
## argument, same as IllustratedItemArt's own _UNUSED_TILE_SIZE.
const _UNUSED_TILE_SIZE := ProceduralSpellEffectSprite.SIZE

var _registry := IllustratedArtRegistry.new()
var _loader := IllustratedArtLoader.new()
var _procedural := ProceduralSpellEffectSprite.new()

## address string -> ImageTexture (or null, cached as "known absent").
var _texture_cache: Dictionary = {}
var _frames_cache: Dictionary = {}


## The one file an atom's effect address names. Pure -- no disk, no
## registry -- mirroring IllustratedItemArt.path_for's own contract, with
## the four non-varying axes collapsed rather than taken as parameters.
static func path_for(atom_id: String) -> String:
	return "%s/%s/%s/%s/%s/%s.png" % [ART_ROOT, atom_id, _CONTEXT, _SEASON, _STATE, _ANIMATION]


## Which address actually serves, resolved against the REAL tree.
## `is_procedural` true means this atom has nothing drawn for it and the
## caller keeps its generated sprite.
func resolve(atom_id: String) -> Dictionary:
	if not _registry.has_subject(atom_id):
		return {
			"is_procedural": true, "context": _CONTEXT,
			"season": _SEASON, "state": _STATE, "animation": _ANIMATION,
		}
	var entry := _registry.entry_for(atom_id)
	return IllustratedArtResolver.resolve(
		_CONTEXT, _SEASON, _STATE, _ANIMATION, entry,
		func(c: String, se: String, st: String, a: String) -> bool:
			return ResourceLoader.exists(_path_for_address(atom_id, c, se, st, a))
	)


## The real art for this atom, or null when it has none -- null is the
## caller's cue to keep its generated sprite.
func illustrated_texture_for(atom_id: String) -> ImageTexture:
	var frames := frames_for(atom_id)
	return null if frames.is_empty() else frames[0]


## Every frame of the resolved cast row, in order -- empty for a
## procedural-only atom. Not yet consumed by SpellEffectMarker (see
## spell_vfx.md's "One frame, not yet the full beat"), built now so the day
## the marker plays a real beat instead of tweening one frame, the frames
## are already one call away.
func frames_for(atom_id: String) -> Array[ImageTexture]:
	var address := resolve(atom_id)
	if address.is_procedural:
		return []
	var key := "%s|%s|%s|%s|%s" % [
		atom_id, address.context, address.season, address.state, address.animation
	]
	if not _frames_cache.has(key):
		_frames_cache[key] = _build_frames(atom_id, address)
	return _frames_cache[key]


## What a call site draws: the illustrated picture when one exists, the
## generated one when it does not -- always at CANVAS_SIZE, so it drops in
## exactly where the generated sprite stood.
func texture_for(atom_id: String) -> ImageTexture:
	var illustrated := illustrated_texture_for(atom_id)
	if illustrated == null:
		return _procedural.texture_for(atom_id)
	var key := "fitted|%s" % atom_id
	if not _texture_cache.has(key):
		_texture_cache[key] = _fitted(illustrated)
	return _texture_cache[key]


## `texture` scaled uniformly so its longest side is CANVAS_SIZE -- itself
## when it already is, so nothing the loader already fitted is resampled a
## second time. Identical to IllustratedItemArt._fitted; duplicated rather
## than shared because that one is keyed to ProceduralItemSprite's own
## CANVAS_SIZE and the two are only coincidentally the same number today.
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


func _build_frames(atom_id: String, address: Dictionary) -> Array[ImageTexture]:
	var entry := _registry.entry_for(atom_id)
	var contexts: Dictionary = entry.get("contexts", {})
	var declared: Dictionary = contexts.get(address.context, {})
	var images := _loader.load_row(
		_path_for_address(atom_id, address.context, address.season, address.state, address.animation),
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


static func _path_for_address(
	atom_id: String, context: String, season: String, state: String, animation: String
) -> String:
	return "%s/%s/%s/%s/%s/%s.png" % [ART_ROOT, atom_id, context, season, state, animation]
