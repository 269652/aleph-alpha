# Taming

How a wild animal becomes a working animal: approached without spooking it,
caught with a rope, held while it fights you, and then won over by feeding it —
not clicked once and converted.

This doc was overhauled after a live play session
(`docs/playtests/2026-08-26-taming-breeding-session.md`) in which the player
could reach every stage of the loop and still felt like a spectator at all of
them. The loop is real and it works; what it lacked was a player inside its
dramatic beats. The catch resolved as a silent dice roll, the feed happened by
standing still, and every verb picked its own target. Those three sections are
new or rewritten. The trust/hunger-gating, break-free, fatigue, predator-gating
and mount reasoning below is unchanged, because it was right.

## Design pillars

- **Taming is a relationship over time, not a transaction.** The lasso only
  buys you the chance to start; trust is earned by turning up when the animal
  is hungry, repeatedly. An animal you caught an hour ago and ignored is still
  wild.
- **The animal fights back, and strength decides.** A healthy horse should
  usually break a first throw. Wearing an animal down is a real (if brutal)
  strategy, and so is picking a weaker individual — the same
  individual-variation the roster already models (`CreatureInfo` levels, health).
- **Every dramatic beat is a beat the player is *in*.** This is the pillar the
  first version failed. A struggle the player watches resolve, a feed that
  happens because they stood still, a verb that picks its own target — each of
  those is the simulation acting *at* the player. If the animal is about to
  win or lose, the player's hands are on the rope; if the animal eats, the
  player offered; if a key fires, the player chose who it was aimed at.
- **The animal is an agent, and it may say no.** A refused offer is not a
  failure state, it is information: this animal is not hungry, or does not eat
  that, or does not trust you enough to take it from your hand yet. An animal
  that can only accept is a vending machine.
- **A tamed animal is an individual, not a species instance.** It has a name
  the player gave it and a history that happened, and the same animal comes
  back after a reload — not a fresh roll of the same species with a trust
  number pasted on.
- **Nothing is instant and nothing is hidden.** Catching, holding, tying and
  feeding are all things the player watches happen, with the animal's state
  legible on the animal itself (see "What the player can see"). This follows
  `flora.md`'s "what is visible must be what is real": if the animal is hungry,
  that is a fact the simulation holds and the player can read. The corollary
  cuts the other way too — what the *player* knows is also real and separate
  from what the simulation knows, which is why a preference is displayed only
  after it has been discovered.
- **A tied animal is a placed object in the world.** Tying the rope to a tree
  is what makes taming compatible with actually going away and doing something
  else — the world keeps simulating (see `ecosystem_dynamics.md`), so the
  animal gets hungry on its own schedule while you are gone.

## Real-world grounding

Traditional horse-breaking and modern natural horsemanship both work in the
order this models: **approach → restrain → hold → habituate → reward**. The
rope halter comes first and does not itself tame anything; it prevents flight.
Trust is then built by being the source of food and by repetition over days,
not by a single feed. A well-fed, healthy animal resists restraint far more
effectively than a weak one, which is why the break-free chance is driven by
condition.

**Riding the rope.** A handler holding a fighting animal does not simply pull
harder. Bracing rigidly against a full-strength surge is how ropes part and
handlers get dragged; giving line at the peak of the pull and taking it back
as the animal tires is how the animal is held. That give-and-take is the whole
craft, and it is what the struggle section below turns into a contest — the
animal supplies the force, the handler supplies the timing.

**The flight zone.** Every prey animal has a distance inside which a human
becomes a threat, and it *shrinks with familiarity* — this is Temple Grandin's
flight-zone model and it is the reason a farm animal tolerates a stockman at
arm's length while the same species in a wild herd will not let you within a
hundred metres. That gives trust an expression far better than a bar: a
half-trusted animal simply lets you closer.

**You do not catch a prey animal by outrunning it.** No stockman, hunter or
horseman has ever worked that way, because a human on foot loses that race to
almost anything worth catching. What works is removing the animal's reason to
run: food it wants more than it wants distance, a posture that does not read as
a predator's, and time. That is not flavour — §0 shows it is also literally
true in this build's arithmetic.

**Refusal and preference.** Animals are neophobic about unfamiliar feed and
individually inconsistent about what they will take, which is why real
stockmen learn what a particular animal likes rather than reading it off the
species. A refused offer from a hand held too close, too fast, or attached to
someone carrying a tool is ordinary animal behaviour, not a bug.

Carrots are the canonical horse reward for good reason: high-sugar root
vegetables are strongly preferred by equines and are the traditional training
treat.

## Mechanism spec

### 0. Getting near it at all — owned by `animal_husbandry.md`

The live play session found the real entry barrier, and it is not the lasso.
Wild animals flee as you approach, and there is no bait, lure, crouch, stalk
or calming verb anywhere in the game. Closing the distance by walking is not
skill, it is luck about which way the animal happened to wander.

**A refuted explanation, recorded here so nobody rebuilds on it.** The obvious
reading is that `Player.LASSO_RANGE` (72.0, `scenes/player.gd`) sits *inside*
`CreatureMarker.SENSE_RADIUS` (80.0, `src/rendering/creature_marker.gd`), so a
wild animal could never be roped "by construction". **That is false**, and the
code refutes it: `CreatureMarker.FLEE_SPEED` is **40.0** against
`Player.BASE_SPEED` **80.0**. A fleeing animal moves at half the player's
nominal walking pace, so an 8 px gap closes easily — and
`test_the_measured_catch_rate_matches_the_model`
(`tests/unit/test_creature_marker.gd`) measures sixty real captures against a
real marker. Catching is demonstrably possible.

**The real cause: the player's speed is a product, not a constant.** What the
player actually moves at is `BASE_SPEED × current_speed_multiplier`, and that
multiplier is the product of four independent penalties, composed in
`Player._authority_step` (which is all `_physics_process` does — it delegates
straight to it):

```gdscript
current_speed_multiplier = (
    water_result.speed_multiplier
    * _weather_speed_multiplier()      # rain/storm, times the freezing penalty
    * _terrain_speed_multiplier(tile)  # TerrainPassability, driven by real slope
    * ConditionPenalty.speed_multiplier(survival.fitness)
)
```

Through most of the live session the HUD read **`Speed: 47%`** — autumn rain,
over vegetated ground, with a Cold/Freezing meter running. 0.47 × 80 = **37.6
px/s, which is below `FLEE_SPEED` 40.0**. At that point a healthy wild animal
is not merely hard to catch, it is *unrunnable-down*: it opens the gap
indefinitely and no amount of persistence closes it. Later in the same session
the multiplier rose to 75% (60 px/s) and the approach immediately became
viable. Nothing in the game connects those facts for the player. The HUD shows
a percentage; it never says *you are now slower than a sheep*. A player in
rain, in long grass, slightly cold, concludes that taming is broken — and for
that afternoon, functionally, it is.

**Pinned by** `test_a_player_slowed_by_weather_and_terrain_cannot_outpace_a_fleeing_animal`,
which composes a realistic weather × terrain × condition multiplier against
`Player.BASE_SPEED` and compares the product to `CreatureMarker.FLEE_SPEED` —
asserting the *relationship*, never either number, so retuning the freezing
slow or the slope curve cannot silently re-break the loop without failing here.
A companion, `test_an_unencumbered_player_outpaces_a_fleeing_animal`, pins
the other end so the test is a relationship and not a one-sided assertion.

**Why this is a stronger argument for the approach layer than the arithmetic
was.** If the barrier were a fixed 8 px, "widen the rope" would be a legitimate
fix. It is not. The barrier is that **chasing is the wrong verb to build the
mechanic on at all** — its viability is a function of four systems the player
is not thinking about, and it degrades to impossible without saying so. Bait
works regardless of your speed multiplier: the animal comes to the food. A
stalk closes distance without a foot race: the flight radius shrinks rather
than the gap being sprinted across. Patience costs time, which the player has.
Those three verbs are robust where a chase is brittle, and that is the reason
to build them.

