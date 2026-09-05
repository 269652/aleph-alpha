extends RefCounted

## The behaviour kernel (docs/concept/ethogram.md §6): an ordered list of
## wirings, an individual's expressed receptors, this tick's drive levels and
## this tick's stimuli in; one intent and a heading out.
##
## A wiring is one line of a species' ethogram:
##
##   {"gate": "hunger", "channels": ["flesh"], "approach": "hunt"}
##   {"gate": "thirst", "channels": ["water"], "approach": "seek_water", "search": "search_water"}
##   {"gate": "fear",   "channels": ["predator", "player"], "approach": "attack", "avoid": "flee"}
##
##   gate      the drive whose level scales this wiring; level zero skips it,
##             a drive missing from the table counts as fully open
##   channels  the subset of the basis this wiring listens on
##   approach  the intent when the best stimulus DRAWS (pull > 0), heading
##             toward it
##   avoid     (optional) the intent when it REPELS (pull < 0), heading away.
##             A wiring WITHOUT one listens only for what draws it: a deer
##             that smells a carcass neither bolts from it nor lets it
##             distract it from the ripe apple beyond
##   search    (optional) the intent when the gate is open but nothing on
##             these channels is sensed at all, with a zero direction for the
##             caller to fill in -- CreatureBehavior's search_food contract
##   floor     (optional) the score a stimulus must exceed to fire this
##             wiring at all -- ScentForaging's "not interested enough to
##             cross a field", as a property of the wiring
##
## Wirings are walked top to bottom and the first that fires wins, the same
## first-match discipline the NPC instruction evaluator uses; in slice 1
## order is priority. Within a wiring every stimulus is scored
##
##   pull  = sum over channels of features * sensitivity * valence
##   score = |pull| * level * weight
##
## where `weight` is the stimulus's own `strength` when the SENSE that
## reported it knows how loud it is at this range (smell, with its dilution
## law), and otherwise Affinity.proximity(distance), a unit-free ranking so
## that between two equal stimuli the nearer one wins -- which is exactly
## the old `_nearest`. The SIGN of the winning pull picks approach or avoid.
## The kernel never drops a stimulus a sense chose to report: range is
## Olfaction.dilution's or SENSE_RADIUS's business, and a strength of zero
## is how a sense says "out of range".
##
## A stimulus is {"position": Vector2, "features": {channel: float}} plus
## whatever the caller wants back: the winning stimulus is returned whole, so
## a marker that tagged it with a node reference gets the node. Olfaction's
## own {"position", "mixture"} shape is accepted as-is.
##
## Stateless on purpose (ethogram.md pillar 4): it ranks, the caller commits.
## Flee hysteresis, grazing approach commitment and every other ramp stay in
## the markers and motor programs that own them. Pure, static, no RNG.

const Affinity = preload("res://src/gameplay/affinity.gd")

## The answer when no wiring fires: nothing pressing, roam.
const WANDER := "wander"


## `receptors` is {"sensitivity": {channel: float}, "valence": {channel: float}}
## (Ethogram.express's shape). `drives` is {drive_name: level}. Returns
## {"intent": String, "direction": Vector2, "score": float, "target": Vector2
## or null, "stimulus": the winning stimulus Dictionary or null}. `direction`
## is zero for a search or a wander, for the caller to fill in with its own
## roaming heading.
static func decide(
	wirings: Array, receptors: Dictionary, drives: Dictionary, position: Vector2, stimuli: Array
) -> Dictionary:
	for wiring in wirings:
		var gate := String(wiring.get("gate", ""))
		var level := 1.0 if gate == "" else float(drives.get(gate, 1.0))
		if level <= 0.0:
			continue
		var avoid := String(wiring.get("avoid", ""))
		var best := best_stimulus(
			receptors, wiring.get("channels", []), position, stimuli, level,
			float(wiring.get("floor", 0.0)), avoid == ""
		)
		if not best.is_empty():
			var stimulus: Dictionary = best["stimulus"]
			var at: Vector2 = stimulus["position"]
			if best["pull"] > 0.0:
				return _decision(
					String(wiring["approach"]), Affinity.toward(position, at), best["score"], stimulus
				)
			return _decision(avoid, Affinity.away_from(position, at), best["score"], stimulus)
		var search := String(wiring.get("search", ""))
		if search != "":
			return _decision(search, Vector2.ZERO, 0.0, {})
	return _decision(WANDER, Vector2.ZERO, 0.0, {})


## The ranking on its own: the stimulus with the highest score on `channels`,
## as {"stimulus", "pull", "score"}, or empty when nothing scores above
## `floor`. `attract_only` drops repellent stimuli from the running, which
## is what a wiring without an avoid program wants and what a motor program
## choosing something to walk TO wants (ScentForaging.best_source).
static func best_stimulus(
	receptors: Dictionary, channels: Array, position: Vector2, stimuli: Array,
	level: float = 1.0, floor: float = 0.0, attract_only: bool = false
) -> Dictionary:
	var sensitivity: Dictionary = receptors.get("sensitivity", {})
	var valence: Dictionary = receptors.get("valence", {})
	var best := {}
	var best_score := maxf(floor, 0.0)
	for stimulus in stimuli:
		var pull := Affinity.pull(_features_of(stimulus), sensitivity, valence, channels)
		if pull == 0.0 or (attract_only and pull < 0.0):
			continue
		var score := absf(pull) * level * _weight(stimulus, position)
		if score > best_score:
			best_score = score
			best = {"stimulus": stimulus, "pull": pull, "score": score}
	return best


## Every stimulus this animal NOTICES on `channels` -- nonzero pull, whatever
## its sign. A marker asks this for "is anything dangerous around", which
## matters whether it would fight or flee: it lifts its head from grazing
## either way, and it keeps the wider flee-release radius either way.
static func perceived(receptors: Dictionary, channels: Array, stimuli: Array) -> Array:
	var sensitivity: Dictionary = receptors.get("sensitivity", {})
	var valence: Dictionary = receptors.get("valence", {})
	var noticed: Array = []
	for stimulus in stimuli:
		if Affinity.pull(_features_of(stimulus), sensitivity, valence, channels) != 0.0:
			noticed.append(stimulus)
	return noticed


static func _weight(stimulus: Dictionary, position: Vector2) -> float:
	if stimulus.has("strength"):
		return maxf(float(stimulus["strength"]), 0.0)
	return Affinity.proximity(position.distance_to(stimulus["position"]))


static func _features_of(stimulus: Dictionary) -> Dictionary:
	return stimulus.get("features", stimulus.get("mixture", {}))


static func _decision(intent: String, direction: Vector2, score: float, stimulus: Dictionary) -> Dictionary:
	return {
		"intent": intent,
		"direction": direction,
		"score": score,
		"target": null if stimulus.is_empty() else stimulus["position"],
		"stimulus": null if stimulus.is_empty() else stimulus,
	}
