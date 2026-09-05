extends RefCounted

## The behaviour kernel (docs/concept/ethogram.md §6): an ordered list of
## wirings, an individual's expressed receptors, this tick's drive levels and
## this tick's stimuli in; one intent and a heading out.
##
## A wiring is one line of a species' ethogram:
##
##   {"gate": "hunger", "channels": ["flesh"], "approach": "hunt"}
##   {"gate": "thirst", "channels": ["water"], "approach": "seek_water", "search": "search_water"}
##   {"gate": "fear",   "channels": ["danger"], "approach": "attack", "avoid": "flee"}
##
##   gate      the drive whose level scales this wiring; level zero skips it,
##             a drive missing from the table counts as fully open
##   channels  the subset of the basis this wiring listens on
##   approach  the intent when the best stimulus DRAWS (pull > 0), heading
##             toward it
##   avoid     (optional) the intent when it REPELS (pull < 0), heading away;
##             without one a repellent stimulus is ignored rather than fled --
##             a deer that smells a carcass walks on
##   search    (optional) the intent when the gate is open but nothing on
##             these channels is sensed at all, with a zero direction for the
##             caller to fill in -- CreatureBehavior's search_food contract
##
## Wirings are walked top to bottom and the first that fires wins, the same
## first-match discipline the NPC instruction evaluator uses; in slice 1
## order is priority. Within a wiring every stimulus is scored
##
##   pull  = sum over channels of features * sensitivity * valence
##   score = |pull| * level * Affinity.proximity(distance)
##
## and the highest score wins, so between two equal stimuli the nearer one
## does -- which is exactly the old `_nearest` -- and the SIGN of the winning
## pull picks approach or avoid. The kernel never drops a stimulus a sense
## chose to report: range is Olfaction.dilution's or SENSE_RADIUS's business.
##
## Stateless on purpose (ethogram.md pillar 4): it ranks, the caller commits.
## Flee hysteresis, grazing approach commitment and every other ramp stay in
## the markers and motor programs that own them. Pure, static, no RNG.

const Affinity = preload("res://src/gameplay/affinity.gd")

## The answer when no wiring fires: nothing pressing, roam.
const WANDER := "wander"


## `receptors` is {"sensitivity": {channel: float}, "valence": {channel: float}}
## (Ethogram.express's shape). `drives` is {drive_name: level}. Each stimulus
## is {"position": Vector2, "features": {channel: float}}; Olfaction's own
## {"position", "mixture"} shape is accepted as-is. Returns
## {"intent": String, "direction": Vector2, "score": float, "target": Vector2
## or null}. `direction` is zero for a search or a wander, for the caller to
## fill in with its own roaming heading.
static func decide(
	wirings: Array, receptors: Dictionary, drives: Dictionary, position: Vector2, stimuli: Array
) -> Dictionary:
	var sensitivity: Dictionary = receptors.get("sensitivity", {})
	var valence: Dictionary = receptors.get("valence", {})
	for wiring in wirings:
		var gate := String(wiring.get("gate", ""))
		var level := 1.0 if gate == "" else float(drives.get(gate, 1.0))
		if level <= 0.0:
			continue
		var channels: Array = wiring.get("channels", [])
		var best := {}
		var best_score := 0.0
		var best_pull := 0.0
		for stimulus in stimuli:
			var features: Dictionary = stimulus.get("features", stimulus.get("mixture", {}))
			var pull := Affinity.pull(features, sensitivity, valence, channels)
			if pull == 0.0:
				continue
			var at: Vector2 = stimulus["position"]
			var score := absf(pull) * level * Affinity.proximity(position.distance_to(at))
			if score > best_score:
				best_score = score
				best_pull = pull
				best = stimulus
		if not best.is_empty():
			var at: Vector2 = best["position"]
			if best_pull > 0.0:
				return _decision(String(wiring["approach"]), Affinity.toward(position, at), best_score, at)
			var avoid := String(wiring.get("avoid", ""))
			if avoid != "":
				return _decision(avoid, Affinity.away_from(position, at), best_score, at)
			continue  # repelled, with nothing to do about it: walk on
		var search := String(wiring.get("search", ""))
		if search != "":
			return _decision(search, Vector2.ZERO, 0.0, null)
	return _decision(WANDER, Vector2.ZERO, 0.0, null)


static func _decision(intent: String, direction: Vector2, score: float, target) -> Dictionary:
	return {"intent": intent, "direction": direction, "score": score, "target": target}