**This doc does not build them, and must not.** The approach layer — scent and
wind, crouching, bait placed on the ground, per-species flight distance, the
wariness an animal carries between encounters, and the pressure-and-release
grammar that governs all of it — is specified in
[animal_husbandry.md](animal_husbandry.md)'s "The approach", which owns the
wild→handled transition for the whole game (grazing, pens, herding,
production). Taming is a *consumer* of that layer: it assumes the player has a
way to get inside `LASSO_RANGE` on a calm animal, and everything below starts
from the frame in which they have.

Two contracts run between the docs, and both belong to husbandry:

- The **flight radius is a function, not a constant** —
  `FlightDistance.radius(species, wariness, trust, crouched)`. Husbandry
  defines it, owns its signature and owns every test that pins it. This doc's
  §5 only explains what the `trust` input *means* to the player.
- **Bait on the ground is the pre-taming feed** — an animal that has eaten
  from a spot the player left food at is calmer at that spot next time. That
  is husbandry's mechanism; taming's `feed_treat` is the *hand-fed* version of
  the same act, and §4 below is where the two meet.

⬜ Unbuilt in both docs. Until it exists, taming's entry cost is luck, and on a
wet cold afternoon it is not luck but a wall.

### 1. The lasso, and choosing what it is aimed at

A craftable tool: **4 plant fibre → 1 lasso** (`CraftingRecipeBook`). Plant
fibre already comes from harvesting mature tall grass
(`EarthChunkManager.harvest_grass_near`), so the entry cost is a walk through a
meadow rather than a tech tree.

Held in hand, the lasso enables a **throw** at a creature within range. Range
is deliberately short — you have to close with the animal first, which is the
part that makes stalking a horse feel like something.

**The throw must be aimed.** Today it is not: `Player._throw_lasso` scans the
creature group and takes whichever tameable animal is nearest, and so do
`_nearest_tamed` and `_try_mount`. With two horses standing together the player
cannot say which one they mean, which makes a *herd* impossible in principle:
every multi-animal mechanic in this doc and in `animal_husbandry.md` is blocked
behind this one thing.

**The selection mechanism is [animal_husbandry.md](animal_husbandry.md)'s to
define** — "Choosing an animal" specifies a persistent, click-latched
`Player.selected_animal`, cleared when the animal dies or leaves range, drawn
with a selection ring, with hover-nearest as the fallback when nothing is
selected. It is pinned there by
`test_a_verb_prefers_the_selected_animal_over_a_nearer_one` and its regression
guard `test_with_nothing_selected_a_verb_still_takes_the_nearest`. **That is
the only spelling of that test anywhere**, and taming's three "nearest" call
sites (`_throw_lasso`, `_nearest_tamed`, `_try_mount`) are among its first
consumers. This doc adds no second selection rule and no second test name.

**What taming does own is what the animal offers to do.** The tooltip machinery
is already shared and already complete: `HoverTargetFinder`
(`src/rendering/hover_target_finder.gd`) resolves "what is under the mouse"
across one `"hoverable"` group; `CreatureMarker` is already in that group and
already answers `get_display_name()`; `World._update_hover_tooltip` reads both
and renders each entity's `get_hover_actions()` as a verb plus the live
keybinding glyph through `_hover_tooltip_text` (so a rebind shows immediately).
That scan is written defensively — `marker.get_hover_actions() if
marker.has_method("get_hover_actions") else []` — which is exactly why the gap
is silent rather than a crash.

Fifteen scripts join `HoverTargetFinder.GROUP_NAME`; **eleven implement
`get_hover_actions()`** — `choppable_tree.gd`, `carcass.gd`, `carcass_guts.gd`,
`dropped_item.gd`, `liftable_stone.gd`, `minable_ore.gd`,
`wild_crop_marker.gd`, `lumberjack_marker.gd`, `smashable_stone.gd`,
`diggable_rock.gd`, `collapsed_passage.gd`. **Four do not**:
`creature_marker.gd`, `fish_marker.gd`, `piscivore_bird_marker.gd` and
`ambient_flyer_marker.gd`. The other three are scenery you cannot act on with a
key, so the honest claim is narrower than "the only one" and no weaker for it:
**`CreatureMarker` is the only entity in the game the player has verbs for that
hovers with a name and no verb.**

- **`CreatureMarker.get_hover_actions()`** returns the verb this animal, in
  this state, would actually accept: "Lasso" on a wild tameable, "Order" and
  "Ride" on a tamed horse, "Offer" on anything holding still for food, nothing
  at all on a predator (`Taming.can_be_tamed` already knows). Roughly ten lines
  in a pattern used eleven times. It is also the honest answer to "why did
  nothing happen when I pressed R" — the tooltip stops offering a verb the
  animal will not take.

  **What the player presses:** nothing. They move the mouse over an animal and
  the world tells them which key does what to *that* animal. Pinned by
  `test_a_predator_offers_no_taming_verb` (the state-to-verb table's hardest
  case, and the one `Taming.can_be_tamed` already decides) and
  `test_a_tamed_horse_offers_ride_and_a_tamed_boar_does_not`.

### 2. The catch, and breaking free

A throw that lands puts the animal in a **restrained** state. It immediately
begins trying to break out, and keeps trying at intervals for as long as it is
restrained.

Break-free chance is driven by the animal's **condition** — its health
fraction scaled down by how tired it already is. Each failed attempt costs
**stamina**, not health: fighting a rope winds an animal, it does not wound it,
and a successful catch should not hand the player a nearly-dead horse as its
prize.

An animal that has fought itself to a **standstill gives up** and stops
fighting. That is how breaking an animal actually works, and mechanically it is
what makes the rest of taming possible: an exhausted animal that went on
rolling its floor chance forever would mean a horse tied to a tree is certain
to be gone by the time the player gets back with carrots.

The number that matters is the chance of holding the animal across the **whole**
struggle, not on one attempt — attempts repeat, so a per-attempt figure
compounds into something quite different. Getting that backwards shipped a
version where a "healthy animals usually win" per-attempt chance of 0.85
compounded to ~99.9% escape and nothing could ever be caught. The rate is
therefore pinned by *measuring* sixty real captures
(`test_the_measured_catch_rate_matches_the_model` in
`tests/unit/test_creature_marker.gd`), not by a formula: about one throw in
three lands on a fresh, full-strength horse, and a worn-down one is usually
held. `Taming.hold_chance` is deliberately labelled an *estimate* in its own
doc comment and reads optimistic against that measurement; the measurement is
the authority.

An animal that breaks free flees — `CreatureMarker._step_restraint` calls
`release()` and sets `_flee_direction` away from `_rope_anchor` with a fresh
`FLEE_COMMIT_SECONDS` commit, so it bolts in a straight line rather than
dithering. It is **not** currently any harder to catch again; see §2b.

### 2a. The struggle as a contest the player is in

This is the section the old doc named as its single honest gap, and it is the
biggest "mature versus watching" win available anywhere in taming.

**What happens today.** `CreatureMarker._step_restraint` counts up to
`STRUGGLE_INTERVAL := 1.2` seconds, then rolls one deterministic hash —
`hash("%d_%d_struggle" % [wander_seed, _struggle_count])` — against
`Taming.break_free_chance(condition)`. Either the animal is gone or it is not.
There is no animation, no sound, no rope tension, no window in which the player
can do anything, and no way to tell a near-miss from a comfortable hold. The
whole "the animal fights back" pillar resolves in a branch the player never
sees. And note the rope model already contains the missing vocabulary:
`RopeTether.is_taut` (`src/gameplay/rope_tether.gd`) is written and
unit-tested (`tests/unit/test_rope_tether.gd`) and has **zero production
callers** (verified: the symbol appears only in `rope_tether.gd` and that test)
— nothing in the game has ever needed to know the rope is tight, because
nothing has ever been dramatic about it.

