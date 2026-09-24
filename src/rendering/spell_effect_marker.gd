extends Sprite2D

## The transient visual for one spell atom's effect (docs/concept/
## spell_runtime.md, magic.md's atom-effects section, spell_vfx.md's shader
## layer): a procedural grow-hold-fade Tween over the atom's own sprite
## (illustrated when one exists, ProceduralSpellEffectSprite's generated
## shape when it does not -- see IllustratedSpellEffectArt), with two
## shader techniques layered on top of whichever sprite is showing: an
## additive glow halo (every atom) and a screen-space impact warp
## (burst-family atoms only). Motion is procedural (a Tween), not a
## hand-baked multi-frame animation -- the same spirit as WeaponSwing's own
## pure-rotation swing, just for a burst instead of an arc. Thin
## Node-composition glue over tested pure generation; not unit-tested
## beyond "does it show the right art, wire the right shaders, and clean up
## after itself," the same boundary this codebase's other cosmetic marker
## nodes already sit on.

const ProceduralSpellEffectSprite = preload("res://src/rendering/procedural_spell_effect_sprite.gd")
const IllustratedSpellEffectArt = preload("res://src/rendering/illustrated_spell_effect_art.gd")
const SpellGlowShader = preload("res://src/rendering/spell_glow_shader.gd")
const SpellImpactDistortionShader = preload("res://src/rendering/spell_impact_distortion_shader.gd")

const GROW_DURATION := 0.12
const HOLD_DURATION := 0.15
const FADE_DURATION := 0.35

## Shared across every marker, same reasoning as the generator's own
## _texture_cache being static: the art is a pure function of the atom id.
static var _art := IllustratedSpellEffectArt.new()

## The halo this cast spawned, if any -- kept only so its lifetime can be
## tied to this marker's own tween sequence.
var _glow_halo: MeshInstance2D


## Builds this marker's art for `atom_id`, wires this atom's shader
## techniques (spell_vfx.md), and starts its grow-hold-fade animation,
## freeing itself -- and its glow halo -- when it finishes.
func play(atom_id: String) -> void:
	texture = _art.texture_for(atom_id)
	scale = Vector2.ZERO
	modulate.a = 1.0

	var total_duration := GROW_DURATION + HOLD_DURATION + FADE_DURATION
	var grow_fraction := GROW_DURATION / total_duration
	var hold_fraction := HOLD_DURATION / total_duration

	if SpellImpactDistortionShader.atom_gets_distortion(atom_id):
		material = SpellImpactDistortionShader.material_for()
		# Peaks right as the burst finishes gathering -- the instant of
		# release, not the hold or the fade.
		material.set_shader_parameter("peak_fraction", grow_fraction)

	_glow_halo = _spawn_glow_halo(atom_id, grow_fraction, hold_fraction)

	# A SEPARATE tween drives the shared `progress` clock both shaders read,
	# rather than shoehorning it into the existing scale/hold/alpha-fade
	# sequence below (which is sequential -- one step at a time -- while
	# `progress` must run continuously across the whole beat). Two Tweens on
	# one node animating different things is safe in Godot; there is no
	# property they could fight over.
	var progress_tween := create_tween()
	progress_tween.tween_method(
		_apply_progress, 0.0, 1.0, total_duration
	)

	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2.ONE, GROW_DURATION).set_trans(Tween.TRANS_BACK).set_ease(
		Tween.EASE_OUT
	)
	tween.tween_interval(HOLD_DURATION)
	tween.tween_property(self, "modulate:a", 0.0, FADE_DURATION)
	tween.tween_callback(queue_free)
	if _glow_halo != null:
		tween.tween_callback(_glow_halo.queue_free)


## Pushes the shared `progress` clock (0 at cast start, 1 at animation end)
## onto every shader this cast is using -- the halo's own material and, for
## a burst-family atom, this sprite's own distortion material -- so both
## stay in exact lockstep with the marker's own beat rather than running an
## independently-timed clock of their own.
func _apply_progress(value: float) -> void:
	if material != null:
		material.set_shader_parameter("progress", value)
	if _glow_halo != null:
		(_glow_halo.material as ShaderMaterial).set_shader_parameter("progress", value)


## The ambient glow every atom casts (spell_vfx.md) -- a sibling
## `MeshInstance2D`, not a material on this sprite: it needs to read
## further out than this sprite's own silhouette, and a fresh
## `ShaderMaterial` per cast so two casts mid-flight together never share
## (and stomp) one `progress` uniform. `null` when this marker has not been
## added to the tree yet (no parent to spawn a sibling under).
func _spawn_glow_halo(atom_id: String, grow_fraction: float, hold_fraction: float) -> MeshInstance2D:
	if get_parent() == null:
		return null
	var halo_size := float(ProceduralSpellEffectSprite.SIZE) * SpellGlowShader.HALO_SIZE_MULTIPLIER
	var quad := QuadMesh.new()
	quad.size = Vector2(halo_size, halo_size)
	var halo := MeshInstance2D.new()
	halo.mesh = quad
	halo.material = SpellGlowShader.material_for(atom_id)
	# The GLSL's own grow_fraction/hold_fraction uniforms default close to
	# these but must be set explicitly to the REAL derived values -- a
	# shader whose defaults merely happen to resemble the marker's true
	# beat is exactly the "eyeballed number" CLAUDE.md forbids; this is
	# what makes them the ACTUAL number rather than a lookalike.
	halo.material.set_shader_parameter("grow_fraction", grow_fraction)
	halo.material.set_shader_parameter("hold_fraction", hold_fraction)
	halo.position = position
	get_parent().add_child(halo)
	# Drawn BEHIND this sprite (a lower sibling index draws first, so a
	# later sibling paints over it): light spilling outward only reads
	# correctly if the sprite's own crisp silhouette sits on top of it.
	get_parent().move_child(halo, get_index())
	return halo
