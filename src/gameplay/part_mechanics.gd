extends RefCounted

## The swing: a PartGraph treated as the rotating rigid body it is. Pure
## functions, no engine, no scene tree. Design doc:
## docs/concept/emergent_crafting.md, whose Status list has carried
## "composite stats ... nothing yet computes that momentum FROM a part graph"
## as a ⬜ row since the graph landed. This is that row.
##
## ## Why this is rigid-body dynamics and not a stat table
##
## The temptation is `damage = head_mass * some_curve`. That is monotonic in
## mass, and a model monotonic in mass says a 20 kg hammer is the best hammer,
## which is the one thing everybody who has ever picked one up knows is false.
## Real swinging has an optimum because a swung implement is a body rotating
## about the grip: angular acceleration is torque / moment of inertia, mass far
## from the hand costs inertia as the SQUARE of its distance, and the torque a
## human has left over to accelerate the thing is what remains after holding it
## up against gravity. Past a certain mass the static hold eats the whole
## budget and the swing stops being a swing.
##
## Every number below is either a measurement, a piece of geometry, or the one
## free constant SOLVED FOR from a measured anchor. Nothing is shaped until it
## felt good. test_there_is_an_optimum_head_mass_for_delivered_momentum is the
## test that would catch a relapse: it asserts the curve turns over.
##
## ## What is deliberately NOT modelled (and what that costs)
##
## - **The actor's own limb inertia.** A real swing must also accelerate your
##   arm, so a weightless implement still cannot be swung infinitely fast.
##   Omitted because the graph's own inertia already prevents the light-end
##   blow-up (momentum goes to zero as head mass does, with or without it) and
##   adding an arm-inertia constant would be a second ungrounded number bought
##   for nothing. The rejected alternative was a published segment-inertia
##   figure for the upper limb (~0.4 kg m^2 about the shoulder), rejected
##   because the shoulder is not the pivot this model uses.
## - **Orientation.** PartGraph has none (it says so itself), so parts lie
##   end-to-end along their own spans and `path_length_cm` -- the shipped
##   notion of physical distance along a route -- is what measures them. A
##   crossguard therefore reads as 20 cm of reach it does not really have.
##   Reusing the shipped symbol is worth more than a private, differently-wrong
##   guess at which dimension points along the assembly; see the ⬜ "Part
##   orientation" row in emergent_crafting.md.
## - **Where the hand actually is.** The pivot is the grip part's CENTRE. True
##   enough for a sword, generous for an axe (you hold the end of the haft, not
##   the middle), so long-hafted tools come out with roughly half the lever they
##   really have. The calibration anchor below uses the same convention, so the
##   one free constant absorbs it and the model stays self-consistent; the
##   rejected alternative -- pivot at the grip's far end -- makes gravity torque
##   on a two-handed axe eat most of a one-handed torque budget, which is worse.
## - **Fatigue, accuracy and control.** All three are why real practice settles
##   on lighter tools than pure momentum wants. None is priced here.

const ItemPart: GDScript = preload("res://src/gameplay/item_part.gd")

## Standard gravity, m/s^2. A measurement.
const GRAVITY_MS2: float = 9.80665

## The arc a strike travels from cocked to contact, in radians. A quarter turn:
## hammer and hatchet work driven from the elbow covers roughly 60-90 degrees,
## and a sword cut from a guard position is about the same. Held as a named
## constant because the swing is solved as constant angular acceleration
## through a fixed ANGLE (you swing until you arrive, not for a fixed time),
## which is what makes swing_time_s fall out of the same equation as
## delivered_momentum instead of being a second opinion about the same swing.
const SWING_ARC_RAD: float = PI / 2.0

