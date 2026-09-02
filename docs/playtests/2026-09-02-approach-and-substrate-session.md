# Playtest — 2026-09-02 — the approach, and the substrate nobody calls

A session aimed at two questions: **what does the game feel like to play right
now**, and **what is already in the tree that nothing in the running game ever
asks for?** The first was answered by booting the real build and driving it
with real keyboard and mouse events. The second by auditing every `.gd` in
`src/` for production callers.

Findings are ordered by how much they cost the player.

**Setup.** Godot 4.7 stable, debug build, `--path` on this worktree, 1280×720,
GL Compatibility on **llvmpipe software rendering** under Xvfb (this session
ran headless in a container with no GPU). Driven through real X11 keyboard and
mouse events with a screenshot after every step, so everything below is what a
player sees, not what a harness reports.

**Save safety.** `HOME` was redirected to a scratch directory for the whole
session, so Godot's `user://` — and therefore the save, the license and the
settings — lived in a throwaway tree. `project.godot` is unchanged on disk.

**Caveat that applies throughout.** Frame rate sat at **6–14 FPS** for the
whole session because the renderer is software. Absolute responsiveness
numbers are therefore not trustworthy. Everything about *what is wired to what*
is hardware-independent and does stand. Movement distances quoted below are
measured against the world, not against wall-clock, so they stand too.

---

## The headline

**The approach problem from the 2026-08-26 session is still there, and this
session reproduced it in play rather than by reading the code.** One full
design iteration later — with `AnimalActions`' scored primary/secondary slots
now live, capture tools per body plan, and a real `/spawn` roster — a player
still cannot get near a wild animal, and the reason is still that the only verb
available is a foot race the player usually loses.

I spent the second half of the session doing nothing but trying to close 400
pixels on a sheep, in clear weather, at noon, on flat ground. I never got
inside `Player.LASSO_RANGE`.

The good news is the substrate to fix it was already there and idle. See
"What nothing calls", below.

---

## Findings

### 1. The speed product is a hidden pass/fail line, and the HUD does not say so 🚧

`CreatureMarker.FLEE_SPEED` is **40.0**. `Player.BASE_SPEED` is **80.0**. So a
fleeing animal moves at exactly **50% of the number the HUD prints**. Below
50%, no wild animal can ever be caught; above it, the gap closes at
`(pct − 50%) × 80` px/s.

Speed readings actually observed this session, all of them on the HUD:

| situation | HUD reads | closing speed vs. a fleeing animal |
|---|---|---|
| first frame, spring, clear, noon | 96–100% | +37 to +40 px/s |
| noon, clear, open grass | **75%** | +20 px/s |
| forest floor | **56%** | **+4.8 px/s** |
| spring storm | **36%** | **−11 px/s (it opens the gap)** |
| swimming | **23–24%** | −21 px/s |

Three of those five are at or below the line. The 56% forest reading is the
cruel one: it *looks* like more than half, and it buys the player 4.8 px/s —
about 80 seconds of unbroken pursuit to close a single 400 px gap, assuming the
animal never turns.

The HUD shows a percentage. It never says *you are now slower than a sheep*.

`docs/concept/animal_husbandry.md` already named this as its highest-value item
and named the test for it. **That test is still unwritten**, and the readout is
still a bare percentage. This is the one part of the approach layer this pass
did not close.

### 2. In-world, the reason the chase fails is not always speed — it is trees ✅ (diagnosed)

Twice I held a direction key for 8–9 seconds and the player moved roughly
100 px, then on a later attempt moved 500 px in the same time. The difference
was tree collision: the player wedges on a trunk and there is no slide-around,
and at 8 FPS with `Speed: 56%` **being blocked by a tree is visually identical
to input not arriving.** The previous session recorded the same symptom and
attributed it to frame rate; it is collision.

Not fixed here (it is a movement question, not an approach one), but it
compounds finding 1 exactly when the player is least able to tell.

### 3. `/spawn` puts animals out of reach 🚧

`/spawn sheep 5` scattered five sheep at 200–500 px. By the time the console
closed, every one of them was outside sense range and drifting. Combined with
finding 1, iterating on any animal mechanic through the console is punishingly
slow — the previous session said the same thing and it is still true.

The cheapest possible unblock for animal work remains a `/spawn` that places at
the player's feet, and the `/tame`, `/breed`, `/kept` commands that still do
not exist.

### 4. The console loses keyboard focus, and the leaked keystrokes open windows 🐛

