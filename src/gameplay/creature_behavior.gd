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
## Context keys:
##   position, temperament, is_predator, health_fraction, hungry, thirsty,
##   is_courting; is_mature (defaults to true), is_world_boss / is_aggroed
##   (default to false) and fears_players (defaults to true) so contexts
##   built before those keys existed keep behaving exactly as they did
##   species  (optional) the ethogram record to express; a species with no
##            record runs the ladder on the body plan's defaults
##   genome   (optional) this individual's receptor genes (Ethogram.express)
##   stimuli  (optional) what the caller senses, already on the shared basis:
##            {"position", "features", ...anything else it wants back}. This
##            is what CreatureMarker publishes (ethogram.md slice 2): every
##            nearby creature as {predator: 1} or {flesh: 1} by what IT is,
##            every player as {player: 1}, the nearest water/food tile, the
##            courtship partner. The verdict is the valence, below.
##   threats, prey, food_direction, water_direction, partner_position, smells
##            the older shape -- position lists and headings -- read ONLY
##            when `stimuli` is absent, and turned into stimuli here. Kept
##            for callers and tests that still speak it.
##
## "seek_*" heads toward a sensed resource; "search_*" means the need exists
## but nothing's in range, so the creature should roam to look (the caller
## supplies the roaming heading, same as it does for "wander"). The decision
## also names its `target`, `score` and winning `stimulus` (see
## BehaviorKernel.decide), which is how the marker gets its prey or attack
## target back as the node it tagged the stimulus with.

