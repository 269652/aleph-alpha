extends RefCounted

## Sims-4-style witty loading tips (see docs/concept/persistence.md's
## "Loading screens" section). Requested live: "make the loading screens
## use SIMS 4 style loading descriptions (funny witty progress lines)."
## Pure rotation logic, no Node/Control dependency -- the same "pure
## model, thin Node" split LoadingSpinner.frame_for_elapsed already uses
## for the identical reason (LoadingOverlay just reads whichever line this
## returns for the current elapsed time).
##
## Original lines written in the spirit of that genre's dry, self-aware
## humor -- not reproduced from any specific game -- flavored with THIS
## project's own real systems (ants, mushrooms, karma, seasons, bees,
## world bosses, cicadas...) rather than generic filler, so a returning
## player recognizes the joke as being about ITS world.

const TIPS: Array[String] = [
	"Convincing the ant colony to unionize, then talking them out of it.",
	"Teaching mushrooms the difference between a bite and a full crush.",
	"Politely asking the bees to buzz in the right key.",
	"Explaining to the deer that the trees are taller than they think.",
	"Double-checking the Earth is still spinning the correct direction.",
	"Bribing the worker bees with a slightly better shift.",
	"Reminding the wolves that lunch is not always guaranteed.",
	"Calibrating exactly how crunchy the snow should sound underfoot.",
	"Making sure nobody crushes a mushroom by accident. Yet.",
	"Untangling every ant's pheromone trail, one at a time.",
	"Counting how many robins are actually nearby right now.",
	"Setting today's karma to 'mostly fair'.",
	"Warning the boars that footsteps are getting closer.",
	"Waking the bears up just enough to hibernate properly.",
	"Reminding the caterpillars that they, too, will amount to something.",
	"Fact-checking every wolf howl for pitch accuracy.",
	"Deciding whether it's spring yet. It probably is.",
	"Giving the honeybees a quick pep talk before their shift.",
	"Making sure the world boss stays exactly as mythical as advertised.",
	"Fine-tuning how many twigs should crack per footstep.",
	"Asking the kingfisher to hold its dive for one more second.",
	"Cross-referencing every mushroom against several disagreeing field guides.",
	"Reminding the squirrels where they buried everything.",
	"Negotiating rent with the local ant colony.",
	"Making sure the cicadas know it's their season.",
	"Polishing every individual snowflake, one at a time.",
	"Convincing the river it should, in fact, flow downhill.",
	"Making sure the sun rises from approximately the correct direction.",
	"Reassuring a queenless ant mound that help is on the way.",
	"Letting the grass frogs know the pond is ready.",
]

## How long (seconds) each tip stays on screen before the next one shows
## -- long enough to comfortably read a short line, short enough that a
## long real load (measured 39-90s+, see this doc's own "Loading screens"
## section) shows several different ones rather than staring at just one.
## A real, deliberate UX choice, pinned by test_tip_interval_is_a_real_
## reasonable_reading_duration rather than left an eyeballed guess.
const TIP_INTERVAL_SECONDS := 4.5


## `start_offset` is rolled ONCE per loading-screen appearance (a caller-
## supplied index, e.g. `randi() % TIPS.size()`) so this stays pure and
## deterministic to test -- the same "caller rolls, this decides" split
## every chance-gated moment in this codebase already uses. Different
## loads then open on a different tip instead of always starting at index
## 0, cycling forward through the rest in a fixed, readable order rather
## than re-rolling randomly each interval (which risks an unlucky run
## repeating the same line twice in a row).
static func tip_for_elapsed(elapsed_seconds: float, start_offset: int) -> String:
	var steps := int(maxf(elapsed_seconds, 0.0) / TIP_INTERVAL_SECONDS)
	var index := (start_offset + steps) % TIPS.size()
	return TIPS[index]
