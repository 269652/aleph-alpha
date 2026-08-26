# Playtest — 2026-08-26 — taming, breeding, and the agency gap

A session aimed at one question: **what can a player actually DO to an animal?**
Booted the real build, made a character, entered a fresh world, crafted the
taming kit through the dev console, and tried to tame something. Findings are
ordered by how much they cost the player, not by how easy they are to fix.

**Setup.** Godot 4.7 stable, debug build, `--path` on this worktree, 1280×720
window, GL Compatibility on Intel integrated graphics. Driven through real OS
keyboard/mouse events (physical scancodes) with a screenshot after every step,
so everything below is what a player sees, not what a harness reports.

**Save safety.** This session ran against an isolated `user://` — the worktree's
`project.godot` was temporarily given `config/use_custom_user_dir=true` +
`custom_user_dir_name="AlephAlfaPlaytest"`, so the session could not touch the
real save. The patch was reverted afterwards; `project.godot` is unchanged on
disk. This is worth repeating for any future play session: the user data
directory is keyed on the project *name*, so a worktree shares one save with
`main` unless you do this.

**Caveat that applies throughout.** Frame rate sat at **6–11 FPS** for the whole
session, because ~3 other Godot processes from concurrent sessions were
competing for CPU on this machine. Absolute responsiveness numbers below are
therefore not trustworthy. Everything about *what is wired to what* is
hardware-independent and does stand.

---

## The headline

The game **looks** like a deep simulation and, underneath, largely is one. The
HUD alone reports latitude/longitude, local solar time, sun elevation, season,
weather, movement mode, a speed percentage, HP, food, water, stamina, a
freezing/cold meter, gold, and a live minimap. Animals graze, flee, and are
individually levelled.

The gap the player feels is not that the simulation is thin. It is that **their
hands are tied behind their back while they watch it.** Taming is the one deep,
player-driven verb the game has over animals — and its most dramatic beats are
invisible or automatic. Breeding does not exist at all.

---

## Findings

### 1. In ordinary weather you are slower than the animal you are chasing ⬜

This is the big one, and it took two passes to get right — the first
explanation written here was wrong, so both are recorded.

**What happened.** Sheep and horses sense the player as a threat and move away
as you approach. I repeatedly walked at a wild sheep and repeatedly failed to
get inside `Player.LASSO_RANGE` (72px, `scenes/player.gd:72`) before it drifted
off. Every `R` press produced the same banner:

> Lasso ready — press the lasso key near an animal.

Spawning a horse directly with `/spawn horse 1` did not help — it was already
out of range by the time the console closed.

**The wrong explanation.** My first reading was that the rope's 72px reach sits
inside `CreatureMarker.SENSE_RADIUS` (80px, `:118`), so a wild animal could
never be lassoed "by construction". That is refuted by the code:
`CreatureMarker.FLEE_SPEED` is **40.0** (`:147`) against `Player.BASE_SPEED`
**80.0** (`scenes/player.gd:64`) — a fleeing animal moves at half the player's
walking pace, so an 8px gap closes easily. `tests/unit/test_creature_marker.gd:2091`
(`test_the_measured_catch_rate_matches_the_model`) measures 60 real captures.
Catching is clearly *possible*.

**The real explanation.** The player's speed is not `BASE_SPEED`; it is
`BASE_SPEED × current_speed_multiplier`, and that multiplier is the product of
four separate penalties (`scenes/player.gd:1267`):

```
current_speed_multiplier = water × weather × terrain × ConditionPenalty(fitness)
```

Through most of this session the HUD read **`Speed: 47%`** — autumn rain, over
vegetated ground, with a Cold/Freezing meter running. 0.47 × 80 = **37.6 px/s,
which is below `FLEE_SPEED` 40**. A healthy wild animal was not merely hard to
catch; it was *outrunning me*, and would have kept outrunning me indefinitely.
Later in the same session the multiplier rose to 75% (60 px/s) and the approach
immediately became viable — that is when I got closest.

**Why this matters more than the tuning.** Nothing in the game connects those
facts. The HUD shows a percentage; it never says "you are now slower than a
sheep". A player in rain, in long grass, slightly cold, will simply conclude
that taming is broken — and on that afternoon, functionally, it is.

The deeper point is that **chasing is the wrong verb to build the mechanic on
at all.** There is no bait, no lure, no crouch, no slow approach, no calming,
and no per-species flight distance to learn and play around. Bait would work
regardless of the speed multiplier; a stalk closes distance without a foot race.
`docs/concept/olfaction.md` already exists and is the natural home for scent-led
baiting, so the foundation is specified but unconnected.

### 2. The nearby-creature panel is an anonymous stack 🚧

Approaching animals stacks cards in the top-left, each reading only:

> `Sheep Lv.4` / `HP 31 / 31`

With four or five animals nearby that is a column of near-identical cards. No
name, no trust, no hunger, no age, no sex, no indication which one you are about
to lasso — and since **every taming verb resolves to *nearest*** (`_throw_lasso`
`scenes/player.gd:2193`, `_nearest_tamed` `:2318`, `_try_mount`), you cannot
choose between two animals standing together. Any multi-animal mechanic — a
herd, a pen, a chosen breeding pair — is blocked on this.