**What replaces it.** The 1.2s tick stops being the resolution and becomes the
*trigger*: when it fires and the animal still has fight in it, the animal
enters a **surge** — a few seconds in which it plants, hauls directly away from
the anchor, and the rope goes taut. During a surge:

- A **tension** value, 0 to breaking, rises with the animal's pull and falls
  when the player gives line. It is drawn in world space above the animal,
  reusing `World._build_charge_meter`'s exact shape (a Background/Fill
  `ColorRect` pair fed a [0,1] fraction through the shared
  `HealthBar.fill_width`, positioned every frame through the viewport canvas
  transform in `_update_charge_meter`). A second meter of that shape is a copy
  of a pattern, not a new UI system.
- **What the player presses.** The player **braces** (holds the brace input) to
  plant their feet and refuse to be dragged, or **slackens** (releases) to give
  line. Bracing drives tension up faster; slackening lets it fall. One new
  entry in `src/gameplay/keybindings.gd`'s `ACTIONS` registry — 26 actions
  today, with `KEY_X` and `KEY_Z` both free — yields the InputMap binding, the
  rebind row and the tooltip glyph. It is a **level** action by
  [input.md](input.md)'s rule (bracing is a held state, not an event), so
  unlike `offer` in §4 it is read directly rather than latched.
- **Slack has a cost too**, which is what stops this being a hold-the-key
  check. Two ways to lose the animal:
  - **Tension reaches breaking** — you braced through the peak, the rope parts,
    and the animal is gone with the existing flee-commit behaviour.
  - **Tension sits at zero for the whole surge** — the animal reaches the end
    of a slack rope with its footing under it and walks itself out of the
    catch.
  - The winning play is neither: give line at the peak of the pull, take it
    back as the surge decays, and let the surge end inside the band. That is
    literally riding the rope, and it is a *timing* skill rather than a reflex
    or a stat check.
- **Bracing costs the player stamina**, spent through the meter that already
  exists and is already on the HUD (`SurvivalMeters.spend_stamina`; the bar is
  built in `World._build_survival_bar` and updated in
  `World._update_survival_bar`). A player out of stamina
  (`SurvivalMeters.is_exhausted`) cannot brace and must ride it out on slack.
  That gives the player a fatigue axis mirroring the animal's, so a long fight
  wears down *both* parties — which is the honest version of "wearing an
  animal down is a strategy with a cost".
- **While the rope is taut and the player is not bracing, the player is
  dragged** toward the animal. That is the visible price of slack and the
  reason the two options trade off in space as well as in tension.
- The animal is **doing something**, not standing there. Its `_current_action`
  becomes a struggle action for the duration and it hauls away from
  `_rope_anchor` through the ordinary `_advance_gated` step, so a surging horse
  still goes around a tree rather than through it. The rope line
  (`Player._build_rope_line` / `_draw_rope`, whose colour comes from
  `ROPE_COLOR`) recolours with tension. `RopeTether.is_taut` finally gets its
  caller: it is exactly the predicate the drag and the rope colour both need.

Surviving a surge costs the animal `Taming.STRUGGLE_FATIGUE` (0.25) exactly as
a failed attempt does today, so `fatigue_after_struggle`, `has_given_up` and
the entire existing exhaustion arc are untouched and their tests keep passing.
The new logic is a **pure model** in the house style — engine-free, no RNG held
inside, alongside `taming.gd` and `rope_tether.gd` — holding the tension
integration, the surge's pull-over-time shape, and the three outcomes.

**How the numbers get pinned.** Not by eye, and not by asserting a rise rate.
Two measured tests bracket the tuning, in the same manner
`test_the_measured_catch_rate_matches_the_model` already uses:

- `test_a_player_who_never_touches_the_brace_key_holds_the_same_share_of_animals_as_before`
  — sixty real captures with the brace input never pressed, asserting the hold
  count still matches the measured baseline. This is the compatibility
  invariant and the more important of the two: **the contest must not change
  the odds for a player who ignores it.** It may only reward one who plays it.
- `test_riding_the_rope_holds_more_animals_than_ignoring_it` — the same sixty
  under an ideal brace-and-give policy, asserting a strictly higher hold count.
  Skill has to be worth something measurable, or the meter is decoration.

The tension scale's own top is 1.0 by definition, which is a scale, not a
tuned value. The player's brace drain is pinned as a *consequence* by
`test_bracing_through_one_full_surge_costs_less_than_half_the_players_stamina`,
which measures the drain across one real surge rather than asserting a rate —
the threshold that matters is "you can hold two surges back to back but not
five", and that is a count, not a number.

⬜ Unbuilt. Everything in §2a is spec.

### 2b. What an escaped animal remembers

The old doc claimed (at its "The catch, and breaking free") that an animal
which breaks free "is harder to catch again for a while — it has learned what
the rope means". **That was never implemented**: `_step_restraint` sets a flee
heading and nothing else, and no per-individual memory of having been roped
exists anywhere.

It should exist, and it belongs with the individual-identity work in §6 rather
than as a floating modifier: an animal that has broken a rope carries that,
permanently and visibly. Concretely — it spooks at a longer distance from a
player holding a lasso specifically, it fights the first surge of a second
catch harder, and (once names exist) it is *recognisably the same animal*,
which is the point. Losing one becomes a story rather than a re-roll.

The longer-distance half rides on husbandry's `wariness` input to
`FlightDistance.radius` rather than on a second radius rule of taming's own —
one escape is exactly the kind of event that raises wariness, and this is the
one case where it must *not* fully decay. The escape memory is per-individual
state keyed to `wander_seed`, so it must survive the reload; that is §6's
persistence bump, and the field is listed there.

**What the player presses:** nothing, and that is the point — the consequence
is attached to a choice they already made (braced too hard, or walked away
mid-surge) and is collected the next time they meet that animal. Pinned by
`test_an_animal_that_has_broken_a_rope_is_harder_to_catch_the_second_time`,
measured as a difference in hold count across two runs of the same seed rather
than asserted as a modifier.

⬜ Unbuilt, and previously mis-stated as built.

### 3. Leading and tying

While restrained and held, the animal **follows the player** at rope length: it
is pulled along rather than choosing to come. This reuses the existing movement
gate (`CreatureMovementGate`) so a led animal still walks around trees rather
than through them. Leading is nothing more than an anchor that walks with the
player: `Player._hold_the_rope` pushes `restrain_to(position, false)` every
frame, and `CreatureMarker._apply_rope_limit` clamps the animal to
`RopeTether.ROPE_LENGTH` (44.0) *after* its own movement, so whatever the AI
did this frame, a rope is still a rope.

The loose end can be **tied to a tree**, which anchors the animal to that spot:
`_hold_the_rope` passes `_tie_anchor` instead, so it wanders only within rope
length of the anchor and cannot flee past it. Trees are already solid bodies
(`ChoppableTree`, found through `EarthChunkManager.solid_obstacles_near`), so
"tie it to that one" needs no new entity. This is what lets the player leave.
Untying returns it to being led.

Tying stays what it is — a genuinely good mechanic, and the one that makes
taming compatible with going and doing something else. The only change §2a
brings here is that a **tied** animal's surges pull against the tree rather
than the player, so an unattended animal resolves its own struggles exactly as
it does today. Bracing is something you can only do while you are holding the
rope. Walking away is therefore a real choice with a real cost: you keep your
hands free, and you give up the ability to help it stay caught.

### 4. Trust, and feeding as an offer that can be refused