Reproduced repeatedly. After the console has been open and anything else takes
the window's keyboard focus (in this session, the screenshot tool), the
`LineEdit` no longer has focus but the console is still **visible**. The next
thing typed goes to the game: typing `/give lasso 1` opened the **skill tree**
(the `l`), typing `/give carrot 20` opened **crafting** (the `c`), and the `i`
opened the **inventory**.

Under a normal window manager this needs an alt-tab away and back to trigger,
which a player will do. The fix is for `DevConsole` to re-grab focus while
visible (a `_notification(NOTIFICATION_WM_WINDOW_FOCUS_IN)` re-grab, or a
per-frame `if visible and not _input.has_focus(): _input.grab_focus()`).

Not fixed in this pass — flagged, with the repro.

### 5. Bait had no gesture: you cannot put food on the ground 🐛 (fixed)

Found while trying to verify the bait layer in play. The whole simulation half
was live — ground food is published as a smell, a grazer walks up the gradient,
`take_bait_at` lets it eat what it reached — and **a player had no way to put
food on the ground at all.**

`inventory_window.gd`'s own header comment says an item can be dropped "onto
the world to throw it away". Tested twice, once with a slow eight-step drag so
the drag payload was visibly attached to the cursor: the stack stays at 20, and
nothing lands. The window's on-screen label says only "drag to move", which is
what the code actually implements.

