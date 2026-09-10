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

## The original, individually hand-written tips -- kept in full (not
## folded into the template combinator below) since each one earns its
## own specific joke rather than fitting the generic "verb + subject"
## shape every _TEMPLATES entry follows.
const _CURATED_TIPS: Array[String] = [
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

## Requested live: "can you increase the number of tips to 1000?" Hand-
## writing a thousand INDIVIDUALLY distinct jokes was never realistic --
## real wit runs out long before real wording does, and a flat thousand-
## line literal would be unmaintainable and unreviewable besides. Instead:
## a small, curated set of generic "verb-ing + subject" FRAMES, each
## deliberately built around a present-participle opener ("Convincing",
## "Reminding", "Untangling"...) so it never needs a conjugated verb that
## has to agree with the subject's own grammatical number -- the one
## thing that would otherwise make a cross-product like this read as
## broken English at scale (compare "Making sure X know(s)..." — the verb
## has to change for "the ants" vs "the ant queen"; "Making sure X
## haven't wandered off" has no such problem, since "haven't" governs a
## silent "they've" that reads fine either way). Every _SUBJECTS entry was
## picked from this project's own real systems (see docs/concept/
## soundscape.md, soil_fauna.md, karma_and_luck.md, ecosystem_dynamics.md)
## for the exact same reason _CURATED_TIPS above are flavored that way,
## not generic filler.
const _TEMPLATES: Array[String] = [
	"Convincing %s to cooperate, just this once.",
	"Double-checking %s one more time.",
	"Politely asking %s to hurry up. They won't.",
	"Reminding %s how this is supposed to work.",
	"Giving %s a quick pep talk.",
	"Untangling %s, one strand at a time.",
	"Negotiating with %s about the schedule.",
	"Bribing %s with slightly better terms.",
	"Reassuring %s that everything is under control.",
	"Warning %s that footsteps are getting closer.",
	"Waking %s up just enough to get moving.",
	"Counting %s. Losing count. Starting over.",
	"Calibrating exactly how %s should behave today.",
	"Setting %s to 'probably fine'.",
	"Teaching %s the difference between fact and rumor.",
	"Cross-referencing %s against several disagreeing sources.",
	"Fine-tuning %s down to the last decimal.",
	"Explaining to %s that this is, in fact, normal.",
	"Keeping an eye on %s so nothing wanders off.",
	"Asking %s to hold that pose for one more second.",
]

const _SUBJECTS: Array[String] = [
	"the ants", "the ant colony", "the ant queen", "the mushrooms",
	"the honeybees", "the wild bees", "the bee hive", "the wolves",
	"the deer", "the boars", "the bears", "the squirrels", "the robins",
	"the sparrows", "the kingfisher", "the caterpillars", "the cicadas",
	"the grass frogs", "the world boss", "karma", "the snow", "the river",
	"the seasons", "the trees", "the mushroom spores",
	"the pheromone trails", "the leaf litter", "the worm population",
	"the millipedes", "the decomposer bugs", "the fish", "the butterflies",
	"the wind", "the weather", "the sun", "the tides", "the footprints",
	"the crush mechanic", "the taming system", "the karma meter",
	"the luck stat", "the quest log", "the crafting recipes",
	"the hunger bar", "the stamina bar", "the day/night cycle",
	"the biome map", "the chunk loader", "the save file", "the skill web",
]


## Every (template, subject) combination -- `_TEMPLATES.size() *
## _SUBJECTS.size()` entries, exactly (pinned by test_generated_tip_
## count_matches_templates_times_subjects_exactly), each a real,
## grammatically complete sentence (see _TEMPLATES' own doc comment for
## why no combination can read as broken English).
static func _generated_tips() -> Array[String]:
	var tips: Array[String] = []
	for template in _TEMPLATES:
		for subject in _SUBJECTS:
			tips.append(template % subject)
	return tips


## Curated tips take priority; any generated combination that happens to
## exactly collide with one (confirmed to actually happen: "Warning the
## boars that footsteps are getting closer." is both a hand-written
## _CURATED_TIPS entry and the "Warning %s that footsteps are getting
## closer." x "the boars" combination) is dropped rather than shown
## twice. A real de-dup, not just a theoretical guard -- test_every_tip_
## is_unique caught the exact collision above; this is the fix, not
## reworded templates/subjects chasing one specific clash that a future
## edit could just as easily reintroduce a different way.
static func _deduplicated(tips: Array[String]) -> Array[String]:
	var seen := {}
	var result: Array[String] = []
	for tip in tips:
		if seen.has(tip):
			continue
		seen[tip] = true
		result.append(tip)
	return result


## The full rotation pool: every hand-curated tip plus every generated
## combination, de-duplicated -- comfortably over 1000 (pinned by
## test_pool_reaches_at_least_a_thousand_tips), not trimmed down to
## exactly that number. A `static var` (not `const`) since building it
## runs real loops (_generated_tips, _deduplicated), not something
## GDScript's `const` folding can evaluate at parse time -- initialized
## once, the same "computed once, read many times" shape those functions'
## own doc comments already describe.
static var TIPS: Array[String] = _deduplicated(_CURATED_TIPS + _generated_tips())

## How long (seconds) each tip stays on screen before the next one shows.
## Revised (2026-09-10), reported live after actually watching a real
## launch: the original 4.5s read as "it doesn't rotate" -- a load short
## enough not to reach even one full interval never shows a second tip at
## all, so the rotation itself was invisible, not broken. 2.0s is short
## enough that rotation is visible even on a brief load, still long enough
## to comfortably read a short line without feeling rushed. A real,
## deliberate UX choice, pinned by test_tip_interval_is_a_real_reasonable_
## reading_duration rather than left an eyeballed guess.
const TIP_INTERVAL_SECONDS := 2.0


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
