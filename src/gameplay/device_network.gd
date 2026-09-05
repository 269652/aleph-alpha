extends RefCounted

## The series-loop solver of docs/concept/standard_model.md ("5. Resolution
## order"): one Thevenin source driving a chain of transformers, gyrators,
## resistors and stores, solved in CLOSED FORM. Pure static functions, no
## engine, no scene tree, no iteration, no relaxation -- same text, same
## inputs, same answer, in the same order.
##
## ## How it solves
##
## 1. REDUCE. Walk the chain from its far end back to the source, folding
##    everything downstream of each point into one affine load `e = R f +
##    e0` by DeviceElements' two reflection rules (R/r^2 through a
##    transformer, k^2/R with a flipped offset through a gyrator) and series
##    composition for one-ports. A chain ending in a two-port has an OPEN
##    output (R = INF); one ending in a one-port closes the loop.
## 2. SOLVE the one unknown: f = (e0_source - e0_load) / (R_source + R_load).
##    Infinite resistance is zero flow (an open circuit doing nothing, as
##    electromagnetism.md's pillar 4 says it should). A NEGATIVE flow is
##    legal and reported, not clamped: it is a charged store driving the loop
##    the other way round -- the battery that motors the mill when the river
##    stops, which no rule wrote.
## 3. PROPAGATE forward from the source, recording every element's port
##    efforts and flows and its power in, power out, dissipated and stored.
## 4. STEP every store by the power flowing into it times dt, clamped to
##    [0, capacity], the clipped surplus reported as overflow (a full battery
##    overcharged sheds it as heat, as a real one does).
##
## ## Conservation is asserted, not assumed
##
## Across a closed loop the source's terminal power equals dissipated plus
## stored power to the watt, and the efforts around the loop sum to zero
## (test_source_power_equals_dissipated_plus_stored_power,
## test_efforts_around_a_closed_loop_sum_to_zero). The maximum power transfer
## theorem -- delivered power rising then falling with load, peaking at the
## matched load -- emerges from these rules rather than being written in, and
## test_there_is_an_optimum_load_for_delivered_power is the anchor that says
## so, the twin of part_mechanics.gd's optimum-head-mass test.
##
## ## What this slice does not solve, and refuses rather than mis-solves
##
## - One source per loop. A second is refused by name.
## - Series only. Parallel junctions (a battery ACROSS a bulb) are the
##   concept doc's designed-but-unbuilt `fork`; nothing here pretends.
## - An ideal effort (a store with no internal resistance) behind a gyrator
##   would pin the shaft's speed -- a flow constraint the affine form cannot
##   express. Refused, naming the store, with the physical reason.
## - Thermal is a pseudo-bond (its effort x flow is not a power); the
##   compiler keeps it out of loops, so nothing here accounts for it.

const DeviceElements: GDScript = preload("res://src/gameplay/device_elements.gd")


## Structure in, solved state out. Always returns every key, whether or not
## it solved, so a caller reads the result rather than branching on `ok` to
## find out which fields exist.
static func solve(chain: Array, dt: float = 0.0) -> Dictionary:
	var result := _empty_result()
	var refusal := _why_it_will_not_solve(chain)
	if not refusal.is_empty():
		result["errors"] = refusal
		return result

	var order: Array[String] = []
	for element in chain:
		order.append(String(element["id"]))
	result["order"] = order

	# -- 1. reduce -----------------------------------------------------------
	var last: Dictionary = chain[chain.size() - 1]
	var load: Dictionary = DeviceElements.open_load() \
		if DeviceElements.is_two_port(String(last["kind"])) else DeviceElements.closed_load()
	var last_one_port_id := ""
	for i in range(chain.size() - 1, 0, -1):
		var element: Dictionary = chain[i]
		var params: Dictionary = element["params"]
		match String(element["kind"]):
			DeviceElements.KIND_RESIST:
				load = DeviceElements.in_series(load, float(params["resistance"]), 0.0)
				last_one_port_id = String(element["id"])
			DeviceElements.KIND_STORE:
				load = DeviceElements.in_series(
					load, float(params.get("resistance", 0.0)), _store_effort(params)
				)
				last_one_port_id = String(element["id"])
			DeviceElements.KIND_TRANSFORM:
				load = DeviceElements.reflect_through_transform(load, float(params["ratio"]))
			DeviceElements.KIND_GYRATE:
				if float(load["resistance"]) <= 0.0 and float(load["effort"]) != 0.0:
					result["errors"] = _errors([
						"'%s' sits behind gyrator '%s' with no internal resistance:"
						% [last_one_port_id, element["id"]]
						+ " an ideal effort behind a gyrator would pin the shaft's speed,"
						+ " a constraint this slice cannot express -- give it a resistance",
					])
					return result
				load = DeviceElements.reflect_through_gyrate(load, float(params["ratio"]))

	# -- 2. solve ---------------------------------------------------------------
	var source: Dictionary = chain[0]
	var source_effort_0 := float(source["params"]["effort"])
	var source_resistance := float(source["params"]["resistance"])
	var total_resistance: float = source_resistance + float(load["resistance"])
	var net_effort: float = source_effort_0 - float(load["effort"])
	var flow := 0.0
	if total_resistance == INF:
		flow = 0.0
	elif total_resistance <= 0.0:
		if net_effort != 0.0:
			result["errors"] = _errors([
				"source '%s' has no internal resistance and drives a short:" % source["id"]
				+ " an ideal source into no resistance has no finite flow",
			])
			return result
		flow = 0.0
	else:
		flow = net_effort / total_resistance

	# -- 3. propagate -------------------------------------------------------------
	var elements := {}
	var stores := {}
	var terminal_effort: float = DeviceElements.source_terminal_effort(
		source_effort_0, source_resistance, flow
	)
	var source_power: float = DeviceElements.power(terminal_effort, flow)
	elements[String(source["id"])] = _record(
		DeviceElements.KIND_SOURCE, terminal_effort, flow, 0.0, source_power, 0.0, 0.0
	)
	result["source_internal_loss"] = DeviceElements.dissipated(source_resistance, flow)

	var effort := terminal_effort
	var dissipated_power := 0.0
	var stored_power := 0.0
	for i in range(1, chain.size()):
		var element: Dictionary = chain[i]
		var id := String(element["id"])
		var kind := String(element["kind"])
		var params: Dictionary = element["params"]
		match kind:
			DeviceElements.KIND_RESIST:
				var resistance := float(params["resistance"])
				var drop: float = DeviceElements.resist_effort(resistance, flow)
				var heat: float = DeviceElements.dissipated(resistance, flow)
				elements[id] = _record(kind, drop, flow, DeviceElements.power(drop, flow), 0.0, heat, 0.0)
				dissipated_power += heat
				effort -= drop
			DeviceElements.KIND_STORE:
				var internal := float(params.get("resistance", 0.0))
				var store_effort := _store_effort(params)
				var drop: float = DeviceElements.resist_effort(internal, flow) + store_effort
				var heat: float = DeviceElements.dissipated(internal, flow)
				var stored_rate: float = DeviceElements.power(store_effort, flow)
				elements[id] = _record(kind, drop, flow, DeviceElements.power(drop, flow), 0.0, heat, stored_rate)
				stores[id] = _step_store(params, store_effort, stored_rate, dt)
				dissipated_power += heat
				stored_power += stored_rate
				effort -= drop
			DeviceElements.KIND_TRANSFORM, DeviceElements.KIND_GYRATE:
				var ratio := float(params["ratio"])
				var out: Dictionary = DeviceElements.transform_out(effort, flow, ratio) \
					if kind == DeviceElements.KIND_TRANSFORM \
					else DeviceElements.gyrate_out(effort, flow, ratio)
				var power_in: float = DeviceElements.power(effort, flow)
				var power_out: float = DeviceElements.power(out["effort"], out["flow"])
				var record := _record(kind, effort, flow, power_in, power_out, 0.0, 0.0)
				record["effort_out"] = out["effort"]
				record["flow_out"] = out["flow"]
				elements[id] = record
				effort = out["effort"]
				flow = out["flow"]

	result["ok"] = true
	result["elements"] = elements
	result["stores"] = stores
	result["source_flow"] = float(elements[String(source["id"])]["flow"])
	result["source_effort"] = terminal_effort
	result["source_power"] = source_power
	result["dissipated_power"] = dissipated_power
	result["stored_power"] = stored_power
	# Zero around a closed loop; the open-circuit effort at an open end.
	result["residual_effort"] = effort
	return result