## ## The one free constant, and the measurement it is solved for
##
## The torque an unmodified adult delivers about the GRIP over a swing, in N m,
## at actor_strength 1.0.
##
## It is not picked. It is the framing-hammer anchor below solved for torque:
## build the reference hammer (33 cm haft, 21 oz iron head -- the geometry a
## century of carpentry converged on), demand that its striking face arrive at
## the measured speed, and read off the torque that produces. Concretely, with
## I and the gravity torque both computed from the fixture:
##
##   tau = I * (v / reach)^2 / (2 * SWING_ARC_RAD) + M * g * balance_point
##
## Re-derived from the anchor by
## test_the_swing_torque_constant_is_the_framing_hammer_anchor_solved_for_torque,
## so it cannot drift away from the measurement it encodes.
##
## The rejected alternative was to take a published isometric wrist-torque
## figure (~10 N m) straight from an ergonomics table. Rejected because a swing
## is a whole-body kinetic chain delivering THROUGH the grip, not an isolated
## wrist action, so the isometric wrist number understates it by about half --
## and the model would then have said a carpenter cannot drive a nail.
const SWING_TORQUE_NM_AT_UNIT_STRENGTH: float = 17.13976807

## The anchor itself: the striking face of a one-handed framing hammer arrives
## at roughly 10 m/s. Measured, not modelled -- nail-driving studies put
## carpenters' hammer-head speeds at about 8 m/s for finish work and into the
## teens for framing. Pinned by
## test_the_reference_hammer_face_arrives_at_the_measured_framing_speed.
const FRAMING_HAMMER_FACE_SPEED_MS: float = 10.0


# -- topology: where the mass sits relative to the hand ---------------------

## The part a hand takes hold of -- the first ROLE_GRIP part in construction
## order, or "" if the assembly has nothing to hold it by.
##
## First-in-construction-order rather than "the only one": a two-handed haft or
## a pair of scissors genuinely has more than one grip, and picking the first
## keeps the answer stable (PartGraph's whole ordering discipline) instead of
## refusing to answer a question that has a reasonable answer.
static func grip_part_id(graph: RefCounted) -> String:
	var grips: Array = graph.parts_with_role(ItemPart.ROLE_GRIP)
	return "" if grips.is_empty() else String(grips[0])


## Distance from the pivot part's centre to `part_id`'s centre, in cm, SIGNED.
##
## Magnitude is the shipped path length between the two, less half of each end
## part's own span -- i.e. the whole of every part in between plus half of each
## end, which is what "centre to centre along the chain" means.
##
## The sign is what makes a pommel a pommel. Remove the pivot part and the
## assembly falls into branches; a sword's blade is down one and its pommel down
## the other, so they lie on OPPOSITE SIDES OF THE HAND and their gravity
## torques oppose. The branch holding the farthest part is positive and every
## other branch is negative. That is the most an unoriented graph can honestly
## say about direction, and for the one-hand-in-the-middle assemblies this
## model is about, it is exactly right. An assembly with three or more branches
## off the grip gets them all lumped onto one side, which is a real
## simplification and is why `separates_into`-style multi-branch tools are not
## claimed here.
static func offset_cm(graph: RefCounted, pivot_part_id: String, part_id: String) -> float:
	return _side_of(graph, pivot_part_id, part_id) * _magnitude_cm(graph, pivot_part_id, part_id)


## How far the farthest point of the assembly is from the pivot's centre, in cm
## -- the radius the working end actually strikes at.
static func reach_cm(graph: RefCounted, pivot_part_id: String) -> float:
	if not graph.has_part(pivot_part_id):
		return 0.0
	var farthest := 0.0
	for part_id in graph.part_ids():
		var to_far_end: float = _magnitude_cm(graph, pivot_part_id, part_id) \
			+ 0.5 * graph.part(part_id).span_cm()
		farthest = maxf(farthest, to_far_end)
	return farthest


## Where the thing balances: the signed distance in cm from the pivot's centre
## to the centre of mass. Small is a lively item; large is one that hangs off
## the hand -- and it is the lever arm gravity acts on, which is why it is the
## quantity a pommel exists to shrink.
static func balance_point_cm(graph: RefCounted, pivot_part_id: String) -> float:
	var total_mass: float = graph.total_mass_kg()
	if total_mass <= 0.0:
		return 0.0
	var moment := 0.0
	for part_id in graph.part_ids():
		moment += graph.part(part_id).mass_kg() * offset_cm(graph, pivot_part_id, part_id)
	return moment / total_mass