A restrained animal has a **trust** value, 0 to fully tame. Trust rises **only
when the animal is fed while it is actually hungry** — feeding a full animal
does nothing, which is what stops taming being a matter of spamming carrots.
Since hunger rises on its own schedule (`CreatureNeeds`, at
`HUNGER_RATE_PER_SECOND`), taming is naturally paced across real time: turn up,
feed, come back later. This rule is the one the whole system rests on and it
stays exactly as it is (`Taming.trust_after_feeding`).

**Carrots** are the reward the system is tuned around. They come from the
meadow rather than from a farm: wild carrot is a real, visible plant that
grows and spreads among the grasses (see [wild_crops.md](wild_crops.md)) —
pulling a mature one is a swing-driven harvest, the same input as chopping a
tree or harvesting grass fibre. That deliberately puts the lasso and its
reward in the same place — a walk through a meadow equips you for the whole
loop. It takes several successful feeds to reach full trust
(`TRUST_PER_FEED := 0.2`, pinned as the resulting *count* by
`test_it_takes_several_hungry_feeds_to_tame_an_animal` in
`tests/unit/test_taming.gd`, not as the number).

**What is wrong today is not the rule, it is the gesture.** There is no feed
key. `Player._try_feed_lassoed` is called every frame from `_hold_the_rope`,
and it fires whenever the player is within `FEED_RANGE := 28.0` with a carrot
in the inventory. The player does not feed the animal; the player *stands near
it* and the simulation transfers a carrot. The single most relationship-shaped
act in the game is the one act the player never performs. Worse, a refusal is
invisible — `feed_treat()` returns false, the carrot is not removed, and
nothing is said, so the player cannot distinguish "not hungry" from "nothing
happened" from "I am too far away".

**The offer.** A new **`offer` action**, one entry in
`src/gameplay/keybindings.gd`'s `ACTIONS` registry — which is all it takes to
get an InputMap binding, a rebind row in the settings overlay, and a live key
glyph in every tooltip. It is an **edge** action by [input.md](input.md)'s rule
(offering is an event, not a state), so it joins `Player.MOMENTARY_ACTIONS`
and is consumed from the `InputLatch` (`src/gameplay/input_latch.gd`) — a
140 ms tap on the feed key must never be swallowed at 8 FPS, which is a real
frame rate in this build.

**What the player presses:** the offer key, holding out whatever food is in the
active hotbar slot, aimed at the selected animal (§1). **What the world does
back:** the player stands still with food extended, and the animal decides. The
offer is a held-out gesture with a beat to it, not an instant transfer.

**The animal may refuse, and the refusal says which refusal it is.** Four
answers, each with its own visible behaviour:

- **Not hungry** — it looks at the food and looks away. Nothing is consumed
  and nothing is learned. Already the rule; now it has a face.
- **Not that** — it comes close enough to sniff, then turns its head. This is
  the new axis. `CreatureInfo.DIET_BY_SPECIES` already decides at the species
  level whether a food is edible at all; anything outside it is refused flatly.
  Within the diet, each individual has one **favourite**, derived from its
  `wander_seed` by the same deterministic hash idiom `CreatureNeeds._stagger`
  already uses to give each animal its own place in the hunger cycle. A
  favourite is worth more trust per feed than a merely acceptable food, so
  finding it is worth the wasted carrots.
- **Not from you, not yet** — below a trust threshold the animal will not take
  food from a hand at all. It will take the same food **placed on the ground**
  and backed away from. Crossing that threshold — the first time it eats out of
  your hand — is the single most legible milestone in the whole loop, and it
  needs no number attached to it. (This is where taming meets
  [animal_husbandry.md](animal_husbandry.md)'s ground-bait mechanism; they are
  the same act at two distances, and husbandry's bait work — a per-item scent
  mixture, a nose for every keepable species, a `FOOD_BAIT` forage kind, and a
  `take_bait_at` so the food can actually be eaten — is what makes the
  ground-placed half real.)
- **Not like that** — an offer made while holding a weapon, or made from
  inside the animal's personal space at a run, is refused on principle and
  costs a little calm. That is the pressure-and-release lesson, taught by the
  animal rather than by a tutorial box.

**Accepted** means the animal **steps toward the player** to take it, and only
then is the food consumed and trust gained. The animal choosing to close the
distance is the reward frame — it is the moment the player can see that
something changed.

**How the player learns a preference: by offering.** Not from a tooltip and
not from a stat sheet. A refusal is a fact the player now knows about *this*
animal, and it is remembered on the animal (§6) and shown on its readout only
*after* it has been discovered. Displaying what the simulation knows rather
than what the player has found out would be the same mistake as showing a
trust bar over every deer in the world.

Numbers pinned as consequences, not as constants:

- `test_a_favourite_food_tames_in_fewer_feeds_than_a_merely_acceptable_one` —
  counts feeds to full trust under each, so the favourite's bonus is pinned by
  the difference in count.
- `test_offering_the_wrong_food_consumes_nothing_and_earns_nothing`.
- `test_a_barely_trusting_animal_will_not_take_food_from_the_hand` and its
  ground-placed counterpart.
- `test_an_offer_made_at_a_run_is_refused` — the **shy threshold** (the
  approach speed and posture above which an animal refuses contact) is defined
  in [animal_husbandry.md](animal_husbandry.md)'s "The approach", as part of
  the same pressure-and-release layer that owns crouch and wariness. This test
  asserts only that taming honours it.

### 5. Trust as a relationship, not a meter

Trust is a float from 0 to `TAME_TRUST := 1.0`, and today it is read as a
**boolean** in both of the places where it governs behaviour:
`Taming.accepts_orders` is `is_tame(trust)`, and `CreatureMarker.fears_players()`
is `not is_tame()`. So an animal at 0.8 trust — four carrots in, most of an
evening's work — behaves *identically* to one at 0.0: take the rope off and it
bolts from the person who fed it. The bar moves and nothing else does. That is
the definition of a meter rather than a relationship, and it is why the player
experiences the middle of the loop as waiting.

Four graded behaviours, all of them things the player can read off the animal
without looking at a bar:

- **Flight distance shrinks with trust.** [animal_husbandry.md](animal_husbandry.md)
  owns the function — `FlightDistance.radius(species, wariness, trust, crouched)`,
  where species sets the base, wariness multiplies up, and trust and crouch
  multiply down — and owns every test that pins it, including the single
  Schmitt-gap invariant `test_a_graded_flight_radius_never_dithers` (which
  checks that no composed radius reaches `FLEE_RELEASE_RADIUS := 120.0`, so the
  hysteresis that fixed the measured flee-dithering bug cannot invert). **This
  doc defines no second flight function and no second dither test.**

  What taming owns is what the `trust` input *means*: it is the animal's
  familiarity with this particular person, earned one hungry feed at a time,
  and its behavioural payoff is that a half-trusted animal simply lets you walk
  closer. This is Grandin's flight zone, it costs no UI at all, and it does
  something structurally important: **trust buys you the approach**, which is
  the loop's entry barrier (§0). Each animal you invest in gets easier to work
  with, so the loop feeds itself instead of restarting from zero every time —
  and, because bait and crouch are the other two inputs, the player's answer to
  a bad speed multiplier is never "run faster".
- **Startle instead of bolt.** Below full trust a sudden movement nearby makes
  the animal step back and re-settle, rather than committing to a full
  `FLEE_COMMIT_SECONDS := 1.1` flight. Startle chance falls as trust rises.
  This is what gives the player a *reading*: an animal that still flinches is
  not finished, and one that stops flinching is nearly there. The step-back
  distance is not a new constant — it is a fraction of the animal's own
  `FlightDistance.radius`, so it scales with species and trust like everything
  else, pinned by `test_a_startle_moves_the_animal_less_than_a_flee_does`.
