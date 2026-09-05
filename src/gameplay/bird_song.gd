extends RefCounted

## Whether a bird is singing right now -- a pure, periodic duty-cycle roll,
## not a phase machine: singing has no world-state consequence (no worm
## eaten, no fish caught), only a visual/animation one, so it doesn't need
## GroundForageBehavior/PiscivoreBirdBehavior's own kind of state (see
## docs/concept/ecosystem_dynamics.md's Phase 3 writeup). Requested
## directly, alongside dancing/pecking/foraging: "no tweeting... wire this
## all up".
##
## Per-bird offset (via `seed_value`) so a flock doesn't all start and stop
## singing on the same instant -- the same reason FlapGlide/NectaringPosture
## salt their own clocks with a seed.

## How often a bird MIGHT begin a singing bout.
const SING_INTERVAL_SECONDS := 6.0

## How long one bout lasts once it starts -- long enough to actually read
## as singing (several sound-line frames), short enough that a bird spends
## most of its time doing everything else.
const SING_DURATION_SECONDS := 1.5


static func should_sing(seed_value: int, elapsed_seconds: float) -> bool:
	var offset := float(absi(seed_value) % 997)
	var phase := fposmod(elapsed_seconds + offset, SING_INTERVAL_SECONDS)
	return phase < SING_DURATION_SECONDS