# -- rigid-body inertia ----------------------------------------------------

## Moment of inertia about the pivot part's centre, in kg m^2.
##
## The real thing: sum over parts of (own moment about its own centre) + m d^2,
## the parallel-axis theorem. The d^2 term is what makes mass at the tip cost so
## much more than mass at the hand, and it is the entire reason a pommel works.
##
## Each part's OWN moment uses the slender-rod result m L^2 / 12 for every
## geometry, rather than a per-geometry inertia tensor. That is a documented
## simplification and not a load-bearing one: for the shipped arming sword the
## own-moment terms are a small correction to the d^2 terms, which
## test_the_own_moment_is_a_small_correction_not_the_answer pins. The rejected
## alternative -- a real tensor per geometry -- would have added five formulas to
## change the sword's inertia by a few percent, and a sphere's true 2/5 m r^2
## against the rod's m d^2 / 12 differs by less than a fifth of a percent of the
## total on any assembly this model is for.
static func moment_of_inertia(graph: RefCounted, pivot_part_id: String) -> float:
	if not graph.has_part(pivot_part_id):
		return 0.0
	var total := 0.0
	for part_id in graph.part_ids():
		var part: RefCounted = graph.part(part_id)
		var mass: float = part.mass_kg()
		var distance_m := _magnitude_cm(graph, pivot_part_id, part_id) / 100.0
		var span_m: float = part.span_cm() / 100.0
		total += mass * distance_m * distance_m + mass * span_m * span_m / 12.0
	return total


## Moment of inertia about the CENTRE OF MASS, in kg m^2 -- how hard the thing
## is to turn about its own balance point, which is what "point control" and
## "recovering after a cut" actually cost.
##
## This is the quantity a pommel improves and the moment about the grip is not:
## a pommel sits behind the hand, so it ADDS to the inertia about the grip while
## pulling the balance point back toward the hand and dropping the inertia about
## it. Derived by the parallel-axis theorem from the moment about the grip
## rather than summed again, so the two can never disagree.
static func moment_of_inertia_about_balance_point(
	graph: RefCounted, pivot_part_id: String
) -> float:
	var balance_m := balance_point_cm(graph, pivot_part_id) / 100.0
	return maxf(
		0.0,
		moment_of_inertia(graph, pivot_part_id)
			- graph.total_mass_kg() * balance_m * balance_m
	)


# -- the swing -------------------------------------------------------------

## The torque gravity levies just for holding the thing out, in N m: the whole
## mass acting at the balance point. Absolute, because holding a sword out costs
## the same whichever side of the hand its balance point is on.
static func gravity_torque_nm(graph: RefCounted, pivot_part_id: String) -> float:
	return graph.total_mass_kg() * GRAVITY_MS2 * absf(balance_point_cm(graph, pivot_part_id)) / 100.0


## What is left to ACCELERATE with, in N m. Zero when the thing is so heavy that
## holding it out is all the actor can do -- which is the heavy end of the
## optimum, and the honest reason a swing has one.
static func net_swing_torque_nm(
	graph: RefCounted, pivot_part_id: String, actor_strength: float
) -> float:
	var available := maxf(0.0, actor_strength) * SWING_TORQUE_NM_AT_UNIT_STRENGTH
	return maxf(0.0, available - gravity_torque_nm(graph, pivot_part_id))


## Angular velocity at contact, rad/s. Constant angular acceleration through
## SWING_ARC_RAD from rest: omega = sqrt(2 * arc * torque / inertia).
static func swing_speed_rad_s(
	graph: RefCounted, pivot_part_id: String, actor_strength: float
) -> float:
	var inertia := moment_of_inertia(graph, pivot_part_id)
	if inertia <= 0.0:
		return 0.0
	return sqrt(2.0 * SWING_ARC_RAD * net_swing_torque_nm(graph, pivot_part_id, actor_strength) / inertia)


