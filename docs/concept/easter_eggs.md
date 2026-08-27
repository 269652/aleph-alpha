## Easter eggs: hand-placed, not emergent — deliberately

A small, separate content category: hidden, non-canonical curiosities
placed at real-world coordinates, behind secret console commands, or
gated on real calendar dates — pure delight, zero mechanical weight.
Prompted directly by a fun request: Gyarados-and-friends lurking in the
Bermuda Triangle, plus Ready Player One and the tangle of 80s pop culture
*it* references.

### Design pillars

1. **Hand-placed on purpose — the one deliberate exception to this
   project's "emergent, not placed" rule.** World bosses
   ([worldbosses.md](worldbosses.md)), ancient trees
   ([flora.md](flora.md#ancient-trees-emergent-legendary-flora)), and
   regional mythology (worldbosses.md's own brainstorm) are all explicitly
   *never* hand-placed — a genuinely different design axiom governs
   this doc, and it's worth naming rather than quietly contradicting: an
   Easter egg's entire appeal is that it's the **same** discovery for
   every player, at a **fixed**, findable spot — "I found the thing at
   coordinate X" is a shared, comparable moment, not a per-world roll.
   Emergent-vs-placed isn't a universal rule this project follows blindly;
   it's the right default for *simulation content*, and the wrong one for
   *cultural in-jokes*. Both can be true at once.
2. **Zero mechanical weight.** Cosmetic, flavor-text, or at most a tiny
   harmless effect (a silly item that does nothing useful, a one-line
   console response) — never a stat boost, never optimal-strategy
   material. An Easter egg that's also the best gear in the game stops
   being a delight and starts being a wiki page. Keeps this whole category
   exempt from the balance/testing rigor the rest of the game rightly
   demands.
3. **Undocumented in-game, on purpose.** No quest marker, no glowing
   waypoint, no hint system pointing at these — discovery is the reward.
   (This doc itself existing is the one necessary exception — someone has
   to write down what to build.)
4. **Homage over reproduction — the IP-safety default.** Real, trademarked
   characters/creatures (Pokémon chief among them) don't get reproduced by
   name or design; they get an affectionately on-the-nose **original**
   stand-in a player will absolutely recognize the wink toward, without
   the game containing an actual copy of someone else's IP. Real-world
   folklore (Nessie, UFO lore) and properly transformative homage
   (referencing a book/film's *premise* or *history* rather than quoting
   its text) don't need this treatment — see each entry below for which
   register it's in.

### Mechanism: three trigger shapes, all reusing existing infrastructure

- **Real-coordinate triggers.** The exact same `GeoCoordinates`
  (`src/world/geo_coordinates.gd`) real lat/lon lookup the regional-
  mythology brainstorm already uses — a tiny, hand-curated table of
  {lat/lon (± a small radius), effect} entries, checked the same way a
  mythic-region classifier would be, just against a handful of specific
  points instead of macro-regions.
- **Secret console commands.** `console_command_parser.gd`'s existing
  parse-then-dispatch shape already supports this for free — an Easter
  egg command is just another `match` arm in `World`'s dispatcher
  (`scenes/world.gd`), deliberately **not** listed in `/help`'s output.
  One constraint on the name: a secret command must still begin with `/`
  or a letter, because the parser now drops any leading run of characters
  that cannot start a command (`_strip_leading_junk`) — that run is
  layout/dead-key junk, e.g. the buffered German `^`. So no command may be
  hidden behind a punctuation prefix; hide it by omission from `/help`
  instead.
- **Calendar-date triggers.** The game already has a real, live clock
  driving seasons/weather (`SeasonCycle`, `WeatherModel`) — a date-gated
  egg is a small, pure check against the real system date, the same kind
  of "reads real-world time" input those systems already use, just keyed
  to one specific day instead of a season.

None of these need new engine capability — every trigger shape is a thin
read against a system this project has already built for entirely
unrelated (serious) reasons.

### Starter collection (illustrative — the fun part)

**Bermuda Triangle** (~25.5°N, 71°W) — real maritime mystery lore, a
natural home for something impossible. A vanishingly rare, glitch-flavored
aquatic cameo: a long, serpentine, furious-looking sea-dragon with a
white, mane-like fin crest — unmistakably a wink at a certain 1996
monster-collecting classic's signature Water/Flying dragon without
reproducing its name or exact design. Working name: **"Squallmaw."**
Spawns at a wildly lower rate than even the rarest ordinary predator, and
does nothing a real creature doesn't already do (fight, flee, be tamed) —
the surprise *is* the payoff, not a new mechanic.

**Loch Ness** (57.3°N, 4.4°W) — genuine public-domain folklore (no
homage-safety concern at all; Nessie herself is fair game), and a lovely
double-reference: this exact coordinate already sits in the Celtic/British
Isles regional-mythology roster (worldbosses.md's each-uisge/kelpie
entry). A gentle, long-necked, placid lake serpent cameo alongside it —
also unmistakably reminiscent of a certain other very-friendly
Water/Ice long-necked classic — working name **"Coilnecca."** Deliberately
calm-temperament (not aggressive like the mythology roster's kelpie) so
the two coexist without one obviously overshadowing the other.

**Roswell, New Mexico** (33.4°N, 104.5°W) & **Area 51, Nevada** (37.2°N,
115.8°W) — a matched UFO-lore pair, not a Pokémon homage this time, its
own original joke: a small, inert "crashed saucer" landmark prop at each
coordinate, and a chance a wandering "little grey" NPC cameo says one
odd, deadpan line and vanishes if approached. No item drop, no quest —
just atmosphere.

**WarGames easter egg (secret console command).** RP1's Halliday is
explicitly obsessed with this 1983 film; its most famous line ("Shall we
play a game?") is cultural shorthand at this point, not something that
needs quoting to reference. A hidden console command
(`/globalthermonuclearwar`, never listed in `/help`) prints one original,
deadpan homage line back — a nod to the premise, not a transcript.

**A found ancient terminal (Zork homage, not reproduction).** RP1 treats
Zork as OASIS scripture — the first great text adventure. Zork's actual
prose is Infocom/Activision's copyrighted text, so this isn't a quote —
it's an **original** tiny text-adventure moment: interacting with a
specific, out-of-the-way ruin drops the player into a few lines of
old-school parser-style prose (fully original writing, evoking the FEEL
of a 1980 text adventure, not lifting from one) before returning them to
normal play. A palate-cleanser, not a new game mode.

**A signed secret room (Atari *Adventure* homage — the deepest cut).**
RP1's entire premise is modeled on a real historical event: Warren
Robinett hid the **first video game Easter egg** ever — his own name, in
a secret room — inside Atari's 1980 *Adventure*, without Atari's
knowledge. The most fitting way to honor that isn't referencing the game
itself; it's **repeating the actual gesture** — hide a small, genuinely
hard-to-reach room somewhere in this world (an obscure action sequence,
not a coordinate) containing nothing but a quiet signature/credit. A
meta-Easter-egg: the *existence* of a hidden signed room is the reference,
the same way dozens of modern games already pay this exact tribute.

**October 21 (Back to the Future Day, calendar-gated).** The real-world
date fans famously marked as "the future" the trilogy travels to. On that
one real calendar day each year, a silver, gull-winged car cameo (no
name used, description only — flavor text can gesture at "requires
serious speed" without needing to reproduce a trademarked name) appears
briefly somewhere the player is standing, then is gone. Once a year,
blink and you miss it.

**Monty Python's Bridgekeeper (three-riddle NPC).** RP1 name-drops this
film directly. A rarely-encountered wandering NPC who blocks a narrow
crossing and asks three short, **original** riddles (not the film's own
lines) before letting the player pass either way — failing a riddle is
harmless, just a silly non-consequence rather than a real penalty
(unlike the film's own rather more dramatic outcome).

**Rush (the band) — ambient nod.** Halliday's favorite band in RP1. A
specific, out-of-the-way location plays a short original ambient
instrumental cue on approach — evocative of prog rock's mood (odd meter,
synth-and-guitar interplay), never an actual cover or sampled riff, which
would be real copyright territory this project shouldn't cross even in
homage.

**A d20 in an otherwise dice-free game (D&D nod, and a joke about this
project itself).** RP1's Wade is a D&D kid. This game deliberately has
**no random rolls anywhere** — combat, crafting, spellcasting are all
fully deterministic by design (see materials.md, magic.md). The joke
writes itself: a single, secret, genuinely-random d20 roll, findable
somewhere unlikely, that does something harmless and silly on a natural
20 (and nothing at all otherwise) — the one deliberately non-deterministic
moment in an otherwise rigorously deterministic game, precisely *because*
that's funnier here than it would be anywhere else.

**More real-world cryptid cameos — pure public-domain folklore this time,
no homage-safety concern at all (same register as Loch Ness, unlike
Squallmaw), so these get to be played straighter and spookier:**

- **Point Pleasant, West Virginia** (38.85°N, 82.13°W) — Mothman. A
  tall, winged, red-eyed silhouette glimpsed at range that's simply gone
  if the player gets close — never actually catchable, no stats, no
  fight. The one entry on this whole list that's pure atmosphere with
  literally no mechanical presence at all, which is exactly right for
  this particular legend.
- **Lake Champlain** (44.5°N, 73.3°W) — Champ, the American cousin of
  Nessie. Deliberately NOT a reskin of Coilnecca above despite the
  obvious family resemblance in premise: skittish rather than placid,
  visible only from a real distance and diving the instant the player
  closes in, so it reads as genuinely shy wildlife rather than a second
  copy of the Loch Ness cameo.
- **The New Jersey Pine Barrens** (39.7°N, 74.5°W) — the Jersey Devil.
  A winged, hoofed, goat-headed silhouette with the same glimpsed-then-
  gone treatment as Mothman, but paired with a real, un-ownable sound
  cue (a distinct shriek) rather than a purely visual tell — spookier at
  night, same zero-mechanical-weight rule as everything else here.

**The Kraken — a condition trigger, not a coordinate (the collection's
one deliberately higher-stakes entry).** Every other cameo above is
pinned to a fixed point; this one instead fires on a real *condition*
already computed live by this project's own weather/time systems —
open ocean, night, and active storm weather (`WeatherModel`), all at
once, anywhere on the map. Genuinely dangerous rather than purely
cosmetic (the collection's sole exception to pillar 2's "zero mechanical
weight" — earns it by being vanishingly rare AND requiring the player to
deliberately be somewhere risky at a risky time, so it never becomes
free content, only content you had to go looking for trouble to find),
massive, many-tentacled, and — unlike the fixed-coordinate cameos above
— actually a real fight if it notices you.

**A hidden sea cave at the Bermuda Triangle, with a dueling-birds
cabinet inside — a real, playable homage, correctly placed and staged.**
RP1's actual first major set-piece (not the finale — the book's climax
against Sorrento is a giant-mech fight, no bird in sight) is Parzival
besting a shapeshifting guardian at a best-of-three match of a real,
famous 1982 two-player arcade game where each side rides a flying mount
and jousts the other off it, to win the first of three keys — staged
inside a cave modeled on a classic tabletop dungeon, where the guardian's
own throne transforms into the arcade cabinet mid-challenge. Worth
staging properly rather than just dropping a cabinet in the open: a
hidden, half-flooded **sea cave** at the exact Bermuda Triangle
coordinates (a natural pairing — shipwrecks and hidden grottoes are
already what that stretch of ocean is *for*, folklore-wise), reachable
only by finding its entrance, alongside Squallmaw above. An **original**
guardian (not the book's own specific character — a different, this-
world creature or spirit entirely) sits before a simple stone seat that
visibly reconfigures into the cabinet the moment the player accepts the
challenge — one small scripted transformation beat, not a full cutscene
system. The match itself: two mounted riders on a scrolling aerial
arena, collide to knock the other off, higher rider wins the joust —
built from scratch in this engine, not reproducing the real game's code
or assets, just its elegant two-line premise. A genuinely bigger
implementation lift than this doc's other entries (a hidden sub-area, a
scripted transform beat, and a real second game loop, not just a prop),
worth calling out as its own scoped task rather than folded silently
into "just an Easter egg."

**A hidden retro handheld, playing an original mini-game starring this
GAME's own creatures — not the Easter eggs', the real roster.** The
obvious next wish — "and somewhere, a classic monster-collecting
handheld you can actually play" — runs straight into real IP: an actual
ROM of that genre's most famous commercial game is Nintendo's complete,
literal copyrighted software, not a reference to it, and embedding one
isn't homage, it's distributing a copy of someone else's commercial
product (a full GBA-class emulator core is also its own serious
standalone engineering project, well beyond "Easter egg" scope, before
that question even comes up). The payoff doesn't need either, and lands
better without it: a small, battered handheld prop (generic, undescribed
hardware — no trademarked shape or logo) hidden somewhere, which boots
into a tiny, **original**, actually-playable turn-based creature-battler
starring **miniature pixel-art versions of this project's own already-
built roster** — catch/battle a pocket-sized deer, wolf, boar, bear,
lynx, or (rarer, at higher "levels") the regional-mythology cast
(Krampus, Lindwurm, Rübezahl) in a few original turn-based moves. Zero
new art needed at the character level (the existing procedural/
illustrated sprites already exist for every one of these — see
`ProceduralAnimalSprite`/`IllustratedAnimalSprite`) — the actual new work
is a small, self-contained turn-based battle-menu loop and a "world's
smallest Pokédex" catch-list UI skinned to read as a retro handheld
screen, not new creature designs. Fully self-contained, fully this
project's own content already, and it ties the whole collection together
instead of gesturing at someone else's — a tiny game about this game's
own wildlife, nested one level deeper, playable on a prop you find
inside the world it's depicting.

**"Three Fragments" — a hunt about the hunt (RP1's actual biggest
structural idea, done originally).** RP1's whole plot is a three-key,
three-gate hunt. The honest way to honor that structure without copying
its specific content (the Copper/Jade/Crystal Keys are the book's own
invented plot, not just "80s culture" the way WarGames or Zork are) is
to build an ORIGINAL three-stage hunt out of eggs already on this list:
finding the signed secret room, successfully navigating the Zork-homage
terminal, and triggering the WarGames console command each quietly
leaves behind one small, unremarkable "fragment" item — no fanfare, easy
to miss the significance of any one. Holding all three at once triggers
one final, extra-special bonus discovery. Turns four separate one-off
jokes into a hunt with its own quiet throughline, mirroring the book's
structure rather than quoting its content.

**The final bonus discovery (the implementing stage's own creative call —
this entry originally left the payoff open, "TBD what... whoever
implements this gets to invent the actual payoff"):** the three
fragments — a pitted circuit shard, a tarnished token, a scorched punch
card, individually inert junk with no visible connection to each other —
turn out, held together, to physically interlock. Nothing mechanical
happens. But the joined piece carries one line scratched on its
underside, meant for whoever was thorough enough to notice: "you weren't
supposed to find all three. nice work." The choice deliberately mirrors,
at the meta level, the exact gesture the signed secret room itself pays
tribute to — Robinett's own quiet, personal signature left for whoever
found it — rather than inventing new lore or referencing RP1's own
Copper/Jade/Crystal Keys (pillar 4: homage to the *shape* of the
gesture, not a copy of the book's own invented content). Still zero
mechanical weight (pillar 2): the assembled item does nothing a normal
inert material item doesn't already do.

### Status

🚧 Partial. The reverse-geo-lookup-with-radius infrastructure
(`GeoCoordinates.tile_for_coordinate`/`radius_in_tiles`/
`tile_is_within_radius`) and four of the real-coordinate cameos above —
Mothman, the Jersey Devil, and the Roswell/Area 51 crashed-saucer +
"little grey" pair — are implemented (`src/gameplay/
easter_egg_sightings.gd`), as brief on-screen sighting lines rather than
spawned sprites/props (a deliberate, documented scope choice — see the
module's own doc comment and `docs/progress.md`).

Squallmaw, Coilnecca, and Champ are also implemented, but unlike the four
above they're real, spawnable creatures — full `CreatureInfo`/
`AnimalAnatomy`/`ProceduralAnimalSprite` entries, following the Germany-
region world-boss precedent's shape but explicitly not their stat scale
(`src/gameplay/easter_egg_creatures.gd` decides when/where one should
appear, reusing the same reverse-geo + roll shape as
`easter_egg_sightings.gd`; `scenes/world.gd` then spawns it for real via
`CreatureRenderer.spawn_single`, the same API `/spawn` itself uses). Champ
introduces a new `"skittish"` temperament value — `CreatureBehavior` only
special-cases `"aggressive"`, so it already flees exactly like `"calm"`
does today, but the distinct label keeps it from reading as a mechanical
duplicate of Coilnecca. Champ's "dives immediately if the player closes
in" is approximated (spawned at a fixed distance from the player, then the
ordinary flee-when-threatened creature AI takes over) rather than a
literal per-species detection-radius mechanic — see `docs/progress.md` for
the exact scope call and what a fuller version would need.

The Kraken is also partially implemented: `KrakenTrigger`
(`src/gameplay/kraken_trigger.gd`) is a pure, fully-tested decision module
for its condition trigger (open ocean + night + active storm, all at once,
anywhere on the map — no coordinate lookup, unlike every cameo above), and
it has a full `CreatureInfo`/`AnimalAnatomy`/`ProceduralAnimalSprite` roster
entry, `/spawn`-able for testing the same way as every other cameo creature.
Deliberately the collection's toughest entry by a clear margin (max_health
and world_scale both exceed every existing species, including every
Germany-region world boss) and its `is_world_boss` flag is set, reusing
`BossAggro`'s existing aggro-gate mechanism so it fights for real once
provoked rather than free-ambushing an unprovoked player — see
`creature_info.gd`'s own comment for why this does NOT make it part of
`worldbosses.md`'s regional-mythology roster. Not yet wired into
`scenes/world.gd`'s live per-frame loop (unlike Squallmaw/Coilnecca/Champ) —
the actual live depth/weather/night computation feeding the trigger, and the
`spawn_single` + combat encounter it should produce, are a documented
follow-up; see `docs/progress.md`.

The two remaining trigger shapes — secret console commands and calendar-date
gating — are now implemented too, alongside two more Starter Collection
entries: the WarGames secret console command
(`/globalthermonuclearwar`, `src/gameplay/wargames_response.gd`, wired as an
undocumented `match` arm in `scenes/world.gd`'s dispatcher) prints one
original, deadpan homage line, and Back to the Future Day
(`src/gameplay/back_to_the_future_day.gd`) fires once per session on the
real *system* calendar date of October 21st (`Time.
get_datetime_dict_from_system()` — a different clock than this game's own
fictional `SeasonCycle`) as a brief, description-only on-screen cameo line,
reusing the same banner `EasterEggSightings` already uses. The Rush ambient
nod (`src/gameplay/rush_ambient_cue.gd`) is also implemented as a real,
location-triggered (no rarity roll — proximity alone fires it) on-screen
flavor line at a real, out-of-the-way coordinate, but its *audio* half is
deliberately stubbed: no audio-generation tool was available to build the
doc's actual ask (a real composed ambient instrumental cue), so `scenes/
world.gd` leaves an explicit `TODO` where a real `AudioStreamPlayer2D` +
`.ogg` cue belongs — see `docs/progress.md`. The D&D d20 nod is also
implemented (`src/gameplay/secret_d20.gd`) as this project's one deliberate,
tightly isolated exception to "no random rolls anywhere" — a dedicated
`RandomNumberGenerator` instance never shared with anything else, wired as
a second undocumented secret console command (`/rolld20`), harmless and
silly on a natural 20, a no-op otherwise.

Three more Starter Collection entries are now implemented: the Zork-homage
ancient terminal, the signed secret room, and Monty Python's Bridgekeeper.

The ancient terminal (`src/gameplay/ancient_terminal.gd`) is pinned at a
real-world coordinate (Cambridge, Massachusetts, where Zork was actually
written — never named in-game, reusing `GeoCoordinates` exactly like every
other real-coordinate cameo) plus a few lines of fully original, old-school-
parser-style prose, enforced never to quote Zork's own text by its own test.
Unlike the proximity-only cameos above, it needs a deliberate interaction —
the player's own "talk" input — at the location, not just approach, wired
into `scenes/world.gd` on every frame (rather than the throttled cadence the
rarity-roll cameos use) so the single-frame key-press is never missed.
Deliberately no floating interaction prompt at the ruin — that would itself
be a hint, against pillar 3.

The signed secret room (`src/gameplay/signed_secret_room.gd`) repeats Warren
Robinett's actual gesture rather than referencing *Adventure* itself: pinned
at Sunnyvale, California (Atari's real historical HQ, never named in-game)
plus an obscure four-verb action sequence (stash, then lasso, then fish,
then mount — real, existing interaction verbs from unrelated contexts,
chosen over combat verbs specifically because those chain together too
easily by accident). `CREDIT_TEXT` is a tasteful, generic placeholder
credit, marked with a `TODO(ship)` comment so whoever ships this can swap in
real names with a one-line edit. Reaching the gate reveals the credit via
the same on-screen banner every other cameo in this doc uses rather than
a literal new walkable interior — a deliberate, documented scope call
matching this doc's "not a new game mode" discipline, not a silent
under-build.

Monty Python's Bridgekeeper (`src/gameplay/bridgekeeper_encounter.gd`) asks
three original riddles set in this game's own nature vocabulary (a river, a
tree, snow) rather than the film's own three questions. This project has no
bridge/river-crossing terrain concept and no path-blocking NPC AI to reuse,
so — the same kind of documented scope call `EasterEggSightings` already
makes for Mothman — the "wandering NPC" is a rare, location-gated encounter
roll (pinned at Trift Bridge, Switzerland, a real narrow rope crossing,
never named in-game) that opens a riddle exchange through a new undocumented
`/answer <text>` console command, the same secret-console-command shape
WarGames/the d20 egg already use. Passage never actually depends on the
score, by construction, matching "failing is harmless, a silly
non-consequence."

The ancient terminal, the signed secret room, and the WarGames console
command each expose a clean, testable `has_been_found()`/`mark_found()`
signal (forwarded by `World.has_found_ancient_terminal()`/
`has_found_signed_secret_room()`/`has_found_wargames_egg()` — the WarGames
egg's own signal was added specifically to let "Three Fragments" check all
three consistently, mirroring the shape the other two already
established).

**"Three Fragments" is now implemented.** `ThreeFragmentsHunt`
(`src/gameplay/three_fragments_hunt.gd`) is the pure aggregation module —
`has_all_fragments`/`should_trigger`/`mark_triggered`/`has_triggered`, every
input a plain caller-supplied boolean rather than the three source egg
modules themselves, so it's fully testable independent of them (the same
"caller supplies the real primitive" shape `KrakenTrigger`/
`BridgekeeperEncounter` already use). `scenes/world.gd` grants one fragment
item (`ItemCatalog`'s `terminal_fragment`/`secret_room_token`/
`wargames_punch_card`, all inert "material" items) into the player's
inventory the first time each source egg's own `has_been_found()` flips
from false to true — quietly, no fanfare, alongside whatever else that egg
already does — then checks `Inventory.has(...)` for all three and grants
the bonus item (`curious_keepsake`) plus a banner message the moment all
three are first held together. See this doc's own "Three Fragments" entry
above for the final bonus discovery's actual content and the reasoning
behind that creative choice. Monty Python's Bridgekeeper is deliberately
NOT part of this hunt (it was never one of the three eggs the doc names).

The hidden sea cave / dueling-birds cabinet (the Joust homage above) is
now implemented: `JoustMatch` (`src/gameplay/joust_match.gd`) is the pure,
fully-tested rules core (deterministic AI, no random rolls, best-of-three
scoring); `SeaCaveGuardian` (`src/gameplay/sea_cave_guardian.gd`) is an
original guardian ("the Brinewarden") gating the challenge at the exact
Bermuda Triangle coordinate Squallmaw uses; `JoustMatchView`
(`src/rendering/joust_match_view.gd`) is the actual playable arcade-cabinet
screen, wired into `scenes/world.gd` with a scripted transform beat and a
real pause-the-world match. See `docs/progress.md`'s Easter Eggs section
for the full writeup, including its one deliberate, documented scope call
(no literal new interior geometry for the cave itself, reusing this doc's
own established "point + interaction" shape rather than a new spatial
system — the encounter and the joust itself are both real, not props).

The retro-handheld creature-battler is now implemented. `HandheldRoster`
(`src/gameplay/handheld_roster.gd`) is the pure roster data — the doc's own
"deer, wolf, boar, bear, lynx at common tiers; krampus/lindwurm/rubezahl at
[legendary] tiers", a self-contained stat table deliberately NOT read from
`CreatureInfo` (this mini-game needs its own small internal balance
independent of the open world's own combat numbers). At the time this was
written, "wolf" had no entry at all in `CreatureInfo` — a pre-existing gap
in the open world's own wolf wiring — but merging this branch into `main`
brought in another concurrent session's own fix for exactly that gap (a
real `CreatureInfo`/`ProceduralAnimalSprite` wolf entry), so the gap
described below is now closed; `HandheldRoster` still keeps its own
separate stat table by design, not as a workaround.
`HandheldBattle` (`src/gameplay/handheld_battle.gd`) is the pure,
fully-tested turn-based rules core — four original moves (charge/rend/
guard/focus), deterministic damage (no `randf()` anywhere, matching this
project's derived-not-rolled combat/crafting philosophy), and a
deterministic skill-based AI opponent, the same discipline `JoustMatch`
already established for this doc's family. `HandheldCatch`
(`src/gameplay/handheld_catch.gd`) is the catch mechanic — a seed-derived
(never `randf()`), health-fraction-based success chance, mirroring
`CreatureInfo`'s own seed → level derivation. `HandheldCollection`
(`src/gameplay/handheld_collection.gd`) is the pure "world's smallest
Pokédex" catch-list model. `HandheldBattleView`
(`src/rendering/handheld_battle_view.gd`) is the actual playable battle +
dex screen, drawing every creature with the EXISTING `ProceduralAnimalSprite`/
`IllustratedAnimalSprite` rendering (zero new art, per the doc). `RetroHandheld`
(`src/gameplay/retro_handheld.gd`) is the hidden prop's location + interaction
gate (a real-world coordinate, Kyoto — a quiet nod to the handheld-games era,
never named in-game — plus a "talk" press, the same shape `AncientTerminal`
uses), repeatable like `SeaCaveGuardian` rather than a one-shot find. See
`docs/progress.md`'s Easter Eggs section for the full writeup. This stage
originally documented a gap here — "wolf" had an `AnimalAnatomy` body
profile but no `ProceduralAnimalSprite`/`CreatureInfo` wiring, so it
rendered with the generic procedural silhouette instead of a wolf-shaped
one — but merging this branch into `main` brought in another concurrent
session's own fix for that exact gap, so wolf encounters (both here and via
the open world's own `/spawn wolf`) now render correctly.

### Open questions

- Exact rarity/probability numbers for the coordinate-triggered cameos —
  first-pass placeholders needed, same "pin it with a test, don't
  eyeball it" discipline as everywhere else once these get implemented.
- Should there be a quiet, spoiler-free "curiosities found: N" counter
  anywhere in the UI (proof you've found *something* without revealing
  what's left), or should this stay entirely undiscoverable-by-the-game-
  itself, matching pillar 3 above as strictly as possible?
- Is a config toggle to disable Easter eggs worth adding for players who'd
  rather the world stay purely in-universe? Leaning "not worth the
  complexity for a first pass," but noting it as a real option.
- Where does the line actually sit between "homage" and "too close" for
  each entry above — this doc took a conservative first pass; worth a
  second look, entry by entry, before any of this ships.
- Who else's "book that's entirely made of references" is worth its own
  cluster the way Ready Player One got one here — Stranger Things, The
  Matrix, and Wreck-It Ralph are the obvious next candidates if this
  category proves fun to build out.
