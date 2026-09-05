extends RefCounted

## The five element laws of docs/concept/standard_model.md ("The formal
## model / 3. The element algebra"), as pure static functions, plus the two
## affine-load reflection rules the series solver (device_network.gd) is built
## from. No engine, no scene tree, no state.
##
## ## Why exactly these five
##
## They are bond-graph theory's own one- and two-port elements, minus inertia
## (deferred -- see the concept doc's Status list): a source (Se, made real
## with a Thevenin internal resistance), a resistor (R), a transformer (TF),
## a gyrator (GY) and a capacitor (C, the store). A lever, a gear pair, a
## wheel's radius, a piston and a pump are all TRANSFORM; a generator and a
## motor are both GYRATE; a battery, a reservoir and a drawn bow are all
## STORE. Nothing else has to be invented for any device this project has
## named, which is the entire argument for borrowing the formalism rather than
## writing one system per machine.
##
## ## Conservation is structural
##
## transform_out and gyrate_out preserve effort x flow EXACTLY (asserted as a
## property over a sweep by test_device_elements.gd). A device built from them
## cannot make energy because the algebra cannot express one that does -- this
## is synthesis.md's "physical conservation" balance pillar made literal.
##
## ## The affine-load reduction
##
## Everything downstream of any point in a series chain looks, from that
## point, like `e = R f + e0` -- a resistance in series with an opposing
## effort (a charging battery is the canonical one). reflect_through_transform
## and reflect_through_gyrate move such a load one element upstream; in_series
## folds a one-port into it. Applied from the far end of a chain back to its
## source, they ARE the solver. The gyrator rule is worth reading twice: it
## turns a resistance into a conductance (a heavy mechanical load is a small
## electrical resistance, which is why a stalled motor draws its maximum
## current) and flips the sign of an opposing effort (a charged battery behind
## a generator is, from the shaft, something trying to turn it -- a motor).

const KIND_SOURCE := "source"
const KIND_RESIST := "resist"
const KIND_TRANSFORM := "transform"
const KIND_GYRATE := "gyrate"
const KIND_STORE := "store"

## Fixed order, kept explicitly.
const KINDS: Array[String] = [
	KIND_SOURCE, KIND_RESIST, KIND_TRANSFORM, KIND_GYRATE, KIND_STORE,
]

## kind -> {ports, required}. `required` are the CANONICAL parameters the
## laws below consume; the derivations that produce them from a part or a
## fluid (device_physics.gd) resolve into these before validation, so an
## element is validated on what it will actually be solved with.
const _SPECS := {
	KIND_SOURCE: {"ports": 1, "required": ["effort", "resistance"]},
	KIND_RESIST: {"ports": 1, "required": ["resistance"]},
	KIND_TRANSFORM: {"ports": 2, "required": ["ratio"]},
	KIND_GYRATE: {"ports": 2, "required": ["ratio"]},
	KIND_STORE: {"ports": 1, "required": ["capacity", "full_effort"]},
}


# -- kinds -----------------------------------------------------------------

static func is_known(kind: String) -> bool:
	return _SPECS.has(kind)


static func is_two_port(kind: String) -> bool:
	return int(_SPECS.get(kind, {}).get("ports", 1)) == 2


static func required_params(kind: String) -> Array:
	return Array(_SPECS.get(kind, {}).get("required", [])).duplicate()


# -- power -----------------------------------------------------------------

static func power(effort: float, flow: float) -> float:
	return effort * flow


# -- transform: e2 = r e1, f2 = f1 / r ---------------------------------------

## A lever, a gear pair, a pulley, a wheel's radius, a piston, a pump. Effort
## is multiplied by the ratio and flow divided by it, so power passes through
## untouched. A ratio of 1 is a rigid coupling -- a shaft -- which is why a
## shaft needs no element of its own.
static func transform_out(effort_in: float, flow_in: float, ratio: float) -> Dictionary:
	return {"effort": ratio * effort_in, "flow": flow_in / ratio}


# -- gyrate: e2 = k f1, f2 = e1 / k -------------------------------------------

## A generator or a motor -- anything Faraday. The output effort is the input
## FLOW scaled (EMF = k * omega), and the output flow is the input EFFORT
## scaled (I = tau / k); the same k in both directions is why the two machines
## are one machine. Power passes through untouched.
static func gyrate_out(effort_in: float, flow_in: float, ratio: float) -> Dictionary:
	return {"effort": ratio * flow_in, "flow": effort_in / ratio}


# -- resist: e = R f -----------------------------------------------------------

static func resist_effort(resistance: float, flow: float) -> float:
	return resistance * flow


## What a resistor turns into heat: R f^2, never negative -- a backwards flow
## still warms the wire.
static func dissipated(resistance: float, flow: float) -> float:
	return resistance * flow * flow


# -- source: a Thevenin pair ----------------------------------------------------