const Ethogram = preload("res://src/gameplay/ethogram.gd")
const BehaviorKernel = preload("res://src/gameplay/behavior_kernel.gd")
const ScentForaging = preload("res://src/gameplay/scent_foraging.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

## The body plan every CreatureMarker species runs on.
const BODY_PLAN := "mammal"

## A creature only stands and fights a threat if it's at least this healthy;
## below it, even an aggressive creature flees ("weak monsters should flee").
const STRONG_HEALTH_FRACTION := 0.5

## A sensed DIRECTION (food, water; the older context shape) becomes a
## stimulus one tile ahead. Any positive distance hands the same normalised
## heading back; one tile keeps it in scale with the positions the kernel
## ranks it against.
const DIRECTION_STIMULUS_DISTANCE := float(TerrainRenderer.TILE_SIZE)

## The wirings and the individual's base expression are cached on this
## instance: decide() runs every frame for every creature, and
## Ethogram.express/wirings_for hand back fresh copies by contract.
var _wirings: Array = []
var _expressed := {}
var _expressed_species := ""
var _expressed_genome := {}
var _drives := {}


func decide(context: Dictionary) -> Dictionary:
	_ensure_wirings()
	return BehaviorKernel.decide(
		_wirings, _receptors(context), _drives_for(context), context["position"], _stimuli(context)
	)


## Populates the cached wirings on whichever of decide()/threats() is called
## FIRST for this instance. Both call _receptors(), whose genome-change
## detection (below) patches the fear wiring's boldness floor (ethogram.md
## §9) into _wirings -- so _wirings must already exist before _receptors
## ever runs, or the floor patches an empty array and the (now genome-
## marked-seen) cache never gets another chance to apply it. CreatureMarker
## calls threats() once per sensing tick, before it ever calls decide() for
## a fresh instance, which is exactly the ordering that exposed this.
func _ensure_wirings() -> void:
	if _wirings.is_empty():
		_wirings = Ethogram.wirings_for(BODY_PLAN)


## Patches the cached fear wiring's floor for this individual's boldness gene
## (docs/concept/ethogram.md §9). `_wirings` is this instance's own private
## copy (Ethogram.wirings_for hands back a deep copy per adapter, and each
## CreatureMarker owns one adapter), so mutating it in place touches nobody
## else. Runs alongside _receptors' own genome-change detection, below,
## which already knows when this individual's genome has actually changed.
func _apply_boldness_floor(genome: Dictionary) -> void:
	var gene := float(genome.get(Ethogram.BOLDNESS, Ethogram.NEUTRAL_BOLDNESS_GENE))
	var floor_value := Ethogram.fear_floor(gene)
	for wiring in _wirings:
		if wiring["gate"] == Ethogram.DRIVE_FEAR:
			wiring["floor"] = floor_value


## Everything this individual NOTICES on the fear channels, whether it would
## fight or flee it -- a predator for a herbivore, a person for anything
## that still fears people. CreatureMarker keeps the result as its threat
## list: an animal lifts its head from grazing for a wolf it would fight
## just as for one it would flee, and keeps the wider flee-release radius
## either way. This is the verdict that used to live in the marker's own
## scan ("predators are threats to herbivores; players to everyone").
func threats(context: Dictionary) -> Array:
	_ensure_wirings()
	return BehaviorKernel.perceived(
		_receptors(context), [Ethogram.PREDATOR, Ethogram.PLAYER], _stimuli(context)
	)


## This individual's expressed receptors, with the overrides that are species
## and state facts reaching decide() only as context flags today (ethogram.md
## §3): who stands and fights, who eats prey, who is not threatened by other
## creatures. Applied IN PLACE on the cached base expression -- every
## affected channel is rewritten on every call, so nothing stale survives.
##
## An un-aggroed world boss gets zero danger SENSITIVITY -- it genuinely does
## not perceive the player as a threat, so it neither attacks nor flees and
## still drinks and eats -- rather than zero valence. So does a tamed animal
## for people (fears_players false): it is not that it tolerates them, it is
## that they are not a thing it reacts to at all any more.
func _receptors(context: Dictionary) -> Dictionary:
	var species := String(context.get("species", ""))
	var genome: Dictionary = context.get("genome", {})
	if _expressed.is_empty() or species != _expressed_species or genome != _expressed_genome:
		_expressed = Ethogram.express(species, genome, BODY_PLAN)
		_expressed_species = species
		_expressed_genome = genome.duplicate()
		_apply_boldness_floor(genome)
	var sensitivity: Dictionary = _expressed["sensitivity"]
	var valence: Dictionary = _expressed["valence"]
	var perceives := _perceives_threats(context)
	var is_predator: bool = context["is_predator"]
	var fight := _will_fight(context)
	sensitivity[Ethogram.PREDATOR] = 1.0 if perceives else 0.0
	sensitivity[Ethogram.PLAYER] = 1.0 if perceives and context.get("fears_players", true) else 0.0
	valence[Ethogram.PLAYER] = 1.0 if fight else -1.0
	if is_predator:
		valence[Ethogram.PREDATOR] = 0.0  # not threatened by other creatures, only by people
	else:
		valence[Ethogram.PREDATOR] = 1.0 if fight else -1.0
	valence[Ethogram.FLESH] = 1.0 if is_predator else 0.0
	return _expressed


## Drive levels as gains. A caller that publishes `drives` (CreatureNeeds.
## gains, the one drive clock -- ethogram.md §5) is taken at its word, and a
## partial gain still opens its gate; the `hungry`/`thirsty` booleans are the
## older shape, read only when `drives` is absent. Fear is always open (the
## world-boss case is sensitivity, above).
func _drives_for(context: Dictionary) -> Dictionary:
	_drives[Ethogram.DRIVE_FEAR] = 1.0
	if context.has("drives"):
		var published: Dictionary = context["drives"]
		_drives[Ethogram.DRIVE_THIRST] = float(published.get(Ethogram.DRIVE_THIRST, 0.0))
		_drives[Ethogram.DRIVE_HUNGER] = float(published.get(Ethogram.DRIVE_HUNGER, 0.0))
	else:
		_drives[Ethogram.DRIVE_THIRST] = 1.0 if context.get("thirsty", false) else 0.0
		_drives[Ethogram.DRIVE_HUNGER] = 1.0 if context.get("hungry", false) else 0.0
	_drives[Ethogram.DRIVE_COURTSHIP] = 1.0 if context.get("is_courting", false) else 0.0
	return _drives


## What the caller senses, on the shared basis. A caller that publishes
## `stimuli` is taken at its word; otherwise the older position lists and
## headings are turned into stimuli here. A legacy "threat" is handed over
## as a person: the one feature every species answers, and what the old
## scan's threat list was made of for a predator.
func _stimuli(context: Dictionary) -> Array:
	if context.has("stimuli"):
		return context["stimuli"]
	var position: Vector2 = context["position"]
	var stimuli: Array = []
	for at in context.get("threats", []):
		stimuli.append({"position": at, "features": {Ethogram.PLAYER: 1.0}})
	for at in context.get("prey", []):
		stimuli.append({"position": at, "features": {Ethogram.FLESH: 1.0}})
	_append_direction(stimuli, position, context.get("water_direction", Vector2.ZERO), Ethogram.WATER)
	_append_direction(stimuli, position, context.get("food_direction", Vector2.ZERO), Ethogram.FORAGE)
	if context.get("is_courting", false):
		stimuli.append({"position": context["partner_position"], "features": {Ethogram.MATE: 1.0}})
	# Smells go through the smell sense, which attaches how loud each one is
	# at this range: the smell wiring's floor is stated in those units.
	stimuli.append_array(ScentForaging.stimuli_from(position, context.get("smells", [])))
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


## Whether this creature reacts to threats at all this tick (docs/concept/
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
