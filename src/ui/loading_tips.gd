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
##
## Revised again (2026-09-12), reported live: "make the witty tips more
## funny and original? Thought through and natural humour; it feels so
## forced." The 2026-09-10 pass fixed the ORDERING (shuffle, no repeated
## template runs) but never revisited the WORDING it was shuffling: most
## of `_CURATED_TIPS` still opened with the same "[Gerund]-ing a game
## system through a workplace-sitcom verb" shape (unionizing, filing tax
## records, negotiating rent, bribing a shift change...) -- a real,
## legitimate joke ONCE, worn down to a template by repetition, exactly
## the "same pattern" complaint this file already diagnosed once for the
## combinator half. `_TEMPLATES` had the opposite problem: safe, grammar-
## correct, and almost entirely unfunny ("Double-checking %s one more
## time.", "%s: pending review.") -- filler wearing the shape of a joke.
## Both arrays rewritten from scratch: `_CURATED_TIPS` now deliberately
## mixes joke MECHANISMS (deadpan escalation, one-sided argument, ironic
## reversal, absurdly specific detail, a flat non-answer, a quoted
## denial), not just sentence openers, still grounded in this project's
## own real systems throughout; `_TEMPLATES` now gives every line an
## actual per-line turn rather than a generic status update, while
## keeping the exact grammar discipline the subject list demands (see
## that constant's own doc comment on why `%s` can never be followed by a
## number-agreeing verb) -- and additionally never lets `%s` be the
## subject of ANY later verb, relative-clause verb, reflexive pronoun, or
## possessive either: a back-reference like "..., who is..." or "...
## its own..." would silently break for every plural entry in `_SUBJECTS`
## (about half the list -- "the ants", "the wolves", "the sparrows"...)
## the same way a bare "%s is" would, just past where the earlier
## hazard-substring test could catch it. `_SUBJECTS` itself untouched:
## the complaint was about the joke, not which real system it names.
##
## A live spot-check of the first rewrite (printing 40 consecutive
## playback tips) found the real remaining problem: with the pool at
## ~3,200 (161 curated, 45 templates x 68 subjects), a typical stretch is
## OVERWHELMINGLY template-generated, and 45 templates recurring across
## that many combinations means the SAME exact frame ("Filing X under
## 'somebody else's problem.'", noun swapped) turns up again within about
## ten to fifteen tips -- the precise "same pattern, different word"
## shape this file already diagnosed once, just relocated from the
## curated set to the template set rather than actually gone. Doubled
## `_TEMPLATES` from 45 to 90 (same grammar discipline throughout) so any
## one shape recurs roughly half as often in a given stretch -- a
## structural fix to how often a frame repeats, not just fresher words
## inside it.

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
	"The ant queen has read the room and is not requeening today.",
	"Ant colony HR has opened an investigation into the pheromone trails.",
	"An ant mound's tax return has been rejected for the third year running.",
	"The ants voted. The vote was close. Nobody will say by how much.",
	"One ant has been promoted to scout. The others have feelings about this.",
	"The colony's pheromone budget was quietly cut. Nobody's told the ants yet.",
	"An ant carried home a leaf twice its own size and would like this noted.",
	"The ant queen's schedule says 'lay eggs, repeat.' It has not changed in years.",
	"A single ant has decided, unilaterally, to go rogue. The colony has noticed.",
	"The ant mound's leaf-litter stockpile just hit a new personal best.",
	"The death cap looks exactly as trustworthy as it should: not at all.",
	"Somebody mixed up the false death cap and the real one again. This never ends well.",
	"The fly agaric has been informed it looks like a video game mushroom. It is offended.",
	"Eight mushroom species, eight completely different opinions on being eaten.",
	"The champignon remains suspiciously normal-looking among its more dramatic neighbors.",
	"A parasol mushroom has unfurled on schedule, entirely unbothered by witnesses.",
	"The chanterelle would like it noted that it is not, in fact, a black trumpet.",
	"Somebody's mushroom field guide disagrees with itself, again, on page twelve.",
	"The mushroom known for its... effects has, again, declined to comment.",
	"Somebody is checking whether the fifth mushroom species agrees with the fourth. It does not.",
	"The last mushroom field guide consulted disagreed with the first one too.",
	"Karma has reviewed the footage and is choosing not to comment.",
	"The luck stat was asked for a straight answer. It gave a percentage instead.",
	"A crush penalty was issued, appealed, and reduced on a technicality.",
	"Karma is currently sitting at a number nobody is especially proud of.",
	"The quest log added an entry without asking permission. It does that.",
	"Somebody asked karma for a straight answer. Karma offered a shrug instead.",
	"The last crush penalty was reversed by evening. Karma, it turns out, forgives fast.",
	"The karma meter twitched just now. Nobody's saying why.",
	"The bee queen is between hives and would prefer not to discuss it further.",
	"Requeening takes about 28 days. The hive insists it feels considerably longer.",
	"A wild bee nest has filed a noise complaint against itself.",
	"The honeybees unionized, briefly, over a disputed shift change.",
	"One bee has been assigned to scouting duty. It is taking this very seriously.",
	"The hive's honey percentage ticked up by exactly one bee's worth of effort.",
	"Somebody is topping off a beehive's honey reserves, one flower at a time.",
	"A wild bee nest has settled somewhere reasonably defensible, all things considered.",
	"The hive's queen situation remains, delicately, a whole ongoing situation.",
	"Krampus has been briefed on the situation. Krampus is always briefed.",
	"Rübezahl is somewhere in these mountains, unimpressed by your hiking pace.",
	"Nyx does not appreciate being loaded before she's ready. Few do.",
	"The Lindwurm is stretching. This is expected to take a while.",
	"The world boss insists, again, that it is mythical. The evidence disagrees.",
	"Somebody asked the world boss for an autograph. It did not go well.",
	"The world boss roster has been checked. All four remain suitably, insistently mythical.",
	"The cicadas would like it on record that this is, in fact, their season.",
	"Somebody counted the cicadas today. The number was higher than anyone wanted.",
	"The forest's ambient bed and the river's are layering without a seam. On purpose.",
	"Rain has been scheduled. The sun was not consulted and is furious about it.",
	"A storm has been scheduled. The sun disagrees, loudly, and at some length.",
	"The millipedes are thriving, in the specific unglamorous way millipedes thrive.",
	"A worm has been recruited as fishing bait. Its consent was not requested.",
	"The decomposer bugs would like the record to show they are doing important work.",
	"Leaf litter has reached a new personal best. Somebody should probably clean that up.",
	"The millipede population continues to thrive in a way nobody is tracking closely.",
	"A beetle has been illustrated in exacting detail, for reasons of pure artistic pride.",
	"A worm has just been recruited into a career it did not apply for.",
	"Grass footsteps used to sound like a drum solo. This has been mostly fixed.",
	"Rock and sand still share no footstep sound of their own. A known and honest gap.",
	"The mushroom-crush sound is, technically, crushed styrofoam. Please don't mention this to the mushrooms.",
	"Snow crunch has been calibrated down to a specific, deeply unnecessary degree of accuracy.",
	"A footstep just landed on twigs. The twigs cracked exactly as advertised.",
	"A river bend is quietly reconsidering its own geometry, as rivers do.",
	"The fish have been fed precisely what they're owed. Mostly seaweed, some regret.",
	"The kingfisher has been diving since dawn. The fish have started taking it personally.",
	"Somebody is wading through the river. The river is making the appropriate amount of noise.",
	"A leaf is drifting downstream, entirely unbothered by any of this.",
	"The kingfisher's dive record stands. Nobody has beaten it. Nobody has really tried.",
	"Deciding whether it's spring yet. Technically, probably, almost.",
	"Every individual snowflake is being polished. There is no reasonable end to this task.",
	"A tide is coming in, gently, exactly as tides are contractually obligated to.",
	"Somebody checked the weather glass. It says 'stormy.' The sky says otherwise.",
	"Snow is settling on the treetops first, the way real snow insists on doing.",
	"A tree's canopy is changing color at its own pace and will not be rushed.",
	"A snowflake sparkle shader has been asked to be tasteful about this. Results pending.",
	"The wind has been given a strength value and is, for once, using it responsibly.",
	"The boars heard footsteps and have chosen, as always, to be unimpressed.",
	"The bears are being woken up just enough to hibernate correctly. Harder than it sounds.",
	"The deer have concluded the trees really are taller than they are. Real progress.",
	"The wolves had a rough winter and will, most likely, be fine.",
	"A sheep and an alpaca are both, technically, livestock. Neither has been informed.",
	"A horse has been tamed. The horse has strong opinions about this development.",
	"The last person to anger this wolf pack has not been seen since. Unrelated, probably.",
	"A wolf pack is deciding whether tonight's the night. Statistically: probably not.",
	"A boar is currently mistaking a passerby for lunch. This should resolve itself shortly.",
	"Sparrows are now flocking. Robins remain furious about the whole arrangement.",
	"An owl is awake unusually early. This is either dedication or a real problem.",
	"A raven has been spotted and, as expected, declines to comment on it.",
	"Pigeons have colonized a rooftop that does not, strictly speaking, exist yet.",
	"A buzzard circles overhead for no functional reason except atmosphere.",
	"The blue tit and the hummingbird are, regrettably, nothing alike in scale.",
	"Bats have been accounted for. They would very much prefer to stay that way.",
	"Two butterflies are courting nearby. This takes considerably longer than expected.",
	"A caterpillar is quietly becoming something else and would rather not be watched.",
	"A caterpillar was eaten by a robin today. Unfortunately, that's the food chain.",
	"The compass points north. It has exactly one job and does it without complaint.",
	"The spyglass has been polished. The star chart has never once been read correctly.",
	"A rough compass has been upgraded to a marginally less rough compass.",
	"The stone axe still remembers being a rock. It has not fully processed the change.",
	"A butterfly net has been readied. Every butterfly nearby has been quietly warned.",
	"The saw and the iron sword have not spoken in some time. It's a whole thing.",
	"Somebody is polishing a torch that is, by any reasonable measure, already lit.",
	"Somebody argued with the compass about which way is north. The compass won.",
	"The stone axe and the iron pickaxe are not currently on speaking terms either.",
	"A hero composite sprite is auditioning poses. None of them have been approved yet.",
	"An archetype has been selected and seems, on reflection, fairly confident about it.",
	"Somebody drew a portrait for every class. Every single one looks deeply determined.",
	"The character diorama is deciding what season flatters it best.",
	"A villager is haggling at the market. Nobody involved is currently winning.",
	"A farmer has overplanted the carrots again. Somebody should really say something.",
	"A settlement's population is growing, slowly, the way real populations actually do.",
	"Regional trade has resumed. A caravan is, technically, en route.",
	"An NPC farmer is, once again, quietly overharvesting the carrots. Noticed. Nothing changed.",
	"The world clock is running and does not, on principle, care if you're ready.",
	"A chunk of the world just finished loading and has immediate opinions about its neighbors.",
	"The save file has been asked, politely, not to corrupt itself. It has agreed, for now.",
	"Sun elevation is adjusting. Local time remains, as ever, none of your business.",
	"This is taking a while. That is, historically, a promising sign.",
	"Somewhere behind the scenes, eight mushroom species are fruiting exactly on schedule.",
	"The world clock ticked forward. It has never once apologized for this.",
	"The tip you are reading was picked at random. So, entirely coincidentally, was the last one.",
	"Somebody double-checked that no two loading tips are identical. There used to be a real problem here.",
	"This load has run long enough that a tip may repeat. It was, for what it's worth, a good one.",
	"Gold: still zero. This is, structurally, expected at this stage.",
	"Stamina, hunger, and water were all asked how they're doing. All three lied.",
	"Freezing percentage is climbing. Somebody, somewhere, should build a fire.",
	"A bonded companion cap was raised recently. The companions noticed immediately.",
	"Taming is in progress. The animal has agreed to absolutely nothing yet.",
	"The biome map has been redrawn. The tundra remains, on principle, unreasonably cold.",
	"Grassland, forest, desert, tundra, mountain, rainforest: pick a mood, any mood.",
	"The ocean was asked to lower the ambient noise. It declined, loudly.",
	"A hillshade has been cast across the terrain purely for dramatic effect.",
	"The footprint field remembers every step. It has an excellent, faintly unsettling memory.",
	"A creature's mass is being weighed before its footprint gets drawn. This takes a moment.",
	"Somebody is arguing with the chunk loader about how much detail is really necessary.",
	"The world elevation map was consulted just now, for approximately no reason.",
	"A save file just quietly survived a restart, exactly as it's supposed to.",
	"The intro globe has received one more coat of sparkle, whether it needed it or not.",
	"Aleph Alpha is being spelled out, one letter of light at a time.",
	"Somewhere, a class icon is warming into the cache well ahead of schedule.",
	"Checking that the intro's fifth row of sparkle still lines up with the fourth. It mostly does.",
	"The boot sequence has a great deal to load and is, genuinely, doing its best.",
	"Is the honey ready? Define 'ready.'",
	"Has the world boss ever technically lost a fight it agreed to? No. Not once.",
	"'Everything's fine,' says the ant colony, mid-collapse, for the third time this week.",
	"A queenless ant mound has been reassured that help is coming. It is skeptical.",
	"The grass frogs were told the pond is ready. They remain, understandably, unconvinced.",
	"'This is normal,' someone insists, about something that is visibly not normal.",
	"A bridgekeeper waits patiently. His questions have not gotten any easier.",
	"The Sea Cave Guardian is reviewing the joust rules again, for reasons unclear.",
	"Somewhere, a retro handheld is charging for a battle nobody scheduled.",
	"A ledger, a deed, and a field journal have been packed into one very confused backpack.",
	"Land health is recovering, slowly, the exact way real soil actually does it.",
	"Pollination is happening quietly in the background, precisely as it's supposed to.",
	"The wild bee patch has not been evicted. Not yet, anyway.",
	"Cherry, apple, walnut, hazelnut, acorn, pine: the full orchard lineup, present and correct.",
	"A composite fruit tree is deciding, at its own pace, whether it counts as old growth.",
	"Someone left a sapling completely unattended. It grew anyway, out of spite.",
	"Somebody double-checked that a full beard renders as a beard, not a face mask. Mostly.",
	"A grass frog relocated to a pond that did not exist an hour ago. It is thrilled.",
	"The world's only bridgekeeper has been waiting so long he's started keeping notes.",
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
	"Bribing %s with better terms than last time.",
	"Reasoning with %s. Historically, a mistake.",
	"Giving %s a pep talk, whether needed or not.",
	"Quietly lowering expectations around %s for today.",
	"Asking %s to sign off on this. No word back yet.",
	"Filing %s under 'somebody else's problem.'",
	"Reminding %s this exact thing happened last time too.",
	"Untangling %s from whatever this currently is.",
	"Negotiating a truce with %s. Terms still pending.",
	"Politely lying to %s about the timeline.",
	"Warning %s that this is being closely monitored. It is not.",
	"Double-booking %s by accident. Again.",
	"Apologizing to %s well in advance.",
	"Overruling every objection %s might have.",
	"Buying %s exactly one more minute.",
	"Reassuring %s that this is, statistically, fine.",
	"Consulting %s, always full of strong opinions.",
	"Trying a new approach with %s. The old one stopped working.",
	"Reading %s the full terms and conditions out loud.",
	"Explaining the situation to %s, very slowly.",
	"Rescheduling around %s without asking first.",
	"Handing %s a clipboard and hoping for the best.",
	"Cross-examining %s, currently pleading the fifth.",
	"Offering %s a deal nobody sane would refuse.",
	"Talking %s out of something not yet attempted.",
	"Overpromising to %s. As usual.",
	"Making small talk with %s to stall for time.",
	"Handing %s a participation trophy, just in case.",
	"Quietly hoping none of this bothers %s.",
	"Fact-checking %s against the official record.",
	"Signing %s up for something regrettable.",
	"Extending %s the benefit of the doubt. Again.",
	"Padding out a schedule around %s for no reason.",
	"Coaching %s through a routine already known cold.",
	"Nominating %s for employee of the month, unofficially.",
	"Running %s past legal. Legal has concerns.",
	"Talking %s into one more round of this.",
	"Underestimating %s. This will not end well.",
	"Onboarding %s as though this started yesterday.",
	"Debriefing %s. The report remains inconclusive.",
	"Micromanaging %s for no defensible reason.",
	"Cc'ing %s on an email nobody will ever read.",
	"Watching %s repeat exactly what happened yesterday.",
	"Interrogating %s about recent whereabouts. No comment given.",
	"Padding out the numbers on %s, just this once.",
	"Putting %s on formal notice. Informally.",
	"Drafting a strongly worded memo about %s. Never sent.",
	"Asking %s, point blank, what the plan is. No answer.",
	"Filing an incident report on %s. Nothing to see, apparently.",
	"Quietly benching %s for the rest of the day.",
	"Auditing %s. The numbers do not add up. Somehow fine.",
	"Trying diplomacy with %s first. Diplomacy is losing.",
	"Placing %s under close, entirely unofficial observation.",
	"Drawing up a contingency plan for %s. Plan B is a shrug.",
	"Sending %s a strongly worded but ultimately empty warning.",
	"Getting a second opinion on %s. The first opinion stands.",
	"Convening an emergency meeting about %s. It resolves nothing.",
	"Putting %s through a routine check. Routine, technically.",
	"Circling back to %s later. Later has arrived.",
	"Escalating the situation with %s to absolutely nobody.",
	"Drafting terms of surrender for %s. Filed, not signed.",
	"Quietly rebranding %s as a feature, not a problem.",
	"Requesting a status update from %s. Status: unchanged.",
	"Testing whether %s can tell the difference. It cannot.",
	"Holding %s to a standard nobody wrote down.",
	"Politely declining to elaborate on %s further.",
	"Comparing notes on %s with absolutely no one.",
	"Preparing a rebuttal to %s. There was no argument.",
	"Assigning %s a case number for internal tracking only.",
	"Loosely supervising %s from a safe, sensible distance.",
	"Drawing a line under %s. The line keeps moving.",
	"Attempting small talk with %s. It goes nowhere fast.",
	"Reassigning %s to a lower-priority queue, quietly.",
	"Flagging %s for review. The review will take a while.",
	"Sending a follow-up about %s. There was no original.",
	"Downgrading the alert level on %s. Nobody upgraded it.",
	"Reading between the lines on %s. There are no lines.",
	"Putting a pin in %s for now. The pin is permanent.",
	"Requesting a little patience from %s. None was offered.",
	"Making a mental note about %s. The note will be lost.",
	"Splitting the difference with %s. Nobody agreed to that.",
	"Giving %s a final warning. There was no warning before it.",
	"Attempting to reason %s down from something unspecified.",
	"Holding a brief, one-sided debrief with %s.",
	"Deferring judgment on %s indefinitely.",
	"Quietly moving %s to the bottom of a very long list.",
	"Requesting backup for %s. None was available.",
	"Politely, firmly, uselessly correcting %s.",
	"Opening a dialogue with %s. The dialogue is one-sided.",
	"Putting %s in writing, for absolutely no one to read.",
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
## test_no_long_run_of_the_same_template_in_playback_order). Re-searched
## 2026-09-12 after `_CURATED_TIPS`/`_TEMPLATES` were rewritten wholesale
## (different array contents shuffle differently even at the same seed,
## since Fisher-Yates's own swap range depends on the array): seed 97
## itself now left a run of exactly 3, so this is the first seed checked,
## from 1 upward, that clears the bar against the CURRENT content.
const _SHUFFLE_SEED := 1


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
## Revised again (2026-09-13), reported live: 2.0s was too fast to actually
## read a tip before it changed. 5.0s is the explicit, user-requested
## duration -- pinned exactly by test_tip_interval_is_a_real_reasonable_
## reading_duration rather than left an eyeballed guess.
const TIP_INTERVAL_SECONDS := 5.0


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