- **Coming without being told.** Above a threshold and below full trust, an
  untied animal drifts toward the player when the player walks away — not the
  ordered `FOLLOW` behaviour, and at a far longer leash than
  `FOLLOW_DISTANCE := 28.0`; just a reluctance to be left. No order was given.
  The animal chose. That is the moment taming stops being a chore and it should
  happen *before* the loop completes, not as its reward. The threshold is not
  asserted as a number: the pair
  `test_a_mostly_trusting_animal_closes_the_gap_when_the_player_walks_away` and
  `test_a_barely_trusting_animal_stays_where_it_is_when_the_player_walks_away`
  pin the **ordering**, which is the only property that matters. (Spelled out
  rather than left as "…and one that does not": a half-written name is
  ambiguous against `test_a_barely_trusting_animal_will_not_take_food_from_the_hand`
  above, which is a different animal doing a different thing.)
- **Orders stay gated at full trust.** Unchanged, and deliberately so: a
  half-trusting animal is one you are holding by a rope, and a menu of commands
  for an animal that would leave if it could is a lie. What changes is that the
  space *below* the gate is no longer flat.

**Retiring `pet_loyalty.gd` — owned here.** `src/gameplay/pet_loyalty.gd`
exists, is fully unit-tested (`tests/unit/test_pet_loyalty.gd`), and has **zero
production callers** (verified: the symbol appears only in the file itself and
that test, which is also the only thing that instantiates it — its `feed`,
`neglect`, `will_follow` and `will_guard` are instance methods, not statics).
It holds exactly the graded thresholds this section needs —
`FOLLOW_THRESHOLD := 0.4`, `GUARD_THRESHOLD := 0.75`, and its own doc comment's
"a loyal-but-not-devoted pet won't fight for you" — plus a `feed`/`neglect`
pair that duplicates `Taming.trust_after_feeding`/`trust_after_neglect` with
different rates (`_FEED_RATE := 0.3` against `TRUST_PER_FEED := 0.2`;
`_NEGLECT_DECAY_RATE := 0.02` per second against a period-based decay past
`NEGLECT_SECONDS`). Two 0..1 relationship scales on the same animal is
precisely the parallel system CLAUDE.md forbids, and the two would drift apart
the first time either was tuned.

**Recommendation: fold and delete.** `Taming.trust` is the one that is
persisted, drawn, tested and live; move `PetLoyalty`'s one genuinely distinct
idea — a stricter threshold for fighting for you than for walking with you —
into `Taming` as a named threshold beside `accepts_orders`, and delete
`pet_loyalty.gd` with its test. Pinned by
`test_guarding_needs_more_trust_than_following`, which is an ordering between
two thresholds and therefore survives any retune of either.
[animal_husbandry.md](animal_husbandry.md)'s "Work" section is the consumer of
the guard threshold and references it; it does not re-specify it.
`docs/concept/pets.md` is the older status-less sketch these thresholds came
from, and is superseded by this cluster of docs.

### 6. A tamed animal, and who it is

At full trust the rope is no longer what is holding it, and the animal stops
being **afraid** of the player at all — worth stating explicitly because the
player is sensed as a threat by every wild creature, so a tamed animal that
kept that reflex would flee the person who tamed it.

A tamed animal accepts **orders**:

- **Follow** — travels with the player, using the same led-movement path,
  stopping short at `FOLLOW_DISTANCE` rather than at zero (a target of zero
  would have the horse shoving into the player forever).
- **Stay** — holds position, wandering only within `STAY_RADIUS`, without
  needing a tie.
- **Mount** — the player rides it, moving at the animal's speed rather than
  their own. Only species that can plausibly carry a person offer this
  (`Taming.RIDABLE_SPECIES` is `{"horse": true}`); a tamed boar follows and
  stays but is not a mount. The **rider stays the thing the player controls**
  and the mount is carried along underneath them, rather than handing control
  over to the animal — which keeps inventory, combat, survival and everything
  else working unchanged while mounted. A horse travels at a working trot, not
  a gallop: this is a world of real geography to travel *through* (see
  `exploration.md`), not to blur past. `MOUNTED_SPEED := 150.0` against
  `Player.BASE_SPEED := 80.0`, pinned as a ratio by
  `test_riding_is_faster_than_walking` rather than as a speed. (Note that
  `Player.current_speed()` returns `MOUNTED_SPEED` and is then multiplied by
  `current_speed_multiplier` like any other movement, so §0's weather and
  terrain penalties apply to a rider too — a horse does not exempt you from
  the mud, it just gives you more to lose to it.)

**And it gets a name.** Today `CreatureInfo._init` sets `display_name =
a_species.capitalize()` and `CreaturePanel.set_info` renders `"%s Lv.%d"`,
which is why the live session found four or five identical "Sheep Lv.4 / HP
31/31" cards stacked in the corner with no way to tell them apart — including
the one the player had spent the evening on. An anonymous stack is the opposite
of what this doc's pillars claim to build.

- **The player names it, once, at the moment it becomes tame.** Not
  auto-generated flavour — a real input, with a default offered so it can be
  dismissed in one key. That naming beat is the ceremony that marks the end of
  the taming loop; right now the loop has no ending at all, the bar just fills.
  Budget the standard window plumbing tax: any new overlay must be registered
  in `World._any_gameplay_window_open`, `World._close_gameplay_windows` and
  `World._unhandled_input`. `scenes/world.gd` is already 4,345 lines, so a new
  overlay is a real cost and a one-line inline prompt may be the better shape.
- **It remembers what happened to it.** Where it was caught, how many surges
  it fought before it gave up, what it has been discovered to eat, how long it
  has been kept, whether it has ever broken a rope (§2b). Surfaced on hover
  through `get_display_name()`/`get_hover_actions()` (§1) and in its own panel.
  None of this is a stat; all of it is a record of things the player did.
- **The panel must distinguish individuals.** `CreaturePanel` shows name,
  level and HP and nothing about the relationship. For an animal in the loop it
  should show the name, the trust state and the hunger/sick state that
  `CreatureMarker._update_taming_readouts` already computes for the world-space
  pips. Everything needed is already on the marker.

**Identity has to survive a reload, or it is not identity.**
`KeptAnimals` (`src/world/kept_animals.gd`, `FORMAT_VERSION := 1`) stores
`{species, position, trust, order, is_tied, tied_to}` through positional
`store_*` calls. It does **not** store `wander_seed` — which is the value that
derives the animal's `level` and `max_health` in `CreatureInfo._init`, its
needs stagger (`CreatureNeeds._stagger`), its struggle rolls, and (per §4) its
food preference. So the horse that comes back after a chunk unload is a
*different individual* wearing the old trust number. A named animal that is
statistically a stranger is worse than an unnamed one.

**The V2 record is defined once, in [animal_genetics.md](animal_genetics.md).**
That doc owns the complete field union, the V1→V2 upgrade path and the byte
budget (`test_the_v2_record_size_stays_within_the_measured_budget`), because it
is the doc that knows how large an ancestry list is allowed to get. Taming
requires these fields in it — `wander_seed`, the player-given name, which food
preferences have been discovered, kept-since time, and the escape memory (§2b)
— **plus the rest of the V2 record, defined in `animal_genetics.md`**. Taming
does not restate the layout and must not.

The format is versioned and round-trip tested precisely so that this is a bump
rather than a rewrite. Pinned from taming's side by
`test_a_kept_animal_comes_back_with_the_same_seed_and_therefore_the_same_level`
and by extending the existing round-trip test to the fields listed above.

