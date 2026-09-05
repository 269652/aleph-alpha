extends RefCounted

## The land-mammal adapter onto the behaviour kernel (docs/concept/
## ethogram.md §7). CreatureMarker gathers what a creature senses and how it
## feels into a flat context and applies the result; this turns that context
## into the kernel's terms -- stimuli on the shared channel basis, expressed
## receptors, drive levels -- and runs Ethogram.BODY_PLANS["mammal"]'s
## wirings over them. No engine dependency, no RNG.
##
## The priority the ladder encodes (most urgent first), for the same reasons
## as ever -- an animal does not court while it is being hunted, dying of
## thirst, starving, or (for a predator) mid-hunt:
##   1. A nearby threat -> flee (calm, or weak) / attack (aggressive AND strong)
##   2. Thirsty -> seek water (in reach) or search for it (roam) if none sensed
##   3. Hungry predator with prey in reach -> hunt (its way of feeding)
##   4. Hungry, with smells in the context -> seek the best-smelling food
##   5. Hungry -> seek food (in reach) or search for it (roam) if none sensed
##   6. Paired for courtship (see MammalCourtship / World._pair_up_courtships)
##      -> court: walk toward the partner and linger near it
##   7. Nothing pressing -> wander
## That order is DATA (Ethogram.BODY_PLANS["mammal"]["wirings"]) and is
## pinned by test_ethogram's ladder-order test, not by the nesting of ifs.
## The caller (CreatureMarker/World) only ever sets "is_courting" once
## AnimalReproduction.can_reproduce() already gated eligibility AND an
## eligible same-species neighbour was actually found nearby -- this adapter
## does not re-check either, it only says where courtship ranks.
##
## Context keys, all as before, plus three optional ones:
##   position, temperament, is_predator, health_fraction, hungry, thirsty,
##   threats, prey, food_direction, water_direction, is_courting,
##   partner_position; is_mature (defaults to true) and is_world_boss /
##   is_aggroed (default to false) so contexts built before those keys
##   existed keep behaving exactly as they did
##   species  (optional) the ethogram record to express; a species with no
##            record runs the ladder on the body plan's defaults
##   genome   (optional) this individual's receptor genes (Ethogram.express)
##   smells   (optional) a {position, mixture} list in EarthChunkManager.
##            smells_near's own shape. Nothing live passes this yet:
##            ScentForaging does the job inside CreatureMarker until the
##            marker publishes its senses as stimuli (ethogram.md §8).
##
## "seek_*" heads toward a sensed resource; "search_*" means the need exists
## but nothing's in range, so the creature should roam to look (the caller
## supplies the roaming heading, same as it does for "wander"). The decision
## also names its `target` and `score` (see BehaviorKernel.decide) for a
## caller that wants them; CreatureMarker reads only intent and direction.

