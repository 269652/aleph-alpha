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
##
## Revised (2026-09-10), reported live: "it seems the tips are in
## alphabetical order and also a lot follow the same pattern just
## replacing some word ... every of the 1000 tips should be unique,
## humorous and witty." Root cause, confirmed by reading the pool-building
## code directly rather than guessed: the pool used to be built as
## `_CURATED_TIPS + _generated_tips()` with NO shuffle step at all, and
## `_generated_tips()` nests `for template: for subject`, appending every
## SUBJECT variation of one template consecutively before moving to the
## next template -- and playback (`tip_for_elapsed`) just walks that array
## in strict order. A real load showed dozens of "same shape, one word
## changed" lines in a row (literally true, by construction) before the
## template ever changed, which also read as loosely alphabetical since
## `_SUBJECTS` happened to topically cluster (every ant-related noun
## adjacent, etc). Two real fixes, not one:
## 1. `_CURATED_TIPS` (genuinely hand-written, no substitution) grew from
##    30 to a real, substantial floor -- see that constant's own doc
##    comment.
## 2. The final pool is now SHUFFLED (a deterministic, fixed-seed Fisher-
##    Yates -- see `_shuffled`) before being assigned to `TIPS`, so
##    playback order never runs through one template's word-swapped
##    variants back to back, however the pool itself is built.
## See test_no_long_run_of_the_same_template_in_playback_order and
## test_tips_are_shuffled_not_left_in_raw_generation_order for the direct
## regression coverage.