`CreatureMarker` is already in `HoverTargetFinder.GROUP_NAME` and already has
`get_display_name()`, so the hover half of this is close to free.

### 3. Feeding — the heart of taming — has no key at all 🚧

`Player._try_feed_lassoed` (`scenes/player.gd:2182`) runs **every frame** and
feeds the animal if it is within 28px and a carrot is in the inventory. The
carrot is only consumed if trust actually rose, which is a nice touch — but the
consequence is that the "relationship" pillar the design rests on reduces, in
play, to *standing near the animal with food in your bag*.

`docs/concept/taming.md` argues well that hunger-gating the feed is what makes
taming read as a relationship rather than a purchase. That argument is sound and
the gating is real — but with no gesture to perform, the player never
experiences the offer being made or refused.

### 4. The struggle is invisible 🚧

The animal fighting the rope is the most dramatic moment in the whole mechanic.
Today it is a silent deterministic hash roll every 1.2 s
(`src/rendering/creature_marker.gd:854-879`): no animation, no bucking, no rope
tension, no sound, and no way for the player to contest it. You cannot tell a
struggle happened unless the animal escapes.

`docs/concept/taming.md` is honest about this — it already flags the silent
struggle as its one open gap. `World._build_charge_meter` (`scenes/world.gd:2044`)
already draws exactly the kind of world-space meter this needs.

### 5. There is no breeding ⬜

Confirmed by code audit rather than by play, because it is not reachable in play.
Mammal reproduction is **asexual budding**: `World._step_reproduction`
(`scenes/world.gd:3933`) spawns a same-species offspring beside any single
creature over an energy/health threshold. There is no partner, no sex, no mate
check on that path, and the offspring's seed is a fresh `randi()`
(`src/rendering/creature_renderer.gd:266`) — so **the child inherits nothing from
the parent but the species string**.

It is also effectively unreachable: `REPRO_COOLDOWN` is 24 *real* hours
(`src/gameplay/animal_reproduction.gd:32`), `_seconds_since_birth` advances on
raw frame delta, is not persisted, and resets on chunk unload — and `/ecotest`
does not accelerate it. An individual mammal birth cannot realistically be
observed in a session.

The only visible courtship in the game is between pollinators — I saw a labelled
`Swallowtail` — and its outcome is a flat 0.25 coin flip
(`src/gameplay/courtship.gd:111`) with no fitness term.

Meanwhile `src/gameplay/dna_crossover.gd` (a complete, tested two-parent
crossover with bounded mutation) and `src/world/animal_fitness.gd`
(`phenotype_for`, `fitness_score`, `mate_attractiveness`) sit in the tree with
**zero production callers**.

### 6. No pet roster, anywhere ⬜

The inventory screen is an equipment doll plus a 12-slot grid. There is no list
of animals you own, no way to see where they are, and no way to check on one you
tied to a tree an hour ago. `CreaturePanel` cards are proximity-driven and vanish
when you walk away.

### 7. No `/tame`, `/breed` or `/kept` console commands ⬜

`/help` lists 30+ commands — sky, season, weather, ecotest, the whole emergence
reader set (`/history`, `/why`, `/household`, `/market`, `/institution`,
`/settlement`, `/boss`, `/quests`), `/spawn`, `/give`, `/craft`, `/gold`, and the
wayfinding instruments. Not one of them touches taming.

Since a tamed animal today costs a lucky 72px throw plus roughly five
hunger-gated feeds spread over real minutes, **iterating on any animal mechanic
is punishingly slow**. This is the cheapest possible unblock for the work below.

### 8. Smaller things seen in passing

- `/weather off` did not visibly take effect — the HUD stayed on `Rain` while
  `/day` pinned the sky correctly. Worth a look; not chased down this session.
- The dev console's output pane still shows older lines rather than scrolling to
  the newest entry after a burst of commands, so command results are hard to read.
- Movement is easy to mistake for a hang: at 6–11 FPS with `Speed: 47%`, an
  800 ms key hold moves the player a few pixels, and walking into a tree looks
  identical to input not arriving. Long holds (2–4 s) are needed to confirm.

---

## What this session did not establish

- **I never completed a tame.** The approach problem (finding 1) plus the frame
  rate meant no animal was caught, so the lead → tie → feed → order → mount
  chain was *not* exercised end to end in play. Everything asserted about those
  later stages comes from reading the code, not from playing it, and should be
  treated as such.
- No claim here rests on a test run — Godot's test suite was not executed as
  part of this session.
- Frame-rate figures are contaminated by concurrent sessions and should not be
  used as a performance baseline.

---

## Where the specs went

The design work this session fed into lives in:

- `docs/concept/animal_husbandry.md` — the approach layer, pens, feed/water,
  production, roles, and the ongoing cost of keeping animals (new).
- `docs/concept/animal_genetics.md` — the `AnimalGenome`, inheritance through
  the existing `dna_crossover.gd`, two-parent pairing, and selection the player
  drives (new).
- `docs/concept/taming.md` — corrected status, plus the struggle contest,
  the feed gesture, targeting, and trust expressed as behaviour (rewritten).

Status in `docs/progress.md` was corrected in the same pass; several entries
there described taming as unwired when the loop is live, and credited a dead
module (`src/gameplay/taming_system.gd`, zero callers) as "the Taming System".