## The effort actually available at a real source's terminals sags with the
## flow it delivers: e = e0 - R f. A paddle in a stream, a generator under
## load and a person on a crank all do this.
static func source_terminal_effort(effort: float, resistance: float, flow: float) -> float:
	return effort - resistance * flow


## The flow at which a source's terminal effort reaches zero -- the paddle
## moving as fast as the water. INF for an ideal source with no internal
## resistance, which is what "no ceiling" honestly means.
static func source_free_flow(effort: float, resistance: float) -> float:
	if resistance <= 0.0:
		return INF
	return effort / resistance


## The most power a source can ever deliver, e0^2 / (4 R) -- reached only
## when the load matches the internal resistance (the maximum power transfer
## theorem, which device_network.gd's anchor test asserts emerges from the
## solver rather than being written into it). INF for an ideal source.
static func source_max_power(effort: float, resistance: float) -> float:
	if resistance <= 0.0:
		return INF
	return effort * effort / (4.0 * resistance)


# -- store: a linear capacitor ----------------------------------------------------

## A store's effort rises linearly with what it holds: a battery's voltage as
## it charges, a reservoir's pressure as it fills, a bow's draw force as it is
## drawn. Empty is zero, full is `full_effort`. A store with no capacity has
## no effort rather than a division by zero.
static func store_effort(capacity: float, full_effort: float, level: float) -> float:
	if capacity <= 0.0:
		return 0.0
	return full_effort * level / capacity


# -- affine loads and the reflection rules ------------------------------------

## `e = resistance * f + effort`, as seen looking downstream from a point in
## a chain.
static func affine_load(resistance: float, effort: float) -> Dictionary:
	return {"resistance": resistance, "effort": effort}


## Nothing downstream at all: the loop closes straight back to the source.
static func closed_load() -> Dictionary:
	return affine_load(0.0, 0.0)


## An open end -- a two-port with nothing on its output. Infinite resistance:
## nothing can flow.
static func open_load() -> Dictionary:
	return affine_load(INF, 0.0)


## A one-port in series with what is already downstream: resistances add,
## opposing efforts add. Onto an open end it stays open (INF + anything).
static func in_series(load: Dictionary, resistance: float, opposing_effort: float) -> Dictionary:
	return affine_load(
		float(load["resistance"]) + resistance, float(load["effort"]) + opposing_effort
	)


## What a downstream load looks like from the input side of a transformer:
## R' = R / r^2, e0' = e0 / r. A load behind a ratio-2 lever feels a quarter
## as stiff. An open end stays open.
static func reflect_through_transform(load: Dictionary, ratio: float) -> Dictionary:
	var resistance := float(load["resistance"])
	if resistance == INF:
		return open_load()
	return affine_load(resistance / (ratio * ratio), float(load["effort"]) / ratio)


## What a downstream load looks like from the input side of a gyrator:
## R' = k^2 / R, e0' = -k e0 / R. A resistance becomes a conductance and an
## opposing effort flips sign (see this file's header). An open end becomes a
## SHORT: an unloaded generator spins freely and pushes back with no torque.
static func reflect_through_gyrate(load: Dictionary, ratio: float) -> Dictionary:
	var resistance := float(load["resistance"])
	if resistance == INF:
		return closed_load()
	if resistance <= 0.0:
		# A short on the far side is an open on the near side -- and the
		# offset has nothing to divide by, so it is gone too.
		return open_load()
	return affine_load(
		ratio * ratio / resistance, -ratio * float(load["effort"]) / resistance
	)


# -- validation ------------------------------------------------------------------

## "" when `params` carry everything `kind`'s law consumes, otherwise a
## message naming the missing or impossible value. Nothing is defaulted: a
## defaulted resistance is a confident, wrong current, the same class of bug
## ItemPart refuses to commit for a defaulted dimension.
static func validation_error(kind: String, params: Dictionary) -> String:
	if not _SPECS.has(kind):
		return "unknown element kind '%s'" % kind
	for name in required_params(kind):
		if not params.has(name):
			return "%s needs '%s'" % [kind, name]
	match kind:
		KIND_TRANSFORM, KIND_GYRATE:
			if float(params["ratio"]) <= 0.0:
				return "%s needs a positive ratio, got %s" % [kind, params["ratio"]]
		KIND_RESIST:
			if float(params["resistance"]) < 0.0:
				return "resist needs a non-negative resistance, got %s" % params["resistance"]
		KIND_SOURCE:
			if float(params["resistance"]) < 0.0:
				return "source needs a non-negative internal resistance, got %s" % params["resistance"]
		KIND_STORE:
			var capacity := float(params["capacity"])
			if capacity <= 0.0:
				return "store needs a positive capacity, got %s" % params["capacity"]
			var level := float(params.get("level", 0.0))
			if level < 0.0 or level > capacity:
				return "store level %s is outside its capacity %s" % [level, capacity]
			if float(params.get("resistance", 0.0)) < 0.0:
				return "store needs a non-negative internal resistance, got %s" % params["resistance"]
	return ""