Fixed by giving the stash key (default `H`) a second, contextual meaning,
exactly the way `E` already has one (see `stone.md`'s held-item concept): with
something in hand it still stashes, and with an **empty** hand it puts one
bait down at the player's feet. Which food goes down is
`Player.bait_item_id_from` — the taming treat if carried, otherwise the first
food — pure and tested, with the "no selected-item concept yet" limit recorded
in its own doc comment.

Verified in play: press `H` carrying carrots, and a carrot is lying on the
ground with the world's own `Pick (E)` prompt over it.

### 6. `/weather off` now explains itself ✅ (regression fixed since last session)

The 2026-08-25 session reported `/weather off` as having no visible effect.
It now prints:

> Weather was not pinned -- storm here is the real forecast. (/weather off
> releases a pin; it does not stop the weather.)

That is exactly right and closes that finding.

### 7. The world reads beautifully, and the simulation is visibly running ✅

Worth recording, because the findings above are all friction. In one session I
saw, without looking for any of it: five distinct fish species swimming in one
pond; a labelled `Swallowtail`; a worm surfacing; a bird crossing a field; a
wild carrot with a `Pull (Space)` prompt; a `Cobble` and a `Pebble` offering
different verbs (`Pick Up (E)` / `Kick (K)`); trees in spring blossom that
became bare and orange when I skipped the season; rain drawn as real falling
streaks; and a saddled horse standing in a meadow at Lat 52.5 Lon 13.4.

The character creator's live preview diorama — the player, a boar, a pond, a
frog, grass — is genuinely lovely.

### 8. Pre-existing red tests 🐛

A full-suite run finished with 17 reds. **Every one of them is pre-existing** —
verified by stashing this session's changes and re-running the same files and
the same `-gunit_test_name` selections, which produced identical results
(7 seed failures, 1 fruiting failure, 5 tree-sprite failures, 1 dialogue-topic
failure). None is caused by this work, and none is fixed by it.

- `tests/unit/test_earth_chunk_manager.gd`, the seed group
  (`test_shed_seed_appears_on_the_ground_and_is_rendered`,
  `test_every_edible_seed_is_rendered`, `test_a_bird_eating_a_seed_removes_its_sprite`,
  `test_seeds_near_reports_seed_lying_on_the_ground`,
  `test_take_seed_at_returns_the_species_and_removes_it`,
  `test_an_eaten_seed_names_a_real_plantable_species`,
  `test_try_plant_seed_at_fails_outside_forest_or_rainforest`) — all fail at the
  same precondition, `[0] expected to be > than [0]: precondition: some seed
  has been shed`, then throw `Out of bounds get index '0' (on base: 'Array')`.
  Something upstream stopped shedding seed.
- `tests/unit/test_earth_chunk_manager.gd`:
  `test_step_fruiting_skips_a_far_tree_then_shows_its_real_ripeness_once_in_range`
  — `[2] expected to equal [10]`, a catch-up ripeness that is not catching up.
- `tests/unit/test_procedural_tree_sprite.gd` — four canopy/fruit-drawing
  failures.
- `tests/unit/test_dialogue_topic.gd`:
  `test_every_event_type_the_substrate_really_emits_is_claimed_by_some_topic`
  — `player_settled` is emitted and claimed by no topic. That one is a
  one-line fix in `DialogueTopic.MEMORY_TOPIC_EVENT_TYPES`.

None should stay red; the seed group in particular looks like it is masking a
real regression in seed shedding.

---

## What nothing calls

An audit of every `.gd` under `src/` for production callers (`src/` + `scenes/`,
excluding the file itself and its own tests) turned up **38 modules with tests
and zero production callers**. Some are scaffolding for unbuilt features and
that is fine. Two were load-bearing for the finding above:

- **`WeatherModel.wind_direction_for`** — written, documented and tested since
  the weather model existed. **No production caller at all.** The world had a
  wind direction that nothing in the running game ever asked for. Nor did
  `FlowerPatch.set_wind`, its only intended consumer.
- **`Olfaction`'s `MUSK` and `SMOKE` molecules** — defined from the first day
  of that doc, with a sensitivity and a response row for every animal. **Nothing
  in the world emits either.** The player, a campfire and a carcass are all
  odourless.

Put those two together and the missing mechanic writes itself: *the player has
a smell, and the wind carries it.* That is the entire difference between
walking at an animal and stalking one, it costs the player nothing but
attention, and both halves were already in the tree waiting to be joined.

The other 36 are listed in the audit for later; the ones that stand out as
ready-to-wire are `pet_loyalty.gd`, `wounds.gd`, `corpse.gd`, `farm_plot.gd`,
`crop_breeding.gd`, `smelting.gd`, `crafting_station.gd`, `coziness_score.gd`,
`faction_reputation.gd` and `npc_recognition.gd`.

---

## What this session built

Everything in `docs/concept/animal_husbandry.md` §1 "The approach", plus one
mechanic that doc did not specify. See that doc's Status section for the full
list and the divergences. In short:

- **Bait** works for a plain grazer now, and has a gesture (finding 5). A
  carrot smells like a carrot (`Olfaction.bait_mixture`, plus a new `OIL`
  molecule so a nut is not a fruit), every species on the anatomy roster has a
  nose, a non-fruit-eater tags a smelled find as the new
  `GrazerForaging.FOOD_BAIT`, and `EarthChunkManager.take_bait_at` lets it
  actually eat what it walked to. **Bait is the answer to finding 1**: it works
  at any speed multiplier, because the animal comes to you.
- **The stalk** is a real held stance on Ctrl with a real speed cost.
- **Flight distance is a function, not a constant** —
  `FlightDistance.radius(species, wariness, trust, crouched)`, with the species
  term read from the same `world_scale` the art uses.
- **Wariness** is a per-individual ramp: chasing an animal costs you, and
  walking away is the input that undoes it.
- **The wind** carries the player's musk, and the status line names it.

## What was verified in play, and what was not

**Verified in the running game**, on the real build with the real save:

- `Wind: south-easterly` in the status line, turning with the world clock.
- `Mode: crouching` with `Speed: 20%` against `47%` standing — the crouch's
  real, measured cost (0.45×, exactly `FlightDistance.CROUCH_SPEED_MULTIPLIER`).
- Pressing `H` while carrying carrots leaves a carrot on the ground, with the
  world's own `Pick (E)` prompt over it.

**Verified by test, not by eye:**

- A sheep crossing a field to a carrot and eating it
  (`test_a_baited_grazer_walks_to_a_carrot_it_would_never_forage_for`,
  `test_bait_works_with_no_player_involved_at_all`, against a real
  `CreatureMarker`). Watching this happen in the world needs a calmer, longer
  observation than a 11-FPS software-rendered session over a 500 px search
  radius allows: `/spawn` scatters animals 200–500 px away (finding 3), the
  smell reaches 20 tiles, and a freshly spawned animal takes up to ~25 s to
  become hungry enough to go looking. Carrots left on the ground did disappear
  across two waits with sheep nearby, which is consistent with them being eaten
  but is not proof.
- A crouched approach letting the player closer than a standing one
  (`test_a_crouched_player_gets_closer_before_a_sheep_flees`).
- The wind changing what an animal makes of the player
  (`test_standing_upwind_of_an_animal_makes_it_warier_than_standing_downwind`).

## What this session did not establish

- **I never completed a tame**, for the same reason the last session did not.
  Everything asserted about the lead → tie → feed → order → mount chain still
  comes from reading the code.
- Frame-rate figures are software-renderer figures and are not a baseline.