**Separately and independently broken: New Game does not touch kept animals.**
`EarthChunkManager.KEPT_ANIMALS_DIR` (`user://chunk_kept_animals`) is absent
from `World.backed_up_directories()` *and* from `World._wipe_persisted_world()`
— which lists only `MODIFICATIONS_DIR`, `PLANTED_TREES_DIR`,
`FISH_POPULATION_DIR` and `ROOF_MODIFICATIONS_DIR` in both places. So New Game
neither backs up nor wipes tamed animals, and a previous world's horses turn up
standing in the new one. `ECOLOGY_DIR` (`user://chunk_ecology`) is missing from
both lists in exactly the same way.

**The existing test is correct and must not be "fixed".** An earlier draft of
this doc claimed `tests/unit/test_world_backup_paths.gd` "pins the wrong set".
It does not. `test_the_backup_lists_cover_exactly_what_the_wipe_destroys` reads
the source text of `_wipe_persisted_world` and asserts
`backed_up_directories().size() == body.count("_world_reset.wipe_directory(")`
— four entries against four calls, internally consistent, and deliberately
designed as a drift alarm. Adding `KEPT_ANIMALS_DIR` to the backup list *alone*
would break it, and breaking it would be the alarm working.

So the red-first move is a **new** test, not an edit to that one:

- `test_the_kept_animal_and_ecology_directories_are_wiped_and_backed_up_like_their_siblings`,
  in the same shape as the existing
  `test_the_roof_modification_directory_is_wiped_and_backed_up_like_its_siblings`
  — assert `_wipe_body()` contains
  `wipe_directory(EarthChunkManager.KEPT_ANIMALS_DIR)` **and** that
  `backed_up_directories()` has it. It fails on both halves today.
- The fix is therefore two edits, not one: add the directory to
  `backed_up_directories()` *and* add the matching `wipe_directory` call to
  `_wipe_persisted_world`. The drift test then passes because both counts moved
  together, which is exactly what it was written to enforce.
- `ECOLOGY_DIR` deserves the identical treatment and the identical test; it is
  the same bug with a different constant.

### 7. Neglect, and leaving

A tamed animal still eats, still gets hungry, and is still a creature in the
ecosystem rather than a vehicle.

**Neglect currently costs nothing, contrary to what this doc used to say.**
`Taming.trust_after_neglect` and `NEGLECT_SECONDS := 600.0` are written,
reasoned and unit-tested (`test_a_neglected_animal_loses_trust`,
`test_a_short_wait_is_not_neglect` and `test_neglect_cannot_push_trust_below_nothing`
in `tests/unit/test_taming.gd`) — and have **zero production callers**
(verified: the symbols appear only in `taming.gd` and its own test). A horse
tied to a tree and left hungry forever loses no trust at all. The old status
list marked this ✅. It was not true.

Wiring it is small, and it belongs here because `Taming.trust` is this doc's:
`CreatureMarker` already owns `_needs` and already runs a per-frame
restraint/order step, so it needs a `_hungry_seconds` accumulator that advances
while `_needs.is_hungry()` and is reset by `feed_treat()` — or, once
[animal_husbandry.md](animal_husbandry.md)'s Keeping section exists, by a real
graze or a full trough, which is husbandry's half of the same wire. **One test
name for the one mechanism**, shared with husbandry rather than forked:
`test_a_tied_animal_left_hungry_loses_trust`, which fails today because nothing
calls the function.

**A kept animal that is FREE to leave walks off and goes feral.** The old doc
also claimed a tamed animal "dies if neglected"; that is likewise unimplemented
— `CreatureMarker` reads `_needs.is_hungry()` only to gate foraging and the
hunger pip, and hunger never touches `info.health`, so nothing routes to
`_die()`. And death is the wrong answer for an animal that could have solved
its own problem: an animal that starves off-screen is a punishment the player
can only read about afterwards, and it is also implausible — a hungry animal
that is following you, standing where you told it to stay, or tied somewhere it
could be untied from has legs and a world full of grass. An animal that **walks
off and goes feral** — reverting toward wild behaviour, keeping its
`wander_seed` and its name, carrying its wariness of you — is a consequence the
player can act on, can meet again, and can watch refuse them. That is the same
design instinct as §2b's escape memory, and the two share their machinery: a
feral ex-pet is an animal with a rope memory and a name.

**A PENNED animal is the other case, and it belongs to husbandry.** A fence is
the player choosing to remove the animal's own option to solve the problem, and
that is exactly what makes penning a responsibility rather than free storage.
An animal that cannot walk to grass, and whose trough you never filled, does
starve — routed through `CreatureMarker._die()`.
[animal_husbandry.md](animal_husbandry.md)'s "Keeping: feed, water, shelter,
neglect" owns that outcome and its test; this doc does not restate it.

One correction to an earlier draft of this section, which claimed the starved
animal "leaves a real carcass and joins [carrion.md](carrion.md)'s loop":
**it does not, yet.** `LootTable._DROPS` has rows for `herbivore`, `boar`,
`predator` and `lynx` only, and `CreatureMarker._spawn_carcass_if_eligible`
returns immediately when `drops_for` comes back empty — so a starved sheep,
goat or horse currently vanishes without a trace. Giving the keepable species
their own drop rows is a named prerequisite in
[animal_husbandry.md](animal_husbandry.md), not something either doc may
assume. Until it lands, penned starvation has no visible remains, which would
make the one consequence that is supposed to teach the lesson invisible. The two
outcomes are not a contradiction, they are the same rule — *the animal takes
the best option available to it* — evaluated in two situations the player
created. Free animals leave; penned animals cannot.

