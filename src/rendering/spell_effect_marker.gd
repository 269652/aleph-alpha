extends Sprite2D

## The transient visual for one spell atom's effect (docs/concept/
## spell_runtime.md, magic.md's atom-effects section): a procedural
## grow-hold-fade Tween over the atom's own art, freed on completion.
## Illustrated art (see IllustratedSpellEffectSprite) takes priority when
## an atom has it; ProceduralSpellEffectSprite is the fallback for one that
## doesn't (per magic.md's "procedural fallback first" two-track pattern --
## no real catalog atom is missing illustrated art anymore, but a future
## one added to spell_atom_catalog.gd without art yet must still render
## something). The grow/scale/fade motion is unchanged either way -- a
## procedural Tween, not a hand-baked animation, the same spirit as
## WeaponSwing's own pure-rotation swing, just for a burst instead of an
## arc. Illustrated art additionally steps through its own real 6-frame
## wind-up/peak/fade cycle (a second, parallel Tween) across that same
## total duration, evenly spaced -- the procedural texture has no frames to
## step through, so this is a no-op for it. Thin Node-composition glue over
## tested pure generation; not unit-tested beyond "does it show the right
## art and clean up," the same boundary this codebase's other cosmetic
## marker nodes already sit on.

const ProceduralSpellEffectSprite = preload("res://src/rendering/procedural_spell_effect_sprite.gd")
const IllustratedSpellEffectSprite = preload("res://src/rendering/illustrated_spell_effect_sprite.gd")

const GROW_DURATION := 0.12
const HOLD_DURATION := 0.15
const FADE_DURATION := 0.35
const TOTAL_DURATION := GROW_DURATION + HOLD_DURATION + FADE_DURATION

## Shared across every marker, same reasoning as the generators' own
## caches being static: the art is a pure function of the atom id.
static var _generator := ProceduralSpellEffectSprite.new()
static var _illustrated := IllustratedSpellEffectSprite.new()


## Builds this marker's art for `atom_id` and starts its grow-hold-fade
## animation, freeing itself when it finishes.
##
## `start_delay` and `scale_multiplier` exist for a chained multi-atom cast
## (scenes/player.gd's pipeline loop, e.g. `fire_damage |> ignite`): every
## atom in one cast used to spawn its own marker in the same frame, all
## growing in at once -- two disconnected pops rather than one cascading
## blow. A small increasing `start_delay` per pipeline step staggers them
## into a real sequence, and a small increasing `scale_multiplier` reads
## as the blow building rather than repeating. Both default to "no change"
## so a single-atom cast is unaffected.
func play(atom_id: String, start_delay: float = 0.0, scale_multiplier: float = 1.0) -> void:
	var frames := _illustrated.frames_for(atom_id)
	texture = frames[0] if not frames.is_empty() else _generator.texture_for(atom_id)
	scale = Vector2.ZERO
	modulate.a = 1.0
	var grown_scale := Vector2.ONE * scale_multiplier

	var tween := create_tween()
	if start_delay > 0.0:
		tween.tween_interval(start_delay)
	tween.tween_property(self, "scale", grown_scale, GROW_DURATION).set_trans(Tween.TRANS_BACK).set_ease(
		Tween.EASE_OUT
	)
	tween.tween_interval(HOLD_DURATION)
	tween.tween_property(self, "modulate:a", 0.0, FADE_DURATION)
	tween.tween_callback(queue_free)

	if frames.size() > 1:
		var frame_tween := create_tween()
		if start_delay > 0.0:
			frame_tween.tween_interval(start_delay)
		var step := TOTAL_DURATION / float(frames.size())
		for i in range(1, frames.size()):
			frame_tween.tween_interval(step)
			frame_tween.tween_callback(_set_texture.bind(frames[i]))


func _set_texture(new_texture: Texture2D) -> void:
	texture = new_texture
