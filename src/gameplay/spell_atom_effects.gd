extends RefCounted

## Dispatches one spell atom step's real effect against a resolved target
## (docs/concept/spell_runtime.md). Every operation is duck-typed against a
## small set of methods Player and CreatureMarker both implement --
## take_damage/heal/apply_knockback/apply_spell_debuff/apply_shield/position
## -- the same "one shared method, either receiver" shape take_damage itself
## already established, generalized. Returns true if the atom actually did
## something; false for a target missing the needed method, a null target,
## or an unrecognized atom -- the caller still spends the caster's mana
## regardless ("even an affordable spell still has to land", magic.md).
##
## Atoms NOT handled here: accelerate_growth/reveal target the WORLD (a
## plant, a chunk of the map), not a creature/player -- Player resolves
## those directly against its own _chunk_manager (see spell_runtime.md).
## portal/induce_mutation are deferred entirely (no effect at all yet).
## summon_wisp targets the CASTER (self-delivery) but IS handled here, via
## the same generic status dispatch as every other timed atom -- see
## SpellStatusEffects.SUMMON_WISP's own note on why it's tracked-only today.

const SpellAtomCatalog = preload("res://src/gameplay/spell_atom_catalog.gd")
const SpellStatusEffects = preload("res://src/gameplay/spell_status_effects.gd")

const _DAMAGE_ATOMS := ["fire_damage", "frost_damage", "shock_damage", "poison_damage"]
const _HEAL_ATOMS := ["minor_heal", "major_heal"]
const _FORCE_ATOMS := ["push", "pull"]

## atom_id -> the SpellStatusEffects debuff_id it applies. Every "timed, no
## extra magnitude" status atom routes through the SAME generic
## apply_spell_debuff(debuff_id, duration) call -- what holding each debuff
## actually MEANS (a damage tick, a movement lock, a speed penalty, a
## behavior-context override) is entirely the target's own concern, exactly
## like DebuffStack itself staying agnostic about what venom does.
const _STATUS_ATOMS := {
	"ignite": SpellStatusEffects.IGNITE,
	"blight": SpellStatusEffects.BLIGHT,
	"freeze": SpellStatusEffects.FREEZE,
	"root": SpellStatusEffects.ROOT,
	"slow": SpellStatusEffects.SLOW,
	"illuminate": SpellStatusEffects.ILLUMINATE,
	"calm": SpellStatusEffects.CALM,
	"fear": SpellStatusEffects.FEAR,
	"suppress_mutation": SpellStatusEffects.SUPPRESS_MUTATION,
	"summon_wisp": SpellStatusEffects.SUMMON_WISP,
}

var _catalog := SpellAtomCatalog.new()


func apply_to_target(atom_id: String, params: Dictionary, target, caster_position: Vector2, facing_direction: Vector2) -> bool:
	if target == null:
		return false
	if _DAMAGE_ATOMS.has(atom_id):
		return _apply_damage(atom_id, params, target)
	if _HEAL_ATOMS.has(atom_id):
		return _apply_heal(atom_id, params, target)
	if _FORCE_ATOMS.has(atom_id):
		return _apply_force(atom_id, params, target, caster_position)
	if _STATUS_ATOMS.has(atom_id):
		return _apply_status(atom_id, params, target)
	if atom_id == "shield":
		return _apply_shield(params, target)
	if atom_id == "teleport":
		return _apply_teleport(params, target, facing_direction)
	if atom_id == "gravity_shift":
		return _apply_gravity_shift(params, target, caster_position, facing_direction)
	return false


## Magnitude/duration, defaulting to the atom's own reference value from the
## catalog (the same "reference" spell_cost.gd's own atom_cost reads) when
## the spell text doesn't override it.
func _magnitude(atom_id: String, params: Dictionary) -> float:
	var reference := _catalog.mag_ref(atom_id) if _catalog.has(atom_id) else 0.0
	return float(params.get("magnitude", reference))


func _duration(atom_id: String, params: Dictionary) -> float:
	var reference := _catalog.dur_ref(atom_id) if _catalog.has(atom_id) else 0.0
	return float(params.get("duration", reference))


func _apply_damage(atom_id: String, params: Dictionary, target) -> bool:
	if not target.has_method("take_damage"):
		return false
	target.take_damage(_magnitude(atom_id, params))
	return true


func _apply_heal(atom_id: String, params: Dictionary, target) -> bool:
	if not target.has_method("heal"):
		return false
	target.heal(_magnitude(atom_id, params))
	return true


## A direction from the caster through the target, same convention
## MeleeAttack.knockback_vector already uses -- push extends it, pull
## reverses it. A target standing exactly on the caster (degenerate zero
## direction) falls back to a fixed direction, same as MeleeAttack's own
## "always actually displaces the target" guarantee.
func _apply_force(atom_id: String, params: Dictionary, target, caster_position: Vector2) -> bool:
	if not target.has_method("apply_knockback"):
		return false
	var direction: Vector2 = target.position - caster_position
	if direction.length() < 0.001:
		direction = Vector2.DOWN
	direction = direction.normalized()
	if atom_id == "pull":
		direction = -direction
	target.apply_knockback(direction * _magnitude(atom_id, params))
	return true


func _apply_status(atom_id: String, params: Dictionary, target) -> bool:
	if not target.has_method("apply_spell_debuff"):
		return false
	target.apply_spell_debuff(_STATUS_ATOMS[atom_id], _duration(atom_id, params))
	return true


func _apply_shield(params: Dictionary, target) -> bool:
	if not target.has_method("apply_shield"):
		return false
	target.apply_shield(_magnitude("shield", params), _duration("shield", params))
	return true


## No dry-land/collision validation -- that's _compute_dry_land_spawn_tile-
## grade expensive, chunk-aware work, the wrong cost for an instant cast (see
## spell_runtime.md's own honest note on this gap). A direction-less cast
## (no facing to teleport along) fails outright rather than guessing one.
func _apply_teleport(params: Dictionary, target, facing_direction: Vector2) -> bool:
	if facing_direction.length() < 0.001:
		return false
	target.position += facing_direction.normalized() * _magnitude("teleport", params)
	return true


## Approximated as a single strong shove scaled by BOTH magnitude and
## duration (a "bigger push", not a sustained levitation) -- no vertical/
## airborne axis exists anywhere in this 2D top-down game to build a real
## gravity mechanic on (see spell_runtime.md's own honest label on this).
func _apply_gravity_shift(params: Dictionary, target, caster_position: Vector2, facing_direction: Vector2) -> bool:
	if not target.has_method("apply_knockback"):
		return false
	var direction: Vector2 = target.position - caster_position
	if direction.length() < 0.001:
		direction = facing_direction if facing_direction.length() > 0.001 else Vector2.DOWN
	direction = direction.normalized()
	var force := _magnitude("gravity_shift", params) * maxf(_duration("gravity_shift", params), 1.0)
	target.apply_knockback(direction * force)
	return true
