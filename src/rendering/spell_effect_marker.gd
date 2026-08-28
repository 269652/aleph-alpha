extends Sprite2D

## The transient visual for one spell atom's effect (docs/concept/
## spell_runtime.md, magic.md's atom-effects section): a procedural
## grow-hold-fade Tween over the atom's own procedural sprite (see
## ProceduralSpellEffectSprite), freed on completion. Motion is procedural
## (a Tween), not a hand-baked multi-frame animation -- the same spirit as
## WeaponSwing's own pure-rotation swing, just for a burst instead of an arc.
## Thin Node-composition glue over tested pure generation; not unit-tested
## beyond "does it show the right art and clean up," the same boundary this
## codebase's other cosmetic marker nodes already sit on.

const ProceduralSpellEffectSprite = preload("res://src/rendering/procedural_spell_effect_sprite.gd")

const GROW_DURATION := 0.12
const HOLD_DURATION := 0.15
const FADE_DURATION := 0.35

## Shared across every marker, same reasoning as the generator's own
## _texture_cache being static: the art is a pure function of the atom id.
static var _generator := ProceduralSpellEffectSprite.new()


## Builds this marker's art for `atom_id` and starts its grow-hold-fade
## animation, freeing itself when it finishes.
func play(atom_id: String) -> void:
	texture = _generator.texture_for(atom_id)
	scale = Vector2.ZERO
	modulate.a = 1.0

	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2.ONE, GROW_DURATION).set_trans(Tween.TRANS_BACK).set_ease(
		Tween.EASE_OUT
	)
	tween.tween_interval(HOLD_DURATION)
	tween.tween_property(self, "modulate:a", 0.0, FADE_DURATION)
	tween.tween_callback(queue_free)