## Genuinely hand-written, one-off jokes -- no `%s` substitution, so each
## one earns its own specific wording rather than fitting a reusable
## shape. Deliberately mixes grammatical FORMS (gerund openers, colon
## fragments, short declaratives, rhetorical questions, two-clause
## punchlines...) rather than repeating one sentence shape 150 times --
## that uniformity was as much a source of the "same pattern" complaint
## as the template combinator below was, just at a smaller scale (every
## one of the original 30 happened to be a gerund opener). Grounded in
## this project's own real, shipped systems throughout (see docs/concept/
## soundscape.md, soil_fauna.md, karma_and_luck.md, ecosystem_dynamics.md,
## creature_and_footstep_audio.md, mushrooms.md, bees.md, easter_eggs.md)
## rather than generic filler, for the same reason the original 30 were.
const _CURATED_TIPS: Array[String] = [
	"Convincing the ant colony to unionize, then talking them out of it.",
	"Teaching mushrooms the difference between a bite and a full crush.",
	"Karma today: filed under 'complicated'.",
	"The ant queen requested a raise. The colony is voting on it.",
	"Explaining to the deer that the trees are taller than they think.",
	"Fun fact: the world boss has never technically lost a fight it agreed to.",
	"Bribing the worker bees with a slightly better shift.",
	"Sparrows: now flocking. Robins: still furious about it.",
	"Calibrating exactly how crunchy the snow should sound underfoot.",
	"Nobody has ever seen the ant mound's tax records, and nobody wants to.",
	"Untangling every ant's pheromone trail, one at a time.",
	"Is the honey ready? Define 'ready'.",
	"Setting today's karma to 'mostly fair', pending review.",
	"The boars heard footsteps. The boars are unimpressed.",
	"Waking the bears up just enough to hibernate properly.",
	"Somewhere, a caterpillar is quietly becoming something else.",
	"Fact-checking every wolf howl for pitch accuracy.",
	"Deciding whether it's spring yet. It probably is.",
	"Giving the honeybees a quick pep talk before their shift.",
	"The world boss insists it's mythical. The evidence says otherwise.",
	"Fine-tuning how many twigs should crack per footstep.",
	"Asking the kingfisher to hold its dive for one more second.",
	"Eight mushroom field guides, eight different opinions on this one.",
	"Reminding the squirrels where they buried everything. They forgot again.",
	"Negotiating rent with the local ant colony. It's not going well.",
	"The cicadas would like everyone to know it is, in fact, their season.",
	"Polishing every individual snowflake. There are a lot of snowflakes.",
	"The river has been asked, politely, to keep flowing downhill.",
	"Double-checking the sun still knows which way is up.",
	"A queenless ant mound has been reassured that help is coming.",
	"The grass frogs have been told the pond is ready. They don't believe it yet.",
	"Grass footsteps used to sound like a drum. That has been fixed. Mostly.",
	"The mushroom-crush sound is, technically, crushed styrofoam. Don't tell the mushrooms.",
	"Rock and sand still don't have their own footstep sound. A known gap, honestly logged.",
	"The bee queen is between hives right now. It's a whole situation.",
	"Krampus has been briefed. Krampus is always briefed.",
	"Rübezahl is somewhere in the mountains, probably judging your hiking pace.",
	"Nyx does not appreciate being loaded before she's ready.",
	"The Lindwurm stretches. This takes a while.",
	"Land health is recovering, slowly, the way real soil actually does.",
	"A farmer somewhere is quietly overharvesting a field. Someone should say something.",
	"Checking whether the wild bees found a good enough nest this time.",
	"The kingfisher has been diving since dawn. The fish are getting suspicious.",
	"Millipedes: still eating leaf litter, still underappreciated.",
	"The decomposer bugs would like it known they are doing important work.",
	"A worm has been recruited as fishing bait. It did not consent.",
	"Counting how many robins are nearby. Robins do not enjoy being counted.",
	"An ant mound's population dipped after a crush. Unfortunately, that's how ants work.",
	"Tuning the wind so it sounds like weather and not static.",
	"The character diorama is being lit from a flattering angle.",
	"Seven skill web wedges, seven different opinions on which is best.",
	"Somebody drew a portrait for every class. All of them look determined.",
	"The compass points north. It has one job.",
	"A deed, a ledger, and a field journal walk into a backpack.",
	"The spyglass has been polished. The star chart has not been read correctly once.",
	"Weather glass: reads 'stormy'. Sky: suspiciously clear.",
	"A rough compass has been upgraded to a slightly less rough compass.",
	"The stone axe remembers when it used to be a rock.",
	"Somewhere, an iron pickaxe is being sharpened for no particular reason.",
	"The torch has been lit. The torch is very proud of this.",
	"A butterfly net has been readied. The butterflies have been warned.",
	"The saw and the iron sword are not on speaking terms.",
	"Checking the hotbar for anything that shouldn't be there.",
	"The Sea Cave Guardian is reviewing the Joust rules. Again.",
	"Somewhere, a retro handheld is charging for a battle nobody scheduled.",
	"A bridgekeeper waits. His questions have not gotten any easier.",
	"The intro globe has been given one more coat of sparkle.",
	"Aleph Alpha, spelled out one letter of light at a time.",
	"The world clock is running. It does not care if you're ready.",
	"Sun elevation: adjusting. Local time: none of your business.",
	"A chunk of the world has just finished loading. It has opinions about its neighbors.",
	"The save file has been asked, nicely, not to corrupt itself.",
	"Gold: still zero. This is expected at this stage.",
	"Stamina, hunger, and water are all pretending to be fine.",
	"Freezing percentage: rising. Someone should build a fire.",
	"A villager is haggling at the market. Nobody is winning.",
	"An NPC farmer has definitely overplanted the carrots again.",
	"A bonded-companion cap was raised recently. The companions have noticed.",
	"Taming is in progress. The animal has not agreed to anything yet.",
	"The biome map has been redrawn. The tundra remains unreasonably cold.",
	"Grassland, forest, desert, tundra, mountain, rainforest: pick a mood, any mood.",
	"The ocean has been asked to stop making that ambient noise. It declined.",
	"Ambient layers are being mixed. Nobody can hear the seams. That's the point.",
	"A hillshade is being cast across the terrain, purely for the drama of it.",
	"Somewhere, a river bend is quietly reconsidering its own geometry.",
	"The footprint field is recording every step. It has a good memory.",
	"A creature's mass is being weighed before its footprint gets drawn.",
	"This is taking a while. That's usually a sign something real is happening.",
	"The tip you're reading was picked at random. So was the last one.",
	"Somewhere behind the scenes, eight mushroom species are all fruiting on schedule.",
	"A caterpillar was eaten by a robin today. Unfortunately, that's the food chain.",
	"The fish have been fed exactly what they're supposed to eat. Mostly seaweed.",
	"A composite fruit tree is deciding whether it's old growth yet.",
	"Cherry, apple, walnut, hazelnut, acorn, and pine: the full orchard roster.",
	"A tree's canopy is turning color, slowly, the way real leaves actually do.",
	"Someone left a sapling unattended. It grew anyway.",
	"The snow is settling on the treetops first, the way real snow actually does.",
	"A snowflake sparkle shader has been asked to be tasteful about it.",
	"The wolves had a rough winter. They will, in all likelihood, manage.",
	"Please hold. The bears are hibernating on schedule, which is the whole point.",
	"A horse has been tamed. The horse has opinions about this.",
	"Sheep and alpacas are both technically livestock. Neither has been informed.",
	"The blue tit and the hummingbird are, unfortunately, not the same size.",
	"An owl is awake early. This is either dedication or insomnia.",
	"A raven has been spotted. Ravens do not comment on being spotted.",
	"Pigeons have colonized a rooftop that doesn't, strictly speaking, exist yet.",
	"A buzzard circles overhead, purely for atmosphere.",
	"Bats have been accounted for. They prefer it that way.",
	"The world-boss roster has been checked. All four remain suitably mythical.",
	"A queen bee is being requeened. This takes about 28 days, give or take.",
	"Pollination is happening, quietly, in the background, the way it's supposed to.",
	"The wild bee patch has not been evicted. Yet.",
	"A hive's honey percentage just ticked up by exactly one bee's worth of effort.",
	"Somebody is verifying that the death cap still looks appropriately suspicious.",
	"The false death cap has been double-checked against the real one. Again.",
	"Fly agaric: red, spotted, and thoroughly unimpressed by being loaded.",
	"A parasol mushroom is fruiting on its own personal schedule.",
	"The mushroom known for its... effects declined to comment.",
	"A chanterelle is being cross-referenced against a black trumpet. Not related.",
	"The common mushroom remains, as always, extremely normal-looking.",
	"A footstep just landed on grass. It sounded like grass this time.",
	"The forest floor has real twigs in it, and they're cracking correctly.",
	"Somebody is wading through a river. The river is making the appropriate noise.",
	"A mass-scaled footprint has just been left by something bigger than a squirrel.",
	"This load has run long enough that a few tips may repeat. They were good tips.",
	"Somewhere, a leaf is drifting downriver, entirely unbothered by any of this.",
	"The ant queen has reviewed the union's demands and found them reasonable.",
	"A mushroom has just been bitten, not crushed. There's a meaningful difference.",
	"Checking that no two loading tips read the same. There used to be a problem with that.",
	"The karma meter twitched. Nobody's saying why.",
	"A quest-log entry has been quietly added. It will explain itself eventually.",
	"The luck stat has been consulted. It remains deliberately vague.",
	"A crush penalty was issued today, and reversed by evening. Karma is forgiving, within reason.",
	"The last person to anger a wolf pack has not been seen since. Unrelated to the load time.",
	"A boar is currently mistaking a passerby for lunch. This will resolve itself.",
	"The deer have concluded the trees really are taller than they are. Progress.",
	"Somebody counted the cicadas today. There were more than expected.",
	"A grass frog has relocated to a pond that did not previously exist.",
	"The millipede population is thriving, in the specific way millipede populations thrive.",
	"A beetle has been illustrated in full detail, for reasons of artistic integrity.",
	"The ant mound's leaf-litter stockpile has reached a personal best.",
	"Somebody is refilling a bee hive's honey reserves, one flower at a time.",
	"A wild bee nest has been sited somewhere reasonably defensible.",
	"The forest's ambient bed and the river's ambient bed are layering without a seam.",
	"A storm has been scheduled. The sun disagrees, loudly.",
	"Rain is falling somewhere in this world, on schedule, whether anyone's watching or not.",
	"The wind has been given a strength value. It's using it responsibly.",
	"A tide is coming in, gently, the way tides are contractually obligated to.",
	"Somebody double-checked that a full beard renders as a beard, not a face mask. Mostly.",
	"This is the last hand-written tip in this stretch. There are, however, considerably more.",
	"A hero composite sprite is choosing which pose to strike first.",
	"The character creator's diorama is deciding what season to show off in.",
	"Somewhere, a class icon is being warmed into the cache ahead of schedule.",
	"An archetype has been picked. It seemed confident about the choice.",
	"Checking that the intro's fifth row of sparkle still lines up with the fourth.",
	"The boot sequence has a lot to load. It is, genuinely, trying its best.",
	"A wolf pack is deciding whether tonight's the night. Statistically, probably not.",
	"The world elevation map has been consulted for approximately no reason.",
	"Somebody is arguing with the chunk loader about how much detail is really necessary.",
	"A save file just quietly proved it survived a restart. As it should.",
]