# -- refusals ------------------------------------------------------------------

static func _why_it_will_not_solve(chain: Array) -> Array[String]:
	if chain.is_empty():
		return _errors(["there is no loop to solve"])
	var seen := {}
	for i in range(chain.size()):
		var element: Dictionary = chain[i]
		var id := String(element.get("id", ""))
		var kind := String(element.get("kind", ""))
		if id == "":
			return _errors(["element %d has no id" % i])
		if seen.has(id):
			return _errors(["duplicate element id '%s'" % id])
		seen[id] = true
		if i == 0 and kind != DeviceElements.KIND_SOURCE:
			return _errors(["a loop needs a source first, got %s '%s'" % [kind, id]])
		if i > 0 and kind == DeviceElements.KIND_SOURCE:
			return _errors([
				"this slice solves one source per loop; '%s' is a second" % id,
			])
		var reason: String = DeviceElements.validation_error(kind, element.get("params", {}))
		if reason != "":
			return _errors(["element '%s': %s" % [id, reason]])
	return _errors([])


# -- internals -------------------------------------------------------------------

static func _store_effort(params: Dictionary) -> float:
	return DeviceElements.store_effort(
		float(params["capacity"]), float(params["full_effort"]), float(params.get("level", 0.0))
	)


## The tank step: level += stored_rate * dt, clamped to [0, capacity]. The
## surplus a full store cannot take is reported, not lost silently; a store
## that hits empty says so.
static func _step_store(params: Dictionary, store_effort: float, stored_rate: float, dt: float) -> Dictionary:
	var capacity := float(params["capacity"])
	var level := float(params.get("level", 0.0)) + stored_rate * dt
	var overflow := 0.0
	var depleted := false
	if level > capacity:
		overflow = level - capacity
		level = capacity
	if level < 0.0:
		depleted = true
		level = 0.0
	return {
		"level": level, "capacity": capacity, "effort": store_effort,
		"overflow_j": overflow, "depleted": depleted,
	}


static func _record(
	kind: String, effort: float, flow: float, power_in: float, power_out: float,
	dissipated: float, stored_rate: float
) -> Dictionary:
	return {
		"kind": kind,
		"effort": effort,
		"flow": flow,
		"power": power_in if kind != DeviceElements.KIND_SOURCE else power_out,
		"power_in": power_in,
		"power_out": power_out,
		"dissipated": dissipated,
		"stored_rate": stored_rate,
	}


static func _empty_result() -> Dictionary:
	return {
		"ok": false,
		"errors": [] as Array[String],
		"order": [] as Array[String],
		"elements": {},
		"stores": {},
		"source_flow": 0.0,
		"source_effort": 0.0,
		"source_power": 0.0,
		"source_internal_loss": 0.0,
		"dissipated_power": 0.0,
		"stored_power": 0.0,
		"residual_effort": 0.0,
	}


static func _errors(messages: Array) -> Array[String]:
	var typed: Array[String] = []
	for message in messages:
		typed.append(str(message))
	return typed