Pinned from this side by `test_a_kept_animal_left_hungry_long_enough_walks_off`,
which measures the elapsed hungry time until departure rather than asserting
the constant, `test_a_penned_animal_cannot_walk_off` (the boundary between the
two rules, and the reason husbandry's starvation case exists at all), and
`test_ordinary_play_never_triggers_it` — walking off to find carrots and coming
back must never cost anything, which is the whole reason `NEGLECT_SECONDS` is
as long as it is.

**What the player presses:** the offer key, before the timer runs out. **What
the world does back:** if they do not, they come back to an empty tree, a
snapped-off rope, and — eventually, somewhere in the same region — an animal
that knows them and will not let them close.

## What the player can see

- The **rope** itself, drawn between the player (or the anchor tree) and the
  animal, so "this animal is on a line" is never ambiguous — and recoloured
  with tension during a surge, so "this animal is winning" is not either.
- A **rope-tension meter** in world space above a struggling animal, the same
  shape as the held-item charge meter (`World._build_charge_meter`).
- The **selected animal** ringed (husbandry's selection, §1), and a hover
  tooltip naming it and the verb it would accept — so the player knows which
  animal a key press is aimed at before pressing it.
- A **hunger indicator** above a restrained or tamed animal when it is hungry —
  the cue that it is time to feed it. Hunger already exists in the simulation
  (`CreatureNeeds.is_hungry`); `_update_taming_readouts` already shows the pip
  and already gates it on the animal being "in the loop" (restrained, or trust
  above zero), so a deer in a field does not wear a progress bar.
- A **trust indicator** showing progress toward tame, so the player can tell
  that feeding is doing something. It is a supplement to the graded behaviours
  of §5, never a substitute: an animal that has stopped flinching has told the
  player more than the bar has.
- A **sick indicator**, the same shape as the hunger pip, when a kept animal
  is carrying a disease (see [disease.md](disease.md)) — an animal you've
  invested trust in reads as sick the instant it happens, not as a silent
  population-level stat.
- The **refusal** itself: a head turned away, a sniff and a step back, a shy.
  A refused offer must never be silent, because a silent refusal is
  indistinguishable from a bug — and that is exactly what the current
  proximity feed produces.
- The animal's **name and its history** on its panel and its tooltip, so a
  handful of kept animals are individuals rather than a stack of identical
  cards.
- **Why you cannot catch anything right now.** §0's finding is invisible today:
  the HUD shows `Speed: 47%` and never connects it to the animal walking away
  from you. Whatever form this takes — a line on the speed readout when the
  composed multiplier drops the player below `FLEE_SPEED`, a note in the lasso
  banner — the rule is [hud.md](hud.md)'s and this doc only states the
  requirement: **a mechanic that has become impossible must say so.**

## What this doc does not cover

- **The approach layer** (bait, crouch, flight distance, wariness) —
  [animal_husbandry.md](animal_husbandry.md), §0.
- **Selection and the pen, keeping, breeding, production and work** —
  [animal_husbandry.md](animal_husbandry.md).
- **What a bred animal inherits, and the `KeptAnimals` V2 record** —
  [animal_genetics.md](animal_genetics.md), §6.
- **Hunting** — tracking, traps, and the choice between catching an animal and
  killing it, has no spec anywhere and is **deliberately deferred**. It becomes
  worth writing the moment husbandry's mortality term lands, because that is
  when killing a wild animal first has a consequence the region notices. Naming
  it here so it is a known hole rather than an oversight.

## How much of this is verified

Every code fact in this document was read directly out of the tree in the
session that wrote it. **No test named here was executed**: Godot is not on
PATH in this environment, so the existing suite could not be run and none of
the new tests could be driven red. Every ⬜ below is spec, and every ✅ is a
claim about code that was read, not about a test run that was watched.

`tests/` contains only `unit/` — there is no integration layer. Almost every
mechanism specified here is cross-node (surge → tension → rope → player drag;
offer → refusal → trust → flight radius). The repo's existing answer to that is
`tests/unit/test_creature_marker.gd`, which builds a real marker and runs real
frames — `test_the_measured_catch_rate_matches_the_model` is exactly that
shape — and it is the pattern every measured test above should follow, with the
pure models (`taming.gd`, `rope_tether.gd`, the new tension model) covered
headlessly beside it.

## Iterating on any of this

There is no `/tame`, `/kept` or `/breed` console command, so the only route to
a tamed animal is a real throw at roughly one-in-three odds followed by five
hunger-gated feeds — after first solving §0 by luck. Every mechanism in this
doc is slow to test by hand as a direct result, which is a design risk in its
own right: an author who cannot reach a state cheaply will not tune it
honestly. A `/tame <trust>` that sets trust on the selected animal and a
`/kept` that lists the roster are small. `World._on_console_command` is a plain
`match` on the command name, and `ConsoleCommandParser.parse` already hands it
a name plus args — it splits on spaces with no quoting, so **no argument may
contain a space**, which is why naming an animal is an in-world input and not a
console argument. Note that the dispatch itself currently has no test at all;
adding one along with the first new command is the cheap moment to fix that.

## The dead duplicate

`src/gameplay/taming_system.gd` has **zero callers outside its own test**
(`tests/unit/test_taming_system.gd`) — verified. `docs/progress.md`'s
"Pets (`concept/pets.md`)" section nonetheless calls it "the Taming System" and
marks it 🚧 under a heading that claims "No pets/taming system is wired into
live gameplay", which is also false: the loop in this document is live and
playable.

**Recommendation: delete `taming_system.gd` and its test, and correct
`docs/progress.md`.** `taming.gd` is the live model, it is what this doc
specifies, and it is what every test that matters exercises. Leaving a second,
differently-shaped taming model in the tree means every future reader has to
work out which one is real — and the rot has already spread. Six doc comments
in live files cite `TamingSystem.attempt_tame`/`taming_chance` as the house
pattern for a deterministic `(chance, seed_value)` roll:
`src/gameplay/disease_model.gd` (two), `src/gameplay/sickness.gd` (three) and
`tests/unit/test_player.gd` (one). Two concept docs do the same
([disease.md](disease.md), twice). That is how a dead file becomes load-bearing
documentation.

Repoint those citations at `Taming` — which uses the identical hash-roll idiom
in `CreatureMarker._step_restraint` — **before** removing the file. And note
that `docs/progress.md` cites `TamingSystem` in a second, unrelated place (the
disease entry's "same deterministic hash-seeded roll pattern as
`Sickness`/`TamingSystem`"), so a checklist that greps for the name and expects
one hit will be wrong; both sites need repointing.

## Status / mechanisms

**Built and live:**

- ✅ `Lasso` item + 4× plant fibre recipe, and the `Carrot` item, both with
  their own art
- ✅ Throw/catch interaction from the held lasso (`Player._throw_lasso`, one
  key that throws / ties / unties / releases depending on what you are holding)
- ✅ Break-free model driven by condition, with per-attempt stamina cost
  (`Taming.break_free_chance` / `fatigue_after_struggle` /
  `effective_condition`), with the rate pinned by measuring sixty real
  captures (`test_the_measured_catch_rate_matches_the_model`)
- ✅ Restrained state on `CreatureMarker` — a caught animal stops making its
  own decisions, cannot flee, and fights the rope on its own clock
- ✅ Give-up on exhaustion (`Taming.has_given_up`), without which a tied animal
  eventually always escapes and taming can never be completed
- ✅ Leading at rope length, through the existing movement gate (`RopeTether`,
  `CreatureMarker._apply_rope_limit`), so a led animal walks around a tree
  rather than through it
- ✅ Tying the loose end to a tree; the anchor simply stops moving with the
  player, so the animal grazes around its tree instead of following
- ✅ Trust rises only on feeding a HUNGRY animal (`Taming.trust_after_feeding`,
  `CreatureMarker.feed_treat`) — the rule the whole system rests on
- ✅ Hunger + trust indicators on the animal, gated to animals actually in the
  loop (`_update_taming_readouts`), and a state line in the HUD
- ✅ A third sick pip beside them, shown while a kept animal is `INFECTED`
  (see [disease.md](disease.md), `CreatureMarker._sick_pip`) — same
  "already in the loop with the player" gating as the other two
- ✅ Tamed orders: follow / stay, cycled with the lasso key once the animal is
  tame (the rope has nothing left to do at that point, so the key changes
  meaning). A tamed animal also **stops treating the player as a threat** —
  players are sensed as threats, so without that a horse you spent five
  carrots taming would have spent the rest of its life fleeing from you
- ✅ Mounting (horses only): the rider stays the node the player controls and
  the mount is carried along with them, so inventory, combat and survival all
  keep working unchanged while riding
- ✅ Carrots have a source: **wild carrot** (Daucus carota) is a real,
  visible meadow plant that grows, spreads, and is pulled directly —
  `WildCropPatch`/`WildCropMarker`, see [wild_crops.md](wild_crops.md) —
  superseding the earlier grass-harvest freebie. The same meadow that
  supplies the lasso also supplies the reward
- 🚧 Persistence: a tamed, part-tamed or tied animal is kept across chunk
  unload and across sessions (`KeptAnimals` FORMAT_VERSION 1), re-spawned where
  it was left with its trust, its order and whatever it was tied to.
  Deliberately stored outside the region's aggregate population: a herd is a
  number and one deer is much like another, but the horse the player spent an
  evening winning over is a particular animal in a particular place — and the
  aggregate is capped at carrying capacity, so rolling it in there could see it
  culled to make room for wild deer. Kept animals are therefore EXTRA: carrying
  capacity governs wild animals, not the ones the player is looking after.
  **Known gap:** `wander_seed` is not among the saved fields, so a reloaded
  animal is a statistically different individual carrying the old trust number
  (§6). Downgraded from ✅ on that basis.

**Corrections to this document's previous claims:**

- ⬜ Trust decay on neglect. `Taming.trust_after_neglect` /
  `NEGLECT_SECONDS` exist and are unit-tested but have **zero production
  callers** — neglect currently costs nothing. This entry was previously
  marked ✅; that was false.
- ⬜ An escaped animal being harder to catch again. Previously asserted in
  prose as though implemented; `_step_restraint` sets a flee heading and
  nothing more. No per-individual rope memory exists (§2b).
- ⬜ A tamed animal dying if neglected. Previously asserted in prose;
  a tamed animal's hunger never reaches its health. §7 specifies **leaving**
  for an animal that is free to leave, and hands the penned starvation case
  to [animal_husbandry.md](animal_husbandry.md).
- ✏️ **The approach barrier was mis-diagnosed.** An earlier version of this
  section argued that `SENSE_RADIUS` (80) exceeding `LASSO_RANGE` (72) made a
  wild animal uncatchable "by construction". That is refuted by `FLEE_SPEED`
  (40.0) against `BASE_SPEED` (80.0) and by sixty measured captures. The real
  cause is the composed `current_speed_multiplier` dropping the player below
  `FLEE_SPEED` (§0). Recorded rather than deleted, because the wrong version
  was load-bearing for four proposed subsystems and anyone re-deriving it
  should meet the refutation.
- ✏️ **The backup test was mis-diagnosed.** An earlier version said
  `tests/unit/test_world_backup_paths.gd` "pins the wrong set". It does not —
  it is a correct drift alarm, and the fix is a new test plus matching
  `wipe_directory` calls (§6).

**Specified here, not built:**

- ⬜ The struggle as a contest — surge, rope tension, brace/slacken, player
  stamina cost, drag, world-space tension meter, a visible struggle action on
  the animal (§2a). This was the previous status list's one honest ⬜ ("the
  struggle is resolved silently; it has no animation of its own") and is now
  specified rather than merely admitted. `RopeTether.is_taut` (zero production
  callers) and `World._build_charge_meter` are the existing pieces it reuses.
- 🚧 Feeding as a deliberate act. **Done (2026-08-28):** it is a gesture now --
  `Player.offer_treat_to`, reached from the primary action slot while holding
  the food. The old `_try_feed_lassoed` fired from proximity every frame, so
  the relationship the whole mechanic rests on reduced, in play, to standing
  still next to a horse; a test now pins that walking past your own tied hungry
  animal with carrots in the bag feeds it nothing.
  **Still ⬜:** refusal, per-individual food preference, ground-placed versus
  hand-fed, and discovery-by-offering (§4). The animal can decline a feed it is
  not hungry for, but it cannot yet decline one it simply does not want from
  you.
- ✅ `CreatureMarker.get_hover_actions()` — implemented, delegating to
  `AnimalActions.for_animal`, so hovering an animal finally offers verbs the
  way hovering a pebble always did. The ORDERING is the substance: the primary
  slot is whatever the animal's own state most needs -- a tied hungry horse
  with food in your hand offers Feed ahead of Ride. Two context slots
  (`primary_action`/`secondary_action`) reach whichever verbs are offered, and
  every verb keeps its own dedicated key; the slot routes into the same handler
  rather than a copy of it (`Player.perform_rope_verb`).
- ✅ An animal's condition is readable at all — `CreatureMarker.animal_state()`,
  one reporter feeding the creature card, the hover tooltip and the rope
  banner. Trust, food, water and warmth all read 1.0 = fine, 0.0 = trouble,
  including food and water, which the simulation stores the other way round as
  deficits; a test pins that a starving animal reads LOW. The card shows the
  full percentages only for an animal the player has a stake in
  (`is_player_invested`), so a meadow of wild sheep stays a column of small
  cards. Warmth is new: animals had no temperature at all while the player
  standing beside them had a full one, so they now run the SAME
  `SurvivalMeters` model against the same `EarthChunkManager.ambient_warmth`.
- ✅ Prompts name their key. The banner read "press the lasso key", which is
  not a key any keyboard has; `Keybindings.display_key_for` reads the live
  InputMap so a rebind shows at once. The **selection** it feeds is
  [animal_husbandry.md](animal_husbandry.md)'s, pinned there by
  `test_a_verb_prefers_the_selected_animal_over_a_nearer_one`; taming's three
  "nearest" call sites are its consumers.
- ⬜ Graded trust: startle-instead-of-bolt, coming without being told,
  hand-feeding threshold (§5). Trust is currently read as a boolean in both
  places where it governs behaviour. The flight-distance half is husbandry's
  `FlightDistance.radius(...)`; taming supplies the `trust` input's meaning and
  defines no second function.
- ⬜ Bond and identity: player-given name, remembered history, an individual-
  distinguishing panel (§6), and the taming-side fields of `KeptAnimals`
  FORMAT_VERSION 2 — `wander_seed`, name, discovered preferences, kept-since
  time, escape memory — **plus the rest of the V2 record, defined in
  [animal_genetics.md](animal_genetics.md)**.
- ⬜ Neglect wired to a consequence, and a free kept animal going feral (§7).
  The penned-starvation counterpart is
  [animal_husbandry.md](animal_husbandry.md)'s.
- ⬜ The approach layer — bait, stalking, calm/spook state, per-species flight
  distance. **Owned by [animal_husbandry.md](animal_husbandry.md)**, not by
  this doc; taming depends on it and is gated behind it in practice, because a
  player whose composed speed multiplier drops them below `FLEE_SPEED` cannot
  close the distance on foot at all (§0).
- ⬜ Any in-game signal that the approach has become impossible ("What the
  player can see").
- ⬜ `/tame`, `/kept` console commands, and any test at all for
  `World._on_console_command`.

**Repairs owed:**

- ⬜ `KEPT_ANIMALS_DIR` (and `ECOLOGY_DIR`) added to **both**
  `World.backed_up_directories()` and `World._wipe_persisted_world()`, driven
  by a new `test_the_kept_animal_and_ecology_directories_are_wiped_and_backed_up_like_their_siblings`
  in the shape of the existing roof-directory test. The existing drift test is
  correct and stays as it is. Until this lands, New Game neither backs up nor
  wipes tamed animals, and a previous world's horses turn up in the new one.
- ⬜ `src/gameplay/taming_system.gd` deleted, its test deleted, the six live-file
  doc comments and two [disease.md](disease.md) citations repointed at
  `Taming`, and `docs/progress.md`'s "Pets" section corrected — it claims no
  taming system is wired into gameplay and names the dead file as the real one.
  A second `docs/progress.md` citation, in the disease entry, needs repointing
  too.
- ⬜ `src/gameplay/pet_loyalty.gd` folded into `Taming` (its guard-versus-follow
  threshold kept as a named constant beside `accepts_orders`, pinned by
  `test_guarding_needs_more_trust_than_following`; the file and its test
  deleted), rather than becoming a second 0..1 relationship scale on the same
  animal (§5).

## Editor's note

Two places where the coherence audit itself is off, corrected above rather than
carried through:

1. **The hoverable count.** The audit states "17 scripts join
   `HoverTargetFinder.GROUP_NAME`". The actual count is **15**
   `add_to_group(HoverTargetFinder.GROUP_NAME)` call sites (no `.tscn` file
   adds the group, and `hover_target_finder.gd` itself only declares
   `GROUP_NAME := "hoverable"`). The audit's substantive point is correct and
   is what §1 now says: 11 implement `get_hover_actions()`, and four do not —
   `creature_marker.gd`, `fish_marker.gd`, `piscivore_bird_marker.gd`,
   `ambient_flyer_marker.gd`.
2. **A line-number nit that reverses the right answer.** The audit's P6 table
   says `creature_info.gd:346` (`display_name`) should be `:345`. It is at
   **346**; `:345` is `species = a_species`. The draft was right and the audit
   was wrong there. Its other nit in the same row is correct — level and
   max_health are at `:351`/`:353`, not `:352-354`. Both are moot above,
   because per the arbitration this doc now cites `CreatureInfo._init` by name
   and carries no line numbers for anything that moves.