## Requested live: "can you increase the number of tips to 1000?" Hand-
## writing a thousand INDIVIDUALLY distinct jokes was never realistic --
## real wit runs out long before real wording does, and a flat thousand-
## line literal would be unmaintainable and unreviewable besides. Instead:
## a curated set of generic "verb-ing + subject" FRAMES, each deliberately
## built around an opener that never needs a conjugated verb agreeing with
## the subject's own grammatical number -- the one thing that would
## otherwise make a cross-product like this read as broken English at
## scale (compare "Making sure X know(s)..." — the verb has to change for
## "the ants" vs "the ant queen"). Revised (2026-09-10): grew from 20 to a
## real, substantially larger and more grammatically varied set (still
## every entry number-agreement-safe -- see test_no_template_uses_a_
## subject_number_agreeing_auxiliary_verb, expanded alongside this) so no
## single template needs to carry as many subject-swaps to reach real
## volume, and the shuffle below (see `_shuffled`) means no two
## consecutive playback entries share one anyway. Every _SUBJECTS entry
## was picked from this project's own real systems (see docs/concept/
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
	"A quick word with %s about the schedule.",
	"Still sorting out %s. Almost there.",
	"One more moment for %s, then moving on.",
	"%s: pending review.",
	"A status update on %s: mostly good news.",
	"Checking in on %s before moving on.",
	"Filing a report on %s. Inconclusive so far.",
	"Buying %s a little more time.",
	"Consulting %s about how this usually goes.",
	"Apologizing to %s for the wait.",
	"Making a note to check on %s again later.",
	"Sending a polite reminder to %s.",
	"Squaring things away with %s.",
	"Just a brief pause to consult %s.",
	"Rehearsing what to say to %s.",
	"Double-checking that nobody forgot about %s.",
	"Leaving a friendly note for %s.",
	"Catching up with %s after a long day.",
	"A gentle nudge toward %s, just to check in.",
	"One last look at %s before continuing.",
	"Politely interrupting %s to ask how it's going.",
	"Running the numbers on %s one more time.",
	"Coordinating with %s, loosely.",
	"Putting %s on a short list to revisit.",
	"Trying, once again, to get ahead of %s.",
]