const Ethogram = preload("res://src/gameplay/ethogram.gd")
const BehaviorKernel = preload("res://src/gameplay/behavior_kernel.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

## The body plan every CreatureMarker species runs on.
const BODY_PLAN := "mammal"

## A creature only stands and fights a threat if it's at least this healthy;
## below it, even an aggressive creature flees ("weak monsters should flee").
const STRONG_HEALTH_FRACTION := 0.5

## A sensed DIRECTION (food, water) becomes a stimulus one tile ahead. Any
## positive distance hands the same normalised heading back; one tile keeps
## it in scale with the positions the kernel ranks it against.
const DIRECTION_STIMULUS_DISTANCE := float(TerrainRenderer.TILE_SIZE)


func decide(context: Dictionary) -> Dictionary:
	return BehaviorKernel.decide(
		Ethogram.wirings_for(BODY_PLAN),
		_receptors(context),
		_drives(context),
		context["position"],
		_stimuli(context),
	)


## This individual's expressed receptors, with the two overrides that are
## species and state facts reaching decide() only as context flags today
## (ethogram.md §3): who stands and fights, and who eats prey. An un-aggroed
## world boss gets zero danger SENSITIVITY -- it genuinely does not perceive
## the player as a threat, so it neither attacks nor flees and still drinks
## and eats -- rather than zero valence.
func _receptors(context: Dictionary) -> Dictionary:
	var receptors := Ethogram.express(
		String(context.get("species", "")), context.get("genome", {}), BODY_PLAN
	)
	receptors["sensitivity"][Ethogram.DANGER] = 1.0 if _perceives_threats(context) else 0.0
	receptors["valence"][Ethogram.DANGER] = 1.0 if _will_fight(context) else -1.0
	receptors["valence"][Ethogram.FLESH] = 1.0 if context["is_predator"] else 0.0
	return receptors


## Drive levels: the needs the caller already tracks, as gains. Fear is
## always open (the world-boss case is sensitivity, above). Levels are 0/1
## because CreatureNeeds' own thresholds are; ramps are ethogram.md's slice 3.
func _drives(context: Dictionary) -> Dictionary:
	return {
		Ethogram.DRIVE_FEAR: 1.0,
		Ethogram.DRIVE_THIRST: 1.0 if context["thirsty"] else 0.0,
		Ethogram.DRIVE_HUNGER: 1.0 if context["hungry"] else 0.0,
		Ethogram.DRIVE_COURTSHIP: 1.0 if context.get("is_courting", false) else 0.0,
	}


## Everything sensed, as stimuli on the shared basis. `danger` and `flesh`
## are the marker's own classifications handed over as features (ethogram.md
## §1 names this for what it is); smells are already feature vectors.
func _stimuli(context: Dictionary) -> Array:
	var position: Vector2 = context["position"]
	var stimuli: Array = []
	for at in context["threats"]:
		stimuli.append({"position": at, "features": {Ethogram.DANGER: 1.0}})
	for at in context["prey"]:
		stimuli.append({"position": at, "features": {Ethogram.FLESH: 1.0}})
	_append_direction(stimuli, position, context["water_direction"], Ethogram.WATER)
	_append_direction(stimuli, position, context["food_direction"], Ethogram.FORAGE)
	if context.get("is_courting", false):
		stimuli.append({"position": context["partner_position"], "features": {Ethogram.MATE: 1.0}})
	for smell in context.get("smells", []):
		stimuli.append(smell)
	return stimuli


func _append_direction(stimuli: Array, position: Vector2, direction: Vector2, channel: String) -> void:
	if direction == Vector2.ZERO:
		return
	stimuli.append({
		"position": position + direction.normalized() * DIRECTION_STIMULUS_DISTANCE,
		"features": {channel: 1.0},
	})


## An aggressive creature that's still strong enough stands and fights;
## everything else (calm, or weakened) flees.
##
## An IMMATURE creature never fights, regardless of temperament or health --
## a real juvenile of even an aggressive-tempered species (boar, bear, lion)
## flees rather than stands its ground. "is_mature" is supplied by
## CreatureMarker every frame (see MammalGrowth.is_mature), the same way
## "is_courting"/"partner_position" were added to this context earlier.
## `.get(..., true)` defaults a context that doesn't set the key at all to
## mature -- every pre-existing caller/test that predates this key keeps
## exercising exactly today's behaviour.
func _will_fight(context: Dictionary) -> bool:
	if not context.get("is_mature", true):
		return false
	return context["temperament"] == "aggressive" and context["health_fraction"] >= STRONG_HEALTH_FRACTION


## Whether this creature reacts to `threats` at all this tick (docs/concept/
## worldbosses.md: "bosses should not attack low-level players on their
## own, even if they attack -- only if they deal actual damage do they pull
## aggro"). An ordinary creature always perceives threats, unchanged. A
## world boss perceives NONE of them -- doesn't attack, and doesn't flee
## either, which a bare "skip only the attack branch" gate would have
## accidentally produced by falling through to the flee case -- until
## BossAggro/CreatureMarker.take_damage has flipped is_aggroed on via a
## real hit. `.get(..., false)` defaults both new keys to "ordinary
## creature" so a context dict built before this feature existed (as every
## test predating it does) keeps behaving exactly as it always did.
func _perceives_threats(context: Dictionary) -> bool:
	if not context.get("is_world_boss", false):
		return true
	return context.get("is_aggroed", false)