## How long one swing takes, in seconds -- the same swing, solved for time
## instead of speed: t = sqrt(2 * arc * inertia / torque).
##
## INF when the actor cannot swing it at all (holding it out already costs
## everything they have). INF rather than a large number because "you cannot" and
## "it takes a while" are different answers and a caller must be able to tell
## them apart -- the same reason item.gd uses 0.0 for "not modelled" rather than
## a plausible guess.
static func swing_time_s(graph: RefCounted, actor_strength: float) -> float:
	var pivot := grip_part_id(graph)
	if pivot == "":
		return INF
	var torque := net_swing_torque_nm(graph, pivot, actor_strength)
	if torque <= 0.0:
		return INF
	return sqrt(2.0 * SWING_ARC_RAD * moment_of_inertia(graph, pivot) / torque)


## The linear impulse the swung assembly can deliver at its striking radius, in
## kg m/s -- the momentum ImpactResolver.resolve_impact already consumes.
##
## It is the angular momentum about the grip divided by the strike radius,
## L / r = I * omega / r. That is the textbook rigid-body impact quantity and it
## is the RIGHT generalisation rather than a convenient one: for a point mass at
## radius r it reduces exactly to m * v, so this is plain momentum wherever
## plain momentum is defined, and it carries the effective mass at the contact
## point everywhere else. That effective-mass term (I / r^2) is why a strike
## near the hand transfers less than one at the tip even at the same tip speed.
##
## Zero for an assembly with nothing to hold, or one too heavy for the actor to
## swing at all.
static func delivered_momentum(graph: RefCounted, actor_strength: float) -> float:
	var pivot := grip_part_id(graph)
	if pivot == "":
		return 0.0
	var radius_m := reach_cm(graph, pivot) / 100.0
	if radius_m <= 0.0:
		return 0.0
	return moment_of_inertia(graph, pivot) \
		* swing_speed_rad_s(graph, pivot, actor_strength) / radius_m


# -- internals -------------------------------------------------------------

## Unsigned centre-to-centre distance along the chain, in cm.
static func _magnitude_cm(graph: RefCounted, pivot_part_id: String, part_id: String) -> float:
	if not graph.has_part(pivot_part_id) or not graph.has_part(part_id):
		return 0.0
	var route: Array = graph.path_between(pivot_part_id, part_id)
	if route.is_empty():
		return 0.0
	var half_ends: float = 0.5 * graph.part(pivot_part_id).span_cm() \
		+ 0.5 * graph.part(part_id).span_cm()
	return maxf(0.0, graph.path_length_cm(route) - half_ends)


## +1.0 on the branch carrying the farthest part, -1.0 on every other branch.
## See offset_cm's doc comment for why an unoriented graph can say this much and
## no more.
static func _side_of(graph: RefCounted, pivot_part_id: String, part_id: String) -> float:
	if part_id == pivot_part_id:
		return 1.0
	var branch := _branch_containing(graph, pivot_part_id, part_id)
	var farthest_branch := _branch_containing(
		graph, pivot_part_id, _farthest_part(graph, pivot_part_id)
	)
	return 1.0 if branch == farthest_branch else -1.0


## The parts reachable from `part_id` without passing back through the pivot,
## as a stable key: the first member in construction order.
static func _branch_containing(
	graph: RefCounted, pivot_part_id: String, part_id: String
) -> String:
	if part_id == "" or part_id == pivot_part_id:
		return ""
	var seen := {part_id: true}
	var queue: Array[String] = [part_id]
	var head := 0
	while head < queue.size():
		var current := queue[head]
		head += 1
		for next_part in graph.neighbors(current):
			if next_part == pivot_part_id or seen.has(next_part):
				continue
			seen[next_part] = true
			queue.append(next_part)
	for candidate in graph.part_ids():
		if seen.has(candidate):
			return candidate
	return ""


static func _farthest_part(graph: RefCounted, pivot_part_id: String) -> String:
	var farthest := ""
	var best := -1.0
	for part_id in graph.part_ids():
		var distance := _magnitude_cm(graph, pivot_part_id, part_id)
		if distance > best:
			best = distance
			farthest = part_id
	return farthest