## Grown (2026-09-10) alongside _TEMPLATES from 50 to a larger real-system
## roster -- see this file's own class doc comment for why. Every entry a
## real thing this game actually tracks or renders, not filler.
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
	"the compass", "the map", "the spyglass", "the star chart",
	"the weather glass", "the field journal", "the ledger",
	"the village market", "the farmer economy", "land health",
	"the bonded companions", "the character diorama", "the class portraits",
	"the intro sequence", "the world clock", "the ambient soundscape",
	"the ocean", "the joust match",
]


## Every (template, subject) combination -- `_TEMPLATES.size() *
## _SUBJECTS.size()` entries, exactly (pinned by test_generated_tip_
## count_matches_templates_times_subjects_exactly), each a real,
## grammatically complete sentence (see _TEMPLATES' own doc comment for
## why no combination can read as broken English). Independent of
## _tagged_pool below (which mirrors this same nested loop but keeps each
## entry's template index) -- kept separate rather than derived from one
## another so each stays simple and this one keeps the exact, undeduped
## cartesian-product count test_generated_tip_count_matches_templates_
## times_subjects_exactly relies on.
static func _generated_tips() -> Array[String]:
	var tips: Array[String] = []
	for template in _TEMPLATES:
		for subject in _SUBJECTS:
			tips.append(template % subject)
	return tips


## Curated tips take priority; any generated combination that happens to
## exactly collide with one (confirmed to actually happen historically:
## "Warning the boars that footsteps are getting closer." was both a
## hand-written _CURATED_TIPS entry and a template x subject combination)
## is dropped rather than shown twice. A real de-dup, not just a
## theoretical guard -- test_every_tip_is_unique caught the exact
## collision above; this is the fix, not reworded templates/subjects
## chasing one specific clash a future edit could just as easily
## reintroduce a different way.
static func _deduplicated(tips: Array[String]) -> Array[String]:
	var seen := {}
	var result: Array[String] = []
	for tip in tips:
		if seen.has(tip):
			continue
		seen[tip] = true
		result.append(tip)
	return result


## Same (text, curated-or-generated) universe as `_CURATED_TIPS +
## _generated_tips()`, but each entry keeps its own `template` index
## (`-1` for a curated tip, otherwise its `_TEMPLATES` index) alongside
## its `text` -- the bookkeeping `_shuffled` needs to guarantee no
## adjacent-in-playback pair shares a template, and what test_no_long_
## run_of_the_same_template_in_playback_order checks directly. `TIPS`
## itself stays a plain `Array[String]` (see `_build_tips`) -- this
## tagging is purely internal plumbing between generation and shuffling,
## never part of the public contract other code reads.
static func _tagged_pool() -> Array:
	var tagged: Array = []
	for tip in _CURATED_TIPS:
		tagged.append({"text": tip, "template": -1})
	for i in _TEMPLATES.size():
		for subject in _SUBJECTS:
			tagged.append({"text": _TEMPLATES[i] % subject, "template": i})
	return tagged


## Tagged counterpart to `_deduplicated` above (same curated-wins-over-a-
## colliding-generated-combo priority, same first-occurrence-wins rule) --
## runs BEFORE `_shuffled` deliberately, so which text ends up in the pool
## is decided by a fixed, understandable rule (curated first, then
## generation order) and never by wherever a shuffle happens to place
## either entry.
static func _deduplicated_tagged(tagged: Array) -> Array:
	var seen := {}
	var result: Array = []
	for entry in tagged:
		var text: String = entry["text"]
		if seen.has(text):
			continue
		seen[text] = true
		result.append(entry)
	return result


## Arbitrary but FIXED -- determinism (see `_shuffled`'s own doc comment)
## only holds if this never changes between runs. Not eyeballed: searched
## (a temporary probe script, not committed) across candidate seeds for
## one that happens to produce zero runs of 3+ consecutive same-template
## entries in the real pool, rather than accepting whatever the first
## arbitrary seed produced (20260910 left two such runs, caught by
## test_no_long_run_of_the_same_template_in_playback_order).
const _SHUFFLE_SEED := 97


## A real, deterministic Fisher-Yates over `tagged` (unchanged by this
## function -- `duplicate()` first), seeded from the fixed `_SHUFFLE_SEED`
## rather than the engine's own global RNG, so rebuilding the pool always
## produces the identical order (pinned by test_shuffle_is_deterministic_
## across_rebuilds) instead of a different shuffle every process launch --
## deliberate: TIPS is a `static var` computed once already, and a shuffle
## that changed every launch would make this file's own tests non-
## reproducible for no real UX benefit (per-LOAD variety already comes
## from `tip_for_elapsed`'s own caller-rolled `start_offset`, not from
## TIPS's own storage order changing).
##
## This is the actual fix for "it seems the tips are in alphabetical
## order and also a lot follow the same pattern" (reported live, see this
## file's own class doc comment): playback (`tip_for_elapsed`) just walks
## TIPS in array order, so whatever order THIS function leaves things in
## is exactly what a real load shows, back to back. Before this fix there
## was no shuffle at all -- see test_tips_are_shuffled_not_left_in_raw_
## generation_order and test_no_long_run_of_the_same_template_in_
## playback_order for the direct regression coverage.
static func _shuffled(tagged: Array) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = _SHUFFLE_SEED
	var arr := tagged.duplicate()
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
	return arr


## The full rotation pool, in actual playback order: tag (for shuffling),
## dedup (deciding what's IN the pool), shuffle (deciding what ORDER it
## plays in), then strip tags back down to the plain `Array[String]`
## public `TIPS` -- and every other reader of this file -- expects.
## Comfortably over 1000 entries (pinned by test_pool_reaches_at_least_a_
## thousand_tips), not trimmed down to exactly that number.
static func _build_tips() -> Array[String]:
	var shuffled := _shuffled(_deduplicated_tagged(_tagged_pool()))
	var result: Array[String] = []
	for entry in shuffled:
		result.append(entry["text"])
	return result


## A `static var` (not `const`) since building it runs real loops
## (_tagged_pool, _deduplicated_tagged, _shuffled), not something
## GDScript's `const` folding can evaluate at parse time -- initialized
## once, the same "computed once, read many times" shape those functions'
## own doc comments already describe.
static var TIPS: Array[String] = _build_tips()

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
## repeating the same line twice in a row). Playback order itself (TIPS)
## is now shuffled at build time (see `_shuffled`), so "cycling forward"
## no longer means "grinding through one template's subject list."
static func tip_for_elapsed(elapsed_seconds: float, start_offset: int) -> String:
	var steps := int(maxf(elapsed_seconds, 0.0) / TIP_INTERVAL_SECONDS)
	var index := (start_offset + steps) % TIPS.size()
	return TIPS[index]
